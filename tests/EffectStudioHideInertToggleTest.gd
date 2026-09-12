extends Node
## Guard for the session-local "Hide inert" mode (ADR-0089 amendment). Drives the real
## EmitterProjector → EffectKeyframeInspector path with a fixture emitter and asserts the
## LIVE-only contract: with hide_inert ON, Inactive/Dead folds and lone fields, suppressing
## gates at their neutral, the Dead "N hidden" reveal, and the velocity formula view all
## vanish, while Live rows stay and a section left with no live rows omits its header.
## Default (OFF) view is unchanged. Headful E019 is the human acceptance; this is the fast
## per-build regression.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/EffectStudioHideInertToggleTest.tscn

const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const Projector = preload("res://src/effects/studio/EmitterProjector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0
var _insp = null
var _ed = null
var _sections: Array = []
var _cp: Callable = func(_i): return []


func _ready() -> void:
	await _boot()
	await _test_default_view_shows_inert_salience()
	await _test_hide_inert_drops_inactive_dead_keeps_live_gates()
	await _test_hide_inert_suppresses_reveal_and_formula()
	await _test_hide_inert_keeps_live_rows_and_thins_the_panel()
	await _test_hide_inert_prunes_an_all_inert_sections_header()

	print("\n=== EffectStudioHideInertToggleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioHideInertToggleTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioHideInertToggleTest")
		get_tree().quit(0)


func _boot() -> void:
	_ed = _effect_editable()
	_insp = Inspector.new()
	_insp.custom_minimum_size = Vector2(420, 900)
	add_child(_insp)
	await get_tree().process_frame
	var span = Model.build(_ed)["lanes"][0]["spans"][0]
	_sections = Projector.sections(span, _ed)
	_cp = func(idx: int) -> Array:
		var c = _ed.get_curve(idx)
		return c.samples if c else []


## Render the fixture through the inspector at the given hide-inert mode.
func _show(hide_inert: bool) -> void:
	_insp.show_target(Target.emitter(0), [], _sections, _cp, func(_ci, _n): pass,
		func(_t): pass, func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_ref, _raw): pass, func(_refs, _col): return Color.BLACK, hide_inert)
	await get_tree().process_frame


func _marker_kinds() -> Dictionary:
	var counts := {}
	for m in _insp.relevance_markers():
		var k := str(m.get("kind", ""))
		counts[k] = int(counts.get(k, 0)) + 1
	return counts


## Baseline: the DEFAULT view (hide_inert off) still surfaces the inert salience — the
## Dead reveal, the Inactive/gate markers — so the hide-mode assertions below test the delta.
func _test_default_view_shows_inert_salience() -> void:
	await _show(false)
	var kinds := _marker_kinds()
	_assert_true(int(kinds.get("inactive", 0)) >= 1, "default: Inactive fields are marked")
	_assert_true(int(kinds.get("dead", 0)) >= 1, "default: a Dead lone field is marked")
	_assert_true(int(kinds.get("gate", 0)) >= 1, "default: a suppressing gate is marked")
	_assert_true(_insp.hidden_reveals().size() >= 1, "default: a Dead reveal is built")


## Hide mode: every Inactive and Dead `!` marker is gone (the fields that carried them are
## not rendered) — this covers the suppressing gates AT THEIR NEUTRAL (homing_strength /
## outward speed 0), which self-classify Inactive. A gate switch that is itself Live (a real
## "mode disabled" config choice) still renders per the iff-Live rule, marker and all — so we
## assert those survive, pinning that hide mode never over-hides a Live row.
func _test_hide_inert_drops_inactive_dead_keeps_live_gates() -> void:
	await _show(true)
	var kinds := _marker_kinds()
	_assert_true(int(kinds.get("inactive", 0)) == 0, "hide: no Inactive markers survive (neutral gates included)")
	_assert_true(int(kinds.get("dead", 0)) == 0, "hide: no Dead markers survive")
	_assert_true(int(kinds.get("gate", 0)) >= 1, "hide: a Live suppressing-gate switch still renders")


## Hide mode: the Dead "N hidden (not in effect)" reveal and the velocity formula view are
## suppressed wholesale (not diverted, not built).
func _test_hide_inert_suppresses_reveal_and_formula() -> void:
	await _show(true)
	_assert_true(_insp.hidden_reveals().size() == 0, "hide: no Dead reveal is built")
	_assert_true(_insp.velocity_formulas().size() == 0, "hide: no velocity formula view is built")


