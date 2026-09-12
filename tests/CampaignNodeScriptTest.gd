extends Node
## X1 step 2 — the node script table, and the interpreter that reads it.
##
## Numbers first, and every one of them is ROM-measured rather than restated from the
## port: the table is 43 nodes / 182 scripts with a fixed emit census, node 6 at story 1
## yields scenario 13, and node 24 yields 15 at story 2 and 59 at story 10 — the same
## node, the same map, two different scenarios chosen purely by the story counter. That
## last pair is the whole reason a name-based node↔map join is structurally wrong.
##
## `_test_transition_mode_join` is the §32.5 assertion the design asked for: it is a
## CROSS-FILE check (the node script table vs the scenario records), so a bad decode or a
## bad join shows up here rather than three systems later. It asserts the measured 54/55
## and NAMES the exception, because a rule stated without its exception is the shape of
## claim that rots quietly.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/CampaignNodeScriptTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase


var _passed := 0
var _failed := 0

## The census `tools/parse_world_map.py` prints, pinned. A silent change here means the
## decoder moved, and every conclusion downstream of the table is suspect.
const EMIT_CENSUS := {
	"enter": 55, "reveal_route": 43, "reveal_node": 41, "here200": 17,
	"triple20": 11, "multi": 7, "pair100": 4, "unary800": 2,
	"unary10": 1, "setvar40": 1,
}

## §29.4's spine, spot-checked: story counter -> (node index, scenario id, transition mode).
const SPINE := [
	[1, 6, 13, 2],    # Gariland Magic City -> Balbanes's Death (Setup), light
	[2, 24, 15, 1],   # Mandalia Plains, heavy (deploys a squad)
	[3, 2, 26, 2],    # Igros Castle -> Returning to Igros, light
	[10, 24, 59, 2],  # Mandalia Plains AGAIN, different scenario, light
]


