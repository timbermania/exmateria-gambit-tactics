extends Node
## ADR-0089 inspector-presentation ACCEPTANCE (#291, headful, real E019): boots the
## real EffectViewer, parks E019 in the Studio, and drives BOTH surfaces —
## a particle span's inspector and the bare emitter browser — asserting the
## presentation contract on live widgets (grouped single-column folds, collapsed
## fresh inspect, header summaries, used-window sparklines) and saving real-window
## screenshots for the human review pass (field dumps don't count — the
## FedsPairStrip lesson):
##   /tmp/e019_span_inspector_collapsed.png
##   /tmp/e019_span_inspector_expanded.png
##   /tmp/e019_emitter_browser.png
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectEmitterInspectorUxAcceptanceTest.tscn

const EFFECT_SCENE := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 19
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const EmitterChannel = preload("res://src/effects/studio/EmitterChannel.gd")

# The 14 evolution-clock curve-assignment fields (ADR-0089) — the span surface
# dims THESE by the firing window (over-life colour/homing dim by lifetime).
const EVOLUTION_CURVE_FIELDS := [
	"curve_position", "curve_spread", "curve_velocity_base_angle",
	"curve_velocity_dir_spread", "curve_inertia", "curve_weight",
	"curve_radial_velocity", "curve_acceleration", "curve_drag", "curve_lifetime",
	"curve_target_offset", "curve_particle_count", "curve_spawn_interval",
	"curve_homing_strength"]

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_span_inspector_and_browser_present_grouped_folds()

	print("\n=== EffectEmitterInspectorUxAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectEmitterInspectorUxAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectEmitterInspectorUxAcceptanceTest")
		get_tree().quit(0)


func _test_span_inspector_and_browser_present_grouped_folds() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available — acceptance skipped")
		_passed += 1
		return

	var scn = load(EFFECT_SCENE).instantiate()
	add_child(scn)
	await _frames(30)

	# Load THROUGH the page (the KindSelector pattern): the page owns the
	# inspector and re-binds its _effect_data to the host's live model — selecting
	# on the scene alone leaves the page projecting the startup effect.
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with("E%03d" % EFFECT_ID):
			dir = d
	_assert_true(dir != "", "E%03d is in the effect catalogue" % EFFECT_ID)
	page._load_effect(dir)
	await _frames(30)

	var insp = page._inspector
	var data = page._effect_data
	_assert_true(data != null and not data.emitters.is_empty(), "E019 loads with emitters")

	# Pick a particle span whose emitter has an assigned curve and a sub-160-frame
	# firing, so the used-window dimming is actually VISIBLE in the screenshot.
	var span := _curve_assigned_span(page._timeline._score, data)
	_assert_true(not span.is_empty(), "E019 offers a curve-assigned particle span")
	page._on_span_selected(str(span.get("id", "")))
	await _frames(4)

	# Span surface: grouped folds, all collapsed on fresh inspect, summaries on
	# the headers, at least one header sparkline dimmed by this firing's window.
	var folds: Array = insp.param_folds()
	_assert_true(folds.size() >= 10, "span inspector hangs a fold per parameter group")
	var all_collapsed := true
	for f in folds:
		if f["body"].visible:
			all_collapsed = false
	_assert_true(all_collapsed, "fresh inspect = every fold collapsed")
	_assert_true(insp.fold_bulk_buttons().size() >= 1, "Expand all / Collapse all present")
	var window := int(span["end"]) - int(span["start"])
	var dimmed := 0
	for s in insp.sparklines():
		if s.used_window() == window and s.is_enabled():
			dimmed += 1
	_assert_true(dimmed > 0, "a live sparkline dims by this firing's %d-frame window" % window)
	_shot(insp, "/tmp/e019_span_inspector_collapsed.png")

	# Expand a curve-assigned fold (its cells + curve-row sparkline take over)
	# and scroll it into view so the shot shows the [enum, sparkline] strip.
	for f in folds:
		if f["spark"] != null:
			f["header"].button_pressed = true
			await _frames(2)
			insp.get_child(0).ensure_control_visible(f["body"])
			break
	await _frames(4)
	_shot(insp, "/tmp/e019_span_inspector_expanded.png")

	# Browser surface: same folds hung on the same explicit group identity, the
	# evolution window now the WIDEST firing of that emitter.
	page._set_root(Target.emitter(int(span.get("emitter_index", 0))))
	await _frames(4)
	var bfolds: Array = insp.param_folds()
	_assert_true(bfolds.size() >= 10, "emitter browser hangs the same parameter-group folds")
	_assert_true(bfolds[0]["key"] == folds[0]["key"],
		"both surfaces key folds off the same (emitter, group) identity")
	# E019 emitter 0 has a long provenance header — scroll the folds into frame.
	insp.get_child(0).ensure_control_visible(bfolds[mini(4, bfolds.size() - 1)]["header"])
	await _frames(2)
	_shot(insp, "/tmp/e019_emitter_browser.png")


## The first particle span whose emitter has any assigned curve nibble and a
## duration under 160 frames (so the tail-dim is visible), else {}.
func _curve_assigned_span(score: Dictionary, data) -> Dictionary:
	for lane in score.get("lanes", []):
		if lane.get("kind", "") != "particle":
			continue
		for span in lane.get("spans", []):
			var ei := int(span.get("emitter_index", -1))
			if ei < 0 or ei >= data.emitters.size():
				continue
			var dur := int(span.get("end", 0)) - int(span.get("start", 0))
			if dur <= 0 or dur >= 160:
				continue
			for field in EVOLUTION_CURVE_FIELDS:
				if EmitterChannel.read_raw(data.emitters[ei], str(field)) > 0:
					return span
	return {}


## Capture the WINDOW that hosts `ctrl` — the Studio lives in the DebugDashboard,
## a separate OS Window (its own viewport), not the main game viewport.
func _shot(ctrl: Control, path: String) -> void:
	var img := ctrl.get_window().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s" % path)


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
