extends RefCounted

## Manages distort movement (QueueDistortAnim) for abilities like Dash.
##
## Applies a temporary visual offset that LERPs between positions over
## a given number of animation frames. The GPU remains source of truth
## for unit position; this offset is purely visual.
## Vault: [[SEQ Movement Opcodes]]

# Distance factors for movement types
const RigDebug = preload("res://addons/exmateria_sprite_rig/install/RigDebug.gd")
const CHARGE_DISTANCE_FACTOR: float = 0.9   # How close to get to target (type 2)
const STEP_BACK_DISTANCE_FACTOR: float = 0.3 # How far to step back (type 13)

# Movement type constants (from FFT wiki)
const TYPE_SLIDE_TO_TARGET: int = 2   # handler 4: Slide to target
const TYPE_SLIDE_TO_HOME: int = 3     # handler 5: Slide back to home
const TYPE_STEP_BACK: int = 13        # handler 15: Wind-up step backward

var _active: bool = false
var _type: int = 0
var _total_frames: int = 0
var _elapsed_frames: int = 0
var _start_offset: Vector3 = Vector3.ZERO
var _target_offset: Vector3 = Vector3.ZERO
var _current_offset: Vector3 = Vector3.ZERO


func start(type: int, frame_count: int, home_pos: Vector3, target_pos: Vector3) -> void:
	"""Begin a distort movement.

	Args:
		type: Movement type (2=charge, 3=return, 13=step-back)
		frame_count: Duration in animation frames
		home_pos: Unit's home tile world position
		target_pos: Target unit's tile world position
	"""
	_type = type
	_total_frames = maxi(frame_count, 1)
	_elapsed_frames = 0
	_start_offset = _current_offset  # Chain from current offset
	_active = true

	var direction = (target_pos - home_pos)

	match type:
		TYPE_SLIDE_TO_TARGET:
			_target_offset = direction * CHARGE_DISTANCE_FACTOR
		TYPE_SLIDE_TO_HOME:
			_target_offset = Vector3.ZERO
		TYPE_STEP_BACK:
			# Step away from target (opposite direction)
			if direction.length_squared() > 0.001:
				_target_offset = -direction.normalized() * direction.length() * STEP_BACK_DISTANCE_FACTOR
			else:
				_target_offset = Vector3.ZERO
		_:
			push_warning("[DistortMovement] Unknown type %d - completing instantly" % type)
			_target_offset = _start_offset
			_active = false

	if RigDebug.iteration():
		print("[DistortMovement] start type=%d frames=%d start=%s target=%s" % [
			type, frame_count, str(_start_offset), str(_target_offset)])


func advance_frame() -> void:
	"""Advance one animation frame. Call at animation tick rate."""
	if not _active:
		return

	_elapsed_frames += 1
	var t = clampf(float(_elapsed_frames) / float(_total_frames), 0.0, 1.0)
	_current_offset = _start_offset.lerp(_target_offset, t)

	if _elapsed_frames >= _total_frames:
		_current_offset = _target_offset
		_active = false
		if RigDebug.iteration():
			print("[DistortMovement] complete type=%d final_offset=%s" % [_type, str(_current_offset)])


func get_offset() -> Vector3:
	"""Return current visual offset from home position."""
	return _current_offset


func is_active() -> bool:
	"""Whether a movement is currently in progress."""
	return _active


func reset() -> void:
	"""Clear all state, set offset to zero."""
	_active = false
	_type = 0
	_total_frames = 0
	_elapsed_frames = 0
	_start_offset = Vector3.ZERO
	_target_offset = Vector3.ZERO
	_current_offset = Vector3.ZERO
