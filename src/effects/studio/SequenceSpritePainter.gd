extends RefCounted
## Draws ONE animator state — the composited frameset at its offset, or the crosshair
## that stands in for a state holding no sprite yet.
##
## Extracted so the #247 sequence viewport's PLAYER and a per-opcode THUMBNAIL paint
## through identical code. They differ only in the rect they are given: a shared
## painter is what makes a thumbnail a small copy of the player rather than a second
## drawing routine that drifts from it.
##
## Everything the paint depends on arrives as an argument — the shared coordinate box
## included — so the caller, not this file, owns the rule that every cell shares one
## box (`SequenceTimeline.bounds`). Fit each state to its own sprite and an
## offset-only change becomes invisible; see `SequenceTimeline` for why that matters.
##
## `texture` must already be `FramesetCanvas.display_image`'d. Passing a raw sheet
## paints the erased class as a solid black slab, because RGBA has no "erased" value
## and the extractor carries `0x0000` as opaque black.
##
## No `class_name` (ADR-0004).

const SequenceTimeline = preload("res://src/effects/studio/SequenceTimeline.gd")

const CROSSHAIR_COLOR := Color(0.45, 0.75, 1.0)
const CROSSHAIR_ARM := 5.0

## A quad's blend GROUP (ADR-0103 dec. 7). `-1` is the opaque pass — a frame with
## `semi_trans_on` false never reaches a blend at all — and 0-3 are the PSX semi-transparent
## modes, the same ints `FramesetProjector` labels and `EffectParticleRenderer` routes on.
const BLEND_OPAQUE := -1
## "Every quad, whatever its mode" — the un-layered draw, and the default so a caller that
## does not care about blend keeps the one-call shape.
const BLEND_ALL := -2

## The four PSX modes as Godot canvas blending, MEASURED against what the renderer does
## rather than eyeballed:
##   0 BLEND_50 `0.5*dst + 0.5*src`  -> MIX at alpha 0.5, which IS the 50/50
##   1 ADD      `dst + src`          -> ADD at alpha 1
##   2 SUB      `dst - src`          -> SUB at alpha 1
##   3 ADD_25   `dst + 0.25*src`     -> ADD at alpha 0.25 (the renderer's `level_scale`,
##              `EngineFoldCompositor.gd:152`: mode 3 rides the NATIVE_ADD path with its
##              0.25 baked into COLOR, so the quarter belongs on the source, not the mode)
## Godot's canvas ADD is `dst + src*src_alpha` and SUB is `dst - src*src_alpha`, which is
## why the level lands on the vertex alpha in both cases.
const BLEND_MODES := {
	BLEND_OPAQUE: CanvasItemMaterial.BLEND_MODE_MIX,
	0: CanvasItemMaterial.BLEND_MODE_MIX,
	1: CanvasItemMaterial.BLEND_MODE_ADD,
	2: CanvasItemMaterial.BLEND_MODE_SUB,
	3: CanvasItemMaterial.BLEND_MODE_ADD,
}
const BLEND_ALPHAS := {BLEND_OPAQUE: 1.0, 0: 0.5, 1: 1.0, 2: 1.0, 3: 0.25}
const BLEND_NAMES := {BLEND_OPAQUE: "opaque", 0: "BLEND_50", 1: "ADD", 2: "SUB", 3: "ADD_25"}

## Five materials for the whole studio, keyed by blend group. A `CanvasItemMaterial` per
## layer would mean one per cell per mode — 36 rows of them on E019 — for five distinct
## values. Godot's blend mode is per-CanvasItem, not per-material-instance, so sharing is
## free.
static var _materials: Dictionary = {}


