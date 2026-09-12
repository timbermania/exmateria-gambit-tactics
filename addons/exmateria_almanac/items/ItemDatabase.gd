extends RefCounted

## Item Database - Auto-generated lookup for FFT item data
##
## Contains all 254 items with their stats, attributes, and equipment data.
## Item categories:
## - Weapons (0-127): Knives, swords, katanas, axes, rods, staffs, etc.
## - Shields (128-143): Block rates
## - Armor (144-207): Helms, body armor, clothes, robes
## - Accessories (208-239): Shoes, gauntlets, rings, armlets, mantles
## - Consumables (240-253): Potions, ethers, etc.

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const ITEMS_PATH = "res://addons/exmateria_almanac/items/items.json"
const ATTRIBUTES_PATH = "res://addons/exmateria_almanac/items/item_attributes.json"

static var _items: Dictionary = {}
static var _attributes: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	"""Ensure data is loaded before access."""
	if _loaded:
		return
	_items = JsonAsset.load_dict(ITEMS_PATH)
	_attributes = JsonAsset.load_dict(ATTRIBUTES_PATH)
	_loaded = true
	print("[ItemDatabase] Loaded %d items, %d attributes" % [_items.size(), _attributes.size()])


static func get_item(item_id: int) -> Dictionary:
	"""Get item data by ID (0-253)."""
	_ensure_loaded()
	var key = str(item_id)
	if _items.has(key):
		return _items[key]
	return {}


static func get_item_name(item_id: int) -> String:
	"""Get item name by ID."""
	var item = get_item(item_id)
	return item.get("name", "Unknown")


static func get_items_by_category(category: String) -> Array:
	"""Get all items of a specific category (weapon, shield, armor, accessory, consumable)."""
	_ensure_loaded()
	var result = []
	for key in _items:
		var item = _items[key]
		if item.get("category") == category:
			result.append(item)
	return result


static func get_weapons() -> Array:
	"""Get all weapon items (ID 0-127)."""
	return get_items_by_category("weapon")


static func get_shields() -> Array:
	"""Get all shield items (ID 128-143)."""
	return get_items_by_category("shield")


static func get_armor() -> Array:
	"""Get all armor items (ID 144-207)."""
	return get_items_by_category("armor")


static func get_accessories() -> Array:
	"""Get all accessory items (ID 208-239)."""
	return get_items_by_category("accessory")


# Item type helpers

static func is_weapon(item_id: int) -> bool:
	"""Check if item ID is a weapon (0-127)."""
	return item_id >= 0 and item_id < 128


static func is_shield(item_id: int) -> bool:
	"""Check if item ID is a shield (128-143)."""
	return item_id >= 128 and item_id < 144


static func is_head_armor(item_id: int) -> bool:
	"""Check if item ID is head armor (helm/hat)."""
	var item = get_item(item_id)
	var item_type = item.get("item_type", "")
	return item_type in ["Helmet", "Hat", "HairAdornment"]


static func is_body_armor(item_id: int) -> bool:
	"""Check if item ID is body armor."""
	var item = get_item(item_id)
	var item_type = item.get("item_type", "")
	return item_type in ["Armor", "Clothing", "Robe"]


# Stat calculation helpers

static func get_weapon_power(item_id: int) -> int:
	"""Get weapon power for a weapon item."""
	var item = get_item(item_id)
	var weapon = item.get("weapon", {})
	return int(weapon.get("weapon_power", 0))


static func get_weapon_range(item_id: int) -> int:
	"""Get attack range for a weapon item."""
	var item = get_item(item_id)
	var weapon = item.get("weapon", {})
	return int(weapon.get("range", 1))


static func get_weapon_evade(item_id: int) -> int:
	"""Get evasion percentage for a weapon item (W-EV).

	In FFT, some weapons (mainly knives and ninja blades) provide evasion.
	This is separate from shield block and only applies to physical attacks.
	"""
	var item = get_item(item_id)
	var weapon = item.get("weapon", {})
	return int(weapon.get("evade_percent", 0))


static func get_weapon_formula(item_id: int) -> int:
	"""Get the damage formula ID for a weapon item.

	Common formulas:
	- 1: PA * WP (most weapons)
	- 2: PA * (PA/2) (bare fist)
	- 7: MA * WP (rods, staves)
	"""
	var item = get_item(item_id)
	var weapon = item.get("weapon", {})
	return int(weapon.get("formula", 1))


static func get_weapon_flags(item_id: int) -> Dictionary:
	"""Get weapon attack type flags.

	Returns dictionary with:
	- striking: bool - Overhead/swing attacks (axes)
	- lunging: bool - Thrust attacks (swords, spears)
	- direct: bool - Straight-line projectiles (bows)
	- arc: bool - Arcing projectiles (thrown items)
	"""
	var item = get_item(item_id)
	var weapon = item.get("weapon", {})
	var flags = weapon.get("weapon_flags", {})
	return {
		"striking": flags.get("striking", false),
		"lunging": flags.get("lunging", false),
		"direct": flags.get("direct", false),
		"arc": flags.get("arc", false),
	}


static func get_physical_block(item_id: int) -> int:
	"""Get physical block rate for a shield."""
	var item = get_item(item_id)
	var shield = item.get("shield", {})
	return int(shield.get("physical_block", 0))


static func get_magic_block(item_id: int) -> int:
	"""Get magic block rate for a shield."""
	var item = get_item(item_id)
	var shield = item.get("shield", {})
	return int(shield.get("magic_block", 0))


