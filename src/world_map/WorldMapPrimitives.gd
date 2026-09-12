class_name WorldMapPrimitives
extends RefCounted
## GENERATE the settled world-map frame's primitives from the data model.
##
## A GDScript port of [code]world_map_captures/wldgen.py[/code]
## (WORLD_MAP_SCREEN.md §30), which emits the console's own primitives exactly:
## 60/60 main list and 12/12 travel ribbon, packet for packet, on two captures.
## [b]That is this class's oracle[/b] — `python3 wldgen.py prims` prints the list
## this must reproduce, and `images/round13_generated_scene.png` is the picture.
##
## It EMITS; it does not replay. Nothing here reads an ordering table.
##
## Draw order is submission order (§28.2): pins → party marker → additive aperture
## → subtractive aperture → cursor → HUD. Slot 15 down to slot 4 of the reverse
## ordering table, i.e. back to front.

const PROJ := Vector2i(128, 12)          # §25.3 — the GTE parks at identity
const DEFAULT_RGB := 0x808080            # 0x80 is 1.0x modulation on the PSX
const NAME_FRAME_BASE := 0x36
const MONTH_FRAME_BASE := 0x1F
const DIGIT_FRAME_BASE := 0x2C
const CURSOR_FRAME := 0
const FUNDS_DIGITS := 8
const FUNDS_TPAGE := 0x021F              # the shared UI sheet, 4bpp at VRAM (960,256)
const FUNDS_LABEL_CLUT := 0x7842
const FUNDS_DIGIT_CLUT := 0x7847
const FUNDS_DIGIT_U0 := 168
const FUNDS_DIGIT_V := 52
const PULSE_TOP := 0x40
const LINE_TPAGE := 0x0200               # the E1 word the funds tick rides behind

## §24.2's runtime palette override, in the console's own 1-based descriptor-palette
## numbers. The override lands as `clut_x = 16 * (pal - 1)` on the cel's own CLUT row —
## row 481 for every cel this screen draws — so a palette number IS a CLUT word, and both
## of these were read straight out of a savestate's live ordering table rather than
## chosen: `dump_frame.py world_map_ss1_settled_dialog_closed.sstate` prints the "you are
## here" pin carrying `clut=784B` and the cursor's lit layer carrying `clut=7847` (its
## unoverridden `clut_sel`).
##
## [b]DEACTIVATED is the blue-grey the map's cursor wears while a window is open[/b] —
## §15.21's "send to background" mechanism, which the world map runs on the cursor and on
## NOTHING else. Measured, not inferred: diffing `round16_menu_open.png` (the console with
## the START menu up) against `ss1`'s own framebuffer leaves **83 differing pixels in the
## whole right half of the screen**, all of them inside the cursor's 16x16 lit quad plus
## the party marker's own animation, and the four texel indices that move go
## (239,239,239) -> (140,148,165), (181,189,198) -> (107,123,140),
## (123,140,156) -> (90,107,115), (99,107,115) -> (74,90,99) — which is CLUT `0x7849` at
## VRAM (144,481), i.e. `pal = 10`. The pins, the name plate, the date, the war funds and
## the map itself do not change by one pixel.
## [b]A palette number is only meaningful on its own CLUT ROW.[/b] The override moves x
## and nothing else, so `PAL_DEACTIVATED` means "the blue-grey twin" only for a cel whose
## `clut_xy.y` is 481 — the cursor's row, and the pins'. The node-NAME cels sit on row
## 486, where slot 0 is the only populated CLUT in the whole row: applying 10 there
## resolves to `0x7989`, sixteen zero halfwords, and the cel draws NOTHING. (It did, for
## one build of the place list.) Row 486's slot 0 is byte-identical to `0x7847`, so the
## twin exists — it just is not reachable from that row by an override.
const PAL_HERE := 12                     # clut 0x784B — the pulsing "you are here" pin
const PAL_DEACTIVATED := 10              # clut 0x7849 — the blue-grey twin of 0x7847

var _a: WorldMapAssets


