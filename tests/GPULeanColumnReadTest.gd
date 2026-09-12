extends "res://tests/GPUSeedReproTest.gd"
# test-kind: gpu
# seeded-break: read_unit_column's intra-unit index in GPUBatchSimulator.gd read one int past the field (field_offset + 1) - arm 1 REDed with 8292 lean-read mismatches (lean columns no longer equal the full snapshot; e.g. evade_type lean=13050 full=0) while arm 2's hot-snapshot arm stayed fully green; GREEN unbroken on the reverted tree

## GPU lean-column read contract guard.
##
## The combat loop's per-tick reads go through GPUStateReader.get_unit_column /
## GPUBatchSimulator.read_unit_column — a lean int column pulled off the
## version-cached region WITHOUT building the full 101-field per-unit Dictionary
## (perf: it was ~0.6ms/tick of dict construction). This asserts the lean column
## returns EXACTLY the same values as the corresponding field of the full
## get_all_unit_states() snapshot, across many ticks, for the fields the loop
## actually reads per tick (HP / EVADE_TYPE / CINEMATIC_TIMER / PAUSED) plus a
## couple of others. If the intra-unit offset mapping ever drifts, this fails
## loudly here instead of silently corrupting damage/cinematic detection.
##
## Arm 2 (W1) does the same for the LEAN PER-FRAME SNAPSHOT,
## GPUBatchSimulator.get_battle_unit_states_hot(): 31 of the 101 fields, built by
## walking parallel HOT_UNION_KEYS / HOT_UNION_OFFSETS arrays instead of hashing
## each key into SNAPSHOT_FIELDS. That is a SECOND, independent offset-resolution
## path over the same bytes, so it can drift on its own — this asserts the lean
## snapshot carries exactly the union's keys and the same values the full
## snapshot has for each of them.
##
## Neither arm can tell you the union is COMPLETE — that every field a per-frame
## consumer reads is in it. That is tools/check_snapshot_union.py (static) and
## tests/GPUSnapshotUnionTest.tscn (a poisoned battle).
##
## Run headful (never --headless):
##   godot --path . tests/GPULeanColumnReadTest.tscn


const CHECK_TICKS = 200
const WARMUP = 20

# Fields the per-tick loop reads through the lean path, plus a couple of extras
# to exercise the generic accessor across the record.
const CHECK_FIELDS = ["hp", "evade_type", "cinematic_timer", "paused", "state", "pos_x"]


func get_test_name() -> String:
	return "GPU Lean Column Read Test"


func _ready():
	max_ticks = 999999
	auto_start = false
	regression_logging = false
	_rlog = RegressionLogger.new(get_test_name(), false)

	print("\n=== %s ===" % get_test_name())

	await get_tree().process_frame
	await get_tree().process_frame

	# ADR-0192 dec. 3's clean fetch — one untyped step at the seam, into a LOCAL
	# annotated here (the field is inherited from `CombatHost`, and the register's
	# receiver inference is per file), then stored.
	var lat: Lattice = map.lattice
	lattice = lat
	if not lattice:
		print("[FAIL] Map has no lattice")
		get_tree().quit(1)
		return

	_setup_distance_field()
	_setup_gpu_simulator()
	await _create_units()

	if not gpu_simulator:
		print("[FAIL] GPU simulator not available")
		get_tree().quit(1)
		return

	_configure_battle(TEST_SEED)
	for _i in range(WARMUP):
		gpu_simulator.step_tick(1)

	var offsets := {}
	for f in CHECK_FIELDS:
		offsets[f] = GPUBatchSimulator.SNAPSHOT_FIELDS[f]

	var union_keys: Array = GPUCombatPacker.SNAPSHOT_HOT_UNION
	var mismatches := 0
	var checks := 0
	var snap_checks := 0
	for _t in range(CHECK_TICKS):
		gpu_simulator.step_tick(1)
		var full: Array = gpu_state_reader.get_all_unit_states()

		# --- Arm 2 (W1): the lean per-frame SNAPSHOT vs the full one ----------
		var hot: Array = gpu_state_reader.get_all_unit_states_hot()
		if hot.size() != full.size():
			mismatches += 1
			print("[FAIL] hot snapshot size %d != full snapshot size %d" % [hot.size(), full.size()])
			break
		for i in range(full.size()):
			# Exactly the union — no more (that is the point) and no less (a
			# missing key is a silent `.get()` default at every consumer).
			if hot[i].size() != union_keys.size():
				mismatches += 1
				print("[FAIL] tick=%d unit=%d hot snapshot has %d keys, union has %d" % [
					_t, i, hot[i].size(), union_keys.size()])
				break
			for key in union_keys:
				snap_checks += 1
				if not hot[i].has(key):
					mismatches += 1
					print("[FAIL] tick=%d unit=%d hot snapshot missing union key '%s'" % [_t, i, key])
				elif int(hot[i][key]) != int(full[i][key]):
					mismatches += 1
					print("[FAIL] tick=%d unit=%d field=%s hot=%d full=%d" % [
						_t, i, key, int(hot[i][key]), int(full[i][key])])

		# --- Arm 1: the lean per-tick COLUMNS vs the full snapshot ------------
		for f in CHECK_FIELDS:
			var col: PackedInt32Array = gpu_state_reader.get_unit_column(offsets[f])
			if col.size() != full.size():
				mismatches += 1
				print("[FAIL] column '%s' size %d != snapshot size %d" % [f, col.size(), full.size()])
				break
			for i in range(full.size()):
				checks += 1
				if col[i] != int(full[i][f]):
					mismatches += 1
					print("[FAIL] tick=%d unit=%d field=%s lean=%d full=%d" % [
						_t, i, f, col[i], int(full[i][f])])

	if mismatches == 0:
		print("[PASS] lean columns byte-identical to full snapshot (%d comparisons over %d ticks x %d fields)" % [
			checks, CHECK_TICKS, CHECK_FIELDS.size()])
		print("[PASS] lean SNAPSHOT carries exactly the %d union keys, values byte-identical to the full snapshot (%d comparisons over %d ticks)" % [
			union_keys.size(), snap_checks, CHECK_TICKS])
		get_tree().quit(0)
	else:
		print("[FAIL] %d lean-read mismatches" % mismatches)
		get_tree().quit(1)


func _configure_battle(battle_seed: int) -> void:
	"""Mirror GPUSeedReproTest._run_combat's setup (without the snapshot loop) —
	same helper GPUPerfBenchmark uses to stand up a deterministic 4v4."""
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

	gpu_simulator.set_battle_units(0, gpu_team0, gpu_team1, battle_seed)

	for i in range(team0_units.size()):
		gpu_simulator.set_unit_gambits(0, i, get_gambits_for_unit(i, 0))
	for i in range(team1_units.size()):
		gpu_simulator.set_unit_gambits(0, team0_units.size() + i, get_gambits_for_unit(team0_units.size() + i, 1))

	gpu_state_reader.initialize(gpu_simulator, 0)
