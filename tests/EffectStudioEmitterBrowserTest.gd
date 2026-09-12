extends Node
## TDD guard (real page + fake host) for the exhaustive EMITTER BROWSER (ADR-0073) — the
## entry point that guarantees the reachability invariant: EVERY emitter is inspectable,
## including an ORPHAN (referenced by no keyframe and no parent — e.g. callback-only or dead
## data) that no timeline span or child-ref link can reach. Asserts the browser lists all
## emitters and that activating one sets it as a fresh inspection root.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioEmitterBrowserTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_browser_lists_every_emitter()
	await _test_browsing_reaches_an_orphan_emitter()
	await _test_placeholder_is_a_no_op()

	print("\n=== EffectStudioEmitterBrowserTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioEmitterBrowserTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioEmitterBrowserTest")
		get_tree().quit(0)


func _test_browser_lists_every_emitter() -> void:
	var page = await _page()
	_load(page)   # 3 emitters
	# One entry per emitter, plus the leading placeholder prompt.
	_assert_eq(page._emitter_picker.item_count, 4, "the browser lists every emitter (+ placeholder)")
	# Labeled by 0-based index, matching the timeline "E<i>"; position 3 = emitter index 2.
	_assert_eq(page._emitter_picker.get_item_text(3), "emitter 2", "the last entry is emitter index 2")
	page.queue_free()


## Emitter 2 is referenced by nothing (no keyframe, no parent) — unreachable via span or
## link. The browser is the ONLY way in; activating it makes it the inspection root.
func _test_browsing_reaches_an_orphan_emitter() -> void:
	var page = await _page()
	_load(page)
	page._on_emitter_browsed(3)   # position 3 → item id 2 (the orphan)
	_assert_eq(page._nav.size(), 1, "browsing an emitter starts a fresh root")
	_assert_true(Target.equals(page._nav.back(), Target.emitter(2)),
		"the orphan emitter is now the inspection root — reachability guaranteed")
	page.queue_free()


func _test_placeholder_is_a_no_op() -> void:
	var page = await _page()
	_load(page)
	page._on_emitter_browsed(0)   # the "— pick emitter —" placeholder (id -1)
	_assert_eq(page._nav.size(), 0, "selecting the placeholder mints no target")
	page.queue_free()


# --- fixtures -------------------------------------------------------------

func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	page.bind_host(_FakeHost.new())
	return page


## A particle span spawns emitter 0; emitter 1 is a child of 0; emitter 2 is an ORPHAN
## (referenced by nothing). Populate the browser from it.
func _load(page) -> void:
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
	ed.emitters.append(EffectEmitter.new())   # emitter 1 — child of 0
	ed.emitters.append(EffectEmitter.new())   # emitter 2 — ORPHAN
	page._effect_data = ed
	page._nav.clear()
	page._timeline.load_score(Model.build(ed))
	page._refresh_emitter_browser()


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
