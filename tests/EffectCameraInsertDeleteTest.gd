extends Node
## TDD guard for the ADD / DELETE camera lane-editing verbs (ADR-0086 dec. 7, #287-adjacent). The author edits LANES: `insert_event` adds an event
## to a sub-channel lane, `delete_event` removes one; `CameraLowering.lower` decides
## packing (coalesce vs split) automatically. These are NOT the ADR-0086 de-coalesce
## split — this is the INSERT-WAYPOINT verb (cut a span in TIME) and its inverse.
##
## Everything is asserted SEMANTICALLY — parse the lane and check the event at its
## `(camera_channel, ordinal)` address (§#286) — never by a raw keyframe count, which
## `lower` renumbers (drops mask==0 pads, may coalesce).
##
## Seam (slice 1): CameraChannel.insert_event / delete_event — the camera encoder,
## which the #255 EffectEditSession choke point delegates to (wired in slice 2).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraInsertDeleteTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const CameraChannel = preload("res://src/effects/studio/CameraChannel.gd")

const SRC_MAP := 0x0C0
const INTERP_COSINE_A := 0x0400

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_insert_into_an_empty_lane_creates_its_first_event()
	_test_insert_into_a_span_cuts_it_with_an_interpolated_seed()
	_test_delete_a_waypoint_removes_it_and_respans_the_neighbours()
	_test_delete_the_sole_event_empties_the_lane()
	_test_insert_that_coincides_and_agrees_with_a_sibling_coalesces()

	print("\n=== EffectCameraInsertDeleteTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraInsertDeleteTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraInsertDeleteTest")
		get_tree().quit(0)


# --- Slice 1a: insert into a fully unused sub-channel lane -------------------

## A for_each with a single angle-only keyframe: the ZOOM lane is empty. Inserting a
## zoom event at frame 15 must CREATE the lane's first event (seed from lane defaults),
## structural so the host re-projects, without perturbing the angle lane.
func _test_insert_into_an_empty_lane_creates_its_first_event() -> void:
	var data = _effect_with_solo_angle_kf()

	var res: Dictionary = CameraChannel.insert_event(data, _at("zoom", 15))

	_assert_eq(res.get("structural", false), true, "an insert restructures (host re-projects)")

	var table = data.camera.get_table("for_each")
	var lanes: Dictionary = CameraLowering.parse(table)
	_assert_eq(lanes["zoom"].size(), 1, "the zoom lane gained its first event")
	_assert_eq(lanes["zoom"][0]["end_frame"], 15, "the new zoom event lands at frame 15")
	_assert_eq(lanes["angle"].size(), 1, "the angle lane is untouched")
	_assert_eq(lanes["angle"][0]["end_frame"], 10, "the angle event keeps its frame")


# --- Slice 1b: insert inside a span (the insert-waypoint) -------------------

## The headline verb: cutting a covering span at frame F seeds the new event with the
## value INTERPOLATED at F along that span (a visual no-op) and INHERITS the cut span's
## command word. Fixture: a DIRECT/LINEAR angle lane ramping (0,0,0)@10 → (100,0,0)@20.
## Inserting at frame 14 must cut span [10,20): fraction (14-10)/(20-10)=0.4, so the
## worked-by-hand LINEAR value is (40,0,0). The new event is ordinal 1 (between 10 and
## 20); the neighbour @20 keeps (100,0,0). NOT the de-coalesce split — one lane throughout.
func _test_insert_into_a_span_cuts_it_with_an_interpolated_seed() -> void:
	var data = _effect_with_direct_linear_angle_ramp()

	var res: Dictionary = CameraChannel.insert_event(data, _at("angle", 14))

	_assert_eq(res.get("structural", false), true, "the span cut is structural")
	_assert_eq(res.get("ordinal", -1), 1, "selection lands on the new event (ordinal 1)")

	var lanes: Dictionary = CameraLowering.parse(data.camera.get_table("for_each"))
	_assert_eq(lanes["angle"].size(), 3, "the two-event ramp gained a middle waypoint")
	_assert_eq(lanes["angle"][1]["end_frame"], 14, "the new waypoint sits at frame 14")
	_assert_eq(lanes["angle"][1]["value"], Vector3i(40, 0, 0),
		"seed = LINEAR-interpolated value at F (worked by hand: lerp((0,0,0),(100,0,0),0.4))")
	_assert_eq(lanes["angle"][1]["interp_bits"], 0x0800, "inherited LINEAR from the cut span")
	_assert_eq(lanes["angle"][1]["source_bits"], 0x040, "inherited DIRECT source from the cut span")
	_assert_eq(lanes["angle"][2]["end_frame"], 20, "the neighbour keeps its end frame")
	_assert_eq(lanes["angle"][2]["value"], Vector3i(100, 0, 0), "the neighbour target is unchanged")


# --- Slice 1c: delete a waypoint (the inverse) ------------------------------

