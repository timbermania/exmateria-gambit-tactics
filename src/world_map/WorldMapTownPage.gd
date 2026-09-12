class_name WorldMapTownPage
extends Node2D
## The screen you get by pressing ○ while standing on a town — WORLD_MAP_SCREEN.md §35.
##
## The location painting, its subtractive drop shadow, the node's name plate, and the
## Bar / Shop / Soldier office list. Five elements, and §35 reads four of them off the
## console packet for packet.
##
## [b]It is the map's OWN screen, not a hand-off.[/b] `FUN_8006FAF0(node)` pushes WLDCORE
## page mode 4 and the map keeps drawing underneath — §35.8 shows the picture and shadow
## built in `WLDCORE`'s own packet pools, the same pools as the map background and the
## travel path, with only the list panel coming from a `WORLD.BIN` chain. So this mounts
## in [WorldMapScene]'s holder beside [WorldMapStartMenu] and [WorldMapPlaceList], and the
## background, the aperture, the date and the war funds all stay up behind it. That is
## visible in `images/round18_town_frame.png` and is the reason this is not a
## [signal WorldMapScene.node_entered] subscriber: entering a BATTLEFIELD is Campaign's
## business, entering a TOWN is the map's.
##
## [b]What is measured and must stay exact[/b] — all of it from the model, none retyped:
## [codeblock]
##   the picture   one 0x64 rect, screen-centred (-64,-76) 120x80        §35.6
##   the shadow    cel 15 (frame 11) at (-8,16): 28 quads, abr 2         §35.7
##   the plate     the node's OWN name cel, at the picture's centre x    §35.6 + §9
##   the box       a nine-patch spanning x -42..34, y 8..84              §35.8
##   the rows      FUN_8008D2C8's rules, and the pitch is 16             §35.10
## [/codeblock]
##
## [b]Draw order is not the packet dump's order.[/b] §35.0 lists the picture rect ahead of
## the 28 shadow quads, which is CHAIN order; the shadow is UNDER the picture. §35.9's
## own re-render is the proof — it replays the 28 quads against the framebuffer while
## skipping the picture rect and the panel, *"drawn over the shadow"*, and reaches
## 99.933%. So this emits shadow → picture → plate → box → rows → glove.
##
## [b]The box and the rows used to be synthesis. §37 ended both.[/b] The console's box
## samples tpage `0x0407` = VRAM (448,0) — art `vram.bin` does not hold — so the first
## build borrowed [WorldMapStartMenu]'s FLAT crop and the START menu's row inset. Both
## were wrong by eye, and both are now measured: §37.2 traces all nine slices back to
## `EVENT/FRAME.BIN` rects (see [constant PANEL_TILES]) through the console's own CLUT,
## and §37.3 decodes the rows' scratch strip at VRAM (576,256) and reads their ink
## directly (see [constant ROW_INK_XY]). The one thing still synthesised on this screen
## is the GLYPH shapes — the port's FONT.BIN bake, not the console's rasterised strip.
##
## [b]What this deliberately does not do.[/b] Follow a row. The Bar pushes WLDCORE page
## mode 5; Shop / Soldier office / Fur shop are one blocking call into `WORLD.BIN` with a
## different selector, `FUN_80133478(0 / 0x65 / 0x64)` — which §36 then read as ONE
## 28-entry state machine entered at three different states (0, 14, 20), sharing a single
## teardown at state 13. Three more screens and their own rounds. This surfaces the choice
## through [signal chose] and stops, which is what §35.9's *"1 push, 3 blocking calls"*
## leaves a port able to say.
##
## Vault: [[World Map Screen]]

