extends Node
## Pure-logic guard (no scene/VM/GPU) for [GameNavigator] — the headless story-graph
## walk planner. Mirrors the [ScenarioPath] planner style: it reads the real
## transition_graph.json + scenario_groups.json artifacts and emits the ordered beat
## sequence the runtime navigator drives, with NO rendering.
##
## Covers the Orbonne opening milestone (HANDOFF_navigator_run_1to7.md §1): the walk
## group 1 -> group 3 (battle, beats 4/6) -> group 7, and the two building blocks it
## composes — one linear group's member beats and one battle group's setup/opener/
## victory beats (mid beat skipped for v1).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/GameNavigatorTest.tscn

const GS := preload("res://src/scenarios/GameState.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_linear_group_beats()
	_test_battle_group_beats()
	_test_full_walk_1_to_7()
	_test_plan_actions()
	_test_plan_actions_1_to_9_plays_through_gariland()
	_test_formation_view_gated_off_by_default()
	_test_formation_view_inserted_between_opener_and_pre_battle()
	_test_plan_battle_group_is_one_group()
	_test_battle_entry_index()

	print("\n=== GameNavigatorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] GameNavigatorTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] GameNavigatorTest")
		get_tree().quit(1)
	else:
		print("[PASS] GameNavigatorTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


## Assert a beat Array matches an expected list of [scenario_id, state] pairs.
func _assert_beats(beats: Array, want: Array, name: String) -> void:
	_eq(beats.size(), want.size(), "%s: beat count" % name)
	var n: int = min(beats.size(), want.size())
	for i in n:
		var b: Dictionary = beats[i]
		_eq(int(b.get("scenario_id", -1)), want[i][0], "%s[%d].scenario_id" % [name, i])
		_eq(int(b.get("state", -99)), want[i][1], "%s[%d].state" % [name, i])


# --- Slice 1: one linear (non-battle) group emits a SCENARIO beat per member ---
func _test_linear_group_beats() -> void:
	var nav := GameNavigator.new()
	# Group 1 (Chapel of Orbonne): members 1 (setup) + 2 (member), both cinematic
	# nodes -> SCENARIO state.
	var beats := nav.beats_for_group(1)
	_assert_beats(beats, [
		[1, GS.State.SCENARIO],
		[2, GS.State.SCENARIO],
	], "group1 linear beats")


# --- Slice 2: a battle group weaves setup + opener + victory (mid beat skipped) ---
func _test_battle_group_beats() -> void:
	var nav := GameNavigator.new()
	# Group 3 (Orbonne battle): setup node 3 (battle) + BC beats 4 (opener, Var509),
	# 5 (mid — SKIPPED for v1), 6 (victory, Victory()). All BATTLE state.
	var beats := nav.beats_for_group(3)
	_assert_beats(beats, [
		[3, GS.State.BATTLE],
		[4, GS.State.BATTLE],
		[6, GS.State.BATTLE],
	], "group3 battle beats")
	# Roles are synthesized for the battle weave.
	_eq(String(beats[0].get("role", "")), "setup", "group3 beat0 role=setup")
	_eq(String(beats[1].get("role", "")), "opener", "group3 beat1 role=opener")
	_eq(String(beats[2].get("role", "")), "victory", "group3 beat2 role=victory")
	# The mid beat (scn 5) is deliberately absent.
	for b in beats:
		_true(int(b.get("scenario_id", -1)) != 5, "group3 skips mid beat scn5")


# --- Slice 3: the milestone walk group 1 -> 3 (battle) -> 7, then STOP (HANDOFF §1) ---
func _test_full_walk_1_to_7() -> void:
	var nav := GameNavigator.new()
	# grp1 (linear, ATTACK->3) -> grp3 (battle: setup/opener/victory, victory node 6
	# ATTACK->7) -> grp7 root scenario 7 entered as SCENARIO, then halt.
	var beats := nav.plan_walk(1, 7)
	_assert_beats(beats, [
		[1, GS.State.SCENARIO],   # grp1 setup
		[2, GS.State.SCENARIO],   # grp1 member (prayer)
		[3, GS.State.BATTLE],     # grp3 battle setup
		[4, GS.State.BATTLE],     # opener beat
		[6, GS.State.BATTLE],     # victory beat
		[7, GS.State.SCENARIO],   # grp7 entered — STOP
	], "walk 1->3->7")


# --- Slice 4: the DRIVER action plan — coarse steps the runtime navigator drives ---
# (SCENARIO group, then a battle's opener -> combat -> victory, then the stop group.)
func _test_plan_actions() -> void:
	var nav := GameNavigator.new()
	var actions := nav.plan_actions(1, 7)
	_eq(actions.size(), 6, "action count")
	if actions.size() != 6:
		return
	# grp1: play the whole scenario group (members 1,2), then yield.
	_eq(String(actions[0].get("kind", "")), "scenario", "action0 kind=scenario")
	_eq(int(actions[0].get("root", -1)), 1, "action0 root=1")
	_eq(actions[0].get("beats", []).size(), 2, "action0 has 2 beats")
	# grp3 battle: opener (scn4) -> PRE_BATTLE -> combat -> victory (scn6).
	_eq(String(actions[1].get("kind", "")), "opener", "action1 kind=opener")
	_eq(int(actions[1].get("beat", {}).get("scenario_id", -1)), 4, "action1 opener=scn4")
	_eq(String(actions[2].get("kind", "")), "pre_battle", "action2 kind=pre_battle (before combat)")
	_eq(int(actions[2].get("root", -1)), 3, "action2 pre_battle root=3")
	_eq(String(actions[3].get("kind", "")), "combat", "action3 kind=combat")
	_eq(int(actions[3].get("root", -1)), 3, "action3 combat root=3 (ENTD 387)")
	_eq(String(actions[4].get("kind", "")), "victory", "action4 kind=victory")
	_eq(int(actions[4].get("beat", {}).get("scenario_id", -1)), 6, "action4 victory=scn6")
	# grp7: the terminal scenario group — enter and STOP.
	_eq(String(actions[5].get("kind", "")), "scenario", "action5 kind=scenario")
	_eq(int(actions[5].get("root", -1)), 7, "action5 root=7")
	_true(bool(actions[5].get("terminal", false)), "action5 is terminal")


# --- Slice 5: extend the walk PAST Military Academy — play into group 7 (scn 8) and
# then PLAY THROUGH Gariland (group 9, the first roster-fed battle). Group 7 is a pure
# cinematic (setup 7 -> latch -> scn 8 -> ATTACK 9), so it plays as ONE scenario action
# (no combat). Group 9 is a BATTLE stop-root: instead of an enter-and-halt terminal, it
# EXPANDS to the full opener -> pre_battle -> combat -> victory weave (wayfinder #234 A),
# then the walk ends (no chain past the stop root). The victory beat (scn 12) is the
# clean endpoint (#234 F).
func _test_plan_actions_1_to_9_plays_through_gariland() -> void:
	var nav := GameNavigator.new()
	var actions := nav.plan_actions(1, 9)
	_eq(actions.size(), 10, "1->9 action count (grp9 expands, not a terminal scenario)")
	if actions.size() != 10:
		return
	# actions 0..4 = the grp1 + grp3 (Orbonne) battle steps.
	# grp7 (Military Academy): NOT a battle — one scenario action that PLAYS setup 7 + scn 8.
	_eq(String(actions[5].get("kind", "")), "scenario", "action5 kind=scenario (grp7 plays)")
	_eq(int(actions[5].get("root", -1)), 7, "action5 root=7")
	_true(not bool(actions[5].get("terminal", false)), "action5 is NOT terminal (it plays)")
	var g7_ids: Array = []
	for b in actions[5].get("beats", []):
		g7_ids.append(int(b.get("scenario_id", -1)))
	_true(g7_ids.has(8), "grp7 plays the Military Academy cinematic (scn 8)")
	# grp9 (Gariland) expands as a battle: opener(10) -> pre_battle(9) -> combat(9) -> victory(12).
	_eq(String(actions[6].get("kind", "")), "opener", "action6 kind=opener (Gariland opener)")
	_eq(int(actions[6].get("beat", {}).get("scenario_id", -1)), 10, "action6 opener=scn10")
	_eq(String(actions[7].get("kind", "")), "pre_battle", "action7 kind=pre_battle")
	_eq(int(actions[7].get("root", -1)), 9, "action7 pre_battle root=9")
	_eq(String(actions[8].get("kind", "")), "combat", "action8 kind=combat (Gariland ENTD 388)")
	_eq(int(actions[8].get("root", -1)), 9, "action8 combat root=9")
	_eq(String(actions[9].get("kind", "")), "victory", "action9 kind=victory (clean endpoint)")
	_eq(int(actions[9].get("beat", {}).get("scenario_id", -1)), 12, "action9 victory=scn12")
	# No terminal scenario for grp9 — the walk simply ends after the victory beat.
	for a in actions:
		if String(a.get("kind", "")) == "scenario" and int(a.get("root", -1)) == 9:
			_true(false, "grp9 must NOT appear as a scenario action")


# --- Slice E1: the formation view is debug-gated OFF — the proof plan omits it ---
func _test_formation_view_gated_off_by_default() -> void:
	var nav := GameNavigator.new()
	var actions := nav.plan_actions(1, 9)  # show_formation defaults false
	for a in actions:
		_true(String(a.get("kind", "")) != "formation_view", "no formation_view action by default")


# --- Slice E1b: with the flag set, a formation_view node inserts between opener + pre_battle ---
func _test_formation_view_inserted_between_opener_and_pre_battle() -> void:
	var nav := GameNavigator.new()
	var actions := nav.plan_actions(1, 9, null, true)  # show_formation = true
	# For the Gariland battle group: opener(10) → formation_view(9) → pre_battle(9).
	var i := -1
	for n in range(actions.size()):
		var a: Dictionary = actions[n]
		if String(a.get("kind", "")) == "opener" and int(a.get("beat", {}).get("scenario_id", -1)) == 10:
			i = n
			break
	_true(i >= 0, "found the Gariland opener (scn10)")
	if i < 0 or i + 2 >= actions.size():
		return
	_eq(String(actions[i + 1].get("kind", "")), "formation_view", "formation_view follows the opener")
	_eq(int(actions[i + 1].get("root", -1)), 9, "formation_view root=9")
	_eq(String(actions[i + 2].get("kind", "")), "pre_battle", "pre_battle follows the formation_view")


# --- ADR-0264: "play battle N" plans ONE battle group, and enters it at pre_battle ---

## `plan_battle_group` stops where `plan_actions(root, root)` does not. The stop test in
## the chaining planner is `root == stop_root and not actions.is_empty()`, and on the first
## iteration `actions` IS empty — so start == stop chains onward like any other walk. The
## first arm is that fact, asserted rather than assumed: it is the whole reason the second
## entry point exists, and a future simplification that "obviously" collapses the two would
## silently give every launched battle the rest of the story after it.
func _test_plan_battle_group_is_one_group() -> void:
	var nav := GameNavigator.new()
	var chained := nav.plan_actions(9, 9)
	_true(chained.size() > 4,
		"plan_actions(9, 9) does NOT stop at group 9 — it chains on (%d actions)" % chained.size())

	var group := nav.plan_battle_group(9)
	_eq(group.size(), 4, "plan_battle_group(9) is exactly the Gariland group's actions")
	_eq(String(group[0].get("kind", "")), "opener", "0: the opener beat")
	_eq(int(group[0].get("beat", {}).get("scenario_id", -1)), 10, "0: opener is scn 10")
	_eq(String(group[1].get("kind", "")), "pre_battle", "1: the pre-battle breakpoint")
	_eq(int(group[1].get("root", -1)), 9, "1: pre_battle root 9")
	_eq(String(group[2].get("kind", "")), "combat", "2: combat")
	_eq(String(group[3].get("kind", "")), "victory", "3: the victory beat")
	for a in group:
		_true(a.has("mutations"), "every action carries its catalogue mutations")

	# A quiet group has no pre_battle action to seek to, so there is no battle to launch —
	# it reports and returns empty rather than handing back a plan that starts nowhere.
	_eq(nav.plan_battle_group(1).size(), 0, "a non-battle root plans no battle group")

	# The formation view still weaves in when it is asked for, so the launcher's plan is
	# the mainline expansion and not a second, diverging one.
	var with_view := nav.plan_battle_group(9, null, true)
	_eq(with_view.size(), 5, "plan_battle_group honours show_formation")
	_eq(String(with_view[1].get("kind", "")), "formation_view", "the view sits between opener and pre_battle")


## The entry index: `pre_battle` by default (the opener fast-forwards inside the seek),
## `opener` when the launch asks to watch it, and -1 — never 0 — when the plan carries
## neither, because `NavigatorRunner.begin_at` clamps a negative index to the top of the
## plan and a silent 0 would look exactly like a working launch.
func _test_battle_entry_index() -> void:
	var nav := GameNavigator.new()
	var group := nav.plan_battle_group(9)
	_eq(GameNavigator.battle_entry_index(group, false), 1, "default entry is the pre_battle action")
	_eq(GameNavigator.battle_entry_index(group, true), 0, "watch_opener enters at the opener")

	var with_view := nav.plan_battle_group(9, null, true)
	_eq(GameNavigator.battle_entry_index(with_view, false), 2,
		"the entry index is read off the PLAN, so the formation view moves it")

	_eq(GameNavigator.battle_entry_index([], false), -1, "an empty plan has no entry action")
	_eq(GameNavigator.battle_entry_index([{"kind": "scenario", "root": 7}], false), -1,
		"a plan with no pre_battle action reports -1 rather than 0")
