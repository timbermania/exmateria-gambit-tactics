extends Node
## TDD guard for the Effect Studio authoring choke point (#255, pilot slice 1).
##
## `EffectEditSession.apply_edit(field_ref, new_raw)` is the SINGLE mutation entry
## point over the raw-authoritative `EffectData` (#254). It routes by channel to a
## per-channel raw↔value encoder (`ScreenChannel` first) that: writes the raw byte,
## recomputes the derived `value` cache, and declares whether the edit invalidates
## the sim. The screen COLOUR field is read-live (`ScreenSubsystem` rebuilds the
## ColorStack every frame by-reference), so editing it is `invalidates_sim=false` —
## the host mutates in place and repaints at the current frame with ZERO re-seek
## (the reason #253 picked the Screen backdrop as the pilot).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectEditSessionTest.tscn

const EffectData = ExMateriaEffects.EffectData
const ScreenData = ExMateriaEffects.ScreenData
const CameraData = ExMateriaEffects.CameraData
const EffectEditSession = preload("res://src/effects/studio/EffectEditSession.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_editing_start_r_writes_raw_and_recomputes_the_value_cache()
	_test_editing_end_g_writes_raw_and_recomputes_end_color()
	_test_editing_start_r_is_not_sim_invalidating()
	_test_apply_edit_reports_before_and_after_raw()
	_test_undo_restores_the_previous_raw_and_value_cache()
	_test_undo_on_empty_history_is_a_noop()
	_test_undo_unwinds_edits_in_reverse_order()
	_test_in_range_colour_byte_is_faithful()
	_test_out_of_range_colour_byte_is_flagged_but_still_applied()
	_test_editing_kind_to_gradient_clears_ctrl_bit7_and_sets_mode()
	_test_editing_kind_to_blend_sets_ctrl_bit7()
	_test_kind_edit_is_structural_and_read_live()
	_test_undo_restores_the_previous_kind()
	_test_apply_compound_writes_all_member_edits()
	_test_undo_of_a_compound_is_one_step()
	_test_coalesced_same_field_edits_are_one_undo_to_baseline()
	_test_edits_outside_a_coalesce_stay_separate()
	_test_effect_flags_edit_routes_to_the_flags_channel()
	_test_undo_of_a_flags_edit_restores_the_raw_byte()
	_test_time_scale_edit_routes_to_the_time_scale_channel()
	_test_undo_of_a_time_scale_edit_restores_the_curve()

	print("\n=== EffectEditSessionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectEditSessionTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectEditSessionTest")
		get_tree().quit(0)


## Editing one raw colour component through the choke point writes the raw byte on
## the live keyframe AND keeps the derived `start_color` cache in sync (raw/255 per
## the PSX unsigned-byte → normalized-colour encoding). Expected 0.7843 = 200/255,
## a spec literal, NOT recomputed the way the code does.
func _test_editing_start_r_writes_raw_and_recomputes_the_value_cache() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)

	session.apply_edit(_start_r_ref(), 200)

	var kf = data.screen.get_channel("for_each").get_keyframe(0)
	_assert_eq(kf.start_r_raw, 200, "the raw byte is written on the live keyframe")
	_assert_true(abs(kf.start_color.r - 0.7843) < 0.001,
		"the derived start_color cache is recomputed to 200/255")
	_assert_true(abs(kf.start_color.g - 20 / 255.0) < 0.001,
		"the untouched green component is preserved")