## Fit `box` into `into`, preserving aspect and centring. `{scale, origin}` maps a
## PSX-unit point to `origin + (p - box.position) * scale`. Scale 0 when there is
## nothing to fit — which `paint` treats as nothing to draw. Pure.
static func fit(box: Rect2i, into: Rect2) -> Dictionary:
	if box.size.x <= 0 or box.size.y <= 0 or into.size.x <= 0.0 or into.size.y <= 0.0:
		return {"scale": 0.0, "origin": into.position}
	var s: float = minf(into.size.x / float(box.size.x), into.size.y / float(box.size.y))
	var drawn := Vector2(float(box.size.x), float(box.size.y)) * s
	return {"scale": s, "origin": into.position + (into.size - drawn) * 0.5}


## Paint `entry` (one `SequenceTimeline.trace` cell) onto `ci` through `fit_result`.
##
## `modulate` is the particle's RESOLVED COLOUR at this cell's age (ADR-0103 dec. 1) —
## the thing that makes a thumbnail the real render rather than a white stand-in for it.
## It defaults to white, the identity, so a caller that has no emitter to resolve against
## (the `none` rung) draws exactly what shipped before.
##
## `clip` bounds the CROSSHAIR only, and only that: a sprite cannot escape its rect,
## because `box` is the union of every step's extent so each step lies inside it by
## construction. An offset set before the first FRAME is the exception — `bounds`
## unions only steps that HAVE a sprite — so that is the one mark that can land
## outside and the one that is checked.
static func paint(ci: CanvasItem, entry: Dictionary, framesets: Array,
		box: Rect2i, texture: Texture2D, fit_result: Dictionary,
		alpha: float = 1.0, clip: Rect2 = Rect2(),
		modulate: Color = Color.WHITE) -> void:
	paint_mark(ci, entry, box, fit_result, clip)
	paint_quads(ci, entry, framesets, box, texture, fit_result, alpha, modulate)


## The CROSSHAIR half — the mark that stands in for a state holding no sprite yet, and
## nothing else. Split from the quads because a layered host draws this on ITSELF (at
## normal blend, beside its background and border) while the sprite goes to the child
## CanvasItems dec. 7 needs.
static func paint_mark(ci: CanvasItem, entry: Dictionary, box: Rect2i,
		fit_result: Dictionary, clip: Rect2 = Rect2()) -> void:
	var s: float = float(fit_result.get("scale", 0.0))
	if s <= 0.0 or bool(entry.get("has_sprite", false)):
		return
	var origin: Vector2 = fit_result.get("origin", Vector2.ZERO)
	var offset: Vector2i = entry.get("offset", Vector2i.ZERO)
	var c: Vector2 = origin + (Vector2(offset) - Vector2(box.position)) * s
	if clip.size == Vector2.ZERO or clip.has_point(c):
		ci.draw_line(c - Vector2(CROSSHAIR_ARM, 0), c + Vector2(CROSSHAIR_ARM, 0), CROSSHAIR_COLOR, 1.0)
		ci.draw_line(c - Vector2(0, CROSSHAIR_ARM), c + Vector2(0, CROSSHAIR_ARM), CROSSHAIR_COLOR, 1.0)


