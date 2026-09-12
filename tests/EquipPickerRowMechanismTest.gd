extends Node
## §15.26 equipment-picker ROW mechanism guard (RE round 35) — pure, no GPU.
##
## The picker item row is 5 columns, each with a SPECIFIC ROM mechanism (§15.26 table B). This
## guards the mechanism-bearing pieces that are testable without the (unextracted) ITEM.BIN sheet:
##   (b) item ICON = ITEM.BIN via the `graphic` byte — the WORLD literal from
##       world_item_icon_place 0x800EA990: U=(graphic%15)*16, V=(graphic/15)*16+0x20, 16x16,
##       CLUT 0x3fa8 by item type. The icon TEXTURE is a documented deferral; the FORMULA is here.
##   (a) type/class glyph = PER-TYPE 12×12 RANGETILE cells (WORLD.BIN LUT 0x8018D7FC) through the
##       idle dark CLUT 0x7c3c (§15.28 round 47).
##   rows carry the `graphic` + `type` + `wtype` bytes the icon/CLUT/glyph are keyed on.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EquipPickerRowMechanismTest.tscn

const EquipPickerMenu = preload("res://src/ui3/detail/EquipPickerMenu.gd")
const UIFrame = preload("res://src/ui3/elements/UIFrame.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	# (b) The ITEM.BIN icon UV formula — the WORLD literal (world_item_icon_place 0x800EA990).
	# §15.26 dynamic proofs: u192,v32 -> graphic 12; u16,v32 -> 1; u0,v128 -> 90; and u0,v32 -> 0.
	_expect(EquipPickerMenu.icon_uv_for(12) == Rect2(192, 32, 16, 16),
		"icon_uv_for(12) = %s, want (192,32,16,16)" % EquipPickerMenu.icon_uv_for(12))
	_expect(EquipPickerMenu.icon_uv_for(1) == Rect2(16, 32, 16, 16),
		"icon_uv_for(1) = %s, want (16,32,16,16)" % EquipPickerMenu.icon_uv_for(1))
	_expect(EquipPickerMenu.icon_uv_for(90) == Rect2(0, 128, 16, 16),
		"icon_uv_for(90) = %s, want (0,128,16,16)" % EquipPickerMenu.icon_uv_for(90))
	_expect(EquipPickerMenu.icon_uv_for(0) == Rect2(0, 32, 16, 16),
		"icon_uv_for(0) = %s, want (0,32,16,16)" % EquipPickerMenu.icon_uv_for(0))

	# The two CLUT constants the columns are keyed on (icon 0x3fa8 by type; type-glyph idle 0x7c3c —
	# §15.28: FUN_801298C0 loads DAT_801CD1BC from the WORLD bank @0x8018DF8C; the live prim scan shows
	# every picker row idle. Round-35's 0x7dfc claim is refuted).
	_expect(EquipPickerMenu.ITEM_ICON_CLUT == 0x3fa8,
		"ITEM_ICON_CLUT = 0x%x, want 0x3fa8" % EquipPickerMenu.ITEM_ICON_CLUT)
	_expect(EquipPickerMenu.TYPE_GLYPH_CLUT == 0x7c3c,
		"TYPE_GLYPH_CLUT = 0x%x, want 0x7c3c" % EquipPickerMenu.TYPE_GLYPH_CLUT)

	# (§15.26 b, round-36) per-type icon CLUT = 0x3fa8 + (type&7) + (type>>3)*0x40, from the live-read
	# DAT bases (640,254). Oracle-observed banks: weapons type 0 → 0x3fa8; armour 0x3fae (6), 0x3feb (11).
	_expect(EquipPickerMenu.type_clut(0) == 0x3fa8, "type_clut(0)=0x%x, want 0x3fa8" % EquipPickerMenu.type_clut(0))
	_expect(EquipPickerMenu.type_clut(6) == 0x3fae, "type_clut(6)=0x%x, want 0x3fae" % EquipPickerMenu.type_clut(6))
	_expect(EquipPickerMenu.type_clut(11) == 0x3feb, "type_clut(11)=0x%x, want 0x3feb" % EquipPickerMenu.type_clut(11))
	_expect(EquipPickerMenu.type_clut(8) == 0x3fe8, "type_clut(8)=0x%x, want 0x3fe8" % EquipPickerMenu.type_clut(8))

	# Rows carry the `graphic` + `type` bytes (the icon/CLUT keys), not just name/counts.
	var p = EquipPickerMenu.new()
	add_child(p)
	await get_tree().process_frame
	_expect(p.entries.size() >= 1, "picker built no rows")
	if p.entries.size() >= 1:
		var e: Dictionary = p.entries[0]
		_expect(e.has("graphic"), "row lacks the ITEM.BIN `graphic` byte (icon key)")
		_expect(e.has("palette"), "row lacks the item `palette` byte (icon CLUT key — round 49: the ROM CLUT selector IS rec[0] palette, renamed from `type`)")
		_expect(e.has("id"), "row lacks the item `id` (the ROM candidate identity)")
		_expect(e.has("name") and e.has("equipped") and e.has("owned"),
			"row lacks name/equipped/owned columns")
	# (b) the item ICON actually RENDERS now — one ITEM.BIN icon quad per row with graphic>0, sampled
	# from the extracted indexed sheet (assets/items/item_icons_index.tga) through the index→CLUT shader.
	var nonzero := 0
	for e in p.entries:
		if int(e.get("graphic", 0)) > 0:
			nonzero += 1
	_expect(p.icon_materials().size() == nonzero,
		"picker mounted %d ITEM.BIN icons, want %d (one per graphic>0 row)" % [p.icon_materials().size(), nonzero])
	_expect(p.icon_texture() != null, "picker has no ITEM.BIN icon sheet loaded")
	if p.icon_materials().size() > 0:
		var m: ShaderMaterial = p.icon_materials()[0]
		var cell: Vector4 = m.get_shader_parameter("cell")
		# row 0 = Broad Sword, graphic 12 (items.json / RAM rec[1], round 49 — the old default
		# graphic 2 was the round-35 mispairing) → cell (192,32,16,16), the live oracle prim.
		_expect(cell == Vector4(192, 32, 16, 16),
			"row-0 icon cell %s != icon_uv_for(12)=(192,32,16,16)" % cell)
	# (§15.26 b, round-36) per-type CLUT is WIRED: distinct item types resolve to distinct palettes,
	# and every icon material carries a palette (not a hardcoded single bank).
	if p.icon_materials().size() > 0:
		_expect(p.icon_materials()[0].get_shader_parameter("palette_tex") != null,
			"row-0 icon material has no per-type palette_tex")
	if p._item_palettes.size() >= 12:
		_expect(p._palette_for_type(0) != p._palette_for_type(6),
			"palette 0 and palette 6 must resolve to different CLUT textures")

	# (round 49) PER-ROW palette wiring — a non-zero-palette row samples its OWN CLUT bank
	# (closes the §15.26-b "palette 0 for all rows" deferral). Leather Hat: items.json palette 11
	# → CLUT 0x3FEB (live-proven on the Head picker); Broad Sword palette 0 → 0x3FA8.
	var p2 = EquipPickerMenu.new()
	p2.entries = [
		{"id": 157, "name": "Leather Hat", "equipped": 1, "owned": 1, "graphic": 90, "palette": 11, "wtype": 21},
		{"id": 19, "name": "Broad Sword", "equipped": 4, "owned": 4, "graphic": 12, "palette": 0, "wtype": 3},
	]
	add_child(p2)
	await get_tree().process_frame
	if p2.icon_materials().size() == 2:
		var hat_pal = p2.icon_materials()[0].get_shader_parameter("palette_tex")
		var sword_pal = p2.icon_materials()[1].get_shader_parameter("palette_tex")
		_expect(hat_pal != null and sword_pal != null and hat_pal != sword_pal,
			"per-row icon CLUT not wired: hat (palette 11) and sword (palette 0) share a palette_tex")
		var hat_cell: Vector4 = p2.icon_materials()[0].get_shader_parameter("cell")
		_expect(hat_cell == Vector4(0, 128, 16, 16),
			"Leather Hat icon cell %s != icon_uv_for(90)=(0,128,16,16) (live Head-picker prim)" % hat_cell)
	else:
		_expect(false, "custom 2-row picker mounted %d icons, want 2" % p2.icon_materials().size())
	if p2.type_glyph_materials().size() == 2:
		var hat_glyph: Vector4 = p2.type_glyph_materials()[0].get_shader_parameter("cell")
		_expect(hat_glyph == Vector4(152, 152, 12, 12),
			"Leather Hat type glyph %s != LUT[21 Hat]=(152,152,12,12) (live Head-picker prim)" % hat_glyph)
	p2.queue_free()

	# (round 49) SCROLL — the ROM picker window shows MAX 5 rows (16px pitch) and scrolls:
	# live-proven with 6 candidates (5 icon prims y147..211, the 6th reachable by scrolling;
	# DAT_801cd824 = TOTAL count, DAT_801cd54c = scroll). The port renders only the visible
	# window and keeps the cursor inside it.
	_expect(EquipPickerMenu.VISIBLE_ROWS == 5, "VISIBLE_ROWS != the ROM capacity 5")
	var p3 = EquipPickerMenu.new()
	p3.entries = []
	for i in 7:
		p3.entries.append({"id": 19 - i, "name": "Item %d" % i, "equipped": 0, "owned": 1,
			"graphic": 12 - i, "palette": 0, "wtype": 3})
	add_child(p3)
	await get_tree().process_frame
	_expect(p3.row_count() == 7, "7-entry picker row_count %d" % p3.row_count())
	_expect(p3.scroll() == 0, "fresh picker scroll %d != 0" % p3.scroll())
	_expect(p3.icon_materials().size() == 5,
		"7-entry picker mounted %d icons, want 5 (only the visible window renders)" % p3.icon_materials().size())
	_expect(p3.type_glyph_materials().size() == 5,
		"7-entry picker mounted %d glyphs, want 5 (visible window)" % p3.type_glyph_materials().size())
	# walk to row 4 (bottom of the window): no scroll yet; record the cursor's resting y.
	for i in 4:
		p3.move_down()
	_expect(p3.selected_row() == 4 and p3.scroll() == 0,
		"row 4 should not scroll yet (row %d scroll %d)" % [p3.selected_row(), p3.scroll()])
	var bottom_y := p3.cursor_display_pos().y
	# one more: row 5 enters — the window slides (scroll 1), the cursor STAYS on the bottom line.
	p3.move_down()
	_expect(p3.selected_row() == 5 and p3.scroll() == 1,
		"row 5 must scroll the window (row %d scroll %d)" % [p3.selected_row(), p3.scroll()])
	_expect(p3.cursor_display_pos().y == bottom_y,
		"scrolled cursor y %s != bottom-line y %s (cursor left the window)" % [p3.cursor_display_pos().y, bottom_y])
	_expect(p3.icon_materials().size() == 5, "scrolled picker still renders 5 icons")
	if p3.icon_materials().size() == 5:
		var first_cell: Vector4 = p3.icon_materials()[0].get_shader_parameter("cell")
		var want_cell := EquipPickerMenu.icon_uv_for(11)  # entries[1].graphic — the new top row
		_expect(first_cell == Vector4(want_cell.position.x, want_cell.position.y, 16, 16),
			"scrolled top row icon %s != entries[1] graphic 11 %s" % [first_cell, want_cell])
	# wrap: down past the end returns to row 0 with the window rewound...
	p3.move_down()
	_expect(p3.selected_row() == 6 and p3.scroll() == 2, "row 6 scroll 2, got %d/%d" % [p3.selected_row(), p3.scroll()])
	p3.move_down()
	_expect(p3.selected_row() == 0 and p3.scroll() == 0,
		"wrap to top must rewind the window (row %d scroll %d)" % [p3.selected_row(), p3.scroll()])
	# ...and up from row 0 wraps to the LAST row with the window at the tail.
	p3.move_up()
	_expect(p3.selected_row() == 6 and p3.scroll() == 2,
		"wrap to bottom must scroll to the tail (row %d scroll %d)" % [p3.selected_row(), p3.scroll()])
	p3.queue_free()

	# (a) type/class GLYPH — PER-TYPE cells (§15.28 round 47): the WORLD.BIN type→UV LUT (0x8018D7FC,
	# parsed into RANGETILE.json type_glyphs; page v == tga y) keyed by the row's item CLASS byte
	# (`wtype`). Live-prim proven: Broad Sword (type 3) → (104,128) 12×12; Mythril Knife/Dagger
	# (type 1) → (80,128) 12×12. The old fixed sword-on-every-row cell (64,0,16,13) is dead.
	_expect(p.type_glyph_materials().size() == p.entries.size(),
		"picker mounted %d type glyphs, want %d (one per row)" % [p.type_glyph_materials().size(), p.entries.size()])
	if p.type_glyph_materials().size() == 3:
		var want := [Vector4(104, 128, 12, 12), Vector4(80, 128, 12, 12), Vector4(80, 128, 12, 12)]
		for i in 3:
			var gcell: Vector4 = p.type_glyph_materials()[i].get_shader_parameter("cell")
			_expect(gcell == want[i],
				"row-%d type-glyph cell %s != per-type LUT cell %s" % [i, gcell, want[i]])
	# rows carry the class byte the glyph is keyed on.
	if p.entries.size() >= 1:
		_expect((p.entries[0] as Dictionary).has("wtype"),
			"row lacks the item CLASS byte `wtype` (glyph cell key)")

	# (d,e) COUNT column "NN/NN" (§15.27 round 46, issue #290): the digits sample the FRAME.BIN
	# BIG number strip (ROM prim U=0x78+8·d, v=1, 8×14, CLUT 0x7C3C → our extracted 8×16 cells),
	# while the bridging slash stays the SMALL set (ROM cell (180,16) 6×11 → extracted 6×10).
	# Round-35's all-SMALL reading of world_render_number_element 0x80127C34 is REFUTED.
	_expect(p.count_digit_materials().size() == 4 * p.entries.size(),
		"picker mounted %d count digits, want %d (2+2 per row)"
		% [p.count_digit_materials().size(), 4 * p.entries.size()])
	for dm in p.count_digit_materials():
		var dcell: Vector4 = dm.get_shader_parameter("cell")
		if not (dcell.z == 8.0 and dcell.w == 16.0 and dcell.y == 0.0):
			_expect(false, "count digit cell %s is not a BIG-set 8x16 cell (still SMALL?)" % dcell)
			break
	_expect(p.count_slash_materials().size() == p.entries.size(),
		"picker mounted %d count slashes, want %d (one per row)"
		% [p.count_slash_materials().size(), p.entries.size()])
	if p.count_slash_materials().size() > 0:
		var scell: Vector4 = p.count_slash_materials()[0].get_shader_parameter("cell")
		_expect(scell == Vector4(70, 17, 6, 10),
			"count slash cell %s != SMALL '/' (70,17,6,10)" % scell)

	# (f) the "Eqp."/"ALL" header mounts BAKED RANGETILE word cells (window_tabs "Eqp" 28,32 + "ALL"
	# 45,120) through the cream active-label CLUT 0x7CBC — the §15.19 mechanism, NOT FONT.BIN glyphs.
	_expect(EquipPickerMenu.HEADER_EQP_CELL == "Eqp" and EquipPickerMenu.HEADER_ALL_CELL == "ALL",
		"header cell names are not the window-tab 'Eqp'/'ALL' cells")
	_expect(p.header_cell_materials().size() == 2,
		"header mounted %d baked cells, want 2 (Eqp+ALL) — still FONT?" % p.header_cell_materials().size())
	if p.header_cell_materials().size() == 2:
		# mount order: [0]="Eqp" (28,32,18,10), [1]="ALL" (45,120,16,8). Cells come from RANGETILE.json.
		var eqp_cell: Vector4 = p.header_cell_materials()[0].get_shader_parameter("cell")
		var all_cell: Vector4 = p.header_cell_materials()[1].get_shader_parameter("cell")
		_expect(eqp_cell == Vector4(28, 32, 18, 10),
			"header 'Eqp' cell %s != window_tabs (28,32,18,10)" % eqp_cell)
		_expect(all_cell == Vector4(45, 120, 16, 8),
			"header 'ALL' cell %s != window_tabs (45,120,16,8)" % all_cell)
		_expect(p.header_cell_materials()[0].get_shader_parameter("index_atlas") != null,
			"header cell has no RANGETILE index_atlas — not the baked cream MECHANISM")

	# (f/GAP3) the item-list window uses the FFT brown-stripe frame chrome (UIFrame.STRIPE_SOURCE) —
	# the dark brown header stripe the cream cells sit on — NOT the flat menu-tile default (3,3,28,25).
	_expect(p.frame_source_region() == UIFrame.STRIPE_SOURCE,
		"picker frame source %s != brown-stripe STRIPE_SOURCE %s" % [p.frame_source_region(), UIFrame.STRIPE_SOURCE])
	p.queue_free()

	print("\n=== EquipPickerRowMechanismTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EquipPickerRowMechanismTest")
		get_tree().quit(1)
	else:
		print("[PASS] EquipPickerRowMechanismTest: ITEM.BIN icon UV formula + CLUT keys + row data")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
