class_name EquippedAbilities
extends Node

## Equipped Abilities - Container for a unit's available abilities in combat
##
## Manages which abilities a unit can use and provides lookup methods.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityData = ExMateriaAlmanac.AbilityData


var abilities: Array[AbilityData] = []


func get_ability(id: String) -> AbilityData:
	"""Get an ability by its ID. Returns null if not found."""
	for ability in abilities:
		if ability.id == id:
			return ability
	return null


func has_ability(id: String) -> bool:
	"""Check if unit has a specific ability."""
	return get_ability(id) != null


func add_ability(ability: AbilityData) -> void:
	"""Add an ability to the equipped set."""
	if not has_ability(ability.id):
		abilities.append(ability)
