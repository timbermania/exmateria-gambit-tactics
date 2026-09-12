extends Node
## ADR-0089 ACCEPTANCE (headful, real E019 / Fire 4 — the emitter-rich tracker
## baseline): an emitter edit made through the LIVE Studio choke point must
## (1) re-fold the parked sim (invalidates_sim — particles are born from params),
## (2) reach the byte-patched E###.BIN via studio_save's layered chain, and
## (3) survive a reload of the saved BIN — verified by re-reading the written
## bytes at independently-computed record offsets, with EVERY other byte
## identical to the pristine source (the whole layered save stays byte-faithful).
##
## Edits: emitter 0's "Particles per burst" (particle_count_start u16 @0xB0) and
## "Gravity scale" (weight_min_start s16 @0x54) — the visually loud parameters
## the ADR names.
##
## Run: <GODOT> --path . --quit-after 240 res://tests/EffectEmitterSaveAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 19
const EFFECT_DIR := "res://assets/effects/E019"
const BASE_BIN := "res://../project-assets/fft-extract/EFFECT/E019.BIN"

# Independent record math (master_parser layout): records follow the 20-byte
# particle-system header at effect_data_ptr; 196 bytes each.
const PARTICLE_HEADER_SIZE := 20
const EMITTER_SIZE := 196
const OFF_WEIGHT_MIN_START := 0x54
const OFF_PARTICLE_COUNT_START := 0xB0

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_emitter_edit_refolds_saves_and_survives_reload()

	print("\n=== EffectEmitterSaveAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectEmitterSaveAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectEmitterSaveAcceptanceTest")
		get_tree().quit(0)


func _test_emitter_edit_refolds_saves_and_survives_reload() -> void:
	var base_abs := ProjectSettings.globalize_path(BASE_BIN).simplify_path()
	if not FileAccess.file_exists(base_abs):
		print("[SKIP] E019.BIN not available (ROM extract absent) — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)
	scn.studio_select_effect(EFFECT_ID)   # parked at frame 0, Studio owns the clock
	await _frames(20)

	var data = scn._current_effect.effect_data
	_assert_true(data != null and not data.emitters.is_empty(), "E019 loads with emitters")

	var src := FileAccess.get_file_as_bytes(base_abs)
	var em0: int = _emitter_base(0)

	# The edits: +3 particles per burst, gravity scale to a distinct raw.
	var new_count: int = src.decode_u16(em0 + OFF_PARTICLE_COUNT_START) + 3
	var new_weight: int = src.decode_s16(em0 + OFF_WEIGHT_MIN_START) + 512

	# (1) live choke-point edits at the parked frame — every emitter edit must
	# re-fold (read-live is impossible for spawned particles).
	var res1: Dictionary = scn.studio_apply_edit(
		{"channel": "emitter", "emitter_index": 0, "field": "particle_count_start"}, new_count)
	_assert_true(bool(res1.get("invalidates_sim", false)), "particle-count edit invalidates the sim")
	var res2: Dictionary = scn.studio_apply_edit(
		{"channel": "emitter", "emitter_index": 0, "field": "weight_min_start"}, new_weight)
	_assert_true(bool(res2.get("invalidates_sim", false)), "gravity-scale edit invalidates the sim")
	await _frames(6)
	_assert_true(is_instance_valid(scn._current_effect), "the parked effect survived the re-folds")
	_assert_eq(int(data.emitters[0].particle_count_start), new_count, "live model holds the edit")

	# (2) save: the layered chain patches every bridged section into ONE BIN.
	var res_save: Dictionary = scn.studio_save()
	_assert_true(res_save.get("ok", false),
		"studio_save() succeeds (%s)" % str(res_save.get("error", "")))
	if not res_save.get("ok", false):
		return

	# (3) reload the saved BIN's bytes: the edits landed at their independently-
	# computed offsets, and NOTHING else changed.
	var out := FileAccess.get_file_as_bytes(res_save.get("out_path", ""))
	_assert_eq(out.size(), src.size(), "the patched BIN keeps the base byte length")
	_assert_eq(out.decode_u16(em0 + OFF_PARTICLE_COUNT_START), new_count,
		"the saved BIN holds the new particle count")
	_assert_eq(out.decode_s16(em0 + OFF_WEIGHT_MIN_START), new_weight,
		"the saved BIN holds the new gravity scale")

	var allowed := {}
	for o in [em0 + OFF_PARTICLE_COUNT_START, em0 + OFF_PARTICLE_COUNT_START + 1,
			em0 + OFF_WEIGHT_MIN_START, em0 + OFF_WEIGHT_MIN_START + 1]:
		allowed[o] = true
	var stray: Array = []
	for i in range(src.size()):
		if src[i] != out[i] and not allowed.has(i):
			stray.append(i)
	_assert_true(stray.is_empty(),
		"no byte outside the two edited fields changed (stray: %s)" % str(stray.slice(0, 8)))


func _emitter_base(index: int) -> int:
	var h = JSON.parse_string(FileAccess.get_file_as_string("%s/header.json" % EFFECT_DIR))
	return int(h["header"]["effect_data_ptr"]) + PARTICLE_HEADER_SIZE + index * EMITTER_SIZE


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


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
