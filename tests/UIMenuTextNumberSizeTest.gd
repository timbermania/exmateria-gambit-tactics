extends Node3D
## §15.27 (round 46, issue #290) — UIMenuText.mount_number/number_width take a FRAMEFONT
## size ("big"/"small"), defaulting SMALL so every existing caller (Status stats band,
## vitals) is unchanged. The equip-picker count digits are the BIG-set consumer.
##
## Expected literals come from FRAMEFONT.json (the parse_frame_font.py extraction),
## NOT recomputed through NumberFont: big advance 7, big '0' cell (0,0,8,16),
## big '/' cell (90,0,8,16); small advance 5, small '0' cell (0,17,6,10).
##
## Run: <GODOT> --path . --quit-after 6 res://tests/UIMenuTextNumberSizeTest.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	var t := UIMenuText.new()

	# number_width in each size — fixed advance per char (manifest literals 7 / 5).
	_expect(is_equal_approx(t.number_width("00", NumberFont.BIG), 14.0),
		"number_width('00', BIG) = %f, want 14 (big advance 7)" % t.number_width("00", NumberFont.BIG))
	_expect(is_equal_approx(t.number_width("00", NumberFont.SMALL), 10.0),
		"number_width('00', SMALL) = %f, want 10 (small advance 5)" % t.number_width("00", NumberFont.SMALL))
	# Default stays SMALL — the no-arg width every existing caller right-aligns with.
	_expect(is_equal_approx(t.number_width("00"), 10.0),
		"number_width('00') default = %f, want 10 (SMALL)" % t.number_width("00"))

	# mount_number(BIG): glyphs sample the BIG atlas cells and advance 7px apart.
	var parent := Node3D.new()
	add_child(parent)
	var mats: Array = []
	var adv := t.mount_number(parent, "0/", Vector3.ZERO, 0, 1.0, null, mats, NumberFont.BIG)
	_expect(is_equal_approx(adv, 14.0), "mount_number BIG '0/' advanced %f px, want 14" % adv)
	_expect(mats.size() == 2, "mount_number BIG '0/' mounted %d glyphs, want 2" % mats.size())
	if mats.size() == 2:
		var c0: Vector4 = mats[0].get_shader_parameter("cell")
		var c1: Vector4 = mats[1].get_shader_parameter("cell")
		_expect(c0 == Vector4(0, 0, 8, 16), "BIG '0' cell %s, want (0,0,8,16)" % c0)
		_expect(c1 == Vector4(90, 0, 8, 16), "BIG '/' cell %s, want (90,0,8,16)" % c1)
	var holders := parent.get_children()
	_expect(holders.size() == 2 and is_equal_approx((holders[1] as Node3D).position.x
			- (holders[0] as Node3D).position.x, 7.0),
		"BIG glyph pitch != 7px between holders")

	# mount_number default (no size arg) still samples the SMALL set.
	var parent2 := Node3D.new()
	add_child(parent2)
	var mats2: Array = []
	t.mount_number(parent2, "0", Vector3.ZERO, 0, 1.0, null, mats2)
	_expect(mats2.size() == 1 and mats2[0].get_shader_parameter("cell") == Vector4(0, 17, 6, 10),
		"default mount_number '0' cell drifted from SMALL (0,17,6,10)")

	print("\n=== UIMenuTextNumberSizeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UIMenuTextNumberSizeTest")
		get_tree().quit(1)
	else:
		print("[PASS] UIMenuTextNumberSizeTest")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
