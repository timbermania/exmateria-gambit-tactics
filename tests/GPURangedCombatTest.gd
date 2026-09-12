extends GPUCombatTestBase

## GPU Ranged Combat Test
##
## Tests ranged combat with bows (range 5, DIRECT attack).
## Expected: Units attack at distance without moving.
##
## Also asserts the firer transits LOGICAL_ACTIVITY_AWAITING_IMPACT after SEQ end and
## before damage landing (ADR-0032), with the ADR-0026 assertion shape
## (activity, current_animation_front, last_resolution.source).


var _awaiting_impact_assertions: int = 0
var _awaiting_impact_failures: Array[String] = []


func get_test_name() -> String:
	return "GPU Ranged Combat Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Archer",
		"pos_x": 0, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 6, "ma": 5, "wp": 4,  # PA*WP = 24 damage per hit
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 5,
		"weapon_flags": 4,  # DIRECT (no vertical limit)
		"weapon_type": 11,  # Bow animation
		"weapon_id": 83,    # Long Bow (equip visually)
		"body_sprite_id": 0x03
	}]


func get_team1_unit_configs() -> Array:
	# Runner starts close and flees - tests projectile tracking moving target
	return [{
		"name": "Runner",
		"pos_x": 3, "pos_z": 0,  # Start close to archer
		"hp": 200, "max_hp": 200,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1,
		"weapon_flags": 1,
		"weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x05
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		# Archer attacks
		return [make_attack_gambit()]
	else:
		# Runner flees to far corner (9, 9)
		return [make_move_to_gambit(9, 9)]


func on_state_changed(unit_idx: int, old_state: int, new_state: int):
	if old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		print("  -> %s attacking" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		if unit_idx == 1:
			print("  -> %s fleeing!" % units[unit_idx].name)
		else:
			print("  -> %s moving" % units[unit_idx].name)
	elif old_state == GPUConstants.LOGICAL_ACTIVITY_WALKING and new_state == GPUConstants.LOGICAL_ACTIVITY_IDLE:
		print("  -> %s stopped moving" % units[unit_idx].name)


func on_hp_changed(unit_idx: int, _old_hp: int, new_hp: int, delta: int):
	if delta < 0:
		print("  -> %s hit by arrow for %d! HP=%d" % [units[unit_idx].name, abs(delta), new_hp])


func on_awaiting_impact(unit_idx: int) -> void:
	"""ADR-0032 assertion: when the firer enters LOGICAL_ACTIVITY_AWAITING_IMPACT, the
	CPU activity must be AWAITING_IMPACT, the BODY render field bound to the
	resolved slot, and last_resolution.source == "atlas". Matches the ADR-0026
	external-behaviour shape; no internal U_TIMER values are asserted."""
	var unit = units[unit_idx] if unit_idx < units.size() else null
	if not is_instance_valid(unit):
		return
	_awaiting_impact_assertions += 1
	var A = DisplayActivity.Activity
	if unit.activity != A.AWAITING_IMPACT:
		_awaiting_impact_failures.append("%s activity is %s, expected AWAITING_IMPACT" % [
			unit.name, A.keys()[unit.activity]])
		return
	var r = unit.last_resolution
	if r == null or r.source != "atlas":
		_awaiting_impact_failures.append("%s last_resolution.source=%s, expected atlas" % [
			unit.name, "null" if r == null else r.source])
		return
	if unit.current_animation_front != str(r.body_slot):
		_awaiting_impact_failures.append("%s current_animation_front=%s, expected %d" % [
			unit.name, unit.current_animation_front, r.body_slot])


func on_victory(winning_team: int):
	if winning_team >= 0:
		print("\n[PASS] Ranged combat resolved - Team %d won" % winning_team)
	else:
		print("\n[FAIL] Ranged combat ended in a draw")
	if _awaiting_impact_assertions == 0:
		print("[FAIL] ADR-0032: firer never entered LOGICAL_ACTIVITY_AWAITING_IMPACT")
	elif _awaiting_impact_failures.is_empty():
		print("[PASS] ADR-0032: LOGICAL_ACTIVITY_AWAITING_IMPACT entry asserted %d times" % _awaiting_impact_assertions)
	else:
		for msg in _awaiting_impact_failures:
			print("[FAIL] ADR-0032 awaiting_impact: %s" % msg)
