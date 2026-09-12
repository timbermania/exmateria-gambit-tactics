extends Node3D
## Haste 2 Camera Test - Auto-plays E033 with camera enabled and extensive
## debug logging to diagnose camera positioning issues.

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
var _effect_started: bool = false
var _polling: bool = false

var caster_pos := Vector2i(4, 6)
var target_pos := Vector2i(4, 6)  # Self-targeting (Haste targets self)


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a debug rig — auto-plays E033 with camera logging to diagnose positioning; it asserts nothing")
	DebugConfig.camera_debug_enabled = true

	await get_tree().process_frame
	await get_tree().process_frame

	map.change_map("MAP042")
	await get_tree().process_frame

	await _spawn_units()

	var cam = get_node_or_null("PlayerCamera")
	if cam:
		cam.y_target_rot = 135.0
		cam.rotation_settled = false

	# Wait for map and units to fully load before starting effect
	await get_tree().create_timer(3.0).timeout
	_play_effect()


func _spawn_units() -> void:
	var unit_scene = load("res://assets/scenes/Unit.tscn")

	_caster = unit_scene.instantiate()
	_caster.name = "Caster"
	add_child(_caster)
	await get_tree().process_frame
	_caster.body_sprite_id = 0x01
	_caster.place_on_tile(caster_pos.x, caster_pos.y, map)

	# For self-targeting, target = caster. But create a second unit for reference.
	_target = unit_scene.instantiate()
	_target.name = "Target"
	add_child(_target)
	await get_tree().process_frame
	_target.body_sprite_id = 0x80
	_target.place_on_tile(target_pos.x, target_pos.y, map)

	_caster.face_toward_unit(_target)
	_target.face_toward_unit(_caster)


func _process(_delta: float) -> void:
	# Apply camera controller output to PlayerCamera (mirrors EffectViewerScene._process)
	if not _current_effect or not is_instance_valid(_current_effect):
		return
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


func _play_effect() -> void:
	var effect = EffectInstanceClass.new()
	get_viewport().add_child(effect)

	effect.camera_started.connect(_on_camera_started)
	effect.camera_finished.connect(_on_camera_finished)

	var caster_world = _caster.global_position
	var target_world = _target.global_position

	# Set _current_effect BEFORE initialize — camera_started signal fires during
	# initialize() and the handler needs _current_effect to set saved camera state
	_current_effect = effect

	# Set map center for CAMERA anchor before initialize
	if map and map.dynamic_geo_builder:
		var bounds: Rect2i = map.dynamic_geo_builder.map_bounds
		effect.map_center_godot = Vector3(float(bounds.size.x) / 2.0, 0.0, float(bounds.size.y) / 2.0)

	var success = effect.initialize("E033", "res://assets/effects/E033", caster_world, 512)
	if not success:
		print("[HASTE2_CAM] ERROR: Failed to load E033")
		_current_effect = null
		effect.queue_free()
		get_tree().quit()
		return

	effect.global_position = caster_world
	var target_offset = target_world - caster_world

	effect.set_anchors(target_offset, target_offset, Vector3.ZERO, target_offset)
	effect.set_unit_targets(_caster, _target)
	effect.attach_anchors_to_units(_caster, _target)
	effect.auto_loop = false
	_effect_started = true

	print("")
	print("[HASTE2_CAM] ========================================")
	print("[HASTE2_CAM] === E033 HASTE 2 CAMERA DEBUG TEST ===")
	print("[HASTE2_CAM] ========================================")
	print("[HASTE2_CAM] Caster: tile(%d,%d) godot_pos=%s" % [caster_pos.x, caster_pos.y, caster_world])
	print("[HASTE2_CAM] Target: tile(%d,%d) godot_pos=%s" % [target_pos.x, target_pos.y, target_world])
	print("[HASTE2_CAM] Caster PSX pos: %s" % PsxChirality.godot_position_to_psx(caster_world))
	print("[HASTE2_CAM] Target PSX pos: %s" % PsxChirality.godot_position_to_psx(target_world))

	# Map center for EFFECT_CTR
	var bounds: Rect2i = map.dynamic_geo_builder.map_bounds if map.dynamic_geo_builder else Rect2i()
	var map_center_psx = Vector3(float(bounds.size.x) * 14.0, 0.0, float(bounds.size.y) * 14.0)
	print("[HASTE2_CAM] Map bounds: %s  map_center_psx: %s  godot: (%.2f, 0, %.2f)" % [
		bounds, map_center_psx, map_center_psx.x / 28.0, map_center_psx.z / 28.0])
	print("")

	_poll_completion(effect)