## §37.2. The panel's OWN window art, and it is on the disc.
##
## [b]The box was the wrong frame.[/b] It used to borrow [WorldMapStartMenu]'s crop —
## `frame.tga` (2,2) 29x26, margins 4/4/5/4, the FLAT menu tile — against a console box
## that is not flat at all: it carries an olive header bar under its top edge and a
## matching footer bar above its bottom one. That was recorded as synthesis because the
## console samples tpage `0x0407` = VRAM (448,0), which `vram.bin` does not hold.
##
## §37 found it. The nine `0x66` rects each carry their OWN `GP0(E2)` texture window (the
## second word of the `DR_MODE` packet the old dump read as a bare `DR_TPAGE`), so the
## five slices that looked like they all sampled `uv (0,0)` were each TILING a different
## 8x16 or 16x16 patch — and every one of those patches is byte-identical to a rect of
## `EVENT/FRAME.BIN`, which `tools/parse_frame.py` already decodes to `frame.tga` through
## FRAME.BIN palette 0 = the console's own CLUT `0x7C3C`. So nothing here is synthesis
## any more; it is the console's art at the console's addresses.
##
## Source rects in `frame.tga`, each proven by a 16-row strided byte match against the
## VRAM band of `world_map_ss4_town_menu_open` (§37.2's table):
## [codeblock]
##   TL (216, 0) 8x16   top (224, 0) 16x16   TR (240, 0) 8x16
##   L  (  0, 8) 8x16   body(  8, 8) 16x16   R  ( 24, 8) 16x16
##   BL (216,16) 8x16   bot (224,16) 16x16   BR (240,16) 8x16
## [/codeblock]
## They are not contiguous on the sheet — the top and bottom bands come from the small
## banded prototype box at (218,3) (the same rect [UIFrame.STRIPE_SOURCE] names), the
## middle band from the tall flat box at (0,8) — so [method _panel_texture] packs them
## into one 32x48 nine-slice in the layout a [NinePatchRect] wants.
## §38. The OPEN transition — four animations on three clocks, and an instant close.
##
## The settled frame this file draws is §37's, and it is pixel-exact. It also used to be
## the FIRST frame: the page popped. §38 watched the ~30 vsyncs before it on the console,
## per primitive, and they are four separate animations that do not share a clock:
## [codeblock]
##   frames  0..8    the picture opens          a centre-out CLIP reveal, 5 percents
##   frames  0..19   black -> normal            level += 7, clamped at 128
##   frames  0..19   the drop shadow fades in   ...the SAME ramp, the same instruction
##   frames 21..29   the menu opens             the panel's SCISSOR, 5 percents
## [/codeblock]
## The last one starts only after the first three finish — measured, both on the console
## and here: the panel's chain is not linked until the ramp has disarmed.
##
## [b]Both apertures are clip reveals, and that is the part worth not getting wrong.[/b]
## The picture's rect shrinks and its uv insets by exactly the same amount, so what you
## see is the middle of the painting at 1:1 — never a squashed one. The panel is a
## scissor: its nine slices are emitted at their SETTLED size on every frame from the
## first, and only the clip grows. A centre-out geometry scale would crush the corner art
## of a nine-patch, and the console never does that (§38.7).
const OPEN_APERTURE_P: Array[int] = [20, 50, 80, 90, 100]
## §38.1. `FUN_8006B678` is five literal `ori`s and this arithmetic — and the divisor is
## [b]200[/b], not 100: `0x8006B6F8` loads `0x51EB851F` and `0x8006B72C` is `sra v0,t1,6`,
## and `2**38 / 0x51EB851F == 200`. The same constant with `sra 5` is the familiar
## divide-by-100; reading it that way doubles every width and misses all ten measured
## numbers. The `& ~3` lands on the HALF, so the drawn size snaps to a multiple of 8 —
## which is why p=50 gives 56 and not 60, and p=90 gives 104 and not 108.
##
## Returns `(inset, size)`: the rect is drawn `inset` in from its settled left/top, `size`
## wide, [b]and the uv insets by that same `inset`[/b].
static func aperture(full: int, p: int) -> Vector2i:
	var half := (full >> 1) & ~3
	var scaled := ((full * p) / 200) & ~3
	return Vector2i(half - mini(half, scaled), mini(half, scaled) * 2)

## §38.1. `0x8006B354/60` pass `counter >> 1`, so every percent is held for two vsyncs,
## and `0x8006B3C8 slti v0,v0,4` ends it — steps 0,0,1,1,2,2,3,3,4.
const OPEN_APERTURE_VSYNCS := 9
## §38.3. `0x80070488 addiu v0,v1,7`, clamped at 128 — the neutral PSX gouraud level, and
## the same [constant WorldMapPrimitives.DEFAULT_RGB] the settled frame carries.
const OPEN_RAMP_STEP := 7
## §38.4. The page opener zeroes the cel rgb (`0x8006FC4C/50/54 sb zero`) before anything
## draws, so the first frame is [b]literally black[/b] — the user's "it doesn't fade in
## from nowhere, it starts black" is that `sb zero`, not a curve.
const OPEN_RAMP_VSYNCS := 19
## §38.0. Measured: the page is pushed on console vsync 58 and the panel's chain is first
## linked on 79. The ramp disarms at 77, so the gap is the ramp plus two frames of
## bookkeeping. ⚠ The two frames are a MEASUREMENT, not a mechanism — §38.11 leaves what
## actually triggers the window open unread.
const OPEN_PANEL_DELAY := 21
## §38.7. `world_menu_open_curve @0x801533B8`, read one index per vsync — the doubled
## entries are why each step lasts two frames. The port carries the nine that matter; the
## console's table pads to twelve with 100s.
const OPEN_PANEL_CURVE: Array[int] = [10, 10, 60, 60, 90, 90, 95, 95, 100]
## The whole transition, in vsyncs. Past this the page is the settled §37 frame.
const OPEN_VSYNCS := OPEN_PANEL_DELAY + 9

