extends Node
## TDD guard (#273, ADR-0094) for the score REFLOW on a script-pattern swap. A swap
## rewrites ONLY the script section; the phase-1/phase-2 timeline data is left
## DORMANT (kept, no longer ticked). The Studio score must hide the Phase 1 / Phase 2
## sections while the pattern is `1-phase` (for-each only) and restore them on
## swap-back — driven purely off EffectScoreModel.build(...)["phases"], which now
## gates non-for-each phases on the detected pattern.
##
## Uses the real E001 (3-phase) effect and flips its live script_ops to the canonical
## 1-phase root (the swap's in-memory effect), then rebuilds the score.
##
## Run: <GODOT> --path . --quit-after 3 res://tests/EffectScriptReflowTest.tscn

const EffectScoreModel = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const ESP = preload("res://src/effects/studio/EffectScriptPattern.gd")
const EffectPhase = ExMateriaEffects.EffectPhase

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var ed = EffectDataClass.load_from_directory("res://assets/effects/E001")
	if ed == null or not (ed.script_ops is Array) or ed.script_ops.is_empty():
		print("  [FAIL] could not load E001 effect data")
		get_tree().quit(1)
		return

	# 3-phase (as authored): the for-each phase and at least one outer phase are present.
	var score3: Dictionary = EffectScoreModel.build(ed)
	var phases3 := _phase_names(score3)
	_assert_true(EffectPhase.PHASE_FOR_EACH in phases3, "3-phase score has a For-each section")
	_assert_true(EffectPhase.PHASE1 in phases3 or EffectPhase.PHASE2 in phases3,
		"3-phase score shows at least one outer phase section")

	# Swap in-memory to 1-phase (keep the prologue), then rebuild.
	var pro: Dictionary = ESP.extract_prologue(ed.script_ops)
	ed.script_ops = ESP.regenerate_root_ops("1-phase", int(pro["texture_page"]), pro["callbacks"])
	_assert_eq(ESP.detect(ed.script_ops), "1-phase", "flipped script_ops re-detects as 1-phase")

	var score1: Dictionary = EffectScoreModel.build(ed)
	var phases1 := _phase_names(score1)
	_assert_true(EffectPhase.PHASE_FOR_EACH in phases1, "1-phase score keeps the For-each section")
	_assert_true(not (EffectPhase.PHASE1 in phases1), "1-phase score hides Phase 1")
	_assert_true(not (EffectPhase.PHASE2 in phases1), "1-phase score hides Phase 2")

	# Swap back to 3-phase: the outer phase sections reappear (dormant data restored).
	ed.script_ops = ESP.regenerate_root_ops("3-phase", int(pro["texture_page"]), pro["callbacks"])
	var score_back: Dictionary = EffectScoreModel.build(ed)
	var phases_back := _phase_names(score_back)
	_assert_true(phases_back.size() == phases3.size(),
		"swap-back restores the same phase sections as the original 3-phase")

	print("\n=== EffectScriptReflowTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectScriptReflowTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectScriptReflowTest")
		get_tree().quit(0)


func _phase_names(score: Dictionary) -> Array:
	var out: Array = []
	for p in score.get("phases", []):
		out.append(String(p.get("name", "")))
	return out


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
