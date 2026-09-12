extends RefCounted
## Ordered list of gambits for a unit.
##
## Gambits are evaluated in priority order (index 0 = highest priority).
## The first gambit whose condition is met will be used.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const _Self = preload("res://addons/exmateria_almanac/gambits/GambitList.gd")
const Gambit = preload("res://addons/exmateria_almanac/gambits/Gambit.gd")

## The ordered list of gambits
var gambits: Array[Gambit] = []


func _init(initial_gambits: Array[Gambit] = []) -> void:
	gambits = initial_gambits


func add(gambit: Gambit) -> void:
	"""Add a gambit to the end of the list (lowest priority)."""
	gambits.append(gambit)


func remove_at(index: int) -> void:
	"""Remove gambit at index."""
	if index >= 0 and index < gambits.size():
		gambits.remove_at(index)


func move(from_index: int, to_index: int) -> void:
	"""Move gambit from one position to another."""
	if from_index < 0 or from_index >= gambits.size():
		return
	if to_index < 0 or to_index >= gambits.size():
		return

	var gambit = gambits[from_index]
	gambits.remove_at(from_index)
	gambits.insert(to_index, gambit)


func replace_at(index: int, gambit: Gambit) -> void:
	"""Replace gambit at index with a new gambit."""
	if index >= 0 and index < gambits.size():
		gambits[index] = gambit


func get_at(index: int) -> Gambit:
	"""Get gambit at index."""
	if index >= 0 and index < gambits.size():
		return gambits[index]
	return null


func clear() -> void:
	"""Remove all gambits."""
	gambits.clear()


func size() -> int:
	"""Get number of gambits."""
	return gambits.size()


func is_empty() -> bool:
	"""Check if list is empty."""
	return gambits.is_empty()


## Number of visible gambit slots (always 4)
const VISIBLE_SLOTS: int = 4


func ensure_fixed_size() -> void:
	"""Ensure the gambit list has exactly VISIBLE_SLOTS (4) gambits.

	Pads with empty gambits ("Always: Wait on Self") if needed.
	Removes excess gambits if there are more than 4.
	"""
	while gambits.size() < VISIBLE_SLOTS:
		gambits.append(_create_empty_gambit())
	while gambits.size() > VISIBLE_SLOTS:
		gambits.pop_back()


func _create_empty_gambit() -> Gambit:
	"""Create an empty gambit (Always: Wait on Self).

	ONE definition of empty, and it is the constructor's. This used to restate all four fields,
	and it disagreed with `Gambit._init` on one of them (`action_target`) — two definitions of the
	same object, welded to `Gambit.is_empty` in a way that meant neither could be corrected
	without the other. A restatement that agrees is still a second place for it to stop agreeing.
	"""
	return Gambit.new()


func _to_string() -> String:
	"""Human-readable representation for debugging."""
	var lines: Array[String] = []
	for i in range(gambits.size()):
		lines.append("%d. %s" % [i + 1, gambits[i]._to_string()])
	return "\n".join(lines)


## Static factory methods to create common gambit lists

# ============================================================================
# SERIALIZATION
# ============================================================================

func to_array() -> Array:
	"""Convert to array of dictionaries for JSON serialization."""
	var result: Array = []
	for gambit in gambits:
		result.append(gambit.to_dict())
	return result


static func from_array(data: Array) -> _Self:
	"""Create from array of dictionaries (JSON deserialization)."""
	var gl = _Self.new()
	for gambit_dict in data:
		gl.gambits.append(Gambit.from_dict(gambit_dict))
	gl.ensure_fixed_size()
	return gl
