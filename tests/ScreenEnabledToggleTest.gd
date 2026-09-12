extends Node
## TDD guard for the SCREEN Enabled toggle (ADR-0087 dec. 11) — screen has NO enable bit
## (ctrl bit-7 is the Kind), so on disk "disabled" and "identity no-op Blend" (mode 0, zero
## param — the insert-seed convention) are the SAME bytes. The harmonized toggle is therefore a
## BYTE-SWAP with a session stash:
##   * Disable = overwrite the keyframe to the identity no-op, stashing the prior bytes in an
##     authoring-only sidecar ON the keyframe object (the ADR-0085 anchor_offset pattern — the
##     stash rides the object through insert/delete renumbers and dies with a fresh parse).
##     A Gradient disables to a Blend no-op (a disabled keyframe always presents Blend).
##   * Re-enable = restore the stash losslessly and clear it.
##   * A COLD no-op (no stash — e.g. after save/reload) shows Disabled with nothing to
##     restore: enabling it changes NO bytes and records NO undo entry — "author a tint",
##     never a fabricated byte restore.
##   * Disabled is DERIVED (identity-no-op bytes OR stash present): the live raw bytes always
##     equal what plays and what saves — no preview/disk divergence.
## The toggle never touches time_value/duration (the tile stays; a disabled tween holds its
## span). Undo replays the same `enabled` field scalar-style: the stash makes it self-inverse.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ScreenEnabledToggleTest.tscn

