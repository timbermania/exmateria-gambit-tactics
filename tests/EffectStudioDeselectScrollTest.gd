extends Node
## TDD guard for the PURE decisions behind Effect-Studio ESC-deselect + scroll-selected-into-view
## (CONTEXT.md "Deselected (empty inspection)"). Fast + scene-free, like EffectStudioUndoShortcutTest:
##   • compute_scroll_target — the minimal-nudge math (−1 = already visible; span-above vs
##     span-below branches, headroom, clamp-at-0);
##   • _is_escape — the Esc key recognizer (down, no echo);
##   • _is_text_focus — "is the focus owner a value-cell edit control" (drives the two-stage Esc).
## The collaborator-state _deselect() flow + the deferred scroll wiring are exercised elsewhere
## (EffectStudioNavStackTest / the headful acceptance).
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioDeselectScrollTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_already_visible_span_leaves_scroll_alone()
	_test_span_above_the_window_scrolls_up_with_headroom()
	_test_span_above_near_the_top_clamps_at_zero()
	_test_span_below_the_window_scrolls_down_with_headroom()
	_test_escape_press_is_recognized()
	_test_non_escape_and_release_and_echo_are_not()
	_test_text_edit_controls_are_value_cell_focus()
	_test_non_text_controls_and_null_are_not()

	print("\n=== EffectStudioDeselectScrollTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioDeselectScrollTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioDeselectScrollTest")
		get_tree().quit(0)


# --- compute_scroll_target: minimal-nudge into view -----------------------

## A span already fully inside the visible window is left exactly where it is (−1 = no scroll),
## so re-selecting a visible event never jars the view.
func _test_already_visible_span_leaves_scroll_alone() -> void:
	# window [40, 140); span [50, 70) sits fully inside.
	var got := Page.compute_scroll_target(Rect2(0.0, 50.0, 100.0, 20.0), 40, 100.0, 24.0)
	_assert_eq(got, -1, "a fully-visible span is left alone (no scroll)")


## A span pushed ABOVE the window top (the inspector grew over it) scrolls up so its top sits
## `headroom` below the new window top — a one-lane gap, not flush against the editor.
func _test_span_above_the_window_scrolls_up_with_headroom() -> void:
	# window [140, 340); span top 100 is above it. target = 100 − 24 = 76.
	var got := Page.compute_scroll_target(Rect2(0.0, 100.0, 20.0, 20.0), 140, 200.0, 24.0)
	_assert_eq(got, 76, "a span above the window scrolls up to (top − headroom)")


## The nudge never scrolls past the content top: a span near frame 0 clamps the target to 0.
func _test_span_above_near_the_top_clamps_at_zero() -> void:
	# window [40, 140); span top 10, headroom 24 → 10 − 24 = −14 → clamped to 0.
	var got := Page.compute_scroll_target(Rect2(0.0, 10.0, 20.0, 20.0), 40, 100.0, 24.0)
	_assert_eq(got, 0, "the up-nudge clamps at the content top (never negative)")


## Symmetric below-the-bottom branch: a span past the window bottom scrolls down just enough
## to seat its bottom `headroom` above the window bottom. (A click can't reach this, but the
## helper stays symmetric.)
func _test_span_below_the_window_scrolls_down_with_headroom() -> void:
	# window [100, 300); span [300, 320) ends below it. target = 320 − 200 + 24 = 144.
	var got := Page.compute_scroll_target(Rect2(0.0, 300.0, 20.0, 20.0), 100, 200.0, 24.0)
	_assert_eq(got, 144, "a span below the window scrolls down to seat its bottom with headroom")


# --- _is_escape ------------------------------------------------------------

func _test_escape_press_is_recognized() -> void:
	_assert_true(Page._is_escape(_key(KEY_ESCAPE, true, false)), "Esc key-down is the deselect key")


func _test_non_escape_and_release_and_echo_are_not() -> void:
	_assert_true(not Page._is_escape(_key(KEY_A, true, false)), "a letter is not Esc")
	_assert_true(not Page._is_escape(_key(KEY_ESCAPE, false, false)), "an Esc key-up does not deselect")
	_assert_true(not Page._is_escape(_key(KEY_ESCAPE, true, true)), "a held Esc echo does not repeat-deselect")


# --- _is_text_focus (two-stage Esc: first drop a focused value cell) -------

func _test_text_edit_controls_are_value_cell_focus() -> void:
	_assert_true(Page._is_text_focus(LineEdit.new()), "a focused LineEdit is a value-cell edit")
	_assert_true(Page._is_text_focus(SpinBox.new()), "a focused SpinBox is a value-cell edit")
	_assert_true(Page._is_text_focus(TextEdit.new()), "a focused TextEdit is a value-cell edit")


func _test_non_text_controls_and_null_are_not() -> void:
	_assert_true(not Page._is_text_focus(Button.new()), "a focused Button is not a value-cell edit")
	_assert_true(not Page._is_text_focus(null), "no focus owner is not a value-cell edit")


# --- helpers ---------------------------------------------------------------

func _key(keycode: int, pressed: bool, echo: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = pressed
	e.echo = echo
	return e


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
