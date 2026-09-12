class_name GameNavigator
extends RefCounted

## The pure story-graph WALK planner — turns the transition graph into the ordered
## sequence of beats the runtime navigator drives (SCENARIO playback and BATTLE
## combat over ONE persistent world; decision #179). No scene / VM / GPU / rendering
## dependency; fully headless-testable, mirroring the [ScenarioPath] planner style.
## A scene-side executor (the navigator Node) consumes the plan and drives
## [ScenarioPathApplier] / CombatLoop, advancing on the sub-scenes' finish signals.
##
## It is the SOLE reader of transition_graph.json (node kinds + BC/successor edges);
## group membership + the `next-scenario` successor come from [ScenarioGroupDatabase].
##
## A BEAT is one played sub-scene on the walk:
##   { "scenario_id": int, "state": GameState.State, "role": String }
## role ∈ {"setup","member","opener","victory"}. The mid-combat interlude beat
## (scn 5 for Orbonne) is skipped for v1 (HANDOFF §7).

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const GRAPH_PATH := "res://assets/scenarios/transition_graph.json"

## An successor edge's target is normally an int scenario id, but 110 of them name a SINK
## instead — 97 `WORLD_MAP` (successor=0x80 world-map) and 13 `RESET` (post=0x82). The
## group database agrees from its own side: 94 of the 155 groups carry
## `exit == "world-map"`.
##
## [b]These used to end the walk silently.[/b] `_next_root` ran `int(target)`, GDScript
## reads a non-numeric String as 0, and the caller treated 0 as "no successor". The very
## first story walk hits one: 1 -> 3 -> 7 -> 9, and group 9 (Gariland) exits to
## `WORLD_MAP`. NavigatorMain even logged it — *"Walk finished at group 9 (world map
## OOS)"*. Naming the sink is what turns that into a transition.
##
## [b]That paragraph is about the GRAPH, and for a while it was not true of the WALK.[/b]
## A `stop_root` is consulted FIRST — the stop-root branch below breaks before it ever
## reaches [method successor_kind] — and `NavigatorMain.STOP_ROOT` was 9, so the walk a player
## cold-booted stopped on Gariland's victory beat with the sink unread. Correct behaviour
## from this file (a stop root means stop), and the wrong walk to ask for; the constant is
## 0 (natural end) now. See WORLD_MAP_PORT_LIST.md §17.
const SUCCESSOR_WORLD_MAP := "WORLD_MAP"

var _nodes: Dictionary = {}   # scenario_id (int) -> graph node Dictionary


func _init() -> void:
	var root := JsonAsset.load_dict(GRAPH_PATH)
	var nodes: Dictionary = root.get("nodes", {})
	# JSON object keys are strings; re-key by int scenario_id for lookups.
	for k in nodes.keys():
		_nodes[int(k)] = nodes[k]


## The graph node kind for `scenario_id` ("battle"/"quiet"/"cinematic_linear"/...),
## or "" if the scenario is not in the graph.
func _kind(scenario_id: int) -> String:
	return _nodes.get(scenario_id, {}).get("kind", "")


## Build one beat Dictionary. `state < 0` derives the state from the node kind;
## otherwise the caller forces it (battle-group beats are all BATTLE state even
## though a woven cinematic member's own node kind is quiet/cinematic_linear).
func _beat(scenario_id: int, role: String, state: int = -1) -> Dictionary:
	return {
		"scenario_id": scenario_id,
		"state": GameState.for_node_kind(_kind(scenario_id)) if state < 0 else state,
		"role": role,
	}


## The BC-edge target on `node` whose reason string contains `marker`, or -1.
## Battle beats are woven by BattleConditionals predicate; the graph already tags
## each BC edge with its predicate ("Variable =(509,1)" opener / "Victory()" ...),
## so the walk reads them straight off the node — no BC-evaluator needed (HANDOFF §4).
func _bc_target(node: Dictionary, marker: String) -> int:
	for e in node.get("edges", []):
		if String(e.get("via", "")) == "BC" and String(e.get("why", "")).contains(marker):
			return int(e.get("target", -1))
	return -1


