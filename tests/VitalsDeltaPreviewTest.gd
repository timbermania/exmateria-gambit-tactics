extends Node
## Vitals HP/MP delta preview (FORMATION_SCREEN.md §15.26 / EQUIP_STAT_PREVIEW.md §6).
##
## Armor/accessory equip deltas route to a DIFFERENT sink than the weapon Weap.Power row: the
## vitals HP/MP NUMERATORS. The oracle sstate3 (Clothes onto Body, hp_bonus 5) shows the HP
## numerator gain "+5" (positive → cool/blue). A field with no change (Clothes mp_bonus 0) stays
## a dash, exactly like the plain preview.
##
## Seam: UIUnitInfoWindow. `set_hpmp_delta(hp, mp)` enters HP/MP preview AND fills each numerator
## with its signed delta ("+5" blue / "-N" red), or a dash when the delta is 0. Denominator +
## slash keep their normal menu ink; only the numerator is sign-coloured.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/VitalsDeltaPreviewTest.tscn

const WindowScript = preload("res://src/ui3/UIUnitInfoWindow.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	var w = WindowScript.new()
	add_child(w)
	w.set_unit_view({
		"name": "Ramza", "job": "Squire", "level": 5, "exp": 8,
		"current_hp": 44, "max_hp": 44, "current_mp": 8, "max_mp": 8,
		"ct": 100, "brave": 70, "faith": 55, "sprite_id": 0x01})
	await get_tree().process_frame

	# sstate3: Clothes onto Body → HP numerator +5 (blue), MP unchanged (0 → dash).
	w.set_hpmp_delta(5, 0)
	await get_tree().process_frame

	# HP row: "+5" (2 glyphs) + "/" + "044" (3) = 6 cells; numerator coloured blue.
	_expect(w.number_glyph_count(0) == 6,
		"HP +5 fraction should render 6 cells (+5/044), got %d" % w.number_glyph_count(0))
	var hp: Dictionary = w.number_glyph_palette_counts(0)
	_expect(hp.get("pos", -1) == 2,
		"HP +5 numerator should render 2 blue glyphs, got %s" % hp)
	_expect(hp.get("neg", -1) == 0, "a gain must render no red glyphs, got %s" % hp)

	# MP row: delta 0 → dash preview ("-/008" = 5 cells), nothing coloured.
	_expect(w.number_glyph_count(1) == 5,
		"MP unchanged should stay a dash fraction (-/008 = 5 cells), got %d" % w.number_glyph_count(1))
	var mp: Dictionary = w.number_glyph_palette_counts(1)
	_expect(mp.get("pos", -1) == 0 and mp.get("neg", -1) == 0,
		"an unchanged (0) MP field must colour no glyphs, got %s" % mp)

	# A loss recolours red: removing a +5-HP item previews -5 (red).
	w.set_hpmp_delta(-5, 0)
	await get_tree().process_frame
	var loss: Dictionary = w.number_glyph_palette_counts(0)
	_expect(loss.get("neg", -1) == 2 and loss.get("pos", -1) == 0,
		"HP -5 numerator should render 2 red glyphs, got %s" % loss)

	# Leaving preview restores the real numeric fraction, nothing coloured.
	w.set_hpmp_preview(false)
	await get_tree().process_frame
	_expect(w.number_glyph_count(0) == 7,
		"HP fraction should return to 7 cells (044/044) after preview off, got %d" % w.number_glyph_count(0))
	var off: Dictionary = w.number_glyph_palette_counts(0)
	_expect(off.get("pos", -1) == 0 and off.get("neg", -1) == 0,
		"leaving preview must clear delta colouring, got %s" % off)

	w.queue_free()
	print("\n=== VitalsDeltaPreviewTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] VitalsDeltaPreviewTest")
		get_tree().quit(1)
	else:
		print("[PASS] VitalsDeltaPreviewTest: HP/MP numerator delta renders +blue / -red / dash")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