func _init(assets: WorldMapAssets) -> void:
	_a = assets


# ---------------------------------------------------------------- the pulse

## §30.6 — the pin pulse. `96 + 2c` for the node carrying a palette override,
## `224 - 2c` for every other, so §21.3's `dim + bright == 320` holds by
## construction rather than by observation. Phase 0 counts up to 0x40, phase 1
## counts down to 0; 64 + 64 is the 128-frame period §21.3 measured.
static func pulse_greys(c: int) -> Vector2i:
	return Vector2i((96 + 2 * c) & 0xFF, (-32 - 2 * c) & 0xFF)


# ---------------------------------------------------------------- packet fields

static func clut_word(x: int, y: int) -> int:
	return ((y & 0x1FF) << 6) | ((x >> 4) & 0x3F)


static func tpage_word(tx: int, ty: int, abr: int, bpp: int) -> int:
	var depth := 1 if bpp == 8 else 0
	return ((ty / 256) << 4) | ((tx / 64) & 0xF) | ((abr & 3) << 5) | (depth << 7)


## Resolve one cel part to the three attributes the packet carries (§24.2, §24.3).
## [param desc_pal] is the descriptor's 1-based palette override; blend bit 3
## vetoes it, which is how a shadow keeps its own CLUT while its body recolours.
func part_packet(cel: Dictionary, part: Dictionary, desc_pal: int = 0) -> Dictionary:
	var cx: int = cel["clut_xy"][0]
	var cy: int = cel["clut_xy"][1]
	var tx: int = cel["tpage_xy"][0]
	var ty: int = cel["tpage_xy"][1]
	var blend: int = part["blend"]
	var x: int
	if desc_pal > 0 and (blend & 0x08) == 0:
		x = cx + 16 * (desc_pal - 1)
	else:
		x = (cx + (int(part["clut_sel"]) << 16)) >> 12
	var abr := (blend >> 4) & 3
	var bpp := 8 if (blend & 0x04) != 0 else 4
	return {
		"clut": clut_word(x, cy),
		"tpage": tpage_word(tx, ty, abr, bpp),
		"abr": abr,
		"semi": (blend >> 6) & 1 == 1,
	}


## One cel part -> one quad, exactly as FUN_8006AED0 writes it (§19.5).
## Blend bit 0 runs v backwards and bit 1 runs u backwards — §26.3's mirroring,
## which is how the aperture is one quadrant drawn four ways.
func _part_quad(cel: Dictionary, part: Dictionary, d: Vector2i, rgb: int,
		desc_pal: int) -> Dictionary:
	var pk := part_packet(cel, part, desc_pal)
	var w: int = part["w"]
	var h: int = part["h"]
	var x0: int = d.x + int(part["x"])
	var y0: int = d.y + int(part["y"])
	var blend: int = part["blend"]
	var u_lo: int = int(part["u"]) + (w if (blend & 0x02) != 0 else 0)
	var u_hi: int = int(part["u"]) + (0 if (blend & 0x02) != 0 else w)
	var v_lo: int = int(part["v"]) + (h if (blend & 0x01) != 0 else 0)
	var v_hi: int = int(part["v"]) + (0 if (blend & 0x01) != 0 else h)
	return {
		"kind": "quad",
		# PSX corner order is TL, TR, BL, BR.
		"xy": [Vector2i(x0, y0), Vector2i(x0 + w, y0),
			   Vector2i(x0, y0 + h), Vector2i(x0 + w, y0 + h)],
		"uv": [Vector2i(u_lo, v_lo), Vector2i(u_hi, v_lo),
			   Vector2i(u_lo, v_hi), Vector2i(u_hi, v_hi)],
		"tpage": pk["tpage"], "clut": pk["clut"], "abr": pk["abr"],
		"semi": pk["semi"], "rgb": rgb,
	}


