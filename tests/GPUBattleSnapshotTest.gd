extends "res://tests/GPUSeedReproTest.gd"

## GPU Battle Snapshot / Reconfigure Test — the GambitBattle keystone (ADR-0235).
##
## The design's §2 gate: `snapshot → restore → run N ticks` must be bit-identical
## to running N ticks without the round trip. A lossy round trip was rejected
## because the enemy AI would fork into a world that differs from the one it is
## advising on, and that divergence is INVISIBLE — it presents as an AI that is
## subtly, unaccountably bad.
##
## Four arms, on the seed-locked 4v4 from GPUSeedReproTest re-gambited to CAST
## (every ability carries `cooldown_ticks: 300`, so a spell gambit is what puts
## live state in the separately-buffered cooldown SSBO — with attack-only gambits
## that slice stays all-zero and the arm below would pass vacuously):
##
##   A. Slice identity — `snapshot → restore → snapshot` returns the same four
##      slices. Proves every captured slice is written back, independent of
##      whether the battle happens to exercise it.
##   B. Bit-identity (the §2 gate) — reference N ticks from the snapshot point,
##      restore, run N again, compare all 102 fields of all 8 units plus all four
##      slices. N is ODD on purpose: the second run therefore starts on the
##      OPPOSITE ping-pong half, so a restore that wrote only one half fails here.
##   C. No-op reconfigure identity — reconfigure a unit mid-battle with its
##      UNCHANGED config; all 102 offsets must be byte-identical. This is the arm
##      that catches a field misclassified `recompute`-when-it-should-be-`carry`
##      (the silent-reset failure) without knowing what a job change should do.
##   D. Job-change arm — the `recompute` set moved, the `clamp` set clamped, the
##      `carry` set and every non-schema offset did not. Without it, C could pass
##      by doing nothing at all.
##
## The exhaustive-over-every-offset half of C/D lives in UnitEncodeSchemaTest
## (pure, no GPU): a real battle only diverges the fields it happens to touch, so
## a GPU arm alone cannot see a misclassified field the battle never moved.
##
## Run headful (never --headless):
##   godot --path . tests/GPUBattleSnapshotTest.tscn

const ABILITY_FIRE = 16
const WARMUP_TICKS = 200    # long enough for casts to land, cooldowns to arm
const DIVERGE_TICKS = 181   # ODD — see arm B

var _snap_failed: bool = false
var _snap_reason: String = ""
var _unit_cfgs: Array = []          # the unit_config dicts the battle was built from
var _key_by_offset: Dictionary = {}  # UnitField offset -> SNAPSHOT_FIELDS key


func get_test_name() -> String:
	return "GPU Battle Snapshot Test"


# Cast, don't just swing — this is what makes the cooldown slice non-empty.
func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_spell_gambit(ABILITY_FIRE), make_attack_gambit()]


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, into a LOCAL
	# annotated here (the field is inherited from `CombatHost`).
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		_snap_fail("Map has no lattice")
		_finish()
		return

	_setup_distance_field()
	_setup_gpu_simulator()
	await _create_units()

	if not gpu_simulator:
		_snap_fail("GPU simulator not available")
		_finish()
		return

	for k in GPUCombatPacker.SNAPSHOT_FIELDS:
		_key_by_offset[GPUCombatPacker.SNAPSHOT_FIELDS[k]] = k

	_configure_battle()
	gpu_simulator.step_tick(WARMUP_TICKS)

	if gpu_simulator.is_battle_finished(0):
		_snap_fail("battle already finished at tick %d — every arm below would be vacuous" % WARMUP_TICKS)
		_finish()
		return

	var snap: Dictionary = gpu_simulator.snapshot_battle(0)
	if snap.is_empty():
		_snap_fail("snapshot_battle(0) returned {}")
		_finish()
		return
	_report_snapshot(snap)

	_arm_a_slice_identity(snap)
	if not _snap_failed:
		_arm_b_bit_identity(snap)
	if not _snap_failed:
		_arm_c_noop_reconfigure()
	if not _snap_failed:
		_arm_d_job_change()
	_finish()


func _process(_delta):
	pass


## Configure the seed-locked battle from scratch (resets both ping-pong halves).
func _configure_battle() -> void:
	var gpu_team0: Array = []
	var gpu_team1: Array = []
	var team0_configs = get_team0_unit_configs()
	var team1_configs = get_team1_unit_configs()
	for i in range(team0_units.size()):
		gpu_team0.append(_build_gpu_config(
			team0_units[i].movement_component.current_cell, team0_configs[i]))
	for i in range(team1_units.size()):
		gpu_team1.append(_build_gpu_config(
			team1_units[i].movement_component.current_cell, team1_configs[i]))
	gpu_simulator.set_battle_units(0, gpu_team0, gpu_team1, TEST_SEED)
	_unit_cfgs = gpu_team0 + gpu_team1
	for i in range(_unit_cfgs.size()):
		gpu_simulator.set_unit_gambits(0, i, get_gambits_for_unit(i, 0 if i < gpu_team0.size() else 1))
	gpu_state_reader.initialize(gpu_simulator, 0)


