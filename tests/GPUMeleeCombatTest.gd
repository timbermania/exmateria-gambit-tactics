extends GPUCombatTestBase

## GPU Melee Combat Test
##
## Tests basic melee combat with two units equipped with swords.
## Expected: Units move toward each other, attack when adjacent, one dies.
##
## Also verifies the full death → SFX path end-to-end: the death triggers
## `unit_stats.die()` → `EventBus.unit_died` → `SfxRouter` → `combat.unit_died`
## cue. Synthetic coverage of the same wiring lives in `SfxRouterTest`; this
## test proves it survives the live combat path.


var _death_cue_count := 0


func _ready() -> void:
	SfxRouter.cue_requested.connect(_on_cue_requested)
	super()


func _on_cue_requested(name: String, _bank: String, _slot: int) -> void:
	if name == "combat.unit_died":
		_death_cue_count += 1


func get_test_name() -> String:
	return "GPU Melee Combat Test"


func get_team0_unit_configs() -> Array:
	# Original positions with height differences to test vertical attack limits
	return [{
		"name": "Swordsman",
		"pos_x": 0, "pos_z": 0,  # Height varies on this map
		"hp": 150, "max_hp": 150,
		"pa": 8, "ma": 5, "wp": 5,  # PA*WP = 40 damage per hit
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,  # STRIKING
		"weapon_type": 1,   # Sword -> SWING animation
		"weapon_id": 19,    # Broad Sword
		"body_sprite_id": 0x02
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Enemy",
		"pos_x": 2, "pos_z": 0,  # 2 tiles apart, will have height diff
		"hp": 150, "max_hp": 150,
		"pa": 8, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,
		"weapon_type": 1,
		"weapon_id": 19,    # Broad Sword
		"body_sprite_id": 0x05
	}]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return [make_attack_gambit()]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		print("  -> %s moving toward enemy" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_WALKING and new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		print("  -> %s in range, attacking!" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s hit for %d! HP=%d" % [units[unit_idx].name, abs(delta), new_hp])


func on_victory(winning_team: int):
	if winning_team < 0:
		print("\n[FAIL] Melee combat ended in a draw")
		return
	if _death_cue_count < 1:
		print("\n[FAIL] Team %d won but no combat.unit_died cue observed" % winning_team)
		return
	print("\n[PASS] Melee combat resolved - Team %d won (death cue x%d)" % [
		winning_team, _death_cue_count])
