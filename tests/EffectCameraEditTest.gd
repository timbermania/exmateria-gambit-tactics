extends Node
## TDD guard for the CAMERA authoring channel (wayfinder #267).
##
## Makes the Camera Timeline keyframes editable through the ONE mutation choke
## point (`EffectEditSession.apply_edit`, #255). A camera edit routes by channel
## to `CameraChannel.apply_raw`, the raw↔value encoder that:
##   * writes the raw value on the live `CameraData.Keyframe`,
##   * for the packed COMMAND word (source / interp / channel_mask / param / flags),
##     folds the edited bitfield back into `command_raw` preserving the other bits
##     AND recomputes the decoded string/int cache,
##   * declares `invalidates_sim` (camera framing is folded during the sim — unlike
##     the read-live screen colour — so a camera edit needs a re-seek to re-fold).
##
## Expected command-word literals are hand-computed from the bit layout
## (mask 0x0007 / param<<3 / source 0x01E0 / interp 0x1E00 / flags<<13), an
## independent source from the encoder's own math.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectCameraEditTest.tscn

const EffectData = ExMateriaEffects.EffectData
const CameraData = ExMateriaEffects.CameraData
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_edit_angle_component_writes_raw_and_invalidates_sim()
	_test_edit_position_and_zoom_components()
	_test_edit_end_frame()
	_test_edit_source_mode_folds_command_preserving_other_bits()
	_test_edit_interpolation_folds_command_preserving_source()
	_test_source_and_interp_edits_request_relayout_for_labels()
	_test_param_and_flags_edits_do_not_relayout()
	_test_channel_mask_is_not_an_authorable_field()
	_test_edit_param_index_and_flags()
	_test_apply_edit_reports_before_and_after_raw()
	_test_undo_restores_angle()
	_test_undo_restores_command_word()
	_test_out_of_range_s16_is_flagged_but_applied()
	_test_unknown_camera_field_is_a_noop()

	print("\n=== EffectCameraEditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectCameraEditTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectCameraEditTest")
		get_tree().quit(0)


# --- value fields (raw s16 arrays) -----------------------------------------

func _test_edit_angle_component_writes_raw_and_invalidates_sim() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ref("angle_y"), 999)

	var kf = data.camera.get_table("phase1").get_keyframe(0)
	_assert_eq(kf.angle.y, 999, "angle_y raw is written on the live keyframe")
	_assert_eq(kf.angle.x, 100, "the untouched pitch component is preserved")
	_assert_eq(res.get("invalidates_sim", false), true,
		"camera edits re-fold the sim (not read-live like screen colour)")


## Value edits address a sub-channel EVENT (ADR-0086 dec. 5, #286), so the position
## and zoom edits route through THEIR lanes — a coalesced (mask 7) keyframe carries all
## three, and each value edit writes its own vec in place (never a split).
func _test_edit_position_and_zoom_components() -> void:
	var data = _effect_with_coalesced_kf()
	var session = EffectEditSession.new(data)

	session.apply_edit(_ch_ref("position", "position_z", 0), -50)
	session.apply_edit(_ch_ref("zoom", "zoom", 0), 2048)

	var kf = data.camera.get_table("phase1").get_keyframe(0)
	_assert_eq(kf.position.z, -50, "position_z raw is written")
	_assert_eq(kf.position.x, 10, "position_x preserved")
	_assert_eq(kf.zoom.x, 2048, "zoom writes slot 0")
	_assert_eq(kf.zoom.y, 0, "the engine-ignored zoom slots are untouched")


func _test_edit_end_frame() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)
	session.apply_edit(_ref("end_frame"), 42)
	_assert_eq(data.camera.get_table("phase1").get_keyframe(0).end_frame, 42,
		"end_frame raw is written")


# --- the packed command word -----------------------------------------------

