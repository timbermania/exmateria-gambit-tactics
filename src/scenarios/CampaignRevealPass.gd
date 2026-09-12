class_name CampaignRevealPass
extends RefCounted
## One node's [b]reveal pass[/b] — the ordered walk of its node script list that drains
## every reveal it owes right now, one [b]reveal step[/b] at a time
## (docs/adr/0230-the-reveal-drain-is-an-ordered-pass-and-the-animation-writes-the-bit.md).
##
## [codeblock]
## var pass_ := Campaign.reveal_pass(node_index)
## while true:
##     var s := pass_.step()
##     if s.is_empty():
##         break
##     draw(s)          # ← the animation's job — WorldMapRevealAnimation, ADR-0231.
## [/codeblock]
##
## [b]A cursor, not a re-query.[/b] `Campaign.query` is first-match from script 0, exactly
## as `FUN_80091238` is, so looping it until it returns {} does not terminate: nine nodes
## open their beat with a [look-at](docs/context/11-campaign-spine.md) guarded on a bit
## only a later script sets, and 17 of the 107 reveal-mask scripts never clear their own
## guard. Holding a cursor is the whole difference — conditions are still re-evaluated
## against the LIVE store on every step (so a triplet's `reveal_node` is what opens the
## next look-at), but a script is visited at most once, so termination is by construction
## rather than by a property of the data that is false.
##
## [b]The step writes the bit.[/b] On the console `0x8006DFA0` — the store — is inside
## mode `0x36`'s tick, the node-reveal ANIMATION page, not inside op `0x22`'s emit
## handler. So the bit and the picture are one event, and [method step] returns AFTER
## writing. Putting the write in the caller would make the animation a re-cut of this
## seam rather than a pacing change (ADR-0230 dec. 3).
##
## [b]The caller paces this, and one does[/b] — [WorldMapRevealAnimation] holds each step
## for the length of the console's animation page for it (ADR-0231). Nothing here moved to
## make that possible, which is what ADR-0230 dec. 4 predicted.
##
## Vocabulary: CONTEXT.md → "Campaign spine" → Reveal / Reveal step / Reveal pass /
## Look-at / Reveal animation. `pair100` and `unary800` are retired names for the ERASE direction; they
## survive only as `events.json`'s own keys, which this class translates and does not
## rename at the source.

## What [method step] returns in `kind`. Four of the five move a bit; `look_at` moves the
## pen and nothing else (ADR-0230 dec. 6 — it is 17 of the 107 scripts and it is the
## choreography, so it is returned rather than skipped).
const KIND_REVEAL_NODE := &"reveal_node"
const KIND_UNREVEAL_NODE := &"unreveal_node"
const KIND_REVEAL_ROUTE := &"reveal_route"
const KIND_UNREVEAL_ROUTE := &"unreveal_route"
const KIND_LOOK_AT := &"look_at"

## `events.json`'s emit mask → our kind. The JSON's own `kind` strings are the PLACEHOLDER
## names (`pair100`, `unary800`, `here200`) that `tools/parse_world_map.py` emits and that
## `CampaignNodeScriptTest.EMIT_CENSUS` pins; the rename is ours, downstream of the parser.
const KIND_OF_MASK := {
	0x080: KIND_REVEAL_ROUTE,
	0x100: KIND_UNREVEAL_ROUTE,
	0x200: KIND_LOOK_AT,
	0x400: KIND_REVEAL_NODE,
	0x800: KIND_UNREVEAL_NODE,
}

## A look-at operand of `0xFF` means "the marker's own node" —
## `FUN_8006C894`'s `OUT[0] == 0xFF ? marker : OUT[0]`. No shipped operand is 0xFF (all
## 107 reveal-mask operands are < 43, asserted by `CampaignRevealPassTest`); the branch is
## here because the ROM has it and the vocabulary names it, not because the table uses it.
const LOOK_AT_SELF := 0xFF

## The node this pass belongs to — a [b]node index[/b] (0-based), never a place number.
var node_index: int = -1

var _scripts: Array = []
var _store: WorldMapProgress = null
## `Vector2i(min(a, b), max(a, b))` → route index. Built once by [Campaign]; total over
## the shipped data (ADR-0230 dec. 7).
var _route_of: Dictionary = {}
## Campaign's own `_conditions_pass`, with the store already bound (ADR-0230 dec. 10 — the
## rule it applies needed no change). Handed in rather than reached for because the STORE
## is the caller's to name, not because this class is free of the autoload: [method step]
## reads `Campaign.MASK_REVEAL`, and that constant is Campaign's vocabulary to own.
var _conditions_pass: Callable
## Index of the next script to consider. Monotonic: this is what bounds the walk.
var _cursor: int = 0


