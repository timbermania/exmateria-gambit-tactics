class_name GPUVisualBridge
extends RefCounted

## Applies GPU combat state to the visual scene each frame.
##
## Reads the authoritative per-unit snapshot, then drives Godot: death arc and
## grounding, movement-visualizer interpolation, animation state, facing, and
## position. The *interpretation* of the raw movement fields — is this a new
## step, a continuing step, or a stale retry/wait? — lives in
## [GPUMovementInterpreter], which owns the `move_step_id` change detection and
## the `timer <= total_ticks` staleness guard. The bridge consumes that verdict
## and decides what to render. See ADR-0017.

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

## And the schema façade for the cell type (ADR-0212 dec. 1) — `TerrainCell.ground`
## is how this file states that the GPU stack runs on the ground plane (ADR-0219).
const TerrainCell = ExMateriaSchema.TerrainCell


const GPUMovementVisualizerClass = preload("res://src/gpu/GPUMovementVisualizer.gd")
const GPUMovementInterpreterClass = preload("res://src/gpu/GPUMovementInterpreter.gd")

const TELEPORT_THRESHOLD := 0.5  # World units — triggers diagnostic log

# Visual state tracking (all keyed by unit_index)
var visual_positions: Dictionary = {}       # -> Vector3
var movement_visualizers: Dictionary = {}   # -> GPUMovementVisualizer
var _dead_grounded: Dictionary = {}         # -> bool (dead units that reached ground)

# Owns the new-step detection + staleness guard (ADR-0017). Private to the
# bridge: nothing else reads the GPU movement fields.
var _interp := GPUMovementInterpreterClass.new()

# Diagnostic-only tracking (used by _log_movement_diagnostics)
var _prev_visual_pos: Dictionary = {}       # -> Vector3 (teleport detection logging)
var _prev_state: Dictionary = {}            # -> int (state transition logging)


