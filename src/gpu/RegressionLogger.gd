class_name RegressionLogger
extends RefCounted

## Structured regression logging for GPU combat tests.
##
## Produces parseable log entries in the format:
##   [T:tick] EVENT_TYPE key=value key=value ...
##
## These logs can be diffed between runs to detect behavioral changes.
## Event order (state transitions, damage, movement) is the regression signal,
## not exact tick counts.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


var _log: Array = []
var _animation_play_counts: Dictionary = {}
var _charging_start_tick: Dictionary = {}

var test_name: String
var enabled: bool
var current_tick: int = 0


func _init(p_test_name: String = "", p_enabled: bool = true) -> void:
	test_name = p_test_name
	enabled = p_enabled


func log_entry(event_type: String, data: Dictionary) -> void:
	if not enabled:
		return

	var parts: Array = ["[T:%d]" % current_tick, event_type]
	for key in data.keys():
		var value = data[key]
		if value is String:
			parts.append("%s=\"%s\"" % [key, value])
		else:
			parts.append("%s=%s" % [key, str(value)])

	_log.append(" ".join(parts))


func log_state(unit_idx: int, old_state: int, new_state: int, timer: int, pos: Vector2i) -> void:
	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
	log_entry("STATE", {
		"unit": unit_idx,
		"old": old_name,
		"new": new_name,
		"timer": timer,
		"pos": "(%d,%d)" % [pos.x, pos.y]
	})


func log_anim(unit_idx: int, anim_id: int, anim_name: String) -> void:
	_animation_play_counts[unit_idx] = _animation_play_counts.get(unit_idx, 0) + 1
	log_entry("ANIM", {
		"unit": unit_idx,
		"id": anim_id,
		"name": anim_name,
		"count": _animation_play_counts[unit_idx]
	})


func log_ability(unit_idx: int, ability_id: int, target_idx: int, pos: Vector2i) -> void:
	var ability := AbilityDatabase.get_ability_view(ability_id)
	var ability_name = ability.name if not ability.is_empty() else "Attack"
	log_entry("ABILITY", {
		"unit": unit_idx,
		"ability_id": ability_id,
		"ability_name": ability_name,
		"target": target_idx,
		"pos": "(%d,%d)" % [pos.x, pos.y]
	})


func log_projectile_spawn(unit_idx: int, target_idx: int, proj_type: String, flight_ticks: int, ability_id: int) -> void:
	log_entry("PROJECTILE_SPAWN", {
		"unit": unit_idx,
		"target": target_idx,
		"type": proj_type,
		"flight_ticks": flight_ticks,
		"ability_id": ability_id
	})


func log_projectile_land(unit_idx: int, target_idx: int, proj_type: String) -> void:
	log_entry("PROJECTILE_LAND", {
		"unit": unit_idx,
		"target": target_idx,
		"type": proj_type
	})


func log_damage(unit_idx: int, target_idx: int, amount: int, hp_before: int, hp_after: int) -> void:
	log_entry("DAMAGE", {
		"unit": unit_idx,
		"target": target_idx,
		"amount": amount,
		"hp_before": hp_before,
		"hp_after": hp_after
	})


func log_heal(unit_idx: int, target_idx: int, amount: int, hp_before: int, hp_after: int) -> void:
	log_entry("HEAL", {
		"unit": unit_idx,
		"target": target_idx,
		"amount": amount,
		"hp_before": hp_before,
		"hp_after": hp_after
	})


func log_mp_change(unit_idx: int, old_mp: int, new_mp: int, ability_id: int) -> void:
	log_entry("MP", {
		"unit": unit_idx,
		"old": old_mp,
		"new": new_mp,
		"delta": new_mp - old_mp,
		"ability_id": ability_id
	})


func log_move(unit_idx: int, from_pos: Vector2i, to_pos: Vector2i) -> void:
	log_entry("MOVE", {
		"unit": unit_idx,
		"from": "(%d,%d)" % [from_pos.x, from_pos.y],
		"to": "(%d,%d)" % [to_pos.x, to_pos.y]
	})


func log_charge_start(unit_idx: int, ability_id: int, charge_ticks: int) -> void:
	var ability := AbilityDatabase.get_ability_view(ability_id)
	var ability_name = ability.name if not ability.is_empty() else "Unknown"
	_charging_start_tick[unit_idx] = current_tick
	log_entry("CHARGE_START", {
		"unit": unit_idx,
		"ability_id": ability_id,
		"ability_name": ability_name,
		"charge_ticks": charge_ticks
	})


func log_charge_end(unit_idx: int, ability_id: int) -> void:
	var start_tick = _charging_start_tick.get(unit_idx, current_tick)
	var duration = current_tick - start_tick
	log_entry("CHARGE_END", {
		"unit": unit_idx,
		"ability_id": ability_id,
		"duration_ticks": duration
	})


func log_effect(unit_idx: int, target_idx: int, effect_id: String) -> void:
	log_entry("EFFECT", {
		"unit": unit_idx,
		"target": target_idx,
		"effect_id": effect_id
	})


func log_victory(winning_team: int, tick: int) -> void:
	log_entry("VICTORY", {
		"winning_team": winning_team,
		"tick": tick
	})


func output() -> void:
	if not enabled or _log.is_empty():
		return

	var separator = "=".repeat(60)
	print("\n" + separator)
	print("REGRESSION LOG - %s" % test_name)
	print(separator)
	for line in _log:
		print(line)
	print(separator)
	print("Total entries: %d" % _log.size())
	print(separator + "\n")
