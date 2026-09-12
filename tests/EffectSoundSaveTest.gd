extends Node
## TDD guard for the unified SOUND save bridge (ADR-0085 amendment 2026-08-11,
## slice 4): the three previously-unbridged sound seams — TIER-1 triggers
## (sound.json), TIER-2 containers (sound_containers.json), TIER-3 feds bytes —
## lower through ONE EffectSoundSaver (template: EffectCameraSaver) into the
## byte-exact Python sound-sections writer, layered onto studio_save's chain.
##
##   (1) The saver refuses when the effect carries nothing sound-ish.
##   (2) ACCEPTANCE (real extract): an UNEDITED save reproduces the source
##       E###.BIN byte-for-byte across all three sections.
##   (3) A FEDS byte edit through the choke point lands in the written BIN at
##       exactly its blob offset — and nowhere else.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/EffectSoundSaveTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const Saver = preload("res://src/effects/studio/EffectSoundSaver.gd")
const Session = preload("res://src/effects/studio/EffectEditSession.gd")

const BASE_BIN := "../project-assets/fft-extract/EFFECT/E317.BIN"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_refuses_without_sound_sections()
	_test_unedited_save_is_byte_identical()
	_test_feds_edit_lands_at_its_offset()

	print("\n=== EffectSoundSaveTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSoundSaveTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSoundSaveTest")
		get_tree().quit(0)


func _base_bin_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join(BASE_BIN).simplify_path()


func _test_refuses_without_sound_sections() -> void:
	var ed = EffectDataClass.new()
	var res: Dictionary = Saver.save(317, ed, "")
	_assert_eq(bool(res.get("ok", true)), false, "nothing sound-ish → refused, not a silent no-op")


func _test_unedited_save_is_byte_identical() -> void:
	if not FileAccess.file_exists(_base_bin_path()):
		print("[SKIP] ROM extract absent")
		return
	var ed = EffectDataClass.load_from_directory("res://assets/effects/E317")
	var res: Dictionary = Saver.save(317, ed, "")
	_assert_eq(bool(res.get("ok", false)), true, "unedited save succeeds (%s)" % res.get("error", ""))
	if not res.get("ok", false):
		return
	var out: PackedByteArray = FileAccess.get_file_as_bytes(res["out_path"])
	var base: PackedByteArray = FileAccess.get_file_as_bytes(_base_bin_path())
	_assert_eq(out.size(), base.size(), "output size matches the source")
	_assert_true(out == base, "UNEDITED save reproduces E317.BIN byte-for-byte")


func _test_feds_edit_lands_at_its_offset() -> void:
	if not FileAccess.file_exists(_base_bin_path()):
		print("[SKIP] ROM extract absent")
		return
	var ed = EffectDataClass.load_from_directory("res://assets/effects/E317")
	if ed.feds_bank == null:
		_assert_true(false, "E317 should carry a FEDS bank")
		return
	# Find a real param byte to patch: the first track's first opcode with params.
	var events: Array = ed.feds_bank.get_track_events(0)
	var patch_off := -1
	var before := -1
	for e in events:
		if e is ExMateriaSound.SoundOpcodes.OpcodeEvent and e.params.size() > 0:
			patch_off = ed.feds_bank.track_offsets[0] + e.offset + 1
			before = ed.feds_bank.raw[patch_off]
			break
	if patch_off < 0:
		print("[SKIP] E317 track 0 has no parameterized opcode")
		return
	var session = Session.new(ed)
	var new_val := (before + 1) % 128
	var eres: Dictionary = session.apply_edit(
			{"channel": "sound_def", "kind": "byte", "offset": patch_off, "pair_idx": 0}, new_val)
	_assert_eq(bool(eres.get("invalidates_feds", false)), true, "edit went through the choke point")

	var res: Dictionary = Saver.save(317, ed, "")
	_assert_eq(bool(res.get("ok", false)), true, "edited save succeeds (%s)" % res.get("error", ""))
	if res.get("ok", false):
		var out: PackedByteArray = FileAccess.get_file_as_bytes(res["out_path"])
		var base: PackedByteArray = FileAccess.get_file_as_bytes(_base_bin_path())
		# The header knows where the feds blob starts in the BIN.
		var header_txt := FileAccess.get_file_as_string("res://assets/effects/E317/header.json")
		var sound_def_ptr := int((JSON.parse_string(header_txt).get("header", {})).get("sound_def_ptr", -1))
		var diffs: Array = []
		for i in range(base.size()):
			if out[i] != base[i]:
				diffs.append(i)
		_assert_eq(diffs, [sound_def_ptr + patch_off],
				"the ONE edited FEDS byte is the only difference")
		if diffs.size() == 1:
			_assert_eq(int(out[diffs[0]]), new_val, "the new byte value landed")

	# Restore the cached EffectData (load_from_directory caches per dir).
	session.undo()
	_assert_eq(int(ed.feds_bank.raw[patch_off]), before, "session undo restores the byte")


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
