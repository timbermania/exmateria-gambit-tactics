class_name UIMenuText
extends RefCounted
## Reusable FONT.BIN dark-on-tan proportional text renderer for the menu screens
## (FORMATION_SCREEN.md §14.6). This is the SAME rendering the formation info-panel /
## nameplate uses for the name/job words — the Status screen's stats band draws every
## label AND value AND punctuation ("Weap.Power", "C-EV", "004 / 05%") through it, so
## the one-glyph-at-a-time dark-ink path lives here as ONE widget instead of copied
## per screen. Faithfulness rule: FFT visuals + layout, OUR data.
##
## FONT.BIN carries the full glyph set — letters, digits AND the punctuation the stats
## band needs ('.', '-', '/', '%', space) — keyed by the FFT character index (via
## UIFont.get_char_index), so no baked RANGETILE label cells are required for this text.
##
## A caller mounts a string onto a parent Node3D at a LOCAL top-left world position
## (already converted from 256x240 px), advancing left-to-right by each glyph's §14.6
## proportional width. Ordering is by `render_priority` (ADR-0077 / the box-open group
## orders by priority, not Z), matching DetailScene's icon path.

const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const _FONT_OPAQUE_SHADER := "res://src/ui3/shaders/formation_font_opaque.gdshader"
const _TEXT_OPAQUE_SHADER := "res://src/ui3/shaders/formation_text_opaque.gdshader"

# Sentinel for the optional `z_meta` tag (see [method mount]): when a caller passes a real fold rung,
# each glyph mesh records `set_meta("z_rung", rung)` so the no-unauthored-depth guard (ADR-0077
# amendment) can key on the AUTHORED rung. Default = untagged (unchanged for every non-Status caller).
const NO_Z_META := -0x40000000

# FONT.BIN ink starts ~2px below its cell top (shared with the nameplate/HUD digits).
const FONT_INK_TOP_PAD := 2.0
const DIGIT_INK_TOP_PAD := 2.0

var _font: UIFont
var _digit_font: NumberFont       # HUD digit font (FRAMEFONT) — same as nameplate Brave/Faith
var _digit_pal: ImageTexture      # dark-on-tan digit CLUT (glyph indices 1/2/3 → ink ramp)


func _init() -> void:
	_font = UIFont.new()
	_digit_font = NumberFont.new()
	# Dark digit CLUT (dark-on-tan), exactly as UIUnitNameplate builds for Brave/Faith:
	# the FRAMEFONT glyph strokes are indices 1/2/3 → dark ink ramp; cell fill (4) and the
	# rest → transparent so the tan window shows through.
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, Color(0, 0, 0, 0))
	img.set_pixel(1, 0, UIUnitNameplate.INFO_INK_DARK)
	img.set_pixel(2, 0, UIUnitNameplate.INFO_INK_MID)
	img.set_pixel(3, 0, UIUnitNameplate.INFO_INK_LIGHT)
	_digit_pal = ImageTexture.create_from_image(img)


## Px width of `text` under the §14.6 proportional layout (glyph advance per char;
## a SPACE uses the ROM narrow advance). Lets a caller right-align a value or size a
## dot-leader without mounting anything.
func measure(text: String) -> float:
	var w := 0.0
	for ch in text:
		w += UIUnitNameplate.glyph_advance(_font, ch)
	return w


## Advance (px) of a single character — exposed so callers can lay dot-leaders etc.
func advance(ch: String) -> float:
	return UIUnitNameplate.glyph_advance(_font, ch)


