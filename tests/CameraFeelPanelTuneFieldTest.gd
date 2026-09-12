extends Node
## Move-2 guard (ADR-0068): CameraFeelDebugPanel's rows are built by the shared
## TuneField bound to `camera.*` slugs, not HSliders writing onto the PlayerCamera
## node — so each carries the accent (pinnable) label AND writes through to its slug
## (which PlayerCamera coalesces). Built in a bare tree; setup() takes an (unused)
## camera arg, so null is fine here.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/CameraFeelPanelTuneFieldTest.tscn

const CameraPanel = preload("res://src/debug/CameraFeelDebugPanel.gd")
const TuneField = preload("res://src/debug/TuneField.gd")
# 🔴 LOAD-BEARING WITH NO READER, AND THAT IS THE POINT (ADR-0208 dec. 1).
# Nothing below uses `CameraMount`. Its entire value is the SIDE EFFECT of loading it:
# loading this PackedScene loads the addon camera script it is based on, whose
# `_static_init` binds the `camera.*` slugs at class load. `CameraFeelDebugPanel` names no
# script at all — it is a pure view over slug STRINGS — so without this line the panel
# renders every row as an unsupported read-only field and the assertions below stop
# meaning anything.
#
# This used to preload the ADDON script by path (a criterion-4 site) and then call
# `register_tunables()` explicitly. Measured, four ways: the explicit call is a NO-OP —
# class load alone registers — and loading the HOST mount registers identically without
# instantiating anything. Instantiating it, which ADR-0207 dec. 3 assumed was required,
# builds the whole camera rig plus the host's CombatUI and throws eight
# `get_value(render.ui_pixel_aspect) before its bind` errors doing it. So the reach was never
# about reaching a `static func`; it was about forcing a class load, and the host's own
# declared mount already does that.
#
# DO NOT DELETE THIS AS UNUSED. `_ready`'s first assert fails loudly if you do.
const CameraMount = preload("res://assets/scenes/CombatCamera.tscn")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# `reset_overrides()`, NOT `reset()` — ADR-0173 / #535, and `Tune.reset()`'s own docstring
	# says so in as many words: a test that clears the registry and then wants a class-load
	# owner's slugs back has no way back, because `_static_init` fires once per class load per
	# process. Clearing only the recoverable half (overrides, committed baseline, R8 scrub
	# tracking) leaves the DECLARATIONS standing, which is the whole isolation this test needs.
	# Replaying an owner's registration by naming it is the deleted `register_all()` shape done
	# by hand for one owner.
	Tune.reset_overrides()
	# THE GUARD ON THE CONST ABOVE. This fires if `CameraMount` is deleted as unused, if the
	# mount stops carrying the camera script, or if `_static_init` regresses — it tests the
	# EFFECT, not the line. Without it, all four assertions below would pass vacuously against
	# unregistered slugs, which is exactly how CameraFeel once printed [PASS] through 5322
	# `get_value` script errors (src/core/Tune.gd, on_update's 🔴).
	assert(Tune.is_registered("camera.rot_speed"),
		"[CameraFeelPanelTuneFieldTest] the camera.* slugs are not registered — the mount "
		+ "const above is what loads the owner's class. ADR-0208 dec. 1.")
	var panel := CameraPanel.new()
	add_child(panel)
	panel.setup(null)

	var row := _find_row(panel, "Rotation speed")
	_assert_true(row != null, "the 'Rotation speed' row exists")
	if row:
		var label := row.get_child(0) as Label
		_assert_true(label != null and label.has_theme_color_override("font_color")
			and label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the Rotation speed row carries the TuneField accent label")
		var sb := _first_spinbox(row)
		_assert_true(sb != null, "the Rotation speed row has a SpinBox control")
		if sb:
			sb.value = 22.0
			sb.value_changed.emit(22.0)
			_assert_true(is_equal_approx(float(Tune.bind("camera.rot_speed", 10.0)), 22.0),
				"scrubbing the row writes through to camera.rot_speed")
	Tune.clear("camera.rot_speed")

	panel.queue_free()

	print("\n=== CameraFeelPanelTuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraFeelPanelTuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraFeelPanelTuneFieldTest")
		get_tree().quit(0)


func _find_row(node: Node, label_text: String) -> Control:
	for child in node.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var lbl := child.get_child(0) as Label
			if lbl and lbl.text == label_text:
				return child
		var found := _find_row(child, label_text)
		if found:
			return found
	return null


func _first_spinbox(row: Control) -> SpinBox:
	for child in row.get_children():
		if child is SpinBox:
			return child
	return null


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)
