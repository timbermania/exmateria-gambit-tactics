extends Node3D
## Test scene for E065 (Shiva) callbacks — auto-plays with camera tracks enabled.
##
## IT ENDS ON ITS OWN (#504). `_on_effect_finished()` used to wait 1 s and call the play
## function again, unconditionally — an infinite replay loop with no exit condition, so
## any run that selected this scene paid the full `timeout 360` and scored HUNG. A rig is
## allowed to assert nothing; it is not allowed to hang. It now replays under a TOTAL_TIME
## budget and quits, printing how many plays it got through.
##
## Touch any key and the budget is cancelled — watching the callbacks and the camera track
## by eye is what the rig is for, and it must not be cut off mid-look.

const EffectEmitter = ExMateriaEffects.EffectEmitter

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
	print("[NOT_A_TEST] a by-eye E065 callback/camera-track rig — it replays the effect and prints callback and camera telemetry for a human, and asserts nothing; named *Test, but it is a rig")
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

	var effect_id_str := "E065"
	var effect_path := "res://assets/effects/E065"

	var effect = EffectInstanceClass.new()
	get_viewport().add_child(effect)
	_current_effect = effect

	effect.camera_started.connect(_on_camera_started)
	effect.camera_finished.connect(_on_camera_finished)

	var caster_pos := _caster.global_position
	var target_pos := _target.global_position

	var success = effect.initialize(effect_id_str, effect_path, caster_pos, 512)
	if not success:
		print("[E065 Test] Failed to load effect")
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
	print("[E065 Test] Playing Shiva effect")


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
	print("[E065 Test] Effect finished — replaying in 1s")
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
		print("[E065 Test] done — %d full plays in %.0fs" % [_play_count, elapsed])
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
				print("[E065 CAM] angles=%s pos=%s zoom=%.1f" % [str(ctrl.current_angles), str(ctrl.current_position), ctrl.current_zoom])
	# CAMERA anchor diagnostic — log every 60 frames
	if Engine.get_process_frames() % 60 == 0:
		_log_camera_anchor_debug()
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


func _log_camera_anchor_debug() -> void:
	"""Log diagnostic info for CAMERA-anchored emitters to understand positioning."""
	if not _current_effect or not is_instance_valid(_current_effect):
		return
	var manager = _current_effect.manager
	if not manager or not _current_effect.effect_data:
		return

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var effect_pos: Vector3 = _current_effect.global_position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / viewport_size.y

	# PSX screen → Godot view-plane scale
	var psx_scale_x: float = camera.size * aspect / 256.0
	var psx_scale_y: float = camera.size / 240.0
	var cam_right: Vector3 = camera.global_basis.x
	var cam_up: Vector3 = camera.global_basis.y

	# Find first CAMERA-anchored active particle
	var logged := false
	for particle in manager.get_active_particles():
		var cfg = _current_effect.effect_data.get_emitter(particle.emitter_index)
		if not cfg or cfg.get_emitter_anchor_mode() != EffectEmitter.AnchorMode.CAMERA:
			continue
		if logged:
			break
		logged = true

		var raw = cfg.raw_data
		var raw_start = raw.get("position_start", [0, 0, 0])
		var raw_end = raw.get("position_end", [0, 0, 0])

		# Current state
		var world_pos: Vector3 = effect_pos + particle.position
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var screen_center: Vector2 = viewport_size / 2.0

		print("=== CAMERA ANCHOR DEBUG (effect_frame=%d) ===" % _current_effect.get_effect_frame())
		print("  Camera: pos=%s size=%.2f" % [camera.global_position, camera.size])
		print("  Effect: pos=%s" % effect_pos)
		print("  Anchors: target=%s world=%s" % [manager.anchor_target, manager.anchor_world])
		print("  Emitter %d: raw_start=(%d, %d, %d) raw_end=(%d, %d, %d)" % [
			particle.emitter_index,
			raw_start[0], raw_start[1], raw_start[2],
			raw_end[0], raw_end[1], raw_end[2]])
		print("  Particle: local=%s world=%s" % [particle.position, world_pos])
		print("  Screen: actual=(%d, %d) center=(%d, %d) offset=(%d, %d)" % [
			screen_pos.x, screen_pos.y, screen_center.x, screen_center.y,
			screen_pos.x - screen_center.x, screen_pos.y - screen_center.y])

		# Hypothesis A: raw values as world offset from target (current behavior)
		# This is what we're already doing — particle.position = anchor_target + godot_offset
		print("  [HYP-A World offset] godot=(%.2f, %.2f, %.2f) from target" % [
			particle.position.x - manager.anchor_target.x,
			particle.position.y - manager.anchor_target.y,
			particle.position.z - manager.anchor_target.z])

		# Hypothesis B: raw values as PSX screen pixels relative to (0,0)=screen center
		# Expected world pos = target + cam_right * raw_x * scale_x + cam_up * -raw_y * scale_y
		var anchor_world_pos: Vector3 = effect_pos + manager.anchor_target
		var hyp_b_world: Vector3 = anchor_world_pos \
			+ cam_right * float(raw_end[0]) * psx_scale_x \
			+ cam_up * float(-raw_end[1]) * psx_scale_y
		var hyp_b_screen: Vector2 = camera.unproject_position(hyp_b_world)
		print("  [HYP-B Screen pixels] world=%s screen=(%d, %d) offset=(%d, %d)" % [
			hyp_b_world,
			hyp_b_screen.x, hyp_b_screen.y,
			hyp_b_screen.x - screen_center.x, hyp_b_screen.y - screen_center.y])

		# Hypothesis C: raw values as PSX screen pixels relative to (128, 120)
		var hyp_c_world: Vector3 = anchor_world_pos \
			+ cam_right * (float(raw_end[0]) - 128.0) * psx_scale_x \
			+ cam_up * (-(float(raw_end[1]) - 120.0)) * psx_scale_y
		var hyp_c_screen: Vector2 = camera.unproject_position(hyp_c_world)
		print("  [HYP-C Screen pixels+center] world=%s screen=(%d, %d) offset=(%d, %d)" % [
			hyp_c_world,
			hyp_c_screen.x, hyp_c_screen.y,
			hyp_c_screen.x - screen_center.x, hyp_c_screen.y - screen_center.y])