## Mount `text` under `parent`, its top-left at local world position `base_local`
## (a 256x240 px position already converted to parent-local units — e.g. via a
## screen_to_world / _local_under_container helper). `ppu` = pixels_per_unit; each
## glyph is an opaque, depth-writing quad on `render_priority`. Returns the x-advance
## END in px (so callers can chain a value after a label).
## `mats_out` (optional): if given, every glyph ShaderMaterial created here is appended to it,
## so a caller can push per-frame uniforms onto them later (DetailScene's box-open `clip_world`
## scissor, §15.17). Default null ⇒ nothing collected, so all other callers are unchanged.
## `inks` (optional): a 3-entry [body, mid, edge] Color array overriding the default dark-on-tan
## ramp — e.g. the cream label ([cream, mid, dark-outline]) the §15.24 Change-Job "Lv. N" line uses.
## `z_meta` (optional): the AUTHORED fold rung to stamp on each glyph mesh via `set_meta("z_rung")`, so
## the no-unauthored-depth guard (ADR-0077 dec. 7) can verify these opaque, depth-writing glyphs
## named a rung. Default NO_Z_META ⇒ untagged (every non-Status caller unchanged). The caller still owns
## the Z-lift on `base_local`; this only records the intent.
func mount(parent: Node3D, text: String, base_local: Vector3, render_priority: int, ppu: float,
		mats_out = null, inks = null, z_meta: int = NO_Z_META) -> float:
	var ink := base_local + Vector3(0.0, FONT_INK_TOP_PAD * ppu, 0.0)  # ink sits ~2px below cell top
	var body: Color = inks[0] if inks != null else UIUnitNameplate.INFO_INK_DARK
	var mid: Color = inks[1] if inks != null else UIUnitNameplate.INFO_INK_MID
	var edge: Color = inks[2] if inks != null else UIUnitNameplate.INFO_INK_LIGHT
	var x_px := 0.0
	for ch in text:
		var w := UIUnitNameplate.glyph_advance(_font, ch)
		if ch != " ":
			var idx := _font.get_char_index(ch)
			var info := _font.get_char_info(idx)
			var mat := ShaderMaterial.new()
			mat.shader = load(_FONT_OPAQUE_SHADER)
			mat.set_shader_parameter("font_atlas", _font.atlas_texture)
			mat.set_shader_parameter("atlas_size", Vector2(_font.atlas_width, _font.atlas_height))
			mat.set_shader_parameter("char_region", Vector4(
				float(info.get("atlas_x", 0)), float(info.get("atlas_y", 0)),
				_font.char_width, _font.char_height))
			mat.set_shader_parameter("use_palette", true)
			mat.set_shader_parameter("palette_light", _ink(body))
			mat.set_shader_parameter("palette_mid", _ink(mid))
			mat.set_shader_parameter("palette_dark", _ink(edge))
			mat.render_priority = render_priority
			if mats_out != null:
				mats_out.append(mat)
			var holder := Node3D.new()
			holder.position = ink + Vector3(x_px * ppu, 0.0, 0.0)
			parent.add_child(holder)
			var gq := _glyph_quad(Vector2(_font.char_width, _font.char_height), mat, ppu)
			if z_meta != NO_Z_META:
				gq.set_meta("z_rung", z_meta)
			holder.add_child(gq)
		x_px += w
	return x_px


