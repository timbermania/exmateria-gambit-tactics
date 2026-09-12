extends Node3D
## TrapViewerScene - Scene for previewing all TRAP particle handlers.
## Spawns two units on a small map and provides a debug panel to select
## handlers and elements, with optional looping.

const TrapChargeLineEffect = ExMateriaEffects.TrapChargeLineEffect
const TrapEffect = ExMateriaEffects.TrapEffect
const TrapOrbitalEffect = ExMateriaEffects.TrapOrbitalEffect

const TrapViewerPanelClass = preload("res://src/debug/TrapViewerPanel.gd")

@onready var map: Node3D = $ProceduralMap

var _caster: Unit
var _target: Unit
var _current_effect: Node = null  # TrapEffect, TrapChargeLineEffect, or TrapOrbitalEffect
var _panel: TrapViewerPanelClass
var _looping: bool = false
var _last_handler_id: int = -1
var _last_element_id: int = 0
var _last_direction_deg: float = 0.0


func _ready() -> void:
	# Wait for map to build its default
	await get_tree().process_frame
	await get_tree().process_frame

	# Switch to MAP116 (11x11 grid)
	# #589: hand the map's two outputs to the host systems that consume them.
	# Replay-then-connect, so a map the composer auto-built in ITS `_ready`
	# (children ready before parents) is covered by the replay and every later
	# `change_map` by the connect. See BattlefieldWiring.
	BattlefieldWiring.wire_map(map)
	map.change_map("MAP116")

	# Wait for map to finish loading
	await get_tree().process_frame

	# Spawn units
	await _spawn_units()

	# Set up debug panel
	_setup_debug_panel()


func _spawn_units() -> void:
	var unit_scene = load("res://assets/scenes/Unit.tscn")

	# Caster - sprite 0x01 (Ramza, RAMUZA.SPR) at tile (4, 5). The ROM-faithful
	# sprite map starts at 0x01; 0x00 doesn't resolve to a texture.
	_caster = unit_scene.instantiate()
	_caster.name = "Caster"
	add_child(_caster)
	await get_tree().process_frame

	_caster.body_sprite_id = 0x01
	_caster.place_on_tile(4, 5, map)

	# Target - sprite 0x80 at tile (7, 5)
	_target = unit_scene.instantiate()
	_target.name = "Target"
	add_child(_target)
	await get_tree().process_frame

	_target.body_sprite_id = 0x80
	_target.place_on_tile(7, 5, map)

	# Face toward each other
	_caster.face_toward_unit(_target)
	_target.face_toward_unit(_caster)


func _setup_debug_panel() -> void:
	# The map's Skirts + Map Render panels. Mounted host-side (#555) — `MapComposer`
	# used to construct and register them itself, which is an ADR-0068 R1 violation:
	# the production owner of the tunables also instantiated their view. Placed here,
	# after the map is composed, so the pure-VIEW rows resolve their owners' defaults.
	MapDebugPanels.register_map_panels(map)

	# Workflow-split panels (was GeneralDebugPanel + LOGGING was a duplicate).
	var scenario_panel = ScenarioDebugPanel.new()
	scenario_panel.setup(map)
	DebugOverlay.register_panel(scenario_panel, DebugOverlay.Category.SCENARIO, "scenario")

	var simulation_panel = SimulationDebugPanel.new()
	simulation_panel.setup()
	DebugOverlay.register_panel(simulation_panel, DebugOverlay.Category.SIMULATION, "simulation")

	var ui_display_panel = UIDisplayDebugPanel.new()
	ui_display_panel.setup()
	DebugOverlay.register_panel(ui_display_panel, DebugOverlay.Category.DISPLAY, "ui_display")

	var units_func = func(): return [_caster, _target].filter(func(u): return is_instance_valid(u))
	var unit_shader_panel = UnitShaderDebugPanel.new()
	unit_shader_panel.setup(self, units_func)
	DebugOverlay.register_panel(unit_shader_panel, DebugOverlay.Category.SHADERS, "unit_shader")

	# Trap viewer panel
	_panel = TrapViewerPanelClass.new()
	_panel.setup()
	_panel.play_requested.connect(play_trap)
	_panel.stop_requested.connect(stop_trap)
	_panel.loop_toggled.connect(set_looping)
	DebugOverlay.register_panel(_panel, DebugOverlay.Category.EFFECTS)

	# Show overlay and switch to Effects tab
	DebugOverlay.show_overlay()
	DebugOverlay.switch_to_tab(DebugOverlay.Category.EFFECTS)


## Special handlers that use their own effect class instead of TrapEffect
static var SPECIAL_HANDLERS: Dictionary = {
	4: {class_ref = TrapChargeLineEffect, label = "Spell Charge Lines"},
	22: {class_ref = TrapOrbitalEffect, label = "Orbital Summon Orbs"},
}


func play_trap(handler_id: int, element_id: int, direction_deg: float) -> void:
	_last_handler_id = handler_id
	_last_element_id = element_id
	_last_direction_deg = direction_deg

	# Stop any current effect
	_stop_current_effect()

	var target_pos = _target.global_position

	# Special handlers use their own effect class
	if handler_id in SPECIAL_HANDLERS:
		var info = SPECIAL_HANDLERS[handler_id]
		var effect = info["class_ref"].new()
		get_viewport().add_child(effect)
		effect.start(target_pos, _target)
		effect.animation_finished.connect(_on_trap_finished)
		_current_effect = effect
		_panel.update_status("Playing %d (%s)" % [handler_id, info["label"]])
		return

	# Standard TrapEffect handlers
	var effect = TrapEffect.new()
	get_viewport().add_child(effect)

	var success = effect.initialize(7, element_id)
	if not success:
		effect.queue_free()
		_panel.update_status("Failed to initialize")
		return

	# Calculate impact direction from slider angle
	var angle_rad = deg_to_rad(direction_deg)
	var impact_dir = Vector3(cos(angle_rad), 0.0, sin(angle_rad))

	effect.play_handler(handler_id, element_id, target_pos, impact_dir, _target)
	effect.animation_finished.connect(_on_trap_finished)

	_current_effect = effect
	var handler_name = TrapEffect.HANDLER_GROUP_NAMES.get(handler_id, "Unknown")
	_panel.update_status("Playing %d (%s)" % [handler_id, handler_name])


func stop_trap() -> void:
	_looping = false
	_stop_current_effect()
	_panel.update_status("Idle")


func set_looping(enabled: bool) -> void:
	_looping = enabled


func _stop_current_effect() -> void:
	if _current_effect and is_instance_valid(_current_effect):
		if _current_effect.has_method("stop"):
			_current_effect.stop()
		_current_effect.queue_free()
		_current_effect = null


func _on_trap_finished() -> void:
	_current_effect = null
	if _looping and _last_handler_id >= 0:
		var handler_name = TrapEffect.HANDLER_GROUP_NAMES.get(_last_handler_id, "Unknown")
		_panel.update_status("Looping %d (%s)..." % [_last_handler_id, handler_name])
		await get_tree().create_timer(0.3).timeout
		if _looping:
			play_trap(_last_handler_id, _last_element_id, _last_direction_deg)
	else:
		_panel.update_status("Idle")