static func get_accessory_evade(item_id: int) -> int:
	"""Get physical evade (A-EV) granted by an accessory (mantles, shoes).

	items.json does not yet parse an accessory evade field, so this returns 0 for
	current data — the honest data path (mirrors get_physical_block / get_weapon_evade),
	lighting up for free once the field is extracted. See UnitProgression.get_accessory_evade.
	"""
	var item = get_item(item_id)
	var accessory = item.get("accessory", {})
	return int(accessory.get("evade_percent", 0))


static func get_hp_bonus(item_id: int) -> int:
	"""Get HP bonus from armor/accessory."""
	var item = get_item(item_id)
	# Check armor-specific data
	var armor = item.get("armor", {})
	if armor:
		return int(armor.get("hp_bonus", 0))
	# Check accessory-specific data
	var accessory = item.get("accessory", {})
	if accessory:
		return int(accessory.get("hp_bonus", 0))
	return 0


static func get_mp_bonus(item_id: int) -> int:
	"""Get MP bonus from armor/accessory."""
	var item = get_item(item_id)
	var armor = item.get("armor", {})
	if armor:
		return int(armor.get("mp_bonus", 0))
	var accessory = item.get("accessory", {})
	if accessory:
		return int(accessory.get("mp_bonus", 0))
	return 0


static func get_stat_bonuses(item_id: int) -> Dictionary:
	"""Get all stat bonuses from item attributes.

	Returns dictionary with:
	- pa_bonus, ma_bonus, speed_bonus, move_bonus, jump_bonus
	- hp_bonus, mp_bonus (from armor/accessory data)
	"""
	var item = get_item(item_id)
	var attr = item.get("attributes", {})

	return {
		"pa": int(attr.get("pa_bonus", 0)),
		"ma": int(attr.get("ma_bonus", 0)),
		"speed": int(attr.get("speed_bonus", 0)),
		"move": int(attr.get("move_bonus", 0)),
		"jump": int(attr.get("jump_bonus", 0)),
		"hp": get_hp_bonus(item_id),
		"mp": get_mp_bonus(item_id),
	}


static func get_elements(item_id: int) -> Dictionary:
	"""Get elemental properties from item attributes.

	Returns dictionary with:
	- absorb, cancel, half, weak, strengthen (arrays of element names)
	- weapon_elements (for weapons)
	"""
	var item = get_item(item_id)
	var attr = item.get("attributes", {})
	var weapon = item.get("weapon", {})

	return {
		"absorb": attr.get("absorb_elements", []),
		"cancel": attr.get("cancel_elements", []),
		"half": attr.get("half_elements", []),
		"weak": attr.get("weak_elements", []),
		"strengthen": attr.get("strengthen_elements", []),
		"weapon_elements": weapon.get("elements", []),
	}


static func get_statuses(item_id: int) -> Dictionary:
	"""Get status effects from item attributes.

	Returns dictionary with:
	- permanent: Array of status names granted permanently while equipped
	- immunity: Array of status names the wearer is immune to
	- starting: Array of status names applied at battle start

	Per ADR-0013, the `item_attributes.json` already carries decoded name
	arrays (set form); this is now a typed pass-through.
	"""
	var item = get_item(item_id)
	var attr = item.get("attributes", {})

	return {
		"permanent": attr.get("permanent_statuses", []),
		"immunity": attr.get("status_immunity", []),
		"starting": attr.get("starting_statuses", []),
	}


# Weapon sprite data helpers

static func get_weapon_graphic(item_id: int) -> int:
	"""Get weapon graphic index for sprite rendering.

	The graphic field maps to vertical frame selection in WEP1.tga.

	Args:
		item_id: Item ID (0-253)

	Returns:
		Graphic index for weapon sprite rendering
	"""
	var item = get_item(item_id)
	return int(item.get("graphic", 0))


static func get_weapon_palette(item_id: int) -> int:
	"""Get weapon palette index for sprite coloring.

	Args:
		item_id: Item ID (0-253)

	Returns:
		Palette index for weapon coloring
	"""
	var item = get_item(item_id)
	return int(item.get("palette", 0))


static func get_item_type_id(item_id: int) -> int:
	"""Get item type ID for animation selection.

	Maps to weapon categories for WEP1 animation selection:
	- 1-9: Swing weapons (Knife, Sword, Axe, etc.)
	- 10: Gun
	- 11-12: Bow/Crossbow
	- 13: Instrument
	- 14: Book
	- 15-16: Poke weapons (Polearm, Pole)
	- 17-18: Throw weapons (Bag, Cloth)
	- 32-34: Thrown items (Shuriken, Ball, Consumable)

	Args:
		item_id: Item ID (0-253)

	Returns:
		Item type ID for animation category mapping
	"""
	var item = get_item(item_id)
	return int(item.get("item_type_id", 0))


# Item icon spritesheet helpers for projectile rendering


static func get_item_graphic(item_id: int) -> int:
	"""Get item graphic index for icon lookup.

	Alias for get_weapon_graphic that works for all item types.

	Args:
		item_id: Item ID (0-253)

	Returns:
		Graphic index for item sprite rendering
	"""
	var item = get_item(item_id)
	return int(item.get("graphic", 0))


# ITEM.BIN from EVENT folder - 256x256 texture
# Icon size TBD based on inspection - trying 16x16 first (16 icons per row)
const ITEM_ICON_SIZE := 16  # Each icon is 16x16 pixels
const ITEM_SHEET_WIDTH := 256  # Spritesheet width in pixels
const ITEM_ICONS_PER_ROW := 16  # 256 / 16 = 16 icons per row
const ITEM_SHEET_HEIGHT := 256  # 256x256 texture from ITEM.BIN
