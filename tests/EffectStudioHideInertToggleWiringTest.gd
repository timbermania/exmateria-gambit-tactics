extends Node
## TDD guard for the "Hide inert" PAGE toggle wiring (ADR-0089 amendment) — the session-local
## mode that renders only Live emitter fields. Mirrors the Ripple precedent: a global toolbar
## button flips a page-level bool that is threaded into show_target and never written to the
## effect. This guard pins the DECISIONS (flag flips, re-renders, passes through, updates the
## caption, is not persisted); the pixels are covered headfully (E019 acceptance).
##
## Pure logic: the page is new()'d WITHOUT add_child; a SPY inspector records the hide_inert
## flag each show_target receives, and a recording host proves the toggle never applies/saves.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioHideInertToggleWiringTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Inspector = preload("res://src/effects/studio/EffectKeyframeInspector.gd")
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")
const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const EffectEmitter = ExMateriaEffects.EffectEmitter
const TimelineDataClass = ExMateriaEffects.TimelineData
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_default_off_and_toggle_flips_and_reprojects()
	_test_flag_is_passed_through_show_target()
	_test_toggle_updates_the_caption()
	_test_toggle_is_session_local_never_saved()
	await _test_verdict_flip_composes_with_hide_mode()

	print("\n=== EffectStudioHideInertToggleWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioHideInertToggleWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioHideInertToggleWiringTest")
		get_tree().quit(0)


## Default off; each toggle flips the page bool AND re-renders the inspector (unlike Ripple,
## which is edit-time only — this mode changes what is drawn, so it must re-render).
func _test_default_off_and_toggle_flips_and_reprojects() -> void:
	var page = _page()
	var spy = page._inspector
	_assert_true(not page._hide_inert, "default: Hide inert is off")
	spy.calls = 0
	page._toggle_hide_inert()
	_assert_true(page._hide_inert, "toggle turns Hide inert on")
	_assert_true(spy.calls >= 1, "toggling re-renders the inspector")
	page._toggle_hide_inert()
	_assert_true(not page._hide_inert, "toggling again turns it back off")
	page.free()


## The page threads the CURRENT flag as the last positional arg of show_target, so the view
## renders in the mode the toolbar shows.
func _test_flag_is_passed_through_show_target() -> void:
	var page = _page()
	var spy = page._inspector
	page._hide_inert = true
	page._render_current()
	_assert_true(spy.last_hide_inert == true, "render passes hide_inert=true through show_target")
	page._hide_inert = false
	page._render_current()
	_assert_true(spy.last_hide_inert == false, "render passes hide_inert=false through show_target")
	page.free()


## The toolbar caption mirrors the flag (built by _update_labels), exactly like Ripple.
func _test_toggle_updates_the_caption() -> void:
	var page = _page()
	page._hide_inert_btn = Button.new()
	page._toggle_hide_inert()
	_assert_true(page._hide_inert_btn.text == "Hide inert: on", "caption reads 'on' when hiding")
	page._toggle_hide_inert()
	_assert_true(page._hide_inert_btn.text == "Hide inert: off", "caption reads 'off' when showing")
	page._hide_inert_btn.free()
	page.free()


## Session-local: the toggle routes purely through the UI — it never applies an edit or saves,
## so nothing about it reaches the effect bytes.
func _test_toggle_is_session_local_never_saved() -> void:
	var page = _page()
	var host = page._host
	host.applies = 0
	page._toggle_hide_inert()
	page._toggle_hide_inert()
	_assert_eq(host.applies, 0, "toggling Hide inert never applies an edit / touches the effect")
	page.free()


## End-to-end composition (ADR-0089): with Hide inert ON, editing homing_strength flips the
## target-offset group's verdict, and the reproject-on-flip already wired in _apply_edit
## re-renders through show_target(hide_inert) — so a woken group REAPPEARS and a re-deadened one
## VANISHES, live. Uses a REAL inspector (added to the tree) + a session-backed host, so the
## row-count delta is the real rendered surface, not a spy count.
func _test_verdict_flip_composes_with_hide_mode() -> void:
	var page = _page()
	var insp = Inspector.new()
	add_child(insp)
	await get_tree().process_frame
	page._inspector = insp
	page._host = _SessionHost.new()
	page._host.bind(page._effect_data)
	page._hide_inert = true
	page._render_current()
	await get_tree().process_frame
	var base_rows: int = insp.param_row_count()
	# Wake homing (0 → 5): target_offset flips Dead → Live and must REAPPEAR under hide.
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "homing_strength_min_start"}, 5)
	await get_tree().process_frame
	var woken_rows: int = insp.param_row_count()
	_assert_true(woken_rows > base_rows, "hide: waking homing reveals the woken target-offset rows")
	# Re-dead it (5 → 0): the woken group vanishes again.
	page._apply_edit({"channel": "emitter", "emitter_index": 0, "field": "homing_strength_min_start"}, 0)
	await get_tree().process_frame
	var deadened_rows: int = insp.param_row_count()
	_assert_true(deadened_rows < woken_rows, "hide: re-deadening homing hides the target-offset rows again")
	insp.free()
	page.free()


## A page over a single-emitter effect, nav rooted on the emitter so `_render_current` targets
## it; a SPY inspector records the hide_inert flag each render passes.
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
	page._inspector = _SpyInspector.new()
	page._nav = [Target.emitter(0)]
	return page


## Records the hide_inert flag (the last positional arg) each show_target receives.
class _SpyInspector extends RefCounted:
	var calls: int = 0
	var last_hide_inert = null
	func show_target(_target, _header, _sections, _curve_provider = null, _on_open = null,
			_on_navigate = null, _suppressed = null, _on_toggle = null, _on_mutate = null,
			_on_pick = null, hide_inert = false, marker = {}, on_action = null) -> void:
		calls += 1
		last_hide_inert = hide_inert
	# The page refreshes the playhead marker each cadence tick (ADR-0089 amendment); the spy
	# just absorbs it (no rebuild, no marker state to track here).
	func update_marker(_marker) -> void:
		pass


## A host stub counting applies — the toggle must never reach it (session-local, never saved).
class _FakeHost extends RefCounted:
	var applies: int = 0
	func studio_apply_edit(_field_ref: Dictionary, _new_raw, _defer_refold: bool = false) -> Dictionary:
		applies += 1
		return {}


## A host applying each edit through a real EffectEditSession bound to the shared data — the
## production choke point — so a value edit genuinely mutates the emitter and the page's
## relevance-signature comparison sees the verdict move.
class _SessionHost extends RefCounted:
	var _session = null
	func bind(ed) -> void:
		_session = EffectEditSession.new(ed)
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
