extends Node
## Defect #9 guard (FORMATION_SCREEN.md §15.26 §D): the equip-picker vitals PREVIEW blanks the
## HP/MP numerator to a dash, but the fraction is a fixed-width right-aligned 3-DIGIT field, so the
## denominator always renders 3 cells — even a 2-digit max like `44` shows as `044`. Round-34 drew
## the denominator unpadded (`-/44`, 4 cells); the fix pads it to `-/044` (5 cells).
##
## Seam: UIUnitInfoWindow (the vitals window) fed a unit view with a 2-digit HP/MP max, flipped
## into preview mode, then queried for its visible number-glyph count per row. The layout maths
## themselves are guarded purely in NumberFontTest; here we prove the caller threads field_width=3.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/VitalsPreviewFieldWidthTest.tscn

const WindowScript = preload("res://src/ui3/UIUnitInfoWindow.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	var w = WindowScript.new()
	add_child(w)
	# 2-digit HP/MP maxes — the round-34 bug rendered these as 2 cells.
	w.set_unit_view({
		"name": "Ramza", "job": "Squire", "level": 5, "exp": 8,
		"current_hp": 44, "max_hp": 44, "current_mp": 8, "max_mp": 8,
		"ct": 100, "brave": 70, "faith": 55, "sprite_id": 0x01})
	await get_tree().process_frame

	# Normal (non-preview) fraction is already a 3-wide field on both sides: `044/044` = 7 cells.
	_expect(w.number_glyph_count(0) == 7,
		"normal HP fraction should render 7 cells (044/044), got %d" % w.number_glyph_count(0))
	# Capture the numerator's three digit-cell left edges — the fixed field the dash must land in.
	var normal_xs: Array = w.number_glyph_xs(0)
	_expect(normal_xs.size() == 7, "normal HP row should expose 7 glyph positions, got %d" % normal_xs.size())

	# Preview: numerator blanks to a single dash, denominator stays a fixed 3-wide field ->
	# `-/044` = 1 dash + slash + 3 digits = 5 cells (NOT 4 with a 2-digit denominator).
	w.set_hpmp_preview(true)
	await get_tree().process_frame
	_expect(w.number_glyph_count(0) == 5,
		"preview HP fraction should render 5 cells (-/044), got %d" % w.number_glyph_count(0))
	_expect(w.number_glyph_count(1) == 5,
		"preview MP fraction should render 5 cells (-/008), got %d" % w.number_glyph_count(1))
	# §15.26 dash-cell bug: the ROM CENTERS the blanked numerator in the fixed 3-cell field
	# (" - " — dash cell 0xba in the MIDDLE digit cell), not right-aligned ("  -"). So the
	# preview dash's left edge must equal the MIDDLE numerator digit cell of the normal render.
	if normal_xs.size() == 7:
		var prev_xs: Array = w.number_glyph_xs(0)
		_expect(prev_xs.size() == 5, "preview HP row should expose 5 glyph positions, got %d" % prev_xs.size())
		if prev_xs.size() == 5:
			_expect(absf(float(prev_xs[0]) - float(normal_xs[1])) < 0.01,
				"preview dash must sit in the MIDDLE digit cell (x=%.2f), got x=%.2f (right cell is x=%.2f)"
				% [float(normal_xs[1]), float(prev_xs[0]), float(normal_xs[2])])

	# Toggling preview off restores the full numeric fraction (7 cells).
	w.set_hpmp_preview(false)
	await get_tree().process_frame
	_expect(w.number_glyph_count(0) == 7,
		"HP fraction should return to 7 cells after preview off, got %d" % w.number_glyph_count(0))

	w.queue_free()
	print("\n=== VitalsPreviewFieldWidthTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] VitalsPreviewFieldWidthTest")
		get_tree().quit(1)
	else:
		print("[PASS] VitalsPreviewFieldWidthTest: preview denominator is a fixed 3-wide field")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
