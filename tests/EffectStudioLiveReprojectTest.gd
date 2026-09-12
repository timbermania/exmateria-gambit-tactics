extends Node
## TDD guard: the inspector re-projects from the LIVE keyframe, never a stale
## score-build snapshot (#267 follow-on — the camera-edit desync). When an author
## edits a keyframe through the choke point (EffectEditSession.apply_edit) and then
## RE-SELECTS the span, EffectScoreModel.span_sections must show the NEW value.
##
## Before this fix only the SCREEN arm resolved the live keyframe; camera / palette /
## sound projected `span.fields` — a copy captured once at score-build time — so a
## re-select after an edit showed the OLD value (the UI "reverted" while the data was
## actually correct). This pins all three archetypes to live re-projection.
##
## Seam: EffectScoreModel.span_sections(span, effect_data) — the model's public
## projection entry point the page calls on every (re)select. Edits go through the
## real EffectEditSession, not by poking fields, so the test tracks the true path.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioLiveReprojectTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const PaletteData = ExMateriaEffects.PaletteData
const TimelineData = ExMateriaEffects.TimelineData
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_camera_reproject_reflects_live_edit()
	_test_palette_reproject_reflects_live_edit()
	_test_sound_reproject_reflects_live_edit()

	print("\n=== EffectStudioLiveReprojectTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioLiveReprojectTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioLiveReprojectTest")
		get_tree().quit(0)


# --- camera ----------------------------------------------------------------

## Editing Source TARGET/DIRECT → CASTER folds command_raw on the live keyframe;
## re-projecting the SAME span must show CASTER (0x140), not the build-time snapshot.
func _test_camera_reproject_reflects_live_edit() -> void:
	var ed = _effect_with_camera()
	var score := Model.build(ed)
	var span: Dictionary = _lane(score, "camera:phase1:angle")["spans"][0]

	_assert_eq(_row(Model.span_sections(span, ed), "Source"), 0x040,
		"[camera] baseline Source row = DIRECT (0x040)")

	var session = EffectEditSession.new(ed)
	# Address by (camera_channel, ordinal) — the #286 ordinal address that superseded the
	# old event_index (CameraChannel._origin_index). The span is camera:phase1:angle.
	session.apply_edit({"channel": "camera", "context": "phase1",
		"camera_channel": "angle", "ordinal": 0, "field": "source_mode"}, 0x140)

	_assert_eq(_row(Model.span_sections(span, ed), "Source"), 0x140,
		"[camera] re-projected Source reflects the live edit (CASTER 0x140)")


# --- palette ---------------------------------------------------------------

## Editing the tint's Blend mode writes ctrl bits on the live keyframe; re-projecting
## the SAME span must show the new mode.
func _test_palette_reproject_reflects_live_edit() -> void:
	var ed = _effect_with_palette()
	var score := Model.build(ed)
	var span: Dictionary = _lane(score, "palette:for_each:target")["spans"][0]

	_assert_eq(_row_str(Model.span_sections(span, ed), "Blend mode"), "2",
		"[palette] baseline Blend mode = 2")

	var session = EffectEditSession.new(ed)
	session.apply_edit({"channel": "palette", "context": "for_each",
		"channel_name": "target", "event_index": 0, "field": "blend_mode"}, 5)

	_assert_eq(_row_str(Model.span_sections(span, ed), "Blend mode"), "5",
		"[palette] re-projected Blend mode reflects the live edit (5)")


# --- sound -----------------------------------------------------------------

## Editing a trigger's Sound id writes it on the live keyframe dict; re-projecting the
## SAME span must show the new id.
func _test_sound_reproject_reflects_live_edit() -> void:
	var ed = _effect_with_sound()
	var score := Model.build(ed)
	var span: Dictionary = _lane(score, "sound:for_each:0")["spans"][0]
	var ei: int = int(span.get("keyframe_index", -1))

	_assert_eq(_row(Model.span_sections(span, ed), "Sound"), 5,
		"[sound] baseline Sound = 5")

	var session = EffectEditSession.new(ed)
	session.apply_edit({"channel": "sound", "phase": "for_each", "channel_index": 0,
		"event_index": ei, "field": "sound_id"}, 7)

	_assert_eq(_row(Model.span_sections(span, ed), "Sound"), 7,
		"[sound] re-projected Sound reflects the live edit (7)")


# --- fixtures --------------------------------------------------------------

func _effect_with_camera():
	var ed = _timeline_effect()
	ed.camera = CameraData.from_json({
		"phase1": {"max_keyframe": 1, "keyframes": [{
			"index": 0, "end_frame": 8,
			"angle": [10, 20, 30], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR",
			"param_index": 0, "flags": 0,
		}]},
	})
	return ed


func _effect_with_palette():
	var ed = _timeline_effect()
	ed.palette = PaletteData.from_json({
		"for_each": {"target": {"context": "for_each", "channel_name": "target",
			"max_keyframe": 2, "keyframes": [
				{"index": 0, "duration_frames": 10, "enabled": true, "blend_mode": 2,
					"rgb": [255, 128, 0]}]}},
	})
	return ed


func _effect_with_sound():
	var ed = _timeline_effect()
	ed.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": 2, "keyframes": [
				{"duration_frames": 6, "sound_id": 5},
				{"duration_frames": 4, "sound_id": 9}]},
		],
	}
	return ed


func _timeline_effect():
	var ed = EffectData.new()
	ed.timeline = TimelineData.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	return ed


func _row(sections: Array, name: String) -> int:
	for sec in sections:
		for f in sec.get("fields", []):
			if f.get("name", "") == name:
				return int(f.get("value", -1))
	return -1


func _row_str(sections: Array, name: String) -> String:
	for sec in sections:
		for f in sec.get("fields", []):
			if f.get("name", "") == name:
				return str(f.get("value", ""))
	return "<none>"


func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score.get("lanes", []):
		if lane.get("id", "") == lane_id:
			return lane
	return {}


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
