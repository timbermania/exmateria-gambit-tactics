extends RefCounted

## Minimal per-layer animation frame state, advanced one frame at a time.
##
## Uses integer frame counting for deterministic, PSX-faithful animation.
## Time ownership — the delta→frames accumulator, the tick-vs-delta mode, and
## the speed multiplier — lives in AnimationClock (ADR-0020), the one clock per
## unit. This object just holds a frame counter and steps it via advance_frame().
## Vault: [[SEQ Movement Opcodes]]
## Vault: [[TRAP Sprite Effect System]]
## Vault: [[Unit Sprite Render Pipeline]]
## Vault: [[Unit Sprite SEQ Opcodes]]

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const AnimationFrameCalculator = preload("res://addons/exmateria_sprite_rig/sequence/AnimationFrameCalculator.gd")

## `AnimationOpcodes` is `addons/exmateria_sprite_rig`'s now, published on the
## addon's one global name; this aliases it back so every use site below keeps
## the spelling it had (ADR-0211 dec. 4, ADR-0217 dec. 6).
const RigDebug = preload("res://addons/exmateria_sprite_rig/install/RigDebug.gd")
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const SpriteLayer = ExMateriaSchema.SpriteLayer.Kind

const FRAME_DURATION: float = 1.0 / 45.0  # 45 fps = ~0.0222 seconds per frame

var anim_id: String = ""
var anim_frame: int = 0              # Current animation frame (integer)
var last_display_frame: int = -1     # Last frame_id sent to sprite layer
var last_processed_frame: int = 0    # For side effect detection
var is_paused: bool = false
var sequences: Dictionary            # Reference to type1_seq/wep1_seq/etc
var _completion_emitted: bool = false  # Prevent multiple completion signals

# Distort movement state (QueueDistortAnim / WaitForDistort opcodes)
var _waiting_for_distort: bool = false
var distort_controller = null  # DistortMovementController, set by Unit

# SEQ movement opcode state (pixel-space nudges for attack wind-up/lunge/settle)
var _move_offset: Vector2 = Vector2.ZERO  # Accumulated pixel offset from Move opcodes

signal frame_changed(frame_id: int)
signal side_effect(effect_type: int, params: Dictionary)
signal animation_complete()
signal animation_paused()
signal distort_requested(type: int, frame_count: int)
signal move_offset_changed(offset: Vector2)


## Start playing an animation.
##
## Args:
##     new_anim_id: Animation hex ID to play
##     seqs: Reference to sequences dictionary (type1_seq, wep1_seq, etc.)
##     start_frame: Optional frame to start at (for camera sync)
func start(new_anim_id: String, seqs: Dictionary, start_frame: int = 0) -> void:
	anim_id = new_anim_id
	sequences = seqs
	anim_frame = start_frame
	last_display_frame = -1
	# Use start_frame - 1 so side effects at exactly start_frame are captured.
	# This is critical for opcodes like QueueSpriteAnim that appear at t=0
	# BEFORE any LoadFrameWait in the animation sequence.
	last_processed_frame = start_frame - 1
	is_paused = false
	_completion_emitted = false
	_waiting_for_distort = false
	_move_offset = Vector2.ZERO

	# DEBUG: Log animation start with opcode details
	if RigDebug.iteration():
		var opcodes = seqs.get(new_anim_id, [])
		var duration = AnimationFrameCalculator.get_duration(new_anim_id, seqs)
		var is_loop = AnimationFrameCalculator.is_looping(new_anim_id, seqs)
		var is_hold = AnimationFrameCalculator.is_hold_forever(new_anim_id, seqs)
		print("[PLAYBACK_DEBUG] start anim_id='%s' start_frame=%d duration=%d is_loop=%s is_hold=%s opcodes=%d" % [
			new_anim_id, start_frame, duration, str(is_loop), str(is_hold), opcodes.size()])
		for i in range(opcodes.size()):
			var op = opcodes[i]
			print("[PLAYBACK_DEBUG]   [%d] %s p0=%s p1=%s p2=%s" % [
				i, op.get("op_code_name", "?"),
				str(op.get("op_code_param_0", "")),
				str(op.get("op_code_param_1", "")),
				str(op.get("op_code_param_2", ""))])


