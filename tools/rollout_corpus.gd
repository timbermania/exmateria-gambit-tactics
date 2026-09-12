extends GPUCombatTestBase

## ROLLOUT CORPUS GENERATOR — the ground truth #896's value function is fit to.
##
## [GambitBattle](../docs/GAMBIT-BATTLE-DESIGN.md) §8 says the ground truth for
## both `H` and `f` is the same thing: **recorded outcomes of battles played to
## completion**. Nothing in the tree played one at scale before this file. It
## does, on the GPU, and writes a CSV the Python fitter reads.
##
## 🔴 A CORPUS BATTLE IS A GPU FLEET BATTLE, NOT A `CombatLoop` RUN, AND THAT IS
## THE FIRST REAL DECISION HERE. §8 wants battles "played by the current gambit
## AI with adjustments disabled". The shader IS that AI — `stage_compute`
## evaluates the gambit rows and `CombatLoop` only drives the clock — so a fleet
## battle is a faithful game, not a simulation of one. It is also the only
## affordable option: `CombatLoop` ticks at 60/s, so one 5,000-tick battle costs
## 83 seconds of wall clock and a thousand of them costs a day. The fleet runs a
## thousand battles in one compute list, and ADR-0237 dec. 1 is why that is
## nearly free — 1024 battles cost 1.4x what one costs. #890's own corpus note
## adds the other half: a finished battle stops costing, because every stage
## opens `if (result != RESULT_ONGOING) return;`, so a to-completion run is much
## cheaper per battle than `ticks x battles` suggests.
##
## 🔴 THE SAMPLE GRID IS WHAT MAKES ONE CORPUS SERVE THE WHOLE H-SWEEP. §8 says
## to sample "only at the states the AI will actually query" — `H` ticks after a
## decision — and to stratify by remaining battle length. Sampling every
## `stride` ticks gives both at once: any grid state is reachable as `D + H` from
## the grid state `H` earlier, for every `H` that is a multiple of `stride`. So
## ONE run at `stride = 100` supports `H` in {100, 200, 400, 800} without
## re-simulating anything, and `terminal_tick - tick` is the exact stratifier.
##
## 🔴 THE ROSTER IS RANDOMISED, AND THAT IS NOT DECORATION. ADR-0180 retired the
## arena's rosters, so this rig carries its own — and a corpus played by one
## fixed roster teaches `f` about one battle. Two failures in particular:
##
## - **Symmetric teams make the label nearly a coin flip with no signal in it.**
##   Team sizes are drawn independently, so the corpus spans lopsided fights,
##   which is where a value function earns its coefficients.
## - **An ATTACK-only roster makes the MP feature a constant.** Nobody spends
##   MP, so `R_TEAM*_MP` never moves, and a fit over it produces a coefficient
##   that means nothing. A fraction of every roster casts.
##
## Deliverable is DATA, not a guard: it asserts nothing and gates nothing. It is
## a `tools/` rig and not a test on purpose (#896's own scope note), which also
## keeps it off `check_test_list_coverage.py`'s books.
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . tools/rollout_corpus.tscn
##   godot --path . tools/rollout_corpus.tscn -- battles=512 rounds=8 stride=100
##
## `--` args (all optional, ADR-0051 dec. 5): `battles=` `units=` `stride=`
## `maxticks=` `rounds=` `seed=` `caster=` `out=`.

