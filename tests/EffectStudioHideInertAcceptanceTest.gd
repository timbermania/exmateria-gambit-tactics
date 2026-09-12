extends Node
## "Hide inert" ACCEPTANCE (ADR-0089 amendment, headful, real E019 — the emitter-rich, base-0
## effect the design handoff names; NOT E317, which is CODE-format and parses 0 channels). Boots
## the EffectViewer, roots on the emitter carrying the most inert content, and drives the REAL
## page toolbar toggle (`_toggle_hide_inert`) to assert the LIVE-only contract on live widgets:
## with the toggle ON the Dead reveal, the Inactive/Dead `!` markers, and the now-empty rows all
## vanish while Live rows stay; waking a field under hide reveals it; toggling OFF restores the
## hidden knobs. Screenshots for the human review pass:
##   /tmp/e019_hide_inert_off.png  /tmp/e019_hide_inert_on.png  /tmp/e019_hide_inert_wake.png
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectStudioHideInertAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 19
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Oracle = preload("res://src/effects/studio/EmitterFieldRelevance.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_hide_inert_thins_the_real_emitter_panel()

	print("\n=== EffectStudioHideInertAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioHideInertAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioHideInertAcceptanceTest")
		get_tree().quit(0)


func _test_hide_inert_thins_the_real_emitter_panel() -> void:
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
	_assert_true(data != null and data.emitters.size() >= 1, "E%03d loads with emitters" % EFFECT_ID)

	# Pick the emitter with the most inert content, so the thinning is visible.
	var idx := _emitter_with_most_inert(data)
	_assert_true(idx >= 0, "some emitter carries inert (Inactive/Dead) content")
	page._set_root(Target.emitter(idx))
	await _frames(8)
	var insp = page._inspector

	# DEFAULT (toggle off): inert salience is present — markers + a Dead reveal.
	_assert_true(not page._hide_inert, "Hide inert defaults off")
	var off_markers := _marker_kinds(insp)
	var off_rows: int = insp.param_row_count()
	var off_reveals: int = insp.hidden_reveals().size()
	_assert_true(int(off_markers.get("inactive", 0)) + int(off_markers.get("dead", 0)) >= 1,
		"default: emitter %d shows Inactive/Dead salience" % idx)
	_shot(insp, "/tmp/e019_hide_inert_off.png")

	# TOGGLE ON via the real toolbar path — it re-renders in LIVE-only mode.
	page._toggle_hide_inert()
	await _frames(6)
	_assert_true(page._hide_inert, "toggle turns Hide inert on")
	var on_markers := _marker_kinds(insp)
	var on_rows: int = insp.param_row_count()
	_assert_true(int(on_markers.get("inactive", 0)) == 0, "hide: no Inactive markers survive")
	_assert_true(int(on_markers.get("dead", 0)) == 0, "hide: no Dead markers survive")
	_assert_true(insp.hidden_reveals().size() == 0, "hide: the Dead reveal is gone (was %d)" % off_reveals)
	_assert_true(insp.velocity_formulas().size() == 0, "hide: no velocity formula view")
	_assert_true(on_rows >= 1, "hide: Live rows still render")
	_assert_true(on_rows < off_rows, "hide: fewer rows than default (%d → %d)" % [off_rows, on_rows])
	print("[HIDE] emitter %d rows %d → %d, reveals %d → 0" % [idx, off_rows, on_rows, off_reveals])
	_shot(insp, "/tmp/e019_hide_inert_on.png")

	# WAKE under hide: editing an Inactive group non-neutral flips it Live, and the reproject
	# re-renders WITH hide still on, so the woken group reappears (more rows than the hidden view).
	var wake := _pick_inactive_wake_field(data.get_emitter(idx))
	if not wake.is_empty():
		page._apply_edit({"channel": "emitter", "emitter_index": idx, "field": wake["field"]},
			int(wake["value"]))
		await _frames(6)
		var woken_rows: int = insp.param_row_count()
		_assert_true(woken_rows > on_rows, "hide: waking %s reveals the woken rows (%d → %d)" %
			[wake["field"], on_rows, woken_rows])
		print("[WAKE] %s=%d → rows %d → %d" % [wake["field"], int(wake["value"]), on_rows, woken_rows])
		_shot(insp, "/tmp/e019_hide_inert_wake.png")

	# TOGGLE OFF restores the hidden knobs (the recovery path).
	page._toggle_hide_inert()
	await _frames(6)
	_assert_true(not page._hide_inert, "toggle off again")
	_assert_true(int(_marker_kinds(insp).get("inactive", 0)) >= 1,
		"off: the Inactive salience returns (recovery path)")


## The emitter index with the greatest count of Inactive+Dead groups (the richest thinning), or
## -1 if the effect has no inert content at all.
func _emitter_with_most_inert(data) -> int:
	var best := -1
	var best_n := 0
	for i in range(data.emitters.size()):
		var groups: Dictionary = Oracle.verdicts(data.get_emitter(i)).get("groups", {})
		var n := 0
		for id in groups:
			var st := str(groups[id].get("state", ""))
			if st == Oracle.INACTIVE or st == Oracle.DEAD:
				n += 1
		if n > best_n:
			best_n = n
			best = i
	return best


## The first currently-Inactive numeric group's wake field + a non-neutral value, restricted to
## groups that GATE nothing (so waking moves exactly this group Live), or {} if none.
func _pick_inactive_wake_field(em) -> Dictionary:
	var groups: Dictionary = Oracle.verdicts(em).get("groups", {})
	var candidates := {
		"weight": "weight_min_start", "drag": "drag_min_start_x",
		"acceleration": "acceleration_min_start_x", "spread": "spread_start_x",
	}
	for id in candidates:
		var g: Dictionary = groups.get(id, {})
		if str(g.get("state", "")) == Oracle.INACTIVE and g.get("gates", []).is_empty():
			return {"field": candidates[id], "value": 100}
	return {}


func _marker_kinds(insp) -> Dictionary:
	var counts := {}
	for m in insp.relevance_markers():
		var k := str(m.get("kind", ""))
		counts[k] = int(counts.get(k, 0)) + 1
	return counts


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
