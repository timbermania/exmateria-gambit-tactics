class_name UIDisplayDebugPanel
extends BaseDebugPanel
## UI-side PAR scrub. Parallel to the world PAR in DisplayDebugPanel (clip-X stretch in
## world shaders) but independent: this drives PSXDisplay.live_ui_par, which UIChar /
## UIText / UIPortrait / UIFrame read for mesh-width math and rebuild on the
## live_ui_par_changed signal (ADR-0036). The row is a shared TuneField bound to the
## `render.ui_pixel_aspect` slug (ADR-0068 move 2): PSXDisplay OWNS it (facade over Tune, like
## pixel_aspect), so this panel is just a VIEW (decision 12) — an override applies at boot.

const TuneField = preload("res://src/debug/TuneField.gd")


func setup() -> void:
	panel_title = "UI Display"
	panel_category = Category.DISPLAY
	_build_ui()


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(200, 0)
	add_child(main_vbox)

	# Pure VIEW (ADR-0068 decision 12): slug only — PSXDisplay owns the default (project.godot
	# facade) + hint, bound with meta in its register_tunables(); read back from the registry.
	TuneField.add(main_vbox, "PSX UI PAR (mesh-width)", "render.ui_pixel_aspect")
