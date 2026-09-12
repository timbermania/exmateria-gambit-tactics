extends Node
## TDD guard for the ADR-0085 "every event is accessible via a timeline handle"
## amendment — the sound-lane bijection. The score projection (EffectScoreModel) must
## surface ONE selectable handle per sound EVENT over the live window `[0, max_keyframe)`
## (audible or not — a silent event is an event that emits no new sound, not a rest),
## plus exactly ONE inert terminator end-cap at index `max_keyframe`. `max_keyframe == 0`
## and padding slots (index > max_keyframe) project nothing. The tail (ghost/energy) is
## the SOLE tell of sound: a silent event's handle carries no ghost, and a TERMINATOR
## carries no ghost even if its slot's sound_id looks audible (the runtime never fires it).
##
## This is the honest-projection invariant: the audible-only filter that used to live
## inside _sound_spans is gone; the few audible-only concerns (ghost/energy) fall out of
## the ghost maps, which only map sound_id >= 2. Asserted over the real E317 sound bank
## (heavy skips + a long silent tail) and synthetic edge lanes.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectSoundEventHandleBijectionTest.tscn

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_e317_for_each_0_bijection()
	_test_e317_all_lanes_bijection()
	_test_all_skip_max_kf_1_lane_shows_event_and_terminator()
	_test_max_keyframe_zero_projects_nothing()
	_test_padding_projects_nothing()
	_test_terminator_never_carries_a_tail()

	print("\n=== EffectSoundEventHandleBijectionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSoundEventHandleBijectionTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSoundEventHandleBijectionTest")
		get_tree().quit(0)


## E317 for_each:0 is the canonical case from the design (phase offset 8, max_keyframe 5,
## sids [0,2,0,3,0] — three skips + two fires): 5 EVENT handles on the absolute axis at
## 8/22/33/48/64, all role "event", then ONE terminator end-cap at 8+600 = 608.
func _test_e317_for_each_0_bijection() -> void:
	var score := _e317_score()
	if score.is_empty():
		print("[SKIP] E317 assets absent")
		return
	var lane := _lane(score, "sound:for_each:0")
	_assert_true(not lane.is_empty(), "E317 builds sound:for_each:0")

	var events := _spans_with_role(lane, "event")
	var terms := _spans_with_role(lane, "terminator")
	_assert_eq(events.size(), 5, "for_each:0 projects one handle per live event (max_keyframe 5)")
	_assert_eq(terms.size(), 1, "for_each:0 projects exactly one terminator")

	var frames: Array = []
	for e in events:
		frames.append(int(e["start"]))
	frames.sort()
	_assert_eq(frames, [8, 22, 33, 48, 64], "every event handle lands on its true fire frame (audible or silent)")

	var indices: Array = []
	for e in events:
		indices.append(int(e["keyframe_index"]))
	indices.sort()
	_assert_eq(indices, [0, 1, 2, 3, 4], "event handles address indices 0..max_keyframe-1")

	var term: Dictionary = terms[0]
	_assert_eq(int(term["keyframe_index"]), 5, "terminator is addressed at index == max_keyframe")
	_assert_eq(int(term["start"]), 608, "terminator sits at its true frame (last fire + last gap = 8 + 600)")
	_assert_eq(int(term.get("ghost_frames", 0)), 0, "terminator carries no ghost tail")
	_assert_eq(term["id"], "sound:for_each:0#5", "terminator id is stable (lane#max_keyframe)")


## Every sound lane in E317 obeys the bijection: events == mini(kfs.size, max_keyframe),
## exactly one terminator (all E317 lanes have max_keyframe >= 1), no span past the
## terminator index.
func _test_e317_all_lanes_bijection() -> void:
	var score := _e317_score()
	if score.is_empty():
		return
	var checked := 0
	for lane in score.get("lanes", []):
		if lane.get("kind", "") != "sound":
			continue
		checked += 1
		var events := _spans_with_role(lane, "event")
		var terms := _spans_with_role(lane, "terminator")
		# The live window count from the lane id → the raw channel (max_keyframe clamp).
		var mk := _max_keyframe_for(lane)
		_assert_eq(events.size(), mk, "%s: one handle per live event" % lane["id"])
		_assert_eq(terms.size(), 1 if mk >= 1 else 0, "%s: one terminator when max_keyframe>=1" % lane["id"])
		# No span addresses a padding slot (index > max_keyframe).
		var over := 0
		for span in lane["spans"]:
			if int(span.get("keyframe_index", 0)) > mk:
				over += 1
		_assert_eq(over, 0, "%s: no span addresses a padding slot" % lane["id"])
	_assert_true(checked >= 7, "E317 exercises every sound lane (7: 3 phase1 + 3 for_each + phase2/...)")


