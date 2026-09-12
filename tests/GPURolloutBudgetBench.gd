extends GPUCombatTestBase

## GPU Rollout Budget Bench — the COST side of §7's `K x M x H` (#890, map #886).
##
## GambitBattle's enemy picks its gambit edit by running a **rollout fleet**: `K`
## candidate edits x `M` common-random-number seeds = `K*M` battles, each carried
## `H` ticks forward from a snapshot of the live battle, then scored. The whole
## fleet is one batch in one `GPUBatchSimulator`, so a **thinking beat** costs
## exactly three legs, and this rig times all three:
##
##   fill  — `restore_battle(b, snap)` into every fleet slot (5 `buffer_update`s
##           each), with the CRN seed rewritten per slot
##   run   — ONE `step_tick(H)`: the whole fleet advances H ticks inside a single
##           submit/sync, because every battle in the batch is dispatched by the
##           same compute list
##   score — reading the fleet back out so the value function can rank it
##
## It sweeps `(battles, units_per_battle)` because rollout compute scales with
## **allocated** slots, not living units: teams split at the midpoint and
## `units_per_battle = 2 * max(t0, t1)`, so an asymmetric battle pays for padding.
## `MAX_UNITS_PER_BATTLE = 8` is vestigial (one reference in the tree, its own
## declaration) and does NOT bound the sweep.
##
## 🔴 EVERY BATTLE IS POPULATED, AND THAT IS THE WHOLE MEASUREMENT. An unconfigured
## battle's result word is zero, which reads as `RESULT_TEAM_0_WINS`, and
## `stage_compute.glsl`'s `if (result != RESULT_ONGOING) return;` retires all of its
## threads on the first instruction. A sweep that allocates 1024 battles and
## configures one measures an empty machine. `--` arg `populate=first` runs exactly
## that arm on purpose, to price the trap.
##
## Deliverable is a MEASUREMENT, not a guard: it asserts nothing and gates nothing.
## §10 is explicit that no size cap gets hardcoded — a ceiling found here belongs in
## an ADR-0068 tunable, set by whoever wires the AI (#897).
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . tests/GPURolloutBudgetBench.tscn
##   godot --path . tests/GPURolloutBudgetBench.tscn -- battles=1,16,256 units=8
##
## `--` args (all optional): `battles=` `units=` `horizon=` `pertick=` `warmup=`
## `roster=attack|cast` `populate=all|first` `profile=chunks` `prefork=`.
##
## Emits one `BENCH_ROW ...` line per configuration plus a CSV under
## `res://tests/logs/`, both for scripted before/after diffing.


const DEFAULT_BATTLES: Array[int] = [1, 4, 16, 64, 256, 1024]
const DEFAULT_UNITS: Array[int] = [8, 16, 32]
const DEFAULT_HORIZON := 300      # §7's starting H
const DEFAULT_PERTICK := 60       # ticks timed one-submit-each, for the fence cost
const DEFAULT_WARMUP := 20        # discarded — first ticks pay one-time GPU warmup
const SCORE_SAMPLE := 16          # battles sampled for the ongoing/finished count
const PROFILE_CHUNKS := 8          # battles sampled for the ongoing/finished count

const ABILITY_FIRE := 16          # a CAST roster's spell, for the `roster=cast` arm

var _battles: Array[int] = []
var _units: Array[int] = []
var _horizon: int = DEFAULT_HORIZON
var _pertick: int = DEFAULT_PERTICK
var _warmup: int = DEFAULT_WARMUP
var _roster: String = "attack"
var _populate: String = "all"
var _profile: bool = false
var _prefork: int = 0
var _rows: Array[Dictionary] = []
var _cells: Array = []            # walkable level-0 cells, sorted, for placement


