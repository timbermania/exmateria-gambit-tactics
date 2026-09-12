class_name WorldMapStartMenu
extends Node2D
## The world map's START menu — WORLD.BIN window record 4 (WORLD_MAP_SCREEN.md §33).
##
## Six rows, opened with START or △, closed with ✕. Its geometry, row count, row pitch,
## cursor position, entry table and the six labels are all [b]read[/b] out of
## `model.json`'s `start_menu` block, which `tools/parse_world_map.py` derives from the
## disc — §33.10 point 1, *"the menu is data, a port should read it, not retype it"*.
## Nothing in this file names a row, a count or a pitch.
##
## [b]What is a parity claim here and what is not.[/b] §34.7–§34.11 established that the
## console's own menu box is a single `0x66` textured rect sampling VRAM (512,256) — a
## page nothing on the world-map path ever writes, holding zeros or an unrelated
## character strip in all 38 savestates in `reference-assets/`. [b]So there is no
## console-accurate pixel reference for the BOX[/b], and the nine-slice art and ink ramp
## below are SYNTHESIS from the port's own FFT window art, marked ⚠ at each site.
##
## [b]Everything else on this window is now a byte-check[/b], and the instrument is
## §33.9a's ordering-table dump of a menu-open savestate — seven primitives, printed in
## full in the document:
## [codeblock]
##   1  66808080 FFB0FF90 7C3C0000 00700048   the box    (-112,-80)  72x112
##   2  E1 tpage=005F                         VRAM (960,256), 4bpp, abr 2
##   3  66808080 FFBCFF86 7DBC00B8 00100010   glove shadow (-122,-68) uv(184,0) 16x16
##   4  SPRT     (-124,-70) 16x16 uv(168,0) clut=7D7C   glove LIT
##   5  66808080 FFAFFF93 7CBC7878 00080018   "Menu" tab  (-109,-81) uv(120,120) 24x8
## [/codeblock]
## Primitive 5 is the title tab and primitive 4 pins the cursor: `-124 = -112 − 12 + 0`
## and `-70 = -80 + 16·0 + 10`, so §33.2's unread `slide` is the glove BOB and it was 0 on
## that frame. Both are read straight off the console.
##
## What IS measured, and must stay exact:
##   • the rect      (-112, -80) 72 x 112, screen-centred (§4)   — record fields
##   • six rows      `rec+0x1E + 1`; FUN_800EBDCC wraps the cursor on that halfword
##   • row pitch     16 px, and cursor row r at `y = rec.y + 16r + 10` (FUN_800EC5B8)
##   • the wrap      down from the last row goes to 0, up from 0 goes to the last
##   • the entries   windows 6 / 7 / 11 / 14 / 12 / 5, one per row (FUN_800EBB08)
##   • the glove     its LIT layer's display top-left, at `rec + (-12, 10)` + bob
##   • the "Menu" tab  uv (120,120) 24x8 through CLUT 0x7CBC, at `rec + (3, -1)`
##
## Only row 0 (Move) is the map's own business — §33.10 point 3. The other five hand off
## to screens that are not the map's, and this class does not know what any of them are:
## it emits [signal chose] with the row and its WINDOW ID and stops there.

## The label ink, dark-on-tan — FRAME.BIN palette 0 entries 1 / 2 / 3, the same ramp
## [UIUnitNameplate] drives for every other FFT menu word in this project. The font atlas
## is baked as an OFF-WHITE ramp, so the mapping is INVERTED: the atlas's brightest level
## is the glyph BODY and becomes the darkest ink. ⚠ Synthesis — see the class note.
const INK_BODY := Color8(48, 40, 32)     # atlas (238,238,230)
const INK_MID := Color8(80, 80, 64)      # atlas (156,156,148)
const INK_EDGE := Color8(128, 120, 104)  # atlas (82,82,74)
## The three levels the font atlas actually contains (`font_atlas.tga` holds exactly four
## colours: these and a fully transparent key).
const ATLAS_BODY := Color8(238, 238, 230)
const ATLAS_MID := Color8(156, 156, 148)
const ATLAS_EDGE := Color8(82, 82, 74)

