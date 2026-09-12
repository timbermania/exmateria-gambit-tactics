class_name WorldMapRenderer
extends Node2D
## Draws a generated primitive list with the PSX's blend rules.
##
## One [Polygon2D] per primitive, in submission order (tree order is draw order).
## 153 nodes for a full frame, which is nothing — the point of the scaffold is to be
## obviously correct and easy to diff against the oracle, not to be clever.
##
## [b]The blend model[/b] (§13, and `render_scene.py`'s `blend()`):
## [codeblock]
##   abr 0   (B + F) / 2   -> BLEND_MODE_MIX with alpha 0.5   (mix is F·a + B·(1-a))
##   abr 1    B + F        -> BLEND_MODE_ADD with alpha 1
##   abr 2    B - F        -> BLEND_MODE_SUB with alpha 1
##   abr 3    B + F/4      -> BLEND_MODE_ADD with alpha 0.25
##   opaque   F            -> BLEND_MODE_MIX with alpha 1
## [/codeblock]
## Only quads whose command byte sets the semi-transparency bit consult `abr` at all;
## an opaque quad with abr 2 still just writes F, which is why the cursor's shadow
## (abr 2, semi) darkens and its body (abr 0, opaque) does not.
##
## Texel index 0 is the PSX's transparent key and is baked to alpha 0 (§18/§24), so
## no discard is needed — Godot's own alpha blend does it.
##
## [b]Why the texture is baked on the CPU[/b]: it follows [FrameCellAtlas]'s precedent
## — an [ImageTexture] built in GDScript goes through exactly the path every other
## sprite in this project uses, so no importer or colour-space question touches it.
## Bakes are cached by (tpage, clut, uv rect), so the ~150 primitives of a frame
## resolve to a few dozen images and the pin pulse (which only moves `modulate`)
## costs nothing.
##
## Vault: [[World Map Screen]]

const PSX_ONE := 128.0                  # 0x80 in a primitive's rgb is 1.0x modulation
## A 5-bit level is stored as `8 * v` so that fixed-function blending lands where the
## console's does; `psx_expand_555.gdshader` widens it once at the end of the frame.
const LEVEL_SCALE := 8

var _assets: WorldMapAssets
var _bakes: Dictionary = {}             # key -> ImageTexture
var _palettes: Dictionary = {}          # key -> Array[PackedByteArray], 16 or 256
var _mats: Dictionary = {}              # blend key -> CanvasItemMaterial

## The texture alpha a semi-transparent texel gets under [method _per_texel_blend].
## 128/255 is where the existing vertex alpha 0.5 already quantises, so the all-blend
## CLUTs render identically whichever path they take.
const SEMI_ALPHA := 128

## `0x808080` — the rgb that means "no modulation", and the palette cache's default key.
const NEUTRAL_RGB := 0x808080


func setup(assets: WorldMapAssets) -> void:
	_assets = assets


## Draw [param prims], in order.
##
## Children are REUSED when the list keeps its shape, which it does on almost every
## frame: the pin pulse only moves `modulate` and the party marker only swaps a cel.
## Rebuilding 153 nodes per frame instead made the capture time out — the first
## version of this file did exactly that.
func draw_primitives(prims: Array) -> void:
	var kids := get_children()
	if kids.size() == prims.size():
		var same := true
		for i in prims.size():
			if not _update(kids[i], prims[i]):
				same = false
				break
		if same:
			return
		kids = get_children()
	for c in kids:
		remove_child(c)
		c.queue_free()
	for prim in prims:
		var node := _node_for(prim)
		if node != null:
			add_child(node)


