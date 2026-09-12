extends GPUCombatTestBase

## GPU Reaction Defender Test
##
## Tests Tier 2 #7 (partial) — the three defender-side reactions resolved
## in stage_damage's Phase 3:
##
##   REACT_MANA_SHIELD (6) — drain MP first, overflow hits HP
##   REACT_ABSORB_MP   (2) — gain MP equal to damage/4 (capped)
##   REACT_AUTO_POTION (3) — if surviving HP < max_hp/4, heal +AUTO_POTION_HEAL_AMOUNT
##
## Three defenders + three matching attackers. Each attacker walks up to
## adjacency and swings exactly once with a known WP, producing a known
## damage = PA * WP. After the swing lands the test verifies HP / MP.

const REACT_MANA_SHIELD = 6
const REACT_ABSORB_MP   = 2
const REACT_AUTO_POTION = 3
const AUTO_POTION_HEAL  = 50

# Defender expectations after the first hit.
var _results: Dictionary = {}
var _initial_hp: Dictionary = {}
var _initial_mp: Dictionary = {}
var _done_logged: bool = false
var _check_timer: float = 0.0


func get_test_name() -> String:
	return "GPU Reaction Defender Test"


func get_team0_unit_configs() -> Array:
	# Attackers — pa * wp gives the chosen damage.
	return [
		{
			"name": "Atk_Shield", "pos_x": 0, "pos_z": 0,
			"hp": 200, "max_hp": 200, "pa": 10, "ma": 5, "wp": 5,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
		},
		{
			"name": "Atk_Absorb", "pos_x": 0, "pos_z": 2,
			"hp": 200, "max_hp": 200, "pa": 10, "ma": 5, "wp": 4,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
		},
		{
			"name": "Atk_Potion", "pos_x": 0, "pos_z": 4,
			"hp": 200, "max_hp": 200, "pa": 10, "ma": 5, "wp": 8,
			"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
			"speed": 100, "move": 4, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
			"weapon_id": 19, "body_sprite_id": 0x02,
		},
	]


func get_team1_unit_configs() -> Array:
	# Defenders — each with one of the three reactions equipped.
	return [
		# Mana Shield: 100 MP / 100 HP. Takes 50 → MP 50, HP 100.
		{
			"name": "Def_ManaShield", "pos_x": 2, "pos_z": 0,
			"hp": 100, "max_hp": 100, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 100, "max_mp": 100,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05, "reaction_ability": REACT_MANA_SHIELD,
		},
		# Absorb MP: 0 MP / 100 HP. Takes 40 → MP 10, HP 60.
		{
			"name": "Def_AbsorbMP", "pos_x": 2, "pos_z": 2,
			"hp": 100, "max_hp": 100, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 100,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05, "reaction_ability": REACT_ABSORB_MP,
		},
		# Auto-Potion: 100 HP / 200 max. Takes 80 → 20, heal +50 → 70.
		{
			"name": "Def_AutoPotion", "pos_x": 2, "pos_z": 4,
			"hp": 100, "max_hp": 200, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05, "reaction_ability": REACT_AUTO_POTION,
		},
	]


func get_gambits_for_unit(unit_idx: int, team: int) -> Array:
	# Only attackers act; defenders idle.
	if team == 0:
		return [make_attack_gambit()]
	return []


func _ready():
	max_ticks = 500
	super._ready()
	# Record initial HP/MP for after-the-fact deltas.
	for i in range(3, 6):
		_initial_hp[i] = -1
		_initial_mp[i] = -1


func _capture_initial(states: Array) -> void:
	for i in range(3, 6):
		if _initial_hp[i] < 0 and i < states.size():
			_initial_hp[i] = int(states[i].get("hp", 0))
			_initial_mp[i] = int(states[i].get("mp", 0))


func _process(delta):
	super._process(delta)
	if _done_logged or not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.2:
		return
	_check_timer = 0.0

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 6:
		return
	_capture_initial(states)

	# Wait until all three defenders have taken their first hit (hp dropped
	# from initial or mp changed for absorb/shield cases). Each defender
	# is hit exactly once because attackers die quickly after a single swing
	# from no return fire... actually attackers don't die. Re-evaluate.
	# Strategy: capture the FIRST observed post-damage HP/MP per defender
	# and never overwrite. Print results once all three have an observation.
	for i in range(3, 6):
		if _results.has(i):
			continue
		var hp: int = int(states[i].get("hp", 0))
		var mp: int = int(states[i].get("mp", 0))
		# Hit registered when HP or MP changed from initial.
		if hp != _initial_hp[i] or mp != _initial_mp[i]:
			_results[i] = {"hp": hp, "mp": mp}

	if _results.size() == 3:
		_print_results()


func _print_results():
	if _done_logged:
		return
	_done_logged = true

	# Expected post-hit values:
	#   Mana Shield (3): pa*wp=50; mp 100→50, hp 100.
	#   Absorb MP  (4):  pa*wp=40; mp 0→10, hp 100→60.
	#   Auto-Potion(5):  pa*wp=80; hp 100→20→70 (max=200, threshold=50), mp 0.
	var expected = {
		3: {"hp": 100, "mp": 50,  "label": "ManaShield"},
		4: {"hp":  60, "mp": 10,  "label": "AbsorbMP"},
		5: {"hp":  70, "mp":  0,  "label": "AutoPotion"},
	}

	print("\n=== REACTION DEFENDER TEST RESULTS ===")
	var pass_count = 0
	for i in [3, 4, 5]:
		var got: Dictionary = _results.get(i, {"hp": -1, "mp": -1})
		var exp: Dictionary = expected[i]
		var hp_ok = got.hp == exp.hp
		var mp_ok = got.mp == exp.mp
		var verdict = "PASS" if (hp_ok and mp_ok) else "FAIL"
		print("  [%s] %s: hp=%d (expected %d), mp=%d (expected %d)" % [
			verdict, exp.label, got.hp, exp.hp, got.mp, exp.mp])
		if hp_ok and mp_ok:
			pass_count += 1

	if pass_count == 3:
		print("\n[PASS] All 3 defender reactions resolved correctly")
	else:
		print("\n[FAIL] %d/3 defender reactions correct" % pass_count)
	print("=========================================\n")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _done_logged:
		_print_results()
