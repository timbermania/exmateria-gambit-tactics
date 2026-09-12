class_name WorldMapRevealAnimation
extends RefCounted
## The [b]reveal animation[/b] — one [CampaignRevealPass] paced across the console's
## vsyncs, and the picture each of its steps draws
## (docs/adr/0231-the-reveal-animation-is-three-pages-on-the-vsync-clock.md).
##
## ADR-0230 dec. 4 left exactly this on the map's side: *"the pass is stepped, not run …
## pace the calls, draw between them."* Nothing in [CampaignRevealPass] moves. This object
## owns the pass, holds each [b]reveal step[/b] on screen for as long as the console's
## animation page holds it, and says what extra the frame must draw while it does.
##
## [b]It is stepped from [method WorldMapScene.advance], never from a [Tween].[/b] Same
## reason as [WorldMapScreenIn] and §38's town-page open: a delta-driven ramp runs at the
## display's refresh rate, measured 143.9 Hz here, so a 16-vsync hold would land in a
## third of a second instead of a quarter (ADR-0161).
##
## [b]The console runs three pages, and all three were read.[/b] `FUN_8006C894` — the
## reveal runner, mode `0x39`'s tick — dispatches one emit per invocation into one of
## three page pushes, and the tick table at `0x8009E690` names each one's tick:
##
## [codeblock]
## kind             push            page   tick            what it does
## look_at          FUN_8006D7F4    0x32   FUN_8006D928    a CAMERA pan to the node
## reveal_route     FUN_8006DA88    0x35   FUN_8006DBB8    the ribbon grows, quad by quad
## reveal_node      FUN_8006DE50    0x36   FUN_8006DF4C    16 vsyncs, and nothing else
## [/codeblock]
##
## [b]The bit and the picture disagree at one end, and that is what
## [method hidden_route] and [method ghost_node] are for.[/b] ADR-0230 dec. 3 has
## [method CampaignRevealPass.step] write the bit and return, so by the time this object
## sees a step the store already reads the FINISHED state. The console does not always
## write it then: `0x8006DFA0` sets a node's bit on the animation's first frame (so a
## revealed node is on screen the whole hold — no disagreement), but the ROUTE arm sets
## `556 + r` on its LAST frame (`0x8006DCFC`..`0x8006DD08`) and the node ERASE clears
## `512 + n` on its last frame (`0x8006E040`..`0x8006E048`). Those two are the ones the
## store would draw early, so those two are overridden for the length of the page.
##
## [b]It never writes a bit itself.[/b] The write is [CampaignRevealPass]'s, on the seam
## ADR-0230 dec. 3 put it on; this side is presentation, and a second writer would be the
## re-cut of that seam the ADR exists to prevent.

## The hold on a node reveal or erase, in vsyncs — `ori v1,zero,0x10` at `0x8006DE58`,
## the value `FUN_8006DE50` stores into the page record's `+8` and `FUN_8006DF4C`
## decrements once per tick before it pops. [b]Sixteen frames of nothing changing[/b]:
## the pin is already on screen (the bit landed on frame 1) and the tick's whole body is
## the counter and the rebuild flag. It is a BEAT, and it is what makes a triplet read as
## choreography rather than as a jump cut.
const NODE_VSYNCS := 16

## The hold on a look-at. [b]This one is the port's, not a measurement, and the reason is
## that the console's picture here is a camera pan the port structurally does not have[/b]
## — §21.1: the view never scrolls. `FUN_8006D7F4` pushes page `0x32` either way, and
## `FUN_8006D928`'s first act is to test the pan enable at `0x800D0AF8 & 1`: with no pan
## armed it pops on that same tick, which is one vsync. So one vsync is what the console
## spends when it has nothing to pan, and it is what this spends.
##
## The look-at's actual content is not in the page at all — see [member regarding].
const LOOK_AT_VSYNCS := 1