## §37.1 — the `WORLD.BIN` window ELEMENT the scissor is derived from, and it is [b]not[/b]
## [method size].
##
## The drawn box is 76x76 (`record.box.wh`, the nine-patch's own extent), but the console's
## element — and therefore its `DR_AREA` — is [b]84[/b] wide: §37.1 found the 16-wide right
## slice against 8-wide corners and showed the extra 8 columns are index 0 on all 16 rows,
## so the element is widened to give that rect room and paints nothing with it. The
## aperture scales the ELEMENT, so the clip has to as well; deriving it from the 76 makes
## every step ~10% narrow and the box finishes 8px short of where the console leaves it.
const PANEL_ELEM_WH := Vector2i(84, 76)

const PANEL_TEXTURE := "res://assets/ui/frame.tga"
## `frame.tga` rects, in the packed atlas's own order: TL, top, TR, L, body, R, BL, bot, BR.
const PANEL_TILES: Array[Rect2i] = [
	Rect2i(216, 0, 8, 16), Rect2i(224, 0, 16, 16), Rect2i(240, 0, 8, 16),
	Rect2i(0, 8, 8, 16), Rect2i(8, 8, 16, 16), Rect2i(24, 8, 8, 16),
	Rect2i(216, 16, 8, 16), Rect2i(224, 16, 16, 16), Rect2i(240, 16, 8, 16),
]
## The packed atlas: three 16-tall bands of 8 + 16 + 8 texels.
const PANEL_ATLAS_WH := Vector2i(32, 48)

## The 9-slice margins, and they are [b]not[/b] the 4/4/5/4 the flat tile used.
##
## §37.1 read the slice rects straight off the ss4 display list: corners 8x16, top and
## bottom edges 60x16, left edge 8x44, right edge 16x44, centre 60x44 — so the lattice is
## left 8 / top 16 / bottom 16, and the RIGHT slice is 16 wide of which the outer 8 texels
## are index 0. Painting it or not paints the same pixels (the ink stops at x 33 either
## way), so the port's right margin is 8 and the box is the 76x76 the model records.
##
## [b]The header is IN the top edge.[/b] `images/round18_town_frame.png`'s olive bars are
## not a separate primitive and not a title tab: rows 3..11 of the top-edge tile are
## outline / bevel / three rows of olive / tan / olive / outline / bevel, and rows 1..8 of
## the bottom-edge tile are its mirror. Nine rects draw the whole chrome.
const PANEL_MARGIN_L := 8
const PANEL_MARGIN_R := 8
const PANEL_MARGIN_T := 16
const PANEL_MARGIN_B := 16

## §37.3. Where a row's INK lands, MEASURED — this used to be the round's last synthesis.
##
## The console rasterises the three labels into a VRAM scratch strip and blits them as one
## `0x66` rect, so §35.8 could not say where inside the box a row sits. It can now: decode
## the strip through its own texture window and the ink is there to read. All three rows
## start at x [b]-30[/b] (= the box origin + 12, not the borrowed +9), and their ink tops
## are y 24 / 40 / 56 — pitch 16, the same pitch the glove already used.
##
## [codeblock]
##   Bar             y 24..32   x -30..-17
##   Shop            y 40..50   x -30..-13     (the p descender is the 11th row)
##   Soldier office  y 56..64   x -30.. 21
## [/codeblock]
const ROW_INK_XY := Vector2i(-30, 24)
## FONT.BIN's cap glyphs begin 2 rows down inside their cell, so the cell top is the ink
## top minus 2 — the same relation [WorldMapStartMenu] uses, applied to a measured ink.
const ROW_CELL_INK_DY := 2

## §35.6. The picture rect, screen-centred, and its centre — which is where the name
## plate is anchored (`-64 + 120/2 = -4`, and the console's plate quad is at x -4).
const PICTURE_XY := Vector2i(-64, -76)
const PICTURE_WH := Vector2i(120, 80)