## Editing a BOTTOM-stop component (the Gradient `end_r/g/b`) through the choke point writes
## its raw byte on the live keyframe AND keeps the derived `end_color` cache in sync (raw/255),
## while leaving the TOP stop's `start_color` untouched — the two Gradient stops are independent
## (#255 scope B, the two-picker editor). Fixture end=(40,50,60); edit end_g → 200.
func _test_editing_end_g_writes_raw_and_recomputes_end_color() -> void:
	var data = _effect_with_gradient_kf()
	var session = EffectEditSession.new(data)
	session.apply_edit(_end_g_ref(), 200)

	var kf = data.screen.get_channel("for_each").get_keyframe(0)
	_assert_eq(kf.end_g_raw, 200, "the raw byte is written on the bottom stop")
	_assert_true(abs(kf.end_color.g - 200 / 255.0) < 0.001,
		"the derived end_color cache is recomputed to 200/255")
	_assert_true(abs(kf.end_color.r - 40 / 255.0) < 0.001,
		"the bottom stop's other components are preserved (end_color.r = 40/255)")
	_assert_true(abs(kf.start_color.g - 20 / 255.0) < 0.001,
		"a bottom-stop edit leaves the TOP stop's start_color untouched (independent stops)")


## The screen colour field is read-live, so its edit must NOT ask for a re-seek —
## this is the property that makes the pilot the cleanest case (#255).
func _test_editing_start_r_is_not_sim_invalidating() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_start_r_ref(), 200)

	_assert_eq(res.get("invalidates_sim", true), false,
		"screen colour edits repaint in place, never re-seek")


## The choke point reports the pre- and post-edit raw so the snapshot-command undo
## stack (slice 2) can be recorded from the same return value.
func _test_apply_edit_reports_before_and_after_raw() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_start_r_ref(), 200)

	_assert_eq(res.get("before_raw"), 10, "reports the pre-edit raw byte")
	_assert_eq(res.get("after_raw"), 200, "reports the post-edit raw byte")


## Undo pops the last command and replays the pre-edit raw through the same
## dispatch path, restoring BOTH the raw byte and the derived value cache.
func _test_undo_restores_the_previous_raw_and_value_cache() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)
	var kf = data.screen.get_channel("for_each").get_keyframe(0)

	session.apply_edit(_start_r_ref(), 200)
	var undone: bool = session.undo()

	_assert_eq(undone, true, "undo reports it unwound a command")
	_assert_eq(kf.start_r_raw, 10, "the raw byte is restored to its pre-edit value")
	_assert_true(abs(kf.start_color.r - 10 / 255.0) < 0.001,
		"the derived colour cache is restored too")


## Undo with nothing to unwind is a harmless no-op, not an error.
func _test_undo_on_empty_history_is_a_noop() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)

	_assert_eq(session.undo(), false, "undo on empty history returns false")


## The snapshot stack is LIFO — two edits unwind newest-first, each back to the
## value it held at the moment that edit was applied.
func _test_undo_unwinds_edits_in_reverse_order() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)
	var kf = data.screen.get_channel("for_each").get_keyframe(0)

	session.apply_edit(_start_r_ref(), 200)   # 10 → 200
	session.apply_edit(_start_r_ref(), 77)    # 200 → 77

	session.undo()                            # → 200
	_assert_eq(kf.start_r_raw, 200, "first undo returns to the intermediate value")
	session.undo()                            # → 10
	_assert_eq(kf.start_r_raw, 10, "second undo returns to the original value")


## A raw colour byte in [0, 255] fits the screen section's byte encoding, so the
## edit is Faithful (patchable back into E###.BIN).
func _test_in_range_colour_byte_is_faithful() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_start_r_ref(), 200)
	var verdict: Dictionary = res.get("faithful", {})

	_assert_eq(verdict.get("ok", false), true, "an in-range colour byte is Faithful")


## Free is the default and always ACCEPTS the write (native resource holds it), but
## a raw byte outside [0, 255] can't be lowered to E###.BIN — so the verdict flags
## it NON-destructively: the edit still applied, only the advisory says un-Faithful.
func _test_out_of_range_colour_byte_is_flagged_but_still_applied() -> void:
	var data = _effect_with_screen_kf()
	var session = EffectEditSession.new(data)
	var kf = data.screen.get_channel("for_each").get_keyframe(0)

	var res: Dictionary = session.apply_edit(_start_r_ref(), 300)
	var verdict: Dictionary = res.get("faithful", {})

	_assert_eq(kf.start_r_raw, 300, "Free accepts the write (non-destructive advisory)")
	_assert_eq(verdict.get("ok", true), false, "an out-of-range byte is flagged un-Faithful")
	_assert_true(String(verdict.get("reason", "")).length() > 0,
		"the advisory carries a human reason")


