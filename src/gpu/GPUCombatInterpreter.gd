class_name GPUCombatInterpreter
extends RefCounted

## Interprets a unit's per-frame GPU combat snapshot into the frame's ordered
## list of typed combat events, which an apply-only pump consumes.
##
## The sibling of [GPUMovementInterpreter]: same shape (pure [RefCounted],
## GPU-free, scene-free), but where movement returns one derived [MoveStep],
## this returns the whole frame's [CombatEvent]s and owns the **precedence**
## across them — a death this frame suppresses the unit's other events (the old
## `_check_state_changes` loop's early `continue`). It owns the cross-frame
## **sample buffers** (last frame's GPU values, used only for edge detection),
## never an invented decision-state.
##
## Read rule (ADR-0018): battle state lives only in the GPU, so this reads only
## the string-keyed snapshot Dictionary (ADR-0002) plus immutable GPU-mirrored
## reference data; never a live [Unit] node, terrain, or [RenderingDevice] —
## those belong to the pump. So the new-step/death/hp/mp/stat detection is
## unit-testable with synthetic snapshot dicts and no GPU. See ADR-0018.
##
## This file covers the **simple diffs** (death, position, hp, mp, stat,
## projectile-fired). The cast/charge events (keyed off the GPU's CAST_STEP_ID)
## land in a later slice; until then `_process_spell_cast` / state-transition
## stay in the caller.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase


const GPUConstantsClass = preload("res://src/gpu/GPUConstants.gd")


enum EventKind {
	DIED,             ## Unit transitioned to dead this frame. Suppresses its other events.
	POSITION_CHANGED, ## grid position differs from last frame (regression-log move).
	MP_CHANGED,       ## mp differs from last frame.
	CAST_BEGAN,       ## a new action (cast_step_id changed) with a valid ability + target.
	ACTION_COMMITTED, ## any action commit (cast_step_id changed), ability OR pure attack. Discrete-commit witness independent of host-frame state sampling (#93).
	STATE_CHANGED,    ## gpu state differs from last frame (facing / animation / charge vfx).
	PROJECTILE_FIRED, ## anim_flags projectile-trigger bit went 0 -> 1.
	HP_CHANGED,       ## hp differs from last frame.
	STAT_CHANGED,     ## a break-affected stat (pa/ma/speed/wp/s_ev) differs from last frame.
}


## The break-affected stats the GPU can change mid-battle, with their log label.
## (key in the snapshot Dictionary, human label for the regression log.)
const STAT_FIELDS := [
	["pa", "PA"],
	["ma", "MA"],
	["speed", "Speed"],
	["wp", "WP"],
	["s_ev", "S_EV"],
]


## One derived combat event for one unit this frame. `kind` is always set; the
## payload fields are meaningful per-kind (see EventKind). Carries everything an
## applier needs so the pump never re-reads the snapshot for detection.
class CombatEvent extends RefCounted:
	var kind: int
	var unit_index: int = -1
	# HP_CHANGED / MP_CHANGED:
	var delta: int = 0          ## new - prev (HP only; signed)
	var new_value: int = 0      ## hp or mp after the change
	var prev_value: int = 0     ## hp or mp before the change
	var was_heal: bool = false  ## HP_CHANGED: delta > 0
	var killed: bool = false    ## HP_CHANGED: the change brought hp <= 0
	# STAT_CHANGED:
	var stat_key: String = ""   ## snapshot key (e.g. "pa")
	var stat_label: String = "" ## log label (e.g. "PA")
	# POSITION_CHANGED:
	var from_pos: Vector2i = Vector2i.ZERO
	var to_pos: Vector2i = Vector2i.ZERO
	# CAST_BEGAN:
	var ability_id: int = -1
	var target: int = -1
	var defers_trap: bool = false   ## weapon-range non-damage ability → pump defers the TRAP
	# STATE_CHANGED:
	var prev_state: int = 0
	var new_state: int = 0
	var cast_began_this_frame: bool = false  ## a CAST_BEGAN was emitted for this unit this frame


# Per-unit sample buffers (last frame's GPU values). Pure edge-detection memory,
# not battle state — the GPU remains the source of truth, re-read every frame.
var _seen: Dictionary = {}              # unit_index -> true once first seeded
var _prev_dead: Dictionary = {}         # unit_index -> bool
var _prev_pos: Dictionary = {}          # unit_index -> Vector2i
var _prev_hp: Dictionary = {}           # unit_index -> int
var _prev_mp: Dictionary = {}           # unit_index -> int
var _prev_anim_flags: Dictionary = {}   # unit_index -> int
var _prev_stats: Dictionary = {}        # unit_index -> {stat_key -> int}
var _prev_state: Dictionary = {}        # unit_index -> int (gpu STATE_*)
var _prev_casting_ability_id: Dictionary = {}  # unit_index -> int
var _prev_cast_target: Dictionary = {}  # unit_index -> int
var _prev_cast_step: Dictionary = {}    # unit_index -> int (GPU CAST_STEP_ID last acted on)


