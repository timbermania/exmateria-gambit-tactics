extends Node
## The world map's START menu — [WorldMapStartMenu] against WORLD_MAP_SCREEN.md §33/§34.
##
## [b]What makes this a real check and not a tautology.[/b] Every number asserted below
## was measured on the console and written down in §33.2/§33.3 and §34.0–§34.2 —
## `round16_menu_rows.csv` drove the menu open with START and with △ and read the record's
## x / y / w / h / last_row / msg back out of RAM on each; `round17_debug_rows.csv` poked
## `rec+0x1E` from 5 to 8 and watched three more rows appear. The values the code sees
## come from the OTHER direction entirely: `tools/parse_world_map.py` reads WORLD.BIN's
## window record and EVENT/WORLD.LZW's text archive off the disc, with no savestate
## anywhere. A test that compared the extractor against itself would pass on any number;
## this one fails the moment either side moves.
##
## The one thing it deliberately does NOT assert is how the BOX looks. §34.7–§34.11
## established that the console's box samples a VRAM page nothing on this path ever
## writes, so there is no pixel oracle for it — see [WorldMapStartMenu]'s class note. What
## is checked here about the picture is only that it is WELL-FORMED: the labels bake from
## real glyphs rather than from the font's `?` fallback, and every baked texel lands in
## the console's 5-bit channels.
##
## [b]Everything else on the window IS asserted against the console[/b], out of §33.9a's
## seven-primitive ordering-table dump of a menu-open savestate: the glove's lit layer at
## `(-124,-70)` and the "Menu" title tab at `(-109,-81)`, uv (120,120) 24x8 through CLUT
## 0x7CBC. Those are packet fields, not a reading of a picture.
##
## Run: <GODOT> --path . --quit-after 12 res://tests/WorldMapStartMenuTest.tscn

## WORLD_MAP_SCREEN.md §33.2's record-4 table, and §33.3's six rows, transcribed from the
## DOCUMENT — i.e. from the console side of the derivation, not from the extractor.
const WANT_RECT := Rect2i(-112, -80, 72, 112)
const WANT_ROWS := 6
const WANT_PITCH := 16
const WANT_CURSOR_DX := -12
const WANT_CURSOR_DY := 10
const WANT_MSG := 0xA010
const WANT_HELP := 18
const WANT_CLOSE := 1
const WANT_WINDOWS := [6, 7, 11, 14, 12, 5]
const WANT_LABELS := ["Move", "Formation", "Brave Story", "Tutorial", "Data", "Option"]
## §34.0–§34.2: the entry table is nine long and the label string 0xA00F carries nine
## names, but `rec+0x1E` is 5. Debug / Flag / Party are windows 16 / 15 / 17.
const WANT_UNREACHABLE := [16, 15, 17]

## §33.9a's primitive 4 — `SPRT (-124,-70) 16x16 uv(168,0) clut=7D7C`, the glove's LIT
## layer, on row 0, on a frame whose bob was 0.
const WANT_CURSOR_TL_ROW0 := Vector2i(-124, -70)
## §33.9a's primitive 5 — `66808080 FFAFFF93 7CBC7878 00080018`: a semi-transparent
## textured rect at (-109,-81), uv (120,120), 24x8, CLUT 0x7CBC.
const WANT_TAB_XY := Vector2i(-109, -81)
const WANT_TAB_UV := Vector2i(120, 120)
const WANT_TAB_WH := Vector2i(24, 8)
const WANT_TAB_CLUT := 0x7CBC
## ...under `E1 tpage=005F` — VRAM (960,256), 4bpp, abr 2.
const WANT_TAB_TPAGE := 0x005F
## `glove_idle`, WORLD.BIN `0x80156352`: six `[threshold, offset]` pairs, period 46.
const WANT_BOB_PERIOD := 46

var _passed := 0
var _failed := 0
var _assets: WorldMapAssets
var _menu: WorldMapStartMenu


