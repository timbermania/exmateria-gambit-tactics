extends Node
## TDD guard (real page) for the #275 "Sequences:" browser — the exhaustive entry
## point that makes every animation sequence in the loaded effect reachable, even
## one no emitter currently plays. Mirrors the #278 "Frames:" browser it sits
## beside on transport row 3.
##
## The projector rows themselves are guarded by EffectStudioSequenceEditTest; this
## file is the seam ABOVE that: does the picker actually enumerate the sequences and
## does choosing one make it the inspection root?
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectStudioSequenceBrowserTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_browser_lists_one_entry_per_sequence()
	await _test_browsing_to_a_sequence_makes_it_the_inspection_root()
	await _test_the_placeholder_row_is_inert()
	_test_transport_right_edge_is_the_rightmost_control_not_a_named_one()

	print("\n=== EffectStudioSequenceBrowserTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioSequenceBrowserTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioSequenceBrowserTest")
		get_tree().quit(0)


func _test_browser_lists_one_entry_per_sequence() -> void:
	var page = await _page()
	page._effect_data = _fake_data()

	page._refresh_sequence_browser()

	_assert_eq(page._sequence_picker.item_count, 3, "a placeholder row plus one row per sequence")
	_assert_eq(page._sequence_picker.get_item_text(1), "sequence 0 (5 opcodes)",
		"each row names the sequence and how many opcodes it runs")
	_assert_eq(page._sequence_picker.get_item_text(2), "sequence 1 (2 opcodes)",
		"the second sequence is listed too")
	_assert_eq(page._sequence_picker.get_item_metadata(1), Target.animation(0),
		"the row carries the sequence's InspectionTarget")
	page.queue_free()


func _test_browsing_to_a_sequence_makes_it_the_inspection_root() -> void:
	var page = await _page()
	page._effect_data = _fake_data()
	page._refresh_sequence_browser()

	page._on_sequence_browsed(2)

	_assert_eq(page._nav.back(), Target.animation(1),
		"choosing a row roots the inspector on that sequence")
	page.queue_free()


func _test_the_placeholder_row_is_inert() -> void:
	var page = await _page()
	page._effect_data = _fake_data()
	page._refresh_sequence_browser()
	var before: Array = page._nav.duplicate()

	page._on_sequence_browsed(0)

	_assert_eq(page._nav, before, "the '— pick sequence —' placeholder navigates nowhere")
	page.queue_free()


## REGRESSION (2026-08-18): the frameset canvas panel docks top-right and computes its
## safe left edge from the transport bar's rendered right edge. That measurement used to
## read ONE named control (`_frameset_picker`) on the assumption it was row3's rightmost —
## true when written, false the moment #275 appended "Sequences:" to the right of it, so
## the panel was drawn straight over the new dropdown (it rendered as a dead grey strip).
## The edge must be measured as the MAX over the row's real children, so appending another
## control can never silently put it under the canvas again.
func _test_transport_right_edge_is_the_rightmost_control_not_a_named_one() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var a := Control.new()
	a.position = Vector2(0, 0)
	a.custom_minimum_size = Vector2(100, 10)
	var b := Control.new()
	b.position = Vector2(0, 0)
	b.custom_minimum_size = Vector2(50, 10)
	row.add_child(a)
	row.add_child(b)
	row.size = Vector2(400, 10)

	var edge: float = Page.transport_right_edge(row)
	var a_edge: float = a.get_global_rect().position.x + a.get_global_rect().size.x
	var b_edge: float = b.get_global_rect().position.x + b.get_global_rect().size.x

	_assert_eq(edge, maxf(a_edge, b_edge), "the edge is the rightmost child's, whichever that is")
	_assert_true(edge >= a_edge, "a control appended AFTER the historically-last one still counts")
	row.queue_free()


func _fake_data():
	var data = EffectDataClass.new()
	data.animations = [
		{"index": 0, "opcodes": [
			{"type": "SET_OFFSET", "x": 0, "y": -12},
			{"type": "FRAME", "frameset": 3, "duration": 8, "depth_mode": 1},
			{"type": "ADD_OFFSET", "dx": 2, "dy": -1},
			{"type": "FRAME", "frameset": 4, "duration": 0, "depth_mode": 1},
			{"type": "LOOP"},
		]},
		{"index": 1, "opcodes": [
			{"type": "SET_OFFSET", "x": 4, "y": 4},
			{"type": "LOOP"},
		]},
	]
	return data


func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	return page


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