## The ordered beats one group contributes to the walk. A LINEAR (non-battle) group
## is one beat per member in file order; a BATTLE group weaves its setup + opener +
## victory beats (the mid-combat interlude beat is skipped for v1, HANDOFF §7).
func beats_for_group(root_id: int) -> Array:
	if _kind(root_id) == "battle":
		return _battle_beats(root_id)
	var beats: Array = []
	var group := ScenarioGroupDatabase.get_group_by_root(root_id)
	for m in group.get("members", []):
		beats.append(_beat(int(m.get("scenario_id", -1)), String(m.get("role", "member"))))
	return beats


## Plan the full walk from group `start_root`, chaining group -> group via each
## group's exit edge, until it would ENTER `stop_root`. The stop group's setup beat
## is emitted as the terminal halt beat (T5: "enter group 7 and stop") — its members
## are NOT played. Returns the ordered beat list for the whole run.
func plan_walk(start_root: int, stop_root: int) -> Array:
	var beats: Array = []
	var root := start_root
	var guard := 0
	while guard < 512:
		guard += 1
		if root == stop_root and not beats.is_empty():
			beats.append(_beat(root, "setup"))
			break
		var group_beats := beats_for_group(root)
		beats.append_array(group_beats)
		var next_root := _next_root(root, group_beats)
		if next_root <= 0:
			break
		root = next_root
	return beats


## The walk as the COARSE action steps the runtime navigator drives — one entry per
## sub-scene the executor plays and then yields on a finish signal (decision #179).
## A linear group is one "scenario" action (play all members, wait group_finished); a
## battle group expands to "opener" (a woven cinematic beat), "combat" (run the ENTD
## battle, wait victory), then "victory" (the terminal cinematic beat). The stop group
## is one terminal "scenario" action — entered, then the walk halts. Action shapes:
##   { "kind":"scenario", "root":int, "beats":Array, "terminal":bool, "mutations":Array }
##   { "kind":"opener"|"victory", "beat":Dictionary, "mutations":Array }
##   { "kind":"combat", "root":int, "mutations":Array }
##
## Every action carries a `mutations` list — the Catalog deltas [CatalogueReplay] folds
## as the walk advances (ADR-0201). `script` supplies them (a [MutationScript]); with no
## script every action carries `[]` (the plumbing is inert until a real script is set).
func plan_actions(start_root: int, stop_root: int, script: MutationScript = null,
		show_formation: bool = false) -> Array:
	var actions := _plan_actions_bare(start_root, stop_root, show_formation)
	var mut := script if script != null else MutationScript.new()
	for a in actions:
		a["mutations"] = mut.for_action(a)
	return actions


## The coarse actions of ONE battle group and nothing after it — the plan that "play
## battle N" walks (ADR-0264). Same expansion as the mainline: opener ->
## [formation_view] -> pre_battle -> combat -> victory.
##
## [b]`plan_actions(root, root)` cannot express this.[/b] Its stop test is `root ==
## stop_root and not actions.is_empty()`, and on the first iteration `actions` IS empty,
## so a start == stop walk falls through to the ordinary branch and chains onward down the
## successor graph exactly as an unbounded one does. That reading is deliberate there — a
## walk may pass back through its own start root — which is why "just this group" is a
## separate entry point rather than a change to the stop condition.
##
## Returns [] (and reports) for a non-battle root: a quiet group has no pre_battle action
## to seek to, so there is no battle to launch.
func plan_battle_group(root: int, script: MutationScript = null,
		show_formation: bool = false) -> Array:
	var actions: Array = []
	if _kind(root) != "battle":
		push_error("[GameNavigator] plan_battle_group: group %d is kind '%s', not a battle" %
			[root, _kind(root)])
		return actions
	_append_battle_actions(actions, root, beats_for_group(root), show_formation)
	var mut := script if script != null else MutationScript.new()
	for a in actions:
		a["mutations"] = mut.for_action(a)
	return actions


