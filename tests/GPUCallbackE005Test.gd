extends Node3D
## Test scene for E005 (Fire) callbacks — auto-plays with camera tracks enabled.
##
## IT ENDS ON ITS OWN (#504). `_on_effect_finished()` used to wait 1 s and call the play
## function again, unconditionally — an infinite replay loop with no exit condition, so
## any run that selected this scene paid the full `timeout 360` and scored HUNG. A rig is
## allowed to assert nothing; it is not allowed to hang. It now replays under a TOTAL_TIME
## budget and quits, printing how many plays it got through.
##
## Touch any key and the budget is cancelled — watching the callbacks and the camera track
## by eye is what the rig is for, and it must not be cut off mid-look.

## ADR-0212 dec. 1 — `addons/exmateria_platform` publishes one global,
## `ExMateriaPlatform`; aliasing a member back keeps every use site below
## spelled the way it was (ADR-0211 dec. 4). The PSX trio arrived at
## extraction #7 (#1220) and lost its three bare `class_name`s on the way.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude
const CameraCalibration = ExMateriaPlatform.CameraCalibration
const PsxChirality = ExMateriaPlatform.PsxChirality


const EffectInstanceClass = ExMateriaEffects.EffectInstance

@onready var map: Node3D = $ProceduralMap

var _caster: Unit
var _target: Unit
var _current_effect: Node = null

## Unattended budget — the exit condition the replay loop never had. A key press hands
## the session to the human and cancels it.
## WALL CLOCK, deliberately, and not `delta`. The budget exists to bound this scene
## under the runner's `timeout 360`, and `delta` is not a bound on real time:
## GPUCombatTestBase sets `Engine.time_scale = test_time_scale` (4.0 by default), so a
## delta-summed budget runs 4x fast there and 4x SLOW at time_scale 0.25 — the direction
## that would walk straight back into a hang.
const TOTAL_TIME := 60.0
var _t0_ms := Time.get_ticks_msec()
var _manual := false
var _play_count := 0

const DEFAULT_CASTER_POS := Vector2i(4, 6)
const DEFAULT_TARGET_POS := Vector2i(7, 6)


func _ready() -> void:
	# #463/#504: a rig, not a test. Declared FIRST so it is on the record whatever the
	# load below does. The verdict reader scores it NOT_A_TEST — see tests/lib/verdict.sh.
	print("[NOT_A_TEST] a by-eye E005 callback/camera-track rig — it replays the effect and prints callback and camera telemetry for a human, and asserts nothing; named *Test, but it is a rig")
	await get_tree().process_frame
	await get_tree().process_frame

	map.change_map("MAP042")
	await get_tree().process_frame

	await _spawn_units()

	var cam = get_node_or_null("PlayerCamera")
	if cam:
		cam.y_target_rot = 135.0
		cam.rotation_settled = false

	# Enable timeline debug logging for CB16 diagnostics
	DebugConfig.timeline_debug_enabled = true
	# Enable camera debug logging for angle bug investigation
	DebugConfig.camera_debug_enabled = true
	# Enable particle debug logging for mid-life child spawning diagnostics
	DebugConfig.particle_debug_enabled = true

	await get_tree().create_timer(0.5).timeout
	_play_e065()


func _spawn_units() -> void:
	var unit_scene = load("res://assets/scenes/Unit.tscn")

	_caster = unit_scene.instantiate()
	_caster.name = "Caster"
	add_child(_caster)
	await get_tree().process_frame
	_caster.body_sprite_id = 0x01
	_relocate_unit(_caster, DEFAULT_CASTER_POS)

	_target = unit_scene.instantiate()
	_target.name = "Target"
	add_child(_target)
	await get_tree().process_frame
	_target.body_sprite_id = 0x80
	_relocate_unit(_target, DEFAULT_TARGET_POS)

	_caster.face_toward_unit(_target)
	_target.face_toward_unit(_caster)


func _relocate_unit(unit: Unit, pos: Vector2i) -> void:
	if not unit or not is_instance_valid(unit):
		return
	if unit.place_on_tile(pos.x, pos.y, map):
		return
	unit.place_on_tile(0, 0, map)


