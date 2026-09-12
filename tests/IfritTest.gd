extends Node3D
## Ifrit (E067) Callback Test — monitors CB19 tube lifecycle

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
var _polling: bool = false

var caster_pos := Vector2i(3, 5)
var target_pos := Vector2i(7, 7)


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a callback PROBE — it monitors the E067 CB19 tube lifecycle and prints it; it asserts nothing")
	DebugConfig.camera_debug_enabled = false

	await get_tree().process_frame
	await get_tree().process_frame

	map.change_map("MAP042")
	await get_tree().process_frame

	await _spawn_units()

	var cam = get_node_or_null("PlayerCamera")
	if cam:
		cam.y_target_rot = 135.0
		cam.rotation_settled = false

	await get_tree().create_timer(3.0).timeout
	_play_effect()


func _spawn_units() -> void:
	var unit_scene = load("res://assets/scenes/Unit.tscn")
	_caster = unit_scene.instantiate()
	_caster.name = "Caster"
	add_child(_caster)
	await get_tree().process_frame
	_caster.place_on_tile(caster_pos.x, caster_pos.y, map)
	_target = unit_scene.instantiate()
	_target.name = "Target"
	add_child(_target)
	await get_tree().process_frame
	_target.body_sprite_id = 0x80
	_target.place_on_tile(target_pos.x, target_pos.y, map)
	_caster.face_toward_unit(_target)
	_target.face_toward_unit(_caster)


func _play_effect() -> void:
	var effect = EffectInstanceClass.new()
	get_viewport().add_child(effect)

	effect.camera_started.connect(_on_camera_started)
	effect.camera_finished.connect(_on_camera_finished)

	_current_effect = effect

	if map and map.dynamic_geo_builder:
		var bounds: Rect2i = map.dynamic_geo_builder.map_bounds
		effect.map_center_godot = Vector3(float(bounds.size.x) / 2.0, 0.0, float(bounds.size.y) / 2.0)

	var caster_world = _caster.global_position
	var target_world = _target.global_position

	var success = effect.initialize("E067", "res://assets/effects/E067", caster_world, 512)
	if not success:
		print("[IFRIT] ERROR: Failed to load E067")
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

	print("[IFRIT] === E067 IFRIT TEST ===")
	_poll_completion(effect)


func _poll_completion(effect: Node) -> void:
	_polling = true
	await get_tree().create_timer(0.5).timeout

	var poll_count = 0
	var saw_particles = false
	var last_cb_log_frame = -10
	while is_instance_valid(effect) and effect == _current_effect and _polling:
		var count = effect.get_active_particle_count()
		var frame = effect.get_effect_frame()
		poll_count += 1
		if count > 0:
			saw_particles = true

		# Monitor ALL callbacks every 30 frames
		if frame - last_cb_log_frame >= 30 and effect.callback_manager:
			last_cb_log_frame = frame
			for child in effect.callback_manager.get_children():
				if child is Node3D and child.has_method("is_active"):
					var script_name = child.get_script().get_path().get_file() if child.get_script() else "?"
					var has_mesh = false
					var surfaces = 0
					for sc in child.get_children():
						if sc is MeshInstance3D and sc.mesh:
							has_mesh = true
							surfaces = sc.mesh.get_surface_count()
					print("[IFRIT] f=%d %s state=%d active=%s surfaces=%d particles=%d" % [
						frame, script_name, child.state, child.is_active(), surfaces, count])

		if count == 0 and saw_particles and frame > 50:
			# Log final callback state
			if effect.callback_manager:
				for child in effect.callback_manager.get_children():
					if child is Node3D and child.has_method("is_active"):
						var script_name = child.get_script().get_path().get_file() if child.get_script() else "?"
						var surfaces = 0
						for sc in child.get_children():
							if sc is MeshInstance3D and sc.mesh:
								surfaces = sc.mesh.get_surface_count()
						print("[IFRIT] FINAL f=%d %s state=%d active=%s surfaces=%d" % [
							frame, script_name, child.state, child.is_active(), surfaces])
			_on_effect_done()
			return
		if poll_count > 600:
			print("[IFRIT] Timeout f=%d" % frame)
			_on_effect_done()
			return
		await get_tree().create_timer(0.1).timeout


func _on_effect_done() -> void:
	_polling = false
	print("[IFRIT] === EFFECT COMPLETE ===")
	var cam = get_node_or_null("PlayerCamera")
	if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
		cam.release_takeover()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _on_camera_started() -> void:
	var cam = get_node_or_null("PlayerCamera")
	if not cam:
		return
	cam.request_takeover(self)
	if _current_effect and _current_effect.camera_controller:
		var ctrl = _current_effect.camera_controller
		ctrl.saved_position = PsxChirality.godot_position_to_psx(cam.global_position)
		ctrl.saved_angles = Vector3(
			PsxMagnitude.deg_to_angle(-cam._saved_x_rot),
			PsxMagnitude.deg_to_angle(cam._saved_y_rot + 360.0), 0)
		ctrl.saved_zoom = CameraCalibration.ortho_size_to_zoom(cam._saved_camera_size)
		ctrl.current_position = ctrl.saved_position
		ctrl.current_angles = ctrl.saved_angles
		ctrl.current_zoom = ctrl.saved_zoom
		if map and map.dynamic_geo_builder:
			var bounds: Rect2i = map.dynamic_geo_builder.map_bounds
			ctrl.map_center = Vector3(float(bounds.size.x) * 14.0, 0.0, float(bounds.size.y) * 14.0)


func _on_camera_finished() -> void:
	var cam = get_node_or_null("PlayerCamera")
	if cam and cam.camera_mode == cam.CameraMode.TAKEOVER:
		cam.release_takeover()


func _process(_delta: float) -> void:
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