## Seed (or re-seed) a unit's sample buffers from a snapshot without emitting
## events. The caller seeds from the initial battle state so the first live
## frame compares against it (matching the old base's `_log_initial_state`).
func seed_unit(unit_index: int, state: Dictionary) -> void:
	_prev_dead[unit_index] = _is_dead(state)
	_prev_pos[unit_index] = Vector2i(int(state.get("pos_x", 0)), int(state.get("pos_z", 0)))
	_prev_hp[unit_index] = int(state.get("hp", 0))
	_prev_mp[unit_index] = int(state.get("mp", 0))
	_prev_anim_flags[unit_index] = int(state.get("anim_flags", 0))
	var stats := {}
	for sf in STAT_FIELDS:
		stats[sf[0]] = int(state.get(sf[0], 0))
	_prev_stats[unit_index] = stats
	_prev_state[unit_index] = int(state.get("state", 0))
	_prev_casting_ability_id[unit_index] = int(state.get("casting_ability_id", -1))
	_prev_cast_target[unit_index] = int(state.get("cast_target", -1))
	_prev_cast_step[unit_index] = int(state.get("cast_step_id", 0))
	_seen[unit_index] = true


## Forget one unit's sample buffers (mirrors the movement interpreter's forget()).
## Whole-battle reset needs no method: the interpreter is recreated per battle.
func forget(unit_index: int) -> void:
	_seen.erase(unit_index)
	_prev_dead.erase(unit_index)
	_prev_pos.erase(unit_index)
	_prev_hp.erase(unit_index)
	_prev_mp.erase(unit_index)
	_prev_anim_flags.erase(unit_index)
	_prev_stats.erase(unit_index)
	_prev_state.erase(unit_index)
	_prev_casting_ability_id.erase(unit_index)
	_prev_cast_target.erase(unit_index)
	_prev_cast_step.erase(unit_index)


