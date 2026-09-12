extends RefCounted
## THE FRAME QUAD AS A TRANSFORM, not as eight signed integers (#278, ADR-0099 amendment).
##
## A frame stores where its sprite is drawn as four corner points — `top_left`,
## `top_right`, `bottom_left`, `bottom_right` — each a signed offset in PSX units. The
## author's report on being shown them:
##
##   *"this stuff is kind of esoteric. the names aren't good … It should be a series of
##   transformation 'on top of' the base position (UV centred on origin at uv dimensions)"*
##
## This file is that reading. THE IDENTITY IS THE SHEET REGION ITSELF: its own width and
## height, centred on the sprite origin. Every stored quad is then that base under a
## translate / rotate / scale / shear, and the eight numbers become five facts of which
## most are at rest.
##
## E317 frameset 16 frame 0 — the frame in the report — is the whole argument. It stores
## `TL(-20,-18) TR(20,-18) BL(-20,22) BR(20,22)` against a 40x40 sheet region, which reads:
##
##     base 40x40 · scale 1.00x · rotation 0° · shear 0.00 · position 0,+2
##
## Four terms at rest and a two-pixel nudge. `1.00x` is not an invented reference either:
## 41.8% of all 22,920 corpus frames are drawn at exactly native texel size on both axes,
## and 1.0 is the most common scale factor by a factor of ten.
##
## WHY SIX TERMS AND NOT EIGHT. A quad has 8 degrees of freedom. Translate(2) + rotate(1) +
## scale(2) + shear(1) is 6, and reaches every PARALLELOGRAM; the 2 it gives up are the
## projective/keystone terms that turn a rectangle into a trapezoid. The corpus does not
## use them: 22,800 of 22,920 quads are exact parallelograms, and every one of the 120
## exceptions is off by AT MOST ONE UNIT — integer rounding on a rotated quad, not a
## deliberate trapezoid. So those 120 are not a second species needing a second editor;
## they are a parallelogram plus a `residual` this file carries, which reads ZERO for
## 99.48% of frames and never exceeds a pixel for the rest. Nothing is unreachable and
## there is no second vocabulary. (A per-corner "bias" parameterisation was considered and
## rejected: 8 free numbers reach every shape by CONTAINING every shape, which is the
## esoteric surface again under a new name.)
##
## PRECISION IS KEPT IN THE TRANSFORM, NOT IN THE ROWS. `decompose` returns exact floats;
## `with_term` replaces ONE of them and leaves the others at full precision. That matters
## because 8.89% of corpus quads sit at a genuinely arbitrary angle: if the rotation the
## author reads (`12.3°`) were the rotation a scale edit recomposed from, every untouched
## corner would drift by the display rounding. Only the term actually typed takes a typed
## value.
##
## Pure statics, no node, no window — the seam `FramesetCanvas`'s coordinate math already
## uses, and the reason the round trip is assertable against all 401 `E###.BIN` files.
## No `class_name` (ADR-0004).

const CORNERS := ["top_left", "top_right", "bottom_left", "bottom_right"]

## Vertices are signed 16-bit on disk. A scale that leaves this range is REFUSED for the
## whole gesture rather than clamped per member — a clamp on one member of a region is a
## partial edit, and ADR-0099 dec. 4a's rule is that every member is asked for a verdict
## before any of them is written.
const V_MIN := -32768
const V_MAX := 32767

## Below this the quad has no area on an axis and the decomposition has no basis to divide
## by. Exactly one corpus frame is degenerate; `decompose` reports rather than throws.
const EPS := 1e-9


## The identity quad's size: the sheet region's own dimensions, sign folded out (a negative
## uv width is a MIRROR flag, not a smaller box — see `FramesetCanvas.normalised_block`).
static func base_size(frame: Dictionary) -> Vector2i:
	var uv: Dictionary = frame.get("uv", {})
	return Vector2i(absi(int(uv.get("width", 0))), absi(int(uv.get("height", 0))))


