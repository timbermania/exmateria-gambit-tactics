extends Node
## TDD guard for the colour boundary trade's FAR-EDGE FREEZE (ADR-0087 dec. 30,
## ADR-0101 decision 1). PaletteBoundaryEditTest already asserts the trade on nicely-aligned
## numbers; this guard asserts the INVARIANT on every drag position, which is where it broke.
##
## A colour span's length is `1` or a multiple of 8 (`time_value × 8`, tv 0 = 1 frame), so the
## neighbour's share of a trade is storable only by luck. The pre-fix code handed it
## `total - new_dur_n` and let `_set_duration` re-snap it SILENTLY — the far edge slid ±1 frame
## in ~13% of positions, always where a span landed on the 1-frame minimum. The author saw it as
## "drag the left side to the first frame snap and BOTH sides move".
##
## The invariant: `dur[n] + dur[n+1]` is CONSERVED EXACTLY by a non-ripple boundary trade, and
## both halves land on storable lengths. An exact pair always exists — a trade's total is by
## construction the sum of two storable lengths, so it is its own witness (unlike the
## insert-waypoint split, where a single span of 1 or 8 genuinely has no clean cut).
##
## Palette and screen carry the identical trade and are both swept here — forked snap math is
## how the palette split bug happened.
##
## Run: <GODOT> --path . res://tests/ColourBoundaryFarEdgeTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const ScreenDataClass = ExMateriaEffects.ScreenData
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

## Pinned so a mid-test abort shows as a SHORT COUNT rather than a green [PASS]
## (the runner counts only assertions that RAN).
const EXPECTED_ASSERTIONS := 48

## The storable lengths under test: tv 0 → 1 frame, then multiples of 8.
const TVS := [0, 1, 2, 3, 4]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_palette_far_edge_is_conserved_at_every_drag_position()
	_test_screen_far_edge_is_conserved_at_every_drag_position()
	_test_both_halves_always_land_on_storable_lengths()
	_test_the_reported_case_the_first_snap_moves_only_one_edge()
	_test_downstream_is_untouched_by_any_trade()
	_test_an_exact_pair_exists_for_every_reachable_total()

	var total: int = _passed + _failed
	if total != EXPECTED_ASSERTIONS:
		_failed += 1
		print("[FAIL] assertion count drifted — expected %d, ran %d (a mid-test abort?)"
			% [EXPECTED_ASSERTIONS, total])
	print("\n=== ColourBoundaryFarEdgeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourBoundaryFarEdgeTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourBoundaryFarEdgeTest")
		get_tree().quit(0)


## THE regression. For every pair of storable lengths and EVERY boundary position an author can
## drag to, the two traded durations must still sum to what they summed to before.
func _test_palette_far_edge_is_conserved_at_every_drag_position() -> void:
	for tv_a in TVS:
		var worst := _sweep_pair("palette", tv_a)
		_assert_eq(worst["drift"], 0,
			"palette: far edge conserved for every position after a %d-frame span (worst: %s)"
				% [Lowering.duration_for_time_value(tv_a), str(worst)])


func _test_screen_far_edge_is_conserved_at_every_drag_position() -> void:
	for tv_a in TVS:
		var worst := _sweep_pair("screen", tv_a)
		_assert_eq(worst["drift"], 0,
			"screen: far edge conserved for every position after a %d-frame span (worst: %s)"
				% [Lowering.duration_for_time_value(tv_a), str(worst)])


## Freezing the far edge must not be bought by writing an UNSTORABLE length — a duration that
## is neither 1 nor a multiple of 8 would round-trip differently through save/load.
func _test_both_halves_always_land_on_storable_lengths() -> void:
	for kind in ["palette", "screen"]:
		for tv_a in TVS:
			var worst := _sweep_pair(kind, tv_a)
			_assert_true(bool(worst["all_storable"]),
				"%s: both traded halves stay storable after a %d-frame span"
					% [kind, Lowering.duration_for_time_value(tv_a)])


## The reported symptom, pinned as one concrete case: an 8-frame hold before a 24-frame tween.
## Dragging the boundary hard left must move the GRABBED edge and leave the far one alone.
func _test_the_reported_case_the_first_snap_moves_only_one_edge() -> void:
	for kind in ["palette", "screen"]:
		var ctx := _make(kind, [1, 3, 2])          # 8 / 24 / 16 — the drift case
		var far_before: int = _dur(ctx, 0) + _dur(ctx, 1)
		ctx["session"].apply_edit(_ref(kind, 0), 0)   # drag hard left
		_assert_eq(_dur(ctx, 0) + _dur(ctx, 1), far_before,
			"%s: the far edge did not move when the boundary was dragged to 0" % kind)
		_assert_true(_dur(ctx, 1) != 32,
			"%s: the 24-frame neighbour was not silently re-snapped up to 32" % kind)