func get_test_name() -> String:
	return "GPU Rollout Budget Bench"


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())
	print("[NOT_A_TEST] a cost measurement for the rollout budget (#890) — it times fill/run/score over a (battles x units) sweep and asserts nothing")

	_parse_args()

	await get_tree().process_frame
	await get_tree().process_frame

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, into a LOCAL
	# annotated here, then stored (the field is inherited from `CombatHost`).
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		print("[bench] map has no lattice — nothing to measure")
		_finish()
		return

	_collect_cells()
	_setup_distance_field()
	var df: DistanceFieldGenerator = combat_loop.distance_field
	if not df:
		print("[bench] no distance field — nothing to measure")
		_finish()
		return

	print("[bench] adapter: %s" % RenderingServer.get_video_adapter_name())
	# The placement cells are printed because the map is BUILT, not loaded: two runs
	# that disagree about the terrain are measuring two different battles, and the
	# cell count alone cannot tell them apart.
	print("[bench] unit block %d ints, shader v%d, walkable cells %d, first %s last %s" % [
		GPUCombatPacker.UNIT_SIZE, GPUCombatPacker.SHADER_VERSION, _cells.size(),
		str(_cells[0]) if not _cells.is_empty() else "-",
		str(_cells[_cells.size() - 1]) if not _cells.is_empty() else "-"])
	print("[bench] sweep battles=%s units=%s horizon=%d prefork=%d roster=%s populate=%s" % [
		str(_battles), str(_units), _horizon, _prefork, _roster, _populate])

	for u in _units:
		for n in _battles:
			_measure(df, n, u)
			# One frame between configurations so the driver is not asked to build
			# and tear down local devices back to back.
			await get_tree().process_frame

	_report()
	_finish()


func _process(_delta):
	pass


func _parse_args() -> void:
	_battles = DEFAULT_BATTLES.duplicate()
	_units = DEFAULT_UNITS.duplicate()
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		var key: String = parts[0].lstrip("-")
		var val: String = parts[1]
		match key:
			"battles":
				_battles = _int_list(val)
			"units":
				_units = _int_list(val)
			"horizon":
				_horizon = int(val)
			"pertick":
				_pertick = int(val)
			"warmup":
				_warmup = int(val)
			"roster":
				_roster = val
			"populate":
				_populate = val
			"profile":
				_profile = val == "chunks"
			"prefork":
				_prefork = int(val)


func _int_list(val: String) -> Array[int]:
	var out: Array[int] = []
	for piece in val.split(",", false):
		out.append(int(piece))
	return out


## Every level-0 cell a unit may stand on, in a stable order. Placement takes
## team 0 off the front and team 1 off the back, so the two teams start apart and
## walk toward each other whatever the map's size.
func _collect_cells() -> void:
	var cells: Array = []
	# `lattice` is declared on `CombatHost`, and annotation inference is PER FILE,
	# so the port guard reads the inherited field as an undeclared receiver. One
	# typed local, the same shape `GPUCombatTestBase:782` already uses.
	var lat: Lattice = lattice
	for c in lat.all_cells():
		if c.grid.z != 0:
			continue
		if c.impassable or c.pass_through_only:
			continue
		cells.append(c.grid)
	cells.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	_cells = cells