## ADR-0237 dec. 5's shipping shape: Gariland's ENTD fills 6 of 16 slots, and
## with the player's squad the padded `units_per_battle` lands near 12.
const DEFAULT_UNITS := 12
## The fleet. ADR-0237 dec. 1: the tick is a fixed cost the whole batch shares.
const DEFAULT_BATTLES := 256
## The sample grid, in ticks. The SMALLEST H in §8's sweep, so every larger H in
## {200, 400, 800} is a whole multiple of it and needs no second run.
const DEFAULT_STRIDE := 100
## #890 measured a plain roster finishing in 1,600-7,500 ticks; a randomised one
## with 320-HP units runs longer. This is the give-up point, and a battle that
## reaches it is DROPPED, not labelled — see `_write_corpus`.
##
## 🔴 THE CAP IS A BIAS, NOT JUST A BUDGET, WHICH IS WHY IT IS GENEROUS. The
## battles it truncates are the LONG ones, and a long battle is exactly the
## close-fought one a value function has the most to learn from — so a tight cap
## quietly trains `f` on decisive fights and then asks it about grindy ones.
## Long battles also contribute the most samples, so the loss is superlinear in
## the drop rate.
##
## Measured, though, the cap is NOT what was truncating this corpus. A run that
## left 19% of battles unlabelled and dropped 48% of its samples looked exactly
## like a cap set too low; it was the Regen roster above, and battles that could
## not end. With two offensive spells all 64 battles of a smoke round finish by
## tick 6,700 and nothing is dropped at all. The cap is insurance now, and this
## note is here because those two causes are indistinguishable from the drop
## count alone.
const DEFAULT_MAX_TICKS := 30000
const DEFAULT_ROUNDS := 4
const DEFAULT_SEED := 20260907
## Fraction of units given a spell gambit ahead of their attack, so MP moves.
const DEFAULT_CASTER_FRACTION := 0.4

## Two OFFENSIVE spells at different MP costs. Both offensive on purpose: a
## first pass here reached for ability 8 as a heal and ability 8 is **Regen** —
## and `make_spell_gambit` targets the nearest ENEMY by default, so the roster
## was regenerating the people it was fighting. 19% of battles never reached a
## verdict and 48% of samples had to be dropped for want of a label. Two attack
## spells make MP move without ever making a battle unable to end.
const ABILITY_FIRE := 16
const ABILITY_FIRE2 := 17

var _battles := DEFAULT_BATTLES
var _units := DEFAULT_UNITS
var _stride := DEFAULT_STRIDE
var _max_ticks := DEFAULT_MAX_TICKS
var _rounds := DEFAULT_ROUNDS
var _seed := DEFAULT_SEED
var _caster_fraction := DEFAULT_CASTER_FRACTION
var _out := "res://tools/logs/rollout_corpus.csv"

var _cells: Array = []
var _rng := RandomNumberGenerator.new()
## One entry per SAMPLE: {round, battle, tick, <record fields>}.
var _samples: Array[Dictionary] = []
## `"%d:%d" % [round, battle]` -> {result, ticks}. Battles with no terminal
## verdict never get an entry, and their samples are dropped with a count.
var _labels: Dictionary = {}
var _stats := {"seated": 0, "finished": 0, "unfinished": 0, "rows": 0, "dropped": 0}


func get_test_name() -> String:
	return "Rollout Corpus"


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())
	print("[NOT_A_TEST] the corpus generator for #896's value function — it plays battles to completion and writes a CSV, and asserts nothing")

	_parse_args()
	_rng.seed = _seed

	await get_tree().process_frame
	await get_tree().process_frame

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam into a typed
	# local, then stored (the field is inherited from `CombatHost`).
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		print("[corpus] map has no lattice — nothing to play")
		_finish()
		return

	_collect_cells()
	_setup_distance_field()
	var df: DistanceFieldGenerator = combat_loop.distance_field
	if not df:
		print("[corpus] no distance field — nothing to play")
		_finish()
		return
	if _cells.size() < _units:
		print("[corpus] map has %d walkable cells, need %d" % [_cells.size(), _units])
		_finish()
		return

	# THE LEVER SET REFEREES ITSELF BEFORE THE RIG RUNS (ADR-0277 dec. 9). A
	# measuring tool aborts where the game only warns: a factor that names a
	# category the kernel never reads produces numbers nobody can attribute,
	# and a corpus written under one is worse than no corpus.
	if not LeverSet.shared().abort_if_invalid():
		_finish()
		return

	print("[corpus] adapter: %s" % RenderingServer.get_video_adapter_name())
	# The map is BUILT, not loaded: two runs that disagree about the terrain
	# played two different games, and the cell count alone cannot tell them apart.
	print("[corpus] unit block %d ints, record %d ints, shader v%d, walkable cells %d, first %s last %s" % [
		GPUCombatPacker.UNIT_SIZE, GPUCombatPacker.RESULT_SIZE, GPUCombatPacker.SHADER_VERSION,
		_cells.size(), str(_cells[0]), str(_cells[_cells.size() - 1])])
	print("[corpus] battles=%d units=%d stride=%d maxticks=%d rounds=%d seed=%d caster=%.2f" % [
		_battles, _units, _stride, _max_ticks, _rounds, _seed, _caster_fraction])

	for r in range(_rounds):
		_play_round(df, r)
		await get_tree().process_frame

	_write_corpus()
	_finish()


