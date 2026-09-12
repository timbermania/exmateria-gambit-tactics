class_name EvasionTestBase
extends GPUCombatTestBase

## Base class for evasion test scenes.
##
## Subclasses override: get_test_name(), get_team0/1_unit_configs(),
## get_result_tick(), and _print_results().

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ReactionType = ExMateriaAlmanac.ReactionType


var _observed: Array[String] = []
var _results_printed: bool = false
var _signals_connected: bool = false


func get_result_tick() -> int:
	return 800


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


func _ready():
	super._ready()


func _process(delta):
	super._process(delta)
	if not _signals_connected:
		_connect_signals()
	if current_tick >= get_result_tick() and not _results_printed:
		_results_printed = true
		_print_results()


func _connect_signals():
	if _signals_connected or units.is_empty():
		return
	var expected = get_team0_unit_configs().size() + get_team1_unit_configs().size()
	if units.size() < expected:
		return
	_signals_connected = true
	for i in range(units.size()):
		units[i].reaction_animation_played.connect(_on_reaction.bind(i))


func _on_reaction(reaction_type: int, unit_idx: int):
	var type_str = ReactionType.to_string_key(reaction_type)
	if unit_idx == 1:
		_observed.append(type_str)
		print("[REACT] %s played '%s' (count: %d)" % [units[unit_idx].name, type_str, _observed.size()])


func _get_counts() -> Dictionary:
	var counts: Dictionary = {}
	for r in _observed:
		counts[r] = counts.get(r, 0) + 1
	return counts


func _print_header():
	print("\n=== %s RESULTS ===" % get_test_name().to_upper())
	var total = _observed.size()
	var counts = _get_counts()
	print("Total reactions: %d" % total)
	for type in counts:
		print("  %s: %d (%.0f%%)" % [type, counts[type], float(counts[type]) / max(1, total) * 100.0])


func _print_results():
	_print_header()
	print("===\n")


func on_state_changed(_unit_idx: int, _old_state: int, _new_state: int):
	pass


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if unit_idx == 1 and delta < 0:
		print("  -> Target hit for %d! HP=%d" % [abs(delta), new_hp])


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("[%s] Team %d wins" % [get_test_name(), winning_team])


# --- Common unit config helpers ---

func _melee_attacker(overrides: Dictionary = {}) -> Dictionary:
	var config = {
		"name": "Attacker", "pos_x": 0, "pos_z": 0,
		"hp": 999, "max_hp": 999, "pa": 8, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50, "speed": 100, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19, "c_ev": 0, "s_ev": 0, "w_ev": 0, "body_sprite_id": 0x02,
	}
	config.merge(overrides, true)
	return config


func _ranged_attacker(overrides: Dictionary = {}) -> Dictionary:
	var config = {
		"name": "Archer", "pos_x": 0, "pos_z": 0,
		"hp": 999, "max_hp": 999, "pa": 8, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50, "speed": 100, "move": 4, "jump": 3,
		"weapon_range": 5, "weapon_flags": 4, "weapon_type": 11,
		"weapon_id": 83, "c_ev": 0, "s_ev": 0, "w_ev": 0, "body_sprite_id": 0x03,
	}
	config.merge(overrides, true)
	return config


func _melee_target(overrides: Dictionary = {}) -> Dictionary:
	var config = {
		"name": "Target", "pos_x": 1, "pos_z": 0,
		"hp": 999, "max_hp": 999, "pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50, "speed": 50, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19, "c_ev": 0, "s_ev": 0, "w_ev": 0, "body_sprite_id": 0x05,
	}
	config.merge(overrides, true)
	return config


func _ranged_target(overrides: Dictionary = {}) -> Dictionary:
	var config = _melee_target(overrides)
	config["pos_x"] = 0
	config["pos_z"] = 4
	config.merge(overrides, true)
	return config
