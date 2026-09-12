class_name RolloutHarness
extends RefCounted

## One THINKING BEAT of §7's enemy AI (#895): snapshot the live battle, fill the
## fleet with `K` candidates x `M` common-random-number seeds, run `H` ticks,
## read the fleet back, restore the live battle.
##
## 🔴 THE FLEET IS EVERY BATTLE SLOT, THE LIVE ONE INCLUDED — WHICH IS WHY THE
## RESTORE IS NOT OPTIONAL BOOKKEEPING. `step_tick` dispatches over the WHOLE
## batch in one compute list (ADR-0237 dec. 1 — that is also why 1024 battles
## cost 1.4x what one costs). There is no per-battle active mask, so the live
## battle is carried `H` ticks forward along with the candidates whether it is a
## candidate slot or not. §7's answer is to lean into it: the live battle is
## simply candidate slot 0's substrate, and `restore_battle(live, pristine)` puts
## it back. The restore is the keystone primitive's second consumer (ADR-0235),
## so ADR-0235's bit-identity test guards exactly the thing this depends on.
##
## That is also the ONLY reason no shader change was needed. A `1 + K` simulator
## with an active mask is the upgrade §7 names for Active mode, where a rollout
## would have to overlap live play instead of running inside a frozen turn.
##
## 🔴 THE SCORE LEG IS ONE BULK READ OF THE RESULT BUFFER. ADR-0237 dec. 7
## measured the alternative: `read_unit_column` is a blocking `buffer_get_data`
## per battle, and one column across 1024 battles costs 33-51 ms — as much as
## running the entire horizon, for one feature. The whole result buffer reads in
## 0.11 ms and `stage_victory` writes it every tick for every ongoing battle. So
## this harness never touches a unit block, and #896's value function is fed from
## the result record. Widening that record is how features get added; looping a
## per-battle read is the shape to reject.
##
## What this file does NOT do:
##
## - **Rank the candidates.** The value function `f` and its calibration are #896.
##   `run` returns the raw per-slot records and stops there — a harness that also
##   scored would make the H-sweep unable to vary the scorer.
## - **Decide K, M or H.** ADR-0237 dec. 8: a discovered ceiling belongs in an
##   ADR-0068 `static var`, and publishing a default with no reader ships a number
##   nobody chose. #897 owns the sizing, with ADR-0237's table as its input.
## - **Allocate the fleet.** The simulator is handed in, already sized. See
##   `CombatLoop.rollout_fleet_size`.

## `rand_int` in `combat_common.glslinc` is a stateless hash of
## `battle_seed + unit_id * 1000 + tick` — no per-battle stream, no state to
## capture. The stride between one unit's draws is therefore exactly this.
const RNG_UNIT_STRIDE := 1000

## Result-record layout. `GPUCombatPacker.ResultField` is generated from
## `combat_common.glslinc` by `tools/gen_gpu_layout.py`, so the shader is the one
## author of it (ADR-0001).
##
## This was a hand-written copy of the four fields the record had when #895
## shipped. #896 widened the record with the value function's features, and a
## hand-written copy is precisely the thing that cannot be widened safely: it
## would still have parsed, still have returned four fields, and quietly
## described a record that no longer existed.
const ResultField = GPUCombatPacker.ResultField


## Row key -> record offset, DERIVED from the generated enum rather than listed
## again beside it.
##
## The enumeration is its own oracle here on purpose. #895's lesson was a
## candidate family that `families()` enumerated and `FAMILIES` never offered:
## two lists, and the test walked the wrong one, so a seeded defect deleted its
## own check and went green. A row map authored by hand would fail the same way
## — the record would grow a field, this file would keep handing out the old
## ones, and every row would still look perfectly well-formed.
static func record_key_map() -> Dictionary:
	var out: Dictionary = {}
	for name in ResultField.keys():
		out[String(name).to_lower()] = int(ResultField[name])
	return out

var _sim: GPUBatchSimulator = null
var _live_battle: int = 0


func _init(sim: GPUBatchSimulator, live_battle: int = 0) -> void:
	_sim = sim
	_live_battle = live_battle


#region Common random numbers


