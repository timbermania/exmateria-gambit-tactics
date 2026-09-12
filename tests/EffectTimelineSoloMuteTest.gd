extends Node
## TDD guard for EffectScoreTimeline's per-lane SOLO / MUTE gutter buttons — the
## Effect Studio "isolate one lane" surface. Each lane row carries two small buttons
## in the (otherwise inert) label gutter: S (solo) and M (mute). This exercises the
## pure layout + hit_test seam plus the toggle state + change signal, no paint. See
## CONTEXT.md "Effect Studio".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectTimelineSoloMuteTest.tscn

const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_each_lane_has_solo_and_mute_buttons()
	_test_hit_test_routes_mute_and_solo()
	_test_press_toggles_mute_and_emits()
	_test_press_toggles_solo_and_emits()
	_test_solo_silences_other_lanes()
	_test_load_score_clears_solo_mute()

	print("\n=== EffectTimelineSoloMuteTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectTimelineSoloMuteTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectTimelineSoloMuteTest")
		get_tree().quit(0)


## Layout builds a solo AND a mute button rect for every visible lane row, each
## sitting inside the gutter (x < GUTTER_W).
func _test_each_lane_has_solo_and_mute_buttons() -> void:
	var tl = _timeline()
	var lanes: int = tl._lane_rows.size()
	_assert_true(lanes > 0, "the score has lanes")
	_assert_eq(tl._lane_button_rects.size(), lanes * 2, "two buttons (solo+mute) per lane row")
	var kinds := {}
	for b in tl._lane_button_rects:
		kinds[b["kind"]] = true
		_assert_true(b["rect"].position.x + b["rect"].size.x <= Timeline.GUTTER_W,
			"a lane button lives inside the gutter")
	_assert_true(kinds.has("mute") and kinds.has("solo"), "both button kinds are present")


## A click on a lane's mute button routes to a "mute" intent carrying its lane id;
## the solo button routes to "solo".
func _test_hit_test_routes_mute_and_solo() -> void:
	var tl = _timeline()
	var lane_id: String = tl._lane_rows[0]["lane"]["id"]
	var m := _button_center(tl, lane_id, "mute")
	var s := _button_center(tl, lane_id, "solo")
	var hm = tl.hit_test(m)
	var hs = tl.hit_test(s)
	_assert_eq(hm["kind"], "mute", "clicking the mute button routes to a mute intent")
	_assert_eq(hm["lane_id"], lane_id, "the mute intent carries the lane id")
	_assert_eq(hs["kind"], "solo", "clicking the solo button routes to a solo intent")
	_assert_eq(hs["lane_id"], lane_id, "the solo intent carries the lane id")


## A real left-press on the mute button toggles the lane's mute and fires
## lane_audibility_changed; pressing again un-mutes.
func _test_press_toggles_mute_and_emits() -> void:
	var tl = _timeline()
	var lane_id: String = tl._lane_rows[0]["lane"]["id"]
	var seen := {"count": 0}
	tl.lane_audibility_changed.connect(func(): seen["count"] += 1)
	_press(tl, _button_center(tl, lane_id, "mute"))
	_assert_true(tl.is_lane_muted(lane_id), "pressing M mutes the lane")
	_assert_eq(seen["count"], 1, "muting fires lane_audibility_changed once")
	_press(tl, _button_center(tl, lane_id, "mute"))
	_assert_true(not tl.is_lane_muted(lane_id), "pressing M again un-mutes the lane")
	_assert_eq(seen["count"], 2, "un-muting fires the signal again")


## Solo behaves the same way through a press.
func _test_press_toggles_solo_and_emits() -> void:
	var tl = _timeline()
	var lane_id: String = tl._lane_rows[0]["lane"]["id"]
	var seen := {"count": 0}
	tl.lane_audibility_changed.connect(func(): seen["count"] += 1)
	_press(tl, _button_center(tl, lane_id, "solo"))
	_assert_true(tl.is_lane_soloed(lane_id), "pressing S solos the lane")
	_assert_eq(seen["count"], 1, "soloing fires lane_audibility_changed once")


## The DAW rule surfaced on the control: soloing one lane marks every OTHER lane
## silenced (the gutter dims their labels), the soloed one stays audible.
func _test_solo_silences_other_lanes() -> void:
	var tl = _timeline()
	var a: String = tl._lane_rows[0]["lane"]["id"]
	var b: String = tl._lane_rows[1]["lane"]["id"]
	tl.toggle_solo(a)
	_assert_true(not tl.is_lane_silenced(a), "the soloed lane is audible")
	_assert_true(tl.is_lane_silenced(b), "an un-soloed lane is silenced while a solo is active")


## Loading a new score clears the old solo/mute (lane ids differ per effect).
func _test_load_score_clears_solo_mute() -> void:
	var tl = _timeline()
	tl.toggle_mute(tl._lane_rows[0]["lane"]["id"])
	tl.toggle_solo(tl._lane_rows[1]["lane"]["id"])
	_assert_true(not tl.muted_lanes().is_empty(), "precondition: something muted")
	tl.load_score(tl._score)   # reload same shape → fresh document
	_assert_true(tl.muted_lanes().is_empty(), "load_score clears mute")
	_assert_true(tl.soloed_lanes().is_empty(), "load_score clears solo")


# --- fixtures / helpers ---------------------------------------------------

func _press(tl, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	tl._gui_input(ev)

func _timeline():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 40, "emitter_id": 2}]},
			{"context": "for_each", "channel_index": 1, "max_keyframe": 0, "keyframes": []},
		],
	})
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	return tl


func _button_center(tl, lane_id: String, kind: String) -> Vector2:
	for b in tl._lane_button_rects:
		if b["lane_id"] == lane_id and b["kind"] == kind:
			return b["rect"].position + b["rect"].size * 0.5
	return Vector2(-1, -1)


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