func _init(node_index_: int, scripts: Array, store: WorldMapProgress,
		route_of: Dictionary, conditions_pass: Callable) -> void:
	node_index = node_index_
	_scripts = scripts
	_store = store
	_route_of = route_of
	_conditions_pass = conditions_pass


## Apply the next reveal this node owes and describe it, or {} when the pass is finished.
##
## The descriptor is what the animation will draw:
## [codeblock]
## {"kind": &"reveal_node",  "node": 26, "host": 2, "script": 2}
## {"kind": &"reveal_route", "route": 12, "a": 6, "b": 26, "host": 2, "script": 1}
## {"kind": &"look_at",      "node": 5,  "host": 21, "script": 0}
## [/codeblock]
## `host` is [member node_index]; `script` is the position in that node's script list, so
## a caller can say WHICH script it just watched without re-deriving it.
func step() -> Dictionary:
	while _cursor < _scripts.size():
		var s: Dictionary = _scripts[_cursor]
		var emit: Dictionary = s.get("emit", {})
		var mask := int(emit.get("mask", 0)) & Campaign.MASK_REVEAL
		var at := _cursor
		_cursor += 1
		if mask == 0 or not _conditions_pass.call(s.get("conditions", [])):
			continue
		var d := _apply(mask, emit.get("operands", []), at)
		# A faulted script has already said so through `push_error`. It must not come back
		# as {}: to the caller {} is FINISHED, and returning it here would truncate the
		# rest of the beat on a decode fault instead of losing one step of it.
		if d.is_empty():
			continue
		return d
	return {}


## Write the bit and build the descriptor. Split out of [method step] only so the walk and
## the effect read as two things.
func _apply(mask: int, operands: Array, script_index: int) -> Dictionary:
	var kind: StringName = KIND_OF_MASK.get(mask, &"")
	if kind == &"":
		# `MASK_REVEAL` is five single bits and an emit carries exactly one of them, so a
		# combination here means the decoder moved, not that the table has a sixth kind.
		push_error("[CampaignRevealPass] node %d script %d: reveal mask 0x%03X is not one "
				% [node_index, script_index, mask]
				+ "of the five kinds — see docs/adr/0230")
		return {}
	var d := {"kind": kind, "host": node_index, "script": script_index}
	match kind:
		KIND_LOOK_AT:
			var n := int(operands[0]) if operands.size() > 0 else LOOK_AT_SELF
			d["node"] = node_index if n == LOOK_AT_SELF else n
		KIND_REVEAL_NODE, KIND_UNREVEAL_NODE:
			if operands.size() < 1:
				return _bad_operands(kind, operands, script_index)
			d["node"] = int(operands[0])
			_store.set_node_known(int(operands[0]), kind == KIND_REVEAL_NODE)
		KIND_REVEAL_ROUTE, KIND_UNREVEAL_ROUTE:
			if operands.size() < 2:
				return _bad_operands(kind, operands, script_index)
			var a := int(operands[0])
			var b := int(operands[1])
			var r := route_of(a, b)
			if r < 0:
				return {}
			d["route"] = r
			d["a"] = a
			d["b"] = b
			_store.set_route_drawn(r, kind == KIND_REVEAL_ROUTE)
	return d


## The route whose two endpoints are [param a] and [param b] in EITHER order, or -1.
##
## The emit names two nodes; the drawn bit is `556 + route`. Over the shipped `model.json`
## all 48 routes have a unique endpoint pair and all 47 route emits resolve to a route
## whose bit is exactly the guard they are conditioned on — so the lookup is total, and a
## miss is a decode fault rather than a case to skip quietly (ADR-0230 dec. 7).
func route_of(a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not _route_of.has(key):
		push_error("[CampaignRevealPass] node %d: no route joins %d and %d — the reveal "
				% [node_index, a, b]
				+ "is silently skipped; regenerate assets/world_map/model.json")
		return -1
	return int(_route_of[key])


func _bad_operands(kind: StringName, operands: Array, script_index: int) -> Dictionary:
	push_error("[CampaignRevealPass] node %d script %d: %s carries %d operand(s)"
			% [node_index, script_index, kind, operands.size()])
	return {}
