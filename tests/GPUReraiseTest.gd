extends GPUCombatTestBase

## GPU Reraise Test
##
## Tests RERAISE re-targeting -- status_system.md S2 "Re-targeting" row, with
## the issue #107 two-stage split: Stage A in stage_damage.glsl flips the
## carrier to FLAG_DEAD + HP=0 + leaves STATUS_RERAISE set + stamps a
## RERAISE_REVIVE_DELAY_TICKS deadline into U_TIMER; Stage B in stage_spell.glsl
## opens a self-targeted E007 cinematic once the deadline elapses, restores HP
## at the effect's first_hit_frame, and tears down at total_frames (the same
## beat that finally drops the STATUS_RERAISE bit + its timer slot).
##
## A normal melee attacker (PA*WP = lethal) swings a defender holding RERAISE.
## First lethal hit triggers Stage A (CPU plays the dying anim through the
## delay window), then Stage B reviv es and the second lethal kills normally.
##
## The defender is otherwise harmless (PA*WP = 1) so it can't fluke a kill on
## the attacker mid-test; the attacker carries enough HP to absorb a counter
## without dying.
##
## Detection: per-tick log of (hp, status_flags_lo, flags). When the defender
## reaches the FINAL death (FLAG_DEAD set AND STATUS_RERAISE bit cleared --
## the "Reraise has been consumed" predicate) we replay the log to identify
## the consume frame (the first tick where the RERAISE bit cleared) and
## check the HP was at the revive amount. Stage A's transient FLAG_DEAD does
## NOT count -- the bit is still set there.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const RERAISE_HP_DIVISOR = 10           # must match combat_common.glslinc

var _defender_log: Array = []
var _last_tick_logged: int = -1
var _results_printed: bool = false


func get_test_name() -> String:
	return "GPU Reraise Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Attacker", "pos_x": 1, "pos_z": 0,
			"hp": 400, "max_hp": 400, "pa": 20, "ma": 5, "wp": 10,
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
			"name": "ReraiseCarrier", "pos_x": 2, "pos_z": 0,
			"hp": 100, "max_hp": 200, "pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50, "mp": 0, "max_mp": 0,
			"speed": 1, "move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
			"c_ev": 0, "s_ev": 0, "w_ev": 0,
			"body_sprite_id": 0x05,
			# RERAISE and NO countdown: the ROM gives it none (#1116 — it is not
			# one of the sixteen statuses with a slot at unit+0x5D), so it lasts
			# until it fires. The seeded timer this fixture used to carry was inert
			# even before that — a dead unit's compute step early-returns before
			# `tick_status_timers` — and the packer now refuses a duration for an
			# unslotted status rather than writing it somewhere it does not belong.
			"status_flags_lo": (1 << StatusRegistry.bit(&"reraise")),
		},
	]


func get_gambits_for_unit(_unit_idx: int, team: int) -> Array:
	return [make_attack_gambit()] if team == 0 else []


func _ready() -> void:
	# The two-stage revive eats a long fixed window before the second lethal
	# can land: RERAISE_REVIVE_DELAY_TICKS (~90) of visible dying + the E007
	# cinematic (~721 frames) + the attacker's resumed swing animation
	# (~30-60 ticks). 1500 covers both lethal hits with margin.
	max_ticks = 1500
	test_time_scale = 1.0
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if _results_printed or not gpu_state_reader:
		return

	if current_tick == _last_tick_logged:
		return
	_last_tick_logged = current_tick

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 2:
		return

	var def = states[1]
	# CPU-side state (#108) — combat_loop.tick() has already run for this
	# frame (CombatHost._process → super._process before our _process body),
	# so unit_stats.is_dead / activity reflect this tick's _handle_revives.
	var def_unit = units[1] if units.size() > 1 else null
	var cpu_is_dead: bool = def_unit.unit_stats.is_dead if def_unit and def_unit.unit_stats else false
	var cpu_activity_id: int = int(def_unit.activity) if def_unit else -1
	_defender_log.append({
		"tick": current_tick,
		"hp": int(def.get("hp", 0)),
		"flags": int(def.get("flags", 0)),
		"status_lo": int(def.get("status_flags_lo", 0)),
		"cpu_is_dead": cpu_is_dead,
		"cpu_activity": cpu_activity_id,
	})

	# Final death: FLAG_DEAD set AND RERAISE bit cleared. The transient
	# Stage A FLAG_DEAD (with the bit still set) is part of the visible
	# dying-anim window and does NOT terminate the test. GPUStateReader
	# exposes the bitmask as `status_flags_lo` -- mirror the same key our
	# log copy uses above.
	var reraise_mask := 1 << StatusRegistry.bit(&"reraise")
	if (int(def.get("flags", 0)) & 1) != 0 \
			and (int(def.get("status_flags_lo", 0)) & reraise_mask) == 0:
		_print_results()


