@tool
class_name UIPassiveAbilityPopup
extends UIListModalWindow
## Passive ability selection popup for Reaction, Support, and Movement slots.
##
## Name-only list with a "---" clear option at the head (ability_id = -1).
##
## Vault: [[Formation Ability Picker]]

## Emitted when a passive ability is selected.
## ability_id is -1 when the "---" clear option was picked.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase

signal passive_selected(slot_type: String, ability_id: int)


class PassiveRow:
	extends RefCounted
	var id: int
	var name: String

	func _init(p_id: int = -1, p_name: String = "") -> void:
		id = p_id
		name = p_name


const _COLUMNS = [
	{ "child": &"NameText", "field": &"name" },
]


#region Internal State

var _current_slot_type: String = "Reaction"

#endregion


## Show abilities for a passive slot type.
## slot_type should be "Reaction", "Support", or "Movement".
func show_for_type(slot_type: String, world_position: Vector3 = Vector3.ZERO) -> void:
	_current_slot_type = slot_type
	_open_with_rows(build_rows(slot_type), "Select %s" % slot_type, world_position)


func build_rows(slot_type: String) -> Array:
	var rows: Array = [PassiveRow.new(-1, "---")]

	if AbilityDatabase:
		var abilities := AbilityDatabase.get_views_by_type(slot_type)
		var temp: Array[PassiveRow] = []
		for ability in abilities:
			temp.append(PassiveRow.new(
				ability.ability_id,
				ability.name if not ability.name.is_empty() else "???"
			))
		temp.sort_custom(func(a, b): return a.name < b.name)
		for r in temp:
			rows.append(r)

	return rows


func _on_picked(row: Variant) -> void:
	var pr := row as PassiveRow
	if pr:
		passive_selected.emit(_current_slot_type, pr.id)


func _columns() -> Array:
	return _COLUMNS


func _preview_rows() -> Array:
	return build_rows("Reaction")