## The minimum seed separation that keeps two battles' RNG streams apart, and
## therefore the WIDTH of the integer window one battle consumes.
##
## `rand_int` hashes `seed + unit_id * 1000 + tick`, so a battle running `U` unit
## slots for `H` ticks draws on exactly the integers
## `[S, S + (U-1) * 1000 + H - 1]` — a window `(U-1) * 1000 + H` wide. Two seeds
## `S` and `S + d` therefore have provably disjoint streams when `d` is at least
## that width, and can share draws for any smaller `d` (at `d = width - 1`, unit
## `U-1` at tick `H-1` in the first battle and unit 0 at tick 0 in the second hash
## the identical integer).
##
## An aliasing pair is not a crash and not a visible wrong answer: it is the
## variance reduction quietly turning into shared error, so the M replicates stop
## being independent and the comparison between candidates keeps a bias nobody
## can see. §7's own note; `RolloutCrnSeedsTest` proves both sides of the
## boundary against the hash's actual inputs rather than against this formula.
static func crn_min_separation(units_per_battle: int, horizon: int) -> int:
	return maxi(0, units_per_battle - 1) * RNG_UNIT_STRIDE + maxi(0, horizon)


## `M` seeds guaranteed not to alias each other at this shape.
##
## The SAME M seeds are used across all K candidates — that is what "common
## random numbers" means, and it is deliberate aliasing: two candidates under
## seed m face identical luck, so the difference between their outcomes is the
## gambit edit and nothing else. Only the M seeds themselves must be disjoint.
static func crn_seeds(m: int, units_per_battle: int, horizon: int,
		base_seed: int = 1) -> PackedInt32Array:
	var out := PackedInt32Array()
	if m <= 0:
		return out
	var stride := crn_min_separation(units_per_battle, horizon)
	out.resize(m)
	for i in range(m):
		out[i] = base_seed + i * stride
	return out


## Do these seeds keep their streams apart at this shape? The assertion §7 asks
## for, callable by the caller that supplies its own seeds.
##
## Conservative by construction: below the separation two windows OVERLAP, and
## whether an overlap actually produces a shared draw depends on `H` versus the
## 1000-wide unit stride. "Might share" is the only answer worth acting on.
static func seeds_are_disjoint(seeds: PackedInt32Array, units_per_battle: int,
		horizon: int) -> bool:
	var separation := crn_min_separation(units_per_battle, horizon)
	for i in range(seeds.size()):
		for j in range(i + 1, seeds.size()):
			if absi(seeds[i] - seeds[j]) < separation:
				return false
	return true


#endregion


## The acting unit's current gambit rows, read out of a snapshot. The starting
## point every mutation operator edits.
static func rows_from_snapshot(snap: Dictionary, unit_idx: int) -> PackedInt32Array:
	if not snap.has("gambits"):
		return PackedInt32Array()
	return RolloutCandidates.unit_rows(snap["gambits"], unit_idx)


