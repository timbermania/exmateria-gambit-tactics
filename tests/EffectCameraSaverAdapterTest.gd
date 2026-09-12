extends Node
## TDD guard for the CAMERA SAVE adapter — `EffectCameraSaver.to_camera_json`, the
## shape bridge between the LIVE camera model and the byte writer (Save-bridge ticket).
##
## The live model (after any edit) is a VARIABLE-length coalesced `PhaseTable`
## (CameraLowering.lower): `keyframes.size()` == the live group count, `max_keyframe`
## == that watermark. The byte writer (`write_effect_camera.py`) is the INVERSE of
## `parse_camera_keyframes`, which reads FIXED native SoA slots (phase1=21 / for_each=17
## / phase2=21) and indexes `keyframes[i]` for EVERY slot. So the adapter must pad each
## live table up to its native slot count — trailing (dead, past-watermark) slots zeroed —
## carry `max_keyframe` verbatim, and REFUSE an over-capacity table (more live keyframes
## than native slots) rather than let the writer raise mid-shell-out (ADR-0086: capacity
## is post-compile, Free-only — it cannot be section-written to the ROM's fixed slots).
##
## Pure — no disk, no shell-out. The disk/round-trip half is EffectCameraSaveRoundTripTest.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraSaverAdapterTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const EffectCameraSaver = preload("res://src/effects/studio/EffectCameraSaver.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_pads_a_lowered_short_table_to_native_slots()
	_test_padding_slots_are_zeroed()
	_test_carries_the_live_watermark()
	_test_live_keyframes_keep_their_raw_fields()
	_test_over_capacity_table_is_refused()
	_test_absent_tables_are_skipped()
	_test_a_full_unedited_table_passes_through_unchanged()

	print("\n=== EffectCameraSaverAdapterTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraSaverAdapterTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraSaverAdapterTest")
		get_tree().quit(0)


# --- padding to native slots ------------------------------------------------

## A lowered for_each table with 2 live keyframes must serialize to EXACTLY 17
## keyframes (the native slot count) so the writer's fixed `range(count)` walk is
## in-bounds for every slot.
func _test_pads_a_lowered_short_table_to_native_slots() -> void:
	var camera = _lowered_for_each_with_two_kfs()
	var res: Dictionary = EffectCameraSaver.to_camera_json(camera)

	_assert_eq(res.get("ok", false), true, "a valid short table serializes ok")
	var kfs: Array = res["json"]["for_each"]["keyframes"]
	_assert_eq(kfs.size(), CameraLowering.NATIVE_SLOTS["for_each"],
		"for_each padded up to its 17 native slots")


## Every padded (dead) trailing slot is a fully zeroed keyframe — end_frame /
## angle / position / zoom / command_raw all 0. They sit past the watermark, so
## the runtime never reads them; zeroing is the deterministic dead-slot fill.
func _test_padding_slots_are_zeroed() -> void:
	var camera = _lowered_for_each_with_two_kfs()
	var kfs: Array = EffectCameraSaver.to_camera_json(camera)["json"]["for_each"]["keyframes"]

	var dead: Dictionary = kfs[5]  # any slot past the 2 live ones
	_assert_eq(dead["end_frame"], 0, "dead slot end_frame zeroed")
	_assert_eq(dead["angle"], [0, 0, 0], "dead slot angle zeroed")
	_assert_eq(dead["position"], [0, 0, 0], "dead slot position zeroed")
	_assert_eq(dead["zoom"], [0, 0, 0], "dead slot zoom zeroed")
	_assert_eq(dead["command_raw"], 0, "dead slot command word zeroed")


## `max_keyframe` is the live watermark, carried verbatim — the writer needs it to
## re-mark the active window in the fixed slot array.
func _test_carries_the_live_watermark() -> void:
	var camera = _lowered_for_each_with_two_kfs()
	var res: Dictionary = EffectCameraSaver.to_camera_json(camera)
	_assert_eq(res["json"]["for_each"]["max_keyframe"], 1, "watermark = live group count - 1")


