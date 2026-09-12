class_name SoundChannel
extends RefCounted
## Write-side channel archetype for the SOUND TIMELINE SFX-trigger tracks (#268) —
## the six outer (phase1/phase2) + three for-each trigger lanes. Given a raw-byte
## edit it writes the storage field on the live keyframe and declares whether the
## edit invalidates the sim. Channels supply encoders, not mutation logic; the
## single choke point is EffectEditSession.apply_edit.
##
## Model DIFFERS from ScreenChannel/PaletteChannel: `EffectData.sound` is a RAW
## `Dictionary` parsed straight from sound.json ({ phase -> [channel dicts] }), not a
## typed Keyframe object. So the encoder mutates dict entries directly
## (`kf["sound_id"] = new_raw`). Dictionaries are reference types, so the score model —
## which reads this SAME `data.sound` (EffectScoreModel._sound_lanes) and not a copy —
## sees the mutation live.
##
## Address is THREE-dimensional (palette had two): phase ∈ {phase1,phase2,for_each} ×
## channel_index ∈ {0,1,2} × event_index. Editable fields per keyframe: `sound_id`
## (u8) and `duration_frames` (the s16 time_value = trigger timing).
##
## `invalidates_sim = false`: sound triggers fire one-shot during the pump and have NO
## visual framebuffer impact, so no re-fold is needed and the studio preview repaints
## nothing. (The AUDIO only re-fires on the next playthrough — the studio preview is
## visual; immediate re-audition is a follow-up.)
##
## RE / semantics (FEDS 3-tier map): sound_id is NOT a raw SFX id — 0/1 = skip,
## N>=2 indexes SoundContainer[N-2] (TIER-2, effect-flags section) which resolves via a
## mode to a FEDS pair (TIER-3, header[0x20]). We surface the raw TIER-1 byte and stay
## faithful to it; a named-enum editor needs TIER-2 resolution and is a follow-up.
## ROM read: `lbu a0,0x12(v0)` (outer sound walker @0x801A47E0).

const _S16_MIN := -32768
const _S16_MAX := 32767


## Write one raw value for the sound keyframe named by `field_ref`, and return the
## snapshot the choke point records for undo.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var kf = _resolve_keyframe(data, field_ref)
	if kf == null:
		push_error("SoundChannel: no sound keyframe for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")
	if field == "sound_id":
		return _apply_field(kf, "sound_id", int(new_raw), _byte_verdict("sound_id", int(new_raw)))
	if field == "duration_frames":
		# `duration_frames` is the GAP to the next trigger: changing it shifts trigger i+1
		# and every later marker on the channel (EffectScoreModel runs `local += dur`), so
		# it invalidates the timeline MARKER LAYOUT — the third response axis, orthogonal to
		# invalidates_sim (framebuffer). The page reprojects the ruler on it while preserving
		# transport. (sound_id changes the resolved ghost LENGTH, not a fire frame — its
		# heavier ghost-reproject is deferred, so it stays layout-false for now.)
		return _apply_field(kf, "duration_frames", int(new_raw),
			_s16_verdict("duration_frames", int(new_raw)), true)
	if field == "anchor_offset":
		# ADR-0085 anchor: authoring-only metadata carried on the live keyframe. It is
		# NEVER lowered to E###.BIN (the writer drops it), so it is ALWAYS faithful —
		# no byte/s16 range applies. Like the others it has no framebuffer impact.
		return _apply_field(kf, "anchor_offset", int(new_raw), {"ok": true, "reason": ""})
	push_error("SoundChannel: unknown sound field '%s'" % field)
	return {}


## Write one raw field on the live keyframe dict (reference type → score model sees it).
## `invalidates_layout` (default false) declares that the edit MOVES timeline markers (a
## Gap edit does; a sound_id/anchor edit does not) — the third response axis the page
## reprojects the ruler on.
static func _apply_field(kf: Dictionary, key: String, new_raw: int, faithful: Dictionary,
		invalidates_layout: bool = false) -> Dictionary:
	var before: int = int(kf.get(key, 0))
	kf[key] = new_raw
	return {
		"before_raw": before,
		"after_raw": new_raw,
		"invalidates_sim": false,
		"invalidates_layout": invalidates_layout,
		"faithful": faithful,
	}


