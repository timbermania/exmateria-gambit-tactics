extends RefCounted

## THE GAMBIT LAB'S FLEET SWEEPER — every cell the synthesizer can build, in ONE fleet.
## ADR-0275 decs. 13, 15, 16; issue #1130.
##
## Hostless on purpose. This is a `RefCounted` driving [GPUBatchSimulator] directly, exactly
## as [RolloutHarness] does: no [CombatHost], no [CombatLoop], no `Unit` nodes, no scene at
## all. It is handed a lattice and a distance field and it returns a report.
##
## === WHY IT IS A FLEET AND NOT A LOOP (dec. 13) ============================================
##
## Each scenario the live arm boots builds a fresh `CombatLoop` -> a fresh LOCAL
## `RenderingDevice` -> all eight pipelines (`CombatLoop.gd:480-504`). That is ~0.35 s warm
## and **7,739 ms cold**, so N cells sequentially is N boots — and it churns NVIDIA's 1 GB
## `GLCache`, so some fraction of them pay the cold compile rather than the warm one. The
## fleet allocates ONE device, holds every cell resident as its own battle slot, and advances
## the whole batch in one batched submit. ADR-0237 dec. 1 is why that is nearly free: 1024
## battles cost 1.4x what one costs, because the tick is a fixed cost the whole batch shares.
##
## === THE FLEET IS UNIFORM, AND THE TWO UNIFORMITIES BITE DIFFERENTLY =======================
##
## `GPUBatchSimulator` sizes every slot the same, in MAP and in `units_per_battle`. So:
##
## - **Map.** Every cell the synthesizer builds is on [constant GambitCellSynth.MAP], by
##   dec. 11, so one lattice serves the whole sweep and the uniformity costs nothing. A sweep
##   over the 84 fixtures could NOT be run this way — 67 are MAP042 and 5 are MAP100 — and
##   that is a real limit of this instrument, not an oversight.
## - **`units_per_battle`.** DERIVED here from the widest roster in the batch
##   ([method _fleet_width]), never a literal. It is NOT padding: `set_battle_units` marks
##   every unused slot dead, so a 2-unit cell in a 4-wide fleet seats two units and two
##   corpses, which is what a 2-unit battle is. The hazard is the other direction and it is
##   SILENT — `set_battle_units` takes `mini(team.size(), _units_per_battle / 2)` and drops
##   the rest without a word. [method _seat] refuses a cell whose team would be truncated
##   rather than seating a battle that is not the cell on the label (dec. 10).
##
## === THE TICK BUDGET IS PER CELL AND THE FLEET ADVANCES IN LOCKSTEP ========================
##
## #1129's dec. 12 finding: a cell's budget is DERIVED from its actor's Speed, and the throw
## straddle runs its actor at Speed 8 — **450 ticks** to its first turn against 30 at Speed
## 120. The fleet cannot advance two battles at different rates, so the horizon is the MAX
## budget in the batch and every cell rides to it. Two things make that honest rather than
## wasteful:
##
##   1. A cell LATCHES at its own first evaluation and is never read again, so a Speed-120
##      cell's answer is taken at tick ~30 whatever the horizon is.
##   2. The sweep stops the moment every cell has latched, so the horizon is a ceiling and
##      not a cost. [method run] reports the tick it actually stopped at.
##
## Bucketing the batch by budget was considered and is NOT done, and the measurement is
## blunter than the argument: **the horizon has never bound.** Swept over the whole catalogue
## the batch's budgets are `{120: 23, 1380: 1, 1575: 1}` — bimodal exactly as dec. 12 says —
## and the loop stops at **tick 1**, because every actor already has a verdict there.
##
## ⚠️ That is worth reading twice, because it is not what dec. 12's prose predicts. The
## "450 ticks to its first turn" number is the wait from an EMPTY turn meter, and no unit
## starts with one: `initial_turn_meter` is uniform in `[0, TURN_METER_FULL)` and the actor
## is unit 0 under seed 42 on every cell, which opens it at 2,991/3,600 — 83% charged. The
## budget is therefore a safe ceiling that has never been approached, not a cost anyone pays,
## and bucketing a one-iteration loop by its slowest member would buy nothing at all.
##
## What is NOT claimed here is the mechanism — whether the kernel walks an idle unit's slots
## every tick, or whether 83% is simply enough. The sweep measures WHEN, and the tick budget
## stays derived (dec. 12) rather than collapsed to a literal, because a catalogue that grows
## a slower actor or a different seed would move this and a literal would not move with it.
##
## === IT SCORES THE FIRST EVALUATION, NOT THE LAST =========================================
##
## `clear_verdict` is scoped to `max_slot` and rewrites every slot the next call walks, so a
## sweep that stepped to the horizon and read once would score a LATER decision than the one
## the cell predicts. [GambitLabScene] `_score_cell` takes the first, and this takes the
## first, because two instruments that score different ticks do not describe the same
## experiment. That is also why the buffer is read every tick instead of once at the end.
##
## === WHAT THE FLEET DOES NOT REPRODUCE, SAID OUT LOUD =====================================
##
## The live arm runs inside a `CombatLoop`, and the loop writes BACK to the GPU in two
## places during a battle: `TurnDirector.consume_turn` and `CombatLoop.apply_pending_heal`.
## The fleet has no host, so neither happens here — the same model [RolloutHarness] and
## `tools/rollout_corpus.gd` already run under (ADR-0237).
##
## Neither can reach the quantity this sweep measures: both are consequences of a unit having
## ALREADY acted, and every cell is scored at its actor's FIRST evaluation, which is strictly
## earlier. That is an argument, though, not a measurement — so the acceptance for this file
## is a MEASUREMENT of it: #1129 ran all 25 buildable cells through the live arm one boot at
## a time and every predicted field-set held. This sweep must reproduce that verdict, cell
## for cell, in one boot. A cell the fleet scores differently from the live arm is a finding
## about THIS FILE, not about the kernel, and it is the first thing to suspect.
##
## === IT NEVER JOINS THE SUITE (dec. 15) ===================================================
##
## Not a test, not promotable to one, not "a curated subset later". It is red on day one for
## reasons that are findings — hollow status bits, unreachable opcodes, straddle refusals —
## and a test red for known reasons is one everybody trains themselves to ignore, which would
## take the 84 real fixtures' credibility down with it. A frozen expectation generated from
## current behaviour also ratchets today's bugs into the guard.
##
## Its REPORT is a gitignored artifact (dec. 16); its INPUTS — the straddle table, the
## synthesizer, the censuses — are committed. Knowledge is committed; measurements are not.
##
## Driven by `tools/gambit_fleet_sweep.tscn`. See that scene's script for the command line.

