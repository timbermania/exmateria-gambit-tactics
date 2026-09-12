extends Node
## TDD guard for ColorLowering (ADR-0087) — the pure conversion between the colour-lane
## AUTHORING model (absolute frame intervals) and its length-encoded STORAGE (`time_value`
## s16, `duration_frames = time_value × 8`, or 1 when time_value == 0). Palette AND screen
## share this encoding (same parser rule), so both channels lower through this ONE module —
## forked snap math is how the palette split bug happened. This is the colour analogue of
## CameraLowering: a boundary drag authors an absolute interval; lowering re-derives the
## on-disk `time_value`, so drags SNAP to 8-frame steps and clamp to a minimum 1-frame tween
## (time_value 0), never zero-width. See CONTEXT "Authoring time / Lowering".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ColorLoweringTest.tscn

const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_duration_for_time_value_matches_the_parser_rule()
	_test_time_value_for_duration_snaps_to_eight()
	_test_the_two_conversions_round_trip()
	_test_snap_duration_yields_a_faithful_length()
	_test_trade_durations_freezes_the_far_edge()
	_test_split_durations_prefers_zero_drift_then_nearest_click()
	_test_split_durations_short_span_drifts_minimally_toward_the_click()
	_test_covering_finds_the_keyframe_owning_a_frame()
	_test_stub_split_brackets_a_one_frame_stub_with_spacers()

	print("\n=== ColorLoweringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColorLoweringTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColorLoweringTest")
		get_tree().quit(0)


## The on-disk decode: time_value × 8, but a time_value of 0 is a 1-frame snap (the parser's
## `duration_frames = time_value*8 if time_value>0 else 1`).
func _test_duration_for_time_value_matches_the_parser_rule() -> void:
	_assert_eq(Lowering.duration_for_time_value(0), 1, "tv 0 → 1-frame snap")
	_assert_eq(Lowering.duration_for_time_value(1), 8, "tv 1 → 8 frames")
	_assert_eq(Lowering.duration_for_time_value(5), 40, "tv 5 → 40 frames")


## The inverse: an authored duration lowers to the nearest 8-frame time_value; a ≤1-frame
## interval is time_value 0 (the 1-frame min tween).
func _test_time_value_for_duration_snaps_to_eight() -> void:
	_assert_eq(Lowering.time_value_for_duration(1), 0, "1 frame → tv 0")
	_assert_eq(Lowering.time_value_for_duration(8), 1, "8 frames → tv 1")
	_assert_eq(Lowering.time_value_for_duration(40), 5, "40 frames → tv 5")
	_assert_eq(Lowering.time_value_for_duration(12), 2, "12 frames rounds to tv 2 (16 frames)")
	_assert_eq(Lowering.time_value_for_duration(3), 0, "3 frames rounds down to tv 0 (1-frame min)")


## time_value → duration → time_value is the identity for every encodable time_value.
func _test_the_two_conversions_round_trip() -> void:
	for tv in range(0, 11):
		var back := Lowering.time_value_for_duration(Lowering.duration_for_time_value(tv))
		_assert_eq(back, tv, "tv %d round-trips through duration" % tv)


## snap_duration is the faithful length any authored duration lands on — 1 or a multiple of 8.
func _test_snap_duration_yields_a_faithful_length() -> void:
	_assert_eq(Lowering.snap_duration(8), 8, "8 stays 8")
	_assert_eq(Lowering.snap_duration(10), 8, "10 snaps down to 8")
	_assert_eq(Lowering.snap_duration(12), 16, "12 snaps up to 16")
	_assert_eq(Lowering.snap_duration(3), 1, "3 snaps to the 1-frame min")


## The BOUNDARY-TRADE chooser (ADR-0101 decision 1): both halves faithful, summing to `total`
## EXACTLY so the far edge cannot move, landing as near the drag as the encoding allows.
## For total 40 (= 8+32) the offered boundaries are {8, 16, 24, 32} — 1 is NOT offered, because
## its partner 39 has no encoding. That is the ratified 8-grained trade.
func _test_trade_durations_freezes_the_far_edge() -> void:
	_assert_eq(Lowering.trade_durations(40, 16)["first"], 16, "an offered position is hit exactly")
	_assert_eq(Lowering.trade_durations(40, 1)["first"], 8, "1 is not offered (39 is unstorable) → nearest offered is 8")
	_assert_eq(Lowering.trade_durations(40, 12)["first"], 16, "a tie between 8 and 16 rounds UP, matching time_value_for_duration")
	_assert_eq(Lowering.trade_durations(40, 100)["first"], 32, "an over-drag lands on the last offered position")
	_assert_eq(Lowering.trade_durations(40, 40)["first"], 32, "desired == total still leaves the neighbour ≥ 1 frame")
	for desired in range(0, 41):
		var t := Lowering.trade_durations(40, desired)
		if int(t["first"]) + int(t["second"]) != 40 \
				or not Lowering.is_faithful(int(t["first"])) \
				or not Lowering.is_faithful(int(t["second"])):
			_assert_eq(false, true, "trade at %d broke the invariant: %s" % [desired, str(t)])
			return
	_assert_eq(true, true, "every position on a 40-frame total sums exactly and stays storable")
	# A total that DOES admit the 1-frame minimum: 9 = 1+8, so {1, 8} are both offered.
	_assert_eq(Lowering.trade_durations(9, 0)["first"], 1, "the 1-frame squeeze IS reachable when the total allows it")
	_assert_eq(Lowering.trade_durations(9, 0)["second"], 8, "…and its partner is exact, not re-snapped")


