extends Node
## TDD guard for the colour MOVE (ADR-0101 decisions 3-7) — a body-drag that slides a colour
## span at frame granularity by spending keyframe slots.
##
## The fixture is FOLD-DERIVED, per the proof standard this branch runs on: it stamps no
## `fields.spacer` anywhere and asserts the REAL fold's verdict vector before relying on it.
## An idempotent repeat of a settled tint is disable-equivalent (ADR-0087 decs. 17-22), so
## the fold — not the test author — decides which tiles are HOLDS, which is the whole currency
## Move trades in. If the first assertion ever fails, the fixture has stopped exercising the
## fold and everything below it is worthless.
##
## Run: <GODOT> --path . res://tests/ColourMoveTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")
const MovePlan = preload("res://src/effects/studio/ColourMovePlan.gd")
const PaletteChannelClass = preload("res://src/effects/studio/PaletteChannel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_fixture_is_fold_derived_not_stamped()
	_test_the_planner_is_pure_arithmetic()
	_test_a_coarse_slide_preserves_width_and_pins_the_outside()
	_test_a_fine_slide_costs_exactly_the_residual_in_one_frame_keyframes()
	_test_a_broke_channel_degrades_to_eight_grained_rather_than_refusing()
	_test_a_fine_slide_can_be_slid_straight_back()
	_test_dragging_into_a_hold_run_collapses_it_and_recovers_the_slot()
	_test_padding_is_a_copy_of_the_hold_not_a_disabled_keyframe()
	_test_a_wedged_span_is_refused()
	_test_an_empty_run_is_grown_by_minting_padding()
	_test_the_cap_refuses_an_insert_into_a_full_channel()
	_test_a_body_drag_is_one_undo_and_a_click_is_none()

	print("\n=== ColourMoveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourMoveTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourMoveTest")
		get_tree().quit(0)


## The fold, unprompted, must call spans 1 and 3 empty space and spans 0/2/4 drawn.
func _test_the_fixture_is_fold_derived_not_stamped() -> void:
	var data = _fixture()
	var verdicts := _score_verdicts(data)
	_assert_eq(verdicts, [false, true, false, true, false],
		"the REAL fold declares the two idempotent repeats holds, unstamped")
	_assert_eq(PaletteChannelClass.move_context(data, _ref(2))["holds"],
		[false, true, false, true, false],
		"…and move_context's hold vector agrees with the score's")


## The rule is arithmetic over two plain arrays, so it is guarded with no EffectData, no fold
## and no paint. `1` and the multiples of 8 are the only storable lengths, so a region of
## `8a + b` frames costs `1 + b` keyframes.
func _test_the_planner_is_pure_arithmetic() -> void:
	var durations := [16, 16, 24, 16, 16]
	var holds := [false, true, false, true, false]

	var coarse: Dictionary = MovePlan.plan(durations, holds, 2, 8, 29)
	_assert_eq(int(coarse["delta"]), 8, "an 8-frame slide is offered whole")
	_assert_eq(int(coarse["cost"]), 0, "…and costs nothing: both runs stay on the 8-grid")

	var fine: Dictionary = MovePlan.plan(durations, holds, 2, 3, 29)
	_assert_eq(int(fine["delta"]), 3, "a 3-frame slide is offered at frame granularity")
	_assert_eq(int(fine["granularity"]), 1, "…and reports itself fine-grained")
	# lead 16→19 = 16 + 3×1 (4 keyframes... 1 + 3); trail 16→13 = 8 + 5×1 (1 + 5). Both runs
	# held one keyframe before, so the net is (4 + 6) − 2 = 8: decision 4's forced price.
	_assert_eq(int(fine["cost"]), 8, "…for exactly 8 slots, the forced price of a sub-8 delta")

	_assert_eq(int(MovePlan.plan(durations, holds, 2, 999, 29)["delta"]), 16,
		"a slide past the trailing hold clamps to the room it has")
	_assert_eq(int(MovePlan.plan(durations, holds, 2, -999, 29)["delta"]), -16,
		"…and symmetrically to the left")
	_assert_eq(MovePlan.hold_run_bounds(holds, 2), {"p": 1, "q": 4},
		"the runs bracketing span 2 are [1,2) and [3,4)")


## Width preserved, and everything outside the two hold runs still starts where it started.
func _test_a_coarse_slide_preserves_width_and_pins_the_outside() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var before_starts := _drawn_starts(ch)
	var before_width: int = _durations(ch)[2]
	var session = Session.new(data)
	var res: Dictionary = session.move_span(_ref(2), 8)

	_assert_eq(int(res.get("delta", 0)), 8, "the span slid 8 frames")
	var starts := _drawn_starts(ch)
	_assert_eq(_durations(ch)[_moved_index(res)], before_width, "its width is preserved")
	_assert_eq(starts[0], before_starts[0], "the tint before the run is still pinned")
	_assert_eq(starts[2], before_starts[2], "the tint after the run is still pinned")
	_assert_eq(starts[1], before_starts[1] + 8, "…and only the moved span moved")
	_assert_eq(_lane_length(ch), _lane_length(_chan(_fixture())),
		"the lane's total length is unchanged")


## A non-multiple-of-8 delta is representable ONLY as one-frame keyframes, and the price is
## forced by the arithmetic, never chosen.
func _test_a_fine_slide_costs_exactly_the_residual_in_one_frame_keyframes() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var used_before: int = int(ch.max_keyframe)
	var session = Session.new(data)
	var res: Dictionary = session.move_span(_ref(2), 3)

	_assert_eq(int(res.get("delta", 0)), 3, "the span slid 3 frames — frame granularity")
	_assert_eq(int(ch.max_keyframe) - used_before, 8, "…paid for with exactly 8 slots")
	_assert_eq(_lead_lengths(ch), [16, 1, 1, 1], "the lead run is 16 + three 1-frame keyframes")
	_assert_eq(_lane_length(ch), _lane_length(_chan(_fixture())), "the lane length is unchanged")


## Decision 4: where the channel cannot pay, the drag COARSENS rather than refusing.
func _test_a_broke_channel_degrades_to_eight_grained_rather_than_refusing() -> void:
	var data = _fixture(29)          # max_keyframe 29 → 4 free slots, under the fine budget
	var ch = _chan(data)
	var session = Session.new(data)
	var res: Dictionary = session.move_span(_ref(2), 11)
	_assert_eq(int(res.get("delta", 0)), 8, "an 11-frame ask lands on 8 — the author still moves")
	_assert_eq(int(res.get("granularity", 0)), 8, "…and the plan says so")
	_assert_eq(int(ch.max_keyframe), 29, "…having spent no slot at all")

	var broke = _fixture(29)
	var s2 = Session.new(broke)
	_assert_true(s2.move_span(_ref(2), 3).is_empty(),
		"a sub-8 ask on a broke channel is a no-op, not a fabricated 3-frame slide")


## REVERSIBILITY, the fault the author reported as "once you move it, it doesn't let you move
## back". A fine slide SPENDS the slots that licensed it, and `EffectEditSession.begin_move`
## re-reads the budget at EVERY grab — so the return trip found the channel under the fine
## budget, planned in eights, and never offered the frame the span came from. Author, verbatim:
## *"it will stay in place until it is close to the next option AFTER the original spot — then
## it will snap to that. It's like the original movepoint is not a candidate."*
##
## The return's own cost is NEGATIVE: it re-merges exactly the padding the out trip inserted.
## It was always affordable — `free_slots >= FINE_SLOT_BUDGET` is a WORST-CASE bound, and using
## it as a gate meant the exact delta was never priced. Shipped witnesses: E003
## for_each/target #1 and E023 phase1/affected_units #2.
func _test_a_fine_slide_can_be_slid_straight_back() -> void:
	var data = _fixture(20)              # 13 free slots: fine, but fewer than 8 to spare
	var ch = _chan(data)
	var lead_before := _lead_lengths(ch)
	var used_before: int = int(ch.max_keyframe)
	var session = Session.new(data)

	var out: Dictionary = session.move_span(_ref(2), 3)
	_assert_eq(int(out.get("delta", 0)), 3, "the slide OUT is frame-granular")
	_assert_eq(int(ch.max_keyframe), used_before + 8,
		"…and spends the very 8 slots that licensed it")
	_assert_true(Lowering.free_slots(ch) < MovePlan.FINE_SLOT_BUDGET,
		"…leaving the channel under the fine budget — the trap the second grab walks into")

	# The return's PRICE, read off the planner the second grab actually consults.
	var n1: int = int(out.get("event_index", -1))
	var ctx: Dictionary = PaletteChannelClass.move_context(data, _ref(n1))
	var priced: Dictionary = MovePlan.plan(ctx["durations"], ctx["holds"], n1, -3,
		int(ctx["free_slots"]))
	_assert_eq(int(priced.get("cost", 999)), -8,
		"the return RECOVERS 8 slots — never unaffordable, merely never priced")

	var back: Dictionary = session.move_span(_ref(n1), -3)
	_assert_eq(int(back.get("delta", 0)), -3,
		"the second grab slides it straight BACK — the frame it came from is still offered")
	_assert_eq(int(ch.max_keyframe), used_before, "…and the budget is back where it started")
	_assert_eq(_lead_lengths(ch), lead_before, "…as is the lead run, keyframe for keyframe")


## Decision 7: a hold's 1-frame floor bounds a KEYFRAME, not a REGION — a run dragged to zero
## vanishes and its slot comes back.
func _test_dragging_into_a_hold_run_collapses_it_and_recovers_the_slot() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var used_before: int = int(ch.max_keyframe)
	var session = Session.new(data)
	var res: Dictionary = session.move_span(_ref(2), -16)

	_assert_eq(int(res.get("delta", 0)), -16, "the span slid onto the previous tint's edge")
	_assert_eq(int(ch.max_keyframe), used_before - 1, "the emptied hold was deleted, freeing a slot")
	_assert_eq(_durations(ch).slice(0, 3), [16, 24, 32],
		"…so the tint butts straight against the moved span, and the trail absorbed it all")
	_assert_eq(_lane_length(ch), _lane_length(_chan(_fixture())), "the lane length is unchanged")


## Decision 6, narrowed: where the run HAS an adjacent hold, padding is still a COPY of it —
## byte-shaped like the shipped data it extends, and free. (Where the run is EMPTY the padding
## is now MINTED inert instead of copying the keyframe at the insertion point; that half of
## decision 6 lives in `ColourMovePadShapeTest`.)
func _test_padding_is_a_copy_of_the_hold_not_a_disabled_keyframe() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var hold_rgb: Vector3i = ch.keyframes[1].rgb
	var hold_ctrl: int = int(ch.keyframes[1].ctrl)
	Session.new(data).move_span(_ref(2), 3)

	var pads_enabled := true
	var pads_match := true
	for i in range(1, 5):            # the re-encoded lead run: 16 + three 1-frame pads
		pads_enabled = pads_enabled and bool(ch.keyframes[i].enabled)
		pads_match = pads_match and ch.keyframes[i].rgb == hold_rgb \
			and int(ch.keyframes[i].ctrl) == hold_ctrl
	_assert_true(pads_enabled, "every padding keyframe is ENABLED (a hold, not a disabled tween)")
	_assert_true(pads_match, "…and carries the adjacent hold's own bytes")
	_assert_eq(_score_verdicts(data).slice(1, 5), [true, true, true, true],
		"…so the REAL fold still calls the whole lead run empty space, and it stays invisible")


## A span with a drawn tween hard against it on both sides has nowhere to put the frames.
func _test_a_wedged_span_is_refused() -> void:
	var data = _wedged_fixture()
	var session = Session.new(data)
	_assert_eq(_score_verdicts(data), [false, false, false],
		"the wedged fixture's three tints are all DRAWN by the fold")
	_assert_true(session.move_span(_ref(1), 8).is_empty(),
		"a span wedged between two drawn tweens is refused")
	_assert_true(session.move_span(_ref(1), -8).is_empty(), "…in both directions")


## An empty run has no adjacent hold to copy, so it MINTS its padding — unconditionally, with
## no licence to grant or refuse. This test used to assert the opposite (a fold-measured
## `manufacture_left`, refused where a copy of the preceding tint would have shown), which is
## the rule ADR-0101 decision 6's narrowing retired; what stayed is the PRICE.
func _test_an_empty_run_is_grown_by_minting_padding() -> void:
	var durations := [16, 24, 16]
	var holds := [false, false, true]      # nothing in front of span 1, a hold behind it

	var grown: Dictionary = MovePlan.plan(durations, holds, 1, 8, 29)
	_assert_eq(int(grown["delta"]), 8, "the empty lead run is grown")
	_assert_eq(int(grown["cost"]), 1, "…for one slot: the minted pad itself")

	# The population the old licence REFUSED — a DRAWN tint hard in front of the span, so the
	# copy-the-insertion-point fallback would have tinted the lane. It moves now, because the
	# pad it grows carries no bytes to be wrong about.
	var strict = _build([
		{"tv": 2, "rgb": [0, 240, 241]},
		{"tv": 3, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 40, 200]},
	], 4)
	_assert_eq(int(Session.new(strict).move_span(_ref(1), 8).get("delta", 0)), 8,
		"a span whose only lead candidate was a DRAWN tint now slides — see ColourMovePadShapeTest")

	# A wedged span is still refused: minting invents PADDING, never room.
	_assert_true(not MovePlan.plan([16, 24, 16], [false, false, false], 1, 8, 29).get("ok", false),
		"…while a span between two DRAWN tweens still has no frames to trade")


