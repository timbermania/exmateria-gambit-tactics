extends GPUCombatTestBase

## GPU Poison Test
##
## Tests POISON per-tick HP delta — the first per-status combat semantic to
## use the StatusRegistry plug-in convention (status_system.md §2 "Per-tick HP
## delta" row → stage_damage Phase 1.5).
##
## Two units share team 0 with no enemies in attack range:
##   PoisonedKnight — POISON seeded + timer slot, max_hp 200.
##                    Expect: HP drops by 25 (max_hp/8) at each tick that is
##                    a multiple of POISON_TICK_INTERVAL (=30), until timer
##                    expires.
##   UndeadCarrier  — UNDEAD + POISON both seeded, max_hp 200, HP 100.
##                    Expect: poison routes through pending_damage, Phase 3
##                    flips heal↔damage on undead, HP grows toward max_hp.
##
## Both checks are load-bearing: damage path AND undead-invert wiring.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const POISON_TICK_INTERVAL = 30        # must match combat_common.glslinc
const POISON_HP_DIVISOR    = 8         # must match combat_common.glslinc
const POISON_TIMER_TICKS   = 200       # outlives test window so decay isn't observed here

var _poisoned_hp_log: Array = []
var _undead_hp_log: Array = []
var _last_tick_logged: int = -1
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Poison Test"


func get_team0_unit_configs() -> Array:
	var base := {
		"pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50,
		"mp": 0, "max_mp": 0,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x06,
	}
	return [
		_merge(base, {
			"name": "PoisonedKnight",
			"pos_x": 0, "pos_z": 0,
			"hp": 200, "max_hp": 200,
			"status_flags_lo": (1 << StatusRegistry.bit(&"poison")),
			"status_timers": [{"bit": StatusRegistry.bit(&"poison"), "ticks": POISON_TIMER_TICKS}],
		}),
		_merge(base, {
			"name": "UndeadCarrier",
			"pos_x": 0, "pos_z": 2,
			"hp": 100, "max_hp": 200,
			"status_flags_lo": (1 << StatusRegistry.bit(&"poison")) | (1 << StatusRegistry.bit(&"undead")),
			"status_timers": [{"bit": StatusRegistry.bit(&"poison"), "ticks": POISON_TIMER_TICKS}],
		}),
	]


func get_team1_unit_configs() -> Array:
	# Stub enemy parked far away so the suite has a team-1 to satisfy the
	# battle setup invariants. No gambits, no swing range.
	return [
		{
			"name": "Dummy",
			"pos_x": 8, "pos_z": 8,
			"hp": 999, "max_hp": 999,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"body_sprite_id": 0x05,
		},
	]


func get_gambits_for_unit(_unit_idx: int, _team: int) -> Array:
	return []


func _ready() -> void:
	max_ticks = 200
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	# Log HP once per tick so we don't double-count between polls.
	if current_tick == _last_tick_logged:
		return
	_last_tick_logged = current_tick

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	_poisoned_hp_log.append([current_tick, int(states[0].get("hp", 0))])
	_undead_hp_log.append([current_tick, int(states[1].get("hp", 0))])

	# Stop once the poisoned unit has died, or we've covered enough ticks to
	# see ≥3 poison ticks fire.
	var poisoned_dead = int(states[0].get("hp", 0)) <= 0
	if poisoned_dead or current_tick >= 150:
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	print("\n=== POISON TEST RESULTS ===")
	var poisoned_start = int(_poisoned_hp_log[0][1]) if _poisoned_hp_log.size() > 0 else -1
	var poisoned_end   = int(_poisoned_hp_log[-1][1]) if _poisoned_hp_log.size() > 0 else -1
	var undead_start   = int(_undead_hp_log[0][1])   if _undead_hp_log.size()   > 0 else -1
	var undead_end     = int(_undead_hp_log[-1][1])  if _undead_hp_log.size()   > 0 else -1

	# Count discrete poison ticks observed on the alive unit by scanning the
	# HP log for drops of >= max_hp/POISON_HP_DIVISOR.
	var expected_step = 200 / POISON_HP_DIVISOR
	var observed_drops := 0
	for i in range(1, _poisoned_hp_log.size()):
		var prev_hp = int(_poisoned_hp_log[i - 1][1])
		var curr_hp = int(_poisoned_hp_log[i][1])
		if prev_hp - curr_hp >= expected_step:
			observed_drops += 1

	print("  PoisonedKnight: HP %d -> %d (expected drops every %d ticks of %d)" % [
		poisoned_start, poisoned_end, POISON_TICK_INTERVAL, expected_step])
	print("  Discrete poison hits observed: %d (need >= 3)" % observed_drops)
	print("  UndeadCarrier:  HP %d -> %d (expected to grow, not shrink)" % [
		undead_start, undead_end])

	var damage_ok = poisoned_end < poisoned_start
	var multiple_ticks_ok = observed_drops >= 3
	var undead_heal_ok = undead_end > undead_start

	if damage_ok and multiple_ticks_ok and undead_heal_ok:
		print("\n[PASS] POISON damages live units, undead invert routes through pending_damage")
	else:
		var why := []
		if not damage_ok:        why.append("no HP loss on PoisonedKnight")
		if not multiple_ticks_ok: why.append("fewer than 3 poison ticks observed (%d)" % observed_drops)
		if not undead_heal_ok:   why.append("UndeadCarrier HP did not grow (%d -> %d)" % [undead_start, undead_end])
		print("\n[FAIL] %s" % ", ".join(why))
	print("===========================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		_print_results()


static func _merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var result = base.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result
