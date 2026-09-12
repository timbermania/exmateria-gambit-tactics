class_name ParticleTimelineChannel
extends RefCounted
## Write-side channel encoder for the PARTICLE TIMELINE — emitter *events* (the spans on
## the timeline: WHEN an emitter fires and WHICH one), as opposed to the emitter's
## parameters (EmitterChannel). Claims the reserved channel name "particle" (ADR-0089
## particle_timeline amendment). Given a raw edit it writes the storage field on the live
## TimelineData.Keyframe, and declares that the edit invalidates the sim (particles are
## born during the sim — no read-live — so a parked frame must re-fold).
##
## ADDRESSING is palette/screen-like, NOT camera: particle channels are FLAT (no
## sub-channels, no coalescing), so a keyframe is 1:1 with storage and its stable address
## is the raw keyframe index (context + channel_index + event_index). Because `time` is
## cumulative-ABSOLUTE (not length-encoded like palette), a boundary edit is a single
## direct `kf[N].time` write — everything downstream stays auto-pinned.
##
## THE INVARIANT: an edit only ever consumes or creates gap (null-span) space; it never
## changes another DRAWN span's extent. This governs the clamps below. Channels supply
## encoders, not mutation logic; the single choke point is EffectEditSession.apply_edit.

const S16_MAX := 32767
const PARTICLE_SLOTS := 25   # the fixed native channel capacity (parse_effect.PARTICLE_SLOTS)
const _TimelineData = ExMateriaEffects.TimelineData


## Write one raw value for the particle keyframe named by `field_ref`, and return the
## snapshot the choke point records for undo.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	var field: String = field_ref.get("field", "")
	# The right-edge grip / typed boundary (slice 2): a scalar kf[N].time re-time, clamped
	# by the gap-trade invariant.
	if field == "boundary_end":
		return _apply_boundary(data, field_ref, int(new_raw))
	# The span inspector's two scalar controls (slice 3): Enabled toggle + Emitter retarget.
	if field == "enabled":
		return _apply_enabled(data, field_ref, int(new_raw))
	if field == "emitter_index":
		return _apply_retarget(data, field_ref, int(new_raw))
	# A RAW boundary write (slice 6 Move): a direct kf[N].time set with NO gap-trade clamp — the
	# per-boundary invariant is enforced ONCE by plan_move, then the two shifts apply verbatim as
	# one apply_compound. Not a user-facing verb on its own.
	if field == "boundary_raw":
		return _apply_boundary_raw(data, field_ref, int(new_raw))
	push_error("ParticleTimelineChannel: unknown particle field '%s'" % field)
	return {}


## A DIRECT kf[N].time write (no clamp, no structural side effect) — the Move slide's member
## edit. before/after carry the raw time so apply_compound's undo replays it verbatim.
static func _apply_boundary_raw(data, field_ref: Dictionary, new_time: int) -> Dictionary:
	var kf = _resolve_keyframe(data, field_ref)
	if kf == null:
		push_error("ParticleTimelineChannel: no keyframe for %s" % str(field_ref))
		return {}
	var before: int = int(kf.time)
	kf.time = new_time
	return {
		"before_raw": before,
		"after_raw": new_time,
		"invalidates_sim": true,
		"invalidates_layout": true,   # apply_compound ORs this → the host reprojects
		"faithful": _s16_faithful(new_time),
	}


