extends Node
## TDD guard for the CAMERA MOVE (ADR-0101 decision 3) — the cheap kind. `end_frame` is
## ABSOLUTE, so a camera slide is two boundary writes: no quantization, no padding, no slot
## budget. Everything the colour lanes pay for is arithmetic camera gets for free, which is why
## it is the kind that proves the ARMING and the WEDGED-REFUSAL path on their own.
##
## A camera span owns `[events[n-1].end_frame, events[n].end_frame)`, so shifting both ends by
## one clamped delta preserves its width and pins everything outside the two neighbours. Both
## neighbours must be HOLDS (`CameraValueSemantics.is_spacer` — MAP + zero, decidable locally
## with no fold), because a move must never change what another span renders.
##
## Run: <GODOT> --path . res://tests/EffectCameraMoveTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const CameraChannelClass = preload("res://src/effects/studio/CameraChannel.gd")
const CameraLoweringClass = preload("res://src/effects/studio/CameraLowering.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_arming_covers_every_movable_kind()
	_test_a_slide_preserves_width_and_pins_the_outside()
	_test_the_delta_clamps_to_the_room_each_hold_has()
	_test_a_wedged_span_is_refused()
	_test_the_first_event_slides_right_by_growing_a_hold_at_the_origin()
	_test_a_drawn_left_neighbour_gets_a_manufactured_hold_too()
	_test_a_drawn_right_neighbour_gets_the_manufactured_hold()
	_test_a_sibling_lane_is_untouched()
	_test_a_body_drag_is_one_undo()
	_test_the_motion_path_touches_no_keyframe()
	_test_release_applies_exactly_once_and_reports_the_landing()
	_test_an_emptied_lead_hold_is_deleted_not_left_at_zero_width()
	_test_an_emptied_TRAIL_hold_is_deleted_too()
	_test_the_round_trip_restores_the_STORAGE_not_just_the_picture()

	print("\n=== EffectCameraMoveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraMoveTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraMoveTest")
		get_tree().quit(0)


## The gate that used to read `begins_with("particle:")`. `camera_compiled` is the read-only
## storage view and must NOT arm, which is exactly what keying on the id's own prefix buys.
func _test_the_arming_covers_every_movable_kind() -> void:
	for id in ["particle:phase1:0#2", "camera:phase1:angle#1",
			"palette:for_each:caster#3", "screen:phase2#0"]:
		_assert_true(Timeline.is_movable_span(id), "%s arms a Move" % id)
	for id in ["camera_compiled:phase1#4", "sound:phase1:2#0", "time_scale:for_each"]:
		_assert_true(not Timeline.is_movable_span(id), "%s does not" % id)


## Span 1 sits between two MAP+zero holds; sliding it moves both of its own boundaries and
## leaves every other end_frame in the lane where it was.
func _test_a_slide_preserves_width_and_pins_the_outside() -> void:
	var ed = _effect(_lane_json())
	var session = Session.new(ed)
	var before := _ends(ed)
	var res: Dictionary = session.move_span(_ref(2), 6)

	_assert_eq(int(res.get("delta", 0)), 6, "the span slid 6 frames")
	var after := _ends(ed)
	_assert_eq(after[1] - after[0], (before[1] - before[0]) + 6,
		"the hold in FRONT absorbed the slide by growing")
	_assert_eq(after[2] - after[1], before[2] - before[1], "the span's WIDTH is preserved")
	_assert_eq(after[3] - after[2], (before[3] - before[2]) - 6,
		"…and the hold BEHIND gave up exactly what the front took")
	_assert_eq(after[1], before[1] + 6, "its start moved by the delta")
	_assert_eq(after[2], before[2] + 6, "…and so did its end")
	_assert_eq(after[0], before[0], "the event before the lead hold is pinned")
	_assert_eq(after[3], before[3], "…and the one past the trailing hold too")


## Room is what each neighbouring hold actually has: the lead can be eaten to nothing, the
## trailing hold likewise, and neither can be pushed through the event beyond it. "Eaten to
## nothing" means GONE — a hold the slide empties is deleted rather than parked at zero width
## (ADR-0101 decision 7); see _test_an_emptied_lead_hold_is_deleted_not_left_at_zero_width.
func _test_the_delta_clamps_to_the_room_each_hold_has() -> void:
	var ed = _effect(_lane_json())
	# lead hold spans [10, 20) → 10 frames of left room; trailing hold [40, 60) → 20 right.
	var plan_l: Dictionary = CameraChannelClass.plan_move(ed, _ref(2), -999)
	var plan_r: Dictionary = CameraChannelClass.plan_move(ed, _ref(2), 999)
	_assert_eq(int(plan_l["delta"]), -10, "the left clamp is the lead hold's whole length")
	_assert_eq(int(plan_r["delta"]), 20, "the right clamp is the trailing hold's")

	var session = Session.new(ed)
	session.move_span(_ref(2), -999)
	var after := _ends(ed)
	_assert_eq(after[0], 10, "the event before the collapsed hold is still pinned")
	_assert_eq(after, [10, 30, 60],
		"…and the emptied hold is gone, so the span butts against that event (dec. 7)")


## A drawn tween hard against the span is a wall: shifting its end would re-time what it draws.
func _test_a_wedged_span_is_refused() -> void:
	var ed = _effect({"phase1": {"max_keyframe": 3, "keyframes": [
		{"index": 0, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 64, 0]},
		{"index": 1, "end_frame": 20, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 32, 0]},
		{"index": 2, "end_frame": 30, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 16, 0]},
	]}})
	var session = Session.new(ed)
	var plan: Dictionary = CameraChannelClass.plan_move(ed, _ref(1), 4)
	_assert_true(not plan.get("ok", false), "a span wedged between two drawn tweens is refused")
	_assert_true(String(plan["reason"]).contains("wedged"), "…in plan_move's own vocabulary")
	_assert_true(session.move_span(_ref(1), 4).is_empty(), "…and nothing is written")
	_assert_eq(_ends(ed), [10, 20, 30], "…so every end_frame is where it was")


