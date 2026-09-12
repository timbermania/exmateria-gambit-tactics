extends RefCounted

## Enum for ability types, replacing string comparisons.

enum Type {
	NONE = 0,
	NORMAL,
	REACTION,
	SUPPORT,
	MOVEMENT,
	ITEM,
	THROWING,
	CHARGING,
	JUMPING,
	ARITHMETICK,
}

static var _name_to_type: Dictionary = {}

static func from_string(s: String) -> int:
	if _name_to_type.is_empty():
		_name_to_type = {
			"None": Type.NONE,
			"Normal": Type.NORMAL,
			"Reaction": Type.REACTION,
			"Support": Type.SUPPORT,
			"Movement": Type.MOVEMENT,
			"Item": Type.ITEM,
			"Throwing": Type.THROWING,
			"Charging": Type.CHARGING,
			"Jumping": Type.JUMPING,
			"Arithmetick": Type.ARITHMETICK,
		}
	return _name_to_type.get(s, Type.NONE)
