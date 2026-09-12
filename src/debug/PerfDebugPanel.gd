class_name PerfDebugPanel
extends BaseDebugPanel
## PerfDebugPanel - F3 tab for the performance monitor.
##
## Three sections:
##  - Controls: toggle HUD, toggle spike log, threshold spinbox, clear-log
##  - Rolling frame-time graph (last SAMPLE_BUFFER_LEN frames)
##  - Spike log table (most recent spikes)
##
## Reads from the PerfMonitor autoload; never owns sampling state.

const _PERF_GRAPH_SIZE := Vector2(480, 96)
const _GREEN_60FPS_MS := 1000.0 / 60.0
const _YELLOW_30FPS_MS := 1000.0 / 30.0

const TuneField = preload("res://src/debug/TuneField.gd")

## The live readout and the 240-sample graph refresh at ~10 Hz, not at frame rate
## (W4). Together they are ~46 % of what the F3 overlay costs while OPEN, and the goal
## is a fast game with it up — "close it" is not the fix. A frame-time graph and a text
## readout are read by a human eye; ten updates a second is fully legible and costs about
## a fourteenth of 144.
##
## Accumulated from the SAMPLE's own frame time rather than read off the clock, so the
## rate is a function of frames observed and a test can drive it deterministically —
## counted work, not wall clock (W8's standing ruling).
const LIVE_UPDATE_INTERVAL_MS: float = 100.0

var _live_label: Label
var _graph: Control
var _spike_list: ItemList
var _since_update_ms: float = 0.0


func setup() -> void:
	panel_title = "Performance"
	panel_category = Category.PERFORMANCE
	_build_ui()

	if PerfMonitor:
		PerfMonitor.sample_taken.connect(_on_sample)
		PerfMonitor.spike_detected.connect(_on_spike)


func _build_ui() -> void:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	add_child(container)

	add_section_title(container, "Performance Monitor")
	add_separator(container)

	# --- Controls. TuneField rows bound to the flags' Tune slugs (ADR-0068): blue
	# accent labels, Pin/Reset, and synced with the same slug anywhere else.
	var controls := create_collapsible_section(container, "Controls")
	TuneField.add(controls, "Show corner HUD", "debug.perf_hud_enabled", false)
	TuneField.add(controls, "Log spikes", "debug.perf_spike_log_enabled", true)
	TuneField.add(controls, "Spike threshold (ms)", "debug.perf_spike_threshold_ms", 33.0,
		{"min": 5.0, "max": 500.0, "step": 1.0})

	add_separator(container)

	# --- Live readout
	var live := create_collapsible_section(container, "Live")
	_live_label = Label.new()
	_live_label.add_theme_font_size_override("font_size", 11)
	_live_label.text = "FPS …"
	live.add_child(_live_label)

	add_separator(container)

	# --- Rolling graph
	var graph_section := create_collapsible_section(container, "Frame time (last 4s)")
	_graph = Control.new()
	_graph.custom_minimum_size = _PERF_GRAPH_SIZE
	_graph.draw.connect(_draw_graph)
	graph_section.add_child(_graph)

	add_separator(container)

	# --- Spike log
	var log_section := create_collapsible_section(container, "Spike log")
	var log_row := HBoxContainer.new()
	log_section.add_child(log_row)
	var clear_btn := Button.new()
	clear_btn.text = "Clear log"
	clear_btn.pressed.connect(_on_clear_log)
	log_row.add_child(clear_btn)
	var print_btn := Button.new()
	print_btn.text = "Print to console"
	print_btn.pressed.connect(_on_print_log)
	log_row.add_child(print_btn)

	_spike_list = ItemList.new()
	_spike_list.custom_minimum_size = Vector2(480, 200)
	_spike_list.add_theme_font_size_override("font_size", 10)
	log_section.add_child(_spike_list)


func _on_sample(sample) -> void:
	# PerfMonitor samples every frame whether or not anyone is looking. The
	# dashboard is a separate OS window (ADR-0035), so an unwatched panel used to
	# keep formatting a nine-field string and re-drawing a 240-sample polyline
	# behind a hidden window or a folded-shut category cell. Measured on the arena
	# fixture, that graph redraw alone is ~8 % of the frame (#866). Do neither
	# unless the control is actually on screen.
	if not DebugConfig.debug_overlay_visible:
		return
	# Both the format and the redraw sit behind ONE gate: they are the same readout at
	# two fidelities, and a throttle that let either through at frame rate would leave
	# most of the cost in place.
	_since_update_ms += sample.frame_time_ms
	if _since_update_ms < LIVE_UPDATE_INTERVAL_MS:
		return
	_since_update_ms = 0.0
	if _live_label and _live_label.is_visible_in_tree():
		_update_live_label(sample)
	if _graph and _graph.is_visible_in_tree():
		_graph.queue_redraw()