## A trade is strictly local: nothing past the neighbour may shift by a single frame.
func _test_downstream_is_untouched_by_any_trade() -> void:
	for kind in ["palette", "screen"]:
		for desired in [0, 1, 7, 8, 9, 15, 16, 23, 24, 31, 32]:
			var ctx := _make(kind, [1, 3, 2])
			var down_before: int = _dur(ctx, 2)
			ctx["session"].apply_edit(_ref(kind, 0), desired)
			_assert_eq(_dur(ctx, 2), down_before,
				"%s: downstream span untouched by a trade to %d" % [kind, desired])


## The claim decision 1 rests on: because a trade's total is the sum of two storable lengths, an
## exact storable pair ALWAYS exists, so the freeze never needs a drifting fallback.
func _test_an_exact_pair_exists_for_every_reachable_total() -> void:
	var storable := {}
	for k in range(0, 200):
		storable[Lowering.duration_for_time_value(k)] = true
	var checked: int = 0
	var missing: Array = []
	for tv_a in range(0, 40):
		for tv_b in range(0, 40):
			var total: int = Lowering.duration_for_time_value(tv_a) \
				+ Lowering.duration_for_time_value(tv_b)
			var found := false
			for a in storable.keys():
				if a < total and storable.has(total - a):
					found = true
					break
			checked += 1
			if not found:
				missing.append(total)
	_assert_true(checked > 0, "the reachable-total sweep actually ran")
	_assert_eq(missing.size(), 0,
		"every reachable total has an exact storable pair (missing: %s)" % str(missing.slice(0, 5)))


# --- the sweep ------------------------------------------------------------

## Drag the boundary after span 0 to EVERY position in [0, total] and report the worst
## far-edge drift plus whether every written length stayed storable.
func _sweep_pair(kind: String, tv_a: int) -> Dictionary:
	var worst := {"drift": 0, "all_storable": true, "at": -1, "tv_b": -1}
	for tv_b in TVS:
		var total: int = Lowering.duration_for_time_value(tv_a) \
			+ Lowering.duration_for_time_value(tv_b)
		for desired in range(0, total + 1):
			var ctx := _make(kind, [tv_a, tv_b, 2])
			ctx["session"].apply_edit(_ref(kind, 0), desired)
			var got: int = _dur(ctx, 0) + _dur(ctx, 1)
			var drift: int = got - total
			if absi(drift) > absi(int(worst["drift"])):
				worst["drift"] = drift
				worst["at"] = desired
				worst["tv_b"] = tv_b
			for i in [0, 1]:
				var d: int = _dur(ctx, i)
				if d != 1 and (d % Lowering.STEP) != 0:
					worst["all_storable"] = false
	return worst


# --- fixtures -------------------------------------------------------------

func _ref(kind: String, index: int) -> Dictionary:
	if kind == "screen":
		return {"channel": "screen", "context": "for_each",
			"event_index": index, "field": "boundary_end"}
	return {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": index, "field": "boundary_end"}


func _dur(ctx: Dictionary, index: int) -> int:
	return int(ctx["chan"].keyframes[index].duration_frames)


## Build a one-channel effect of the given kind from a list of time_values.
func _make(kind: String, time_values: Array) -> Dictionary:
	var data := _FakeData.new()
	var chan
	if kind == "screen":
		data.screen = _screen_data(time_values)
		chan = data.screen.get_channel("for_each")
	else:
		data.palette = _palette_data(time_values)
		chan = data.palette.get_channel("for_each", "affected_units")
	return {"data": data, "chan": chan, "session": Session.new(data)}


func _palette_data(time_values: Array):
	var kfs: Array = []
	for i in range(time_values.size()):
		var tv: int = int(time_values[i])
		kfs.append({"index": i, "time_value": tv,
			"duration_frames": Lowering.duration_for_time_value(tv),
			"rgb": [10, 20, 30], "ctrl": 0x85, "enabled": true, "blend_mode": 0})
	return PaletteDataClass.from_json({
		"for_each": {"affected_units": {
			"context": "for_each", "channel_name": "affected_units",
			"max_keyframe": time_values.size() + 1, "keyframes": kfs,
		}},
	})


func _screen_data(time_values: Array):
	var kfs: Array = []
	for i in range(time_values.size()):
		var tv: int = int(time_values[i])
		kfs.append({"index": i, "time_value": tv,
			"duration_frames": Lowering.duration_for_time_value(tv),
			"start_r": 0, "start_g": 0, "start_b": 0,
			"end_r": 128, "end_g": 128, "end_b": 128,
			"ctrl": 0x85, "blend_mode": 0})
	return ScreenDataClass.from_json({
		"for_each": {
			"context": "for_each",
			"max_keyframe": time_values.size() + 1, "keyframes": kfs,
		},
	})


class _FakeData extends RefCounted:
	var screen = null
	var palette = null
	var camera = null


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