## The 9-slice window art, from [UIFrame]'s own constants — `assets/ui/frame.tga`
## (2,2) 29x26 with margins 4 / 4 / 5 / 4. [UIFrame] itself is a [Node3D] and cannot mount
## in this [Node2D] scene, so the region is re-baked here and handed to a [NinePatchRect].
## ⚠ Synthesis — see the class note.
const FRAME_TEXTURE := "res://assets/ui/frame.tga"
const FRAME_REGION := Rect2i(2, 2, 29, 26)
const FRAME_MARGIN_L := 4
const FRAME_MARGIN_R := 4
const FRAME_MARGIN_T := 5
const FRAME_MARGIN_B := 4

## FONT.BIN's narrow SPACE advance (`DialogueBox.SPACE_WIDTH_PX`), which the glyph table
## does not carry.
const SPACE_ADVANCE := 4

## The "Menu" title tab — §33.9a's primitive 5, field for field. It is the SAME cell and
## the SAME CLUT [StartActionMenu] draws for Formation's own START menu (`RANGETILE.json`
## `window_tabs` names it `Menu` at (120,120) 24x8, `clut: 31932` = 0x7CBC), which is not
## a coincidence: `FUN_800EC5B8` is one generic window driver and this is its title.
##
## Nothing here is synthesised. The texels are in the world map's own `vram.bin` (the
## FRAME.BIN band `parse_world_map.py` blits to (960,256)); the CLUT is too, since the
## extractor now also copies FRAME.BIN's CLUT tail to (960, 496+N) — verified byte for
## byte against the console's VRAM in two savestates. The tab pokes 1px ABOVE the box's
## top edge and 3px in from its left, exactly as Formation's does.
const TITLE_TAB_OFFSET := Vector2i(3, -1)
const TITLE_TAB_UV := Vector2i(120, 120)
const TITLE_TAB_SIZE := Vector2i(24, 8)
const TITLE_TAB_CLUT := 0x7CBC
## `E1 tpage=005F` — VRAM (960,256), 4bpp, abr 2 (B − F). The tab IS emitted as a `0x66`,
## i.e. with the semi-transparency bit set, and the abr word behind it is subtractive.
##
## [b]It still draws opaque, and that is a measurement rather than a shortcut.[/b] On the
## PSX, a semi-transparent TEXTURED primitive blends per TEXEL: the subtraction applies
## only where the resolved CLUT halfword sets bit 15 (STP), and every other texel is
## written straight. CLUT 0x7CBC sets STP on exactly two entries, 14 and 15 — and the
## "Menu" cell at (120,120) 24x8 uses indices 0, 1, 2, 3, 4 and 6, [b]none of them[/b].
## So no texel of this cell is ever blended and the quad is opaque in effect.
##
## That distinction is not academic here. [WorldMapRenderer] carries `semi` as a
## PER-PRIMITIVE flag — which is right for every cel on this screen, whose descriptors
## carry one blend byte each — so emitting this quad as `semi: true` makes Godot subtract
## the WHOLE tab, and the picture comes out INVERTED: the cream letterforms (entry 1,
## nearly white) subtract to black and the dark plate (entry 4) leaves the map showing
## through. That is what the first build of this did, and it is why [method _title_tab_quad]
## records `abr` faithfully and sets `semi` to false. `_check_title_tab` asserts the STP
## premise so the day a cell reaches entry 14 the guard says so instead of the picture.
const TITLE_TAB_TPAGE := 0x005F

## ⚠ Synthesis, and the last one on this window's layout. §33 never reads where the row
## labels sit inside the box, because the console rasterises them into a scratch page the
## port cannot see (§34.10). This is [b]not[/b] a free choice, though: it is
## [StartActionMenu]'s `ROW_TEXT_INSET_X`, framebuffer-measured on `formation_startmenu_ss1`
## for the SAME window driver, so it is a real number from a real screen — just not from
## this one. The widest label, `Brave Story` at 48 px, then ends at `rec.x + 57`, 15 px
## clear of the box's right edge.
static var label_inset_x: int = 9

## A row was taken. [param window] is the window id the entry table names for it — the
## console's `FUN_800EBB08` opens that record, and what each one IS is §33.3's table.
## Row 0 (window 6) is the Move list, the only one the map owns.
## This screen's name on the [code]Focus[/code] stack (ADR-0177). It is what
## [code]Focus.describe()[/code] prints, so it is this window's own name in every
## diagnostic. record 4's `+0x20 = 1`: one level over the map.
const FOCUS_STATE := "world_map_start_menu"


