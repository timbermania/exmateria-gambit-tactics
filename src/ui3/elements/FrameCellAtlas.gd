class_name FrameCellAtlas
extends RefCounted
## FRAME.BIN word cells as an index→CLUT sprite source (LEARN_PICKER.md round 9).
##
## `assets/ui/frame.tga` is not just the 9-slice chrome [UIFrame] tiles: its left/middle
## columns are BAKED UI WORD CELLS — `Move Job :` / `Jump Brave` / `Wt Faith Lv.` /
## `Hp Mp CT Br Jp` / `Total Next ALL Check …`. The ROM draws those cells as 4bpp indexed
## quads through whatever CLUT the screen wants, which is how the SAME cell reads dark-on-tan
## inside a panel and CREAM-on-dark above one (the Learn job picker's five column headers,
## §9.2 — five live FT4 quads, all CLUT 0x7CBC).
##
## `tools/parse_frame.py` decodes FRAME.BIN's 4bpp pixels through PALETTE 0 (file offset
## 0x9000) and emits the sheet as flat RGBA, so the index information is recoverable exactly:
## every pixel's colour IS `PALETTE0[index]`. This class inverts that — crop a cell, map each
## pixel back to its 4bpp index, and hand back the grayscale INDEX bitmap
## (`value = index × 17`) that `vitals_sprite.gdshader` already speaks, so a caller pairs it
## with any 16-entry CLUT texture the way it would a RANGETILE cell.
##
## Usage:
##   var tex := FrameCellAtlas.index_texture(Rect2i(22, 32, 17, 8))   # the "Job" word cell
##   mat.set_shader_parameter("index_atlas", tex)
##   mat.set_shader_parameter("atlas_size", Vector2(17, 8))
##   mat.set_shader_parameter("cell", Vector4(0, 0, 17, 8))
##   mat.set_shader_parameter("palette_tex", clut_0x7cbc)

const TEXTURE_PATH := "res://assets/ui/frame.tga"

## FRAME.BIN palette 0 (offset 0x9000), BGR555→RGBA in INDEX ORDER — the table
## `tools/parse_frame.py` decodes the sheet with. Index 0 is the transparent key (the
## shader discards it), so the sheet's 16 distinct colours address 1:1 back to 4bpp indices.
const PALETTE0: Array[Color] = [
	Color8(0, 0, 0, 0),        # 0  transparent key
	Color8(48, 40, 32, 255),   # 1  dark ink   (cream 0xE7E7E7 under CLUT 0x7CBC)
	Color8(80, 80, 64, 255),   # 2
	Color8(128, 120, 104, 255),# 3
	Color8(152, 144, 120, 255),# 4
	Color8(96, 88, 72, 255),   # 5
	Color8(112, 104, 88, 255), # 6
	Color8(136, 128, 112, 255),# 7
	Color8(160, 152, 128, 255),# 8
	Color8(104, 40, 16, 255),  # 9
	Color8(120, 72, 56, 255),  # 10
	Color8(136, 120, 104, 255),# 11
	Color8(168, 160, 136, 255),# 12
	Color8(32, 24, 16, 255),   # 13
	Color8(112, 104, 80, 255), # 14
	Color8(208, 200, 168, 255),# 15
]

## Index bitmaps are immutable per cell and shared by every caller — cache them process-wide.
static var _cell_cache: Dictionary = {}
static var _sheet: Image = null
static var _rgb_to_index: Dictionary = {}


## The INDEX bitmap for `cell` (frame.tga pixels) as an `ImageTexture` the sprite shader can
## sample with `cell = (0, 0, w, h)` and `atlas_size = cell.size`. Null when the sheet is
## missing or the rect is empty. Cached.
static func index_texture(cell: Rect2i) -> ImageTexture:
	if cell.size.x <= 0 or cell.size.y <= 0:
		return null
	var key := "%d,%d,%d,%d" % [cell.position.x, cell.position.y, cell.size.x, cell.size.y]
	if _cell_cache.has(key):
		return _cell_cache[key]
	var sheet := _sheet_image()
	if sheet == null:
		return null
	var bounds := Rect2i(0, 0, sheet.get_width(), sheet.get_height())
	if not bounds.encloses(cell):
		push_error("FrameCellAtlas: cell %s is outside frame.tga %s" % [cell, bounds])
		return null
	# Walk the raw RGBA8 bytes rather than get_pixel(): the importer's `fix_alpha_border`
	# rewrites the RGB of fully transparent pixels, so alpha is the ONLY reliable read for
	# index 0 — and byte compares can't drift the way float Color equality can.
	var data := sheet.get_data()
	var stride := sheet.get_width() * 4
	var img := Image.create(cell.size.x, cell.size.y, false, Image.FORMAT_RGBA8)
	for y in cell.size.y:
		var row := (cell.position.y + y) * stride
		for x in cell.size.x:
			var o := row + (cell.position.x + x) * 4
			var idx := 0 if data[o + 3] < 128 else _index_for(data[o], data[o + 1], data[o + 2])
			# The shader reads `int(r * 15 + 0.5)`, i.e. the RANGETILE "index × 17" grayscale.
			var v := float(idx * 17) / 255.0
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_cell_cache[key] = tex
	return tex


## The decoded sheet (loaded once). Null + a pushed error if the asset is absent — a missing
## gitignored ROM-derived sheet is a setup problem, not a silently blank header.
static func _sheet_image() -> Image:
	if _sheet != null:
		return _sheet
	var tex: Texture2D = load(TEXTURE_PATH)
	if tex == null:
		push_error("FrameCellAtlas: could not load %s (see SETUP.md)" % TEXTURE_PATH)
		return null
	_sheet = tex.get_image()
	if _sheet != null and _sheet.get_format() != Image.FORMAT_RGBA8:
		_sheet.convert(Image.FORMAT_RGBA8)
	return _sheet


## The 4bpp index whose PALETTE0 entry is this RGB. Unknown colours fall back to index 0
## (transparent) — a sheet that no longer decodes through palette 0 should read as a hole,
## not as arbitrary ink.
static func _index_for(r: int, g: int, b: int) -> int:
	if _rgb_to_index.is_empty():
		for i in PALETTE0.size():
			var c: Color = PALETTE0[i]
			_rgb_to_index[(int(c.r8) << 16) | (int(c.g8) << 8) | int(c.b8)] = i
	return int(_rgb_to_index.get((r << 16) | (g << 8) | b, 0))
