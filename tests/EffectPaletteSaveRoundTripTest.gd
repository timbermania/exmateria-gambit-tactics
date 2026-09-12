extends Node
## End-to-end guard for the PALETTE SAVE bridge (ADR-0087): a real palette edit made through
## the Studio choke point must REACH the byte-patched E###.BIN. Before this bridge, `studio_save`
## persisted screen + camera and dropped every palette edit on the floor.
##
## The round-trip, on the REAL E317:
##   1. load E317's live PaletteData from its extracted json,
##   2. find an enabled palette keyframe and edit its rgb.r through the PaletteChannel choke point,
##   3. EffectPaletteSaver.save → shells the byte writer → authored_effects/E317.BIN,
##   4. RE-READ the written BIN's raw bytes IN GDScript, at the independently-computed rgb offset,
##      and assert the edited byte landed — while the file length is preserved (a partial patch).
## Byte-level, no Python: GDScript reads the u8 straight from the channel's RGB block.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectPaletteSaveRoundTripTest.tscn

const EffectData = ExMateriaEffects.EffectData
const PaletteChannel = preload("res://src/effects/studio/PaletteChannel.gd")
const EffectPaletteSaver = preload("res://src/effects/studio/EffectPaletteSaver.gd")
const PaletteDataClass = ExMateriaEffects.PaletteData

const EFFECT_ID := 317
const EFFECT_DIR := "res://assets/effects/E317"
const BASE_BIN := "res://../project-assets/fft-extract/EFFECT/E317.BIN"

# The ONE ROM layout (parse_effect.PALETTE_TRACK_OFFSETS / field offsets), for the byte reparse.
const TRACK_OFFSETS := {
	"for_each": {"affected_units": 806, "caster": 1006, "target": 1206},
	"phase1": {"affected_units": 3550, "caster": 3750, "target": 3950},
	"phase2": {"affected_units": 4450, "caster": 4650, "target": 4850},
}
const OFF_RGB := 0x42   # + i*3, u8 R/G/B

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_a_palette_edit_reaches_the_written_bin()

	print("\n=== EffectPaletteSaveRoundTripTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPaletteSaveRoundTripTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPaletteSaveRoundTripTest")
		get_tree().quit(0)


func _test_a_palette_edit_reaches_the_written_bin() -> void:
	var base_abs := ProjectSettings.globalize_path(BASE_BIN).simplify_path()
	if not FileAccess.file_exists(base_abs):
		print("[SKIP] E317 base BIN absent (%s) — ROM extract not populated" % base_abs)
		_passed += 1  # environment gap, not a failure
		return

	var data = EffectData.load_from_directory(EFFECT_DIR)
	_assert_eq(data != null and data.palette != null, true, "E317 loads with a palette")

	var found := _first_enabled_keyframe(data.palette)
	if found.is_empty():
		print("[SKIP] no enabled palette keyframe on E317 — save round-trip skipped")
		_passed += 1
		return
	var phase: String = found["phase"]
	var channel_name: String = found["channel_name"]
	var index: int = found["index"]
	var kf = found["kf"]

	# Edit rgb.r through the choke point to a distinct value (a clean single-byte change).
	var new_r: int = (int(kf.rgb.x) + 7) & 0xFF
	if new_r == int(kf.rgb.x):
		new_r = (new_r + 1) & 0xFF
	PaletteChannel.apply_raw(data, {
		"channel": "palette", "context": phase, "channel_name": channel_name,
		"event_index": index, "field": "r"}, new_r)
	_assert_eq(int(kf.rgb.x), new_r, "the choke point wrote the new red byte on the live keyframe")

	# Save: pristine base → authored_effects/E317.BIN (palette section re-serialized).
	var res_save: Dictionary = EffectPaletteSaver.save(EFFECT_ID, data.palette)
	_assert_eq(res_save.get("ok", false), true, "the save succeeded (%s)" % str(res_save.get("error", "")))
	if not res_save.get("ok", false):
		return

	var out_bytes := FileAccess.get_file_as_bytes(res_save["out_path"])
	var base_bytes := FileAccess.get_file_as_bytes(base_abs)
	_assert_eq(out_bytes.size(), base_bytes.size(), "the patched BIN keeps the base byte length")
	_assert_eq(out_bytes != base_bytes, true, "the edit actually changed bytes (not a no-op)")

	# Re-read the edited rgb.r straight from the written BIN at its independently-computed offset.
	var timeline_ptr := _timeline_ptr()
	var channel_base: int = (timeline_ptr + 8 if phase == "for_each" else timeline_ptr) \
		+ int(TRACK_OFFSETS[phase][channel_name])
	var rgb_r_off: int = channel_base + OFF_RGB + index * 3
	_assert_eq(out_bytes[rgb_r_off], new_r, "the edited red byte landed in the written BIN")


# --- helpers ----------------------------------------------------------------

func _first_enabled_keyframe(palette) -> Dictionary:
	for phase in palette.channels.keys():
		for channel_name in PaletteDataClass.ALL_CHANNELS:
			var ch = palette.get_channel(phase, channel_name)
			if ch == null:
				continue
			for i in range(ch.keyframes.size()):
				if ch.keyframes[i].enabled:
					return {"phase": phase, "channel_name": channel_name, "index": i, "kf": ch.keyframes[i]}
	return {}


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
