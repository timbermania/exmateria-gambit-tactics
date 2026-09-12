extends Node
## TDD guard (#271 follow-up): EffectScoreModel.phase2_content_end — the floor the studio
## applies to its displayed end frame so a SCHEDULED phase 2 (camera/particle/sound) plays
## live instead of being dimmed as "dead" when particles reap right at the phase-2 boundary.
## It is the max span extent across phase-2 lanes, EXCLUDING the read-live tint channels
## (screen/palette) — their long holds are intentionally NOT counted as "still running" (the
## EffectEndModel tail-trim principle: a tint held to f600 must not extend the effect). The
## faithful EffectEndModel particle-reap is untouched; this is purely the studio display floor.
##
## Run: <GODOT> --path . --quit-after 3 res://tests/EffectPhase2EndFloorTest.tscn

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_returns_phase2_camera_extent()
	_test_excludes_screen_and_palette_tint_holds()
	_test_excludes_sound_terminator_cap()
	_test_zero_when_no_phase2_lanes()
	_test_real_e019_reaches_phase2_content()

	print("\n=== EffectPhase2EndFloorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectPhase2EndFloorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectPhase2EndFloorTest")
		get_tree().quit(0)


func _lane(phase: String, kind: String, spans: Array) -> Dictionary:
	return {"id": "%s:%s" % [kind, phase], "phase": phase, "kind": kind, "spans": spans}


func _span(start: int, end: int) -> Dictionary:
	return {"start": start, "end": end}


func _terminator_span(start: int, end: int) -> Dictionary:
	return {"start": start, "end": end, "role": "terminator"}


func _test_returns_phase2_camera_extent() -> void:
	var score := {"lanes": [
		_lane("phase1", "particle", [_span(0, 60)]),
		_lane("for_each", "particle", [_span(96, 100)]),
		_lane("phase2", "camera", [_span(104, 118), _span(118, 120)]),
	]}
	_assert_eq(Model.phase2_content_end(score), 120, "phase2 camera content extent")


func _test_excludes_screen_and_palette_tint_holds() -> void:
	# A phase-2 screen tint held far out (f300) must NOT extend the floor — camera to 120 wins.
	var score := {"lanes": [
		_lane("phase2", "camera", [_span(104, 120)]),
		_lane("phase2", "screen", [_span(104, 300)]),
		_lane("phase2", "palette", [_span(104, 280)]),
	]}
	_assert_eq(Model.phase2_content_end(score), 120,
		"screen/palette tint holds are excluded from the floor")


func _test_zero_when_no_phase2_lanes() -> void:
	var score := {"lanes": [
		_lane("phase1", "particle", [_span(0, 60)]),
		_lane("for_each", "camera", [_span(96, 110)]),
	]}
	_assert_eq(Model.phase2_content_end(score), 0, "no phase2 content → no floor")


## The sound TERMINATOR (the inert end-of-track cap at the max keyframe index, ADR-0085
## decision 7) sits at its true frame — often a long silent tail past the real content —
## and must NOT extend the floor, exactly as build() already excludes it from max_frame.
## (Union-merge guard: without this, every effect with a sound track floored its displayed
## end at the terminator and the playhead crawled ~600 frames past dead content.)
func _test_excludes_sound_terminator_cap() -> void:
	var score := {"lanes": [
		_lane("phase1", "particle", [_span(0, 60)]),
		_lane("phase2", "camera", [_span(104, 120)]),
		_lane("phase2", "sound", [_span(105, 105), _terminator_span(689, 689)]),
	]}
	_assert_eq(Model.phase2_content_end(score), 120,
		"sound terminator cap is excluded from the floor")


## On real E019 the floor reaches phase 2's content end (120), well past the particle-reap
## (~105) that would otherwise dim phase 2.
func _test_real_e019_reaches_phase2_content() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/effects/E019")):
		print("  [skip] E019 assets absent")
		_passed += 1
		return
	var data = EffectDataClass.load_from_directory("res://assets/effects/E019")
	var score = Model.build(data, {}, {}, [])
	_assert_eq(Model.phase2_content_end(score), 120, "E019 phase2 content end")


# --- helpers ---------------------------------------------------------------
func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])
