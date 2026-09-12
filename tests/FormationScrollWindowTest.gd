extends Node
# test-kind: logic
# seeded-break: scroll_window's `scroll_offset * COLS` step changed to `* ROWS` (a row-step slides the window 2 units instead of 4) — 'one row-step advances the window start by COLS=4' + 'offset 1 window is units 4..11' RED (got 2..9), last-window start/end RED (148->74, 155->81); every offset-0, short-roster, clamp, and empty-roster arm stays green; GREEN unbroken on the reverted tree

## TDD guard for the formation roster SCROLL windowing (ADR-0081 all-templates view).
##
## Seam 3 (computational, pure fn): the 8-cell grid (ROWS×COLS) is a ROW-GRANULAR window
## onto the full owned roster. `scroll_window(units, offset)` returns the ≤8 units visible
## at a row offset (each step = COLS units); `max_scroll_offset(count)` is the last top-row
## that still fills the window; `clamp_scroll(offset, count)` pins an advance at the end.
## Fixed ROM cells, NOT pagination — a single row scrolls in.
##
## Uses a synthetic index array as stand-in units — windowing is pure index math, so the
## seam is exercised independent of the seeder or any Character. Expected values are
## hand-worked from ROWS=2, COLS=4 (window=8), not recomputed the way the code does.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/FormationScrollWindowTest.tscn

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_window_size_and_row_granular_start()
	_test_last_window_and_offset_clamps_at_end()
	_test_short_roster_never_scrolls()
	_test_empty_roster_is_safe()

	print("\n=== FormationScrollWindowTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationScrollWindowTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationScrollWindowTest")
		get_tree().quit(0)


func _seq(n: int) -> Array:
	var a: Array = []
	for i in range(n):
		a.append(i)
	return a


## A full roster (156) windows 8 at a time; one row-step advances the window by COLS=4.
func _test_window_size_and_row_granular_start() -> void:
	var units := _seq(156)
	var w0 := FormationScene.scroll_window(units, 0)
	_assert_eq(w0.size(), 8, "window shows exactly ROWS*COLS=8")
	_assert_eq(w0[0], 0, "offset 0 starts at unit 0")
	_assert_eq(w0[7], 7, "offset 0 ends at unit 7")

	var w1 := FormationScene.scroll_window(units, 1)
	_assert_eq(w1[0], 4, "one row-step advances the window start by COLS=4")
	_assert_eq(w1[7], 11, "offset 1 window is units 4..11")


## 156 units = 39 rows; the last top-row that fills 8 cells is 39-ROWS=37. Advancing past
## it clamps (no blank scroll past the end), and that last window is still a full 8.
func _test_last_window_and_offset_clamps_at_end() -> void:
	var units := _seq(156)
	_assert_eq(FormationScene.max_scroll_offset(156), 37, "max top-row offset = 39 rows - 2")

	var last := FormationScene.scroll_window(units, 37)
	_assert_eq(last.size(), 8, "the last in-bounds window is full (156 divides by COLS)")
	_assert_eq(last[0], 148, "last window starts at unit 148")
	_assert_eq(last[7], 155, "last window ends at the final unit 155")

	_assert_eq(FormationScene.clamp_scroll(38, 156), 37, "advancing past the end clamps to max")
	_assert_eq(FormationScene.clamp_scroll(999, 156), 37, "a wild offset clamps to max")
	_assert_eq(FormationScene.clamp_scroll(-3, 156), 0, "a negative offset clamps to 0")


## A roster that fits within (or under) the grid never scrolls: max offset 0, and a partial
## last window returns just the units present.
func _test_short_roster_never_scrolls() -> void:
	var five := _seq(5)
	_assert_eq(FormationScene.max_scroll_offset(5), 0, "5 units (2 rows) never scroll")
	var w := FormationScene.scroll_window(five, 0)
	_assert_eq(w.size(), 5, "short roster window returns just the 5 present")
	_assert_eq(FormationScene.clamp_scroll(1, 5), 0, "cannot advance past a non-scrolling roster")

	# Exactly one full page (8) also never scrolls.
	_assert_eq(FormationScene.max_scroll_offset(8), 0, "exactly 8 units (2 rows) never scroll")


## Zero units: no crash, empty window, no scroll.
func _test_empty_roster_is_safe() -> void:
	_assert_eq(FormationScene.scroll_window([], 0).size(), 0, "empty roster -> empty window")
	_assert_eq(FormationScene.max_scroll_offset(0), 0, "empty roster has max offset 0")
	_assert_eq(FormationScene.clamp_scroll(2, 0), 0, "empty roster clamps any offset to 0")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
