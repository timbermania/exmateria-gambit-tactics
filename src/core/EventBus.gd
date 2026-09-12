extends Node

## EventBus (Autoload Singleton)
## Accessed globally as: EventBus
##
## Centralized event system for cross-system communication.
## Reduces coupling between systems and provides single point for event tracking.
##
## Usage:
##   EventBus.unit_hp_changed.connect(_on_hp_changed)
##   EventBus.emit_unit_hp_changed(unit, old_hp, new_hp)

# === Unit Lifecycle Events ===

## Emitted when any unit dies
signal unit_died(unit: Node)

## Emitted when unit HP changes (covers both damage and healing)
signal unit_hp_changed(unit: Node, old_hp: int, new_hp: int)

## Emitted when unit MP changes
signal unit_mp_changed(unit: Node, old_mp: int, new_mp: int)


# === Emit Helper Methods ===

func emit_unit_died(unit: Node) -> void:
	"""Emit unit_died when a unit dies"""
	unit_died.emit(unit)


func emit_unit_hp_changed(unit: Node, old_hp: int, new_hp: int) -> void:
	"""Emit unit_hp_changed for any HP modification"""
	unit_hp_changed.emit(unit, old_hp, new_hp)


func emit_unit_mp_changed(unit: Node, old_mp: int, new_mp: int) -> void:
	"""Emit unit_mp_changed for any MP modification"""
	unit_mp_changed.emit(unit, old_mp, new_mp)
