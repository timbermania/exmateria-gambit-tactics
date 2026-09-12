class_name FramesetChannel
extends RefCounted
## Write-side channel encoder for FRAME fields (#278). A frame is a plain
## JSON-shaped Dictionary at `data.framesets[frameset_index]["frames"][frame_index]`
## (no wrapper class, unlike palette/screen's typed Keyframe — matches
## `parse_frame()`'s output shape verbatim: `godot-learning/tools/parse_effect.py`).
## `apply_raw` writes one raw field on the live frame dict, recomputes the
## derived `blend_mode` name cache when `semi_trans_mode` changes, and returns
## the snapshot the choke point records for undo.
##
## Frames are READ-LIVE — `EffectParticleRenderer` re-reads
## `effect_data.framesets` every draw — so an edit reaches the preview in
## place with no re-seek (`invalidates_sim = false`), mirroring ScreenChannel.
##
## v1 SCOPE (locked via /grill-with-docs 2026-08-17, see #278): IN-PLACE FIELD
## EDITS ONLY. No add/remove/reorder of frames within a frameset, framesets
## within the section, or frameset-group membership — this channel has no
## `insert_event`/`delete_event`/`snapshot`/`restore` verbs by design; every
## edit is a scalar byte write the choke point's default undo path replays.
## Channels supply encoders, not mutation logic; the single choke point is
## `EffectEditSession.apply_edit` (#255).

const Canvas = preload("res://src/effects/studio/FramesetCanvas.gd")

const _BLEND_NAMES := ["BLEND_50", "ADD", "SUB", "ADD_25"]

# Author-facing / on-disk field name → top-level scalar key on the frame dict.
const _SCALAR_FIELD := {
	"palette_id": "palette_id",
	"semi_trans_on": "semi_trans_on",
	"is_8bpp": "is_8bpp",
}

# UV field name → key inside frame.uv.
const _UV_FIELD := {
	"uv_x": "x", "uv_y": "y", "uv_width": "width", "uv_height": "height",
}

# Vertex field name → [vertices corner key, component index (0=x, 1=y)].
const _VERTEX_FIELD := {
	"vertex_tl_x": ["top_left", 0], "vertex_tl_y": ["top_left", 1],
	"vertex_tr_x": ["top_right", 0], "vertex_tr_y": ["top_right", 1],
	"vertex_bl_x": ["bottom_left", 0], "vertex_bl_y": ["bottom_left", 1],
	"vertex_br_x": ["bottom_right", 0], "vertex_br_y": ["bottom_right", 1],
}


## Write one raw field for the frame named by `field_ref`, recompute the
## derived `blend_mode` cache when relevant, and return the snapshot the
## choke point records for undo.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var frame: Dictionary = _resolve_frame(data, field_ref)
	if frame.is_empty():
		push_error("FramesetChannel: no frame for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")

	if field == "semi_trans_mode":
		return _apply_semi_trans_mode(frame, int(new_raw))

	if _SCALAR_FIELD.has(field):
		var key: String = _SCALAR_FIELD[field]
		var before = frame.get(key)
		frame[key] = int(new_raw)
		return _result(before, int(new_raw), _faithful_verdict(field, int(new_raw)))

	if _UV_FIELD.has(field):
		var key: String = _UV_FIELD[field]
		var uv: Dictionary = frame.get("uv", {})
		var before = uv.get(key)
		uv[key] = int(new_raw)
		frame["uv"] = uv
		# `before` is what the EXTRACTOR produced for this axis, which is the only
		# evidence here of the sign flag that decides the byte's range.
		return _result(before, int(new_raw), _faithful_verdict(field, int(new_raw), before))

	if _VERTEX_FIELD.has(field):
		var addr: Array = _VERTEX_FIELD[field]
		var corner: String = addr[0]
		var comp: int = addr[1]
		var vertices: Dictionary = frame.get("vertices", {})
		var pair: Array = vertices.get(corner, [0, 0])
		var before = pair[comp]
		pair[comp] = int(new_raw)
		vertices[corner] = pair
		frame["vertices"] = vertices
		return _result(before, int(new_raw), _faithful_verdict(field, int(new_raw)))

	push_error("FramesetChannel: unknown frame field '%s'" % field)
	return {}


