extends Node

## RangeTileAtlas test — pure GDScript, no GPU.
##
## Guards the feedback-HUD sprite seam (#88): RangeTileAtlas loads
## RANGETILE.json (emitted by tools/parse_range_tiles.py) and hands consumers
## (#89 over-unit numbers, #90 status icons, #91 info window) the atlas texture
## plus per-glyph / per-icon cell rects. Values are the measured atlas cells.

const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")


func _ready() -> void:
	var failed := false
	var atlas := RangeTileAtlas.new()

	# 1. The atlas texture loads.
	if atlas.texture == null:
		print("[FAIL] atlas.texture is null (RANGETILE.tga not loaded)")
		failed = true

	# 2. Digit set: 0-9 and '/', fixed-pitch-8 cells at the ROM-corrected
	#    origin (168,49) / 8x14 (the old y52/h11 clipped the 6/8 tops).
	if atlas.digit_glyphs() != "0123456789/":
		print("[FAIL] digit glyphs = '%s'" % atlas.digit_glyphs())
		failed = true
	if atlas.digit_rect("0") != Rect2(168, 49, 8, 14):
		print("[FAIL] digit '0' rect = %s, expected (168,49,8,14)" % atlas.digit_rect("0"))
		failed = true
	if atlas.digit_rect("/") != Rect2(248, 49, 8, 14):
		print("[FAIL] digit '/' rect = %s, expected (248,49,8,14)" % atlas.digit_rect("/"))
		failed = true
	# fixed pitch: '5' is the 6th glyph -> origin + 5*8
	if atlas.digit_rect("5").position.x != 168 + 5 * 8:
		print("[FAIL] digit '5' x = %d" % atlas.digit_rect("5").position.x)
		failed = true

	# 2b. Digit CLUT (number palette 0x7d7c): the DAMAGE path lights every glyph
	#     through these 16 entries, so an empty/short array => an all-transparent
	#     palette => the shader discards everything => INVISIBLE numbers. A stale
	#     RANGETILE.json (generated before the parser emitted `digits.colors`) hits
	#     exactly this; assert the CLUT is fully present so CI catches it, not the eye.
	var dc: Array = atlas.digit_palette_colors()
	if dc.size() != 16:
		print("[FAIL] digit CLUT has %d colors, expected 16 — stale RANGETILE.json? rerun parse_range_tiles.py" % dc.size())
		failed = true
	else:
		# idx0 transparent (the key), idx2 the white fill — the parser's VRAM-verified anchors.
		if dc[0].a8 != 0:
			print("[FAIL] digit CLUT idx0 alpha = %d, expected 0 (transparent key)" % dc[0].a8)
			failed = true
		if dc[2].r8 < 200 or dc[2].g8 < 200 or dc[2].b8 < 200 or dc[2].a8 != 255:
			print("[FAIL] digit CLUT idx2 = %s, expected opaque near-white fill" % str(dc[2]))
			failed = true

	# 3. Status icons: 20 across three atlas rows (176/188/200).
	if atlas.status_icon_count() != 20:
		print("[FAIL] status_icon_count = %d, expected 20" % atlas.status_icon_count())
		failed = true
	# The ROM's X bytes are atlas COLUMNS, not indices into a synthetic 14px grid at
	# x=16 — the parser used to snap them and shifted every cell onto its right-hand
	# neighbour (AT_MARKER_RENDERING.md §8.2). Entry 0 is the strip's first cell at x=0;
	# entry 8 is the "AT" glyph the marker itself draws, which is what makes this
	# assertion discriminating rather than a restatement of the emitter.
	if atlas.status_icon_rect(0) != Rect2(0, 176, 14, 12):
		print("[FAIL] icon 0 rect = %s, expected (0,176,14,12)" % atlas.status_icon_rect(0))
		failed = true
	if atlas.status_icon_rect(8) != Rect2(114, 176, 14, 12):
		print("[FAIL] icon 8 rect = %s, expected (114,176,14,12) — shifted strip?" % atlas.status_icon_rect(8))
		failed = true

	# 3a. The "AT" active-turn marker: two 14x12 frames one row apart at the ROM's
	#     literal (114,176), its own CLUT, and the 16-frame/1px animation constants.
	#     Slot 21 of the carousel, addressed by CODE not by the status table, so it is
	#     a named block and NOT status_icon_rect(21).
	if atlas.active_turn_frame_count() != 2:
		print("[FAIL] active_turn_frame_count = %d, expected 2 — stale RANGETILE.json? rerun parse_range_tiles.py" % atlas.active_turn_frame_count())
		failed = true
	else:
		if atlas.active_turn_rect(0) != Rect2(114, 176, 14, 12):
			print("[FAIL] AT phase 0 rect = %s, expected (114,176,14,12)" % atlas.active_turn_rect(0))
			failed = true
		if atlas.active_turn_rect(1) != Rect2(114, 188, 14, 12):
			print("[FAIL] AT phase 1 rect = %s, expected (114,188,14,12)" % atlas.active_turn_rect(1))
			failed = true
	if atlas.active_turn_phase_frames() != 16 or atlas.active_turn_bob_px() != 1:
		print("[FAIL] AT animation = %d frames / %d px, expected 16 / 1" % [
			atlas.active_turn_phase_frames(), atlas.active_turn_bob_px()])
		failed = true
	# 3a-ii. The per-sprite-type marker offset switch (AT_MARKER_RENDERING.md §5.2). Keyed
	#     by the SHP-type byte of BATTLE.BIN 0x2D748 — the table parse_sprite_types.py
	#     already extracts — so a monster hangs the marker at -50 and a KANZEN at -120
	#     where one constant used to put every unit at -40. `x` is a SCREEN-pixel nudge and
	#     is 0 on every reachable row: the -5 rows key off three UNNAMED ROM pose ids, so
	#     asserting it stays 0 is asserting the GAP, not the absence of the feature.
	var at_off_expected := {
		"TYPE1": Vector2i(0, -40), "TYPE2": Vector2i(0, -40),
		"CYOKO": Vector2i(0, -50), "MON": Vector2i(0, -50), "RUKA": Vector2i(0, -50),
		"OTHER": Vector2i(0, -25), "ARUTE": Vector2i(0, -70), "KANZEN": Vector2i(0, -120),
	}
	for shp in at_off_expected:
		if atlas.active_turn_offset(shp) != at_off_expected[shp]:
			print("[FAIL] AT offset for %s = %s, expected %s" % [
				shp, atlas.active_turn_offset(shp), at_off_expected[shp]])
			failed = true
	# An unknown / weapon / effect SHP key (the ROM's `>= 8` fall-through) takes the
	# default row, not zero — a marker at height 0 would sit inside the unit's feet.
	if atlas.active_turn_offset("WEP1") != Vector2i(0, -50):
		print("[FAIL] AT offset fallback = %s, expected (0,-50)" % atlas.active_turn_offset("WEP1"))
		failed = true
	# 3a-iii. The same rows resolved from a SPRITE ID, which is what both over-head elements
	#     actually hold. These are the CAROUSEL's offsets: `unit_sprite_poly_builder`
	#     (0x8007EEC0) reads `unit[+0x2DF]` at 0x8007F0C4, after the AT slot, slots 0/20 and
	#     the table-indexed slots 1..19 have ALL converged on LAB_8007F088, with no slot test
	#     between. So `StatusBubble3D` reads them too.
	if atlas.overhead_offset_for_sprite(0x49) != Vector2i(0, -120):
		print("[FAIL] sprite 0x49 offset = %s, expected (0,-120) — the KANZEN row" % atlas.overhead_offset_for_sprite(0x49))
		failed = true
	if atlas.overhead_offset_for_sprite(0x86) == atlas.overhead_offset_for_sprite(0x00):
		print("[FAIL] a monster and a human resolve to the same offset — the lookup collapsed")
		failed = true
	# A negative / unknown sprite id is the human-scale fallback, NOT zero: an icon at
	# height 0 would sit inside the unit's feet.
	if atlas.overhead_offset_for_sprite(-1) != Vector2i(0, -40):
		print("[FAIL] sprite -1 offset = %s, expected (0,-40)" % atlas.overhead_offset_for_sprite(-1))
		failed = true
	# -Y is up in FFT and +Y is up in Godot, so the height NEGATES and divides by the tile.
	if not is_equal_approx(RangeTileAtlas.overhead_raise_for_offset(Vector2i(0, -28)), 1.0):
		print("[FAIL] overhead_raise_for_offset(-28) = %f, expected 1.0 (one tile up)" %
			RangeTileAtlas.overhead_raise_for_offset(Vector2i(0, -28)))
		failed = true

	var atc: Array = atlas.active_turn_colors()
	if atc.size() != 16:
		print("[FAIL] AT CLUT has %d colors, expected 16" % atc.size())
		failed = true
	elif atc[0].a8 != 0:
		print("[FAIL] AT CLUT idx0 alpha = %d, expected 0 (transparent key)" % atc[0].a8)
		failed = true
	var rows := {}
	for i in atlas.status_icon_count():
		rows[atlas.status_icon_rect(i).position.y] = true
	var row_keys := rows.keys()
	row_keys.sort()
	if row_keys != [176.0, 188.0, 200.0]:
		print("[FAIL] icon rows = %s, expected [176,188,200]" % str(row_keys))
		failed = true

	# 3b. Word labels (vitals readout): ROM-authoritative cells (decoded from the
	#     live GPU primitives). Hp is the SPRT cell (168,32) 16x9.
	if not atlas.has_label("Hp"):
		print("[FAIL] word label 'Hp' missing from atlas")
		failed = true
	if atlas.label_rect("Hp") != Rect2(168, 32, 16, 9):
		print("[FAIL] label 'Hp' rect = %s, expected (168,32,16,9)" % atlas.label_rect("Hp"))
		failed = true
	for n in ["Mp", "Ct", "Exp."]:
		if not atlas.has_label(n):
			print("[FAIL] word label '%s' missing" % n)
			failed = true

	# 3c. Detail/Status-screen Ability-window icons (§15.15): five FIXED cells in
	#     the (136,0)-(168,32) block, sharing the menu icon CLUT 0x7d7c. Rows 0/1
	#     share the blade cell; 2/3/4 are fist/diamond/boot.
	if atlas.ability_icon_count() != 5:
		print("[FAIL] ability_icon_count = %d, expected 5" % atlas.ability_icon_count())
		failed = true
	var abl_expected := [Rect2(136, 0, 12, 16), Rect2(136, 0, 12, 16),
			Rect2(148, 0, 12, 16), Rect2(136, 16, 16, 16), Rect2(152, 16, 16, 16)]
	for i in abl_expected.size():
		if atlas.ability_icon_rect(i) != abl_expected[i]:
			print("[FAIL] ability icon %d rect = %s, expected %s" % [i, atlas.ability_icon_rect(i), abl_expected[i]])
			failed = true
	if atlas.ability_icon_palette_colors().size() != 16:
		print("[FAIL] ability icon CLUT has %d colors, expected 16" % atlas.ability_icon_palette_colors().size())
		failed = true

	# 3d. Detail/Status-screen Eqp slot-category icons (§15.16): five two-layer
	#     rows (dark backing 0x7c3c under lit 0x7d7c) + the two-handed variant.
	if atlas.slot_icon_count() != 5:
		print("[FAIL] slot_icon_count = %d, expected 5" % atlas.slot_icon_count())
		failed = true
	if atlas.slot_icon_lit_rect(0) != Rect2(0, 140, 8, 12):
		print("[FAIL] slot R.Hand lit = %s, expected (0,140,8,12)" % atlas.slot_icon_lit_rect(0))
		failed = true
	if atlas.slot_icon_dark_rect(0) != Rect2(0, 128, 8, 12):
		print("[FAIL] slot R.Hand dark = %s, expected (0,128,8,12)" % atlas.slot_icon_dark_rect(0))
		failed = true
	if atlas.slot_icon_2h_lit_rect() != Rect2(48, 144, 16, 16):
		print("[FAIL] slot 2H variant = %s, expected (48,144,16,16)" % atlas.slot_icon_2h_lit_rect())
		failed = true
	# Both slot CLUTs present; dark idx1 is the dark ink, lit idx2 the white fill.
	if atlas.slot_icon_lit_colors().size() != 16 or atlas.slot_icon_dark_colors().size() != 16:
		print("[FAIL] slot CLUTs sizes = %d/%d, expected 16/16" % [atlas.slot_icon_lit_colors().size(), atlas.slot_icon_dark_colors().size()])
		failed = true
	elif atlas.slot_icon_dark_colors()[1].r8 > 80 or atlas.slot_icon_lit_colors()[2].r8 < 200:
		print("[FAIL] slot CLUTs look wrong: dark idx1=%s lit idx2=%s" % [atlas.slot_icon_dark_colors()[1], atlas.slot_icon_lit_colors()[2]])
		failed = true

	# 4. Convenience: an AtlasTexture for a cell is region-clipped to that cell.
	var at := atlas.cell_atlas_texture(atlas.digit_rect("7"))
	if at == null or at.region != atlas.digit_rect("7"):
		print("[FAIL] cell_atlas_texture region mismatch")
		failed = true

	if failed:
		print("[FAIL] RangeTileAtlas test")
	else:
		print("[PASS] RangeTileAtlas: digits 0-9/ + 20 status icons + 5 ability + 5 slot icons from RANGETILE.json")
	get_tree().quit()