func update_visual_positions(gpu_states: Array, units: Array, lattice: Lattice,
		tick_alpha: float = 0.0) -> void:
	"""Interpolate visual positions toward GPU logical positions.

	Reads authoritative movement state from GPU: prev_move_pos (origin),
	pos_x/z (destination), timer (countdown), move_total_ticks (duration).

	`tick_alpha` is the fraction of a TICK_INTERVAL the host has banked but not yet
	simulated (#1206). It defaults to 0.0 so a caller that has no accumulator — every test
	that drives this bridge directly — keeps the exact per-tick behaviour it asserts.
	"""
	for i in range(mini(gpu_states.size(), units.size())):
		var unit = units[i]
		if not is_instance_valid(unit):
			continue

		var state = gpu_states[i]
		var is_dead = (state.get("flags", 0) & 1) != 0

		# Bridge GPU-shader death → Godot Unit: fire `die()` once on the
		# transition so the death animation, EventBus.unit_died, and the
		# SfxRouter death cue all fire. The matching path in tests
		# (GPUCombatTestBase._process_death) does the same; without this
		# the F5 scene silently dropped dead units to the ground with no
		# event chain.
		if is_dead and unit.unit_stats and not unit.unit_stats.is_dead:
			unit.unit_stats.die()

		# Dead units: finish movement arc to ground, then stop updating
		if is_dead:
			if _dead_grounded.get(i, false):
				continue
			var visualizer = movement_visualizers.get(i, null) as GPUMovementVisualizer
			if visualizer and state.get("timer", 0) > 0:
				var new_pos = visualizer.calculate_position(
					_render_timer(state.get("timer", 0), tick_alpha))
				visual_positions[i] = new_pos
				unit.global_position = new_pos
			else:
				var dead_pos := _resolve_gpu_cell(state, lattice, "death grounding")
				# `world_position_at` returns Vector3.ZERO for BOTH "no cell" and "the
				# cell at the origin", so existence is asked separately (ADR-0192
				# dec. 6 — the scalar query is what keeps the per-frame path below
				# allocation-free; this branch runs once per death, not per frame).
				if lattice.terrain_at(dead_pos) != null:
					var dead_world := lattice.world_position_at(dead_pos)
					unit.global_position = dead_world
					visual_positions[i] = dead_world
				_clear_movement_state(i)
				_dead_grounded[i] = true
			continue

		# Destination tile / timer / state the bridge still needs. Origin
		# unpacking + the movement & staleness guard live in the interpreter.
		var gpu_pos := _resolve_gpu_cell(state, lattice, "movement writeback")
		if lattice.terrain_at(gpu_pos) == null:
			continue

		var target_world := lattice.world_position_at(gpu_pos)
		var timer: int = state.get("timer", 0)
		var total_ticks: int = state.get("move_total_ticks", 0)
		var gpu_state: int = state.get("state", 0)

		# Clear stale visualizer when conflict resolution blocked movement
		if state.get("dbg_conflict_blocked", 0) == 1:
			_log_viz_erase(i, unit, "conflict_blocked")
			_clear_movement_state(i)

		var new_visual: Vector3
		var step := _interp.classify(i, state)
		if step.kind == GPUMovementInterpreterClass.Kind.NEW_STEP:
			# Fresh step — build a visualizer from the interpreter's grid coords.
			var current_visual = visual_positions.get(i, unit.global_position)

			_log_viz_new(i, unit, step.from_grid, gpu_pos, current_visual, state)

			var visualizer = GPUMovementVisualizerClass.new()
			# 🔴 `from_cell` IS NOT COSMETIC — it is one of the two arguments to
			# `lattice.is_cliff_edge` inside `start_movement`, which decides arc
			# versus linear. Get its level wrong on a descent off a bridge and a
			# nine-half-step drop renders as a flat slide.
			#
			# `step.from_grid` is a COLUMN: the interpreter unpacks it from
			# `U_PREV_MOVE_POS`, which ADR-0224 dec. 5 deliberately left as a
			# two-field pack (a unit cannot change level in place, so the
			# oscillation memory it exists for never needed a third field). Taking
			# `gpu_pos.z` instead would be right for every step WITHIN a level and
			# wrong for exactly the cross-level step this ADR exists to enable.
			#
			# The origin's level is already in the tree: `movement_component
			# .current_cell` still holds the PREVIOUS cell at this point — it is
			# assigned `gpu_pos` a few lines below, after the visualizer is built.
			# So the level is read from there when its column matches the
			# interpreter's origin, and falls back to the ground otherwise. No
			# fourth unit field: dec. 4 stores a level beside a position because
			# deriving it would re-run a climb decision, and nothing is re-run here.
			var prev_cell: Vector3i = unit.movement_component.current_cell
			var from_cell := TerrainCell.ground(step.from_grid.x, step.from_grid.y)
			if prev_cell.x == step.from_grid.x and prev_cell.y == step.from_grid.y:
				from_cell = prev_cell
			if lattice.terrain_at(from_cell) == null:
				from_cell = TerrainCell.ground(step.from_grid.x, step.from_grid.y)
			if lattice.terrain_at(from_cell) != null:
				# 🔴 THE JUMP IS NOT COSMETIC EITHER. A pass-through step lands the
				# unit past an ally, up to eight tiles away, and the visualizer has
				# to walk the tiles BETWEEN — which cell of a two-cell column it
				# crossed is a question only this unit's jump answers. Get it wrong
				# and the fallback is the old end-to-end reading, which slid the
				# sprite through the tile it should have hopped.
				# `Unit.jump` forwards to `unit_stats`, which the death branch above
				# already treats as possibly null — so ask the same way here rather
				# than trusting a live unit to have one.
				var mover_jump: int = int(unit.jump) if unit.unit_stats \
					else GPUMovementVisualizer.DEFAULT_JUMP
				visualizer.start_movement(from_cell, gpu_pos, lattice, current_visual,
					mover_jump)
			else:
				visualizer.is_cliff_move = false
				visualizer.start_pos = current_visual
				visualizer.end_pos = target_world
			visualizer.set_gpu_total_ticks(step.total_ticks)
			movement_visualizers[i] = visualizer
			unit.movement_component.current_cell = gpu_pos

			new_visual = _follow_visualizer(i, unit, _render_timer(timer, tick_alpha), target_world)
		elif step.kind == GPUMovementInterpreterClass.Kind.CONTINUING:
			new_visual = _follow_visualizer(i, unit, _render_timer(timer, tick_alpha), target_world)
		else:
			# NO_MOVE — waiting/retry, stale, or not moving. Drop any stale
			# visualizer so it can't reactivate, and snap to the GPU tile.
			if movement_visualizers.has(i):
				var reason := ("retry/wait timer=%d total=%d" % [timer, total_ticks]) \
					if (gpu_state == GPUConstants.LOGICAL_ACTIVITY_WALKING or gpu_state == GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST or gpu_state == GPUConstants.LOGICAL_ACTIVITY_APPROACHING) \
					else ("state_left_moving state=%s" % _state_name(gpu_state))
				_log_viz_erase(i, unit, reason)
				_clear_movement_state(i)
			new_visual = target_world

		_log_movement_diagnostics(i, unit, gpu_state, timer, gpu_pos, new_visual, target_world)

		visual_positions[i] = new_visual
		unit.global_position = new_visual + unit.distort_offset


