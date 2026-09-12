extends Node3D

## Guard (#1273): UI's five `SfxRouter` reaches, inverted onto three narrow signals
## and named host-side by `src/scenes/UIWiring.gd`.
##
## WHAT NO STATIC GUARD CAN SEE. `check_ui_autoload_reach.py` proves no UI member
## spells `SfxRouter`. It cannot see whether the SOUND STILL PLAYS, and an inversion
## that silently deletes a cue passes every static check ever written. Nor can it see
## the thing that actually goes wrong here, which is a signal that is too WIDE.
##
## 🔴 THE NARROWNESS IS THE CLAIM, NOT THE PLUMBING. `DialogueBox.advanced` already
## existed and it fires when the box is DISMISSED. Folding the page-flip cue onto it
## would compile, pass the ratchet, and blip on every dismissal — which is exactly the
## failure `TileCursor.cursor_stepped` was created to avoid ("a behaviour change
## wearing a refactor's clothes"). Arms 1 and 2 are that claim: `page_turned` fires
## once per REAL turn, never on the refused final advance, and never on a dismissal.
##
## Cues are observed through `SfxRouter.cue_requested`, which the router emits BEFORE
## backend dispatch precisely so a test with no SPU backend can still see them. The
## return token is NOT usable as the discriminator: `play_cue` returns 0 both when the
## cue is unknown and when the backend is absent, so asserting on it would be vacuous
## here for the same reason #1263's PAR and #1272's empty roster were.
##
## Run: <GODOT> --path . res://tests/UICueInversionTest.tscn

const DialogueBoxClass = preload("res://src/ui3/assemblies/DialogueBox.gd")
const FormationScreenScript = preload("res://src/ui3/formation/FormationDetailTransition.gd")

const CUE_PAGE_FLIP := "ui.dialogue_page_flip"
const CUE_TYPING := "ui.text_typing"
const CUE_INVALID := "system.invalid"

var _passed := 0
var _failed := 0

var _cues: Array[String] = []
var _turns := 0
var _glyphs := 0
var _advances := 0


func _ready() -> void:
	var router := get_tree().root.get_node_or_null(^"SfxRouter")
	if router == null:
		_fail("the SfxRouter autoload is not in this tree — no arm can run")
		_report()
		return
	router.cue_requested.connect(_on_cue)

	_test_page_turned_fires_once_per_real_turn()
	_test_page_turned_is_not_the_dismissal_signal()
	_test_glyph_revealed_beats_while_typing()
	_test_the_wiring_names_both_dialogue_cues()
	_test_the_wiring_is_idempotent()
	_test_the_invalid_slug_actually_resolves()
	_test_the_formation_screen_publishes_what_the_wiring_connects()
	_report()


func _on_cue(name: String, _bank: String, _slot: int) -> void:
	_cues.append(name)


func _on_turn() -> void:
	_turns += 1


func _on_glyph() -> void:
	_glyphs += 1


func _on_advanced() -> void:
	_advances += 1


## Enough lines to paginate — `_paginate` splits on a LINE budget, not a token.
func _many_line_tokens() -> Array:
	var t: Array = [{"type": "color", "palette": 0}]
	for i in range(9):
		t.append({"type": "text", "value": "line %d" % i})
		t.append({"type": "newline"})
	return t


func _make_box() -> Node:
	var box: Node = DialogueBoxClass.new()
	add_child(box)
	box.throttle = 2
	return box


## ARM 1 — one beat per REAL turn, and silence on the advance that is refused.
func _test_page_turned_fires_once_per_real_turn() -> void:
	var box := _make_box()
	box.show_dialog(_many_line_tokens(), 0x12, -1, 0.0)
	var pages: int = box.page_count()
	_assert(pages >= 2, "arm 1 needs a multi-page message to mean anything (got %d)" % pages)
	box.page_turned.connect(_on_turn)

	_turns = 0
	var granted := 0
	while box.advance_page():
		granted += 1
	_assert_eq(granted, pages - 1, "advance_page grants exactly page_count-1 turns")
	_assert_eq(_turns, pages - 1, "page_turned beats once per granted turn")

	# The refused advance is the one `advanced` would have fired on.
	var before := _turns
	_assert_eq(box.advance_page(), false, "the last advance is refused")
	_assert_eq(_turns, before, "a REFUSED advance emits no page_turned")
	box.queue_free()


