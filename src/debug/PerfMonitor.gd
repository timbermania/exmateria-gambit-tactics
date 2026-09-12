@tool
extends Node
## PerfMonitor - Per-frame performance sampler + spike detector.
##
## Autoload. Samples real frame time, CPU process time, draw calls, particle
## count, and combat_visuals group size every frame. Maintains a rolling
## SAMPLE_BUFFER_LEN history (drawn as a graph in PerfDebugPanel). Emits
## `spike_detected` when a frame's real frame_time_ms exceeds the configurable
## threshold (DebugConfig.perf_spike_threshold_ms).
##
## Owns the PerfHUD CanvasLayer child — a cheap always-on corner readout
## toggled by DebugConfig.perf_hud_enabled.
##
## Determinism note: combat decisions are deterministic by seed (see
## GPUArena.gd), but lazy-load spikes (texture load, shader compile) are
## session-state-dependent — they only fire on cold caches. Ctrl+R reloads the
## scene without restarting the process, so warm-cache replay reproduces
## steady-state perf but NOT first-load spikes.

const SAMPLE_BUFFER_LEN: int = 240  # 4s @ 60fps rolling history
const SPIKE_LOG_MAX: int = 256      # Cap to bound memory

const _PERF_HUD_SCRIPT = preload("res://src/debug/PerfHUD.gd")

## Per-frame sample. Index 0 is oldest, SAMPLE_BUFFER_LEN-1 is newest.
class Sample:
	var frame_time_ms: float = 0.0       # Real wall-clock frame time
	var process_time_ms: float = 0.0     # Performance.TIME_PROCESS
	var physics_time_ms: float = 0.0     # Performance.TIME_PHYSICS_PROCESS
	var draw_calls: int = 0
	var objects_in_frame: int = 0
	var node_count: int = 0
	var combat_visuals: int = 0
	var fps: float = 0.0

## A logged spike. Created when frame_time_ms > DebugConfig.perf_spike_threshold_ms.
class SpikeEntry:
	var tick: int = -1                   # CombatLoop tick at the time (-1 if unknown)
	var wall_time_s: float = 0.0         # Seconds since process start
	var frame_time_ms: float = 0.0
	var process_time_ms: float = 0.0
	var draw_calls: int = 0
	var combat_visuals: int = 0
	var node_count_delta: int = 0        # Change in node count this frame
	var note: String = ""                # Free-form label (first-load marker etc.)

signal spike_detected(entry: SpikeEntry)
signal sample_taken(sample: Sample)

var _samples: Array[Sample] = []
var _spike_log: Array[SpikeEntry] = []
var _last_tick_usec: int = 0
var _last_node_count: int = 0
var _hud: CanvasLayer = null

# Running aggregates over the whole session (not just the ring buffer)
var _total_frames: int = 0
var _frame_time_sum_ms: float = 0.0
var _frame_time_max_ms: float = 0.0
var _process_time_sum_ms: float = 0.0
var _physics_time_sum_ms: float = 0.0
## Session mean of `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`. Already sampled per
## frame; summing it makes the F3 overlay's cost FALSIFIABLE (W4). The dashboard is a
## second OS window (ADR-0035) and `renderer_viewport.cpp` draws any viewport attached to
## a screen every frame regardless of update mode, so opening it MUST raise this number.
## An open-vs-closed timing arm that does not move it was measuring a window that never
## rendered, and a blind instrument's zero reads exactly like an absent effect.
var _draw_calls_sum: float = 0.0

# Set externally by CombatLoop so spike entries can name the current tick.
# CombatLoop has no awareness of PerfMonitor; PerfMonitor pulls via group lookup
# instead. Cheap because there is at most one CombatLoop alive at a time.
var _combat_loop_cache: Node = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_samples.resize(SAMPLE_BUFFER_LEN)
	for i in range(SAMPLE_BUFFER_LEN):
		_samples[i] = Sample.new()

	_last_tick_usec = Time.get_ticks_usec()
	_last_node_count = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	_hud = _PERF_HUD_SCRIPT.new()
	add_child(_hud)
	_hud.visible = DebugConfig.perf_hud_enabled
	DebugConfig.perf_hud_toggled.connect(func(v: bool): _hud.visible = v)

	# Auto-summary on regression-test / CLI auto-quit so headless trials surface
	# their perf data without a panel to click.
	DebugConfig.quit_requested.connect(print_summary)

	# Run before _process of most game scripts so HUD sees this frame's data.
	process_priority = -100


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var now_usec: int = Time.get_ticks_usec()
	var real_frame_us: int = now_usec - _last_tick_usec
	_last_tick_usec = now_usec
	var frame_time_ms: float = float(real_frame_us) / 1000.0

	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs_in_frame: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var combat_visuals: int = _count_combat_visuals()
	var fps: float = Engine.get_frames_per_second()

	var s: Sample = _samples[SAMPLE_BUFFER_LEN - 1]
	# Ring-rotate: shift up, then overwrite the new tail. Cheap on a fixed-size array.
	for i in range(SAMPLE_BUFFER_LEN - 1):
		_samples[i] = _samples[i + 1]
	_samples[SAMPLE_BUFFER_LEN - 1] = Sample.new()
	s = _samples[SAMPLE_BUFFER_LEN - 1]
	s.frame_time_ms = frame_time_ms
	s.process_time_ms = process_ms
	s.physics_time_ms = physics_ms
	s.draw_calls = draw_calls
	s.objects_in_frame = objs_in_frame
	s.node_count = node_count
	s.combat_visuals = combat_visuals
	s.fps = fps

	_total_frames += 1
	_frame_time_sum_ms += frame_time_ms
	_draw_calls_sum += float(draw_calls)
	_process_time_sum_ms += process_ms
	_physics_time_sum_ms += physics_ms
	if frame_time_ms > _frame_time_max_ms:
		_frame_time_max_ms = frame_time_ms

	sample_taken.emit(s)

	if DebugConfig.perf_spike_log_enabled and frame_time_ms > DebugConfig.perf_spike_threshold_ms:
		var spike := SpikeEntry.new()
		spike.tick = _current_combat_tick()
		spike.wall_time_s = float(Time.get_ticks_msec()) / 1000.0
		spike.frame_time_ms = frame_time_ms
		spike.process_time_ms = process_ms
		spike.draw_calls = draw_calls
		spike.combat_visuals = combat_visuals
		spike.node_count_delta = node_count - _last_node_count
		_spike_log.append(spike)
		if _spike_log.size() > SPIKE_LOG_MAX:
			_spike_log.pop_front()
		spike_detected.emit(spike)

	_last_node_count = node_count