func _poll_completion(effect: Node) -> void:
	_polling = true
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(effect) or not _polling:
		return

	var poll_count = 0
	var saw_particles = false
	while is_instance_valid(effect) and effect == _current_effect and _polling:
		var count = effect.get_active_particle_count()
		var frame = effect.get_effect_frame()

		# Log camera position vs unit position every poll
		var cam = get_node_or_null("PlayerCamera")
		if cam and poll_count % 5 == 0:
			var cam_world = cam.global_position
			var unit_world = _caster.global_position if _caster and is_instance_valid(_caster) else Vector3.ZERO
			var cam_to_unit = unit_world - cam_world
			var dist = cam_to_unit.length()
			var ctrl_pos = effect.camera_controller.current_position if effect.camera_controller else Vector3.ZERO
			var ctrl_godot = PsxChirality.psx_position_to_godot(ctrl_pos)
			print("[HASTE2_CAM] f=%d cam=(%5.1f,%5.1f,%5.1f) unit=(%5.1f,%5.1f,%5.1f) dist=%.1f | psx_target=%s godot_target=%s" % [
				frame, cam_world.x, cam_world.y, cam_world.z,
				unit_world.x, unit_world.y, unit_world.z, dist,
				ctrl_pos, ctrl_godot])

		poll_count += 1
		if count > 0:
			saw_particles = true
		if count == 0 and saw_particles and frame > 50:
			_on_effect_done()
			return
		if poll_count > 300:
			print("[HASTE2_CAM] Timeout after %d polls" % poll_count)
			_on_effect_done()
			return
		await get_tree().create_timer(0.1).timeout


func _on_effect_done() -> void:
	_polling = false
	print("[HASTE2_CAM] === EFFECT COMPLETE ===")
	var cam = get_node_or_null("PlayerCamera")
	if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
		cam.release_takeover()
	await get_tree().create_timer(1.0).timeout
	print("[HASTE2_CAM] Exiting.")
	get_tree().quit()


func _on_camera_started() -> void:
	var cam = get_node_or_null("PlayerCamera")
	if not cam:
		return
	cam.request_takeover(self)

	print("[HASTE2_CAM] Camera entering effect mode")
	print("[HASTE2_CAM]   Camera godot_pos: %s" % cam.global_position)
	print("[HASTE2_CAM]   Camera PSX pos: %s" % PsxChirality.godot_position_to_psx(cam.global_position))
	print("[HASTE2_CAM]   Saved x_rot: %.2f  y_rot: %.2f  size: %.2f" % [cam._saved_x_rot, cam._saved_y_rot, cam._saved_camera_size])

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
		# Set map center for EFFECT_CTR
		var bounds: Rect2i = map.dynamic_geo_builder.map_bounds if map.dynamic_geo_builder else Rect2i()
		ctrl.map_center = Vector3(float(bounds.size.x) * 14.0, 0.0, float(bounds.size.y) * 14.0)
		print("[HASTE2_CAM]   Saved PSX angles: %s" % ctrl.saved_angles)
		print("[HASTE2_CAM]   Saved PSX position: %s" % ctrl.saved_position)
		print("[HASTE2_CAM]   Saved PSX zoom: %.1f" % ctrl.saved_zoom)
		print("[HASTE2_CAM]   Map center PSX: %s" % ctrl.map_center)
		print("")


func _on_camera_finished() -> void:
	print("[HASTE2_CAM] Camera finished signal received")
	var cam = get_node_or_null("PlayerCamera")
	if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
		cam.release_takeover()
