extends Resource

## The equipped-action-menu projection of an ability — the three fields
## the equipped-set UI and the roster's max-MP check actually consume.
## See CONTEXT.md "Ability data" and ADR-0008.
##
## Built from an AbilityView; the cast path (`CombatLoop`,
## `GPUAbilityLoader`) reads the AbilityView directly via
## `AbilityDatabase.get_ability_view(id)` and does not go through this
## type, so this type does not carry charge_time / effect_id / range /
## formula or any cast-path field.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const _Self = preload("res://addons/exmateria_almanac/abilities/AbilityData.gd")
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")
const AbilityType = preload("res://addons/exmateria_almanac/abilities/AbilityType.gd")

@export var id: String = ""
@export var display_name: String = ""
@export var mp_cost: int = 0


static func from_database(ability_id: int) -> _Self:
	var view := AbilityDatabase.get_ability_view(ability_id)
	if view.is_empty():
		return null

	var ability := _Self.new()
	ability.id = str(ability_id)
	ability.display_name = view.name
	# Items don't cost MP regardless of what the record carries.
	if AbilityType.from_string(view.ability_type) == AbilityType.Type.ITEM:
		ability.mp_cost = 0
	else:
		ability.mp_cost = view.mp_cost
	return ability