const Lattice = ExMateriaBattlefield.Lattice

## dec. 13's fleet. 256 is `rollout_corpus.gd`'s number and ADR-0237's measured shape; the
## catalogue is far smaller today, so this is a CEILING that has never bound. It is honoured
## by BATCHING rather than by truncating — a catalogue larger than this runs as several
## fleets and every one of them is reported, because a sweep that silently dropped its tail
## would read as "covered everything".
const MAX_FLEET := 256

## The distance field's jump range, matching `CombatLoop.setup_distance_field`. Quoted from
## there rather than re-chosen: a sweep whose pathing differs from the live arm's is a sweep
## of a different battle.
const DISTANCE_FIELD_JUMP := 3

var _lattice: Lattice = null
var _distance_field: DistanceFieldGenerator = null
var _reader: GambitVerdictReader = null

## Per-tick cost, measured rather than asserted — the numbers behind "bucketing by budget
## would buy nothing". `{submit_us, read_us, scan_us, ticks}` accumulated over the run.
var _cost: Dictionary = {}


func _init(lattice: Lattice, distance_field: DistanceFieldGenerator) -> void:
	_lattice = lattice
	_distance_field = distance_field


## Sweep every cell in [param cells] and return the report.
##
## [param cells] is [method GambitCellSynth.catalogue]'s output verbatim — refusals INCLUDED,
## because dec. 9 makes the refusal list the product and a sweep handed a pre-filtered array
## could not count what it never saw.
##
## The returned dict is the whole measurement: `{cells, scored, passed, failed, blind,
## refused, dropped, batches, horizon, stopped_at, cost, rows}`. `rows` is one record per
## cell, in catalogue order.
func run(cells: Array, opts: Dictionary = {}) -> Dictionary:
	_reader = GambitVerdictReader.new()
	var layout_ok := _reader.load_layout()
	_cost = {"submit_us": 0, "read_us": 0, "scan_us": 0, "ticks": 0}

	var report := {
		"cells": cells.size(),
		"layout_ok": layout_ok,
		"layout_checks": _reader.checks.duplicate(true),
		"scored": 0, "passed": 0, "failed": 0, "blind": 0, "refused": 0, "dropped": 0,
		"batches": [], "rows": [],
	}
	if not layout_ok:
		# The decoder reports its own checks and this one failed, so every verdict below
		# would be decoded against a layout the kernel does not have. A wrong NAME for the
		# right bits is worse than no decode at all, so the sweep declines to run.
		report["rows"] = []
		return report

	var fleet_size: int = int(opts.get("fleet", MAX_FLEET))
	var buildable: Array = []
	for c in cells:
		if bool(c.get("refused", false)):
			report["refused"] += 1
			report["rows"].append(_refusal_row(c))
		else:
			buildable.append(c)

	var batch_start := 0
	while batch_start < buildable.size():
		var batch: Array = buildable.slice(batch_start, mini(batch_start + fleet_size,
			buildable.size()))
		var summary := _run_batch(batch, report)
		report["batches"].append(summary)
		batch_start += batch.size()

	report["cost"] = _cost.duplicate()
	return report