func get_samples() -> Array[Sample]:
	"""Return the rolling buffer. Index 0 = oldest, SAMPLE_BUFFER_LEN-1 = newest."""
	return _samples


func get_latest_sample() -> Sample:
	return _samples[SAMPLE_BUFFER_LEN - 1]


func get_spike_log() -> Array[SpikeEntry]:
	return _spike_log


func clear_spike_log() -> void:
	_spike_log.clear()


func print_summary() -> void:
	"""Dump session aggregates and top-10 spikes to stdout. Connected to
	DebugConfig.quit_requested so headless trials surface their perf data."""
	var seed_hint: int = DebugConfig.active_combat_seed
	print("")
	print("================ PerfMonitor session summary ================")
	print("seed=%d  frames=%d  spikes=%d  threshold=%.1fms" % [
		seed_hint, _total_frames, _spike_log.size(), DebugConfig.perf_spike_threshold_ms,
	])
	if _total_frames > 0:
		var mean_ft := _frame_time_sum_ms / float(_total_frames)
		var mean_cpu := _process_time_sum_ms / float(_total_frames)
		var mean_phy := _physics_time_sum_ms / float(_total_frames)
		print("frame_time: mean=%.2fms  max=%.2fms  est_fps_mean=%.1f" % [
			mean_ft, _frame_time_max_ms, 1000.0 / max(mean_ft, 0.001),
		])
		print("cpu_proc:   mean=%.2fms  phys:  mean=%.2fms  est_other_mean=%.2fms" % [
			mean_cpu, mean_phy, max(0.0, mean_ft - mean_cpu - mean_phy),
		])
		print("draw_calls: mean=%.1f" % (_draw_calls_sum / float(_total_frames)))
	# Top-10 spikes by frame_time
	var sorted := _spike_log.duplicate()
	sorted.sort_custom(func(a, b): return a.frame_time_ms > b.frame_time_ms)
	var n: int = min(10, sorted.size())
	if n > 0:
		print("--- top %d spikes ---" % n)
		for i in range(n):
			var e = sorted[i]
			print("  +%.2fs  tick=%d  ft=%.1fms  cpu=%.1f  draw=%d  vis=%d  nodes_d=%+d  %s" % [
				e.wall_time_s, e.tick, e.frame_time_ms, e.process_time_ms,
				e.draw_calls, e.combat_visuals, e.node_count_delta, e.note,
			])
	print("=============================================================")
	print("")


func _count_combat_visuals() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	return tree.get_nodes_in_group("combat_visuals").size()


func _current_combat_tick() -> int:
	"""Best-effort lookup of the active CombatLoop's tick. Returns -1 if none."""
	var tree := get_tree()
	if tree == null:
		return -1
	# CombatLoop is a Node, not in a known group. Cache the first one we find;
	# nil out if it has gone away.
	if _combat_loop_cache != null and not is_instance_valid(_combat_loop_cache):
		_combat_loop_cache = null
	if _combat_loop_cache == null:
		var root := tree.current_scene
		if root != null:
			_combat_loop_cache = _find_combat_loop(root)
	if _combat_loop_cache == null:
		return -1
	return int(_combat_loop_cache.get("current_tick"))


func _find_combat_loop(node: Node) -> Node:
	if node.get_script() != null:
		var path: String = node.get_script().resource_path
		if path.ends_with("CombatLoop.gd") or path.ends_with("CombatHost.gd"):
			# Prefer the loop's own current_tick, but the host forwards it, so
			# either works.
			if "current_tick" in node:
				return node
	for child in node.get_children():
		var found := _find_combat_loop(child)
		if found != null:
			return found
	return null