## A row was taken. [param leads_to] is §35.9's reading of where it goes, verbatim from
## the model: `{"kind": "wldcore_page_mode", "arg": 5}` for the Bar, or
## `{"kind": "world_bin_screen", "arg": 0 | 0x65 | 0x64}` for the other three.
##
## [b]A report, not a mount[/b] — the same shape as [signal WorldMapScene.node_entered]
## and for the same reason. Nothing this port has can show any of the four.
## This screen's name on the [code]Focus[/code] stack (ADR-0177). It is what
## [code]Focus.describe()[/code] prints, so it is this window's own name in every
## diagnostic. §35: WLDCORE page mode 4 is a PAGE PUSH, so the windows the map had up are closed
## by the opener before this mounts — this frame sits directly on the map's.
const FOCUS_STATE := "world_map_town_page"


signal chose(row: int, msg: int, label: String, leads_to: Dictionary)
## ✕. The page closes and the map is back.
signal cancelled()
## The highlighted row moved — the caller repaints if it cares.
signal row_changed(row: int)

var record: Dictionary = {}
## The rows this node actually gets, in `FUN_8008D2C8`'s order. Each is the model's own
## row dictionary (`msg`, `label`, `leads_to`), or a Deep Dungeon floor.
var rows_for_node: Array = []
var row: int = 0
var node_1based: int = 0

var _assets: WorldMapAssets
var _gen: WorldMapPrimitives
var _progress: WorldMapProgress
var _back: WorldMapRenderer
var _front: WorldMapRenderer
var _box: NinePatchRect
var _labels: Array[Sprite2D] = []
var _bob_frame: int = 0
## Vsyncs since the page was pushed, or [constant OPEN_VSYNCS] for "settled".
##
## [b]It starts settled on purpose.[/b] [method setup] builds the §37 frame, every
## existing caller and every settled-frame assertion keeps the numbers it already has,
## and the animation is opt-in through [method begin_open]. A page that animated by
## default would make every one of those assertions read a frame nobody asked it about.
var _open_frame: int = OPEN_VSYNCS
var _clip: Control = null


## Build the page for [param node]. False (and a push_error) when the model predates the
## `town` block, or when the node does not open one — [b]the caller must not have to
## know which nodes do[/b], so the gate lives here and is [method opens_for].
func setup(assets: WorldMapAssets, gen: WorldMapPrimitives, progress: WorldMapProgress,
		node: int) -> bool:
	_assets = assets
	_gen = gen
	_progress = progress
	node_1based = node
	var m: Variant = assets.model.get("town")
	if typeof(m) != TYPE_DICTIONARY or (m as Dictionary).is_empty():
		push_error("world map: model.json has no `town` — "
				+ "run `uv run python tools/parse_world_map.py`")
		return false
	record = m
	if not opens_for(assets, node):
		return false
	rows_for_node = rows_for(assets, progress, node)
	row = 0
	_build()
	return true


## Whether ○ on [param node] opens this page at all.
##
## [b]The gate is the node KIND, and it is NOT "does the node have a picture".[/b] 19
## nodes carry a picture and 16 open a list: Murond Holy Place, Orbonne Monastery and
## Bethla Garrison have a picture and no menu. Gating on the picture gives all three a
## screen the console does not give them.
##
## ⚠ [b]Open, and §35 does not close it.[/b] Whether those three show a bare picture with
## no list, or nothing at all, was never watched — `FUN_8008D2C8` returns 0 rows for them
## and what mode 4 does with an empty list is unread. This port does nothing, which
## matches the handoff's reading (*"the 27 nodes that should do nothing"*) and is the
## conservative half. The instrument to settle it is a driven ○ while standing on node
## 16, 18 or 21; none of the three savestates in `reference-assets/` is on one.
static func opens_for(assets: WorldMapAssets, node: int) -> bool:
	if node < 1 or node > assets.nodes().size():
		return false
	return bool(assets.node(node - 1).get("opens_menu", false))


