extends Node
## TDD guard for the CAMERA COMPILED (storage/truth) lane — the strictly READ-ONLY
## observability pane over the packed camera keyframe table (handoff: "compiled lane
## + Length row"). ADR-0086's sub-channel AUTHORING stands unchanged; this adds a lane
## that shows the packed truth (one span per stored keyframe) so a designer can SEE
## how their sub-channel edits coalesce/split into the actual byte-level schedule.
##
## Two seams live here:
##   A) EffectScoreModel.build()["lanes"] gains a `camera_compiled` lane per phase with
##      a camera table, appended AFTER that phase's three sub-channel lanes. One span
##      per packed keyframe, no-op/terminator keyframes collapsed exactly like
##      _camera_spans (end must advance past prev_end).
##   B) EffectScoreModel.span_sections(camera_compiled span) → CameraCompiledProjector,
##      emitting ONLY read-only `const` rows (Index, End frame, Length, Channels,
##      Source, Interp, Param, Flags, Command word). No edit/link field → editing is
##      impossible by construction (the orphan bug ADR-0086 killed stays dead).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraCompiledLaneTest.tscn

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData
const Compiled = preload("res://src/effects/studio/CameraCompiledProjector.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# Seam A — the compiled lane + spans in the score.
	_test_compiled_lane_exists_after_sub_channel_lanes()
	_test_one_marker_per_packed_keyframe_dropping_no_ops()
	_test_coincident_split_siblings_both_show()
	_test_span_fields_carry_the_packed_command_word()
	_test_compiled_lane_has_no_mute_controls()
	# Seam B — the read-only projector.
	_test_projector_emits_only_const_rows()
	_test_projector_decodes_channels_and_command_word()
	_test_span_sections_routes_camera_compiled_to_the_projector()

	print("\n=== EffectCameraCompiledLaneTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraCompiledLaneTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraCompiledLaneTest")
		get_tree().quit(0)


# --- Seam A: compiled lane in the score -----------------------------------

## The compiled lane is appended AFTER the phase's angle/position/zoom sub-channel
## lanes — it is the storage-view companion to them, not a replacement.
func _test_compiled_lane_exists_after_sub_channel_lanes() -> void:
	var score := Model.build(_camera_effect())
	var lane := _lane(score, "camera_compiled:phase1")
	_assert_true(not lane.is_empty(), "a camera_compiled lane exists for a phase with a table")
	_assert_eq(lane["kind"], "camera_compiled", "lane kind is camera_compiled")
	_assert_eq(lane["phase"], "phase1", "lane carries its phase")
	var zoom_i := _lane_index(score, "camera:phase1:zoom")
	var compiled_i := _lane_index(score, "camera_compiled:phase1")
	_assert_true(compiled_i == zoom_i + 1,
		"compiled lane is appended right after the three sub-channel lanes (zoom is last)")


## One MARKER per REAL packed keyframe: iterate 0..max_keyframe and emit a point marker
## for every keyframe that drives a sub-channel (channel_mask != 0 — the SAME "is-this-
## real" test CameraLowering.parse applies). Pure no-ops (the mask==0 empty slots the SoA
## pads with) drop out. A marker is anchored AT its end_frame (a keyframe is "a target
## reached at frame N"), NOT an interval — storage stores no duration, so the compiled
## view must not invent one (that per-track window lives on the sub-channel lanes).
func _test_one_marker_per_packed_keyframe_dropping_no_ops() -> void:
	var score := Model.build(_camera_effect())
	var lane := _lane(score, "camera_compiled:phase1")
	_assert_eq(lane["spans"].size(), 2,
		"kf1 and kf2 are real; the mask==0 empty-slot pads (kf0, kf3) drop")
	var s0: Dictionary = lane["spans"][0]
	var s1: Dictionary = lane["spans"][1]
	_assert_true(s0.get("marker", false), "a compiled item is a point marker, not an interval")
	_assert_eq(s0["keyframe_index"], 1, "first marker is keyframe 1")
	_assert_eq(s0["authored_start"], s0["authored_end"], "a marker is a point (authored start == end)")
	_assert_eq(s0["authored_end"], 8, "kf1 marker sits at its end_frame")
	_assert_eq(s0["start"], 8, "phase1 offset 0 → absolute frame == end_frame")
	_assert_eq(s0["end"], 8, "a marker is a point (start == end)")
	_assert_eq(s1["keyframe_index"], 2, "second marker is keyframe 2 (kf3 pad dropped)")
	_assert_eq(s1["authored_end"], 58, "kf2 marker sits at its end_frame")
	_assert_eq(s1["start"], 58, "kf2 absolute frame")
	_assert_eq(s1["id"], "camera_compiled:phase1#2", "marker id is lane_id#keyframe_index")


## The behavior /verify demands: when a coalesced keyframe SPLITS, the storage grows two
## keyframes at the same end_frame (angle@10, position@10). Both must show as distinct
## markers — the split is the whole point of the observability lane. As POINT markers they
## land at the same frame (two keyframes reached at frame 10), each carrying its own mask.
func _test_coincident_split_siblings_both_show() -> void:
	var ed = _bare_camera({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 10, "channel_mask": 1, "command_raw": 0x0141,
			"source_mode": "CASTER", "interpolation": "IMMEDIATE", "angle": [1, 2, 3]},
		{"index": 1, "end_frame": 10, "channel_mask": 2, "command_raw": 0x00C2,
			"source_mode": "MAP", "interpolation": "IMMEDIATE", "position": [4, 5, 6]}]}})
	var lane := _lane(Model.build(ed), "camera_compiled:for_each")
	_assert_eq(lane["spans"].size(), 2,
		"two same-frame split siblings BOTH show (the sibling is not collapsed away)")
	var s0: Dictionary = lane["spans"][0]
	var s1: Dictionary = lane["spans"][1]
	_assert_eq(int(s0["fields"]["channel_mask"]), 1, "first sibling is the angle keyframe")
	_assert_eq(int(s1["fields"]["channel_mask"]), 2, "second sibling is the position keyframe")
	_assert_true(s0.get("marker", false) and s1.get("marker", false), "both are point markers")
	# for_each offset is phase1_duration (8); markers sit at 8 + end_frame(10) = 18.
	_assert_eq(s0["start"], 18, "first sibling marker at the for_each-offset frame")
	_assert_eq(s1["start"], 18, "coincident sibling lands at the SAME frame (both reached at 10)")


