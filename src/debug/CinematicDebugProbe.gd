class_name CinematicDebugProbe extends RefCounted

## Debug-only instrumentation for cinematic-spell pause/freeze diagnosis.
##
## Owns the per-tick paired CPU/GPU freeze detector, the third-unit spotlight,
## the periodic cinematic summary, the cinematic-ended watchdog, and the
## began/ended per-unit pause snapshot dumps. All logging is conditioned on
## DebugConfig.iteration_debug_enabled at the call site (CombatLoop), so the
## probe itself doesn't re-gate.
##
## CombatLoop constructs this lazily — only when iteration_debug_enabled is
## true — and otherwise carries a null reference, keeping production overhead
## at zero.
##
## Read-only against battle_state / all_states / units; never writes anything.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

const GPU_FLAGS_DEAD_BIT: int = 1

# Periodic in-cinematic summary.
var _cinematic_summary_due_tick: int = -1

# Post-cinematic-ended watchdog window.
var _cinematic_watchdog_until_tick: int = -1
var _cinematic_watchdog_post_end_tick: int = -1
# Per-unit pose at cinematic-ended:
#   {idx -> {state, timer, ability_id, react_active, state_changed_at}}
var _cinematic_watchdog_unit_snapshot: Dictionary = {}

# Paired CPU+GPU freeze counts (per-tick edge detection — log on count change).
var _freeze_prev_gpu_paused: int = -1
var _freeze_prev_cpu_zero_speed: int = -1
var _freeze_prev_combat_visuals_disabled: bool = false

# Spotlight: a non-caster, non-target unit we watch tick-by-tick.
var _spotlight_idx: int = -1
var _spotlight_prev_anim_frame: int = -1
var _spotlight_prev_state: int = -1
var _spotlight_prev_t1_paused: bool = false
var _spotlight_last_anim_change_tick: int = 0


## Per-tick entry point. Called from CombatLoop.tick() when iteration_debug_enabled.
##
## anim_speed_fn: Callable(unit_idx: int) -> int — returns the CPU's view of the
## unit's animation speed multiplier this tick (CombatLoop._get_unit_anim_speed).
func probe(battle_state: Dictionary, all_states: Array, units: Array,
		prev_cinematic_caster_idx: int, tick: int, anim_speed_fn: Callable,
		tree: SceneTree) -> void:
	_emit_cinematic_periodic_summary(battle_state, all_states, tick)
	_emit_cinematic_post_end_watchdog(all_states, units, tick)
	_emit_paired_freeze_detector(battle_state, all_states, units,
		prev_cinematic_caster_idx, tick, anim_speed_fn, tree)


## Cinematic-began hook: dump per-unit pause snapshot + arm the periodic summary.
func on_cinematic_began(all_states: Array, units: Array,
		caster_idx: int, target_idx: int, tick: int) -> void:
	_dump_unit_pause_snapshot(all_states, units, "BEGAN", caster_idx, target_idx, tick)
	_cinematic_summary_due_tick = tick


## Cinematic-ended hook: dump per-unit pause snapshot + seed the post-end
## watchdog state so subsequent probe() calls can compare against it.
func on_cinematic_ended(all_states: Array, units: Array,
		prev_caster_idx: int, tick: int) -> void:
	_dump_unit_pause_snapshot(all_states, units, "ENDED", prev_caster_idx, -1, tick)
	_cinematic_watchdog_until_tick = tick + 120
	_cinematic_watchdog_post_end_tick = tick
	_cinematic_watchdog_unit_snapshot.clear()
	for i in range(all_states.size()):
		if i >= units.size() or not is_instance_valid(units[i]):
			continue
		var s: Dictionary = all_states[i]
		_cinematic_watchdog_unit_snapshot[i] = {
			"state": s.get("state", -1),
			"timer": s.get("timer", -1),
			"ability_id": s.get("casting_ability_id", -1),
			"react_active": units[i].is_reacting,
			"state_changed_at": -1,
		}


