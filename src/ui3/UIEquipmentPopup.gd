@tool
class_name UIEquipmentPopup
extends UIListModalWindow
## Equipment selection popup showing items available for a specific slot.
##
## Extends UIListModalWindow with equipment-specific functionality:
## - Filtering items by equipment slot
## - Displaying item stats (WP, EV, bonuses, …) as a pre-rendered second column
## - Item database integration

## Emitted when an item is equipped

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ItemDatabase = ExMateriaAlmanac.ItemDatabase

signal item_equipped(slot: int, item_id: int)


class EquipRow:
	extends RefCounted
	var id: int
	var name: String
	## Pre-rendered stats column. Built at row-construction time so the heavy
	## formatting (bonuses, elements, statuses) happens once per populate, not
	## per virtual-scroll factory call.
	var stats: String

	func _init(p_id: int = -1, p_name: String = "", p_stats: String = "") -> void:
		id = p_id
		name = p_name
		stats = p_stats


## Subclass-specific defaults
const _EQUIPMENT_DEFAULTS = {
	"stats_offset_x": 90.0,
	"stats_scale": 0.7,
	"stats_palette": 0,
}


const _COLUMNS = [
	{ "child": &"NameText",  "field": &"name" },
	{ "child": &"StatsText", "field": &"stats",
	  "offset_x_prop": &"stats_offset_x",
	  "scale_prop":    &"stats_scale",
	  "palette_prop":  &"stats_palette",
	  "hide_when_empty": true },
]

#region Configuration Exports

@export_group("Equipment Display")

## Stats text offset from item name (X position in virtual pixels)
@export var stats_offset_x: float = 90.0:
	set(value):
		if stats_offset_x == value:
			return
		stats_offset_x = value
		_mark_layout_dirty()

## Stats text scale
@export var stats_scale: float = 0.7:
	set(value):
		if stats_scale == value:
			return
		stats_scale = value
		_mark_layout_dirty()

## Stats text palette
@export var stats_palette: int = 0:
	set(value):
		if stats_palette == value:
			return
		stats_palette = value
		_mark_layout_dirty()

#endregion

#region Internal State

var _current_slot: int = -1
var _current_unit: Node = null

#endregion


## Show equipment options for a specific slot
func show_for_slot(slot: int, unit: Node, world_position: Vector3 = Vector3.ZERO) -> void:
	_current_slot = slot
	_current_unit = unit

	var slot_names = ["R.Hand", "L.Hand", "Head", "Body", "Accessory"]
	var slot_name: String = slot_names[slot] if slot < slot_names.size() else "Item"
	_open_with_rows(build_rows(slot, unit), "Select %s" % slot_name, world_position)


func build_rows(slot: int, _unit: Node) -> Array:
	var rows: Array = []
	for item in _get_items_for_slot(slot):
		var item_id: int = int(item.get("id", -1))
		rows.append(EquipRow.new(
			item_id,
			item.get("name", "???"),
			_format_item_stats(item_id, slot)
		))
	return rows


func _get_items_for_slot(slot: int) -> Array:
	if not ItemDatabase:
		return []

	match slot:
		0:  # RIGHT_HAND
			return ItemDatabase.get_weapons()
		1:  # LEFT_HAND
			return ItemDatabase.get_shields()
		2:  # HEAD
			var head_armor: Array = []
			for armor in ItemDatabase.get_armor():
				if ItemDatabase.is_head_armor(int(armor.get("id", -1))):
					head_armor.append(armor)
			return head_armor
		3:  # BODY
			var body_armor: Array = []
			for armor in ItemDatabase.get_armor():
				if ItemDatabase.is_body_armor(int(armor.get("id", -1))):
					body_armor.append(armor)
			return body_armor
		4:  # ACCESSORY
			return ItemDatabase.get_accessories()
	return []


