extends RefCounted
## Pure projection of a parsed E###.BIN timeline (TimelineData) into the "score"
## the embedded EffectViewer timeline strip draws. No scene, no widgets — this is
## the testable core; EffectTimelineView is thin glue that renders these lanes
## and overlays a live playhead. See EffectTimelineModelTest.
##
## A `timeline` (TimelineData) is passed in rather than reaching through an
## EffectInstance, so the projection is unit-testable against plain JSON.
##
## Keyframe semantics are PhaseBlock's: kf[0] is a skipped anchor, and
## kf[N].emitter_id spawns emitter (id - 1) DURING frames
## [kf[N-1].time, kf[N].time); emitter_id 0 is a silence window. Times are
## phase-local, so each context is offset onto the absolute frame axis the live
## playhead uses: phase1 at 0, for_each at phase1_duration, phase2 at phase2_start.

const EffectPhaseClass = ExMateriaEffects.EffectPhase

## Phase draw order — top-to-bottom, matching execution order.
const _CONTEXT_ORDER = [
	EffectPhaseClass.PHASE1,
	EffectPhaseClass.PHASE_FOR_EACH,
	EffectPhaseClass.PHASE2,
]


## Build the score. `phase1_duration` / `phase2_start` are the SAME boundaries the
## live clock uses (EffectTimeline.setup); the caller passes them so the model
## never re-derives the single-target formula. Returns:
##   {
##     phase1_duration: int, phase2_start: int, max_frame: int,
##     lanes: [ { context, channel_index, spans: [ {emitter_index, start, end} ] } ],
##   }
## Only channels that actually spawn get a lane; lanes are ordered phase then
## channel_index.
static func build(timeline, phase1_duration: int, phase2_start: int) -> Dictionary:
	var lanes: Array = []
	var max_frame: int = maxi(1, phase2_start)

	for context in _CONTEXT_ORDER:
		var offset := _context_offset(context, phase1_duration, phase2_start)
		var channels: Array = timeline.get_channels(context) if timeline != null else []
		var sorted := channels.duplicate()
		sorted.sort_custom(func(a, b): return a.channel_index < b.channel_index)
		for channel in sorted:
			var spans := _spans_for(channel, offset)
			if spans.is_empty():
				continue
			lanes.append({
				"context": context,
				"channel_index": channel.channel_index,
				"spans": spans,
			})
			for span in spans:
				max_frame = maxi(max_frame, span["end"])

	return {
		"phase1_duration": phase1_duration,
		"phase2_start": phase2_start,
		"max_frame": max_frame,
		"lanes": lanes,
	}


## Absolute-frame left edge for a context. phase1 starts at 0; for_each's first
## instance starts when phase1 ends; phase2 starts at phase2_start.
static func _context_offset(context: String, phase1_duration: int, phase2_start: int) -> int:
	match context:
		EffectPhaseClass.PHASE_FOR_EACH: return phase1_duration
		EffectPhaseClass.PHASE2: return phase2_start
		_: return 0


## One channel's emitter spans, in absolute frames. Skips kf[0] (anchor) and any
## keyframe whose emitter_id is 0 (silence).
static func _spans_for(channel, offset: int) -> Array:
	var spans: Array = []
	var kfs: Array = channel.keyframes
	var last := mini(channel.max_keyframe, kfs.size() - 1)
	for n in range(1, last + 1):
		var kf = kfs[n]
		if kf.emitter_id == 0:
			continue
		spans.append({
			"emitter_index": kf.emitter_id - 1,
			"start": offset + kfs[n - 1].time,
			"end": offset + kf.time,
		})
	return spans
