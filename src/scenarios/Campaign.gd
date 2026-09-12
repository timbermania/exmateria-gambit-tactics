extends Node
## CAMPAIGN — the spine's state (ADR-0117 system #9): the one game-variable store, and
## the node script table that decides what a world-map node does.
##
## [b]One store, not three.[/b] FFT keeps a single game-variable array at `0x8005771C` —
## SCUS BSS, below `0x80067000`, so it survives the `BATTLE.BIN` overlay load. The world
## map's overlay, the event-script interpreter's `0xB0`–`0xBE` writers and the battle
## side's `event_set_script_variable` all address the same bytes. This node owns the port's
## single [WorldMapVariables]; [ScenarioVM] takes it by injection. See
## [url]docs/adr/0179-the-game-variable-store-is-one-array-and-the-port-had-three.md[/url].
##
## [b]Campaign asks the table, the map does not.[/b] `WORLD_MAP_SCREEN.md` §32.9 point 1:
## the map reports [signal WorldMapScene.node_entered] and Campaign resolves it. That is
## why the table is `assets/world_map/events.json` and not a key in `model.json` — anything
## in `model.json` is reachable from the map through [WorldMapAssets] by construction. The
## rule is about the TABLE, and it is one-way: since ADR-0230 this node also reads
## `model.json`'s `routes` array, because a reveal names two node indices and the store's
## bit is `556 + route` — see [constant MODEL_PATH]. The map still never reads the table.
##
## Vocabulary: CONTEXT.md → "Campaign spine". A **node script** is conditions-then-one-emit;
## an **enter** emit carries `(scenario_id, transition_mode)`; the **story counter** is
## `var[110]`, written by the scenarios themselves and never by the map.

## The node script table, emitted by `tools/parse_world_map.py`. Gitignored + regenerable.
const EVENTS_PATH := "res://assets/world_map/events.json"

## Where the route ENDPOINT PAIRS come from. `reveal_route(a, b)` names two nodes and the
## store's bit is `556 + route`, so the pair → route join is store vocabulary, not screen
## vocabulary — Campaign resolves it rather than asking the map, which keeps the crossing
## one-way (ADR-0230 dec. 2 and dec. 7). Only the `routes` array's `r`/`a`/`b` are read;
## the geometry beside them is [WorldMapAssets]'s business and is never touched here.
const MODEL_PATH := "res://assets/world_map/model.json"

## Emit TYPE bits — `FUN_80091238(node, mask)`'s second argument (§29.1). A caller asks
## for the KIND it cares about; one node's script list serves several unrelated questions.
const MASK_ENTER := 0x008    ## the hand-off: `var[0x27] = a`, `FUN_8008047C(b)`
const MASK_SETVAR := 0x040   ## `FUN_8008E2BC`'s second query
const MASK_REVEAL := 0xF80   ## what `FUN_8006C894` asks for — 0x080…0x800

## Condition opcodes. The whole 182-script table uses exactly TWO of the 41 the dispatcher
## defines, so these are the only ones implemented — measured, not guessed:
##   `0x01 var[a] == b`   317 uses
##   `0x04 party has job a` 7 uses, across 6 scripts (Goug ×4, Nelveska, one at node 8)
## Anything else is a table we have not seen and FAILS LOUD rather than passing silently.
const COND_VAR_EQ := 0x01
const COND_PARTY_JOB := 0x04

## Campaign's save data, in the ROM's own encoding. Never null after `_ready`.
var progress: WorldMapProgress = null

var _events: Dictionary = {}
var _by_node: Array = []
## `Vector2i(min(a, b), max(a, b))` → route index, built on first use by [method _routes].
var _route_of: Dictionary = {}
var _routes_loaded: bool = false


func _ready() -> void:
	progress = WorldMapProgress.load_or_new()
	_load_events()


func _load_events() -> void:
	var f := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if f == null:
		push_error("[Campaign] %s missing — run tools/parse_world_map.py" % EVENTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Campaign] %s did not parse as an object" % EVENTS_PATH)
		return
	_events = parsed
	_by_node = _events.get("by_node", [])


## The single game-variable store. The one object [ScenarioVM] is handed.
func vars() -> WorldMapVariables:
	return progress.vars if progress != null else null


## `var[110]` — the world-map story counter. Written by the scenarios' own
## `Zero(110); Add(110, k)`, never here.
func story_counter() -> int:
	return progress.story_counter() if progress != null else 0


func save() -> void:
	if progress != null:
		progress.save_to_file()


## --- the node script interpreter -------------------------------------------

## Node `node_index`'s scripts, in evaluation order. [param node_index] is a
## [b]node index[/b] (0-based storage space), not a place number — see `place_to_index`.
func scripts_for(node_index: int) -> Array:
	if node_index < 0 or node_index >= _by_node.size():
		return []
	return _by_node[node_index].get("scripts", [])


## The ROM's `place number` → `node index` conversion, and the ONLY place it happens.
## `FUN_8006C350`'s hit test returns `i + 1` with 0 for "none", and the arrival handler
## writes `arrived_node + 1` to the HUD word — so the screen counts from 1 and the store
## counts from 0. [signal WorldMapScene.node_entered] carries a place number.
static func place_to_index(place: int) -> int:
	return place - 1


