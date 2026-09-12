class_name WorldMapTravel
extends RefCounted
## Walking the party marker from one node to another — WORLD_MAP_SCREEN.md §27, and §29.6
## which watched a real traversal end to end.
##
## [b]This is a port of a measurement, and an unusually complete one.[/b] §29.6 drove the
## console from `ss1` to node 2 and recorded 2,709 vsyncs; `travel.py walk 6 2` predicts
## the same walk from `WLDCORE.BIN` alone, and the two agree **waypoint for waypoint** —
## two routes, both reversed, twelve waypoints, a 12-bit heading and a frame-list id each.
##
## [codeblock]
## v227  ○ pressed, heading set, frame list still 16
## v228  frame list 26 — the FAST bank engages and the marker starts moving
## v272  marker node 6 -> 24, route 3 hands off to route 1
## v321  marker node 24 -> 2.  94 vsyncs, 1.6 s, two routes, twelve waypoints
## [/codeblock]
##
## §29.6's three additions to the static reading, all honoured here: the marker walks the
## WHOLE path on the fast bank (frame lists 26–29; the slow bank 16–23 is never entered),
## the leg count is the CURRENT ROUTE's and not the path's, and `0x800D3BBC` — round 10's
## "selected route" — is not the traversal and is not read here. (§40.2 read it: it is the
## REVEAL ribbon's animation state, and it belongs to [WorldMapRevealAnimation]'s subject,
## not to this one.)

## §27.3 / `FUN_8008F434`. The bank is a state flag, not a speed threshold: §29.6 saw
## `0x8009F24C` read 4 for the whole traversal across twelve different headings.
const SLOW_BANK := 16
const FAST_BANK := 24
## The list a marker standing still holds: the slow bank at facing 0. §26.2 — *"id = 16
## at rest means the idle marker faces the camera"*. It is NOT `SLOW_BANK + facing(h)`;
## a parked marker does not face its next heading, it faces the player.
const IDLE_LIST := SLOW_BANK
## Headings are 12-bit, 4096 to the turn.
const HALF_TURN := 2048


## The frame-list index within a bank — `FUN_8008F434`.
static func facing(heading: int) -> int:
	return ((heading + 256) >> 9) & 7


static func frame_list_for(heading: int, fast: bool) -> int:
	return (FAST_BANK if fast else SLOW_BANK) + facing(heading)


## Breadth-first hop list `[[route, reversed], …]` from [param from_node] to
## [param to_node], both 1-based, or `[]` when there is no path.
##
## Restricted to routes whose BOTH endpoints the party knows. §29's measurement is that
## the known set and the drawn-route set coincide — `ss1` knows nodes {2, 6, 24} and has
## routes {1, 3} drawn, *"exactly the two edges joining those three nodes"* — so the two
## gates agree on every capture the repo holds. Known-endpoints is the one used because
## the other is circular: a route is drawn by story script, and gating travel on it would
## mean a node you can see is a node you can never reach.
static func route_path(assets: WorldMapAssets, progress: WorldMapProgress,
		from_node: int, to_node: int) -> Array:
	var src := from_node - 1
	var dst := to_node - 1
	if src < 0 or dst < 0:
		return []
	var adj: Dictionary = {}
	var routes: Array = assets.model["routes"]
	for r in routes.size():
		var a: int = int(routes[r]["a"])
		var b: int = int(routes[r]["b"])
		if not (progress.is_node_known(a) and progress.is_node_known(b)):
			continue
		adj.get_or_add(a, []).append([b, r, false])
		adj.get_or_add(b, []).append([a, r, true])
	var seen: Dictionary = {src: null}
	var queue: Array = [src]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == dst:
			var out: Array = []
			while seen[cur] != null:
				var back: Array = seen[cur]
				out.push_front([back[1], back[2]])
				cur = back[0]
			return out
		for edge in adj.get(cur, []):
			if not seen.has(edge[0]):
				seen[edge[0]] = [cur, edge[1], edge[2]]
				queue.append(edge[0])
	return []


# ---------------------------------------------------------------- one traversal

## `[{from, to, heading, steps}]` in traversal order. `steps` is 2·d — see [method step].
##
## [b]A multi-hop path is FLATTENED into this one array[/b], so the node boundaries between
## route hops would otherwise vanish — see [member _leg_end_node], which keeps them.
var legs: Array = []
## `leg index -> 1-based node that leg ENDS on`, for the legs that land on a node. Only
## the last leg of each route hop has an entry.
##
## [b]This exists because the ROM asks its event question at every node, not just the
## last.[/b] `FUN_8008E540` (§32.2) sets the marker node, queries the event table with mask
## 8, and only THEN looks at whether more legs remain — so a story battle standing on the
## way is not walked past. Flattening the hops threw that boundary away.
var _leg_end_node: Dictionary = {}
## The 1-based node the marker reached on the vsync [method step] just returned, or 0.
## Read it immediately after `step()`; the next `step()` clears it.
var reached_node: int = 0
## Map-space position, i.e. what the marker's descriptor holds. Screen is `+ (128, 12)`.
var position: Vector2i
var heading: int = 0
## 1-based node the marker has reached, updated at each hand-off; 0 while between nodes.
var at_node: int = 0
## 1-based destination.
var destination: int = 0
var finished: bool = false

