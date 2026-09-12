extends Node
## TDD guard (#273, ADR-0094) for the script-pattern SWAP through the mutation choke
## point (EffectEditSession) — the third effect_settings tenant beside Timeline (#271)
## and Flags (#272). A swap fans the target choice index on the `script_pattern`
## channel; EffectScriptChannel regenerates the ROOT script_ops to the target canonical
## pattern (prologue preserved), declares invalidates_sim + invalidates_layout, and the
## session records a STRUCTURAL snapshot so undo restores the pre-swap script wholesale.
##
## Custom / CODE-format / non-canonical scripts are REFUSED (read-only). A swap to the
## already-current pattern is a no_edit (records nothing).
##
## Run: <GODOT> --path . --quit-after 3 res://tests/EffectScriptSwapTest.tscn

const EffectData = ExMateriaEffects.EffectData

const EffectEditSessionClass = preload("res://src/effects/studio/EffectEditSession.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const ESP = preload("res://src/effects/studio/EffectScriptPattern.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_swap_3phase_to_1phase()
	_test_undo_restores_3phase()
	_test_swap_to_same_pattern_is_noop()
	_test_code_format_is_refused()
	_test_custom_is_refused()

	print("\n=== EffectScriptSwapTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScriptSwapTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScriptSwapTest")
		get_tree().quit(0)


# E001-shaped 3-phase root fixture (texture_page 16, no callbacks), DATA format.
func _op(offset: int, opcode: int, name: String, flags: int, size: int, arg1 = null, arg2 = null) -> Dictionary:
	var d := {"offset": offset, "opcode": opcode, "name": name, "flags": flags, "size": size}
	if arg1 != null:
		d["arg1"] = arg1
	if arg2 != null:
		d["arg2"] = arg2
	return d


func _e001_data() -> EffectData:
	var ed = EffectDataClass.new()
	ed.script_code_format = false
	ed.script_ops = [
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
	return ed


func _ref() -> Dictionary:
	return {"channel": "script_pattern"}


func _test_swap_3phase_to_1phase() -> void:
	var ed = _e001_data()
	var session = EffectEditSessionClass.new(ed)
	# choice index 1 -> "1-phase".
	var res: Dictionary = session.apply_edit(_ref(), 1)
	_assert_true(not res.is_empty(), "a swap is applied")
	_assert_eq(ESP.detect(ed.script_ops), "1-phase", "script_ops now detects as 1-phase")
	_assert_true(bool(res.get("structural", false)), "swap is structural (full re-project — the choice re-seeds)")
	_assert_true(bool(res.get("invalidates_layout", false)), "swap re-flows the score (invalidates_layout)")
	_assert_true(bool(res.get("invalidates_sim", false)), "swap re-pumps the sim (invalidates_sim)")
	# The 1-phase prologue kept the texture page and gained clear_timeline_a (op 42).
	_assert_eq(int((ed.script_ops[0] as Dictionary)["flags"]), 16, "texture page preserved through swap")
	_assert_eq(int((ed.script_ops[1] as Dictionary)["opcode"]), 42, "clear_timeline_a added for 1-phase")


func _test_undo_restores_3phase() -> void:
	var ed = _e001_data()
	var session = EffectEditSessionClass.new(ed)
	session.apply_edit(_ref(), 1)
	_assert_eq(ESP.detect(ed.script_ops), "1-phase", "swapped to 1-phase")
	var ok: bool = session.undo()
	_assert_true(ok, "undo reports success")
	_assert_eq(ESP.detect(ed.script_ops), "3-phase", "undo restores the 3-phase script")
	_assert_eq(ed.script_ops.size(), 11, "the pre-swap root op count is restored")


func _test_swap_to_same_pattern_is_noop() -> void:
	var ed = _e001_data()
	var session = EffectEditSessionClass.new(ed)
	# choice index 0 -> "3-phase" — already the current pattern.
	var res: Dictionary = session.apply_edit(_ref(), 0)
	_assert_true(res.get("no_edit", false), "swapping to the current pattern is a no_edit")
	_assert_eq(ESP.detect(ed.script_ops), "3-phase", "script unchanged")
	# Nothing was recorded — undo finds nothing.
	_assert_true(not session.undo(), "a no_edit records no undo entry")


func _test_code_format_is_refused() -> void:
	var ed = _e001_data()
	ed.script_code_format = true  # CODE-format: script is MIPS, not editable
	var session = EffectEditSessionClass.new(ed)
	var res: Dictionary = session.apply_edit(_ref(), 1)
	_assert_true(res.is_empty(), "a CODE-format script refuses the swap")
	_assert_eq(ESP.detect(ed.script_ops), "3-phase", "script unchanged")


func _test_custom_is_refused() -> void:
	var ed = EffectDataClass.new()
	ed.script_code_format = false
	# E306-shaped Custom: op41 but no op31 -> not swappable.
	ed.script_ops = [
		_op(0, 5, "set_texture_page", 16, 2),
		_op(2, 39, "init_physics_params", 0, 2),
		_op(4, 30, "branch_anim_done_complex", 0, 4, 18),
		_op(8, 41, "process_timeline_frame", 0, 4, 32),
		_op(12, 4, "end", 0, 2),
	]
	var session = EffectEditSessionClass.new(ed)
	var res: Dictionary = session.apply_edit(_ref(), 1)
	_assert_true(res.is_empty(), "a Custom script refuses the swap")


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