## Read the four corners as the transform that produces them from the base.
##
## `scale`   — edge length over base length. 1.0 is native texel size.
## `rotation`— degrees, the angle of the TOP edge. 91.1% of the corpus is exactly a
##             multiple of 90°.
## `shear`   — how far the side edge leans off perpendicular, as a ratio. Exactly 0.00 for
##             98.1% of the corpus.
## `position`— the quad's CENTRE as an offset from the sprite origin. Taken as `(TR+BL)/2`,
##             which equals `(TL+BR)/2` on a parallelogram and stays the centre of the
##             IMPLIED parallelogram on the 120 that are not — so `position` never absorbs
##             the residual and the two terms stay independent.
## `residual`— actual BR minus the BR the other three corners imply. Zero for 99.48%.
##
## `ok` is false only for a degenerate quad (an edge of zero length); the caller shows the
## raw corners instead of dividing by zero. Pure.
static func decompose(frame: Dictionary) -> Dictionary:
	var v: Dictionary = frame.get("vertices", {})
	var tl := _pt(v, "top_left")
	var tr := _pt(v, "top_right")
	var bl := _pt(v, "bottom_left")
	var br := _pt(v, "bottom_right")
	var base := base_size(frame)

	var u := tr - tl                      # the top edge
	var w := bl - tl                      # the side edge
	var out := {
		"base": base, "scale": Vector2.ONE, "rotation": 0.0, "shear": 0.0,
		"position": (tr + bl) * 0.5, "residual": Vector2.ZERO, "affine": true, "ok": false,
	}
	if u.length_squared() < EPS or w.length_squared() < EPS:
		return out

	var theta := atan2(u.y, u.x)
	var ct := cos(theta)
	var st := sin(theta)
	var edge_w := u.length()
	# The side edge expressed in the quad's OWN basis: its y component is the height, its x
	# component is the lean. This is also why `scale` never shears a rotated quad — it
	# multiplies along the quad's edges, not along screen X/Y.
	var lean := w.x * ct + w.y * st
	var edge_h := -w.x * st + w.y * ct
	if absf(edge_h) < EPS:
		return out

	out["ok"] = true
	out["rotation"] = rad_to_deg(theta)
	out["shear"] = lean / edge_h
	out["scale"] = Vector2(
		edge_w / float(base.x) if base.x != 0 else 0.0,
		edge_h / float(base.y) if base.y != 0 else 0.0)
	out["residual"] = br - (tr + bl - tl)
	out["affine"] = out["residual"] == Vector2.ZERO
	return out


## The four corners a transform produces, as the `vertices` dictionary shape the frame
## stores. The inverse of `decompose` and exact: recomposing an untouched decomposition
## reproduces the stored integers for 99.47% of the corpus (worst error 2.8e-14), because
## `TL = centre - (u+v)/2` is an identity when `centre` is `(TR+BL)/2`.
static func compose(t: Dictionary) -> Dictionary:
	var base: Vector2i = t.get("base", Vector2i.ONE)
	var scale: Vector2 = t.get("scale", Vector2.ONE)
	var theta := deg_to_rad(float(t.get("rotation", 0.0)))
	var shear := float(t.get("shear", 0.0))
	var centre: Vector2 = t.get("position", Vector2.ZERO)
	var residual: Vector2 = t.get("residual", Vector2.ZERO)

	var ct := cos(theta)
	var st := sin(theta)
	var edge_w := scale.x * float(base.x)
	var edge_h := scale.y * float(base.y)
	var u := Vector2(edge_w * ct, edge_w * st)
	var lean := shear * edge_h
	var w := Vector2(lean * ct - edge_h * st, lean * st + edge_h * ct)

	var tl := centre - (u + w) * 0.5
	return {
		"top_left": _round(tl),
		"top_right": _round(tl + u),
		"bottom_left": _round(tl + w),
		"bottom_right": _round(tl + u + w + residual),
	}