## ARM 2 — the anti-fold arm. This is the whole reason a new signal exists.
func _test_page_turned_is_not_the_dismissal_signal() -> void:
	var box := _make_box()
	box.show_dialog(_many_line_tokens(), 0x12, -1, 0.0)
	box.page_turned.connect(_on_turn)
	box.advanced.connect(_on_advanced)
	_turns = 0
	_advances = 0

	# `advance()` is the DISMISSAL verb; `advance_page()` is the turn verb. One word
	# apart, opposite meanings — the collision this arm exists to pin down.
	box.advance()
	_assert_eq(_advances, 1, "advance() — the dismissal — emits `advanced`")
	_assert_eq(_turns, 0,
		"dismissing emits NO page_turned — folding the cue onto `advanced` would blip on close")
	box.queue_free()


## ARM 3 — the typing beat tracks the reveal rather than the show.
func _test_glyph_revealed_beats_while_typing() -> void:
	var box := _make_box()
	box.glyph_revealed.connect(_on_glyph)
	_glyphs = 0
	box.show_dialog(_many_line_tokens(), 0x12, -1, 0.0)
	_assert_eq(_glyphs, 0, "showing the box reveals no glyph yet")
	box.advance_frames(6)
	_assert(_glyphs > 0, "advancing frames reveals glyphs and beats (got %d)" % _glyphs)
	box.queue_free()


## ARM 4 — the signal reaches the REAL cue names, through the real wiring.
func _test_the_wiring_names_both_dialogue_cues() -> void:
	var box := _make_box()
	UIWiring.wire_dialogue_box(box)

	_cues.clear()
	box.page_turned.emit()
	_assert_eq(_cues, [CUE_PAGE_FLIP], "page_turned -> the page-flip cue, by name")

	_cues.clear()
	box.glyph_revealed.emit()
	_assert_eq(_cues, [CUE_TYPING], "glyph_revealed -> the typing cue, by name")
	box.queue_free()


## ARM 5 — a second wire must not double the sound. `ScenarioPlayerScene` pools three
## boxes and `CombatUITestScene` wires one it already owns.
##
## 🔴 WHAT THIS ARM DOES AND DOES NOT CATCH, MEASURED BY SEEDING BOTH. Deleting
## `wire_dialogue_box`'s `is_connected` guard leaves this arm GREEN — Godot refuses a
## duplicate connection of the same named Callable on its own and logs an error. What
## this arm DOES catch is the adapters being rewritten as inline lambdas: a fresh
## Callable per call, every one accepted, and the blip plays three times. Seeded
## exactly that way it reds with `got 3, want 1`. The arm is a pin on the named-static
## shape, not a proof of the guard.
func _test_the_wiring_is_idempotent() -> void:
	var box := _make_box()
	UIWiring.wire_dialogue_box(box)
	UIWiring.wire_dialogue_box(box)
	UIWiring.wire_dialogue_box(box)

	_cues.clear()
	box.page_turned.emit()
	_assert_eq(_cues.size(), 1, "wiring three times still plays the cue ONCE")
	box.queue_free()


## ARM 6 — `play_system` is not `play_cue`: an unresolvable slug push_warnings and
## emits NOTHING, so a typo here would be a silent deletion that arms 1-5 cannot see.
func _test_the_invalid_slug_actually_resolves() -> void:
	_cues.clear()
	UIWiring._play_invalid_cue()
	_assert_eq(_cues, [CUE_INVALID],
		"the refusal buzz resolves to a real system-bank slot, not a push_warning")


## ARM 7 — the screen still PUBLISHES what the wiring subscribes to. Mounting the real
## screen needs a camera and a cursor rig; the signal's existence does not.
func _test_the_formation_screen_publishes_what_the_wiring_connects() -> void:
	# Via a Script-typed local: `Preloaded.method()` parses as a STATIC call and
	# `get_script_signal_list` is an instance method of Script.
	var scr: Script = FormationScreenScript
	var names: Array = []
	for s in scr.get_script_signal_list():
		names.append(String(s["name"]))
	_assert(names.has("input_refused"),
		"FormationDetailTransition declares `input_refused` (has: %d signals)" % names.size())
	UIWiring.wire_formation_screen(null)
	_assert(true, "wire_formation_screen(null) is safe — mount_over_map can return null")


func _report() -> void:
	print("\n=== UICueInversionTest: %d passed, %d failed ===" % [_passed, _failed])
	print("[PASS] UICueInversionTest" if _failed == 0 else "[FAIL] UICueInversionTest")
	get_tree().quit(1 if _failed > 0 else 0)


func _assert(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("  [x] %s" % what)
	else:
		_failed += 1
		print("  [ ] %s" % what)


func _assert_eq(got: Variant, want: Variant, what: String) -> void:
	if got == want:
		_passed += 1
		print("  [x] %s" % what)
	else:
		_failed += 1
		print("  [ ] %s (got %s, want %s)" % [what, got, want])


func _fail(what: String) -> void:
	_failed += 1
	print("  [ ] %s" % what)