func _print_results() -> void:
	if _results_printed:
		return
	_results_printed = true

	# Expected revive HP for max_hp=200: 200/10 = 20.
	var expected_revive_hp = 200 / RERAISE_HP_DIVISOR
	var reraise_bit = StatusRegistry.bit(&"reraise")
	var reraise_mask = 1 << reraise_bit

	# Find the consume frame: the first tick where the bit clears. The
	# Phase 3 hook clears the bit + sets HP=max_hp/N in the same tick, so
	# the row at the consume frame is the load-bearing observation.
	var consume_idx := -1
	for i in range(_defender_log.size()):
		if (_defender_log[i]["status_lo"] & reraise_mask) == 0:
			consume_idx = i
			break

	var consume_hp = -1
	var initial_hp = int(_defender_log[0]["hp"]) if _defender_log.size() > 0 else -1
	if consume_idx >= 0:
		consume_hp = int(_defender_log[consume_idx]["hp"])

	var died = _defender_log.size() > 0 and (int(_defender_log[-1]["flags"]) & 1) != 0
	var final_hp = int(_defender_log[-1]["hp"]) if _defender_log.size() > 0 else -1

	# #108 CPU-side revive: at the consume frame the CombatLoop's per-tick
	# _handle_revives must have flipped unit_stats.is_dead back to false.
	# Activity at consume should already be IDLE — the rise pose plays
	# mid-cinematic off the CPU HIT_REACT keyframe (GPURiseTimingTest
	# covers that timing), so the GETTING_UP SEQ has long since completed
	# into IDLE by the time the GPU clears FLAG_DEAD here.
	var cpu_alive_ok = false
	var cpu_activity_ok = false
	var cpu_is_dead_at_consume = true
	var cpu_activity_at_consume = -1
	if consume_idx >= 0:
		cpu_is_dead_at_consume = bool(_defender_log[consume_idx].get("cpu_is_dead", true))
		cpu_activity_at_consume = int(_defender_log[consume_idx].get("cpu_activity", -1))
		cpu_alive_ok = not cpu_is_dead_at_consume
		cpu_activity_ok = cpu_activity_at_consume == DisplayActivity.Activity.IDLE

	print("\n=== RERAISE TEST RESULTS ===")
	print("  Defender initial HP: %d (max 200)" % initial_hp)
	print("  Consume frame: tick=%d HP=%d (expected HP=%d, bit cleared)" % [
		(int(_defender_log[consume_idx]["tick"]) if consume_idx >= 0 else -1),
		consume_hp, expected_revive_hp])
	print("  CPU at consume: is_dead=%s activity=%s (expected false / IDLE)" % [
		str(cpu_is_dead_at_consume),
		DisplayActivity.Activity.keys()[cpu_activity_at_consume] if cpu_activity_at_consume >= 0 and cpu_activity_at_consume < DisplayActivity.Activity.keys().size() else str(cpu_activity_at_consume)])
	print("  Final HP / dead-flag: %d / %s (expected 0 / true)" % [final_hp, str(died)])

	var bit_cleared_ok = consume_idx >= 0
	var revive_ok = consume_hp == expected_revive_hp
	var killed_ok = died and final_hp == 0

	if bit_cleared_ok and revive_ok and killed_ok and cpu_alive_ok and cpu_activity_ok:
		print("[PASS] RERAISE consumed first lethal hit (HP -> %d, bit cleared, CPU IDLE); second lethal killed" % expected_revive_hp)
	else:
		var why := []
		if not bit_cleared_ok:   why.append("RERAISE bit never cleared")
		if not revive_ok:        why.append("revive HP %d != %d" % [consume_hp, expected_revive_hp])
		if not cpu_alive_ok:     why.append("CPU unit_stats.is_dead still true at consume frame")
		if not cpu_activity_ok:  why.append("CPU activity %d != IDLE at consume frame" % cpu_activity_at_consume)
		if not killed_ok:        why.append("second lethal hit did not kill (hp=%d dead=%s)" % [final_hp, str(died)])
		print("[FAIL] %s" % ", ".join(why))
	print("============================\n")
	get_tree().quit()


func on_victory(_winning_team: int) -> void:
	if not _results_printed:
		_print_results()
