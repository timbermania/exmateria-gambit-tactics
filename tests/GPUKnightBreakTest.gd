extends GPUCombatTestBase

## GPU Knight Break Test
##
## Tests all Knight Break ability types against a SINGLE target:
## - SpeedBreak (143): Formula 43, reduces Speed by 2. Pass: target speed < initial.
## - WeaponBreak (141): Formula 37, sets target WP to 0. Pass: target WP == 0.
## - MagicBreak (142): Formula 44, drains 50% of target MaxMP. Pass: target MP < initial.
##
## Team 0: 3 Knights clustered near the single target, each with a different break
## Team 1: 1 immobile Target with high HP
##
## All 3 knights target the same enemy (the only one). Break abilities don't deal
## HP damage, so the target survives all 3. We check speed, WP, MP on unit index 3.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


const ABILITY_SPEED_BREAK = 143
const ABILITY_WEAPON_BREAK = 141
const ABILITY_MAGIC_BREAK = 142

# Pass/fail tracking
var _speed_break_landed: bool = false
var _weapon_break_landed: bool = false
var _magic_break_landed: bool = false

# Initial values for comparison
const INITIAL_TARGET_SPEED = 80
const INITIAL_TARGET_WP = 8
const INITIAL_TARGET_MP = 100

# Check interval
var _check_timer: float = 0.0
var _all_passed_logged: bool = false


func get_test_name() -> String:
	return "GPU Knight Break Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "SpeedBreaker",
			"pos_x": 3, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 12, "ma": 5, "wp": 6,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 100,
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
				"action_id": ABILITY_SPEED_BREAK,
				"action_target_type": GPUConstants.TARGET_THEM
			}]
		},
		{
			"name": "WeaponBreaker",
			"pos_x": 4, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 12, "ma": 5, "wp": 6,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 100,
			"move": 4, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,
			"weapon_type": 1,
			"weapon_id": 19,
			"body_sprite_id": 0x02,
			"job_id": "3d",
			"gambits": [{
				"enabled": true,
				"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
				"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
				"action_type": GPUConstants.ACTION_ABILITY,
				"action_id": ABILITY_WEAPON_BREAK,
				"action_target_type": GPUConstants.TARGET_THEM
			}]
		},
		{
			"name": "MagicBreaker",
			"pos_x": 5, "pos_z": 0,
			"hp": 500, "max_hp": 500,
			"pa": 12, "ma": 5, "wp": 6,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 100,
			"move": 4, "jump": 3,
			"weapon_range": 1,
			"weapon_flags": 1,
			"weapon_type": 1,
			"weapon_id": 19,
			"body_sprite_id": 0x02,
			"job_id": "3d",
			"gambits": [{
				"enabled": true,
				"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
				"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
				"action_type": GPUConstants.ACTION_ABILITY,
				"action_id": ABILITY_MAGIC_BREAK,
				"action_target_type": GPUConstants.TARGET_THEM
			}]
		},
	]