## One fleet: seat the batch, advance it in lockstep, latch each cell's first evaluation,
## score every cell against its own prediction.
func _run_batch(batch: Array, report: Dictionary) -> Dictionary:
	var width := _fleet_width(batch)
	var sim := GPUBatchSimulator.new()
	if not sim.initialize(_lattice, _distance_field, batch.size(), width):
		sim.cleanup()
		# Not silent: a fleet that could not be allocated means every cell in it is
		# UNMEASURED, and an unmeasured cell must never read as a refused one.
		for c in batch:
			var row := _base_row(c)
			row["outcome"] = "UNMEASURED"
			row["note"] = ("the fleet failed to initialize %d battles x %d units — VRAM?"
				% [batch.size(), width])
			report["dropped"] += 1
			report["rows"].append(row)
		return {"seated": 0, "width": width, "failed_init": true}

	var seated: Array = []       # battle_id -> cell, for the cells that actually seated
	var dropped: Array = []
	for i in range(batch.size()):
		var c: Dictionary = batch[i]
		var why := _seat(sim, seated.size(), c, width)
		if why != "":
			var row := _base_row(c)
			row["outcome"] = "DROPPED"
			row["note"] = why
			report["dropped"] += 1
			report["rows"].append(row)
			dropped.append(c)
			continue
		seated.append(c)

	# 🔴 THE POSITIVE CONTROL, AND IT IS NOT OPTIONAL. The latch below fires on "some slot's
	# verdict word is non-zero", and EVERY cell in this catalogue latches on tick 1 — which
	# is either a true reading (`initial_turn_meter` is uniform in `[0, TURN_METER_FULL)`, so
	# the actor opens 83% charged under seed 42 rather than empty) or an instrument firing on
	# residue it seated itself. Those two are indistinguishable from the latch alone.
	#
	# So the buffer is read ONCE here, after seating and before a single tick: at this point
	# the kernel has not run and every verdict word must be zero. A non-zero reading means the
	# sweep is measuring its own seating, and it says so rather than reporting 25 passes.
	var pre := sim.read_all_gambits()
	var pre_walked := 0
	for b in range(seated.size()):
		if _actor_walked(pre, b, width):
			pre_walked += 1

	# The horizon is the SLOWEST budget in the batch (dec. 12's Speed straddle), and it is a
	# ceiling: the loop below stops the tick every cell has latched.
	var horizon := 0
	for c in seated:
		horizon = maxi(horizon, int(c.get("ticks", 0)))

	var latched: Array = []      # battle_id -> [] until latched, then the actor's six slots
	var latch_tick: Array = []
	for i in range(seated.size()):
		latched.append([])
		latch_tick.append(-1)

	var remaining := seated.size()
	var tick := 0
	while tick < horizon and remaining > 0:
		var t0 := Time.get_ticks_usec()
		sim.step_tick(1)
		tick += 1
		var t1 := Time.get_ticks_usec()
		var words := sim.read_all_gambits()
		var t2 := Time.get_ticks_usec()
		for b in range(seated.size()):
			if latch_tick[b] >= 0:
				continue
			# The RAW int is tested before anything is decoded. The verdict word is zero
			# until the kernel walks the slot, so this is a PackedInt32Array read per slot
			# per unlatched battle and nothing more — the decode happens once, for the one
			# tick that is the cell's answer.
			if not _actor_walked(words, b, width):
				continue
			var slots: Array = []
			for s in range(GPUConstants.MAX_GAMBITS):
				slots.append(_reader.read_slot(words, b * width, s))
			latched[b] = slots
			latch_tick[b] = tick
			remaining -= 1
		var t3 := Time.get_ticks_usec()
		_cost["submit_us"] += t1 - t0
		_cost["read_us"] += t2 - t1
		_cost["scan_us"] += t3 - t2
		_cost["ticks"] += 1

	for b in range(seated.size()):
		report["rows"].append(_score(seated[b], latched[b], latch_tick[b], report))

	sim.cleanup()
	return {
		"seated": seated.size(), "dropped": dropped.size(), "width": width,
		"horizon": horizon, "stopped_at": tick, "unlatched": remaining,
		"pre_step_walked": pre_walked,
		"budgets": _budget_spread(seated),
	}