## Decision 8: the verbs enforce the 33-slot cap up front instead of letting the saver
## discover the overflow.
func _test_the_cap_refuses_an_insert_into_a_full_channel() -> void:
	var full = _fixture(33)
	var session = Session.new(full)
	var add := _ref(0)
	add["frame"] = 4
	_assert_true(session.insert_event(add).is_empty(),
		"Add into a channel with no free slot is refused at the verb")
	_assert_eq(int(_chan(full).max_keyframe), 33, "…and nothing was appended past the 33rd")

	var roomy = _fixture()
	var ok := _ref(0)
	ok["frame"] = 4
	_assert_true(not Session.new(roomy).insert_event(ok).is_empty(),
		"…while a channel with room still adds")


## The live body-drag is ONE undo; a plain click (grab + release, no motion) records none.
func _test_a_body_drag_is_one_undo_and_a_click_is_none() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var pristine := _durations(ch)
	var session = Session.new(data)
	var ref := _ref(2)

	session.begin_move(ref)
	for d in [3, 11, 8]:
		session.move_preview(ref, d)
	session.end_move()
	_assert_eq(_durations(ch)[_run_start(ch)], 24, "the drag settled on its last position (16+8)")
	_assert_true(session.undo(), "the whole gesture is one undo")
	_assert_eq(_durations(ch), pristine, "…restoring the pristine channel")
	_assert_true(not session.undo(), "…and there is nothing more to undo")

	session.begin_move(ref)
	session.end_move()
	_assert_true(not session.undo(), "a click with no motion records no undo entry")


