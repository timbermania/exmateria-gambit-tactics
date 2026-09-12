extends Node
## GPUMovementInterpreter unit test (ADR-0017). Pure GDScript — no RenderingDevice,
## no tiles, no Unit nodes, no scene. Feeds synthetic snapshot dicts and asserts
## the new-step / continuing / no-move classification, the `timer <= total_ticks`
## staleness guard, and the forget()/clear() memory reset. The interpreter being
## drivable this way is the whole point of pulling it out of GPUVisualBridge,
## whose apply loop could not be exercised without the live GPU.

const InterpClass = preload("res://src/gpu/GPUMovementInterpreter.gd")

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


# Build a snapshot dict. `from` and `to` are grid Vector2i; prev_move_pos packs
# the origin the way the GPU does (x << 16 | z).
func _state(gpu_state: int, from: Vector2i, to: Vector2i, timer: int, total_ticks: int, step_id: int) -> Dictionary:
	return {
		"state": gpu_state,
		"prev_move_pos": (from.x << 16) | from.y,
		"pos_x": to.x,
		"pos_z": to.y,
		"timer": timer,
		"move_total_ticks": total_ticks,
		"move_step_id": step_id,
	}


func _ready() -> void:
	_test_not_moving_is_no_move()
	_test_new_then_continuing()
	_test_step_id_change_is_new()
	_test_stale_timer_is_no_move()
	_test_no_displacement_is_no_move()
	_test_bad_origin_is_no_move()
	_test_moving_to_cast_counts()
	_test_forget_reopens_step()

	if _failed:
		print("[FAIL] GPUMovementInterpreter test")
	else:
		print("[PASS] GPUMovementInterpreter: new/continuing/no-move, staleness guard, forget OK")
	get_tree().quit()


func _test_not_moving_is_no_move() -> void:
	var it = InterpClass.new()
	var s := _state(GPUConstants.LOGICAL_ACTIVITY_IDLE, Vector2i(1, 1), Vector2i(2, 1), 5, 10, 7)
	_check(it.classify(0, s).kind == InterpClass.Kind.NO_MOVE, "idle state ⇒ NO_MOVE regardless of move fields")


func _test_new_then_continuing() -> void:
	var it = InterpClass.new()
	var s := _state(GPUConstants.LOGICAL_ACTIVITY_WALKING, Vector2i(3, 4), Vector2i(3, 5), 8, 10, 1)
	var a = it.classify(0, s)
	_check(a.kind == InterpClass.Kind.NEW_STEP, "first moving frame ⇒ NEW_STEP")
	_check(a.from_grid == Vector2i(3, 4), "NEW_STEP from_grid unpacked from prev_move_pos (got %s)" % str(a.from_grid))
	_check(a.to_grid == Vector2i(3, 5), "NEW_STEP to_grid from pos_x/pos_z")
	_check(a.total_ticks == 10 and a.step_id == 1, "NEW_STEP carries total_ticks + step_id")

	# Same step id next frame (timer ticked down) ⇒ CONTINUING, no new step.
	var s2 := _state(GPUConstants.LOGICAL_ACTIVITY_WALKING, Vector2i(3, 4), Vector2i(3, 5), 6, 10, 1)
	_check(it.classify(0, s2).kind == InterpClass.Kind.CONTINUING, "same step_id ⇒ CONTINUING")


func _test_step_id_change_is_new() -> void:
	var it = InterpClass.new()
	it.classify(0, _state(GPUConstants.LOGICAL_ACTIVITY_WALKING, Vector2i(0, 0), Vector2i(1, 0), 9, 10, 1))
	var b = it.classify(0, _state(GPUConstants.LOGICAL_ACTIVITY_WALKING, Vector2i(1, 0), Vector2i(2, 0), 9, 10, 2))
	_check(b.kind == InterpClass.Kind.NEW_STEP, "changed move_step_id ⇒ NEW_STEP")
	_check(b.from_grid == Vector2i(1, 0), "second step from_grid follows the new origin")


func _test_stale_timer_is_no_move() -> void:
	# The GPU's retry/wait sets timer without updating total_ticks: timer > total.
	var it = InterpClass.new()
	var s := _state(GPUConstants.LOGICAL_ACTIVITY_WALKING, Vector2i(1, 1), Vector2i(2, 1), 30, 10, 5)
	_check(it.classify(0, s).kind == InterpClass.Kind.NO_MOVE, "timer > total_ticks (retry/wait) ⇒ NO_MOVE")


func _test_no_displacement_is_no_move() -> void:
	var it = InterpClass.new()
	var s := _state(GPUConstants.LOGICAL_ACTIVITY_WALKING, Vector2i(2, 2), Vector2i(2, 2), 5, 10, 9)
	_check(it.classify(0, s).kind == InterpClass.Kind.NO_MOVE, "origin == destination ⇒ NO_MOVE")


func _test_bad_origin_is_no_move() -> void:
	var it = InterpClass.new()
	var s := {
		"state": GPUConstants.LOGICAL_ACTIVITY_WALKING,
		"prev_move_pos": -1,  # GPU hasn't recorded an origin
		"pos_x": 4, "pos_z": 4, "timer": 5, "move_total_ticks": 10, "move_step_id": 3,
	}
	_check(it.classify(0, s).kind == InterpClass.Kind.NO_MOVE, "prev_move_pos < 0 ⇒ NO_MOVE")


func _test_moving_to_cast_counts() -> void:
	var it = InterpClass.new()
	var s := _state(GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST, Vector2i(0, 0), Vector2i(0, 1), 7, 10, 1)
	_check(it.classify(0, s).kind == InterpClass.Kind.NEW_STEP, "LOGICAL_ACTIVITY_WALKING_TO_CAST is a moving state")


func _test_forget_reopens_step() -> void:
	var it = InterpClass.new()
	var s := _state(GPUConstants.LOGICAL_ACTIVITY_WALKING, Vector2i(1, 1), Vector2i(1, 2), 8, 10, 4)
	_check(it.classify(0, s).kind == InterpClass.Kind.NEW_STEP, "forget: initial NEW_STEP")
	_check(it.classify(0, s).kind == InterpClass.Kind.CONTINUING, "forget: same id ⇒ CONTINUING")
	it.forget(0)
	_check(it.classify(0, s).kind == InterpClass.Kind.NEW_STEP, "after forget(), same step_id ⇒ NEW_STEP again")