## Mount a HUD-digit number (`text` = digits / '/' / '-') under `parent`, its top-left at
## `base_local` — the SAME FRAMEFONT font + dark CLUT the nameplate draws Brave/Faith and
## the vitals gauges with (so the Status numbers read as gauge digits, not FONT.BIN text).
## Fixed HUD advance; each glyph is an opaque, depth-writing quad on `render_priority`.
## Returns the x-advance end in px. Spaces are NOT glyphs here — leave gaps via the caller.
## `palette` overrides the CLUT the glyphs render through (a 16x1 index→RGBA texture).
## Default (null) = the dark-on-tan Brave/Faith 3-ink CLUT. The Status stats band passes
## the full 16-colour menu value CLUT (0x7FFC ≡ label 0x7C3C for idx0-8) so the '/' and '%'
## glyphs — whose strokes are indices 3/6, which the 3-ink CLUT drops to transparent —
## render their proper dark-on-tan shades instead of coming out faint/broken.
## `mats_out` (optional): collects each glyph ShaderMaterial (see [method mount]) for the
## box-open `clip_world` scissor. Default null ⇒ unchanged for every other caller.
## `size` picks the FRAMEFONT set (NumberFont.SMALL/BIG). Default SMALL = the vitals/stats
## reality; the equip-picker count digits pass BIG (§15.27 — the ROM samples the BIG strip
## U=0x78+8·d for the "NN/NN" column, keeping the SMALL slash).
## `z_meta` (optional): see [method mount] — the authored fold rung stamped on each glyph mesh for the
## no-unauthored-depth guard (ADR-0077 dec. 7). Default NO_Z_META ⇒ untagged (callers unchanged).
func mount_number(parent: Node3D, text: String, base_local: Vector3, render_priority: int, ppu: float,
		palette: ImageTexture = null, mats_out = null, size: String = NumberFont.SMALL,
		z_meta: int = NO_Z_META) -> float:
	var top := base_local + Vector3(0.0, DIGIT_INK_TOP_PAD * ppu, 0.0)
	var pal := palette if palette != null else _digit_pal
	var placements := _digit_font.place_number(text, 0.0, 0.0, size, false, 1.0, 0)
	for g in placements:
		var cell: Rect2 = g["cell"]
		if cell.size == Vector2.ZERO:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = load(_TEXT_OPAQUE_SHADER)
		mat.set_shader_parameter("mode", 0)
		mat.set_shader_parameter("index_atlas", _digit_font.texture)
		mat.set_shader_parameter("atlas_size", Vector2(_digit_font.texture.get_width(), _digit_font.texture.get_height()))
		mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
		mat.set_shader_parameter("palette_tex", pal)
		mat.set_shader_parameter("brightness", 1.0)
		mat.render_priority = render_priority
		if mats_out != null:
			mats_out.append(mat)
		var pos: Vector2 = g["pos"]
		var holder := Node3D.new()
		holder.position = top + Vector3(pos.x * ppu, 0.0, 0.0)
		parent.add_child(holder)
		var gq := _glyph_quad(cell.size, mat, ppu)
		if z_meta != NO_Z_META:
			gq.set_meta("z_rung", z_meta)
		holder.add_child(gq)
	return _digit_font.advance_for(size) * float(text.length())


## The px width `mount_number` advances for `text` (fixed advance per char in `size`)
## — so a caller can right-align a numeric column (place at `right_x - width`).
func number_width(text: String, size: String = NumberFont.SMALL) -> float:
	return _digit_font.advance_for(size) * float(text.length())


## The px width of `text`'s actual INK — `advance × (n−1)` plus the LAST glyph's cell width,
## which is wider than the advance (the SMALL set advances 5 but draws a 6px cell). Use this,
## not [method number_width], to CENTRE a numeric column: number_width overshoots the centre
## by half the overhang, and on a 6px digit that half-pixel is visible.
##
## Pinned against the ROM: LEARN_PICKER.md §9.2's job-row glyph run is screen x123..224. A
## 1-digit Lv. centred on its header (centre 125.5) starts at 125.5 − 6/2 = 122.5 → x123, and a
## 4-digit Jp centred on 213.5 ends at 213.5 + 21/2 = x224. Both edges land exactly; the same
## columns right-aligned would read x128..220.
func number_ink_width(text: String, size: String = NumberFont.SMALL) -> float:
	if text.is_empty():
		return 0.0
	var last: Rect2 = _digit_font.cell_for(text.substr(text.length() - 1, 1), size)
	return _digit_font.advance_for(size) * float(text.length() - 1) + last.size.x


## A dot-leader ("Move … 5"): '.' glyphs from `x0_px` up to `x1_px` at `pitch` px,
## mounted like [method mount]. Same dark ink; returns nothing (cosmetic filler).
func mount_dots(parent: Node3D, base_local: Vector3, x0_px: float, x1_px: float,
		pitch: float, render_priority: int, ppu: float) -> void:
	var x := x0_px
	while x <= x1_px:
		mount(parent, ".", base_local + Vector3(x * ppu, 0.0, 0.0), render_priority, ppu)
		x += pitch


func _glyph_quad(size_px: Vector2, mat: ShaderMaterial, ppu: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_px * ppu
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)  # top-left anchor
	mi.material_override = mat
	return mi


static func _ink(c: Color) -> Vector4:
	return Vector4(c.r, c.g, c.b, c.a)
