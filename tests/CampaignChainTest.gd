extends Node
## X1 step 4 — the world map stops being terminal, and the walk loops.
##
## The `world_map` action was terminal by design (ADR-0117 dec. 8): the map reported a node
## and nothing consumed it. Making it chain needs no state-machine change at all, and this
## test pins the two facts that make that true:
##
## 1. `plan_actions(root, root)` for a group whose successor is `world-map` yields that
##    group's actions **plus a fresh `world_map` action** — so each hop hands back a map.
## 2. `NavigatorRunner._advance` re-reads `_actions.size()`, so appending at the tail turns
##    a walk that was about to finish into one that continues.
##
## Together those are the loop. Break either and the walk either stops at the map (what it
## did before) or runs a group and stops (what a naive append would do).
##
## Run: <GODOT> --path . --quit-after 10 res://tests/CampaignChainTest.tscn

var _passed := 0
var _failed := 0


class FakeExecutor:
	var calls: Array = []
	var runner: NavigatorRunner = null
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
	_test_first_hop_resolves_end_to_end()
	_test_group_13_plan_ends_in_a_fresh_world_map()
	_test_appending_makes_the_map_non_terminal()
	_test_every_world_map_group_hands_back_a_map()

	if _failed > 0:
		print("[FAIL] CampaignChainTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] CampaignChainTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


## Place 7 (Gariland) at story 1, all the way to a group root — every link the runtime
## handler walks, with no scene mounted.
func _test_first_hop_resolves_end_to_end() -> void:
	var keep := Campaign.progress.story_counter()
	Campaign.progress.set_story_counter(1)

	var emit := Campaign.enter_at(Campaign.place_to_index(7))
	_eq("place 7 -> scenario", int(emit.get("scenario_id", -1)), 13)
	_eq("place 7 -> transition mode", int(emit.get("transition_mode", -1)), 2)
	_eq("scenario 13 -> group root",
		ScenarioGroupDatabase.root_for_scenario(int(emit.get("scenario_id", -1))), 13)

	Campaign.progress.set_story_counter(keep)


## `[scenario(13), world_map(13)]` — the shape the whole chain rests on.
##
## Node 13 is `cinematic_latch` (BC -> 14); node 14 is `exit_worldmap`, whose successor
## edge target is the STRING "WORLD_MAP", so `_successor_target` returns -1, `next_root`
## is <= 0, and the planner falls through to the `world-map` successor branch.
func _test_group_13_plan_ends_in_a_fresh_world_map() -> void:
	var actions := GameNavigator.new().plan_actions(13, 13)
	_eq("group 13 plans 2 actions", actions.size(), 2)
	if actions.size() != 2:
		return
	_eq("first is the scenario group", String(actions[0].get("kind", "")), "scenario")
	_eq("...rooted at 13", int(actions[0].get("root", -1)), 13)
	_eq("...carrying both members", int(actions[0].get("beats", []).size()), 2)
	_eq("second is a world map", String(actions[1].get("kind", "")), "world_map")
	_eq("...rooted at 13", int(actions[1].get("root", -1)), 13)


## The mechanism, driven: a runner sitting on a terminal `world_map` action finishes the
## walk; the same runner, with a sub-plan appended first, steps into it instead.
func _test_appending_makes_the_map_non_terminal() -> void:
	# Arm A — nothing appended. The map is the last action, so the walk ends.
	var exec_a := FakeExecutor.new()
	var runner_a := NavigatorRunner.new([{"kind": "world_map", "root": 9}], exec_a)
	var finished_a := [false]
	runner_a.walk_finished.connect(func() -> void: finished_a[0] = true)
	runner_a.begin()
	runner_a.on_world_map_finished()
	_true("without an append the walk finishes at the map", finished_a[0])
	_eq("...having dispatched only the map", exec_a.calls.size(), 1)

	# Arm B — the same runner, with group 13's sub-plan appended while the map is up.
	var exec_b := FakeExecutor.new()
	var runner_b := NavigatorRunner.new([{"kind": "world_map", "root": 9}], exec_b)
	var finished_b := [false]
	runner_b.walk_finished.connect(func() -> void: finished_b[0] = true)
	runner_b.begin()
	runner_b._actions.append_array(GameNavigator.new().plan_actions(13, 13))
	runner_b.on_world_map_finished()
	_true("with an append the walk does NOT finish", not finished_b[0])
	_eq("...it advanced into the appended group", exec_b.calls.size(), 2)
	_eq("...which is scenario 13",
		String(exec_b.calls[1].get("m", "")) + ":" + str(exec_b.calls[1].get("root", -1)),
		"scenario:13")

	# ...and the hop after that is a map again, so the loop is closed rather than
	# one-shot. This is the arm that would have caught "append works, chain doesn't".
	runner_b.on_scenario_finished()
	_eq("the next action is another world map", exec_b.calls.size(), 3)
	_eq("...rooted at 13",
		String(exec_b.calls[2].get("m", "")) + ":" + str(exec_b.calls[2].get("root", -1)),
		"world_map:13")


## The property in general, not just for group 13: EVERY group whose successor is
## `world-map` must end its own plan with a `world_map` action, or a hop into it would be
## a dead end. 97 groups carry that successor.
func _test_every_world_map_group_hands_back_a_map() -> void:
	var nav := GameNavigator.new()
	var checked := 0
	var dead_ends: Array[int] = []
	for g in ScenarioGroupDatabase.all_groups():
		if String(g.get("successor", "")) != "world-map":
			continue
		var root := int(g.get("group_root_id", -1))
		var actions := nav.plan_actions(root, root)
		checked += 1
		if actions.is_empty() or String(actions[actions.size() - 1].get("kind", "")) != "world_map":
			dead_ends.append(root)
	_true("checked every world-map group", checked >= 90)
	_eq("no world-map group is a dead end", dead_ends.size(), 0)
	if dead_ends.size() > 0:
		print("    dead ends: %s" % str(dead_ends.slice(0, 10)))


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