## Replace ONE term and leave every other at the precision `decompose` produced. See the
## header: a rotation the author reads as `12.3°` is stored as the angle that actually
## reproduces the corners, and only an edit to `rotation` itself may coarsen it.
static func with_term(t: Dictionary, term: String, value) -> Dictionary:
	var out := t.duplicate(true)
	match term:
		"scale_x": out["scale"] = Vector2(float(value), t.get("scale", Vector2.ONE).y)
		"scale_y": out["scale"] = Vector2(t.get("scale", Vector2.ONE).x, float(value))
		"rotation": out["rotation"] = float(value)
		"shear": out["shear"] = float(value)
		"position_x": out["position"] = Vector2(float(value), t.get("position", Vector2.ZERO).y)
		"position_y": out["position"] = Vector2(t.get("position", Vector2.ZERO).x, float(value))
		# `width`/`height` are the same knob as `scale`, typed in PSX units instead of as a
		# ratio — which is how the author reads a size off the screen. Expressed here so
		# both spellings lower through one path and cannot drift apart.
		"width":
			var bx: int = t.get("base", Vector2i.ONE).x
			out["scale"] = Vector2(float(value) / float(bx) if bx != 0 else 0.0,
				t.get("scale", Vector2.ONE).y)
		"height":
			var by: int = t.get("base", Vector2i.ONE).y
			out["scale"] = Vector2(t.get("scale", Vector2.ONE).x,
				float(value) / float(by) if by != 0 else 0.0)
		_:
			push_error("FrameQuadTransform: unknown term '%s'" % term)
	return out


## What a transform change lowers to: one `{field_ref, new_raw}` per CHANGED vertex
## component, in the shape `EffectEditSession.apply_compound` consumes — so turning one
## knob is ONE undo entry however many of the eight components it moved (ADR-0099 dec. 9),
## through the #255 choke point exactly as a region drag already is.
##
## Only changed components are emitted, so a knob nudged back to where it started is not an
## undo entry the author has to press through.
static func vertex_edits(frameset_index: int, frame_index: int, frame: Dictionary,
		t: Dictionary) -> Array:
	var want := compose(t)
	var have: Dictionary = frame.get("vertices", {})
	var edits: Array = []
	for corner in CORNERS:
		var a: Array = want.get(corner, [0, 0])
		var b: Array = have.get(corner, [0, 0])
		for comp in range(2):
			var new_v := int(a[comp])
			var old_v: int = int(b[comp]) if b.size() > comp else 0
			if new_v == old_v:
				continue
			edits.append({
				"field_ref": {"channel": "frameset", "frameset_index": frameset_index,
					"frame_index": frame_index, "field": _FIELD[corner][comp]},
				"new_raw": new_v,
			})
	return edits


## THE REGION-SCOPED SCALE (the ADR-0099 dec. 3 amendment). Multiply every selected
## member's quad by `ratio` about the sprite origin.
##
## Dec. 3's letter forbids a region edit from writing vertices at all. Its REASONING
## forbids only the ADDITIVE form: a uniform delta over 30 members that deliberately draw
## at 7x7 through 56x56 "would flatten a 6x growth ramp into a constant offset". A
## MULTIPLICATIVE factor has no such failure — it preserves every ratio the group encodes,
## so the ramp stays a ramp. That is the distinction the amendment turns on.
##
## ABOUT THE ORIGIN, NOT ABOUT EACH QUAD'S OWN CENTRE, and that is a REGION decision rather
## than a taste one. `(0,0)` is the particle's position — `EffectParticleRenderer` packs
## the corners into `transform.basis` and the position into `transform.origin`, and
## `align_to_velocity` already rotates about it. Scaling about it is ONE similarity applied
## to the whole set, so no member moves relative to any other: 0px, every group. Scaling
## about each member's own centre uses a different pivot per member and slides them apart —
## >4px in 29% of the 2,030 multi-size regions, worst 247px. E408's beam shares one region
## across 13 frames with its base pinned at exactly y=0 at every size; centre-scaling at 2x
## walks that base from +7 to +56 over its own animation.
##
## Multiplying the eight raw components is EXACTLY multiplying `scale`, `position` and
## `residual` while leaving `rotation` and `shear` — a similarity scales lengths, not
## angles — so it is written the short way here and the equivalence is guarded.
static func scale_edits(framesets: Array, members: Array, ratio: float) -> Array:
	var edits: Array = []
	for m in members:
		var fi := int(m.get("frameset_index", -1))
		var fj := int(m.get("frame_index", -1))
		var frame := _member_frame(framesets, fi, fj)
		if frame.is_empty():
			continue
		var v: Dictionary = frame.get("vertices", {})
		for corner in CORNERS:
			var pair: Array = v.get(corner, [])
			for comp in range(2):
				if pair.size() <= comp:
					continue
				var old_v := int(pair[comp])
				var new_v := int(round(float(old_v) * ratio))
				if new_v == old_v:
					continue
				edits.append({
					"field_ref": {"channel": "frameset", "frameset_index": fi,
						"frame_index": fj, "field": _FIELD[corner][comp]},
					"new_raw": new_v,
				})
	return edits