## One (battles x units_per_battle) configuration, start to finish: a fresh
## simulator, a populated fleet, then the three legs of a thinking beat.
func _measure(df: DistanceFieldGenerator, num_battles: int, units_per_battle: int) -> void:
	var per_team: int = units_per_battle / 2
	if _cells.size() < units_per_battle:
		print("[bench] N=%-5d U=%-3d SKIPPED — map has %d walkable cells, needs %d" % [
			num_battles, units_per_battle, _cells.size(), units_per_battle])
		return

	var t_init := Time.get_ticks_usec()
	var sim := GPUBatchSimulator.new()
	if not sim.initialize(lattice, df, num_battles, units_per_battle):
		sim.cleanup()
		print("[bench] N=%-5d U=%-3d FAILED to initialize (VRAM?)" % [num_battles, units_per_battle])
		return
	var init_ms := float(Time.get_ticks_usec() - t_init) / 1000.0

	var team0: Array = []
	var team1: Array = []
	for i in range(per_team):
		team0.append(_build_gpu_config(_cells[i], _bench_unit_cfg(i, 0)))
		team1.append(_build_gpu_config(_cells[_cells.size() - 1 - i], _bench_unit_cfg(i, 1)))

	var populated: int = num_battles if _populate == "all" else 1
	var t_pop := Time.get_ticks_usec()
	for b in range(populated):
		_seat_battle(sim, b, team0, team1, units_per_battle, 1000 + b * 7919)
	var populate_ms := float(Time.get_ticks_usec() - t_pop) / 1000.0

	for _i in range(_warmup):
		sim.step_tick(1)

	# --- Leg 0: the per-tick fence, one submit/sync per tick. This is what the
	# LIVE battle pays (CombatLoop steps one tick at a time); the fleet does not.
	var samples := PackedFloat64Array()
	samples.resize(_pertick)
	for t in range(_pertick):
		var t0 := Time.get_ticks_usec()
		sim.step_tick(1)
		samples[t] = float(Time.get_ticks_usec() - t0)
	var sorted := samples.duplicate()
	sorted.sort()
	var median_us: float = sorted[sorted.size() / 2]
	var p99_us: float = sorted[int(sorted.size() * 0.99)]

	# Re-seat, so the horizon below starts from a fresh battle rather than one
	# already `_warmup + _pertick` ticks old.
	for b in range(populated):
		_seat_battle(sim, b, team0, team1, units_per_battle, 1000 + b * 7919)

	# 🔴 A ROLLOUT DOES NOT START FROM A FRESH BATTLE. §7 forks the LIVE battle at
	# an enemy turn — units already engaged, some already dead — and the chunk
	# profile shows a tick in that regime costing several times an opening tick.
	# `prefork=T` advances battle 0 by T ticks BEFORE the snapshot, so the fleet is
	# forked from a position of that age. `prefork=0` (the default) measures the
	# cheapest position a rollout can ever start from, which is a FLOOR, not the
	# expected cost.
	if _prefork > 0:
		sim.step_tick(_prefork)

	# --- Leg 1: FILL. §7's fork — snapshot the live battle once, then install it
	# into every fleet slot with the CRN seed rewritten per slot.
	var t_snap := Time.get_ticks_usec()
	var snap: Dictionary = sim.snapshot_battle(0)
	var snapshot_ms := float(Time.get_ticks_usec() - t_snap) / 1000.0
	# 🔴 THE FILL IS WHAT MAKES A SLOT LIVE. `restore_battle` installs battle 0's
	# header, `RESULT_ONGOING` and all, so filling every slot ERASES the difference
	# between a populated fleet and an empty one — which is why `populate=first`
	# has to skip the fill as well as the seating, or the arm measures nothing.
	# The seed spacing here is arbitrary: this rig prices the fill, and CRN seed
	# spacing is a statistical question #895 owns.
	var t_fill := Time.get_ticks_usec()
	var image: PackedInt32Array = snap["battle"]
	for b in range(1, populated):
		image[GPUCombatPacker.BattleHeaderField.SEED] = 90001 + b * 131
		snap["battle"] = image
		sim.restore_battle(b, snap)
	var fill_ms := float(Time.get_ticks_usec() - t_fill) / 1000.0

	# --- Leg 2: RUN. The whole fleet, H ticks, ONE submit/sync.
	var t_run := Time.get_ticks_usec()
	sim.step_tick(_horizon)
	var run_ms := float(Time.get_ticks_usec() - t_run) / 1000.0
	# Did the horizon actually run? `step_tick(H)` is one compute list of H*8
	# dispatches, and a batch that silently ran fewer ticks would read as a win.
	# Read BEFORE the optional chunk profile, which advances the clock again.
	var end_tick: int = sim.get_battle_tick(0)

	# `profile=chunks` re-runs the horizon in PROFILE_CHUNKS equal slices, timing
	# each. A horizon whose cost is superlinear in H is not a driver artefact of a
	# long compute list — it is later ticks being BUSIER than early ones (units
	# spend the opening walking toward each other and the rest fighting), and the
	# only way to tell those apart is to watch the cost climb inside one battle.
	if _profile:
		for b in range(populated):
			_seat_battle(sim, b, team0, team1, units_per_battle, 1000 + b * 7919)
		var chunk: int = maxi(1, _horizon / PROFILE_CHUNKS)
		var marks: Array[String] = []
		for c in range(PROFILE_CHUNKS):
			var t_c := Time.get_ticks_usec()
			sim.step_tick(chunk)
			marks.append("%d-%d:%.1fms" % [c * chunk, (c + 1) * chunk,
				float(Time.get_ticks_usec() - t_c) / 1000.0])
		print("  [profile] N=%d U=%d ticks %s" % [num_battles, units_per_battle, " ".join(marks)])

	# --- Leg 3: SCORE. Two shapes: the per-battle column read a value function
	# over unit state needs, and the one bulk read of the result buffer.
	var f_hp: int = GPUCombatPacker.UnitField.HP
	var t_score := Time.get_ticks_usec()
	for b in range(num_battles):
		sim.read_unit_column(b, f_hp)
	var score_ms := float(Time.get_ticks_usec() - t_score) / 1000.0
	var t_res := Time.get_ticks_usec()
	var _r: Dictionary = sim.get_battle_result(0)
	var results_ms := float(Time.get_ticks_usec() - t_res) / 1000.0

	# How much of the horizon was actually simulated: a battle that ENDS inside H
	# retires its threads for the rest of it, so a fleet of short battles is
	# cheaper than the same fleet of long ones. Sampled, because the public
	# surface answers this one battle at a time.
	var sample: int = mini(SCORE_SAMPLE, num_battles)
	var finished := 0
	var tick_sum := 0
	for b in range(sample):
		var res: Dictionary = sim.get_battle_result(b)
		if int(res.get("winner", -1)) != GPUBatchSimulator.RESULT_ONGOING:
			finished += 1
			tick_sum += int(res.get("ticks", 0))

	# Did the roster do what its name says? A CAST roster whose spells never fire
	# prices an ATTACK battle under another name — every ability carries
	# `cooldown_ticks: 300`, so a nonzero `cooldown_ready_at` is the witness that a
	# cast actually committed. An ATTACK roster leaves that SSBO all-zero, which is
	# the control.
	var cast_witness := 0
	for b in range(sample):
		for i in range(units_per_battle):
			if sim.get_cooldown_ready_at(b, i, ABILITY_FIRE) != 0:
				cast_witness += 1
	var alive0 := 0
	for hp in sim.read_unit_column(0, f_hp):
		if hp > 0:
			alive0 += 1

	var beat_ms: float = fill_ms + run_ms + score_ms
	var tick_rate: float = float(_horizon) / (run_ms / 1000.0) if run_ms > 0.0 else 0.0
	var battle_tick_rate: float = tick_rate * float(num_battles)

	print("  N=%-5d U=%-3d | per-tick %7.1f us (p99 %7.1f) | fill %7.2f ms  run %8.2f ms  score %6.2f ms | beat %8.2f ms | %8.0f ticks/s  %11.0f battle-ticks/s | finished %d/%d alive0 %d/%d cast %d" % [
		num_battles, units_per_battle, median_us, p99_us, fill_ms, run_ms, score_ms,
		beat_ms, tick_rate, battle_tick_rate, finished, sample, alive0, units_per_battle,
		cast_witness])
	if end_tick != _horizon + _prefork:
		print("  [bench] N=%d U=%d ran %d ticks, asked for %d" % [
			num_battles, units_per_battle, end_tick, _horizon + _prefork])
	print("BENCH_ROW battles=%d units=%d roster=%s populate=%s horizon=%d prefork=%d end_tick=%d per_tick_us=%.1f p99_us=%.1f fill_ms=%.2f snapshot_ms=%.2f run_ms=%.2f score_ms=%.2f results_ms=%.2f beat_ms=%.2f ticks_per_s=%.0f battle_ticks_per_s=%.0f finished=%d/%d alive0=%d cast_witness=%d avg_end_tick=%.0f init_ms=%.1f populate_ms=%.1f" % [
		num_battles, units_per_battle, _roster, _populate, _horizon, _prefork, end_tick, median_us, p99_us,
		fill_ms, snapshot_ms, run_ms, score_ms, results_ms, beat_ms, tick_rate,
		battle_tick_rate, finished, sample, alive0, cast_witness,
		(float(tick_sum) / finished) if finished > 0 else 0.0, init_ms, populate_ms])

	_rows.append({
		"battles": num_battles, "units": units_per_battle, "per_tick_us": median_us,
		"p99_us": p99_us, "fill_ms": fill_ms, "run_ms": run_ms, "score_ms": score_ms,
		"results_ms": results_ms, "beat_ms": beat_ms, "ticks_per_s": tick_rate,
		"battle_ticks_per_s": battle_tick_rate, "finished": finished, "sample": sample,
		"init_ms": init_ms, "populate_ms": populate_ms,
		"alive0": alive0, "cast_witness": cast_witness,
	})

	sim.cleanup()


