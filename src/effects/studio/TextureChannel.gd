extends RefCounted
## Write-side channel for TEXTURE replacement (#280, ADR-0199).
##
## The texture is the sheet every frame UVs into: `texture_ptr` -> EOF, the
## file's last section and its largest gap (33,796 B). v1 replaces it from a
## same-dimensions RGBA .tga with the CLUT held FIXED.
##
## WHAT THIS CHANNEL OWNS. The index-delta quantization (ADR-0199 dec. 2) needs
## the ORIGINAL indexed plane, which exists only in the BIN — the asset dir
## carries colours (texture.tga) and the CLUT (texture_palette.json) but no
## plane. So quantization lives in `godot-learning/tools/write_effect_texture.py`
## (corpus-guarded over 338 effects) and runs at save time. This channel owns
## what only the live session can: the scope verdict, the preview swap, and the
## authored bytes the saver hands to Python.
##
## Undo is a SNAPSHOT, not a scalar (ADR-0199 dec. 5) — a 33 KB sheet has no
## meaningful before/after scalar — mirroring the `"feds"` bank swap.
##
## No `class_name` (ADR-0004).

const Tga = preload("res://src/effects/studio/TextureTga.gd")


## Can this effect's sheet be authored through a flat RGBA image?
##
## Mirrors `write_effect_texture.authorable`, which gates the byte writer. This
## copy reads the LIVE framesets so the inspector can explain a refusal without
## shelling out to Python; the two must agree, and the Python side is the one
## the corpus guard proves.
static func authorable(framesets: Array) -> Dictionary:
	var depths := {}
	var subs := {}
	for fs in framesets:
		for fr in fs.get("frames", []):
			depths[bool(fr.get("is_8bpp", false))] = true
			subs[int(fr.get("palette_id", 0))] = true

	if depths.size() != 1:
		return {"ok": false, "reason":
			"the sheet's colour depth cannot be established — no frame references it, "
			+ "or its frames disagree on depth — so refusing rather than assuming 8bpp"}
	if not depths.has(true):
		return {"ok": false, "reason":
			"4bpp sheets render through per-frame 16-colour sub-palettes, so one flat "
			+ "RGBA export cannot show the sheet truthfully — faithful 4bpp authoring "
			+ "is a follow-on"}
	if subs.size() > 1:
		var ids := subs.keys()
		ids.sort()
		return {"ok": false, "reason":
			"this sheet is drawn through sub-palettes %s, so a single flat export would "
			% str(ids) + "show most of it in the wrong colours"}
	return {"ok": true, "reason": ""}


## Replace the live sheet with an imported RGBA image.
##
## Swaps the preview texture and keeps the authored TGA bytes for the saver.
## Returns `{ok, error, texture_snapshot, invalidates_sim}`; the snapshot is what
## the choke point records for undo.
static func replace(data, rgba: PackedByteArray, width: int, height: int) -> Dictionary:
	var current: Vector2i = _dimensions(data)
	if width != current.x or height != current.y:
		return {"ok": false, "error":
			"imported sheet is %dx%d but this effect's texture is %dx%d — v1 replaces "
			% [width, height, current.x, current.y]
			+ "at the same dimensions only (a resize cascades into every frame's UVs)"}
	if rgba.size() != width * height * 4:
		return {"ok": false, "error":
			"expected %d RGBA bytes for %dx%d, got %d"
			% [width * height * 4, width, height, rgba.size()]}

	var snapshot := {
		"texture": data.texture,
		"authored_texture_tga": data.authored_texture_tga,
	}
	var img := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
	data.texture = ImageTexture.create_from_image(img)
	data.authored_texture_tga = Tga.encode(width, height, rgba)
	return {
		"ok": true,
		"error": "",
		"texture_snapshot": snapshot,
		# The sheet is sampled by every particle sprite, so a swap only reaches
		# the preview through a re-fold.
		"invalidates_sim": true,
	}


## Restore a snapshot taken by `replace`, wholesale — the verb never mutated it.
static func restore(data, snapshot: Dictionary) -> void:
	data.texture = snapshot.get("texture", null)
	data.authored_texture_tga = snapshot.get("authored_texture_tga", PackedByteArray())


static func _dimensions(data) -> Vector2i:
	if data.texture == null:
		return Vector2i.ZERO
	return Vector2i(data.texture.get_width(), data.texture.get_height())
