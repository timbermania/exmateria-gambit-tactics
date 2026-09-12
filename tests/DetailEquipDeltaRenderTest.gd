extends Node3D
## Equip stat-DELTA render guard (FORMATION_SCREEN.md §15.26 / EQUIP_STAT_PREVIEW.md).
##
## The equip-picker compare panel fills the Weap.Power row with the SIGNED delta of the item
## under the cursor: positive → blue "+N", negative → red "-N", zero/field-N-A → a tan dash.
## This is the port of the ROM's sign→colour→dash classifier (doc §5) — the port swaps the
## whole number CLUT (blue/red = FRAME pal 15 sub-ramps) rather than the ROM's index bias, but
## the outcome is the same: the digits of a gain render blue, a loss red.
##
## Seam: DetailScene. `set_stats_preview_delta(delta, slot)` enters preview AND fills the
## focused hand's Weap.Power row with the delta; the guard reads how many stats-text glyphs
## render through the blue vs red delta CLUT (stats_delta_glyph_palette_counts()).
##
## Expected numbers are the oracle savestates:
##   sstate2  Broad Sword into empty R.Hand → +4 / +5  (both BLUE): "+4" and "+5" = 4 blue glyphs.
##   sstate4  Dagger over equipped Broad Sword → -1 / -  (RED then dash): "-1" = 2 red glyphs,
##            evade 0 → a tan dash (0 coloured).
##
## Run: <GODOT> --path . --quit-after 10 res://tests/DetailEquipDeltaRenderTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	var d = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	await get_tree().process_frame
	d.set_stats_view({
		"move": 3, "jump": 3, "speed": 8, "r_power": 4, "r_wev": 5, "l_power": 0, "l_wev": 0,
		"r_at": 4, "c_ev": 5, "s_ev": 0, "a_ev": 0, "l_at": 0})
	await get_tree().process_frame

	# Plain preview (no delta) = all dashes: nothing coloured.
	d.set_stats_preview(true)
	await get_tree().process_frame
	var plain: Dictionary = d.stats_delta_glyph_palette_counts()
	_expect(plain.get("pos", -1) == 0 and plain.get("neg", -1) == 0,
		"dash-mode preview must colour no glyphs, got %s" % plain)
	d.set_stats_preview(false)
	await get_tree().process_frame

	# sstate2: Broad Sword into empty R.Hand → Weap.Power R = +4 / +5 (blue).
	d.set_stats_preview_delta({"wp": 4, "wev": 5, "hp": 0, "mp": 0},
		UnitProgression.EquipSlot.RIGHT_HAND)
	await get_tree().process_frame
	var gain: Dictionary = d.stats_delta_glyph_palette_counts()
	# "+4" = '+' and '4'; "+5" = '+' and '5' → 4 blue glyphs, no red.
	_expect(gain.get("pos", -1) == 4,
		"+4 / +5 must render 4 blue glyphs, got pos=%s (%s)" % [gain.get("pos"), gain])
	_expect(gain.get("neg", -1) == 0,
		"a pure gain must render no red glyphs, got neg=%s" % gain.get("neg"))
	_expect(d.stats_delta_active(),
		"the compare panel must be built in delta-preview mode")

	# sstate4: Dagger over equipped Broad Sword → Weap.Power R = -1 / - (red + dash).
	d.set_stats_preview_delta({"wp": -1, "wev": 0, "hp": 0, "mp": 0},
		UnitProgression.EquipSlot.RIGHT_HAND)
	await get_tree().process_frame
	var loss: Dictionary = d.stats_delta_glyph_palette_counts()
	# "-1" = '-' and '1' → 2 red glyphs; evade 0 → a tan dash (not coloured).
	_expect(loss.get("neg", -1) == 2,
		"-1 must render 2 red glyphs, got neg=%s (%s)" % [loss.get("neg"), loss])
	_expect(loss.get("pos", -1) == 0,
		"a loss (evade 0) must render no blue glyphs, got pos=%s" % loss.get("pos"))

	# The delta on the OTHER hand's slot leaves the R row dashed (only the focused slot fills).
	d.set_stats_preview_delta({"wp": 4, "wev": 5, "hp": 0, "mp": 0},
		UnitProgression.EquipSlot.LEFT_HAND)
	await get_tree().process_frame
	var lhand: Dictionary = d.stats_delta_glyph_palette_counts()
	_expect(lhand.get("pos", -1) == 4,
		"a Left-hand delta must fill the L Weap.Power row (4 blue), got %s" % lhand)

	# Leaving preview returns to real values, nothing coloured.
	d.set_stats_preview(false)
	await get_tree().process_frame
	var off: Dictionary = d.stats_delta_glyph_palette_counts()
	_expect(off.get("pos", -1) == 0 and off.get("neg", -1) == 0,
		"leaving preview must clear all delta colouring, got %s" % off)

	d.queue_free()
	print("\n=== DetailEquipDeltaRenderTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailEquipDeltaRenderTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailEquipDeltaRenderTest: Weap.Power delta renders +blue / -red / dash")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