## Delete is the inverse of insert-waypoint: removing the middle event of a three-event
## angle lane (ends 10 / 14 / 20) leaves two events (10 / 20) — the neighbour @20 just
## re-spans back over the gap. Addressed by `(camera_channel, ordinal)`; structural, and
## selection lands on the previous neighbour (ordinal 0).
func _test_delete_a_waypoint_removes_it_and_respans_the_neighbours() -> void:
	var data = _effect_with_three_event_angle_lane()

	var res: Dictionary = CameraChannel.delete_event(data, _ord("angle", 1))

	_assert_eq(res.get("structural", false), true, "a delete is structural (host re-projects)")
	_assert_eq(res.get("ordinal", -1), 0, "selection lands on the previous neighbour")

	var lanes: Dictionary = CameraLowering.parse(data.camera.get_table("for_each"))
	_assert_eq(lanes["angle"].size(), 2, "the middle waypoint is gone")
	_assert_eq(lanes["angle"][0]["end_frame"], 10, "the first event is untouched")
	_assert_eq(lanes["angle"][1]["end_frame"], 20, "the neighbour re-spans back over the gap")
	_assert_eq(lanes["angle"][1]["value"], Vector3i(100, 0, 0), "the neighbour target is unchanged")


## Deleting the sole event of a lane empties it — nothing remains to select (ordinal -1).
func _test_delete_the_sole_event_empties_the_lane() -> void:
	var data = _effect_with_solo_angle_kf()

	var res: Dictionary = CameraChannel.delete_event(data, _ord("angle", 0))

	_assert_eq(res.get("structural", false), true, "emptying a lane is structural")
	_assert_eq(res.get("ordinal", 0), -1, "an empty lane has nothing to select")
	var lanes: Dictionary = CameraLowering.parse(data.camera.get_table("for_each"))
	_assert_eq(lanes["angle"].size(), 0, "the angle lane is now empty")


## Coalesce-on-add is bounded (ADR-0086): an inserted event only shares a storage
## keyframe with a sibling when it COINCIDES (exact frame) AND AGREES (same command
## word). A zoom event inserted at frame 15 — the exact frame of a TARGET/LINEAR angle
## event whose word the default seed matches — lowers into ONE mask=5 (angle+zoom)
## keyframe. The author edited a lane; the packer reacted. Asserted by the compiled mask,
## never by count alone.
func _test_insert_that_coincides_and_agrees_with_a_sibling_coalesces() -> void:
	var data = _effect_with_target_linear_angle_at_15()

	CameraChannel.insert_event(data, _at("zoom", 15))

	var table = data.camera.get_table("for_each")
	var live: int = mini(table.keyframes.size(), table.max_keyframe + 1)
	_assert_eq(live, 1, "the coincident-and-agreeing events share ONE storage keyframe")
	_assert_eq(int(table.keyframes[0].channel_mask), 5, "the shared keyframe carries angle+zoom")

	var lanes: Dictionary = CameraLowering.parse(table)
	_assert_eq(lanes["angle"].size(), 1, "the angle event survives the coalesce")
	_assert_eq(lanes["zoom"].size(), 1, "the zoom event survives the coalesce")


# --- fixtures ---------------------------------------------------------------

## A camera insert address: which lane (context + camera_channel) and the frame.
func _at(camera_channel: String, frame: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each",
		"camera_channel": camera_channel, "frame": frame}


## A camera delete address: which lane + the event's ordinal within it (§#286).
func _ord(camera_channel: String, ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each",
		"camera_channel": camera_channel, "ordinal": ordinal}


## for_each with ONE angle-only (mask=1) keyframe @ end 10; position + zoom lanes empty.
func _effect_with_solo_angle_kf():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 0, "keyframes": [{
		"index": 0, "end_frame": 10,
		"angle": [1, 2, 3], "position": [0, 0, 0], "zoom": [0, 0, 0],
		"command_raw": 0x04C1, "channel_mask": 1,
		"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0,
	}]}})
	return data


## for_each with a DIRECT/LINEAR angle ramp: two solo angle keyframes (mask=1),
## (0,0,0)@10 → (100,0,0)@20. cmd = interp LINEAR 0x0800 | source DIRECT 0x040 | mask 1.
func _effect_with_direct_linear_angle_ramp():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 10,
			"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 20,
			"angle": [100, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
	]}})
	return data


## for_each with THREE solo angle keyframes (mask=1) at ends 10 / 14 / 20 — a ramp with
## a middle waypoint. Deleting the middle collapses back to the two-event ramp.
func _effect_with_three_event_angle_lane():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 2, "keyframes": [
		{"index": 0, "end_frame": 10,
			"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 14,
			"angle": [40, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 2, "end_frame": 20,
			"angle": [100, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
	]}})
	return data


## for_each with ONE angle-only keyframe @ end 15, source TARGET / interp LINEAR / param 0
## / flags 0 — exactly the default seed a fresh insert carries. cmd = 0x0800 | 0x000 | 1.
func _effect_with_target_linear_angle_at_15():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 0, "keyframes": [{
		"index": 0, "end_frame": 15,
		"angle": [7, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
		"command_raw": 0x0801, "channel_mask": 1,
		"source_mode": "TARGET", "interpolation": "LINEAR", "param_index": 0, "flags": 0,
	}]}})
	return data


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
