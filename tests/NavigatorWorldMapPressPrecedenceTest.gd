extends Node
## The reported bug — [i]"move the cursor to Mandalia Plains, press ○, and the scenario
## plays INSTANTLY instead of walking the marker there"[/i] — driven end to end through
## the real [code]NavigatorMain[/code], with a real ○ press, at both story counters.
##
## [b]It is not a bug, and this is the arm that says so.[/b] `WORLD_MAP_SCREEN.md` §29.3
## decompiles `FUN_8008E2BC` as testing the node the MARKER stands on, never the node under
## the cursor:
##
## [codeblock]
## if (FUN_80091238(*(u32*)0x8009F254, 0x08)) {   // 0x8009F254 is the MARKER's node
##     ... hand off ...
##     return 0;                                  // the pathfinder is never reached
## }
## [/codeblock]
##
## At story 1 the marker is on Gariland and Gariland is the one node with a live `enter`
## (Balbanes's Death is Gariland-hosted), so ○ fires GARILAND'S scenario wherever the
## cursor is. At story 2 the live `enter` has moved to Mandalia while the marker is still
## on Gariland, arm 1 falls through, and the very same press walks. The story-1 shape is
## one of only six such beats in the whole spine — 33 of 38 consecutive story hops move to
## a different node and therefore walk.
##
## [b]What no existing test covered.[/b] [WorldMapSecondHopTest] drives the walk, but
## through [method WorldMapScene.enter_place] — the autoplay API — on the standalone map,
## so the [b]press[/b] path ([code]_confirm[/code] → [member WorldMapCursor.hit_node] →
## [code]_enter_node[/code]) was never exercised with the cursor on a node that is NOT the
## marker's, which is precisely what the report describes.
## [NavigatorWorldMapChainTest] mounts NavigatorMain but runs on autoplay with no input at
## all. So the one thing the user did — hover elsewhere, press ○ — had no coverage, and
## neither did the pair "story 1 is instant AND story 2 walks", which is what makes the
## instant arm correct rather than broken.
##
## Arm 1 carries a DIRECTION seed: with the hand-off set emptied, the identical press at
## the identical story counter plans a walk to Mandalia instead. That is the pre-§29.3
## behaviour the port shipped before `a5de03641`, and it is what makes the assertions below
## load-bearing rather than incidental.
##
## HEADFUL — run standalone:
##   godot --path . --quit-after 6000 res://tests/NavigatorWorldMapPressPrecedenceTest.tscn

const TIMEOUT_MS := 60000

## Gariland Magic City — node index 6. Where the campaign opens, and where the marker
## stands at BOTH story counters this drives.
const GARILAND := 7
## Mandalia Plains — node index 24. Where the user put the cursor, and the story-2
## hand-off.
const MANDALIA := 25

var _passed := 0
var _failed := 0
var _nav: Node = null
var _start_ms := 0