func _process(_delta):
	pass


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		var key: String = parts[0].lstrip("-")
		var val: String = parts[1]
		match key:
			"battles": _battles = int(val)
			"units": _units = int(val)
			"stride": _stride = int(val)
			"maxticks": _max_ticks = int(val)
			"rounds": _rounds = int(val)
			"seed": _seed = int(val)
			"caster": _caster_fraction = float(val)
			"out": _out = val


## Every level-0 cell a unit may stand on, in a stable order. Placement takes
## team 0 off the front and team 1 off the back, so the two teams start apart and
## walk toward each other whatever the map's size — the same convention
## `GPURolloutBudgetBench` uses, so the two rigs describe the same battles.
func _collect_cells() -> void:
	var cells: Array = []
	var lat: Lattice = lattice
	for c in lat.all_cells():
		if c.grid.z != 0:
			continue
		if c.impassable or c.pass_through_only:
			continue
		cells.append(c.grid)
	cells.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	_cells = cells


## One fleet, seated and played to completion on the sample grid.
func _play_round(df: DistanceFieldGenerator, round_idx: int) -> void:
	var sim := GPUBatchSimulator.new()
	if not sim.initialize(lattice, df, _battles, _units):
		sim.cleanup()
		print("[corpus] round %d FAILED to initialize %d x %d (VRAM?)" % [
			round_idx, _battles, _units])
		return

	for b in range(_battles):
		_seat_battle(sim, b, round_idx)
		_stats["seated"] += 1

	var width := sim.get_result_size()
	var tick := 0
	while tick < _max_ticks:
		sim.step_tick(_stride)
		tick += _stride
		var raw := sim.read_all_results()
		var live := 0
		for b in range(_battles):
			var base := b * width
			if raw[base + GPUCombatPacker.ResultField.RESULT] != GPUBatchSimulator.RESULT_ONGOING:
				continue
			# Only LIVE states are sampled. A finished battle's record stops
			# being rewritten (every stage returns early on a decided battle),
			# so sampling past the end would stack identical copies of the
			# terminal record — and the AI never queries a decided position.
			live += 1
			_samples.append(_record_row(raw, base, round_idx, b, tick))
		if live == 0:
			break

	# The labels: each battle's own terminal record, read once at the end.
	var final := sim.read_all_results()
	for b in range(_battles):
		var base := b * width
		var result := final[base + GPUCombatPacker.ResultField.RESULT]
		if result == GPUBatchSimulator.RESULT_ONGOING:
			_stats["unfinished"] += 1
			continue
		_stats["finished"] += 1
		_labels["%d:%d" % [round_idx, b]] = {
			"result": result,
			"ticks": final[base + GPUCombatPacker.ResultField.TICKS],
		}

	print("[corpus] round %d: %d battles, ran to tick %d, %d finished, %d samples so far" % [
		round_idx, _battles, tick, _stats["finished"], _samples.size()])
	sim.cleanup()


