extends Node
## ADR-0230 — the reveal pass. [b]`Campaign.MASK_REVEAL` had zero callers[/b], so nothing
## in the port ever turned a reveal emit into a known node and the map could not open up.
##
## The oracle is the shipped table itself, walked here in the ADR's own terms: 19 story
## beats plus the two that are not gated on the story counter at all, each with the nodes
## and routes its own scripts name. Every number below is derived from
## `assets/world_map/events.json` + `model.json` and none of it is restated from the port.
##
## [b]The store is built from `new_campaign()`, never seeded.[/b] A fixture that sets
## known nodes by hand passes straight through the defect this test exists for —
## `WorldMapPlaceListTest` calls `set_node_known` in a loop and is green against the bug
## unchanged. Nothing here writes a bit it is about to assert.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/CampaignRevealPassTest.tscn

var _passed := 0
var _failed := 0

## `counter → host node`: the 19 story beats that carry reveal scripts, i.e. every
## `var[110] == k` a reveal-mask script is guarded on, with the node whose list carries it.
## The host is unique per counter — no beat is split across two nodes.
const BEATS := [
	[1, 6], [4, 2], [6, 9], [8, 2], [10, 2], [16, 9], [18, 35], [22, 3], [25, 11],
	[28, 39], [29, 19], [31, 9], [34, 0], [36, 9], [41, 1], [45, 5], [47, 21],
	[52, 2], [53, 16],
]

## Each beat run in ISOLATION — opening capture, that beat's counter, nothing else — as
## `[counter, host, +known, +drawn, steps]`. Isolation is why no beat here erases anything:
## an erase is guarded on the bit it clears, and from the opening capture that bit is 0.
## The erase arms are exercised by [method _test_the_campaign_walk] instead.
##
## Counter 1 is the measured zero: Gariland's four scripts are all guarded on bits the
## OPENING CAPTURE already holds ({2, 6, 24} known, {1, 3} drawn), so the beat is already
## spent on the console state the port opens from. It is listed rather than dropped
## because "0 steps" is the assertion.
const ISOLATED := [
	[1, 6, [], [], 0],
	[4, 2, [9, 26], [11, 12], 4],
	[6, 9, [28], [10], 2],
	[8, 2, [17], [2], 2],
	[10, 2, [15, 25, 29], [4, 5, 6], 7],
	[16, 9, [21, 32, 35], [20, 21, 22], 6],
	[18, 35, [3, 10, 37], [36, 37, 38], 6],
	[22, 3, [11, 30], [43, 44], 4],
	[25, 11, [12, 39], [39, 40, 47], 6],
	[28, 39, [19], [42], 2],
	[29, 19, [], [39], 1],
	[31, 9, [0, 8], [17, 18], 4],
	[34, 0, [18], [19], 2],
	[36, 9, [1, 7, 31, 33], [13, 14, 15, 16], 9],
	[41, 1, [5, 13, 38, 40], [25, 26, 27, 28], 12],
	[45, 5, [21, 34], [23, 24], 6],
	[47, 21, [4, 14, 41, 42], [30, 31, 32, 33], 12],
	[52, 2, [16], [46], 3],
	[53, 16, [18], [19], 3],
]

## The same 19 beats run IN ORDER against one store, as
## `[counter, host, +known, -known, +drawn, -drawn, steps]`. This is the campaign, and it
## is the only arm that reaches the erase direction: counter 18 takes back the node and
## route counter 16 drew, and counters 25 and 28 take back more. Six emits across three
## nodes — the known set is not monotonic from Chapter 2 on.
const WALK := [
	[1, 6, [], [], [], [], 0],
	[4, 2, [9, 26], [], [11, 12], [], 4],
	[6, 9, [28], [], [10], [], 2],
	[8, 2, [17], [], [2], [], 2],
	[10, 2, [15, 25, 29], [], [4, 5, 6], [], 7],
	[16, 9, [21, 32, 35], [], [20, 21, 22], [], 6],
	[18, 35, [3, 10, 37], [21], [36, 37, 38], [22], 8],
	[22, 3, [11, 30], [], [43, 44], [], 4],
	[25, 11, [12, 39], [30], [39, 40, 47], [43, 44], 9],
	[28, 39, [19], [], [42], [39], 3],
	[29, 19, [], [], [39], [], 1],
	[31, 9, [0, 8], [], [17, 18], [], 4],
	[34, 0, [18], [], [19], [], 2],
	[36, 9, [1, 7, 31, 33], [], [13, 14, 15, 16], [], 9],
	[41, 1, [5, 13, 38, 40], [], [25, 26, 27, 28], [], 12],
	[45, 5, [21, 34], [], [23, 24], [], 6],
	[47, 21, [4, 14, 41, 42], [], [30, 31, 32, 33], [], 12],
	[52, 2, [16], [], [46], [], 3],
	[53, 16, [], [], [], [], 0],
]

