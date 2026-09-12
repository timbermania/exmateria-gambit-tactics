extends RefCounted
## The **frameset** / **frame** target-kind projector (ADR-0073, #278). One script
## handles both kinds (the registry `load()`s it for either) since a frame is
## always read through its owning frameset's context:
##
##   "frameset" → the container view: which group it belongs to (display/navigate
##       only — no membership edits in v1, see #278's locked scope) and a LINK row
##       to each child frame (mirrors EmitterTargetProjector's provenance links).
##   "frame"    → the 24-byte sprite-rect record's fields as EDITABLE rows (UV
##       x/y/width/height, 4 signed vertices, palette_id, blend mode, semi_trans_on,
##       is_8bpp — the v1 field set), plus a LINK row back to the owning frameset.
##       texture_page (TPAGE) is read-only in v1 — not part of the approved
##       in-place-edit field set. Those rows are returned as FOUR FOLDABLE SECTIONS
##       (Appearance / Sheet region / Drawn quad / Raw corners / Texture Page),
##       each with a stable
##       `fold_id` — see `_frame_sections` for why the split is ADR-0099's boundary
##       and not a presentation choice.
##
## Frames are plain JSON-shaped Dictionaries (`parse_frame()`'s shape verbatim) —
## no wrapper class. No `class_name` (ADR-0004); model/target loaded at call time
## to avoid a parse-time cycle, mirroring the other target-kind projectors.

## The frame target's section fold ids (ADR-0130's `fold_id` contract). Stable STRINGS,
## because `EffectKeyframeInspector` keys its `_section_state` on them and an edit rebuilds
## the whole inspector — without an id the author's fold choice is lost on every keystroke.
## They are also the handle downstream surfaces filter on: `SequenceFocusBlock` drops the
## TPAGE section and swaps the region one, and it must not do that by matching prose.
const FOLD_APPEARANCE := "frame:appearance"
const FOLD_REGION := "frame:region"
const FOLD_QUAD := "frame:quad"
const FOLD_TPAGE := "frame:tpage"
## The eight raw corner components, kept as a SHUT section beneath the transform view. Not
## an escape hatch for a shape the knobs cannot reach — there is no such shape, the residual
## covers the 0.52% that are not parallelograms — but the only place the bytes that are
## actually stored can be read. See `_quad_transform_fields`.
const FOLD_CORNERS := "frame:corners"

const _BLEND_CHOICES := ["BLEND_50 (50%)", "ADD", "SUB", "ADD_25 (25%)"]
const _OFF_ON := ["Off", "On"]
const _4_8_BPP := ["4bpp", "8bpp"]


