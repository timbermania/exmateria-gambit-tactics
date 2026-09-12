class_name WorldMapProgress
extends RefCounted
## The world map's slice of campaign progression — [b]Campaign's payload, not the
## screen's[/b] (docs/WORLD_MAP_PORT_LIST.md crossing C3).
##
## A query surface (ADR-0116 dec. 3's cheapest legal shape) over [WorldMapVariables],
## which is `WORLD.BIN`'s game-variable store in the ROM's own encoding. The consumer
## asks questions; it does not read the store's layout. When Campaign lands, this class
## and its backing move together and the callers do not change.
##
## [codeblock]
## node i is known    bit 512 + i
## route r is drawn   bit 556 + r
## story position     var 110
## gil                var 0x2C     date   vars 0x2E / 0x2F
## [/codeblock]
##
## ⚠ `gil` is var `0x2C`. That index was read as "chapter" until 2026-08-22; the battle
## side's `event_set_script_variable` special-cases it and clamps it to 99,999,999, and
## BC opcodes 0x0E/0x0F read it as "Gil >= / <=".
##
## [b]What is deliberately NOT here.[/b] The SELECTED node. `DAT_800D0BB4` is the world
## map's own working RAM, not `WORLD.BIN`'s variable store, and §27.4 derives it from
## the cursor by hit test every frame — see [WorldMapCursor]. Putting it here is what
## made the scaffold draw the cursor four pixels low.

const NODE_COUNT := 43
const ROUTE_COUNT := 48

const NODE_KNOWN_BASE := 512
const ROUTE_DRAWN_BASE := 556
const STORY_COUNTER := 110
const GIL := 0x2C
const DATE_MONTH := 0x2E
const DATE_DAY := 0x2F

## The console's variable store at the opening of the game, read off
## `reference-assets/world_map_ss1_settled_dialog_closed.sstate` — nodes {2, 6, 24},
## routes {1, 3}, story 1, gil 4500, Jan 1. Regenerate, never hand-edit:
##
##     python3 tools/wm_progress_dump.py <sstate>
##
## ⚠ This is the EARLIEST capture the repo holds, not a proven new-game seed: nothing
## read yet says what `WORLD.BIN` starts a fresh campaign with. It is a real console
## state rather than three hand-typed numbers, which is the point — the decode of these
## bytes into {2, 6, 24} / {1, 3} is checkable, and `WorldMapProgressTest` checks it.
## The words this RE has not named are carried verbatim; they are still progression.
const OPENING_CAPTURE := [
	[26, 0x00062000], [27, 0xFFFE4000], [28, 0x0010A000], [29, 0x0000012E],
	[30, 0x00000A00], [32, 0x00001000], [44, 0x00001194], [46, 0x00000001],
	[47, 0x00000001], [49, 0x00000006], [50, 0x00000184], [51, 0x00000016],
	[52, 0x00000001], [54, 0x00000001], [81, 0x00000001], [82, 0x00000005],
	[87, 0x000002CF], [95, 0x00000001], [96, 0x00000001], [109, 0x00000001],
	[110, 0x00000001], [111, 0x00000001], [127, 0x00000001], [137, 0x10000000],
	[140, 0x01000044], [141, 0x0000A000], [143, 0x00002000], [146, 0x000E0000],
	[163, 0x11000011], [164, 0x00000100], [166, 0x01000000], [170, 0x10000000],
]

const SAVE_PATH := "user://world_progress.json"

var vars: WorldMapVariables = WorldMapVariables.new()

## 1-based node the party marker stands on; 0 while travelling between two.
##
## ⚠ Not a game variable. On the console the marker's node is read back off its
## descriptor position (§30.4 derives it that way), and nothing located so far says
## where a save keeps it. It is held here because a save has to keep it somewhere and
## this is the object Campaign inherits.
var _party_node: int = 0


# ---------------------------------------------------------------- the four questions

func is_node_known(i: int) -> bool:
	return vars.get_var(NODE_KNOWN_BASE + i) != 0


func is_route_drawn(r: int) -> bool:
	return vars.get_var(ROUTE_DRAWN_BASE + r) != 0


func known_nodes() -> Array:
	var out: Array = []
	for i in NODE_COUNT:
		if is_node_known(i):
			out.append(i)
	return out


func drawn_routes() -> Array:
	var out: Array = []
	for r in ROUTE_COUNT:
		if is_route_drawn(r):
			out.append(r)
	return out


func story_counter() -> int:
	return vars.get_var(STORY_COUNTER)


func gil() -> int:
	return vars.get_var(GIL)


func date() -> Vector2i:
	return Vector2i(vars.get_var(DATE_MONTH), vars.get_var(DATE_DAY))


func party_node() -> int:
	return _party_node


# ---------------------------------------------------------------- advancing it

func set_node_known(i: int, known: bool = true) -> void:
	vars.set_var(NODE_KNOWN_BASE + i, 1 if known else 0)


func set_route_drawn(r: int, drawn: bool = true) -> void:
	vars.set_var(ROUTE_DRAWN_BASE + r, 1 if drawn else 0)


func set_story_counter(n: int) -> void:
	vars.set_var(STORY_COUNTER, n)


func set_gil(n: int) -> void:
	vars.set_var(GIL, n)


func set_date(month: int, day: int) -> void:
	vars.set_var(DATE_MONTH, month)
	vars.set_var(DATE_DAY, day)


func set_party_node(node_1based: int) -> void:
	_party_node = clampi(node_1based, 0, NODE_COUNT)


# ---------------------------------------------------------------- seeding and saving

## The state a campaign opens in. See [constant OPENING_CAPTURE] for what that means
## and does not mean.
static func new_campaign() -> WorldMapProgress:
	var p := WorldMapProgress.new()
	p.vars.load_sparse(OPENING_CAPTURE)
	p._party_node = 7                     # Gariland, where the opening capture stands
	return p


## `reference-assets/world_map_ss1_settled_dialog_closed.sstate` — the capture every
## §30 assertion is made against, so the scaffold has an oracle.
static func ss1_fixture() -> WorldMapProgress:
	return new_campaign()


## `world_map_pre_scenario14_root13`. It holds the SAME progression as ss1 — the three
## things §30.4 says the pair separates (selected node, party node, "you are here"
## highlight) are all downstream of where the CURSOR is, and none of them is stored
## here. Kept as its own name so a caller says which capture it means.
static func ss2_fixture() -> WorldMapProgress:
	return new_campaign()


func to_dict() -> Dictionary:
	return {"vars": vars.to_sparse(), "party_node": _party_node}


static func from_dict(d: Dictionary) -> WorldMapProgress:
	var p := WorldMapProgress.new()
	p.vars.load_sparse(d.get("vars", []))
	p._party_node = int(d.get("party_node", 0))
	return p


func save_to_file(path: String = SAVE_PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return OK


## The saved campaign, or [method new_campaign] when there is none — the same
## seed-or-load shape the retired per-side rosters used (ADR-0180).
static func load_or_new(path: String = SAVE_PATH) -> WorldMapProgress:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return new_campaign()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("world map: %s did not parse as an object" % path)
		return new_campaign()
	return from_dict(parsed)
