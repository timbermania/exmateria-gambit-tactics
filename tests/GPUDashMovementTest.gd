extends GPUCombatTestBase

## Tests Dash ability (ID 147) distort movement opcodes.
## Squire should: step back (wind-up), charge to target, return home.
## PASS: Target takes damage from Dash.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


const ABILITY_DASH = 147

var _done: bool = false


func get_test_name() -> String:
	return "GPU Dash Movement Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Squire",
		"pos_x": 3, "pos_z": 3,
		"hp": 200, "max_hp": 200,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,  # Broad Sword
		"body_sprite_id": 0x02,
		"speed": 100
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Target",
		"pos_x": 4, "pos_z": 3,  # Adjacent (range 1 for Dash)
		"hp": 999, "max_hp": 999,  # High HP so test runs multiple Dashes
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"move": 0, "jump": 3,  # move=0 so target stays put
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x05,
		"speed": 1  # Very slow so Squire always acts first
	}]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team == 0:
		return [make_ability_gambit(ABILITY_DASH, GPUConstants.TARGET_NEAREST_ENEMY)]
	else:
		return [make_attack_gambit()]


func _ready():
	max_ticks = 3000
	super._ready()
	call_deferred("_print_dash_debug")


func _print_dash_debug():
	print("\n=== DASH MOVEMENT TEST ===")
	var ability := AbilityDatabase.get_ability_view(ABILITY_DASH)
	print("[DASH] Ability 147: %s" % ability.name)
	print("[DASH] effect_anim_id=%d ct=%d range=%d formula=%d" % [
		ability.effect_anim_id,
		ability.ct,
		ability.range,
		ability.formula])
	# Check that animation 212 exists and has distort opcodes
	if units.size() > 0:
		var unit = units[0]
		if unit.animation_set:
			var anim_key = "212"
			if unit.animation_set.type1_seq.has(anim_key):
				var seq = unit.animation_set.type1_seq[anim_key]
				print("[DASH] Animation 212 opcodes (%d):" % seq.size())
				for op in seq:
					print("  %s p0=%s p1=%s" % [
						op.get("op_code_name", "?"),
						str(op.get("op_code_param_0", "")),
						str(op.get("op_code_param_1", ""))])
			else:
				print("[DASH] WARNING: Animation 212 not found!")
	print("=== END DASH DEBUG ===\n")


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(old_state)
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(new_state)
	print("  [STATE] %s: %s -> %s" % [unit_name, old_name, new_name])


func on_hp_changed(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	if _done:
		return
	var unit_name = units[unit_idx].name if unit_idx < units.size() else "Unit%d" % unit_idx
	if unit_idx == 1 and delta < 0:
		_done = true
		print("\n[PASS] Dash dealt %d damage to %s (HP: %d -> %d)" % [
			abs(delta), unit_name, old_hp, new_hp])
		_rlog.log_entry("TEST_PASS", {"damage": abs(delta)})
		_rlog.output()
		victory_achieved = true
		combat_active = false
		get_tree().quit()
	elif delta < 0:
		print("  [DAMAGE] %s: %d -> %d (-%d)" % [unit_name, old_hp, new_hp, abs(delta)])


func on_victory(winning_team: int):
	if not _done:
		print("\n[FAIL] Dash test: no damage dealt to Target before victory (team %d won)" % winning_team)
		_rlog.log_entry("TEST_FAIL", {"reason": "no_damage_to_target"})
		_rlog.output()
		get_tree().quit()
