extends Node
## TDD guard (#273, ADR-0094) for EffectScriptPattern — the PURE script-pattern
## logic that the Studio surface and the score reflow ride on. `script.json` is
## ROOT-ONLY (parse stops at the first `end`), so everything here works on the
## observable root: detect the pattern, classify swappability (the strict-canonical
## + DATA gate), and regenerate the canonical ROOT op-list for a swap.
##
## The byte-exact whole-section rewrite (root + for-each child + tail-shift + header
## fix-up) lives in tools/write_effect_script.py; this mirrors its canonical layout
## on the root. Fixtures below are INDEPENDENT truth transcribed from the real ROM
## script.json of E001 (3-phase) and E043 (1-phase).
##
## Run: <GODOT> --path . --quit-after 3 res://tests/EffectScriptPatternTest.tscn

const ESP = preload("res://src/effects/studio/EffectScriptPattern.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_detect_3phase()
	_test_detect_1phase()
	_test_detect_custom()
	_test_extract_prologue_3phase()
	_test_extract_prologue_1phase_skips_clear_timeline()
	_test_extract_prologue_with_callbacks()
	_test_regenerate_3phase_root_matches_e001()
	_test_regenerate_1phase_root_matches_e043()
	_test_regenerate_with_callbacks_shifts_offsets()
	_test_classify_canonical_3phase_is_swappable()
	_test_classify_canonical_1phase_is_swappable()
	_test_classify_code_format_is_readonly()
	_test_classify_custom_is_readonly()
	_test_classify_noncanonical_outlier_is_readonly()
	_test_swap_regenerates_other_pattern_and_redetects()
	_test_other_pattern()

	print("\n=== EffectScriptPatternTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScriptPatternTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScriptPatternTest")
		get_tree().quit(0)


# --- independent fixtures (transcribed from real ROM script.json) -------------

func _op(offset: int, opcode: int, name: String, flags: int, size: int, arg1 = null, arg2 = null) -> Dictionary:
	var d := {"offset": offset, "opcode": opcode, "name": name, "flags": flags, "size": size}
	if arg1 != null:
		d["arg1"] = arg1
	if arg2 != null:
		d["arg2"] = arg2
	return d


# E001: 3-phase, set_texture_page flags=16, no callbacks. Root ends at the first `end`.
func _e001_root() -> Array:
	return [
		_op(0, 5, "set_texture_page", 16, 2),
		_op(2, 39, "init_physics_params", 0, 2),
		_op(4, 31, "branch_target_type", 0, 4, 34),
		_op(8, 30, "branch_anim_done_complex", 0, 4, 22),
		_op(12, 41, "process_timeline_frame", 0, 4, 36),
		_op(16, 37, "update_all_particles", 0, 2),
		_op(18, 0, "goto_yield", 0, 4, 8),
		_op(22, 37, "update_all_particles", 0, 2),
		_op(24, 22, "branch_count_eq", 0, 6, 0, 34),
		_op(30, 0, "goto_yield", 0, 4, 22),
		_op(34, 4, "end", 0, 2),
	]


# E043: 1-phase, set_texture_page flags=8, no callbacks. clear_timeline_a in the prologue.
func _e043_root() -> Array:
	return [
		_op(0, 5, "set_texture_page", 8, 2),
		_op(2, 42, "clear_timeline_a", 0, 2),
		_op(4, 39, "init_physics_params", 0, 2),
		_op(6, 31, "branch_target_type", 0, 4, 34),
		_op(10, 29, "branch_anim_done", 0, 4, 22),
		_op(14, 40, "for_each", 0, 2),
		_op(16, 37, "update_all_particles", 0, 2),
		_op(18, 0, "goto_yield", 0, 4, 10),
		_op(22, 37, "update_all_particles", 0, 2),
		_op(24, 22, "branch_count_eq", 0, 6, 0, 34),
		_op(30, 0, "goto_yield", 0, 4, 22),
		_op(34, 4, "end", 0, 2),
	]


# --- detect -------------------------------------------------------------------

func _test_detect_3phase() -> void:
	_assert_eq(ESP.detect(_e001_root()), "3-phase", "op41 + op31 -> 3-phase")


func _test_detect_1phase() -> void:
	_assert_eq(ESP.detect(_e043_root()), "1-phase", "op40 without op41 -> 1-phase")


func _test_detect_custom() -> void:
	# E306-shaped: has op41 but NO op31 branch_target_type -> Custom (read-only).
	var custom := [
		_op(0, 5, "set_texture_page", 16, 2),
		_op(2, 39, "init_physics_params", 0, 2),
		_op(4, 30, "branch_anim_done_complex", 0, 4, 18),
		_op(8, 41, "process_timeline_frame", 0, 4, 32),
		_op(12, 4, "end", 0, 2),
	]
	_assert_eq(ESP.detect(custom), "Custom", "op41 without op31 -> Custom")


# --- prologue -----------------------------------------------------------------

func _test_extract_prologue_3phase() -> void:
	var pro: Dictionary = ESP.extract_prologue(_e001_root())
	_assert_eq(int(pro.get("texture_page", -1)), 16, "3-phase texture page read from set_texture_page flags")
	_assert_eq((pro.get("callbacks", [1]) as Array).size(), 0, "no callbacks")


func _test_extract_prologue_1phase_skips_clear_timeline() -> void:
	var pro: Dictionary = ESP.extract_prologue(_e043_root())
	_assert_eq(int(pro.get("texture_page", -1)), 8, "1-phase texture page")
	_assert_eq((pro.get("callbacks", [1]) as Array).size(), 0, "clear_timeline_a is not a callback")


func _test_extract_prologue_with_callbacks() -> void:
	# E015-shaped prologue: 4 load_callbacks between set_texture_page and init_physics.
	var ops := [
		_op(0, 5, "set_texture_page", 32, 2),
		_op(2, 6, "load_callback", 0, 4, 7),
		_op(6, 6, "load_callback", 2, 4, 8),
		_op(10, 6, "load_callback", 4, 4, 9),
		_op(14, 6, "load_callback", 6, 4, 8),
		_op(18, 39, "init_physics_params", 0, 2),
		_op(20, 31, "branch_target_type", 0, 4, 50),
		_op(24, 30, "branch_anim_done_complex", 0, 4, 38),
		_op(28, 41, "process_timeline_frame", 0, 4, 52),
		_op(32, 37, "update_all_particles", 0, 2),
		_op(34, 0, "goto_yield", 0, 4, 24),
		_op(38, 37, "update_all_particles", 0, 2),
		_op(40, 22, "branch_count_eq", 0, 6, 0, 50),
		_op(46, 0, "goto_yield", 0, 4, 38),
		_op(50, 4, "end", 0, 2),
	]
	var pro: Dictionary = ESP.extract_prologue(ops)
	var cbs: Array = pro.get("callbacks", [])
	_assert_eq(cbs.size(), 4, "4 callbacks extracted")
	_assert_eq(cbs[0], [0, 7], "callback 0 = (slot 0, id 7)")
	_assert_eq(cbs[3], [6, 8], "callback 3 = (slot 6, id 8)")


# --- regenerate ---------------------------------------------------------------

func _test_regenerate_3phase_root_matches_e001() -> void:
	var regen: Array = ESP.regenerate_root_ops("3-phase", 16, [])
	_assert_true(_ops_equal(regen, _e001_root()), "regenerated 3-phase root == E001")


func _test_regenerate_1phase_root_matches_e043() -> void:
	var regen: Array = ESP.regenerate_root_ops("1-phase", 8, [])
	_assert_true(_ops_equal(regen, _e043_root()), "regenerated 1-phase root == E043")


func _test_regenerate_with_callbacks_shifts_offsets() -> void:
	var base: Array = ESP.regenerate_root_ops("3-phase", 16, [])
	var withcb: Array = ESP.regenerate_root_ops("3-phase", 16, [[0, 7], [2, 8]])
	# Two callbacks add 8 bytes: the final `end` offset shifts by 8.
	var base_end: int = int((base[base.size() - 1] as Dictionary)["offset"])
	var cb_end: int = int((withcb[withcb.size() - 1] as Dictionary)["offset"])
	_assert_eq(cb_end, base_end + 8, "two callbacks shift the root by 8 bytes")


# --- classify -----------------------------------------------------------------

func _test_classify_canonical_3phase_is_swappable() -> void:
	var c: Dictionary = ESP.classify(_e001_root(), true)
	_assert_eq(c.get("mode"), "3-phase", "mode is 3-phase")
	_assert_true(bool(c.get("swappable")), "canonical DATA 3-phase is swappable")


func _test_classify_canonical_1phase_is_swappable() -> void:
	var c: Dictionary = ESP.classify(_e043_root(), true)
	_assert_true(bool(c.get("swappable")), "canonical DATA 1-phase is swappable")


func _test_classify_code_format_is_readonly() -> void:
	# Even a canonical-looking script is read-only when the file is CODE-format.
	var c: Dictionary = ESP.classify(_e001_root(), false)
	_assert_true(not bool(c.get("swappable")), "CODE-format is read-only")
	_assert_true(String(c.get("read_only_reason", "")).contains("CODE"), "reason mentions CODE")


func _test_classify_custom_is_readonly() -> void:
	var custom := [
		_op(0, 5, "set_texture_page", 16, 2),
		_op(2, 39, "init_physics_params", 0, 2),
		_op(4, 30, "branch_anim_done_complex", 0, 4, 18),
		_op(8, 41, "process_timeline_frame", 0, 4, 32),
		_op(12, 4, "end", 0, 2),
	]
	var c: Dictionary = ESP.classify(custom, true)
	_assert_eq(c.get("mode"), "Custom", "Custom detected")
	_assert_true(not bool(c.get("swappable")), "Custom is read-only")


func _test_classify_noncanonical_outlier_is_readonly() -> void:
	# E225-shaped outlier: a 1-phase body MISSING the leading branch_target_type.
	# Detects as 1-phase but does not match the canonical body -> read-only.
	var outlier := [
		_op(0, 5, "set_texture_page", 8, 2),
		_op(2, 42, "clear_timeline_a", 0, 2),
		_op(4, 39, "init_physics_params", 0, 2),
		_op(6, 29, "branch_anim_done", 0, 4, 18),
		_op(10, 40, "for_each", 0, 2),
		_op(12, 37, "update_all_particles", 0, 2),
		_op(14, 0, "goto_yield", 0, 4, 6),
		_op(18, 37, "update_all_particles", 0, 2),
		_op(20, 22, "branch_count_eq", 0, 6, 0, 30),
		_op(26, 0, "goto_yield", 0, 4, 18),
		_op(30, 4, "end", 0, 2),
	]
	var c: Dictionary = ESP.classify(outlier, true)
	_assert_eq(c.get("mode"), "1-phase", "still detects as 1-phase")
	_assert_true(not bool(c.get("swappable")), "non-canonical body is read-only")


func _test_swap_regenerates_other_pattern_and_redetects() -> void:
	# A swap of E001 (3-phase) to 1-phase: keep the prologue (texture_page 16), drop
	# to the 1-phase canonical root (which grows a clear_timeline_a), re-detects 1-phase.
	var pro: Dictionary = ESP.extract_prologue(_e001_root())
	var swapped: Array = ESP.regenerate_root_ops(
		"1-phase", int(pro["texture_page"]), pro["callbacks"])
	_assert_eq(ESP.detect(swapped), "1-phase", "swapped root re-detects as 1-phase")
	# The 1-phase prologue keeps the texture page and gains clear_timeline_a.
	_assert_eq(int((swapped[0] as Dictionary)["flags"]), 16, "texture page preserved through swap")
	_assert_eq(int((swapped[1] as Dictionary)["opcode"]), 42, "clear_timeline_a added for 1-phase")


func _test_other_pattern() -> void:
	_assert_eq(ESP.other("3-phase"), "1-phase", "3-phase toggles to 1-phase")
	_assert_eq(ESP.other("1-phase"), "3-phase", "1-phase toggles to 3-phase")


# --- helpers ------------------------------------------------------------------

func _ops_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		print("  [ops_equal] size %d != %d" % [a.size(), b.size()])
		return false
	for i in range(a.size()):
		var x: Dictionary = a[i]
		var y: Dictionary = b[i]
		for key in ["offset", "opcode", "flags", "size"]:
			if int(x.get(key, -999)) != int(y.get(key, -998)):
				print("  [ops_equal] idx %d key %s: %s != %s" % [i, key, str(x.get(key)), str(y.get(key))])
				return false
		if int(x.get("arg1", -1)) != int(y.get("arg1", -1)):
			print("  [ops_equal] idx %d arg1: %s != %s" % [i, str(x.get("arg1")), str(y.get("arg1"))])
			return false
		if int(x.get("arg2", -1)) != int(y.get("arg2", -1)):
			print("  [ops_equal] idx %d arg2: %s != %s" % [i, str(x.get("arg2")), str(y.get("arg2"))])
			return false
	return true


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
