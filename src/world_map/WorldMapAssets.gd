class_name WorldMapAssets
extends RefCounted
## The world map's disc-derived inputs: VRAM halfwords and the WLDCORE model.
##
## Produced by [code]tools/parse_world_map.py[/code]; both files are gitignored and
## regenerable. See [code]docs/WORLD_MAP_PORT_LIST.md[/code] §7 and
## [code]research/working_documents/WORLD_MAP_SCREEN.md[/code] §30.
##
## [b]VRAM is kept as raw halfwords, not as a sheet.[/b] The screen samples 4bpp and
## 8bpp INDICES through CLUTs that also live in VRAM, and one CLUT is overridden at
## runtime (the "you are here" pin, §24.2) — a pre-resolved RGBA sheet cannot express
## that. [method texel] and [method clut_levels] are the PSX GPU's two reads.
##
## Vault: [[World Map Screen]]

const VRAM_PATH := "res://assets/world_map/vram.bin"
const MODEL_PATH := "res://assets/world_map/model.json"
const VRAM_W := 1024
const VRAM_H := 512

var vram: PackedByteArray
var model: Dictionary
var loaded: bool = false
var error: String = ""


func load_all() -> bool:
	var f := FileAccess.open(VRAM_PATH, FileAccess.READ)
	if f == null:
		error = "%s missing — run tools/parse_world_map.py" % VRAM_PATH
		return false
	vram = f.get_buffer(VRAM_W * VRAM_H * 2)
	f.close()
	if vram.size() != VRAM_W * VRAM_H * 2:
		error = "vram.bin is %d bytes, expected %d" % [vram.size(), VRAM_W * VRAM_H * 2]
		return false

	var mf := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if mf == null:
		error = "%s missing — run tools/parse_world_map.py" % MODEL_PATH
		return false
	var parsed: Variant = JSON.parse_string(mf.get_as_text())
	mf.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		error = "model.json did not parse as an object"
		return false
	model = parsed
	loaded = true
	return true


