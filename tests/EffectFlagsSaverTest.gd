extends Node
## TDD guard (#272, ADR-0092) for EffectFlagsSaver — the game→json→bin repack of the effect's
## GLOBAL flags byte. Two seams: (1) the pure adapter reads the live flags dict into the
## writer's `{flags_byte}` shape; (2) end-to-end, save() shells the byte-exact Python writer and
## the output E###.BIN carries the edited flags byte with the engine-ignored bits preserved —
## the whole write path, ROM-backed (skipped when the extract is absent).
##
## Run: <GODOT> --path . --quit-after 5 res://tests/EffectFlagsSaverTest.tscn

const EffectFlagsSaver = preload("res://src/effects/studio/EffectFlagsSaver.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_adapter_reads_live_flags()
	_test_adapter_refuses_empty_flags()
	_test_save_roundtrips_edited_byte_preserving_ignored_bits()

	print("\n=== EffectFlagsSaverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectFlagsSaverTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectFlagsSaverTest")
		get_tree().quit(0)


func _flags(flags_byte: int) -> Dictionary:
	return {
		"flags_byte": flags_byte,
		"terrain_height_adjust": (flags_byte & 0x08) != 0,
		"audio_fade": (flags_byte & 0x10) != 0,
		"time_scale_pattern1": (flags_byte & 0x20) != 0,
		"time_scale_pattern2": (flags_byte & 0x40) != 0,
	}


func _test_adapter_reads_live_flags() -> void:
	var res: Dictionary = EffectFlagsSaver.to_flags_json(_flags(0x23))
	_assert_true(res.get("ok", false), "adapter accepts a live flags dict")
	_assert_eq(res.get("json", {}).get("flags_byte"), 0x23, "flags_byte from the live dict")


func _test_adapter_refuses_empty_flags() -> void:
	var res: Dictionary = EffectFlagsSaver.to_flags_json({})
	_assert_true(not res.get("ok", true), "an empty flags dict is a hard error, not a crash")


## End-to-end: E019 stores flags 0x23 (bits 0,1 ignored + bit5). Clear bit5 → 0x03, save through
## the Python writer, and confirm the output BIN carries 0x03 with bits 0,1 preserved — the whole
## game→json→bin path.
func _test_save_roundtrips_edited_byte_preserving_ignored_bits() -> void:
	var base := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E019.BIN").simplify_path()
	if not FileAccess.file_exists(base) \
			or not FileAccess.file_exists("res://assets/effects/E019/header.json"):
		print("  [skip] E019 ROM extract / header.json absent — writer round-trip not run")
		_passed += 1
		return

	var base_bytes := FileAccess.get_file_as_bytes(base)
	var ptr := int(base_bytes.decode_u32(0x18))  # effect_flags_ptr (header 0x18, base_offset 0)
	_assert_eq(base_bytes[ptr], 0x23, "E019 base flags byte is 0x23")

	# Author clears bit5 (time-scale 3-phase): 0x23 -> 0x03.
	var res: Dictionary = EffectFlagsSaver.save(19, _flags(0x03))
	_assert_true(res.get("ok", false), "save() succeeds: %s" % res.get("error", ""))
	if not res.get("ok", false):
		return

	var out_bytes := FileAccess.get_file_as_bytes(res.get("out_path", ""))
	_assert_eq(out_bytes[ptr], 0x03, "the saved BIN carries the edited flags byte 0x03")
	_assert_eq(out_bytes[ptr] & 0x03, 0x03, "engine-ignored bits 0,1 preserved through the save path")
	# Every OTHER byte is verbatim — only the flags byte changed.
	var changed := 0
	for i in range(base_bytes.size()):
		if out_bytes[i] != base_bytes[i]:
			changed += 1
	_assert_eq(changed, 1, "exactly one byte (the flags byte) differs from the base")


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
