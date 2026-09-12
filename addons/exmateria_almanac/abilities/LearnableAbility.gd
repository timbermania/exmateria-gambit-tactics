extends RefCounted

## The learn-list projection of an ability record — the typed row the
## job-learn screen renders. Sibling of [AbilityView] (the 1:1 mirror) and
## [AbilityData] (the cast-path projection); see CONTEXT.md "Ability data"
## and ADR-0008.
##
## Four fields: id, name, jp_cost, and category (action / reaction /
## support / movement / other). `category` is derived from which skill-set
## slot the id came from (`actions` -> "action") and the ability's
## `ability_type` (Reaction / Support / Movement under `rsm`), so it
## cannot live on [AbilityView] — the mirror is a 1:1 of the record and
## `category` is not a record field.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const _Self = preload("res://addons/exmateria_almanac/abilities/LearnableAbility.gd")
const AbilityView = preload("res://addons/exmateria_almanac/abilities/AbilityView.gd")

const CATEGORY_ACTION: String = "action"
const CATEGORY_REACTION: String = "reaction"
const CATEGORY_SUPPORT: String = "support"
const CATEGORY_MOVEMENT: String = "movement"
const CATEGORY_OTHER: String = "other"

var id: int
var name: String
var jp_cost: int
var category: String


func _init(p_id: int = 0, p_name: String = "", p_jp_cost: int = 0, p_category: String = CATEGORY_OTHER) -> void:
	id = p_id
	name = p_name
	jp_cost = p_jp_cost
	category = p_category


## Build a LearnableAbility from a raw ability record plus the skill-set
## slot it came from. The database enumerator uses this; callers outside
## the database should use [from_view] instead.
## `slot` is either "actions" or "rsm".
static func from_record(ability_id: int, record: Dictionary, slot: String) -> _Self:
	var ability_name := str(record.get("name", "Unknown"))
	var cost := int(record.get("jp_cost", 0))
	var cat := _category_for(slot, str(record.get("ability_type", "")))
	return _Self.new(ability_id, ability_name, cost, cat)


## Build a LearnableAbility from a typed view and the skill-set slot it
## came from. Use this from callers outside the database (e.g. UI that
## wants to project a manually-traversed skill set).
static func from_view(view: AbilityView, slot: String) -> _Self:
	return _Self.new(view.ability_id, view.name, view.jp_cost,
		_category_for(slot, view.ability_type))


static func _category_for(slot: String, ability_type: String) -> String:
	if slot == "actions":
		return CATEGORY_ACTION
	match ability_type:
		"Reaction":
			return CATEGORY_REACTION
		"Support":
			return CATEGORY_SUPPORT
		"Movement":
			return CATEGORY_MOVEMENT
	return CATEGORY_OTHER