## Can EVERY member survive this scale? Asked before any of them is written (ADR-0099
## dec. 4a): a clamp discovered halfway through 30 members is a partial edit, and the
## author has no diagnostic for the half that landed.
##
## Two ways to fail. A component can leave signed 16-bit — the corpus already reaches
## 198x198, so this is not hypothetical at large factors. Or the factor can COLLAPSE a
## member: a 7x7 quad at 0.05x rounds to nothing, and a quad with no area is invisible and
## not recoverable by scaling back up. Both are refusals, not warnings. Pure.
static func scale_verdict(framesets: Array, members: Array, ratio: float) -> Dictionary:
	var blocked: Array = []
	for m in members:
		var fi := int(m.get("frameset_index", -1))
		var fj := int(m.get("frame_index", -1))
		var frame := _member_frame(framesets, fi, fj)
		if frame.is_empty():
			continue
		var v: Dictionary = frame.get("vertices", {})
		var lo := Vector2i(1 << 30, 1 << 30)
		var hi := Vector2i(-(1 << 30), -(1 << 30))
		var any := false
		for corner in CORNERS:
			var pair: Array = v.get(corner, [])
			if pair.size() < 2:
				continue
			var p := Vector2i(int(round(float(int(pair[0])) * ratio)),
				int(round(float(int(pair[1])) * ratio)))
			any = true
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
			for axis in range(2):
				var c: int = p.x if axis == 0 else p.y
				if c >= V_MIN and c <= V_MAX:
					continue
				blocked.append({"frameset_index": fi, "frame_index": fj,
					"reason": "frameset %d frame %d would put a corner at %d, outside the signed 16-bit vertex range"
						% [fi, fj, c]})
		if any and (hi.x - lo.x < 1 or hi.y - lo.y < 1):
			var was: Vector2i = _quad_extent(v)
			blocked.append({"frameset_index": fi, "frame_index": fj,
				"reason": "frameset %d frame %d is %dx%d and would collapse to nothing at %.3fx"
					% [fi, fj, was.x, was.y, ratio]})
	var message := ""
	if not blocked.is_empty():
		message = "%d of %d member%s cannot be scaled %.3fx: %s" % [blocked.size(),
			members.size(), "" if members.size() == 1 else "s", ratio, blocked[0]["reason"]]
	return {"ok": blocked.is_empty(), "blocked": blocked, "message": message}


## Vertex corner + component → the raw field name `FramesetChannel` writes. The channel's
## own `_VERTEX_FIELD` is the inverse of this table; they are checked against each other by
## the guard rather than kept in step by hand.
const _FIELD := {
	"top_left": ["vertex_tl_x", "vertex_tl_y"],
	"top_right": ["vertex_tr_x", "vertex_tr_y"],
	"bottom_left": ["vertex_bl_x", "vertex_bl_y"],
	"bottom_right": ["vertex_br_x", "vertex_br_y"],
}


static func _pt(v: Dictionary, key: String) -> Vector2:
	var pair: Array = v.get(key, [])
	return Vector2(float(pair[0]) if pair.size() > 0 else 0.0,
		float(pair[1]) if pair.size() > 1 else 0.0)


static func _round(p: Vector2) -> Array:
	return [int(round(p.x)), int(round(p.y))]


static func _quad_extent(v: Dictionary) -> Vector2i:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for corner in CORNERS:
		var pair: Array = v.get(corner, [])
		if pair.size() < 2:
			continue
		lo = Vector2i(mini(lo.x, int(pair[0])), mini(lo.y, int(pair[1])))
		hi = Vector2i(maxi(hi.x, int(pair[0])), maxi(hi.y, int(pair[1])))
	return hi - lo


static func _member_frame(framesets: Array, fi: int, fj: int) -> Dictionary:
	if fi < 0 or fi >= framesets.size():
		return {}
	var fs = framesets[fi]
	var frames: Array = (fs.get("frames", []) if fs is Dictionary else [])
	if fj < 0 or fj >= frames.size():
		return {}
	var frame = frames[fj]
	return frame if frame is Dictionary else {}