## The index in `actions` of a battle group's ENTRY action — where "play battle N" begins
## the walk (ADR-0264).
##
## `pre_battle` by default: [method NavigatorMain._ensure_battle_world] boots the world,
## deploys the squad and fast-forwards the opener at 30x from there (~1 s), so the walk
## lands in Deployment with the authored framing already settled. `watch_opener` begins one
## action earlier instead, and the opener plays at normal speed.
##
## -1 when `actions` carries neither, which is the caller's cue to REFUSE rather than start
## somewhere: [method NavigatorRunner.begin_at] clamps a negative index to 0, so a silent
## -1 would boot the top of the plan and look like a working launch.
static func battle_entry_index(actions: Array, watch_opener: bool) -> int:
	var wanted := "opener" if watch_opener else "pre_battle"
	for i in actions.size():
		if String(actions[i].get("kind", "")) == wanted:
			return i
	if watch_opener:
		# All 72 battle groups carry an opener (ADR-0264), so this is a data anomaly rather
		# than a shape to absorb quietly — say so, then land in Deployment.
		push_warning("[GameNavigator] battle_entry_index: no opener action in the plan — "
			+ "falling back to the pre_battle entry")
		return battle_entry_index(actions, false)
	return -1


## The action plan WITHOUT catalogue mutations — the pure story-graph walk. Kept split
## from `plan_actions` so the mutation attachment is a single, testable seam.
func _plan_actions_bare(start_root: int, stop_root: int, show_formation: bool = false) -> Array:
	var actions: Array = []
	var root := start_root
	var guard := 0
	while guard < 512:
		guard += 1
		var group_beats := beats_for_group(root)
		if root == stop_root and not actions.is_empty():
			# The stop root is played, then the walk ends (no chain onward). A BATTLE stop
			# root is played through in full — opener -> pre_battle -> combat -> victory
			# (wayfinder #234 A: Gariland is roster-fed, so "terminal" means *stop after
			# this group's actions*, not *skip them*); the victory beat is the clean
			# endpoint (#234 F). A non-battle stop root is entered-and-halted as before.
			if _kind(root) == "battle":
				_append_battle_actions(actions, root, group_beats, show_formation)
			else:
				actions.append({"kind": "scenario", "root": root,
					"beats": [_beat(root, "setup")], "terminal": true})
			break
		if _kind(root) == "battle":
			_append_battle_actions(actions, root, group_beats, show_formation)
		else:
			actions.append({"kind": "scenario", "root": root,
				"beats": group_beats, "terminal": false})
		var next_root := _next_root(root, group_beats)
		if next_root <= 0:
			# No successor ROOT — but the group may still go somewhere. `successor_kind` is
			# where the console goes; a WORLD_MAP sink is the overworld, and the walk
			# continues INTO it rather than stopping one step short.
			if successor_kind(root) == SUCCESSOR_WORLD_MAP:
				actions.append({"kind": "world_map", "root": root, "terminal": true})
			break
		root = next_root
	return actions


## Append one battle group's coarse driver actions — opener (woven cinematic) ->
## pre_battle (universal setup breakpoint) -> combat -> victory — onto `actions`.
## Shared by the mainline (chaining) battle groups and a battle STOP root, so the
## Gariland expansion is identical whether or not the walk continues past it.
func _append_battle_actions(actions: Array, root: int, group_beats: Array,
		show_formation: bool = false) -> void:
	for b in group_beats:
		if String(b.get("role", "")) == "opener":
			actions.append({"kind": "opener", "beat": b})
		# setup has no standalone cinematic; pre_battle + combat + victory follow the opener.
	# The formation view (wayfinder #234 E) is DEBUG-GATED (default OFF): shown between the
	# opener and the pre-battle deployment when `navigator.show_formation` is set. View-only,
	# non-gating — the end-to-end proof omits it (this branch is skipped by default).
	if show_formation:
		actions.append({"kind": "formation_view", "root": root})
	# A universal PRE-BATTLE setup step precedes combat (GAME_STATE_TRANSITIONS.md §2.6):
	# EVERY battle builds + presents its config and pauses. The executor gates deployment
	# on the ENTD control flag at runtime — predetermined casts (Orbonne) present a fixed
	# config, roster-fed battles (Gariland) host deployment placement.
	actions.append({"kind": "pre_battle", "root": root})
	actions.append({"kind": "combat", "root": root})
	for b in group_beats:
		if String(b.get("role", "")) == "victory":
			actions.append({"kind": "victory", "beat": b})


## The raw successor-edge target on `scenario_id`'s node: an int scenario id, or a sink
## NAME ("WORLD_MAP" / "RESET"), or null when the node has no successor edge.
func _successor_edge(scenario_id: int) -> Variant:
	for e in _nodes.get(scenario_id, {}).get("edges", []):
		if String(e.get("via", "")) == "successor":
			return e.get("target", null)
	return null


