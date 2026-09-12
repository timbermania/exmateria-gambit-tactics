extends RefCounted
## The pure conversion between the colour-lane AUTHORING model (absolute frame intervals) and
## its length-encoded STORAGE (ADR-0087) — the colour analogue of CameraLowering. PALETTE and
## SCREEN share this one module: both store the identical `time_value` encoding (same parser
## rule), and forked snap math is how the palette split bug happened.
##
## Each keyframe stores one `time_value` (s16); the runtime decodes it as
## `duration_frames = time_value × 8` (or 1 when time_value == 0), with cumulative starts (no
## stored end). So the author manipulates absolute `[start, end)` intervals and this module
## lowers a length back to the nearest on-disk `time_value` — which is why colour boundary
## drags SNAP to 8-frame steps and clamp to a minimum 1-frame tween (time_value 0), never a
## zero-width span. The `time_value` field is BOTH the length and the DDA ramp, so re-timing a
## boundary re-times the ramp (one knob). No class_name (ADR-0004).

## The on-disk length unit: one time_value step is 8 frames (the fast/slow DDA table base).
const STEP := 8

## The FIXED on-disk keyframe slot count per colour channel — the track stride proves it
## exactly: `0x04B4 − 0x03EC = 200 = 33×2 (time_values) + 33×3 (rgb) + 33 (ctrl) + 2
## (max_keyframe)`. Thirty-three slots, always present, mostly dead. Both savers carry their
## own mirror of this number for the writer's shape (`EffectPaletteSaver.MAX_PALETTE_KEYFRAMES`
## / `EffectScreenSaver.MAX_SCREEN_KEYFRAMES`); this is the copy the AUTHORING verbs enforce, so
## an over-insert is refused at the verb instead of discovered by the saver (ADR-0101 dec. 8).
const NATIVE_KEYFRAME_SLOTS := 33

const _EffectPhase = ExMateriaEffects.EffectPhase


## Decode one time_value to its played length — the parser's rule (time_value × 8, but a 0 is
## a 1-frame snap, never a 0-length span).
static func duration_for_time_value(tv: int) -> int:
	return tv * STEP if tv > 0 else 1


## Lower an authored duration to the nearest encodable time_value: round to 8-frame steps, and
## a ≤1-frame interval is time_value 0 (the 1-frame minimum tween).
static func time_value_for_duration(dur: int) -> int:
	if dur <= 1:
		return 0
	return maxi(0, roundi(float(dur) / float(STEP)))


## The faithful length an authored duration lands on after lowering — 1 (time_value 0) or a
## multiple of 8. The composition duration→time_value→duration.
static func snap_duration(dur: int) -> int:
	return duration_for_time_value(time_value_for_duration(dur))


## Is `dur` a length the storage can hold EXACTLY? Only `1` (time_value 0) and the multiples of
## 8 exist; a 2..7 or 9..15 has no encoding, and writing one silently re-snaps.
static func is_faithful(dur: int) -> bool:
	return dur == 1 or (dur > 0 and dur % STEP == 0)


## The BOUNDARY-TRADE chooser (ADR-0087 dec. 30, ADR-0101 decision 1): split `total`
## into two faithful lengths that sum to it **EXACTLY**, landing the boundary as near `desired`
## as the encoding allows. Returns `{first, second}`.
##
## A tie goes to the LONGER first span, matching `time_value_for_duration`'s round-half-up — so
## the typed Duration row and the drag agree, and a typed 20 on a 16+16 pair still reads 24 the
## way it always has. Only the far edge changes here; the quantization convention does not.
##
## This is the trade's answer to the far edge — the caller must never compute a neighbour's
## share as `total − first` and hand it to a setter, because that residual is faithful only by
## luck and re-snapping it slides the far edge (±1 frame in ~13% of drag positions, always where
## a span lands on the 1-frame minimum — the reported "both sides move").
##
## Unlike `split_durations`, which cuts ONE stored span and must therefore sometimes drift (8
## has no faithful pair), a trade's `total` is by construction the **sum of two faithful
## lengths** — so it is its own witness and an exact pair ALWAYS exists. Positions with no exact
## pair are simply not offered: the boundary snaps to the nearest one that is, and the handle
## visibly skips the rest. That makes colour trades strictly 8-grained on a multiple-of-8 total,
## which is ratified — sub-8 positioning is the Move gesture's job, not the trade's.
static func trade_durations(total: int, desired: int) -> Dictionary:
	var best: int = -1
	var best_dist: int = 0x7FFFFFFF
	var cand: int = 1
	while cand < total:
		if is_faithful(total - cand):
			var dist: int = absi(cand - desired)
			if dist <= best_dist:     # `<=` keeps the LAST (longest) on a tie — round-half-up
				best_dist = dist
				best = cand
		cand = STEP if cand == 1 else cand + STEP
	if best < 0:
		# Unreachable from real data (see above); never write a zero-width span.
		best = maxi(1, mini(snap_duration(desired), total - 1))
	return {"first": best, "second": total - best}