## Event 0 owns `[0, end)` against the phase origin. LEFT is a wall — there is nothing before
## frame 0 to give up. RIGHT is not: the space in front of it is simply not stored yet, so the
## slide MANUFACTURES the hold that holds it (author: *"I should be able to move it right, and
## it would do a spacer to the left of it"*).
func _test_the_first_event_slides_right_by_growing_a_hold_at_the_origin() -> void:
	var ed = _effect(_lane_json())
	_assert_eq(int(CameraChannelClass.plan_move(ed, _ref(0), -4)["delta"]), 0,
		"the first event still cannot move LEFT — frame 0 is the wall")

	var res: Dictionary = Session.new(ed).move_span(_ref(0), 6)
	_assert_eq(int(res.get("delta", 0)), 6, "…but it slides RIGHT")
	_assert_eq(_ends(ed), [6, 16, 20, 40, 60],
		"a hold now owns [0,6), the span kept its 10-frame width, and the hold behind gave the 6 up")
	_assert_eq(int(res.get("event_index", -1)), 1,
		"the span's ordinal moved with the manufactured event in front of it")
	_assert_true(_is_hold(ed, 0), "the manufactured event is a MAP+zero HOLD — it renders as nothing")
	_assert_eq(_spacer_flags(ed).slice(0, 2), [true, false],
		"…and the score paints it as empty space with the moved span drawn beside it")


## The same mechanism where the wall is a DRAWN tween rather than the origin: the space in
## front is manufactured, and the drawn neighbour keeps its extent untouched.
func _test_a_drawn_left_neighbour_gets_a_manufactured_hold_too() -> void:
	var ed = _effect({"phase1": {"max_keyframe": 2, "keyframes": [
		{"index": 0, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 64, 0]},
		{"index": 1, "end_frame": 30, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 32, 0]},
		{"index": 2, "end_frame": 50, "channel_mask": 1, "source_mode": "MAP",
			"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]},
	]}})
	Session.new(ed).move_span(_ref(1), 8)
	_assert_eq(_ends(ed), [10, 18, 38, 50],
		"a hold owns [10,18), the span kept its 20 frames, and the trailing hold absorbed the 8")
	_assert_true(_is_hold(ed, 1), "the manufactured event is a hold")
	_assert_eq(_spacer_flags(ed), [false, true, false, true],
		"…so the drawn tween in front is untouched and the new space renders as nothing")


