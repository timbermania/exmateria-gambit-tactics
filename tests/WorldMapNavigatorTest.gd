extends Node
## Crossing C2 — entering the world map from the story walk.
##
## `GameState.State.WORLD_MAP` has been in the spine enum since it was written, and
## before this every reference to it was inside `GameState.gd`: nothing implemented the
## state. What was missing was not the scene but the EDGE. 110 of the graph's successor
## edges name a sink rather than an int scenario id — 97 `WORLD_MAP`, 13 `RESET` — and
## `_next_root` ran `int(target)` over them. GDScript reads a non-numeric String as 0,
## the caller reads 0 as "no successor", and the walk ended silently.
##
## The very first story walk hits one: 1 -> 3 -> 7 -> 9, and group 9 (Gariland) exits to
## `WORLD_MAP`. NavigatorMain logged exactly that — *"Walk finished at group 9 (world map
## OOS)"*.
##
## The first three tests below hardcode their bounds — `plan_actions(1, 9)` stops,
## `plan_actions(1, 0)` reaches the map — and BOTH are right. The walk a player actually
## boots is neither: it is whatever `NavigatorMain`'s own constants ask for, and for a
## while that was the truncated arm. `_test_shipped_default_walk_reaches_the_world_map`
## is the arm that reads those constants instead of restating them (§17).
##
## Run: <GODOT> --path . --quit-after 6 res://tests/WorldMapNavigatorTest.tscn

var _passed := 0
var _failed := 0


class FakeExecutor:
	var calls: Array = []
	func play_scenario(root: int, beats: Array, terminal: bool) -> void:
		calls.append({"m": "scenario", "root": root, "beats": beats.size(), "terminal": terminal})
	func play_beat(beat: Dictionary) -> void:
		calls.append({"m": "beat", "scn": int(beat.get("scenario_id", -1))})
	func run_pre_battle(root: int) -> void:
		calls.append({"m": "pre_battle", "root": root})
	func run_formation_view(root: int) -> void:
		calls.append({"m": "formation_view", "root": root})
	func run_combat(root: int) -> void:
		calls.append({"m": "combat", "root": root})
	func run_world_map(root: int) -> void:
		calls.append({"m": "world_map", "root": root})


