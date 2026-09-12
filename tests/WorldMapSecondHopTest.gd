extends Node
## X1 — the SECOND hop: the one where the marker actually walks.
##
## [b]Hop 1 is the no-walk case, and it was the only one covered.[/b] At story 1 the live
## hand-off is at node 6 Gariland, which is the node the marker is standing on, so
## `FUN_8008E2BC`'s type-8 arm fires before the pathfinder is ever reached (§29.3) — and
## `round15_expB.csv` measured exactly that on the console, `BATTLE.BIN` resident 43 vsyncs
## after the press with the marker never moving. [NavigatorWorldMapChainTest] drives that
## hop and stops there, so every line of the travel rig was unreached by the live scene.
##
## At story 2 the hand-off moves to node 24 Mandalia Plains and the marker is still on
## Gariland — a DIFFERENT node — so ○ plans a path, the marker walks it, and the scenario
## fires on ARRIVAL with no second press (§32.2). That is the hop this covers.
##
## [b]The numbers are the console's, not the port's.[/b] §29.6 drove the real traversal and
## `travel.py walk 6 24` predicts it from `WLDCORE.BIN` alone: one route hop (route 3,
## reversed), five waypoints, headings 951/1183/1407/1362/1078, frame lists 26/26/27/27/26
## on the fast bank, 45 vsyncs — v227…v271 of the recording, the leg before the marker's
## node changed 6 -> 24.
##
## Run: <GODOT> --path . --quit-after 600 res://tests/WorldMapSecondHopTest.tscn

const SCENE_PATH := "res://assets/scenes/WorldMap.tscn"

## Gariland Magic City. Place numbers are 1-based; node index 6 (§29.4).
const GARILAND := 7
## Mandalia Plains — node index 24, the story-2 hand-off.
const MANDALIA := 25
## Igros Castle — node index 2. Known at story 1, and TWO route hops away: the walk to it
## passes through Mandalia.
const IGROS := 3

## `travel.py walk 6 24`, and §29.6's recording, waypoint for waypoint.
const ROM_HEADINGS := [951, 1183, 1407, 1362, 1078]
const ROM_FRAME_LISTS := [26, 26, 27, 27, 26]
const ROM_TOTAL_TICKS := 45

var _passed := 0
var _failed := 0


