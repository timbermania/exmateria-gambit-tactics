extends Node
## TDD guard for DECOUPLED sub-channel authoring (ADR-0086, handoff point 3).
##
## Camera stores coincident-and-agreeing sub-channel events packed into one masked
## keyframe with a SHARED command word. Under the authoring model the three
## sub-channels are INDEPENDENT lanes, so editing a shared field (source / interp /
## end / param / flags) on ONE sub-channel of a coalesced keyframe must NOT drag its
## siblings along — the encoder SPLITS that sub-channel out (via CameraLowering)
## instead of mutating the shared word in place. Value edits (angle/pos/zoom) already
## live in separate vecs, so they never perturb and never split.
##
## Seam: EffectEditSession.apply_edit → CameraChannel.apply_raw (the #255 choke
## point). A split edit reports `structural: true` so the host re-projects.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraDecoupleTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const CameraLowering = preload("res://src/effects/studio/CameraLowering.gd")
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")

const SRC_MAP := 0x0C0
const SRC_CASTER := 0x140

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_editing_one_subchannels_source_splits_and_spares_the_sibling()
	_test_value_edit_on_a_coalesced_keyframe_does_not_split()
	_test_shared_field_edit_on_a_solo_keyframe_stays_in_place()
	_test_split_over_native_slots_is_flagged_but_applied()
	_test_end_frame_edit_that_makes_two_solo_kfs_agree_remerges()
	_test_source_edit_that_makes_split_siblings_agree_remerges()
	_test_solo_edit_that_stays_disagreeing_does_not_remerge()
	_test_solo_end_frame_edit_flags_relayout()
	_test_solo_source_edit_flags_relayout_for_labels()

	print("\n=== EffectCameraDecoupleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraDecoupleTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraDecoupleTest")
		get_tree().quit(0)


## The core guarantee: on a mask=3 (angle+position) keyframe sharing source MAP,
## changing the ANGLE event's source to CASTER splits the keyframe — angle becomes
## CASTER while position KEEPS MAP. Before ADR-0086 the shared word would have
## dragged position to CASTER too.
func _test_editing_one_subchannels_source_splits_and_spares_the_sibling() -> void:
	var data = _effect_with_coalesced_camera_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ref("angle", "source_mode"), SRC_CASTER)

	_assert_eq(res.get("structural", false), true, "a split edit is structural (host re-projects)")
	_assert_eq(res.get("before_raw"), SRC_MAP, "reports the pre-edit angle source bits")
	_assert_eq(res.get("after_raw"), SRC_CASTER, "reports the post-edit angle source bits")

	var table = data.camera.get_table("for_each")
	_assert_eq(table.keyframes.size(), 2, "the coalesced keyframe split into two")

	var lanes: Dictionary = CameraLowering.parse(table)
	_assert_eq(lanes["angle"][0]["source_bits"], SRC_CASTER, "the angle event took the new source")
	_assert_eq(lanes["angle"][0]["value"], Vector3i(1, 2, 3), "angle value preserved through the split")
	_assert_eq(lanes["position"][0]["source_bits"], SRC_MAP, "the position sibling KEPT its own source")
	_assert_eq(lanes["position"][0]["value"], Vector3i(4, 5, 6), "position value preserved through the split")


## A value edit (angle_x) on the same coalesced keyframe writes only the angle vec —
## no split, non-structural, position untouched.
func _test_value_edit_on_a_coalesced_keyframe_does_not_split() -> void:
	var data = _effect_with_coalesced_camera_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ref("angle", "angle_x"), 99)

	_assert_eq(res.get("structural", false), false, "a value edit does not restructure")
	var table = data.camera.get_table("for_each")
	_assert_eq(table.keyframes.size(), 1, "still one keyframe — no split")
	_assert_eq(table.keyframes[0].angle, Vector3i(99, 2, 3), "angle_x written")
	_assert_eq(table.keyframes[0].position, Vector3i(4, 5, 6), "position vec untouched")


## A shared-field edit on a SOLO keyframe (mask selects only this sub-channel) has no
## sibling to spare, so it stays a fast in-place fold — not structural.
func _test_shared_field_edit_on_a_solo_keyframe_stays_in_place() -> void:
	var data = _effect_with_solo_camera_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ref("angle", "source_mode"), SRC_CASTER)

	_assert_eq(res.get("structural", false), false, "a solo-keyframe field edit is in place, not structural")
	var kf = data.camera.get_table("for_each").get_keyframe(0)
	_assert_eq(kf.source_mode, "CASTER", "source folded in place on the solo keyframe")
	_assert_eq(kf.channel_mask, 1, "still angle-only — no membership change")


