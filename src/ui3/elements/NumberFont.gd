class_name NumberFont
extends RefCounted
## FFT's HUD number font (#91), extracted from EVENT/FRAME.BIN.
##
## The bottom-left vitals draw a blocky two-tone menu/number font through the menu
## CLUT 0x7cbc (same CLUT as the Hp/Mp/Ct labels). tools/parse_frame_font.py
## extracts the clean ISO source into FRAMEFONT.tga + .json. The file carries TWO
## authored sizes (`big` 8x16, `small` 6x10) — but the HP/MP/CT readout uses the
## SMALL set for EVERYTHING: cur, the bridging `/`, and max are all one size, with
## max staggered a baseline lower-right (disasm: the HUD builder FUN_801363dc
## @0x801363dc draws each fraction via the small digit routine FUN_8014aec0
## @0x8014aec0; U = digit*6 + 0x78). The big set is FFT's larger number font for
## other displays. See docs/frame-bin-number-font.md.
##
## This resource owns the atlas + per-glyph cells + metrics and LAYS OUT a number
## string or a cur/max pair into glyph placements; the caller (UIUnitInfoWindow)
## renders each placement as one index->CLUT quad. See docs/hud-number-font.md.
##
## Usage:
##   var font := NumberFont.new()
##   for g in font.place_pair(cur, maximum, divider_x, row_y):
##       draw_cell(g["cell"], g["pos"], g["size"])   # caller-supplied quad
##
## Vault: [[Formation Screen Compositing]]
## Vault: [[Formation Vitals And Nameplate]]
## Vault: [[Learn Job Picker]]

const DEFAULT_JSON := "res://assets/sprites/textures/FRAMEFONT.json"

const BIG := "big"
const SMALL := "small"

var texture: Texture2D = null            ## FRAMEFONT.tga (indexed-as-grayscale)
var clut: int = 0x7CBC                   ## menu CLUT the font renders through
var max_baseline_dy: float = 4.0         ## `max` top sits this many px below `cur`

## The HP/MP/CT vitals draw cur, '/', and max ALL in the small set (same size);
## the manifest pins which set each part uses (disasm: FUN_801363dc draws the
## whole fraction via the small routine FUN_8014aec0). Defaults are the vitals
## reality; the big set stays available via place_number(text, ..., BIG).
var cur_size: String = SMALL
var max_size: String = SMALL
var slash_size: String = SMALL

var _cells: Dictionary = {}              ## size -> { glyph -> Rect2 }
var _advance: Dictionary = {}            ## size -> float (px between glyph origins)


func _init(json_path: String = DEFAULT_JSON) -> void:
	load_manifest(json_path)


func load_manifest(json_path: String) -> bool:
	if not FileAccess.file_exists(json_path):
		push_error("NumberFont: missing manifest %s" % json_path)
		return false
	var json := JSON.new()
	if json.parse(FileAccess.open(json_path, FileAccess.READ).get_as_text()) != OK:
		push_error("NumberFont: JSON parse error in %s" % json_path)
		return false
	var data: Dictionary = json.data
	var base := json_path.get_base_dir()

	var tex_name: String = data.get("texture", "")
	if tex_name != "" and ResourceLoader.exists(base + "/" + tex_name):
		texture = load(base + "/" + tex_name)

	clut = int(data.get("clut", clut))
	max_baseline_dy = float(data.get("max_baseline_dy", max_baseline_dy))
	cur_size = str(data.get("cur_size", cur_size))
	max_size = str(data.get("max_size", max_size))
	slash_size = str(data.get("slash_size", slash_size))

	_cells.clear()
	_advance.clear()
	for s in data.get("sets", []):
		var size := str(s.get("size", ""))
		var by_glyph: Dictionary = {}
		for c in s.get("cells", []):
			by_glyph[str(c.get("glyph", ""))] = Rect2(
					c.get("x", 0), c.get("y", 0), c.get("w", 0), c.get("h", 0))
		_cells[size] = by_glyph
		_advance[size] = float(s.get("advance", 5.0))
	return not _cells.is_empty()


func has_size(size: String) -> bool:
	return _cells.has(size)


func advance_for(size: String) -> float:
	"""Px between glyph origins for `size` (big `cur` digits sit wider apart than
	small `max` digits — the two authored sizes kern differently)."""
	return _advance.get(size, 5.0)


func cell_for(glyph: String, size: String = BIG) -> Rect2:
	"""The FRAMEFONT atlas cell for `glyph` in the given size. Unknown glyphs fall
	back to '0' (so a number string never crashes on a stray char)."""
	var by_glyph: Dictionary = _cells.get(size, {})
	if by_glyph.has(glyph):
		return by_glyph[glyph]
	return by_glyph.get("0", Rect2())