func _dump_unit_pause_snapshot(all_states: Array, units: Array, label: String,
		caster_idx: int, target_idx: int, tick: int) -> void:
	var lines := PackedStringArray()
	for i in range(all_states.size()):
		if i >= units.size() or not is_instance_valid(units[i]):
			continue
		var s: Dictionary = all_states[i]
		var paused: int = s.get("paused", 0)
		var st: int = s.get("state", 0)
		var st_name: String = GPUConstants.LOGICAL_ACTIVITY_NAMES[st] if st < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(st)
		var ab: int = s.get("casting_ability_id", -1)
		var ct: int = s.get("cast_target", -1)
		var aoe_caster: int = s.get("aoe_pending_caster", -1)
		var aoe_frame: int = s.get("aoe_pending_fire_frame", -1)
		var role := ""
		if i == caster_idx:
			role = " <CASTER>"
		elif i == target_idx:
			role = " <TARGET>"
		lines.append("  u%d %s%s: paused=%d state=%s ab=%d cast_target=%d aoe(c=%d f=%d)" % [
			i, units[i].name, role, paused, st_name, ab, ct, aoe_caster, aoe_frame])
	print("[Tick %d] [CINEMATIC %s] per-unit state:" % [tick, label])
	for line in lines:
		print(line)


## Resolve the spotlight caster + per-unit cinematic timer from the unit-side
## snapshot. Issue #118: the cinematic-spell frame counter is per-unit, so we
## scan U_CINEMATIC_TIMER >= 0 instead of reading the retired battle header.
## Returns [caster_idx, timer] or [-1, 0] if no cinematic is active anywhere.
static func _resolve_active_caster(all_states: Array) -> Array:
	for i in range(all_states.size()):
		var t: int = int(all_states[i].get("cinematic_timer", -1))
		if t >= 0:
			return [i, t]
	return [-1, 0]


func _emit_cinematic_periodic_summary(_battle_state: Dictionary, all_states: Array, tick: int) -> void:
	var resolved: Array = _resolve_active_caster(all_states)
	var caster: int = resolved[0]
	var timer: int = resolved[1]
	if caster < 0:
		_cinematic_summary_due_tick = -1
		return
	if tick < _cinematic_summary_due_tick:
		return
	_cinematic_summary_due_tick = tick + 30
	var paused_count := 0
	for i in range(all_states.size()):
		if all_states[i].get("paused", 0) != 0:
			paused_count += 1
	print("[Tick %d] [CINEMATIC tick] caster=%d timer=%d paused_units=%d/%d" % [
		tick, caster, timer, paused_count, all_states.size()])


