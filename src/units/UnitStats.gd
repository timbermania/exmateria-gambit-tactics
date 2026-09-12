@tool
class_name UnitStats
extends Node

## Unit Statistics Component
##
## Manages all unit stats: combat (HP, MP, attack, defense), movement (range, jump, speed),
## and state (team, death, charging). Attach to any entity that participates in combat.
##
## Supports two modes:
## 1. Legacy mode: Hardcoded stat values (backwards compatible)
## 2. Progression mode: Delegates to UnitProgression for FFT-style stat calculation
##
## Usage (Legacy):
##   var stats = $UnitStats
##   stats.initialize(100, 25, 15, 60, UnitStats.Team.PLAYER)
##   stats.take_damage(20)
##
## Usage (Progression):
##   var stats = $UnitStats
##   stats.initialize_from_progression($UnitProgression, UnitStats.Team.PLAYER)

# Reference to UnitProgression (when using progression-based stats)
var _progression: Resource = null  # UnitProgression (Resource; typed loosely to avoid circular dependency)

# Legacy stat backing fields (used when _progression is null)
var _max_hp: int = 100
var _max_mp: int = 50
var _attack: int = 20
var _defense: int = 10
var _magic_attack: int = 20
var _magic_defense: int = 10
var _move_range: int = 4
var _jump_height: float = 3.0
var _atb_speed: int = 50

# Runtime state (always stored here)
var current_hp: int = 100
# MP is mutated from scattered places (GPU readback, rosters, debug, init), so the
# setter owns mp_changed emission — any assignment notifies listeners (single source).
var current_mp: int = 50:
	set(value):
		if current_mp != value:
			var old_mp = current_mp
			current_mp = value
			mp_changed.emit(old_mp, value)
@export var movement_speed: float = 3.0  # Movement speed in units/second

# Combat state
enum Team { PLAYER, ENEMY }
var team: Team = Team.PLAYER
var is_dead: bool = false
var is_charging_spell: bool = false  # Vulnerability flag during spell charge

const CHARGING_VULNERABILITY: float = 1.5  # 50% extra damage while charging

# Signals
signal hp_changed(old_hp: int, new_hp: int)
signal mp_changed(old_mp: int, new_mp: int)
signal died()
signal revived(new_hp: int)


## Stat Properties (delegate to progression when available)

var max_hp: int:
	get:
		if _progression:
			return _progression.get_effective_hp()
		return _max_hp
	set(value):
		_max_hp = value

var max_mp: int:
	get:
		if _progression:
			return _progression.get_effective_mp()
		return _max_mp
	set(value):
		_max_mp = value

var attack: int:
	get:
		if _progression:
			return _progression.get_effective_pa()
		return _attack
	set(value):
		_attack = value

var defense: int:
	get:
		# FFT doesn't have a direct "defense" stat - physical defense comes from equipment
		# For now, return a baseline when using progression
		if _progression:
			return _progression.get_effective_pa() / 2  # Placeholder: half of PA
		return _defense
	set(value):
		_defense = value

var magic_attack: int:
	get:
		if _progression:
			return _progression.get_effective_ma()
		return _magic_attack
	set(value):
		_magic_attack = value

var magic_defense: int:
	get:
		# FFT doesn't have a direct "magic defense" stat - it comes from equipment
		# For now, return a baseline when using progression
		if _progression:
			return _progression.get_effective_ma() / 2  # Placeholder: half of MA
		return _magic_defense
	set(value):
		_magic_defense = value

var move_range: int:
	get:
		if _progression:
			return _progression.get_move()
		return _move_range
	set(value):
		_move_range = value

var jump_height: float:
	get:
		if _progression:
			return float(_progression.get_jump())
		return _jump_height
	set(value):
		_jump_height = value

var atb_speed: int:
	get:
		if _progression:
			return _progression.get_effective_speed()
		return _atb_speed
	set(value):
		_atb_speed = value


