extends Node
## TDD guard for EffectScreenSaver.to_screen_json (ADR-0087) — the SHAPE BRIDGE of the screen
## Save seam (the counterpart to EffectPaletteSaver.to_palette_json). The byte writer
## (write_effect_screen.serialize_screen_channel) writes a FIXED 33 keyframe slots per
## channel; the live model after edits (boundary trade / insert / delete) is a
## variable-length keyframe list — fed straight to the writer it silently truncates on 34
## and CRASHES on 32. `to_screen_json` pads each live channel up to 33 slots — dead trailing
## slots zeroed — carries max_keyframe verbatim, and emits the flat disk fields straight
## (start_r IS the 0-255 byte on disk). Over-capacity (a used keyframe past slot 33) is
## REFUSED — the ROM has no slot to hold it.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectScreenSaverAdapterTest.tscn

const Saver = preload("res://src/effects/studio/EffectScreenSaver.gd")
const ScreenDataClass = ExMateriaEffects.ScreenData

const MAX_SLOTS := 33

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_pads_each_channel_to_the_fixed_slot_count()
	_test_emits_the_flat_disk_fields_straight()
	_test_carries_max_keyframe_and_skips_absent_contexts()
	_test_over_capacity_is_refused()

	print("\n=== EffectScreenSaverAdapterTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScreenSaverAdapterTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScreenSaverAdapterTest")
		get_tree().quit(0)


## A live channel of 3 keyframes pads up to the fixed 33 slots, the trailing ones zeroed —
## every slot carrying the full raw key set the writer's flat-field fallback needs.
func _test_pads_each_channel_to_the_fixed_slot_count() -> void:
	var res: Dictionary = Saver.to_screen_json(_screen([2, 1, 3]))
	_assert_true(res.get("ok", false), "the adapter succeeds")
	var ch: Dictionary = res.get("json", {}).get("for_each", {})
	var kfs: Array = ch.get("keyframes", [])
	_assert_eq(kfs.size(), MAX_SLOTS, "the channel is padded to 33 slots")
	_assert_eq(int(kfs[0].get("time_value", -1)), 2, "slot 0 carries the live time_value")
	var dead: Dictionary = kfs[MAX_SLOTS - 1]
	for key in ["time_value", "start_r", "start_g", "start_b", "end_r", "end_g", "end_b", "ctrl"]:
		_assert_eq(int(dead.get(key, -1)), 0, "the trailing dead slot zeroes %s" % key)


## The flat disk fields are emitted straight — start_r IS the 0-255 byte on disk, ctrl
## carries the kind bit-7 + blend mode.
func _test_emits_the_flat_disk_fields_straight() -> void:
	var sd = _screen([2])
	var kf = sd.get_channel("for_each").get_keyframe(0)
	kf.start_r_raw = 225
	kf.end_b_raw = 40
	kf.ctrl = 0x85
	var kfs: Array = Saver.to_screen_json(sd).get("json", {}).get("for_each", {}).get("keyframes", [])
	_assert_eq(int(kfs[0].get("start_r", -1)), 225, "start_r emits the raw byte straight")
	_assert_eq(int(kfs[0].get("end_b", -1)), 40, "end_b emits the raw byte straight")
	_assert_eq(int(kfs[0].get("ctrl", -1)), 0x85, "ctrl emits the kind + blend-mode byte straight")


## max_keyframe is carried verbatim; contexts with no channel are omitted (the writer then
## leaves their base bytes untouched).
func _test_carries_max_keyframe_and_skips_absent_contexts() -> void:
	var sd = _screen([2, 2])
	sd.get_channel("for_each").max_keyframe = 3
	var json: Dictionary = Saver.to_screen_json(sd).get("json", {})
	_assert_eq(int(json.get("for_each", {}).get("max_keyframe", -1)), 3,
		"max_keyframe is carried verbatim")
	_assert_true(not json.has("phase1"), "an absent context is omitted")


## A channel whose USED keyframes exceed the 33 native slots cannot be section-written — refused.
func _test_over_capacity_is_refused() -> void:
	var tvs: Array = []
	for i in range(MAX_SLOTS + 1):
		tvs.append(1)
	var res: Dictionary = Saver.to_screen_json(_screen(tvs))
	_assert_true(not res.get("ok", true), "an over-capacity channel is refused")
	_assert_true(String(res.get("error", "")) != "", "…with a reason")


# --- fixtures -------------------------------------------------------------

func _screen(time_values: Array):
	var kfs: Array = []
	for i in range(time_values.size()):
		kfs.append({"index": i, "time_value": int(time_values[i]),
			"duration_frames": maxi(1, int(time_values[i]) * 8),
			"start_r": 10, "start_g": 20, "start_b": 30,
			"end_r": 10, "end_g": 20, "end_b": 30,
			"ctrl": 0x85, "mode": "TINT", "blend_mode": 5})
	return ScreenDataClass.from_json({"for_each": {
		"context": "for_each", "max_keyframe": time_values.size() + 1, "keyframes": kfs,
	}})


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