func _update_live_label(sample) -> void:
	_live_label.text = "FPS %d  ft %.1fms  cpu %.1f  phy %.1f  other %.1f\ndraw %d  obj %d  nodes %d  visuals %d" % [
		int(sample.fps),
		sample.frame_time_ms,
		sample.process_time_ms,
		sample.physics_time_ms,
		max(0.0, sample.frame_time_ms - sample.process_time_ms - sample.physics_time_ms),
		sample.draw_calls,
		sample.objects_in_frame,
		sample.node_count,
		sample.combat_visuals,
	]


func _on_spike(entry) -> void:
	var line := "+%.2fs  tick=%d  ft=%.1fms  cpu=%.1f  draw=%d  vis=%d  nodes_d=%+d  %s" % [
		entry.wall_time_s, entry.tick, entry.frame_time_ms, entry.process_time_ms,
		entry.draw_calls, entry.combat_visuals, entry.node_count_delta,
		entry.note,
	]
	_spike_list.add_item(line)
	if _spike_list.item_count > 0:
		_spike_list.ensure_current_is_visible()
		_spike_list.select(_spike_list.item_count - 1)


func _on_clear_log() -> void:
	if PerfMonitor:
		PerfMonitor.clear_spike_log()
	_spike_list.clear()


func _on_print_log() -> void:
	if PerfMonitor == null:
		return
	var log := PerfMonitor.get_spike_log()
	print("")
	print("=".repeat(60))
	print("# Performance spike log (%d entries)" % log.size())
	print("=".repeat(60))
	for entry in log:
		print("+%.2fs  tick=%d  ft=%.1fms  cpu=%.1f  draw=%d  vis=%d  nodes_d=%+d  %s" % [
			entry.wall_time_s, entry.tick, entry.frame_time_ms, entry.process_time_ms,
			entry.draw_calls, entry.combat_visuals, entry.node_count_delta,
			entry.note,
		])
	print("=".repeat(60))


func _draw_graph() -> void:
	if PerfMonitor == null:
		return
	var samples = PerfMonitor.get_samples()
	if samples.is_empty():
		return

	var w: float = _PERF_GRAPH_SIZE.x
	var h: float = _PERF_GRAPH_SIZE.y
	# Y-scale: floor 50ms, but stretch if we have a spike higher than that.
	var max_ms: float = 50.0
	for s in samples:
		if s.frame_time_ms > max_ms:
			max_ms = s.frame_time_ms
	max_ms = min(max_ms, 200.0)  # Cap so one huge spike doesn't squash the graph

	# Background
	_graph.draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.08, 0.10, 1.0), true)

	# Reference lines: 16.67ms (60fps, green), 33.33ms (30fps, yellow),
	# threshold (red).
	_draw_h_line(_GREEN_60FPS_MS, max_ms, w, h, Color(0.2, 0.7, 0.2, 0.6))
	_draw_h_line(_YELLOW_30FPS_MS, max_ms, w, h, Color(0.8, 0.7, 0.2, 0.6))
	_draw_h_line(DebugConfig.perf_spike_threshold_ms, max_ms, w, h, Color(0.9, 0.2, 0.2, 0.6))

	# Polyline of frame times
	var n: int = samples.size()
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(n)
	for i in range(n):
		var x: float = (float(i) / float(n - 1)) * w
		var y: float = h - (samples[i].frame_time_ms / max_ms) * h
		pts[i] = Vector2(x, clamp(y, 0.0, h))
	if pts.size() >= 2:
		_graph.draw_polyline(pts, Color(0.4, 0.85, 1.0, 1.0), 1.0, true)

	# Tiny y-axis labels
	var font := _graph.get_theme_default_font()
	var fsize := 9
	_graph.draw_string(font, Vector2(2, 10), "%d ms" % int(max_ms), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, 0.7))
	_graph.draw_string(font, Vector2(2, h - 2), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, 0.7))


func _draw_h_line(ms: float, max_ms: float, w: float, h: float, color: Color) -> void:
	if ms > max_ms:
		return
	var y: float = h - (ms / max_ms) * h
	_graph.draw_line(Vector2(0, y), Vector2(w, y), color, 1.0)