## command_raw fixture = 0x0841: mask=1(angle), param=0, source=0x040(DIRECT),
## interp=0x0800(LINEAR), flags=0. Editing source→CASTER(0x140):
## (0x0841 & ~0x01E0) | 0x140 = 0x0801 | 0x140 = 0x0941. interp+mask preserved.
func _test_edit_source_mode_folds_command_preserving_other_bits() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)

	session.apply_edit(_ref("source_mode"), 0x140)   # CASTER bits

	var kf = data.camera.get_table("phase1").get_keyframe(0)
	_assert_eq(kf.command_raw, 0x0941, "source bits folded in, other bits preserved")
	_assert_eq(kf.source_mode, "CASTER", "the decoded source_mode cache is recomputed")
	_assert_eq(kf.interpolation, "LINEAR", "interpolation untouched")
	_assert_eq(kf.channel_mask, 1, "channel_mask untouched")


## Editing interp→IMMEDIATE(0x0200): (0x0841 & ~0x1E00) | 0x0200
## = 0x0041 | 0x0200 = 0x0241. source bits preserved.
func _test_edit_interpolation_folds_command_preserving_source() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)

	session.apply_edit(_ref("interpolation"), 0x0200)   # IMMEDIATE bits

	var kf = data.camera.get_table("phase1").get_keyframe(0)
	_assert_eq(kf.command_raw, 0x0241, "interp bits folded in, source/mask preserved")
	_assert_eq(kf.interpolation, "IMMEDIATE", "decoded interpolation recomputed")
	_assert_eq(kf.source_mode, "DIRECT", "source_mode untouched")


## source_mode and interpolation drive the value-row LABELS (#281: an offset yaw vs an
## absolute yaw vs a shake amplitude), so an edit to either must ask the page to REPROJECT
## in place — else the labels stay stale until the author re-selects the span. A reproject
## also refreshes the sim preview, which a mode/interp change needs anyway.
func _test_source_and_interp_edits_request_relayout_for_labels() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)

	var src_res: Dictionary = session.apply_edit(_ref("source_mode"), 0x140)   # CASTER
	_assert_true(src_res.get("relayout", false), "a source_mode edit requests relayout (labels refresh)")

	var interp_res: Dictionary = session.apply_edit(_ref("interpolation"), 0x1000)  # SHAKE_DAMPED
	_assert_true(interp_res.get("relayout", false), "an interpolation edit requests relayout (labels refresh)")


## param_index / flags do NOT change any label or lane geometry, so they must NOT trigger a
## reproject — a value fold stays a cheap in-place edit.
func _test_param_and_flags_edits_do_not_relayout() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)

	var p_res: Dictionary = session.apply_edit(_ref("param_index"), 2)
	_assert_true(not p_res.get("relayout", false), "a param_index edit does not relayout")

	var f_res: Dictionary = session.apply_edit(_ref("flags"), 3)
	_assert_true(not f_res.get("relayout", false), "a flags edit does not relayout")


## channel_mask left the author's vocabulary (ADR-0086) — it is a lowering artifact,
## born only when the encoder packs coincident sub-channel events, never a control a
## person sets. Editing it is an unknown-field no-op (the orphan gesture is gone).
func _test_channel_mask_is_not_an_authorable_field() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)
	var kf = data.camera.get_table("phase1").get_keyframe(0)

	var res: Dictionary = session.apply_edit(_ref("channel_mask"), 6)

	_assert_true(res.is_empty(), "channel_mask is not a routable camera field (no-op)")
	_assert_eq(kf.command_raw, 0x0841, "the command word is untouched")
	_assert_eq(kf.channel_mask, 1, "the derived mask is unchanged")


## param_index = bits 3-4 (param<<3); flags = bits 13-15 (flags<<13).
func _test_edit_param_index_and_flags() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)

	session.apply_edit(_ref("param_index"), 3)   # 3<<3 = 0x18
	var kf = data.camera.get_table("phase1").get_keyframe(0)
	_assert_eq(kf.command_raw, 0x0859, "param bits set (0x0841 | 0x18 = 0x0859)")
	_assert_eq(kf.param_index, 3, "decoded param_index recomputed")

	session.apply_edit(_ref("flags"), 5)         # 5<<13 = 0xA000
	_assert_eq(kf.command_raw, 0xA859, "flags bits set (0x0859 | 0xA000 = 0xA859)")
	_assert_eq(kf.flags, 5, "decoded flags recomputed")