## Classify this frame's snapshot for `unit_index` into an ordered event list,
## advancing the sample buffers. First sight of a unit seeds and returns no
## events. Death suppresses every other event for that unit this frame.
func interpret(unit_index: int, state: Dictionary) -> Array:
	var events: Array = []

	if not _seen.has(unit_index):
		seed_unit(unit_index, state)
		return events

	# Death precedence: a newly-dead unit emits only DIED; an already-dead unit
	# emits nothing. Mirrors the old loop's `_process_death` + `continue`.
	if _is_dead(state):
		if not _prev_dead.get(unit_index, false):
			_prev_dead[unit_index] = true
			var ev := _make(EventKind.DIED, unit_index)
			ev.prev_value = int(_prev_hp.get(unit_index, 0))  # for the hp_changed(prev, 0) emit
			events.append(ev)
		return events
	_prev_dead[unit_index] = false

	# Order mirrors the old `_check_state_changes` steps: position, mp,
	# projectile-fired, hp, stats.
	var cur_pos := Vector2i(int(state.get("pos_x", 0)), int(state.get("pos_z", 0)))
	if cur_pos != _prev_pos[unit_index]:
		var ev := _make(EventKind.POSITION_CHANGED, unit_index)
		ev.from_pos = _prev_pos[unit_index]
		ev.to_pos = cur_pos
		events.append(ev)
		_prev_pos[unit_index] = cur_pos

	var cur_mp := int(state.get("mp", 0))
	if cur_mp != _prev_mp[unit_index]:
		var ev := _make(EventKind.MP_CHANGED, unit_index)
		ev.new_value = cur_mp
		ev.prev_value = _prev_mp[unit_index]
		events.append(ev)
		_prev_mp[unit_index] = cur_mp

	# Cast begin (step 4): a new action instance (cast_step_id changed) carrying a
	# valid ability + target. Keyed off the GPU counter, so it fires once per cast
	# with no invented latch. Pure attacks bump cast_step_id but carry no ability,
	# so emit no CAST_BEGAN — but DO emit ACTION_COMMITTED (which carries ability_id
	# = -1 for the pure-attack case). ACTION_COMMITTED is the discrete-commit
	# witness the gambit-suite predicates need: STATE_CHANGED gets coalesced when
	# ACTING → IDLE → ACTING happens within one host frame, but cast_step_id bumps
	# survive any host-frame sampling because the GPU counter only goes up (#93).
	var cast_began := false
	var cur_cast_step := int(state.get("cast_step_id", 0))
	if cur_cast_step != int(_prev_cast_step[unit_index]):
		_prev_cast_step[unit_index] = cur_cast_step
		var prev_casting := int(_prev_casting_ability_id[unit_index])
		var ability_id := prev_casting if prev_casting >= 0 else int(state.get("casting_ability_id", -1))
		var target_id := int(state.get("cast_target", -1))
		if target_id < 0:
			target_id = int(_prev_cast_target[unit_index])
		var ac_ev := _make(EventKind.ACTION_COMMITTED, unit_index)
		ac_ev.ability_id = ability_id
		ac_ev.target = target_id
		events.append(ac_ev)
		if ability_id >= 0 and target_id >= 0:
			cast_began = true
			var ev := _make(EventKind.CAST_BEGAN, unit_index)
			ev.ability_id = ability_id
			ev.target = target_id
			ev.defers_trap = _defers_trap(ability_id)
			events.append(ev)

	# State change (step 5): the pump reacts with facing / animation / charge vfx.
	var cur_state := int(state.get("state", 0))
	if cur_state != int(_prev_state[unit_index]):
		var ev := _make(EventKind.STATE_CHANGED, unit_index)
		ev.prev_state = int(_prev_state[unit_index])
		ev.new_state = cur_state
		ev.cast_began_this_frame = cast_began
		events.append(ev)
		_prev_state[unit_index] = cur_state

	# Track casting fields each frame (mirrors the old _process_spell_cast tail) so
	# next frame can resolve a cleared casting_ability_id / cast_target.
	_prev_casting_ability_id[unit_index] = int(state.get("casting_ability_id", -1))
	_prev_cast_target[unit_index] = int(state.get("cast_target", -1))

	var cur_af := int(state.get("anim_flags", 0))
	if (cur_af & 2) != 0 and (int(_prev_anim_flags[unit_index]) & 2) == 0:
		events.append(_make(EventKind.PROJECTILE_FIRED, unit_index))
	_prev_anim_flags[unit_index] = cur_af

	var cur_hp := int(state.get("hp", 0))
	if cur_hp != _prev_hp[unit_index]:
		var d := cur_hp - int(_prev_hp[unit_index])
		var ev := _make(EventKind.HP_CHANGED, unit_index)
		ev.delta = d
		ev.new_value = cur_hp
		ev.prev_value = _prev_hp[unit_index]
		ev.was_heal = d > 0
		ev.killed = cur_hp <= 0
		events.append(ev)
		_prev_hp[unit_index] = cur_hp

	var stats: Dictionary = _prev_stats[unit_index]
	for sf in STAT_FIELDS:
		var key: String = sf[0]
		var cur_val := int(state.get(key, 0))
		if cur_val != int(stats[key]):
			var ev := _make(EventKind.STAT_CHANGED, unit_index)
			ev.stat_key = key
			ev.stat_label = sf[1]
			ev.prev_value = stats[key]
			ev.new_value = cur_val
			events.append(ev)
			stats[key] = cur_val

	return events


func _is_dead(state: Dictionary) -> bool:
	return (int(state.get("flags", 0)) & GPUConstantsClass.FLAG_DEAD_BIT) != 0


## A weapon-range non-damage ability (break, holy sword) whose TRAP the pump
## defers to the weapon-impact frame. Reads immutable, GPU-mirrored ability data
## (allowed by the read rule) — not battle state.
func _defers_trap(ability_id: int) -> bool:
	var ab := AbilityDatabase.get_ability_view(ability_id)
	return ab.weapon_range and AbilityDatabase.is_non_damage_formula(ab.formula)


## The casting ability id this unit last carried (sample buffer). The pump reads
## it to attribute a melee hit cloud to the attacker whose casting_ability_id the
## GPU already cleared. Reading, not owning — the GPU stays the source of truth.
func last_casting_ability_id(unit_index: int) -> int:
	return int(_prev_casting_ability_id.get(unit_index, -1))


## The hp this unit carried at last frame's interpret (sample buffer). The
## intra-tick quick-damage check reads it to time reactions before interpret()
## runs for the frame. Reading, not owning.
func last_hp(unit_index: int) -> int:
	return int(_prev_hp.get(unit_index, 0))


## The gpu state this unit carried at last frame's interpret (sample buffer).
## The per-tick animation-speed read uses it (1-tick lag is negligible).
## Defaults to LOGICAL_ACTIVITY_IDLE (0). Reading, not owning.
func last_state(unit_index: int) -> int:
	return int(_prev_state.get(unit_index, 0))


func _make(kind: int, unit_index: int) -> CombatEvent:
	var ev := CombatEvent.new()
	ev.kind = kind
	ev.unit_index = unit_index
	return ev