## Plan the MOVE slide (ADR-0089 particle_timeline): a body-drag shifts BOTH of span N's
## boundaries by one clamped delta, width preserved. Because time is absolute, the shift is
## absorbed by the two IMMEDIATE neighbours, so BOTH must be gaps (or a phase edge): the left
## neighbour (span N−1) must be a gap and not the pinned origin; the right neighbour (span N+1)
## a gap, or the open tail. A burst wedged between two drawn bursts is PINNED — refused. The
## delta is clamped to the gap room on each side. Returns {ok, edits, delta, reason}; the two
## `boundary_raw` edits apply as one apply_compound (one undo). Pure — no mutation.
static func plan_move(data, field_ref: Dictionary, delta: int) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return {"ok": false, "edits": [], "delta": 0, "reason": "no channel"}
	var n: int = int(field_ref.get("event_index", -1))
	# n must be a real span (>= 1) with a movable LEFT boundary: kf[n-1]. When n == 1 that
	# boundary is the pinned origin kf[0] — a wall, so the first span can never slide.
	if n < 2 or n >= ch.keyframes.size():
		return {"ok": false, "edits": [], "delta": 0, "reason": "the first span is pinned to the origin"}

	# Left neighbour span (window owned by kf[n-1]) must be a gap — moving kf[n-1] changes its
	# width, and a drawn span's extent must not change.
	if int(ch.keyframes[n - 1].emitter_id) != 0:
		return {"ok": false, "edits": [], "delta": 0, "reason": "wedged: the left neighbour is a drawn span"}

	var has_right: bool = (n + 1 <= int(ch.max_keyframe)) and (n + 1 < ch.keyframes.size())
	if has_right and int(ch.keyframes[n + 1].emitter_id) != 0:
		return {"ok": false, "edits": [], "delta": 0, "reason": "wedged: the right neighbour is a drawn span"}

	var left_time: int = int(ch.keyframes[n - 1].time)
	var right_time: int = int(ch.keyframes[n].time)
	# Room: moving LEFT shrinks the left gap (down to zero); moving RIGHT shrinks the right gap
	# (or extends into the open tail up to s16).
	var left_room: int = left_time - int(ch.keyframes[n - 2].time)
	var right_room: int = (int(ch.keyframes[n + 1].time) - right_time) if has_right \
		else (S16_MAX - right_time)
	var d: int = clampi(delta, -left_room, right_room)

	var addr := {"channel": "particle", "context": field_ref.get("context", ""),
		"channel_index": int(field_ref.get("channel_index", -1))}
	var left_edit := addr.duplicate()
	left_edit["event_index"] = n - 1
	left_edit["field"] = "boundary_raw"
	var right_edit := addr.duplicate()
	right_edit["event_index"] = n
	right_edit["field"] = "boundary_raw"
	return {
		"ok": true,
		"delta": d,
		"edits": [
			{"field_ref": left_edit, "new_raw": left_time + d},
			{"field_ref": right_edit, "new_raw": right_time + d},
		],
	}


## The ENABLED toggle (ADR-0089 particle_timeline): the ROM's only "off" is `emitter_id 0`,
## which loses the identity — so disable STASHES the prior `emitter_id` on a transient keyframe
## field (the screen/palette kf-object-stash precedent) and zeroes it; enable restores the
## stash. Session-only by construction: a saved-disabled span reloads as an ordinary gap (the
## stash is never serialized). Self-inverse through the scalar undo replay: undo of a disable
## replays enabled=1 with the stash still present; undo of an enable replays enabled=0,
## re-stashing the same id. Enabling with no remembered id is a no-op (nothing to restore).
static func _apply_enabled(data, field_ref: Dictionary, new_val: int) -> Dictionary:
	var kf = _resolve_keyframe(data, field_ref)
	if kf == null:
		push_error("ParticleTimelineChannel: no keyframe for %s" % str(field_ref))
		return {}
	var before: int = 1 if int(kf.emitter_id) != 0 else 0
	var on: bool = new_val != 0
	if on:
		if int(kf.remembered_emitter_id) == 0:
			# Cold gap with nothing remembered — enabling restores nothing, records no undo.
			return {"before_raw": before, "after_raw": before, "no_edit": true,
				"invalidates_sim": false, "faithful": {"ok": true, "reason": ""}}
		kf.emitter_id = int(kf.remembered_emitter_id)
		kf.remembered_emitter_id = 0
	else:
		if int(kf.emitter_id) == 0:
			# Already off — no byte changes, no undo entry.
			return {"before_raw": before, "after_raw": before, "no_edit": true,
				"invalidates_sim": false, "faithful": {"ok": true, "reason": ""}}
		kf.remembered_emitter_id = int(kf.emitter_id)
		kf.emitter_id = 0
	return {
		"before_raw": before,
		"after_raw": 1 if on else 0,
		"invalidates_sim": true,
		# A visibility flip restyles the span (drawn ↔ dimmed null span) → host reprojects.
		"relayout": true,
		"faithful": {"ok": true, "reason": ""},
	}


## The EMITTER retarget picker (ADR-0089 particle_timeline): point the span at a different
## emitter. `new_index` is the 0-based emitter index (the ROM stores `emitter_id = index + 1`).
## Editable even while DISABLED — a disabled span retargets its REMEMBERED id (so re-enabling
## fires the new emitter); a live span retargets `emitter_id` directly. before/after carry the
## 0-based index so the scalar undo replays straight back.
static func _apply_retarget(data, field_ref: Dictionary, new_index: int) -> Dictionary:
	var kf = _resolve_keyframe(data, field_ref)
	if kf == null:
		push_error("ParticleTimelineChannel: no keyframe for %s" % str(field_ref))
		return {}
	var before: int = _current_index(kf)
	var new_id: int = new_index + 1
	if int(kf.emitter_id) != 0:
		kf.emitter_id = new_id            # live retarget
	else:
		kf.remembered_emitter_id = new_id  # retarget while disabled (stays off, new target)
	return {
		"before_raw": before,
		"after_raw": new_index,
		"invalidates_sim": true,
		"relayout": true,
		"faithful": _emitter_index_faithful(new_index),
	}


