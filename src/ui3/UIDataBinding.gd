class_name UIDataBinding
extends RefCounted
## Data binding resolver for Combat UI.
##
## Resolves binding fields from units and rosters to display values.
## Supports unit stats (HP, MP, name), action context, and equipment.

## Binding types
enum BindingType {
	STATIC,      ## No binding, text is literal
	UNIT_STAT,   ## HP, MP, name, level from unit data
	UNIT_ACTION, ## Current action, target from debug_action_context
	ROSTER_FRAME ## Portrait with sprite_id from roster
}


## Resolve a stat field from a unit.
## Returns the value as a string, or fallback if unit is null.
static func resolve_stat(unit: Node, field: String, fallback: String = "") -> String:
	if not unit:
		return fallback

	match field:
		"hp_current":
			return str(unit.current_hp) if "current_hp" in unit else fallback
		"hp_max":
			return str(unit.max_hp) if "max_hp" in unit else fallback
		"mp_current":
			return str(unit.current_mp) if "current_mp" in unit else fallback
		"mp_max":
			return str(unit.max_mp) if "max_mp" in unit else fallback
		"unit_name":
			return unit.name if unit else fallback
		"level":
			return str(unit.level) if "level" in unit else fallback
		"body_sprite_id":
			return str(unit.body_sprite_id) if "body_sprite_id" in unit else fallback

	return fallback


## Resolve an action context field from a unit.
## Uses debug_action_context dictionary on the unit.
static func resolve_action(unit: Node, field: String, fallback: String = "") -> String:
	if not unit:
		return fallback

	if not "debug_action_context" in unit:
		return fallback

	var context: Dictionary = unit.debug_action_context

	match field:
		"action_name":
			return context.get("action_type", fallback)
		"target_name":
			var target = context.get("target")
			if target is Node:
				return target.name
			return fallback
		"goal_name":
			return context.get("goal_name", fallback)
		"gambit_triggered":
			return context.get("gambit_triggered", fallback)

	return fallback


## Resolve a formatted string with multiple binding fields.
## Format string uses %d or %s placeholders, fields array provides values.
## Example: format="HP %d/%d", fields=["hp_current", "hp_max"]
static func resolve_format(unit: Node, format_str: String, fields: Array, fallback: String = "") -> String:
	if not unit:
		return fallback

	var values: Array = []
	for field in fields:
		var field_str = str(field)
		var value = resolve_stat(unit, field_str, "?")
		values.append(value)

	# Use format string with values
	if values.size() > 0:
		return format_str % values

	return format_str


## Get sprite_id from unit for portrait binding.
static func get_sprite_id(unit: Node) -> int:
	if not unit:
		return -1

	if "body_sprite_id" in unit:
		return unit.body_sprite_id

	return -1


## Get sprite_id from roster data.
## Resolve equipment name from unit.
## slot: "weapon", "shield", "helm", "body", "accessory"
## Resolve ability slot from unit.
## slot: "job", "subjob", "reaction", "support", "movement"
## Parse binding type from string.
static func parse_binding_type(type_str: String) -> BindingType:
	match type_str.to_lower():
		"static":
			return BindingType.STATIC
		"unit_stat":
			return BindingType.UNIT_STAT
		"unit_action":
			return BindingType.UNIT_ACTION
		"roster_frame":
			return BindingType.ROSTER_FRAME
	return BindingType.STATIC


## Resolve a binding config to text value.
## config should have: binding_type, binding_field(s), format (optional), fallback (optional)
static func resolve_binding(unit: Node, config: Dictionary) -> String:
	var binding_type_str = config.get("binding_type", "static")
	var binding_type = parse_binding_type(binding_type_str)
	var fallback = config.get("fallback", "")

	match binding_type:
		BindingType.STATIC:
			return config.get("text", fallback)

		BindingType.UNIT_STAT:
			if config.has("binding_fields") and config.has("format"):
				# Multiple fields with format string
				return resolve_format(unit, config["format"], config["binding_fields"], fallback)
			elif config.has("binding_field"):
				# Single field
				return resolve_stat(unit, config["binding_field"], fallback)

		BindingType.UNIT_ACTION:
			if config.has("binding_field"):
				return resolve_action(unit, config["binding_field"], fallback)

		BindingType.ROSTER_FRAME:
			# Roster frames don't resolve to text, they resolve to sprite_id
			return fallback

	return fallback
