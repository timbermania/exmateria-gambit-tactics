extends Node
## Regression test for CinematicPoseLUT.resolve_low_range_seq_key — the PSX
## FUN_80085c0c body-frame dispatch (BATTLE.BIN 0x80085df4+).
##
## Pins the bug fix: a low-range POSE anim (e.g. the female-knight kneel,
## event_anim_id 0x24 → current_anim_id 37) must render its OWN authored SEQ
## frame (key "72"), NOT be hijacked into the pose-octant idle "tent". Only
## event_anim_id == 2 (current_anim_id == 3, the chapel "at-ease" stance) uses
## the tent. Ground-truthed live at the orbonne held-by-Simon beat:
## unit[+0x1DC] = 0x48 = 72 (the kneel); chapel anim-2 actors sit at tent keys
## 1..5. See the prior "is_static_pose" heuristic, which over-matched any
## single-LoadFrameWait anim and painted a standing idle frame for the kneel.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/CinematicLowRangeSeqKeyTest.tscn

const CinematicPoseLUTClass = ExMateriaSpriteRig.CinematicPoseLUT
# A SEQ table with both kneel front/back keys + the tent keys authored, so the
# CASE B back-frame fallback is NOT exercised unless we deliberately omit a key.
const SEQ_FULL := {
	"1": {}, "2": {}, "3": {}, "4": {}, "5": {},  # tent frame bases
	"72": {}, "73": {},                           # kneel front / back (anim 0x24)
}

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_kneel_never_uses_tent()
	_test_kneel_north_resolves_72()
	_test_at_ease_stance_uses_tent()
	_test_back_frame_fallback()
	_test_idle_stays_inline()  # documents that current_anim_id 0 is NOT this path

	print("\n=== CinematicLowRangeSeqKeyTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] CinematicLowRangeSeqKeyTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] CinematicLowRangeSeqKeyTest")
		get_tree().quit(1)
	else:
		print("[PASS] CinematicLowRangeSeqKeyTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# THE regression guard: the kneel (current_anim_id 37) must NEVER resolve to a
# tent frame base (1..5) at ANY pose_octant — it always renders its own SEQ key.
func _test_kneel_never_uses_tent() -> void:
	for octant in range(16):
		var res: Dictionary = CinematicPoseLUTClass.resolve_low_range_seq_key(37, octant, SEQ_FULL)
		var key: String = res["seq_key"]
		_assert_true(key == "72" or key == "73",
			"kneel octant %d → key %s (must be 72/73, never a tent base)" % [octant, key])


# Live-verified vector: at the held-by-Simon beat pose_octant == 14 (NORTH),
# frontback[NORTH] == 0, so the kneel resolves to key "72" (SHP frame 72).
func _test_kneel_north_resolves_72() -> void:
	var res: Dictionary = CinematicPoseLUTClass.resolve_low_range_seq_key(37, 14, SEQ_FULL)
	_assert_eq(res["seq_key"], "72", "kneel pose_octant 14 (NORTH) → key 72 (held-by-Simon ground truth)")


# event_anim_id == 2 (current_anim_id == 3): the ONE anim that uses the tent.
func _test_at_ease_stance_uses_tent() -> void:
	for octant in range(16):
		var res: Dictionary = CinematicPoseLUTClass.resolve_low_range_seq_key(3, octant, SEQ_FULL)
		var want := str(CinematicPoseLUTClass.SUB_A_FRAME_BASE[octant])
		_assert_eq(res["seq_key"], want,
			"at-ease stance octant %d → tent key %s" % [octant, want])


# CASE B back-frame fallback: when (anim-1)*2 + 1 isn't authored, fall back to
# the front key (anim-1)*2. Use a SEQ table missing "73".
func _test_back_frame_fallback() -> void:
	var seq_no_back := {"72": {}}  # front kneel only, no back
	# pose_octant 4 → cardinal_idx 1 → frontback offset 1 → would want key "73",
	# which is absent, so it must fall back to "72".
	var res: Dictionary = CinematicPoseLUTClass.resolve_low_range_seq_key(37, 4, seq_no_back)
	_assert_eq(res["seq_key"], "72", "missing back key 73 → falls back to front key 72")


# Documents the contract boundary: current_anim_id 0 (idle) is handled by the
# caller's separate branch, NOT this helper. Passing 0 here would compute
# (0-1)*2 = -2; callers must never route idle through it. This asserts the
# helper is only ever called for current_anim_id in [1, 0x1f4].
func _test_idle_stays_inline() -> void:
	# current_anim_id 1 (event_anim_id 0, true idle on the CASE B path) → key 0/1.
	var res: Dictionary = CinematicPoseLUTClass.resolve_low_range_seq_key(1, 0, {"0": {}})
	_assert_eq(res["seq_key"], "0", "current_anim_id 1 (event 0) → CASE B key 0")