## The two beats gated on no story counter at all, as `[host, gate var, +known, +drawn]`.
## They can fire only through the ARRIVAL hook, which is half of why ADR-0230 dec. 8 has
## one: nothing about the story counter ever makes them live.
const UNCOUNTED := [
	[5, 170, 23, 29],
	[12, 165, 22, 41],
]

## Where [WorldMapScene] lives, for the two hook arms. The screen is mounted for real
## rather than stubbed: dec. 8's claim is about WHERE in `_ready` and `_arrive_at` the
## drain sits, and a stub cannot be wrong about that.
const WORLD_MAP_SCENE := "res://assets/scenes/WorldMap.tscn"

const MASK_REVEAL_ROUTE := 0x080
const MASK_UNREVEAL_ROUTE := 0x100
const ROUTE_DRAWN_BASE := 556


func _ready() -> void:
	_test_the_counter_4_beat()
	_test_every_beat_in_isolation()
	_test_the_campaign_walk()
	_test_the_uncounted_beats()
	_test_a_finished_pass_stays_finished()
	_test_look_at_moves_no_bit()
	_test_route_lookup_is_total()
	_test_no_operand_is_out_of_range()
	await _test_the_map_open_hook()
	await _test_the_arrival_hook()

	if _failed > 0:
		print("[FAIL] CampaignRevealPassTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] CampaignRevealPassTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


# ---------------------------------------------------------------- the arms

## ADR-0230's Prediction 1, on its own, because it is the reported defect: the spine stalls
## at story counter 4 because Sweegy Woods (node 26) is unknown and the four scripts that
## would light it sit on Igros, which is where the marker is standing.
func _test_the_counter_4_beat() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(4)
	_eq("counter 4: the store opens knowing {2, 6, 24}", str(p.known_nodes()), "[2, 6, 24]")
	_eq("counter 4: ...and drawing {1, 3}", str(p.drawn_routes()), "[1, 3]")

	var steps := _drain(2, p)
	_eq("counter 4: Igros owes four reveal steps", steps.size(), 4)
	_eq("counter 4: known becomes {2, 6, 9, 24, 26}", str(p.known_nodes()),
			"[2, 6, 9, 24, 26]")
	_eq("counter 4: drawn becomes {1, 3, 11, 12}", str(p.drawn_routes()), "[1, 3, 11, 12]")
	# ...and the ORDER is the choreography: draw the road, then light the town it reaches.
	_eq("counter 4: step 1 draws route 12", _describe(steps[0]), "reveal_route 12")
	_eq("counter 4: step 2 lights node 26", _describe(steps[1]), "reveal_node 26")
	_eq("counter 4: step 3 draws route 11", _describe(steps[2]), "reveal_route 11")
	_eq("counter 4: step 4 lights node 9", _describe(steps[3]), "reveal_node 9")


## Every beat, from the opening capture, asserting exactly what its own scripts name and
## that NOTHING else moves.
func _test_every_beat_in_isolation() -> void:
	_eq("the isolated table covers every beat", ISOLATED.size(), BEATS.size())
	for row in ISOLATED:
		var counter: int = row[0]
		var host: int = row[1]
		var p := WorldMapProgress.new_campaign()
		p.set_story_counter(counter)
		var before_known := p.known_nodes()
		var before_drawn := p.drawn_routes()
		var steps := _drain(host, p)
		_eq("counter %d at node %d: step count" % [counter, host], steps.size(), int(row[4]))
		_eq("counter %d at node %d: nodes gained" % [counter, host],
				str(_gained(before_known, p.known_nodes())), str(row[2]))
		_eq("counter %d at node %d: nothing loses a node" % [counter, host],
				str(_gained(p.known_nodes(), before_known)), "[]")
		_eq("counter %d at node %d: routes gained" % [counter, host],
				str(_gained(before_drawn, p.drawn_routes())), str(row[3]))
		_eq("counter %d at node %d: nothing loses a route" % [counter, host],
				str(_gained(p.drawn_routes(), before_drawn)), "[]")


## The 19 beats in order against ONE store — the campaign as it is actually played, and
## the only place the erase direction is reachable.
func _test_the_campaign_walk() -> void:
	var p := WorldMapProgress.new_campaign()
	var erased := 0
	for row in WALK:
		var counter: int = row[0]
		var host: int = row[1]
		p.set_story_counter(counter)
		var before_known := p.known_nodes()
		var before_drawn := p.drawn_routes()
		var steps := _drain(host, p)
		_eq("walk %d@%d: step count" % [counter, host], steps.size(), int(row[6]))
		_eq("walk %d@%d: +known" % [counter, host],
				str(_gained(before_known, p.known_nodes())), str(row[2]))
		_eq("walk %d@%d: -known" % [counter, host],
				str(_gained(p.known_nodes(), before_known)), str(row[3]))
		_eq("walk %d@%d: +drawn" % [counter, host],
				str(_gained(before_drawn, p.drawn_routes())), str(row[4]))
		_eq("walk %d@%d: -drawn" % [counter, host],
				str(_gained(p.drawn_routes(), before_drawn)), str(row[5]))
		erased += (row[3] as Array).size() + (row[5] as Array).size()
	# The positive arm on the erase direction: "nothing is ever removed" would otherwise
	# pass this whole walk for the wrong reason.
	_eq("the walk removes six things across three beats", erased, 6)
	_eq("the campaign ends knowing 37 of the 43 places", p.known_nodes().size(), 37)
	_eq("...and drawing 36 of the 48 roads", p.drawn_routes().size(), 36)


## The two beats no story counter can make live. They are why the arrival hook exists.
func _test_the_uncounted_beats() -> void:
	for row in UNCOUNTED:
		var host: int = row[0]
		var gate: int = row[1]
		var p := WorldMapProgress.new_campaign()
		_eq("node %d owes nothing while var[%d] is 0" % [host, gate],
				_drain(host, p).size(), 0)
		p.vars.set_var(gate, 1)
		var steps := _drain(host, p)
		_eq("node %d at var[%d]==1: three steps" % [host, gate], steps.size(), 3)
		_eq("node %d: the pen moves first" % host, _describe(steps[0]),
				"look_at %d" % host)
		_eq("node %d: then the road" % host, _describe(steps[1]),
				"reveal_route %d" % int(row[3]))
		_eq("node %d: then the town" % host, _describe(steps[2]),
				"reveal_node %d" % int(row[2]))


## ADR-0230's Prediction 2 and the property the rejected design fails: after a pass, a
## FRESH pass on the same node against the same store returns {} on its first step.
##
## A re-query loop cannot do this — nine nodes open their beat with a look-at guarded on a
## bit only a later script sets, so `query()` hands back the same script forever. This arm
## is the one that would hang rather than fail.
func _test_a_finished_pass_stays_finished() -> void:
	var residue := 0
	for row in BEATS:
		var p := WorldMapProgress.new_campaign()
		p.set_story_counter(int(row[0]))
		_drain(int(row[1]), p)
		if not Campaign.reveal_pass(int(row[1]), p).step().is_empty():
			residue += 1
			print("  FAIL counter %d at node %d has a live reveal after its pass"
					% [int(row[0]), int(row[1])])
	_eq("no beat leaves a live reveal behind", residue, 0)
	# The same question asked of the WHOLE table, not just the hosts: after the campaign
	# walk, no node anywhere owes a step at the final counter.
	var q := WorldMapProgress.new_campaign()
	for row in WALK:
		q.set_story_counter(int(row[0]))
		_drain(int(row[1]), q)
	var live := 0
	for n in range(WorldMapProgress.NODE_COUNT):
		if not Campaign.reveal_pass(n, q).step().is_empty():
			live += 1
	_eq("after the walk no node owes a reveal at counter 53", live, 0)


## Dec. 6: a look-at is returned as a step and applies nothing. Asserted by taking the
## store's whole word array on both sides of one, because "no bit moved" is the claim and
## the four questions [WorldMapProgress] asks are not all of it.
func _test_look_at_moves_no_bit() -> void:
	var p := WorldMapProgress.new_campaign()
	p.vars.set_var(170, 1)
	var reveals := Campaign.reveal_pass(5, p)
	var before := str(p.vars.to_sparse())
	var s := reveals.step()
	_eq("node 5's first step is a look-at", _describe(s), "look_at 5")
	_eq("...and it changed no variable", str(p.vars.to_sparse()), before)
	_true("...and the step still carries its node", int(s.get("node", -1)) == 5)


## Dec. 7, asserted rather than trusted: the endpoint pair → route lookup is a bijection
## over the data it is asked about. An unresolvable pair is a silently skipped reveal, so
## the two halves are checked separately — the routes are unique, AND every route emit
## resolves to the route whose drawn bit is the guard it is conditioned on.
func _test_route_lookup_is_total() -> void:
	var model := _json("res://assets/world_map/model.json")
	var routes: Array = model.get("routes", [])
	_eq("model.json ships 48 routes", routes.size(), WorldMapProgress.ROUTE_COUNT)
	var seen := {}
	for row in routes:
		seen[Vector2i(mini(int(row["a"]), int(row["b"])), maxi(int(row["a"]), int(row["b"])))] = true
	_eq("...and all 48 endpoint pairs are distinct", seen.size(), routes.size())

	# The join, through the SHIPPED lookup rather than a copy of it.
	var p := WorldMapProgress.new_campaign()
	var emits := 0
	var agree := 0
	for node in _json(Campaign.EVENTS_PATH).get("by_node", []):
		var reveals := Campaign.reveal_pass(int(node["node"]), p)
		for s in node.get("scripts", []):
			var emit: Dictionary = s["emit"]
			if int(emit["mask"]) != MASK_REVEAL_ROUTE and int(emit["mask"]) != MASK_UNREVEAL_ROUTE:
				continue
			emits += 1
			var ops: Array = emit["operands"]
			var r := reveals.route_of(int(ops[0]), int(ops[1]))
			var guards: Array = []
			for c in s.get("conditions", []):
				if int(c["op"]) == Campaign.COND_VAR_EQ:
					guards.append(int((c["operands"] as Array)[0]))
			if r >= 0 and guards.has(ROUTE_DRAWN_BASE + r):
				agree += 1
			else:
				print("  FAIL route emit %s resolved to %d, guards %s" % [ops, r, guards])
	_eq("the table carries 47 route emits", emits, 47)
	_eq("...and every one is guarded on 556 + the route its pair resolves to", agree, emits)


## No reveal operand is a node index the store cannot hold — which is also what makes
## [constant CampaignRevealPass.LOOK_AT_SELF] unreachable against the shipped table. The
## ROM's `OUT[0] == 0xFF ? marker : OUT[0]` is implemented, and this says the data has
## never asked for it, so nobody reads the branch as evidence that it has.
func _test_no_operand_is_out_of_range() -> void:
	var scripts := 0
	var bad := 0
	var self_relative := 0
	for node in _json(Campaign.EVENTS_PATH).get("by_node", []):
		for s in node.get("scripts", []):
			var emit: Dictionary = s["emit"]
			if int(emit["mask"]) & Campaign.MASK_REVEAL == 0:
				continue
			scripts += 1
			for o in emit["operands"]:
				if int(o) == CampaignRevealPass.LOOK_AT_SELF:
					self_relative += 1
				elif int(o) < 0 or int(o) >= WorldMapProgress.NODE_COUNT:
					bad += 1
	_eq("MASK_REVEAL selects 107 of the 182 scripts", scripts, 107)
	_eq("no reveal operand is outside the 43 nodes", bad, 0)
	_eq("no shipped look-at is 0xFF (the branch is the ROM's, not the table's)",
			self_relative, 0)


## ADR-0230 dec. 8's first trigger, and the reported defect end to end. The spine stalls
## at counter 4 because the one live `enter` is Sweegy Woods and Sweegy Woods is unknown,
## so [WorldMapCursor] skips it and [WorldMapTravel] drops every route touching it. The
## four scripts that would light it are on Igros, where the marker is already standing.
func _test_the_map_open_hook() -> void:
	var keep := Campaign.progress
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(4)
	p.set_party_node(3)                                  # place 3 == node index 2, Igros
	# In production the injected store IS this autoload's — `NavigatorMain` hands the
	# screen `Campaign.progress` itself — so the arm asks Campaign the same question the
	# auto-advance walk asks.
	Campaign.progress = p
	_eq("counter 4: the one live enter is Sweegy Woods",
			str(Campaign.live_enter_nodes()), "[26]")
	_true("...and it is unknown before the map opens", not p.is_node_known(26))
	var view := await _mount(p)
	# ADR-0231 paced the pass across frames, so the trigger this arm is about now STARTS
	# an animation instead of landing one. Settling is the pre-0231 behaviour exactly —
	# what moved is when, and dec. 8 is about where.
	view.call("settle_reveal")
	_true("opening the map makes Sweegy Woods known", p.is_node_known(26))
	_eq("...and the four steps land, not one", str(p.known_nodes()), "[2, 6, 9, 24, 26]")
	# NOT `live_enter_nodes()` — it reads conditions only, so it answers [26] whether or
	# not the reveal ever ran, and an arm that cannot fail is not an arm. What the stall
	# actually needed is the node KNOWN and the roads to it DRAWN: `WorldMapCursor` skips
	# an unknown node and `WorldMapTravel` drops every route with an unknown endpoint.
	_eq("...and both roads to it are drawn", str(p.drawn_routes()), "[1, 3, 11, 12]")
	view.queue_free()
	await get_tree().process_frame
	Campaign.progress = keep


## Dec. 8's second trigger, and the one Prediction 3 was falsified into existing. It is
## asserted on DORTER, which is a town: `_arrive_at` returns early for a town, so a drain
## placed after that return would score exactly zero here and nowhere else.
##
## Counter 31 is the beat that needs it — its reveals are Dorter's and counter 30 binds no
## hand-off, so the marker is elsewhere when the counter reaches 31.
func _test_the_arrival_hook() -> void:
	var p := WorldMapProgress.new_campaign()
	p.set_story_counter(31)
	p.set_party_node(2)                                  # Lesalia, not Dorter
	var view := await _mount(p)
	view.call("settle_reveal")
	_eq("counter 31: opening the map elsewhere reveals nothing",
			str(p.known_nodes()), "[2, 6, 24]")
	_true("Dorter is a town, so arrival returns early", WorldMapTownPage.opens_for(
			view.get("assets"), 10))
	view.call("_arrive_at", 10)
	view.call("settle_reveal")                           # ADR-0231 — see the arm above
	_eq("...and arriving there still drains its four steps",
			str(p.known_nodes()), "[0, 2, 6, 8, 24]")
	_eq("...including both roads", str(p.drawn_routes()), "[1, 3, 17, 18]")
	view.queue_free()
	await get_tree().process_frame


func _mount(store: WorldMapProgress) -> Node:
	var view: Node = (load(WORLD_MAP_SCENE) as PackedScene).instantiate()
	view.call("set_progress", store)                     # crossing C3: the map is HANDED it
	add_child(view)
	await get_tree().process_frame
	return view


# ---------------------------------------------------------------- helpers

## Run a pass to completion and collect its descriptors. This loop is the CALLER's, which
## is the point of dec. 4 — [WorldMapScene] owns the identical one and the animation will
## own a paced version of it.
func _drain(node_index: int, store: WorldMapProgress) -> Array:
	var reveals := Campaign.reveal_pass(node_index, store)
	var out: Array = []
	while true:
		var s: Dictionary = reveals.step()
		if s.is_empty():
			break
		out.append(s)
		if out.size() > 64:
			_fail("node %d did not terminate within 64 steps" % node_index)
			break
	return out


func _describe(s: Dictionary) -> String:
	var kind: StringName = s.get("kind", &"?")
	if kind == CampaignRevealPass.KIND_REVEAL_ROUTE \
			or kind == CampaignRevealPass.KIND_UNREVEAL_ROUTE:
		return "%s %d" % [kind, int(s.get("route", -1))]
	return "%s %d" % [kind, int(s.get("node", -1))]


## What [param after] has that [param before] does not, both sorted ascending.
func _gained(before: Array, after: Array) -> Array:
	var out: Array = []
	for v in after:
		if not before.has(v):
			out.append(v)
	return out


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("%s missing — run tools/parse_world_map.py" % path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s: got %s, want %s" % [what, got, want])


func _true(what: String, ok: bool) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s" % what)


func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL %s" % msg)
