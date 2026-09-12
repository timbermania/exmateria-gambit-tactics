extends Node
## The DERIVED effect end (EffectEndModel) — the frame the real engine reaps the
## cast (all phases done spawning AND every particle dead), NOT the last authored
## keyframe. This is what the Effect Studio marks on the timeline and clamps the
## playhead to, so a SCREEN tint authored far past the particles (E173: a black
## TINT holding to ~f611) doesn't make the preview run long past the real end.
##
## Guards, on real effect dirs (RD-free, the ADR-0070 replay harness):
##   - a settled end is found (> 0, < the safety cap);
##   - it is deterministic (fixed seed → identical frame across calls);
##   - for E173 the derived end is STRICTLY LESS THAN the authored max_frame —
##     i.e. the long screen tail really is trimmed off.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectEndModelTest.tscn

const EndModel = ExMateriaEffects.EffectEndModel
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _ready() -> void:
	_test_finds_a_settled_end()
	_test_is_deterministic()
	_test_e173_trims_the_screen_tail()

	if _failed:
		print("[FAIL] EffectEndModel test")
	else:
		print("[PASS] EffectEndModel: derived runtime end is settled, deterministic, and trims the authored tail")
	get_tree().quit()


func _authored_max(dir: String) -> int:
	var data = EffectDataClass.load_from_directory(dir)
	if data == null:
		return -1
	return int(Model.build(data).get("max_frame", 0))


func _end(dir: String) -> int:
	var data = EffectDataClass.load_from_directory(dir)
	return EndModel.derived_end_frame(data)


## A real, particle-bearing effect settles: the sim reaches "no particles left"
## before the safety cap, at a positive frame.
func _test_finds_a_settled_end() -> void:
	var dir := "res://assets/effects/E317"   # Choco Ball — a normal particle effect
	var end := _end(dir)
	print("[EndModel] E317 derived_end=%d  authored_max=%d" % [end, _authored_max(dir)])
	_check(end > 0, "E317: a settled end is found (> 0), got %d" % end)
	_check(end < EndModel.HARD_CAP, "E317: settles before the safety cap, got %d" % end)


## Fixed seed → the marker frame is stable across calls (so it doesn't jitter on
## every reload of the same effect).
func _test_is_deterministic() -> void:
	var dir := "res://assets/effects/E317"
	var data = EffectDataClass.load_from_directory(dir)
	var a := EndModel.derived_end_frame(data)
	var b := EndModel.derived_end_frame(data)
	_check(a == b, "same-seed derived end is deterministic (%d vs %d)" % [a, b])


## The whole point: E173 authors a SCREEN tint far past its particles. The derived
## runtime end must fall well short of that authored max — the tail is trimmed.
func _test_e173_trims_the_screen_tail() -> void:
	var dir := "res://assets/effects/E173"
	var end := _end(dir)
	var authored := _authored_max(dir)
	print("[EndModel] E173 derived_end=%d  authored_max=%d" % [end, authored])
	_check(end > 0, "E173: a settled end is found (> 0), got %d" % end)
	_check(authored > 0, "E173: has an authored span, got %d" % authored)
	_check(end < authored,
		"E173: derived end (%d) is strictly less than authored max (%d) — screen tail trimmed" % [end, authored])
