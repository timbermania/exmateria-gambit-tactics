extends Node3D
## Guard: the equip-picker window keeps its STRIPE frame chrome (border + brown header stripe +
## footer) but tiles a CLEAN fine-dither interior — the same patch the Eqp/Ability/stats panels
## tile — instead of the STRIPE crop's coarse 5px center block (which repeated its dense top row
## every 5px into a mottled, low-res body). Locks:
##   A. the frame border still samples STRIPE_SOURCE (218,3,30,22) — the frame is unchanged;
##   B. the frame's tiled CENTER samples the fine-dither patch (the picker's body_dither_patch()
##      tuneable), so the interior matches the other forms.

const EquipPickerMenu = preload("res://src/ui3/detail/EquipPickerMenu.gd")
const UIFrame = preload("res://src/ui3/elements/UIFrame.gd")

var _failed := false


func _ready() -> void:
	var m: EquipPickerMenu = EquipPickerMenu.new()
	m.autoplay_open = false
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	# A. border unchanged — still the STRIPE crop.
	_expect(m.frame_source_region() == UIFrame.STRIPE_SOURCE,
		"picker frame border must stay STRIPE_SOURCE, got %s" % [m.frame_source_region()])

	# B. center tiles the fine-dither patch (non-zero, and NOT the STRIPE interior).
	var patch := m.body_dither_patch()
	_expect(patch.z > 0.0, "body_dither_patch must be a real atlas region, got %s" % [patch])
	_expect(m.frame_center_region() == patch,
		"picker frame center_region not wired to body_dither_patch: got %s want %s"
			% [m.frame_center_region(), patch])
	# The fine patch must come from the flat menu-tile dither, NOT inside the STRIPE sprite.
	var stripe := UIFrame.STRIPE_SOURCE
	var inside_stripe := patch.x >= stripe.x and patch.x < stripe.x + stripe.z \
		and patch.y >= stripe.y and patch.y < stripe.y + stripe.w
	_expect(not inside_stripe,
		"the fine-dither patch must be OUTSIDE the STRIPE sprite (its 5px body is the coarse one), got %s" % [patch])

	m.queue_free()
	if _failed:
		printerr("[FAIL] EquipPickerInteriorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EquipPickerInteriorTest")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		printerr("  " + msg)
