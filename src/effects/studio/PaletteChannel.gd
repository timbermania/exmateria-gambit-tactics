class_name PaletteChannel
extends RefCounted
## Write-side channel archetype for the PALETTE / field-tint channel (#266) — the
## unit/map colour tracks (affected_units / caster / target across the three
## phases). Copies ScreenChannel: given a raw-byte edit it writes the storage
## field on the live PaletteData.Keyframe, recomputes the derived cache, and
## declares whether the edit invalidates the sim.
##
## Palette colour is READ-LIVE — PaletteSubsystem rebuilds its ColorStack from the
## keyframes every frame (no per-frame stepper; see PaletteSubsystem "no held
## per-frame output state"), so a colour / blend / enable edit reaches the preview
## IN PLACE with no re-seek (`invalidates_sim = false`; EffectInstance.
## redeliver_colors re-folds the read-live palette lane). Channels supply encoders,
## not mutation logic; the single choke point is EffectEditSession.apply_edit.
##
## RE: channel-0 (affected_units) tints map terrain bank0 AND every affected unit's
## CLUT banks 3/4 (`advance_affected_units_palette_track @0x801A41A0`); the studio
## preview currently routes Field→map-only (a known parity gap) — we surface the
## colour and stay faithful to the stored bytes.
##
## Fields: r/g/b are absolute UNSIGNED colour bytes (colour = raw/255, like a
## Gradient stop — no signed solver). blend_mode (bits 0-6) and enabled (bit 7)
## SHARE the ctrl byte, so each is a read-modify-write preserving the other's bits;
## the `enabled` toggle fans the whole recomputed ctrl word (field "ctrl").

const _RGB_COMPONENT := {"r": 0, "g": 1, "b": 2}
const _Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const _PaletteData = ExMateriaEffects.PaletteData
const _SpacerVerdicts = preload("res://src/effects/studio/SpacerVerdicts.gd")
const _MovePlan = preload("res://src/effects/studio/ColourMovePlan.gd")


## Write one raw byte for the palette keyframe named by `field_ref`, recompute the
## derived cache, and return the snapshot the choke point records for undo.
static func apply_raw(data, field_ref: Dictionary, new_raw) -> Dictionary:
	# The boundary-drag pseudo-field (ADR-0087) is a channel-level trade, not a per-keyframe
	# byte — resolve the whole channel + index rather than one keyframe.
	if field_ref.get("field", "") == "boundary_end":
		return _apply_boundary(data, field_ref, int(new_raw))
	# The typed Duration row (ADR-0087 dec. 9) is the SAME boundary edit in duration
	# units — the channel adds the cumulative start the inspector doesn't know.
	if field_ref.get("field", "") == "duration":
		return _apply_duration(data, field_ref, int(new_raw))
	var kf = _resolve_keyframe(data, field_ref)
	if kf == null:
		push_error("PaletteChannel: no palette keyframe for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")
	var res: Dictionary
	if _RGB_COMPONENT.has(field):
		res = _apply_rgb(kf, field, int(new_raw))
	elif field == "ctrl":
		res = _apply_ctrl(kf, int(new_raw))
	elif field == "blend_mode":
		res = _apply_blend_mode(kf, int(new_raw))
	elif field == "enabled":
		res = _apply_enabled(kf, int(new_raw))
	else:
		push_error("PaletteChannel: unknown palette field '%s'" % field)
		return {}
	# RESTYLE (ADR-0087 decs. 17-22, decision 4): every VALUE edit flags layout
	# unconditionally — the spacer verdict is contextual (disable-equivalence over the
	# whole stream), so an edit HERE can flip ANY keyframe's verdict, same channel, any
	# phase. The host rebuild recomputes verdicts lane-wide without re-deriving the
	# inspector (the spinbox being typed into keeps focus). This subsumes and replaces
	# the third amendment's per-keyframe verdict-flip detection.
	if not res.is_empty():
		res["invalidates_layout"] = true
	return res


