extends RefCounted
## Write-side channel for **curve contents** — the 160 samples a
## [curve use site](../../../docs/context/16-effect-studio-authoring-tool.md) owns (ADR-0089 curve-ownership amendment).
##
## Since the [explode] (`ExMateriaEffects.CurveExplode`) those samples are PRIVATE: a
## commit here moves that one param on that one emitter and nothing else. Before it, the
## painter mutated a SHARED curve and restyled every referring param — the common case,
## not the tail (70.8% of ROM curve slots have more than one referrer, E009's slot 0 has
## 30), which is the whole reason the ownership model changed.
##
## A paint is a WHOLE-CURVE commit, not a scalar: the painter previews into a local grid
## and writes the bound curve once on mouse-up. So this channel takes the whole 160-int
## array as `new_raw` and snapshots the pre-edit array as `before_raw` — the same shape
## `TimeScaleChannel` uses for the pacing curves, which were already the working proof of
## private curves (`_open_pacing_painter` mints its own EffectCurve and saves it undoably).
## Undo is therefore the ordinary scalar replay through `EffectEditSession`: the stored
## array re-applies through this same `apply_raw`, so one committed stroke is one undo.
##
## DOMAIN: `new_raw` is the painter's grid alphabet (0-255 ints); storage is normalized
## 0-1 floats. This channel owns that bridge, so no caller has to remember which side of
## it they are on. Values outside 0-255 are accepted but reported un-faithful (a Free-only
## edit) rather than clamped — ADR-0089's never-clamp rule.
##
## The file also carries the PICKER's verb, `assign_shape` (channel `curve_assign`), because
## it is the same subject seen from the address side: a pick COPIES a shape into this use
## site's own curve — minting one when the site had none — and nothing links afterward.
##
## What is NOT here: the ≤15-slot / nibble packing. That is the deferred COMPILER;
## authoring is unbounded by design.
##
## No `class_name` (ADR-0004) — preloaded by path.

const CurveExplode = ExMateriaEffects.CurveExplode

const VMAX := 255


## Write the whole curve `new_raw` (a 0-255 int array) into the curve at
## `field_ref.curve_index`, snapshotting the pre-edit samples for undo. Returns the
## snapshot the choke point records. Refuses (empty result) when the index does not
## resolve — an unresolvable curve address is a bug in the caller, not an edit to record.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var curve = _resolve(data, field_ref)
	if curve == null:
		push_error("CurveChannel: no curve at index %s" % str(field_ref.get("curve_index", -1)))
		return {}
	if not (new_raw is Array):
		push_error("CurveChannel: expected a whole-curve int array, got %s" % typeof(new_raw))
		return {}
	var before: Array = to_grid(curve)
	var after: Array = (new_raw as Array).duplicate()
	_write(curve, after)
	return {
		"before_raw": before,
		"after_raw": after,
		# The sim reads emitter-clocked curves ONCE at spawn, so already-live particles
		# keep the old shape until the fold replays them. A colour curve would repaint in
		# place (the renderer holds the EffectCurve by reference), but one honest answer
		# for both beats a per-slot rule that would go stale the first time a use site
		# changed clock domain.
		"invalidates_sim": true,
		"faithful": _faithful_verdict(after),
	}


## Read the live samples of the curve at `field_ref.curve_index` as 0-255 ints — the read
## half of the choke, and the seed the painter binds. Empty when the index does not resolve.
static func read_raw(data, field_ref: Dictionary) -> Array:
	var curve = _resolve(data, field_ref)
	return [] if curve == null else to_grid(curve)


## An EffectCurve's normalized samples as the painter's 0-255 int grid.
static func to_grid(curve) -> Array:
	var out: Array = []
	if curve == null:
		return out
	out.resize(curve.samples.size())
	for i in range(curve.samples.size()):
		out[i] = clampi(roundi(float(curve.samples[i]) * float(VMAX)), 0, VMAX)
	return out


# --- internals -------------------------------------------------------------

static func _write(curve, values: Array) -> void:
	curve.samples.resize(values.size())
	for i in range(values.size()):
		curve.samples[i] = clampf(float(values[i]) / float(VMAX), 0.0, 1.0)


static func _resolve(data, field_ref: Dictionary):
	if data == null or data.curves == null:
		return null
	var idx: int = int(field_ref.get("curve_index", -1))
	if idx < 0 or idx >= data.curves.size():
		return null
	return data.curves[idx]


## Non-destructive Faithful advisory: a curve sample lowers to ONE BYTE on disk, so a
## value outside 0-255 cannot be written back. Free accepts it; the verdict says so.
static func _faithful_verdict(values: Array) -> Dictionary:
	for i in range(values.size()):
		var v: int = int(values[i])
		if v < 0 or v > VMAX:
			return {"ok": false,
				"reason": "sample %d = %d is outside the 0–255 byte encoding (Free-only)" % [i, v]}
	return {"ok": true, "reason": ""}


# --- the picker's verb -----------------------------------------------------

## Assign a SHAPE to a use site (channel `curve_assign`) — the picker's verb since
## ADR-0089 decision 3 changed it from *reference* to *copy*. Under decision 1 there is no
## shared slot to point at, so picking a thumbnail writes those samples into this use
## site's own curve and nothing links afterward.
##
## `field_ref` addresses the use site: `{emitter_index, slot, kind}` where kind is "param"
## or "colour". `new_raw` is the chosen shape as 0-255 ints, or EMPTY for "no curve".
##
## A site that had no curve MINTS one (decision 5) — appended, pointed at, and filled with
## the picked shape. Minting an all-zero identity first and overwriting it immediately is
## deliberate: `mint_identity` is the ONE place a use site gains a curve, so "adding a
## curve changes nothing until it is painted" holds whether the caller then paints or not.
##
## Picking `none` clears the ADDRESS, not the array. Removing the entry would renumber
## every index above it — the one thing the explode's private-index model cannot survive —
## and an unreferenced authored curve is exactly what the compiler already knows to drop.
static func assign_shape(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var e: int = int(field_ref.get("emitter_index", -1))
	var slot: String = str(field_ref.get("slot", ""))
	var kind: String = str(field_ref.get("kind", "param"))
	if data == null or data.emitters == null or e < 0 or e >= data.emitters.size() or slot == "":
		push_error("CurveChannel: cannot assign a shape to use site %s" % str(field_ref))
		return {}
	var samples: Array = (new_raw as Array) if new_raw is Array else []
	var before: int = CurveExplode.site_index(data, e, slot, kind)
	if samples.is_empty():
		if before < 0:
			return {"no_edit": true, "faithful": {"ok": true, "reason": ""}}
		CurveExplode.set_site_index(data, e, slot, kind, -1)
		return _assign_result()
	var idx: int = CurveExplode.mint_identity(data, e, slot, kind, maxi(1, samples.size()))
	if idx < 0 or idx >= data.curves.size():
		push_error("CurveChannel: could not mint a curve for use site %s" % str(field_ref))
		return {}
	_write(data.curves[idx], samples)
	return _assign_result()


## An assignment reshapes the ROW, not just a value: gaining or losing a curve flips the
## group's relevance (with no curve the sim pins the param to its start, so the end axis
## deads), and the gauge moves. Hence `relayout` alongside `invalidates_sim`.
static func _assign_result() -> Dictionary:
	return {"invalidates_sim": true, "relayout": true, "faithful": {"ok": true, "reason": ""}}