## `FUN_8008D2C8(node, out)`, as RULES rather than as a list — §35.10:
## [codeblock]
##   if node == 22:                              /* Deep Dungeon, tested FIRST */
##       n = var[101] + 1                        /* a WORD: the floor counter */
##       return [0xB8ED + i for i in range(n)]
##   if node_record[node].byte3 != 1: return []  /* not a town */
##   rows = [Bar, Shop, Soldier office]
##   if var[144] and node in (9, 12, 14): rows.append(Fur shop)
## [/codeblock]
##
## [b]The two gates differ in KIND and §27.4 says so by STORAGE, without knowing what
## either gates[/b]: the variable store is words at 0..127, bits at 128..863 and nibbles
## at 864..1023, so `101` is a counter and `144` is a flag. The model carries that as
## `var_kind` and this reads `101` as a count and `144` as a truth value accordingly —
## which is why a save with `var[101] = 3` gives four floors rather than one row.
##
## Nodes are 1-BASED here and 0-based in `FUN_8008D2C8`; the model's `nodes` list is the
## console's, so the conversion happens once, at the lookup.
static func rows_for(assets: WorldMapAssets, progress: WorldMapProgress,
		node: int) -> Array:
	var town: Dictionary = assets.model.get("town", {})
	if town.is_empty() or node < 1:
		return []
	var dd: Dictionary = town["deep_dungeon"]
	if node - 1 == int(dd["node"]):
		var floors: Array = dd["floors"]
		var n := progress.vars.get_var(int(dd["count_var"])) + 1
		return floors.slice(0, clampi(n, 0, floors.size()))
	if int(assets.node(node - 1).get("kind", 0)) != int(town["kind_town"]):
		return []
	var out: Array = []
	for r in (town["rows"] as Array):
		var gate: Variant = (r as Dictionary).get("gate")
		if gate == null:
			out.append(r)
			continue
		var g: Dictionary = gate
		if progress.vars.get_var(int(g["var"])) == 0:
			continue
		# ⚠ `(node - 1) in g["nodes"]` is FALSE here even when the node is on the list.
		# `JSON.parse_string` hands back every number as a [float], so the gate reads
		# `[9.0, 12.0, 14.0]`, and Array `in` compares variants by TYPE as well as by
		# value — `9 in [9.0]` is false. Written that way this row never appears, at any
		# of the three towns, and nothing else on the screen changes to say so.
		if not _has_int(g["nodes"] as Array, node - 1):
			continue
		out.append(r)
	return out


func rows() -> int:
	return rows_for_node.size()


func label_of(r: int) -> String:
	return String(rows_for_node[r]["label"]) if r >= 0 and r < rows() else ""


## The box's top-left and size, screen-centred — §35.8's nine-patch extent.
func origin() -> Vector2i:
	return _v(record["box"]["xy"])


func size() -> Vector2i:
	return _v(record["box"]["wh"])


## The glove's LIT top-left on row [param r], with the bob added.
##
## [b]Not [method WorldMapStartMenu.cursor_top_left].[/b] That is `FUN_800EC5B8`'s
## formula on a `WORLD.BIN` window record, and this window is not one of the 18 — none of
## them is at (-42,8) 76x76, and applying the formula to this box lands at (-54,18)
## where the console is at (-51,22). This page is WLDCORE's own mode 4 with its own
## driver, so the anchor is MEASURED instead: the glove's lit quad reads (-51,22) on the
## row-0 savestate and (-52,54) on the row-2 one, which fixes both the origin and the
## pitch. The 1px of x between them is the bob, not a second unknown.
func cursor_top_left(r: int) -> Vector2i:
	return _v(record["box"]["cursor_xy"]) + Vector2i(
			bob_x(), int(record["box"]["row_pitch"]) * r)


## The same point as a cel ANCHOR — cel 0's lit layer is its own min corner, so the
## conversion is `top_left − cel_bounds.position`, exactly as the START menu's is.
func cursor_at(r: int) -> Vector2i:
	var cel := _assets.static_cel(WorldMapPrimitives.CURSOR_FRAME)
	return cursor_top_left(r) - _assets.cel_bounds(cel).position


func bob_x() -> int:
	return WorldMapStartMenu.glove_bob(_bob_frame)


## Row [param r]'s label cell top-left — §37.3's measured ink, minus the glyph's own
## 2-row top bearing. No bob: the glove wobbles on X, the text does not move at all.
func row_cell_top_left(r: int) -> Vector2i:
	return ROW_INK_XY + Vector2i(0, int(record["box"]["row_pitch"]) * r
			- ROW_CELL_INK_DY)


