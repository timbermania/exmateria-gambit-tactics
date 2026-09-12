extends Node
## Acceptance (#273, ADR-0094) for the SCRIPT-PATTERN save chain, end to end with REAL file
## IO: EffectData.script_ops → EffectScriptSaver.to_script_json → the byte-exact Python writer
## (write_effect_script.py) → a patched E###.BIN. Proves the game→json→bin glue the studio's
## studio_save runs, on the real E019 (3-phase) ROM extract.
##
## Checks the four ADR "Consequences" at the file level:
##   1. Swap E019 → 1-phase produces a VALID intermediate: re-parse the header, detect 1-phase,
##      every downstream pointer lands 4-aligned + ascending (there-and-back alone can't prove this).
##   2. Section shrinks by exactly the delta (64 → 36 = 28 bytes).
##   3. There-and-back (3→1→3) at the file level is byte-identical to the pristine base.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/EffectScriptSaverAcceptanceTest.tscn

const EffectEditSessionClass = preload("res://src/effects/studio/EffectEditSession.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectScriptSaver = preload("res://src/effects/studio/EffectScriptSaver.gd")
const ESP = preload("res://src/effects/studio/EffectScriptPattern.gd")

const _OPSIZE := {0: 4, 1: 4, 2: 4, 3: 2, 4: 2, 5: 2, 6: 4, 7: 4, 8: 8, 9: 2, 10: 2, 11: 8,
	12: 2, 13: 2, 14: 8, 15: 2, 16: 4, 17: 6, 18: 6, 19: 6, 20: 6, 21: 6, 22: 6, 23: 6, 24: 6,
	25: 6, 26: 4, 27: 4, 28: 6, 29: 4, 30: 4, 31: 4, 32: 2, 33: 2, 34: 4, 35: 4, 36: 2, 37: 2,
	38: 2, 39: 2, 40: 2, 41: 4, 42: 2, 43: 2, 44: 2, 45: 2}

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var pristine_path := ProjectSettings.globalize_path("res://").path_join(
		"../project-assets/fft-extract/EFFECT/E019.BIN").simplify_path()
	if not FileAccess.file_exists(pristine_path):
		print("[SKIP] EffectScriptSaverAcceptanceTest — E019 ROM extract not present")
		get_tree().quit(0)
		return
	var pristine := FileAccess.get_file_as_bytes(pristine_path)

	var ed = EffectDataClass.load_from_directory("res://assets/effects/E019")
	if ed == null or ed.script_ops.is_empty():
		print("[FAIL] could not load E019")
		get_tree().quit(1)
		return
	_assert_eq(ESP.detect(ed.script_ops), "3-phase", "E019 loads as 3-phase")

	# Swap the live script to 1-phase through the choke point, then save (base = pristine extract).
	var session = EffectEditSessionClass.new(ed)
	session.apply_edit({"channel": "script_pattern"}, 1)
	_assert_eq(ESP.detect(ed.script_ops), "1-phase", "swapped in-memory to 1-phase")

	var res: Dictionary = EffectScriptSaver.save(19, ed.script_ops, "")
	_assert_true(bool(res.get("ok", false)), "1-phase save succeeds: %s" % str(res.get("error", "")))
	if not res.get("ok", false):
		_finish()
		return
	var swapped := FileAccess.get_file_as_bytes(res["out_path"])

	# Consequence 1 + 2: the intermediate file is a VALID 1-phase effect.
	_assert_eq(_detect_bin(swapped), "1-phase", "the saved BIN re-parses as 1-phase")
	_assert_pointers_valid(swapped)
	_assert_eq(swapped.size(), pristine.size() - 28, "the file shrank by the section delta (28)")

	# Consequence 3: there-and-back at the file level. Feed the swapped BIN back as the base and
	# swap to 3-phase — it must reproduce the pristine bytes exactly.
	session.undo()  # live script back to 3-phase (not strictly needed; save reads the base)
	var back: Dictionary = EffectScriptSaver.save(19, ed.script_ops, res["out_path"])
	_assert_true(bool(back.get("ok", false)), "swap-back save succeeds")
	if back.get("ok", false):
		var restored := FileAccess.get_file_as_bytes(back["out_path"])
		_assert_true(restored == pristine, "3→1→3 at the file level is byte-identical to pristine E019")

	_finish()


func _finish() -> void:
	print("\n=== EffectScriptSaverAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScriptSaverAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScriptSaverAcceptanceTest")
		get_tree().quit(0)


# --- independent BIN parse (not via the writer) -------------------------------

func _u32(b: PackedByteArray, off: int) -> int:
	return b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24)


func _detect_bin(b: PackedByteArray) -> String:
	var script_ptr := _u32(b, 0x08)
	var effect_data_ptr := _u32(b, 0x0C)
	var ids := {}
	var pos := script_ptr
	while pos + 2 <= effect_data_ptr:
		var oid: int = b[pos] | (b[pos + 1] << 8)
		oid = oid & 0x1FF
		ids[oid] = true
		pos += int(_OPSIZE.get(oid, 2))
		if oid == 4:
			break
	if ids.has(41) and ids.has(31):
		return "3-phase"
	if ids.has(40) and not ids.has(41):
		return "1-phase"
	return "Custom"


func _assert_pointers_valid(b: PackedByteArray) -> void:
	var prev := _u32(b, 0x08)  # script_ptr
	for off in [0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24]:
		var p := _u32(b, off)
		if p == 0:
			continue
		_assert_true(p % 4 == 0, "pointer 0x%02X is 4-aligned (%d)" % [off, p])
		_assert_true(p <= b.size(), "pointer 0x%02X in bounds" % off)
		_assert_true(p > prev, "pointer 0x%02X ascends" % off)
		prev = p


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
