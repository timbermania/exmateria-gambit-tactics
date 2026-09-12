extends Node
## TDD guard for CAMERA RIPPLE (ADR-0087 decs. 15-16) — with the ripple flag on the
## field_ref, an end_frame edit is no longer a lone boundary write: the channel writes the
## edited event's end_frame and adds the delta to every DOWNSTREAM end_frame in the SAME
## sub-channel lane, so every later move keeps its width and shifts with the edit. Camera is
## endpoint-encoded, so this is a parse→shift→lower recompile (structural):
##   * a downstream keyframe that also drives OTHER sub-channels SPLITS out lane-locally —
##     sibling lanes never move (the §2 lane-local contract holds inside camera too),
##   * undo is the STRUCTURAL table-object stash (the insert/delete-verb shape), restored
##     exactly; the drag-scoped coalesce keeps the FIRST stash — one drag, one undo,
##   * the channel REFUSES (error + no-op, nothing recorded) a typed edit that would push
##     any downstream end_frame past s16 — never saturate.
## Seam: EffectEditSession.apply_edit → CameraChannel.apply_raw (the #255 choke point).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraRippleTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_ripple_end_frame_shifts_downstream_in_the_lane()
	_test_ripple_splits_a_downstream_coalesced_keyframe_lane_locally()
	_test_undo_restores_the_pre_ripple_table_exactly()
	_test_drag_coalesce_keeps_the_first_stash_one_drag_one_undo()
	_test_overflowing_ripple_is_refused_and_records_nothing()

	print("\n=== EffectCameraRippleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraRippleTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraRippleTest")
		get_tree().quit(0)


## Three solo angle keyframes at ends 8 / 20 / 30. A rippled edit of ordinal 0's end to 14
## (Δ = +6) shifts the downstream ends to 26 / 36 — widths preserved, the whole lane tail
## rides the boundary. The recompile is structural (the host re-projects).
func _test_ripple_end_frame_shifts_downstream_in_the_lane() -> void:
	var data = _effect_with_angle_lane([8, 20, 30])
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ripple_ref("angle", 0), 14)

	_assert_eq(res.get("structural", false), true, "a rippled end_frame edit is structural")
	_assert_eq(_lane_ends(data, "angle"), [14, 26, 36],
		"the edited end moved to 14 and every downstream end shifted by +6")


## A downstream keyframe that ALSO drives position (mask 3 at end 20) must SPLIT, not drag
## its sibling: rippling angle ordinal 0's end 8 → 14 shifts the angle lane to [14, 26]
## while the position lane keeps its 20 — the lane-local contract inside camera.
func _test_ripple_splits_a_downstream_coalesced_keyframe_lane_locally() -> void:
	var data = _effect_with_coalesced_downstream()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ripple_ref("angle", 0), 14)

	_assert_eq(res.get("structural", false), true, "the splitting ripple is structural")
	_assert_eq(_lane_ends(data, "angle"), [14, 26], "the angle lane shifted (edited 14, downstream 26)")
	_assert_eq(_lane_ends(data, "position"), [20], "the position sibling NEVER moved (split, not dragged)")
	var table = data.camera.get_table("for_each")
	_assert_eq(table.keyframes.size(), 3, "the coalesced keyframe split into two (plus the edited one)")
	var lanes: Dictionary = CameraLowering.parse(table)
	_assert_eq(lanes["position"][0]["value"], Vector3i(4, 5, 6), "position kept its value through the split")
	_assert_eq(lanes["angle"][1]["value"], Vector3i(7, 8, 9), "the shifted angle event kept its value")


## Undo of a rippled edit is the STRUCTURAL table-object stash (the insert/delete-verb
## shape): the pre-edit table comes back AS THE OBJECT — byte-exact by construction, no
## scalar replay whose re-lower could diverge (ordering, provenance, stale slots).
func _test_undo_restores_the_pre_ripple_table_exactly() -> void:
	var data = _effect_with_coalesced_downstream()
	var session = EffectEditSession.new(data)
	var original_table = data.camera.get_table("for_each")

	session.apply_edit(_ripple_ref("angle", 0), 14)
	_assert_true(session.undo(), "the rippled edit is undoable")

	_assert_true(data.camera.get_table("for_each") == original_table,
		"undo restores the pre-edit table OBJECT (structural stash, byte-exact)")
	_assert_eq(_lane_ends(data, "angle"), [8, 20], "the angle lane is back")
	_assert_eq(_lane_ends(data, "position"), [20], "…and the position sibling")
	_assert_eq(data.camera.get_table("for_each").keyframes.size(), 2,
		"the split un-did — the coalesced keyframe is whole again")