func _seat_battle(sim: GPUBatchSimulator, battle_id: int, team0: Array, team1: Array,
		units_per_battle: int, battle_seed: int) -> void:
	sim.set_battle_units(battle_id, team0, team1, battle_seed)
	for i in range(units_per_battle):
		sim.set_unit_gambits(battle_id, i, _bench_gambits())


## The bench roster. Stats are uniform on purpose — this measures COST, and a
## roster whose units differ only by seat would make the shape harder to read.
## `speed` is FFT Speed (5..13, what `atb_speed` carries), not the legacy 65..100.
func _bench_unit_cfg(seat: int, team: int) -> Dictionary:
	return {
		"name": "%s%d" % ["P" if team == 0 else "E", seat],
		"hp": 200, "max_hp": 200, "pa": 12, "ma": 10, "wp": 6,
		"brave": 60, "faith": 60, "mp": 200, "max_mp": 200,
		"speed": 8, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"c_ev": 10, "s_ev": 15, "w_ev": 10,
		"body_sprite_id": 0x02 if team == 0 else 0x05,
	}


## ATTACK-only is the floor of the workload; a CAST roster adds the charge/spell
## path AND the cooldown SSBO (every ability carries `cooldown_ticks: 300`, so an
## attack-only battle leaves that buffer untouched).
func _bench_gambits() -> Array:
	if _roster == "cast":
		return [make_spell_gambit(ABILITY_FIRE), make_attack_gambit()]
	return [make_attack_gambit()]