## The live keyframes' AUTHORITATIVE raw fields (end_frame + the three s16 vecs +
## command_raw) survive into the fixed-slot dict as the writer's flat arrays.
func _test_live_keyframes_keep_their_raw_fields() -> void:
	var camera = _lowered_for_each_with_two_kfs()
	var kfs: Array = EffectCameraSaver.to_camera_json(camera)["json"]["for_each"]["keyframes"]

	_assert_eq(kfs[0]["end_frame"], 10, "kf0 end_frame")
	_assert_eq(kfs[0]["angle"], [1, 2, 3], "kf0 angle vec")
	_assert_eq(kfs[0]["command_raw"], 0x0841, "kf0 command word (folded, raw→bytes pure)")
	_assert_eq(kfs[1]["end_frame"], 20, "kf1 end_frame")
	_assert_eq(kfs[1]["position"], [4, 5, 6], "kf1 position vec")
	_assert_eq(kfs[1]["zoom"], [7, 0, 0], "kf1 zoom vec")


# --- capacity refusal -------------------------------------------------------

## A lowered table with MORE live keyframes than its native slots cannot be
## section-written (the ROM has no slot to hold it). The adapter refuses loudly —
## a byte-patched Faithful save is impossible; Free-only is not a disk artifact
## (ADR-0086). The failure is reported ({ok:false}), never a silent truncation.
func _test_over_capacity_table_is_refused() -> void:
	var camera = _over_capacity_for_each()
	var res: Dictionary = EffectCameraSaver.to_camera_json(camera)
	_assert_eq(res.get("ok", true), false, "over-capacity table is refused")
	_assert_eq(str(res.get("error", "")).is_empty(), false, "the refusal carries a reason")


# --- table presence ---------------------------------------------------------

## Only the phase tables the live camera actually has are serialized; absent
## tables are omitted so the writer leaves their base bytes verbatim.
func _test_absent_tables_are_skipped() -> void:
	var camera = _lowered_for_each_with_two_kfs()  # for_each only
	var json: Dictionary = EffectCameraSaver.to_camera_json(camera)["json"]
	_assert_eq(json.has("for_each"), true, "the present table is serialized")
	_assert_eq(json.has("phase1"), false, "an absent table is omitted")
	_assert_eq(json.has("phase2"), false, "an absent table is omitted")


## An UNEDITED table already at native length (parse yields all `count` slots)
## passes through as `count` keyframes with its raw fields intact — so re-saving an
## un-touched camera reproduces its bytes (the round-trip identity property).
func _test_a_full_unedited_table_passes_through_unchanged() -> void:
	var camera = _full_phase1_from_parse_shape()
	var res: Dictionary = EffectCameraSaver.to_camera_json(camera)
	var kfs: Array = res["json"]["phase1"]["keyframes"]
	_assert_eq(kfs.size(), CameraLowering.NATIVE_SLOTS["phase1"], "full table stays 21 slots")
	_assert_eq(kfs[3]["end_frame"], 99, "an interior slot keeps its raw end_frame")
	_assert_eq(kfs[3]["command_raw"], 0x1234, "an interior slot keeps its raw command word")


# --- fixtures ---------------------------------------------------------------

## A for_each with 2 live keyframes (as CameraLowering.lower would leave it):
## keyframes.size()==2, max_keyframe==1.
func _lowered_for_each_with_two_kfs():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 10, "angle": [1, 2, 3], "position": [0, 0, 0],
			"zoom": [0, 0, 0], "command_raw": 0x0841, "channel_mask": 1},
		{"index": 1, "end_frame": 20, "angle": [0, 0, 0], "position": [4, 5, 6],
			"zoom": [7, 0, 0], "command_raw": 0x0842, "channel_mask": 2},
	]}})
	return data.camera


## A for_each carrying 18 keyframes — one past its 17 native slots.
func _over_capacity_for_each():
	var kfs: Array = []
	for i in range(18):
		kfs.append({"index": i, "end_frame": i, "angle": [0, 0, 0], "position": [0, 0, 0],
			"zoom": [0, 0, 0], "command_raw": 0x0001, "channel_mask": 1})
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 16, "keyframes": kfs}})
	return data.camera


## A phase1 already at its full 21-slot native length (as parse_camera_keyframes
## emits it), with a recognizable interior slot to probe.
func _full_phase1_from_parse_shape():
	var kfs: Array = []
	for i in range(21):
		var ef := 99 if i == 3 else 0
		var cr := 0x1234 if i == 3 else 0
		kfs.append({"index": i, "end_frame": ef, "angle": [0, 0, 0], "position": [0, 0, 0],
			"zoom": [0, 0, 0], "command_raw": cr, "channel_mask": 0})
	var data = EffectData.new()
	data.camera = CameraData.from_json({"phase1": {"max_keyframe": 3, "keyframes": kfs}})
	return data.camera


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
