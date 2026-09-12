extends GPUCombatTestBase

## GPU Status Cancel Tracer (#100)
##
## End-to-end witness for the [code]inflict_mode == "cancel"[/code] path: a
## preseeded poison flag + decay-timer slot, an Antidote item-cast on self,
## and the assertion that BOTH the bit and the timer slot zero out after the
## cast lands.
##
## Pairs with [code]GPUStatusInflictTest[/code] (the ALL-mode witness). Once
## green, every other cancel-mode ability/item lights up on the same code
## path: Esuna (14), Stigma Magic (100), Heal (156), Eye Drop (375), Echo
## Grass (376), Maiden's Kiss (377), Soft (378), Holy Water (379), Remedy
## (380), Phoenix Down (381 — Dead bit). Item-side dispatch goes through
## start_spell -> cast_instant_spell -> apply_break_effect (formula 56) ->
## apply_inflict_all with mode=CANCEL.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const ABILITY_ANTIDOTE = 374
const POISON_TIMER_TICKS = 600  # long enough that natural decay can't beat the cleanse

var _start_flags_lo: int = 0
var _start_timer_slot0: int = 0
var _cleansed_tick: int = -1
var _cleansed_flags_lo: int = -1
var _cleansed_timer_slot0: int = -1
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Status Cancel Test (Antidote -> Poison)"


func get_team0_unit_configs() -> Array:
	# Chemist: preseeded with POISON + a long decay timer in slot 0, casts
	# Antidote on self. Antidote uses formula 56 (status-only, 100% hit) with
	# inflict_mode "cancel" on Poison; the shader should clear both the bit
	# and the timer slot in the same tick the cast resolves.
	var poison_bit := StatusRegistry.bit(&"poison")
	return [
		{
			"name": "Chemist",
			"pos_x": 0, "pos_z": 0,
			"hp": 200, "max_hp": 200,
			"pa": 5, "ma": 5, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 50, "max_mp": 50,
			"speed": 100, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x02,
			"status_flags_lo": (1 << poison_bit),
			"status_timers": [{"bit": poison_bit, "ticks": POISON_TIMER_TICKS}],
		},
	]


func get_team1_unit_configs() -> Array:
	# Inert enemy. Stands far enough away that it never engages -- it exists
	# only to keep the battle live until the cancel slice resolves.
	return [
		{
			"name": "Dummy",
			"pos_x": 8, "pos_z": 8,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	if unit_idx == 0:
		return [make_item_gambit(ABILITY_ANTIDOTE, GPUConstants.TARGET_SELF)]
	return []


func _ready() -> void:
	# Item-cast on self is ~instant (no charge_time, no projectile). 600 ticks
	# of slack covers gambit-eval cadence + item animation. Well under the
	# preseeded poison timer so a natural-decay false positive is impossible.
	max_ticks = 600
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 1:
		return

	var poison_bit_mask := 1 << StatusRegistry.bit(&"poison")
	var flags_lo := int(states[0].get("status_flags_lo", 0))
	var timer_slot0 := int(states[0].get("status_timer_0", 0))

	if _start_flags_lo == 0:
		_start_flags_lo = flags_lo
		_start_timer_slot0 = timer_slot0

	# Cleanse witness: poison bit drops AND timer slot 0 zeroes. We track the
	# first tick that both conditions are met -- the shader does them in the
	# same write, so a one-tick lag is normal but they should never diverge.
	var poison_cleared := (flags_lo & poison_bit_mask) == 0
	var timer_freed := timer_slot0 == 0

	if poison_cleared and timer_freed and _cleansed_tick < 0:
		_cleansed_tick = current_tick
		_cleansed_flags_lo = flags_lo
		_cleansed_timer_slot0 = timer_slot0
		_print_results(states)
		return

	if current_tick >= max_ticks - 1:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	var poison_bit_mask := 1 << StatusRegistry.bit(&"poison")
	var flags_lo := int(states[0].get("status_flags_lo", 0))
	var timer_slot0 := int(states[0].get("status_timer_0", 0))
	var hp_now := int(states[0].get("hp", 0))

	print("\n=== STATUS CANCEL TEST RESULTS ===")
	print("  start: status_flags_lo = 0x%08X (poison bit %s), timer_slot_0 = 0x%08X" % [
		_start_flags_lo,
		"SET" if (_start_flags_lo & poison_bit_mask) != 0 else "missing",
		_start_timer_slot0])
	print("  now:   status_flags_lo = 0x%08X (poison bit %s), timer_slot_0 = 0x%08X" % [
		flags_lo,
		"SET" if (flags_lo & poison_bit_mask) != 0 else "cleared",
		timer_slot0])
	print("  Chemist HP %d / 200 (poison ticks should stop after cleanse)" % hp_now)
	print("  cleanse tick: %d" % _cleansed_tick)

	var preseed_ok := (_start_flags_lo & poison_bit_mask) != 0 and _start_timer_slot0 != 0
	var bit_ok := (flags_lo & poison_bit_mask) == 0
	var slot_ok := timer_slot0 == 0
	var cleansed_in_time := _cleansed_tick >= 0

	if preseed_ok and bit_ok and slot_ok and cleansed_in_time:
		print("\n[PASS] Antidote cleared POISON bit + freed timer slot 0")
	else:
		var why: Array = []
		if not preseed_ok:        why.append("preseed missing (flags=0x%08X, slot=0x%08X)" % [_start_flags_lo, _start_timer_slot0])
		if not bit_ok:            why.append("POISON bit still set (flags_lo=0x%08X)" % flags_lo)
		if not slot_ok:           why.append("timer slot 0 still occupied (0x%08X)" % timer_slot0)
		if not cleansed_in_time:  why.append("Antidote never cleared poison within %d ticks" % max_ticks)
		print("\n[FAIL] %s" % ", ".join(why))
	print("===================================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)
