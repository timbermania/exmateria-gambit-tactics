extends GPUCombatTestBase

## GPU unit-anchored MOVE behaviour test (ADR-0062, issue #37).
##
## End-to-end through the encoder: a real `Gambit` (MOVE → nearest enemy) is
## projected by `GambitEncoder` to an `ACTION_MOVE_TO_UNIT` config and run on the
## GPU. Asserts the mover:
##   1. walks toward the enemy and STOPS ADJACENT (manhattan distance == 1),
##   2. NEVER attacks — the enemy's HP is untouched and the mover never enters
##      LOGICAL_ACTIVITY_ACTING (pure reposition; acting stays ATTACK/ABILITY's job).
## The enemy only WAITs, so combat never resolves — arrival detection quits.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.


const ENEMY_START_HP := 500

var _has_approached: bool = false
var _mover_acted: bool = false
var _done: bool = false


func get_test_name() -> String:
	return "GPU Move-To-Unit Test"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Mover",
		"pos_x": 0, "pos_z": 0,
		"hp": 200, "max_hp": 200,
		"pa": 10, "ma": 5, "wp": 5,
		"brave": 50, "faith": 50,
		"move": 5, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19,
		"body_sprite_id": 0x02
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Idler",
		"pos_x": 5, "pos_z": 0,
		"hp": ENEMY_START_HP, "max_hp": ENEMY_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		# MOVE toward the nearest enemy, always — encoded through GambitEncoder so
		# this exercises the real Gambit -> ACTION_MOVE_TO_UNIT projection.
		var g := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.MOVE, -1, TargetSelector.enemies())
		return GambitEncoder.encode_gambits([g])
	# The enemy just holds position so the battle never resolves into combat.
	return [make_wait_gambit()]


func on_state_changed(unit_idx: int, _old_state: int, new_state: int):
	if unit_idx != 0:
		return
	if new_state == GPUConstants.LOGICAL_ACTIVITY_APPROACHING:
		_has_approached = true
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		_mover_acted = true
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_IDLE and _has_approached:
		_check_arrival()


func _check_arrival():
	if _done:
		return
	_done = true
	var states = gpu_state_reader.get_all_unit_states()
	var mover = states[0]
	var enemy = states[1]
	var dist: int = abs(mover["pos_x"] - enemy["pos_x"]) + abs(mover["pos_z"] - enemy["pos_z"])
	var enemy_hp: int = enemy.get("hp", -1)

	print("\n=== MOVE-TO-UNIT TEST RESULTS ===")
	print("  Mover at (%d,%d), Idler at (%d,%d), manhattan dist = %d" % [
		mover["pos_x"], mover["pos_z"], enemy["pos_x"], enemy["pos_z"], dist])
	print("  Idler HP = %d (start %d), mover entered ACTING = %s" % [enemy_hp, ENEMY_START_HP, _mover_acted])

	var ok := true
	if dist != 1:
		print("  [x] expected mover to stop ADJACENT (dist 1), got %d" % dist)
		ok = false
	if enemy_hp != ENEMY_START_HP:
		print("  [x] mover damaged the enemy — MOVE must never attack")
		ok = false
	if _mover_acted:
		print("  [x] mover entered LOGICAL_ACTIVITY_ACTING — MOVE must never attack")
		ok = false

	if ok:
		print("[PASS] unit-anchored MOVE: stopped adjacent, never attacked")
	else:
		print("[FAIL] unit-anchored MOVE behaviour incorrect")
	print("=== END RESULTS ===")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _done:
		_check_arrival()
