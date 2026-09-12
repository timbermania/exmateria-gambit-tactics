extends RefCounted
## Inspector projector for the effect's TEXTURE sheet (#280, ADR-0199 dec. 6).
##
## The sheet is the indexed image every frame UVs into — the file's last section
## and its largest gap (33,796 B). This surface carries the sheet's metadata and
## the two halves of the artist round trip: Export writes an RGBA .tga matching
## `extract_effect_texture.lua` byte for byte, Import reads one back.
##
## A sheet outside v1 scope offers NO actions and says why. That includes
## Export: for a 4bpp sheet the flat RGBA export is itself the untruthful
## artifact — 58 of the 60 4bpp effects render through 3-7 per-frame
## sub-palettes, so one palette's decode shows most of the sheet in the wrong
## colours. Handing an artist that file is the failure this refusal prevents.
##
## No `class_name` (ADR-0004).

const Channel = preload("res://src/effects/studio/TextureChannel.gd")
const _Fields = preload("res://src/effects/studio/ProjectorField.gd")


## Header rows follow the contract EffectKeyframeInspector._render_header_rows
## enforces: each row is `{label, value}` (or `{label, link}`). That renderer
## indexes row["label"] HARD, so any other shape crashes the inspector when the
## row is clicked into — not at projection time.
static func header(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var facts: Dictionary = _facts(effect_data)
	var rows: Array = [
		{"label": "Sheet", "value": "%d×%d · %s" % [
			facts["width"], facts["height"], facts["depth"]]},
	]
	var verdict: Dictionary = Channel.authorable(effect_data.framesets)
	if not verdict.get("ok", false):
		rows.append({"label": "Replaceable", "value": "no — see below"})
	return rows


static func sections(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var facts: Dictionary = _facts(effect_data)
	var verdict: Dictionary = Channel.authorable(effect_data.framesets)

	var fields: Array = [
		_Fields.const_field("Dimensions", "%d×%d" % [facts["width"], facts["height"]],
			"The sheet's texel size. v1 replaces at the SAME dimensions only — a shape "
			+ "change cascades into every frame's UV fields."),
		_Fields.const_field("Colour depth", facts["depth"],
			"Read from the frames' own render flag (flags_byte0 bit 7), NOT the texture "
			+ "header's +0x403 byte — that one selects the VRAM upload stride and "
			+ "disagrees for every 4bpp effect."),
		_Fields.const_field("Sub-palette", facts["sub_palettes"],
			"Which 16-colour CLUT window the frames draw through (flags_byte0 & 0x0F). "
			+ "More than one means a single flat export cannot show the sheet truthfully."),
		_Fields.const_field("Dual palette", facts["dual_palette"],
			"Which CLUT LINE the frames read their sub-palette from — flags_byte0 bit 4 "
			+ "picks palette 2 (VRAM 0x7B40) over palette 1 (0x7B00), a static per-sprite "
			+ "choice verified at 0x801a5664. Both palettes are always uploaded."),
		_Fields.const_field("VRAM upload", facts["vram_upload"],
			"The texture section's 4-byte header at +0x400. The 24-bit value there is the "
			+ "PIXEL DATA SIZE, not a Y coordinate — measured equal to the plane's byte "
			+ "count in all 401 effects; the engine divides it by the row stride to get "
			+ "height. Upload X is a fixed 0x180 and no Y is encoded in the file."),
		_Fields.const_field("Palette", "fixed — %d entries" % facts["clut_size"],
			"Import matches painted colours INTO this palette; it never rewrites it. "
			+ "8bpp sheets already average 162 of 256 colours, so there is no headroom "
			+ "to re-derive one without evicting colours the sheet still uses."),
	]

	if not verdict.get("ok", false):
		fields.append(_Fields.const_field("Not replaceable", verdict.get("reason", ""),
			"This sheet is outside #280 v1's scope, so neither direction of the round "
			+ "trip is offered — an export you cannot trust is worse than none."))
		return [{"title": "Texture", "fields": fields}]

	fields.append({
		"name": "Export",
		"shape": "action",
		"label": "⭳ Export .tga",
		"tooltip": "Write this sheet as a 32-bit RGBA .tga — the same bytes "
			+ "extract_effect_texture.lua produces. Paint it in any tool that opens "
			+ "TGA with alpha, then bring it back with Import.",
		"action": {"kind": "texture_export"},
	})
	fields.append({
		"name": "Import",
		"shape": "action",
		"label": "⭱ Import .tga",
		"tooltip": "Replace this sheet from a %d×%d RGBA .tga. Colours are matched into "
			% [facts["width"], facts["height"]]
			+ "the existing palette (which never changes); texels you did not repaint "
			+ "keep the exact index they had. Undoable (Ctrl+Z).",
		# The action declares the channel it WRITES so the manifest guard can see
		# this subsystem is wired: the texture is authored by a wholesale
		# replacement, not by any shape:"edit" field row.
		"action": {"kind": "texture_import", "channel": "texture"},
	})
	return [{"title": "Texture", "fields": fields}]


## The public read of `_facts`, for surfaces other than this projector's own rows.
##
## ADR-0130 gives the texture TWO surfaces — this page and the tab on the inspector row —
## and they must never disagree about a sheet's depth, sub-palette or dual-palette state.
## Two surfaces quoting different numbers for the same sheet is a defect that reads on
## screen as a rendering bug, so the tab reads THIS, not a second derivation.
static func facts(effect_data) -> Dictionary:
	return _facts(effect_data)


## Sheet facts the inspector can honestly read from Godot-side assets.
##
## Both facts #262 asked for are now real, via a parser field + asset regen:
## dual-palette-in-use reads the per-frame `uses_palette_2` (flags_byte0 bit 4),
## and the upload rectangle comes from `texture_meta.json`.
##
## There is deliberately NO "VRAM Y" row. The format doc called texture +0x400 a
## "VRAM Y coordinate", but it is the pixel-data SIZE (measured equal to the
## plane's byte count in all 401 effects). The file encodes no Y, so displaying
## one would be a fabrication wearing the right label.
static func _facts(effect_data) -> Dictionary:
	var width := 0
	var height := 0
	if effect_data.texture != null:
		width = effect_data.texture.get_width()
		height = effect_data.texture.get_height()

	var depths := {}
	var subs := {}
	for fs in effect_data.framesets:
		for fr in fs.get("frames", []):
			depths[bool(fr.get("is_8bpp", false))] = true
			subs[int(fr.get("palette_id", 0))] = true

	var depth := "unknown"
	if depths.size() == 1:
		depth = "8bpp" if depths.has(true) else "4bpp"
	elif depths.size() > 1:
		depth = "mixed"

	var ids := subs.keys()
	ids.sort()
	var sub_text := "none referenced" if ids.is_empty() else str(ids)

	# flags_byte0 bit 4, per frame: which CLUT line the sub-palette comes from.
	var pal2 := 0
	var pal1 := 0
	for fs in effect_data.framesets:
		for fr in fs.get("frames", []):
			if bool(fr.get("uses_palette_2", false)):
				pal2 += 1
			else:
				pal1 += 1
	var dual := "palette 1 only"
	if pal2 > 0 and pal1 > 0:
		dual = "BOTH — %d frames on palette 1, %d on palette 2" % [pal1, pal2]
	elif pal2 > 0:
		dual = "palette 2 only (%d frames)" % pal2
	elif pal1 == 0:
		dual = "no frames reference this sheet"

	var meta: Dictionary = effect_data.texture_meta
	var upload := "unknown (texture_meta.json missing — re-run parse_all_effects_py.py)"
	if not meta.is_empty():
		upload = "x=%d, %d bytes/row, %d rows (%s B of pixels)" % [
			int(meta.get("vram_x", 0)), int(meta.get("row_bytes", 0)),
			int(meta.get("height", 0)),
			String.num_uint64(int(meta.get("pixel_data_size", 0)))]

	return {
		"width": width, "height": height, "depth": depth,
		"sub_palettes": sub_text,
		"dual_palette": dual,
		"vram_upload": upload,
		"clut_size": 256 if depths.has(true) else 16,
	}
