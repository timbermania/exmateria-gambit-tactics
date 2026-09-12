class_name ScreenChannel
extends RefCounted
## Write-side channel archetype (the deep module, beginning here) for the SCREEN
## backdrop channel (#248). It owns the raw↔value encoding for a screen tween:
## given a raw-byte edit, it writes the storage field on the live keyframe,
## recomputes the derived `value` cache, and declares whether the edit invalidates
## the sim. Screen colour is READ-LIVE — `ScreenSubsystem` rebuilds the ColorStack
## by-reference every frame — so a colour edit reaches the preview in place with no
## re-seek (`invalidates_sim = false`). Channels supply encoders, not mutation
## logic; the single choke point is `EffectEditSession.apply_edit` (#255).

const ScreenDataClass = ExMateriaEffects.ScreenData
const _Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const _SpacerVerdicts = preload("res://src/effects/studio/SpacerVerdicts.gd")
const _MovePlan = preload("res://src/effects/studio/ColourMovePlan.gd")

# Author-facing / on-disk field name → the Keyframe storage attr holding its raw byte.
# The Gradient kind sets the two backdrop stops independently: start_* = the TOP stop,
# end_* = the BOTTOM stop (#255 scope B). Blend uses only start_* (its shared param).
const _RAW_FIELD := {
	"start_r": "start_r_raw",
	"start_g": "start_g_raw",
	"start_b": "start_b_raw",
	"end_r": "end_r_raw",
	"end_g": "end_g_raw",
	"end_b": "end_b_raw",
}


## Write one raw byte for the screen keyframe named by `field_ref`, recompute the
## derived colour cache, and return the snapshot the choke point records for undo.
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
		push_error("ScreenChannel: no screen keyframe for %s" % str(field_ref))
		return {}
	var field: String = field_ref.get("field", "")
	if field == "kind":
		return _apply_kind(kf, int(new_raw))
	if field == "enabled":
		return _apply_enabled(kf, int(new_raw))
	var res: Dictionary
	if field == "blend_mode":
		res = _apply_blend_mode(kf, int(new_raw))
	elif _RAW_FIELD.has(field):
		var storage: String = _RAW_FIELD[field]
		var before_raw = kf.get(storage)
		kf.set(storage, int(new_raw))
		_recompute_value_cache(kf)
		res = {
			"before_raw": before_raw,
			"after_raw": int(new_raw),
			"invalidates_sim": false,
			"faithful": _faithful_verdict(field, int(new_raw)),
		}
	else:
		push_error("ScreenChannel: unknown screen field '%s'" % field)
		return {}
	# RESTYLE (ADR-0087 decs. 17-22, decision 4): every VALUE edit (colour bytes,
	# blend mode) flags layout unconditionally — the spacer verdict is contextual
	# (disable-equivalence over the whole stream, both endpoints), so an edit HERE can
	# flip ANY keyframe's verdict. The host rebuild recomputes verdicts lane-wide; the
	# inspector is not re-derived (the cell being typed into keeps focus). Subsumes the
	# third amendment's is_disabled-crossing detection. (Kind and Enabled are structural
	# above: they already reproject.)
	res["invalidates_layout"] = true
	return res


## Flip the screen tween's KIND (Blend/Gradient variant) — a STRUCTURAL edit: it
## reshapes the field set, so the caller must re-project (unlike a value edit). The kind
## is ctrl bit-7 (BLEND = set), so this is a read-modify-write that preserves the low
## bits, plus the derived `mode` cache. Read-live (invalidates_sim=false) and always
## Faithful (a bit flip is always encodable). `before/after_raw` carry the mode enum.
static func _apply_kind(kf, new_kind: int) -> Dictionary:
	var before: int = int(kf.mode)
	var kind: int = ScreenDataClass.ScreenMode.BLEND if new_kind == ScreenDataClass.ScreenMode.BLEND \
		else ScreenDataClass.ScreenMode.GRADIENT
	kf.mode = kind
	if kind == ScreenDataClass.ScreenMode.BLEND:
		kf.ctrl = (int(kf.ctrl) & 0x7F) | 0x80
	else:
		kf.ctrl = int(kf.ctrl) & 0x7F
	return {
		"before_raw": before,
		"after_raw": kind,
		"invalidates_sim": false,
		"structural": true,
		"faithful": {"ok": true, "reason": ""},
	}