## Has the kernel written ANY verdict into the actor's slots in this battle?
##
## The actor is global unit `battle * width` — GPU unit 0 of its battle — by construction:
## the cell spec lists the actor first and on team 0, and `set_battle_units` writes team 0
## into indices `0..n0-1`. The same claim the live arm rests its scoring on.
func _actor_walked(words: PackedInt32Array, battle: int, width: int) -> bool:
	var base: int = battle * width * GPUCombatPacker.GAMBITS_PER_UNIT
	for s in range(GPUConstants.MAX_GAMBITS):
		var at: int = base + s * GPUCombatPacker.GAMBIT_SIZE \
			+ GPUCombatPacker.GambitField.RESERVED_14
		if at < words.size() and words[at] != 0:
			return true
	return false


## Seat one cell as one battle. Returns "" on success, or the reason it was dropped.
##
## This is the live arm's boot with the scene taken out of it: `encode_units` and
## `build_battle_spec` are [GambitScenarioBoot]'s, unchanged, so a fleet cell and a
## live cell reach the GPU through the same two functions. `spawn_unit` is the third and
## it is NOT called — it builds a scene-side `Unit` node, which is exactly the host this
## file does not have.
func _seat(sim: GPUBatchSimulator, battle: int, cell: Dictionary, width: int) -> String:
	var scenario: Dictionary = cell.get("scenario", {})
	if scenario.is_empty():
		return "the cell spec carries no scenario dict"

	var spec := GambitScenarioBoot.build_battle_spec(scenario, _lattice)
	var t0: Array = spec["team0"]
	var t1: Array = spec["team1"]
	var cap: int = width / 2
	# 🔴 THE TRUNCATION IS SILENT AT THE SEAM, SO IT IS CAUGHT HERE. `set_battle_units` seats
	# `mini(team.size(), _units_per_battle / 2)` and discards the rest with no return value
	# and no warning — a cell whose dummy was dropped would still produce a verdict, and that
	# verdict would describe a battle the label does not name (dec. 10's productive failure).
	if t0.size() > cap or t1.size() > cap:
		return ("roster %d v %d does not fit a %d-wide fleet (cap %d per team) — seating it "
			+ "would DROP a unit silently") % [t0.size(), t1.size(), width, cap]

	var encoded := GambitScenarioBoot.encode_units(scenario)
	var gambits: Array = encoded["gambits"]
	sim.set_battle_units(battle, t0, t1, int(scenario.get("seed", 42)))
	# Every slot is written, the empty ones included — `boot_battle` idles the whole roster
	# before arming it, and a slot left unwritten keeps whatever the freshly-created buffer
	# holds, verdict ints and all.
	for u in range(width):
		sim.set_unit_gambits(battle, u, gambits[u] if u < gambits.size() else [])
	return ""


