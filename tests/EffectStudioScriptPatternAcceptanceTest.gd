extends Node
## ACCEPTANCE (headful, real E019 = Fire 4, #273 / ADR-0094): the whole "Effect Settings →
## swap the script pattern → the score re-flows and playback still runs" path, end to end
## through the LIVE studio.
##   1. The "Effect ⚙" surface renders a "Script Pattern" section whose choice row is seeded to
##      E019's current pattern (3-phase = index 0), on the script_pattern channel.
##   2. The 3-phase score shows the outer phase sections (Phase 1 / Phase 2) beside For-each.
##   3. Swapping to 1-phase through the page choke point rewrites the live script (detects
##      1-phase) and the score COLLAPSES to For-each only — Phase 1 / Phase 2 hide.
##   4. Swapping back to 3-phase restores the outer phase sections (dormant timeline, not deleted).
##   5. Playback still runs after the swap: the live instance seeks/folds across frames without error.
## Skips when E019 assets are absent (gitignored/ROM-derived). A screenshot is written.
## Run: godot --path . --quit-after 400 res://tests/EffectStudioScriptPatternAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectPhase = ExMateriaEffects.EffectPhase
const SHOT := "user://script_pattern_e019.png"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioScriptPatternAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioScriptPatternAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioScriptPatternAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E019"):
			dir = d
	_assert_true(dir != "", "E019 in the effect catalogue")
	page._load_effect(dir)
	await _frames(40)

	var data = page._effect_data
	_assert_true(data != null and not data.script_ops.is_empty(), "E019 has a parsed script")
	if data == null or data.script_ops.is_empty():
		return

	# --- (1) The settings surface shows a Script Pattern choice seeded to 3-phase. ---
	page._open_effect_settings()
	await _frames(10)
	var sections = Model.inspector_sections(Target.effect_settings(), data, page._timeline._score)
	var sec := _find_section(sections, "Script Pattern")
	_assert_true(not sec.is_empty(), "the inspector shows a Script Pattern section")
	var row = sec.get("fields", [])[0] if not sec.get("fields", []).is_empty() else {}
	_assert_eq(str(row.get("editor", "")), "choice", "the pattern row is a choice selector")
	_assert_eq(int(row.get("value", -1)), 0, "the choice seeds E019's current pattern (3-phase = 0)")

	# --- (2) The 3-phase score shows the outer phase sections. ---
	var phases3 := _phase_names(page._timeline._score)
	_assert_true(EffectPhase.PHASE_FOR_EACH in phases3, "3-phase score has a For-each section")
	_assert_true(EffectPhase.PHASE1 in phases3 or EffectPhase.PHASE2 in phases3,
		"3-phase score shows at least one outer phase section")

	# --- (3) Swap to 1-phase → live script rewritten + score collapses to For-each. ---
	page._apply_edit({"channel": "script_pattern"}, 1)
	await _frames(30)
	_assert_true(_detect(data.script_ops) == "1-phase", "the live script is now 1-phase")
	var phases1 := _phase_names(page._timeline._score)
	_assert_true(EffectPhase.PHASE_FOR_EACH in phases1, "1-phase score keeps For-each")
	_assert_true(not (EffectPhase.PHASE1 in phases1), "1-phase score hides Phase 1")
	_assert_true(not (EffectPhase.PHASE2 in phases1), "1-phase score hides Phase 2")

	# --- (5) Playback still runs on the 1-phase effect (seek across frames, no error). ---
	for f in [1, 5, 10, 20]:
		page._seek(f)
		await _frames(2)
	_assert_true(page._timeline.get_playhead() >= 0, "playback seeks without error on the 1-phase effect")

	# Visual record of the collapsed score.
	await _frames(5)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))

	# --- (4) Swap back to 3-phase → the outer phase sections reappear. ---
	page._apply_edit({"channel": "script_pattern"}, 0)
	await _frames(30)
	_assert_true(_detect(data.script_ops) == "3-phase", "the live script is 3-phase again")
	var phases_back := _phase_names(page._timeline._score)
	_assert_eq(phases_back.size(), phases3.size(),
		"swap-back restores the same phase sections (dormant timeline, not deleted)")

	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))
	print("  phases 3->1->3: %s | %s | %s" % [str(phases3), str(phases1), str(phases_back)])


# --- helpers ------------------------------------------------------------------

const _OPSIZE := {0: 4, 4: 2, 22: 6, 29: 4, 30: 4, 31: 4, 37: 2, 39: 2, 40: 2, 41: 4, 42: 2, 5: 2, 6: 4}

func _detect(ops: Array) -> String:
	var ids := {}
	for op in ops:
		if op is Dictionary:
			ids[int(op.get("opcode", -1))] = true
	if ids.has(41) and ids.has(31):
		return "3-phase"
	if ids.has(40) and not ids.has(41):
		return "1-phase"
	return "Custom"


func _phase_names(score: Dictionary) -> Array:
	var out: Array = []
	for p in score.get("phases", []):
		out.append(String(p.get("name", "")))
	return out


func _find_section(sections: Array, title: String) -> Dictionary:
	for sec in sections:
		if str(sec.get("title", "")) == title:
			return sec
	return {}


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


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
