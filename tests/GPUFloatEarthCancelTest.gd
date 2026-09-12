extends GPUCombatTestBase

## GPU Float × Earth Cancel Test (issue #112)
##
## Witnesses the status-driven element-defense overlay added in PRD #112.
## A Float-status target hit by an Earth-element spell takes [b]0[/b] damage,
## matching BATTLE.BIN [code]FUN_80186FF8[/code] at [code]0x801870D0[/code]
## (the Float branch tail-calls into [code]FUN_80184E40[/code] which nulls
## damage). Mirrors [code]GPUElementCancelTest[/code]'s pattern, but the cancel
## source is the target's STATUS_FLOAT bit (seeded into
## [code]status_flags_lo[/code]) rather than a pre-seeded
## [code]element_cancel_mask[/code].
##
## Layout (Manhattan):
##   Mage   (team 0, caster, Titan gambit) at (0, 0)
##   Target (team 1, STATUS_FLOAT) at (3, 0) -- in Titan range 4
##
## PASS: target HP unchanged across the cast window.
## FAIL: HP drops (Float×Earth branch didn't fire) or HP rises (absorb compose
## bug).

const ABILITY_TITAN = 64  # Earth-element damage spell (formula 8, ct=5, mp=30)
const STATUS_FLOAT_BIT = 21
const TARGET_START_HP = 200


func get_test_name() -> String:
	return "GPU Float×Earth Cancel Test (Titan vs Floating target)"


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
		"name": "FloatingKnight",
		"pos_x": 3, "pos_z": 0,
		"hp": TARGET_START_HP, "max_hp": TARGET_START_HP,
		"pa": 5, "ma": 5, "wp": 1,
		"brave": 50, "faith": 100,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x05,
		"status_flags_lo": 1 << STATUS_FLOAT_BIT,
	}]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_TITAN, GPUConstants.TARGET_NEAREST_ENEMY)]
	return []


func _ready() -> void:
	# Titan ct=5 → 100+ ticks charge + anim + slack. 1500 covers at least one
	# full resolve.
	max_ticks = 1500
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

	# Titan costs 30 MP; the mage starts at 99. Once MP drops below 99 the
	# first cast has been committed -- that's the moment the cancel fires.
	var mage_mp := int(states[0].get("mp", 99))
	if not _first_cast_seen and mage_mp < 99:
		_first_cast_seen = true
		_hp_after_first_cast = hp_now

	# Bail early on a damage event -- Float×Earth didn't fire.
	if hp_now < TARGET_START_HP:
		_print_results(states)
		return
	# Bail early on an unexpected heal.
	if hp_now > TARGET_START_HP:
		_print_results(states)
		return

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
	var flags_lo := int(states[1].get("status_flags_lo", 0))
	var mage_mp := int(states[0].get("mp", 99))

	print("\n=== FLOAT × EARTH CANCEL TEST RESULTS ===")
	print("  FloatingKnight HP: start=%d, now=%d (delta=%+d)" % [
		TARGET_START_HP, hp_now, hp_now - TARGET_START_HP])
	print("  status_flags_lo = 0x%08X (Float bit %s)" % [
		flags_lo,
		"SET" if (flags_lo & (1 << STATUS_FLOAT_BIT)) != 0 else "missing"])
	print("  mage MP = %d (cast detected: %s)" % [
		mage_mp, "yes" if _first_cast_seen else "no"])

	var preseed_ok := (flags_lo & (1 << STATUS_FLOAT_BIT)) != 0
	var hp_flat := hp_now == TARGET_START_HP
	if preseed_ok and _first_cast_seen and hp_flat:
		print("\n[PASS] Float cancelled Earth damage (HP unchanged after Titan cast)")
	else:
		var why: Array = []
		if not preseed_ok:       why.append("status_flags_lo missing Float bit (encode failed)")
		if not _first_cast_seen: why.append("no Titan cast resolved within %d ticks" % max_ticks)
		if not hp_flat:          why.append("HP changed (%+d) -- Float×Earth didn't fire" % (hp_now - TARGET_START_HP))
		print("\n[FAIL] %s" % ", ".join(why))
	print("==========================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
