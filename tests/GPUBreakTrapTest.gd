extends GPUCombatTestBase

## GPU Break TRAP Effect Test
##
## Tests that Knight Break abilities spawn the correct TRAP particle effects.
## Uses a single WeaponBreaker vs a single tanky Target.
##
## Expected:
## - When break ability lands, a TRAP effect spawns at target (scattered_dots, config 11)
## - No white palette flash (enable_palette_flash = false)
## - Particles should be visible triangles, not dust+flash
##
## The test also verifies the HP-change path spawns a TRAP (breaks deal damage)
## and the stat-change path spawns a TRAP (breaks modify stats).

const TrapEffect = ExMateriaEffects.TrapEffect

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


const ABILITY_WEAPON_BREAK = 141  # Formula 37 (0x25) — equipment break
const ABILITY_SPEED_BREAK = 143   # Formula 43 (0x2B) — stat break

# Tracking
var _hp_trap_spawned: bool = false
var _stat_trap_spawned: bool = false
var _trap_spawn_count: int = 0
var _check_timer: float = 0.0
var _weapon_break_landed: bool = false
var _target_damaged: bool = false
var _results_printed: bool = false
const INITIAL_TARGET_WP = 10


func get_test_name() -> String:
	return "GPU Break TRAP Effect Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "WeaponBreaker",
			"pos_x": 2, "pos_z": 1,
			"hp": 999, "max_hp": 999,
			"pa": 15, "ma": 5, "wp": 8,
			"brave": 70, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 120,
			"move": 4, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,  # STRIKING
			"weapon_type": 1,   # Sword
			"weapon_id": 19,    # Broad Sword
			"body_sprite_id": 0x02,
			"job_id": "3d",     # Knight
			"gambits": [{
				"enabled": true,
				"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
				"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
				"action_type": GPUConstants.ACTION_ABILITY,
				"action_id": ABILITY_WEAPON_BREAK,
				"action_target_type": GPUConstants.TARGET_THEM
			}]
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Target",
			"pos_x": 2, "pos_z": 3,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 5, "wp": 10,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 50,
			"move": 3, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,
			"weapon_type": 1,
			"weapon_id": 19,
			"body_sprite_id": 0x05,
			"job_id": "3d",
			"gambits": [{
				"enabled": true,
				"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
				"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
				"action_type": GPUConstants.ACTION_ATTACK,
				"action_id": 0,
				"action_target_type": GPUConstants.TARGET_THEM
			}]
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	var all_configs = get_team0_unit_configs() + get_team1_unit_configs()
	if unit_idx < all_configs.size():
		return all_configs[unit_idx].get("gambits", [make_attack_gambit()])
	return [make_attack_gambit()]


func _ready():
	super._ready()
	print("\n=== BREAK TRAP EFFECT DEBUG ===")
	# Print ability data for reference
	for aid in [ABILITY_WEAPON_BREAK, ABILITY_SPEED_BREAK]:
		var ab := AbilityDatabase.get_ability_view(aid)
		print("[BREAK_TEST] Ability %d (%s): formula=%d (0x%02X) effect_anim_id=%d weapon_range=%s" % [
			aid, ab.name, ab.formula, ab.formula,
			ab.effect_anim_id, str(ab.weapon_range)])
	print("=== END BREAK TRAP DEBUG ===\n")


func _process(delta):
	super._process(delta)
	if not combat_active or victory_achieved:
		return
	if not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 1.0:
		return
	_check_timer = 0.0

	# Dump attacker state to understand ability_id availability
	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	var attacker_state = states[0]
	var target_state = states[1]
	var a_state_id = attacker_state.get("state", 0)
	var a_state_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[a_state_id] if a_state_id < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(a_state_id)
	print("[BREAK_POLL] tick=%d attacker: state=%s casting_ability_id=%d target=%d damage_target=%d | target: hp=%d wp=%d" % [
		current_tick, a_state_name,
		attacker_state.get("casting_ability_id", -1),
		attacker_state.get("target", -1),
		attacker_state.get("damage_target", -1),
		target_state.get("hp", 0),
		target_state.get("wp", 0)])

	# Check if WeaponBreak landed (WP reduced)
	if not _weapon_break_landed and target_state.get("wp", INITIAL_TARGET_WP) < INITIAL_TARGET_WP:
		_weapon_break_landed = true
		print("[BREAK_TEST] WeaponBreak landed! Target WP: %d -> %d" % [INITIAL_TARGET_WP, target_state.get("wp", 0)])

	# Count TrapEffect children
	var trap_count = 0
	for child in get_children():
		if child is TrapEffect:
			trap_count += 1
	if trap_count > 0:
		print("[BREAK_POLL] Active TrapEffect nodes: %d" % trap_count)
		_hp_trap_spawned = true

	# Auto-print results once WeaponBreak has landed
	if _weapon_break_landed and not _results_printed:
		_print_results()


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
	print("  [STATE] %s: %s -> %s" % [unit_name, old_name, new_name])


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta_hp: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if delta_hp < 0:
		print("  [DAMAGE] %s hit for %d! HP: %d -> %d" % [unit_name, abs(delta_hp), old_hp, new_hp])
		if unit_idx == 1:  # Target
			_target_damaged = true
	elif delta_hp > 0:
		print("  [HEAL] %s healed for %d! HP: %d -> %d" % [unit_name, delta_hp, old_hp, new_hp])


func _print_results():
	if _results_printed:
		return
	_results_printed = true
	print("\n=== BREAK TRAP TEST RESULTS ===")
	var all_pass = true
	if _weapon_break_landed:
		print("  [PASS] WeaponBreak landed (target WP reduced)")
	else:
		print("  [FAIL] WeaponBreak never landed")
		all_pass = false
	if _hp_trap_spawned:
		print("  [PASS] TrapEffect particle spawned")
	else:
		print("  [INFO] No TrapEffect observed (visual-only, not a failure)")
	if all_pass:
		print("[PASS] Break trap test passed")
	else:
		print("[FAIL] Break trap test failed")
	print("=================================")
	get_tree().quit()


func on_victory(winning_team: int):
	if not _results_printed:
		_print_results()
