class_name GPUMovementInterpreter
extends RefCounted

## Interprets a unit's per-frame GPU movement state into a renderable move step.
##
## Owns the cross-frame memory that decides whether the GPU's movement fields
## describe a **new** step, a **continuing** step, or **no live move** — the
## `move_step_id` change detection plus the staleness guard that rejects the
## GPU's retry/wait timer (`timer > total_ticks`). This logic used to be tangled
## inside [GPUVisualBridge]'s apply loop, where it could not be exercised without
## a RenderingDevice, real tiles, and live [Unit] nodes.
##
## Pure: it reads only the string-keyed snapshot Dictionary (ADR-0002) and holds
## one int per unit. No terrain, no Node, no scene-tree handle — so it is driven
## the same way in a test as in the bridge. [MoveStep] is a **derived** value
## (grid coords + ticks), not a typed mirror of the 85-field snapshot, so it does
## not re-litigate ADR-0002's "snapshot stays a dict". See ADR-0017.

enum Kind {
	NO_MOVE,    ## Not moving, or moving but stale (retry/wait) — clear any visualizer, snap to tile.
	NEW_STEP,   ## A fresh move step began this frame — start a visualizer from `step`.
	CONTINUING, ## Same live step as last frame — keep the existing visualizer.
}


## The interpreter's verdict for one unit this frame. `kind` is always set; the
## grid/tick fields are meaningful only when `kind == NEW_STEP`.
class MoveStep extends RefCounted:
	var kind: int = Kind.NO_MOVE
	var from_grid: Vector2i = Vector2i.ZERO
	var to_grid: Vector2i = Vector2i.ZERO
	var total_ticks: int = 0
	var step_id: int = -1


# unit_index -> int (the move_step_id currently being rendered for that unit)
var _active_step_id: Dictionary = {}


## Classify this frame's movement state for `unit_index`, advancing the
## per-unit step memory when a new step is detected.
func classify(unit_index: int, state: Dictionary) -> MoveStep:
	var step := MoveStep.new()

	var gpu_state: int = state.get("state", 0)
	# EVERY move state writes the same movement fields — `write_movement_step` is
	# one function and APPROACHING, WALKING_TO_CAST and RETREATING all reach it —
	# so the visualizer must follow all of them. This used to hand-list three, and
	# the fourth (RETREATING, ADR-0301) arrived without it: the miss is invisible
	# from here, because a state this does not know about reads as a unit standing
	# still and the bridge dutifully snaps it to its destination tile.
	# `GPUConstants.is_movement_state` is derived from the taxonomy instead.
	if not GPUConstants.is_movement_state(gpu_state):
		step.kind = Kind.NO_MOVE
		return step

	var from_packed: int = state.get("prev_move_pos", -1)
	var to_x: int = state.get("pos_x", 0)
	var to_z: int = state.get("pos_z", 0)
	var from_x: int = (from_packed >> 16) & 0xFFFF
	var from_z: int = from_packed & 0xFFFF
	var timer: int = state.get("timer", 0)
	var total_ticks: int = state.get("move_total_ticks", 0)

	# Real-movement + staleness guard: a valid origin that differs from the
	# destination, with the timer inside (0, total_ticks]. The `timer <=
	# total_ticks` clause rejects the GPU's retry/wait timer — it sets `timer`
	# without updating `total_ticks`, so an old visualizer must not reactivate
	# as the timer counts back down into range.
	var moving := (
		from_packed >= 0
		and (from_x != to_x or from_z != to_z)
		and total_ticks > 0
		and timer > 0
		and timer <= total_ticks
	)
	if not moving:
		step.kind = Kind.NO_MOVE
		return step

	var step_id: int = state.get("move_step_id", 0)
	if step_id != _active_step_id.get(unit_index, -1):
		_active_step_id[unit_index] = step_id
		step.kind = Kind.NEW_STEP
		step.from_grid = Vector2i(from_x, from_z)
		step.to_grid = Vector2i(to_x, to_z)
		step.total_ticks = total_ticks
		step.step_id = step_id
		return step

	step.kind = Kind.CONTINUING
	return step


## Forget one unit's step memory (its visualizer was torn down). Mirrors the
## bridge's per-unit `_clear_movement_state`. Whole-battle reset needs no method:
## the bridge — and its interpreter — are recreated per battle.
func forget(unit_index: int) -> void:
	_active_step_id.erase(unit_index)
