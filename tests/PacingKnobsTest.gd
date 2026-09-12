extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: make `scale_hp_transfer` in combat_common.glslinc ignore its scale argument
# (return the raw transfer) — the damage-scale arm reds while the move-time arm stays green,
# which is the three-ways-to-go-dead split this test is built to tell apart.

## Pacing knobs — the two `pacing.*` tunables are LIVE, not inert.
##
## `pacing.damage_scale` and `pacing.move_time_scale` re-time FFT's turn-based
## balance for continuous combat (see `scale_hp_transfer` / `scale_move_ticks` in
## `combat_common.glslinc`). Both ride SimConfig, which means they can go dead in
## three separate ways this test is built to tell apart:
##
##   1. the GDScript never reaches the buffer (a stale 9-int `config_data`),
##   2. the buffer never reaches the SHADER the batched path binds
##      (`_config_buffer_pair` is what `_run_tick` binds, not `_config_buffer`),
##   3. the shader reads the field and the helper is a no-op.
##
## 🔴 EVERY ARM CARRIES ITS OWN POSITIVE CONTROL. A knob that silenced the whole
## battle and a knob that did nothing both produce "the numbers did not go up",
## so each arm asserts the BASELINE moved first — damage actually landed, units
## actually walked — and only then that the scrubbed arm differs in the stated
## direction. Without the baseline assertion this test passes on a broken map.
##
## The two arms measure DIFFERENT observables on purpose: damage is scored as HP
## lost over a fixed horizon (a rate), movement as the tick of first contact (a
## delay). Scoring both the same way would let one knob's effect masquerade as
## the other's.
##
## Run headful (never --headless), from `godot-learning/`:
##   godot --path . --quit-after 900 tests/PacingKnobsTest.tscn

const MOVE_SLUG := GPUBatchSimulator.MOVE_TIME_SCALE_SLUG
const DAMAGE_SLUG := GPUBatchSimulator.DAMAGE_SCALE_SLUG

## Units per battle (two teams of two). Small — this is a DIRECTION test, not a
## balance measurement, and every extra seat is horizon the arms have to agree on.
const UNITS_PER_BATTLE := 4
## Horizon for the damage arm. Long enough past first contact (~450 ticks here)
## that the baseline lands several hits, and SHORT enough that it kills nobody: a
## horizon that runs the baseline to a wipe SATURATES — the dead stop taking
## damage, the arms converge, and the measurement stops being a rate. Assert the
## no-death property rather than trusting the number, because the tick of first
## contact is a property of the generated map.
const DAMAGE_HORIZON := 900
## Horizon for the movement arm: a ceiling on "first contact", not a target.
const CONTACT_HORIZON := 2400
## The scrubbed values. Deliberately far from 1.0: this asserts DIRECTION, and a
## knob one rounding step from its default would be a test of `round()`.
const DAMAGE_SCRUB := 0.25
const MOVE_SCRUB := 3.0
## Same seed both arms, so the only difference between them is the knob.
const BATTLE_SEED := 20260907

var _cells: Array = []
var _passed: int = 0
var _failed: int = 0


func get_test_name() -> String:
	return "Pacing Knobs"


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		_fail("map has no lattice — nothing to measure")
		_report()
		return

	_collect_cells()
	_setup_distance_field()
	var df: DistanceFieldGenerator = combat_loop.distance_field
	if not df:
		_fail("no distance field — nothing to measure")
		_report()
		return
	if _cells.size() < UNITS_PER_BATTLE:
		_fail("map has %d walkable cells, needs %d" % [_cells.size(), UNITS_PER_BATTLE])
		_report()
		return

	# The subject, printed: an empty register here would otherwise read as "the
	# knobs are fine" rather than "nothing was examined".
	print("[pacing] shader v%d, walkable cells %d, first %s last %s" % [
		GPUCombatPacker.SHADER_VERSION, _cells.size(), str(_cells[0]), str(_cells[-1])])

	var sim := GPUBatchSimulator.new()
	if not sim.initialize(lattice, df, 1, UNITS_PER_BATTLE):
		sim.cleanup()
		_fail("simulator failed to initialize (VRAM?)")
		_report()
		return

	_run_damage_arm(sim)
	await get_tree().process_frame
	_run_move_arm(sim)

	sim.cleanup()
	# Leave the registry as this test found it — a scrub that outlived the test
	# would re-time every battle in the same process.
	Tune.set_value(DAMAGE_SLUG, 1.0)
	Tune.set_value(MOVE_SLUG, 1.0)
	_report()


