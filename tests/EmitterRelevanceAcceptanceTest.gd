extends Node
## Field-relevance salience ACCEPTANCE (ADR-0089 amendment, headful, real E317):
## boots the EffectViewer, opens the bare browser for emitter idx 6 — the grounding
## fixture (every curve index 0, flags_lo 0x60): only a handful of its ~16 groups
## are Live, the rest Inactive/Dead — and asserts the salience contract on live
## widgets (Dead groups gathered under a collapsed "N hidden" reveal; Inactive
## groups marked, not hidden; end-axis-Dead notes; gate switches carrying
## bidirectional markers). Saves a real-window screenshot for the human review pass
## (field dumps don't count — the FedsPairStrip lesson):
##   /tmp/e317_emitter6_relevance.png
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EmitterRelevanceAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 317
const EMITTER_IDX := 6
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Oracle = preload("res://src/effects/studio/EmitterFieldRelevance.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_emitter6_reads_as_what_is_in_effect()

	print("\n=== EmitterRelevanceAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EmitterRelevanceAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EmitterRelevanceAcceptanceTest")
		get_tree().quit(0)


func _test_emitter6_reads_as_what_is_in_effect() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E%03d" % EFFECT_ID)):
		print("[SKIP] E%03d assets not available — acceptance skipped" % EFFECT_ID)
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E%03d" % EFFECT_ID):
			dir = d
	_assert_true(dir != "", "E%03d is in the effect catalogue" % EFFECT_ID)
	page._load_effect(dir)
	await _frames(30)

	var data = page._effect_data
	_assert_true(data != null and data.emitters.size() > EMITTER_IDX,
		"E%03d loads with emitter %d" % [EFFECT_ID, EMITTER_IDX])

	# Bare emitter browser for idx 6 — the same folds/salience both surfaces share.
	page._set_root(Target.emitter(EMITTER_IDX))
	await _frames(8)
	var insp = page._inspector

	# Every curve nibble is 0 on this emitter, so EVERY two-axis group is end-axis
	# Dead — the inspector flags the unread end column in place.
	var end_marks := 0
	var inactive := 0
	var gate := 0
	var dead := 0
	for m in insp.relevance_markers():
		match str(m.get("kind", "")):
			"end_dead": end_marks += 1
			"inactive": inactive += 1
			"gate": gate += 1
			"dead": dead += 1
	_assert_true(end_marks >= 1, "curve-less groups flag their end axis as unused (%d)" % end_marks)
	_assert_true(inactive >= 1, "at-neutral groups are marked Inactive, not hidden (%d)" % inactive)

	# Dead groups (target offset when homing is zero, etc.) are gathered under a
	# collapsed per-section reveal — the field-count win.
	var hidden_total := 0
	for r in insp.hidden_reveals():
		hidden_total += int(r.get("count", 0))
		_assert_true(not r["body"].visible, "the hidden reveal starts collapsed")
	print("[SALIENCE] emitter %d — end_dead=%d inactive=%d gate=%d dead=%d hidden_groups=%d" %
		[EMITTER_IDX, end_marks, inactive, gate, dead, hidden_total])

	# THE VELOCITY-FAMILY BUG (this handoff): emitter 6 is Outward with outward speed 0,
	# so Launch direction / Direction scatter are annihilated (direction × 0 = 0) and now
	# gather under the Dead reveal — with a formula view explaining why, once for the section.
	var vf: Array = insp.velocity_formulas()
	_assert_true(vf.size() == 1, "one velocity formula view renders on emitter 6 (%d)" % vf.size())
	if not vf.is_empty():
		_assert_true(str(vf[0].get("mode", "")) == "outward",
			"emitter 6 reads as the Outward, radial-0 annihilation")
		_assert_true("Outward speed" in str(vf[0].get("fix", "")),
			"the fix line points at the one knob: set Outward speed > 0")
		print("[VELOCITY] emitter %d formula fix: %s (marked=%s)" %
			[EMITTER_IDX, str(vf[0].get("fix", "")), str(vf[0].get("marked", []))])

	# Scroll a few folds down (past the provenance header) so the markers + reveal
	# land in frame, then capture the real window.
	var folds: Array = insp.param_folds()
	if folds.size() > 6:
		insp.get_child(0).ensure_control_visible(folds[mini(8, folds.size() - 1)]["header"])
	await _frames(4)
	_shot(insp, "/tmp/e317_emitter6_relevance.png")

	# THE FIX (this handoff): editing an input inside an Inactive ("!") fold must WAKE it — the
	# `!` clears — because the page reprojects the inspector when a plain value edit flips a
	# relevance verdict. Pick a currently-Inactive numeric group (one that GATES nothing, so
	# exactly one marker moves), edit one of its fields non-neutral through the REAL page choke
	# point, and assert the Inactive `!` count drops by one. This is the end-to-end proof that the
	# stale-marker symptom is gone; before the fix, `_apply_edit` never reprojected here.
	var em = data.get_emitter(EMITTER_IDX)
	var wake := _pick_inactive_wake_field(em)
	_assert_true(not wake.is_empty(), "emitter %d has a wake-able Inactive group" % EMITTER_IDX)
	if not wake.is_empty():
		page._apply_edit({"channel": "emitter", "emitter_index": EMITTER_IDX,
			"field": wake["field"]}, int(wake["value"]))
		await _frames(6)
		var inactive_after := 0
		for m in insp.relevance_markers():
			if str(m.get("kind", "")) == "inactive":
				inactive_after += 1
		_assert_true(inactive_after == inactive - 1,
			"waking one Inactive group clears exactly one `!` (%d → %d)" % [inactive, inactive_after])
		print("[WAKE] %s=%d → inactive %d → %d" % [wake["field"], int(wake["value"]), inactive, inactive_after])
		_shot(insp, "/tmp/e317_emitter6_relevance_after_wake.png")


## The first currently-Inactive numeric group's wake field + a non-neutral value, or {} if none.
## Restricted to groups that GATE nothing so waking moves EXACTLY one salience marker — the
## assertion above counts on the clean −1. Excludes homing_strength AND the velocity family:
## radial_velocity now GATES the direction groups (ADR-0089 velocity amendment), so waking it
## would un-dead two folds at once; the direction groups are Dead here, not Inactive, anyway.
func _pick_inactive_wake_field(em) -> Dictionary:
	var groups: Dictionary = Oracle.verdicts(em).get("groups", {})
	# "weight" (shown as "Gravity scale") first — it sits high in the born-with list, so the
	# before/after screenshots capture its `!` clearing in frame.
	var candidates := {
		"weight": "weight_min_start", "drag": "drag_min_start_x",
		"acceleration": "acceleration_min_start_x", "spread": "spread_start_x",
	}
	for id in candidates:
		var g: Dictionary = groups.get(id, {})
		if str(g.get("state", "")) == Oracle.INACTIVE and g.get("gates", []).is_empty():
			return {"field": candidates[id], "value": 100}
	return {}


func _shot(ctrl: Control, path: String) -> void:
	var img := ctrl.get_window().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s" % path)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
