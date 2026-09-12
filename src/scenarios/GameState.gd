class_name GameState
extends RefCounted
## Canonical top-level game states — the "spine" the state navigator drives
## (scenario <-> battle <-> world map <-> formation ...). This is the compile-time
## handle for those states; the machine-readable source of truth (descriptions,
## RE status, graph mappings) is [code]assets/scenarios/game_states.json[/code].
##
## Reference states BY NAME ([code]GameState.State.BATTLE[/code]), never by a
## literal int. [GameStateTest] asserts this enum stays in parity with the JSON
## (same slugs, same order) so the two never drift.
##
## The scenario story graph ([code]transition_graph.json[/code], built by
## tools/build_transition_graph.py) tags each node with a [i]kind[/i] and each
## edge with a [i]sink[/i]; [method for_node_kind] / [method for_successor] map those
## onto the owning state so the navigator can turn a graph walk into state
## transitions. See research/working_documents/GAME_STATE_TRANSITIONS.md.

## Enum order MUST match game_states.json `order`. GameStateTest guards this.
enum State {
	TITLE = 0,
	SCENARIO = 1,
	BATTLE = 2,
	DEPLOYMENT = 3,
	WORLD_MAP = 4,
	FORMATION = 5,
	RESET = 6,
	## Universal pre-combat setup breakpoint (navigator construct): every battle builds +
	## presents its config (placed units, teams, roster→slot binding) and pauses before
	## combat. Hosts DEPLOYMENT placement for roster-fed battles; predetermined battles
	## (Orbonne) present the fixed config. Appended (order 7) to keep prior enum values.
	PRE_BATTLE = 7,
}

const CATALOG_PATH := "res://assets/scenarios/game_states.json"

## Slug (lower-case enum name) per State, in enum order. The canonical string id.
const SLUGS := [
	"title",
	"scenario",
	"battle",
	"deployment",
	"world_map",
	"formation",
	"reset",
	"pre_battle",
]


## Canonical slug for a State value ("battle").
static func slug_of(state: int) -> String:
	if state < 0 or state >= SLUGS.size():
		return ""
	return SLUGS[state]


## State value for a slug, or -1 if unknown.
static func from_slug(slug: String) -> int:
	return SLUGS.find(slug)


## Owning state for a transition_graph.json node `kind`. Only `battle` nodes are
## the BATTLE state; every cinematic node kind (quiet / cinematic_linear /
## cinematic_latch / exit_worldmap / reset) is played in the SCENARIO state.
## NB `battle` means the node owns a BC set with a real combat predicate — a
## latch-only BC-owner is `cinematic_latch`, not a battle (see §2.5 of the doc).
static func for_node_kind(kind: String) -> int:
	if kind == "battle":
		return State.BATTLE
	return State.SCENARIO


## Owning state for a transition_graph.json edge target sink ("WORLD_MAP"/"RESET").
## Returns -1 for a normal scenario-id target (not a sink).
static func for_successor(sink: String) -> int:
	match sink:
		"WORLD_MAP":
			return State.WORLD_MAP
		"RESET":
			return State.RESET
		_:
			return -1


## Load the JSON catalog as an Array of per-state Dictionaries (source of truth
## for descriptions / RE status / godot_scene / graph mappings). Returns [] on
## failure. Prefer the enum + helpers above for control flow; use this for
## metadata (docs, debug panels, the navigator's scene lookup).
static func load_catalog() -> Array:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("GameState: catalog missing at %s" % CATALOG_PATH)
		return []
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("states"):
		push_error("GameState: malformed catalog at %s" % CATALOG_PATH)
		return []
	return parsed["states"]