## Re-point an existing child at [param prim]. False if the shapes do not match, in
## which case the caller falls back to a full rebuild.
func _update(node: Node, prim: Dictionary) -> bool:
	if prim["kind"] == "line":
		# A line is a flat Polygon2D rect (see _line_node) and never changes shape.
		return node is Polygon2D and (node as Polygon2D).texture == null
	if not (node is Polygon2D):
		return false
	var poly := node as Polygon2D
	var uv: Array = prim["uv"]
	var per_texel := _per_texel_blend(prim)
	var baked := int(prim["rgb"]) if bakes_modulation(int(prim["rgb"])) else NEUTRAL_RGB
	var tex := _bake(int(prim["tpage"]), int(prim["clut"]), uv[0], uv[3],
			level_shift(int(prim["abr"]), bool(prim["semi"])), per_texel, baked)
	if tex == null:
		return false
	var xy: Array = prim["xy"]
	poly.polygon = PackedVector2Array([
		Vector2(xy[0]), Vector2(xy[1]), Vector2(xy[3]), Vector2(xy[2])])
	if poly.texture != tex:
		poly.texture = tex
		var w := float(tex.get_width())
		var h := float(tex.get_height())
		poly.uv = PackedVector2Array([
			Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	poly.color = _modulate(prim)
	poly.material = material_for(int(prim["abr"]), bool(prim["semi"]))
	return true


func _modulate(prim: Dictionary) -> Color:
	var rgb: int = NEUTRAL_RGB if bakes_modulation(int(prim["rgb"])) else int(prim["rgb"])
	# Vertex alpha 1 when the TEXTURE carries the per-texel factor — the two multiply,
	# so halving here as well would blend the blended half twice.
	var a := 1.0 if _per_texel_blend(prim) else _alpha_for(prim)
	return Color(
		float((rgb >> 16) & 0xFF) / PSX_ONE,
		float((rgb >> 8) & 0xFF) / PSX_ONE,
		float(rgb & 0xFF) / PSX_ONE,
		a)


func _node_for(prim: Dictionary) -> Node2D:
	if prim["kind"] == "line":
		return _line_node(prim)
	return _quad_node(prim)


func _quad_node(prim: Dictionary) -> Node2D:
	var uv: Array = prim["uv"]
	var per_texel := _per_texel_blend(prim)
	var baked := int(prim["rgb"]) if bakes_modulation(int(prim["rgb"])) else NEUTRAL_RGB
	var tex := _bake(int(prim["tpage"]), int(prim["clut"]), uv[0], uv[3],
			level_shift(int(prim["abr"]), bool(prim["semi"])), per_texel, baked)
	if tex == null:
		return null
	var xy: Array = prim["xy"]
	var poly := Polygon2D.new()
	# PSX corner order is TL, TR, BL, BR; a polygon needs a ring.
	poly.polygon = PackedVector2Array([
		Vector2(xy[0]), Vector2(xy[1]), Vector2(xy[3]), Vector2(xy[2])])
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	poly.uv = PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	poly.texture = tex
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	poly.color = _modulate(prim)
	poly.material = material_for(int(prim["abr"]), bool(prim["semi"]))
	return poly


## Whether this quad's rgb has to be baked into its texture rather than ridden on the
## vertex colour.
##
## [b]Only when it BRIGHTENS.[/b] `Polygon2D.color` is quantised to 8 bits a channel, so
## a modulation above `0x80` — which is 1.0x — clamps to 1.0 and the brightening is lost
## outright. The pin pulse spends half its period there: §30.6's `96 + 2c` reaches
## `0xE0`, and both pins in `ss1` carry `0x90` and `0xB0`. Baking it is also the exact
## reproduction, because the console clamps per channel at 5 bits
## (`min(31, (level * rgb) >> 7)`) and the palette is where that clamp belongs.
##
## Dimming (<= 0x80) keeps the vertex-colour path: it is exact there, it costs no bake,
## and it is what every other primitive on the screen uses.
static func bakes_modulation(rgb: int) -> bool:
	return ((rgb >> 16) & 0xFF) > 0x80 or ((rgb >> 8) & 0xFF) > 0x80 or (rgb & 0xFF) > 0x80


## Whether this quad has to blend PER TEXEL rather than as a whole.
##
## True only when the quad enables semi-transparency AND its CLUT carries both kinds of
## used entry. On this screen that is the node pins and nothing else — every other CLUT
## in the settled frame's display list is all-blend or all-opaque, which is exactly why
## one blend per quad was right everywhere but there.
##
## ⚠ [b]Restricted to abr 0 on purpose.[/b] With `MIX`, a per-texel alpha reproduces both
## halves exactly: alpha 1 gives `F` and alpha 0.5 gives `(B + F) / 2`, which are the
## console's two rules. `ADD` and `SUB` cannot express "write F" at any alpha, so a mixed
## CLUT on abr 1/2/3 would need two draws. No primitive on this screen is one, and
## [WorldMapBlendTest] asserts the corpus stays that way rather than leaving the gap
## silent — a mode that is only correct because nothing reaches it is a footnote waiting
## to be a bug.
func _per_texel_blend(prim: Dictionary) -> bool:
	if not bool(prim["semi"]) or int(prim["abr"]) != 0:
		return false
	var tpage := int(prim["tpage"])
	var n := 256 if int(WorldMapAssets.tpage_origin(tpage)[2]) == 8 else 16
	return _assets.clut_stp_mixed(int(prim["clut"]), n)


func _alpha_for(prim: Dictionary) -> float:
	if not bool(prim["semi"]):
		return 1.0
	match int(prim["abr"]):
		0: return 0.5      # (B + F) / 2 -- the blender's halving is exact
		_: return 1.0      # B + F, B - F, and B + (F >> 2) with F shifted at bake time


## The Godot blend mode that reproduces `abr` on a framebuffer holding 8 x level.
##
##   abr 0  (B + F) / 2   MIX   alpha 0.5  ->  4(B+F), and floor(/8) IS `(B+F) >> 1`
##   abr 1   B + F        ADD   alpha 1    ->  clamps at byte 255, i.e. level 31
##   abr 2   B - F        SUB   alpha 1    ->  clamps at byte 0
##   abr 3   B + F/4      ADD   alpha 0.25
##
## An opaque quad ignores `abr` entirely — which is why the cursor's shadow (abr 2,
## semi) darkens and its body (abr 0, opaque) does not.
func material_for(abr: int, semi: bool) -> CanvasItemMaterial:
	var mode := CanvasItemMaterial.BLEND_MODE_MIX
	if semi:
		match abr:
			1, 3: mode = CanvasItemMaterial.BLEND_MODE_ADD
			2: mode = CanvasItemMaterial.BLEND_MODE_SUB
			_: mode = CanvasItemMaterial.BLEND_MODE_MIX
	if not _mats.has(mode):
		var m := CanvasItemMaterial.new()
		m.blend_mode = mode
		_mats[mode] = m
	return _mats[mode]


## GP0 0x40 LINE_F2, flat colour — the 4px black tick under the funds field (§8), and
## the only line the world map emits.
##
## [b]Not a [Line2D].[/b] The PSX fills the integer cells `x0..x1` INCLUSIVE on row
## `y0`, so the shape is the rect `[x0, x1+1) x [y0, y0+1)`. A width-1 [Line2D] through
## `y0` instead straddles rows `y0-1` and `y0` by half a pixel each and Godot resolves
## the tie by drawing neither: the tick vanished entirely, five black pixels the frame
## should have had. It cost nothing in the picture and showed up as the largest
## single delta in the frame.
func _line_node(prim: Dictionary) -> Node2D:
	var a: Vector2i = prim["a"]
	var b: Vector2i = prim["b"]
	if a.y != b.y:
		push_error("world map: LINE_F2 (%s)->(%s) is not horizontal" % [a, b])
		return null
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x) + 1
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(x0, a.y), Vector2(x1, a.y), Vector2(x1, a.y + 1), Vector2(x0, a.y + 1)])
	# A LINE_F2 carries an 8-bit rgb the GPU truncates to 5 bits; store it as 8 x level
	# like every other primitive so the expansion pass sees one encoding.
	var rgb: int = int(prim["rgb"])
	poly.color = Color(
			float(((rgb >> 16) & 0xFF) >> 3) * 8.0 / 255.0,
			float(((rgb >> 8) & 0xFF) >> 3) * 8.0 / 255.0,
			float((rgb & 0xFF) >> 3) * 8.0 / 255.0, 1.0)
	return poly