## Say what the snapshot actually contains, so a vacuous slice is VISIBLE rather
## than reported as covered.
func _report_snapshot(snap: Dictionary) -> void:
	var nonzero := func(a: PackedInt32Array) -> int:
		var n := 0
		for v in a:
			if v != 0:
				n += 1
		return n
	print("[snapshot] tick=%d  battle=%d ints (%d nonzero)  cooldowns=%d (%d nonzero)  gambits=%d (%d nonzero)  results=%d" % [
		snap["battle"][GPUCombatPacker.BattleHeaderField.TICK],
		snap["battle"].size(), nonzero.call(snap["battle"]),
		snap["cooldowns"].size(), nonzero.call(snap["cooldowns"]),
		snap["gambits"].size(), nonzero.call(snap["gambits"]),
		snap["results"].size()])
	if nonzero.call(snap["cooldowns"]) == 0:
		_snap_fail("cooldown slice is all zero at tick %d — arms A and B would not test it" % WARMUP_TICKS)


## A. snapshot -> restore -> snapshot returns the same four slices.
func _arm_a_slice_identity(snap: Dictionary) -> void:
	if not gpu_simulator.restore_battle(0, snap):
		_snap_fail("A: restore_battle(0, snap) returned false")
		return
	var again: Dictionary = gpu_simulator.snapshot_battle(0)
	for slice in ["battle", "cooldowns", "gambits", "results"]:
		if not _slices_equal("A", slice, snap[slice], again[slice]):
			return
	print("[arm A] slice identity OK — all four slices survive a restore round trip")


## B. THE GATE. Reference N ticks, restore, run N again, compare everything.
func _arm_b_bit_identity(snap: Dictionary) -> void:
	var before_states: Array = gpu_simulator.get_battle_unit_states(0).duplicate(true)
	gpu_simulator.step_tick(DIVERGE_TICKS)
	var ref_states: Array = gpu_simulator.get_battle_unit_states(0).duplicate(true)
	var ref_snap: Dictionary = gpu_simulator.snapshot_battle(0)

	# Non-vacuity: the N ticks must actually have moved the world, or "identical"
	# means nothing.
	if _states_identical(before_states, ref_states):
		_snap_fail("B: %d ticks changed no unit field — the arm would pass on a no-op restore" % DIVERGE_TICKS)
		return

	if not gpu_simulator.restore_battle(0, snap):
		_snap_fail("B: restore_battle returned false")
		return
	gpu_simulator.step_tick(DIVERGE_TICKS)
	var got_states: Array = gpu_simulator.get_battle_unit_states(0)
	var got_snap: Dictionary = gpu_simulator.snapshot_battle(0)

	for u in range(ref_states.size()):
		var expected: Dictionary = ref_states[u]
		var got: Dictionary = got_states[u]
		for key in expected:
			if expected[key] != got.get(key):
				_snap_fail("B: unit=%d field=%s after %d ticks: straight-through=%s, via restore=%s" % [
					u, key, DIVERGE_TICKS, str(expected[key]), str(got.get(key))])
				return
	for slice in ["battle", "cooldowns", "gambits", "results"]:
		if not _slices_equal("B", slice, ref_snap[slice], got_snap[slice]):
			return
	print("[arm B] bit-identity OK — %d ticks through a restore match %d straight through, on the OPPOSITE ping-pong half" % [
		DIVERGE_TICKS, DIVERGE_TICKS])


## C. A no-op reconfigure moves NOTHING.
func _arm_c_noop_reconfigure() -> void:
	var idx := _pick_living_unit()
	if idx < 0:
		_snap_fail("C: no unit with hp >= 2 — the reconfigure arms cannot run")
		return
	var before: Dictionary = gpu_simulator.get_battle_unit_states(0)[idx].duplicate()
	if not gpu_simulator.reconfigure_unit(0, idx, _unit_cfgs[idx]):
		_snap_fail("C: reconfigure_unit returned false")
		return
	var after: Dictionary = gpu_simulator.get_battle_unit_states(0)[idx]
	var moved: Array = []
	for key in before:
		if before[key] != after.get(key):
			moved.append("%s %s->%s" % [key, str(before[key]), str(after.get(key))])
	if not moved.is_empty():
		_snap_fail("C: unchanged config moved %d of %d fields on unit %d: %s" % [
			moved.size(), before.size(), idx, ", ".join(moved)])
		return
	print("[arm C] no-op identity OK — an unchanged config moved 0 of %d fields at tick %d" % [
		before.size(), gpu_simulator.get_battle_state(0).get("tick", -1)])


