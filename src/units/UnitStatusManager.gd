class_name UnitStatusManager
extends Node

## UnitStatusManager - Manages unit status effects
##
## A per-unit component that owns status state. Death becomes "just another status"
## with special priority. Systems use the query API instead of scattered is_dead checks.
##
## Status effects:
##   &"dead" - Unit has 0 HP (triggers DYING animation, blocks all actions)
##   Future: &"poisoned", &"hasted", &"stopped", &"petrified", etc.

# Signals for status changes
signal status_added(status_id: StringName, source: Node)
signal status_removed(status_id: StringName, reason: String)
signal unit_incapacitated()  # Emitted when unit becomes unable to act (death, petrify, stop)

# Internal status storage
# Key: StringName (status ID), Value: Dictionary with metadata
# Example: { &"dead": { "source": attacker_node, "added_time": 12345.0 } }
var _statuses: Dictionary = {}

# Parent unit reference (cached for efficiency)
var _unit: Node = null


func _ready() -> void:
	_unit = get_parent()
	if not _unit:
		push_warning("[UnitStatusManager] No parent unit found")


## Query API - systems use these instead of scattered is_dead checks

func is_dead() -> bool:
	"""Check if unit is dead (has 'dead' status)."""
	return has_status(&"dead")


## Status Management

func add_status(status_id: StringName, source: Node = null, duration: float = -1.0) -> bool:
	"""Add a status effect to the unit.

	Args:
		status_id: Unique identifier for the status (e.g., &"dead", &"poisoned")
		source: Node that caused this status (e.g., the attacking unit)
		duration: Duration in seconds (-1.0 = permanent until removed)

	Returns:
		true if status was added, false if already present
	"""
	if has_status(status_id):
		return false

	_statuses[status_id] = {
		"source": source,
		"added_time": Time.get_ticks_msec() / 1000.0,
		"duration": duration
	}

	status_added.emit(status_id, source)

	# Check if this status causes incapacitation
	if _is_incapacitating_status(status_id):
		unit_incapacitated.emit()

	return true


func remove_status(status_id: StringName, reason: String = "expired") -> bool:
	"""Remove a status effect from the unit.

	Args:
		status_id: Status to remove
		reason: Why the status was removed (for logging/debugging)

	Returns:
		true if status was removed, false if not present
	"""
	if not has_status(status_id):
		return false

	_statuses.erase(status_id)
	status_removed.emit(status_id, reason)

	return true


func has_status(status_id: StringName) -> bool:
	"""Check if unit has a specific status.

	Args:
		status_id: Status to check for

	Returns:
		true if unit has this status
	"""
	return _statuses.has(status_id)


func get_all_statuses() -> Array[StringName]:
	"""Get list of all active status IDs.

	Returns:
		Array of status StringNames
	"""
	var result: Array[StringName] = []
	for key in _statuses.keys():
		result.append(key)
	return result


## Internal Helpers

func _is_incapacitating_status(status_id: StringName) -> bool:
	"""Check if a status causes the unit to become incapacitated.

	Incapacitation means the unit cannot act and should trigger
	special handling (cancel pending actions, end turn, etc.)
	"""
	return status_id in [&"dead", &"stopped", &"petrified"]