func _ready() -> void:
	_test_table_shape()
	_test_spine_lookups()
	_test_story_counter_gates_the_node()
	_test_live_enter_is_unique_at_the_opening()
	_test_roster_conditions_do_not_fire()
	_test_transition_mode_join()
	_test_place_number_conversion()

	if _failed > 0:
		print("[FAIL] CampaignNodeScriptTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] CampaignNodeScriptTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _events() -> Dictionary:
	var f := FileAccess.open(Campaign.EVENTS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


## 43 nodes, 182 scripts, and the emit census to the unit.
func _test_table_shape() -> void:
	var ev := _events()
	if ev.is_empty():
		_fail("events.json missing — run tools/parse_world_map.py")
		return
	var by_node: Array = ev.get("by_node", [])
	_eq("43 nodes carry a script list", by_node.size(), 43)
	_eq("182 node scripts", int(ev.get("script_count", -1)), 182)

	var census := {}
	var counted := 0
	for n in by_node:
		for s in n.get("scripts", []):
			var k := String(s["emit"]["kind"])
			census[k] = int(census.get(k, 0)) + 1
			counted += 1
	_eq("the census sums to the script count", counted, 182)
	for kind in EMIT_CENSUS:
		_eq("emit census: %s" % kind, int(census.get(kind, 0)), int(EMIT_CENSUS[kind]))
	_eq("no emit kind outside the ten named", census.size(), EMIT_CENSUS.size())


## The four spine rows, driven through the real interpreter by poking the counter.
func _test_spine_lookups() -> void:
	var keep := Campaign.progress.story_counter()
	for row in SPINE:
		var story: int = row[0]
		var node: int = row[1]
		Campaign.progress.set_story_counter(story)
		var e := Campaign.enter_at(node)
		_eq("story %d, node %d -> scenario" % [story, node],
			int(e.get("scenario_id", -1)), int(row[2]))
		_eq("story %d, node %d -> transition mode" % [story, node],
			int(e.get("transition_mode", -1)), int(row[3]))
	Campaign.progress.set_story_counter(keep)


## The same node, two story values, two answers — and NOTHING at a third. A node does not
## "have" a scenario.
func _test_story_counter_gates_the_node() -> void:
	var keep := Campaign.progress.story_counter()

	Campaign.progress.set_story_counter(2)
	_eq("node 24 at story 2", int(Campaign.enter_at(24).get("scenario_id", -1)), 15)
	Campaign.progress.set_story_counter(10)
	_eq("node 24 at story 10", int(Campaign.enter_at(24).get("scenario_id", -1)), 59)
	Campaign.progress.set_story_counter(1)
	_true("node 24 at story 1 has NO live enter", Campaign.enter_at(24).is_empty())

	# §29.5: eight counter values bind no script at all anywhere in the game.
	Campaign.progress.set_story_counter(14)
	_eq("story 14 binds no enter anywhere", Campaign.live_enter_nodes().size(), 0)

	Campaign.progress.set_story_counter(keep)


## At the opening the ONLY node in the game with a live enter is Gariland (§29.5, which
## measured the same thing against three savestates). That uniqueness is what lets the
## auto-advance walk take the emit without a policy.
func _test_live_enter_is_unique_at_the_opening() -> void:
	var keep := Campaign.progress.story_counter()
	Campaign.progress.set_story_counter(1)
	var live := Campaign.live_enter_nodes()
	_eq("exactly one live enter at story 1", live.size(), 1)
	_eq("...and it is node 6, Gariland", live[0] if live.size() > 0 else -1, 6)
	Campaign.progress.set_story_counter(keep)


## The roster-gated scripts must not fire: the port has no party-composition query, so a
## `party has job` condition reads as FAILING.
##
## [b]Assert on the SCENARIO, never on the node.[/b] Goug (node 11) carries fifteen
## scripts, and only the last four are the Worker-8 beats — the other two enters are
## ordinary spine rows gated purely on `var[110]`. A first draft of this test asserted
## "node 11 never yields an enter", which is false, and the failure was the test's premise
## rather than the interpreter's behaviour. A node does not have a policy; a script does.
const ROSTER_GATED_SCENARIOS := [210, 212, 214, 216, 218, 484, 488]

func _test_roster_conditions_do_not_fire() -> void:
	var keep := Campaign.progress.story_counter()
	var leaked: Array[int] = []
	var goug_spine := {}
	for story in range(0, 53):
		Campaign.progress.set_story_counter(story)
		for node in range(43):
			var e := Campaign.enter_at(node)
			if e.is_empty():
				continue
			var scn := int(e["scenario_id"])
			if ROSTER_GATED_SCENARIOS.has(scn):
				leaked.append(scn)
			if node == 11:
				goug_spine[story] = scn
	_eq("no roster-gated scenario is ever reachable", leaked.size(), 0)
	# ...and the positive arm: Goug's two SPINE enters must still work, or "nothing fires"
	# would pass for the wrong reason.
	_eq("Goug at story 23 -> scn 164", int(goug_spine.get(23, -1)), 164)
	_eq("Goug at story 24 -> scn 166", int(goug_spine.get(24, -1)), 166)
	_eq("Goug yields an enter at exactly two story values", goug_spine.size(), 2)
	Campaign.progress.set_story_counter(keep)


## §32.5's join, asserted across BOTH files. `transition_mode == 1` (heavy) correlates
## with "the launch deploys a squad" for 54 of the 55 enter emits. The one break is
## scenario 484, Nelveska Temple — optional content, authored apart from the story spine —
## and it is named rather than tolerated as noise.
func _test_transition_mode_join() -> void:
	var ev := _events()
	if ev.is_empty():
		return
	var agree := 0
	var disagree: Array[int] = []
	for n in ev.get("by_node", []):
		for s in n.get("scripts", []):
			if String(s["emit"]["kind"]) != "enter":
				continue
			var ops: Array = s["emit"]["operands"]
			var scenario_id := int(ops[0])
			var heavy := int(ops[1]) != 2
			var rec: Dictionary = ScenarioDatabase.get_scenario(scenario_id)
			if rec.is_empty():
				_fail("enter emit names scenario %d, which is not in the table" % scenario_id)
				continue
			var deploys := int(rec.get("first_squad_deployment_idx", 0)) != 0
			if heavy == deploys:
				agree += 1
			else:
				disagree.append(scenario_id)
	_eq("54 of the 55 enter emits agree with the deployment field", agree, 54)
	_eq("the one break is exactly one scenario", disagree.size(), 1)
	_eq("...and it is 484, Nelveska Temple", disagree[0] if disagree.size() > 0 else -1, 484)


## Place number (screen, 1-based, 0 = none) vs node index (storage, 0-based). Converted in
## one place. `WorldMapProgress.OPENING_CAPTURE` is in index space; `node_entered` is not.
func _test_place_number_conversion() -> void:
	_eq("place 7 is node index 6", Campaign.place_to_index(7), 6)
	var keep := Campaign.progress.story_counter()
	Campaign.progress.set_story_counter(1)
	_eq("entering PLACE 7 resolves Gariland's scenario",
		int(Campaign.enter_at(Campaign.place_to_index(7)).get("scenario_id", -1)), 13)
	Campaign.progress.set_story_counter(keep)


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
