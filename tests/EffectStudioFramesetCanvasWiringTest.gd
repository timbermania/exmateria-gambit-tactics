extends Node
## TDD guard (real page + fake host) for the #279 UV-drag COMMIT wiring — the frameset
## canvas's `uv_rect_changed` signal → `EffectStudioPage._on_frameset_uv_changed` →
## ONE compound edit through the host's `studio_apply_compound` → the live frame dict
## updates. Mirrors EffectStudioEdgeDragWiringTest's real-page + fake-host shape.
##
## The drag INTERACTION itself (hit_test/move_uv/resize_uv, the _gui_input state
## machine) is guarded by EffectStudioFramesetEditTest (pure functions) — this file is
## the seam ABOVE that: given a final committed uv dict (what a real release emits),
## does it actually reach the live data through exactly one undo-worthy edit?
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioFramesetCanvasWiringTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_committing_a_uv_drag_is_one_compound_edit_that_updates_the_live_frame()
	await _test_committing_while_not_on_a_frame_target_is_a_no_op()

	print("\n=== EffectStudioFramesetCanvasWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioFramesetCanvasWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioFramesetCanvasWiringTest")
		get_tree().quit(0)


func _test_committing_a_uv_drag_is_one_compound_edit_that_updates_the_live_frame() -> void:
	var page = await _page()
	var data = _fake_data()
	page._effect_data = data
	page._nav = [Target.frame(0, 0)]
	var host := _FakeHost.new()
	host.bind(data)
	page.bind_host(host)

	page._on_frameset_uv_changed({"x": 50, "y": 60, "width": 70, "height": 80})

	_assert_eq(host.compound_calls, 1, "the drag commits as exactly ONE compound call (one undo)")
	_assert_eq(host.last_compound.size(), 4, "the compound bundles all four uv fields")
	var frame: Dictionary = data.framesets[0]["frames"][0]
	_assert_eq(frame["uv"], {"x": 50, "y": 60, "width": 70, "height": 80},
		"the compound edit actually reaches the live frame dict through FramesetChannel")
	page.queue_free()


func _test_committing_while_not_on_a_frame_target_is_a_no_op() -> void:
	var page = await _page()
	var data = _fake_data()
	page._effect_data = data
	page._nav = [Target.frameset(0)]   # NOT a "frame" target
	var host := _FakeHost.new()
	host.bind(data)
	page.bind_host(host)

	page._on_frameset_uv_changed({"x": 99, "y": 99, "width": 99, "height": 99})

	_assert_eq(host.compound_calls, 0, "no commit fires when the current target isn't a frame")
	var frame: Dictionary = data.framesets[0]["frames"][0]
	_assert_eq(frame["uv"], {"x": 8, "y": 0, "width": 32, "height": 32}, "the live frame is untouched")
	page.queue_free()


func _fake_data():
	var data = EffectDataClass.new()
	data.framesets = [{
		"index": 0, "header_flags": 0,
		"frames": [{
			"index": 0, "palette_id": 3, "semi_trans_mode": 0, "semi_trans_on": false,
			"is_8bpp": true, "blend_mode": "BLEND_50",
			"uv": {"x": 8, "y": 0, "width": 32, "height": 32},
			"vertices": {"top_left": [0, 0], "top_right": [32, 0],
				"bottom_left": [0, 16], "bottom_right": [32, 16]},
			"texture_page": {"x_base": 0, "y_base": 0, "blend": 0, "color_depth": 0},
		}],
	}]
	return data


func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	return page


## Records every compound call AND applies it through a real EffectEditSession bound to
## the shared effect data — exactly what the production host (EffectViewerScene) does.
class _FakeHost extends RefCounted:
	const _Session = preload("res://src/effects/studio/EffectEditSession.gd")
	var compound_calls: int = 0
	var last_compound: Array = []
	var _session = null
	func bind(ed) -> void:
		_session = _Session.new(ed)
	func studio_apply_compound(edits: Array) -> Dictionary:
		compound_calls += 1
		last_compound = edits
		return _session.apply_compound(edits) if _session != null else {}
	func studio_seek(_f: int) -> void: pass
	func studio_set_playing(_p: bool) -> void: pass
	func studio_current_frame() -> int: return 0
	func studio_select_effect(_id: int) -> void: pass


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