## Non-destructive Faithful advisory: a u8-encoded field only lowers to E###.BIN if
## it fits its unsigned byte range.
static func _byte_verdict(field: String, raw: int) -> Dictionary:
	if raw < 0 or raw > 255:
		return {
			"ok": false,
			"reason": "%s = %d is outside the 0–255 byte encoding (Free-only)" % [field, raw],
		}
	return {"ok": true, "reason": ""}


## Faithful advisory for the s16 time_value: only fits if within signed-16 range.
static func _s16_verdict(field: String, raw: int) -> Dictionary:
	if raw < _S16_MIN or raw > _S16_MAX:
		return {
			"ok": false,
			"reason": "%s = %d does not fit the signed-16 time_value (%d..%d)" % [field, raw, _S16_MIN, _S16_MAX],
		}
	return {"ok": true, "reason": ""}


# --- Structural lane verbs (ADD / DELETE a trigger event) --------------------
#
# The third instance of the ADR-0086/0087 span-lane verbs (camera, palette-designed,
# sound). Sound is LENGTH-encoded: `duration_frames` is the GAP to the next trigger,
# a fire frame is the prefix sum. So:
#   insert at frame F = split the CONTAINING gap in TIME (two gaps summing to the
#     original — every other fire frame is pinned), seeded `sound_id = 0` (the honest
#     silent no-op; 0/1 = skip);
#   delete event j = merge its gap into the PREDECESSOR's (the inverse — every later
#     fire pinned). The FIRST event has no predecessor: the successor absorbs the gap.
# Capacity is the channel's NATIVE slot budget = its keyframes array length (the
# byte-exact writer serializes exactly that many slots: 9 outer / 17 for-each); a full
# channel REFUSES the insert (mirror the camera writer's raise-over-cap — never
# silently drop a byte). Both verbs REPLACE `data.sound[phase][ci]` with a NEW channel
# dict (the old one is never mutated) so the EffectEditSession's structural undo can
# stash the pre-edit object as an exact snapshot.


## Insert a new (silent) trigger event at `field_ref.frame` (phase-LOCAL). The frame is
## clamped into the live window [0, terminator-1]; the containing gap splits at it.
## Returns the structural result with `ordinal` = the new event's index, or {} when the
## channel is unknown, empty (nothing to split), or at native capacity.
static func insert_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return {}
	var kfs: Array = ch["keyframes"]
	var max_kf: int = int(ch.get("max_keyframe", 0))
	if max_kf < 1:
		push_error("SoundChannel: insert into an empty channel is not supported (no gap to split)")
		return {}
	if max_kf + 1 >= kfs.size():
		push_error("SoundChannel: channel is at its native slot budget (%d) — cannot insert" % kfs.size())
		return {}

	# Fires are prefix sums; the terminator caps the live window at fire[last] + gap[last].
	var term: int = 0
	for i in range(max_kf):
		term += int(kfs[i].get("duration_frames", 0))
	if term < 1:
		push_error("SoundChannel: every gap is zero — no room to split")
		return {}
	var frame: int = clampi(int(field_ref.get("frame", 0)), 0, term - 1)

	# Find the containing gap [fire[i], fire[i] + dur[i]).
	var fire: int = 0
	var at: int = -1
	for i in range(max_kf):
		var dur: int = int(kfs[i].get("duration_frames", 0))
		if frame >= fire and frame < fire + dur:
			at = i
			break
		fire += dur
	if at < 0:
		return {}   # unreachable after the clamp; defensive

	var new_kfs: Array = []
	for i in range(kfs.size()):
		new_kfs.append(kfs[i].duplicate(true))
	var remainder: int = int(new_kfs[at]["duration_frames"]) - (frame - fire)
	new_kfs[at]["duration_frames"] = frame - fire
	new_kfs.insert(at + 1, {"duration_frames": remainder, "sound_id": 0})
	new_kfs.pop_back()   # the freed padding slot absorbs the growth — native count holds

	_replace_channel(data, field_ref, ch, new_kfs, max_kf + 1)
	return _structural_result(at + 1)