## The timer to RENDER at, from the timer the sim is AT.
##
## `timer` counts DOWN, so carrying the render back by the un-simulated fraction of the
## current tick means adding `1 - alpha`: at alpha 0 (a tick just fired) it resolves to the
## PREVIOUS tick's value, and as alpha approaches 1 it slides continuously onto the current
## one — at which point the next tick fires, `timer` drops by one and alpha resets, and the
## two changes cancel exactly. That cancellation is why the result is continuous across the
## tick boundary rather than merely finer-grained.
##
## 🔴 THIS INTERPOLATES BEHIND, IT DOES NOT EXTRAPOLATE AHEAD. The GPU sim is authoritative
## and `vis_states` is the CURRENT tick; sampling at `timer - alpha` would draw a unit where
## the sim has not yet put it. That buys ~16.7 ms of latency on rendered movement, which is
## invisible for units executing an already-committed order, and it is the price of never
## rendering a position the simulation did not authorise. See ADR-0292.
static func _render_timer(timer: int, tick_alpha: float) -> float:
	return float(timer) + (1.0 - tick_alpha)


func _follow_visualizer(i: int, unit: Unit, timer: float, target_world: Vector3) -> Vector3:
	# Drive the unit off its active visualizer: position, animation, facing.
	# Returns the GPU tile when no visualizer is present (defensive — NEW_STEP/
	# CONTINUING should always have created/kept one).
	var visualizer = movement_visualizers.get(i, null) as GPUMovementVisualizer
	if not visualizer:
		return target_world
	var pos = visualizer.calculate_position(timer)
	var anim_state = visualizer.get_activity(timer)
	if unit.activity != anim_state:
		unit.activity = anim_state
	var move_dir = visualizer.end_pos - visualizer.start_pos
	if move_dir.length_squared() > 0.01:
		update_facing_from_movement(unit, move_dir)
	return pos


# --- Diagnostic logging (gated behind DebugConfig.iteration_debug_enabled) ---


func _state_name(state_id: int) -> String:
	if state_id < GPUConstants.LOGICAL_ACTIVITY_NAMES.size():
		return GPUConstants.LOGICAL_ACTIVITY_NAMES[state_id]
	return str(state_id)


## ADR-0224 dec. 9 — THE WRITEBACK VALIDATES RATHER THAN TRUSTS.
##
## `state` now carries a level (`U_LEVEL`, ADR-0224 dec. 4) and the GPU mover
## writes it (dec. 5). This resolves that cell through the lattice and, if the
## level is not minted there, falls back to the column's ground and logs an
## ERROR — not a debug print.
##
## Erroring rather than trusting is the point: a `Vector3i` the lattice does not
## know turns an indexing bug in the shader into a null dereference inside a
## render path, several frames and one subsystem away from its cause. The line
## above `terrain_at` in the caller already has this shape (`TerrainCell.ground`
## then a null check), so this matches the code beside it.
##
## An unminted GROUND cell is NOT an error here: that is the ordinary off-map
## case the caller's own null check has always handled by skipping the unit. Only
## a level the GPU claimed and the lattice denies is worth a crash-loud message.
func _resolve_gpu_cell(state: Dictionary, lattice: Lattice, context: String) -> Vector3i:
	var x: int = state["pos_x"]
	var z: int = state["pos_z"]
	var level: int = int(state.get("level", TerrainCell.GROUND_LEVEL))
	if level == TerrainCell.GROUND_LEVEL:
		return TerrainCell.ground(x, z)
	var cell := Vector3i(x, z, level)
	if lattice.terrain_at(cell) != null:
		return cell
	push_error("[GPUVisualBridge] %s: the GPU reports (%d, %d) at level %d, which the lattice does not mint. Falling back to the ground cell — this is a state bug in the mover, not a render bug." % [
		context, x, z, level])
	return TerrainCell.ground(x, z)


func _log_viz_new(idx: int, unit: Unit, from_grid: Vector2i, gpu_pos: Vector3i, current_visual: Vector3, state: Dictionary) -> void:
	if not DebugConfig.iteration_debug_enabled:
		return
	print("[VIZ-NEW] u%d \"%s\" pos change (%d,%d)->(%d,%d) current_visual=(%.1f,%.1f,%.1f) timer=%d total=%d state=%s" % [
		idx, unit.name, from_grid.x, from_grid.y, gpu_pos.x, gpu_pos.y,
		current_visual.x, current_visual.y, current_visual.z,
		state.get("timer", 0), state.get("move_total_ticks", 0), _state_name(state.get("state", 0))])