## Write the Blend mode (ADR-0087 dec. 13) — the ctrl byte shares kind (bit-7) and mode
## (low bits), so this is a read-modify-write preserving the kind, mirroring palette's
## enable/mode split. Read-live; `before/after_raw` carry the mode code (0-10).
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


## blend_mode occupies only ctrl bits 0-6; a value above 127 would clobber the kind bit, so
## it is not faithfully encodable (mirrors PaletteChannel's verdict for the enabled bit).
static func _blend_mode_verdict(mode: int) -> Dictionary:
	if mode < 0 or mode > 0x7F:
		return {
			"ok": false,
			"reason": "blend_mode = %d does not fit ctrl bits 0-6 (0–127)" % mode,
		}
	return {"ok": true, "reason": ""}


## The DERIVED disabled state (ADR-0087 dec. 11): screen has no enable bit, so
## "disabled" is identity-no-op BYTES (Blend mode 0, zero param — invisible by construction:
## ColorRecipe lowers it to current + 0) OR a stash present (the keyframe was toggled off this
## session). The live raw bytes always equal what plays and what saves.
static func is_disabled(kf) -> bool:
	if not kf.disabled_stash.is_empty():
		return true
	return int(kf.mode) == ScreenDataClass.ScreenMode.BLEND and int(kf.blend_mode) == 0 \
		and int(kf.start_r_raw) == 0 and int(kf.start_g_raw) == 0 and int(kf.start_b_raw) == 0


## Did a HUMAN deliberately turn this keyframe off (ADR-0087 decs. 23-28)? Screen has no
## enable bit, so the tell is the disabled_stash: the Enabled toggle byte-swaps to the identity
## no-op and stashes the real bytes. A COLD identity no-op (no stash) is NOT author-disabled —
## it is an intrinsic byte spacer, which the fifth amendment renders as invisible empty space
## rather than a "muted, not gone" disabled event. This is the `enabled` the score model carries.
static func is_author_disabled(kf) -> bool:
	return not kf.disabled_stash.is_empty()


## The harmonized Enabled toggle (ADR-0087 dec. 11) — a BYTE-SWAP, not a bit:
##   * disable: stash the prior byte fields on the keyframe object (authoring-only, never
##     serialized) and overwrite it to the identity no-op Blend — a Gradient disables to a
##     Blend no-op too (a disabled keyframe always presents the Blend variant). The tween's
##     length (time_value) is untouched: a disabled tween keeps its tile.
##   * enable: restore the stash losslessly and clear it. A COLD no-op (no stash) has nothing
##     to restore — enabling changes NO bytes and reports `no_edit` so the choke point records
##     no undo entry ("author a tint", never a fabricated restore).
## Self-inverse through the scalar undo replay: undo of a disable replays enabled=1 while the
## stash is still present; undo of an enable replays enabled=0, re-stashing the same bytes.
## Structural (the field set / lane restyle) + read-live (screen refolds in place).
static func _apply_enabled(kf, new_val: int) -> Dictionary:
	var before: int = 0 if is_disabled(kf) else 1
	var on: bool = new_val != 0
	if on:
		if kf.disabled_stash.is_empty():
			return {"before_raw": before, "after_raw": before, "no_edit": true,
				"invalidates_sim": false, "faithful": {"ok": true, "reason": ""}}
		var s: Dictionary = kf.disabled_stash
		kf.mode = int(s["mode"])
		kf.blend_mode = int(s["blend_mode"])
		kf.ctrl = int(s["ctrl"])
		kf.start_r_raw = int(s["start_r_raw"])
		kf.start_g_raw = int(s["start_g_raw"])
		kf.start_b_raw = int(s["start_b_raw"])
		kf.end_r_raw = int(s["end_r_raw"])
		kf.end_g_raw = int(s["end_g_raw"])
		kf.end_b_raw = int(s["end_b_raw"])
		kf.disabled_stash = {}
	else:
		kf.disabled_stash = {
			"mode": int(kf.mode), "blend_mode": int(kf.blend_mode), "ctrl": int(kf.ctrl),
			"start_r_raw": int(kf.start_r_raw), "start_g_raw": int(kf.start_g_raw),
			"start_b_raw": int(kf.start_b_raw), "end_r_raw": int(kf.end_r_raw),
			"end_g_raw": int(kf.end_g_raw), "end_b_raw": int(kf.end_b_raw),
		}
		kf.mode = ScreenDataClass.ScreenMode.BLEND
		kf.ctrl = 0x80
		kf.blend_mode = 0
		kf.start_r_raw = 0
		kf.start_g_raw = 0
		kf.start_b_raw = 0
		kf.end_r_raw = 0
		kf.end_g_raw = 0
		kf.end_b_raw = 0
	_recompute_value_cache(kf)
	return {
		"before_raw": before,
		"after_raw": 1 if on else 0,
		"invalidates_sim": false,
		"structural": true,
		"faithful": {"ok": true, "reason": ""},
	}


