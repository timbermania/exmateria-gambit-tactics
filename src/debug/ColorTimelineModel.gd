extends RefCounted
## Pure projection of an effect's COLOR keyframes (screen background + palette
## tints) into colored timeline lanes — the color-family sibling of
## EffectTimelineModel. No scene, no widgets; EffectTimelineView draws these lanes
## on the same frame axis as the particle lanes. See ColorTimelineModelTest.
##
## It mirrors the block layout the runtime actually plays, so the strip is
## faithful to playback:
##   - Screen (ScreenSubsystem._push_phase_ops): the whole-screen background, TINT
##     keyframes over the WIDER indices 0..max_keyframe (inclusive, no terminator
##     pair); FADE keyframes are timing-only gaps. Block color = start_color.
##   - Palette (PaletteSubsystem._each_keyframe): a channel's ENABLED keyframes,
##     indices 0..max_keyframe-2 (last two are terminators), each spanning its own
##     duration_frames laid back-to-back from the phase offset; disabled keyframes
##     are timing-only gaps. Block color = the keyframe rgb.
## Times are phase-local, so each context is offset onto the absolute axis the live
## playhead uses: phase1 at 0, for_each at phase1_duration, phase2 at phase2_start.

const ScreenData = ExMateriaEffects.ScreenData

const EffectPhaseClass = ExMateriaEffects.EffectPhase

const _CONTEXT_ORDER = [
	EffectPhaseClass.PHASE1,
	EffectPhaseClass.PHASE_FOR_EACH,
	EffectPhaseClass.PHASE2,
]

## Palette channel display order.
const _PALETTE_CHANNELS = ["affected_units", "caster", "target"]


## Build the color score. `phase1_duration` / `phase2_start` are the same
## boundaries the clock uses. Returns:
##   { lanes: [ { context, kind, channel, spans: [ {start, end, color, blend_mode} ] } ],
##     max_frame: int }
## Only channels with at least one visible block get a lane; lanes are ordered
## phase then (screen, palette channels).
static func build(screen_data, palette_data, phase1_duration: int, phase2_start: int) -> Dictionary:
	var lanes: Array = []
	var max_frame: int = 1

	for context in _CONTEXT_ORDER:
		var offset := _context_offset(context, phase1_duration, phase2_start)
		if screen_data != null:
			var s_spans := _screen_spans(screen_data, context, offset)
			if not s_spans.is_empty():
				lanes.append({
					"context": context, "kind": "screen", "channel": "screen", "spans": s_spans,
				})
				for span in s_spans:
					max_frame = maxi(max_frame, span["end"])
		if palette_data != null:
			for channel in _PALETTE_CHANNELS:
				var spans := _palette_spans(palette_data, context, channel, offset)
				if spans.is_empty():
					continue
				lanes.append({
					"context": context, "kind": "palette", "channel": channel, "spans": spans,
				})
				for span in spans:
					max_frame = maxi(max_frame, span["end"])

	return {"lanes": lanes, "max_frame": max_frame}


static func _context_offset(context: String, phase1_duration: int, phase2_start: int) -> int:
	match context:
		EffectPhaseClass.PHASE_FOR_EACH: return phase1_duration
		EffectPhaseClass.PHASE2: return phase2_start
		_: return 0


## Screen blocks: TINT keyframes over the 0..max_keyframe window (inclusive),
## each spanning its duration_frames from `offset`, colored by start_color.
static func _screen_spans(screen_data, context: String, offset: int) -> Array:
	var ch = screen_data.get_channel(context)
	if ch == null or ch.keyframes.is_empty():
		return []
	var spans: Array = []
	var start_frame := 0
	var last_idx: int = mini(ch.keyframes.size(), ch.max_keyframe + 1)
	for i in range(last_idx):
		var kf = ch.get_keyframe(i)
		var dur: int = maxi(1, kf.duration_frames)
		if kf.mode == ScreenData.ScreenMode.BLEND:
			spans.append({
				"start": offset + start_frame,
				"end": offset + start_frame + dur,
				"color": kf.start_color,
				"blend_mode": kf.blend_mode,
			})
		start_frame += dur
	return spans


## Palette channel blocks: enabled keyframes over the 0..max_keyframe-2 window,
## each spanning its duration_frames from `offset`, colored by rgb.
static func _palette_spans(palette_data, context: String, channel: String, offset: int) -> Array:
	var ch = palette_data.get_channel(context, channel)
	if ch == null or ch.keyframes.is_empty():
		return []
	var spans: Array = []
	var start_frame := 0
	var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
	for i in range(last_idx):
		var kf = ch.keyframes[i]
		var dur: int = maxi(1, kf.duration_frames)
		if kf.enabled:
			spans.append({
				"start": offset + start_frame,
				"end": offset + start_frame + dur,
				"color": Color(kf.rgb.x / 255.0, kf.rgb.y / 255.0, kf.rgb.z / 255.0, 1.0),
				"blend_mode": kf.blend_mode,
			})
		start_frame += dur
	return spans
