extends GPUCombatTestBase

## GPU regression: a unit whose target dies WHILE it is mid-march must still
## settle to IDLE and celebrate, so victory fires (issue: navigator Gariland
## battle hung — a guest stuck WALKING toward a corpse's stale destination never
## celebrated, blocking `check_victory`'s "all team-0 survivors CELEBRATING").
##
## Setup:
##   - team0 "Marcher" starts FAR from the lone enemy with an ATTACK-nearest
##     gambit, so it spends many ticks APPROACHING.
##   - team0 "Assassin" starts ADJACENT to the enemy and one-shots it within the
##     first attack cycle — i.e. the enemy dies WHILE the Marcher is still
##     walking, never having reached an attack tile.
##   - team1 "Victim" just WAITs (1 HP) so it holds still and dies instantly.
##
## Before the fix, `handle_moving_state` skipped its target re-eval when the
## current target was dead (gated on `!is_unit_dead(target)`) and kept stepping
## toward the dead unit's stale U_DEST — the Marcher looped WALKING forever and
## victory never fired. After the fix it re-picks (no enemies remain) → IDLE →
## CELEBRATING → team 0 wins.
##
## Assertions: the Marcher genuinely walked, was NOT adjacent when the enemy
## died (so the bug path is exercised), and team 0 wins.

const MARCHER := 0
const ASSASSIN := 1
const VICTIM := 2

var _marcher_walked: bool = false
var _victim_dead: bool = false
var _marcher_dist_at_death: int = -1
var _done: bool = false


func get_test_name() -> String:
	return "GPU Target-Died-Mid-Walk Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Marcher",
			"pos_x": 3, "pos_z": 5,
			"hp": 200, "max_hp": 200,
			"pa": 10, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"move": 5, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19,
			"body_sprite_id": 0x02
		},
		{
			"name": "Assassin",
			"pos_x": 7, "pos_z": 5,
			"hp": 200, "max_hp": 200,
			"pa": 10, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50,
			"move": 5, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19,
			"body_sprite_id": 0x02
		}
	]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "Victim",
		"pos_x": 8, "pos_z": 5,
		"hp": 100, "max_hp": 100,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 50,
		"move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	# The Victim just holds position (dies where it stands); both team-0 units
	# attack the nearest enemy.
	if unit_idx == VICTIM:
		return [make_wait_gambit()]
	return [make_attack_gambit()]


func on_state_changed(unit_idx: int, _old_state: int, new_state: int):
	if unit_idx != MARCHER:
		return
	if new_state == GPUConstants.LOGICAL_ACTIVITY_APPROACHING \
		or new_state == GPUConstants.LOGICAL_ACTIVITY_WALKING:
		_marcher_walked = true
	elif new_state == GPUConstants.LOGICAL_ACTIVITY_CELEBRATING and not _victim_dead:
		# The Marcher settles to CELEBRATING only after re-evaluating a dead
		# target (the fix). Snapshot its distance from where the Victim stood: a
		# distance > 1 proves it was still mid-march (never reached an attack
		# tile) — exactly the case the fix targets.
		_victim_dead = true
		var states = gpu_state_reader.get_all_unit_states()
		var marcher = states[MARCHER]
		var victim = states[VICTIM]
		_marcher_dist_at_death = abs(marcher["pos_x"] - victim["pos_x"]) \
			+ abs(marcher["pos_z"] - victim["pos_z"])
		print("[diag] Marcher celebrated %d tiles from the Victim's tile" % _marcher_dist_at_death)


func on_victory(winning_team: int):
	if _done:
		return
	_done = true

	print("\n=== TARGET-DIED-MID-WALK TEST RESULTS ===")
	print("  winner = %d, marcher walked = %s, marcher dist at enemy death = %d" % [
		winning_team, _marcher_walked, _marcher_dist_at_death])

	var ok := true
	if winning_team != 0:
		print("  [x] expected team 0 to win, got %d" % winning_team)
		ok = false
	if not _marcher_walked:
		print("  [x] Marcher never entered APPROACHING — bug path not exercised")
		ok = false
	if _marcher_dist_at_death <= 1:
		print("  [x] enemy died with Marcher already adjacent (dist %d) — bug path not exercised" % _marcher_dist_at_death)
		ok = false

	if ok:
		print("[PASS] mid-walk unit whose target died settled and celebrated; victory fired")
	else:
		print("[FAIL] target-died-mid-walk did not resolve to a clean team-0 victory")
	print("=== END RESULTS ===")
	get_tree().quit()