func _emit_paired_freeze_detector(battle_state: Dictionary, all_states: Array, units: Array,
		prev_cinematic_caster_idx: int, tick: int, anim_speed_fn: Callable,
		tree: SceneTree) -> void:
	var n: int = all_states.size()
	if n == 0:
		return
	var gpu_paused: int = 0
	var cpu_zero: int = 0
	var type1_internally_paused: int = 0
	var disagreement: PackedInt32Array = PackedInt32Array()
	var visually_stuck: PackedInt32Array = PackedInt32Array()
	for i in range(n):
		if i >= units.size() or not is_instance_valid(units[i]):
			continue
		var p: int = all_states[i].get("paused", 0)
		var s: int = anim_speed_fn.call(i)
		var t1_paused: bool = (units[i].display.type1_playback != null and units[i].display.type1_playback.is_paused)
		if p != 0:
			gpu_paused += 1
		if s == 0:
			cpu_zero += 1
		if t1_paused:
			type1_internally_paused += 1
			if p == 0 and s > 0:
				visually_stuck.append(i)
		var gpu_says_active: bool = (p == 0)
		var cpu_says_active: bool = (s > 0)
		if gpu_says_active != cpu_says_active:
			disagreement.append(i)
	var combat_visuals_disabled: bool = false
	if tree:
		for nd in tree.get_nodes_in_group("combat_visuals"):
			if nd.process_mode == Node.PROCESS_MODE_DISABLED:
				combat_visuals_disabled = true
				break
	var units_disabled: PackedInt32Array = PackedInt32Array()
	for i in range(units.size()):
		var u = units[i]
		if is_instance_valid(u) and u.process_mode == Node.PROCESS_MODE_DISABLED:
			units_disabled.append(i)

	var changed: bool = (
		gpu_paused != _freeze_prev_gpu_paused
		or cpu_zero != _freeze_prev_cpu_zero_speed
		or combat_visuals_disabled != _freeze_prev_combat_visuals_disabled
	)
	if changed or units_disabled.size() > 0 or visually_stuck.size() > 0:
		var resolved: Array = _resolve_active_caster(all_states)
		var cin_caster: int = resolved[0]
		var cin_timer: int = resolved[1]
		print("[Tick %d] [FREEZE] gpu_paused=%d/%d cpu_zero=%d/%d t1_paused=%d/%d combat_visuals_disabled=%s units_disabled=%s cinematic_caster=%d timer=%d disagree=%s visually_stuck=%s" % [
			tick, gpu_paused, n, cpu_zero, n,
			type1_internally_paused, n,
			str(combat_visuals_disabled),
			str(units_disabled) if units_disabled.size() > 0 else "no",
			cin_caster, cin_timer,
			str(disagreement) if disagreement.size() > 0 else "no",
			str(visually_stuck) if visually_stuck.size() > 0 else "no"])
	elif disagreement.size() > 0:
		if tick % 30 == 0:
			print("[Tick %d] [FREEZE_DESYNC] GPU paused != CPU zero-speed for units=%s" % [
				tick, str(disagreement)])
	_freeze_prev_gpu_paused = gpu_paused
	_freeze_prev_cpu_zero_speed = cpu_zero
	_freeze_prev_combat_visuals_disabled = combat_visuals_disabled
	_emit_third_unit_spotlight(battle_state, all_states, units,
		prev_cinematic_caster_idx, tick, anim_speed_fn)


func _emit_third_unit_spotlight(_battle_state: Dictionary, all_states: Array, units: Array,
		prev_cinematic_caster_idx: int, tick: int, anim_speed_fn: Callable) -> void:
	if all_states.is_empty() or units.is_empty():
		return
	var caster: int = _resolve_active_caster(all_states)[0]
	if caster < 0 and prev_cinematic_caster_idx >= 0:
		caster = prev_cinematic_caster_idx
	var target: int = -1
	if caster >= 0:
		for i in range(all_states.size()):
			if all_states[i].get("aoe_pending_caster", -1) == caster:
				target = i
				break
	if (_spotlight_idx < 0
		or _spotlight_idx >= units.size()
		or not is_instance_valid(units[_spotlight_idx])
		or _spotlight_idx == caster
		or _spotlight_idx == target):
		var picked: int = -1
		for i in range(units.size()):
			if i == caster or i == target:
				continue
			if not is_instance_valid(units[i]):
				continue
			if all_states[i].get("flags", 0) & GPU_FLAGS_DEAD_BIT != 0:
				continue
			picked = i
			break
		if picked != _spotlight_idx:
			_spotlight_idx = picked
			_spotlight_prev_anim_frame = -1
			_spotlight_prev_state = -1
			_spotlight_prev_t1_paused = false
			_spotlight_last_anim_change_tick = tick
			if picked >= 0:
				print("[Tick %d] [SPOTLIGHT] watching u%d %s (caster=%d target=%d)" % [
					tick, picked, units[picked].name, caster, target])
	if _spotlight_idx < 0:
		return
	var i: int = _spotlight_idx
	var u = units[i]
	var s: Dictionary = all_states[i]
	var paused: int = s.get("paused", 0)
	var gpu_state: int = s.get("state", -1)
	var timer: int = s.get("timer", 0)
	var ab: int = s.get("casting_ability_id", -1)
	var anim_speed: int = anim_speed_fn.call(i)
	var t1 = u.display.type1_playback
	var t1_paused: bool = (t1 != null and t1.is_paused)
	var t1_anim_id: String = t1.anim_id if t1 != null else ""
	var t1_anim_frame: int = t1.anim_frame if t1 != null else -1
	var activity_name: String = DisplayActivity.Activity.keys()[u.activity] if u.activity < DisplayActivity.Activity.size() else str(u.activity)
	var state_name: String = GPUConstants.LOGICAL_ACTIVITY_NAMES[gpu_state] if gpu_state >= 0 and gpu_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(gpu_state)

	var frame_changed: bool = (t1_anim_frame != _spotlight_prev_anim_frame)
	var state_changed: bool = (gpu_state != _spotlight_prev_state)
	var pause_flipped: bool = (t1_paused != _spotlight_prev_t1_paused)
	if frame_changed:
		_spotlight_last_anim_change_tick = tick
	var ticks_since_change: int = tick - _spotlight_last_anim_change_tick

	var visually_frozen: bool = (ticks_since_change >= 30 and paused == 0)

	if state_changed or pause_flipped or visually_frozen or (frame_changed and (tick % 20 == 0)):
		print("[Tick %d] [SPOTLIGHT u%d %s] gpu_state=%s gpu_paused=%d gpu_timer=%d gpu_ab=%d | cpu_activity=%s anim_speed=%d t1.anim=%s t1.frame=%d t1.is_paused=%s | last_frame_change=%dt ago%s" % [
			tick, i, u.name,
			state_name, paused, timer, ab,
			activity_name, anim_speed, t1_anim_id, t1_anim_frame, str(t1_paused),
			ticks_since_change,
			" <VISUALLY_FROZEN>" if visually_frozen else ""])
	_spotlight_prev_anim_frame = t1_anim_frame
	_spotlight_prev_state = gpu_state
	_spotlight_prev_t1_paused = t1_paused