## The SPRITE half. `only_blend` restricts the draw to one blend group, which is how a
## layered host puts each group on a CanvasItem carrying that group's material; the
## default draws every quad on whatever `ci` already is.
static func paint_quads(ci: CanvasItem, entry: Dictionary, framesets: Array,
		box: Rect2i, texture: Texture2D, fit_result: Dictionary,
		alpha: float = 1.0, modulate: Color = Color.WHITE,
		only_blend: int = BLEND_ALL) -> void:
	var s: float = float(fit_result.get("scale", 0.0))
	if s <= 0.0:
		return
	var origin: Vector2 = fit_result.get("origin", Vector2.ZERO)
	var offset: Vector2i = entry.get("offset", Vector2i.ZERO)
	if not bool(entry.get("has_sprite", false)):
		return
	if texture == null:
		return
	var fs_i: int = int(entry.get("frameset", -1))
	if fs_i < 0 or fs_i >= framesets.size():
		return
	var tex_size := Vector2(float(texture.get_width()), float(texture.get_height()))
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	for quad in SequenceTimeline.sprite_quads(framesets[fs_i], offset):
		if only_blend != BLEND_ALL and blend_key(quad) != only_blend:
			continue
		var screen := PackedVector2Array()
		for p in (quad.get("points") as PackedVector2Array):
			screen.append(origin + (p - Vector2(box.position)) * s)
		# NORMALIZED, not pixel-space — probed with a half-red/half-blue sheet through
		# both conventions; pixel-space UVs wrap and sample the wrong texels.
		var nuv := PackedVector2Array()
		for u in (quad.get("uvs") as PackedVector2Array):
			nuv.append(Vector2(u.x / tex_size.x, u.y / tex_size.y))
		# ADR-0103 dec. 1: the COLOUR MODULATE, where a hardcoded white used to be.
		# `draw_polygon`'s vertex colour MULTIPLIES the texture, which is mechanically
		# the same operation as the particle shader's `ALBEDO = col.rgb * COLOR.rgb` —
		# not an approximation of it. The caller resolves which colour that is
		# (`SequenceCellColour`); white is the identity, i.e. what shipped before.
		var col := Color(modulate.r, modulate.g, modulate.b, alpha)
		ci.draw_polygon(screen, PackedColorArray([col, col, col, col]), nuv, texture)


## Which blend group a quad (or a raw frame Dictionary — they carry the same two keys)
## belongs to. `semi_trans_on` false means the renderer writes it to the OPAQUE pass only
## and it never blends, so it is its own group rather than mode 1's.
static func blend_key(quad: Dictionary) -> int:
	if not bool(quad.get("semi_trans_on", true)):
		return BLEND_OPAQUE
	return clampi(int(quad.get("semi_trans_mode", 1)), 0, 3)


## The distinct blend groups this cell needs, in first-appearance order — i.e. how many
## layers a host has to stand up, and in what draw order.
##
## 95.3% OF CELLS RETURN EXACTLY ONE. Of 17,530 corpus framesets only 827 (4.72%) mix
## modes at all, and every common mix is a PAIR (`ADD`+`ADD_25` 364, `ADD`+`BLEND_50` 322,
## `ADD`+`SUB` 95) — which is what makes per-CanvasItem blending affordable here. Do not
## build for N; the loop handles it, but the cost model is 1.
##
## Read off the FRAMES, not off `sprite_quads`: the keys are needed before any geometry is
## built, and rebuilding every quad just to count modes would triple the per-cell work.
static func blend_keys(entry: Dictionary, framesets: Array) -> Array:
	var out: Array = []
	if not bool(entry.get("has_sprite", false)):
		return out
	var fs_i: int = int(entry.get("frameset", -1))
	if fs_i < 0 or fs_i >= framesets.size():
		return out
	var fs = framesets[fs_i]
	if not (fs is Dictionary):
		return out
	for frame in fs.get("frames", []):
		if not (frame is Dictionary):
			continue
		var k: int = blend_key(frame)
		if not out.has(k):
			out.append(k)
	return out


## The shared `CanvasItemMaterial` for one blend group. Shared because Godot reads the
## blend mode off the CanvasItem's material, so N layers on one mode want one material.
static func material_for(key: int) -> CanvasItemMaterial:
	if not _materials.has(key):
		var m := CanvasItemMaterial.new()
		m.blend_mode = BLEND_MODES.get(key, CanvasItemMaterial.BLEND_MODE_MIX)
		_materials[key] = m
	return _materials[key]


## The vertex alpha a blend group draws at — the SOURCE level, which is where PSX's 50%
## and 25% actually live (see BLEND_MODES). Multiplied into the draw alpha by the host.
static func blend_alpha(key: int) -> float:
	return float(BLEND_ALPHAS.get(key, 1.0))