func _ready() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		print("[FAIL] WorldMapSecondHopTest — cannot load %s" % SCENE_PATH)
		get_tree().quit(1)
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var view := scene.instantiate()
	layer.add_child(view)
	add_child(layer)
	await get_tree().process_frame
	await get_tree().process_frame

	if view.assets == null or not view.assets.loaded:
		# Regenerable and gitignored — a missing asset is not a failing assertion.
		print("[SKIP] WorldMapSecondHopTest — run tools/parse_world_map.py")
		get_tree().quit(0)
		return

	await _check_story_2_moves_the_hand_off(view)
	await _check_the_plan_is_the_console_recording(view)
	await _check_the_marker_walks_and_fires_on_arrival(view)
	await _check_a_hand_off_on_the_WAY_stops_the_walk(view)

	if _failed > 0:
		print("[FAIL] WorldMapSecondHopTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapSecondHopTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## Seat the campaign at story 2, marker on Gariland — the state the port reaches by
## playing Balbanes's Death, whose own bytecode tail writes `Zero(110); Add(110, 2)`
## (CampaignVariableStoreTest drives those handlers; NavigatorWorldMapChainTest drives the
## hop that gets there).
func _seat_at_story_2(view: Node) -> WorldMapProgress:
	var p: WorldMapProgress = Campaign.progress
	p.set_story_counter(2)
	p.set_party_node(GARILAND)
	view.set_progress(p)
	var places: Array[int] = []
	for index in Campaign.live_enter_nodes():
		places.append(index + 1)
	view.set_hand_off_places(places)
	return p


## The whole reason hop 2 differs from hop 1: the live node stops being the marker's.
func _check_story_2_moves_the_hand_off(view: Node) -> void:
	var p := _seat_at_story_2(view)
	_eq("the campaign is at story counter 2", p.story_counter(), 2)
	var live := Campaign.live_enter_nodes()
	_eq("exactly one node offers a hand-off", live.size(), 1)
	_eq("...and it is Mandalia Plains (node index 24)",
			live[0] if live.size() > 0 else -1, 24)
	_eq("...which is NOT the node the marker stands on — hop 1's whole difference",
			(live[0] + 1) if live.size() > 0 else -1, MANDALIA)
	_eq("the marker is still on Gariland", p.party_node(), GARILAND)
	var emit := Campaign.enter_at(24)
	_eq("it hands off scenario 15, Mandalia Plains",
			int(emit.get("scenario_id", -1)), 15)
	_eq("...at transition mode 1 — heavy, it deploys a squad",
			int(emit.get("transition_mode", -1)), 1)


## §29.6, waypoint for waypoint. If the route table or the reversal arithmetic drifts,
## this is where it shows, not three systems later.
func _check_the_plan_is_the_console_recording(view: Node) -> void:
	var p := _seat_at_story_2(view)
	var walk := WorldMapTravel.plan(view.assets, p, GARILAND, MANDALIA)
	_true("Gariland -> Mandalia plans a walk", walk != null)
	if walk == null:
		return
	_eq("five waypoint legs — route 3, reversed", walk.legs.size(), 5)
	_eq("45 vsyncs — the console's v227…v271", walk.total_ticks(), ROM_TOTAL_TICKS)
	for i in range(mini(walk.legs.size(), ROM_HEADINGS.size())):
		var h := int(walk.legs[i]["heading"])
		_eq("leg %d heading is the console's" % i, h, ROM_HEADINGS[i])
		_eq("leg %d walks the fast bank" % i,
				WorldMapTravel.frame_list_for(h, true), ROM_FRAME_LISTS[i])
	# The boundary the flattening used to lose. One route hop, so the ONLY node it lands
	# on is the last leg's, and it is the destination.
	_eq("the last leg is marked as landing on Mandalia",
			int(walk._leg_end_node.get(4, 0)), MANDALIA)


## The user-visible sentence, and the one arm no test mounted: [b]the marker walks to the
## next town, and the scenario fires when it gets there.[/b]
func _check_the_marker_walks_and_fires_on_arrival(view: Node) -> void:
	var p := _seat_at_story_2(view)
	var log := _watch(view)

	view.enter_place(MANDALIA)
	_true("○ on Mandalia plans a walk rather than firing on the spot", view._travel != null)
	if view._travel == null:
		return
	_eq("it departed for Mandalia", _first(log, "departed"), MANDALIA)
	_eq("nothing has fired yet — the event is on ARRIVAL", _first(log, "node_entered"), -1)

	# The sprite MOVES. A walk that jumped straight to the destination would satisfy every
	# signal assertion below and be exactly the thing the report was about.
	var start_pos: Vector2i = view._travel.position
	var moved_mid_walk := false
	var frames := 0
	while view._travel != null and frames < 1200:
		await get_tree().process_frame
		frames += 1
		if view._travel != null and view._travel.position != start_pos:
			moved_mid_walk = true
	_true("the walk finished", view._travel == null)
	_true("...and the marker was somewhere between the two nodes while it ran",
			moved_mid_walk)

	_eq("it arrived at Mandalia", _first(log, "arrived"), MANDALIA)
	_eq("...and the party is there now", p.party_node(), MANDALIA)
	_eq("the scenario fired on arrival, with no second press",
			_first(log, "node_entered"), MANDALIA)
	_eq("...exactly once", _count(log, "node_entered"), 1)
	_unwatch(view, log)


## §32.2's other half — `FUN_8008E540` asks the event table at EVERY node the marker
## reaches and only THEN looks at whether more legs remain:
##
##     if (FUN_80091238(arrived_node, 8)) { ... fire ...; return; }
##     ...
##     if (more_legs) { ... start the next route ...; return; }
##
## Igros Castle is known at story 1 and is two route hops from Gariland, THROUGH Mandalia
## Plains — which at story 2 is holding the story battle. So ○ on Igros must stop at
## Mandalia and fire there, not stroll past it.
func _check_a_hand_off_on_the_WAY_stops_the_walk(view: Node) -> void:
	var p := _seat_at_story_2(view)
	_true("Igros Castle is known, so it can be walked to", p.is_node_known(IGROS - 1))
	var probe := WorldMapTravel.plan(view.assets, p, GARILAND, IGROS)
	_true("Gariland -> Igros plans a two-hop path", probe != null)
	if probe == null:
		return
	_eq("twelve waypoint legs — §29.6's two routes", probe.legs.size(), 12)
	_eq("the FIRST hop lands on Mandalia, and the path knows it",
			int(probe._leg_end_node.get(4, 0)), MANDALIA)
	_eq("...and the second on Igros", int(probe._leg_end_node.get(11, 0)), IGROS)

	var log := _watch(view)
	view.enter_place(IGROS)
	_eq("it departed for Igros", _first(log, "departed"), IGROS)
	var frames := 0
	while view._travel != null and frames < 1200:
		await get_tree().process_frame
		frames += 1
	_true("the walk ended", view._travel == null)
	_eq("it stopped at MANDALIA, not Igros — the event table is asked at every node",
			_first(log, "arrived"), MANDALIA)
	_eq("...and the party is standing on Mandalia", p.party_node(), MANDALIA)
	_eq("...and Mandalia's battle is what fired", _first(log, "node_entered"), MANDALIA)
	_unwatch(view, log)

	# DIRECTION. The assertions above are load-bearing only if losing the node boundary
	# breaks them — which is precisely the state the port was in, one flat `legs` array
	# with no record of where one route hop ended and the next began. Wipe it and the same
	# walk runs straight through Mandalia to Igros with nothing fired.
	var p2 := _seat_at_story_2(view)
	var log2 := _watch(view)
	var blind := WorldMapTravel.plan(view.assets, p2, GARILAND, IGROS)
	blind._leg_end_node.clear()
	view._travel = blind
	var frames2 := 0
	while view._travel != null and frames2 < 1200:
		await get_tree().process_frame
		frames2 += 1
	_eq("without the boundary the marker walks PAST Mandalia to Igros",
			p2.party_node(), IGROS)
	# And it is worse than firing late: Igros is a TOWN with no live hand-off at story 2,
	# so `_arrive_at` stands there and emits nothing. The story battle is not deferred,
	# it is LOST — the campaign simply stops advancing.
	_eq("...and nothing fires at all — the story battle is skipped, not deferred",
			_first(log2, "node_entered"), -1)
	_unwatch(view, log2)


# ------------------------------------------------------------------ plumbing

func _watch(view: Node) -> Array:
	var log: Array = []
	view.departed.connect(func(n: int) -> void: log.append(["departed", n]))
	view.arrived.connect(func(n: int) -> void: log.append(["arrived", n]))
	view.node_entered.connect(func(n: int) -> void: log.append(["node_entered", n]))
	return log


func _unwatch(view: Node, _log: Array) -> void:
	for sig in [view.departed, view.arrived, view.node_entered]:
		for c in sig.get_connections():
			sig.disconnect(c["callable"])


func _first(log: Array, what: String) -> int:
	for row in log:
		if String(row[0]) == what:
			return int(row[1])
	return -1


func _count(log: Array, what: String) -> int:
	var n := 0
	for row in log:
		if String(row[0]) == what:
			n += 1
	return n


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