## A cel's parts in CHAIN order, which is ascending part index — the observable
## fact being that cel 0 puts its shadow (part 0) ahead of its cursor (part 1).
func cel_quads(cel_id: int, at: Vector2i, rgb: int = DEFAULT_RGB,
		desc_pal: int = 0) -> Array:
	var cel := _a.cel(cel_id)
	if cel.is_empty():
		return []
	var out: Array = []
	for part in cel["parts"]:
		out.append(_part_quad(cel, part, at, rgb, desc_pal))
	return out


# ---------------------------------------------------------------- the main list

## The settled frame's primitives, in submission order.
## [param pulse_c] is the pin-pulse counter, 0..64 (§30.6).
## [param cursor_pal] overrides the cursor's palette — [constant PAL_DEACTIVATED] while a
## window owns the screen, 0 (no override) otherwise.
## [param regarding] is the 1-based node the screen is REGARDING — a [b]reveal pass[/b]'s
## look-at, which draws the location name over the node it names instead of over the one
## the cursor is on. 0 leaves the name to the cursor, which is every frame outside a pass.
## It is `DAT_800D0BB4` (§19.1 / §30.4) being written by something other than the hit test.
## [param ghost_node] is a node INDEX to draw a marker for even though the store says it
## is unknown — an erase still holding its sixteen vsyncs. -1 for none.
func main_list(p: WorldMapProgress, cursor: Vector2i, pulse_c: int,
		party_cel: int = 16, party_xy: Variant = null,
		cursor_pal: int = 0, regarding: int = 0, ghost_node: int = -1) -> Array:
	var out: Array = []
	var greys := pulse_greys(pulse_c)
	var bright := greys.x
	var dim := greys.y
	var party := p.party_node()

	# --- slot 15: the node markers. The element walker runs the list ascending and
	# AddPrim head-inserts, so the chain comes out DESCENDING (§24.5).
	var known: Array = p.known_nodes()
	if ghost_node >= 0 and not known.has(ghost_node):
		known.append(ghost_node)
		known.sort()
	known.reverse()
	for i in known:
		var n: Dictionary = _a.node(i)
		var here: bool = (i + 1 == party)
		var grey: int = bright if here else dim
		var cel_id := _a.static_cel(int(n["marker_frame"]))
		if cel_id >= 0:
			out.append_array(cel_quads(cel_id, _screen(n), grey * 0x010101,
					PAL_HERE if here else 0))

	# --- slot 14: the party marker, at its own descriptor position — a node's
	# projected xy when parked, a point along a route while walking (§27.3).
	var pxy: Vector2i = party_xy if party_xy != null else _screen(_a.node(party - 1))
	out.append_array(cel_quads(party_cel, pxy))

	# --- slot 13: the aperture — additive (cel 9) AHEAD of subtractive (cel 8).
	var lay: Dictionary = _a.model["layout"]
	out.append_array(cel_quads(_a.static_cel(int(lay["aperture_add"]["frame"])),
			_v(lay["aperture_add"]["xy"])))
	out.append_array(cel_quads(_a.static_cel(int(lay["aperture_sub"]["frame"])),
			_v(lay["aperture_sub"]["xy"])))

	# --- slot 12: the cursor, drawn last of the map layer so the vignette misses it.
	# Its LIT part takes `cursor_pal`; its shadow part sets blend bit 3, which vetoes the
	# override — see [method part_packet]. That veto is not a port convenience: on the
	# console the shadow keeps `clut=7844` while the hand goes blue-grey.
	out.append_array(cel_quads(_a.static_cel(CURSOR_FRAME), cursor,
			DEFAULT_RGB, cursor_pal))

	# --- slot 4: the HUD. Call order is funds, date, name (§28.2); the chain is
	# its reverse, so the name comes first here. The name is drawn for the node the
	# CURSOR is over, derived here exactly as `FUN_8008D060` derives it — §19.1's
	# `!= 0` guard is live, not defensive, and §9.1's "the label follows the cursor"
	# is two consumers of one node rather than one causing the other.
	var sel := regarding if regarding > 0 else WorldMapCursor.node_under(_a, p, cursor)
	if sel > 0:
		var cid := _a.static_cel(sel + NAME_FRAME_BASE)
		if cid >= 0:
			out.append_array(cel_quads(cid, _screen(_a.node(sel - 1))))
	out.append_array(_date_quads(p))
	out.append_array(_funds_prims(p))
	return out


