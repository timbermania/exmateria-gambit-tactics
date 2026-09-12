extends Node
## TDD guard for SoundGapMath — the pure "stay-local" gap arithmetic behind the
## ADR-0085 fire-drag. A sound keyframe's `duration_frames` is the GAP to the NEXT
## trigger, so a trigger's fire frame is offset + Σ prior gaps. To move trigger N
## later by K frames WITHOUT moving N+1 (or anything after), you trade gaps: the
## RIGHT gap dur[N] absorbs the opposite change (pinning fire[N+1..]) and the LEFT
## prefix carries the move. Skip-aware: the left floor is the previous AUDIBLE
## trigger (sound_id >= 2), reached by consuming the intervening SKIP gaps
## nearest-first. The unit returns `{ "edits": { kf_index: new_dur }, "applied_delta" }`
## — ABSOLUTE new durations over the full governed window, plus the clamped move it
## actually achieved (so the caller never reverse-engineers the clamp). Baseline-
## cumulative: pure function of (baseline, index, delta), reversible when the caller
## feeds a fixed drag-start baseline + a cumulative delta. Plain dicts, no scene.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SoundGapMathTest.tscn

const GapMath = preload("res://src/effects/studio/SoundGapMath.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# No-skip cases (ported to the reshaped return) — audible neighbours, byte-identical.
	_test_move_middle_trigger_later_trades_the_two_neighbouring_gaps()
	_test_move_middle_trigger_earlier_trades_the_two_neighbouring_gaps()
	_test_clamped_so_it_cannot_cross_the_next_trigger()
	_test_clamped_so_it_cannot_cross_the_previous_trigger()
	_test_first_trigger_is_pinned()
	_test_zero_delta_restores_baseline_window()
	_test_return_to_origin_restores_after_a_move()
	_test_out_of_range_index_is_a_noop()
	# Skip-aware cases.
	_test_skip_wall_is_consumed_floors_at_previous_audible()
	_test_skip_gaps_are_consumed_nearest_first()
	_test_no_previous_audible_floors_at_phase_offset()
	_test_reversibility_is_a_pure_function_of_the_baseline()

	print("\n=== SoundGapMathTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundGapMathTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundGapMathTest")
		get_tree().quit(0)


## durs [4,10,6], move index 1 by +3 → dur[0]=7, dur[1]=7. Oracle worked by hand:
## fires were 0,4,14; after they are 0,7,14 — only fire[1] moved (+3), fire[2] stays.
func _test_move_middle_trigger_later_trades_the_two_neighbouring_gaps() -> void:
	var res := GapMath.stay_local_edits(_kfs([4, 10, 6]), 1, 3)
	var edits: Dictionary = res.edits
	_assert_eq(edits.size(), 2, "a valid move edits exactly the two neighbouring gaps")
	_assert_eq(int(edits.get(0, -1)), 7, "dur[N-1] gains K (4+3)")
	_assert_eq(int(edits.get(1, -1)), 7, "dur[N] loses K (10-3)")
	_assert_eq(int(res.applied_delta), 3, "applied_delta reports the achieved move")


## Symmetric: move index 1 by -2 → dur[0]=2, dur[1]=12. fires 0,4,14 → 0,2,14.
func _test_move_middle_trigger_earlier_trades_the_two_neighbouring_gaps() -> void:
	var res := GapMath.stay_local_edits(_kfs([4, 10, 6]), 1, -2)
	_assert_eq(int(res.edits.get(0, -1)), 2, "dur[N-1] loses |K| (4-2)")
	_assert_eq(int(res.edits.get(1, -1)), 12, "dur[N] gains |K| (10+2)")
	_assert_eq(int(res.applied_delta), -2, "applied_delta is the signed achieved move")


## A move larger than the gap to the next trigger clamps at coincidence (gap 0), it
## never makes dur[N] negative: index 1 by +50 with dur[1]=10 → dur[0]=14, dur[1]=0.
func _test_clamped_so_it_cannot_cross_the_next_trigger() -> void:
	var res := GapMath.stay_local_edits(_kfs([4, 10, 6]), 1, 50)
	_assert_eq(int(res.edits.get(0, -1)), 14, "dur[N-1] gains only the clamped delta (+10)")
	_assert_eq(int(res.edits.get(1, -1)), 0, "dur[N] bottoms out at 0, never negative")
	_assert_eq(int(res.applied_delta), 10, "applied_delta is clamped to the right capacity")


## Symmetric clamp against the previous trigger: index 1 by -50 with dur[0]=4 →
## dur[0]=0, dur[1]=14 (fire[1] lands exactly on fire[0], never before it).
func _test_clamped_so_it_cannot_cross_the_previous_trigger() -> void:
	var res := GapMath.stay_local_edits(_kfs([4, 10, 6]), 1, -50)
	_assert_eq(int(res.edits.get(0, -1)), 0, "dur[N-1] bottoms out at 0, never negative")
	_assert_eq(int(res.edits.get(1, -1)), 14, "dur[N] absorbs only the clamped delta (+10)")
	_assert_eq(int(res.applied_delta), -4, "applied_delta is clamped to the left capacity")


## The first trigger's fire IS the phase offset — there's no prior gap to trade, so
## it cannot be moved stay-local. Any delta returns no edits.
func _test_first_trigger_is_pinned() -> void:
	var res := GapMath.stay_local_edits(_kfs([4, 10, 6]), 0, 5)
	_assert_eq(res.edits.size(), 0, "index 0 is pinned (no-op)")
	_assert_eq(int(res.applied_delta), 0, "a pinned move achieves nothing")


## A zero net move (delta 0, or a delta that clamps to 0) re-emits the FULL BASELINE window
## — the gaps at their drag-start values — NOT empty. This is the byte-exact-reversibility
## contract (see the module doc): the caller overwrites the live gaps back to the baseline-
## relative distribution EVERY motion, so after a prior non-zero move a return-to-origin
## RESTORES the baseline (the original frame is reachable again). Emitting empty was the bug
## that stranded a trigger one frame off its origin once you'd dragged it away and back.
func _test_zero_delta_restores_baseline_window() -> void:
	var z := GapMath.stay_local_edits(_kfs([4, 10, 6]), 1, 0)
	_assert_eq(z.edits, {0: 4, 1: 10}, "delta 0 re-emits the baseline window (restore, not empty)")
	_assert_eq(int(z.applied_delta), 0, "…with zero net move")
	# dur[N]=0 already: any positive delta clamps to 0 → still re-emits the baseline window.
	var c := GapMath.stay_local_edits(_kfs([4, 0, 6]), 1, 5)
	_assert_eq(c.edits, {0: 4, 1: 0}, "a delta that clamps to 0 re-emits the baseline window")
	_assert_eq(int(c.applied_delta), 0, "…achieving no net move")


## The reported bug at the pure level: grab a trigger, drag it earlier (−1), then back to
## the origin. The −1 move trades the two gaps; the return (delta 0) must re-emit the ORIGINAL
## gaps so applying it lands the trigger back on its start frame — previously delta 0 emitted
## nothing, so the trigger stuck one frame early and the origin was unreachable.
func _test_return_to_origin_restores_after_a_move() -> void:
	var base := _kfs([4, 10, 6])
	var left := GapMath.stay_local_edits(base, 1, -1)
	_assert_eq(left.edits, {0: 3, 1: 11}, "the −1 move trades the two neighbouring gaps")
	var back := GapMath.stay_local_edits(base, 1, 0)
	_assert_eq(back.edits, {0: 4, 1: 10}, "returning to origin re-emits the baseline gaps (restores)")


## An index off the end of the array (no such keyframe) is inert.
func _test_out_of_range_index_is_a_noop() -> void:
	_assert_eq(GapMath.stay_local_edits(_kfs([4, 10, 6]), 9, 3).edits.size(), 0,
		"an out-of-range index is a no-op")


## E317-shaped: audible kf1, skip kf2, audible kf3 dragged earlier. Dragging kf3
## left by -100 must slide PAST the intervening skip (kf2) and floor on the previous
## AUDIBLE trigger fire[1], consuming the whole skip gap AND kf1's gap. dur[3] absorbs
## the achieved move to pin fire[4..]. Oracle (durs [14,11,15,16,544,600], sids
## [0,2,0,3,0,0]): left capacity = dur[1]+dur[2] = 26 → applied -26; edits
## {1:0, 2:0, 3:16+26=42}.
func _test_skip_wall_is_consumed_floors_at_previous_audible() -> void:
	var base := _kfs_sid([14, 11, 15, 16, 544, 600], [0, 2, 0, 3, 0, 0])
	var res := GapMath.stay_local_edits(base, 3, -100)
	_assert_eq(int(res.applied_delta), -26, "floors at the previous audible, not the skip wall")
	_assert_eq(int(res.edits.get(1, -1)), 0, "kf1's gap fully consumed")
	_assert_eq(int(res.edits.get(2, -1)), 0, "the skip gap fully consumed")
	_assert_eq(int(res.edits.get(3, -1)), 42, "dur[3] absorbs the move to pin later fires")
	_assert_eq(res.edits.size(), 3, "the governed window is [prev_audible .. index]")


## The intervening gaps are consumed NEAREST-first: a -20 move fully collapses the
## adjacent skip gap dur[2] (15) before it touches dur[1], which loses only the
## remaining 5. Oracle: edits {1:11-5=6, 2:0, 3:16+20=36}.
func _test_skip_gaps_are_consumed_nearest_first() -> void:
	var base := _kfs_sid([14, 11, 15, 16, 544, 600], [0, 2, 0, 3, 0, 0])
	var res := GapMath.stay_local_edits(base, 3, -20)
	_assert_eq(int(res.applied_delta), -20, "the full -20 is within capacity")
	_assert_eq(int(res.edits.get(1, -1)), 6, "the farther gap loses only the spill (11-5)")
	_assert_eq(int(res.edits.get(2, -1)), 0, "the nearest skip gap collapses first (15→0)")
	_assert_eq(int(res.edits.get(3, -1)), 36, "dur[3] absorbs the whole move")


## No audible trigger left of the dragged one: the floor is the phase offset, so a
## large leftward drag consumes every prior gap. Oracle (durs [10,7,20,30], sids
## [0,0,3,0], index 2): left capacity = dur[0]+dur[1] = 17 → applied -17; edits
## {0:0, 1:0, 2:20+17=37}.
func _test_no_previous_audible_floors_at_phase_offset() -> void:
	var base := _kfs_sid([10, 7, 20, 30], [0, 0, 3, 0])
	var res := GapMath.stay_local_edits(base, 2, -1000)
	_assert_eq(int(res.applied_delta), -17, "floor = phase offset = sum of all prior gaps")
	_assert_eq(int(res.edits.get(0, -1)), 0, "the first gap is consumed")
	_assert_eq(int(res.edits.get(1, -1)), 0, "the second gap is consumed")
	_assert_eq(int(res.edits.get(2, -1)), 37, "dur[2] absorbs the whole move")


## The byte-exact reversibility fork: the result is a PURE function of (baseline,
## index, delta) — it never reads accumulated state — so the caller (fixed drag-start
## baseline + cumulative delta) can retrace by re-feeding a smaller delta. From the
## same baseline, -20 gives {1:6,2:0,3:36}; re-feeding -5 restores dur[1] to its
## baseline 11 (nearest-first only reached dur[2] this time). Calling twice is
## identical (no history).
func _test_reversibility_is_a_pure_function_of_the_baseline() -> void:
	var base := _kfs_sid([14, 11, 15, 16, 544, 600], [0, 2, 0, 3, 0, 0])
	var far := GapMath.stay_local_edits(base, 3, -20)
	_assert_eq(int(far.edits.get(1, -1)), 6, "the -20 drag reaches dur[1]")
	# Re-feed a smaller cumulative delta from the SAME baseline → dur[1] returns to 11.
	var back := GapMath.stay_local_edits(base, 3, -5)
	_assert_eq(int(back.edits.get(1, -1)), 11, "re-feeding -5 restores dur[1] to baseline 11")
	_assert_eq(int(back.edits.get(2, -1)), 10, "dur[2] carries the whole -5 (15-5)")
	_assert_eq(int(back.edits.get(3, -1)), 21, "dur[3] absorbs -5 (16+5)")
	# Purity: same inputs, same output, regardless of prior calls.
	var again := GapMath.stay_local_edits(base, 3, -20)
	_assert_eq(again.edits, far.edits, "identical inputs yield identical edits (no history)")


func _kfs(durations: Array) -> Array:
	var sids: Array = []
	for _d in durations:
		sids.append(5)
	return _kfs_sid(durations, sids)


func _kfs_sid(durations: Array, sids: Array) -> Array:
	var out: Array = []
	for i in durations.size():
		out.append({"duration_frames": int(durations[i]), "sound_id": int(sids[i])})
	return out


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