## Moving LEFT into a drawn right neighbour manufactures the hold on the OTHER side — the
## vacated frames have to belong to something, and it must not be the drawn tween.
func _test_a_drawn_right_neighbour_gets_the_manufactured_hold() -> void:
	var ed = _effect({"phase1": {"max_keyframe": 2, "keyframes": [
		{"index": 0, "end_frame": 20, "channel_mask": 1, "source_mode": "MAP",
			"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]},
		{"index": 1, "end_frame": 40, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 32, 0]},
		{"index": 2, "end_frame": 60, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 16, 0]},
	]}})
	Session.new(ed).move_span(_ref(1), -8)
	_assert_eq(_ends(ed), [12, 32, 40, 60],
		"the lead hold gave up 8, the span kept its 20, and a new hold owns the vacated [32,40)")
	_assert_true(_is_hold(ed, 2), "the manufactured event is a hold")
	_assert_eq(_spacer_flags(ed), [true, false, true, false],
		"…and the drawn tween behind still owns exactly [40,60)")


## The slide re-lowers the WHOLE phase table, so the guard that matters is that a sibling
## sub-channel lane comes back byte-identical.
func _test_a_sibling_lane_is_untouched() -> void:
	var ed = _effect({"phase1": {"max_keyframe": 4, "keyframes": [
		{"index": 0, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 64, 0]},
		{"index": 1, "end_frame": 20, "channel_mask": 1, "source_mode": "MAP",
			"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]},
		{"index": 2, "end_frame": 40, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 16, 0]},
		{"index": 3, "end_frame": 60, "channel_mask": 1, "source_mode": "MAP",
			"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]},
		{"index": 4, "end_frame": 25, "channel_mask": 2, "source_mode": "DIRECT",
			"interpolation": "LINEAR", "command_raw": 0x842, "position": [8, 0, 8]},
	]}})
	var before := _lane_ends(ed, "position")
	Session.new(ed).move_span(_ref(2), 6)
	_assert_eq(_lane_ends(ed, "position"), before, "the position lane is untouched by an angle move")
	_assert_eq(_lane_ends(ed, "angle"), [10, 26, 46, 60], "…and the angle lane slid its one span")


## Restore-then-reapply: many motions, one undo, and the pristine table comes back.
func _test_a_body_drag_is_one_undo() -> void:
	var ed = _effect(_lane_json())
	var pristine := _ends(ed)
	var session = Session.new(ed)
	var ref := _ref(2)
	session.begin_move(ref)
	for d in [3, 14, -8, 6]:
		session.move_preview(ref, d)
	session.end_move()
	_assert_eq(_ends(ed), [10, 26, 46, 60], "the drag settled on its LAST position, not the sum")
	_assert_true(session.undo(), "the whole gesture is one undo")
	_assert_eq(_ends(ed), pristine, "…restoring the pristine table")
	_assert_true(not session.undo(), "…and there is nothing more to undo")


## STRUCTURE-FREE, the camera arm (ADR-0089's 2026-08-20 amendment, extended past the colour
## kinds). Mid-drag not one keyframe moves: every motion asks `plan_move` — which is already
## pure — how far the slide would go, and stops there. The page draws the span at that offset.
##
## Camera's per-motion apply was never SLOW the way colour's was (~3ms against colour's ~83ms
## on E317), so this is not a performance fix. It is the churn: the apply MANUFACTURES a lead
## hold, DELETES an emptied one and RENUMBERS the lane, so the ordinal the author grabbed named
## a different event one motion later and the selection was chased across the lane underneath
## the cursor. One gesture now renumbers exactly once.
func _test_the_motion_path_touches_no_keyframe() -> void:
	var ed = _effect(_lane_json())
	var pristine := _table_fingerprint(ed)
	var session = Session.new(ed)
	var ref := _ref(2)

	session.begin_move(ref)
	var offered := false
	for d in [3, 14, -8, 6]:
		var res: Dictionary = session.move_preview(ref, d)
		offered = offered or int(res.get("delta", 0)) != 0
		_assert_eq(_table_fingerprint(ed), pristine,
			"motion %+d leaves the camera table byte-identical to the grab" % d)
	_assert_true(offered, "…and the drag was a LIVE one: the planner offered a real slide")
	session.end_move()


