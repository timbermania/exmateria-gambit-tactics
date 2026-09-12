@tool
extends CanvasLayer
## PerfHUD - Cheap top-right corner readout. Child of PerfMonitor.
##
## Renders one Label with the latest Sample's headline stats. Update is driven
## by PerfMonitor.sample_taken so the HUD always lags the buffer by 0 frames
## but costs only a string format + Label.text assignment.
##
## Toggled via DebugConfig.perf_hud_enabled.

const _UPDATE_EVERY_N_FRAMES: int = 5  # 12Hz at 60fps — fast enough, cheap

var _label: Label
var _frame_counter: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	layer = 100  # Above gameplay, below the debug dashboard (separate window)

	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	panel.add_child(_label)

	# Defer connection until parent is in tree.
	call_deferred("_connect_to_monitor")


func _connect_to_monitor() -> void:
	var parent := get_parent()
	if parent and parent.has_signal("sample_taken"):
		parent.sample_taken.connect(_on_sample)


func _on_sample(sample) -> void:
	if not visible:
		return
	_frame_counter += 1
	if _frame_counter < _UPDATE_EVERY_N_FRAMES:
		return
	_frame_counter = 0
	_label.text = "FPS %d  ft %.1fms\nCPU %.1f  phy %.1f  est-other %.1f\ndraw %d  obj %d  vis %d" % [
		int(sample.fps),
		sample.frame_time_ms,
		sample.process_time_ms,
		sample.physics_time_ms,
		max(0.0, sample.frame_time_ms - sample.process_time_ms - sample.physics_time_ms),
		sample.draw_calls,
		sample.objects_in_frame,
		sample.combat_visuals,
	]
