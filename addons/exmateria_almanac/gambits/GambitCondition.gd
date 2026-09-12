extends RefCounted
## Condition evaluation for gambits.
##
## Supports various condition types for checking HP, MP, range, and unit counts.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const _Self = preload("res://addons/exmateria_almanac/gambits/GambitCondition.gd")

enum Type {
	SELF_HP,        ## Check self HP percentage
	ALLY_HP,        ## Check if any ally meets HP condition
	ENEMY_HP,       ## Check if any enemy meets HP condition
	SELF_MP,        ## Check self MP percentage
	ENEMY_IN_RANGE, ## Check if enemy is in attack/spell range
	ALLY_IN_RANGE,  ## Check if ally is in heal range
	ENEMY_COUNT,    ## Check number of enemies
	ALLY_COUNT,     ## Check number of allies
	ALWAYS,         ## Always true (fallback)

	# New condition types for expanded gambit system
	HAS_STATUS,     ## Unit has status X
	MISSING_STATUS, ## Unit doesn't have status X
	HP_MISSING,     ## Unit missing at least N HP
	IN_RANGE_OF,    ## Unit in range of specific ability

	# Target-agnostic types (used by new UI - apply to trigger target)
	TARGET_HP,       ## Check target's HP percentage
	TARGET_MP,       ## Check target's MP percentage
	TARGET_IN_RANGE, ## Check if target is in range of actor

	# The four the kernel has always answered but nobody could ask (#1102).
	# APPENDED, never inserted: `to_dict` serialises `type` as its ORDINAL, so a
	# saved gambit list re-reads every earlier member by position.
	IS_KO,           ## Target is KO'd — down on the field, not removed from it
	IS_ALIVE,        ## Target is not KO'd
	TARGET_DISTANCE  ## Tiles between actor and target (Manhattan), vs `threshold`
}

enum Comparator {
	LESS_THAN,
	GREATER_THAN,
	EQUALS
}

enum RangeType {
	MELEE,  ## Adjacent (distance <= 1)
	SPELL   ## Within spell range
}

## Condition type
var type: Type

## Comparator for numeric conditions
var comparator: Comparator

## Threshold value (percentage 0-100 or count)
var threshold: float

## Range type for ENEMY_IN_RANGE / ALLY_IN_RANGE conditions
var range_type: RangeType

## Status ID for HAS_STATUS / MISSING_STATUS conditions
var status_id: StringName = &""

## Ability name for IN_RANGE_OF condition
var ability_name: StringName = &""

## HP amount for HP_MISSING condition
var hp_amount: int = 0


func _init(p_type: Type = Type.ALWAYS, p_comparator: Comparator = Comparator.LESS_THAN, p_threshold: float = 0.0) -> void:
	type = p_type
	comparator = p_comparator
	threshold = p_threshold
	range_type = RangeType.MELEE


func _to_string() -> String:
	"""Human-readable condition representation."""
	var type_str = Type.keys()[type]
	var comp_str = ""
	match comparator:
		Comparator.LESS_THAN:
			comp_str = "<"
		Comparator.GREATER_THAN:
			comp_str = ">"
		Comparator.EQUALS:
			comp_str = "="

	match type:
		Type.SELF_HP:
			return "SelfHP %s %d%%" % [comp_str, int(threshold)]
		Type.ALLY_HP:
			return "AllyHP %s %d%%" % [comp_str, int(threshold)]
		Type.ENEMY_HP:
			return "EnemyHP %s %d%%" % [comp_str, int(threshold)]
		Type.SELF_MP:
			return "SelfMP %s %d%%" % [comp_str, int(threshold)]
		Type.ENEMY_IN_RANGE:
			var range_str = "melee" if range_type == RangeType.MELEE else "spell"
			return "EnemyInRange(%s)" % range_str
		Type.ALLY_IN_RANGE:
			var range_str = "melee" if range_type == RangeType.MELEE else "spell"
			return "AllyInRange(%s)" % range_str
		Type.ENEMY_COUNT:
			return "EnemyCount %s %d" % [comp_str, int(threshold)]
		Type.ALLY_COUNT:
			return "AllyCount %s %d" % [comp_str, int(threshold)]
		Type.ALWAYS:
			return "Always"
		Type.HAS_STATUS:
			return "HasStatus(%s)" % status_id
		Type.MISSING_STATUS:
			return "MissingStatus(%s)" % status_id
		Type.HP_MISSING:
			return "HPMissing >= %d" % hp_amount
		Type.IN_RANGE_OF:
			return "InRangeOf(%s)" % ability_name
		Type.TARGET_HP:
			return "HP %s %d%%" % [comp_str, int(threshold)]
		Type.TARGET_MP:
			return "MP %s %d%%" % [comp_str, int(threshold)]
		Type.TARGET_IN_RANGE:
			var range_str = "melee" if range_type == RangeType.MELEE else "spell"
			return "In Range(%s)" % range_str
		Type.IS_KO:
			return "IsKO"
		Type.IS_ALIVE:
			return "IsAlive"
		Type.TARGET_DISTANCE:
			return "Distance %s %d" % [comp_str, int(threshold)]
	return type_str


