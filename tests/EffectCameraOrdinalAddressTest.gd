extends Node
## TDD guard for CAMERA ORDINAL ADDRESSING (ADR-0086 dec. 5, #286).
##
## A camera edit used to address a sub-channel event by its RAW storage keyframe
## index (`field_ref.event_index`). But a split (#267) / merge (#284/#285) re-runs
## `CameraLowering.lower`, which re-packs the flat keyframe array and RENUMBERS every
## index — even the first structural edit does, because `lower` drops the `mask==0`
## padding slot. So a raw index captured before a structural edit went stale: the
## follow-up edit (and the undo replay, which stores `{field_ref, before_raw}`) could
## land on the WRONG keyframe, and a selection keyed on the raw index was dropped.
##
## The fix: address by `(sub-channel, ordinal)` — the Nth angle / position / zoom event
## in `CameraLowering.parse` order. `parse ↔ lower` preserve per-sub-channel order, so
## the Nth event of a lane is the Nth event after any re-lower (verified on E317).
##
## Seams under test:
##   A. EffectEditSession.apply_edit → CameraChannel resolves (sub-channel, ordinal)
##      to the correct live keyframe AFTER a split renumbers the store.
##   B. EffectEditSession.undo after a structural edit replays onto the correct keyframe.
##   C. EffectScoreModel span ids are keyed on the ordinal — stable across a structural
##      edit (so a selection survives re-project).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraOrdinalAddressTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

# Positioned command-word bits (mirror CameraChannel's decode maps).
const SRC_MAP := 0x0C0
const SRC_CASTER := 0x140
const INTERP_COSINE_A := 0x0400

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_ordinal_tracks_the_subchannel_event_across_a_renumbering_split()
	_test_undo_after_a_split_reverts_the_correct_keyframe()
	_test_subchannel_span_id_survives_a_structural_renumber()

	print("\n=== EffectCameraOrdinalAddressTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraOrdinalAddressTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraOrdinalAddressTest")
		get_tree().quit(0)


# --- Slice A: ordinal resolution survives a renumbering split ----------------

## A `mask==0` pad at idx0 + a coalesced angle+position keyframe (MAP) at idx1.
## Editing the ANGLE event's Source (ordinal 0) splits the keyframe AND drops the pad,
## so the store renumbers: the angle keyframe is no longer at raw index 1. A SECOND
## edit addressed by the SAME ordinal (angle, 0) must still land on the angle keyframe
## — sparing the position sibling. Under the old raw-index address the second edit
## would follow event_index 1 onto the POSITION keyframe.
func _test_ordinal_tracks_the_subchannel_event_across_a_renumbering_split() -> void:
	var data = _effect_with_pad_then_coalesced_kf()
	var session = EffectEditSession.new(data)

	# Edit 1: split the angle sub-channel out (source MAP -> CASTER).
	var split: Dictionary = session.apply_edit(_ref("angle", "source_mode", 0), SRC_CASTER)
	_assert_eq(split.get("structural", false), true, "the split edit is structural")

	# The pad is gone and the keyframe split in two — raw indices have shifted.
	var table = data.camera.get_table("for_each")
	_assert_eq(_live_count(table), 2, "store re-lowered to two keyframes (pad dropped, split applied)")

	# Edit 2: address the angle event again by ordinal 0 — set Param to 2.
	var second: Dictionary = session.apply_edit(_ref("angle", "param_index", 0), 2)
	_assert_eq(second.is_empty(), false, "ordinal 0 still resolves an angle keyframe after the renumber")

	var angle_kf = _kf_with_mask(table, 1)
	var pos_kf = _kf_with_mask(table, 2)
	_assert_eq(angle_kf != null, true, "an angle-only keyframe exists")
	_assert_eq(pos_kf != null, true, "a position-only keyframe exists")
	if angle_kf == null or pos_kf == null:
		return
	_assert_eq(int(angle_kf.param_index), 2, "the second edit landed on the ANGLE keyframe")
	_assert_eq(angle_kf.source_mode, "CASTER", "the angle keyframe kept its split-out CASTER source")
	_assert_eq(int(pos_kf.param_index), 0, "the position sibling was spared (still param 0)")
	_assert_eq(pos_kf.source_mode, "MAP", "the position sibling kept MAP")