## The narrowest fleet that seats every roster in the batch without truncation.
##
## DERIVED, never a literal: `set_battle_units` caps each team at `units_per_battle / 2`, so
## the width is twice the widest TEAM, not the widest roster. A 2-unit enemy-pool cell and a
## 3-unit ally-pool cell both want 2 per team and both fit in 4.
func _fleet_width(batch: Array) -> int:
	var widest := 1
	for c in batch:
		var t0 := 0
		var t1 := 0
		for u in (c.get("scenario", {}) as Dictionary).get("units", []):
			if int((u as Dictionary).get("team", 0)) == 0:
				t0 += 1
			else:
				t1 += 1
		widest = maxi(widest, maxi(t0, t1))
	return widest * 2


## Score one cell's latched verdict against its own `expect` rows.
##
## The rule is [GambitLabScene] `_score_cell`'s, field for field, and deliberately so: two
## arms that scored differently would disagree about cells neither of them got wrong.
func _score(cell: Dictionary, slots: Array, tick: int, report: Dictionary) -> Dictionary:
	var row := _base_row(cell)
	row["latched_tick"] = tick
	if slots.is_empty():
		# dec. 18. A blind run is a statement about the INSTRUMENT, not about the kernel:
		# `VERDICT_NONE` is 0 and is a real answer, so a zeroed field and a call that never
		# happened are indistinguishable. It scores nothing and is never called a failure.
		row["outcome"] = "BLIND"
		row["note"] = ("the actor was never evaluated inside %d ticks — nothing here can be "
			+ "scored, and a zero from a blind instrument is not absence") % int(cell.get("ticks", 0))
		report["blind"] += 1
		return row

	var problems: Array = []
	var held := 0
	for e in cell.get("expect", []):
		var slot: int = int(e["slot"])
		if slot >= slots.size():
			problems.append("slot %d is past MAX_GAMBITS" % slot)
			continue
		var d: Dictionary = slots[slot]
		var bad: Array = []
		if e.has("p1"):
			var want: int = int(_reader.code_of.get(String(e["p1"]), -1))
			if int(d["p1"]) != want:
				bad.append("p1 is %s, predicted %s" % [
					_reader.verdict_name(int(d["p1"])), e["p1"]])
		for f in ["ci", "op", "payload"]:
			if e.has(f) and int(d[f]) != int(e[f]):
				bad.append("%s is %d, predicted %d" % [f, int(d[f]), int(e[f])])
		if bad.is_empty():
			held += 1
		else:
			problems.append("slot %d: %s\n         predicted: %s\n         measured:  %s" % [
				slot, ", ".join(bad), e.get("why", ""), _reader.format(d)])

	row["held"] = held
	row["problems"] = problems
	row["slots"] = slots
	report["scored"] += 1
	if problems.is_empty():
		row["outcome"] = "PASS"
		report["passed"] += 1
	else:
		row["outcome"] = "FAIL"
		report["failed"] += 1
	return row


func _base_row(cell: Dictionary) -> Dictionary:
	var ax: Dictionary = cell.get("axis", {})
	return {
		"name": String(cell.get("name", "?")),
		"kind": String(cell.get("kind", "?")),
		"opcode": String(ax.get("opcode_name", "?")),
		"knob": String(ax.get("knob", "-")),
		"knob_value": ax.get("knob_value", null),
		"separation": int(cell.get("separation", 0)),
		"actor_speed": int(cell.get("actor_speed", 0)),
		"budget": int(cell.get("ticks", 0)),
		"latched_tick": -1,
		"outcome": "?", "held": 0, "problems": [], "note": "", "slots": [],
	}


func _refusal_row(cell: Dictionary) -> Dictionary:
	var row := _base_row(cell)
	row["outcome"] = "REFUSED"
	row["note"] = String(cell.get("refusal", ""))
	return row


## `{budget: count}` over a batch — the number behind "the horizon is the slowest member".
## Printed rather than folded into an average: a bimodal spread (30 and 450, #1129 dec. 12)
## has no meaningful mean, and the mean is what would hide it.
func _budget_spread(batch: Array) -> Dictionary:
	var out: Dictionary = {}
	for c in batch:
		var b: int = int(c.get("ticks", 0))
		out[b] = int(out.get(b, 0)) + 1
	return out