## `sra v0,v0,5` at `0x8008DBC0`: a ribbon quad is held for
## `isqrt(dx² + dy²) >> 5` vsyncs, the distance between consecutive waypoint PAIRS.
## `FUN_8008D9A0` computes the whole table into `0x800D3BC4` before the page starts.
##
## [b]On the shipped route table every one of those is zero[/b] — the longest segment in
## `model.json` is 31.1 px and the shift needs 32 — so the console draws one quad per
## vsync and a route lands in 3 to 10 frames. The formula is ported anyway rather than
## replaced by the 1 it currently evaluates to: the 1 is a fact about the DATA, and
## `parse_world_map.py` regenerating a longer route would silently lose the slow arm.
const QUAD_SHIFT := 5

## The reveal step being shown, or {} when the pass is finished — the descriptor
## [method CampaignRevealPass.step] returned, verbatim.
var step: Dictionary = {}

## The node index the pass is [b]regarding[/b] — the last look-at's operand, or -1 before
## the first one. [b]It outlives the look-at's own page[/b], which is the whole of why a
## one-vsync page is enough: on the console the look-at's content is the emit handler's
## write of the selected-place word `DAT_800D0BB4` at `0x80091DC8`, and a word stays
## written. §19.1 is what that word draws — the location name, over the node it names —
## so the pen is the LABEL, and it stands there until the next look-at moves it.
##
## It is emphatically not the player's cursor (11-campaign-spine.md → Look-at: *"a
## look-at does not touch it"*). `FUN_8006C844`, which the runner calls before every one
## of the three pushes, ZEROES the cursor's ramp accumulators (`0x8009EF6C`,
## `0x8009EF7C`, `0x8009F184`, `0x8009F194` — [WorldMapCursor]'s own four words). It
## stills the cursor; it does not steer it.
var regarding: int = -1

## Reveal steps shown so far, including the one in flight. For the print and the tests.
var steps_shown: int = 0

var _reveals: CampaignRevealPass = null
var _assets: WorldMapAssets = null
## Vsyncs left on the current page — the node hold and the look-at.
var _left: int = 0
## Ribbon quads currently drawn of a route step, and the vsyncs left on the one at the
## growing end. `_quads` is the picture; `_quad_left` is the clock under it.
var _quads: int = 0
var _quad_left: int = 0
## Per-quad holds for the route step in flight, in the ROUTE's own vertex order.
var _durations: Array[int] = []
## True when the emit named the route's endpoints the other way round — bit 1 of
## `0x800D3BBC`, set at `0x8008DA1C` when the pair matched reversed. The ribbon grows
## away from the node the emit names FIRST, which is the node the look-at before it was
## pointing at, so the direction is the choreography and not a detail.
var _reversed: bool = false


func _init(reveals: CampaignRevealPass, assets: WorldMapAssets) -> void:
	_reveals = reveals
	_assets = assets
	# Take the first step NOW rather than on the first tick, so a pass that owes nothing
	# is never active for even one frame: the callers both want "did this node owe
	# anything" answered before they decide what to do next.
	_advance()


## True while a step is on screen. False the moment the pass is finished.
func is_active() -> bool:
	return not step.is_empty()


## Advance one vsync, and say whether the frame must be redrawn.
##
## [b]Always true while active[/b], which is the console's own rule and not a shortcut:
## every animating tick of all three pages ORs bit 1 into `0x8004D950`
## (`0x8006DD74`..`0x8006DD88`, `0x8006DFCC`..`0x8006DFE0`), and §28.1 reads that bit as
## the rebuild request. A reveal frame is a rebuilt frame.
func tick() -> bool:
	if step.is_empty():
		return false
	if _durations.is_empty():
		_left -= 1
		if _left <= 0:
			_advance()
		return true
	_quad_left -= 1
	if _quad_left <= 0:
		_step_quad()
	return true


## Finish the pass immediately, applying every step it still owes.
##
## The capture rig freezes the vsync clock (`_capture` calls `set_process(false)`), and a
## host that mounts the map for one settled frame wants the state the drain LANDS on, not
## whatever frame of it four warm-up frames reached — the same guarantee
## [method WorldMapScreenIn.settle] gives the ramp. It is also exactly the pre-animation
## behaviour, so a caller that does not want to watch has one call to make.
func settle() -> void:
	while not step.is_empty():
		_advance()


# ---------------------------------------------------------------- the picture

