extends GPUCombatTestBase

## GPU Melee Hit Cloud Test — happy path (slice 1)
##
## A basic melee STRIKE carries the PostGenericAttack (0xDE) opcode, so it must
## produce a hit cloud for the struck target. This guards that re-routing the
## cloud onto the opcode path (away from the damage event) does not silence the
## normal case.
##
## The hit is deliberately NON-LETHAL: a killing blow emits only DIED and
## suppresses HP_CHANGED (GPUCombatInterpreter), so a one-shot would never
## exercise the cloud path. The target survives; the test quits on the first
## observed melee cloud, so the count is exactly one by construction.
##
## Observed at the `hit_cloud_hook` seam (ADR-0018) — the sibling of
## spell_effect_hook. See docs/VFX_TRIGGER_ARCHITECTURE.md and its companion
## Dash test (GPUDashNoHitCloudTest), which asserts the zero case.

var _melee_cloud_count: int = 0
var _finished: bool = false


func get_test_name() -> String:
	return "GPU Melee Hit Cloud Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Striker",
		"pos_x": 2, "pos_z": 1,
		"hp": 200, "max_hp": 200,
		"pa": 8, "ma": 5, "wp": 5,  # PA*WP = 40 — non-lethal vs a 500-HP target
		"brave": 50, "faith": 50,
		"mp": 20, "max_mp": 20,
		"speed": 100,
		"move": 4, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,  # STRIKING -> SWING animation (carries 0xDE)
		"weapon_type": 1,   # Sword
		"weapon_id": 19,    # Broad Sword
		"body_sprite_id": 0x02,
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Target",
		"pos_x": 2, "pos_z": 2,  # adjacent — no pathing needed
		"hp": 500, "max_hp": 500,  # survives the strike so HP_CHANGED fires
		"pa": 5, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"mp": 20, "max_mp": 20,
		"speed": 1,   # slow so it never acts
		"move": 3, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,
		"weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x05,
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	# Striker attacks; Target waits so the ONLY melee cloud is the striker's
	# landed blow (no retaliation cloud to muddy the count).
	if unit_idx == 0:
		return [make_attack_gambit()]
	return [{
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_WAIT,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_SELF,
	}]


## Seam override (ADR-0018): count the hit clouds, then forward. Quit on the
## first one — its existence (and correct target) is the assertion.
func _spawn_hit_cloud(position: Vector3, impact_dir: Vector3, target: Node, ability_id: int):
	_melee_cloud_count += 1
	print("  [HIT_CLOUD] melee cloud #%d for %s" % [
		_melee_cloud_count, target.name if is_instance_valid(target) else "?"])
	super(position, impact_dir, target, ability_id)
	_finish(target)


func _finish(cloud_target: Node) -> void:
	if _finished:
		return
	_finished = true
	if _melee_cloud_count == 1 and cloud_target == units[1]:
		print("\n[PASS] Basic melee strike produced a hit cloud for the struck target")
	else:
		print("\n[FAIL] Expected 1 melee cloud for Target, got %d (target=%s)" % [
			_melee_cloud_count, cloud_target.name if is_instance_valid(cloud_target) else "?"])
	get_tree().quit()


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s hit for %d! HP=%d" % [units[unit_idx].name, abs(delta), new_hp])


func on_victory(_winning_team: int):
	# Reached only if the strike never produced a cloud (target eventually died).
	if not _finished:
		print("\n[FAIL] Strike landed but no melee hit cloud was ever observed")