func get_team1_unit_configs() -> Array:
	# Single immobile target — all 3 knights converge on it
	return [
		{
			"name": "Target",
			"pos_x": 4, "pos_z": 4,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": INITIAL_TARGET_WP,
			"brave": 50, "faith": 50,
			"mp": INITIAL_TARGET_MP, "max_mp": INITIAL_TARGET_MP,
			"speed": 1,
			"move": 0, "jump": 3,
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
	DebugConfig.iteration_debug_enabled = true
	super._ready()
	call_deferred("_print_break_ability_debug")


func _print_break_ability_debug():
	print("\n=== KNIGHT BREAK TEST DEBUG ===")
	for ability_id in [ABILITY_SPEED_BREAK, ABILITY_WEAPON_BREAK, ABILITY_MAGIC_BREAK]:
		var ability := AbilityDatabase.get_ability_view(ability_id)
		print("[ABILITY %d] %s: formula=%d formula_x=%d formula_y=%d range=%d ct=%d weapon_range=%s" % [
			ability_id,
			ability.name,
			ability.formula,
			ability.formula_x,
			ability.formula_y,
			ability.range,
			ability.ct,
			str(ability.weapon_range),
		])
	print("=== END BREAK DEBUG ===\n")


func _process(delta):
	super._process(delta)
	if not combat_active or victory_achieved:
		return
	if not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.5:
		return
	_check_timer = 0.0

	# Check break effects on the single target (unit index 3)
	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 4:
		return

	var target = states[3]

	if not _speed_break_landed and target.get("speed", INITIAL_TARGET_SPEED) < INITIAL_TARGET_SPEED:
		_speed_break_landed = true
		var new_speed = target.get("speed", 0)
		print("\n[PASS] SpeedBreak: Target speed %d -> %d (expected reduction by 2)" % [INITIAL_TARGET_SPEED, new_speed])
		_rlog.log_entry("TEST_PASS", {"test": "speed_break", "old": INITIAL_TARGET_SPEED, "new": new_speed})

	if not _weapon_break_landed and target.get("wp", INITIAL_TARGET_WP) < INITIAL_TARGET_WP:
		_weapon_break_landed = true
		var new_wp = target.get("wp", 0)
		print("\n[PASS] WeaponBreak: Target WP %d -> %d (expected 0)" % [INITIAL_TARGET_WP, new_wp])
		_rlog.log_entry("TEST_PASS", {"test": "weapon_break", "old": INITIAL_TARGET_WP, "new": new_wp})

	if not _magic_break_landed and target.get("mp", INITIAL_TARGET_MP) < INITIAL_TARGET_MP:
		_magic_break_landed = true
		var new_mp = target.get("mp", 0)
		print("\n[PASS] MagicBreak: Target MP %d -> %d (expected 50%% drain)" % [INITIAL_TARGET_MP, new_mp])
		_rlog.log_entry("TEST_PASS", {"test": "magic_break", "old": INITIAL_TARGET_MP, "new": new_mp})

	# All three passed -> declare success
	if _speed_break_landed and _weapon_break_landed and _magic_break_landed and not _all_passed_logged:
		_all_passed_logged = true
		print("\n=== ALL KNIGHT BREAK TESTS PASSED ===")
		_rlog.log_entry("TEST_PASS", {"reason": "all_breaks_landed"})
		_rlog.output()
		get_tree().quit()


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
	print("  [STATE] %s: %s -> %s" % [unit_name, old_name, new_name])


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if delta < 0:
		print("  [DAMAGE] %s hit for %d! HP: %d -> %d" % [unit_name, abs(delta), old_hp, new_hp])
	elif delta > 0:
		print("  [HEAL] %s healed for %d! HP: %d -> %d" % [unit_name, delta, old_hp, new_hp])


func on_victory(winning_team: int):
	var results = []
	results.append("[PASS] SpeedBreak" if _speed_break_landed else "[FAIL] SpeedBreak - never landed")
	results.append("[PASS] WeaponBreak" if _weapon_break_landed else "[FAIL] WeaponBreak - never landed")
	results.append("[PASS] MagicBreak" if _magic_break_landed else "[FAIL] MagicBreak - never landed")

	print("\n=== KNIGHT BREAK TEST RESULTS ===")
	for r in results:
		print("  %s" % r)

	var passed = int(_speed_break_landed) + int(_weapon_break_landed) + int(_magic_break_landed)
	print("  %d/3 tests passed" % passed)

	if passed == 3:
		print("[PASS] All knight break tests passed")
	else:
		print("[FAIL] %d/3 knight break tests failed" % (3 - passed))
		_rlog.log_entry("TEST_FAIL", {
			"speed_break": _speed_break_landed,
			"weapon_break": _weapon_break_landed,
			"magic_break": _magic_break_landed,
		})
	print("=================================")
