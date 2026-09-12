extends Node
## TDD guard for the STRUCTURE-FREE colour Move drag (ADR-0089 Drag preview, generalised from
## particle to the colour kinds; ADR-0101 decision 3's gesture).
##
## THE RULE. Mid-drag a colour Move touches NO KEYFRAME. Every motion plans — so the page knows
## how far the slide is actually allowed and at what granularity — and then stops, leaving the
## channel byte-identical to the grab. The span tracks the cursor as GEOMETRY (the timeline draws
## it at `start + clamped_delta`); the splice happens exactly ONCE, on release.
##
## WHAT IT REPLACES. Every motion used to restore the grab snapshot, re-plan, mint/delete padding
## keyframes and renumber the lane — ~95ms per motion on E317, with the lane's edge-grip count
## oscillating 16 ↔ 23 as padding appeared and vanished under the cursor. None of that work
## survived: the next motion threw it away and re-planned from the same pristine snapshot. The
## drag was already stateless w.r.t. its own path (`_restore_move_pristine` + an ABSOLUTE delta);
## this makes the DATA stateless too, which is the same answer for a hundredth of the cost.
##
## The assertions that go RED against pre-fix code are the whole of `_test_the_motion_path_
## touches_no_keyframe` — pre-fix, motion #1 already re-encodes the lead run.
##
## Run: <GODOT> --path . res://tests/ColourStructureFreeDragTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

const EXPECTED_ASSERTIONS := 21

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_motion_path_touches_no_keyframe()
	_test_the_reported_delta_is_the_planners_clamp()
	_test_release_applies_exactly_once()
	_test_a_wandering_drag_lands_where_a_direct_one_does()
	_test_a_click_records_nothing()
	_test_a_refused_move_changes_nothing()
	_test_a_slide_dragged_back_onto_home_is_a_click()
	_test_release_reports_the_landed_address()

	var total: int = _passed + _failed
	if total != EXPECTED_ASSERTIONS:
		_failed += 1
		print("[FAIL] assertion count drifted — expected %d, ran %d" % [EXPECTED_ASSERTIONS, total])
	print("\n=== ColourStructureFreeDragTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ColourStructureFreeDragTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColourStructureFreeDragTest")
		get_tree().quit(0)


## THE regression. Three motions, each a different cursor position, and after every one of them
## the channel is byte-identical to the grab — not "equivalent", not "same total length", the
## same bytes. A single keyframe minted here is a lane renumber, a grip rebuild and (in the page)
## a spacer re-fold, per frame of cursor travel.
func _test_the_motion_path_touches_no_keyframe() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var pristine := _fingerprint(ch)
	var session = Session.new(data)
	var ref := _ref(2)

	session.begin_move(ref)
	var moved := false
	for d in [3, 11, 8]:
		var res: Dictionary = session.move_preview(ref, d)
		moved = moved or int(res.get("delta", 0)) != 0
		_assert_eq(_fingerprint(ch), pristine,
			"motion to %+d leaves every keyframe byte-identical to the grab" % d)
	_assert_true(moved, "…and the drag was a LIVE one: the planner offered a real slide")
	session.end_move()


## A structure-free motion still has to answer "how far, and at what granularity" — the page
## draws the span at `start + this`. The answer must be the planner's, not the cursor's, and it
## must be the SAME answer the discrete verb commits, or the preview lies about where release
## will land.
func _test_the_reported_delta_is_the_planners_clamp() -> void:
	for wanted in [11, 999]:
		var live = _fixture()
		var session = Session.new(live)
		session.begin_move(_ref(2))
		var previewed: int = int(session.move_preview(_ref(2), wanted).get("delta", 0))
		session.end_move()
		var discrete = _fixture()
		var committed: int = int(Session.new(discrete).move_span(_ref(2), wanted).get("delta", 0))
		_assert_eq(previewed, committed,
			"a %+d motion previews the delta the discrete verb commits (%+d)" % [wanted, committed])


## Release is the ONLY splice. Its result must be byte-identical to the discrete verb applied
## once at the drag's final delta — and it is one undo back to pristine.
func _test_release_applies_exactly_once() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var pristine := _fingerprint(ch)
	var session = Session.new(data)
	var ref := _ref(2)

	session.begin_move(ref)
	for d in [3, 11, 8]:
		session.move_preview(ref, d)
	session.end_move()

	var direct = _fixture()
	Session.new(direct).move_span(ref, 8)
	_assert_eq(_fingerprint(ch), _fingerprint(_chan(direct)),
		"release commits exactly what the discrete verb commits at the final delta")
	_assert_true(session.undo(), "the whole gesture is one undo")
	_assert_eq(_fingerprint(ch), pristine, "…restoring the pristine channel")


## The gesture stays stateless w.r.t. its own path. It always was at the model (every motion
## re-planned from the snapshot); now that no motion writes, the property is structural rather
## than maintained — but it is the property the author feels, so it stays pinned.
func _test_a_wandering_drag_lands_where_a_direct_one_does() -> void:
	var wandered = _fixture()
	var ws = Session.new(wandered)
	ws.begin_move(_ref(2))
	for d in [1, 7, -3, 16, 2, 8]:
		ws.move_preview(_ref(2), d)
	ws.end_move()

	var direct = _fixture()
	var ds = Session.new(direct)
	ds.begin_move(_ref(2))
	ds.move_preview(_ref(2), 8)
	ds.end_move()

	_assert_eq(_fingerprint(_chan(wandered)), _fingerprint(_chan(direct)),
		"a wandering drag lands exactly where a direct one does")
	var unwound: bool = ws.undo()
	_assert_true(unwound and not ws.undo()
			and _fingerprint(_chan(wandered)) == _fingerprint(_chan(_fixture())),
		"…and unwinds in ONE step, not one per motion crossed")


