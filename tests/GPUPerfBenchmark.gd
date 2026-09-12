extends "res://tests/GPUSeedReproTest.gd"

## GPU Arena Performance Benchmark  (diagnosing-bugs Phase 1 feedback loop)
##
## Reuses GPUSeedReproTest's deterministic, seed-locked 4v4 setup, but instead
## of asserting reproducibility it TIMES each `step_tick(1)` and reports robust
## per-tick statistics + a spike log. This is the fixed, red-capable perf
## benchmark: the number to beat is the tick-time distribution (median / p99 /
## max). A fix that removes stall shifts those down; a regression shifts them up.
##
## Wall-clock per tick IS the user's symptom: `_run_pass()` does submit()+sync()
## per pass, so the CPU blocks on the GPU every pass — per-tick wall time is the
## real stall the frame budget pays.
##
## Run headful (never --headless):
##   godot --path . tests/GPUPerfBenchmark.tscn
##
## Emits a machine-readable line `PERF_RESULT ...` and writes a per-tick CSV to
## res://tests/logs/ for before/after diffing.


const WARMUP_TICKS = 40      # discarded — first ticks pay one-time GPU warmup
const BENCH_TICKS = 800      # measured window (matches SeedRepro tick count)
const SPIKE_FACTOR = 2.0     # a tick > SPIKE_FACTOR * median counts as a spike

var _tick_usec: PackedFloat64Array = PackedFloat64Array()


func get_test_name() -> String:
	return "GPU Perf Benchmark"


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

	print("[bench] warmup %d ticks..." % WARMUP_TICKS)
	for _i in range(WARMUP_TICKS):
		gpu_simulator.step_tick(1)

	print("[bench] measuring %d ticks..." % BENCH_TICKS)
	_tick_usec.resize(BENCH_TICKS)
	for tick in range(BENCH_TICKS):
		var t0 := Time.get_ticks_usec()
		gpu_simulator.step_tick(1)
		_tick_usec[tick] = float(Time.get_ticks_usec() - t0)

	_report()
	_bench_batched()
	_bench_readback()
	_finish_bench()


## The hidden per-tick cost the tick-timing above never captures: production
## `CombatLoop.tick` does 2-3 `buffer_get_data` readbacks per tick
## (_read_tick_columns twice, then _check_state_changes + visual re-read the
## SAME unchanged buffer). Each buffer_get_data is a blocking full device sync.
## This times a bare get_all_unit_states() repeated with NO step_tick between —
## i.e. the cost of re-reading an unchanged buffer. With readback caching in place
## these collapse to ~0 (cache hits); without it each pays a full fence.
func _bench_readback() -> void:
	print("\n--- Readback cost: get_all_unit_states() with no step between ---")
	_configure_battle(TEST_SEED)
	for _i in range(WARMUP_TICKS):
		gpu_simulator.step_tick(1)
	var n := 400
	var t0 := Time.get_ticks_usec()
	for _i in range(n):
		gpu_state_reader.get_all_unit_states()
	var per_call: float = float(Time.get_ticks_usec() - t0) / n
	# And the realistic pattern: one step then the 3 re-reads a frame does.
	var t1 := Time.get_ticks_usec()
	var frames := 200
	for _f in range(frames):
		gpu_simulator.step_tick(1)
		gpu_state_reader.get_all_unit_states()   # _read_tick_columns
		gpu_state_reader.get_battle_state()      # _read_tick_columns
		gpu_state_reader.get_all_unit_states()   # _check_state_changes
		gpu_state_reader.get_all_unit_states()   # visual
	var per_frame: float = float(Time.get_ticks_usec() - t1) / frames

	# Per-TICK read overhead (the real win — this is what runs once PER TICK, and a
	# frame can be many ticks). OLD: the per-tick _read_tick_columns rebuilt the
	# full 99-field snapshot (get_all_unit_states, uncached because step bumps the
	# version) + get_battle_state, every tick. NEW: it reads 4 lean columns off the
	# version-cached region — no dict build. Time each ON TOP of a step, then
	# subtract the step so we isolate the read overhead the loop pays per tick.
	var f_hp: int = GPUBatchSimulator.SNAPSHOT_FIELDS["hp"]
	var f_evade: int = GPUBatchSimulator.SNAPSHOT_FIELDS["evade_type"]
	var f_cin: int = GPUBatchSimulator.SNAPSHOT_FIELDS["cinematic_timer"]
	var f_paused: int = GPUBatchSimulator.SNAPSHOT_FIELDS["paused"]
	var f_state: int = GPUBatchSimulator.SNAPSHOT_FIELDS["state"]
	var ticks := 400
	var old_reads := 0.0
	var new_reads := 0.0
	for _t in range(ticks):
		gpu_simulator.step_tick(1)
		var a := Time.get_ticks_usec()
		gpu_state_reader.get_all_unit_states()    # OLD _read_tick_columns
		gpu_state_reader.get_battle_state()       # OLD _read_tick_columns
		old_reads += float(Time.get_ticks_usec() - a)
	for _t in range(ticks):
		gpu_simulator.step_tick(1)
		var a := Time.get_ticks_usec()
		gpu_state_reader.get_unit_column(f_hp)         # NEW _read_tick_columns
		gpu_state_reader.get_unit_column(f_evade)      # NEW _read_tick_columns
		gpu_state_reader.get_unit_column(f_cin)        # NEW cinematic edge
		gpu_state_reader.get_unit_column(f_paused)     # NEW anim freeze
		gpu_state_reader.get_unit_column(f_state)      # NEW lean state edge
		new_reads += float(Time.get_ticks_usec() - a)
	var old_tick_us: float = old_reads / ticks
	var new_tick_us: float = new_reads / ticks

	print("  repeated read (no step):      %.1f us/call" % per_call)
	print("  step + 3 full re-reads/frame: %.1f us/frame" % per_frame)
	print("  OLD per-tick read overhead:   %.1f us/tick (full snapshot rebuild)" % old_tick_us)
	print("  NEW per-tick read overhead:   %.1f us/tick (4 lean columns)" % new_tick_us)
	print("PERF_READBACK per_call_us=%.1f per_frame_us=%.1f old_tick_us=%.1f new_tick_us=%.1f" % [
		per_call, per_frame, old_tick_us, new_tick_us])