# --- Kind (Blend/Gradient) selector — the ctrl bit-7 variant ---------------

## Flipping a screen tween's KIND to Gradient clears ctrl bit-7 (a read-modify-write
## that preserves the low bits) and sets the derived mode. Start ctrl 133 (0x85 = bit-7
## set, low bits 0x05) → Gradient → 0x05 = 5. Expected literals are hand-computed.
func _test_editing_kind_to_gradient_clears_ctrl_bit7_and_sets_mode() -> void:
	var data = _effect_with_screen_kf()   # ctrl 133 (BLEND)
	var session = EffectEditSession.new(data)
	var kf = data.screen.get_channel("for_each").get_keyframe(0)

	session.apply_edit(_kind_ref(), ScreenData.ScreenMode.GRADIENT)

	_assert_eq(kf.ctrl, 5, "ctrl bit-7 is cleared, low bits preserved (0x85 → 0x05)")
	_assert_eq(kf.mode, ScreenData.ScreenMode.GRADIENT, "the derived mode is now Gradient")


## Flipping to Blend sets ctrl bit-7 over the preserved low bits (0x05 → 0x85 = 133).
func _test_editing_kind_to_blend_sets_ctrl_bit7() -> void:
	var data = _effect_with_gradient_kf()   # ctrl 5 (GRADIENT)
	var session = EffectEditSession.new(data)
	var kf = data.screen.get_channel("for_each").get_keyframe(0)

	session.apply_edit(_kind_ref(), ScreenData.ScreenMode.BLEND)

	_assert_eq(kf.ctrl, 133, "ctrl bit-7 is set, low bits preserved (0x05 → 0x85)")
	_assert_eq(kf.mode, ScreenData.ScreenMode.BLEND, "the derived mode is now Blend")


## A kind change is read-live (no re-seek) but STRUCTURAL — the field set reshapes, so
## the caller must re-project (unlike a value edit). before/after report the kind.
func _test_kind_edit_is_structural_and_read_live() -> void:
	var data = _effect_with_screen_kf()   # BLEND
	var session = EffectEditSession.new(data)

	var res: Dictionary = session.apply_edit(_kind_ref(), ScreenData.ScreenMode.GRADIENT)

	_assert_eq(res.get("invalidates_sim", true), false, "kind edits repaint in place (read-live)")
	_assert_eq(res.get("structural", false), true, "a kind edit is flagged structural (fields reshape)")
	_assert_eq(res.get("before_raw"), ScreenData.ScreenMode.BLEND, "reports the pre-edit kind")
	_assert_eq(res.get("after_raw"), ScreenData.ScreenMode.GRADIENT, "reports the post-edit kind")


## Undo of a kind flip replays the previous kind through the same path, restoring ctrl+mode.
func _test_undo_restores_the_previous_kind() -> void:
	var data = _effect_with_screen_kf()   # ctrl 133 (BLEND)
	var session = EffectEditSession.new(data)
	var kf = data.screen.get_channel("for_each").get_keyframe(0)

	session.apply_edit(_kind_ref(), ScreenData.ScreenMode.GRADIENT)   # → 5 / Gradient
	session.undo()

	_assert_eq(kf.ctrl, 133, "undo restores the original ctrl byte")
	_assert_eq(kf.mode, ScreenData.ScreenMode.BLEND, "undo restores the original mode")


# --- Compound edit (one gesture, one undo) — the fire-drag two-gap write --