# 🔴 `get_sentence_text` LEFT AT #1160. It is `GambitProse.condition_sentence`
# in `src/ui3/` now — ADR-0280 dec. 4, the clause a player reads is the host's
# opinion about how to say this, not something the condition knows about
# itself. Its only external caller was `src/ui3/detail/GambitOptions.gd`, which
# is where it went.
#
# `get_ui_display_data` below STAYED, and the two are not the same thing
# wearing different names. This returns the three STRUCTURED parts — `type`,
# `comparator`, `threshold` — which the editor's dropdowns read as FIELDS, one
# per control, and which `_to_string` and the sentence both compose from. It is
# the condition describing its own shape; the sentence was the condition
# writing English.

## Return structured condition data for UI rendering.
func get_ui_display_data() -> Dictionary:
	var comp_str = ""
	match comparator:
		Comparator.LESS_THAN: comp_str = "<"
		Comparator.GREATER_THAN: comp_str = ">"
		Comparator.EQUALS: comp_str = "="

	var type_str = ""
	var threshold_str = ""

	match type:
		# HP conditions - all display as just "HP" (target-agnostic)
		Type.SELF_HP, Type.ALLY_HP, Type.ENEMY_HP, Type.TARGET_HP:
			type_str = "HP"
			threshold_str = "%d%%" % int(threshold)
		# MP conditions - all display as just "MP" (target-agnostic)
		Type.SELF_MP, Type.TARGET_MP:
			type_str = "MP"
			threshold_str = "%d%%" % int(threshold)
		# Range conditions - all display as "In Range" (target-agnostic)
		Type.ENEMY_IN_RANGE, Type.ALLY_IN_RANGE, Type.TARGET_IN_RANGE:
			type_str = "In Range"
			comp_str = ""
			threshold_str = ""
		Type.ENEMY_COUNT:
			type_str = "Enemies"
			threshold_str = "%d" % int(threshold)
		Type.ALLY_COUNT:
			type_str = "Allies"
			threshold_str = "%d" % int(threshold)
		Type.ALWAYS:
			type_str = "Else"
		Type.HAS_STATUS:
			type_str = "Has Status"
			comp_str = ""
			threshold_str = String(status_id)
		Type.MISSING_STATUS:
			type_str = "Missing"
			comp_str = ""
			threshold_str = String(status_id)
		Type.HP_MISSING:
			type_str = "HP Missing"
			comp_str = ">="
			threshold_str = "%d" % hp_amount
		Type.IN_RANGE_OF:
			type_str = "In Range"
			comp_str = "of"
			threshold_str = String(ability_name)
		Type.IS_KO:
			type_str = "KO'd"
			comp_str = ""
			threshold_str = ""
		Type.IS_ALIVE:
			type_str = "Alive"
			comp_str = ""
			threshold_str = ""
		Type.TARGET_DISTANCE:
			type_str = "Distance"
			threshold_str = "%d" % int(threshold)

	return {"type": type_str, "comparator": comp_str, "threshold": threshold_str}


