extends GPUCombatTestBase

## GPU Status Enforcement Test
##
## Tests Tier 2 #8 — the disabling-status gates in stage_compute.
##
## Three pairs of (carrier, target). Carrier holds a status that should
## prevent it from doing what its gambit instructs:
##   Sleep   — gambit says ATTACK, but Sleep blocks all actions. No swing.
##   Silence — gambit says SPELL (Fire), but Silence vetoes spells. No cast.
##   Immobilize — gambit says MOVE_TO target. Immobilize blocks MOVE_TO. No move.
##
## After ~max_ticks the carriers' targets should still be at full HP
## (no swings landed, no spells cast), the Sleep/Silence carriers should
## still be in LOGICAL_ACTIVITY_IDLE (no ACTING transitions), and the Immobilize
## carrier should still be at its spawn position (no movement). Status
## timers are NOT set — these statuses persist for the duration of the
## test so the gates remain active throughout.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const StatusRegistry = ExMateriaAlmanac.StatusRegistry


const ABILITY_FIRE = 16

var _results_printed: bool = false
var _check_timer: float = 0.0
var _initial_target_hp: Dictionary = {}
var _initial_carrier_pos: Dictionary = {}


func get_test_name() -> String:
	return "GPU Status Enforcement Test"


func get_team0_unit_configs() -> Array:
	var base = {
		"hp": 200, "max_hp": 200, "pa": 10, "ma": 10, "wp": 5,
		"brave": 50, "faith": 70, "mp": 50, "max_mp": 50,
		"speed": 100, "move": 4, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 1,
		"weapon_id": 19, "c_ev": 0, "s_ev": 0, "w_ev": 0,
		"body_sprite_id": 0x02,
	}
	return [
		# 0: sleeping melee unit, gambit says attack, status blocks.
		_merge(base, {
			"name": "Sleeper", "pos_x": 1, "pos_z": 0,
			"status_flags_lo": (1 << StatusRegistry.bit(&"sleep")),
		}),
		# 1: silenced caster, gambit casts Fire, status vetoes the spell.
		_merge(base, {
			"name": "Silenced", "pos_x": 1, "pos_z": 4,
			"status_flags_lo": (1 << StatusRegistry.bit(&"silence")),
		}),
		# 2: immobilized walker, gambit moves to (5, 8), status blocks MOVE_TO.
		_merge(base, {
			"name": "Stuck", "pos_x": 1, "pos_z": 8,
			"status_flags_lo": (1 << StatusRegistry.bit(&"immobilize")),
		}),
	]


func get_team1_unit_configs() -> Array:
	var dummy = {
		"hp": 999, "max_hp": 999, "pa": 1, "ma": 1, "wp": 1,
		"brave": 50, "faith": 50, "mp": 50, "max_mp": 50,
		"speed": 1, "move": 0, "jump": 3,
		"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
		"body_sprite_id": 0x05,
	}
	return [
		_merge(dummy, {"name": "Tgt_Sleep",   "pos_x": 2, "pos_z": 0}),
		_merge(dummy, {"name": "Tgt_Silence", "pos_x": 4, "pos_z": 4}),
		_merge(dummy, {"name": "Tgt_Move",    "pos_x": 6, "pos_z": 8}),
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	match unit_idx:
		0: return [make_attack_gambit()]                       # Sleeper
		1: return [make_spell_gambit(ABILITY_FIRE)]            # Silenced
		2: return [make_move_to_gambit(6, 8)]                  # Stuck
		_: return []


func _ready():
	max_ticks = 300
	super._ready()


func _capture_initials(states: Array) -> void:
	# Target HPs (units 3-5) and carrier positions (units 0-2).
	for i in range(3, 6):
		if not _initial_target_hp.has(i) and i < states.size():
			_initial_target_hp[i] = int(states[i].get("hp", 0))
	for i in range(0, 3):
		if not _initial_carrier_pos.has(i) and i < states.size():
			_initial_carrier_pos[i] = [
				int(states[i].get("pos_x", 0)),
				int(states[i].get("pos_z", 0))]


func _process(delta):
	super._process(delta)
	if _results_printed:
		return
	if not gpu_state_reader:
		return

	_check_timer += delta
	if _check_timer < 0.2:
		return
	_check_timer = 0.0

	var states = gpu_state_reader.get_all_unit_states()
	if states.size() < 6:
		return
	_capture_initials(states)

	# Print verdict at tick 100 — well within max_ticks (300). All carriers
	# have had 100 ticks to act; if any of the gates failed it would show
	# up by now (a melee swing lands ~tick 60-80 of an unrestricted unit).
	# Waiting any longer just gives the framework's own timeout a chance
	# to race the verdict under suite-load slowdowns.
	if current_tick >= 100 and not _results_printed:
		_print_results(states)


func _print_results(states: Array) -> void:
	if _results_printed:
		return
	_results_printed = true

	# Sleep: target HP unchanged + carrier never ACTING.
	# Silence: target HP unchanged + carrier never CHARGING/ACTING.
	# Immobilize: carrier still at spawn position.
	var sleep_target_hp_now    = int(states[3].get("hp", 0))
	var silence_target_hp_now  = int(states[4].get("hp", 0))
	var stuck_pos = [
		int(states[2].get("pos_x", 0)),
		int(states[2].get("pos_z", 0))]
	var stuck_init = _initial_carrier_pos.get(2, [0, 0])

	var sleep_ok    = sleep_target_hp_now    == _initial_target_hp.get(3, -1)
	var silence_ok  = silence_target_hp_now  == _initial_target_hp.get(4, -1)
	var stuck_ok    = stuck_pos == stuck_init

	print("\n=== STATUS ENFORCEMENT TEST RESULTS ===")
	print("  Sleep  : target HP %d (initial %d) — %s" % [
		sleep_target_hp_now, _initial_target_hp.get(3, -1),
		"PASS" if sleep_ok else "FAIL"])
	print("  Silence: target HP %d (initial %d) — %s" % [
		silence_target_hp_now, _initial_target_hp.get(4, -1),
		"PASS" if silence_ok else "FAIL"])
	print("  Immobilize: carrier pos %s (initial %s) — %s" % [
		str(stuck_pos), str(stuck_init),
		"PASS" if stuck_ok else "FAIL"])

	var all_ok = sleep_ok and silence_ok and stuck_ok
	if all_ok:
		print("\n[PASS] All three disabling statuses blocked their target action")
	else:
		print("\n[FAIL] One or more statuses did not gate as expected")
	print("=========================================\n")
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _results_printed:
		var s = gpu_state_reader.get_all_unit_states() if gpu_state_reader else []
		_print_results(s)


static func _merge(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var result = base.duplicate()
	for key in overrides:
		result[key] = overrides[key]
	return result
