extends Node
## TDD guard (real page + fake host) for the **path bar** — the drill trail promoted out
## of the inspector's 6-column grid into a strip of its own above the inspector row.
##
## Four things are guarded, and they are the four that can silently regress:
##   1. the trail no longer appears in the inspector — `_breadcrumb_rows` had two callers
##      and BOTH had to stop prepending it, or it renders twice;
##   2. the CURRENT target is the terminal crumb, marked and NOT a link (the old header
##      trail deliberately stopped at the parent);
##   3. `‹` / Alt+Left step back exactly one level, and are inert at the root — Esc still
##      owns deselect, and the two gestures must not converge;
##   4. the elision keeps root + last two past depth 4, and hands the dropped middle to
##      the `…` menu so no crumb becomes unreachable.
##
## The nav STACK itself is EffectStudioNavStackTest's job and is not re-asserted here.
##
## Run: godot --path . --quit-after 8 res://tests/EffectStudioPathBarTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const PathBar = preload("res://src/effects/studio/EffectPathBar.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0
## A GDScript coroutine that errors ABORTS SILENTLY — the run still reports "N passed, 0
## failed", only the total moves. Each test stamps itself; `_ready` fails loudly on a
## missing stamp (the EffectStudioSequenceViewportTest pattern).
var _completed: Dictionary = {}
const _EXPECTED_TESTS := [
	"elision_is_pure", "trail_left_the_inspector", "current_is_the_terminal_crumb",
	"crumb_click_steps_back", "back_button_and_shortcut", "elided_middle_stays_reachable",
	"empty_inspection_keeps_the_bar",
]


func _done(name: String) -> void:
	_completed[name] = true


func _ready() -> void:
	await _run()
	for name in _EXPECTED_TESTS:
		if not _completed.has(name):
			_failed += 1
			print("  FAIL: test '%s' never reached its end — it aborted mid-run, so its assertions were never made" % name)
	print("\n=== EffectStudioPathBarTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioPathBarTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioPathBarTest")
		get_tree().quit(0)


func _run() -> void:
	_test_elision_is_pure()
	await _test_trail_left_the_inspector()
	await _test_current_is_the_terminal_crumb()
	await _test_crumb_click_steps_back()
	await _test_back_button_and_shortcut()
	await _test_elided_middle_stays_reachable()
	await _test_empty_inspection_keeps_the_bar()


## The elision rule and the back-shortcut recognizer are PURE — guarded with no scene,
## the way `_is_undo_shortcut` / `_is_escape` are.
func _test_elision_is_pure() -> void:
	_assert_eq(PathBar.visible_indices(1), [0], "depth 1 shows its one crumb")
	_assert_eq(PathBar.visible_indices(4), [0, 1, 2, 3], "depth 4 is the last un-elided depth")
	_assert_eq(PathBar.visible_indices(5), [0, "…", 3, 4], "past depth 4: root, ellipsis, last two")
	_assert_eq(PathBar.visible_indices(6), [0, "…", 4, 5], "the deepest real chain elides the same way")
	_assert_eq(PathBar.elided_indices(4), [], "nothing is elided at depth 4")
	_assert_eq(PathBar.elided_indices(6), [1, 2, 3], "the dropped middle is every crumb between")

	var alt_left := InputEventKey.new()
	alt_left.pressed = true
	alt_left.keycode = KEY_LEFT
	alt_left.alt_pressed = true
	_assert_true(Page._is_back_shortcut(alt_left), "Alt+Left is the step-back shortcut")
	var bare_left := InputEventKey.new()
	bare_left.pressed = true
	bare_left.keycode = KEY_LEFT
	_assert_true(not Page._is_back_shortcut(bare_left), "a bare Left arrow is NOT step-back")
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	echo.keycode = KEY_LEFT
	echo.alt_pressed = true
	_assert_true(not Page._is_back_shortcut(echo), "an auto-repeat echo is not a fresh press")
	_done("elision_is_pure")


## The trail moved: `_breadcrumb_rows` fed the inspector's grid from TWO callers, and both
## had to stop. If either one still prepends, the trail renders twice — once as chrome and
## once as the header rows it used to be.
func _test_trail_left_the_inspector() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	page._navigate_to(Target.emitter(1))

	# The header GRID is where the crumbs used to live (the section link rows below it are
	# the target's own content and are untouched). Its row count must now be exactly the
	# projector's header, with nothing prepended.
	var score: Dictionary = page._timeline._score
	var expected: int = Model.inspector_header(page._nav.back(), page._effect_data, score).size()
	_assert_eq(page._inspector.row_count(), expected,
		"the inspector header is the projector's rows alone — no trail prepended")
	# Deliberately a COUNT, not a label scan: the header grid still (rightly) holds link
	# rows reading "emitter 0" — the projector's own provenance edges. That a crumb and a
	# provenance edge were indistinguishable there is the complaint the bar answers, so the
	# only honest assertion is that the trail's ROWS are gone.
	_assert_true(page._path_bar.crumb_buttons().size() >= 2,
		"the ancestors render as crumbs in the BAR instead")
	page.queue_free()
	_done("trail_left_the_inspector")


