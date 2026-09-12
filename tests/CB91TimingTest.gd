extends Node3D
## CB91 Timing Test - Measures ball spawn, convergence, and palette flash timing
## for E317 (Choco Ball) to diagnose flash-vs-convergence desync.
##
## Spawns caster + target, auto-plays E317, monitors palette tint and callback
## state, prints timing summary, and quits 2s after convergence.

const EffectInstanceClass = ExMateriaEffects.EffectInstance

@onready var map: Node3D = $ProceduralMap

var _caster: Unit
var _target: Unit
var _current_effect: Node = null

# Configurable unit positions
var caster_pos := Vector2i(4, 6)
var target_pos := Vector2i(7, 6)

# Timing tracking
var _process_frame: int = 0
var _flash_frame: int = -1  # effect_frame when palette tint first goes non-black
var _bright_flash_frame: int = -1  # effect_frame when bright hit flash fires (rgb > 200)
var _max_tint: float = 0.0  # Track max brightness seen
var _max_tint_frame: int = -1
var _converge_detected: bool = false
var _all_dead: bool = false
var _callbacks_seen_active: bool = false  # Must see active before checking for dead
var _callbacks_active_frame: int = -1  # effect_frame when callbacks first became active
var _effect_started: bool = false


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a timing PROBE for E317 flash-vs-convergence desync — it prints a timing summary and asserts nothing")
	# Wait for map
	await get_tree().process_frame
	await get_tree().process_frame

	map.change_map("MAP042")
	await get_tree().process_frame

	# Spawn units
	await _spawn_units()

	# Rotate camera to match EffectViewer
	var cam = get_node_or_null("PlayerCamera")
	if cam:
		cam.y_target_rot = 135.0
		cam.rotation_settled = false

	# Enable particle debug for convergence logging
	DebugConfig.particle_debug_enabled = true
	DebugConfig.timeline_debug_enabled = true

	# Auto-play E317
	await get_tree().process_frame
	_play_e317()


func _spawn_units() -> void:
	var unit_scene = load("res://assets/scenes/Unit.tscn")

	_caster = unit_scene.instantiate()
	_caster.name = "Caster"
	add_child(_caster)
	await get_tree().process_frame
	_caster.body_sprite_id = 0x01
	_caster.place_on_tile(caster_pos.x, caster_pos.y, map)

	_target = unit_scene.instantiate()
	_target.name = "Target"
	add_child(_target)
	await get_tree().process_frame
	_target.body_sprite_id = 0x80
	_target.place_on_tile(target_pos.x, target_pos.y, map)

	_caster.face_toward_unit(_target)
	_target.face_toward_unit(_caster)


func _play_e317() -> void:
	var effect = EffectInstanceClass.new()
	get_viewport().add_child(effect)

	var caster_world = _caster.global_position
	var target_world = _target.global_position

	var success = effect.initialize("E317", "res://assets/effects/E317", caster_world, 512)
	if not success:
		print("[CB91_TEST] ERROR: Failed to load E317")
		effect.queue_free()
		return

	effect.global_position = caster_world
	var target_offset = target_world - caster_world

	effect.set_anchors(target_offset, target_offset, Vector3.ZERO, target_offset)
	effect.set_unit_targets(_caster, _target)
	effect.attach_anchors_to_units(_caster, _target)
	effect.auto_loop = false

	_current_effect = effect
	_effect_started = true

	var tile_dist = (target_pos - caster_pos).length()
	var world_dist = caster_world.distance_to(target_world)
	print("[CB91_TEST] === EFFECT STARTED ===")
	print("[CB91_TEST] Caster: tile(%d,%d) world=%s" % [caster_pos.x, caster_pos.y, caster_world])
	print("[CB91_TEST] Target: tile(%d,%d) world=%s" % [target_pos.x, target_pos.y, target_world])
	print("[CB91_TEST] Unit distance: %.1f tiles (%.2f godot units)" % [tile_dist, world_dist])