func _screen(n: Dictionary) -> Vector2i:
	return Vector2i(int(n["screen"][0]), int(n["screen"][1]))


func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## Month cel then one or two day digits, chain-reversed (§19.3).
func _date_quads(p: WorldMapProgress) -> Array:
	var lay: Dictionary = _a.model["layout"]
	var m := _v(lay["date_xy"])
	var step := _v(lay["date_step"])
	var d := m + step
	var date := p.date()
	var day := date.y
	var out: Array = []
	if day > 9:
		out.append_array(cel_quads(_a.static_cel(day % 10 + DIGIT_FRAME_BASE),
				d + Vector2i(8, 0)))
		out.append_array(cel_quads(_a.static_cel(day / 10 + DIGIT_FRAME_BASE), d))
	else:
		out.append_array(cel_quads(_a.static_cel(day % 10 + DIGIT_FRAME_BASE), d))
	out.append_array(cel_quads(_a.static_cel(date.x + MONTH_FRAME_BASE), m))
	return out


## The war-funds panel: an 8-digit right-aligned SPRT field, a black tick and the
## label (§8). Leading positions carry a DIFFERENT glyph — the hollow placeholder
## zero at uv (208,40) — which is what makes them read dim; it is not a brightness
## trick. The 4px tick sits at the first significant digit: every capture holds
## gil = 4500, so that and "the constant 84" are indistinguishable (§30.7).
func _funds_prims(p: WorldMapProgress) -> Array:
	var a := _v(_a.model["layout"]["funds_xy"])
	var text := str(p.gil())
	var first := FUNDS_DIGITS - text.length()
	var out: Array = []
	for k in range(FUNDS_DIGITS - 1, -1, -1):
		var x := a.x + 4 + 8 * k
		if k < first:
			out.append(_sprt(x, a.y + 12, 208, 40, 8, 8, FUNDS_DIGIT_CLUT))
		else:
			var digit := text.unicode_at(k - first) - 48
			out.append(_sprt(x, a.y + 12, FUNDS_DIGIT_U0 + 8 * digit, FUNDS_DIGIT_V,
					8, 12, FUNDS_DIGIT_CLUT))
	var tick := a.x + 4 + 8 * first
	# GP0 0x40 LINE_F2 behind its own E1 draw-mode word; the console's is 0x0200.
	out.append({"kind": "line", "a": Vector2i(tick, a.y + 8),
			"b": Vector2i(tick + 4, a.y + 8), "rgb": 0, "tpage": LINE_TPAGE})
	out.append(_sprt(a.x, a.y, 156, 120, 41, 8, FUNDS_LABEL_CLUT))
	return out


## The war-funds field is drawn as GP0 0x64 SPRTs, not as textured quads — the same
## pixels either way, but it is what the console emits and the oracle's packet dump
## distinguishes them, so the primitive records it.
func _sprt(x: int, y: int, u: int, v: int, w: int, h: int, clut: int) -> Dictionary:
	return {
		"kind": "quad", "sprt": true,
		"xy": [Vector2i(x, y), Vector2i(x + w, y),
			   Vector2i(x, y + h), Vector2i(x + w, y + h)],
		"uv": [Vector2i(u, v), Vector2i(u + w, v),
			   Vector2i(u, v + h), Vector2i(u + w, v + h)],
		"tpage": FUNDS_TPAGE, "clut": clut, "abr": 0, "semi": false,
		"rgb": DEFAULT_RGB,
	}


# ---------------------------------------------------------------- the ribbon

const PATH_UV := Vector2i(136, 224)
const PATH_UV_WH := Vector2i(15, 15)
const PATH_CLUT := 0x7A01
const PATH_TPAGE := 0x0017


