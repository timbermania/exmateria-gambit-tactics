extends Node3D

## §15.21 guard: the START/sub-menu WINDOW FRAME must actually swap to its blue-grey
## deactivated CLUT when sent to background — not just flip the `_backgrounded` bool.
##
## The nine-slice frame shader (nine_slice_3d_opaque) only performs the fg→bg palette
## remap when `backgrounded > 0.5 AND palette_count > 0`. UI3Element._ensure_chrome arms
## that pair (fg_palette / bg_palette / palette_count=16) on the chrome material. The arm
## was silently dropping because it read `frame.get_material()` before the UIFrame's
## `_ready` had built the material (add_child during the element's own _enter_tree batch
## does NOT run the child's _ready synchronously) — so palette_count stayed 0 and the
## frame never turned blue, even though set_backgrounded() flipped the state + the row
## glyphs / "Menu" tab / glove (which recolour by other means). This guard pins the arm.

const StartActionMenu = preload("res://src/ui3/detail/StartActionMenu.gd")

var _failed := false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] " + msg)


func _ready() -> void:
	# A fresh sub-menu built at its EQUIP home (the §15.23 Item→Equip window).
	var m: StartActionMenu = StartActionMenu.new()
	m.autoplay_open = false
	m.location = StartActionMenu.LOC_EQUIP
	m.rows = StartActionMenu.ROWS_EQUIP
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	var mat := m.frame_element().chrome_material()
	_expect(mat != null, "no chrome material on the built frame")
	if mat != null:
		# The swap GATE must be armed after a plain build (the bug: palette_count unset/0).
		_expect(mat.get_shader_parameter("palette_count") == 16,
			"frame chrome palette_count must be 16 (armed for the §15.21 swap), got %s"
			% mat.get_shader_parameter("palette_count"))
		# Foreground on build.
		_expect(mat.get_shader_parameter("backgrounded") == 0.0,
			"frame must build foreground (backgrounded=0), got %s"
			% mat.get_shader_parameter("backgrounded"))

	# Send to background → the shader now has BOTH gate conditions true (blue frame).
	m.set_backgrounded(true)
	if mat != null:
		_expect(mat.get_shader_parameter("backgrounded") == 1.0,
			"set_backgrounded(true) must set backgrounded=1 on the frame material")
		_expect(mat.get_shader_parameter("palette_count") == 16,
			"palette_count must stay armed through a background swap")

	# Back to foreground.
	m.set_backgrounded(false)
	if mat != null:
		_expect(mat.get_shader_parameter("backgrounded") == 0.0,
			"set_backgrounded(false) must return the frame to foreground")

	m.free()
	if _failed:
		print("[FAIL] StartMenuBackgroundedFrameSwapTest")
		get_tree().quit(1)
	else:
		print("[PASS] StartMenuBackgroundedFrameSwapTest")
		get_tree().quit(0)