## Stop the current animation.
func stop() -> void:
	anim_id = ""
	anim_frame = 0
	is_paused = false


## Force animation to complete (called on unit death).
##
## Emits animation_paused so any awaiting systems are unblocked.
## Does nothing if animation already completed or no animation is playing.
func force_complete() -> void:
	if not _completion_emitted and not anim_id.is_empty():
		_completion_emitted = true
		is_paused = true
		_waiting_for_distort = false
		animation_paused.emit()


## Get the current display frame ID.
##
## Returns:
##     frame_id that should be displayed
func get_current_frame() -> int:
	if anim_id.is_empty():
		return 0
	return AnimationFrameCalculator.get_frame_at(anim_id, anim_frame, sequences)


## Advance animation by exactly one frame.
##
## The AnimationClock calls this once per elapsed frame — once per GPU tick in
## tick mode, or once per accumulated FRAME_DURATION in delta mode — so the
## whole ensemble steps in lockstep with the sim (ADR-0020).
func advance_frame() -> void:
	if anim_id.is_empty() or is_paused:
		return

	# Advance distort controller in lockstep with animation ticks
	if distort_controller and distort_controller.is_active():
		distort_controller.advance_frame()

	# Stall while waiting for distort movement to complete
	if _waiting_for_distort:
		if distort_controller == null or not distort_controller.is_active():
			_waiting_for_distort = false
		else:
			return  # Stall - don't advance frames

	var duration = AnimationFrameCalculator.get_duration(anim_id, sequences)
	var loops = AnimationFrameCalculator.is_looping(anim_id, sequences)

	anim_frame += 1

	if loops and anim_frame >= duration:
		anim_frame = 0
		last_processed_frame = 0

	var display_frame = AnimationFrameCalculator.get_frame_at(anim_id, anim_frame, sequences)
	if display_frame != last_display_frame:
		last_display_frame = display_frame
		frame_changed.emit(display_frame)

	_process_side_effects(last_processed_frame, anim_frame)
	if _waiting_for_distort:
		# Don't advance last_processed_frame — when stall clears, we re-process
		# the same range so opcodes after WaitForDistort (e.g., QueueDistortAnim) fire
		return
	last_processed_frame = anim_frame

	if not loops and anim_frame >= duration and not _completion_emitted:
		_completion_emitted = true
		var is_hold_forever = AnimationFrameCalculator.is_hold_forever(anim_id, sequences)
		if AnimationFrameCalculator.has_pause(anim_id, sequences) or is_hold_forever:
			is_paused = true
			animation_paused.emit()
		else:
			animation_complete.emit()


## Process side effects that occur between from_frame and to_frame.
##
## Side effects fire exactly once when we cross their trigger frame.
## Uses integer range (from_frame, to_frame] for precise detection.
## Fixed-increment movement opcode offsets (x_delta, y_delta).
const _FIXED_MOVE_OFFSETS: Dictionary = {
	AnimationOpcodes.Op.MOVE_FORWARD_1: Vector2(-1, 0),
	AnimationOpcodes.Op.MOVE_FORWARD_2: Vector2(-2, 0),
	AnimationOpcodes.Op.MOVE_BACKWARD_1: Vector2(1, 0),
	AnimationOpcodes.Op.MOVE_BACKWARD_2: Vector2(2, 0),
	AnimationOpcodes.Op.MOVE_UP_1: Vector2(0, -1),
	AnimationOpcodes.Op.MOVE_UP_2: Vector2(0, -2),
	AnimationOpcodes.Op.MOVE_DOWN_1: Vector2(0, 1),
	AnimationOpcodes.Op.MOVE_DOWN_2: Vector2(0, 2),
}