func _test_apply_edit_reports_before_and_after_raw() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_ref("angle_x"), 250)
	_assert_eq(res.get("before_raw"), 100, "reports the pre-edit angle_x")
	_assert_eq(res.get("after_raw"), 250, "reports the post-edit angle_x")

	# The command word reports its OWN field's before/after (the bitfield value),
	# so undo replays it back through the same fold.
	var res2: Dictionary = session.apply_edit(_ref("source_mode"), 0x140)
	_assert_eq(res2.get("before_raw"), 0x040, "source edit reports the pre-edit source bits")
	_assert_eq(res2.get("after_raw"), 0x140, "…and the post-edit source bits")


func _test_undo_restores_angle() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)
	var kf = data.camera.get_table("phase1").get_keyframe(0)

	session.apply_edit(_ref("angle_x"), 250)
	_assert_eq(session.undo(), true, "undo reports it unwound a command")
	_assert_eq(kf.angle.x, 100, "angle_x restored to its pre-edit value")


func _test_undo_restores_command_word() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)
	var kf = data.camera.get_table("phase1").get_keyframe(0)

	session.apply_edit(_ref("source_mode"), 0x140)   # → 0x0941
	session.undo()
	_assert_eq(kf.command_raw, 0x0841, "undo folds the previous source bits back in")
	_assert_eq(kf.source_mode, "DIRECT", "the decoded cache is restored too")


func _test_out_of_range_s16_is_flagged_but_applied() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)
	var kf = data.camera.get_table("phase1").get_keyframe(0)

	var res: Dictionary = session.apply_edit(_ref("angle_x"), 40000)   # > s16 max
	var verdict: Dictionary = res.get("faithful", {})
	_assert_eq(kf.angle.x, 40000, "Free accepts the write (non-destructive advisory)")
	_assert_eq(verdict.get("ok", true), false, "an out-of-s16 value is flagged un-Faithful")


func _test_unknown_camera_field_is_a_noop() -> void:
	var data = _effect_with_camera_kf()
	var session = EffectEditSession.new(data)
	var res: Dictionary = session.apply_edit(_ref("bogus"), 1)
	_assert_true(res.is_empty(), "an unknown camera field returns an empty result (no crash)")


# --- fixtures --------------------------------------------------------------

## The camera authoring address (ADR-0086 dec. 5, #286): a sub-channel + the ordinal
## of the event within that lane, NOT a raw keyframe index. The main fixture is angle-only
## (mask 1), so its single event is (angle, ordinal 0).
func _ref(field: String) -> Dictionary:
	return _ch_ref("angle", field, 0)


func _ch_ref(camera_channel: String, field: String, ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "phase1",
		"camera_channel": camera_channel, "ordinal": ordinal, "field": field}


func _effect_with_camera_kf():
	var data = EffectData.new()
	data.camera = CameraData.from_json({
		"phase1": {
			"max_keyframe": 1,
			"keyframes": [{
				"index": 0, "end_frame": 8,
				"angle": [100, 200, 300],
				"position": [10, 20, 30],
				"zoom": [4096, 0, 0],
				"command_raw": 0x0841,
				"channel_mask": 1, "source_mode": "DIRECT",
				"interpolation": "LINEAR", "param_index": 0, "flags": 0,
			}],
		},
	})
	return data


## A coalesced keyframe carrying all three sub-channels (mask 7) — angle, position AND
## zoom events all sit at ordinal 0, so each lane's value edit resolves to this one kf.
func _effect_with_coalesced_kf():
	var data = EffectData.new()
	data.camera = CameraData.from_json({
		"phase1": {
			"max_keyframe": 0,
			"keyframes": [{
				"index": 0, "end_frame": 8,
				"angle": [100, 200, 300],
				"position": [10, 20, 30],
				"zoom": [4096, 0, 0],
				"command_raw": 0x0847,
				"channel_mask": 7, "source_mode": "DIRECT",
				"interpolation": "LINEAR", "param_index": 0, "flags": 0,
			}],
		},
	})
	return data


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
