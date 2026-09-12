class_name GambitTraceLogger
extends RefCounted

## Queryable per-scenario trace. Subscribes to the existing [CombatLoop] signal
## surface (state_changed / cast_began / unit_died / projectile_fired /
## hp_changed / victory) and to per-tick snapshots of [code]U_CURRENT_GAMBIT[/code]
## and [code]U_DECISION_HIST_*[/code], assembling them into a single object the
## [GambitAssertions] predicate library reads from. Extends the existing
## [RegressionLogger] format (one parseable line per event); the queryable
## structured side is what scenario predicates consume.
##
## No new shader-side seams, no new CombatLoop signals introduced (per #57).

var test_name: String
var _rlog: RegressionLogger

# Unit-name → global unit index (the runner builds this from the scenario's
# units block). Predicates address units by name; the trace stores by index.
var _unit_name_to_idx: Dictionary = {}
var _unit_idx_to_name: Dictionary = {}

# Per-event structured records (predicates read these directly).
var state_events: Array = []         # {tick, unit, prev, new, current_gambit}
var cast_events: Array = []          # {tick, unit, ability_id, target, current_gambit, cooldown_ready_at}
# Discrete action-commit witness independent of host-frame STATE_CHANGED sampling
# (#93). Fires on every cast_step_id bump — pure attacks (ability_id = -1) AND
# abilities — so predicates counting fallback-slot commits don't get fooled by
# ACTING → IDLE → ACTING blinks that coalesce away across host-frame boundaries.
var action_committed_events: Array = []  # {tick, unit, ability_id, target, current_gambit}
var projectile_events: Array = []    # {tick, unit, current_gambit}
var death_events: Array = []         # {tick, unit}
var hp_events: Array = []            # {tick, unit, prev, new, delta}
# Per-tick snapshot of per-unit state — populated by snapshot_tick(); the
# liveness predicates walk this to detect idle runs and gambit-slot commits.
var per_tick_snapshots: Array = []   # [{tick, units:[{state, pos, current_gambit, hp}]}]

# Final outcome — set when victory/timed_out fires.
var winner: int = -2                 # -2 = unresolved, -1 = draw, 0/1 = team
var final_tick: int = 0
var timed_out: bool = false

# Baseline counters for the NORAN sentinel.
var gambit_eval_events: int = 0      # ≥1 = sim actually evaluated gambits

# Per-unit "first commit" record: tick at which a unit first entered a
# committed (ACTING / SPELL_CHARGING) state, and which gambit slot drove it.
var first_commit: Dictionary = {}    # unit_idx → {tick, slot, state}


func _init(p_test_name: String = "", p_rlog: RegressionLogger = null) -> void:
	test_name = p_test_name
	_rlog = p_rlog


## Bind unit names. The runner builds this from the scenario's units block; the
## assertions look up units by name and the trace stores indices.
func bind_units(unit_names: Array) -> void:
	_unit_name_to_idx.clear()
	_unit_idx_to_name.clear()
	for i in range(unit_names.size()):
		_unit_name_to_idx[unit_names[i]] = i
		_unit_idx_to_name[i] = unit_names[i]


func unit_index(unit_name: String) -> int:
	return _unit_name_to_idx.get(unit_name, -1)


func unit_name(unit_idx: int) -> String:
	return _unit_idx_to_name.get(unit_idx, "Unit%d" % unit_idx)


# === Signal handlers (CombatLoop) =============================================

func on_state_changed(unit_idx: int, prev_state: int, new_state: int, tick: int, current_gambit: int) -> void:
	state_events.append({
		"tick": tick,
		"unit": unit_idx,
		"prev": prev_state,
		"new": new_state,
		"current_gambit": current_gambit,
	})
	# Decision-history transitions are surrogate gambit-eval events for the
	# NORAN baseline: a unit entering an acting state or ANY move state got there
	# from a gambit evaluation that fired. The move half is asked, not listed, so
	# a new move state counts from the row that declares it.
	if new_state in [GPUConstants.LOGICAL_ACTIVITY_ACTING,
			GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING] \
			or GPUConstants.is_movement_state(new_state):
		gambit_eval_events += 1
	# Record first commit: the first time this unit enters ACTING (or
	# SPELL_CHARGING) we treat as a gambit having committed an action.
	if not first_commit.has(unit_idx) and new_state in [
			GPUConstants.LOGICAL_ACTIVITY_ACTING,
			GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING]:
		first_commit[unit_idx] = {
			"tick": tick,
			"slot": current_gambit,
			"state": new_state,
		}


func on_cast_began(unit_idx: int, ability_id: int, target: int, tick: int, current_gambit: int, cooldown_ready_at: int = -1) -> void:
	cast_events.append({
		"tick": tick,
		"unit": unit_idx,
		"ability_id": ability_id,
		"target": target,
		"current_gambit": current_gambit,
		# `cooldown_ready_at` captured from the GPU SSBO at cast-emission time.
		# = commit_gpu_tick + cooldown_ticks. Subtracting cooldown_ticks recovers
		# the actual GPU tick of the commit, which can lag `tick` (the host's
		# end-of-frame snapshot) by up to (frame_size - 1) GPU ticks at
		# Engine.time_scale > 1. -1 means uninstrumented (no GPU read).
		"cooldown_ready_at": cooldown_ready_at,
	})


