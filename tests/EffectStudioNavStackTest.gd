extends Node
## TDD guard (real page + fake host) for the inspection NAV STACK (ADR-0073). A timeline
## span select is a fresh ROOT; following child-ref links DRILLS (push); revisiting an
## ancestor STEPS BACK (truncate); consecutive dupes collapse. The path bar renders the
## ancestor trail as clickable crumbs, and the timeline highlight is authoritative ONLY for a
## span target — drilling into an emitter leaves the origin span selected.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioNavStackTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_span_select_is_a_fresh_root()
	await _test_drill_pushes_and_timeline_highlight_is_span_only()
	await _test_breadcrumb_click_steps_back()
	await _test_consecutive_dupe_collapses()
	await _test_deselect_clears_to_empty_inspection()
	await _test_deselect_on_empty_is_a_noop()

	print("\n=== EffectStudioNavStackTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioNavStackTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioNavStackTest")
		get_tree().quit(0)


func _test_span_select_is_a_fresh_root() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	_assert_eq(page._nav.size(), 1, "a timeline span select is a single-item root")
	_assert_true(Target.equals(page._nav.back(), Target.span(span_id)), "the root is the span target")
	_assert_eq(page._timeline.selected_span_id(), span_id, "the timeline highlights the selected span")
	page.queue_free()


func _test_drill_pushes_and_timeline_highlight_is_span_only() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))       # drill: span → emitter 0
	page._navigate_to(Target.emitter(1))       # drill deeper: → emitter 1
	_assert_eq(page._nav.size(), 3, "drilling links pushes onto the stack")
	_assert_true(Target.equals(page._nav.back(), Target.emitter(1)), "the top is the deepest target")
	# The timeline still highlights the ORIGIN span — an emitter target is not selectable there.
	_assert_eq(page._timeline.selected_span_id(), span_id,
		"drilling into an emitter leaves the origin span highlighted (span-only highlight)")
	# The trail renders the two ancestors as clickable crumbs — in the PATH BAR, which is
	# where it moved out of the inspector's grid (EffectStudioPathBarTest owns its detail).
	_assert_true(page._path_bar.crumb_buttons().size() >= 2,
		"the path bar shows the ancestor trail as clickable crumbs")
	page.queue_free()


func _test_breadcrumb_click_steps_back() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	page._navigate_to(Target.emitter(1))
	# Stepping back to an ancestor (the root span) truncates the path.
	page._navigate_to(Target.span(span_id))
	_assert_eq(page._nav.size(), 1, "revisiting an ancestor truncates the stack to it")
	_assert_true(Target.equals(page._nav.back(), Target.span(span_id)), "we are back at the root span")
	_assert_eq(page._timeline.selected_span_id(), span_id, "the timeline re-highlights the span on step-back")
	page.queue_free()


func _test_consecutive_dupe_collapses() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	page._navigate_to(Target.emitter(0))       # same top again → no-op
	_assert_eq(page._nav.size(), 2, "re-navigating to the current target does not grow the stack")
	page.queue_free()


## Esc → Deselected (empty inspection) (CONTEXT.md): _deselect() drops the WHOLE drill path,
## clears the inspector EXPLICITLY (a render won't — _render_current early-returns on empty _nav),
## and clears the timeline highlight. It reports true when it actually cleared something, so the
## caller consumes only a meaningful Esc.
func _test_deselect_clears_to_empty_inspection() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))   # drill deep so we prove a FULL-path clear
	_assert_true(page._inspector.row_count() > 0, "the inspector is showing a target before Esc")

	var cleared: bool = page._deselect()

	_assert_true(cleared, "_deselect reports it cleared a live selection")
	_assert_true(page._nav.is_empty(), "the nav path is emptied (deselected to nothing)")
	_assert_eq(page._inspector.row_count(), 0, "the inspector is cleared explicitly (collapsed)")
	_assert_eq(page._timeline.selected_span_id(), "", "the timeline highlight is cleared")
	page.queue_free()


## Esc in the already-empty state is a no-op: _deselect touches nothing and reports false, so the
## caller leaves that Esc free to bubble (a future close-window).
func _test_deselect_on_empty_is_a_noop() -> void:
	var page = await _page()
	_load(page)
	page._nav.clear()
	page._timeline.select_span("")
	_assert_true(not page._deselect(), "_deselect on an empty inspection reports nothing cleared")
	page.queue_free()


# --- fixtures -------------------------------------------------------------

func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame   # let _ready build the UI
	page.bind_host(_FakeHost.new())
	return page


## Install a synthetic effect (particle span → emitter 0, which spawns emitter 1 on death)
## and return the drawn span's id. Overrides whatever the page auto-loaded on boot.
func _load(page) -> String:
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]},
		],
	})
	var em0 = EffectEmitter.new()
	em0.child_emitter_on_death = 1
	ed.emitters.append(em0)
	ed.emitters.append(EffectEmitter.new())
	page._effect_data = ed
	page._nav.clear()
	page._timeline.load_score(Model.build(ed))
	return Model.build(ed)["lanes"][0]["spans"][0]["id"]


class _FakeHost extends RefCounted:
	func studio_seek(_frame: int) -> void: pass
	func studio_set_playing(_playing: bool) -> void: pass
	func studio_current_frame() -> int: return 0
	func studio_select_effect(_id: int) -> void: pass


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