## The span carries the packed keyframe's raw fields — this is the whole point of a
## storage view: what the bytes actually say, including the raw command word.
func _test_span_fields_carry_the_packed_command_word() -> void:
	var score := Model.build(_camera_effect())
	var s: Dictionary = _lane(score, "camera_compiled:phase1")["spans"][0]
	var f: Dictionary = s["fields"]
	_assert_eq(int(f["end_frame"]), 8, "fields carry end_frame")
	_assert_eq(int(f["channel_mask"]), 3, "fields carry the packed channel_mask (angle+position)")
	_assert_eq(str(f["source_mode"]), "DIRECT", "fields carry the decoded source mode")
	_assert_eq(str(f["interpolation"]), "LINEAR", "fields carry the decoded interpolation")
	_assert_eq(int(f["param_index"]), 1, "fields carry param_index")
	_assert_eq(int(f["flags"]), 2, "fields carry flags")
	_assert_eq(int(f["command_raw"]), 0x0843, "fields carry the raw command word")


## The compiled lane is display-only truth — it must NOT draw Solo/Mute (like the
## sub-channel camera lanes). Muting a storage view is meaningless.
func _test_compiled_lane_has_no_mute_controls() -> void:
	_assert_true(not Model.has_mute_controls("camera_compiled"),
		"camera_compiled is display-only — no S/M, never silenced")


# --- Seam B: the read-only projector --------------------------------------

## Every row the projector emits is a read-only `const` — no `edit`, no `link`,
## no `field_ref`. Editing the packed form is impossible by construction.
func _test_projector_emits_only_const_rows() -> void:
	var secs := Compiled.sections(_compiled_span())
	var rows := 0
	for sec in secs:
		for f in sec.get("fields", []):
			rows += 1
			_assert_eq(f.get("shape", ""), "const", "%s is a read-only const row" % f.get("name", "?"))
			_assert_true(not f.has("field_ref"), "%s carries no write-side field_ref" % f.get("name", "?"))
			_assert_true(not f.has("editor"), "%s carries no editor widget" % f.get("name", "?"))
	_assert_true(rows >= 8, "the projector shows the full storage row set (got %d)" % rows)
	# A point marker has no duration — the storage stores only end_frame, so no Length row
	# (the real per-track window lives on the sub-channel lanes, not the storage view).
	_assert_true(_value(secs, "Length") == "<missing:Length>", "no Length row on a point marker")