## The nine `frame.tga` rects of [constant PANEL_TILES], packed into the 32x48 layout a
## [NinePatchRect] wants: three 16-tall bands of 8 + 16 + 8 texels.
##
## The right column takes only the first 8 texels of the console's 16-wide right tile —
## the other 8 are index 0 on every one of the 16 rows, so this is a crop, not a choice.
## Colours go through [method WorldMapStartMenu.psx_levels] so the box sits on the same
## 5-bit ladder as everything [WorldMapRenderer] draws beside it.
static func _panel_texture() -> ImageTexture:
	var src := load(PANEL_TEXTURE) as Texture2D
	if src == null:
		push_error("world map: %s missing (a dangling worktree symlink looks like this "
				% PANEL_TEXTURE + "— see docs/WORKTREE_SETUP.md)")
		return null
	var img := src.get_image()
	var out := Image.create(PANEL_ATLAS_WH.x, PANEL_ATLAS_WH.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	# column x-origins and widths in the packed atlas, and the band y-origins
	var col_x := [0, 8, 24]
	var col_w := [PANEL_MARGIN_L, 16, PANEL_MARGIN_R]
	for band in 3:
		for col in 3:
			var t: Rect2i = PANEL_TILES[band * 3 + col]
			for y in 16:
				for x in int(col_w[col]):
					out.set_pixel(int(col_x[col]) + x, band * 16 + y,
							WorldMapStartMenu.psx_levels(
									img.get_pixel(t.position.x + x, t.position.y + y)))
	return ImageTexture.create_from_image(out)


## Start §38's transition from frame 0 — the page goes black, closed and clipped, and
## [method advance_open] walks it to the settled frame over [constant OPEN_VSYNCS] vsyncs.
func begin_open() -> void:
	_open_frame = 0
	_apply_open()


## One vsync of the transition, on the same clock as the bob (§21.3). Returns true when
## something moved, so the scene can repaint without polling.
func advance_open() -> bool:
	if _open_frame >= OPEN_VSYNCS:
		return false
	_open_frame += 1
	_apply_open()
	return true


## Park the transition on a chosen vsync — for the filmstrip capture, which needs a
## determinate frame rather than whatever the process clock happened to reach.
func set_open_frame(f: int) -> void:
	_open_frame = clampi(f, 0, OPEN_VSYNCS)
	_apply_open()


## True while any of §38's four animations is still running.
func opening() -> bool:
	return _open_frame < OPEN_VSYNCS


## §38.1 — the picture's aperture percent this frame, or 100 once it has finished.
func aperture_percent() -> int:
	if _open_frame >= OPEN_APERTURE_VSYNCS:
		return 100
	return OPEN_APERTURE_P[mini(_open_frame >> 1, OPEN_APERTURE_P.size() - 1)]


## §38.3 — the grey the drop shadow AND the name plate wear this frame.
##
## Frame 0 is the opener's `sb zero`; after that it is `7k + 1` clamped at 128, which is
## the measured 0, 8, 15, 22, ... 120, 127, 128.
func ramp_level() -> int:
	if _open_frame >= OPEN_RAMP_VSYNCS or _open_frame < 0:
		return WorldMapPrimitives.DEFAULT_RGB & 0xFF
	if _open_frame == 0:
		return 0
	return mini(WorldMapPrimitives.DEFAULT_RGB & 0xFF, OPEN_RAMP_STEP * _open_frame + 1)


## §38.7 — the panel's scissor this frame, in the page's own coordinates.
##
## The rect is `x + w/2 - w*p/200` by `w*p/100` on the settled element, which is the
## SAME arithmetic [method aperture] runs, only landing on a clip instead of on a rect.
## ⚠ It is [b]not[/b] snapped to even: every measured `DR_AREA` carries the odd values
## (§38.7's correction to §37.4).
func panel_clip() -> Rect2i:
	var o := origin()
	var sz := PANEL_ELEM_WH
	if _open_frame >= OPEN_VSYNCS:
		return Rect2i(o, sz)
	var i := _open_frame - OPEN_PANEL_DELAY
	if i < 0:
		return Rect2i(o, Vector2i.ZERO)
	var p := OPEN_PANEL_CURVE[mini(i, OPEN_PANEL_CURVE.size() - 1)]
	return Rect2i(o.x + sz.x / 2 - sz.x * p / 200, o.y + sz.y / 2 - sz.y * p / 200,
			sz.x * p / 100, sz.y * p / 100)


func _apply_open() -> void:
	if _back != null:
		var prims: Array = shadow_quads()
		var pic := picture_quad()
		if not pic.is_empty():
			prims.append(pic)
		_back.draw_primitives(prims)
	if _clip != null:
		var c := panel_clip()
		_clip.position = Vector2(c.position)
		_clip.size = Vector2(c.size)
		if _box != null:
			_box.position = Vector2(origin() - c.position)
		for i in _labels.size():
			_labels[i].position = Vector2(row_cell_top_left(i) - c.position)
		_clip.visible = c.size.x > 0 and c.size.y > 0
	_place_cursor()


## Step the glove's bob — one 60 Hz vsync clock for the whole screen (§21.3).
func set_bob_frame(f: int) -> void:
	if f == _bob_frame:
		return
	var was := bob_x()
	_bob_frame = f
	if bob_x() != was:
		_place_cursor()


## Move the highlight, wrapping on the list's own last row — the list is built at
## runtime, so the wrap is `len - 1` rather than a record halfword.
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


func confirm() -> void:
	if row < 0 or row >= rows():
		return
	var r: Dictionary = rows_for_node[row]
	chose.emit(row, int(r["msg"]), String(r["label"]),
			r.get("leads_to", {}) as Dictionary)


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
## deafened by [code]set_process_*input(false)[/code], so the town page cannot be reached
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


## Route one input event. True when the page consumed it — the caller then does nothing
## else with it, which is how the map's own cursor stays frozen while this is up.
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

## The location painting — §35.6's single `0x64` textured rect.
##
## [b]The tpage and CLUT come from the node, not from a constant[/b], and that is this
## port's one deliberate divergence from the console. On the PSX all 92 WLDPIC entries
## land at the SAME address, VRAM (512,256), swapped in place per node by a `LoadImage`
## on the ○ press. A single baked `vram.bin` cannot hold a region that changes, so
## `parse_world_map.py` gives each of the 19 node-reachable pictures an address of its
## own and puts the resulting tpage/CLUT/uv on the node record. The picture still
## resolves through [method WorldMapAssets.texel] and [method WorldMapAssets.clut_levels]
## like every other primitive on the screen; only its ADDRESS differs — which is the one
## thing the console varies anyway. See ADR-0178.
func picture_quad() -> Dictionary:
	var slot: Variant = _assets.node(node_1based - 1).get("picture_slot")
	if typeof(slot) != TYPE_DICTIONARY:
		return {}
	var s: Dictionary = slot
	var uv := _v(s["uv"])
	var o := PICTURE_XY
	var wh := PICTURE_WH
	# §38.1/§38.2 — the centre-out CLIP reveal. The rect loses `inset` on each side and
	# the uv gains exactly that, so the middle of the painting is sampled at 1:1; a
	# stretch would sample all of it into a smaller rect and read as a squash.
	var p := aperture_percent()
	if p < 100:
		var ax := aperture(wh.x, p)
		var ay := aperture(wh.y, p)
		var inset := Vector2i(ax.x, ay.x)
		o += inset
		uv += inset
		wh = Vector2i(ax.y, ay.y)
		if wh.x <= 0 or wh.y <= 0:
			return {}
	return {
		"kind": "quad", "sprt": true,
		"xy": [o, o + Vector2i(wh.x, 0), o + Vector2i(0, wh.y), o + wh],
		"uv": [uv, uv + Vector2i(wh.x, 0), uv + Vector2i(0, wh.y), uv + wh],
		"tpage": int(s["tpage"]), "clut": int(s["clut"]),
		# abr 0 and OPAQUE, which is what the console's 0x64 command byte carries.
		"abr": 0, "semi": false, "rgb": WorldMapPrimitives.DEFAULT_RGB,
	}


## The name plate — the node's OWN name cel, the same `NAME_FRAME_BASE + n` plate the HUD
## draws under the cursor, from the same VRAM through the same renderer. No glyph is baked
## here: the console's art already spells all 43 names.
##
## The anchor is the PICTURE's centre x. Solved against the console: the plate quad on
## `world_map_ss4_town_menu_open` is `xy (-40,1)-(40,11) uv (0,60)`, and node 6's name cel
## is one part at `x -36 y 1 w 80 h 10 u 0 v 60` — so uv, w and h match outright and the
## anchor is (-4, 0), which is `PICTURE_XY.x + PICTURE_WH.x / 2` exactly.
##
## ⚠ [b]One node, one anchor.[/b] 28 of the 43 name cels carry a self-centre of 0 where
## node 6's is 4, so under a fixed anchor those 28 sit 4px left of where a
## centre-the-art rule would put them. Both readings fit the single observation and the
## repo holds no savestate standing on a node from the other group. This takes the
## literal transcription — it is also what the HUD already does, drawing each name cel at
## a fixed per-node point and letting the cel's own `x` place the art.
func plate_quads() -> Array:
	var cid := _assets.static_cel(node_1based + WorldMapPrimitives.NAME_FRAME_BASE)
	if cid < 0:
		return []
	# §38.3/§38.4 — the plate is a CEL, and "the text starts black" is that cel's own rgb.
	# There is no separate text animation to build.
	return _gen.cel_quads(cid, Vector2i(PICTURE_XY.x + PICTURE_WH.x / 2, 0), _ramp_rgb())


## Cel 15 at (-8,16) — 28 semi-transparent quads at abr 2, reading the 11-step ramp at
## CLUT (0,487). See [WorldMapTownTest] for why this is a cel and not 28 literals.
func shadow_quads() -> Array:
	var sh: Dictionary = record["shadow"]
	var cid := _assets.static_cel(int(sh["frame"]))
	# §38.6 — the shadow does NOT have a fade of its own: it is the second cel record the
	# one ramp writes, the same grey on the same frame as the plate. And because abr 2 is
	# `B - F`, scaling rgb scales how much is subtracted — at level 0 it subtracts nothing
	# and the shadow is simply absent.
	return _gen.cel_quads(cid, _v(sh["xy"]), _ramp_rgb()) if cid >= 0 else []


## §38.3's level as one grey — r == g == b, which is what makes it a brightness ramp and
## not a tint.
func _ramp_rgb() -> int:
	var l := ramp_level()
	return (l << 16) | (l << 8) | l


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_labels.clear()
	_clip = null
	_box = null
	_back = null
	_front = null

	# --- back to front, because tree order IS draw order. The shadow is UNDER the
	# picture (§35.9), and the panel is over both.
	_back = WorldMapRenderer.new()
	_back.setup(_assets)
	add_child(_back)
	var prims: Array = shadow_quads()
	var pic := picture_quad()
	if not pic.is_empty():
		prims.append(pic)
	_back.draw_primitives(prims)

	# --- the panel — the console's own nine-patch, §37.2. Not synthesis any more.
	#
	# §38.7: it lives inside a CLIPPING Control, because the console's open is a scissor.
	# The nine slices and the rows are always at their settled size and only this rect
	# grows; scaling the nine-patch instead would crush the corner art, which the console
	# never does. `clip_contents` is the engine's scissor — it clips every CanvasItem
	# descendant to the Control's rect.
	var o := origin()
	var sz := size()
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.position = Vector2(o)
	_clip.size = Vector2(sz)
	add_child(_clip)
	_box = NinePatchRect.new()
	_box.texture = _panel_texture()
	_box.patch_margin_left = PANEL_MARGIN_L
	_box.patch_margin_right = PANEL_MARGIN_R
	_box.patch_margin_top = PANEL_MARGIN_T
	_box.patch_margin_bottom = PANEL_MARGIN_B
	_box.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_box.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# inside the clip, so its position is relative to the clip's own origin
	_box.position = Vector2.ZERO
	_box.size = Vector2(sz)
	_clip.add_child(_box)

	# --- the rows, at §37.3's MEASURED ink. The cell is placed so its ink lands on
	# ROW_INK_XY + pitch*r; the bob is X-only and never moved these (the old expression
	# subtracted it from Y, which is a jitter this screen does not have).
	var font := UIFont.new()
	for r in rows():
		var s := Sprite2D.new()
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.texture = WorldMapStartMenu._bake_label(font, label_of(r))
		s.position = Vector2(row_cell_top_left(r) - o)
		_clip.add_child(s)
		_labels.append(s)

	# --- the name plate and the glove, over everything, through the map's own renderer.
	_front = WorldMapRenderer.new()
	_front.setup(_assets)
	add_child(_front)
	# _apply_open() rather than _place_cursor(): a rebuild in the middle of the transition
	# has to restore the clip and the ramp too, not just the glove.
	_apply_open()


## The plate rides with the glove because [b]it is drawn OVER the panel[/b], and that is
## a measurement rather than a layering preference. §35.0 lists the plate quad ahead of
## the box's nine `0x66`s, which reads as "the box covers it" — but the plate sits at
## screen y 1..11 and the box's top edge is at y 8, and on
## `world_map_ss4_town_menu_open`'s framebuffer there are ink pixels at fb y 128 and 129,
## ON the box: the descenders of the `g` in "Magic" and the `y` in "City". Drawing the box
## last loses exactly those four pixels, and "Gariland Magic City" comes out reading
## "Gariland Manic Citu". Four pixels, and they are the two that make the word.
func _place_cursor() -> void:
	if _front == null or _gen == null:
		return
	var prims: Array = plate_quads()
	if rows() > 0:
		prims.append_array(_gen.cel_quads(
				_assets.static_cel(WorldMapPrimitives.CURSOR_FRAME), cursor_at(row)))
	_front.draw_primitives(prims)


## `value in arr` for an [Array] that came out of JSON — see the call site.
static func _has_int(arr: Array, value: int) -> bool:
	for e in arr:
		if int(e) == value:
			return true
	return false


static func _v(a: Variant) -> Vector2i:
	var arr: Array = a
	return Vector2i(int(arr[0]), int(arr[1]))