## The INSERT-WAYPOINT split chooser: both halves must be faithful lengths (1 or a multiple
## of 8). Zero far-edge drift (first+second == total) wins outright; among equal-drift pairs
## the cut lands nearest the clicked frame (|first − desired|).
func _test_split_durations_prefers_zero_drift_then_nearest_click() -> void:
	_assert_eq(Lowering.split_durations(16, 4), {"first": 8, "second": 8},
		"a 16-frame span only splits cleanly at 8+8 — a near-start click still gets it")
	_assert_eq(Lowering.split_durations(16, 12), {"first": 8, "second": 8},
		"…and a near-end click gets the same clean split")
	_assert_eq(Lowering.split_durations(24, 3), {"first": 8, "second": 16},
		"a near-start click on 24 takes the clean 8+16, NOT a drifting 1+24 sliver")
	_assert_eq(Lowering.split_durations(24, 20), {"first": 16, "second": 8},
		"a near-end click on 24 takes 16+8")
	_assert_eq(Lowering.split_durations(40, 19), {"first": 16, "second": 24},
		"the cut lands at the nearest storable boundary to the click (19 → 16)")


## A span with no clean split (8 or 1 frames: no faithful pair sums to it) drifts by the
## MINIMUM (one frame), placing the sliver on the side nearest the click.
func _test_split_durations_short_span_drifts_minimally_toward_the_click() -> void:
	_assert_eq(Lowering.split_durations(8, 3), {"first": 1, "second": 8},
		"a near-start click on 8 slivers at start+1 (drift +1, the minimum)")
	_assert_eq(Lowering.split_durations(8, 7), {"first": 8, "second": 1},
		"a near-end click on 8 slivers at the far edge instead")
	_assert_eq(Lowering.split_durations(1, 1), {"first": 1, "second": 1},
		"a 1-frame span degenerates to two 1-frame tweens")


## The shared cumulative-duration window search both channels use to resolve a clicked frame
## to the keyframe whose `[start, start+dur)` tile contains it — {index, start}, index −1 when
## nothing covers it (empty lane or past the tail). Duck-typed on `.time_value` so palette and
## screen keyframes both fit.
func _test_covering_finds_the_keyframe_owning_a_frame() -> void:
	# tv 1 (8 frames) | tv 0 (1-frame snap) | tv 2 (16 frames): starts 0, 8, 9; total 25.
	var kfs: Array = [{"time_value": 1}, {"time_value": 0}, {"time_value": 2}]
	_assert_eq(Lowering.covering(kfs, 0), {"index": 0, "start": 0}, "frame 0 → first tile")
	_assert_eq(Lowering.covering(kfs, 7), {"index": 0, "start": 0}, "frame 7 → still the first tile")
	_assert_eq(Lowering.covering(kfs, 8), {"index": 1, "start": 8}, "frame 8 → the 1-frame snap tile")
	_assert_eq(Lowering.covering(kfs, 9), {"index": 2, "start": 9}, "frame 9 → the third tile")
	_assert_eq(Lowering.covering(kfs, 24), {"index": 2, "start": 9}, "frame 24 → the third tile's last frame")
	_assert_eq(Lowering.covering(kfs, 25), {"index": -1, "start": 25},
		"past the tail → index −1, start = the lane's total length")
	_assert_eq(Lowering.covering([], 5), {"index": -1, "start": 0}, "empty lane → index −1, start 0")


## The ADD-INTO-A-SPACER split (ADR-0087 decs. 23-28): a spacer's only affordance is
## right-click → Add, which cuts its tile into THREE — [before-spacer | 1-frame disabled stub |
## after-spacer]. `stub_split(total, desired)` returns those three faithful lengths: the stub
## is ALWAYS 1 frame (time_value 0), `before` is the largest faithful length (0/1/×8) at-or-
## before the click (the stub lands at the ÷8 boundary nearest below the click — the inherent
## grid residual), and `after` is the faithful length nearest the leftover, or 0 at an edge.
func _test_stub_split_brackets_a_one_frame_stub_with_spacers() -> void:
	_assert_eq(Lowering.stub_split(400, 200), {"before": 200, "stub": 1, "after": 200},
		"a mid click on a 400-frame spacer brackets a 1-frame stub with two spacers")
	_assert_eq(Lowering.stub_split(400, 0), {"before": 0, "stub": 1, "after": 400},
		"a click at the very start seeds [stub | spacer] — no before-spacer")
	_assert_eq(Lowering.stub_split(400, 400), {"before": 392, "stub": 1, "after": 8},
		"a click at the end lands the stub at the last ÷8 boundary, a spacer trailing it")
	_assert_eq(Lowering.stub_split(1, 0), {"before": 0, "stub": 1, "after": 0},
		"a 1-frame spacer becomes just the 1-frame stub (no room to bracket)")
	# The stub is ALWAYS exactly one frame, whatever the click.
	for d in [0, 3, 50, 199, 400]:
		_assert_eq(int(Lowering.stub_split(400, d)["stub"]), 1,
			"the stub is always a single frame (click %d)" % d)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
