extends GPUCombatTestBase

## GPU Undead Inversion Test
##
## Tests Tier 2 #10 — STATUS_UNDEAD inverts damage into healing.
##
## A normal melee attacker swings an undead defender. Without inversion
## the defender would lose 50 HP (PA*WP = 10*5). With inversion the
## "damage" feeds Phase 3's undead branch and HP goes UP by 50 instead.
## Defender's MAX_HP is 200 so the heal lands cleanly under the cap.
##
## (Heal-on-undead → damage is the symmetric case; testing it requires an
## AOE heal centered on an ally-team undead, which is a separate setup.)

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


func get_test_name() -> String:
	return "GPU Undead Inversion Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Attacker", "pos_x": 1, "pos_z": 0,
			"hp": 200, "max_hp": 200, "pa": 10, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Undead_Defender", "pos_x": 2, "pos_z": 0,
			"hp": 100, "max_hp": 200, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
			"status_flags_lo": (1 << StatusRegistry.bit(&"undead")),
		},
	]


func get_gambits_for_unit(_unit_idx: int, team: int) -> Array:
	return [make_attack_gambit()] if team == 0 else []


var _initial_defender_hp: int = -1
var _post_hit_hp: int = -1
var _results_printed: bool = false
var _check_timer: float = 0.0


func _ready():
	max_ticks = 300
	super._ready()


func _process(delta):
	super._process(delta)
	if _results_printed or not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.2:
		return
	_check_timer = 0.0

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	if _initial_defender_hp < 0:
		_initial_defender_hp = int(states[1].get("hp", 0))

	var def_hp = int(states[1].get("hp", 0))
	if def_hp != _initial_defender_hp and _post_hit_hp < 0:
		_post_hit_hp = def_hp
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	# Expected: hp 100 → 150 (heal +50, capped at 200).
	var expected = 150
	var ok = _post_hit_hp == expected

	print("\n=== UNDEAD INVERSION TEST RESULTS ===")
	print("  Defender HP: %d (initial %d, expected %d)" % [
		_post_hit_hp, _initial_defender_hp, expected])
	if ok:
		print("[PASS] Damage inverted to healing on STATUS_UNDEAD target")
	else:
		var dir = "decreased" if _post_hit_hp < _initial_defender_hp else "increased by wrong amount"
		print("[FAIL] HP %s instead of healing to %d" % [dir, expected])
	print("======================================\n")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _results_printed:
		_print_results()