## Write one absolute RGB component byte (r/g/b) — Vector3i is a value type, so
## read-modify-write the whole vector. Colour = raw/255, so no derived cache to
## recompute (the score model hues directly from rgb).
static func _apply_rgb(kf, field: String, new_raw: int) -> Dictionary:
	var comp: int = _RGB_COMPONENT[field]
	var rgb: Vector3i = kf.rgb
	var before: int = rgb[comp]
	rgb[comp] = new_raw
	kf.rgb = rgb
	return {
		"before_raw": before,
		"after_raw": new_raw,
		"invalidates_sim": false,
		"faithful": _byte_verdict(field, new_raw),
	}


## Toggle the enabled bit-7 (ADR-0087) — a read-modify-write preserving blend_mode (bits 0-6).
## `new_val` is 0/1 (the choice index). A disabled tween is a null tween that HOLDS its tile, so
## this is read-live (invalidates_sim=false); it restyles the lane span, so it invalidates the
## layout (the host reprojects). `before/after_raw` carry the 0/1 enable state for undo.
static func _apply_enabled(kf, new_val: int) -> Dictionary:
	var before: int = 1 if kf.enabled else 0
	var on: bool = new_val != 0
	kf.ctrl = (int(kf.ctrl) & 0x7F) | (0x80 if on else 0)
	kf.enabled = on
	return {
		"before_raw": before,
		"after_raw": 1 if on else 0,
		"invalidates_sim": false,
		"invalidates_layout": true,
		"faithful": {"ok": true, "reason": ""},
	}


## Toggle/write the whole ctrl byte (enabled bit-7 + blend_mode bits 0-6). The
## `enabled` bitflags editor fans the recomputed full word here; we re-derive both
## cached flags so the projection stays consistent.
static func _apply_ctrl(kf, new_raw: int) -> Dictionary:
	var before: int = int(kf.ctrl)
	kf.ctrl = new_raw & 0xFF
	kf.enabled = (kf.ctrl & 0x80) != 0
	kf.blend_mode = kf.ctrl & 0x7F
	return {
		"before_raw": before,
		"after_raw": new_raw & 0xFF,
		"invalidates_sim": false,
		"faithful": _byte_verdict("ctrl", new_raw),
	}


## Write the blend mode (ctrl bits 0-6) — a read-modify-write preserving the
## enabled bit-7. `before/after_raw` carry the blend-mode code (0-10).
static func _apply_blend_mode(kf, new_mode: int) -> Dictionary:
	var before: int = int(kf.blend_mode)
	kf.ctrl = (int(kf.ctrl) & 0x80) | (new_mode & 0x7F)
	kf.blend_mode = new_mode & 0x7F
	return {
		"before_raw": before,
		"after_raw": new_mode,
		"invalidates_sim": false,
		"faithful": _blend_mode_verdict(new_mode),
	}