# --- fixtures -------------------------------------------------------------

func _ref(index: int) -> Dictionary:
	return {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": index}


func _chan(data):
	return data.palette.get_channel("for_each", "affected_units")


func _durations(ch) -> Array:
	return Lowering.durations(ch.keyframes)


func _lane_length(ch) -> int:
	var total: int = 0
	for d in _durations(ch).slice(0, Lowering.played_last(ch)):
		total += int(d)
	return total


## The lead run's per-keyframe lengths (index 1 up to the moved span).
func _lead_lengths(ch) -> Array:
	var out: Array = []
	for i in range(1, _run_start(ch)):
		out.append(Lowering.duration_for_time_value(int(ch.keyframes[i].time_value)))
	return out


## The moved span's raw index after a slide — the first keyframe past the lead run whose rgb is
## the moved tint's. Derived rather than assumed, because a fine slide re-encodes the run.
func _run_start(ch) -> int:
	for i in range(ch.keyframes.size()):
		if ch.keyframes[i].rgb == Vector3i(40, 40, 200):
			return i
	return -1


func _moved_index(res: Dictionary) -> int:
	return int(res.get("event_index", -1))


## Phase-local start frames of the three DRAWN tints, in order.
func _drawn_starts(ch) -> Array:
	var out: Array = []
	var start: int = 0
	var seen: Dictionary = {}
	for i in range(Lowering.played_last(ch)):
		var key := str(ch.keyframes[i].rgb)
		if not seen.has(key):
			seen[key] = true
			out.append(start)
		start += Lowering.duration_for_time_value(int(ch.keyframes[i].time_value))
	return out


func _score_verdicts(data) -> Array:
	var score: Dictionary = Model.build(data)
	for lane in score.get("lanes", []):
		if String(lane.get("id", "")) == "palette:for_each:affected_units":
			var out: Array = []
			for sp in lane.get("spans", []):
				out.append(bool(sp.get("fields", {}).get("spacer", false)))
			return out
	return []


## Two settled tints, each followed by an IDEMPOTENT REPEAT the fold calls a hold, then a
## third. Span 2 is the movable one: a hold run in front of it and one behind. Nothing stamps
## `spacer`. `used` overrides `max_keyframe` so a test can make the channel broke without
## changing what it plays (the played window is `max_keyframe − 1`, capped by the array).
func _fixture(used: int = 6):
	return _build([
		{"tv": 2, "rgb": [200, 40, 40]},
		{"tv": 2, "rgb": [200, 40, 40]},
		{"tv": 3, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 200, 40]},
	], used)