signal chose(row: int, window: int)
## ✕. The record's `+0x20` says one level, so this closes the menu and nothing else.
signal cancelled()
## The highlighted row changed — the caller repaints.
signal row_changed(row: int)

var record: Dictionary = {}
var row: int = 0

var _assets: WorldMapAssets
var _gen: WorldMapPrimitives
var _cursor_render: WorldMapRenderer
var _labels: Array[Sprite2D] = []
var _box: NinePatchRect
## The screen's vsync counter, pushed in by [method set_bob_frame].
var _bob_frame: int = 0

static var _glove_idle: Array = []


## Read the menu out of [param assets]' model and build it. False (and a push_error) when
## the model predates the `start_menu` block — regenerate with
## `uv run python tools/parse_world_map.py`.
func setup(assets: WorldMapAssets, gen: WorldMapPrimitives) -> bool:
	_assets = assets
	_gen = gen
	var m: Variant = assets.model.get("start_menu")
	if typeof(m) != TYPE_DICTIONARY or (m as Dictionary).is_empty():
		push_error("world map: model.json has no `start_menu` — "
				+ "run `uv run python tools/parse_world_map.py`")
		return false
	record = m
	row = int(record.get("persisted_row", 0))
	_build()
	return true


## The number of rows, which is `rec+0x1E + 1` and is not a constant anywhere — §33.2:
## *"that is where 'six rows' comes from — it is arithmetic on a disc byte, not a count
## of anything remembered."*
func rows() -> int:
	return int(record.get("rows", 0))


func label_of(r: int) -> String:
	var e: Array = record.get("entries", [])
	return String(e[r]["label"]) if r >= 0 and r < e.size() else ""


## The window id row [param r] opens.
func window_of(r: int) -> int:
	var e: Array = record.get("entries", [])
	return int(e[r]["window"]) if r >= 0 and r < e.size() else -1


## The box's top-left, in the screen-centred coordinates §4 defines.
func origin() -> Vector2i:
	return Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))


func size() -> Vector2i:
	return Vector2i(int(record.get("w", 0)), int(record.get("h", 0)))


## `FUN_800EC5B8`, exactly, for any window record this driver runs — the DISPLAY
## TOP-LEFT of the glove's lit layer on row [param r], with the bob already added:
## `x = rec.x − 12 + bob`, `y = rec.y + 16r + 10`. Both offsets are the record's own
## fields, so the place list gets the same formula by handing over its own record.
##
## §33.9a's primitive 4 is this at `r = 0, bob = 0`: `(-124, -70)` against a record at
## `(-112, -80)`. That also settles what §33.2's unread `slide` is — the BOB, not a
## constant, and the port had no business inventing one.
static func cursor_top_left(rec: Dictionary, r: int, bob_x: int) -> Vector2i:
	return Vector2i(
		int(rec.get("x", 0)) + int(rec.get("cursor_dx", 0)) + bob_x,
		int(rec.get("y", 0)) + int(rec.get("cursor_dy", 0))
			+ int(rec.get("row_pitch", 0)) * r)


## The same point as an ANCHOR for [method WorldMapPrimitives.cel_quads], which places a
## cel by its descriptor origin rather than by its art. Cel 0 IS the glove — part 0 at
## (-15,-3) is the shadow, part 1 at (-17,-5) the lit layer, a +2/+2 pair that is
## `StartActionMenu.CURSOR_SHADOW_DELTA` and that §33.9a's primitives 3 and 4 carry to the
## pixel — so the lit layer is the cel's own min corner and the conversion is exactly
## `anchor = top_left − cel_bounds.position`, i.e. `+ (17, 5)`.
static func cursor_anchor(assets: WorldMapAssets, rec: Dictionary, r: int,
		bob_x: int) -> Vector2i:
	var cel := assets.static_cel(WorldMapPrimitives.CURSOR_FRAME)
	return cursor_top_left(rec, r, bob_x) - assets.cel_bounds(cel).position


## The bob offset the glove is wearing right now, on X (`FUN_800EC504`, ADR-0046).
func bob_x() -> int:
	return glove_bob(_bob_frame)


