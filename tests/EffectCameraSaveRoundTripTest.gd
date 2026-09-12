extends Node
## End-to-end guard for the CAMERA SAVE bridge (Save-bridge ticket): a real camera
## edit made through the Studio choke point must REACH the byte-patched E###.BIN.
## Before this bridge, `studio_save` persisted only the screen section and dropped
## every camera edit on the floor.
##
## The round-trip, on the REAL E317 (a camera-rich effect, 9 active for_each keyframes):
##   1. load E317's live CameraData from its extracted json,
##   2. edit the for_each camera via the CameraChannel choke point (insert a lane event),
##   3. EffectCameraSaver.save → shells the byte writer → authored_effects/E317.BIN,
##   4. RE-READ the written BIN's raw bytes IN GDScript, reparse the for_each SoA table,
##      and assert its per-sub-channel lane stream equals the LIVE edited model's.
##
## Semantic equivalence (ADR-0086), not byte-identity — a count change re-lowers +
## re-packs the fixed slots. The comparison ignores `origin_index` (a lowering artifact).
## Byte-level, no Python: GDScript reads the s16/u16 SoA arrays directly.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectCameraSaveRoundTripTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const CameraChannel = preload("res://src/effects/studio/CameraChannel.gd")
const EffectCameraSaver = preload("res://src/effects/studio/EffectCameraSaver.gd")

const EFFECT_ID := 317
const EFFECT_DIR := "res://assets/effects/E317"
const BASE_BIN := "res://../project-assets/fft-extract/EFFECT/E317.BIN"

# for_each SoA table offsets, mirrored from parse_effect.CAMERA_TRACK_TABLES (the ONE
# ROM layout). All relative to timeline_section_ptr.
const OFF := {
	"end_frame": 0x06B2, "angle": 0x06D4, "position": 0x073A,
	"zoom": 0x07A0, "command": 0x0806, "max_keyframe": 0x0828, "count": 17,
}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_a_camera_edit_reaches_the_written_bin()

	print("\n=== EffectCameraSaveRoundTripTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraSaveRoundTripTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraSaveRoundTripTest")
		get_tree().quit(0)


func _test_a_camera_edit_reaches_the_written_bin() -> void:
	var base_abs := ProjectSettings.globalize_path(BASE_BIN).simplify_path()
	if not FileAccess.file_exists(base_abs):
		print("[SKIP] E317 base BIN absent (%s) — ROM extract not populated" % base_abs)
		_passed += 1  # environment gap, not a failure
		return

	var data = EffectData.load_from_directory(EFFECT_DIR)
	_assert_eq(data != null and data.camera != null, true, "E317 loads with a camera")

	var timeline_ptr := _timeline_ptr()

	# Edit through the choke point: insert a zoom lane event at frame 50 (a region the
	# zoom lane doesn't cover), re-lowering the for_each table to a fresh coalesced stream.
	var res_edit: Dictionary = CameraChannel.insert_event(data, {
		"channel": "camera", "context": "for_each", "camera_channel": "zoom", "frame": 50})
	_assert_eq(res_edit.get("structural", false), true, "the insert is a structural edit")

	var live_lanes: Dictionary = CameraLowering.parse(data.camera.get_table("for_each"))
	_assert_eq(live_lanes["zoom"].size() >= 1, true, "the live zoom lane gained the event")

	# Save: pristine base → authored_effects/E317.BIN (camera section re-serialized).
	var res_save: Dictionary = EffectCameraSaver.save(EFFECT_ID, data.camera)
	_assert_eq(res_save.get("ok", false), true,
		"the save succeeded (%s)" % str(res_save.get("error", "")))
	if not res_save.get("ok", false):
		return

	var out_bytes := FileAccess.get_file_as_bytes(res_save["out_path"])
	var base_bytes := FileAccess.get_file_as_bytes(base_abs)
	_assert_eq(out_bytes.size(), base_bytes.size(), "the patched BIN keeps the base byte length")
	_assert_eq(out_bytes != base_bytes, true, "the edit actually changed bytes (not a no-op)")

	# Reparse the written for_each table from raw bytes and compare its lanes to the live
	# model — the semantic round-trip.
	var reparsed = _reparse_for_each(out_bytes, timeline_ptr)
	var re_lanes: Dictionary = CameraLowering.parse(reparsed)
	for lane in ["angle", "position", "zoom"]:
		_assert_eq(_lane_keys(re_lanes[lane]), _lane_keys(live_lanes[lane]),
			"the %s lane round-trips through the written BIN" % lane)


# --- byte reparse (GDScript mirror of parse_camera_phase_table for for_each) ---

func _reparse_for_each(bytes: PackedByteArray, timeline_ptr: int):
	var base: int = timeline_ptr
	var count: int = OFF["count"]
	var kfs: Array = []
	for i in range(count):
		kfs.append({
			"index": i,
			"end_frame": bytes.decode_s16(base + OFF["end_frame"] + i * 2),
			"angle": _read_vec3(bytes, base + OFF["angle"] + i * 6),
			"position": _read_vec3(bytes, base + OFF["position"] + i * 6),
			"zoom": _read_vec3(bytes, base + OFF["zoom"] + i * 6),
			"command_raw": bytes.decode_u16(base + OFF["command"] + i * 2),
			"channel_mask": bytes.decode_u16(base + OFF["command"] + i * 2) & 0x0007,
		})
	var mk: int = bytes.decode_s16(base + OFF["max_keyframe"])
	return CameraData.PhaseTable.from_json({"max_keyframe": mk, "keyframes": kfs}, "for_each")


func _read_vec3(bytes: PackedByteArray, off: int) -> Array:
	return [bytes.decode_s16(off), bytes.decode_s16(off + 2), bytes.decode_s16(off + 4)]


# --- helpers ----------------------------------------------------------------

## The semantic identity of a parsed lane event — everything EXCEPT origin_index
## (a lowering-provenance artifact the round-trip ignores, per CameraLowering).
func _lane_keys(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		out.append([ev["channel"], ev["end_frame"], ev["source_bits"], ev["interp_bits"],
			ev["param"], ev["flags"], ev["value"]])
	return out


func _timeline_ptr() -> int:
	var f := FileAccess.open("%s/header.json" % EFFECT_DIR, FileAccess.READ)
	var h: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return int(h["header"]["timeline_section_ptr"])


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