func _ready() -> void:
	_assets = WorldMapAssets.new()
	if not _assets.load_all():
		print("[FAIL] WorldMapStartMenuTest — assets: %s" % _assets.error)
		get_tree().quit(1)
		return
	_menu = WorldMapStartMenu.new()
	if not _menu.setup(_assets, WorldMapPrimitives.new(_assets)):
		print("[FAIL] WorldMapStartMenuTest — model.json has no start_menu block")
		get_tree().quit(1)
		return
	add_child(_menu)

	_check_record()
	_check_rows_come_from_the_disc_byte()
	_check_cursor_formula()
	_check_cursor_is_the_console_glove()
	_check_title_tab()
	_check_bob()
	_check_wrap()
	_check_wrap_follows_the_row_count()
	_check_labels_are_real_glyphs()
	_check_channels()
	_check_input()

	if _failed > 0:
		print("[FAIL] WorldMapStartMenuTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapStartMenuTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## §33.2's record 4, field for field.
func _check_record() -> void:
	_eq("box origin", _menu.origin(), WANT_RECT.position)
	_eq("box size", _menu.size(), WANT_RECT.size)
	_eq("row pitch", int(_menu.record["row_pitch"]), WANT_PITCH)
	_eq("cursor dx", int(_menu.record["cursor_dx"]), WANT_CURSOR_DX)
	_eq("cursor dy", int(_menu.record["cursor_dy"]), WANT_CURSOR_DY)
	_eq("label message id", int(_menu.record["label_msg"]), WANT_MSG)
	_eq("SELECT help topic", int(_menu.record["help_topic"]), WANT_HELP)
	_eq("levels closed on X", int(_menu.record["close_levels"]), WANT_CLOSE)
	for r in WANT_ROWS:
		_eq("row %d label" % r, _menu.label_of(r), WANT_LABELS[r])
		_eq("row %d window" % r, _menu.window_of(r), WANT_WINDOWS[r])
	# JSON has one number type, so the model's ints arrive as floats — compare as ints.
	var extra: Array = []
	for w in Array(_menu.record["unreachable_entries"]):
		extra.append(int(w))
	_eq("the three rows retail cannot reach", extra, WANT_UNREACHABLE)


## §33.2: *"that is where 'six rows' comes from — it is arithmetic on a disc byte, not a
## count of anything remembered."* So the record must carry `last_row`, and `rows()` must
## be that plus one rather than a literal.
func _check_rows_come_from_the_disc_byte() -> void:
	_eq("row count", _menu.rows(), WANT_ROWS)
	_eq("last_row is the halfword §34 poked", int(_menu.record["last_row"]), WANT_ROWS - 1)
	_eq("rows() == last_row + 1", _menu.rows(), int(_menu.record["last_row"]) + 1)
	# ...and the six labels and six entries are the SAME six, not two lists that happen
	# to be the right length.
	_eq("one entry per row", Array(_menu.record["entries"]).size(), _menu.rows())


## `FUN_800EC5B8`: `sll v1,row,4` / `addiu v1,v1,10`, on the glove's DISPLAY top-left.
func _check_cursor_formula() -> void:
	var o := _menu.origin()
	var x0 := WorldMapStartMenu.cursor_top_left(_menu.record, 0, 0).x
	for r in _menu.rows():
		var tl := WorldMapStartMenu.cursor_top_left(_menu.record, r, 0)
		_eq("cursor y at row %d" % r, tl.y, o.y + WANT_CURSOR_DY + WANT_PITCH * r)
		_eq("cursor x is row-independent at %d" % r, tl.x, x0)
		_eq("cursor x at row %d" % r, tl.x, o.x + WANT_CURSOR_DX)
	# Six rows at 16 is 96 of the record's 112 — §33.2 says so in as many words, and it
	# is the check that the pitch and the height belong to each other.
	_eq("six rows fit the record's height",
			WANT_PITCH * _menu.rows() <= _menu.size().y, true)
	# The bob is added on X and ONLY on X (`FUN_800EC504`'s result feeds the cursor x).
	var bobbed := WorldMapStartMenu.cursor_top_left(_menu.record, 3, 5)
	var still := WorldMapStartMenu.cursor_top_left(_menu.record, 3, 0)
	_eq("the bob moves the glove on X", bobbed.x - still.x, 5)
	_eq("...and not on Y", bobbed.y, still.y)


## §33.9a's primitives 3 and 4, which are the whole of §4 of this round's handoff: the
## console's glove sits 12 px LEFT of the box and 4 px inside it, and cel 0 IS that glove.
##
## A test that only asserted the formula would pass on the invented `slide` the file used
## to carry, because the formula was never the wrong half. What pins it is the ART: the
## anchor [method WorldMapStartMenu.cursor_at] hands to `cel_quads` has to put cel 0's LIT
## part back on `(-124,-70)`, which is a claim about the cel table AND the placement at
## once.
func _check_cursor_is_the_console_glove() -> void:
	var cel_id := _assets.static_cel(WorldMapPrimitives.CURSOR_FRAME)
	var cel := _assets.cel(cel_id)
	var parts: Array = cel.get("parts", [])
	_eq("the cursor cel has two parts (shadow + lit)", parts.size(), 2)
	if parts.size() != 2:
		return
	var shadow: Dictionary = parts[0]
	var lit: Dictionary = parts[1]
	_eq("part 1 is the LIT layer, uv (168,0)",
			Vector2i(int(lit["u"]), int(lit["v"])), Vector2i(168, 0))
	_eq("part 0 is the SHADOW, uv (184,0)",
			Vector2i(int(shadow["u"]), int(shadow["v"])), Vector2i(184, 0))
	_eq("the shadow is +2/+2 off the lit layer",
			Vector2i(int(shadow["x"]) - int(lit["x"]), int(shadow["y"]) - int(lit["y"])),
			Vector2i(2, 2))
	_eq("the lit layer is 16x16",
			Vector2i(int(lit["w"]), int(lit["h"])), Vector2i(16, 16))
	# ...and now the placement, at the bob the console frame carried.
	_menu.row = 0
	_menu.set_bob_frame(0)
	var anchor := WorldMapStartMenu.cursor_anchor(_assets, _menu.record, 0, 0)
	var lit_tl := anchor + Vector2i(int(lit["x"]), int(lit["y"]))
	_eq("the LIT glove lands where §33.9a's SPRT is", lit_tl, WANT_CURSOR_TL_ROW0)
	# 12 off the box, 4 on it — which is what makes the hand straddle the frame edge
	# rather than sit in the gutter beside the labels.
	var o := _menu.origin()
	_eq("the glove starts 12 px left of the box", o.x - lit_tl.x, 12)
	_eq("...and its 16 px run 4 px onto it", lit_tl.x + 16 - o.x, 4)


## §33.9a's primitive 5, field for field, as the port emits it.
func _check_title_tab() -> void:
	var q: Dictionary = _menu._title_tab_quad()
	var xy: Array = q["xy"]
	var uv: Array = q["uv"]
	_eq("the title tab's top-left", xy[0], WANT_TAB_XY)
	_eq("...is the record origin + (3,-1)", xy[0], _menu.origin() + Vector2i(3, -1))
	_eq("the title tab's size", xy[3] - xy[0], WANT_TAB_WH)
	_eq("the title tab's uv", uv[0], WANT_TAB_UV)
	_eq("...spans 24x8 texels", uv[3] - uv[0], WANT_TAB_WH)
	_eq("the title tab's CLUT", int(q["clut"]), WANT_TAB_CLUT)
	_eq("the title tab's tpage", int(q["tpage"]), WANT_TAB_TPAGE)
	_eq("...which is abr 2", int(q["abr"]), 2)
	# The console's command byte IS 0x66 (semi), but the PSX blends per TEXEL: only a
	# texel whose CLUT halfword sets STP (bit 15) is subtracted. So the quad draws opaque
	# iff no texel of the cell lands on an STP entry — assert THAT, and let the port's
	# per-primitive `semi` follow from it. Getting this backwards inverts the picture:
	# the cream letterforms subtract to black and the dark plate lets the map through.
	var stp_used := 0
	for dv in WANT_TAB_WH.y:
		for du in WANT_TAB_WH.x:
			var idx := _assets.texel(WANT_TAB_TPAGE,
					WANT_TAB_UV.x + du, WANT_TAB_UV.y + dv)
			if _assets.halfword((WANT_TAB_CLUT & 0x3F) * 16 + idx,
					(WANT_TAB_CLUT >> 6) & 0x1FF) >= 0x8000:
				stp_used += 1
	_eq("no texel of the 'Menu' cell carries STP", stp_used, 0)
	_eq("...so the port draws it opaque", bool(q["semi"]), false)
	# ...and 0x7CBC really does have STP entries, so the check above is not vacuous.
	var stp_entries := 0
	for i in 16:
		if _assets.halfword((WANT_TAB_CLUT & 0x3F) * 16 + i,
				(WANT_TAB_CLUT >> 6) & 0x1FF) >= 0x8000:
			stp_entries += 1
	_eq("CLUT 0x7CBC has two STP entries the cell never reaches", stp_entries, 2)
	# The CLUT has to BE in the world map's own vram.bin — it is the thing the extractor
	# did not use to copy, and a missing CLUT is 16 transparent entries, i.e. an invisible
	# tab that no assertion above would notice.
	var nonzero := 0
	for i in 16:
		if _assets.clut_levels(WANT_TAB_CLUT, i).w != 0:
			nonzero += 1
	_eq("CLUT 0x7CBC is resident in vram.bin (15 of 16 entries)", nonzero, 15)
	# ...and so do the texels. Index 0 is the transparent key here, so a blank cell would
	# be 24x8 of it.
	var ink := 0
	for dv in WANT_TAB_WH.y:
		for du in WANT_TAB_WH.x:
			if _assets.texel(WANT_TAB_TPAGE, WANT_TAB_UV.x + du, WANT_TAB_UV.y + dv) != 0:
				ink += 1
	_eq("the 'Menu' cell has ink (>= 100 of 192 texels)", ink >= 100, true)


## `FUN_800EC504` / ADR-0046: `t = timer % period`, then the offset of the FIRST pair
## whose threshold is strictly greater than `t`. The table is WORLD.BIN's, already parsed
## into `assets/sprites/cursor_bob.json` for the Formation port — this checks the world
## map reads THAT one and not a curve of its own.
func _check_bob() -> void:
	_eq("the idle table's period", WorldMapStartMenu.glove_period(), WANT_BOB_PERIOD)
	# The six pairs, sampled inside each threshold band.
	var want := {0: 0, 15: 0, 16: 1, 17: 1, 18: 2, 21: 2, 22: 3, 27: 3, 28: 2, 35: 2,
			36: 1, 45: 1}
	for f in want:
		_eq("bob at frame %d" % f, WorldMapStartMenu.glove_bob(f), int(want[f]))
	_eq("the bob wraps on its period",
			WorldMapStartMenu.glove_bob(WANT_BOB_PERIOD + 7),
			WorldMapStartMenu.glove_bob(7))
	# ...and it actually reaches the cursor.
	_menu.row = 0
	_menu.set_bob_frame(0)
	var at0 := _menu.cursor_at(0)
	# The table's peak: offsets run 0,1,2,3,2,1 over thresholds 16,18,22,28,36,46, so the
	# 3 band is `22 <= t < 28` and frame 28 is already back down to 2.
	_menu.set_bob_frame(27)
	var at3 := _menu.cursor_at(0)
	_eq("the glove moves 3 px right at the bob's peak", at3.x - at0.x, 3)
	_eq("...and not vertically", at3.y, at0.y)
	_menu.set_bob_frame(0)


## `FUN_800EBDCC` reads `rec+0x1E` twice: up from row 0 wraps to it, down from it to 0.
func _check_wrap() -> void:
	_menu.row = 0
	_menu.move(-1)
	_eq("up from row 0 wraps to the last", _menu.row, _menu.rows() - 1)
	_menu.move(1)
	_eq("down from the last wraps to 0", _menu.row, 0)
	_menu.move(1)
	_eq("down from 0 is row 1", _menu.row, 1)
	_menu.row = 0


## §34.0: poking `rec+0x1E` from 5 to 8 made rows 6..8 reachable and the cursor wrapped on
## EIGHT. If the wrap were a literal 6 this would still pass at the default and fail here,
## which is the point — the ratchet has two arms.
func _check_wrap_follows_the_row_count() -> void:
	var poked := WorldMapStartMenu.new()
	poked.record = _menu.record.duplicate(true)
	poked.record["rows"] = 9
	poked.record["last_row"] = 8
	poked.row = 8
	poked.move(1)
	_eq("with rec+0x1E poked to 8, down from row 8 wraps to 0", poked.row, 0)
	poked.move(-1)
	_eq("...and up from row 0 wraps to 8", poked.row, 8)
	poked.free()


## The §2 decision's premise, mechanised: FONT.BIN carries every character of all six
## labels. A missing glyph does NOT throw — [UIFont.get_char_index] silently substitutes
## `?` — so the failure this guards against is six labels that render as punctuation.
func _check_labels_are_real_glyphs() -> void:
	var font := UIFont.new()
	var qmark := font.get_char_index("?")
	for r in _menu.rows():
		var text := _menu.label_of(r)
		_eq("row %d label is not empty" % r, text.is_empty(), false)
		var all_real := true
		for ch in text:
			if ch != "?" and font.get_char_index(ch) == qmark:
				all_real = false
		_eq("every glyph of %s is in FONT.BIN" % text, all_real, true)
		_eq("%s measures > 0 px" % text,
				WorldMapStartMenu.measure(font, text) > 0, true)
	# The widest label has to fit the record's own width, or the box the disc describes
	# cannot hold the labels the disc describes — which would mean one of them is wrong.
	var widest := 0
	for r in _menu.rows():
		widest = maxi(widest, WorldMapStartMenu.measure(font, _menu.label_of(r)))
	_eq("the widest label fits the record's width (%d px)" % widest,
			WorldMapStartMenu.label_inset_x + widest <= _menu.size().x, true)
	# ...and it must not run under the glove either, which is the fault §4 of the round-18
	# handoff describes: the labels had been pushed right to clear a cursor that had been
	# fitted ONTO the box instead of straddling its edge.
	_eq("the labels start inside the box",
			WorldMapStartMenu.label_inset_x > 0, true)


## Everything on this screen composites as `8 x` a 5-bit level and is widened ONCE by
## `psx_expand_555.gdshader` (§13 / [WorldMapRenderer]). A baked texel that is not a
## multiple of 8 is a colour the expansion pass will read a whole level wrong.
func _check_channels() -> void:
	for c in [Color8(255, 255, 255), Color8(48, 40, 32), Color8(0, 0, 0),
			Color8(160, 152, 128), Color8(7, 7, 7)]:
		var q := WorldMapStartMenu.psx_levels(c)
		var ok := true
		for v in [q.r8, q.g8, q.b8]:
			if v % WorldMapRenderer.LEVEL_SCALE != 0 or v > 248:
				ok = false
		_eq("psx_levels(%s) is 8 x a 5-bit level" % c.to_html(false), ok, true)
	_eq("alpha survives quantisation",
			WorldMapStartMenu.psx_levels(Color(1, 1, 1, 0)).a, 0.0)


func _check_input() -> void:
	var seen := {"chose": -1, "window": -1, "cancelled": 0}
	_menu.chose.connect(func(r: int, w: int) -> void:
		seen["chose"] = r
		seen["window"] = w)
	_menu.cancelled.connect(func() -> void: seen["cancelled"] += 1)

	_menu.row = 0
	_eq("ui_down is consumed", _menu.handle_input(_action(&"ui_down")), true)
	_eq("...and moved the row", _menu.row, 1)
	_eq("ui_up is consumed", _menu.handle_input(_action(&"ui_up")), true)
	_eq("...and moved it back", _menu.row, 0)
	_eq("cursor_confirm is consumed",
			_menu.handle_input(_action(&"cursor_confirm")), true)
	_eq("...and chose row 0", seen["chose"], 0)
	_eq("...whose window is the entry table's", seen["window"], WANT_WINDOWS[0])
	_eq("ui_cancel is consumed", _menu.handle_input(_action(&"ui_cancel")), true)
	_eq("...and cancelled once", seen["cancelled"], 1)
	# The map's own opener must NOT be swallowed by the open menu as something else.
	_eq("an unrelated action is not consumed",
			_menu.handle_input(_action(&"ui_right")), false)
	# §33.1's opener is a separate action from Formation's — a missing one would make the
	# menu unopenable, and `is_action` on an absent action is a silent false.
	_eq("world_map_start_menu is in the input map",
			InputMap.has_action(&"world_map_start_menu"), true)
	_eq("...and it is not formation's",
			InputMap.has_action(&"formation_start_menu"), true)


func _action(name: StringName) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = true
	return e


func _eq(what: String, got: Variant, want: Variant) -> void:
	if typeof(got) == typeof(want) and got == want:
		_passed += 1
		return
	_failed += 1
	print("  [x] %s: got %s, want %s" % [what, got, want])