## A single author gesture can touch MORE than one field (fire-drag trades the two
## neighbouring sound gaps). apply_compound applies every member edit through the same
## per-channel path apply_edit uses, so both live keyframes are written. Fixture is a
## sound channel with gaps [4,10,6]; the compound is the stay-local move of trigger 1
## by +3 → gaps become [7,7,6].
func _test_apply_compound_writes_all_member_edits() -> void:
	var data = _effect_with_sound_channel([4, 10, 6])
	var session = EffectEditSession.new(data)

	session.apply_compound([
		{"field_ref": _sound_dur_ref(0), "new_raw": 7},
		{"field_ref": _sound_dur_ref(1), "new_raw": 7},
	])

	var kfs = data.sound["for_each"][0]["keyframes"]
	_assert_eq(int(kfs[0]["duration_frames"]), 7, "the first member edit is written on the live kf")
	_assert_eq(int(kfs[1]["duration_frames"]), 7, "the second member edit is written on the live kf")


## The whole point of the compound: one gesture is ONE undo. A single undo() restores
## BOTH gaps, and there is no second entry left behind (a second undo finds nothing).
func _test_undo_of_a_compound_is_one_step() -> void:
	var data = _effect_with_sound_channel([4, 10, 6])
	var session = EffectEditSession.new(data)
	session.apply_compound([
		{"field_ref": _sound_dur_ref(0), "new_raw": 7},
		{"field_ref": _sound_dur_ref(1), "new_raw": 7},
	])

	var undone: bool = session.undo()

	var kfs = data.sound["for_each"][0]["keyframes"]
	_assert_eq(undone, true, "undo reports it unwound the compound")
	_assert_eq(int(kfs[0]["duration_frames"]), 4, "one undo restores the first gap")
	_assert_eq(int(kfs[1]["duration_frames"]), 10, "one undo restores the second gap")
	_assert_eq(session.undo(), false, "a compound is ONE undo entry, not one-per-member")


## ADR-0086 boundary-drag: one drag gesture is ONE undo. During a begin_coalesce/
## end_coalesce bracket, repeated apply_edits to the SAME field replace the single undo
## entry's after_raw (keeping the pristine before_raw) instead of stacking — so a single
## undo() restores the PRE-DRAG baseline, not the last intermediate frame. Camera-only
## mechanism, exercised here on a camera end_frame edit (the real caller).
func _test_coalesced_same_field_edits_are_one_undo_to_baseline() -> void:
	var data = _effect_with_angle_lane()   # angle ends 10 / 14 / 20
	var session = EffectEditSession.new(data)
	_assert_true(session.has_method("begin_coalesce") and session.has_method("end_coalesce"),
		"the session exposes begin_coalesce / end_coalesce")
	if not (session.has_method("begin_coalesce") and session.has_method("end_coalesce")):
		return   # clean red: the coalesce capability isn't built yet
	var ref := _cam_end_ref("angle", 1)   # ordinal 1 — baseline end_frame 14

	session.begin_coalesce(ref)
	session.apply_edit(ref, 15)
	session.apply_edit(ref, 16)
	session.apply_edit(ref, 17)
	session.end_coalesce()

	var kf = data.camera.get_table("for_each").get_keyframe(1)
	_assert_eq(int(kf.end_frame), 17, "the final drag value is applied")
	_assert_eq(session.undo(), true, "one undo unwinds the whole gesture")
	_assert_eq(int(kf.end_frame), 14, "a single undo restores the PRE-DRAG baseline (not 16)")
	_assert_eq(session.undo(), false, "the coalesced gesture left exactly ONE undo entry")


## Coalescing is OPT-IN: edits made WITHOUT a begin_coalesce bracket keep the normal
## one-entry-per-edit undo (regression guard — the drag mechanism must not change typed edits).
func _test_edits_outside_a_coalesce_stay_separate() -> void:
	var data = _effect_with_angle_lane()
	var session = EffectEditSession.new(data)
	if not session.has_method("begin_coalesce"):
		return
	var ref := _cam_end_ref("angle", 1)   # baseline 14

	session.apply_edit(ref, 15)
	session.apply_edit(ref, 16)

	var kf = data.camera.get_table("for_each").get_keyframe(1)
	_assert_eq(int(kf.end_frame), 16, "both un-bracketed edits applied")
	session.undo()
	_assert_eq(int(kf.end_frame), 15, "first undo reverts only the last edit (separate entries)")
	session.undo()
	_assert_eq(int(kf.end_frame), 14, "second undo reverts the earlier edit")