func _ready() -> void:
	await _story_1_the_press_ignores_the_cursor()
	await _story_2_the_same_press_walks()

	if _failed > 0:
		print("[FAIL] NavigatorWorldMapPressPrecedenceTest — %d/%d"
				% [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] NavigatorWorldMapPressPrecedenceTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## §29.3's arm, in the scene the report was filed against. The cursor is on Mandalia; the
## marker is on Gariland; ○ fires Gariland.
func _story_1_the_press_ignores_the_cursor() -> void:
	var view := await _mount_at_story(1)
	if view == null:
		return
	var p: WorldMapProgress = view.progress

	_eq("the campaign is at story counter 1", Campaign.story_counter(), 1)
	_eq("exactly one node offers a hand-off", Campaign.live_enter_nodes().size(), 1)
	_eq("the map was handed Gariland as the hand-off place",
			str(view._hand_off_places.keys()), str([GARILAND]))
	_eq("the marker stands on Gariland", p.party_node(), GARILAND)

	_park_cursor_on(view, MANDALIA)
	_eq("the cursor is over Mandalia Plains", view._cursor.hit_node, MANDALIA)
	# Without this the two assertions below could both hold for the wrong reason.
	_true("...which is NOT the node the marker is standing on", MANDALIA != GARILAND)

	# DIRECTION. Empty the hand-off set and the identical press plans a walk — the exact
	# pre-§29.3 behaviour ("○ on Mandalia at story 1 planned a walk, arrived, found no
	# hand-off THERE, and did nothing"). If this seed does not depart, the real press
	# below proves nothing about the precedence.
	view.set_hand_off_places([])
	var seed := _watch(view)
	await _press(view)
	_true("SEED: with no hand-off registered the same press plans a walk",
			is_instance_valid(view) and view._travel != null)
	_eq("SEED: ...and it departs for the node under the CURSOR",
			_first(seed["log"], "departed"), MANDALIA)
	_unwatch(view, seed)
	# Abort the seed walk before the marker gets anywhere and restore the real state.
	view._travel = null
	p.set_party_node(GARILAND)
	view.set_hand_off_places(_live_places())

	var w := _watch(view)
	var actions_before: int = _nav._nav_runner._actions.size()
	await _press(view)

	_true("the press planned NO walk — the pathfinder is never reached",
			(not is_instance_valid(view)) or view._travel == null)
	_eq("nothing departed", _first(w["log"], "departed"), -1)
	_eq("it entered the MARKER's node, not the cursor's",
			_first(w["log"], "node_entered"), GARILAND)
	_eq("...exactly once", _count(w["log"], "node_entered"), 1)
	_eq("the marker never moved", p.party_node(), GARILAND)

	await _wait_until(func() -> bool:
		return _nav._nav_runner._actions.size() > actions_before)
	var appended: Array = _nav._nav_runner._actions.slice(actions_before)
	_true("NavigatorMain appended the hand-off's group", appended.size() > 0)
	_eq("...and it is group 13, Balbanes's Death — Gariland's scenario, not Mandalia's",
			_roots_of(appended)[0] if appended.size() > 0 else -1, 13)
	await _teardown()


## The other half, and the reason the first is not a defect: at story 2 the live `enter`
## has moved off the marker's node, so the SAME press on the SAME cursor position walks.
func _story_2_the_same_press_walks() -> void:
	var view := await _mount_at_story(2)
	if view == null:
		return
	var p: WorldMapProgress = view.progress

	_eq("the campaign is at story counter 2", Campaign.story_counter(), 2)
	_eq("the hand-off moved to Mandalia Plains",
			str(view._hand_off_places.keys()), str([MANDALIA]))
	_eq("the marker is still on Gariland", p.party_node(), GARILAND)

	_park_cursor_on(view, MANDALIA)
	_eq("the cursor is over Mandalia Plains", view._cursor.hit_node, MANDALIA)

	var w := _watch(view)
	var actions_before: int = _nav._nav_runner._actions.size()
	var start_pos: Vector2i = Vector2i.ZERO
	await _press(view)

	_true("the identical press now plans a walk", view._travel != null)
	if view._travel == null:
		await _teardown()
		return
	start_pos = view._travel.position
	_eq("it departed for Mandalia", _first(w["log"], "departed"), MANDALIA)
	_eq("nothing has fired yet — the event is on ARRIVAL",
			_first(w["log"], "node_entered"), -1)
	_eq("§29.6's recording: five legs", view._travel.legs.size(), 5)
	_eq("...and 45 vsyncs", view._travel.total_ticks(), 45)

	# The sprite MOVES. A walk that teleported would satisfy every signal assertion here
	# and be exactly the thing the report was about.
	#
	# Written as a plain loop on purpose: GDScript lambdas capture by VALUE, so a flag set
	# inside one never reaches the caller, and a lambda holding `view` dies outright the
	# frame the map is freed ("Lambda capture at index 0 was freed").
	var moved_mid_walk := false
	var frames := 0
	while is_instance_valid(view) and view._travel != null and frames < 2400:
		await get_tree().process_frame
		frames += 1
		if is_instance_valid(view) and view._travel != null \
				and view._travel.position != start_pos:
			moved_mid_walk = true
	_true("...and the marker was between the two nodes while it ran", moved_mid_walk)

	_eq("it arrived at Mandalia", _first(w["log"], "arrived"), MANDALIA)
	_eq("the scenario fired on arrival, with no second press",
			_first(w["log"], "node_entered"), MANDALIA)
	_eq("the party is standing on Mandalia now", p.party_node(), MANDALIA)

	await _wait_until(func() -> bool:
		return _nav._nav_runner._actions.size() > actions_before)
	var appended: Array = _nav._nav_runner._actions.slice(actions_before)
	_true("NavigatorMain appended Mandalia's group", appended.size() > 0)
	# The FIRST root, not the only one: `plan_actions` chains past the group it is given
	# (15 is a battle, so it expands to opener/pre_battle/combat/victory and then runs on
	# into group 24 and a fresh `world_map`). The claim under test is which group the
	# hand-off DISPATCHED, which is the head of that chain.
	_eq("...and it is group 15, Mandalia Plains",
			_roots_of(appended)[0] if appended.size() > 0 else -1, 15)
	await _teardown()


# ------------------------------------------------------------------ plumbing

## Seat the campaign, mount the shipped NavigatorMain seeking straight to its `world_map`
## action, and hand back the mounted map once the screen-in has released input. Story 2 is
## the state the port reaches by playing Balbanes's Death, whose bytecode tail writes
## `Zero(110); Add(110, 2)` — seated directly here so this test does not fight a battle.
func _mount_at_story(story: int) -> Node:
	Campaign.progress.set_story_counter(story)
	Campaign.progress.set_party_node(GARILAND)

	var nav_script: GDScript = load("res://src/scenarios/NavigatorMain.gd")
	var consts: Dictionary = nav_script.get_script_constant_map()
	var start_root := int(consts.get("START_ROOT", 1))
	var stop_root := int(consts.get("STOP_ROOT", 0))
	var plan := GameNavigator.new().plan_actions(start_root, stop_root,
			StoryMutationScript.build())
	var idx := -1
	for i in range(plan.size()):
		if String(plan[i].get("kind", "")) == "world_map":
			idx = i
			break
	_true("story %d: the shipped walk plans a world_map action" % story, idx >= 0)
	if idx < 0:
		return null
	ScenarioDebugSession.navigator_start_root = start_root
	ScenarioDebugSession.navigator_stop_root = stop_root
	ScenarioDebugSession.navigator_start_action = idx

	_start_ms = Time.get_ticks_msec()
	_nav = load("res://assets/scenes/NavigatorMain.tscn").instantiate()
	add_child(_nav)

	var view: Node = null
	while view == null and (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		await get_tree().process_frame
		view = _find_world_map()
	_true("story %d: the navigator mounted the world map" % story, view != null)
	if view == null:
		return null
	if view.assets == null or not view.assets.loaded:
		# Regenerable and gitignored — a missing asset is not a failing assertion.
		print("[SKIP] NavigatorWorldMapPressPrecedenceTest — run tools/parse_world_map.py")
		get_tree().quit(0)
		return null
	# ADR-0161: `_unhandled_input` returns early for the whole of the screen-in, and the
	# gate is `screen_in_active()` — NOT `_input_enabled`, which defaults true and is only
	# lowered by a SUSPEND. Polling the flag instead returns on frame 0, the press lands in
	# the black, and every assertion below reads as "the press did nothing".
	await _wait_until(func() -> bool:
		return is_instance_valid(view) and not view.screen_in_active())
	_true("story %d: the screen-in finished and the map listens" % story,
			not view.screen_in_active())
	return view


func _teardown() -> void:
	if _nav != null and is_instance_valid(_nav):
		_nav.queue_free()
	_nav = null
	await get_tree().process_frame
	await get_tree().process_frame


## The hand-off set exactly as `NavigatorMain.run_world_map` computes it — node INDEX from
## Campaign, place number to the map.
func _live_places() -> Array[int]:
	var places: Array[int] = []
	for index in Campaign.live_enter_nodes():
		places.append(index + 1)
	return places


## "Move the cursor to Mandalia Plains" — park it where the analog walk would leave it, on
## the node's own hit box, and let the cursor's own hit test name the node.
func _park_cursor_on(view: Node, place: int) -> void:
	var n: Dictionary = view.assets.node(place - 1)
	view._cursor.place(WorldMapCursor.rest_at(
			Vector2i(int(n["screen"][0]), int(n["screen"][1]))))
	view._cursor.resolve(view.assets, view.progress)


## One ○, through the real `_unhandled_input` path — not `enter_place`, which is the
## autoplay API every other test uses and which cannot express "the cursor was elsewhere".
func _press(view: Node) -> void:
	var down := InputEventAction.new()
	down.action = &"cursor_confirm"
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = &"cursor_confirm"
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _wait_until(cond: Callable) -> void:
	while (Time.get_ticks_msec() - _start_ms) < TIMEOUT_MS:
		if bool(cond.call()):
			return
		await get_tree().process_frame


## A signal log that disconnects only ITS OWN callables.
##
## [b]The blunt version is a trap here and nowhere else.[/b] [WorldMapSecondHopTest] can
## sweep `get_connections()` because it mounts the bare map with nothing else listening.
## This test mounts the real NavigatorMain, whose [signal WorldMapScene.node_entered]
## subscriber IS the hand-off — sweeping the signal would silently unhook production
## wiring mid-test and every later "NavigatorMain appended…" assertion would fail for a
## reason that has nothing to do with the map.
func _watch(view: Node) -> Dictionary:
	var log: Array = []
	var mine: Array = []
	for sig_name in ["departed", "arrived", "node_entered"]:
		var cb := func(n: int) -> void: log.append([sig_name, n])
		view.connect(sig_name, cb)
		mine.append([sig_name, cb])
	return {"log": log, "mine": mine}


func _unwatch(view: Node, w: Dictionary) -> void:
	if not is_instance_valid(view):
		return
	for row in w.get("mine", []):
		if view.is_connected(String(row[0]), row[1]):
			view.disconnect(String(row[0]), row[1])


## Every distinct group root among a slice of planned actions, in order — `[0]` being the
## group the walk was dispatched INTO. Not `actions[0]["root"]`: a battle group leads with
## an `opener` beat, and `opener`/`victory` carry no root at all, so the first action's
## root reads `-1` for exactly the groups that matter most.
func _roots_of(actions: Array) -> Array[int]:
	var out: Array[int] = []
	for a in actions:
		var r := int(a.get("root", -1))
		if r >= 0 and not out.has(r):
			out.append(r)
	return out


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


## The mounted map lives in the CanvasLayer `run_world_map` builds, not in the scene tree
## `NavigatorMain.tscn` ships — the same probe [NavigatorWorldMapChainTest] uses.
func _find_world_map() -> Node:
	if _nav == null or not is_instance_valid(_nav):
		return null
	for child in _nav.get_children():
		if not (child is CanvasLayer):
			continue
		for gc in child.get_children():
			if gc.has_signal("dismissed") and "_standalone" in gc:
				return gc
	return null
