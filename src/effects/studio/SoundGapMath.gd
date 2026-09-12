extends RefCounted
## The ADR-0085 "stay-local" gap arithmetic behind fire-drag — a pure unit that turns
## "move trigger N by K frames" into the `duration_frames` edits that move ONLY N.
##
## A sound keyframe's `duration_frames` is the GAP to the NEXT trigger (NOT a length,
## NOT a position — see EffectScoreModel._sound_spans), so a trigger's fire frame is
##
##     fire[N] = phase_offset + Σ duration_frames[0 .. N-1]
##
## To slide N without dragging N+1 (or anything after it), the RIGHT gap dur[N]
## absorbs the OPPOSITE change (ceiling = fire[N+1], the adjacent next keyframe), which
## keeps every prefix sum from N+1 onward constant; the left prefix carries the move.
##
## **Skip-aware (BUG #3).** A skip keyframe (`sound_id < 2`) fires no sound — it is an
## invisible wall, not a trigger to floor on. So the left floor is the previous AUDIBLE
## trigger `fire[prev]` (sound_id >= 2), reached by consuming the intervening SKIP gaps
## NEAREST-first. With no audible trigger to the left, the floor is the phase offset
## (consume every prior gap). Rightward stays single-gap against the adjacent ceiling
## (dragging past a right-side skip is deferred — YAGNI, the bug is strictly leftward).
##
## **Return shape.** `{ "edits": { kf_index: new_dur }, "applied_delta": int }` —
## ABSOLUTE new durations over the FULL governed window `[lo .. index]`, plus the
## CLAMPED move actually achieved. The module owns the clamp and reports it, so the
## caller never reverse-engineers the achieved move (that recovery breaks the moment
## consumption spills past one gap). Emitting the whole window (unchanged gaps at their
## baseline value) lets a baseline-cumulative caller overwrite the live durs back to the
## exact baseline-relative distribution every motion → byte-exact reversible.
##
## Pure function of (keyframes, index, delta): read-only over the keyframes it is
## handed, it returns edits and does not apply them (the choke point
## EffectEditSession.apply_compound does). No class_name (ADR-0004).

const EffectScoreModel = preload("res://src/effects/studio/EffectScoreModel.gd")


## Move trigger `index` by `delta` frames, stay-local and skip-aware. Returns
## `{ "edits": { kf_index: new_dur, ... }, "applied_delta": int }` — the governed
## window at ABSOLUTE new durations plus the clamped achieved move. A valid draggable index
## ALWAYS emits the full baseline window (even when the net move clamps to 0 — then the window
## is the untouched baseline, whose re-application RESTORES the origin). Empty edits +
## applied_delta 0 ONLY when the move is structurally impossible: index <= 0 (the first
## trigger's fire IS the phase offset — no prior gap) or index out of range.
static func stay_local_edits(keyframes: Array, index: int, delta: int) -> Dictionary:
	var n: int = keyframes.size()
	if index <= 0 or index >= n:
		return {"edits": {}, "applied_delta": 0}

	var dur: Array = []
	for kf in keyframes:
		dur.append(int(kf.get("duration_frames", 0)))

	# Left floor = the previous AUDIBLE trigger; only skips to the left → the phase offset.
	var lo: int = 0
	for j in range(index - 1, -1, -1):
		if EffectScoreModel.sound_id_fires(int(keyframes[j].get("sound_id", 0))):
			lo = j
			break

	var left_capacity: int = 0          # max leftward move: floor = fire[lo] / phase offset
	for i in range(lo, index):
		left_capacity += dur[i]
	var right_capacity: int = dur[index]  # max rightward move: ceiling = fire[index+1]
	var applied: int = clampi(delta, -left_capacity, right_capacity)
	# NOTE: no early-out when `applied == 0`. The whole window is ALWAYS emitted (at applied 0
	# it is the untouched baseline distribution) so a baseline-cumulative caller overwrites the
	# live gaps back to the exact baseline every motion — the byte-exact-reversibility contract.
	# Returning empty here was the drag bug: after a non-zero move, a return-to-origin (delta 0)
	# emitted nothing, so the caller left the trigger stranded one frame off its start.

	var edits: Dictionary = {}
	for i in range(lo, index + 1):
		edits[i] = dur[i]
	edits[index] = dur[index] - applied    # right gap pins fire[index+1..]
	if applied > 0:
		edits[index - 1] = dur[index - 1] + applied    # later: grow the nearest left gap
	else:
		var rem: int = -applied                        # earlier: remove nearest-first
		for i in range(index - 1, lo - 1, -1):
			var take: int = mini(rem, dur[i])
			edits[i] = dur[i] - take
			rem -= take
			if rem == 0:
				break
	return {"edits": edits, "applied_delta": applied}