func _process(_delta: float) -> void:
	if not _effect_started or not is_instance_valid(_current_effect):
		return

	_process_frame += 1

	# Log palette tint every frame it's non-black to find exact flash timing. The
	# palette subsystem is declarative now (ADR-0067): build its affected_units
	# ColorStack and read the tint as the fold's deviation from a mid-grey probe.
	if _current_effect.palette_controller:
		var effect_frame = _current_effect.get_effect_frame()
		var probe := Vector3(0.5, 0.5, 0.5)
		var folded: Vector3 = _current_effect.palette_controller \
			.build_stack("affected_units").fold(probe, 0, effect_frame)
		var tint := Color(folded.x - probe.x, folded.y - probe.y, folded.z - probe.z)
		if tint != Color.BLACK:
			var brightness: float = maxf(tint.r, maxf(tint.g, tint.b))
			print("[CB91_TINT] ef=%d tint=(%.3f, %.3f, %.3f) bright=%.3f" % [
				effect_frame, tint.r, tint.g, tint.b, brightness])
			if _flash_frame < 0:
				_flash_frame = effect_frame
			if brightness > _max_tint:
				_max_tint = brightness
				_max_tint_frame = effect_frame

	# Check if callback has finished (all projectiles dead)
	# Must see callbacks active first — has_active_callbacks() is false both before
	# callbacks start (INACTIVE) and after they finish, so we track the transition.
	if not _all_dead and _current_effect.callback_manager:
		var has_active = _current_effect.callback_manager.has_active_callbacks()
		if has_active:
			if not _callbacks_seen_active:
				_callbacks_seen_active = true
				_callbacks_active_frame = _current_effect.get_effect_frame()
				print("[CB91_TEST] CALLBACKS ACTIVE at process_frame=%d effect_frame=%d" % [
					_process_frame, _callbacks_active_frame])
		elif _callbacks_seen_active:
			_all_dead = true
			var effect_frame = _current_effect.get_effect_frame()
			print("[CB91_TEST] ALL CALLBACKS INACTIVE at process_frame=%d effect_frame=%d" % [
				_process_frame, effect_frame])
			_print_summary()
			_schedule_quit()


func _print_summary() -> void:
	print("[CB91_TEST] === TIMING SUMMARY ===")
	var tile_dist = (target_pos - caster_pos).length()
	var world_dist = _caster.global_position.distance_to(_target.global_position) if is_instance_valid(_caster) and is_instance_valid(_target) else -1.0
	print("[CB91_TEST] Unit distance: %.1f tiles (%.2f godot units)" % [tile_dist, world_dist])
	if _flash_frame >= 0:
		print("[CB91_TEST] First non-black tint at effect_frame=%d" % _flash_frame)
	else:
		print("[CB91_TEST] Palette tint: NOT DETECTED")
	if _max_tint_frame >= 0:
		print("[CB91_TEST] Peak tint at effect_frame=%d (brightness=%.3f)" % [_max_tint_frame, _max_tint])
	if _callbacks_active_frame >= 0:
		print("[CB91_TEST] CB91 fired at effect_frame=%d" % _callbacks_active_frame)
		var converge_est: int = _callbacks_active_frame + 25
		print("[CB91_TEST] Convergence estimate: effect_frame=%d (fire %d + lifetime 25)" % [
			converge_est, _callbacks_active_frame])
	var dead_ef: int = _current_effect.get_effect_frame() if is_instance_valid(_current_effect) else -1
	print("[CB91_TEST] All callbacks dead at effect_frame=%d" % dead_ef)
	if _max_tint_frame >= 0 and _callbacks_active_frame >= 0:
		var converge_est: int = _callbacks_active_frame + 25
		var gap: int = converge_est - _max_tint_frame
		print("[CB91_TEST] Convergence-to-peak-flash gap: %d effect frames" % gap)
	print("[CB91_TEST] === END SUMMARY ===")


func _schedule_quit() -> void:
	await get_tree().create_timer(2.0).timeout
	print("[CB91_TEST] Exiting.")
	get_tree().quit()
