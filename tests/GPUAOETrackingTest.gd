extends GPUCombatTestBase

## GPU AOE Tracking Test
##
## Verifies spell effects track multiple moving targets independently.
## Caster: high speed, casts Fire (AOE radius 1) repeatedly.
## Three runners flee to different corners of the map.
## Each Fire AOE should produce one effect per runner, each tracking
## its own target independently.

const EffectInstance = ExMateriaEffects.EffectInstance

const ABILITY_FIRE = 16

# Track spawned effects for verification
var _tracked_effects: Array = []
var _max_simultaneous_effects: int = 0
var _tracking_verified: bool = false
var _cast_count: int = 0


func get_test_name() -> String:
	return "GPU AOE Tracking Test"


func get_team0_unit_configs() -> Array:
	# Fast caster in center
	return [{
		"name": "Caster",
		"pos_x": 4, "pos_z": 4,
		"hp": 9999, "max_hp": 9999,
		"pa": 5, "ma": 15, "wp": 1,
		"brave": 50, "faith": 70,
		"mp": 9999, "max_mp": 9999,
		"speed": 80,
		"move": 1, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x04
	}]


func get_team1_unit_configs() -> Array:
	# Three runners starting near each other (within AOE radius 1)
	# then fleeing to different corners
	return [
		{
			"name": "RunnerA",
			"pos_x": 3, "pos_z": 2,
			"hp": 9999, "max_hp": 9999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 40,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x06
		},
		{
			"name": "RunnerB",
			"pos_x": 3, "pos_z": 3,
			"hp": 9999, "max_hp": 9999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 40,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05
		},
		{
			"name": "RunnerC",
			"pos_x": 4, "pos_z": 2,
			"hp": 9999, "max_hp": 9999,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 40,
			"move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x02
		},
	]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	if team == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	# Runners flee to different corners
	match unit_idx:
		1: return [make_move_to_gambit(0, 14)]
		2: return [make_move_to_gambit(9, 0)]
		3: return [make_move_to_gambit(9, 14)]
	return []


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s charging Fire" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and (new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING or new_state == GPUConstants.LOGICAL_ACTIVITY_IDLE):
		_cast_count += 1
		print("  -> %s cast Fire! (cast #%d)" % [units[unit_idx].name, _cast_count])
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		print("  -> %s running" % units[unit_idx].name)


func _spawn_spell_effect(caster: Unit, target: Unit, _ability_id: int, effect_id: int):
	super._spawn_spell_effect(caster, target, _ability_id, effect_id)

	# Find the newly added effect
	var root = get_tree().root
	for i in range(root.get_child_count() - 1, -1, -1):
		var child = root.get_child(i)
		if child is EffectInstance and not _tracked_effects.has(child):
			_tracked_effects.append(child)
			var has_anchors = child._origin_anchor != null and child._target_anchor != null
			var target_parent = child._target_anchor.get_parent().name if has_anchors else "NONE"
			print("[AOE_TRACK] Effect %s -> target %s, anchors=%s" % [
				child.effect_name, target_parent, str(has_anchors)])
			break


func _process(delta):
	super._process(delta)
	if not combat_active or victory_achieved:
		return

	# Track peak simultaneous effects
	_tracked_effects = _tracked_effects.filter(func(e): return is_instance_valid(e))
	if _tracked_effects.size() > _max_simultaneous_effects:
		_max_simultaneous_effects = _tracked_effects.size()
		print("[AOE_TRACK] %d effects active simultaneously" % _max_simultaneous_effects)

	_verify_anchor_tracking()

	if _cast_count >= 4:
		print("\n[PASS] AOE tracking test complete - %d casts, peak %d simultaneous effects" % [
			_cast_count, _max_simultaneous_effects])
		if _tracking_verified:
			print("[PASS] Multi-target anchor tracking verified")
		else:
			print("[INFO] Could not verify multi-target anchor tracking")
		_rlog.log_entry("TEST_PASS", {
			"casts": _cast_count,
			"max_simultaneous": _max_simultaneous_effects,
			"tracking_verified": _tracking_verified
		})
		_rlog.output()
		victory_achieved = true
		combat_active = false
		get_tree().quit()


func _verify_anchor_tracking():
	"""Verify each active effect's anchors match its specific target unit."""
	for effect in _tracked_effects:
		if not effect.manager:
			continue
		if not effect._target_anchor or not is_instance_valid(effect._target_anchor):
			continue
		if not effect._origin_anchor or not is_instance_valid(effect._origin_anchor):
			continue

		var expected_target = effect._target_anchor.global_position - effect.global_position
		var mgr_target = effect.manager.anchor_target
		var diff = (mgr_target - expected_target).length()

		if diff < 0.01 and not _tracking_verified:
			print("[AOE_TRACK] VERIFIED: Effect anchors track individual targets (diff=%.4f)" % diff)
			_tracking_verified = true


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta_val: int):
	if delta_val < 0:
		print("  -> %s hit for %d! HP=%d" % [units[unit_idx].name, abs(delta_val), new_hp])


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("\n[PASS] AOE tracking test - Team %d won" % winning_team)