func _process_side_effects(from_frame: int, to_frame: int) -> void:
	if from_frame == to_frame:
		return

	var opcodes = sequences.get(anim_id, [])
	var t: int = 0

	for op in opcodes:
		var op_id: int = op.get("op_code_id", 0)

		if op_id == AnimationOpcodes.Op.LOAD_FRAME_WAIT:
			t += op.get("op_code_param_1", 0)
		elif op_id == AnimationOpcodes.Op.QUEUE_SPRITE_ANIM:
			if t > from_frame and t <= to_frame:
				var layer_param = op.get("op_code_param_0", 0)
				var layer: SpriteLayer = SpriteLayer.WEP1 if layer_param == 1 else SpriteLayer.EFF1
				var target_anim = str(int(op.get("op_code_param_1", 0)))
				side_effect.emit(AnimationOpcodes.SideEffect.QUEUE_SPRITE_ANIM, {"layer": layer, "anim_id": target_anim})
		elif op_id == AnimationOpcodes.Op.SET_LAYER_PRIORITY:
			if t > from_frame and t <= to_frame:
				var priority = op.get("op_code_param_0", 0)
				side_effect.emit(AnimationOpcodes.SideEffect.SET_LAYER_PRIORITY, {"priority": priority})
		elif op_id == AnimationOpcodes.Op.POST_GENERIC_ATTACK:
			if t > from_frame and t <= to_frame:
				side_effect.emit(AnimationOpcodes.SideEffect.POST_GENERIC_ATTACK, {})
		elif op_id == AnimationOpcodes.Op.QUEUE_THROW_ANIMATION:
			if t > from_frame and t <= to_frame:
				var param0 = op.get("op_code_param_0", 0)
				var param1 = op.get("op_code_param_1", 0)
				side_effect.emit(AnimationOpcodes.SideEffect.QUEUE_THROW_ANIMATION, {"param0": param0, "param1": param1})
		elif op_id == AnimationOpcodes.Op.QUEUE_DISTORT_ANIM:
			if t > from_frame and t <= to_frame:
				var move_type = op.get("op_code_param_0", 0)
				var frame_count = op.get("op_code_param_1", 0)
				distort_requested.emit(move_type, frame_count)
		elif op_id == AnimationOpcodes.Op.WAIT_FOR_DISTORT:
			if t > from_frame and t <= to_frame:
				if distort_controller and distort_controller.is_active():
					_waiting_for_distort = true
					return  # Stop processing — no opcodes after WaitForDistort should fire until stall clears
		elif _FIXED_MOVE_OFFSETS.has(op_id):
			# Fixed-increment movement opcodes (MoveForward1/2, MoveBackward1/2, MoveUp1/2, MoveDown1/2)
			if t > from_frame and t <= to_frame:
				_move_offset += _FIXED_MOVE_OFFSETS[op_id]
				move_offset_changed.emit(_move_offset)
		# Parameterized movement opcodes (signed byte parameters)
		elif op_id == AnimationOpcodes.Op.MOVE_UNIT_FB:
			if t > from_frame and t <= to_frame:
				_move_offset.x -= _to_signed_byte(int(op.get("op_code_param_0", 0)))
				move_offset_changed.emit(_move_offset)
		elif op_id == AnimationOpcodes.Op.MOVE_UNIT_DU:
			if t > from_frame and t <= to_frame:
				_move_offset.y += _to_signed_byte(int(op.get("op_code_param_0", 0)))
				move_offset_changed.emit(_move_offset)
		elif op_id == AnimationOpcodes.Op.MOVE_UNIT_RL:
			if t > from_frame and t <= to_frame:
				_move_offset.x += _to_signed_byte(int(op.get("op_code_param_0", 0)))
				move_offset_changed.emit(_move_offset)
		elif op_id == AnimationOpcodes.Op.MOVE_UNIT_RLDU_FB:
			if t > from_frame and t <= to_frame:
				_move_offset.x += _to_signed_byte(int(op.get("op_code_param_0", 0)))  # RL
				_move_offset.y += _to_signed_byte(int(op.get("op_code_param_1", 0)))  # DU
				_move_offset.x -= _to_signed_byte(int(op.get("op_code_param_2", 0)))  # FB
				move_offset_changed.emit(_move_offset)


static func _to_signed_byte(value: int) -> int:
	"""Convert unsigned byte (0-255) to signed (-128 to 127)."""
	return value if value < 128 else value - 256
