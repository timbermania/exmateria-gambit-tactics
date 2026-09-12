extends Node
## ADR-0177's focus stack, as behaviour a picture cannot show.
##
## [b]Every arm drives `get_viewport().push_input`, never a callback.[/b] ADR-0172's *Built*
## lesson is the whole reason: an arm that calls `_unhandled_input` directly cannot tell
## "ignored" from "never delivered", and this file's central claim is that a non-holder is
## NEVER DELIVERED. Calling the callback would pass on a Focus that does nothing at all.
##
## Run: <GODOT> --path . --quit-after 600 res://tests/FocusStackTest.tscn

class Listener extends Node:
	var tag: String
	var sink: Array
	func _init(t: String, s: Array) -> void:
		tag = t; sink = s
	func _unhandled_input(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed:
			sink.append(tag)

var _heard: Array = []
var _passed := 0
var _failed := 0
var _a: Listener
var _b: Listener
var _c: Listener


func _ready() -> void:
	Focus.reset(Focus.CHANNEL_GAME)
	Focus.reset(Focus.CHANNEL_DEBUG)
	_a = Listener.new("A", _heard); add_child(_a)
	_b = Listener.new("B", _heard); add_child(_b)
	_c = Listener.new("C", _heard); add_child(_c)
	await get_tree().process_frame

	await _check_unpushed_channel_is_transparent()
	await _check_push_deafens_everyone_else()
	await _check_pop_returns_focus_to_the_predecessor()
	await _check_two_channels_are_simultaneous()
	await _check_freeing_the_holder_hands_focus_back()
	_check_the_stack_is_readable()
	await _check_an_unregistered_consumer_is_invisible()

	if _failed > 0:
		print("[FAIL] FocusStackTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] FocusStackTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## 1. An EMPTY stack deafens nobody. This is what lets the conversion be staged: a scene that
## has not been converted yet behaves exactly as it did before Focus existed.
func _check_unpushed_channel_is_transparent() -> void:
	Focus.register(_a); Focus.register(_b); Focus.register(_c)
	await _press()
	_same("an empty stack deafens nobody", _heard, ["C", "B", "A"])


## 2. THE CENTRAL CLAIM: a push does not ask the others to decline, it stops them being called.
func _check_push_deafens_everyone_else() -> void:
	Focus.push("B_STATE", _b)
	await _press()
	_same("only the holder is delivered to", _heard, ["B"])
	_eq("current() names the holder", Focus.current(), "B_STATE")
	_eq("holds() is true for the holder", Focus.holds(_b), true)
	_eq("holds() is false for a non-holder", Focus.holds(_a), false)


## 3. A stack, not a selector: pop returns focus to whoever was underneath, and NOBODY had to
## remember who that was. This is the arm a flat model cannot pass.
func _check_pop_returns_focus_to_the_predecessor() -> void:
	Focus.push("C_STATE", _c)
	await _press()
	_same("the nested state takes it", _heard, ["C"])
	_eq("stack is two deep", Focus.stack_names(), ["B_STATE", "C_STATE"] as Array[String])

	Focus.pop(_c)
	await _press()
	_same("pop hands it BACK to the predecessor", _heard, ["B"])
	_eq("and the stack is one deep again", Focus.stack_names(), ["B_STATE"] as Array[String])

	# Popping a non-holder is an error, not a silent no-op — two states disagreeing about who
	# is up is the bug, and swallowing it would hide it.
	Focus.pop(_b)
	await _press()
	_same("emptied stack goes transparent again", _heard, ["C", "B", "A"])


## 4. ADR-0119 dec. 6 kept: `game` and `debug` do not interact. This is how F3 opens over a
## modal, and it is the one part of ADR-0119's focus design that survives unchanged.
func _check_two_channels_are_simultaneous() -> void:
	Focus.push("GAME_STATE", _a, Focus.CHANNEL_GAME)
	Focus.push("DEBUG_STATE", _c, Focus.CHANNEL_DEBUG)
	await _press()
	_same("a debug holder is NOT deafened by a game push", _heard, ["C", "A"])
	_eq("game channel reads its own top", Focus.current(Focus.CHANNEL_GAME), "GAME_STATE")
	_eq("debug channel reads its own top", Focus.current(Focus.CHANNEL_DEBUG), "DEBUG_STATE")
	Focus.reset(Focus.CHANNEL_DEBUG)
	Focus.reset(Focus.CHANNEL_GAME)


## 5. The failure that would present as "the game stopped responding after closing a menu",
## with nothing in the log: a holder freed without popping.
func _check_freeing_the_holder_hands_focus_back() -> void:
	Focus.register(_a); Focus.register(_b); Focus.register(_c)
	var doomed := Listener.new("D", _heard)
	add_child(doomed)
	Focus.push("A_STATE", _a)
	Focus.push("DOOMED", doomed)
	await _press()
	_same("the doomed holder has it", _heard, ["D"])

	doomed.queue_free()
	await get_tree().process_frame
	await _press()
	_same("freeing the holder returns focus, it does not strand it", _heard, ["A"])
	_eq("and its frame left the stack", Focus.stack_names(), ["A_STATE"] as Array[String])
	Focus.reset(Focus.CHANNEL_GAME)


## 6. The property the six replaced mechanisms could not provide at all: not "am I deaf?" but
## "what ARE the states, and which one holds it?"
func _check_the_stack_is_readable() -> void:
	Focus.push("MODE", _a)
	Focus.push("SCREEN", _b)
	Focus.push("SUBSCREEN", _c)
	_eq("the whole stack reads bottom-to-top", Focus.stack_names(),
			["MODE", "SCREEN", "SUBSCREEN"] as Array[String])
	var d := Focus.describe(Focus.CHANNEL_GAME)
	_eq("describe() names every state in order",
			d.contains("MODE > SCREEN > SUBSCREEN"), true)
	Focus.reset(Focus.CHANNEL_GAME)


## 7. [b]The hole, stated as a property rather than discovered as a bug.[/b] Focus governs
## REGISTERED roots and nothing else, so an unregistered consumer hears everything however
## deep the stack is. That is not a defect in the switch — it is the exact reason ADR-0119
## called focus "a discipline, not a guarantee" and demanded a mandatory code anchor, and it
## is what `tools/check_focus_anchor.py` closes STATICALLY.
##
## This arm exists because writing this file tripped over it: arm 5 forgot to re-register one
## listener after a reset and it kept hearing. If that is that easy to do in a 150-line test,
## it is not something production code should be asked to remember.
func _check_an_unregistered_consumer_is_invisible() -> void:
	Focus.reset(Focus.CHANNEL_GAME)
	var stowaway := Listener.new("STOWAWAY", _heard)
	add_child(stowaway)
	Focus.register(_a); Focus.register(_b); Focus.register(_c)
	Focus.push("HOLDER", _a)
	await _press()
	_same("an UNREGISTERED consumer is not deafened — the anchor's whole reason",
			_heard, ["STOWAWAY", "A"])
	stowaway.queue_free()
	await get_tree().process_frame
	Focus.reset(Focus.CHANNEL_GAME)


func _press() -> void:
	_heard.clear()
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame


func _same(what: String, got: Array, want: Array) -> void:
	_eq(what, str(got), str(want))


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  MISMATCH  %s: got %s, want %s  |  %s" % [what, got, want, Focus.describe()])