static func header(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	match Target.kind(target):
		"frameset":
			return _frameset_header(target, effect_data, Target)
		"frame":
			return _frame_header(target, effect_data, Target)
	return []


static func sections(target: Dictionary, effect_data, score: Dictionary) -> Array:
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	match Target.kind(target):
		"frameset":
			return _frameset_sections(target, effect_data)
		"frame":
			return _frame_sections(target, effect_data, Target)
	return []


static func _frameset_header(target: Dictionary, effect_data, Target) -> Array:
	var fs_idx := int(target.get("ref", {}).get("index", -1))
	var fs := _resolve_frameset(effect_data, fs_idx)
	if fs.is_empty():
		return []
	var frames: Array = fs.get("frames", [])
	var rows: Array = [
		{"label": "Frameset", "value": "index %d (%d frames)" % [fs_idx, frames.size()]},
		{"label": "Group", "value": "group %d (display-only in v1 — see #278)" % _group_for(effect_data, fs_idx)},
	]
	for i in range(frames.size()):
		rows.append({"label": "Frame %d" % i,
			"link": {"label": "frame %d" % i, "target": Target.frame(fs_idx, i)}})
	return rows


static func _frameset_sections(target: Dictionary, effect_data) -> Array:
	var Target = load("res://src/effects/studio/InspectionTarget.gd")
	var fs_idx := int(target.get("ref", {}).get("index", -1))
	var fs := _resolve_frameset(effect_data, fs_idx)
	if fs.is_empty():
		return []
	var fields: Array = [
		# `int()` is not cosmetic here: `frames.json` is parsed by Godot's JSON, which
		# types EVERY number as a float, so the raw value renders as "672.0" — a bit
		# field printed as a decimal, which reads as a measurement rather than a mask.
		{"name": "Header flags", "shape": "const", "value": str(int(fs.get("header_flags", 0)))},
		_sheet_link(Target),
	]
	return [{"title": "Frameset", "fields": fields}]


## The drill-in to the effect's TEXTURE sheet (#280) — the image every frame UVs
## into, carrying its metadata and the Export/Import round trip. Registering the
## `texture` inspection kind does not make it reachable; this link is what mints
## the target, and the frameset/frame inspector is where the frameset canvas
## already puts you.
static func _sheet_link(Target) -> Dictionary:
	return {"name": "Sheet", "shape": "link", "label": "texture",
		"target": Target.texture()}


## `_sheet_actions` was DELETED here — ADR-0130 dec. 6.
##
## It offered a verbatim duplicate of the Texture page's Export/Import pair, and it
## justified itself on the grounds that "repainting is *why* an author is looking at a
## UV rect, so making them drill in put the export a navigation step from the box it
## applies to." That argument is answered rather than ignored: the buttons now live on
## the Texture TAB, which is on every screen — strictly closer to the box than a row on
## the frameset target ever was.
##
## `_sheet_link` above SURVIVES (dec. 7). It is not a place to work, it is the only thing
## that MINTS the `texture` target — registering a kind in `InspectorProjectorRegistry`
## does not make it reachable — so deleting it would strand the page.


static func _frame_header(target: Dictionary, effect_data, Target) -> Array:
	var ref: Dictionary = target.get("ref", {})
	var fs_idx := int(ref.get("frameset_index", -1))
	var fr_idx := int(ref.get("frame_index", -1))
	var frame := _resolve_frame(effect_data, fs_idx, fr_idx)
	if frame.is_empty():
		return []
	return [
		{"label": "Frame", "value": "frameset %d / frame %d" % [fs_idx, fr_idx]},
		{"label": "Frameset", "link": {"label": "frameset %d" % fs_idx, "target": Target.frameset(fs_idx)}},
	]


static func _frame_sections(target: Dictionary, effect_data, Target) -> Array:
	var ref: Dictionary = target.get("ref", {})
	var fs_idx := int(ref.get("frameset_index", -1))
	var fr_idx := int(ref.get("frame_index", -1))
	var frame := _resolve_frame(effect_data, fs_idx, fr_idx)
	if frame.is_empty():
		return []

	var uv: Dictionary = frame.get("uv", {})
	var vertices: Dictionary = frame.get("vertices", {})
	var tpage: Dictionary = frame.get("texture_page", {})

	var f := func(field: String) -> Dictionary:
		return {"channel": "frameset", "frameset_index": fs_idx, "frame_index": fr_idx, "field": field}

	# THREE SECTIONS, NOT ONE FLAT RUN (2026-08-21). The frame target used to emit a single
	# "Frame" section holding sixteen editable rows in one undifferentiated list, ending in
	# eight called `Vertex TL X` … `Vertex BR Y`. Reported as *"this stuff is kind of
	# esoteric. the names aren't good. I think they should be organized better."* All three
	# complaints are answered here rather than in the inspector: `EffectKeyframeInspector`
	# already folds one section per entry and already remembers a `fold_id` across the
	# rebuild an edit fires, so "organised" is a matter of what this function RETURNS.
	#
	# The split is by QUESTION, and each section answers a different one:
	#   Appearance   — how is it coloured and blended?
	#   Sheet region — which box of the sheet does it sample? (SHARED — see ADR-0099)
	#   Drawn quad   — how big, how turned, and where is it drawn? (PER-FRAME, always)
	#
	# That last boundary is the load-bearing one and it is ADR-0099's, not a presentation
	# choice: the region is shared by up to 107 frames and a region edit reaches all of
	# them, while every number under "Drawn quad" belongs to this frame alone. Putting the
	# two in one list was the surface saying they were the same kind of thing.
	var appearance_fields: Array = [
		_sheet_link(Target),
		{"name": "Palette ID", "shape": "edit", "editor": "int", "type": "u8", "min": 0, "max": 15,
			"value": int(frame.get("palette_id", 0)), "field_ref": f.call("palette_id"),
			"tooltip": "Which 16-colour sub-palette of the sheet's CLUT this frame reads through."},
		{"name": "Blend mode", "shape": "edit", "editor": "choice", "choices": _BLEND_CHOICES,
			"value": int(frame.get("semi_trans_mode", 0)), "field_ref": f.call("semi_trans_mode"),
			"tooltip": "The PSX semi-transparency equation. Inert unless Semi-trans on is On."},
		{"name": "Semi-trans on", "shape": "edit", "editor": "choice", "choices": _OFF_ON,
			"value": 1 if bool(frame.get("semi_trans_on", false)) else 0, "field_ref": f.call("semi_trans_on"),
			"tooltip": "Whether the blend mode applies at all. Off draws the sprite opaque."},
		{"name": "8bpp", "shape": "edit", "editor": "choice", "choices": _4_8_BPP,
			"value": 1 if bool(frame.get("is_8bpp", false)) else 0, "field_ref": f.call("is_8bpp"),
			"tooltip": "The sheet's colour depth for this frame — 4bpp reads 16 colours through the sub-palette, 8bpp reads 256."},
	]

	var region_fields: Array = [
		{"name": "UV X", "shape": "edit", "editor": "int", "type": "u8", "min": 0, "max": 255,
			"value": int(uv.get("x", 0)), "field_ref": f.call("uv_x"),
			"tooltip": "The stored origin of the sheet box. NOT always its left edge — a "
				+ "negative width means uv.x names the RIGHT edge and the sprite is mirrored."},
		{"name": "UV Y", "shape": "edit", "editor": "int", "type": "u8", "min": 0, "max": 255,
			"value": int(uv.get("y", 0)), "field_ref": f.call("uv_y"),
			"tooltip": "The stored origin of the sheet box. NOT always its top edge — a "
				+ "negative height means uv.y names the BOTTOM edge and the sprite is flipped."},
		# The spinbox range is this FRAME's, not a constant. The sign of uv.width/height
		# lives in a per-frame, per-axis flag bit that `frames.json` does not carry, so a
		# flat -128..127 both refused the 128..255 that 219 corpus frames legitimately
		# hold (E022 stores height 176) and implied a range some frames cannot store.
		# `encodable_uv_range` infers it from the value the extractor produced — the same
		# primitive the region write path asks before release (ADR-0099 dec. 4a).
		_uv_extent_field("UV Width", int(uv.get("width", 0)), f.call("uv_width")),
		_uv_extent_field("UV Height", int(uv.get("height", 0)), f.call("uv_height")),
	]
	# ADR-0130 dec. 6: `_sheet_actions()` used to be appended here too. The audit that
	# opened that ADR counted the duplicate Export/Import pair as ONE surface (on the
	# frameset target); it was on the FRAME target as well, which is why
	# `SequenceFocusBlock` strips the sheet link out of the frame rows it grafts. Both call
	# sites are gone; the Texture tab carries the pair on every screen.

	var quad_fields: Array = _quad_transform_fields(frame, fs_idx, fr_idx)

	var corner_fields: Array = []
	corner_fields.append_array(_vertex_fields(vertices, "top_left", "Top-left", f))
	corner_fields.append_array(_vertex_fields(vertices, "top_right", "Top-right", f))
	corner_fields.append_array(_vertex_fields(vertices, "bottom_left", "Bottom-left", f))
	corner_fields.append_array(_vertex_fields(vertices, "bottom_right", "Bottom-right", f))

	var texture_page_fields: Array = [
		{"name": "TPAGE X base", "shape": "const", "value": str(tpage.get("x_base", 0))},
		{"name": "TPAGE Y base", "shape": "const", "value": str(tpage.get("y_base", 0))},
		{"name": "TPAGE Blend", "shape": "const", "value": str(tpage.get("blend", 0))},
		{"name": "TPAGE Colour depth", "shape": "const", "value": str(tpage.get("color_depth", 0))},
	]

	# `fold_id`s, not titles, are what downstream code filters these sections on
	# (`SequenceFocusBlock._frame_fold` drops the TPAGE one and swaps the region one for a
	# read-only statement). A title is author-facing prose and will be reworded again; an
	# id is an address. The titles are also kept SHORT on purpose: the inspector's section
	# header is a `Button`, so its text sets a minimum width that propagates to the whole
	# right column. The long form rides `tooltip`, which costs nothing.
	return [
		{"title": "Appearance", "fold_id": FOLD_APPEARANCE, "fields": appearance_fields,
			"tooltip": "How this frame is coloured and blended. All four fields are this "
				+ "frame's alone."},
		{"title": "Sheet region", "fold_id": FOLD_REGION, "fields": region_fields,
			"tooltip": "The box of the texture sheet this frame samples. SHARED: every "
				+ "frame in the effect whose box is exactly equal is the same region, and "
				+ "the frameset canvas edits all of them at once under a scope control "
				+ "(ADR-0099). 81.4%% of corpus regions span more than one frameset."},
		{"title": "Drawn quad", "fold_id": FOLD_QUAD, "fields": quad_fields,
			"tooltip": "How that sheet region is placed on screen, as a transform over it: "
				+ "size, rotation, shear and position, measured from the sprite origin. "
				+ "PER-FRAME, always — frames sharing one region routinely draw it at "
				+ "different sizes (E019's biggest group draws one 23x23 region at ten "
				+ "sizes, 7x7 through 56x56)."},
		{"title": "Raw corners", "fold_id": FOLD_CORNERS, "collapsed": true,
			"fields": corner_fields,
			"tooltip": "The eight signed integers actually stored on disk. The Drawn quad "
				+ "rows above are a lossless reading of these — every corpus frame "
				+ "recomposes to the same bytes — so this section is here to be read, not "
				+ "because there is a shape the transform cannot express."},
		{"title": "Texture Page (read-only)", "fold_id": FOLD_TPAGE, "collapsed": true,
			"fields": texture_page_fields,
			"tooltip": "The PSX TPAGE word this frame was extracted with. Not editable in v1."},
	]


## THE FRAME QUAD AS A TRANSFORM (2026-08-21), which is what the author asked for:
## *"It should be a series of transformation 'on top of' the base position (UV centred on
## origin at uv dimensions)"*.
##
## The base is the SHEET REGION's own size on the sprite origin, and the stored quad is that
## base under a translate / rotate / scale / shear. E317 frameset 16 frame 0 — the frame in
## the report — turns from eight signed integers into `base 40x40 · scale 1.00x · rotation
## 0° · shear 0.00 · position 0,+2`: four terms at rest and a two-pixel nudge.
##
## The maths, the corpus evidence for the identity, and why six terms rather than eight all
## live in `FrameQuadTransform`. What is decided HERE is only what gets a row:
##
##   Base        read-only. It is the sheet region, and that is edited under a scope control
##               on another surface because it is SHARED (ADR-0099).
##   Width/Height  the scale, typed in PSX UNITS rather than as a ratio — it is what an
##               author reads off the screen, and set against the `Base` row directly above
##               it ("40x40 from the sheet" over "40 px") it answers "is this sprite native
##               or blown up?" by comparison. A SECOND row stating the ratio was built and
##               removed: two rows for one number is two rows that can disagree, and the
##               derived one would lag every keystroke, since a typed edit deliberately
##               refreshes IN PLACE rather than reprojecting (a reproject frees the
##               ScrubField being dragged and the drag dies after one pixel — the same
##               reason `_apply_edit`'s sequence branch does not reproject). The ratio rides
##               the Width/Height tooltips instead, where a stale figure misleads nobody.
##   Rotation    degrees. 91.1% of the corpus sits at an exact multiple of 90.
##   Shear       exactly 0.00 for 98.1% of the corpus, so it is a row that will usually read
##               as at-rest rather than as noise.
##   Position    the quad's centre, offset from the sprite origin.
##   Residual    ONLY when the quad is not a parallelogram — 120 corpus frames, every one
##               off by at most a pixel. A row that is absent for 99.48% of frames.
##
## A degenerate quad (one corpus frame) has no basis to decompose against; it says so and
## sends the author to the raw corners rather than showing six zeroes.
static func _quad_transform_fields(frame: Dictionary, fs_idx: int, fr_idx: int) -> Array:
	var Canvas = load("res://src/effects/studio/FramesetCanvas.gd")
	var Quad = load("res://src/effects/studio/FrameQuadTransform.gd")
	var t: Dictionary = Quad.decompose(frame)
	var base: Vector2i = t.get("base", Vector2i.ZERO)

	var q := func(term: String) -> Dictionary:
		return {"channel": "frameset_quad", "frameset_index": fs_idx, "frame_index": fr_idx,
			"field": term}

	var rows: Array = [
		{"name": "Base", "shape": "const", "value": "%d×%d from the sheet" % [base.x, base.y],
			"tooltip": "The identity this frame's quad is measured against: the sheet "
				+ "region's own dimensions, centred on the sprite origin. Read-only here — "
				+ "the region is SHARED, and it is edited on the frameset canvas under the "
				+ "scope control that states the blast radius first (ADR-0099)."},
	]
	if not bool(t.get("ok", false)):
		rows.append({"name": "Transform", "shape": "const", "value": "degenerate — no basis",
			"tooltip": "An edge of this quad has zero length, so there is no rotation or "
				+ "scale to read off it. Exactly one corpus frame is like this. Edit it "
				+ "through Raw corners below."})
		return rows

	var scale: Vector2 = t.get("scale", Vector2.ONE)
	var size := Vector2(scale.x * float(base.x), scale.y * float(base.y))
	var pos: Vector2 = t.get("position", Vector2.ZERO)
	rows.append_array([
		{"name": "Width", "shape": "edit", "editor": "float", "step": 1.0, "suffix": " px",
			"min": -4096.0, "max": 4096.0, "value": size.x, "field_ref": q.call("width"),
			"tooltip": "How wide the sprite is DRAWN, in PSX units — %s of the sheet "
				% _ratio_text(scale.x) + "region's own %d. Scaling happens along the quad's "
				% base.x + "own edges, so this never shears a rotated quad."},
		{"name": "Height", "shape": "edit", "editor": "float", "step": 1.0, "suffix": " px",
			"min": -4096.0, "max": 4096.0, "value": size.y, "field_ref": q.call("height"),
			"tooltip": "How tall the sprite is DRAWN, in PSX units — %s of the sheet "
				% _ratio_text(scale.y) + "region's own %d." % base.y},
		{"name": "Rotation", "shape": "edit", "editor": "float", "step": 0.1, "suffix": "°",
			"min": -180.0, "max": 180.0, "value": float(t.get("rotation", 0.0)),
			"field_ref": q.call("rotation"),
			"tooltip": "The angle of the quad's top edge. 91.1% of corpus frames sit at an "
				+ "exact multiple of 90°; 8.89% are at a genuinely arbitrary angle, and for "
				+ "those the stored angle is finer than this row can show — editing any "
				+ "OTHER row recomposes from the exact value, not from what is displayed."},
		{"name": "Shear", "shape": "edit", "editor": "float", "step": 0.01,
			"min": -8.0, "max": 8.0, "value": float(t.get("shear", 0.0)),
			"field_ref": q.call("shear"),
			"tooltip": "How far the side edge leans off perpendicular, as a ratio of the "
				+ "height. Exactly 0.00 for 98.1% of the corpus."},
		{"name": "Position X", "shape": "edit", "editor": "float", "step": 0.5, "suffix": " px",
			"min": -4096.0, "max": 4096.0, "value": pos.x, "field_ref": q.call("position_x"),
			"tooltip": "The quad's CENTRE, offset from the sprite origin — the point the "
				+ "emitter places this particle at. Half-pixel values are real: a quad with "
				+ "an odd span has its centre between two texels."},
		{"name": "Position Y", "shape": "edit", "editor": "float", "step": 0.5, "suffix": " px",
			"min": -4096.0, "max": 4096.0, "value": pos.y, "field_ref": q.call("position_y"),
			"tooltip": "The quad's centre, offset from the sprite origin. Positive is DOWN."},
		{"name": "Orientation", "shape": "const", "value": Canvas.quad_orientation(frame),
			"tooltip": "How the four corners are arranged, read off the edge directions. "
				+ "upright / turned (an edge axis is negated — mirrored or flipped) / "
				+ "rotated (no edge is axis-aligned) / degenerate. Corpus: 19,120 upright, "
				+ "1,735 turned, 2,064 rotated, 1 degenerate."},
	])
	# ABSENT for 99.48% of frames, and that is the point of showing it at all: a row that is
	# usually not there is a signal when it is. The 120 corpus quads that are not
	# parallelograms are each off by at most one unit, so this never carries a real shape.
	if not bool(t.get("affine", true)):
		var r: Vector2 = t.get("residual", Vector2.ZERO)
		rows.append({"name": "Residual", "shape": "const", "value": "%+d, %+d" % [int(r.x), int(r.y)],
			"tooltip": "This quad is not quite a parallelogram — its bottom-right corner "
				+ "sits this far from where the other three put it. 120 of 22,920 corpus "
				+ "frames are like this and none is off by more than a pixel; it is rounding "
				+ "on a rotated quad, not a deliberate trapezoid. Carried through every edit."})
	return rows


## A scale factor as the author reads it. Two decimals, because the corpus's own factors run
## to eighths and sixteenths of native and `1.1` would collide three of them into one row.
static func _ratio_text(v: float) -> String:
	return "%.2f" % v


## One UV extent row, bounded by what THIS frame's byte can actually store.
static func _uv_extent_field(label: String, value: int, field_ref: Dictionary) -> Dictionary:
	var Canvas = load("res://src/effects/studio/FramesetCanvas.gd")
	var r: Vector2i = Canvas.encodable_uv_range(value)
	return {"name": label, "shape": "edit", "editor": "int", "type": "s16",
		"min": r.x, "max": r.y, "value": value, "field_ref": field_ref}


## One corner of the drawn quad, as its two editable components.
##
## THE LABEL NAMES THE SHEET BOX'S CORNER, NOT THE SCREEN'S, and the tooltip says so. The
## stored pair is *where that corner of the sampled box is drawn*, so on a turned or
## rotated quad — 3,799 corpus frames — `Top-left` lands somewhere other than the top left.
## The old `Vertex TL X` had the same ambiguity and hid it behind an abbreviation as well;
## the `Orientation` fact row directly above these eight is what resolves it.
static func _vertex_fields(vertices: Dictionary, corner: String, label_prefix: String, f: Callable) -> Array:
	var pair: Array = vertices.get(corner, [0, 0])
	var suffix := corner.replace("top_", "t").replace("bottom_", "b").replace("left", "l").replace("right", "r")
	var tip := ("Where the sheet region's %s corner is drawn, as a signed offset from the "
		+ "sprite origin (PSX units, s16). The corner is named on the REGION, not on the "
		+ "screen — see Orientation.") % label_prefix.to_lower()
	return [
		{"name": "%s X" % label_prefix, "shape": "edit", "editor": "int", "type": "s16",
			"value": int(pair[0]) if pair.size() > 0 else 0, "field_ref": f.call("vertex_%s_x" % suffix),
			"tooltip": tip},
		{"name": "%s Y" % label_prefix, "shape": "edit", "editor": "int", "type": "s16",
			"value": int(pair[1]) if pair.size() > 1 else 0, "field_ref": f.call("vertex_%s_y" % suffix),
			"tooltip": tip},
	]


## Which frameset GROUP owns `fs_idx` — `frameset_group_offsets` is a cumulative
## prefix-sum (group 0 starts at offset 0), so the owning group is the last index
## whose offset is `<= fs_idx`. Display-only per #278's v1 scope.
static func _group_for(effect_data, fs_idx: int) -> int:
	if effect_data == null or not (effect_data.frameset_group_offsets is Array):
		return 0
	var offsets: Array = effect_data.frameset_group_offsets
	var group := 0
	for i in range(offsets.size()):
		if int(offsets[i]) <= fs_idx:
			group = i
	return group


static func _resolve_frameset(effect_data, fs_idx: int) -> Dictionary:
	if effect_data == null or not (effect_data.framesets is Array):
		return {}
	if fs_idx < 0 or fs_idx >= effect_data.framesets.size():
		return {}
	var fs = effect_data.framesets[fs_idx]
	return fs if fs is Dictionary else {}


static func _resolve_frame(effect_data, fs_idx: int, fr_idx: int) -> Dictionary:
	var fs := _resolve_frameset(effect_data, fs_idx)
	if fs.is_empty():
		return {}
	var frames: Array = fs.get("frames", [])
	if fr_idx < 0 or fr_idx >= frames.size():
		return {}
	var frame = frames[fr_idx]
	return frame if frame is Dictionary else {}
