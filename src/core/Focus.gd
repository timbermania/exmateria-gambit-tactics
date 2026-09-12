extends Node
## [b]Focus — the right to receive device input, as a STACK of states (ADR-0177).[/b]
##
## There is a set of states that may accept input; exactly one holds it; the assembler tier
## manages the transitions. Push to hand focus down to a nested state, pop to return it to
## whatever was underneath. Supersedes ADR-0119 dec. 1's `focus` row (grant/return handles,
## which cannot answer "who is underneath me") and dec. 5 (a flat railway point, same defect).
##
## [b]It gates DELIVERY, not action.[/b] A non-holder is not asked to decline — Godot does not
## call it. `set_process_input`, `set_process_unhandled_input`, `set_process_unhandled_key_input`
## and `set_process_shortcut_input` go false on every registered root but the top of the stack,
## which is ADR-0119 dec. 2's "the bad state is unrepresentable" reached with an engine
## primitive rather than with discipline. Measured before this file was written; see the ADR.
##
## [b]`Control._gui_input` is a DIFFERENT path and is untouched[/b] — text fields inside the
## F3 panels keep working regardless of who holds focus.
##
## [b]Two channels, genuinely simultaneous[/b] (ADR-0119 dec. 6, kept). `game` and `debug` each
## have their own stack, which is how F3 opens an overlay over a modal. A `debug` participant
## is never deafened by a `game` transition and vice versa.
##
## [b]Registration is what makes the states ENUMERABLE[/b], and that is the point — the six
## mechanisms this replaces (a boolean, a named-action list, a wholesale grab, a predicate, an
## enum, a nullable) could each answer "am I deaf?" and none could answer "what are the
## states?". [method describe] prints the stack. The hole in registration — a consumer that
## never registers — is closed by `tools/check_focus_anchor.py`, the mandatory code anchor
## ADR-0119's Consequences asked for, NOT by asking people to remember.

## The input callbacks a registered root is deafened on. `_gui_input` is deliberately absent.
const _GATED := ["input", "unhandled_input", "unhandled_key_input", "shortcut_input"]

## Channel names. Simultaneous by ADR-0119 dec. 6 — one stack each, no interaction.
const CHANNEL_GAME := "game"
const CHANNEL_DEBUG := "debug"

## Emitted after any transition, with the new holder's state name (or "" when a stack empties).
## For the F3 panel and for tests; nothing routes on it.
signal focus_changed(channel: String, state_name: String)

## channel -> Array of frames. A frame is {"state": String, "root": Node}.
var _stacks: Dictionary = {}
## channel -> Array[Node] of every registered root, whether or not it holds focus.
var _registered: Dictionary = {}


## Register [param root] as a participant on [param channel]. Idempotent. A newly registered
## root is deafened immediately unless it is already the top of its stack, so registering
## mid-transition cannot open a second listener.
func register(root: Node, channel: String = CHANNEL_GAME) -> void:
	if root == null or not is_instance_valid(root):
		push_error("[Focus] register: null or freed root")
		return
	var roots: Array = _registered.get(channel, [])
	if roots.has(root):
		_apply(channel)
		return
	roots.append(root)
	_registered[channel] = roots
	if not root.tree_exiting.is_connected(_on_root_exiting):
		root.tree_exiting.connect(_on_root_exiting.bind(root, channel))
	_apply(channel)


## Push [param root] to the top of [param channel]'s stack under the name [param state_name].
## Everything below it goes deaf; nothing below it is forgotten. Registers [param root] first
## if it is not already a participant, because a push IS a registration in every real caller.
func push(state_name: String, root: Node, channel: String = CHANNEL_GAME) -> void:
	if root == null or not is_instance_valid(root):
		push_error("[Focus] push(%s): null or freed root" % state_name)
		return
	register(root, channel)
	var stack: Array = _stacks.get(channel, [])
	stack.append({"state": state_name, "root": root})
	_stacks[channel] = stack
	_apply(channel)
	focus_changed.emit(channel, state_name)


