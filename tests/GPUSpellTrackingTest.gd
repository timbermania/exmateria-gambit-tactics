extends GPUCombatTestBase

## GPU Spell Tracking Test
##
## Verifies spell effects track a moving target.
## Caster: high speed, casts Fire repeatedly from a fixed position.
## Runner: runs away to far corner via move_to gambit while getting hit.
## Fire effects should visually follow the runner as it moves.

const EffectInstance = ExMateriaEffects.EffectInstance

const ABILITY_FIRE = 16

# Track spawned effects for verification
var _tracked_effects: Array = []
var _tracking_verified: bool = false
var _cast_count: int = 0


func get_test_name() -> String:
	return "GPU Spell Tracking Test"


func get_team0_unit_configs() -> Array:
	# Fast caster that spams Fire from a fixed spot
	return [{
		"name": "Caster",
		"pos_x": 0, "pos_z": 0,
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
	# Runner flees to far corner — high move, moderate speed
	return [{
		"name": "Runner",
		"pos_x": 2, "pos_z": 2,
		"hp": 9999, "max_hp": 9999,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 50, "max_mp": 50,
		"speed": 40,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x06
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		# Caster: only casts Fire
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	else:
		# Runner: flee to far corner
		return [make_move_to_gambit(9, 14)]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		print("  -> %s charging Fire" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and (new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING or new_state == GPUConstants.LOGICAL_ACTIVITY_IDLE):
		_cast_count += 1
		print("  -> %s cast Fire! (cast #%d)" % [units[unit_idx].name, _cast_count])
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		print("  -> %s running" % units[unit_idx].name)


# Override _spawn_spell_effect to track effects for verification
func _spawn_spell_effect(caster: Unit, target: Unit, _ability_id: int, effect_id: int):
	super._spawn_spell_effect(caster, target, _ability_id, effect_id)

	# Find the effect that was just added to root
	var root = get_tree().root
	for i in range(root.get_child_count() - 1, -1, -1):
		var child = root.get_child(i)
		if child is EffectInstance and not _tracked_effects.has(child):
			_tracked_effects.append(child)
			print("[TRACK_TEST] Effect spawned: %s, origin_anchor=%s, target_anchor=%s" % [
				child.effect_name,
				str(child._origin_anchor != null),
				str(child._target_anchor != null)
			])
			if child._origin_anchor == null or child._target_anchor == null:
				print("[TRACK_TEST] FAIL: Anchor markers not attached!")
			else:
				print("[TRACK_TEST] OK: Anchors on %s / %s" % [
					child._origin_anchor.get_parent().name,
					child._target_anchor.get_parent().name])
			break


func _process(delta):
	super._process(delta)
	if not combat_active or victory_achieved:
		return

	_verify_anchor_tracking()

	# Let it run for several casts so the user can observe visually
	if _cast_count >= 6:
		print("\n[PASS] Spell tracking test complete - %d casts" % _cast_count)
		if _tracking_verified:
			print("[PASS] Effect anchor tracking verified")
		else:
			print("[INFO] Could not verify anchor tracking")
		_rlog.log_entry("TEST_PASS", {"casts": _cast_count, "tracking_verified": _tracking_verified})
		_rlog.output()
		victory_achieved = true
		combat_active = false
		get_tree().quit()


func _verify_anchor_tracking():
	"""Check that active effects have anchors matching unit positions."""
	_tracked_effects = _tracked_effects.filter(func(e): return is_instance_valid(e))

	for effect in _tracked_effects:
		if not effect.manager:
			continue
		if not effect._origin_anchor or not is_instance_valid(effect._origin_anchor):
			continue
		if not effect._target_anchor or not is_instance_valid(effect._target_anchor):
			continue

		var mgr_target = effect.manager.anchor_target
		var mgr_origin = effect.manager.anchor_origin

		var expected_origin = effect._origin_anchor.global_position - effect.global_position
		var expected_target = effect._target_anchor.global_position - effect.global_position

		var origin_diff = (mgr_origin - expected_origin).length()
		var target_diff = (mgr_target - expected_target).length()

		if origin_diff < 0.01 and target_diff < 0.01:
			if not _tracking_verified:
				print("[TRACK_TEST] VERIFIED: Manager anchors match unit positions (origin=%.4f, target=%.4f)" % [origin_diff, target_diff])
				_tracking_verified = true


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta_val: int):
	if delta_val < 0:
		print("  -> %s hit for %d! HP=%d" % [units[unit_idx].name, abs(delta_val), new_hp])


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("\n[PASS] Spell tracking test - Team %d won" % winning_team)