## One sample row: the battle's identity plus every field of the record.
##
## The field list is DERIVED from the generated enum, not written out again
## here. #895's lesson: `families()` enumerated and `FAMILIES` offered, two
## lists, and a seeded defect deleted its own check. A hand-listed column set
## would go stale the next time the record is widened, silently, with every row
## still perfectly well-formed.
func _record_row(raw: PackedInt32Array, base: int, round_idx: int, battle: int,
		tick: int) -> Dictionary:
	# Stamped HERE, at sample time, not at write time (ADR-0277 dec. 10). Read
	# once per write it would be constant by construction and could never
	# witness a mid-run scrub, which is the only thing it exists to catch.
	var row := {"round": round_idx, "battle": battle, "tick": tick,
		"lever_digest": LeverSet.shared().digest()}
	for key in RolloutHarness.record_key_map():
		row[key] = raw[base + int(RolloutHarness.record_key_map()[key])]
	return row


## Seat one battle with its own randomised roster and placement.
func _seat_battle(sim: GPUBatchSimulator, battle_id: int, round_idx: int) -> void:
	var per_team_cap: int = _units / 2
	# Team sizes drawn INDEPENDENTLY. A corpus of symmetric fights teaches `f`
	# almost nothing: the label is close to a coin flip and the features barely
	# move with it. Lopsided fights are where a value function earns its
	# coefficients, and the padding slots an asymmetric battle leaves are marked
	# dead by `set_battle_units`, so they cost nothing and count as nothing.
	var t0: int = _rng.randi_range(2, per_team_cap)
	var t1: int = _rng.randi_range(2, per_team_cap)

	var team0: Array = []
	var team1: Array = []
	# Placement jitter so two battles with the same roster still start from
	# different ground.
	var front: int = _rng.randi_range(0, maxi(0, _cells.size() - _units - 1))
	for i in range(t0):
		team0.append(_build_gpu_config(_cells[front + i], _unit_cfg(i, 0)))
	for i in range(t1):
		team1.append(_build_gpu_config(_cells[_cells.size() - 1 - i], _unit_cfg(i, 1)))

	var battle_seed: int = _rng.randi_range(1, 1 << 28)
	sim.set_battle_units(battle_id, team0, team1, battle_seed)
	for i in range(t0 + t1):
		sim.set_unit_gambits(battle_id, i, _gambits())


## A randomised unit. Every stat that moves the outcome is drawn, so the corpus
## spans positions rather than repeating one. `speed` is FFT Speed (5..13, what
## `atb_speed` carries), not the legacy 65..100.
func _unit_cfg(seat: int, team: int) -> Dictionary:
	var max_hp: int = _rng.randi_range(120, 320)
	var max_mp: int = _rng.randi_range(80, 300)
	return {
		"name": "%s%d" % ["P" if team == 0 else "E", seat],
		"hp": max_hp, "max_hp": max_hp,
		"pa": _rng.randi_range(8, 16), "ma": _rng.randi_range(8, 14),
		"wp": _rng.randi_range(4, 9),
		"brave": _rng.randi_range(45, 75), "faith": _rng.randi_range(45, 75),
		"mp": max_mp, "max_mp": max_mp,
		"speed": _rng.randi_range(6, 10),
		"move": _rng.randi_range(3, 5), "jump": 3,
		"weapon_range": 1 if _rng.randf() < 0.75 else 2,
		"weapon_flags": 1, "weapon_type": 1,
		"c_ev": _rng.randi_range(5, 15), "s_ev": _rng.randi_range(10, 20),
		"w_ev": _rng.randi_range(5, 15),
		"body_sprite_id": 0x02 if team == 0 else 0x05,
	}


## A spell ahead of the attack for a fraction of units, so MP actually moves.
## With an ATTACK-only roster `R_TEAM*_MP` is constant for the whole battle and
## its fitted coefficient describes nothing.
func _gambits() -> Array:
	if _rng.randf() >= _caster_fraction:
		return [make_attack_gambit()]
	var spell: int = ABILITY_FIRE if _rng.randf() < 0.7 else ABILITY_FIRE2
	return [make_spell_gambit(spell), make_attack_gambit()]