func _process(_delta):
	pass


# --- Arm 1: damage --------------------------------------------------------

## HP lost across the whole battle over a fixed horizon. A RATE: the horizon is
## identical in both arms, so fewer HP lost means each transfer was smaller, not
## that the battle went differently.
func _run_damage_arm(sim: GPUBatchSimulator) -> void:
	Tune.set_value(MOVE_SLUG, 1.0)

	Tune.set_value(DAMAGE_SLUG, 1.0)
	var base_lost := _hp_lost_over(sim, DAMAGE_HORIZON)
	var base_alive := _alive_count(sim)

	Tune.set_value(DAMAGE_SLUG, DAMAGE_SCRUB)
	var scrub_lost := _hp_lost_over(sim, DAMAGE_HORIZON)

	print("[pacing] damage: 1.0x lost %d HP, %.2fx lost %d HP over %d ticks (%d/%d alive at 1.0x)" % [
		base_lost, DAMAGE_SCRUB, scrub_lost, DAMAGE_HORIZON, base_alive, UNITS_PER_BATTLE])

	# Positive control FIRST — a battle where nothing hits scores 0 in both arms.
	_check(base_lost > 0,
		"baseline landed damage (%d HP lost at 1.0x)" % base_lost)
	_check(scrub_lost < base_lost,
		"damage_scale %.2f cut HP lost (%d < %d)" % [DAMAGE_SCRUB, scrub_lost, base_lost])
	# The knob must SCALE, not silence: a `max(1, ...)` floor per transfer keeps
	# every ability able to hurt, and an arm that reached zero would mean the
	# floor is gone and units are invulnerable to whatever hit them.
	_check(scrub_lost > 0,
		"damage_scale %.2f still lands hits (%d HP lost)" % [DAMAGE_SCRUB, scrub_lost])
	# Un-saturated: with everyone still standing, both arms had the same number of
	# swingers for the whole horizon and the comparison is a rate.
	_check(base_alive == UNITS_PER_BATTLE,
		"baseline horizon killed nobody (%d/%d alive) — arms are comparable" % [
			base_alive, UNITS_PER_BATTLE])


func _hp_lost_over(sim: GPUBatchSimulator, ticks: int) -> int:
	_seat(sim)
	var before := _total_hp(sim)
	sim.step_tick(ticks)
	return before - _total_hp(sim)


# --- Arm 2: movement ------------------------------------------------------

## The tick of first contact. A DELAY, not a rate: the units start apart and must
## walk, so a longer travel time pushes the first HP change later even though the
## damage per hit is unchanged.
func _run_move_arm(sim: GPUBatchSimulator) -> void:
	Tune.set_value(DAMAGE_SLUG, 1.0)

	Tune.set_value(MOVE_SLUG, 1.0)
	var base_tick := _first_contact_tick(sim)

	Tune.set_value(MOVE_SLUG, MOVE_SCRUB)
	var scrub_tick := _first_contact_tick(sim)

	print("[pacing] movement: 1.0x contact at tick %d, %.2fx contact at tick %d (cap %d)" % [
		base_tick, MOVE_SCRUB, scrub_tick, CONTACT_HORIZON])

	# Positive control: contact must actually HAPPEN in the baseline, else both
	# arms return the cap and the comparison is between two timeouts.
	_check(base_tick > 0 and base_tick < CONTACT_HORIZON,
		"baseline made contact at tick %d (before the %d cap)" % [base_tick, CONTACT_HORIZON])
	_check(scrub_tick > base_tick,
		"move_time_scale %.2f delayed contact (tick %d > %d)" % [MOVE_SCRUB, scrub_tick, base_tick])


