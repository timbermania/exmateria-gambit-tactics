extends Node
## TDD guard for the STRUCTURAL camera verbs through the #255 choke point + their
## snapshot-based undo (ADR-0086 dec. 7). `apply_edit`'s undo replays a scalar
## `before_raw`; insert/delete have no scalar inverse, so `EffectEditSession` records a
## SNAPSHOT of the pre-edit camera phase table and `undo()` restores it — on the SAME
## stack Ctrl+Z drives. The hybrid: scalar edits keep the fast before_raw path; only
## insert/delete snapshot, so the four other channels' proven paths are untouched.
##
## Seam: EffectEditSession.insert_event / delete_event / undo (the ONE choke point).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraStructuralUndoTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_insert_through_the_session_then_undo_restores_the_lane()
	_test_delete_through_the_session_then_undo_restores_the_event()
	_test_hybrid_stack_unwinds_scalar_then_structural_in_lifo()

	print("\n=== EffectCameraStructuralUndoTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraStructuralUndoTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraStructuralUndoTest")
		get_tree().quit(0)


## An insert flows through the choke point (structural), and a single undo restores the
## exact pre-insert lane — the added zoom event is gone, the angle lane intact.
func _test_insert_through_the_session_then_undo_restores_the_lane() -> void:
	var data = _effect_with_solo_angle_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.insert_event(_at("zoom", 15))
	_assert_eq(res.get("structural", false), true, "the session routes insert as structural")
	_assert_eq(_lane_size(data, "zoom"), 1, "the zoom event was added")

	_assert_eq(session.undo(), true, "undo reports it unwound the insert")
	_assert_eq(_lane_size(data, "zoom"), 0, "the inserted zoom event is gone after undo")
	_assert_eq(_lane_size(data, "angle"), 1, "the angle lane is intact after undo")


## A delete flows through the choke point, and undo restores the removed waypoint — value
## and all. Snapshot undo, not a scalar replay (there is no scalar inverse for a delete).
func _test_delete_through_the_session_then_undo_restores_the_event() -> void:
	var data = _effect_with_three_event_angle_lane()
	var session = EffectEditSession.new(data)

	session.delete_event(_ord("angle", 1))
	_assert_eq(_lane_size(data, "angle"), 2, "the middle waypoint was deleted")

	_assert_eq(session.undo(), true, "undo reports it unwound the delete")
	_assert_eq(_lane_size(data, "angle"), 3, "the deleted waypoint is back")
	var lanes: Dictionary = CameraLowering.parse(data.camera.get_table("for_each"))
	_assert_eq(lanes["angle"][1]["value"], Vector3i(40, 0, 0),
		"the restored waypoint kept its value")


## The hybrid stack: a structural insert then a scalar value edit, undone in LIFO order —
## the scalar replay first, then the snapshot restore — returns to the exact original. The
## scalar edit never snapshots (its proven fast path is untouched); the insert never scalar-
## replays. A third undo finds nothing.
func _test_hybrid_stack_unwinds_scalar_then_structural_in_lifo() -> void:
	var data = _effect_with_solo_angle_kf()
	var session = EffectEditSession.new(data)

	session.insert_event(_at("zoom", 15))               # structural (snapshot)
	session.apply_edit(_val("angle", "angle_x", 0), 99) # scalar (before_raw)

	_assert_eq(session.undo(), true, "first undo unwinds the scalar edit")
	_assert_eq(session.undo(), true, "second undo unwinds the structural insert")

	var lanes: Dictionary = CameraLowering.parse(data.camera.get_table("for_each"))
	_assert_eq(lanes["zoom"].size(), 0, "the inserted zoom event is gone")
	_assert_eq(lanes["angle"].size(), 1, "the angle lane is back to one event")
	_assert_eq(lanes["angle"][0]["value"], Vector3i(1, 2, 3),
		"the scalar angle_x edit was reverted to the original value")
	_assert_eq(session.undo(), false, "a third undo finds an empty stack")


# --- helpers / fixtures -----------------------------------------------------

func _lane_size(data, lane_name: String) -> int:
	return CameraLowering.parse(data.camera.get_table("for_each")).get(lane_name, []).size()


func _at(camera_channel: String, frame: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each",
		"camera_channel": camera_channel, "frame": frame}


func _ord(camera_channel: String, ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each",
		"camera_channel": camera_channel, "ordinal": ordinal}


## A scalar value edit address (a fast-path apply_edit, not a structural verb).
func _val(camera_channel: String, field: String, ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each",
		"camera_channel": camera_channel, "ordinal": ordinal, "field": field}


func _effect_with_solo_angle_kf():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 0, "keyframes": [{
		"index": 0, "end_frame": 10,
		"angle": [1, 2, 3], "position": [0, 0, 0], "zoom": [0, 0, 0],
		"command_raw": 0x04C1, "channel_mask": 1,
		"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0,
	}]}})
	return data


## for_each with THREE solo angle keyframes (mask=1) at ends 10 / 14 / 20.
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


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