func _emit_cinematic_post_end_watchdog(all_states: Array, units: Array, tick: int) -> void:
	if tick > _cinematic_watchdog_until_tick:
		return
	for i in range(all_states.size()):
		if i >= units.size():
			continue
		var s: Dictionary = all_states[i]
		if s.get("paused", 0) != 0:
			print("[Tick %d] [CINEMATIC watchdog] u%d %s STILL paused=%d state=%d" % [
				tick, i, units[i].name, s.get("paused", 0), s.get("state", 0)])
		if s.get("aoe_pending_caster", -1) != -1:
			print("[Tick %d] [CINEMATIC watchdog] u%d %s aoe_pending_caster=%d frame=%d" % [
				tick, i, units[i].name,
				s.get("aoe_pending_caster", -1), s.get("aoe_pending_fire_frame", -1)])
		if _cinematic_watchdog_unit_snapshot.has(i):
			var snap: Dictionary = _cinematic_watchdog_unit_snapshot[i]
			if snap.get("state_changed_at", -1) == -1:
				var prev_state: int = snap.get("state", -1)
				var cur_state: int = s.get("state", -1)
				if cur_state != prev_state:
					snap["state_changed_at"] = tick
					var dt: int = tick - _cinematic_watchdog_post_end_tick
					var prev_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[prev_state] if prev_state >= 0 and prev_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(prev_state)
					var cur_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[cur_state] if cur_state >= 0 and cur_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(cur_state)
					print("[Tick %d] [CINEMATIC watchdog] u%d %s state %s->%s after %d ticks (frozen_timer_at_end=%d)" % [
						tick, i, units[i].name, prev_name, cur_name, dt, snap.get("timer", -1)])
	if tick == _cinematic_watchdog_until_tick:
		_emit_cinematic_watchdog_summary(units, tick)


func _emit_cinematic_watchdog_summary(units: Array, tick: int) -> void:
	var stuck: PackedStringArray = PackedStringArray()
	for i in _cinematic_watchdog_unit_snapshot.keys():
		var snap: Dictionary = _cinematic_watchdog_unit_snapshot[i]
		if snap.get("state_changed_at", -1) == -1:
			var prev_state: int = snap.get("state", -1)
			var prev_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[prev_state] if prev_state >= 0 and prev_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(prev_state)
			stuck.append("u%d=%s/%s/timer=%d" % [
				i, units[i].name, prev_name, snap.get("timer", -1)])
	print("[Tick %d] [CINEMATIC watchdog] window done: %d units never transitioned [%s]" % [
		tick, stuck.size(), ", ".join(stuck)])
