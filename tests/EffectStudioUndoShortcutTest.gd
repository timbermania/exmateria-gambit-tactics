extends Node
## TDD guard for the Effect-Studio UNDO keybinding recognition (Ctrl+Z).
##
## The undo MACHINERY (EffectEditSession.undo + stable ordinal addressing, #286) was
## already built and guard-tested, but nothing INVOKED it — no key, no button. This
## guards the pure recognizer `EffectStudioPage._is_undo_shortcut(event)` that the page's
## _unhandled_key_input uses to fire undo. Fast + ROM-free (no scene load); the full
## key → host.studio_undo → revert flow is the headful EffectStudioUndoTest.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioUndoShortcutTest.tscn

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_ctrl_z_press_is_the_undo_shortcut()
	_test_plain_z_is_not()
	_test_ctrl_other_key_is_not()
	_test_ctrl_z_release_is_not()
	_test_ctrl_z_autorepeat_echo_is_not()
	_test_delete_key_is_the_colour_delete_shortcut()
	_test_non_delete_key_is_not()
	_test_delete_release_and_echo_are_not()

	print("\n=== EffectStudioUndoShortcutTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioUndoShortcutTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioUndoShortcutTest")
		get_tree().quit(0)


func _test_ctrl_z_press_is_the_undo_shortcut() -> void:
	_assert_true(Page._is_undo_shortcut(_key(KEY_Z, true, true, false)),
		"Ctrl+Z key-down (no echo) is the undo shortcut")


func _test_plain_z_is_not() -> void:
	_assert_true(not Page._is_undo_shortcut(_key(KEY_Z, false, true, false)),
		"a plain Z (no Ctrl) is not undo")


func _test_ctrl_other_key_is_not() -> void:
	_assert_true(not Page._is_undo_shortcut(_key(KEY_Y, true, true, false)),
		"Ctrl+Y is not undo")


func _test_ctrl_z_release_is_not() -> void:
	_assert_true(not Page._is_undo_shortcut(_key(KEY_Z, true, false, false)),
		"a key-up does not fire undo")


func _test_ctrl_z_autorepeat_echo_is_not() -> void:
	_assert_true(not Page._is_undo_shortcut(_key(KEY_Z, true, true, true)),
		"a held-key echo does not repeat-fire undo")


## ADR-0089 editing-UX amendment (decision 4): Del removes the selected colour keyframe. Guards
## the pure recognizer the page's _unhandled_key_input uses (gated on a real keyframe being
## selected — that gate lives in the page state, exercised headful).
func _test_delete_key_is_the_colour_delete_shortcut() -> void:
	_assert_true(Page._is_colour_delete_shortcut(_key(KEY_DELETE, false, true, false)),
		"Del key-down (no echo) is the colour-delete shortcut")


func _test_non_delete_key_is_not() -> void:
	_assert_true(not Page._is_colour_delete_shortcut(_key(KEY_A, false, true, false)),
		"a plain letter is not the colour-delete shortcut")


func _test_delete_release_and_echo_are_not() -> void:
	_assert_true(not Page._is_colour_delete_shortcut(_key(KEY_DELETE, false, false, false)),
		"a Del key-up does not delete")
	_assert_true(not Page._is_colour_delete_shortcut(_key(KEY_DELETE, false, true, true)),
		"a held Del echo does not repeat-delete")


func _key(keycode: int, ctrl: bool, pressed: bool, echo: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.ctrl_pressed = ctrl
	e.pressed = pressed
	e.echo = echo
	return e


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