## Phase 2a: batched multi-tick-per-submit. step_tick(K) runs K ticks in one
## compute list with a single submit()/sync(), amortizing the per-tick fence (the
## dominant cost — see _report above) over K ticks. Measures amortized us/tick for
## several K against the single-tick baseline. Each K re-runs the same seed-locked
## workload after a fresh warmup so the comparison is apples-to-apples.
func _bench_batched() -> void:
	print("\n--- Batched multi-tick-per-submit (Phase 2a) ---")
	var batch_sizes: Array[int] = [1, 2, 8, 30, 60]
	for k in batch_sizes:
		_configure_battle(TEST_SEED)
		for _i in range(WARMUP_TICKS):
			gpu_simulator.step_tick(1)
		var batches: int = BENCH_TICKS / k
		var total_us: float = 0.0
		for _b in range(batches):
			var t0 := Time.get_ticks_usec()
			gpu_simulator.step_tick(k)
			total_us += float(Time.get_ticks_usec() - t0)
		var ticks_done: int = batches * k
		var per_tick: float = total_us / ticks_done
		print("  K=%-3d : %6.1f us/tick amortized  (%d ticks / %d submits, %.2f ms)" % [
			k, per_tick, ticks_done, batches, total_us / 1000.0])
		print("PERF_BATCHED k=%d per_tick_us=%.1f submits=%d ticks=%d" % [
			k, per_tick, batches, ticks_done])


func _configure_battle(battle_seed: int) -> void:
	"""Mirror GPUSeedReproTest._run_combat's setup (without the snapshot loop)."""
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


func _report() -> void:
	var sorted := _tick_usec.duplicate()
	sorted.sort()
	var n := sorted.size()

	var total := 0.0
	for v in _tick_usec:
		total += v
	var mean := total / n
	var median := sorted[n / 2]
	var p95 := sorted[int(n * 0.95)]
	var p99 := sorted[int(n * 0.99)]
	var tmax := sorted[n - 1]
	var tmin := sorted[0]

	# Spike count + first few spike ticks (in submission order, not sorted).
	var spike_threshold := median * SPIKE_FACTOR
	var spike_count := 0
	var first_spikes: Array = []
	for tick in range(n):
		if _tick_usec[tick] > spike_threshold:
			spike_count += 1
			if first_spikes.size() < 10:
				first_spikes.append("t%d=%.0fus" % [tick, _tick_usec[tick]])

	print("\n--- Perf Benchmark Report (%d ticks, %d passes/tick) ---" % [n, 8])
	print("  total:  %.2f ms" % (total / 1000.0))
	print("  mean:   %.1f us/tick" % mean)
	print("  median: %.1f us/tick" % median)
	print("  p95:    %.1f us/tick" % p95)
	print("  p99:    %.1f us/tick" % p99)
	print("  min:    %.1f us/tick" % tmin)
	print("  max:    %.1f us/tick" % tmax)
	print("  spikes (> %.1fx median = %.0fus): %d" % [SPIKE_FACTOR, spike_threshold, spike_count])
	if not first_spikes.is_empty():
		print("  first spikes: %s" % ", ".join(first_spikes))

	# Machine-readable one-liner for scripted before/after diffing.
	print("PERF_RESULT mean_us=%.1f median_us=%.1f p95_us=%.1f p99_us=%.1f max_us=%.1f spikes=%d total_ms=%.2f" % [
		mean, median, p95, p99, tmax, spike_count, total / 1000.0])

	_write_csv()


func _write_csv() -> void:
	var dir_abs := ProjectSettings.globalize_path("res://tests/logs/")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var path := dir_abs.path_join("perf_benchmark.csv")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("[bench] could not open CSV at %s" % path)
		return
	f.store_line("tick,usec")
	for tick in range(_tick_usec.size()):
		f.store_line("%d,%.1f" % [tick, _tick_usec[tick]])
	f.close()
	print("[bench] per-tick CSV written to %s" % path)


func _finish_bench() -> void:
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
