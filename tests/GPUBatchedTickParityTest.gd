extends "res://tests/GPUSeedReproTest.gd"

## GPU Batched-Tick Parity Test (Phase 2a correctness guard)
##
## The batched multi-tick-per-submit path (GPUBatchSimulator._run_ticks_batched,
## used by step_tick(k) for k>1) MUST be byte-identical to running the same k
## ticks one submit at a time (step_tick(1) k times). It amortizes the per-tick
## submit()/sync() fence over the batch — it must not change a single sim bit.
##
## This runs the deterministic seed-locked 4v4 from GPUSeedReproTest twice per
## batch size K: once as a reference (single ticks, full state snapshot every
## tick), once batched (step_tick(K)), comparing EVERY snapshot field of EVERY
## unit at each batch boundary. Any divergence fails with the exact
## (K, tick, unit, field, expected, got).
##
## Run headful (never --headless):
##   godot --path . tests/GPUBatchedTickParityTest.tscn


const PARITY_TICKS = 420           # divisible by every K below; enough for attacks/evasion
const BATCH_SIZES = [1, 2, 7, 30, 60]


func get_test_name() -> String:
	return "GPU Batched-Tick Parity Test"


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
		_fail("Map has no lattice")
		_finish_parity()
		return

	_setup_distance_field()
	_setup_gpu_simulator()
	await _create_units()

	if not gpu_simulator:
		_fail("GPU simulator not available")
		_finish_parity()
		return

	# Reference: single-tick, snapshot every tick.
	var reference := _run_single_reference()
	print("[parity] reference captured: %d single-tick snapshots" % reference.size())

	# Each batch size must reproduce the reference exactly at its boundaries.
	for k in BATCH_SIZES:
		_compare_batched_to_reference(k, reference)
		if _failed:
			break

	_finish_parity()


func _process(_delta):
	pass


## Configure the seed-locked battle from scratch (resets both ping-pong buffers).
func _configure_parity_battle() -> void:
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
	for i in range(team0_units.size()):
		gpu_simulator.set_unit_gambits(0, i, get_gambits_for_unit(i, 0))
	for i in range(team1_units.size()):
		gpu_simulator.set_unit_gambits(0, team0_units.size() + i, get_gambits_for_unit(team0_units.size() + i, 1))
	gpu_state_reader.initialize(gpu_simulator, 0)


## Single-tick run; returns full unit-state snapshots indexed by (tick-1).
func _run_single_reference() -> Array:
	_configure_parity_battle()
	var snaps: Array = []
	for _t in range(PARITY_TICKS):
		gpu_simulator.step_tick(1)
		snaps.append(gpu_state_reader.get_all_unit_states())
	return snaps


## Run the same seed in batches of K, comparing to `reference` at each boundary.
func _compare_batched_to_reference(k: int, reference: Array) -> void:
	_configure_parity_battle()
	var ticks_done := 0
	var boundaries := 0
	while ticks_done < PARITY_TICKS:
		var this_batch: int = mini(k, PARITY_TICKS - ticks_done)
		gpu_simulator.step_tick(this_batch)
		ticks_done += this_batch
		boundaries += 1
		var got: Array = gpu_state_reader.get_all_unit_states()
		var expected: Array = reference[ticks_done - 1]
		if not _states_equal(k, ticks_done, expected, got):
			return  # _states_equal already recorded the failure
	print("[parity] K=%-3d OK  (%d ticks in %d submits, byte-identical to single-tick)" % [
		k, ticks_done, boundaries])


## Deep field-by-field equality of two full unit-state arrays. Fails on the first
## mismatch with the exact locus.
func _states_equal(k: int, tick: int, expected: Array, got: Array) -> bool:
	if expected.size() != got.size():
		_fail("K=%d tick=%d: unit count %d != %d" % [k, tick, got.size(), expected.size()])
		return false
	for u in range(expected.size()):
		var ea: Dictionary = expected[u]
		var ga: Dictionary = got[u]
		for key in ea:
			if ea[key] != ga.get(key):
				_fail("K=%d tick=%d unit=%d field=%s: batched=%s single=%s" % [
					k, tick, u, key, str(ga.get(key)), str(ea[key])])
				return false
	return true


func _finish_parity() -> void:
	print("\n--- Batched-Tick Parity Test Complete ---")
	if _failed:
		print("\n[FAIL] %s" % _fail_reason)
	else:
		print("\n[PASS] Batched step_tick(K) byte-identical to K single ticks for K in %s (%d ticks each)" % [
			str(BATCH_SIZES), PARITY_TICKS])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if _failed else 0)