var _leg: int = 0
var _tick: int = 0
var _ticks_done: int = 0
var _assets: WorldMapAssets


## Plan a walk, or return null when there is no path. [param from_node] and
## [param to_node] are 1-based.
static func plan(assets: WorldMapAssets, progress: WorldMapProgress,
		from_node: int, to_node: int) -> WorldMapTravel:
	var hops := route_path(assets, progress, from_node, to_node)
	if hops.is_empty():
		return null
	var t := WorldMapTravel.new()
	t._assets = assets
	t.destination = to_node
	t.at_node = from_node
	var routes: Array = assets.model["routes"]
	for hop in hops:
		var r := int(hop[0])
		var rev := bool(hop[1])
		t.legs.append_array(_legs_of(assets, r, rev))
		if t.legs.is_empty():
			continue
		# The node THIS hop lands on, in the same 1-based space as `destination`. A hop
		# traversed forward ends on the route's `b`, reversed on its `a` — the two
		# directions `route_path` pushes into `adj`.
		var end_index := int(routes[r]["a"]) if rev else int(routes[r]["b"])
		t._leg_end_node[t.legs.size() - 1] = end_index + 1
	if t.legs.is_empty():
		return null
	t.position = t.legs[0]["from"]
	t.heading = int(t.legs[0]["heading"])
	return t


## One route's legs — `FUN_8008D800`, via `travel.py`'s `Route.legs`.
##
## Reversed, a leg takes the heading and duration of the waypoint it walks TO, and turns
## the heading through half a turn. That asymmetry is the table's own: a waypoint's
## `heading`/`d` describe the step that LEAVES it going forward.
static func _legs_of(assets: WorldMapAssets, r: int, reversed: bool) -> Array:
	var wp: Array = assets.model["routes"][r]["waypoints"]
	var n := wp.size()
	var out: Array = []
	for i in range(n - 1):
		var src: Dictionary
		var dst: Dictionary
		var h: int
		var d: int
		if reversed:
			var k := n - 1 - i
			src = wp[k]
			dst = wp[k - 1]
			h = (int(dst["heading"]) + HALF_TURN) & 0xFFF
			d = int(dst["d"])
		else:
			src = wp[i]
			dst = wp[i + 1]
			h = int(src["heading"]) & 0xFFF
			d = int(src["d"])
		out.append({
			"from": Vector2i(int(src["xy"][0]), int(src["xy"][1])),
			"to": Vector2i(int(dst["xy"][0]), int(dst["xy"][1])),
			"heading": h, "steps": 2 * d,
		})
	return out


## The total length of the walk in vsyncs — `Σ (2·d + 1)`.
func total_ticks() -> int:
	var n := 0
	for leg in legs:
		n += int(leg["steps"]) + 1
	return n


## Advance one vsync. True when the marker moved or turned.
##
## [b]A leg is `2·d` motion steps plus ONE vsync held at its endpoint.[/b] That reading
## is fitted to §29.6's trace and it is the only one that fits: of nine candidates
## (`2d−1`/`2d`/`2d+1` steps × hold-or-not × three roundings), it alone ends the walk on
## the console's own v321, and it is the best on intermediate frames too.
##
## ⚠ **73 of 95 vsyncs land on the console's exact pixel; the other 22 are within 1 px.**
## Every one of the thirteen waypoint arrivals is exact, and so is every heading, frame
## list and leg duration — what is not resolved is the rounding of the *interpolation
## between* waypoints. Truncation toward zero is the best of the three tried. The console
## is presumably stepping a fixed-point accumulator along the heading rather than
## interpolating endpoints, and that is §15's kind of open question, not this port's.
func step() -> bool:
	if finished or legs.is_empty():
		return false
	var leg: Dictionary = legs[_leg]
	var steps: int = int(leg["steps"])
	var was := position
	var was_heading := heading
	reached_node = 0
	_tick += 1
	_ticks_done += 1
	heading = int(leg["heading"])
	if _tick <= steps:
		var a: Vector2i = leg["from"]
		var b: Vector2i = leg["to"]
		if _tick == steps:
			position = b
		else:
			var t := float(_tick) / float(steps)
			position = Vector2i(int(float(a.x) + float(b.x - a.x) * t),
					int(float(a.y) + float(b.y - a.y) * t))
	else:
		# The held vsync at the endpoint, then hand off.
		position = leg["to"]
		_tick = 0
		reached_node = int(_leg_end_node.get(_leg, 0))
		if reached_node > 0:
			at_node = reached_node
		_leg += 1
		if _leg >= legs.size():
			finished = true
			at_node = destination
	return position != was or heading != was_heading


## The marker's frame list this vsync.
##
## §29.6's trace updates the heading one vsync BEFORE the frame list follows it: v227
## reads heading 951 with frame list **16**, and v228 reads 26. Note which 16 that is —
## the IDLE list, not `SLOW_BANK + facing(951)`, which would be 18. The heading register
## had been written but `FUN_8008F434` had not run yet, so the marker was still standing
## in its resting pose. Reproducing that as "the slow bank at the new heading" is what
## this test caught.
func frame_list() -> int:
	if finished or _ticks_done == 0:
		return IDLE_LIST
	return frame_list_for(heading, true)