## A for_each table already at its 17-slot capacity — 16 solo zoom keyframes plus one
## coalesced mask=3 (angle+position). Splitting the coalesced keyframe's angle source
## pushes the compiled count to 18, which Faithful flags — but Free still applies it.
func _test_split_over_native_slots_is_flagged_but_applied() -> void:
	var data = _effect_at_camera_capacity()
	var session = EffectEditSession.new(data)

	# The coalesced mask=3 keyframe holds the ONLY angle event → (angle, ordinal 0),
	# regardless of the raw slot it packs into behind the 16 zoom keyframes.
	var ref := {"channel": "camera", "context": "for_each", "ordinal": 0,
		"camera_channel": "angle", "field": "source_mode"}
	var res: Dictionary = session.apply_edit(ref, SRC_CASTER)

	_assert_eq(res.get("structural", false), true, "the over-capacity split still restructures")
	var verdict: Dictionary = res.get("faithful", {})
	_assert_eq(verdict.get("ok", true), false, "compiling to 18 keyframes over 17 slots is flagged")
	var table = data.camera.get_table("for_each")
	_assert_eq(table.keyframes.size(), 18, "Free applies the split (18 keyframes) despite the flag")


## Auto-remerge (#284): splits are automatic, so merges must be too. Two SOLO
## keyframes on different sub-channels (angle@10, position@20) that come to COINCIDE
## via an end_frame edit — and already agree on the command word — must re-lower into
## ONE coalesced mask=3 keyframe. Mirror of the split test: a solo edit that makes two
## keyframes agree collapses them, structural so the host re-projects.
func _test_end_frame_edit_that_makes_two_solo_kfs_agree_remerges() -> void:
	var data = _effect_with_two_mergeable_solo_kfs()
	var session = EffectEditSession.new(data)

	# Drag the position event (its lane's ordinal 0) from end 20 back onto the angle's end 10.
	var ref := {"channel": "camera", "context": "for_each", "ordinal": 0,
		"camera_channel": "position", "field": "end_frame"}
	var res: Dictionary = session.apply_edit(ref, 10)

	_assert_eq(res.get("structural", false), true, "the auto-remerge is structural (host re-projects)")
	_assert_eq(res.get("before_raw"), 20, "reports the pre-edit end_frame")
	_assert_eq(res.get("after_raw"), 10, "reports the post-edit end_frame")

	var table = data.camera.get_table("for_each")
	_assert_eq(table.keyframes.size(), 1, "the two agreeing solo keyframes coalesced into one")
	_assert_eq(table.keyframes[0].channel_mask, 3, "coalesced keyframe carries both angle+position bits")

	var lanes: Dictionary = CameraLowering.parse(table)
	_assert_eq(lanes["angle"][0]["value"], Vector3i(1, 2, 3), "angle value preserved through the merge")
	_assert_eq(lanes["position"][0]["value"], Vector3i(4, 5, 6), "position value preserved through the merge")


## The command-field mirror: two SPLIT SIBLINGS already on the same frame but disagreeing
## on source (angle=MAP, position=CASTER). Editing the position event's source to MAP makes
## them agree, so they re-merge into one coalesced keyframe.
func _test_source_edit_that_makes_split_siblings_agree_remerges() -> void:
	var data = _effect_with_disagreeing_coincident_solo_kfs()
	var session = EffectEditSession.new(data)

	var ref := {"channel": "camera", "context": "for_each", "ordinal": 0,
		"camera_channel": "position", "field": "source_mode"}
	var res: Dictionary = session.apply_edit(ref, SRC_MAP)

	_assert_eq(res.get("structural", false), true, "bringing siblings into agreement re-merges (structural)")
	var table = data.camera.get_table("for_each")
	_assert_eq(table.keyframes.size(), 1, "the now-agreeing siblings coalesced into one")
	_assert_eq(table.keyframes[0].channel_mask, 3, "coalesced keyframe carries both angle+position bits")

	var lanes: Dictionary = CameraLowering.parse(table)
	_assert_eq(lanes["position"][0]["source_bits"], SRC_MAP, "position took the new source")
	_assert_eq(lanes["angle"][0]["source_bits"], SRC_MAP, "angle kept MAP")


## A solo edit that leaves the keyframes DISAGREEING (still different end_frames) must NOT
## re-merge or report structural — re-lower only restructures when the count actually drops.
func _test_solo_edit_that_stays_disagreeing_does_not_remerge() -> void:
	var data = _effect_with_two_mergeable_solo_kfs()   # angle@10, position@20
	var session = EffectEditSession.new(data)

	# Edit the angle event's source; the two keyframes still sit at different frames.
	var ref := {"channel": "camera", "context": "for_each", "ordinal": 0,
		"camera_channel": "angle", "field": "source_mode"}
	var res: Dictionary = session.apply_edit(ref, SRC_CASTER)

	_assert_eq(res.get("structural", false), false, "no coincidence → no merge → not structural")
	var table = data.camera.get_table("for_each")
	_assert_eq(table.keyframes.size(), 2, "still two separate keyframes")


## end_frame moves the span boundary AND the compiled marker, so even a NON-structural
## solo edit must tell the host to re-layout the lane — otherwise the timeline sits stale
## while the sim re-folds (the reported stale-timeline bug). The flag is `relayout: true`.
func _test_solo_end_frame_edit_flags_relayout() -> void:
	var data = _effect_with_solo_camera_kf()   # single angle-only keyframe, end 10
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ref("angle", "end_frame"), 25)

	_assert_eq(res.get("structural", false), false, "a lone end_frame edit is not structural")
	_assert_eq(res.get("relayout", false), true, "end_frame moved the span boundary → the lane must re-layout")
	_assert_eq(data.camera.get_table("for_each").get_keyframe(0).end_frame, 25, "end_frame written in place")


