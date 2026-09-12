extends Node
## ACCEPTANCE (headful, real E019, #271 follow-up): the timeline draws visible phase-boundary
## lines + labels where phase 1 / for-each / phase 2 begin, and the end marker now sits at
## phase 2's content end (not the particle-reap that dimmed phase 2). Renders a real
## EffectScoreTimeline fed the E019 score into a SubViewport and writes a screenshot for the
## eyeball (field dumps don't count), plus asserts the boundary frames + floored end.
##
## Skips when E019 assets are absent. Run: godot --path . --quit-after 400 res://tests/EffectStudioPhaseBoundaryAcceptanceTest.tscn

const TimelineScene := preload("res://src/effects/studio/EffectScoreTimeline.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EndModel = ExMateriaEffects.EffectEndModel
const EffectPhase = ExMateriaEffects.EffectPhase
const EffectDataClass = ExMateriaEffects.EffectData
const SHOT := "user://phase_boundaries_e019.png"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	print("\n=== EffectStudioPhaseBoundaryAcceptanceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioPhaseBoundaryAcceptanceTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioPhaseBoundaryAcceptanceTest")
		get_tree().quit(0)


func _run() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("[SKIP] E019 assets not available")
		_passed += 1
		return

	var data = EffectDataClass.load_from_directory("res://assets/effects/E019")
	var score = Model.build(data, {}, {}, [])

	var sv := SubViewport.new()
	sv.size = Vector2i(900, 320)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var tl = TimelineScene.new()
	tl.custom_minimum_size = Vector2(900, 320)
	tl.size = Vector2(900, 320)
	sv.add_child(tl)
	tl.load_score(score)
	# The studio floor: run through phase 2 content, not the particle reap.
	var end_frame: int = maxi(EndModel.derived_end_frame(data), Model.phase2_content_end(score))
	tl.set_end_frame(end_frame)
	await _frames(6)

	# Boundaries land at the phase offsets.
	var b: Array = tl.phase_boundaries()
	_assert_true(b.size() >= 2, "E019 projects multiple phase boundaries (%d)" % b.size())
	var by_label := {}
	for e in b:
		by_label[String(e.get("label", ""))] = int(e.get("frame", -1))
	_assert_eq(by_label.get("For-each", by_label.get("for_each", -1)),
		Model.phase_offset(data, EffectPhase.PHASE_FOR_EACH), "for-each boundary at the offset")
	_assert_eq(by_label.get("Phase 2", by_label.get("phase2", -1)),
		Model.phase_offset(data, EffectPhase.PHASE2), "phase 2 boundary at the offset")
	_assert_true(end_frame >= Model.phase2_content_end(score),
		"end marker runs through phase 2 content (%d >= %d)" % [end_frame, Model.phase2_content_end(score)])

	# Visual proof — a real pixel artifact of the boundary lines + labels + end marker.
	var err := sv.get_texture().get_image().save_png(SHOT)
	_assert_true(err == OK, "screenshot written to %s" % ProjectSettings.globalize_path(SHOT))
	print("  screenshot: %s" % ProjectSettings.globalize_path(SHOT))


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
