extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: cast_cinematic_spell's AOE in-radius walk in stage_spell.glsl - `dist > effect_area` -> `dist > effect_area - 1` (shrinks the Fire cinematic-spell AOE radius) - EnemyC no longer gets stamped a pending fire frame, so all 3 are not damaged and the all_enemies_hit gate never trips -> TIMEOUT at tick 6000; GREEN unbroken on the reverted tree

## GPU AOE Combat Test
##
## Tests area-of-effect spell casting with Fire (ID 16, effect_area=1).
## Fire: MP 6, CT 4 (40 ticks), Range 4, AOE radius 1 (5 tiles).
##
## Setup:
## - Team 0: Mage at (0, 0) with Fire gambit
## - Team 1: Enemy A at (4, 0), Enemy B at (4, 1), Enemy C at (5, 0)
##
## Enemy B and C are within Manhattan distance 1 of Enemy A.
## When the mage targets Enemy A, AOE should hit all three enemies.

const ABILITY_FIRE = 16

var _enemies_damaged: Dictionary = {}  # unit_idx -> total damage taken


func get_test_name() -> String:
	return "GPU AOE Combat Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Mage",
		"pos_x": 0, "pos_z": 0,
		"hp": 999, "max_hp": 999,
		"pa": 5, "ma": 12, "wp": 1,
		"brave": 50, "faith": 70,
		"mp": 200, "max_mp": 200,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x04
	}]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "EnemyA",
			"pos_x": 4, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 50, "max_mp": 50,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x06
		},
		{
			"name": "EnemyB",
			"pos_x": 4, "pos_z": 1,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 50, "max_mp": 50,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x06
		},
		{
			"name": "EnemyC",
			"pos_x": 5, "pos_z": 0,
			"hp": 999, "max_hp": 999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 70,
			"mp": 50, "max_mp": 50,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x06
		},
	]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	# Enemies have no gambits — they stay in place so AOE targeting is deterministic
	return []


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s charging Fire spell" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		print("  -> %s cast Fire!" % units[unit_idx].name)
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST:
		print("  -> %s moving to get in range" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		_enemies_damaged[unit_idx] = _enemies_damaged.get(unit_idx, 0) + abs(delta)
		print("  -> %s hit by Fire for %d! HP=%d (total damage: %d)" % [
			units[unit_idx].name, abs(delta), new_hp, _enemies_damaged[unit_idx]])


func _process(delta):
	super._process(delta)
	if not combat_active or victory_achieved:
		return

	# Check if all 3 enemies have taken damage (AOE worked)
	# Enemy indices are 1, 2, 3 (index 0 is the mage)
	var enemies_hit = 0
	for idx in [1, 2, 3]:
		if _enemies_damaged.get(idx, 0) > 0:
			enemies_hit += 1

	if enemies_hit >= 3:
		print("\n[PASS] AOE test passed! All 3 enemies hit by Fire AOE:")
		for idx in [1, 2, 3]:
			print("  %s: total damage = %d" % [units[idx].name, _enemies_damaged.get(idx, 0)])
		_rlog.log_entry("TEST_PASS", {
			"reason": "all_enemies_hit",
			"enemies_hit": enemies_hit,
			"damage_A": _enemies_damaged.get(1, 0),
			"damage_B": _enemies_damaged.get(2, 0),
			"damage_C": _enemies_damaged.get(3, 0),
		})
		_rlog.output()
		victory_achieved = true
		combat_active = false
		get_tree().quit()


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("\n[RESULT] Team %d won" % winning_team)