## The route the store says is drawn but the frame must NOT draw whole — the ribbon in
## flight — or -1. Its quads come from [method ribbon_quads] instead.
func hidden_route() -> int:
	if _durations.is_empty():
		return -1
	return int(step.get("route", -1))


## How many of the in-flight route's ribbon quads to draw, growing or shrinking, and
## which end they are anchored to. `{}` when no route step is in flight.
##
## [codeblock]
## {"route": 12, "quads": 3, "from_end": false}
## [/codeblock]
func ribbon_quads() -> Dictionary:
	if _durations.is_empty():
		return {}
	return {"route": int(step["route"]), "quads": _quads, "from_end": _reversed}


## The node the store says is gone but the frame must still draw — an erase in its hold —
## or -1. `0x8006E048` clears `512 + n` on the LAST frame of the page, so the pin stands
## for all sixteen and the place leaves the map as an event rather than as a dropped
## frame.
func ghost_node() -> int:
	if step.get("kind", &"") != CampaignRevealPass.KIND_UNREVEAL_NODE:
		return -1
	return int(step.get("node", -1))


# ---------------------------------------------------------------- the walk

func _advance() -> void:
	step = _reveals.step()
	_durations = []
	_quads = 0
	_quad_left = 0
	_reversed = false
	if step.is_empty():
		return
	steps_shown += 1
	match step.get("kind", &""):
		CampaignRevealPass.KIND_LOOK_AT:
			regarding = int(step.get("node", -1))
			_left = LOOK_AT_VSYNCS
		CampaignRevealPass.KIND_REVEAL_ROUTE, CampaignRevealPass.KIND_UNREVEAL_ROUTE:
			_begin_route()
		_:
			_left = NODE_VSYNCS


## Arm the ribbon walk — `FUN_8008D9A0`, minus the copy into `0x800D3BE8` that this side
## does not need (the polyline is already addressable through [WorldMapAssets]).
func _begin_route() -> void:
	var r := int(step.get("route", -1))
	var routes: Array = _assets.model.get("routes", [])
	if r < 0 or r >= routes.size():
		# `route_of` already refused an unresolvable pair with a push_error, so this is a
		# model that moved under us. Hold the page for a beat rather than divide by zero.
		_left = LOOK_AT_VSYNCS
		return
	_durations = quad_vsyncs(_assets, r)
	if _durations.is_empty():
		_left = LOOK_AT_VSYNCS
		return
	_reversed = int(step.get("a", -1)) == int(routes[r].get("b", -1))
	if step.get("kind", &"") == CampaignRevealPass.KIND_REVEAL_ROUTE:
		_quads = 0
		_quad_left = _durations[0]
	else:
		_quads = _durations.size()
		_quad_left = _durations[_durations.size() - 1]


## One quad boundary, in whichever direction this step runs.
func _step_quad() -> void:
	var growing: bool = step.get("kind", &"") == CampaignRevealPass.KIND_REVEAL_ROUTE
	_quads += 1 if growing else -1
	if _quads >= _durations.size() or _quads <= 0:
		_advance()
		return
	_quad_left = _durations[_quads if growing else _quads - 1]


## The per-quad hold table for one route — `FUN_8008D9A0`'s loop at `0x8008DB74`.
##
## The polyline stores each waypoint as a PAIR of edge vertices (§12.4), so a quad spans
## two consecutive pairs and the distance is measured between consecutive pair FIRSTS —
## the console's `sll v1,s0,3`, a stride of two vertices. Floored at 1: a zero-length hold
## advances a segment on the tick that reads it (`slt` against a counter already
## incremented), which is one vsync, and every quad in the shipped table is zero.
static func quad_vsyncs(assets: WorldMapAssets, route: int) -> Array[int]:
	var out: Array[int] = []
	var routes: Array = assets.model.get("routes", [])
	if route < 0 or route >= routes.size():
		return out
	var poly: Array = routes[route].get("polyline", [])
	for k in range(poly.size() / 2 - 1):
		var a: Array = poly[2 * k]
		var b: Array = poly[2 * (k + 1)]
		var dx := int(b[0]) - int(a[0])
		var dy := int(b[1]) - int(a[1])
		out.append(maxi(1, int(sqrt(float(dx * dx + dy * dy))) >> QUAD_SHIFT))
	return out