## The INSERT-WAYPOINT split chooser: cut a `total`-frame span at `desired` frames in,
## returning `{first, second}` — BOTH faithful lengths (1 or a multiple of 8). Zero far-edge
## drift (first+second == total) wins outright; among equal-drift pairs the cut lands nearest
## the clicked frame (min |first − desired|), ties to the earlier boundary. Some totals have
## no clean split (8: no faithful pair sums to it) — those drift by the minimum (one frame),
## never silently more.
static func split_durations(total: int, desired: int) -> Dictionary:
	var best := {"first": 1, "second": 1}
	var best_drift: int = 0x7FFFFFFF
	var best_dist: int = 0x7FFFFFFF
	var d1: int = 1
	while d1 <= maxi(1, total):
		var d2: int = _nearest_faithful(total - d1)
		var drift: int = absi(d1 + d2 - total)
		var dist: int = absi(d1 - desired)
		if drift < best_drift or (drift == best_drift and dist < best_dist):
			best = {"first": d1, "second": d2}
			best_drift = drift
			best_dist = dist
		d1 = STEP if d1 == 1 else d1 + STEP
	return best


## The ADD-INTO-A-SPACER split (ADR-0087 decs. 23-28): a spacer's only affordance is
## right-click → Add, which cuts its `total`-frame tile into THREE — a `before` spacer, a fresh
## 1-frame disabled STUB at the click, and an `after` spacer — so you build a new event INTO the
## empty space (the emitter-gap model) instead of converting the spacer. The stub is ALWAYS one
## frame (time_value 0, the storable 1-frame minimum). `before` is the largest faithful length
## (0, 1, or a multiple of 8) at-or-before the click, so the stub lands at the ÷8 boundary just
## below `desired` (the inherent grid residual the memory notes); `after` is the faithful length
## nearest the leftover, or 0 when the click is flush against an edge. A `before`/`after` of 0
## means that side has no spacer (the insert emits only the two remaining keyframes).
static func stub_split(total: int, desired: int) -> Dictionary:
	if total <= 1:
		return {"before": 0, "stub": 1, "after": 0}
	var before: int = _faithful_le_or_zero(mini(desired, total - 1))
	var remaining: int = total - before - 1
	var after: int = 0 if remaining <= 0 else _nearest_faithful(remaining)
	return {"before": before, "stub": 1, "after": after}


## The largest faithful length (0, 1, or a positive multiple of 8) not exceeding `hi`. Unlike
## every other chooser here this can return 0 (no spacer on that side when the click is flush).
static func _faithful_le_or_zero(hi: int) -> int:
	if hi <= 0:
		return 0
	if hi < STEP:
		return 1
	return (hi / STEP) * STEP


## The cumulative-duration window search shared by the palette and screen verbs: the keyframe
## whose `[start, start+dur)` tile contains `frame`, as {index, start}; index −1 when nothing
## covers it (empty lane or past the tail — start is then the lane's total length). Duck-typed
## on `.time_value`, so any length-encoded keyframe array fits.
static func covering(keyframes: Array, frame: int) -> Dictionary:
	var start: int = 0
	for i in range(keyframes.size()):
		var dur: int = duration_for_time_value(int(keyframes[i].time_value))
		if frame >= start and frame < start + dur:
			return {"index": i, "start": start}
		start += dur
	return {"index": -1, "start": start}


## The faithful length (1 or a positive multiple of 8) nearest `frames`; ties prefer shorter.
static func _nearest_faithful(frames: int) -> int:
	if frames <= 1:
		return 1
	var lo: int = (frames / STEP) * STEP
	var best: int = 1
	for cand in [1, lo, lo + STEP]:
		if cand >= 1 and absi(cand - frames) < absi(best - frames):
			best = cand
	return best


## The PLAYED window of a length-encoded colour channel: `[0, played_last)`. Mirrors
## `PaletteSubsystem._each_keyframe` and `ScreenSubsystem._push_phase_ops` exactly — the PSX
## stepper breaks at `max_keyframe − 1`, so the trailing slots are terminators/padding it never
## touches. Walking past it is what drew phantom tint spans (ADR-0071). Duck-typed on the
## channel's `keyframes` + `max_keyframe`.
static func played_last(ch) -> int:
	if ch == null:
		return 0
	return mini(ch.keyframes.size(), maxi(0, int(ch.max_keyframe) - 1))


## Free keyframe slots on a colour channel: `33 − max_keyframe`. `max_keyframe` IS the used
## count (played spans are `max_keyframe − 1`), and the live `keyframes` array is the full
## 33-slot storage, so the array's size is never the budget.
static func free_slots(ch) -> int:
	if ch == null:
		return 0
	return NATIVE_KEYFRAME_SLOTS - int(ch.max_keyframe)


## Per-keyframe played lengths, in index order — the array every length-encoded verb reasons
## over. Duck-typed on `.time_value` like `covering`.
static func durations(keyframes: Array) -> Array:
	var out: Array = []
	for kf in keyframes:
		out.append(duration_for_time_value(int(kf.time_value)))
	return out


## The absolute offsets at which each phase's colour keyframes are concatenated into ONE
## cross-phase stream — the co-ordinates `SpacerVerdicts` folds in (the PSX has no phase
## concept). Mirrors `EffectScoreModel.phase_offset`, which stays the score's source of truth;
## duplicated here (three lines) so the write-side channels can fold a verdict without
## preloading the score model, which preloads them back.
static func stream_offsets(effect_data) -> Dictionary:
	var out: Dictionary = {}
	var tl = effect_data.timeline if effect_data != null else null
	var p1: int = int(tl.phase1_duration) if tl != null else 0
	var delay: int = int(tl.phase2_delay) if tl != null else 0
	for phase in _EffectPhase.ALL:
		match phase:
			_EffectPhase.PHASE_FOR_EACH:
				out[phase] = p1
			_EffectPhase.PHASE2:
				out[phase] = p1 + delay
			_:
				out[phase] = 0
	return out