func on_action_committed(unit_idx: int, ability_id: int, target: int, tick: int, current_gambit: int) -> void:
	action_committed_events.append({
		"tick": tick,
		"unit": unit_idx,
		"ability_id": ability_id,
		"target": target,
		"current_gambit": current_gambit,
	})


func on_projectile_fired(unit_idx: int, tick: int, current_gambit: int) -> void:
	projectile_events.append({
		"tick": tick,
		"unit": unit_idx,
		"current_gambit": current_gambit,
	})


func on_unit_died(unit_idx: int, tick: int) -> void:
	death_events.append({"tick": tick, "unit": unit_idx})


func on_hp_changed(unit_idx: int, prev: int, new_hp: int, delta: int, tick: int) -> void:
	hp_events.append({
		"tick": tick,
		"unit": unit_idx,
		"prev": prev,
		"new": new_hp,
		"delta": delta,
	})


func on_victory(winning_team: int, tick: int) -> void:
	winner = winning_team
	final_tick = tick


func on_timed_out(tick: int) -> void:
	timed_out = true
	final_tick = tick


## Sample the per-unit snapshot once per tick. The runner calls this from the
## host process loop after [code]combat_loop.tick(delta)[/code]; it's a cheap
## dict-copy off the already-read [code]_all_states[/code] snapshot.
##
## [code]target[/code] / [code]status_flags_lo[/code] / [code]status_flags_hi[/code]
## are surfaced so the B-group predicates can verify status bits stayed on the
## unit (B4 silence, B5 immobilize) and which enemy a unit currently has
## resolved as its action target (B7 pass-2 rank pivot).
##
## I/J-group additions: [code]paused[/code] + the AoE-pending stamp fields
## ([code]aoe_pending_caster[/code], [code]aoe_pending_fire_frame[/code],
## [code]aoe_center_x/z[/code], [code]aoe_ability_id[/code]) come from the same
## per-unit GPU buffer the existing fields do — [GPUBatchSimulator]'s
## [code]SNAPSHOT_FIELDS[/code] already exposes them. Issue #118 retired the
## battle-header cinematic pair; the per-unit [code]cinematic_timer[/code] now
## carries the state, and [code]cinematic_caster_idx[/code] on the snapshot is
## derived as "lowest unit_id with cinematic_timer >= 0" so the J-group
## predicates can keep their existing reads.
func snapshot_tick(tick: int, all_states: Array, _battle_state: Dictionary = {}) -> void:
	var units_snap: Array = []
	var spotlight_caster: int = -1
	for i in range(all_states.size()):
		var s: Dictionary = all_states[i]
		# decision_meta packs the thrash diagnostic ring-buffer state — bit 3 is
		# thrash_flag (set when check_decision_thrash sees a stuck-target or
		# repeat-decision pattern across the 6-entry history), [7:4] is the
		# cumulative thrash_count. The G7 / H6 no_thrash predicate reads this.
		var meta: int = s.get("decision_meta", 0)
		var cin_timer: int = int(s.get("cinematic_timer", -1))
		if spotlight_caster < 0 and cin_timer >= 0:
			spotlight_caster = i
		units_snap.append({
			"state": s.get("state", 0),
			"pos_x": s.get("pos_x", 0),
			"pos_z": s.get("pos_z", 0),
			"current_gambit": s.get("current_gambit", -1),
			"hp": s.get("hp", 0),
			"flags": s.get("flags", 0),
			"target": s.get("target", -1),
			"status_flags_lo": s.get("status_flags_lo", 0),
			"status_flags_hi": s.get("status_flags_hi", 0),
			"paused": s.get("paused", 0),
			"aoe_pending_caster": s.get("aoe_pending_caster", -1),
			"aoe_pending_fire_frame": s.get("aoe_pending_fire_frame", -1),
			"aoe_center_x": s.get("aoe_center_x", -1),
			"aoe_center_z": s.get("aoe_center_z", -1),
			"aoe_ability_id": s.get("aoe_ability_id", -1),
			"cinematic_timer": cin_timer,
			"decision_meta": meta,
			"thrash_flag": (meta >> 3) & 0x1,
		})
	per_tick_snapshots.append({
		"tick": tick,
		"units": units_snap,
		"cinematic_caster_idx": spotlight_caster,
	})


# === Queries used by GambitAssertions ========================================

func all_unit_names() -> Array:
	return _unit_idx_to_name.values()


func enemies_of(unit_idx: int) -> Array:
	# Caller supplies the team mapping — we don't track teams in the trace
	# itself. Predicate library threads team info from the runner.
	return []


func count_alive_enemies(target_idx: int, team_of: Dictionary, snapshot: Dictionary) -> int:
	var alive: int = 0
	var team: int = int(team_of.get(target_idx, 0))
	var units_snap: Array = snapshot["units"]
	for i in range(units_snap.size()):
		if i == target_idx:
			continue
		if int(team_of.get(i, 0)) == team:
			continue
		var u: Dictionary = units_snap[i]
		if (int(u["flags"]) & CombatHost.GPU_FLAGS_DEAD_BIT) == 0:
			alive += 1
	return alive