## Three genuinely different tints, no repeats — so the fold declares every one of them drawn
## and the middle span has nowhere to go.
func _wedged_fixture():
	return _build([
		{"tv": 2, "rgb": [200, 40, 40]},
		{"tv": 3, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 200, 40]},
	], 4)


func _build(spec: Array, used: int):
	var kfs: Array = []
	for i in range(spec.size()):
		kfs.append({"index": i, "time_value": int(spec[i]["tv"]),
			"duration_frames": Lowering.duration_for_time_value(int(spec[i]["tv"])),
			"rgb": spec[i]["rgb"], "ctrl": 0x85, "enabled": true, "blend_mode": 5})
	var pd = PaletteDataClass.from_json({
		"for_each": {"affected_units": {
			"context": "for_each", "channel_name": "affected_units",
			"max_keyframe": used, "keyframes": kfs,
		}},
	})
	var data := _FakeData.new()
	data.palette = pd
	return data


## Model.build reads across the whole effect, so the stub carries every field it touches.
class _FakeData extends RefCounted:
	var screen = null
	var palette = null
	var camera = null
	var timeline = null
	var sound = {}
	var script_ops: Array = []
	var emitters: Array = []
	var curves: Array = []
	var frames: Array = []
	var framesets: Array = []
	var animations: Array = []
	var effect_flags = null
	var time_scale = null
	var name: String = "fixture"


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