## Hide mode keeps the Live rows (Position is curve-driven → Live) and renders strictly
## fewer param rows than the default view — the panel thins, it does not empty.
func _test_hide_inert_keeps_live_rows_and_thins_the_panel() -> void:
	await _show(false)
	var default_rows: int = _insp.param_row_count()
	await _show(true)
	var hidden_rows: int = _insp.param_row_count()
	_assert_true(hidden_rows >= 1, "hide: Live rows still render")
	_assert_true(hidden_rows < default_rows, "hide: fewer rows than the default view")
	_assert_true(_insp.group_count() >= 1, "hide: at least one Live section survives")


## A section whose body renders zero live rows omits its header too — no bare headers. Two
## fabricated sections (one all-Dead, one Live): default shows both, hide shows only the Live
## one. Uses hand-built sections so the prune is observed independent of the projector.
func _test_hide_inert_prunes_an_all_inert_sections_header() -> void:
	var dead_field := {"name": "Blend R", "shape": "const", "value": "0",
		"group": {}, "relevance": {"state": "dead", "why": "colour disabled"}}
	var live_field := {"name": "Anim index", "shape": "const", "value": "3", "group": {}}
	var sections := [
		{"title": "Colour (off)", "fields": [dead_field]},
		{"title": "Config", "fields": [live_field]},
	]
	_render_sections(sections, false)
	await get_tree().process_frame
	_assert_true(_insp.group_count() == 2, "default: both sections render (all-Dead + Live)")
	_render_sections(sections, true)
	await get_tree().process_frame
	_assert_true(_insp.group_count() == 1, "hide: the all-inert section's header is pruned")


func _render_sections(sections: Array, hide_inert: bool) -> void:
	_insp.show_target(Target.emitter(0), [], sections, _cp, func(_ci, _n): pass,
		func(_t): pass, func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_ref, _raw): pass, func(_refs, _col): return Color.BLACK, hide_inert)


# --- fixtures -------------------------------------------------------------

## Mirrors EmitterRelevanceViewTest._effect_editable: emitter 0 with a curve-driven Position
## (Live), all-zero additive groups (Inactive), zero homing (Target offset + blend Dead),
## colour enabled (colour curves Live), both child modes disabled (child pickers Dead, mode
## switches suppressing gates).
func _effect_editable():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]},
		],
	})
	var em = ExMateriaEffects.EffectEmitter.new()
	em.curves = {"position": 0}
	em.color_curves = {"r": 0}
	em.anim_index = 3
	em.raw_data = {
		"position_start": [28, -28, 0], "position_end": [0, 0, 0],
		"spread_start": [0, 0, 0], "spread_end": [0, 0, 0],
		"angle_start": [0, 0, 0], "angle_end": [0, 0, 0],
		"vel_spread_start": [0, 0, 0], "vel_spread_end": [0, 0, 0],
		"radial_min_start": 0, "radial_max_start": 0, "radial_min_end": 0, "radial_max_end": 0,
		"accel_min_start": [0, 0, 0], "accel_max_start": [0, 0, 0],
		"accel_min_end": [0, 0, 0], "accel_max_end": [0, 0, 0],
		"drag_min_start": [0, 0, 0], "drag_max_start": [0, 0, 0],
		"drag_min_end": [0, 0, 0], "drag_max_end": [0, 0, 0],
		"target_start": [0, 0, 0], "target_end": [0, 0, 0],
		"homing_min_start": 0, "homing_max_start": 0, "homing_min_end": 0, "homing_max_end": 0,
		"curve_indices_raw": [1, 0, 0, 0, 0, 0, 0, 0],
		"motion_type_flag": 0x42, "animation_target_flag": 0x00,
		"emitter_flags_lo": 0x40, "emitter_flags_hi": 0x01,
		"byte_00": 0, "byte_05": 0,
	}
	em.callback_params = {"param_4C": 0, "param_A8": 7}
	ed.emitters.append(em)
	ed.curves.append(ExMateriaEffects.EffectCurve.from_array([0.0, 0.5, 1.0], 0))
	return ed


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