## The BOUNDARY-DRAG edit (ADR-0087, screen lane): re-time a screen tween by dragging the
## shared edge between it (array keyframe N) and its lane-neighbour (N+1). Screen is
## length-encoded like palette (cumulative starts, no stored end), so moving one absolute
## boundary is a SUM-PRESERVING trade — span N's duration becomes `new_local_end − start_N`
## (snapped to an 8-frame step, clamped so the neighbour keeps ≥ 1 frame) and the neighbour
## absorbs the difference, so their FAR edge (and everything downstream) stays PINNED.
## `new_raw` is the desired phase-local end frame; `before_raw` the pristine boundary so the
## scalar undo/coalesce restore it exactly. Read-live (invalidates_sim=false) — the screen
## rebuilds its ColorStack per frame. Variant-agnostic: the trade re-times Blend and Gradient
## tweens alike (time_value is both length and ramp — the accepted one-knob trade). The lane
## TAIL (no keyframe N+1) has nothing to pin, so it simply extends span N.
static func _apply_boundary(data, field_ref: Dictionary, new_local_end: int) -> Dictionary:
	if data == null or data.screen == null:
		return {}
	var ch = data.screen.get_channel(field_ref.get("context", ""))
	if ch == null:
		push_error("ScreenChannel: no screen channel for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	if n < 0 or n >= ch.keyframes.size():
		push_error("ScreenChannel: boundary index %d out of range" % n)
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
		push_error("ScreenChannel: no screen channel for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	if n < 0 or n >= ch.keyframes.size():
		push_error("ScreenChannel: duration index %d out of range" % n)
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
## equivalence verdict (`SpacerVerdicts`) AND `is_author_disabled` (screen has no enable bit — the tell is the stash) — the same two-part test
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
static func _hold_flags(data, field_ref: Dictionary, ch) -> Array:
	var verdicts: Dictionary = _SpacerVerdicts.screen_verdicts(data.screen, _Lowering.stream_offsets(data)).get(
		String(field_ref.get("context", "")), {})
	var out: Array = []
	for i in range(_Lowering.played_last(ch)):
		out.append(bool(verdicts.get(i, false)) and (not is_author_disabled(ch.keyframes[i])))
	return out


## The cumulative phase-local start frame of keyframe `n` — reported as the move's
## before/after so the result reads as "the span was here, now it is there".
static func _start_of(ch, n: int) -> int:
	var start: int = 0
	for i in range(mini(n, ch.keyframes.size())):
		start += _Lowering.duration_for_time_value(int(ch.keyframes[i].time_value))
	return start


## INSERT-WAYPOINT (ADR-0087, screen lane): cut the span covering `field_ref.frame`
## (phase-local) in TIME, seeding the new keyframe as an ACTIVE IDENTITY no-op tween — screen
## has no `enabled` bit, so the null-tween seed is Blend mode 0 with a ZERO param (ctrl 0x80,
## start RGB 0): ColorRecipe lowers that to `affine(ONE, ZERO)` = current + 0, a per-frame
## visual no-op over ANY covering variant. Never seed by copying the covering keyframe —
## copying a Blend's param pushes its op a second time (doubles the tint, the palette
## Δ-inherit trap) and copying a Gradient absolute-sets. The cut lands at the STORABLE
## boundary nearest the clicked frame (ColorLowering.split_durations): sum-preserving (far
## edge pinned) whenever the 8-grid allows a clean split; a total with no clean split (an
## 8-frame span) drifts by the minimum one frame. Structural: the keyframe array grows, so
## undo is snapshot-based. Returns `{structural, event_index}` selecting the new keyframe
## (raw index).
static func insert_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("ScreenChannel: no channel to insert into for %s" % str(field_ref))
		return {}
	# THE CAP (ADR-0101 decision 8) — see PaletteChannel.insert_event: a colour track is a
	# FIXED 33-slot structure and this verb used to append past it, leaving EffectScreenSaver to
	# refuse the whole save later. Raise at the verb, never truncate. A spacer_stub split adds
	# TWO keyframes, an ordinary cut one.
	var wanted: int = 2 if bool(field_ref.get("spacer_stub", false)) else 1
	if _Lowering.free_slots(ch) < wanted:
		push_error("ScreenChannel: channel full (%d of %d slots used) — Add refused"
			% [int(ch.max_keyframe), _Lowering.NATIVE_KEYFRAME_SLOTS])
		return {}
	var frame: int = int(field_ref.get("frame", 0))
	var cover := _Lowering.covering(ch.keyframes, frame)
	# ADD-INTO-A-SPACER (ADR-0087 decs. 23-28): a spacer's only affordance splits its tile
	# into THREE — the spacer kept on either side, a fresh 1-frame born-disabled stub at the click.
	if bool(field_ref.get("spacer_stub", false)) and int(cover.get("index", -1)) >= 0:
		return _insert_spacer_stub(ch, int(cover["index"]), frame - int(cover["start"]))
	var new_index: int
	if int(cover.get("index", -1)) < 0:
		# No covering span (empty lane / past the tail): append a default 8-frame no-op tween.
		ch.keyframes.append(_new_identity_keyframe(_Lowering.STEP))
		new_index = ch.keyframes.size() - 1
	else:
		var m: int = int(cover["index"])
		var kf_m = ch.keyframes[m]
		var dur_m: int = _Lowering.duration_for_time_value(int(kf_m.time_value))
		var split := _Lowering.split_durations(dur_m, frame - int(cover["start"]))
		_set_duration(kf_m, int(split["first"]))
		ch.keyframes.insert(m + 1, _new_identity_keyframe(int(split["second"])))
		new_index = m + 1
	ch.max_keyframe += 1
	_reindex(ch)
	return {"structural": true, "event_index": new_index, "invalidates_sim": false}


## The 3-way spacer split (ADR-0087 decs. 23-28): replace the covering keyframe `m` with
## [before-spacer | 1-frame BORN-DISABLED stub | after-spacer]. The two sides are COPIES of the
## covering keyframe (they keep the spacer's bytes — stay empty space); the middle is born
## disabled (an identity no-op whose disabled_stash is set) so it draws + hatches even after
## deselect. `offset` is the click's position INTO the covering tile; a 0-length side is omitted.
## Selection lands on the stub. Structural (snapshot undo through the choke point).
static func _insert_spacer_stub(ch, m: int, offset: int) -> Dictionary:
	var kf_m = ch.keyframes[m]
	var dur_m: int = _Lowering.duration_for_time_value(int(kf_m.time_value))
	var parts := _Lowering.stub_split(dur_m, offset)
	var seq: Array = []
	if int(parts["before"]) > 0:
		var b = _dup_keyframe(kf_m)
		_set_duration(b, int(parts["before"]))
		seq.append(b)
	var stub_pos: int = seq.size()
	seq.append(_new_disabled_stub_keyframe(int(parts["stub"])))
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


## A fresh BORN-DISABLED stub of `dur` frames (ADR-0087 decs. 23-28): an identity no-op whose
## disabled_stash is set to those identity bytes, so is_author_disabled reports true and the score
## draws it hatched (muted, not gone) even when it is not selected. Enabling it (the inspector's
## Enabled row) restores the stash and clears it, leaving an identity spacer the author colours in.
static func _new_disabled_stub_keyframe(dur: int):
	var kf = _new_identity_keyframe(dur)
	kf.disabled_stash = {
		"mode": int(kf.mode), "blend_mode": int(kf.blend_mode), "ctrl": int(kf.ctrl),
		"start_r_raw": int(kf.start_r_raw), "start_g_raw": int(kf.start_g_raw),
		"start_b_raw": int(kf.start_b_raw), "end_r_raw": int(kf.end_r_raw),
		"end_g_raw": int(kf.end_g_raw), "end_b_raw": int(kf.end_b_raw),
	}
	return kf


## DELETE the addressed keyframe (raw `event_index`) — the inverse of insert-waypoint. Its
## length folds into the PREVIOUS neighbour (or the NEXT, when it is the first) so everything
## downstream stays pinned at its absolute frame. Deleting the sole keyframe empties the lane.
## Structural + snapshot undo. Returns `{structural, event_index}` selecting the neighbour.
static func delete_event(data, field_ref: Dictionary) -> Dictionary:
	var ch = _resolve_channel(data, field_ref)
	if ch == null:
		push_error("ScreenChannel: no channel to delete from for %s" % str(field_ref))
		return {}
	var n: int = int(field_ref.get("event_index", -1))
	if n < 0 or n >= ch.keyframes.size():
		push_error("ScreenChannel: no keyframe at index %d to delete" % n)
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
		"keyframes": _dup_keyframes(ch.keyframes),
		"max_keyframe": int(ch.max_keyframe),
	}


## Restore a channel snapshot wholesale (the structural-undo inverse of insert/delete).
static func restore(data, snap: Dictionary) -> void:
	if data == null or data.screen == null or snap.is_empty():
		return
	var ch = data.screen.get_channel(snap.get("context", ""))
	if ch == null:
		return
	# DEEP-COPY out of the snapshot so it stays PRISTINE across REPEATED restores — the
	# boundary drag's restore-then-reapply re-plans every motion off one snapshot.
	ch.keyframes = _dup_keyframes(snap["keyframes"])
	ch.max_keyframe = int(snap["max_keyframe"])


## A fresh ACTIVE identity no-op tween of `dur` frames — Blend mode 0, zero param (current +
## 0). All raw bytes zeroed so the writer serializes a clean keyframe.
static func _new_identity_keyframe(dur: int):
	var kf = ScreenDataClass.Keyframe.new()
	kf.mode = ScreenDataClass.ScreenMode.BLEND
	kf.ctrl = 0x80
	kf.blend_mode = 0
	kf.start_r_raw = 0
	kf.start_g_raw = 0
	kf.start_b_raw = 0
	kf.end_r_raw = 0
	kf.end_g_raw = 0
	kf.end_b_raw = 0
	_recompute_value_cache(kf)
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
	var n = ScreenDataClass.Keyframe.new()
	n.index = kf.index
	n.time_value = kf.time_value
	n.duration_frames = kf.duration_frames
	n.mode = kf.mode
	n.blend_mode = kf.blend_mode
	n.ctrl = kf.ctrl
	n.start_r_raw = kf.start_r_raw
	n.start_g_raw = kf.start_g_raw
	n.start_b_raw = kf.start_b_raw
	n.end_r_raw = kf.end_r_raw
	n.end_g_raw = kf.end_g_raw
	n.end_b_raw = kf.end_b_raw
	n.start_color = kf.start_color
	n.end_color = kf.end_color
	n.disabled_stash = kf.disabled_stash.duplicate()   # the stash rides structural snapshots
	return n


## Resolve the addressed channel: screen has a ONE-dimensional address — just the phase
## context (single implicit channel), unlike palette's context + channel_name.
static func _resolve_channel(data, field_ref: Dictionary):
	if data == null or data.screen == null:
		return null
	return data.screen.get_channel(field_ref.get("context", ""))


## Non-destructive Faithful advisory (#255): Free always accepts the write, but a
## colour component only lowers to E###.BIN if it fits the unsigned byte encoding.
static func _faithful_verdict(field: String, raw: int) -> Dictionary:
	if raw < 0 or raw > 255:
		return {
			"ok": false,
			"reason": "%s = %d is outside the 0–255 byte encoding (Free-only)" % [field, raw],
		}
	return {"ok": true, "reason": ""}


static func _resolve_keyframe(data, field_ref: Dictionary):
	if data == null or data.screen == null:
		return null
	var ch = data.screen.get_channel(field_ref.get("context", ""))
	if ch == null:
		return null
	return ch.get_keyframe(int(field_ref.get("event_index", -1)))


## Keep BOTH decoded stop colours in sync with the raw bytes (raw/255, the PSX
## unsigned-byte → normalized-colour encoding — mirrors ScreenData.Keyframe). start_color
## is the TOP stop, end_color the BOTTOM stop (independent Gradient endpoints, #255 scope B).
static func _recompute_value_cache(kf) -> void:
	kf.start_color = Color(
		kf.start_r_raw / 255.0,
		kf.start_g_raw / 255.0,
		kf.start_b_raw / 255.0,
		1.0
	)
	kf.end_color = Color(
		kf.end_r_raw / 255.0,
		kf.end_g_raw / 255.0,
		kf.end_b_raw / 255.0,
		1.0
	)