## One CLUT resolved to bytes, cached — 16 entries for 4bpp, 256 for the aperture.
##
## The byte is [b]8 x the 5-bit level[/b], not the expanded colour: the frame composites
## in the console's own channels and `psx_expand_555.gdshader` widens it once at the end.
## Index 0 keeps alpha 0 — the PSX's transparent key — so no discard is needed and, in
## every one of the three blend modes, a transparent texel is a no-op on the destination.
func _palette(clut: int, tpage: int, shift: int, per_texel: bool = false,
		mod_rgb: int = 0x808080) -> Array:
	var key := "p%d:%d:%d:%s:%06x" % [clut, WorldMapAssets.tpage_origin(tpage)[2], shift,
			per_texel, mod_rgb]
	if _palettes.has(key):
		return _palettes[key]
	var n := 256 if int(WorldMapAssets.tpage_origin(tpage)[2]) == 8 else 16
	var out: Array = []
	for i in range(n):
		var lv := _assets.clut_levels(clut, i)
		# `per_texel` carries the blend factor in the TEXTURE's alpha instead of the
		# vertex's, so one quad can be part blended and part written — see
		# [method _per_texel_blend]. 128, not 127, to land on the same side of the
		# 8-bit quantisation the vertex alpha 0.5 already lands on.
		var a := lv.w * 255
		if per_texel and lv.w != 0 and _assets.clut_stp(clut, i):
			a = SEMI_ALPHA
		# A modulation ABOVE 0x80 brightens, and a vertex colour cannot carry it: Godot
		# quantises `Polygon2D.color` to 8 bits per channel, so anything over 1.0 clamps
		# and the brightening is simply lost. Apply it here instead, where the console's
		# own `min(31, (level * rgb) >> 7)` — clamp included — is exact. See
		# [method _bakes_modulation].
		var lr := lv.x >> shift
		var lg := lv.y >> shift
		var lb := lv.z >> shift
		if mod_rgb != NEUTRAL_RGB:
			lr = mini(31, (lr * ((mod_rgb >> 16) & 0xFF)) >> 7)
			lg = mini(31, (lg * ((mod_rgb >> 8) & 0xFF)) >> 7)
			lb = mini(31, (lb * (mod_rgb & 0xFF)) >> 7)
		out.append(PackedByteArray([lr * LEVEL_SCALE, lg * LEVEL_SCALE,
				lb * LEVEL_SCALE, a]))
	_palettes[key] = out
	return out