func _log_viz_erase(idx: int, unit: Unit, reason: String) -> void:
	if not DebugConfig.iteration_debug_enabled or not movement_visualizers.has(idx):
		return
	print("[VIZ-ERASE] u%d \"%s\" reason=%s" % [idx, unit.name, reason])


func _log_movement_diagnostics(idx: int, unit: Unit, gpu_state: int, timer: int, gpu_pos: Vector3i, new_visual: Vector3, target_world: Vector3) -> void:
	if not DebugConfig.iteration_debug_enabled:
		return

	var prev_vis = _prev_visual_pos.get(idx, new_visual)
	var jump_dist = prev_vis.distance_to(new_visual)

	# Teleport detection for any state
	if jump_dist > TELEPORT_THRESHOLD:
		var prev_state_val = _prev_state.get(idx, gpu_state)
		print("[TELEPORT] Unit %d \"%s\" jumped %.1f units!" % [idx, unit.name, jump_dist])
		print("  state: %s -> %s  timer: %d" % [_state_name(prev_state_val), _state_name(gpu_state), timer])
		print("  gpu_pos: (%d,%d)" % [gpu_pos.x, gpu_pos.y])
		print("  visual: (%.1f,%.1f,%.1f) -> (%.1f,%.1f,%.1f)" % [prev_vis.x, prev_vis.y, prev_vis.z, new_visual.x, new_visual.y, new_visual.z])
		print("  target_world: (%.1f,%.1f,%.1f)" % [target_world.x, target_world.y, target_world.z])
		var viz = movement_visualizers.get(idx, null) as GPUMovementVisualizer
		if viz:
			print("  visualizer: start=(%.1f,%.1f,%.1f) end=(%.1f,%.1f,%.1f) gpu_total=%d total=%d" % [
				viz.start_pos.x, viz.start_pos.y, viz.start_pos.z,
				viz.end_pos.x, viz.end_pos.y, viz.end_pos.z,
				viz.gpu_total_ticks, viz.total_ticks])
		else:
			print("  visualizer: none")

	_prev_visual_pos[idx] = new_visual
	_prev_state[idx] = gpu_state


static func update_facing_from_movement(unit: Unit, move_dir: Vector3) -> void:
	"""Update unit facing direction based on movement direction.

	Literal world mapping: +X=NORTH, -X=SOUTH, +Z=EAST, -Z=WEST.
	"""
	if abs(move_dir.x) > abs(move_dir.z):
		if move_dir.x > 0:
			unit.facing_direction = FacingDirection.NORTH
		else:
			unit.facing_direction = FacingDirection.SOUTH
	else:
		if move_dir.z > 0:
			unit.facing_direction = FacingDirection.EAST
		else:
			unit.facing_direction = FacingDirection.WEST


static func update_facing_toward_target(unit: Unit, unit_id: int, gpu_states: Array) -> void:
	"""Update unit facing direction to face their target."""
	if unit_id >= gpu_states.size():
		return

	var state = gpu_states[unit_id]
	var target_id = state.get("target", -1)
	# During CHARGING, U_TARGET may not be set yet — fall back to cast_target
	if target_id < 0 or target_id >= gpu_states.size():
		target_id = state.get("cast_target", -1)
	if target_id < 0 or target_id >= gpu_states.size():
		return

	# Skip facing update for self-targeting (e.g., Potion on self)
	if target_id == unit_id:
		return

	var target_state = gpu_states[target_id]
	var dx = target_state["pos_x"] - state["pos_x"]
	var dz = target_state["pos_z"] - state["pos_z"]

	if abs(dx) > abs(dz):
		if dx > 0:
			unit.facing_direction = FacingDirection.NORTH
		else:
			unit.facing_direction = FacingDirection.SOUTH
	else:
		if dz > 0:
			unit.facing_direction = FacingDirection.EAST
		else:
			unit.facing_direction = FacingDirection.WEST


func get_visualizer(unit_index: int) -> GPUMovementVisualizer:
	"""Get the active movement visualizer for a unit, or null."""
	return movement_visualizers.get(unit_index, null)


func init_unit_tracking(unit_index: int, world_pos: Vector3) -> void:
	"""Initialize visual tracking for a unit."""
	visual_positions[unit_index] = world_pos


func _clear_movement_state(unit_index: int) -> void:
	movement_visualizers.erase(unit_index)
	_interp.forget(unit_index)