## Lay out a number string into glyph placements at the fixed advance. Each entry
## is { "glyph": String, "cell": Rect2, "pos": Vector2, "size": String }, in
## left-to-right order. `right_align` ends the run at `x` (the cur numerator
## right-aligns to the divider); otherwise the run starts at `x`. `scale` (1.0 =
## native HUD size) scales the advance so glyph spacing tracks glyph size.
## `pad_width` > 0 left-pads a numeric `text` with leading zeros to that many digits,
## exactly as FFT's fixed-field HUD number routine does (e.g. `44` -> `044`, `5` -> `05`
## — the oracle roster shows `044/044`, `Exp.05`). Only pass a numeric string when padding.
func place_number(text: String, x: float, y: float, size: String = BIG,
		right_align: bool = false, scale: float = 1.0, pad_width: int = 0) -> Array:
	if pad_width > 0 and text.is_valid_int():
		text = text.pad_zeros(pad_width)
	var out: Array = []
	var pitch := advance_for(size) * scale
	var draw_x := (x - text.length() * pitch) if right_align else x
	for ch in text:
		out.append({"glyph": ch, "cell": cell_for(ch, size),
				"pos": Vector2(draw_x, y), "size": size})
		draw_x += pitch
	return out


## Lay out a full `cur/max` block exactly as FFT composes it for the vitals:
## `cur` right-aligned to `divider_x`, the bridging `/`, then `max` staggered
## down-right — ALL in the same (small) size per the manifest (`cur_size`,
## `slash_size`, `max_size`). `slash_offset`/`max_offset` are relative to
## (divider_x, y) and scale with `scale`; the defaults are the measured
## composition (slash bridges, max +(advance, baseline)).
func place_pair(cur: int, maximum: int, divider_x: float, y: float,
		slash_offset: Vector2 = Vector2(0, 2),
		max_offset: Vector2 = Vector2(5, max_baseline_dy),
		scale: float = 1.0, pad_width: int = 0) -> Array:
	var cur_s := str(cur)
	var max_s := str(maximum)
	if pad_width > 0:
		cur_s = cur_s.pad_zeros(pad_width)
		max_s = max_s.pad_zeros(pad_width)
	return place_pair_text(cur_s, max_s, divider_x, y, slash_offset, max_offset, scale)


## Lay out a `cur/max` block from already-formatted STRINGS (zero-padded digits, or the
## out-of-battle roster CT dashes `---`). `cur` right-aligns to `divider_x`, then the slash,
## then `max` staggered down-right — same composition as [method place_pair]. The dash `-`
## is a real font glyph (FRAMEFONT index 11), so `"---"` renders three dash cells occupying
## the same slots the three digits would (matches the oracle `Ct ---/---`).
##
## `field_width` > 0 makes each part a fixed-width right-aligned NUMERIC field (§15.26 §D,
## defect #9): a numeric part zero-pads to that width (`44` -> `044`, so the number strip's
## `0x78+6*d` cells always render 3), while a non-numeric BLANKED part (the equip-picker
## preview's "-" numerator) CENTERS in the field — the ROM blanks a numeral to dash cell
## `0xba` in the MIDDLE digit cell of the fixed 3-cell field (" - ", never "  -").
func place_pair_text(cur_text: String, max_text: String, divider_x: float, y: float,
		slash_offset: Vector2 = Vector2(0, 2),
		max_offset: Vector2 = Vector2(5, max_baseline_dy),
		scale: float = 1.0, field_width: int = 0) -> Array:
	var cur_end_x := divider_x
	if field_width > 0:
		var signed_delta := cur_text.length() > 1 and (cur_text[0] == "+" or cur_text[0] == "-")
		if signed_delta:
			# A SIGNED numerator ("+5"/"-1", equip stat-DELTA preview) right-aligns to the divider
			# like a plain number (cur_end_x stays divider_x) and is NOT zero-padded — the sign
			# must stay adjacent to the digit ("+5", never "+05"). (is_valid_int() is true for a
			# signed string, so this MUST precede the pad branch.)
			pass
		elif cur_text.is_valid_int():
			cur_text = cur_text.pad_zeros(field_width)
		else:
			# Blanked numerator: end the right-aligned run at the cell after the field's
			# middle cell, so a single dash lands centered ((field_width-1)/2 from the left).
			var mid := (field_width - 1) / 2
			cur_end_x = divider_x - advance_for(cur_size) * scale * float(field_width - 1 - mid)
		if max_text.is_valid_int():
			max_text = max_text.pad_zeros(field_width)
	var out := place_number(cur_text, cur_end_x, y, cur_size, true, scale)
	out.append({"glyph": "/", "cell": cell_for("/", slash_size),
			"pos": Vector2(divider_x + slash_offset.x * scale, y + slash_offset.y * scale),
			"size": slash_size})
	out += place_number(max_text, divider_x + max_offset.x * scale,
			y + max_offset.y * scale, max_size, false, scale)
	return out