## Release is the only splice, and it is where the lane's single renumber is reported — camera
## manufactures and deletes holds, so the landed ORDINAL is not the grabbed one.
func _test_release_applies_exactly_once_and_reports_the_landing() -> void:
	var ed = _effect(_lane_json())
	var pristine := _table_fingerprint(ed)
	var session = Session.new(ed)
	var ref := _ref(2)
	session.begin_move(ref)
	for d in [3, 14, -8, 6]:
		session.move_preview(ref, d)
	var landed: Dictionary = session.end_move()

	var direct = _effect(_lane_json())
	var committed: Dictionary = Session.new(direct).move_span(_ref(2), 6)
	_assert_eq(_table_fingerprint(ed), _table_fingerprint(direct),
		"release commits exactly what the discrete verb commits at the final delta")
	_assert_eq(int(landed.get("event_index", -1)), int(committed.get("event_index", -2)),
		"…and reports the same landed ordinal the discrete verb reports")
	_assert_true(session.undo(), "the whole gesture is still one undo")
	_assert_eq(_table_fingerprint(ed), pristine, "…restoring the pristine table")


## Every byte of the phase table a Move can touch, in index order. Deliberately not just the
## end_frames: the slide manufactures holds and re-lowers the whole stream, so a stray
## per-motion write could preserve the boundaries while rewriting the commands under them.
func _table_fingerprint(ed) -> String:
	var out: Array = []
	for kf in ed.camera.get_table("phase1").keyframes:
		out.append("%d/%d/%d/%s/%s/%s" % [int(kf.end_frame), int(kf.command_raw),
			int(kf.channel_mask), str(kf.angle), str(kf.position), str(kf.zoom)])
	return ",".join(out)


# --- fixtures -------------------------------------------------------------

## An angle lane of four events: a drawn pan, a MAP+zero HOLD, the drawn span under test, and
## a trailing MAP+zero HOLD. Spans: [0,10) drawn, [10,20) hold, [20,40) the mover, [40,60) hold.
## ADR-0101 decision 7 on the camera lane: "dragging into a hold run collapses it and DELETES
## the emptied keyframes, freeing their slots". Camera shrank the lead hold to zero width and
## left the keyframe sitting there. Invisible in the lane (`_camera_spans` only emits
## `end > prev_end`) — but it is a real opcode: it holds a native SoA slot, it shows as a marker
## on the read-only compiled lane, and it shifts every later event's ordinal by one.
func _test_an_emptied_lead_hold_is_deleted_not_left_at_zero_width() -> void:
	var ed = _effect(_lane_json())
	var session = Session.new(ed)
	var before: int = _kf_count(ed)
	_assert_true(_is_hold(ed, 1), "fixture: the lead of span 2 is a hold")

	# Slide span 2 hard LEFT: its lead hold [10,20) gives up all 10 frames and empties.
	var res: Dictionary = session.move_span(_ref(2), -9999)
	_assert_eq(int(res.get("delta", 0)), -10, "the slide took the lead hold's whole span")
	_assert_eq(_ends(ed), [10, 30, 60], "the emptied hold is GONE from the lane")
	_assert_eq(_kf_count(ed), before - 1, "…and its keyframe with it — the slot is freed")
	_assert_eq(int(res.get("event_index", -1)), 1,
		"the span reports the ordinal it actually landed on (the delete renumbered it)")


## The mirror: sliding RIGHT empties the hold BEHIND, and it must go the same way. A guard
## aimed only at the lead would ship a fix that leaves half the orphans behind.
func _test_an_emptied_TRAIL_hold_is_deleted_too() -> void:
	var ed = _effect(_lane_json())
	var session = Session.new(ed)
	var before: int = _kf_count(ed)
	_assert_true(_is_hold(ed, 3), "fixture: the trail of span 2 is a hold")

	var res: Dictionary = session.move_span(_ref(2), 9999)
	_assert_eq(int(res.get("delta", 0)), 20, "the slide took the trail hold's whole span")
	_assert_eq(_ends(ed), [10, 40, 60], "the emptied trail hold is GONE")
	_assert_eq(_kf_count(ed), before - 1, "…and its keyframe with it")