## Inside a begin/end_coalesce drag bracket, only the FIRST motion's stash survives: three
## rippled motions → ONE undo lands the whole lane back on the PRE-DRAG table; a second
## undo finds nothing.
func _test_drag_coalesce_keeps_the_first_stash_one_drag_one_undo() -> void:
	var data = _effect_with_angle_lane([8, 20, 30])
	var session = EffectEditSession.new(data)
	var original_table = data.camera.get_table("for_each")

	session.begin_coalesce({"channel": "camera", "context": "for_each", "ordinal": 0,
		"camera_channel": "angle", "field": "end_frame"})   # the page's grab ref (no flag)
	session.apply_edit(_ripple_ref("angle", 0), 14)
	session.apply_edit(_ripple_ref("angle", 0), 18)
	session.apply_edit(_ripple_ref("angle", 0), 24)
	session.end_coalesce()
	_assert_eq(_lane_ends(data, "angle"), [24, 36, 46], "the drag landed on the last motion")

	_assert_true(session.undo(), "the whole drag is one undo")
	_assert_true(data.camera.get_table("for_each") == original_table,
		"…restoring the PRE-DRAG table object (first stash kept)")
	_assert_eq(_lane_ends(data, "angle"), [8, 20, 30], "the lane is back to pre-drag")
	_assert_true(not session.undo(), "nothing further to undo — one drag, one entry")


## A typed edit that would push any downstream end past s16 is REFUSED: error + no-op —
## the table is untouched and NOTHING lands on the undo stack. Never saturate.
func _test_overflowing_ripple_is_refused_and_records_nothing() -> void:
	var data = _effect_with_angle_lane([100, 32760])
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ripple_ref("angle", 0), 200)

	_assert_eq(res.get("no_edit", false), true, "the overflow edit reports no_edit")
	_assert_eq(res.get("faithful", {}).get("ok", true), false, "…with a refusing Faithful verdict")
	_assert_eq(_lane_ends(data, "angle"), [100, 32760], "the lane is untouched (no saturation)")
	_assert_true(not session.undo(), "nothing was recorded — a refusal is a full no-op")


# --- fixtures --------------------------------------------------------------

## A camera end_frame field_ref carrying the ripple flag (it rides the field_ref, not
## ambient state, so undo replays ripple semantics after the toggle flips).
func _ripple_ref(camera_channel: String, ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each", "ordinal": ordinal,
		"camera_channel": camera_channel, "field": "end_frame", "ripple": true}


## for_each with one SOLO angle keyframe per entry of `ends` (mask 1, all agreeing on
## MAP / COSINE_A → cmd 0x04C1) with distinct values so shifts are trackable.
func _effect_with_angle_lane(ends: Array):
	var kfs: Array = []
	for i in range(ends.size()):
		kfs.append({"index": i, "end_frame": int(ends[i]),
			"angle": [i + 1, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x04C1, "channel_mask": 1,
			"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0})
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each":
		{"max_keyframe": ends.size() - 1, "keyframes": kfs}})
	return data


## for_each with a solo angle keyframe at end 8 and a COALESCED angle+position keyframe
## (mask 3) at end 20 — both agreeing MAP / COSINE_A (cmd 0x04C1 / 0x04C3).
func _effect_with_coalesced_downstream():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 8,
			"angle": [1, 2, 3], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x04C1, "channel_mask": 1,
			"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 20,
			"angle": [7, 8, 9], "position": [4, 5, 6], "zoom": [0, 0, 0],
			"command_raw": 0x04C3, "channel_mask": 3,
			"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0},
	]}})
	return data


## The lane's end_frames in ordinal order — the observable the ripple contract is about.
func _lane_ends(data, lane_name: String) -> Array:
	var ends: Array = []
	for ev in CameraLowering.parse(data.camera.get_table("for_each")).get(lane_name, []):
		ends.append(int(ev["end_frame"]))
	return ends


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