## The GLOBAL Effect Flags byte (#272) routes through the SAME choke point: an effect_flags
## edit dispatches to EffectFlagsChannel, which writes data.flags.flags_byte, mirrors bits 5/6
## into the time-scale block, and re-folds the sim (invalidates_sim). This guards the _dispatch
## case wiring — the projector's bitflags row hands the whole recomputed word here.
func _test_effect_flags_edit_routes_to_the_flags_channel() -> void:
	var data = _effect_with_flags(0x23)  # bit5 (time_scale 3-phase) on
	var session = EffectEditSession.new(data)
	# Clear bit5 → the bitflags editor hands the recomputed word 0x03.
	var res: Dictionary = session.apply_edit(_flags_ref(), 0x03)
	_assert_eq(int(data.flags["flags_byte"]), 0x03, "the flags byte is written through the choke point")
	_assert_true(not bool(data.time_scale["flags"]["time_scale_pattern1"]),
		"clearing bit5 mirrors into the time-scale block")
	_assert_true(bool(res.get("invalidates_sim", false)), "a flags edit re-folds the sim")


func _test_undo_of_a_flags_edit_restores_the_raw_byte() -> void:
	var data = _effect_with_flags(0x23)
	var session = EffectEditSession.new(data)
	session.apply_edit(_flags_ref(), 0x03)
	session.undo()
	_assert_eq(int(data.flags["flags_byte"]), 0x23, "undo restores the pre-edit flags byte (scalar replay)")
	_assert_true(bool(data.time_scale["flags"]["time_scale_pattern1"]),
		"undo re-arms the time-scale enable via the same dispatch path")


func _flags_ref() -> Dictionary:
	return {"channel": "effect_flags", "field": "flags_byte"}


## The two PACING curves (#270) route through the SAME choke point: a time_scale edit dispatches
## to TimeScaleChannel, which writes the whole 600-int curve onto data.time_scale[<field>] and
## re-folds the sim (invalidates_sim — pacing feeds tl.setup → EffectEndModel). This guards the
## _dispatch case wiring; the painter commits the full curve here on mouse-up.
func _test_time_scale_edit_routes_to_the_time_scale_channel() -> void:
	var data = _effect_with_time_scale()
	var session = EffectEditSession.new(data)
	var painted: Array = []
	for i in range(600):
		painted.append(3 + (i % 7))
	var res: Dictionary = session.apply_edit(_ts_ref("outer_phases"), painted)
	_assert_eq(data.time_scale["outer_phases"], painted,
		"the whole pacing curve is written through the choke point")
	_assert_true(bool(res.get("invalidates_sim", false)), "a pacing edit re-folds the sim")


func _test_undo_of_a_time_scale_edit_restores_the_curve() -> void:
	var data = _effect_with_time_scale()
	var session = EffectEditSession.new(data)
	var original: Array = data.time_scale["outer_phases"].duplicate()
	var painted: Array = []
	for i in range(600):
		painted.append(9)
	session.apply_edit(_ts_ref("outer_phases"), painted)
	session.undo()
	_assert_eq(data.time_scale["outer_phases"], original,
		"undo restores the pre-edit pacing curve (scalar array replay)")


func _ts_ref(field: String) -> Dictionary:
	return {"channel": "time_scale", "field": field}


## A time-scale fixture: two 600-int curves in the real 2..10 range.
func _effect_with_time_scale():
	var data = EffectData.new()
	var outer: Array = []
	var foreach: Array = []
	for i in range(600):
		outer.append(2 + (i % 9))
		foreach.append(2 + ((i + 4) % 9))
	data.time_scale = {
		"flags": {"time_scale_pattern1": true, "time_scale_pattern2": false},
		"outer_phases": outer, "for_each": foreach,
	}
	return data