## The current target is the last crumb, marked and inert — a trail that stops at the
## parent doesn't read as "where am I" once there is no inspector title under it.
func _test_current_is_the_terminal_crumb() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))

	var text: String = page._path_bar.path_text()
	_assert_true(text.begins_with("E"), "the bar names the document first (got '%s')" % text)
	_assert_true(text.ends_with(PathBar.MARK_CURRENT + "emitter 0"),
		"the CURRENT target is the terminal crumb, marked (got '%s')" % text)
	for b in page._path_bar.crumb_buttons():
		_assert_true(not b.text.begins_with("emitter 0"),
			"the current target is not a clickable crumb")
	page.queue_free()
	_done("current_is_the_terminal_crumb")


func _test_crumb_click_steps_back() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	page._navigate_to(Target.emitter(1))
	_assert_eq(page._nav.size(), 3, "three deep before the click")

	page._path_bar.crumb_buttons()[0].pressed.emit()   # the root span crumb

	_assert_eq(page._nav.size(), 1, "clicking an ancestor crumb truncates to it")
	_assert_true(Target.equals(page._nav.back(), Target.span(span_id)), "we are back at the root")
	page.queue_free()
	_done("crumb_click_steps_back")


## `‹` and Alt+Left both step back exactly ONE level, and both are inert at the root —
## stepping off the root would mean deselecting, which stays Esc's job.
func _test_back_button_and_shortcut() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	page._navigate_to(Target.emitter(1))

	_assert_true(not page._path_bar.back_button().disabled, "`‹` is live below the root")
	page._path_bar.back_button().pressed.emit()
	_assert_eq(page._nav.size(), 2, "`‹` steps back exactly one level")
	_assert_true(Target.equals(page._nav.back(), Target.emitter(0)), "one level, not to the root")

	_assert_true(page._step_back(), "the shortcut steps back and reports it moved")
	_assert_eq(page._nav.size(), 1, "back at the root span")
	_assert_true(page._path_bar.back_button().disabled, "`‹` is disabled at the root")
	_assert_true(not page._step_back(), "stepping off the root is a no-op (Esc owns deselect)")
	_assert_eq(page._nav.size(), 1, "and the root survives it")
	page.queue_free()
	_done("back_button_and_shortcut")


## Past depth 4 the middle is folded into `…` — but folded, never dropped: every elided
## crumb is still reachable, and picking one navigates exactly as clicking it would.
func _test_elided_middle_stays_reachable() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	page._navigate_to(Target.animation(0))
	page._navigate_to(Target.frameset(0))
	page._navigate_to(Target.frame(0, 0))
	_assert_eq(page._nav.size(), 5, "five deep")

	var bar = page._path_bar
	_assert_true(bar.elided_button() != null, "the middle folds into a `…` control")
	_assert_eq(bar.elided_targets().size(), 2, "two crumbs were folded away")
	var text: String = bar.path_text()
	_assert_true(text.contains("…"), "the bar shows the ellipsis (got '%s')" % text)
	_assert_true(text.contains("frameset 0") and text.contains("frame 0/0"),
		"the last two crumbs survive the elision (got '%s')" % text)
	_assert_true(not text.contains("emitter 0"), "the middle is not also drawn inline")

	bar.elided_button().get_popup().id_pressed.emit(0)   # pick the first folded crumb
	_assert_eq(page._nav.size(), 2, "picking a folded crumb truncates to it")
	_assert_true(Target.equals(page._nav.back(), Target.emitter(0)), "…and lands on that crumb")
	page.queue_free()
	_done("elided_middle_stays_reachable")


## Deselect empties the trail but NOT the bar: the chrome is constant (the whole reason it
## shows at depth 1), so nothing below it re-flows on the most common gesture. `_deselect`
## does not render, so the bar has to be pushed on that path explicitly.
func _test_empty_inspection_keeps_the_bar() -> void:
	var page = await _page()
	var span_id := _load(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	_assert_true(page._deselect(), "deselect cleared a live selection")

	_assert_true(page._path_bar.visible, "the bar stays visible in the empty inspection")
	_assert_eq(page._path_bar.crumb_buttons().size(), 0, "with no crumbs left")
	_assert_true(page._path_bar.back_button().disabled, "and `‹` inert")
	_assert_true(page._path_bar.path_text().begins_with("E"),
		"still naming the document (got '%s')" % page._path_bar.path_text())
	page.queue_free()
	_done("empty_inspection_keeps_the_bar")


# --- fixtures -------------------------------------------------------------

func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame   # let _ready build the UI
	page.bind_host(_FakeHost.new())
	return page


## Install a synthetic effect (particle span → emitter 0, which spawns emitter 1 on death)
## and return the drawn span's id. Mirrors EffectStudioNavStackTest's fixture, plus the one
## animation/frameset the depth-5 elision case needs to drill through.
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
	ed.animations = [{"opcodes": [], "raw": PackedByteArray()}]
	ed.framesets = [{"frames": [], "header_flags": 0}]
	page._effect_data = ed
	page._current_id = 19
	page._nav.clear()
	page._timeline.load_score(Model.build(ed))
	page._update_path_bar()
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
		print("  FAIL: %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s — expected true" % label)