const Session = preload("res://src/effects/studio/EffectEditSession.gd")
const Chan = preload("res://src/effects/studio/ScreenChannel.gd")
const ScreenDataClass = ExMateriaEffects.ScreenData
const Lowering = preload("res://src/effects/studio/ColorLowering.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_disable_blend_swaps_to_identity_and_stashes()
	_test_reenable_restores_losslessly()
	_test_gradient_disables_to_blend_noop_and_restores()
	_test_cold_noop_enable_never_fabricates()
	_test_disable_then_undo_restores_through_the_stash()
	_test_structural_snapshot_carries_the_stash()
	_test_blend_mode_edit_preserves_the_kind_bit()

	print("\n=== ScreenEnabledToggleTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ScreenEnabledToggleTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScreenEnabledToggleTest")
		get_tree().quit(0)


## Disabling a Blend overwrites it to the identity no-op (mode 0, zero param, ctrl 0x80) and
## stashes the prior bytes; the span keeps its length. Structural (the field set restyles) but
## read-live (screen refolds in place).
func _test_disable_blend_swaps_to_identity_and_stashes() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = _kf(data, 0)

	_assert_true(not Chan.is_disabled(kf), "the fixture Blend derives ENABLED before the toggle")
	var res: Dictionary = session.apply_edit(_enabled_ref(0), 0)
	_assert_eq(int(kf.mode), ScreenDataClass.ScreenMode.BLEND, "disabled presents the Blend variant")
	_assert_eq(int(kf.blend_mode), 0, "…identity mode 0")
	_assert_eq(int(kf.ctrl), 0x80, "…ctrl carries only the Blend kind bit")
	_assert_eq([int(kf.start_r_raw), int(kf.start_g_raw), int(kf.start_b_raw)], [0, 0, 0],
		"…zero param (the insert-seed convention)")
	_assert_eq(int(kf.time_value), 2, "the byte-swap never touches the tween's length")
	_assert_true(Chan.is_disabled(kf), "the keyframe now derives DISABLED")
	_assert_eq(res.get("invalidates_sim", true), false, "screen is read-live — no re-seek")
	_assert_eq(res.get("structural", false), true, "the swap restyles the field set (re-render)")


## Re-enabling restores the stashed bytes losslessly and clears the stash.
func _test_reenable_restores_losslessly() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = _kf(data, 0)

	session.apply_edit(_enabled_ref(0), 0)
	session.apply_edit(_enabled_ref(0), 1)
	_assert_eq(int(kf.ctrl), 0x85, "re-enable restores ctrl")
	_assert_eq(int(kf.blend_mode), 5, "…the blend mode")
	_assert_eq([int(kf.start_r_raw), int(kf.start_g_raw), int(kf.start_b_raw)], [10, 20, 30],
		"…and the param bytes, losslessly")
	_assert_true(not Chan.is_disabled(kf), "…deriving ENABLED again")


## A Gradient disables to a Blend no-op (a disabled keyframe always presents Blend);
## re-enabling restores the stashed GRADIENT — kind included.
func _test_gradient_disables_to_blend_noop_and_restores() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = _kf(data, 1)   # the fixture's Gradient

	session.apply_edit(_enabled_ref(1), 0)
	_assert_eq(int(kf.mode), ScreenDataClass.ScreenMode.BLEND, "a disabled Gradient presents Blend")
	_assert_true(Chan.is_disabled(kf), "…and derives DISABLED")

	session.apply_edit(_enabled_ref(1), 1)
	_assert_eq(int(kf.mode), ScreenDataClass.ScreenMode.GRADIENT, "re-enable restores the Gradient kind")
	_assert_eq([int(kf.end_r_raw), int(kf.end_g_raw), int(kf.end_b_raw)], [40, 50, 60],
		"…with its bottom stop intact")


## A COLD no-op (identity bytes, no stash — the after-save/reload state) has nothing to
## restore: enabling changes NO bytes and records NO undo entry.
func _test_cold_noop_enable_never_fabricates() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = _kf(data, 2)   # the fixture's cold identity no-op

	_assert_true(Chan.is_disabled(kf), "identity bytes derive DISABLED even with no stash")
	session.apply_edit(_enabled_ref(2), 1)
	_assert_eq(int(kf.blend_mode), 0, "a cold enable fabricates nothing (bytes unchanged)")
	_assert_true(Chan.is_disabled(kf), "…still derived DISABLED — author a tint instead")
	_assert_true(not session.undo(), "…and no undo entry was recorded")


## Undo of a disable replays `enabled = 1` through the same path — the stash (still present)
## makes the toggle self-inverse, so the pristine bytes come back.
func _test_disable_then_undo_restores_through_the_stash() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = _kf(data, 0)

	session.apply_edit(_enabled_ref(0), 0)
	_assert_true(session.undo(), "the disable is undoable")
	_assert_eq(int(kf.ctrl), 0x85, "undo restores the pristine ctrl")
	_assert_eq([int(kf.start_r_raw), int(kf.start_g_raw), int(kf.start_b_raw)], [10, 20, 30],
		"…and the pristine param bytes")


## The stash survives the structural verbs: it rides the keyframe OBJECT, so a channel
## snapshot deep-copy carries it — delete + undo hands back a keyframe that still re-enables.
func _test_structural_snapshot_carries_the_stash() -> void:
	var data := _fake_data()
	var session = Session.new(data)

	session.apply_edit(_enabled_ref(0), 0)   # stash kf0
	session.delete_event({"channel": "screen", "context": "for_each", "event_index": 0})
	_assert_true(session.undo(), "the delete is undoable")
	var kf = _kf(data, 0)
	_assert_true(Chan.is_disabled(kf), "the restored keyframe is still disabled")
	session.apply_edit(_enabled_ref(0), 1)
	_assert_eq([int(kf.start_r_raw), int(kf.start_g_raw), int(kf.start_b_raw)], [10, 20, 30],
		"…and still re-enables to the original bytes (the stash rode the snapshot)")


## The screen ctrl byte shares kind (bit-7) and blend mode (low bits) exactly like palette's
## enable/mode split — the editable Blend-mode enum (ADR-0087 dec. 13) is a
## read-modify-write preserving the kind bit, and it undoes scalar-style.
func _test_blend_mode_edit_preserves_the_kind_bit() -> void:
	var data := _fake_data()
	var session = Session.new(data)
	var kf = _kf(data, 0)   # Blend, ctrl 0x85, mode 5

	var ref := {"channel": "screen", "context": "for_each", "event_index": 0, "field": "blend_mode"}
	var res: Dictionary = session.apply_edit(ref, 3)
	_assert_eq(int(kf.blend_mode), 3, "the blend mode is rewritten")
	_assert_eq(int(kf.ctrl), 0x83, "…preserving the kind bit in ctrl (0x80 | 3)")
	_assert_eq(int(kf.mode), ScreenDataClass.ScreenMode.BLEND, "…and the derived kind")
	_assert_eq(res.get("invalidates_sim", true), false, "a mode edit is read-live")

	_assert_true(session.undo(), "the mode edit is undoable")
	_assert_eq(int(kf.blend_mode), 5, "undo restores the mode")
	_assert_eq(int(kf.ctrl), 0x85, "…and ctrl")


# --- fixtures -------------------------------------------------------------

func _enabled_ref(index: int) -> Dictionary:
	return {"channel": "screen", "context": "for_each", "event_index": index, "field": "enabled"}


func _kf(data, index: int):
	return data.screen.get_channel("for_each").get_keyframe(index)


## Three tv-2 keyframes: [0] an active Blend (ctrl 0x85, param 10/20/30), [1] an active
## Gradient (stops 10/20/30 → 40/50/60), [2] a COLD identity no-op (the insert-seed bytes).
func _fake_data() -> RefCounted:
	var kfs: Array = [
		{"index": 0, "time_value": 2, "duration_frames": 16,
			"start_r": 10, "start_g": 20, "start_b": 30, "end_r": 10, "end_g": 20, "end_b": 30,
			"ctrl": 0x85, "mode": "TINT", "blend_mode": 5},
		{"index": 1, "time_value": 2, "duration_frames": 16,
			"start_r": 10, "start_g": 20, "start_b": 30, "end_r": 40, "end_g": 50, "end_b": 60,
			"ctrl": 0x00, "mode": "FADE", "blend_mode": 0},
		{"index": 2, "time_value": 2, "duration_frames": 16,
			"start_r": 0, "start_g": 0, "start_b": 0, "end_r": 0, "end_g": 0, "end_b": 0,
			"ctrl": 0x80, "mode": "TINT", "blend_mode": 0},
	]
	var sd = ScreenDataClass.from_json({
		"for_each": {"context": "for_each", "max_keyframe": 4, "keyframes": kfs},
	})
	var data := _FakeData.new()
	data.screen = sd
	return data


class _FakeData extends RefCounted:
	var screen = null
	var palette = null
	var camera = null


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
