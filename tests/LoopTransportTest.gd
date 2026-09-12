extends Node
## TDD guard for LoopTransport — the pure bounce-transport state machine behind the
## Effect Studio's region loop (ADR-0090). Signature `(start, end, mode, dir, cur) -> next`,
## the seam where the turnaround off-by-one lives. Golden frame sequences below are
## hand-computed (independent source of truth), NOT recomputed the way the code does.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/LoopTransportTest.tscn

const Transport = preload("res://src/effects/studio/LoopTransport.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_forward_mid_region_advances_one()
	_test_forward_wraps_end_to_start_showing_end_once()
	_test_pingpong_full_cycle_reflects_without_repeat()
	_test_pingpong_reflects_at_start_without_repeat()
	_test_off_advances_forward_and_reports_done_at_end()
	_test_off_does_not_wrap()
	_test_min_length_two_region_pingpongs()
	_test_degenerate_single_frame_is_inert()

	print("\n=== LoopTransportTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] LoopTransportTest")
		get_tree().quit(1)
	else:
		print("[PASS] LoopTransportTest")
		get_tree().quit(0)


# --- Forward mode --------------------------------------------------------

func _test_forward_mid_region_advances_one() -> void:
	var s = Transport.step(2, 5, Transport.MODE_FORWARD, Transport.DIR_FWD, 3)
	_assert_eq(s["frame"], 4, "forward mid-region: 3 -> 4")
	_assert_eq(s["dir"], Transport.DIR_FWD, "forward stays forward")
	_assert_eq(s["done"], false, "forward mid-region not done")


func _test_forward_wraps_end_to_start_showing_end_once() -> void:
	# Region [2,5]. Starting at start, one pass then wrap. End (5) shown exactly once
	# before wrapping to start (2); start NOT skipped, end NOT repeated.
	var got := _enumerate(2, 5, Transport.MODE_FORWARD, 2, 7)
	_assert_seq(got, [3, 4, 5, 2, 3, 4, 5], "forward wrap: end shown once, then start")


# --- Ping-pong mode ------------------------------------------------------

func _test_pingpong_full_cycle_reflects_without_repeat() -> void:
	# Region [0,3], start forward at 0. Reflect at each endpoint WITHOUT repeating it:
	# 0,1,2,3,2,1,0,1,2,3,... (3 and 0 each appear once per pass).
	var got := _enumerate(0, 3, Transport.MODE_PINGPONG, 0, 12)
	_assert_seq(got, [1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0],
		"ping-pong: reflect at both ends, endpoints once per pass")


func _test_pingpong_reflects_at_start_without_repeat() -> void:
	# Direction backward, sitting on start: reflect forward to start+1 (not repeat start).
	var s = Transport.step(0, 3, Transport.MODE_PINGPONG, Transport.DIR_BACK, 0)
	_assert_eq(s["frame"], 1, "ping-pong at start (going back): reflect to start+1")
	_assert_eq(s["dir"], Transport.DIR_FWD, "reflect flips direction to forward")


# --- Off mode ------------------------------------------------------------

func _test_off_advances_forward_and_reports_done_at_end() -> void:
	var a = Transport.step(0, 3, Transport.MODE_OFF, Transport.DIR_FWD, 2)
	_assert_eq(a["frame"], 3, "off: 2 -> 3")
	_assert_eq(a["done"], false, "off: not done until AT end")
	var b = Transport.step(0, 3, Transport.MODE_OFF, Transport.DIR_FWD, 3)
	_assert_eq(b["done"], true, "off: done when at end")


func _test_off_does_not_wrap() -> void:
	# Off holds at end (done), never wraps back to start.
	var s = Transport.step(0, 3, Transport.MODE_OFF, Transport.DIR_FWD, 3)
	_assert_eq(s["frame"], 3, "off: parks at end, no wrap to start")


# --- Robustness ----------------------------------------------------------

func _test_min_length_two_region_pingpongs() -> void:
	# Smallest legal region [4,5]: ping-pong just alternates the two frames.
	var got := _enumerate(4, 5, Transport.MODE_PINGPONG, 4, 4)
	_assert_seq(got, [5, 4, 5, 4], "min-length region alternates its two frames")


func _test_degenerate_single_frame_is_inert() -> void:
	# end <= start (below min length): no motion, never crashes.
	var s = Transport.step(3, 3, Transport.MODE_PINGPONG, Transport.DIR_FWD, 3)
	_assert_eq(s["frame"], 3, "degenerate single-frame region stays put")


# --- helpers -------------------------------------------------------------

## Enumerate `n` successive frames from `cur0`, direction resetting forward on
## entry (as Play does). Returns the list of frames the transport lands on.
func _enumerate(start: int, end: int, mode: int, cur0: int, n: int) -> Array:
	var frames: Array = []
	var cur := cur0
	var dir := Transport.DIR_FWD
	for _i in range(n):
		var s = Transport.step(start, end, mode, dir, cur)
		cur = s["frame"]
		dir = s["dir"]
		frames.append(cur)
	return frames


func _assert_seq(got: Array, want: Array, msg: String) -> void:
	_assert_true(got == want, "%s (got %s, want %s)" % [msg, str(got), str(want)])


func _assert_eq(got, want, msg: String) -> void:
	_assert_true(got == want, "%s (got %s, want %s)" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