# --- Slice B: undo replays onto the correct keyframe ------------------------

## The undo stack stores `{field_ref, before_raw}`. Because `field_ref` carries the
## STABLE ordinal (not the raw index the split renumbered), the undo replay lands on the
## angle event that was edited — reverting its source to MAP, which re-coalesces it with
## the position sibling. Under the old raw-index address the replay would follow the stale
## index onto the POSITION keyframe and the angle event would stay CASTER forever.
func _test_undo_after_a_split_reverts_the_correct_keyframe() -> void:
	var data = _effect_with_pad_then_coalesced_kf()
	var session = EffectEditSession.new(data)

	session.apply_edit(_ref("angle", "source_mode", 0), SRC_CASTER)   # split angle out
	_assert_eq(session.undo(), true, "undo reports it unwound the split edit")

	var table = data.camera.get_table("for_each")
	_assert_eq(_live_count(table), 1, "reverting the angle source re-coalesced the keyframe")
	var kf = _kf_with_mask(table, 3)
	_assert_eq(kf != null, true, "the re-coalesced keyframe carries both angle+position")
	if kf == null:
		return
	_assert_eq(kf.source_mode, "MAP", "the ANGLE event's source was reverted to MAP (right keyframe)")


# --- Slice C: span id is stable across a structural edit --------------------

## Selection is keyed on the span id. When the id embeds the raw keyframe index, a split
## (which renumbers + drops the pad) changes it and the selection is dropped on re-project.
## Keyed on the ordinal, the angle span keeps its id across the split → selection survives.
func _test_subchannel_span_id_survives_a_structural_renumber() -> void:
	var data = _effect_with_pad_then_coalesced_kf()
	var session = EffectEditSession.new(data)

	var before_id := _first_angle_span_id(data)
	_assert_eq(before_id != "", true, "there is an angle span to select before the edit")

	session.apply_edit(_ref("angle", "source_mode", 0), SRC_CASTER)   # structural split

	var after_id := _first_angle_span_id(data)
	_assert_eq(after_id, before_id, "the angle span keeps its id across the structural renumber")


func _first_angle_span_id(data) -> String:
	var score: Dictionary = Model.build(data)
	for lane in score.get("lanes", []):
		if String(lane.get("id", "")) == "camera:for_each:angle":
			var spans: Array = lane.get("spans", [])
			if not spans.is_empty():
				return String(spans[0].get("id", ""))
	return ""


# --- fixtures ---------------------------------------------------------------

## for_each: idx0 = mask==0 padding (end 0), idx1 = coalesced angle+position (mask 3,
## MAP, COSINE_A) @ end 10. cmd = interp 0x400 | source 0xC0 | mask 3 = 0x4C3.
func _effect_with_pad_then_coalesced_kf():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 0,
			"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0000, "channel_mask": 0,
			"source_mode": "TARGET", "interpolation": "UNKNOWN", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 10,
			"angle": [1, 2, 3], "position": [4, 5, 6], "zoom": [0, 0, 0],
			"command_raw": 0x04C3, "channel_mask": 3,
			"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0},
	]}})
	return data


func _ref(camera_channel: String, field: String, ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each",
		"camera_channel": camera_channel, "ordinal": ordinal, "field": field}


func _live_count(table) -> int:
	return mini(table.keyframes.size(), table.max_keyframe + 1)


## First live keyframe whose mask carries exactly this single sub-channel bit.
func _kf_with_mask(table, bit: int):
	for i in range(_live_count(table)):
		var kf = table.keyframes[i]
		if int(kf.channel_mask) == bit:
			return kf
	return null


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