## Delete the event at `field_ref.event_index`, merging its gap into the predecessor
## (successor for index 0) so every later fire frame is pinned. Refuses the terminator
## (index == max_keyframe — its bytes are the last event's gap) and out-of-window
## indices. `ordinal` = the neighbour to select, or -1 when the channel emptied.
static func delete_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return {}
	var kfs: Array = ch["keyframes"]
	var max_kf: int = int(ch.get("max_keyframe", 0))
	var at: int = int(field_ref.get("event_index", -1))
	if at < 0 or at >= max_kf:
		push_error("SoundChannel: no sound event at index %d to delete (live window 0..%d)"
			% [at, max_kf - 1])
		return {}

	var new_kfs: Array = []
	for i in range(kfs.size()):
		new_kfs.append(kfs[i].duplicate(true))
	var gap: int = int(new_kfs[at]["duration_frames"])
	if at > 0:
		new_kfs[at - 1]["duration_frames"] = int(new_kfs[at - 1]["duration_frames"]) + gap
	elif max_kf > 1:
		new_kfs[1]["duration_frames"] = int(new_kfs[1]["duration_frames"]) + gap
	new_kfs.remove_at(at)
	new_kfs.append({"duration_frames": 0, "sound_id": 0})   # the freed slot returns as padding

	_replace_channel(data, field_ref, ch, new_kfs, max_kf - 1)
	# Selection falls to the previous neighbour (the new first event when index 0 was
	# deleted); -1 when the channel emptied.
	var remaining: int = max_kf - 1
	return _structural_result(-1 if remaining == 0 else clampi(at - 1, 0, remaining - 1))


## Selection lands on `ordinal` (the new event / the surviving neighbour). Sound has no
## framebuffer impact (`invalidates_sim = false` like every sound edit); `structural`
## makes the host re-project the score and the page re-land the selection.
static func _structural_result(ordinal: int) -> Dictionary:
	return {
		"structural": true,
		"invalidates_sim": false,
		"faithful": {"ok": true, "reason": ""},
		"ordinal": ordinal,
	}


## Swap the addressed slot to a NEW channel dict carrying `new_kfs` / `new_max`. Every
## other channel key (channel_index, parser extras) is copied over verbatim.
static func _replace_channel(data, field_ref: Dictionary, old_ch: Dictionary,
		new_kfs: Array, new_max: int) -> void:
	var new_ch: Dictionary = old_ch.duplicate(false)
	new_ch["keyframes"] = new_kfs
	new_ch["max_keyframe"] = new_max
	data.sound[str(field_ref.get("phase", ""))][int(field_ref.get("channel_index", -1))] = new_ch


## Resolve the addressed CHANNEL dict (`data.sound[phase][channel_index]`), or null.
static func _resolve_channel(data, field_ref: Dictionary):
	if data == null or data.sound == null or not (data.sound is Dictionary):
		return null
	var channels = data.sound.get(str(field_ref.get("phase", "")), null)
	if not (channels is Array):
		return null
	var ci: int = int(field_ref.get("channel_index", -1))
	if ci < 0 or ci >= channels.size() or not (channels[ci] is Dictionary):
		return null
	var ch: Dictionary = channels[ci]
	if not (ch.get("keyframes", null) is Array):
		return null
	return ch


## Resolve the addressed keyframe by walking the raw dict:
## `data.sound[phase][channel_index]["keyframes"][event_index]`. The parser emits the
## three channels positionally (index 0,1,2 == channel_index), so we index by position.
static func _resolve_keyframe(data, field_ref: Dictionary):
	if data == null or data.sound == null or not (data.sound is Dictionary):
		return null
	var phase: String = str(field_ref.get("phase", ""))
	var channels = data.sound.get(phase, null)
	if not (channels is Array):
		return null
	var ci: int = int(field_ref.get("channel_index", -1))
	if ci < 0 or ci >= channels.size() or not (channels[ci] is Dictionary):
		return null
	var kfs = channels[ci].get("keyframes", null)
	if not (kfs is Array):
		return null
	var ei: int = int(field_ref.get("event_index", -1))
	if ei < 0 or ei >= kfs.size() or not (kfs[ei] is Dictionary):
		return null
	return kfs[ei]