## A source_mode / interpolation edit changes NO lane geometry, but it DOES change what the
## stored value means — the value-row labels flip between absolute / offset / Δ / amplitude
## (#281). So it must ask the host to re-layout: the projector re-runs and relabels in place
## (a same-document reproject that preserves transport + selection). Only param/flags fold
## silently. (Superseded the earlier "source edit → no re-layout" contract, pre-#281.)
func _test_solo_source_edit_flags_relayout_for_labels() -> void:
	var data = _effect_with_solo_camera_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ref("angle", "source_mode"), SRC_CASTER)

	_assert_eq(res.get("structural", false), false, "a lone source edit is not structural")
	_assert_eq(res.get("relayout", false), true, "a source edit flips the value-row labels → re-layout")


# --- fixtures --------------------------------------------------------------

## A camera field_ref addressing a sub-channel event by lane + ordinal (ADR-0086
## amendment, #286). These fixtures each carry one event per lane → ordinal 0.
func _ref(camera_channel: String, field: String) -> Dictionary:
	return {"channel": "camera", "context": "for_each", "ordinal": 0,
		"camera_channel": camera_channel, "field": field}


## for_each with ONE coalesced mask=3 keyframe: angle+position share source MAP,
## interp COSINE_A. cmd = interp 0x400 | source 0xC0 | mask 3 = 0x4C3.
func _effect_with_coalesced_camera_kf():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 0, "keyframes": [{
		"index": 0, "end_frame": 10,
		"angle": [1, 2, 3], "position": [4, 5, 6], "zoom": [0, 0, 0],
		"command_raw": 0x04C3, "channel_mask": 3,
		"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0,
	}]}})
	return data


## for_each with ONE angle-only (mask=1) keyframe. cmd = 0x400 | 0xC0 | 1 = 0x4C1.
func _effect_with_solo_camera_kf():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 0, "keyframes": [{
		"index": 0, "end_frame": 10,
		"angle": [1, 2, 3], "position": [0, 0, 0], "zoom": [0, 0, 0],
		"command_raw": 0x04C1, "channel_mask": 1,
		"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0,
	}]}})
	return data


## for_each filled to its 17-slot capacity: 16 solo zoom keyframes (mask 4, distinct
## end_frames) at indices 0..15, then one coalesced mask=3 (angle+position, MAP) at
## index 16. Parses+lowers to exactly 17 keyframes.
func _effect_at_camera_capacity():
	var kfs: Array = []
	for i in range(16):
		kfs.append({
			"index": i, "end_frame": i + 1,
			"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [4096, 0, 0],
			"command_raw": 0x0444, "channel_mask": 4,   # interp 0x400 | source 0x40 | zoom
			"source_mode": "DIRECT", "interpolation": "COSINE_A", "param_index": 0, "flags": 0,
		})
	kfs.append({
		"index": 16, "end_frame": 100,
		"angle": [1, 2, 3], "position": [4, 5, 6], "zoom": [0, 0, 0],
		"command_raw": 0x04C3, "channel_mask": 3,   # interp 0x400 | source 0xC0 | angle|position
		"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0,
	})
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 16, "keyframes": kfs}})
	return data


## Two SOLO keyframes that AGREE on the command word (both MAP / COSINE_A) but sit at
## DIFFERENT frames: angle-only@10 (mask 1) and position-only@20 (mask 2). Dragging the
## position keyframe onto frame 10 makes them coincident-and-agreeing → they coalesce.
func _effect_with_two_mergeable_solo_kfs():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 10,
			"angle": [1, 2, 3], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x04C1, "channel_mask": 1,
			"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 20,
			"angle": [0, 0, 0], "position": [4, 5, 6], "zoom": [0, 0, 0],
			"command_raw": 0x04C2, "channel_mask": 2,
			"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0},
	]}})
	return data


## Two SOLO keyframes already COINCIDENT (both end 10) but DISAGREEING on source: angle-only
## MAP (mask 1) and position-only CASTER (mask 2). Since they disagree they stay two split
## siblings; editing position's source to MAP makes them agree → they coalesce.
func _effect_with_disagreeing_coincident_solo_kfs():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 1, "keyframes": [
		{"index": 0, "end_frame": 10,
			"angle": [1, 2, 3], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x04C1, "channel_mask": 1,   # interp 0x400 | source MAP 0xC0 | angle
			"source_mode": "MAP", "interpolation": "COSINE_A", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 10,
			"angle": [0, 0, 0], "position": [4, 5, 6], "zoom": [0, 0, 0],
			"command_raw": 0x0542, "channel_mask": 2,   # interp 0x400 | source CASTER 0x140 | position
			"source_mode": "CASTER", "interpolation": "COSINE_A", "param_index": 0, "flags": 0},
	]}})
	return data


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