func _format_item_stats(item_id: int, slot: int) -> String:
	if not ItemDatabase:
		return ""

	var parts: Array[String] = []

	match slot:
		0:  # RIGHT_HAND (weapons)
			parts.append("WP:%d" % ItemDatabase.get_weapon_power(item_id))
			var ev = ItemDatabase.get_weapon_evade(item_id)
			if ev > 0:
				parts.append("EV:%d%%" % ev)
		1:  # LEFT_HAND (shields)
			parts.append("PB:%d%%" % ItemDatabase.get_physical_block(item_id))
			parts.append("MB:%d%%" % ItemDatabase.get_magic_block(item_id))
		2, 3:  # HEAD, BODY (armor)
			var hp = ItemDatabase.get_hp_bonus(item_id)
			if hp > 0:
				parts.append("HP+%d" % hp)
			var mp = ItemDatabase.get_mp_bonus(item_id)
			if mp > 0:
				parts.append("MP+%d" % mp)
		4:  # ACCESSORY
			var hp = ItemDatabase.get_hp_bonus(item_id)
			if hp > 0:
				parts.append("HP+%d" % hp)
			var mp = ItemDatabase.get_mp_bonus(item_id)
			if mp > 0:
				parts.append("MP+%d" % mp)

	var bonuses_str := _format_bonuses(item_id)
	if not bonuses_str.is_empty():
		if not parts.is_empty():
			return " ".join(parts) + "   " + bonuses_str
		return bonuses_str
	return " ".join(parts)


## Format stat bonuses, elemental effects, and status immunities
func _format_bonuses(item_id: int) -> String:
	if not ItemDatabase:
		return ""

	var parts: Array[String] = []

	var bonuses = ItemDatabase.get_stat_bonuses(item_id)
	if bonuses.get("pa", 0) > 0:
		parts.append("PA+%d" % bonuses["pa"])
	if bonuses.get("ma", 0) > 0:
		parts.append("MA+%d" % bonuses["ma"])
	if bonuses.get("speed", 0) > 0:
		parts.append("SP+%d" % bonuses["speed"])

	var elements = ItemDatabase.get_elements(item_id)
	for elem in elements.get("weapon_elements", []):
		parts.append(_abbrev_element(elem))
	for elem in elements.get("absorb", []):
		parts.append(_abbrev_element(elem) + ":A")
	for elem in elements.get("cancel", []):
		parts.append(_abbrev_element(elem) + ":N")
	for elem in elements.get("half", []):
		parts.append(_abbrev_element(elem) + ":H")
	for elem in elements.get("strengthen", []):
		parts.append(_abbrev_element(elem) + ":S")

	var statuses = ItemDatabase.get_statuses(item_id)
	for status in statuses.get("permanent", []):
		parts.append("+" + _abbrev_status(status))
	for status in statuses.get("starting", []):
		parts.append("@" + _abbrev_status(status))
	for status in statuses.get("immunity", []):
		parts.append("!" + _abbrev_status(status))

	return "   ".join(parts)


## Abbreviate element names for compact display
func _abbrev_element(elem: String) -> String:
	match elem:
		"Fire": return "Fi"
		"Lightning": return "Lt"
		"Ice": return "Ic"
		"Wind": return "Wi"
		"Earth": return "Ea"
		"Water": return "Wa"
		"Holy": return "Ho"
		"Dark": return "Dk"
		_: return elem.left(2)


## Abbreviate status names for compact display
func _abbrev_status(status: String) -> String:
	match status:
		"Reraise": return "Rer"
		"Regen": return "Rgn"
		"Haste": return "Hst"
		"Protect": return "Prt"
		"Shell": return "Shl"
		"Float": return "Flt"
		"Frog": return "Frg"
		"Poison": return "Psn"
		"Sleep": return "Slp"
		"Confusion": return "Cnf"
		"Silence": return "Sil"
		"Petrify": return "Ptr"
		"Stop": return "Stp"
		"Slow": return "Slw"
		"Don't Move": return "DM"
		"Don't Act": return "DA"
		"Death Sentence": return "DS"
		"Charm": return "Chm"
		"Berserk": return "Bsk"
		"Blind": return "Bln"
		"Oil": return "Oil"
		"Undead": return "Und"
		_: return status.left(3)


func _on_picked(row: Variant) -> void:
	var er := row as EquipRow
	if er:
		item_equipped.emit(_current_slot, er.id)


func _columns() -> Array:
	return _COLUMNS


func _preview_rows() -> Array:
	# Slot 0 (weapons) is the richest column for preview — shows WP, EV, and bonuses.
	return build_rows(0, null)


## Override to include equipment-specific defaults in sync check
func _get_all_defaults() -> Dictionary:
	var defaults = super._get_all_defaults()
	defaults.merge(_EQUIPMENT_DEFAULTS)
	return defaults