## A grab and release with no motion is a CLICK. It must not record an undo entry, and — now
## that nothing is written per motion — must not write on release either.
func _test_a_click_records_nothing() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var pristine := _fingerprint(ch)
	var session = Session.new(data)
	session.begin_move(_ref(2))
	session.end_move()
	_assert_eq(_fingerprint(ch), pristine, "a click leaves the channel untouched")
	_assert_true(not session.undo(), "…and records no undo entry")


## A span wedged between two DRAWN tweens has no frames to trade. The preview answers ZERO —
## deliberately not `{}`, which stays reserved for "there is no live gesture to address". The
## page draws the span at home either way, but only a refusal that carries a number can UNDO a
## slide the motion before it previewed: drag out eight frames, drag back onto home, and the
## span has to return. Release then has nothing to commit.
func _test_a_refused_move_changes_nothing() -> void:
	var data = _wedged_fixture()
	var ch = _chan(data)
	var pristine := _fingerprint(ch)
	var session = Session.new(data)
	session.begin_move(_ref(1))
	var pv: Dictionary = session.move_preview(_ref(1), 8)
	_assert_true(bool(pv.get("preview_only", false)) and int(pv.get("delta", -1)) == 0,
		"a wedged span's motion previews a slide of ZERO, not an empty answer")
	session.end_move()
	_assert_eq(_fingerprint(ch), pristine, "…and release commits nothing")


## Drag out, then drag back onto home. The span must RETURN, release must commit nothing, and
## the gesture must record no undo — a slide the author cancelled is a click.
##
## Pre-fix this fell out of restore-then-reapply for free: the delta-0 motion put the pristine
## snapshot back and applied nothing, so the data was already home. With the data untouched all
## gesture, the ZERO ANSWER is the only thing carrying it — which is why a refused motion has to
## report a number rather than an empty dictionary, and why `_move_delta` is overwritten by
## every motion instead of only by the ones that succeed.
func _test_a_slide_dragged_back_onto_home_is_a_click() -> void:
	var data = _fixture()
	var ch = _chan(data)
	var pristine := _fingerprint(ch)
	var session = Session.new(data)
	var ref := _ref(2)

	session.begin_move(ref)
	_assert_eq(int(session.move_preview(ref, 8).get("delta", 0)), 8,
		"the slide out is previewed")
	_assert_eq(int(session.move_preview(ref, 0).get("delta", -1)), 0,
		"…and dragging back onto home previews it away")
	session.end_move()
	_assert_eq(_fingerprint(ch), pristine, "release commits nothing")
	_assert_true(not session.undo(), "…and the cancelled gesture records no undo entry")


## The page re-selects on where the span ACTUALLY landed — a colour Move renumbers the lane, so
## the id the gesture started on names a different keyframe once the splice runs. Pre-fix the
## page chased that address every motion (`_follow_structural_move`); with the splice deferred
## there is exactly one address change and release is where it is reported.
func _test_release_reports_the_landed_address() -> void:
	var data = _fixture()
	var session = Session.new(data)
	var ref := _ref(2)
	session.begin_move(ref)
	session.move_preview(ref, 8)
	var landed: Dictionary = session.end_move()
	_assert_true(landed.has("event_index"),
		"release reports the moved span's new raw index")

	var direct = _fixture()
	var committed: Dictionary = Session.new(direct).move_span(ref, 8)
	_assert_eq(int(landed.get("event_index", -1)), int(committed.get("event_index", -2)),
		"…the same index the discrete verb reports")


# --- fixtures -------------------------------------------------------------

func _ref(index: int) -> Dictionary:
	return {"channel": "palette", "context": "for_each", "channel_name": "affected_units",
		"event_index": index}


func _chan(data):
	return data.palette.get_channel("for_each", "affected_units")


## Every byte the Move can touch, per keyframe, in index order. Deliberately NOT just the
## durations: the splice mints pads and copies holds, so a per-motion write could preserve the
## lengths while changing the tints or the ctrl bits under them.
func _fingerprint(ch) -> String:
	var out: Array = []
	for kf in ch.keyframes:
		out.append("%d/%d/%d,%d,%d/%d/%d" % [kf.time_value, kf.duration_frames, kf.rgb.x,
			kf.rgb.y, kf.rgb.z, kf.ctrl, 1 if kf.enabled else 0])
	return "max=%d|%s" % [int(ch.max_keyframe), ",".join(out)]


## Hold, SPAN, hold — the shape a Move needs on both sides. Index 1 repeats index 0 and index 3
## repeats index 2, so the real fold (not a stamp) calls both of them empty space.
func _fixture(used: int = 6):
	return _build([
		{"tv": 2, "rgb": [200, 40, 40]},
		{"tv": 2, "rgb": [200, 40, 40]},
		{"tv": 3, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 40, 200]},
		{"tv": 2, "rgb": [40, 200, 40]},
	], used)


## Three genuinely different tints, no repeats — the fold declares every one drawn, so the
## middle span has nowhere to go.
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


# --- harness --------------------------------------------------------------

func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % msg)


func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s\n       expected: %s\n       actual:   %s" % [msg, expected, actual])