## Ticks until the first HP change, or `CONTACT_HORIZON` if none. Stepped in
## small chunks rather than one at a time: a per-tick readback would price the
## fence into a measurement that only cares about ordering.
func _first_contact_tick(sim: GPUBatchSimulator) -> int:
	const CHUNK := 10
	_seat(sim)
	var before := _total_hp(sim)
	var t := 0
	while t < CONTACT_HORIZON:
		sim.step_tick(CHUNK)
		t += CHUNK
		if _total_hp(sim) != before:
			return t
	return CONTACT_HORIZON


# --- Shared ---------------------------------------------------------------

## Team 0 off the front of the cell list, team 1 off the back, so the two sides
## start as far apart as the map allows and the movement arm has a walk to time.
func _seat(sim: GPUBatchSimulator) -> void:
	var per_team: int = UNITS_PER_BATTLE / 2
	var team0: Array = []
	var team1: Array = []
	for i in range(per_team):
		team0.append(_build_gpu_config(_cells[i], _unit_cfg(i, 0)))
		team1.append(_build_gpu_config(_cells[_cells.size() - 1 - i], _unit_cfg(i, 1)))
	sim.set_battle_units(0, team0, team1, BATTLE_SEED)
	for i in range(UNITS_PER_BATTLE):
		sim.set_unit_gambits(0, i, [make_attack_gambit()])


## Plain melee. ATTACK carries no ability_id, so neither arm is gated by the
## ADR-0047 cooldown — this measures the pacing knobs, not the cooldown floor.
## Evasion is zeroed so a run of misses cannot be mistaken for a smaller knob.
##
## HP is far above FFT's range on purpose. At a faithful 400 the baseline wipes
## half the field within ~350 ticks of contact — which is the very pacing problem
## these knobs exist to fix, and which would SATURATE this arm. The inflated pool
## buys a horizon where both arms swing with the same number of units throughout.
func _unit_cfg(seat: int, team: int) -> Dictionary:
	return {
		"name": "%s%d" % ["P" if team == 0 else "E", seat],
		"hp": 2000, "max_hp": 2000, "pa": 12, "ma": 10, "wp": 6,
		"brave": 60, "faith": 60, "mp": 100, "max_mp": 100,
		"speed": 8, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x02 if team == 0 else 0x05,
	}


func _alive_count(sim: GPUBatchSimulator) -> int:
	var hp := sim.read_unit_column(0, GPUCombatPacker.UnitField.HP)
	var alive := 0
	for v in hp:
		if v > 0:
			alive += 1
	return alive


func _total_hp(sim: GPUBatchSimulator) -> int:
	var hp := sim.read_unit_column(0, GPUCombatPacker.UnitField.HP)
	var total := 0
	for v in hp:
		total += v
	return total


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


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok   %s" % what)
	else:
		_failed += 1
		print("  BAD  %s" % what)


func _fail(why: String) -> void:
	_failed += 1
	print("  BAD  %s" % why)


func _report() -> void:
	print("\n=== %s: %d passed, %d failed ===" % [get_test_name(), _passed, _failed])
	# The marker `tests/lib/verdict.sh` scores on. "N passed" above is for a human
	# reading the log; this line is the one the runner reads.
	if _failed > 0:
		print("[FAIL] %d of %d pacing checks failed" % [_failed, _passed + _failed])
	else:
		print("[PASS] pacing.damage_scale and pacing.move_time_scale both reach the shader")
	_finish()


func _finish() -> void:
	# A FRAME, not a duration (charter C14).
	await get_tree().process_frame
	get_tree().quit(0)