## The travel ribbon (§12.4) — every route the store says is drawn. Routes are emitted
## ascending and the chain reverses them.
##
## [param skip_route] is a route the store says is drawn but the frame must not draw
## WHOLE — a [WorldMapRevealAnimation]'s ribbon in flight, whose quads come from
## [method ribbon_quads] instead. -1 (the default) draws every drawn route.
func path_quads(p: WorldMapProgress, skip_route: int = -1) -> Array:
	var out: Array = []
	for r in p.drawn_routes():
		if r == skip_route:
			continue
		out.append_array(ribbon_quads(int(r)))
	out.reverse()
	return out


## One route's ribbon, or the first [param quads] of it while a reveal is drawing it.
##
## The polyline table stores each waypoint as a PAIR of edge vertices — the ribbon's
## cross-section — so a quad is two consecutive pairs, four shorts apart. That is the
## decompiler's "every 4th vertex" read as data rather than as a stride.
##
## [param quads] < 0 is the whole route. [param from_end] anchors the partial ribbon at
## the route's LAST quad instead of its first — the emit named the endpoints the other way
## round, and the console tracks that as bit 1 of `0x800D3BBC` (`0x8008DA1C`). The road
## grows away from the node the emit names first, which is the node the look-at before it
## was pointing at.
##
## Emitted ascending; [method path_quads] reverses the chain over the whole list, and a
## partial ribbon is reversed by its caller for the same reason.
func ribbon_quads(r: int, quads: int = -1, from_end: bool = false) -> Array:
	var out: Array = []
	var poly: Array = _a.model["routes"][r]["polyline"]
	var pairs := poly.size() / 2 - 1
	var lo := 0
	var hi := pairs
	if quads >= 0:
		if from_end:
			lo = maxi(0, pairs - quads)
		else:
			hi = mini(pairs, quads)
	for k in range(lo, hi):
		var pts: Array = []
		var vis := false
		for j in range(4):
			var q: Array = poly[2 * k + j]
			var s := Vector2i(int(q[0]) + PROJ.x, int(q[1]) + PROJ.y)
			pts.append(s)
			if s.x >= -127 and s.x <= 127 and s.y >= -111 and s.y <= 111:
				vis = true
		if not vis:
			continue
		out.append({
			"kind": "quad", "xy": pts,
			"uv": [PATH_UV, PATH_UV + Vector2i(PATH_UV_WH.x, 0),
				   PATH_UV + Vector2i(0, PATH_UV_WH.y), PATH_UV + PATH_UV_WH],
			"tpage": PATH_TPAGE, "clut": PATH_CLUT, "abr": 0, "semi": true,
			"rgb": DEFAULT_RGB,
		})
	return out


# ---------------------------------------------------------------- the background

## The 81 background quads (§7.5). NOT part of a settled frame — §28.3 shows the
## builder DMAs a pre-composited cache and draws its 60 primitives on top — but the
## Godot side has no cache, so it draws the geometry the cache was made from.
## The grid is savestate-sourced (§15 #17); see tools/parse_world_map.py.
func background_quads() -> Array:
	var out: Array = []
	var grid: Array = _a.model["background_grid"]
	for e in grid:
		if bool(e["cull"]) or int(e["row"]) >= 12 or int(e["col"]) >= 16:
			continue
		var x0: int = int(e["screen"][0])
		var y0: int = int(e["screen"][1])
		var w: int = int(e["w"])
		var h: int = int(e["h"])
		var u: int = int(e["u"])
		var v: int = int(e["v"])
		out.append({
			"kind": "quad",
			"xy": [Vector2i(x0, y0), Vector2i(x0 + w, y0),
				   Vector2i(x0, y0 + h), Vector2i(x0 + w, y0 + h)],
			"uv": [Vector2i(u, v), Vector2i(u + w, v),
				   Vector2i(u, v + h), Vector2i(u + w, v + h)],
			# §7.5: GetClut(0, 0x1E0) -> 0x7800, the value all 25 measured packets carry.
			"tpage": int(e["tpage"]) & 0xFFFF, "clut": 0x7800,
			"abr": 0, "semi": false, "rgb": DEFAULT_RGB,
		})
	return out