## Join the samples to their battles' outcomes and write the CSV.
##
## A battle with no terminal verdict has NO GROUND TRUTH, so every sample from it
## is dropped rather than guessed at — and the count is printed, because a rig
## that silently truncated its corpus would read as "covered everything".
func _write_corpus() -> void:
	if _samples.is_empty():
		print("[corpus] no samples — nothing to write")
		return

	var keys: Array = RolloutHarness.record_key_map().keys()
	keys.sort()
	# `lever_digest` is the provenance stamp (ADR-0277 dec. 10): a hash of the
	# COMPOSED effective factors plus the pacing layer's live values. Per ROW
	# and not in a sidecar, because a sidecar separates from its data and a row
	# that travels alone loses the one thing that says what produced it. It is
	# read per row rather than once, so a scrub mid-run writes TWO digests into
	# one file — which is the truth about that run, and a reader can split or
	# reject it. Freezing it at start would claim a uniformity the file lacks.
	var header: Array = ["round", "battle", "tick"] + keys + [
		"terminal_result", "terminal_ticks", "ticks_remaining", "team0_wins",
		"lever_digest"]

	var dir_abs := ProjectSettings.globalize_path(_out.get_base_dir() + "/")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var path := ProjectSettings.globalize_path(_out)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[corpus] could not open %s for writing" % path)
		return
	f.store_line(",".join(header))

	# Feature ranges, printed below. A field that never moved is either a dead
	# feature or a shader that never wrote it, and those two look identical in a
	# CSV nobody summarises. Never report a zero without a positive control.
	var lo := {}
	var hi := {}
	var wins := 0
	for s in _samples:
		var key: String = "%d:%d" % [s["round"], s["battle"]]
		if not _labels.has(key):
			_stats["dropped"] += 1
			continue
		var label: Dictionary = _labels[key]
		var terminal_ticks: int = int(label["ticks"])
		var team0_wins: int = 1 if int(label["result"]) == GPUBatchSimulator.RESULT_TEAM_0_WINS else 0
		wins += team0_wins
		var cols: Array = [s["round"], s["battle"], s["tick"]]
		for k in keys:
			cols.append(s[k])
			lo[k] = mini(int(lo.get(k, s[k])), int(s[k]))
			hi[k] = maxi(int(hi.get(k, s[k])), int(s[k]))
		cols.append_array([label["result"], terminal_ticks,
			terminal_ticks - int(s["tick"]), team0_wins, s["lever_digest"]])
		f.store_line(",".join(cols.map(func(c): return str(c))))
		_stats["rows"] += 1
	f.close()

	print("\n--- corpus ---")
	print("  seated %d battles over %d rounds: %d finished, %d hit the %d-tick cap" % [
		_stats["seated"], _rounds, _stats["finished"], _stats["unfinished"], _max_ticks])
	print("  %d rows written, %d samples DROPPED for having no terminal verdict" % [
		_stats["rows"], _stats["dropped"]])
	# More than one digest means the configuration MOVED mid-run and the file is
	# not one measurement. Printed rather than rejected: the rows are honest
	# about it, and the reader decides whether to split them.
	var digests := {}
	for s in _samples:
		digests[s["lever_digest"]] = true
	print("  lever digests in this corpus: %d (%s)%s" % [
		digests.size(), ", ".join(PackedStringArray(digests.keys())),
		"  <-- THE CONFIGURATION MOVED MID-RUN" if digests.size() > 1 else ""])
	if _stats["rows"] > 0:
		print("  team 0 won %.1f%% of the sampled states' battles" % [
			100.0 * float(wins) / float(_stats["rows"])])
	print("  feature ranges (a field that never moves is a dead feature OR an unwritten one):")
	for k in keys:
		# `result` is RESULT_ONGOING on every row BY CONSTRUCTION — only live
		# states are sampled — so its flag is expected and means nothing. Every
		# other constant is a finding.
		var expected := " (expected: only live states are sampled)" if k == "result" else ""
		print("    %-16s %8d .. %-8d %s%s" % [k, int(lo.get(k, 0)), int(hi.get(k, 0)),
			"<-- CONSTANT" if int(lo.get(k, 0)) == int(hi.get(k, 0)) else "", expected])
	print("[corpus] CSV written to %s" % path)


func _finish() -> void:
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