## Static factory methods for common conditions

static func always() -> _Self:
	"""Create condition: Always true (fallback)"""
	return _Self.new(Type.ALWAYS)


static func has_status(p_status_id: StringName) -> _Self:
	"""Create condition: Unit has status X"""
	var cond = _Self.new(Type.HAS_STATUS)
	cond.status_id = p_status_id
	return cond


static func missing_status(p_status_id: StringName) -> _Self:
	"""Create condition: Unit doesn't have status X"""
	var cond = _Self.new(Type.MISSING_STATUS)
	cond.status_id = p_status_id
	return cond


## Target-agnostic factory methods (for new UI system)

static func target_hp_below(percent: float) -> _Self:
	"""Create condition: Target HP < percent (applies to trigger target)"""
	return _Self.new(Type.TARGET_HP, Comparator.LESS_THAN, percent)


static func target_hp_above(percent: float) -> _Self:
	"""Create condition: Target HP > percent (applies to trigger target)"""
	return _Self.new(Type.TARGET_HP, Comparator.GREATER_THAN, percent)


static func target_mp_below(percent: float) -> _Self:
	"""Create condition: Target MP < percent (applies to trigger target)"""
	return _Self.new(Type.TARGET_MP, Comparator.LESS_THAN, percent)


## Create condition: target is KO'd.
##
## 🔴 NOT [code]has_status(&"dead")[/code]. KO is the CONDITION a unit is in — the
## kernel answers it from [code]FLAG_DEAD[/code] in the unit's flag word, via
## [code]is_unit_dead()[/code]. [code]STATUS_DEAD[/code] is status BIT 0, a
## separate word that nothing in the tree sets or reads. The status spelling
## encodes cleanly, passes every guard, and never fires; this one does.
static func is_ko() -> _Self:
	return _Self.new(Type.IS_KO)


## Create condition: target is NOT KO'd.
static func is_alive() -> _Self:
	return _Self.new(Type.IS_ALIVE)


## Create condition: target is nearer than [param tiles].
##
## Distance is MANHATTAN — planar, level-blind, wall-blind — which is FFT's own
## range metric and a different question from the path cost that ranks
## [code]NEAREST[/code] pools or the reach that
## [constant Type.TARGET_IN_RANGE] asks the action about.
static func target_within(tiles: float) -> _Self:
	return _Self.new(Type.TARGET_DISTANCE, Comparator.LESS_THAN, tiles)


## Create condition: target is further than [param tiles]. Manhattan, as [method target_within].
static func target_beyond(tiles: float) -> _Self:
	return _Self.new(Type.TARGET_DISTANCE, Comparator.GREATER_THAN, tiles)


static func target_in_range(p_range_type: RangeType = RangeType.MELEE) -> _Self:
	"""Create condition: Target is in range of actor"""
	var cond = _Self.new(Type.TARGET_IN_RANGE)
	cond.range_type = p_range_type
	return cond


# ============================================================================
# SERIALIZATION
# ============================================================================

func to_dict() -> Dictionary:
	"""Convert to dictionary for JSON serialization."""
	return {
		"type": type,
		"comparator": comparator,
		"threshold": threshold,
		"range_type": range_type,
		"status_id": String(status_id),
		"ability_name": String(ability_name),
		"hp_amount": hp_amount,
	}


static func from_dict(data: Dictionary) -> _Self:
	"""Create from dictionary (JSON deserialization)."""
	var c = _Self.new()
	c.type = data.get("type", Type.ALWAYS)
	c.comparator = data.get("comparator", Comparator.LESS_THAN)
	c.threshold = data.get("threshold", 0.0)
	c.range_type = data.get("range_type", RangeType.MELEE)
	c.status_id = StringName(data.get("status_id", ""))
	c.ability_name = StringName(data.get("ability_name", ""))
	c.hp_amount = data.get("hp_amount", 0)
	return c