func _ready() -> void:
	_test_successor_kind()
	_test_natural_end_reaches_the_world_map()
	_test_stop_root_walk_is_unchanged()
	_test_shipped_default_walk_reaches_the_world_map()
	_test_runner_dispatch()

	if _failed > 0:
		print("[FAIL] WorldMapNavigatorTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] WorldMapNavigatorTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## The sink read off the graph must agree with the group database's own `exit` field, on
## every linear group — two files written by two different tools. 83 groups, zero
## disagreements, which is what makes `successor_kind` a reading rather than a convention.
func _test_successor_kind() -> void:
	var nav := GameNavigator.new()
	_eq("group 9 (Gariland) exits to the world map", nav.successor_kind(9), "WORLD_MAP")
	_eq("group 1 chains onward, so no sink", nav.successor_kind(1), "")
	var disagreed := 0
	var world_map_groups := 0
	for g in ScenarioGroupDatabase.all_groups():
		var root := int(g.get("group_root_id", -1))
		if root < 0:
			continue
		var by_db := String(g.get("successor", "")) == "world-map"
		var by_graph := nav.successor_kind(root) == GameNavigator.SUCCESSOR_WORLD_MAP
		if by_db:
			world_map_groups += 1
		# Battle groups exit from their VICTORY beat, which is not a group member, so the
		# group database's `exit` describes a different edge for them. Linear groups only.
		if by_db != by_graph and not _is_battle_group(g):
			disagreed += 1
	_true("94 groups carry a `world-map` successor", world_map_groups >= 90)
	_eq("graph sink and group-db exit never disagree on a linear group", disagreed, 0)


func _is_battle_group(g: Dictionary) -> bool:
	for m in g.get("members", []):
		if String(m.get("role", "")) == "opener":
			return true
	return int(g.get("battle_conditionals_id", 0)) != 0


## The natural-end walk (stop_root <= 0) now ends ON the world map instead of one step
## short of it.
func _test_natural_end_reaches_the_world_map() -> void:
	var actions := GameNavigator.new().plan_actions(1, 0)
	if actions.is_empty():
		_fail("natural-end walk planned no actions")
		return
	var last: Dictionary = actions[actions.size() - 1]
	_eq("the walk ends with a world_map action", String(last.get("kind", "")), "world_map")
	_eq("it is the Gariland group's exit", int(last.get("root", -1)), 9)
	_eq("and it is terminal — X1 turns a node into the next scenario",
			bool(last.get("terminal", false)), true)
	# Exactly one: a sink ends the walk, it does not loop.
	var n := 0
	for a in actions:
		if String(a.get("kind", "")) == "world_map":
			n += 1
	_eq("exactly one world_map action", n, 1)


## The proof walk stops AT group 9 by its own stop-root branch, before any successor is
## considered — so it must be byte-identical to what it was. This is the arm that says
## the change is additive rather than a re-route.
func _test_stop_root_walk_is_unchanged() -> void:
	var actions := GameNavigator.new().plan_actions(1, 9)
	_eq("1->9 still plans 10 actions", actions.size(), 10)
	for a in actions:
		if String(a.get("kind", "")) == "world_map":
			_fail("1->9 must not gain a world_map action")
			return
	_eq("1->9 still ends on the victory beat",
			String(actions[actions.size() - 1].get("kind", "")), "victory")


## The arm the other three could not catch: what the SHIPPED cold boot plans.
##
## `_test_stop_root_walk_is_unchanged` hardcodes `plan_actions(1, 9)` and
## `_test_natural_end_reaches_the_world_map` hardcodes `plan_actions(1, 0)`. Both are
## true, and BETWEEN them sits the only walk a player ever runs — the one
## [NavigatorMain] plans from its OWN constants when you boot `NavigatorMain.tscn` with
## no seek. Nothing read those constants, so `STOP_ROOT := 9` truncated the walk one
## action short of the map while all three arms stayed green.
##
## So this reads `START_ROOT`/`STOP_ROOT` off the script rather than restating them: a
## constant that moves moves this guard with it, which is the whole point.
func _test_shipped_default_walk_reaches_the_world_map() -> void:
	var nav_script: GDScript = load("res://src/scenarios/NavigatorMain.gd")
	var consts: Dictionary = nav_script.get_script_constant_map()
	_true("NavigatorMain exposes START_ROOT", consts.has("START_ROOT"))
	_true("NavigatorMain exposes STOP_ROOT", consts.has("STOP_ROOT"))
	if not (consts.has("START_ROOT") and consts.has("STOP_ROOT")):
		return
	var start_root := int(consts["START_ROOT"])
	var stop_root := int(consts["STOP_ROOT"])
	var actions := GameNavigator.new().plan_actions(start_root, stop_root)
	if actions.is_empty():
		_fail("the shipped default walk planned no actions")
		return
	var last: Dictionary = actions[actions.size() - 1]
	_eq("the shipped default walk (%d -> %d) ends on the world map" % [start_root, stop_root],
			String(last.get("kind", "")), "world_map")
	_eq("and it is Gariland's exit that lands there", int(last.get("root", -1)), 9)
	_eq("the walk plays Gariland in full first — victory is the action before it",
			String(actions[actions.size() - 2].get("kind", "")), "victory")
	_eq("11 actions: the 10 of the Gariland proof, plus the map", actions.size(), 11)


func _test_runner_dispatch() -> void:
	var exec := FakeExecutor.new()
	var actions: Array = [{"kind": "world_map", "root": 9, "terminal": true, "mutations": []}]
	var runner := NavigatorRunner.new(actions, exec)
	var finished := [false]
	runner.walk_finished.connect(func() -> void: finished[0] = true)
	runner.begin()
	_eq("the executor is asked to mount the screen", exec.calls, [{"m": "world_map", "root": 9}])
	_eq("the navigator is in the WORLD_MAP state", runner.current_state,
			GameState.State.WORLD_MAP)
	_eq("walk not finished while the screen is up", finished[0], false)
	runner.on_world_map_finished()
	_eq("dismissing the screen finishes the walk", finished[0], true)


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
