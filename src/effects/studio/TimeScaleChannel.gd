class_name TimeScaleChannel
extends RefCounted
## Write-side channel archetype for the effect's two PACING curves (#270, ADR-0093) —
## `outer_phases` ("Phase 1 pacing") and `for_each` ("For-each pacing"), each 600 ints stored
## nibble-packed in the time_scale section (header `0x14` → `time_scale_ptr`). Unlike the
## per-keyframe channels, a pacing edit is a WHOLE-CURVE freehand paint: the painter commits
## the full 600-int array on mouse-up, so this channel takes that array as `new_raw`, snapshots
## the pre-edit array as `before_raw`, and writes it onto `data.time_scale[<field>]`.
##
## Curve edits declare `invalidates_sim`: pacing feeds `tl.setup(...)` → EffectEndModel, so a
## re-fold recomputes the end marker (the same wrinkle #271's timeline-header edit handled).
## Undo is the scalar replay through `EffectEditSession` — the stored `before_raw` array
## re-applies through this same `apply_raw`, so one committed stroke is one undo. `before_raw`
## / `after_raw` are independent copies so a later edit can't corrupt a recorded undo value.
##
## The two enable BITS are NOT here — they physically live in the effect_flags byte and edit via
## EffectFlagsChannel (bits 5/6, mirrored into `data.time_scale.flags`); this channel owns only
## the curve samples. The single choke point is `EffectEditSession.apply_edit`.

# The two author-facing curve fields and their storage key on `data.time_scale`.
const _CURVES := {
	"outer_phases": "outer_phases",
	"for_each": "for_each",
}


## Write the whole pacing curve `new_raw` (a 600-int array) onto the curve named by
## `field_ref.field`, snapshotting the pre-edit array for undo. Returns the snapshot the choke
## point records for scalar undo. Refuses (empty result) when there is no time_scale block or the
## field is not one of the two curves.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	if data == null or not (data.time_scale is Dictionary) or data.time_scale.is_empty():
		push_error("TimeScaleChannel: no time_scale block to edit for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")
	if not _CURVES.has(field):
		push_error("TimeScaleChannel: unknown pacing curve '%s'" % field)
		return {}
	var key: String = _CURVES[field]
	var before: Array = []
	if data.time_scale.get(key, null) is Array:
		before = (data.time_scale[key] as Array).duplicate()
	var after: Array = (new_raw as Array).duplicate()
	data.time_scale[key] = after.duplicate()
	return {
		"before_raw": before,
		"after_raw": after,
		"invalidates_sim": true,
		"faithful": _faithful_verdict(field, after),
	}


## Read the live stored pacing curve for `field_ref.field` — the seed the painter binds an
## EffectCurve from (the read half of the choke). Returns an empty array when absent.
static func read_raw(data, field_ref: Dictionary) -> Array:
	if data == null or not (data.time_scale is Dictionary):
		return []
	var field: String = field_ref.get("field", "")
	if not _CURVES.has(field):
		return []
	var v = data.time_scale.get(_CURVES[field], [])
	return (v as Array).duplicate() if v is Array else []


## Non-destructive Faithful advisory: Free always accepts the paint, but a pacing value only
## lowers to the nibble alphabet (0..15) the writer packs two-per-byte. The corpus uses only
## 2..10; a value outside 0..15 would clobber its neighbour's nibble, so it is not faithful.
static func _faithful_verdict(field: String, values: Array) -> Dictionary:
	for i in range(values.size()):
		var v: int = int(values[i])
		if v < 0 or v > 15:
			return {
				"ok": false,
				"reason": "%s[%d] = %d is outside the 0–15 nibble encoding (Free-only)" % [field, i, v],
			}
	return {"ok": true, "reason": ""}
