class_name ValidationUtils
extends Node

## Centralized validation utilities
##
## Provides reusable validation methods to eliminate duplicate validation logic
## across the codebase. All methods are static and can be called without instantiation.

## Unit Validation

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const TerrainCell = ExMateriaSchema.TerrainCell

static func is_valid_unit(unit: Unit) -> bool:
	"""Check if unit reference is valid (not null, instance valid)

	Args:
		unit: Unit to validate

	Returns:
		true if unit exists and is valid, false otherwise
	"""
	return unit != null and is_instance_valid(unit)

static func has_logical_position(unit: Unit) -> bool:
	"""Check if unit has a valid logical tile position

	Args:
		unit: Unit to check

	Returns:
		true if the unit is standing on a grid cell, false otherwise
	"""
	if not is_valid_unit(unit):
		return false
	# The absence state is a SENTINEL, not `null` (ADR-0166 dec. 3): `current_cell` is
	# a `Vector2i`, so "unplaced" cannot be spelled by a missing object.
	return unit.movement_component.current_cell != TerrainCell.NONE

## Tile Validation

## Component Validation

static func validate_required_components(node: Node, required: Array[String]) -> bool:
	"""Validate that all required child components exist

	Logs errors for any missing components.

	Args:
		node: Parent node to check
		required: Array of component node paths (e.g., ["MovementStats", "$UnitStats"])

	Returns:
		true if all components exist, false otherwise
	"""
	var all_valid = true
	for component_name in required:
		var component = node.get_node_or_null(component_name)
		if not component:
			push_error("[%s] Required component missing: %s" % [node.name, component_name])
			all_valid = false
	return all_valid
