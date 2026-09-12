extends GPUCombatTestBase

## GPU Regen Test
##
## Tests REGEN per-tick HP delta — second consumer of status_system.md §2
## "Per-tick HP delta" row, sharing stage_damage Phase 1.5 with POISON.
##
## REGEN routes as *negative* pending_damage so Phase 3's existing undead
## invert hurts undead-with-regen for free. The two assertions below pin
## both branches of that routing:
##
##   RegenCarrier  — REGEN seeded + timer slot, hp 100/200.
##                   Expect: HP grows by 25 (max_hp/8) at each tick that is
##                   a multiple of POISON_TICK_INTERVAL (=30), capped at
##                   max_hp = 200.
##   UndeadRegen   — UNDEAD + REGEN both seeded, hp 200/200.
##                   Expect: regen routes through pending_damage, Phase 3
##                   inverts heal↔damage on undead, HP shrinks from 200.
##
## Both checks are load-bearing: heal path (negative pending routes around
## reactions) AND undead-invert wiring (negative pending on undead damages).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const POISON_TICK_INTERVAL = 30        # shared cadence — see combat_common.glslinc
const POISON_HP_DIVISOR    = 8         # shared divisor
const REGEN_TIMER_TICKS    = 200       # outlives the test window so decay isn't observed here

var _living_hp_log: Array = []
var _undead_hp_log: Array = []
var _last_tick_logged: int = -1
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Regen Test"


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
			"name": "RegenCarrier",
			"pos_x": 0, "pos_z": 0,
			"hp": 100, "max_hp": 200,
			"status_flags_lo": (1 << StatusRegistry.bit(&"regen")),
			"status_timers": [{"bit": StatusRegistry.bit(&"regen"), "ticks": REGEN_TIMER_TICKS}],
		}),
		_merge(base, {
			"name": "UndeadRegen",
			"pos_x": 0, "pos_z": 2,
			"hp": 200, "max_hp": 200,
			"status_flags_lo": (1 << StatusRegistry.bit(&"regen")) | (1 << StatusRegistry.bit(&"undead")),
			"status_timers": [{"bit": StatusRegistry.bit(&"regen"), "ticks": REGEN_TIMER_TICKS}],
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

	_living_hp_log.append([current_tick, int(states[0].get("hp", 0))])
	_undead_hp_log.append([current_tick, int(states[1].get("hp", 0))])

	# Stop once the undead unit has died, or we've covered enough ticks to
	# see ≥3 regen ticks fire (which also caps the living carrier at max_hp).
	var undead_dead = int(states[1].get("hp", 0)) <= 0
	if undead_dead or current_tick >= 150:
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	print("\n=== REGEN TEST RESULTS ===")
	var living_start = int(_living_hp_log[0][1]) if _living_hp_log.size() > 0 else -1
	var living_end   = int(_living_hp_log[-1][1]) if _living_hp_log.size() > 0 else -1
	var undead_start = int(_undead_hp_log[0][1])   if _undead_hp_log.size()   > 0 else -1
	var undead_end   = int(_undead_hp_log[-1][1])  if _undead_hp_log.size()   > 0 else -1

	# Count discrete regen ticks observed on the living unit by scanning the
	# HP log for jumps of >= max_hp/POISON_HP_DIVISOR. Stop counting once the
	# living unit reaches max_hp (cap is what makes the rise stop).
	var expected_step = 200 / POISON_HP_DIVISOR
	var observed_heals := 0
	for i in range(1, _living_hp_log.size()):
		var prev_hp = int(_living_hp_log[i - 1][1])
		var curr_hp = int(_living_hp_log[i][1])
		if curr_hp - prev_hp >= expected_step:
			observed_heals += 1

	print("  RegenCarrier: HP %d -> %d (expected heals every %d ticks of %d, capped at 200)" % [
		living_start, living_end, POISON_TICK_INTERVAL, expected_step])
	print("  Discrete regen hits observed: %d (need >= 3)" % observed_heals)
	print("  UndeadRegen:  HP %d -> %d (expected to shrink, not grow)" % [
		undead_start, undead_end])

	var heal_ok = living_end > living_start
	var multiple_ticks_ok = observed_heals >= 3
	var heal_capped_ok = living_end <= 200
	var undead_damage_ok = undead_end < undead_start

	if heal_ok and multiple_ticks_ok and heal_capped_ok and undead_damage_ok:
		print("\n[PASS] REGEN heals living units, undead invert routes negative pending to damage")
	else:
		var why := []
		if not heal_ok:            why.append("no HP gain on RegenCarrier")
		if not multiple_ticks_ok:  why.append("fewer than 3 regen ticks observed (%d)" % observed_heals)
		if not heal_capped_ok:     why.append("RegenCarrier exceeded max_hp (%d > 200)" % living_end)
		if not undead_damage_ok:   why.append("UndeadRegen HP did not shrink (%d -> %d)" % [undead_start, undead_end])
		print("\n[FAIL] %s" % ", ".join(why))
	print("==========================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		_print_results()


static func _merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var result = base.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result
