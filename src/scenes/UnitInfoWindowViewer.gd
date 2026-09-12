extends Node3D

## Viewer for the field-inspect info window (#91) in isolation — NOT a test (it
## asserts nothing; see tests/UnitInfoPresenterTest.gd + FieldInspectControllerTest
## for the assertions). Places UIUnitInfoWindow in front of an ortho camera (ui3
## settings) with sample data so the layout can be eyeballed/tuned. Stays open —
## close the window to exit. Press S to save a PNG.

const UIUnitInfoWindow = preload("res://src/ui3/UIUnitInfoWindow.gd")


func _ready() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 14.0
	cam.position = Vector3(0, 0, 10)
	add_child(cam)

	var win: UIUnitInfoWindow = UIUnitInfoWindow.new()
	add_child(win)
	win.position = Vector3(-3.6, 1.9, 0)
	win.set_unit_view({
		"name": "Ramza", "job": "Squire", "level": 5, "exp": 42,
		"current_hp": 333, "max_hp": 999,
		"current_mp": 480, "max_mp": 799,
		"ct": 80, "brave": 70, "faith": 55,
		"sprite_id": 0x01,
		"statuses": ["Haste", "Protect"],
	})

	# Live position-tuning panel (F3 → Designer tab). The window is always
	# visible here, so no preview/field-inspect wiring is needed.
	var panel := VitalsLayoutDebugPanel.new()
	panel.setup(win)
	DebugOverlay.register_panel(panel, DebugOverlay.Category.DESIGNER)


var _auto_frame := 0


func _process(_dt: float) -> void:
	# Auto-capture for headful verification (run with `-- --autoshot`).
	if "--autoshot" in OS.get_cmdline_user_args():
		_auto_frame += 1
		if _auto_frame == 30:
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://unit_info_window_viewer.png")
			print("[VIEWER] auto-saved user://unit_info_window_viewer.png")
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://unit_info_window_viewer.png")
		print("[VIEWER] saved user://unit_info_window_viewer.png")