## THE AUTHOR'S REPORT, stated as an invariant: Move it away, Move it all the way back, and the
## STORAGE must be what it was — not merely what it looked like. The manufactured spacer is the
## Move's own scaffolding; leaving it behind at zero width means every round trip permanently
## costs a keyframe, renumbers the lane, and drops an orphan opcode on the compiled view.
func _test_the_round_trip_restores_the_STORAGE_not_just_the_picture() -> void:
	# The reported shape: a DRAWN event owning the phase origin, a hold behind it to slide into.
	var ed = _effect({"phase1": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 64, 0]},
		{"index": 1, "end_frame": 60, "channel_mask": 1, "source_mode": "MAP",
			"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]},
	]}})
	var session = Session.new(ed)
	var ends0 := _ends(ed)
	var count0: int = _kf_count(ed)

	var out: Dictionary = session.move_span(_ref(0), 6)
	_assert_eq(int(out.get("delta", 0)), 6, "the first event slides right")
	_assert_eq(_ends(ed), [6, 16, 60], "…by manufacturing the spacer that owns the space it left")
	_assert_eq(_kf_count(ed), count0 + 1, "…which costs one keyframe while it exists")

	# All the way back to the phase origin — the for_each boundary in the author's case.
	var back: Dictionary = session.move_span(_ref(1), -6)
	_assert_eq(int(back.get("delta", 0)), -6, "the slide home is not clamped short")
	_assert_eq(_ends(ed), ends0, "the lane's ends are exactly what they were")
	_assert_eq(_kf_count(ed), count0,
		"the manufactured spacer is DELETED, not left at zero width (ADR-0101 dec. 7)")
	_assert_eq(int(back.get("event_index", -1)), 0,
		"…so the event is ordinal 0 again, the address it started on")


## Live keyframes in the phase table — the count the native SoA slots are measured against.
func _kf_count(ed) -> int:
	var t = ed.camera.get_table("phase1")
	return mini(t.keyframes.size(), t.max_keyframe + 1)


func _lane_json() -> Dictionary:
	return {"phase1": {"max_keyframe": 3, "keyframes": [
		{"index": 0, "end_frame": 10, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 64, 0]},
		{"index": 1, "end_frame": 20, "channel_mask": 1, "source_mode": "MAP",
			"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]},
		{"index": 2, "end_frame": 40, "channel_mask": 1, "source_mode": "CASTER",
			"interpolation": "LINEAR", "command_raw": 0x941, "angle": [0, 16, 0]},
		{"index": 3, "end_frame": 60, "channel_mask": 1, "source_mode": "MAP",
			"interpolation": "LINEAR", "command_raw": 0x8C1, "angle": [0, 0, 0]},
	]}}


func _ref(ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "phase1", "camera_channel": "angle",
		"ordinal": ordinal}


func _ends(ed) -> Array:
	return _lane_ends(ed, "angle")


func _lane_ends(ed, lane_name: String) -> Array:
	var out: Array = []
	for ev in CameraLoweringClass.parse(ed.camera.get_table("phase1")).get(lane_name, []):
		out.append(int(ev["end_frame"]))
	return out


## Is the ordinal-th angle event a HOLD by the local predicate (MAP + zero value)?
func _is_hold(ed, ordinal: int) -> bool:
	var table = ed.camera.get_table("phase1")
	var events: Array = CameraLoweringClass.parse(table).get("angle", [])
	if ordinal < 0 or ordinal >= events.size():
		return false
	var kf = table.keyframes[int(events[ordinal]["origin_index"])]
	return String(kf.source_mode) == "MAP" and events[ordinal]["value"] == Vector3i.ZERO


## The `fields.spacer` the SCORE stamps on each angle span, in lane order — what the painter
## actually hides, as opposed to what the planner believes.
func _spacer_flags(ed) -> Array:
	var out: Array = []
	for lane in Model.build(ed).get("lanes", []):
		if String(lane.get("id", "")) == "camera:phase1:angle":
			for sp in lane.get("spans", []):
				out.append(bool(sp.get("fields", {}).get("spacer", false)))
	return out


func _effect(camera_json: Dictionary):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json(camera_json)
	return ed


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