## D. A real change moves the recompute set, clamps the clamp set, and leaves the
##    carry set and every non-schema offset alone.
func _arm_d_job_change() -> void:
	var idx := _pick_living_unit()
	if idx < 0:
		_snap_fail("D: no living unit")
		return
	var before: Dictionary = gpu_simulator.get_battle_unit_states(0)[idx].duplicate()
	var live_hp: int = before["hp"]
	var cfg: Dictionary = _unit_cfgs[idx].duplicate()
	cfg["pa"] = int(cfg.get("pa", 10)) + 7
	cfg["weapon_range"] = int(cfg.get("weapon_range", 1)) + 2
	cfg["max_hp"] = live_hp - 1          # BELOW the live hp, so the clamp must bite
	cfg["pos_x"] = int(before["pos_x"]) + 3   # a carry field the config disagrees about
	if not gpu_simulator.reconfigure_unit(0, idx, cfg):
		_snap_fail("D: reconfigure_unit returned false")
		return
	var after: Dictionary = gpu_simulator.get_battle_unit_states(0)[idx]

	# Recompute rows took the config value; clamp rows kept the live value under
	# the new ceiling; carry rows and non-schema offsets did not move. Driven off
	# the SCHEMA, not a hand-list, so a new row is covered the day it lands.
	var classified := {}
	for row in GPUCombatPacker.UNIT_CONFIG_SCHEMA:
		var field: int = row["field"]
		classified[field] = true
		var key: String = _key_by_offset[field]
		var behave: String = row["behave"]
		if behave == GPUCombatPacker.BEHAVE_RECOMPUTE:
			var want: int = cfg.get(row["key"], row["default"])
			if after[key] != want:
				_snap_fail("D: '%s' (%s) is recompute: expected %d, got %d" % [row["key"], key, want, after[key]])
				return
		elif behave == GPUCombatPacker.BEHAVE_CARRY:
			if after[key] != before[key]:
				_snap_fail("D: '%s' (%s) is carry but moved %s -> %s" % [
					row["key"], key, str(before[key]), str(after[key])])
				return
		elif behave == GPUCombatPacker.BEHAVE_CLAMP:
			var ceiling: int = after[_key_by_offset[row["clamp_to"]]]
			var want_c: int = mini(before[key], ceiling)
			if after[key] != want_c:
				_snap_fail("D: '%s' (%s) is clamp: live %d, ceiling %d, expected %d, got %d" % [
					row["key"], key, before[key], ceiling, want_c, after[key]])
				return
	for field in _key_by_offset:
		if classified.has(field):
			continue
		var k: String = _key_by_offset[field]
		if after[k] != before[k]:
			_snap_fail("D: non-schema offset %d (%s) moved %s -> %s — reconfigure touched live state" % [
				field, k, str(before[k]), str(after[k])])
			return

	# Non-vacuity: the change has to have DONE something on each of the three axes.
	if after["pa"] == before["pa"]:
		_snap_fail("D: pa did not move — the recompute arm is vacuous")
		return
	if after["hp"] != live_hp - 1 or after["hp"] >= live_hp:
		_snap_fail("D: hp %d -> %d against a ceiling of %d — the clamp arm is vacuous" % [
			live_hp, after["hp"], live_hp - 1])
		return
	if after["pos_x"] != before["pos_x"]:
		_snap_fail("D: pos_x followed the config — carry is not carrying")
		return
	print("[arm D] job change OK — recompute moved (pa %d->%d), clamp bit (hp %d->%d under max %d), carry held (pos_x %d)" % [
		before["pa"], after["pa"], live_hp, after["hp"], after["max_hp"], after["pos_x"]])


func _pick_living_unit() -> int:
	var best := -1
	var best_hp := 1
	var states: Array = gpu_simulator.get_battle_unit_states(0)
	for i in range(states.size()):
		var hp: int = states[i]["hp"]
		if hp > best_hp:
			best_hp = hp
			best = i
	return best


func _states_identical(a: Array, b: Array) -> bool:
	for u in range(a.size()):
		for key in a[u]:
			if a[u][key] != b[u].get(key):
				return false
	return true


func _slices_equal(arm: String, name: String, expected: PackedInt32Array, got: PackedInt32Array) -> bool:
	if expected.size() != got.size():
		_snap_fail("%s: slice '%s' size %d != %d" % [arm, name, got.size(), expected.size()])
		return false
	for i in range(expected.size()):
		if expected[i] != got[i]:
			_snap_fail("%s: slice '%s' index %d: expected %d, got %d" % [arm, name, i, expected[i], got[i]])
			return false
	return true


func _snap_fail(reason: String) -> void:
	if not _snap_failed:
		_snap_failed = true
		_snap_reason = reason
	print("[fail] %s" % reason)


func _finish() -> void:
	print("\n--- Battle Snapshot / Reconfigure Test Complete ---")
	if _snap_failed:
		print("\n[FAIL] %s" % _snap_reason)
	else:
		print("\n[PASS] snapshot/restore is bit-identical over %d ticks (odd, so the ping-pong half flips) and reconfigure is a no-op for an unchanged config" % DIVERGE_TICKS)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if _snap_failed else 0)
