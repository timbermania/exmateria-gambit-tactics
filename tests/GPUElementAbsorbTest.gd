extends GPUCombatTestBase

## GPU Element Absorb Test (issue #110)
##
## Witnesses the target-side absorb flip: a Fire spell against a target
## carrying [b]Flame Shield[/b] (item id 135, [code]attributes.absorb_elements
## = ["Fire"][/code]) heals instead of damaging. The queued damage flips sign
## at the encode-boundary [code]apply_element_defense[/code] call inside
## stage_spell, so the [code]U_DAMAGE_AMOUNT[/code] going into stage_damage
## Phase 2 is negative; the heal-only branch of Phase 3 raises HP.
##
## Layout (Manhattan):
##   Mage   (team 0, caster) at (0, 0)
##   Target (team 1, Flame Shield equipped) at (3, 0) -- in Fire range 4
##
## PASS: target HP rises above starting HP (any positive delta) within window.
## FAIL: HP stays flat or drops, or the queued amount never resolves.

const ABILITY_FIRE = 16
const FLAME_SHIELD_ID = 135
const TARGET_START_HP = 100
const TARGET_MAX_HP = 999  # well above start so the heal isn't capped


func get_test_name() -> String:
	return "GPU Element Absorb Test (Fire vs Flame Shield)"


func get_team0_unit_configs() -> Array:
	return [{
		"name": "Mage",
		"pos_x": 0, "pos_z": 0,
		"hp": 500, "max_hp": 500,
		"pa": 5, "ma": 14, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 99, "max_mp": 99,
		"speed": 100, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x04,
	}]


func get_team1_unit_configs() -> Array:
	return [{
		"name": "FlameShieldKnight",
		"pos_x": 3, "pos_z": 0,
		"hp": TARGET_START_HP, "max_hp": TARGET_MAX_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
		"element_defense_items": [FLAME_SHIELD_ID],
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	# Fire ct=4 -> 120 charge + anim + projectile + slack.
	max_ticks = 1200
	super._ready()


var _absorb_witnessed_tick: int = -1
var _absorb_hp_delta: int = 0
var _results_printed: bool = false


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	var hp_now := int(states[1].get("hp", TARGET_START_HP))
	if _absorb_witnessed_tick < 0 and hp_now > TARGET_START_HP:
		_absorb_witnessed_tick = current_tick
		_absorb_hp_delta = hp_now - TARGET_START_HP
		_print_results(states)
		return

	if hp_now < TARGET_START_HP:
		# Damage actually landed -- absorb flip didn't fire; capture and bail.
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var hp_now := int(states[1].get("hp", TARGET_START_HP))
	var absorb_mask := int(states[1].get("element_absorb_mask", 0))
	var fire_bit_mask := 1 << 1  # AB_ELEMENT Fire = 1

	print("\n=== ELEMENT ABSORB TEST RESULTS ===")
	print("  FlameShieldKnight HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, hp_now, hp_now - TARGET_START_HP])
	print("  element_absorb_mask = 0x%02X (Fire bit %s)" % [
		absorb_mask,
		"SET" if (absorb_mask & fire_bit_mask) != 0 else "missing"])
	print("  absorb_witness_tick = %d" % _absorb_witnessed_tick)

	var preseed_ok := (absorb_mask & fire_bit_mask) != 0
	var hp_up := _absorb_witnessed_tick >= 0 and hp_now > TARGET_START_HP
	if preseed_ok and hp_up:
		print("\n[PASS] Flame Shield absorbed Fire (HP +%d)" % _absorb_hp_delta)
	else:
		var why: Array = []
		if not preseed_ok: why.append("absorb mask missing Fire bit (Flame Shield encode failed)")
		if not hp_up:      why.append("HP did not rise within %d ticks" % max_ticks)
		print("\n[FAIL] %s" % ", ".join(why))
	print("===================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
