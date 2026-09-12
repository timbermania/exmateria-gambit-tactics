extends Node
## TDD guard for the Effect Studio EMITTER field-relevance reproject wiring (ADR-0089 salience
## amendment). The bug: editing an input inside an Inactive ("!") emitter fold changed the bytes
## (and the host re-folded the preview) but the INSPECTOR never re-derived its salience markers,
## so the `!` never cleared and homing-gated groups never appeared/disappeared.
##
## The page's `_apply_edit` for a plain emitter value edit is NOT structural (no relayout), so it
## deliberately skips `_render_current()` to preserve the live spinbox mid-scrub. The fix: snapshot
## the emitter's render-affecting relevance signature (EmitterFieldRelevance.render_signature)
## across the edit and reproject IFF a verdict actually flipped. This guard pins:
##   (1) waking an Inactive group (weight 0 → non-zero) REPROJECTS (the `!` refresh),
##   (2) an in-range nudge of an already-Live value does NOT reproject (the live widget survives),
##   (3) a numeric gate crossing (homing strength → 0 deads target offset) REPROJECTS,
##   (4) a NON-emitter plain value edit (screen colour) never triggers the emitter reproject.
##
## Pure logic: the page is new()'d WITHOUT add_child; we inject a real timeline + emitter data +
## a recording fake host applying through a real EffectEditSession, and a SPY inspector counting
## show_target() calls (the reproject observable). Marker rendering itself is covered headfully
## (EmitterRelevanceAcceptanceTest) — this guard pins the DECISION, not the pixels.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioEmitterRelevanceReprojectTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitter = ExMateriaEffects.EffectEmitter
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_waking_inactive_group_reprojects()
	_test_in_range_nudge_does_not_reproject()
	_test_homing_gate_crossing_reprojects()
	_test_non_emitter_edit_does_not_reproject()

	print("\n=== EffectStudioEmitterRelevanceReprojectTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEmitterRelevanceReprojectTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEmitterRelevanceReprojectTest")
		get_tree().quit(0)


## Editing weight (an all-zero → Inactive group) to a non-zero value wakes it Live: the salience
## verdict flips, so the page must reproject the inspector to clear the `!`.
func _test_waking_inactive_group_reprojects() -> void:
	var page = _page()
	var spy = page._inspector
	spy.calls = 0
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "weight_min_start"}, 5)
	_assert_true(spy.calls >= 1, "waking an Inactive weight group reprojects the inspector")
	page.free()


## Nudging an already-Live value within range moves no verdict — the page must NOT reproject, so
## the spinbox being scrubbed is not destroyed.
func _test_in_range_nudge_does_not_reproject() -> void:
	var page = _page()
	var spy = page._inspector
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "weight_min_start"}, 5)  # wake
	spy.calls = 0
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "weight_min_start"}, 6)  # nudge
	_assert_eq(spy.calls, 0, "an in-range nudge of a Live value does not reproject")
	page.free()


## Homing strength → 0 deads target_offset (a numeric gate) — a plain value edit that restructures
## which groups are hidden, so it must reproject.
func _test_homing_gate_crossing_reprojects() -> void:
	var page = _page()
	# Arm homing Live first (target_offset Live), then knock it to 0 and observe the reproject.
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "homing_strength_min_start"}, 5)
	var spy = page._inspector
	spy.calls = 0
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "homing_strength_min_start"}, 0)
	_assert_true(spy.calls >= 1, "a homing gate that deads target_offset reprojects the inspector")
	page.free()


## A plain NON-emitter value edit (screen colour) must never take the emitter reproject path — it
## has no relevance signature and its own branch owns the refresh.
func _test_non_emitter_edit_does_not_reproject() -> void:
	var page = _page()
	var spy = page._inspector
	spy.calls = 0
	# No screen data on this fixture → the host edit no-ops; the point is the emitter branch is not
	# taken for a non-emitter channel (the signature guard is scoped to channel == "emitter").
	page._apply_edit({"channel": "screen", "context": "for_each", "field": "start_r", "event_index": 0}, 10)
	_assert_eq(spy.calls, 0, "a non-emitter edit does not trigger the emitter reproject")
	page.free()


## A page over a single-emitter effect with a projector-safe (parser-shaped) raw store: weight at
## its neutral zero (Inactive), position at a real place (Live), homing off. Nav rooted on the
## emitter so `_render_current` targets it; a SPY inspector counts reprojects.
func _page():
	var page = Page.new()
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 0}]},
		],
	})
	var em = EffectEmitter.new()
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
		"curve_indices_raw": [0, 0, 0, 0, 0, 0, 0, 0],
		"motion_type_flag": 0x00, "animation_target_flag": 0x00,
		"emitter_flags_lo": 0x00, "emitter_flags_hi": 0x00,
		"byte_00": 0, "byte_05": 0,
	}
	em.callback_params = {"param_4C": 0, "param_A8": 0}
	ed.emitters.append(em)

	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed))
	tl.rebuild_layout()
	page._timeline = tl
	page._effect_data = ed
	page._host = _FakeHost.new()
	page._host.bind(ed)
	page._inspector = _SpyInspector.new()
	page._nav = [Target.emitter(0)]
	return page


## Records show_target() (the reproject observable). Matches the production inspector's arity so
## the page's real `_render_current` call binds; the body just counts.
class _SpyInspector extends RefCounted:
	var calls: int = 0
	func show_target(_target, _header, _sections, _curve_provider = null, _on_open = null,
			_on_navigate = null, _suppressed = null, _on_toggle = null, _on_mutate = null,
			_on_pick = null, hide_inert = false, marker = {}, on_action = null) -> void:
		calls += 1
	func update_marker(_marker) -> void:
		pass


## A host stub applying each studio_apply_edit through a real EffectEditSession bound to the shared
## data — exactly what the production host does. Refold accounting is elided (this guard is about
## the inspector reproject, not the sim rescrub).
class _FakeHost extends RefCounted:
	const _Session = preload("res://src/effects/studio/EffectEditSession.gd")
	var _session = null
	func bind(ed) -> void:
		_session = _Session.new(ed)
	func studio_apply_edit(field_ref: Dictionary, new_raw, _defer_refold: bool = false) -> Dictionary:
		return _session.apply_edit(field_ref, new_raw) if _session != null else {}


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
