extends RefCounted
## Per-archetype projector for SOUND triggers (ADR-0071) — the SFX lanes. A trigger
## fires a one-shot at an instant; it projects one Section.
##
## EDITABLE via the F1 shared kit (#268): the trigger's `sound_id` and its
## `duration_frames` (trigger timing / gap to the next fire) are both plain `int`
## editors. `sound_id` is a u8 (0–255) and `duration_frames` is the s16 time_value.
## Both lower through the SOUND channel encoder at the single choke point
## (EffectEditSession.apply_edit); the edit is `invalidates_sim = false` (sound has no
## framebuffer impact, so the preview repaints nothing — audio re-fires next play).
##
## Channel stays a const_field: it is lane IDENTITY (channel_index), not an authored
## value. `sound_id` is left a plain integer rather than a NAMED enum: it is not a raw
## SFX id but a container index (0/1 skip, N>=2 → SoundContainer[N-2] → FEDS pair via a
## TIER-2 mode), so a named picker needs TIER-2 resolution — a deferred follow-up.
##
## The write-side address is THREE-dimensional, derived from the SPAN itself: phase,
## channel_index (int), and keyframe_index. No `class_name` (ADR-0004).

const _Fields = preload("res://src/effects/studio/ProjectorField.gd")
const _Target = preload("res://src/effects/studio/InspectionTarget.gd")


static func sections(span: Dictionary) -> Array:
	# ADR-0085 "every event is accessible via a timeline handle": the TERMINATOR end-cap
	# (index == max_keyframe) is select-to-inspect only — its inspector is inert. It owns no
	# editable byte (the last event's Gap already owns that s16), so it shows a single
	# read-only "end of track" note and nothing else, even if its slot's sound_id looks
	# audible (the runtime never fires it).
	if str(span.get("role", "event")) == "terminator":
		return _terminator_sections(span)
	var f: Dictionary = span.get("fields", {})
	var sound_id := int(f.get("sound_id", 0))
	var fields: Array = [
		# Q1 legibility: the lane-identity cell reads "Track", not the ambiguous "Channel"
		# (authors misread that as an off-by-one index). `channel` here is a plain 0-based
		# sub-track number — NOT off-by-1 (the emitter's E<i>→i+1 has no analog).
		_Fields.const_field("Track", str(f.get("channel", 0)),
			"Which of the effect's sound sub-tracks this trigger lives on (0-based)."),
		_sound_id_edit(span, sound_id),
		_duration_edit(span, int(f.get("duration_frames", 0))),
	]
	# ADR-0085 TIER-2: sound_id is a container index (N>=2 → SoundContainer[N-2]). Follow
	# the reference (ADR-0073) into the shared container's legible selection-logic view.
	if sound_id >= 2:
		fields.append(_container_link(sound_id))
	return [{"title": "Sound", "fields": fields}]


## The INERT terminator inspector (ADR-0085): one read-only section naming the end-cap and
## pointing the author back at the byte's real owner (the last event's Gap). No editable /
## navigable cells — it is a projection of "the track ends here", not an authorable slot.
static func _terminator_sections(span: Dictionary) -> Array:
	var track := str(span.get("fields", {}).get("channel", span.get("channel_index", 0)))
	return [{"title": "Sound", "fields": [
		_Fields.const_field("Event", "End of track",
			"The inert terminator end-cap — the runtime stops firing this track here. " +
			"It is not a sound; the frame it sits at is governed by the last event's Gap."),
		_Fields.const_field("Track", track,
			"Which of the effect's sound sub-tracks this end-cap closes (0-based)."),
	]}]


## A clickable `link` cell (ADR-0073) that drills from this trigger into the shared
## SoundContainer it plays through (container_idx = sound_id - 2). The full mode / emitted
## ids / pairs live on the container target; here the label just names the index.
static func _container_link(sound_id: int) -> Dictionary:
	var index := sound_id - 2
	return {
		"name": "Plays",
		"shape": "link",
		"label": "→ container %d" % index,
		"target": _Target.container(index),
	}


## An EDITABLE `int` cell for the trigger's sound_id (u8 0–255), seeded to the
## keyframe's current raw. Carries the three-dim write-side field_ref, plus a tooltip that
## explains the TIER-2 container mapping (Q2 legibility): sound_id N≥2 plays through
## SoundContainer[N−2]; 0/1 are the SKIP sentinels (no container).
static func _sound_id_edit(span: Dictionary, sound_id: int) -> Dictionary:
	return {
		# Author-facing label: "Sound" (the number is a container SELECTOR, not a raw SFX id —
		# 0/1 silent, N>=2 → SoundContainer[N-2]; the "Plays" link below resolves it). "Sound id"
		# read as an opaque hardware id.
		"name": "Sound",
		"shape": "edit",
		"editor": "int",
		"type": "u8",
		"value": sound_id,
		"tooltip": _sound_id_tooltip(sound_id),
		"field_ref": _sound_ref(span, "sound_id"),
	}


## The Sound id cell's self-describing tooltip. N≥2 names the resolved container (N−2);
## 0/1 name the skip sentinel (no container) so no false mapping is claimed.
static func _sound_id_tooltip(sound_id: int) -> String:
	if sound_id >= 2:
		return "Raw trigger id %d → plays SoundContainer[%d] (id − 2)." % [sound_id, sound_id - 2]
	return "%d is a skip sentinel (0/1) — this trigger fires no sound." % sound_id


## An EDITABLE `int` cell for the trigger timing (`duration_frames` = the s16
## time_value / gap until the next trigger fires), seeded to the current raw. Labelled
## `Gap` (ADR-0085): a trigger is an instant, so this is the space to the NEXT trigger,
## not the sound's length (which is the read-only ghost bar).
static func _duration_edit(span: Dictionary, duration: int) -> Dictionary:
	return {
		"name": "Gap",
		"shape": "edit",
		"editor": "int",
		"type": "s16",
		"value": duration,
		"tooltip": "Frames until the NEXT trigger fires on this track — not the sound's length (that's the ghost bar). Editing it shifts every later trigger on the track.",
		"field_ref": _sound_ref(span, "duration_frames"),
	}


## One field's write-side field_ref for the choke point (EffectEditSession.apply_edit).
## Sound has a THREE-dimensional address — phase, channel_index (int), event_index —
## unlike palette's two (phase + channel_name string).
static func _sound_ref(span: Dictionary, field: String) -> Dictionary:
	return {
		"channel": "sound",
		"phase": str(span.get("phase", "")),
		"channel_index": int(span.get("channel_index", -1)),
		"event_index": int(span.get("keyframe_index", -1)),
		"field": field,
	}
