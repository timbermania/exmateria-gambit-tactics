extends Node
## End-to-end acceptance guard for HUMAN-UNIT camera authoring (degrees → raw bytes).
## Binds the two proven halves on the REAL E317:
##   1. the actual inspector int cell, tagged unit ANGLE_DEG, converts a typed 90.0° into
##      raw 1024 and fans it through the #255 mutate callback (no degrees escape the cell);
##   2. that raw, applied to E317's angle_y through the CameraChannel choke point and saved,
##      lands as s16 1024 in the byte-patched E317.BIN.
## So the number the author types (degrees) compiles down to exactly what the BIN expects
## (raw s16), with storage / writer / runtime untouched.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectCameraUnitAuthoringSaveTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const CameraChannel = preload("res://src/effects/studio/CameraChannel.gd")
const CameraUnits = preload("res://src/effects/studio/CameraUnits.gd")
const EffectCameraSaver = preload("res://src/effects/studio/EffectCameraSaver.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

const EFFECT_ID := 317
const EFFECT_DIR := "res://assets/effects/E317"
const BASE_BIN := "res://../project-assets/fft-extract/EFFECT/E317.BIN"

# for_each SoA table offsets, mirrored from parse_effect.CAMERA_TRACK_TABLES.
const OFF := {
	"end_frame": 0x06B2, "angle": 0x06D4, "position": 0x073A,
	"zoom": 0x07A0, "command": 0x0806, "max_keyframe": 0x0828, "count": 17,
}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_a_degree_edit_reaches_the_written_bin_as_raw()

	print("\n=== EffectCameraUnitAuthoringSaveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraUnitAuthoringSaveTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraUnitAuthoringSaveTest")
		get_tree().quit(0)


func _test_a_degree_edit_reaches_the_written_bin_as_raw() -> void:
	var base_abs := ProjectSettings.globalize_path(BASE_BIN).simplify_path()
	if not FileAccess.file_exists(base_abs):
		print("[SKIP] E317 base BIN absent (%s) — ROM extract not populated" % base_abs)
		_passed += 1
		return

	var data = EffectData.load_from_directory(EFFECT_DIR)
	_assert_eq(data != null and data.camera != null, true, "E317 loads with a camera")

	var live_lanes: Dictionary = CameraLowering.parse(data.camera.get_table("for_each"))
	if live_lanes["angle"].size() < 1:
		print("[SKIP] E317 for_each has no angle lane event to target")
		_passed += 1
		return

	# 1. The REAL inspector cell converts 90.0° → raw 1024 and fans it through mutate.
	var raw := _raw_fanned_typing_degrees(90.0)
	_assert_eq(raw, 1024, "the inspector fans raw 1024 when the author types 90.0°")

	# 2. Apply that raw to the first angle event's yaw through the choke point.
	var ref := {"channel": "camera", "context": "for_each", "camera_channel": "angle",
		"ordinal": 0, "field": "angle_y"}
	var res: Dictionary = CameraChannel.apply_raw(data, ref, raw)
	_assert_eq(res.is_empty(), false, "the angle_y edit applied through the choke point")
	_assert_eq(int(CameraLowering.parse(data.camera.get_table("for_each"))["angle"][0]["value"].y),
		1024, "the live angle event now carries raw 1024")

	# 3. Save → byte-patch → re-read the written BIN and confirm raw 1024 is on disk.
	var res_save: Dictionary = EffectCameraSaver.save(EFFECT_ID, data.camera)
	_assert_eq(res_save.get("ok", false), true,
		"the save succeeded (%s)" % str(res_save.get("error", "")))
	if not res_save.get("ok", false):
		return

	var out_bytes := FileAccess.get_file_as_bytes(res_save["out_path"])
	var reparsed = _reparse_for_each(out_bytes, _timeline_ptr())
	var re_yaw := int(CameraLowering.parse(reparsed)["angle"][0]["value"].y)
	_assert_eq(re_yaw, 1024, "the typed 90.0° is raw s16 1024 in the written E317.BIN")


## Drive the ACTUAL inspector int cell (unit ANGLE_DEG): seed it, type `deg` into its
## SpinBox, and return the raw the mutate callback received.
func _raw_fanned_typing_degrees(deg: float) -> int:
	var sink: Array = []
	var insp = Inspector.new()
	add_child(insp)
	var cell := {"name": "Yaw", "shape": "edit", "editor": "int", "type": "s16", "value": 0,
		"field_ref": {"field": "angle_y"}, "unit": CameraUnits.ANGLE_DEG}
	insp.show_target(Target.span("cam#0"), [], [{"title": "Cam angle", "fields": [cell]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_ref, raw): sink.append(raw))
	var sb = insp.int_widgets()[0]   # ScrubField (drop-in for the old SpinBox)
	sb.value = deg
	insp.queue_free()
	return int(sink[-1]) if not sink.is_empty() else -1


func _reparse_for_each(bytes: PackedByteArray, timeline_ptr: int):
	var base: int = timeline_ptr
	var kfs: Array = []
	for i in range(OFF["count"]):
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
