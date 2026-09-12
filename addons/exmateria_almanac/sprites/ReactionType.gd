extends RefCounted

## Enum for reaction animation types + SEQ animation ID lookup.
##
## Combines the type enum with the reaction animation database
## (previously in ReactionDatabase.gd).
##
## Usage:
##   ReactionType.from_string("evade") -> Type.EVADE
##   ReactionType.get_seq_id("type1", "evade") -> 24

enum Type {
	NONE = 0,
	TAKING_DAMAGE,
	RECEIVE_HEAL,
	EVADE,
	SHIELD_BLOCK,
	BLADE_GRASP,
}

static var _name_to_type: Dictionary = {}

static func from_string(s: String) -> int:
	if _name_to_type.is_empty():
		_name_to_type = {
			"taking_damage": Type.TAKING_DAMAGE,
			"receive_heal": Type.RECEIVE_HEAL,
			"evade": Type.EVADE,
			"shield_block": Type.SHIELD_BLOCK,
			"blade_grasp": Type.BLADE_GRASP,
		}
	return _name_to_type.get(s, Type.NONE)

static func to_string_key(type: int) -> String:
	match type:
		Type.TAKING_DAMAGE: return "taking_damage"
		Type.RECEIVE_HEAL: return "receive_heal"
		Type.EVADE: return "evade"
		Type.SHIELD_BLOCK: return "shield_block"
		Type.BLADE_GRASP: return "blade_grasp"
		_: return "unknown"

# --- Reaction Animation Database ---
# Loads reaction_animations.json which maps sprite types to their reaction SEQ animation IDs.

static var _anim_data: Dictionary = {}

static func _load_anim_data() -> void:
	var file = FileAccess.open("res://addons/exmateria_almanac/sprites/reaction_animations.json", FileAccess.READ)
	if not file:
		push_warning("[ReactionType] Failed to open reaction_animations.json")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_anim_data = parsed

static func get_seq_id(sprite_type: String, reaction_name: String) -> int:
	if _anim_data.is_empty():
		_load_anim_data()
	var type_data = _anim_data.get(sprite_type, {})
	var reactions = type_data.get("reactions", {})
	var reaction = reactions.get(reaction_name, {})
	return int(reaction.get("seq_animation_id", -1))