## The 0-based emitter index the span currently targets: the LIVE emitter_id when enabled, the
## REMEMBERED id when disabled. -1 when neither is set (a cold gap).
static func _current_index(kf) -> int:
	var id: int = int(kf.emitter_id) if int(kf.emitter_id) != 0 else int(kf.remembered_emitter_id)
	return id - 1


## Faithful advisory: the ROM's 14-slot emitter table indexes 0..13, stored as emitter_id
## 1..14 in a u8. An index outside that range can't be stored.
static func _emitter_index_faithful(index: int) -> Dictionary:
	if index < 0 or index > 13:
		return {"ok": false,
			"reason": "emitter index %d is outside the 14-slot emitter table (0–13)" % index}
	return {"ok": true, "reason": ""}


## Resolve the addressed keyframe (context + channel_index + raw event_index).
static func _resolve_keyframe(data, field_ref: Dictionary):
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return null
	var n: int = int(field_ref.get("event_index", -1))
	if n < 0 or n >= ch.keyframes.size():
		return null
	return ch.keyframes[n]


## The RESIZE edit (ADR-0089 particle_timeline): drag span N's RIGHT edge = write kf[N].time.
## Every internal boundary is exactly one span's right edge; the origin (kf[0]) has no grip.
##
## GROW consumes the adjacent gap and clamps at the next stored boundary; a DRAWN neighbour is
## a wall (frozen — Add a null span first to grow past it). When a grow consumes a gap to zero
## width, the gap slot is RECLAIMED (structural). SHRINK always works: against a gap (or tail)
## it just widens the gap; against a DRAWN neighbour it AUTO-OPENS a null span in the vacated
## space (structural) so the neighbour keeps its extent — it is never stretched. `time` is
## absolute, so nothing downstream re-derives. Undo of every boundary edit is a channel
## snapshot (the session stashes it), so a structural side effect unwinds cleanly.
static func _apply_boundary(data, field_ref: Dictionary, new_time: int) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("ParticleTimelineChannel: no channel for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	# kf[0] is the pinned phase origin (period 0) — its "right edge" is span 1's, not its own,
	# and it is never editable. Any n outside (0, size) is out of range.
	if n <= 0 or n >= ch.keyframes.size():
		push_error("ParticleTimelineChannel: boundary index %d not editable" % n)
		return {}
	var kf = ch.keyframes[n]
	var prev = ch.keyframes[n - 1]
	var before: int = int(kf.time)
	var floor_t: int = int(prev.time) + 1

	var has_next: bool = (n + 1 <= int(ch.max_keyframe)) and (n + 1 < ch.keyframes.size())
	var next_drawn: bool = has_next and int(ch.keyframes[n + 1].emitter_id) != 0 \
		and int(ch.keyframes[n + 1].time) > before

	if new_time < before:
		# --- SHRINK ---
		var t: int = maxi(new_time, floor_t)
		if next_drawn:
			# Auto-open a null span filling the vacated [t, before): the drawn neighbour keeps
			# its extent (never stretched). Structural — the keyframe array grows.
			kf.time = t
			ch.keyframes.insert(n + 1, _new_gap_keyframe(before))
			ch.max_keyframe = int(ch.max_keyframe) + 1
			return _boundary_result(before, t, true)
		# Gap or tail neighbour: just widen the gap / shrink the tail. Scalar.
		kf.time = t
		return _boundary_result(before, t, false)

	if new_time > before:
		# --- GROW ---
		if not has_next:
			kf.time = mini(new_time, S16_MAX)   # tail: grow freely
			return _boundary_result(before, int(kf.time), false)
		if next_drawn:
			return _boundary_result(before, before, false)   # frozen against a drawn wall
		var gap_end: int = int(ch.keyframes[n + 1].time)
		if new_time >= gap_end:
			# The gap is consumed to zero width — reclaim its slot. Structural.
			kf.time = gap_end
			ch.keyframes.remove_at(n + 1)
			ch.max_keyframe = maxi(0, int(ch.max_keyframe) - 1)
			return _boundary_result(before, gap_end, true)
		kf.time = new_time   # partial gap consume. Scalar.
		return _boundary_result(before, new_time, false)

	return _boundary_result(before, before, false)   # no change


static func _boundary_result(before: int, after: int, structural: bool) -> Dictionary:
	return {
		"before_raw": before,
		"after_raw": after,
		# Particles are born during the sim (no read-live) — a boundary move must re-fold.
		"invalidates_sim": true,
		# The span geometry changed → relayout (host reprojects + re-folds). structural marks a
		# keyframe insert/reclaim so the host takes the same full-refresh path.
		"relayout": true,
		"structural": structural,
		"faithful": _s16_faithful(after),
	}


# --- Structural verbs: Add / Delete (ADR-0089 particle_timeline) --------------


## ADD (insert_event): split the window covering `field_ref.frame` (phase-local), seeding the
## new keyframe BORN DISABLED (emitter_id 0 — a real gap, so Add never adds spawning) carrying
## a remembered emitter (the covering span's own id if drawn, else the nearest previous drawn,
## else emitter 1) so it draws dimmed and the author can enable/retarget it. Past the last
## keyframe it appends a disabled span at the tail. REFUSES when the channel is full (25 slots)
## — raise, never truncate (the camera writer's rule, applied at the verb). Structural: the
## keyframe array grows, so undo is snapshot-based. Returns `{structural, event_index}`.
static func insert_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("ParticleTimelineChannel: no channel to insert into for %s" % str(field_ref))
		return {}
	if _used(ch) >= PARTICLE_SLOTS:
		push_error("ParticleTimelineChannel: channel full (%d slots) — Add refused" % PARTICLE_SLOTS)
		return {}
	var frame: int = int(field_ref.get("frame", 0))
	var c: int = _covering_index(ch, frame)
	var new_index: int
	if c < 0:
		# Tail: append a disabled span after the last used keyframe.
		var last_i: int = _last_index(ch)
		var t: int = maxi(frame, int(ch.keyframes[last_i].time) + 1)
		ch.keyframes.insert(last_i + 1, _new_disabled_keyframe(t, _nearest_prev_drawn_id(ch, last_i + 1)))
		new_index = last_i + 1
	else:
		var kf_c = ch.keyframes[c]
		var start_t: int = int(ch.keyframes[c - 1].time)
		if int(kf_c.time) - start_t < 2:
			push_error("ParticleTimelineChannel: window too narrow to split at frame %d" % frame)
			return {}
		var f: int = clampi(frame, start_t + 1, int(kf_c.time) - 1)
		var remembered: int = int(kf_c.emitter_id) if int(kf_c.emitter_id) != 0 \
			else _nearest_prev_drawn_id(ch, c)
		# The new keyframe takes the SECOND half [f, old_end) disabled; the covering keyframe
		# keeps [start, f) with its own emitter (mirrors PaletteChannel.insert_event).
		ch.keyframes.insert(c + 1, _new_disabled_keyframe(int(kf_c.time), remembered))
		kf_c.time = f
		new_index = c + 1
	ch.max_keyframe = int(ch.max_keyframe) + 1
	return {"structural": true, "event_index": new_index, "invalidates_sim": true}


## DELETE (delete_event): remove the addressed keyframe (raw event_index). Because `time` is
## absolute, the NEXT keyframe simply owns the merged window down to the previous boundary —
## everything downstream stays pinned. The slot is reclaimed. Deleting the origin is refused.
## Structural + snapshot undo. Returns `{structural, event_index}` selecting the merged span
## (or the previous one at the tail; -1 when the lane has no spans left).
static func delete_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("ParticleTimelineChannel: no channel to delete from for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	if n <= 0 or n >= ch.keyframes.size():
		push_error("ParticleTimelineChannel: keyframe index %d not deletable" % n)
		return {}
	ch.keyframes.remove_at(n)
	ch.max_keyframe = maxi(0, int(ch.max_keyframe) - 1)
	# Land selection on the span that closed up over the freed window (now at index n), else the
	# previous span at the tail; nothing if no spans remain.
	var neighbour: int = -1
	if int(ch.max_keyframe) >= 1:
		neighbour = mini(n, int(ch.max_keyframe))
		if neighbour < 1:
			neighbour = -1
	return {"structural": true, "event_index": neighbour, "invalidates_sim": true}


## Deep-copy the channel's keyframe state — the pre-edit snapshot the choke point stashes for
## structural (and boundary) undo. The verbs mutate the live array in place, so the copy must
## be independent.
static func snapshot(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return {}
	return {
		"context": field_ref.get("context", ""),
		"channel_index": int(field_ref.get("channel_index", -1)),
		"keyframes": _dup_keyframes(ch.keyframes),
		"max_keyframe": int(ch.max_keyframe),
	}


## Restore a channel snapshot wholesale (the undo inverse of the structural verbs + boundary).
static func restore(data, snap: Dictionary) -> void:
	if data == null or data.timeline == null or snap.is_empty():
		return
	var ch = _resolve_channel(data, {"context": snap.get("context", ""),
		"channel_index": int(snap.get("channel_index", -1))})
	if ch == null:
		return
	# ch.keyframes is a typed Array[Keyframe] — assign element-wise (a plain-Array assignment is
	# rejected). Deep-copy the snapshot's keyframes so the snapshot stays PRISTINE across repeated
	# restores (the Move drag preview restores-then-reapplies every motion off one snapshot).
	ch.keyframes.clear()
	for kf in _dup_keyframes(snap["keyframes"]):
		ch.keyframes.append(kf)
	ch.max_keyframe = int(snap["max_keyframe"])


# --- Structural helpers -------------------------------------------------------


## Used slots = the watermark + 1 (indices 0..max_keyframe). The capacity gate for Add.
static func _used(ch) -> int:
	return int(ch.max_keyframe) + 1


## The last used keyframe index (watermark, clamped to the live array).
static func _last_index(ch) -> int:
	return mini(int(ch.max_keyframe), ch.keyframes.size() - 1)


## The keyframe index whose window `[kf[c-1].time, kf[c].time)` contains `frame`, in 1..last.
## -1 when `frame` is at/after the last boundary (a tail insert).
static func _covering_index(ch, frame: int) -> int:
	var last_i: int = _last_index(ch)
	for c in range(1, last_i + 1):
		if int(ch.keyframes[c - 1].time) <= frame and frame < int(ch.keyframes[c].time):
			return c
	return -1


## The emitter_id of the nearest DRAWN (or remembered) keyframe before `before_index`; emitter
## 1 (id 1) when there is none — the Add seed's remembered target.
static func _nearest_prev_drawn_id(ch, before_index: int) -> int:
	for i in range(mini(before_index - 1, ch.keyframes.size() - 1), 0, -1):
		var id: int = int(ch.keyframes[i].emitter_id)
		if id == 0:
			id = int(ch.keyframes[i].remembered_emitter_id)
		if id != 0:
			return id
	return 1


## A fresh DISABLED span keyframe: emitter_id 0 (a gap in the ROM) carrying a remembered id so
## it draws dimmed and re-enables to that emitter.
static func _new_disabled_keyframe(time: int, remembered_id: int):
	var kf = _TimelineData.Keyframe.new()
	kf.time = time
	kf.emitter_id = 0
	kf.remembered_emitter_id = remembered_id
	kf.action_flags = 0
	return kf


## A fresh PURE-GAP keyframe (emitter_id 0, nothing remembered) — the auto-opened null span a
## shrink-against-a-wall leaves behind. Draws nothing.
static func _new_gap_keyframe(time: int):
	var kf = _TimelineData.Keyframe.new()
	kf.time = time
	kf.emitter_id = 0
	kf.remembered_emitter_id = 0
	kf.action_flags = 0
	return kf


static func _dup_keyframes(kfs: Array) -> Array:
	var out: Array = []
	for kf in kfs:
		var n = _TimelineData.Keyframe.new()
		n.time = int(kf.time)
		n.emitter_id = int(kf.emitter_id)
		n.action_flags = int(kf.action_flags)
		n.remembered_emitter_id = int(kf.remembered_emitter_id)
		out.append(n)
	return out


## Resolve the addressed channel: particle has a TWO-dimensional address — phase context AND
## channel_index (the 0-4 lane). Flat, so no sub-channel / ordinal indirection.
static func _resolve_channel(data, field_ref: Dictionary):
	if data == null or data.timeline == null:
		return null
	var idx: int = int(field_ref.get("channel_index", -1))
	for ch in data.timeline.get_channels(field_ref.get("context", "")):
		if int(ch.channel_index) == idx:
			return ch
	return null


## Non-destructive Faithful advisory: a particle `time` only lowers to E###.BIN if it fits
## the signed-16-bit SoA encoding (parse reads back with "<h").
static func _s16_faithful(raw: int) -> Dictionary:
	if raw < -32768 or raw > S16_MAX:
		return {"ok": false,
			"reason": "time = %d is outside the signed 16-bit encoding (Free-only)" % raw}
	return {"ok": true, "reason": ""}