## `FUN_80091238(node, mask)` — the FIRST script whose conditions all pass and whose emit
## kind is selected by [param mask]. Returns that script's `emit` dictionary, or {} when
## no script matches. Scripts whose conditions fail are skipped, exactly as the ROM's
## result-word bit 1 abandons them.
func query(node_index: int, mask: int) -> Dictionary:
	for s in scripts_for(node_index):
		var emit: Dictionary = s.get("emit", {})
		if int(emit.get("mask", 0)) & mask == 0:
			continue
		if not _conditions_pass(s.get("conditions", [])):
			continue
		return emit
	return {}


## The live hand-off at [param node_index], as
## `{"scenario_id": int, "transition_mode": int}`, or {} when the node has none right now.
##
## `transition_mode` is the emit's SECOND operand (§32.5): 2 = light, anything else heavy.
## It selects the screen transition. Across the story spine it correlates 54/55 with
## whether the launch deploys a squad, but that is a correlation — deployment is derived
## from the scenario record's `first_squad_deployment_idx`, and scenario 484 (Nelveska) is
## the measured exception. Do not read it as "mode = battle".
func enter_at(node_index: int) -> Dictionary:
	var emit := query(node_index, MASK_ENTER)
	if emit.is_empty():
		return {}
	var ops: Array = emit.get("operands", [])
	if ops.size() < 2:
		push_error("[Campaign] enter emit at node %d has %d operand(s), expected 2"
				% [node_index, ops.size()])
		return {}
	return {"scenario_id": int(ops[0]), "transition_mode": int(ops[1])}


## Every node index carrying a live `enter` against the current store.
##
## On the main story this is always exactly one: 44 of the 45 story-counter values that
## bind an `enter` bind precisely one, and the 45th (47) disambiguates on `var[162]`. A
## count of 0 or >1 is therefore a real anomaly and the auto-advance walk stops on it
## rather than picking.
func live_enter_nodes() -> Array[int]:
	var out: Array[int] = []
	for i in range(_by_node.size()):
		if not query(i, MASK_ENTER).is_empty():
			out.append(i)
	return out


## --- the reveal pass -------------------------------------------------------

## The [CampaignRevealPass] node [param node_index] owes right now — the whole of the
## Campaign↔map crossing for reveals (ADR-0230 dec. 2). The caller paces it:
## `while true: var s := p.step(); if s.is_empty(): break`.
##
## [param store] is the [WorldMapProgress] the steps write into, defaulting to this
## autoload's own. It is a parameter because [WorldMapScene] does not always draw THIS
## store — its standalone rig branch builds a fixture and its `load_or_new` branch loads a
## second one — and a pass that wrote somewhere other than the store on screen would
## reveal nothing the player could see. Campaign still owns the table and the effect;
## whose save it advances is the caller's to say.
func reveal_pass(node_index: int, store: WorldMapProgress = null) -> CampaignRevealPass:
	var p: WorldMapProgress = store if store != null else progress
	return CampaignRevealPass.new(node_index, scripts_for(node_index), p, _routes(),
			_conditions_pass.bind(p))


## The endpoint-pair → route index map, loaded once. Lazy rather than in [method _ready]
## because most sessions never open the world map, and this is the only thing in Campaign
## that reads `model.json`.
func _routes() -> Dictionary:
	if _routes_loaded:
		return _route_of
	_routes_loaded = true
	var f := FileAccess.open(MODEL_PATH, FileAccess.READ)
	if f == null:
		push_error("[Campaign] %s missing — run tools/parse_world_map.py" % MODEL_PATH)
		return _route_of
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Campaign] %s did not parse as an object" % MODEL_PATH)
		return _route_of
	for row in (parsed as Dictionary).get("routes", []):
		var a := int(row.get("a", -1))
		var b := int(row.get("b", -1))
		var key := Vector2i(mini(a, b), maxi(a, b))
		if _route_of.has(key):
			# Dec. 7 rests on the pair being unique. If it stops being, the lookup stops
			# being a function and the reveal it serves is silently the wrong road.
			push_error("[Campaign] routes %d and %d share endpoints (%d, %d)"
					% [int(_route_of[key]), int(row.get("r", -1)), a, b])
			continue
		_route_of[key] = int(row.get("r", -1))
	return _route_of


## True when every condition holds. A `party has job` condition is NOT modelled — the port
## has no party-composition query — so it reads as FAILING, which keeps the six
## roster-gated optional scripts (Goug's Worker-8 beats, Nelveska) out of the walk instead
## of wrongly entering them. `wldevent.py` marks the same ops indeterminate.
##
## [param store] defaults to this autoload's own and is only ever passed by
## [method reveal_pass], which binds it: a pass evaluates conditions against the SAME
## store its steps write into, or the guard a step just cleared is read off a different
## save. The rule the conditions apply is unchanged either way (ADR-0230 dec. 10).
func _conditions_pass(conditions: Array, store: WorldMapProgress = null) -> bool:
	var p: WorldMapProgress = store if store != null else progress
	for c in conditions:
		var op := int(c.get("op", -1))
		var a: Array = c.get("operands", [])
		match op:
			COND_VAR_EQ:
				if a.size() < 2 or p.vars.get_var(int(a[0])) != int(a[1]):
					return false
			COND_PARTY_JOB:
				return false
			_:
				push_error(("[Campaign] node script condition 0x%02X is not modelled — "
						+ "the table changed; see CONTEXT.md → Campaign spine") % op)
				return false
	return true
