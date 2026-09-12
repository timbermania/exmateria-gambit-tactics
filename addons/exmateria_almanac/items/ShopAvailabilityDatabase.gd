extends RefCounted

## When the shops start stocking an item, and which shop stocks it.
##
## FFT does not store item power — it stores *availability*, and the ordering
## availability produces is the design's own power rank. Three ROM facts, one
## table (`items/shop_availability.json`, emitted by
## `tools/parse_shop_availability.py`):
##
## - every item carries a **shop tier** (`rec[10]`, 1..15; 20 = never sold),
## - and a 16-bit **shop-slot mask** saying which shops carry it,
## - and world variable `0x6F` holds the tier the player has reached.
##
## The ROM's gate (`FUN_8012502C` @0x801251BC/0x801251CC) is exactly
## [method is_stocked]: mask bit AND tier. Nothing writes `0x6F` in engine code
## — 44 event scripts assign it, and because a TEST.EVT event index IS a
## `scenario_id`, [method tier_at_scenario] turns story progress into an
## inventory. See [ScenarioDatabase](../encounters/ScenarioDatabase.gd) for the
## other half of that join, and
## `research/working_documents/ITEM_AVAILABILITY_TIMELINE.md` for the citations.
##
## Pure data over one payload — no node, no scene, the same XDatabase shape as
## ItemDatabase / ScenarioDatabase.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's. One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const SHOP_AVAILABILITY_PATH := "res://addons/exmateria_almanac/items/shop_availability.json"

## `rec[10]` for an item the shops never sell. Not a reachable value of the
## tier variable, which is why the gate below rejects it without a special case.
const TIER_NEVER := 20

static var _items: Dictionary = {}
static var _tiers: Dictionary = {}
static var _timeline: Array = []
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	# One open, three plucks — `timeline` is an Array, which is the case
	# JsonAsset's docstring says to read off the root rather than by key.
	var doc: Dictionary = JsonAsset.load_dict(SHOP_AVAILABILITY_PATH)
	_items = doc.get("items", {})
	_tiers = doc.get("tiers", {})
	_timeline = doc.get("timeline", [])
	_loaded = true


## The item's shop tier: 1..15, or [constant TIER_NEVER] for the 55 items no
## shop ever stocks. 0 for an unknown id.
static func tier_of(item_id: int) -> int:
	_ensure_loaded()
	return int(_items.get(str(item_id), {}).get("shop_tier", 0))


## The 16-bit shop-slot mask, read big-endian from the ROM. Bit `15 - slot`.
static func slot_mask_of(item_id: int) -> int:
	_ensure_loaded()
	return int(_items.get(str(item_id), {}).get("shop_slot_mask", 0))


## The level at which a generic enemy may roll this item as random equipment
## (`rec[2]`) — the ROM's own numeric power index, and the only one it has.
static func enemy_level_of(item_id: int) -> int:
	_ensure_loaded()
	return int(_items.get(str(item_id), {}).get("enemy_level", 0))


## The scenario whose event script first raises the tier that unlocks this item,
## or -1 if no shop ever stocks it.
static func unlock_scenario_of(item_id: int) -> int:
	_ensure_loaded()
	return int(_items.get(str(item_id), {}).get("unlock_scenario_id", -1))


## The ROM gate, both halves. `shop_slot` is the current world-map location
## (world variable 0x31); pass -1 to ask "does ANY shop stock it at this tier".
static func is_stocked(item_id: int, shop_tier: int, shop_slot: int = -1) -> bool:
	_ensure_loaded()
	var row: Dictionary = _items.get(str(item_id), {})
	if row.is_empty():
		return false
	if shop_tier < int(row.get("shop_tier", TIER_NEVER)):
		return false
	if shop_slot < 0:
		return true
	if shop_slot >= 16:
		return false   # ids >= 0x64 are the non-shop facilities; 16..99 mask to 0
	return (int(row.get("shop_slot_mask", 0)) & (0x8000 >> shop_slot)) != 0


## Every item id one shop stocks at a given tier, ascending.
static func stock_for(shop_tier: int, shop_slot: int = -1) -> Array[int]:
	_ensure_loaded()
	var ids: Array[int] = []
	for key in _items.keys():
		var id := int(key)
		if is_stocked(id, shop_tier, shop_slot):
			ids.append(id)
	ids.sort()
	return ids


## The item ids that tier adds, ascending. Empty for tier 16 — it exists in the
## scripts but no item carries availability 16.
static func items_at_tier(shop_tier: int) -> Array[int]:
	_ensure_loaded()
	var ids: Array[int] = []
	for id in _tiers.get(str(shop_tier), {}).get("item_ids", []):
		ids.append(int(id))
	ids.sort()
	return ids


## The tier in force once `scenario_id` has been played. Assignments re-pin
## rather than raise — the Deep Dungeon events all assign 5 — so this walks the
## timeline in scenario order instead of taking a running maximum.
static func tier_at_scenario(scenario_id: int) -> int:
	_ensure_loaded()
	var tier := 0
	for row in _timeline:
		if int(row.get("scenario_id", 0)) > scenario_id:
			break
		tier = int(row.get("tier", tier))
	return tier


## The scenario that first assigns a tier, and its name:
## `{ "tier": int, "unlock_scenario_id": int, "unlock_scenario_name": String,
##    "item_ids": Array, "also_assigned_by": Array }`.
static func unlock_for_tier(shop_tier: int) -> Dictionary:
	_ensure_loaded()
	return _tiers.get(str(shop_tier), {})


## Every tier, ascending.
static func all_tiers() -> Array[int]:
	_ensure_loaded()
	var tiers: Array[int] = []
	for key in _tiers.keys():
		tiers.append(int(key))
	tiers.sort()
	return tiers


## Force reload (for debugging / hot edits).
static func reload() -> void:
	_loaded = false
	_items = {}
	_tiers = {}
	_timeline = []
	_ensure_loaded()