## The BOUNDARY-DRAG edit (ADR-0087): re-time a palette tween by dragging the shared edge
## between it (array keyframe N) and its lane-neighbour (N+1). Because palette is length-encoded
## with cumulative starts, moving one absolute boundary is a SUM-PRESERVING trade — span N's
## duration becomes `new_local_end − start_N` (snapped to an 8-frame step, clamped so the
## neighbour keeps ≥ 1 frame) and the neighbour absorbs the difference, so their FAR edge (and
## everything downstream) stays PINNED. `new_raw` is the desired phase-local end frame;
## `before_raw` is the pristine boundary so the scalar undo/coalesce restore it exactly. Read-
## live (invalidates_sim=false). FAITHFUL NOTE: when the two original durations are off the
## 8-grid (a time_value-0 1-frame neighbour), snapping both cannot preserve the far edge to the
## frame — it may drift ≤7 frames, the same Faithful-not-byte-exact compromise camera accepts.
## The lane TAIL (no keyframe N+1) has nothing to pin, so it simply extends span N.
static func _apply_boundary(data, field_ref: Dictionary, new_local_end: int) -> Dictionary:
	if data == null or data.palette == null:
		return {}
	var ch = data.palette.get_channel(
		field_ref.get("context", ""), field_ref.get("channel_name", ""))
	if ch == null:
		push_error("PaletteChannel: no palette channel for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	if n < 0 or n >= ch.keyframes.size():
		push_error("PaletteChannel: boundary index %d out of range" % n)
		return {}

	# Cumulative start of keyframe N (durations of everything before it, unchanged by this edit).
	var start_n: int = 0
	for i in range(n):
		start_n += _Lowering.duration_for_time_value(int(ch.keyframes[i].time_value))
	var kf = ch.keyframes[n]
	var dur_n: int = _Lowering.duration_for_time_value(int(kf.time_value))
	var before_local_end: int = start_n + dur_n

	var has_next: bool = n + 1 < ch.keyframes.size()
	var desired: int = new_local_end - start_n
	var new_dur_n: int
	# RIPPLE mode (ADR-0087 dec. 10): the author explicitly chose to let downstream
	# shift, so a mid-lane resize takes the tail-extend path — one duration write, neighbour
	# untouched, everything after slides by the delta (length-encoding makes that free). The
	# flag rides the field_ref so undo replays the same semantics even after the toggle flips.
	if has_next and not bool(field_ref.get("ripple", false)):
		var next_kf = ch.keyframes[n + 1]
		var total: int = dur_n + _Lowering.duration_for_time_value(int(next_kf.time_value))
		# FAR-EDGE FREEZE (ADR-0087 dec. 30, ADR-0101 decision 1): the chooser returns
		# two FAITHFUL lengths summing to `total` exactly, so the neighbour's far edge cannot
		# move. Never `total - new_dur_n` — that residual is storable only by luck, and
		# `_set_duration` re-snapping it is what slid the far edge ±1 frame.
		var trade := _Lowering.trade_durations(total, desired)
		new_dur_n = int(trade["first"])
		_set_duration(kf, new_dur_n)
		_set_duration(next_kf, int(trade["second"]))
	else:
		new_dur_n = maxi(1, _Lowering.snap_duration(desired))   # tail / ripple: extend, no trade
		_set_duration(kf, new_dur_n)

	return {
		"before_raw": before_local_end,
		"after_raw": start_n + new_dur_n,
		"invalidates_sim": false,
		# The boundary moved (and the neighbour's width with it) but the field set is unchanged —
		# a LAYOUT edit, so the host reprojects the ruler without re-deriving the inspector.
		"invalidates_layout": true,
		"faithful": {"ok": true, "reason": ""},
	}


## Write a keyframe's duration by lowering it to a time_value + re-deriving the cached
## duration_frames — the one place the two stay consistent.
static func _set_duration(kf, dur: int) -> void:
	kf.time_value = _Lowering.time_value_for_duration(dur)
	kf.duration_frames = _Lowering.duration_for_time_value(int(kf.time_value))


## The TYPED Duration edit (ADR-0087 dec. 9): the `duration` pseudo-field is the SAME
## sum-preserving boundary trade as the drag, expressed in duration units — the channel knows
## the cumulative start, so it delegates `boundary_end = start + new_duration` and maps the
## boundary before/after back to durations (undo replays through this same field). Unlike the
## per-motion drag, a typed value returns `relayout` (not `invalidates_layout`) so the host
## takes the full-refresh path and the cell re-seeds with the SNAPPED number — the camera
## human-units honest tell.
static func _apply_duration(data, field_ref: Dictionary, new_duration: int) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("PaletteChannel: no palette channel for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	if n < 0 or n >= ch.keyframes.size():
		push_error("PaletteChannel: duration index %d out of range" % n)
		return {}
	var start_n: int = 0
	for i in range(n):
		start_n += _Lowering.duration_for_time_value(int(ch.keyframes[i].time_value))
	var res := _apply_boundary(data, field_ref, start_n + new_duration)
	if res.is_empty():
		return res
	res["before_raw"] = int(res["before_raw"]) - start_n
	res["after_raw"] = int(res["after_raw"]) - start_n
	res.erase("invalidates_layout")
	res["relayout"] = true
	return res


## --- MOVE (ADR-0101 decisions 3-7) ------------------------------------------


## The gesture-scoped MOVE CONTEXT for this channel: the facts a plan needs that are too
## expensive to recompute per motion. Captured ONCE at grab (`EffectEditSession.begin_move`)
## and reused every motion — correct because every motion re-plans from the SAME pristine
## snapshot, so nothing it describes can go stale mid-gesture.
##
## `holds` is the FOLD-DERIVED hidden-spacer vector over the played window: the disable-
## equivalence verdict (`SpacerVerdicts`) AND the keyframe's own `enabled` bit (ctrl bit 7) — the same two-part test
## `EffectScoreTimeline.is_hidden_spacer` applies, because "which tiles are empty space" must
## mean the same thing to the painter and to the planner.
##
## There are no `manufacture_*` licences here any more (ADR-0101 decision 6, narrowed): where a
## run is EMPTY the padding is MINTED inert rather than copied from the keyframe at the
## insertion point, so there is nothing to measure. The probe that used to live here did a
## TRIAL INSERT and asked the whole-channel fold about it — reading, per grab, a lane the edit
## was about to invalidate. That was the root of decisions 6 and 7's open faults, and it
## existed only to police a spacer shape that never had to be used.
static func move_context(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return {}
	return {
		"holds": _hold_flags(data, field_ref, ch),
		"durations": _Lowering.durations(ch.keyframes),
		"free_slots": _Lowering.free_slots(ch),
	}


## Slide played span `n` by `delta` frames — the colour arm of ADR-0101 decision 3. The rule
## lives in `ColourMovePlan`; this resolves the channel, hands the planner the two arrays and
## the budget, and executes the returned splice with this kind's own keyframe copier.
##
## STRUCTURAL by construction (padding is inserted, an emptied hold run is deleted), so the
## choke point's undo is the pre-edit channel snapshot, not a scalar replay. Returns {} when
## refused (wedged) or clamped to a no-op, so nothing is recorded. `ctx` is the gesture-scoped
## context; an empty one is computed on the spot (the discrete verb / a test).
static func move_span(data, field_ref: Dictionary, delta: int, ctx: Dictionary = {}) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return {}
	var c: Dictionary = ctx if not ctx.is_empty() else move_context(data, field_ref)
	if c.is_empty():
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	var plan: Dictionary = _MovePlan.plan(c["durations"], c["holds"], n, delta,
		int(c["free_slots"]))
	if not plan.get("ok", false) or int(plan["delta"]) == 0:
		return {}
	var before: int = _start_of(ch, n)
	_MovePlan.apply(ch, plan,
		func(kf): return _dup_keyframe(kf),
		func(kf, dur): _set_duration(kf, dur),
		func(dur): return _new_identity_keyframe(dur))
	_reindex(ch)
	return {
		"before_raw": before,
		"after_raw": before + int(plan["delta"]),
		"delta": int(plan["delta"]),
		"granularity": int(plan["granularity"]),
		"cost": int(plan["cost"]),
		# The span's new raw index: the left run was re-encoded under it, so the address the
		# host re-selects on is the run's start plus however many keyframes now precede it.
		"event_index": int(plan["left"]["from"]) + plan["left"]["seq"].size(),
		# READ-LIVE (the subsystem rebuilds from the keyframes every frame), but the tiling
		# changed, so the host reprojects.
		"invalidates_sim": false,
		"invalidates_layout": true,
		"structural": true,
		"faithful": {"ok": true, "reason": ""},
	}


## The fold-derived hidden-spacer vector over the channel's PLAYED window (see move_context).
##
## Move's own minted padding satisfies this unchanged — it is an ENABLED Δ0 identity, so the
## verdict fold calls it a spacer and the `enabled` term is already true. That is the whole
## reason the pad is minted enabled: a planner that did not recognise its own padding as empty
## space made the very next grab ONE-WAY, and no carve-out was needed to avoid it.
static func _hold_flags(data, field_ref: Dictionary, ch) -> Array:
	var verdicts: Dictionary = _SpacerVerdicts.palette_verdicts(data.palette,
		String(field_ref.get("channel_name", "")), _Lowering.stream_offsets(data)).get(
		String(field_ref.get("context", "")), {})
	var out: Array = []
	for i in range(_Lowering.played_last(ch)):
		out.append(bool(verdicts.get(i, false)) and bool(ch.keyframes[i].enabled))
	return out


## The cumulative phase-local start frame of keyframe `n` — reported as the move's
## before/after so the result reads as "the span was here, now it is there".
static func _start_of(ch, n: int) -> int:
	var start: int = 0
	for i in range(mini(n, ch.keyframes.size())):
		start += _Lowering.duration_for_time_value(int(ch.keyframes[i].time_value))
	return start


## INSERT-WAYPOINT (ADR-0087): cut the span covering `field_ref.frame` (phase-local) in TIME,
## seeding the new keyframe as a DISABLED NULL TWEEN — never by inheriting the neighbour's Δ (a
## Δ-inherit doubles the tint for a current-source mode and erases it under a base-source
## neighbour; a disabled tween holds the prior keyframe's still-live ColorStack layer, so it is
## invisible in ANY mode). The cut lands at the STORABLE boundary nearest the clicked frame
## (ColorLowering.split_durations): sum-preserving (far edge pinned) whenever the 8-grid
## allows a clean split; a total with no clean split (an 8-frame span) drifts by the minimum
## one frame. Structural: the keyframe array grows, so undo is snapshot-based. Returns
## `{structural, event_index}` selecting the new keyframe (raw index).
static func insert_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("PaletteChannel: no channel to insert into for %s" % str(field_ref))
		return {}
	# THE CAP (ADR-0101 decision 8). A colour track is a FIXED 33-slot on-disk structure, and
	# this verb used to append past it with no check at all, leaving `EffectPaletteSaver` to
	# refuse the whole save afterwards — a failure deferred to the one moment it is most
	# expensive. Decision 4 makes the slot budget a first-class quantity, so the cap becomes a
	# precondition the verb enforces: RAISE, never truncate (the particle / camera rule).
	# A spacer_stub split adds TWO keyframes, an ordinary cut one.
	var wanted: int = 2 if bool(field_ref.get("spacer_stub", false)) else 1
	if _Lowering.free_slots(ch) < wanted:
		push_error("PaletteChannel: channel full (%d of %d slots used) — Add refused"
			% [int(ch.max_keyframe), _Lowering.NATIVE_KEYFRAME_SLOTS])
		return {}
	var frame: int = int(field_ref.get("frame", 0))
	var cover := _Lowering.covering(ch.keyframes, frame)
	# ADD-INTO-A-SPACER (ADR-0087 decs. 23-28): a spacer's only affordance splits its tile
	# into THREE — the spacer kept on either side, a fresh 1-frame disabled stub at the click.
	if bool(field_ref.get("spacer_stub", false)) and int(cover.get("index", -1)) >= 0:
		return _insert_spacer_stub(ch, int(cover["index"]), frame - int(cover["start"]))
	var new_index: int
	if int(cover.get("index", -1)) < 0:
		# No covering span (empty lane / past the tail): append a default 8-frame disabled tween.
		ch.keyframes.append(_new_disabled_keyframe(_Lowering.STEP))
		new_index = ch.keyframes.size() - 1
	else:
		var m: int = int(cover["index"])
		var kf_m = ch.keyframes[m]
		var dur_m: int = _Lowering.duration_for_time_value(int(kf_m.time_value))
		var split := _Lowering.split_durations(dur_m, frame - int(cover["start"]))
		_set_duration(kf_m, int(split["first"]))
		ch.keyframes.insert(m + 1, _new_disabled_keyframe(int(split["second"])))
		new_index = m + 1
	ch.max_keyframe += 1
	_reindex(ch)
	return {"structural": true, "event_index": new_index, "invalidates_sim": false}


## The 3-way spacer split (ADR-0087 decs. 23-28): replace the covering keyframe `m` with
## [before-spacer | 1-frame DISABLED stub | after-spacer]. The two sides are COPIES of the
## covering keyframe, so they keep the spacer's bytes (stay empty space); the middle is the
## fresh disabled null tween the author builds over. `offset` is the click's position INTO the
## covering tile. A side of length 0 (a click flush against an edge) is omitted. Selection lands
## on the stub. Structural (snapshot undo through the choke point).
static func _insert_spacer_stub(ch, m: int, offset: int) -> Dictionary:
	var kf_m = ch.keyframes[m]
	var dur_m: int = _Lowering.duration_for_time_value(int(kf_m.time_value))
	var parts := _Lowering.stub_split(dur_m, offset)
	var seq: Array = []
	if int(parts["before"]) > 0:
		var b = _dup_keyframe(kf_m)
		_set_duration(b, int(parts["before"]))
		seq.append(b)
	var stub_pos: int = seq.size()   # the stub's slot within the replacement sequence
	seq.append(_new_disabled_keyframe(int(parts["stub"])))
	if int(parts["after"]) > 0:
		var a = _dup_keyframe(kf_m)
		_set_duration(a, int(parts["after"]))
		seq.append(a)
	ch.keyframes.remove_at(m)
	for j in range(seq.size()):
		ch.keyframes.insert(m + j, seq[j])
	ch.max_keyframe += seq.size() - 1
	_reindex(ch)
	return {"structural": true, "event_index": m + stub_pos, "invalidates_sim": false}


## DELETE the addressed keyframe (raw `event_index`) — the inverse of insert-waypoint. Its
## length folds into the PREVIOUS neighbour (or the NEXT, when it is the first) so everything
## downstream stays pinned at its absolute frame. Deleting the sole keyframe empties the lane.
## Structural + snapshot undo. Returns `{structural, event_index}` selecting the neighbour.
static func delete_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("PaletteChannel: no channel to delete from for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	if n < 0 or n >= ch.keyframes.size():
		push_error("PaletteChannel: no keyframe at index %d to delete" % n)
		return {}
	var dur_n: int = _Lowering.duration_for_time_value(int(ch.keyframes[n].time_value))
	if ch.keyframes.size() > 1:
		# Fold the removed length into a neighbour so the far edge (downstream) stays pinned.
		var absorb: int = n - 1 if n > 0 else n + 1
		var neigh = ch.keyframes[absorb]
		_set_duration(neigh, _Lowering.duration_for_time_value(int(neigh.time_value)) + dur_n)
	ch.keyframes.remove_at(n)
	ch.max_keyframe = maxi(0, int(ch.max_keyframe) - 1)
	_reindex(ch)
	var neighbour: int = -1 if ch.keyframes.is_empty() else maxi(0, n - 1)
	return {"structural": true, "event_index": neighbour, "invalidates_sim": false}


## Deep-copy the channel's keyframe state — the pre-edit snapshot the choke point stashes for
## structural undo (the verbs mutate the live array in place, so the copy must be independent).
static func snapshot(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		return {}
	return {
		"context": field_ref.get("context", ""),
		"channel_name": field_ref.get("channel_name", ""),
		"keyframes": _dup_keyframes(ch.keyframes),
		"max_keyframe": int(ch.max_keyframe),
	}


## Restore a channel snapshot wholesale (the structural-undo inverse of insert/delete).
## DEEP-COPIES out of the snapshot so the snapshot stays PRISTINE across REPEATED restores —
## the boundary drag's restore-then-reapply re-plans every motion off one snapshot, and handing
## the live channel the snapshot's own array would let the second motion restore an
## already-mutated state (the ParticleTimelineChannel.restore precedent).
static func restore(data, snap: Dictionary) -> void:
	if data == null or data.palette == null or snap.is_empty():
		return
	var ch = data.palette.get_channel(snap.get("context", ""), snap.get("channel_name", ""))
	if ch == null:
		return
	ch.keyframes = _dup_keyframes(snap["keyframes"])
	ch.max_keyframe = int(snap["max_keyframe"])


## A fresh ENABLED IDENTITY no-op of `dur` frames — blend mode 0 with a ZERO delta, ctrl 0x80.
## The MOVE's padding (ADR-0101 decision 6, narrowed), and deliberately NOT
## `_new_disabled_keyframe`: the two are indistinguishable in the bytes, and the disabled shape
## is already spoken for — `insert_event` and `_insert_spacer_stub` both seed the author's
## born-disabled STUB with it. Hiding a disabled zero keyframe to hide padding would therefore
## have made every freshly-Added colour event vanish the moment it was deselected, which is the
## exact failure ADR-0087 dec. 27 exists to prevent. (Measured too: of the
## corpus's 287 disabled palette keyframes only 15 are zero-tint, so shipped data would barely
## have noticed — the studio's OWN Add verb was the population that mattered.)
##
## An enabled Δ0 is inert for the same reason the screen arm's pad is: it lowers to "current +
## 0", a per-frame visual no-op whatever it sits next to, so the fold calls it a spacer and
## `is_hidden_spacer` hides it with no carve-out at all. It is also the shape the score model
## already documents as the enabled-inert spacer, so nothing downstream had to learn about it.
static func _new_identity_keyframe(dur: int):
	var kf = _PaletteData.Keyframe.new()
	kf.rgb = Vector3i.ZERO
	kf.ctrl = 0x80
	kf.enabled = true
	kf.blend_mode = 0
	_set_duration(kf, dur)
	return kf


## A fresh DISABLED null tween of `dur` frames — no tint (rgb 0), ctrl bit-7 clear (enabled
## off), blend mode 0. Invisible by construction (it pushes no ColorStack layer). The author's
## born-disabled STUB (`insert_event` / `_insert_spacer_stub`); Move's padding is
## `_new_identity_keyframe` instead — see there for why they must not share a shape.
static func _new_disabled_keyframe(dur: int):
	var kf = _PaletteData.Keyframe.new()
	kf.rgb = Vector3i.ZERO
	kf.ctrl = 0
	kf.enabled = false
	kf.blend_mode = 0
	_set_duration(kf, dur)
	return kf


## Renumber the keyframes' cached `index` field after an insert/delete so it matches the slot.
static func _reindex(ch) -> void:
	for i in range(ch.keyframes.size()):
		ch.keyframes[i].index = i


static func _dup_keyframes(kfs: Array) -> Array:
	var out: Array = []
	for kf in kfs:
		out.append(_dup_keyframe(kf))
	return out


static func _dup_keyframe(kf):
	var n = _PaletteData.Keyframe.new()
	n.index = kf.index
	n.time_value = kf.time_value
	n.duration_frames = kf.duration_frames
	n.rgb = kf.rgb
	n.ctrl = kf.ctrl
	n.enabled = kf.enabled
	n.blend_mode = kf.blend_mode
	return n


static func _resolve_channel(data, field_ref: Dictionary):
	if data == null or data.palette == null:
		return null
	return data.palette.get_channel(
		field_ref.get("context", ""), field_ref.get("channel_name", ""))


## Non-destructive Faithful advisory (mirrors ScreenChannel): a byte-encoded field
## only lowers to E###.BIN if it fits its unsigned byte range.
static func _byte_verdict(field: String, raw: int) -> Dictionary:
	if raw < 0 or raw > 255:
		return {
			"ok": false,
			"reason": "%s = %d is outside the 0–255 byte encoding (Free-only)" % [field, raw],
		}
	return {"ok": true, "reason": ""}


## blend_mode occupies only ctrl bits 0-6; a value above 127 would clobber the
## enabled bit, so it is not faithfully encodable.
static func _blend_mode_verdict(mode: int) -> Dictionary:
	if mode < 0 or mode > 0x7F:
		return {
			"ok": false,
			"reason": "blend_mode = %d does not fit ctrl bits 0-6 (0–127)" % mode,
		}
	return {"ok": true, "reason": ""}


## Resolve the addressed keyframe: palette has a TWO-dimensional address —
## phase context AND channel_name (affected_units / caster / target) — unlike
## screen's single context.
static func _resolve_keyframe(data, field_ref: Dictionary):
	if data == null or data.palette == null:
		return null
	var ch = data.palette.get_channel(
		field_ref.get("context", ""), field_ref.get("channel_name", ""))
	if ch == null:
		return null
	return ch.get_keyframe(int(field_ref.get("event_index", -1)))
