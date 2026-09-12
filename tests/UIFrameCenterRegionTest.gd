extends Node3D
## Guard: UIFrame's optional `center_region` — the tiled 9-slice CENTER samples a DIFFERENT
## atlas patch than the border/corner/edge region (`source_region`). This lets a frame keep a
## specific border+header chrome (e.g. the equip-picker's STRIPE crop) while tiling a clean
## fine-dither interior, instead of the coarse 5px block the STRIPE center would tile.
##
##   A. DEFAULT OFF — a plain UIFrame leaves center_region ZERO, so every existing caller
##      (dialogue, panels, vitals/info frames) is byte-identical (border == center == source).
##   B. PROPAGATES — setting `center_region` pushes it to the live 9-slice material uniform.

const UIFrame = preload("res://src/ui3/elements/UIFrame.gd")

var _failed := false


func _ready() -> void:
	# A. default OFF.
	var a: UIFrame = UIFrame.new()
	add_child(a)
	await get_tree().process_frame
	var ma := a.get_material()
	_expect(ma != null, "UIFrame built no material")
	if ma != null:
		var cr = ma.get_shader_parameter("center_region")
		_expect(cr == null or Vector4(cr) == Vector4.ZERO,
			"default center_region must be ZERO (off), got %s" % [cr])

	# B. propagates.
	var b: UIFrame = UIFrame.new()
	add_child(b)
	await get_tree().process_frame
	var patch := Vector4(6, 7, 21, 17)
	b.center_region = patch
	var mb := b.get_material()
	_expect(mb != null, "UIFrame(b) built no material")
	if mb != null:
		_expect(Vector4(mb.get_shader_parameter("center_region")) == patch,
			"center_region did not reach the material: got %s want %s"
				% [mb.get_shader_parameter("center_region"), patch])
		# border still samples source_region (unchanged).
		_expect(Vector4(mb.get_shader_parameter("source_region")) != patch,
			"source_region must stay the border crop, not the center patch")

	if _failed:
		printerr("[FAIL] UIFrameCenterRegionTest")
		get_tree().quit(1)
	else:
		print("[PASS] UIFrameCenterRegionTest")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		printerr("  " + msg)