## Run one beat and return the raw per-slot records.
##
## `candidates` are gambit images for `unit_idx` (see `RolloutCandidates`);
## `seeds` are the M common-random-number seeds. Slot `k * M + m` runs candidate
## `k` under seed `m`, and the mapping is stated here because #896 reads it back
## the same way.
##
## Returns `{}` when it refuses — an undersized fleet, an aliasing seed set, a
## malformed candidate. Refusing is the whole point: a beat that silently ran 12
## of 64 candidates returns a confident recommendation drawn from a search that
## never happened.
##
## The live battle is restored on EVERY path that reached the fill, including the
## failing ones. A rollout that leaves the player's battle 300 ticks in the
## future is not a wrong answer, it is a destroyed game.
func run(unit_idx: int, candidates: Array, seeds: PackedInt32Array,
		horizon: int) -> Dictionary:
	if _sim == null or not _sim.is_initialized():
		push_error("[RolloutHarness] no initialized simulator")
		return {}
	var num_battles := _sim.get_num_battles()
	var units_per_battle := _sim.get_units_per_battle()
	var k := candidates.size()
	var m := seeds.size()
	if k <= 0 or m <= 0 or horizon <= 0:
		push_error("[RolloutHarness] beat needs K>0, M>0, H>0 — got K=%d M=%d H=%d" % [k, m, horizon])
		return {}
	if k * m > num_battles:
		push_error("[RolloutHarness] K*M = %d exceeds the fleet's %d battles — size the fleet (CombatLoop.rollout_fleet_size) or shrink M first, then K (§7)" % [
			k * m, num_battles])
		return {}
	if unit_idx < 0 or unit_idx >= units_per_battle:
		push_error("[RolloutHarness] unit %d is not in a %d-unit battle" % [unit_idx, units_per_battle])
		return {}
	if not seeds_are_disjoint(seeds, units_per_battle, horizon):
		push_error("[RolloutHarness] the %d seeds alias each other at U=%d H=%d (need %d apart) — the M replicates would share draws instead of averaging over independent ones" % [
			m, units_per_battle, horizon, crn_min_separation(units_per_battle, horizon)])
		return {}

	# PRISTINE. Never mutated, never handed to `restore_battle` for a fleet slot,
	# and the only thing the live battle is ever restored from.
	var pristine: Dictionary = _sim.snapshot_battle(_live_battle)
	if pristine.is_empty():
		push_error("[RolloutHarness] could not snapshot the live battle %d" % _live_battle)
		return {}

	var t_fill := Time.get_ticks_usec()
	var filled := 0
	for ki in range(k):
		var image: PackedInt32Array = candidates[ki]
		for mi in range(m):
			var slot := ki * m + mi
			if not _install(slot, pristine, unit_idx, image, seeds[mi]):
				_sim.restore_battle(_live_battle, pristine)
				return {}
			filled += 1
	var fill_ms := float(Time.get_ticks_usec() - t_fill) / 1000.0

	var t_run := Time.get_ticks_usec()
	_sim.step_tick(horizon)
	var run_ms := float(Time.get_ticks_usec() - t_run) / 1000.0

	var t_read := Time.get_ticks_usec()
	var raw := _sim.read_all_results()
	var read_ms := float(Time.get_ticks_usec() - t_read) / 1000.0

	var t_restore := Time.get_ticks_usec()
	var restored := _sim.restore_battle(_live_battle, pristine)
	var restore_ms := float(Time.get_ticks_usec() - t_restore) / 1000.0
	if not restored:
		push_error("[RolloutHarness] the live battle %d was NOT restored — its state is now %d ticks into a rollout" % [
			_live_battle, horizon])
		return {}

	return {
		"candidates": k,
		"seeds": m,
		"horizon": horizon,
		"unit": unit_idx,
		"filled": filled,
		"rows": _rows_from_results(raw, k, m),
		"fill_ms": fill_ms,
		"run_ms": run_ms,
		"read_ms": read_ms,
		"restore_ms": restore_ms,
	}


## Install one candidate into one fleet slot: the pristine image with this
## slot's CRN seed in the header and this candidate's rows over the acting unit.
##
## Both slices are duplicated before editing. `PackedInt32Array` is copy-on-
## write, so an un-duplicated edit would still leave `pristine` intact — but the
## thing standing between the player's battle and a 300-tick jump should not be a
## language subtlety.
func _install(slot: int, pristine: Dictionary, unit_idx: int,
		rows: PackedInt32Array, seed_value: int) -> bool:
	var header: PackedInt32Array = (pristine["battle"] as PackedInt32Array).duplicate()
	header[GPUCombatPacker.BattleHeaderField.SEED] = seed_value
	var gambits: PackedInt32Array = (pristine["gambits"] as PackedInt32Array).duplicate()
	if not RolloutCandidates.write_unit_rows(gambits, unit_idx, rows):
		return false
	var image := pristine.duplicate()
	image["battle"] = header
	image["gambits"] = gambits
	return _sim.restore_battle(slot, image)


## Split the bulk result buffer into one record per (candidate, seed).
##
## Every field of the record is handed out, features included, because the
## harness does not know which of them a scorer wants — `RolloutValueFunction`
## reads its own feature list out of the calibrated artifact, and an H-sweep that
## varies the feature set has to be able to ask for a term this file never heard
## of. Dropping a field here would be a scorer decision taken in the harness.
func _rows_from_results(raw: PackedInt32Array, k: int, m: int) -> Array:
	var out: Array = []
	var width := _sim.get_result_size()
	var record_keys := record_key_map()
	for ki in range(k):
		for mi in range(m):
			var slot := ki * m + mi
			var base := slot * width
			# The WHOLE record has to be present. The bound used to be the last
			# field this file happened to read, so a buffer short by any of the
			# fields beyond it read past its end.
			if base + width > raw.size():
				break
			var row := {
				"candidate": ki,
				"seed_index": mi,
				"battle": slot,
			}
			for key in record_keys:
				row[key] = raw[base + int(record_keys[key])]
			out.append(row)
	return out
