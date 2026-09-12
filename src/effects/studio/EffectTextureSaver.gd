extends RefCounted
## The texture half of the Studio game→file→bin repack (#280, ADR-0199) — the
## counterpart to EffectTimeScaleSaver.
##
## Given an effect id and the RGBA .tga bytes an author imported, it writes that
## .tga out and shells to the byte-exact Python writer
## (`write_effect_texture.py`), which owns the index-delta quantization: it reads
## the ORIGINAL indexed plane out of the base BIN — the only place that plane
## exists — and keeps the index of every texel the author did not repaint.
##
## COMPOSITION. `save` accepts a `base_bin_override` so this patch layers on top
## of the previous writer's output BIN. The texture section is the file's LAST
## section and disjoint from every other, so it composes in any order.
##
## The CLUT is never written (ADR-0199 dec. 1): the two 512-byte palettes and the
## 4-byte VRAM header ride through verbatim.
##
## No `class_name` (ADR-0004).

const OUT_DIR := "res://authored_effects"
const BASE_BIN_REL := "../project-assets/fft-extract/EFFECT/%s.BIN"


## Repack effect `effect_id`'s texture from the authored .tga bytes.
## Empty bytes → nothing to save (the sheet is still the ROM's), reported as a
## no-op rather than an error. Returns {ok, out_path, error, no_edit}.
static func save(effect_id: int, authored_tga: PackedByteArray,
		base_bin_override: String = "") -> Dictionary:
	var eff := "E%03d" % effect_id
	if authored_tga.is_empty():
		return {"ok": true, "out_path": "", "error": "", "no_edit": true}

	var base_bin: String = base_bin_override
	if base_bin.is_empty():
		base_bin = ProjectSettings.globalize_path("res://").path_join(BASE_BIN_REL % eff).simplify_path()
	if not FileAccess.file_exists(base_bin):
		return {"ok": false, "out_path": "", "error":
			"base %s.BIN not found at %s" % [eff, base_bin], "no_edit": false}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tga_res := "%s/%s.texture.tga" % [OUT_DIR, eff]
	var tf := FileAccess.open(tga_res, FileAccess.WRITE)
	if tf == null:
		return {"ok": false, "out_path": "", "error": "cannot write %s" % tga_res,
			"no_edit": false}
	tf.store_buffer(authored_tga)
	tf.close()

	var out_bin_abs := ProjectSettings.globalize_path("%s/%s.BIN" % [OUT_DIR, eff])
	var args := [
		"run", "--project", ProjectSettings.globalize_path("res://tools"),
		"python", ProjectSettings.globalize_path("res://tools/write_effect_texture.py"),
		"--base-bin", base_bin,
		"--tga", ProjectSettings.globalize_path(tga_res),
		"--out-bin", out_bin_abs,
	]
	var output: Array = []
	var code := OS.execute("uv", args, output, true)
	if code != 0:
		return {"ok": false, "out_path": "", "no_edit": false,
			"error": "writer exit %d: %s" % [code, "\n".join(output)]}

	return {"ok": true, "out_path": out_bin_abs, "error": "", "no_edit": false}


## Write the effect's CURRENT sheet out as an RGBA .tga for an author to paint.
## Returns {ok, path, error}.
static func export_tga(effect_id: int, texture: Texture2D, dest_path: String) -> Dictionary:
	if texture == null:
		return {"ok": false, "path": "", "error": "this effect has no texture to export"}
	var Tga = load("res://src/effects/studio/TextureTga.gd")
	var img: Image = texture.get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)

	var bytes: PackedByteArray = Tga.encode(img.get_width(), img.get_height(), img.get_data())
	var f := FileAccess.open(dest_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "path": "", "error": "cannot write %s" % dest_path}
	f.store_buffer(bytes)
	f.close()
	return {"ok": true, "path": dest_path, "error": ""}