## The projector decodes the packed truth into readable rows: the channel_mask into
## sub-channel names, and the raw command word as hex.
func _test_projector_decodes_channels_and_command_word() -> void:
	var secs := Compiled.sections(_compiled_span())
	_assert_eq(_value(secs, "Index"), "2", "Index row shows the keyframe index")
	_assert_eq(_value(secs, "End frame"), "58", "End frame row is the marker's stored frame")
	_assert_eq(_value(secs, "Channels"), "angle + position", "mask 3 decodes to sub-channel names")
	_assert_eq(_value(secs, "Source"), "DIRECT", "Source row")
	_assert_eq(_value(secs, "Interp"), "LINEAR", "Interp row")
	_assert_eq(_value(secs, "Param"), "1", "Param row")
	_assert_eq(_value(secs, "Flags"), "2", "Flags row")
	_assert_eq(_value(secs, "Command word"), "0x0843", "Command word row is the raw bits as hex")


## The score-model dispatcher routes a camera_compiled span to the compiled
## projector (read-only rows), NOT to the editable CameraTweenProjector.
func _test_span_sections_routes_camera_compiled_to_the_projector() -> void:
	var score := Model.build(_camera_effect())
	var span: Dictionary = _lane(score, "camera_compiled:phase1")["spans"][1]  # keyframe 2
	var secs := Model.span_sections(span, _camera_effect())
	_assert_eq(_value(secs, "Channels"), "angle", "routed span decodes kf2's mask (angle only)")
	# Read-only through the dispatcher too.
	var any_edit := false
	for sec in secs:
		for f in sec.get("fields", []):
			if f.get("shape", "") != "const":
				any_edit = true
	_assert_true(not any_edit, "the dispatched compiled sections are all read-only")


# --- fixtures --------------------------------------------------------------

## A minimal EffectData whose camera table has two real keyframes bracketed by mask==0
## empty-slot pads — exactly the real ROM shape (E317's SoA pads with mask==0/end==0
## slots, verified). kf1/kf2 are the real keyframes; kf0/kf3 are pads that must drop.
func _camera_effect():
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json({
		"phase1": {"max_keyframe": 3, "keyframes": [
			{"index": 0, "end_frame": 0, "channel_mask": 0, "interpolation": "UNKNOWN_0x0000"},
			{"index": 1, "end_frame": 8, "channel_mask": 3, "command_raw": 0x0843,
				"source_mode": "DIRECT", "interpolation": "LINEAR",
				"param_index": 1, "flags": 2, "position": [1, 2, 3], "angle": [10, 20, 30]},
			{"index": 2, "end_frame": 58, "channel_mask": 1, "command_raw": 0x0A41,
				"source_mode": "TARGET", "interpolation": "COSINE_C",
				"param_index": 0, "flags": 0, "angle": [4, 5, 6]},
			{"index": 3, "end_frame": 0, "channel_mask": 0, "interpolation": "UNKNOWN_0x0000"}]},
	})
	return ed


## A minimal EffectData carrying a phase1-offset-0 timeline and a camera table from
## the given camera.json-shaped dict (phase1/for_each offsets: phase1=0, for_each=8).
func _bare_camera(camera_json: Dictionary):
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64},
		"particle_channels": [],
	})
	ed.camera = ExMateriaEffects.CameraData.from_json(camera_json)
	return ed


## A compiled marker span as the score model builds it — a point at end_frame. The
## projector reads its `fields` plus keyframe_index (Index).
func _compiled_span() -> Dictionary:
	return {
		"kind": "camera_compiled", "phase": "phase1", "keyframe_index": 2, "marker": true,
		"authored_start": 58, "authored_end": 58,
		"fields": {
			"index": 2, "end_frame": 58, "channel_mask": 3,
			"source_mode": "DIRECT", "interpolation": "LINEAR",
			"param_index": 1, "flags": 2, "command_raw": 0x0843,
		},
	}


func _lane(score: Dictionary, lane_id: String) -> Dictionary:
	for lane in score["lanes"]:
		if lane["id"] == lane_id:
			return lane
	return {}


func _lane_index(score: Dictionary, lane_id: String) -> int:
	for i in range(score["lanes"].size()):
		if score["lanes"][i]["id"] == lane_id:
			return i
	return -1


func _value(sections: Array, field_name: String) -> String:
	for s in sections:
		for f in s.get("fields", []):
			if f.get("name", "") == field_name:
				return str(f.get("value", ""))
	return "<missing:%s>" % field_name


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