## An all-skip lane with max_keyframe == 1 (E317's phase1:0 is sid 0, dur 600) still shows
## its single event handle + a terminator — the rule is uniform across lanes, and a
## silent-only lane is not invisible (decision 5).
func _test_all_skip_max_kf_1_lane_shows_event_and_terminator() -> void:
	var score := _e317_score()
	if score.is_empty():
		return
	var lane := _lane(score, "sound:phase1:0")
	_assert_true(not lane.is_empty(), "E317 builds the all-skip sound:phase1:0 lane")
	_assert_eq(_spans_with_role(lane, "event").size(), 1, "a lone silent event still projects a handle")
	_assert_eq(_spans_with_role(lane, "terminator").size(), 1, "and its terminator end-cap")


## max_keyframe == 0 → no events, and no terminator (a lone end-cap would point at nothing).
func _test_max_keyframe_zero_projects_nothing() -> void:
	var ed = _effect_with_timeline(8, 83)
	ed.sound = {"for_each": [
		{"channel_index": 0, "max_keyframe": 0, "keyframes": [
			{"duration_frames": 10, "sound_id": 5}]},
	]}
	var lane := _lane(Model.build(ed), "sound:for_each:0")
	_assert_true(not lane.is_empty(), "the lane exists even at max_keyframe 0")
	_assert_eq(lane["spans"].size(), 0, "max_keyframe 0 projects no handles and no terminator")


## Padding past the terminator index is never a handle (E077-class phantom guard, sound side).
func _test_padding_projects_nothing() -> void:
	var ed = _effect_with_timeline(8, 83)
	ed.sound = {"for_each": [
		{"channel_index": 0, "max_keyframe": 2, "keyframes": [
			{"duration_frames": 6, "sound_id": 5},   # 0 event
			{"duration_frames": 4, "sound_id": 7},   # 1 event
			{"duration_frames": 3, "sound_id": 9},   # 2 terminator
			{"duration_frames": 0, "sound_id": 0},   # 3 padding — never drawn
			{"duration_frames": 0, "sound_id": 0}]},  # 4 padding — never drawn
	]}
	var lane := _lane(Model.build(ed), "sound:for_each:0")
	_assert_eq(_spans_with_role(lane, "event").size(), 2, "two live events (indices 0,1)")
	_assert_eq(_spans_with_role(lane, "terminator").size(), 1, "one terminator (index 2)")
	_assert_eq(lane["spans"].size(), 3, "padding indices 3,4 project nothing")


## A terminator whose slot's sound_id LOOKS audible (>= 2) still carries no tail: the
## runtime never fires index == max_keyframe, so a ghost there would be a lie. The tail
## is the tell of a REAL fire, and the terminator is not one.
func _test_terminator_never_carries_a_tail() -> void:
	var ed = _effect_with_timeline(8, 83)
	ed.sound = {"for_each": [
		{"channel_index": 0, "max_keyframe": 1, "keyframes": [
			{"duration_frames": 12, "sound_id": 4},   # 0 event (fires)
			{"duration_frames": 5, "sound_id": 6}]},   # 1 terminator — slot sid 6 >= 2
	]}
	# Supply a ghost map that WOULD give sid 6 a tail if the terminator were treated as a fire.
	var score := Model.build(ed, {4: 20, 6: 30}, {})
	var lane := _lane(score, "sound:for_each:0")
	var events := _spans_with_role(lane, "event")
	var terms := _spans_with_role(lane, "terminator")
	_assert_eq(events.size(), 1, "one live event")
	_assert_eq(int(events[0].get("ghost_frames", 0)), 20, "the live event carries its projected tail")
	_assert_eq(terms.size(), 1, "one terminator")
	_assert_eq(int(terms[0].get("ghost_frames", 0)), 0, "the terminator carries NO tail even with an audible slot sid")


# --- helpers --------------------------------------------------------------

func _e317_score() -> Dictionary:
	var dir := "res://assets/effects/E317"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return {}
	var ed = EffectDataClass.load_from_directory(dir)
	return Model.build(ed)


func _effect_with_timeline(phase1_duration: int, phase2_delay: int):
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": phase1_duration, "phase2_delay": phase2_delay},
		"particle_channels": [],
	})
	return ed


func _spans_with_role(lane: Dictionary, role: String) -> Array:
	var out: Array = []
	for span in lane.get("spans", []):
		if str(span.get("role", "event")) == role:
			out.append(span)
	return out


## The clamped live-window size (mini(kfs.size, max_keyframe)) for a laid-out lane, read
## back off the score's own event handles + terminator so the guard doesn't re-read raw
## data the way the model does (independent source of truth = the design's frame table).
func _max_keyframe_for(lane: Dictionary) -> int:
	var terms := _spans_with_role(lane, "terminator")
	if terms.is_empty():
		return _spans_with_role(lane, "event").size()
	return int(terms[0]["keyframe_index"])


func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score.get("lanes", []):
		if lane["id"] == lane_id:
			return lane
	return {}


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
		print("[FAIL] %s" % label)