static func _result(before, after: int, faithful: Dictionary) -> Dictionary:
	return {
		"before_raw": before,
		"after_raw": after,
		"invalidates_sim": false,
		"faithful": faithful,
	}


## semi_trans_mode (2-bit blend enum, 0-3) also drives the derived `blend_mode`
## display-name cache (`BLEND_50`/`ADD`/`SUB`/`ADD_25`) — mirrors
## `parse_frame()`'s own `["BLEND_50","ADD","SUB","ADD_25"][semi_trans_mode]`.
static func _apply_semi_trans_mode(frame: Dictionary, new_mode: int) -> Dictionary:
	var before: int = int(frame.get("semi_trans_mode", 0))
	frame["semi_trans_mode"] = new_mode
	frame["blend_mode"] = _BLEND_NAMES[new_mode] if new_mode >= 0 and new_mode < _BLEND_NAMES.size() \
		else _BLEND_NAMES[0]
	return _result(before, new_mode, _semi_trans_mode_verdict(new_mode))


static func _semi_trans_mode_verdict(mode: int) -> Dictionary:
	if mode < 0 or mode > 3:
		return {"ok": false, "reason": "semi_trans_mode = %d does not fit the 2-bit encoding (0-3)" % mode}
	return {"ok": true, "reason": ""}


## Non-destructive Faithful advisory (#255): Free always accepts the write, but
## a frame field only lowers to E###.BIN if it fits its on-disk encoding width.
## palette_id is 4 bits (byte0 low nibble); the bool flags are single bits.
## uv_x/uv_y are PLAIN unsigned bytes (`parse_frame` applies no sign correction
## to them — only width/height get that treatment via the width_signed/
## height_signed flag bits, which are NOT editable in v1).
##
## uv_width/uv_height were bounded to a FLAT -128..127 on the reasoning that the
## writer "always encodes correctly regardless (masks to the low byte either
## way); this is advisory-only imprecision, not a round-trip bug". Running the
## round trip for real (ADR-0099 step 2, over all 401 E###.BIN files) falsified
## both halves. The mask is only correct INSIDE the frame's real range: E027
## stores a region at width -128, and writing -136 masks to byte 120, which the
## still-set sign flag reads back as +120 — the value AND the flip lost, which
## is a round-trip bug, not a Free-only advisory. And the flat bound falsely
## flagged the 219 corpus frames whose dimension exceeds 127 (E022 stores height
## 176) even though those round-trip perfectly.
##
## So the bound is per-frame, inferred from the value the extractor produced —
## `FramesetCanvas.encodable_uv_range`, the same primitive the region write path
## asks before release. Vertices are signed 16-bit.
static func _faithful_verdict(field: String, raw: int, current = null) -> Dictionary:
	var bounds: Dictionary = {
		"palette_id": [0, 15],
		"semi_trans_on": [0, 1],
		"is_8bpp": [0, 1],
		"uv_x": [0, 255], "uv_y": [0, 255],
	}
	if field == "uv_width" or field == "uv_height":
		var r := Canvas.encodable_uv_range(0 if current == null else int(current))
		bounds[field] = [r.x, r.y]
	if bounds.has(field):
		var lo: int = bounds[field][0]
		var hi: int = bounds[field][1]
		if raw < lo or raw > hi:
			return {"ok": false, "reason": "%s = %d is outside the %d..%d byte encoding (Free-only)" % [field, raw, lo, hi]}
		return {"ok": true, "reason": ""}
	# Vertex fields are signed s16 — the full authoring range fits.
	if raw < -32768 or raw > 32767:
		return {"ok": false, "reason": "%s = %d does not fit a signed 16-bit vertex (Free-only)" % [field, raw]}
	return {"ok": true, "reason": ""}


static func _resolve_frame(data, field_ref: Dictionary) -> Dictionary:
	if data == null or not (data.framesets is Array):
		return {}
	var fs_idx: int = int(field_ref.get("frameset_index", -1))
	if fs_idx < 0 or fs_idx >= data.framesets.size():
		return {}
	var fs = data.framesets[fs_idx]
	if not (fs is Dictionary):
		return {}
	var frames = fs.get("frames", [])
	if not (frames is Array):
		return {}
	var fr_idx: int = int(field_ref.get("frame_index", -1))
	if fr_idx < 0 or fr_idx >= frames.size():
		return {}
	var frame = frames[fr_idx]
	return frame if frame is Dictionary else {}