func _report() -> void:
	if _rows.is_empty():
		print("[bench] no rows measured")
		return
	print("\n--- Thinking beat at K x M x H (H = %d, roster=%s) ---" % [_horizon, _roster])
	print("  A fleet of K*M battles costs the row whose `battles` is K*M.")
	for row in _rows:
		var n: int = row["battles"]
		print("  K*M=%-5d U=%-3d : beat %8.2f ms   (fill %.2f + run %.2f + score %.2f)" % [
			n, row["units"], row["beat_ms"], row["fill_ms"], row["run_ms"], row["score_ms"]])
	_write_csv()


func _write_csv() -> void:
	var dir_abs := ProjectSettings.globalize_path("res://tests/logs/")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var path := dir_abs.path_join("rollout_budget_%s_%s.csv" % [_roster, _populate])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[bench] could not open CSV at %s" % path)
		return
	f.store_line("battles,units,per_tick_us,p99_us,fill_ms,run_ms,score_ms,results_ms,beat_ms,ticks_per_s,battle_ticks_per_s,finished,sample,init_ms,populate_ms,alive0,cast_witness")
	for row in _rows:
		f.store_line("%d,%d,%.1f,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%.0f,%.0f,%d,%d,%.1f,%.1f,%d,%d" % [
			row["battles"], row["units"], row["per_tick_us"], row["p99_us"], row["fill_ms"],
			row["run_ms"], row["score_ms"], row["results_ms"], row["beat_ms"],
			row["ticks_per_s"], row["battle_ticks_per_s"], row["finished"], row["sample"],
			row["init_ms"], row["populate_ms"], row["alive0"], row["cast_witness"]])
	f.close()
	print("[bench] CSV written to %s" % path)


func _finish() -> void:
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