## The successor-edge target on `scenario_id`'s node (0x81 -> next group root), or -1.
## A sink target is NOT a root — see [method successor_kind].
func _successor_target(scenario_id: int) -> int:
	var t: Variant = _successor_edge(scenario_id)
	return int(t) if typeof(t) == TYPE_FLOAT or typeof(t) == TYPE_INT else -1


## The sink group `root` exits to ("WORLD_MAP" / "RESET"), or "" when it chains to
## another group or simply stops. Read from the same edge `_next_root` reads, so the two
## cannot disagree about where a group goes.
func successor_kind(root: int) -> String:
	var terminal := root
	if _kind(root) == "battle":
		var beats := _battle_beats(root)
		if not beats.is_empty():
			terminal = int(beats[beats.size() - 1].get("scenario_id", root))
	else:
		var members: Array = ScenarioGroupDatabase.get_group_by_root(root).get("members", [])
		if not members.is_empty():
			terminal = int(members[members.size() - 1].get("scenario_id", root))
	var t: Variant = _successor_edge(terminal)
	if typeof(t) == TYPE_STRING:
		return String(t)
	# FALLBACK — the graph read missed, so ask the group database, which reads the
	# successor byte off the group's LAST MEMBER directly.
	#
	# [b]Why it can miss.[/b] For a battle group the terminal above is the `Victory` BC
	# target, and `_battle_beats` recognises victory only by that literal guard. **11 of
	# the 97 `world-map` groups do not have one** — their win condition is spelled
	# `HP <= (boss, 0)` instead, so the terminal resolves to the OPENER and its edge is not
	# a sink. Group 61 is the first: members 61..67, and it is member 67, reached by
	# `Variable =(128,0); HP <=(133,0)`, that carries the `world-map` successor.
	#
	# [b]`HP <= (unit, 0)` is "that unit is dead", which is victory or DEFEAT depending on
	# whose unit it is — so all eleven were checked by name before this fallback was
	# trusted.[/b] Ten are literally "(Victory)" (Elidibs, Murond Death City, Lost Sacred
	# Precincts, Graveyard of Airships, Bervenia Free City, Elmdor II, Adramelk, Hall of
	# St. Murond Temple, Underground Book Storage 3F, Nelveska Temple); the eleventh is
	# "Miluda2 (Miluda's Death)" — killing the boss at Lenalia Plateau. **None is a game
	# over**, so reading their successor is reading a victory route.
	#
	# Without this the chain STRANDS: a hop into any of those 11 plans a group with no
	# trailing `world_map` action and the walk ends mid-story. Caught by
	# `CampaignChainTest._test_every_world_map_group_hands_back_a_map`.
	#
	# Only the two SINKS fall back. A `next-scenario` group must still return "" here, or
	# `plan_actions` would treat a chaining group as a sink.
	match String(ScenarioGroupDatabase.get_group_by_root(root).get("successor", "")):
		"world-map":
			return SUCCESSOR_WORLD_MAP
		"reset":
			return "RESET"
	return ""


## The next group root after playing group `root`. A battle group hands off from
## its terminal (victory) member's successor edge; a linear group from its
## `next-scenario` successor. -1 when the group does not chain onward.
func _next_root(root: int, group_beats: Array) -> int:
	if _kind(root) == "battle":
		if group_beats.is_empty():
			return -1
		var terminal: Dictionary = group_beats[group_beats.size() - 1]
		return _successor_target(int(terminal.get("scenario_id", -1)))
	var group := ScenarioGroupDatabase.get_group_by_root(root)
	if String(group.get("successor", "")) == "next-scenario":
		return int(group.get("successor_scenario_id", -1))
	return -1


## setup + opener (Var509 latch) + victory (Victory()) — all BATTLE state.
func _battle_beats(root_id: int) -> Array:
	var node: Dictionary = _nodes.get(root_id, {})
	var beats: Array = [_beat(root_id, "setup", GameState.State.BATTLE)]
	var opener := _bc_target(node, "509")
	if opener > 0:
		beats.append(_beat(opener, "opener", GameState.State.BATTLE))
	var victory := _bc_target(node, "Victory")
	if victory > 0:
		beats.append(_beat(victory, "victory", GameState.State.BATTLE))
	return beats
