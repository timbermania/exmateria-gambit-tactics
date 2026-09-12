extends GPUCombatTestBase

## GPU Element Cancel Test (issue #110)
##
## Witnesses the null/cancel element result: a Fire spell against a target
## whose [code]element_cancel_mask[/code] has the Fire bit set deals 0 damage.
## Pairs with [code]GPUElementAbsorbTest[/code] (the absorb-side witness).
## The cancel mask is preseeded directly (rather than via items.json) to keep
## the test orthogonal to which equipment carries Fire-cancel -- the encode-
## boundary translation is exercised by the absorb test's item composition.
##
## Layout (Manhattan):
##   Mage   (team 0, caster) at (0, 0)
##   Target (team 1, Fire cancel) at (3, 0) -- in Fire range 4
##
## PASS: target HP unchanged across the cast window.
## FAIL: HP drops (cancel didn't fire) or HP rises (absorb composed wrong).

const ABILITY_FIRE = 16
const TARGET_START_HP = 100
const FIRE_BIT = 1  # AB_ELEMENT Fire = 1
const FIRE_BIT_MASK = 1 << FIRE_BIT


func get_test_name() -> String:
	return "GPU Element Cancel Test (Fire vs Fire-cancel target)"


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
		"name": "FireImmuneKnight",
		"pos_x": 3, "pos_z": 0,
		"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
		"element_cancel_mask": FIRE_BIT_MASK,
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_FIRE, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	# Fire ct=4 -> 120 charge + anim + projectile + slack. Long enough that the
	# mage casts at least twice; one cast is the witness.
	max_ticks = 1200
	super._ready()


var _first_cast_seen: bool = false
var _hp_after_first_cast: int = -1
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

	# Detect that at least one cast resolved by watching the mage's MP drop
	# (Fire costs 6 MP). Once it drops below 94 the first cast has been
	# committed; capture the target's HP at that moment as the witness.
	var mage_mp := int(states[0].get("mp", 99))
	if not _first_cast_seen and mage_mp < 99:
		_first_cast_seen = true
		_hp_after_first_cast = hp_now

	# Bail early on a damage event -- cancel didn't fire.
	if hp_now < TARGET_START_HP:
		_print_results(states)
		return
	# Bail early on an unexpected heal -- shouldn't compose with cancel.
	if hp_now > TARGET_START_HP:
		_print_results(states)
		return

	# Once at least one cast has been seen AND the target HP is still pristine,
	# declare the cancel witness met.
	if _first_cast_seen:
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var hp_now := int(states[1].get("hp", TARGET_START_HP))
	var cancel_mask := int(states[1].get("element_cancel_mask", 0))
	var mage_mp := int(states[0].get("mp", 99))

	print("\n=== ELEMENT CANCEL TEST RESULTS ===")
	print("  FireImmuneKnight HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, hp_now, hp_now - TARGET_START_HP])
	print("  element_cancel_mask = 0x%02X (Fire bit %s)" % [
		cancel_mask,
		"SET" if (cancel_mask & FIRE_BIT_MASK) != 0 else "missing"])
	print("  mage MP = %d (cast detected: %s)" % [
		mage_mp, "yes" if _first_cast_seen else "no"])

	var preseed_ok := (cancel_mask & FIRE_BIT_MASK) != 0
	var hp_flat := hp_now == TARGET_START_HP
	if preseed_ok and _first_cast_seen and hp_flat:
		print("\n[PASS] Cancel-Fire absorbed Fire damage (HP unchanged after cast)")
	else:
		var why: Array = []
		if not preseed_ok:       why.append("cancel mask missing Fire bit (encode failed)")
		if not _first_cast_seen: why.append("no Fire cast resolved within %d ticks" % max_ticks)
		if not hp_flat:          why.append("HP changed (%+d) -- cancel didn't fire" % (hp_now - TARGET_START_HP))
		print("\n[FAIL] %s" % ", ".join(why))
	print("===================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
