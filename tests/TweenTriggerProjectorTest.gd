extends Node
## TDD guard for the PALETTE / CAMERA / SOUND projectors (ADR-0071) — each ports its
## inspector_rows arm into a single Section over the score-model span's own inline
## `fields`. Pure, no scene. See CONTEXT "Tween" / "Trigger".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/TweenTriggerProjectorTest.tscn

const Palette = preload("res://src/effects/studio/PaletteTweenProjector.gd")
# The Camera projector is now EDITABLE (#267); its contract lives in the dedicated
# CameraTweenProjectorTest (shape:edit int/enum/bitflags rows + write-side field_refs).
const Sound = preload("res://src/effects/studio/SoundTriggerProjector.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_palette_tween_section()
	_test_sound_trigger_section()

	print("\n=== TweenTriggerProjectorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TweenTriggerProjectorTest")
		get_tree().quit(1)
	else:
		print("[PASS] TweenTriggerProjectorTest")
		get_tree().quit(0)


func _test_palette_tween_section() -> void:
	var span := {"kind": "palette", "fields": {
		"channel": "caster", "rgb": Vector3i(0, 255, 0),
		"enabled": true, "blend_mode": 3, "duration_frames": 10}}
	var secs := Palette.sections(span)
	_assert_eq(secs.size(), 1, "palette projects one section")
	_assert_eq(secs[0].get("title", ""), "Palette tint", "palette section titled")
	# Palette is EDITABLE, and its Tint is the WYSIWYG RESULT-picker (`target_color`), not
	# the absolute-unsigned `gradient_color`. #266 reused gradient_color (colour = raw/255);
	# that was the "seek-color renders the wrong hue" bug and ADR-0087 retired it — the RGB
	# tint is a SIGNED delta through the blend mode, so the author picks what a fixed
	# mid-grey reference should BECOME and PaletteTintSolver back-solves the delta
	# (PaletteTweenProjector.gd:6-14, ColorTweenRows.tint_row). This assertion still named
	# the retired editor. Blend mode stays a value-carrying enum whose int value == the code.
	_assert_eq(_editor_of(secs[0], "Tint"), "target_color", "palette tint is the WYSIWYG result-picker")
	_assert_eq(_value_of(secs[0], "Blend mode"), "3", "palette blend mode enum value rendered")


func _test_sound_trigger_section() -> void:
	# #268: Sound + Gap are EDITABLE int cells; Track stays const. (Labels: "Sound" is the
	# container selector, "Gap" is duration_frames — renamed from the old "Sound id"/"Duration".)
	var span := {"kind": "sound", "phase": "phase1", "channel_index": 0, "keyframe_index": 1,
		"fields": {"channel": 0, "sound_id": 5, "duration_frames": 60}}
	var secs := Sound.sections(span)
	_assert_eq(secs.size(), 1, "sound projects one section")
	_assert_eq(secs[0].get("title", ""), "Sound", "sound section titled")
	_assert_eq(_value_of(secs[0], "Sound"), "5", "sound id seeded")
	_assert_eq(_value_of(secs[0], "Gap"), "60", "sound gap (duration_frames) seeded")
	_assert_eq(_editor_of(secs[0], "Sound"), "int", "sound id is an editable int")
	_assert_eq(_editor_of(secs[0], "Gap"), "int", "gap is an editable int")


# --- helpers --------------------------------------------------------------

func _value_of(section: Dictionary, name: String) -> String:
	for f in section.get("fields", []):
		if f.get("name", "") == name:
			return str(f.get("value", ""))
	return "<missing:%s>" % name


func _editor_of(section: Dictionary, name: String) -> String:
	for f in section.get("fields", []):
		if f.get("name", "") == name:
			return str(f.get("editor", ""))
	return "<missing:%s>" % name


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
