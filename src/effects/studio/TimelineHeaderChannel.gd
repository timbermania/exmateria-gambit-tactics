class_name TimelineHeaderChannel
extends RefCounted
## Write-side channel archetype for the GLOBAL timeline-header phase durations (#271) —
## the effect's skeleton: `phase1_duration` (@+0x04, frames until for_each starts),
## `spawn_delay` (@+0x06, between-spawn delay for multi-target), and `phase2_delay`
## (@+0x0A, for_each→phase2 gap). Unlike the per-keyframe channels (screen/palette/…),
## these are effect-global and live on `data.timeline` (a TimelineData), reached through
## the `effect_settings` inspection target rather than a span.
##
## An edit writes the storage VAR (what `EffectScoreModel.phase_offset` reads, so the whole
## score re-flows) AND the `header` dict (the saver's timeline.json source) so both stay in
## sync. Every edit therefore declares `invalidates_sim` + `invalidates_layout`: phase
## offsets shift, so the sim re-folds and the score bands re-project. Scalar undo — the raw
## byte fully reconstructs the score, so no snapshot is needed. The single choke point is
## `EffectEditSession.apply_edit`.

# The three author-facing / on-disk duration fields (TimelineData vars, also `header` keys).
# Every other header word (unknown_00/02/08, and the derived first_hit/for_each/total) is
# engine-ignored or derived — NOT authored here; the writer preserves it verbatim.
const _FIELDS := {
	"phase1_duration": true,
	"spawn_delay": true,
	"phase2_delay": true,
}

# A frame duration is a POSITIVE count stored in a 16-bit slot the parser reads as s16, so
# the faithfully-encodable range is 0..32767 (a value past that reads back negative).
const _MAX_FRAMES := 0x7FFF


## Write one raw duration named by `field_ref.field` onto the effect's timeline, keeping the
## sim-read var and the saver's header dict in lockstep. Returns the snapshot the choke point
## records for scalar undo. Every edit re-flows the score (invalidates_sim + layout).
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var field: String = str(field_ref.get("field", ""))
	if data == null or data.timeline == null:
		push_error("TimelineHeaderChannel: no timeline to edit for %s" % str(field_ref))
		return {}
	if not _FIELDS.has(field):
		push_error("TimelineHeaderChannel: unknown timeline-header field '%s'" % field)
		return {}
	var tl = data.timeline
	var before: int = int(tl.get(field))
	tl.set(field, int(new_raw))
	# Keep the header dict — the saver's timeline.json source — tracking the live var.
	if tl.header is Dictionary:
		tl.header[field] = int(new_raw)
	return {
		"before_raw": before,
		"after_raw": int(new_raw),
		"invalidates_sim": true,
		"invalidates_layout": true,
		"faithful": _faithful_verdict(field, int(new_raw)),
	}


## The live stored raw for `field_ref.field` — the seed the inspector's int cell reads so a
## row reflects the current value (mirrors apply_raw's storage; the read half of the choke).
static func read_raw(data, field_ref: Dictionary) -> int:
	var field: String = str(field_ref.get("field", ""))
	if data == null or data.timeline == null or not _FIELDS.has(field):
		return 0
	return int(data.timeline.get(field))


## Non-destructive Faithful advisory: Free always accepts the write, but a duration only
## lowers to E###.BIN if it fits the positive 16-bit frame slot (0..32767).
static func _faithful_verdict(field: String, raw: int) -> Dictionary:
	if raw < 0 or raw > _MAX_FRAMES:
		return {
			"ok": false,
			"reason": "%s = %d is outside the 0–%d frame slot (Free-only)" % [field, raw, _MAX_FRAMES],
		}
	return {"ok": true, "reason": ""}