## abr 3 is `B + (F >> 2)`: the console truncates the QUARTER, then adds. Godot's ADD
## with alpha 0.25 truncates the sum instead — and cannot even do that faithfully, since
## a vertex alpha is 8-bit quantised and 0.25 lands at 63/255, which reads a whole level
## low on 51 of the 1024 (B, F) pairs. F is a CLUT entry and therefore known at bake
## time, so shift it there and add at alpha 1. abr 1 and 2 need no shift, and abr 0's
## halving is the blender's own (`4(B+F)` floors to `(B+F) >> 1`).
##
## No world-map primitive uses abr 3 today. This is here because the blend test walks
## all four modes, and a mode that is only correct because nothing reaches it is a
## footnote waiting to be a bug.
static func level_shift(abr: int, semi: bool) -> int:
	return 2 if (semi and abr == 3) else 0


## Resolve a uv rect through its CLUT into an RGBA8 image. The rect may run
## BACKWARDS in either axis — that is §26.3's mirroring, and baking it here is why
## the quad above can keep a plain 0..1 uv.
func _bake(tpage: int, clut: int, uv0: Vector2i, uv3: Vector2i,
		shift: int, per_texel: bool = false, mod_rgb: int = 0x808080) -> ImageTexture:
	var key := "%d:%d:%d:%d:%d:%d:%d:%s:%06x" % [tpage, clut, uv0.x, uv0.y, uv3.x, uv3.y,
			shift, per_texel, mod_rgb]
	if _bakes.has(key):
		return _bakes[key]
	var w: int = absi(uv3.x - uv0.x)
	var h: int = absi(uv3.y - uv0.y)
	if w <= 0 or h <= 0:
		return null
	var du := 1 if uv3.x >= uv0.x else -1
	var dv := 1 if uv3.y >= uv0.y else -1
	# Straight into bytes rather than set_pixel per texel — the aperture alone is
	# 40 quads up to 97x32, and the per-pixel form was the slow half of the timeout.
	var buf := PackedByteArray()
	buf.resize(w * h * 4)
	var pal: Array = _palette(clut, tpage, shift, per_texel, mod_rgb)
	var o := 0
	for y in range(h):
		var v := (uv0.y + dv * y) & 0xFF
		for x in range(w):
			var u := (uv0.x + du * x) & 0xFF
			var e: PackedByteArray = pal[_assets.texel(tpage, u, v)]
			buf[o] = e[0]; buf[o + 1] = e[1]; buf[o + 2] = e[2]; buf[o + 3] = e[3]
			o += 4
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf)
	var tex := ImageTexture.create_from_image(img)
	_bakes[key] = tex
	return tex