func take_damage(amount: int) -> void:
	"""Apply damage to unit, handle death if HP reaches 0.

	Defense is not subtracted here - it's factored into the formula if applicable.
	Only charging vulnerability is applied here.
	"""
	if is_dead:
		return

	var old_hp = current_hp
	var final_damage = amount

	# Apply vulnerability if charging a spell (50% extra damage)
	if is_charging_spell:
		final_damage = int(final_damage * CHARGING_VULNERABILITY)

	current_hp = max(0, current_hp - final_damage)

	hp_changed.emit(old_hp, current_hp)

	if current_hp == 0:
		die()


func heal(amount: int) -> void:
	"""Restore HP to unit"""
	if is_dead:
		return

	var old_hp = current_hp
	current_hp = min(max_hp, current_hp + amount)

	if old_hp != current_hp:
		hp_changed.emit(old_hp, current_hp)



func die() -> void:
	"""Handle unit death"""
	if is_dead:
		return

	is_dead = true
	died.emit()


func revive(new_hp: int) -> void:
	"""Reverse a prior die() — clear is_dead, sync HP, drop the dead status.

	Mirror of die() for Reraise / Phoenix Down. The CombatLoop calls this
	when the GPU clears FLAG_DEAD on a unit whose CPU still has is_dead set
	(see issue #108). The matching path inside `initialize()` already
	removes &"dead" from the status manager on full re-init; this preserves
	the same idiom for the in-place revive case.
	"""
	if not is_dead:
		return

	is_dead = false
	var old_hp = current_hp
	current_hp = new_hp
	if old_hp != current_hp:
		hp_changed.emit(old_hp, current_hp)

	var status_mgr = _get_status_manager()
	if status_mgr and status_mgr.has_status(&"dead"):
		status_mgr.remove_status(&"dead", "revived")

	revived.emit(new_hp)



func initialize(hp: int, atk: int, def: int, spd: int, unit_team: Team,
		mp: int = 50, m_atk: int = 20, m_def: int = 10,
		move: int = 4, jump: float = 3.0, mov_speed: float = 3.0) -> void:
	"""Helper to set all unit stats at once (legacy mode)"""
	_progression = null  # Clear any progression reference
	_max_hp = hp
	current_hp = hp
	_attack = atk
	_defense = def
	_atb_speed = spd
	team = unit_team
	_max_mp = mp
	current_mp = mp
	_magic_attack = m_atk
	_magic_defense = m_def
	is_dead = false
	is_charging_spell = false
	_move_range = move
	_jump_height = jump
	movement_speed = mov_speed

	# Clear dead status from status manager if present (resurrection support)
	var status_mgr = _get_status_manager()
	if status_mgr and status_mgr.has_status(&"dead"):
		status_mgr.remove_status(&"dead", "resurrected")


func initialize_from_progression(progression: Resource, unit_team: Team, mov_speed: float = 3.0) -> void:
	"""Initialize stats from a UnitProgression component.

	Args:
		progression: UnitProgression node to delegate stat queries to
		unit_team: PLAYER or ENEMY
		mov_speed: Movement animation speed
	"""
	_progression = progression
	team = unit_team
	movement_speed = mov_speed
	is_dead = false
	is_charging_spell = false

	# Initialize current HP/MP to max values from progression
	current_hp = max_hp
	current_mp = max_mp

	# Connect to progression signals for stat updates
	if _progression.has_signal("stats_changed"):
		if not _progression.stats_changed.is_connected(_on_progression_stats_changed):
			_progression.stats_changed.connect(_on_progression_stats_changed)

	# Clear dead status from status manager if present (resurrection support)
	var status_mgr = _get_status_manager()
	if status_mgr and status_mgr.has_status(&"dead"):
		status_mgr.remove_status(&"dead", "resurrected")


func _on_progression_stats_changed() -> void:
	"""Handle stat changes from progression (e.g., level up, job change).

	Note: current_hp/mp are clamped to new max values, not reset to max.
	"""
	current_hp = mini(current_hp, max_hp)
	current_mp = mini(current_mp, max_mp)


func get_progression() -> Resource:
	"""Get the UnitProgression reference (or null if using legacy mode)."""
	return _progression


func _get_status_manager() -> Node:
	"""Get the UnitStatusManager from the parent unit (if available).

	Returns null if parent doesn't have a status manager (backward compatibility).
	"""
	var parent = get_parent()
	if parent and parent.has_node("UnitStatusManager"):
		return parent.get_node("UnitStatusManager")
	return null
