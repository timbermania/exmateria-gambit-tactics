extends Node
## TDD guard (#272, ADR-0092) for EffectFlagsChannel — the write-side encoder for the
## effect's GLOBAL flags byte (@0x00 of the effect_flags section). Only bits 3-6 are
## engine-read (terrain_height_adjust / audio_fade / time_scale_pattern1 / _pattern2), but
## the WHOLE raw byte is stored so the engine-ignored bits 0-2/7 (E001=0x03) ride along —
## the bitflags editor recomputes the full word off the seeded raw byte and hands it here.
##
## The channel writes `data.flags.flags_byte`, keeps the four decoded bools in sync (so a
## reload-free read-back is consistent), and — for bits 5/6 — mirrors the enables into
## `data.time_scale.flags.time_scale_pattern1/2` so a re-fold makes the slow-mo enable/disable
## visible immediately (invalidates_sim). Scalar undo: the raw byte fully re-derives.
##
## Run: <GODOT> --path . --quit-after 3 res://tests/EffectFlagsChannelTest.tscn

const EffectFlagsChannel = preload("res://src/effects/studio/EffectFlagsChannel.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_edit_writes_byte_and_returns_before_after()
	_test_ignored_bits_ride_along()
	_test_decoded_bools_kept_in_sync()
	_test_bit5_syncs_time_scale_pattern1()
	_test_bit6_syncs_time_scale_pattern2()
	_test_time_scale_sync_noop_when_absent()
	_test_every_edit_invalidates_sim()
	_test_read_raw_mirrors_storage()
	_test_null_flags_is_refused()

	print("\n=== EffectFlagsChannelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectFlagsChannelTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectFlagsChannelTest")
		get_tree().quit(0)


# E019-shaped fixture: flags 0x23 (bits 0,1 ignored + bit5 time_scale_pattern1), a live
# time_scale block whose flags mirror bits 5/6.
func _effect(flags_byte: int = 0x23, with_time_scale: bool = true):
	var ed = EffectDataClass.new()
	ed.flags = {
		"flags_byte": flags_byte,
		"terrain_height_adjust": (flags_byte & 0x08) != 0,
		"audio_fade": (flags_byte & 0x10) != 0,
		"time_scale_pattern1": (flags_byte & 0x20) != 0,
		"time_scale_pattern2": (flags_byte & 0x40) != 0,
	}
	if with_time_scale:
		ed.time_scale = {
			"flags": {
				"time_scale_pattern1": (flags_byte & 0x20) != 0,
				"time_scale_pattern2": (flags_byte & 0x40) != 0,
			},
			"outer_phases": [], "for_each": [],
		}
	return ed


func _ref() -> Dictionary:
	return {"channel": "effect_flags", "field": "flags_byte"}


func _test_edit_writes_byte_and_returns_before_after() -> void:
	var ed = _effect(0x23)
	# Author clears bit5 → the bitflags editor hands the full recomputed word 0x03.
	var res: Dictionary = EffectFlagsChannel.apply_raw(ed, _ref(), 0x03)
	_assert_eq(res.get("before_raw"), 0x23, "before_raw is the pre-edit byte")
	_assert_eq(res.get("after_raw"), 0x03, "after_raw is the new byte")
	_assert_eq(int(ed.flags["flags_byte"]), 0x03, "the stored flags byte is updated")


func _test_ignored_bits_ride_along() -> void:
	# E001 seeds ignored bits 0,1 (0x03). Turning bit5 ON gives 0x23 — the channel stores
	# the whole word, so 0,1 survive (it must NOT re-derive from the four bools).
	var ed = _effect(0x03)
	EffectFlagsChannel.apply_raw(ed, _ref(), 0x23)
	_assert_eq(int(ed.flags["flags_byte"]) & 0x03, 0x03, "engine-ignored bits 0,1 preserved")
	_assert_eq(int(ed.flags["flags_byte"]), 0x23, "bit5 set on top of the ignored bits")


func _test_decoded_bools_kept_in_sync() -> void:
	var ed = _effect(0x00)
	# Set terrain (bit3) + audio_fade (bit4): 0x18.
	EffectFlagsChannel.apply_raw(ed, _ref(), 0x18)
	_assert_true(bool(ed.flags["terrain_height_adjust"]), "bit3 decoded to terrain_height_adjust")
	_assert_true(bool(ed.flags["audio_fade"]), "bit4 decoded to audio_fade")
	_assert_true(not bool(ed.flags["time_scale_pattern1"]), "bit5 clear stays false")


func _test_bit5_syncs_time_scale_pattern1() -> void:
	var ed = _effect(0x23)  # pattern1 on
	EffectFlagsChannel.apply_raw(ed, _ref(), 0x03)  # clear bit5
	_assert_true(not bool(ed.time_scale["flags"]["time_scale_pattern1"]),
		"clearing bit5 mirrors into time_scale.flags.time_scale_pattern1 (live re-render)")


func _test_bit6_syncs_time_scale_pattern2() -> void:
	var ed = _effect(0x03)  # both time-scale enables off
	EffectFlagsChannel.apply_raw(ed, _ref(), 0x43)  # set bit6
	_assert_true(bool(ed.time_scale["flags"]["time_scale_pattern2"]),
		"setting bit6 mirrors into time_scale.flags.time_scale_pattern2")


func _test_time_scale_sync_noop_when_absent() -> void:
	var ed = _effect(0x03, false)  # no time_scale block
	var res: Dictionary = EffectFlagsChannel.apply_raw(ed, _ref(), 0x23)
	_assert_true(not res.is_empty(), "an edit with no time_scale block still succeeds (no crash)")
	_assert_eq(int(ed.flags["flags_byte"]), 0x23, "flags byte still written without a time_scale block")


func _test_every_edit_invalidates_sim() -> void:
	var ed = _effect(0x23)
	var res: Dictionary = EffectFlagsChannel.apply_raw(ed, _ref(), 0x03)
	_assert_true(bool(res.get("invalidates_sim", false)),
		"a flags edit re-folds the sim (time-scale enable is honoured in preview)")


func _test_read_raw_mirrors_storage() -> void:
	var ed = _effect(0x23)
	_assert_eq(EffectFlagsChannel.read_raw(ed, _ref()), 0x23,
		"read_raw returns the live stored flags byte (bitflags seed)")


func _test_null_flags_is_refused() -> void:
	var ed = EffectDataClass.new()  # flags is an empty dict
	var res: Dictionary = EffectFlagsChannel.apply_raw(ed, _ref(), 0x08)
	_assert_true(res.is_empty(), "an effect with no flags block is refused (empty result)")


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
