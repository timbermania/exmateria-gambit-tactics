extends Node
## TDD guard (#271) for EffectTimelineHeaderSaver — the game→json→bin repack of the three
## GLOBAL phase durations. Two seams: (1) the pure adapter reads the live TimelineData vars
## into the writer's `{header:{...}}` shape; (2) end-to-end, save() shells the byte-exact
## Python writer and the output E###.BIN parses back with the edited duration — the whole
## write path, ROM-backed (skipped when the extract is absent).
##
## Run: <GODOT> --path . --quit-after 5 res://tests/EffectTimelineHeaderSaverTest.tscn

const EffectTimelineHeaderSaver = preload("res://src/effects/studio/EffectTimelineHeaderSaver.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_adapter_reads_live_vars()
	_test_adapter_refuses_null_timeline()
	_test_save_roundtrips_edited_duration_through_writer()

	print("\n=== EffectTimelineHeaderSaverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectTimelineHeaderSaverTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectTimelineHeaderSaverTest")
		get_tree().quit(0)


func _timeline():
	var tl = TimelineDataClass.new()
	tl.phase1_duration = 111
	tl.spawn_delay = 22
	tl.phase2_delay = 33
	return tl


func _test_adapter_reads_live_vars() -> void:
	var res: Dictionary = EffectTimelineHeaderSaver.to_timeline_header_json(_timeline())
	_assert_true(res.get("ok", false), "adapter accepts a live timeline")
	var header: Dictionary = res.get("json", {}).get("header", {})
	_assert_eq(header.get("phase1_duration"), 111, "phase1_duration from the live var")
	_assert_eq(header.get("spawn_delay"), 22, "spawn_delay from the live var")
	_assert_eq(header.get("phase2_delay"), 33, "phase2_delay from the live var")


func _test_adapter_refuses_null_timeline() -> void:
	var res: Dictionary = EffectTimelineHeaderSaver.to_timeline_header_json(null)
	_assert_true(not res.get("ok", true), "a null timeline is a hard error, not a crash")


## End-to-end: edit E019's phase1_duration, save through the Python writer, and confirm the
## output BIN parses back with the new value — the whole game→json→bin path.
func _test_save_roundtrips_edited_duration_through_writer() -> void:
	var base := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E019.BIN").simplify_path()
	if not FileAccess.file_exists(base) \
			or not FileAccess.file_exists("res://assets/effects/E019/header.json"):
		print("  [skip] E019 ROM extract / header.json absent — writer round-trip not run")
		_passed += 1
		return

	# Load the effect's real durations, bump phase1, and save.
	var tl = _load_e019_timeline()
	if tl == null:
		_assert_true(false, "could not load E019 timeline.json")
		return
	var edited := int(tl.phase1_duration) + 24
	tl.phase1_duration = edited
	var res: Dictionary = EffectTimelineHeaderSaver.save(19, tl)
	_assert_true(res.get("ok", false), "save() succeeds: %s" % res.get("error", ""))
	if not res.get("ok", false):
		return

	# Parse the header of the written BIN back and confirm the edit landed.
	var out_bytes := FileAccess.get_file_as_bytes(res.get("out_path", ""))
	var ptr := _timeline_ptr(out_bytes)
	var got := out_bytes.decode_u16(ptr + 0x04)
	_assert_eq(got, edited, "the saved BIN parses back with the edited phase1_duration")


func _load_e019_timeline():
	var f := FileAccess.open("res://assets/effects/E019/timeline.json", FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	return TimelineDataClass.from_json(data)


func _timeline_ptr(bytes: PackedByteArray) -> int:
	# Header pointer at 0x1C (matches parse_effect.parse_header, base_offset 0).
	return bytes.decode_u32(0x1C)


# --- helpers ---------------------------------------------------------------
func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