## Where the cursor's cel is anchored for row [param r].
func cursor_at(r: int) -> Vector2i:
	return cursor_anchor(_assets, record, r, bob_x())


## Step the glove's bob to the screen's frame [param f] and repaint if it moved. The
## counter is [WorldMapScene]'s — one 60 Hz vsync clock for the whole screen (§21.3),
## because `FUN_800EC504` reads a free-running timer, not a per-window one.
func set_bob_frame(f: int) -> void:
	if f == _bob_frame:
		return
	var was := bob_x()
	_bob_frame = f
	if bob_x() != was:
		_place_cursor()


## `glove_idle`'s six `[threshold, offset]` pairs, out of WORLD.BIN `0x80156352` via
## `assets/sprites/cursor_bob.json` — the table the Formation port already parses and
## already consumes ([StartActionMenu], [JobPickerMenu]). Cached per class, because both
## windows on this screen bob and neither owns the table.
##
## [GloveCursorBob] and not `CursorBob`: ADR-0159 dec. 5 split that class in two on
## trunk, because the glove's bob and the TILE cursor's come from different encodings
## and different systems ([TileCursorBob] is Battlefield's ROM step/hold table). This
## menu wants the glove half — its three methods kept their `glove_` names through the
## split, so the repoint is the identifier and nothing else.
##
## `glove_select` (`0x80156362`, period 38) is the ON-CONFIRM animation and is deliberately
## NOT wired: this port has no confirm beat for it to belong to, and running it on a plain
## nav would be inventing a cadence §33 never read.
static func glove_bob(frame: int) -> int:
	if _glove_idle.is_empty():
		_glove_idle = GloveCursorBob.load_glove_pairs("glove_idle")
	return GloveCursorBob.glove_offset_for_frame(_glove_idle, frame)


## The bob's period, for anyone wrapping the counter.
static func glove_period() -> int:
	if _glove_idle.is_empty():
		_glove_idle = GloveCursorBob.load_glove_pairs("glove_idle")
	return GloveCursorBob.glove_period(_glove_idle)


## Move the highlight by [param d] rows, wrapping. `FUN_800EBDCC` reads `rec+0x1E`
## TWICE: up from row 0 lands on it, and down from it lands on 0. Returns true when the
## row actually changed (it always does while there is more than one row).
func move(d: int) -> bool:
	var n := rows()
	if n <= 0 or d == 0:
		return false
	var was := row
	row = posmod(row + d, n)
	if row == was:
		return false
	_place_cursor()
	row_changed.emit(row)
	return true


## ○ on the highlighted row.
func confirm() -> void:
	chose.emit(row, window_of(row))


func cancel() -> void:
	cancelled.emit()



## [b]Claim the input frame the moment this window mounts (ADR-0177).[/b] The screen
## pushes ITSELF, exactly as [WorldMapScene] does, because it is the live screen from
## the instant it enters the tree — the opener adds it as a child and that is the one
## creation path. Before this, [WorldMapScene._unhandled_input] dispatched here through
## an if-chain ordered by nullable precedence: a hand-rolled focus stack, which is the
## mechanism ADR-0177 replaces with the real one.
##
## There is no matching pop and that is deliberate — [code]Focus[/code] drops the frame
## on [signal Node.tree_exiting], which the opener's [code]remove_child[/code] fires. An
## [code]_exit_tree[/code] that popped as well would run AFTER that signal and pop a
## frame that is already gone, which [method Focus.pop] reports as the programming
## error it would be.
func _ready() -> void:
	Focus.push(FOCUS_STATE, self)


## Godot calls this only while this window holds focus — every other registered root is
## deafened by [code]set_process_*input(false)[/code], so the START menu cannot be reached
## from underneath. The map's own ✕ not firing while this is up is now true by
## construction rather than by an early [code]return[/code] in the map.
func _unhandled_input(event: InputEvent) -> void:
	# [b]The viewport is read BEFORE the dispatch, and that is not a style choice.[/b]
	# `handle_input` can emit `cancelled`, whose handler is the opener's `_close_*` —
	# which calls `remove_child(self)`. By the time it returns, this node is out of the
	# tree and `get_viewport()` is null, so marking the event handled on the way out
	# crashes with "Cannot call method 'set_input_as_handled' on a null value". Measured,
	# not predicted: it printed four times a run before this line existed, while the
	# suite stayed green — a SCRIPT ERROR is not an assertion failure.
	var vp := get_viewport()
	if handle_input(event) and vp != null:
		vp.set_input_as_handled()


