class_name GPUStateReader
extends RefCounted

## Reads GPU combat state and translates it for CPU rendering.
##
## This class bridges the GPU simulator and the visual rendering layer.
## It reads unit states from the GPU via polling (get_all_unit_states)
## so the CPU can trigger appropriate animations and effects.
##
## Usage:
##   var reader = GPUStateReader.new()
##   reader.initialize(gpu_simulator, battle_id)
##   var states = reader.get_all_unit_states()

# Reference to GPU simulator
var _gpu_simulator: GPUBatchSimulator = null
var _battle_id: int = 0

var _initialized: bool = false

# (A third copy of the unit states lived here as `enum UnitState` but was never
# referenced — use GPUConstants.STATE_* instead. Dead enum removed.)

func initialize(gpu_simulator: GPUBatchSimulator, battle_id: int = 0) -> void:
	"""Initialize the state reader.

	Args:
		gpu_simulator: The GPU simulator to read from
		battle_id: Which battle to track (default 0)
	"""
	_gpu_simulator = gpu_simulator
	_battle_id = battle_id
	_initialized = true


func get_all_unit_states() -> Array[Dictionary]:
	"""Get all unit states for the current frame."""
	if not _initialized or _gpu_simulator == null:
		return []
	return _gpu_simulator.get_battle_unit_states(_battle_id)


func get_all_unit_states_hot() -> Array[Dictionary]:
	"""The PER-FRAME snapshot: same values as get_all_unit_states(), but carrying
	only the 39 fields the per-frame combat path reads
	(GPUCombatPacker.SNAPSHOT_HOT_UNION) instead of all 101.

	⚠ Per-frame path ONLY. A consumer reading a field outside the union gets
	`.get()`'s default, silently — see the union constant's comment for the two
	instruments that keep that from happening. Cold callers and tests want
	get_all_unit_states().
	"""
	if not _initialized or _gpu_simulator == null:
		return []
	return _gpu_simulator.get_battle_unit_states_hot(_battle_id)


func get_unit_column(field_offset: int) -> PackedInt32Array:
	"""Lean per-tick read: one field for every unit, as an int column, WITHOUT
	building the full 99-field per-unit Dictionary that get_all_unit_states does.

	The combat loop's per-tick reads (HP / EVADE_TYPE / CINEMATIC_TIMER / PAUSED)
	go through here; the field-heavy full snapshot stays a once-per-frame call. See
	GPUBatchSimulator.read_unit_column.
	"""
	if not _initialized or _gpu_simulator == null:
		return PackedInt32Array()
	return _gpu_simulator.read_unit_column(_battle_id, field_offset)


func get_battle_state() -> Dictionary:
	"""Get per-battle header state (tick, result, flags, seed).

	Distinct from get_all_unit_states (per-unit fields) — this surfaces the
	BattleHeader's per-battle scalars. The cinematic-spell header pair
	retired in #118; cinematic edge detection now scans the per-unit
	U_CINEMATIC_TIMER (CinematicManager._pick_spotlight_caster).
	"""
	if not _initialized or _gpu_simulator == null:
		return {}
	return _gpu_simulator.get_battle_state(_battle_id)


func is_battle_finished() -> bool:
	"""Check if the battle has ended."""
	if not _initialized or _gpu_simulator == null:
		return true
	return _gpu_simulator.is_battle_finished(_battle_id)


func get_battle_result() -> Dictionary:
	"""Get the battle result if finished."""
	if not _initialized or _gpu_simulator == null:
		return {}
	return _gpu_simulator.get_battle_result(_battle_id)