## E019-shaped flags fixture with a live time_scale block whose flags mirror bits 5/6.
func _effect_with_flags(flags_byte: int):
	var data = EffectData.new()
	data.flags = {
		"flags_byte": flags_byte,
		"terrain_height_adjust": (flags_byte & 0x08) != 0,
		"audio_fade": (flags_byte & 0x10) != 0,
		"time_scale_pattern1": (flags_byte & 0x20) != 0,
		"time_scale_pattern2": (flags_byte & 0x40) != 0,
	}
	data.time_scale = {"flags": {
		"time_scale_pattern1": (flags_byte & 0x20) != 0,
		"time_scale_pattern2": (flags_byte & 0x40) != 0,
	}, "outer_phases": [], "for_each": []}
	return data


# --- fixtures (camera boundary-drag coalesce) ----------------------------

## for_each with three solo-angle keyframes (mask=1) at ends 10 / 14 / 20 — a fully-tiled
## angle lane whose ordinals line up 1:1 with the keyframe slots.
func _effect_with_angle_lane():
	var data = EffectData.new()
	data.camera = CameraData.from_json({"for_each": {"max_keyframe": 2, "keyframes": [
		{"index": 0, "end_frame": 10,
			"angle": [0, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 1, "end_frame": 14,
			"angle": [40, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
		{"index": 2, "end_frame": 20,
			"angle": [100, 0, 0], "position": [0, 0, 0], "zoom": [0, 0, 0],
			"command_raw": 0x0841, "channel_mask": 1,
			"source_mode": "DIRECT", "interpolation": "LINEAR", "param_index": 0, "flags": 0},
	]}})
	return data


func _cam_end_ref(camera_channel: String, ordinal: int) -> Dictionary:
	return {"channel": "camera", "context": "for_each",
		"camera_channel": camera_channel, "ordinal": ordinal, "field": "end_frame"}


# --- fixtures -------------------------------------------------------------

func _start_r_ref() -> Dictionary:
	return {"channel": "screen", "context": "for_each", "event_index": 0, "field": "start_r"}


func _end_g_ref() -> Dictionary:
	return {"channel": "screen", "context": "for_each", "event_index": 0, "field": "end_g"}


func _kind_ref() -> Dictionary:
	return {"channel": "screen", "context": "for_each", "event_index": 0, "field": "kind"}


## A sound-channel duration_frames address (the three-dim sound key: phase +
## channel_index + event_index). SoundChannel writes the live raw dict in place.
func _sound_dur_ref(event_index: int) -> Dictionary:
	return {"channel": "sound", "phase": "for_each", "channel_index": 0,
		"event_index": event_index, "field": "duration_frames"}


## A raw sound EffectData whose one for_each channel has the given gap sequence
## (duration_frames). `data.sound` is the raw parsed dict SoundChannel edits directly.
func _effect_with_sound_channel(durations: Array):
	var data = EffectData.new()
	var kfs: Array = []
	for d in durations:
		kfs.append({"duration_frames": int(d), "sound_id": 5})
	data.sound = {
		"for_each": [
			{"channel_index": 0, "max_keyframe": durations.size(), "keyframes": kfs},
		],
	}
	return data


func _effect_with_gradient_kf():
	var data = EffectData.new()
	data.screen = ScreenData.from_json({
		"for_each": {
			"context": "for_each", "max_keyframe": 3,
			"keyframes": [{
				"index": 0, "time_value": 1, "duration_frames": 8,
				"start_r": 10, "start_g": 20, "start_b": 30,
				"end_r": 40, "end_g": 50, "end_b": 60,
				"mode": "FADE", "blend_mode": 0, "ctrl": 5,
			}],
		},
	})
	return data


func _effect_with_screen_kf():
	var data = EffectData.new()
	data.screen = ScreenData.from_json({
		"for_each": {
			"context": "for_each",
			"max_keyframe": 3,
			"keyframes": [
				{
					"index": 0, "time_value": 1, "duration_frames": 8,
					"start_r": 10, "start_g": 20, "start_b": 30,
					"end_r": 40, "end_g": 50, "end_b": 60,
					"mode": "TINT", "blend_mode": 5, "ctrl": 133,
				},
			],
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
