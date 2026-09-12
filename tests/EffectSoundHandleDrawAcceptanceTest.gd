extends Node
## Headful acceptance for the ADR-0085 sound-handle amendment: paint the REAL E317 score
## through a live EffectScoreTimeline (in the tree, so _draw actually runs) and confirm the
## honest projection renders without a paint crash — the silent-event handles, the inert
## terminator END-CAP glyph (_draw_sound_terminator, reachable only in a real paint), and a
## terminator SELECTION outline. The pure guards (bijection / timeline layout / projector)
## cover the data; this covers the brush. NOT --headless (a window opens; output still returns).
##
## Run: <GODOT> --path . --quit-after 6 res://tests/EffectSoundHandleDrawAcceptanceTest.tscn

const Timeline = preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0
var _tl


func _ready() -> void:
	var dir := "res://assets/effects/E317"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		print("[SKIP] E317 assets absent")
		print("[PASS] EffectSoundHandleDrawAcceptanceTest")
		get_tree().quit(0)
		return
	var ed = EffectDataClass.load_from_directory(dir)
	var score := Model.build(ed)   # empty ghost map — the handles + end-cap still paint

	_tl = Timeline.new()
	_tl.size = Vector2(1000.0, 480.0)
	add_child(_tl)
	_tl.load_score(score)
	_run()


func _run() -> void:
	# Two frames: one to resolve the default view + first paint, one after selecting the
	# terminator so its selection-outline draw branch runs too.
	await get_tree().process_frame
	await get_tree().process_frame

	var term := "sound:for_each:0#5"    # E317 for_each:0 terminator (max_keyframe 5)
	var event := "sound:for_each:0#3"   # an interior EVENT (fires 48)

	# After a real paint (rebuild_layout ran inside _draw): the terminator is inert, the
	# event is draggable. If _draw had crashed on the new glyph path we'd never get here.
	_assert_true(_tl.fire_rect_for(term).size == Vector2.ZERO,
		"E317 terminator is not fire-draggable after a real paint")
	_assert_true(_tl.fire_rect_for(event).size.x > 0.0,
		"E317 interior event keeps its fire grab after a real paint")

	# Select the terminator and repaint — exercises _draw_sound_terminator's selection branch.
	_tl.select_span(term)
	_tl.queue_redraw()
	await get_tree().process_frame
	_assert_true(_tl.selected_span_id() == term, "the terminator is selectable and stays selected across a repaint")

	print("\n=== EffectSoundHandleDrawAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectSoundHandleDrawAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectSoundHandleDrawAcceptanceTest")
		get_tree().quit(0)


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % label)