## One VRAM halfword at texel (x, y).
func halfword(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= VRAM_W or y >= VRAM_H:
		return 0
	var o := (y * VRAM_W + x) * 2
	return vram[o] | (vram[o + 1] << 8)


## Decode a tpage word to (vram_x, vram_y, bpp, abr) — the GPU's own packing.
static func tpage_origin(word: int) -> Array:
	var bpp: int = [4, 8, 15, 15][(word >> 7) & 3]
	return [(word & 0xF) * 64, ((word >> 4) & 1) * 256, bpp, (word >> 5) & 3]


## The palette index at (u, v) inside a tpage. §18 / render_scene.py `texel()`.
func texel(tpage: int, u: int, v: int) -> int:
	var o := tpage_origin(tpage)
	var tx: int = o[0]
	var ty: int = o[1]
	var bpp: int = o[2]
	if bpp == 4:
		return (halfword(tx + (u >> 2), ty + v) >> ((u & 3) * 4)) & 0xF
	if bpp == 8:
		return (halfword(tx + (u >> 1), ty + v) >> ((u & 1) * 8)) & 0xFF
	return halfword(tx + u, ty + v)


## Entry [param idx] of the CLUT named by a 16-bit clut word, as its raw 5-bit levels
## in x/y/z and 0 (transparent) or 1 in w.
## BGR555 in VRAM: bits 0-4 R, 5-9 G, 10-14 B, bit 15 = STP.
##
## [b]Levels, not colours.[/b] The expansion to 8 bits belongs at the END of the frame,
## after every blend — see `psx_expand_555.gdshader`. Handing out an expanded colour
## here is what made a blend `e(B) op e(F)` instead of `e(B op F)`.
##
## [b]Transparency is a property of the CLUT VALUE, not of the index.[/b] A texel is
## dropped when its resolved halfword is `0x0000` and only then. "Index 0 is the
## transparent key" is a convention that happens to hold for every 4bpp sprite on this
## screen, and it is [i]false[/i] for both aperture ramps:
## [codeblock]
##   clut 0x7880  subtractive   entry 0 = 0xFFFF -> (31,31,31), FULL subtraction
##                              and NO entry anywhere in it is 0x0000
##   clut 0x7940  additive      entry 0 = 0x9CE7 -> (7,7,7)
##                              129 of its 256 entries ARE 0x0000
## [/codeblock]
## Reading the index instead threw away the subtractive ramp's blackest value exactly
## where the vignette saturates — the four corners, where the console's frame is black
## and every render of this screen so far has painted map. 956 pixels, 1.6% of the
## frame, and §22.3 attributed them to "a ±1 index difference" flipping black to nearly
## black. The errors are 8 to 22 five-bit levels; a ±1 index cannot make one.
func clut_levels(clut_word: int, idx: int) -> Vector4i:
	var cx := (clut_word & 0x3F) * 16
	var cy := (clut_word >> 6) & 0x1FF
	var p := halfword(cx + idx, cy)
	if p == 0:
		return Vector4i.ZERO
	return Vector4i(p & 31, (p >> 5) & 31, (p >> 10) & 31, 1)


## Whether entry [param idx] of [param clut_word] carries the PSX's semi-transparency
## bit — VRAM bit 15 of the resolved halfword.
##
## [b]This is the half of the blend rule the renderer used to ignore.[/b] A quad's command
## byte only says "semi-transparency is ENABLED"; the GPU then blends a texel only if its
## own CLUT entry has bit 15 set, and writes every other texel straight. So one `0x2E`
## quad can be part blended and part opaque, and on this screen exactly one thing is:
## the node pins, CLUTs `0x784A` and `0x784B`, whose 8 used entries carry STP on 3 — the
## outer ring and the drop shadow — and NOT on the four that make the orange ball.
##
## Blending the whole quad washes that ball halfway into the map behind it. Measured
## against `world_map_ss1_settled_dialog_closed`: 23 of the pin's 24 opaque texels land
## on `min(31, texel * rgb / 128 + 7)` exactly — written, not mixed — where the `+ 7` is
## the additive vignette drawn over them afterwards (CLUT `0x7940` entry 0 = 7,7,7).
func clut_stp(clut_word: int, idx: int) -> bool:
	var cx := (clut_word & 0x3F) * 16
	var cy := (clut_word >> 6) & 0x1FF
	return (halfword(cx + idx, cy) & 0x8000) != 0


## True when [param clut_word] has BOTH kinds of used entry, so a semi-transparent quad
## drawing through it needs a per-texel blend rather than one blend for the whole quad.
##
## Across the settled frame's own display list this is true of the two pin CLUTs and
## nothing else — every other CLUT is all-blend or all-opaque, which is why the
## per-quad approximation held everywhere but on the pins.
func clut_stp_mixed(clut_word: int, entries: int) -> bool:
	var seen_opaque := false
	var seen_stp := false
	for i in range(entries):
		if clut_levels(clut_word, i).w == 0:
			continue                      # dropped -- the halfword is 0x0000
		if clut_stp(clut_word, i):
			seen_stp = true
		else:
			seen_opaque = true
		if seen_stp and seen_opaque:
			return true
	return false


## The console's 5-bit -> 8-bit expansion, `(v << 3) | (v >> 2)`. The renderer does NOT
## call this per texel — the shader does it once per frame — but the extractor's own
## checks and any still-image path want it by name rather than open-coded.
static func expand5(v: int) -> int:
	return (v << 3) | (v >> 2)


## The union of a cel's part rects, relative to the position it is drawn at. Used to
## clamp the cursor so its ART stays inside the drawing area rather than its anchor.
##
## For the cursor (cel 0) this comes out x −8..+7, y −12..+5 — which is §27.4's hit box
## (−10..+10, −14..+6) with a little padding, and an independent corroboration of what
## that section says about it: *"the box follows the art, which is drawn above its
## anchor."*
func cel_bounds(cel_id: int) -> Rect2i:
	var c := cel(cel_id)
	if c.is_empty():
		return Rect2i()
	var lo := Vector2i(0x7FFF, 0x7FFF)
	var hi := Vector2i(-0x7FFF, -0x7FFF)
	for part in c["parts"]:
		var a := Vector2i(int(part["x"]), int(part["y"]))
		var b := a + Vector2i(int(part["w"]), int(part["h"]))
		lo = lo.min(a)
		hi = hi.max(b)
	return Rect2i(lo, hi - lo)


func cel(cel_id: int) -> Dictionary:
	return model["cels"].get(str(cel_id), {})


func frame_list(frame_id: int) -> Array:
	return model["frames"].get(str(frame_id), [])


## A frame list whose single entry holds forever — every HUD element is one (§19.5).
## Refuses anything else rather than silently taking entry 0.
func static_cel(frame_id: int) -> int:
	var fl := frame_list(frame_id)
	if fl.size() != 1 or int(fl[0][1]) != 0xFFFF:
		push_error("world map: frame list %d is not static: %s" % [frame_id, fl])
		return -1
	return int(fl[0][0])


func nodes() -> Array:
	return model["nodes"]


func node(i: int) -> Dictionary:
	return model["nodes"][i]
