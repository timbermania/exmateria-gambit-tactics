extends Node
## TDD guard for EffectPaletteSaver.to_palette_json (ADR-0087) — the SHAPE BRIDGE of the
## palette Save seam (the counterpart to EffectCameraSaver.to_camera_json). The byte writer
## (write_effect_palette.serialize_palette_channel) writes a FIXED 33 keyframe slots per channel;
## the live model after edits (boundary trade / insert / delete) is a variable-length keyframe
## list. `to_palette_json` pads each live channel up to 33 slots — dead trailing slots zeroed —
## carries max_keyframe verbatim, and emits {time_value, rgb, ctrl} straight (a palette keyframe
## HAS no raw sub-block; its flat fields ARE the disk bytes). Over-capacity (a used keyframe
## past slot 33) is REFUSED — the ROM has no slot to hold it.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectPaletteSaverAdapterTest.tscn

const Saver = preload("res://src/effects/studio/EffectPaletteSaver.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData

const MAX_SLOTS := 33

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_pads_each_channel_to_the_fixed_slot_count()
	_test_emits_the_flat_disk_fields_straight()
	_test_carries_max_keyframe_and_skips_absent_channels()
	_test_over_capacity_is_refused()

	print("\n=== EffectPaletteSaverAdapterTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPaletteSaverAdapterTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPaletteSaverAdapterTest")
		get_tree().quit(0)


## A live channel of 3 keyframes pads up to the fixed 33 slots, the trailing ones zeroed.
func _test_pads_each_channel_to_the_fixed_slot_count() -> void:
	var res := Saver.to_palette_json(_palette([2, 1, 3]))
	_assert_true(res.get("ok", false), "the adapter succeeds")
	var ch: Dictionary = res.get("json", {}).get("for_each", {}).get("affected_units", {})
	var kfs: Array = ch.get("keyframes", [])
	_assert_eq(kfs.size(), MAX_SLOTS, "the channel is padded to 33 slots")
	_assert_eq(int(kfs[0].get("time_value", -1)), 2, "slot 0 carries the live time_value")
	var dead: Dictionary = kfs[MAX_SLOTS - 1]
	_assert_eq(int(dead.get("time_value", -1)), 0, "the trailing slot is a zeroed dead slot (time)")
	_assert_eq(int(dead.get("ctrl", -1)), 0, "…and ctrl")


## The flat disk fields (time_value, rgb, ctrl) are emitted straight — a palette keyframe has no
## raw sub-block. rgb is the raw 0-255 bytes; ctrl carries enabled bit-7 + blend mode.
func _test_emits_the_flat_disk_fields_straight() -> void:
	var pd = _palette([2])
	var kf = pd.get_channel("for_each", "affected_units").get_keyframe(0)
	kf.rgb = Vector3i(225, 10, 40)   # a signed −31 red byte among positives
	kf.ctrl = 0x85                   # enabled + blend mode 5
	var kfs: Array = Saver.to_palette_json(pd).get("json", {}).get("for_each", {}).get("affected_units", {}).get("keyframes", [])
	_assert_eq(kfs[0].get("rgb", []), [225, 10, 40], "rgb emits the raw 0-255 bytes straight")
	_assert_eq(int(kfs[0].get("ctrl", -1)), 0x85, "ctrl emits the enabled + blend-mode byte straight")


## max_keyframe is carried verbatim; contexts/channels with no data are omitted (the writer
## then leaves their base bytes untouched).
func _test_carries_max_keyframe_and_skips_absent_channels() -> void:
	var pd = _palette([2, 2])
	pd.get_channel("for_each", "affected_units").max_keyframe = 3
	var json: Dictionary = Saver.to_palette_json(pd).get("json", {})
	_assert_eq(int(json.get("for_each", {}).get("affected_units", {}).get("max_keyframe", -1)), 3,
		"max_keyframe is carried verbatim")
	_assert_true(not json.get("for_each", {}).has("caster"), "an absent channel is omitted")


## A channel whose USED keyframes exceed the 33 native slots cannot be section-written — refused.
func _test_over_capacity_is_refused() -> void:
	var tvs: Array = []
	for i in range(MAX_SLOTS + 1):
		tvs.append(1)
	var res := Saver.to_palette_json(_palette(tvs))
	_assert_true(not res.get("ok", true), "an over-capacity channel is refused")
	_assert_true(String(res.get("error", "")) != "", "…with a reason")


# --- fixtures -------------------------------------------------------------

func _palette(time_values: Array):
	var kfs: Array = []
	for i in range(time_values.size()):
		var tv: int = int(time_values[i])
		kfs.append({"index": i, "time_value": tv, "duration_frames": (tv * 8 if tv > 0 else 1),
			"rgb": [10, 20, 30], "ctrl": 0x85, "enabled": true, "blend_mode": 0})
	return PaletteDataClass.from_json({"for_each": {"affected_units": {
		"context": "for_each", "channel_name": "affected_units",
		"max_keyframe": time_values.size(), "keyframes": kfs,
	}}})


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
