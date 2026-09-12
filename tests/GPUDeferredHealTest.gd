extends GPUCombatTestBase

## GPU Deferred Heal Test
##
## Tests Tier 2 #11 — stage_damage's Phase 4 resolution of
## U_PENDING_HEAL_TARGET / U_PENDING_HEAL_AMOUNT.
##
## tick_acting_animation queues these on the caster when a
## projectile-style heal spell fires. Driving a full projectile cast
## from a test scene has a lot of moving parts (right ability ID, right
## animation frames, right line-of-sight). The spawn config now seeds
## the two fields directly so the test exercises just the resolution
## path: at tick 0 caster.pending_heal_target = ally_idx,
## pending_heal_amount = 50; first time stage_damage runs, ally HP
## should rise by 50 and the caster's queue should clear.

func get_test_name() -> String:
	return "GPU Deferred Heal Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			# Caster — seeds a pending heal on the injured ally (unit 1).
			"name": "Caster", "pos_x": 0, "pos_z": 0,
			"hp": 200, "max_hp": 200, "pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"pending_heal_target": 1,
			"pending_heal_amount": 50,
		},
		{
			# Injured ally — starts at 100/200, should resolve to 150.
			"name": "Injured_Ally", "pos_x": 1, "pos_z": 0,
			"hp": 100, "max_hp": 200, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x02,
		},
	]


func get_team1_unit_configs() -> Array:
	# Need at least one enemy so is_enemy_team_dead doesn't immediately
	# end the battle in LOGICAL_ACTIVITY_CELEBRATING. Far away, no gambits — passive.
	return [
		{
			"name": "Distant_Enemy", "pos_x": 14, "pos_z": 14,
			"hp": 999, "max_hp": 999, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return []  # Nobody acts; the pending heal resolves on its own.


var _initial_ally_hp: int = -1
var _post_heal_ally_hp: int = -1
var _post_heal_caster_queue: int = -1
var _results_printed: bool = false
var _check_timer: float = 0.0


func _ready():
	max_ticks = 60
	super._ready()


func _process(delta):
	super._process(delta)
	if _results_printed or not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.1:
		return
	_check_timer = 0.0

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 3:
		return

	if _initial_ally_hp < 0:
		_initial_ally_hp = int(states[1].get("hp", 0))

	var ally_hp = int(states[1].get("hp", 0))
	var caster_queue = int(states[0].get("pending_heal_amount", -1))

	if ally_hp != _initial_ally_hp and _post_heal_ally_hp < 0:
		_post_heal_ally_hp = ally_hp
		_post_heal_caster_queue = caster_queue
		_print_results()
	elif current_tick >= 30 and not _results_printed:
		# Plenty of ticks past the first stage_damage dispatch.
		_post_heal_ally_hp = ally_hp
		_post_heal_caster_queue = caster_queue
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	var expected_hp = 150  # 100 + 50, under max 200
	var hp_ok = _post_heal_ally_hp == expected_hp
	var queue_ok = _post_heal_caster_queue == 0

	print("\n=== DEFERRED HEAL TEST RESULTS ===")
	print("  Ally HP: %d (initial %d, expected %d)" % [
		_post_heal_ally_hp, _initial_ally_hp, expected_hp])
	print("  Caster pending_heal_amount: %d (expected 0 = cleared)" % _post_heal_caster_queue)

	if hp_ok and queue_ok:
		print("[PASS] Deferred heal resolved and queue cleared")
	else:
		var why = []
		if not hp_ok:
			why.append("heal did not land")
		if not queue_ok:
			why.append("queue not cleared (caster still holding %d)" % _post_heal_caster_queue)
		print("[FAIL] " + ", ".join(why))
	print("===================================\n")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _results_printed:
		_print_results()