## Pop the top of [param channel]'s stack and hand focus back to whatever was underneath.
## [param root] is checked against the top frame: popping something that is not the holder is
## a programming error, not a no-op, because it means two states disagree about who is up.
func pop(root: Node, channel: String = CHANNEL_GAME) -> void:
	var stack: Array = _stacks.get(channel, [])
	if stack.is_empty():
		push_error("[Focus] pop on an empty '%s' stack" % channel)
		return
	var top: Dictionary = stack[-1]
	if top["root"] != root:
		push_error("[Focus] pop('%s'): '%s' holds focus, not this node — %s"
				% [channel, top["state"], describe(channel)])
		return
	stack.pop_back()
	_stacks[channel] = stack
	_apply(channel)
	focus_changed.emit(channel, "" if stack.is_empty() else stack[-1]["state"])


## Does [param root] currently hold focus on [param channel]? For assertions and the F3 panel.
## Production code should NOT branch on this — that is the flag this file replaces. If you
## need it to decide whether to act, you are still holding the old model.
func holds(root: Node, channel: String = CHANNEL_GAME) -> bool:
	var stack: Array = _stacks.get(channel, [])
	return not stack.is_empty() and stack[-1]["root"] == root


## The state name on top of [param channel], or "" when nothing holds it.
func current(channel: String = CHANNEL_GAME) -> String:
	var stack: Array = _stacks.get(channel, [])
	return "" if stack.is_empty() else String(stack[-1]["state"])


## The whole stack, bottom to top, as state names. THIS is the thing that did not exist
## before: one readable answer to "which states can accept input, and which one does".
func stack_names(channel: String = CHANNEL_GAME) -> Array[String]:
	var out: Array[String] = []
	for frame in _stacks.get(channel, []):
		out.append(String(frame["state"]))
	return out


## One line per channel, for the F3 panel, `push_error` messages and test failure output.
func describe(channel: String = "") -> String:
	var channels: Array = _stacks.keys() if channel == "" else [channel]
	var parts: Array[String] = []
	for ch in channels:
		var names := stack_names(String(ch))
		parts.append("%s[%d reg]: %s" % [ch, _live(String(ch)).size(),
				" > ".join(names) if not names.is_empty() else "(nobody)"])
	return "  ".join(parts)


## Drop every frame and every registration for [param channel]. For test teardown and for a
## hard scene reset; a normal transition pops.
func reset(channel: String = CHANNEL_GAME) -> void:
	for root in _live(channel):
		_set_gated(root, true)
	_stacks.erase(channel)
	_registered.erase(channel)
	focus_changed.emit(channel, "")


## Registered roots on [param channel] that are still valid, pruning any that were freed
## without leaving the tree first.
func _live(channel: String) -> Array:
	var out: Array = []
	for root in _registered.get(channel, []):
		if root != null and is_instance_valid(root):
			out.append(root)
	_registered[channel] = out
	return out


## The switch itself: the top of the stack hears, every other registered root is deaf. With an
## empty stack nobody is deafened — an unpushed channel behaves exactly as it did before this
## file existed, which is what lets the conversion be staged one caller at a time.
func _apply(channel: String) -> void:
	var stack: Array = _stacks.get(channel, [])
	var holder: Node = null if stack.is_empty() else stack[-1]["root"]
	for root in _live(channel):
		_set_gated(root, holder == null or root == holder)


func _set_gated(root: Node, enabled: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	for what in _GATED:
		root.call("set_process_%s" % what, enabled)


## A root that leaves the tree gives up focus and its registration. Without this a freed screen
## keeps a frame on the stack forever and everything under it stays deaf — the failure would
## present as "the game stopped responding after closing a menu", with nothing in the log.
func _on_root_exiting(root: Node, channel: String) -> void:
	var stack: Array = _stacks.get(channel, [])
	var kept: Array = []
	for frame in stack:
		if frame["root"] != root:
			kept.append(frame)
	var changed := kept.size() != stack.size()
	_stacks[channel] = kept
	var roots: Array = _registered.get(channel, [])
	roots.erase(root)
	_registered[channel] = roots
	_apply(channel)
	if changed:
		focus_changed.emit(channel, "" if kept.is_empty() else kept[-1]["state"])