## Route one input event. True when the menu consumed it — the caller then does nothing
## else with it, which is how the map's own cursor stays frozen while this is up.
##
## The opener is START [b]or[/b] △ (`andi 0x0810` at 0x8006CC64, §33.1) and is the
## CALLER's to watch: this object does not exist until the menu is open.
func handle_input(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event.is_action(&"ui_up"):
		move(-1)
		return true
	if event.is_action(&"ui_down"):
		move(1)
		return true
	if event.is_action(&"ui_cancel"):
		cancel()
		return true
	if event.is_action(&"ui_accept") or event.is_action(&"cursor_confirm"):
		confirm()
		return true
	return false


# ---------------------------------------------------------------- the picture

func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_labels.clear()

	var o := origin()
	var sz := size()

	_box = NinePatchRect.new()
	_box.texture = _frame_texture()
	_box.patch_margin_left = FRAME_MARGIN_L
	_box.patch_margin_right = FRAME_MARGIN_R
	_box.patch_margin_top = FRAME_MARGIN_T
	_box.patch_margin_bottom = FRAME_MARGIN_B
	# The centre is a 2px checker, not a flat fill — stretching it smears the weave.
	_box.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_box.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.position = Vector2(o)
	_box.size = Vector2(sz)
	add_child(_box)

	var font := UIFont.new()
	var pitch := int(record.get("row_pitch", 0))
	for r in rows():
		var tex := _bake_label(font, label_of(r))
		var s := Sprite2D.new()
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.texture = tex
		# ⚠ Synthesis. Six rows at pitch 16 fill 96 of the record's 112, so the row cell
		# is `rec.y + 8 + 16r`; the measured cursor anchor sits 2px into it. The glyph
		# cell's own ink starts ~2px down (UIMenuText.FONT_INK_TOP_PAD), so the cell top
		# goes on the cursor's row rather than 2px above it.
		s.position = Vector2(o.x + label_inset_x,
				cursor_top_left(record, r, 0).y - 2)
		add_child(s)
		_labels.append(s)

	# The cursor and the title tab go through the map's own renderer, so they are baked
	# from VRAM and blended by §13's rules like every other sprite on this screen. Cel 0
	# IS the glove §33.9a's primitives 3 and 4 draw — same two uv rects (168,0) and
	# (184,0), same +2/+2 offset — so "which cel the list driver uses" is answered rather
	# than assumed.
	_cursor_render = WorldMapRenderer.new()
	_cursor_render.setup(_assets)
	add_child(_cursor_render)
	_place_cursor()


## §33.9a's primitive 5, rebuilt as a primitive. It is drawn UNCLIPPED and pokes above the
## box's top edge — the same thing [StartActionMenu] documents for Formation's copy — so it
## goes in the same renderer as the cursor rather than inside the [NinePatchRect].
func _title_tab_quad() -> Dictionary:
	var o := origin() + TITLE_TAB_OFFSET
	var uv := TITLE_TAB_UV
	var wh := TITLE_TAB_SIZE
	return {
		"kind": "quad",
		"xy": [o, o + Vector2i(wh.x, 0), o + Vector2i(0, wh.y), o + wh],
		"uv": [uv, uv + Vector2i(wh.x, 0), uv + Vector2i(0, wh.y), uv + wh],
		"tpage": TITLE_TAB_TPAGE, "clut": TITLE_TAB_CLUT,
		# abr 2 is what the E1 word carries and is recorded as such; `semi` is FALSE
		# because no texel of this cell resolves to an STP entry, so nothing blends. See
		# TITLE_TAB_TPAGE for why the difference is visible rather than pedantic.
		"abr": 2, "semi": false, "rgb": WorldMapPrimitives.DEFAULT_RGB,
	}


func _place_cursor() -> void:
	if _cursor_render == null or _gen == null:
		return
	var prims: Array = [_title_tab_quad()]
	prims.append_array(_gen.cel_quads(
			_assets.static_cel(WorldMapPrimitives.CURSOR_FRAME), cursor_at(row)))
	_cursor_render.draw_primitives(prims)


## `frame.tga`'s 9-slice region, re-baked into a standalone texture in the console's
## channel space. [b]Everything drawn on this screen composites as `8 x` a 5-bit level[/b]
## and `psx_expand_555.gdshader` widens it once at the end of the frame — so an 8-bit
## asset dropped in raw would be read as a level 8x too bright and come back wrong. See
## [WorldMapRenderer]'s own note on the same rule.
static func _frame_texture() -> ImageTexture:
	var src := load(FRAME_TEXTURE) as Texture2D
	if src == null:
		push_error("world map: %s missing (a dangling worktree symlink looks like this "
				% FRAME_TEXTURE + "— see docs/WORKTREE_SETUP.md)")
		return null
	var img := src.get_image()
	var out := Image.create(FRAME_REGION.size.x, FRAME_REGION.size.y,
			false, Image.FORMAT_RGBA8)
	for y in FRAME_REGION.size.y:
		for x in FRAME_REGION.size.x:
			out.set_pixel(x, y, psx_levels(
					img.get_pixel(FRAME_REGION.position.x + x, FRAME_REGION.position.y + y)))
	return ImageTexture.create_from_image(out)


## One string, baked glyph by glyph into an [ImageTexture] — the same CPU bake
## [WorldMapRenderer] uses for the rest of the screen, and for the same reason: it goes
## through no importer and no colour-space question.
##
## [UIText] / [UIChar] are [Node3D]s and cannot mount here, so this uses [UIFont]'s DATA
## (the atlas and the per-glyph metrics) rather than the UI3 nodes.
static func _bake_label(font: UIFont, text: String) -> ImageTexture:
	var atlas: Image = font.atlas_texture.get_image() if font.atlas_texture != null else null
	if atlas == null:
		push_error("world map: the FONT.BIN atlas did not load")
		return null
	var w := measure(font, text)
	var h: int = font.char_height
	var img := Image.create(maxi(w, 1), h, false, Image.FORMAT_RGBA8)
	var pen := 0
	for ch in text:
		if ch == " ":
			pen += SPACE_ADVANCE
			continue
		var info := font.get_char_info(font.get_char_index(ch))
		var ax: int = int(info.get("atlas_x", 0))
		var ay: int = int(info.get("atlas_y", 0))
		var cw: int = int(info.get("width", font.char_width))
		for y in h:
			for x in cw:
				var ink := _ink_for(atlas.get_pixel(ax + x, ay + y))
				if ink.a > 0.0:
					img.set_pixel(pen + x, y, ink)
		pen += cw
	return ImageTexture.create_from_image(img)


## Width of [param text] under FONT.BIN's proportional advance.
static func measure(font: UIFont, text: String) -> int:
	var w := 0
	for ch in text:
		if ch == " ":
			w += SPACE_ADVANCE
		else:
			w += int(font.get_char_info(font.get_char_index(ch)).get("width", font.char_width))
	return w


## One atlas texel to its dark-on-tan ink, in the console's channels. The atlas holds
## exactly four colours, so this is an exact table rather than a nearest-colour search.
static func _ink_for(c: Color) -> Color:
	if c.a <= 0.0:
		return Color(0, 0, 0, 0)
	if c.is_equal_approx(ATLAS_BODY):
		return psx_levels(INK_BODY)
	if c.is_equal_approx(ATLAS_MID):
		return psx_levels(INK_MID)
	if c.is_equal_approx(ATLAS_EDGE):
		return psx_levels(INK_EDGE)
	return Color(0, 0, 0, 0)


## An 8-bit colour in the frame's own encoding: the GPU's 5-bit level, stored as `8 x`
## it, exactly as [WorldMapRenderer] bakes every CLUT entry. Alpha is untouched.
static func psx_levels(c: Color) -> Color:
	return Color(
		float((int(c.r * 255.0) >> 3) * WorldMapRenderer.LEVEL_SCALE) / 255.0,
		float((int(c.g * 255.0) >> 3) * WorldMapRenderer.LEVEL_SCALE) / 255.0,
		float((int(c.b * 255.0) >> 3) * WorldMapRenderer.LEVEL_SCALE) / 255.0,
		c.a)
