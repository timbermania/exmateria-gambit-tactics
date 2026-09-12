extends GPUCombatTestBase

## GPU Berserk Test
##
## Tests Tier 2 #8 (batch 2) — STATUS_BERSERK override.
##
## A berserked unit ignores its gambit list and attacks the nearest enemy.
## To prove the override (not just "the gambit happens to attack"), the
## Berserker is set up with NO gambits at all. Without Berserk it would
## sit idle forever; with Berserk it attacks the enemy until one dies.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


func get_test_name() -> String:
	return "GPU Berserk Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Berserker", "pos_x": 1, "pos_z": 0,
			"hp": 200, "max_hp": 200, "pa": 10, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"status_flags_lo": (1 << StatusRegistry.bit(&"berserk")),
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Punching_Bag", "pos_x": 2, "pos_z": 0,
			"hp": 200, "max_hp": 200, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05,
		},
	]


# No gambits for either team — the Berserker must rely on the
# Berserk override to fire any action at all.
func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return []


var _initial_target_hp: int = -1
var _saw_attack: bool = false
var _results_printed: bool = false
var _check_timer: float = 0.0


func _ready():
	max_ticks = 300
	super._ready()


func _process(delta):
	super._process(delta)
	if _results_printed or not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.2:
		return
	_check_timer = 0.0

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	if _initial_target_hp < 0:
		_initial_target_hp = int(states[1].get("hp", 0))

	var target_hp = int(states[1].get("hp", 0))
	if target_hp < _initial_target_hp:
		_saw_attack = true
		_print_results(target_hp)
		return

	if current_tick >= max_ticks - 2:
		_print_results(target_hp)


func _print_results(target_hp: int) -> void:
	if _results_printed:
		return
	_results_printed = true

	print("\n=== BERSERK TEST RESULTS ===")
	print("  Target HP: %d (initial %d)" % [target_hp, _initial_target_hp])
	if _saw_attack:
		print("[PASS] Berserker attacked despite empty gambit list")
	else:
		print("[FAIL] Berserker never swung at the enemy")
	print("==============================\n")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _results_printed:
		var states = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		var hp = int(states[1].get("hp", -1)) if states.size() >= 2 else -1
		_print_results(hp)