func _play_e065() -> void:
	if _current_effect and is_instance_valid(_current_effect):
		_current_effect.queue_free()
		_current_effect = null

	var effect_id_str := "E005"
	var effect_path := "res://assets/effects/E005"

	var effect = EffectInstanceClass.new()
	get_viewport().add_child(effect)
	_current_effect = effect

	effect.camera_started.connect(_on_camera_started)
	effect.camera_finished.connect(_on_camera_finished)

	var caster_pos := _caster.global_position
	var target_pos := _target.global_position

	var success = effect.initialize(effect_id_str, effect_path, caster_pos, 512)
	if not success:
		print("[E005 Test] Failed to load effect")
		effect.queue_free()
		_current_effect = null
		return

	effect.global_position = caster_pos
	var target_offset := target_pos - caster_pos

	effect.set_anchors(target_offset, target_offset, Vector3.ZERO, target_offset)
	effect.set_unit_targets(_caster, _target)
	effect.attach_anchors_to_units(_caster, _target)
	effect.auto_loop = false

	effect.effect_finished.connect(_on_effect_finished)
	print("[E005 Test] Playing Fire effect effect")


func _on_camera_started() -> void:
	var cam = get_node_or_null("PlayerCamera")
	if not cam:
		return
	cam.request_takeover(self)
	# Save current camera state as SLOT_COPY reference
	if _current_effect and _current_effect.camera_controller:
		var ctrl = _current_effect.camera_controller
		ctrl.saved_position = PsxChirality.godot_position_to_psx(cam.global_position)
		ctrl.saved_angles = Vector3(
			PsxMagnitude.deg_to_angle(-cam._saved_x_rot),
			PsxMagnitude.deg_to_angle(cam._saved_y_rot + 360.0),
			0)
		ctrl.saved_zoom = CameraCalibration.ortho_size_to_zoom(cam._saved_camera_size)
		ctrl.current_position = ctrl.saved_position
		ctrl.current_angles = ctrl.saved_angles
		ctrl.current_zoom = ctrl.saved_zoom


func _on_camera_finished() -> void:
	var cam = get_node_or_null("PlayerCamera")
	if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
		cam.release_takeover()


func _on_effect_finished() -> void:
	_play_count += 1
	print("[E005 Test] Effect finished — replaying in 1s")
	await get_tree().create_timer(1.0).timeout
	_play_e065()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_manual = true


func _process(_delta: float) -> void:
	# Budget FIRST — it must still fire on the frames where there is no live effect to
	# inspect, which is exactly where the early return below lands.
	var elapsed := float(Time.get_ticks_msec() - _t0_ms) / 1000.0
	if not _manual and elapsed >= TOTAL_TIME:
		print("[E005 Test] done — %d full plays in %.0fs" % [_play_count, elapsed])
		get_tree().quit(0)
		return
	if not _current_effect or not is_instance_valid(_current_effect):
		return
	# Log callback states every 60 frames
	if Engine.get_process_frames() % 60 == 0:
		if _current_effect.has_method("get_callback_debug_info"):
			print(_current_effect.get_callback_debug_info())
		elif _current_effect.get("callback_manager"):
			var mgr = _current_effect.callback_manager
			if mgr and mgr.has_method("get_debug_info"):
				print(mgr.get_debug_info())
	# Log camera angles every 30 frames for angle bug investigation
	if Engine.get_process_frames() % 30 == 0:
		if _current_effect.get("camera_controller"):
			var ctrl = _current_effect.camera_controller
			if ctrl:
				print("[E005 CAM] angles=%s pos=%s zoom=%.1f" % [str(ctrl.current_angles), str(ctrl.current_position), ctrl.current_zoom])
	# Apply camera controller output to PlayerCamera
	if not _current_effect.camera_controller or not _current_effect.camera_controller.is_active():
		return
	var cam = get_node_or_null("PlayerCamera")
	if not cam or cam.camera_mode != cam.CameraMode.TAKEOVER:
		return
	var ctrl = _current_effect.camera_controller
	var pos = PsxChirality.psx_position_to_godot(ctrl.current_position)
	var rot = PsxChirality.psx_angles_to_godot_rotation(
		ctrl.current_angles.x, ctrl.current_angles.y, ctrl.current_angles.z)
	var ortho_size = CameraCalibration.zoom_to_ortho_size(ctrl.current_zoom)
	cam.apply_takeover(pos, rot, ortho_size)
