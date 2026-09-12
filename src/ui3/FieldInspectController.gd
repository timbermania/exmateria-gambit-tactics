class_name FieldInspectController
extends Node
## Field-inspect picker (#91).
##
## Left-clicking a unit on the battlefield (3D pick, collision_mask = 4 — the
## unit SelectionArea) opens the screen-space [UIUnitInfoWindow] for it; clicking
## empty ground or re-clicking the same unit dismisses it. While open, the window
## is refreshed every frame from the live unit (no cached mirror — ADR-0063
## observation-only). This is additive: the portrait->StatsMenu path is untouched.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase


const UNIT_PICK_MASK := 4

var _camera: Camera3D
var _window: UIUnitInfoWindow
var _picked: Node = null


func setup(camera: Camera3D, window: UIUnitInfoWindow) -> void:
	_camera = camera
	_window = window
	if _window:
		_window.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _camera == null or _window == null:
		return
	var unit := _pick_unit_at(event.position)
	if unit == null or unit == _picked and _window.visible:
		_dismiss()
	else:
		_inspect(unit)


func _process(_delta: float) -> void:
	# Live update while the inspected unit acts / moves.
	if _window and _window.visible and is_instance_valid(_picked):
		_window.set_unit_view(view_from_unit(_picked))
	elif _window and _window.visible and not is_instance_valid(_picked):
		_dismiss()


## Public: open the info window for a specific unit (e.g. a non-pick caller).
func inspect_unit(unit: Node) -> void:
	if _window == null or unit == null:
		return
	_inspect(unit)


## Public: close the info window.
func dismiss() -> void:
	_dismiss()


func _inspect(unit: Node) -> void:
	_picked = unit
	_window.set_unit_view(view_from_unit(unit))
	_window.visible = true


func _dismiss() -> void:
	_picked = null
	if _window:
		_window.visible = false


## Raycast the unit pick layer; return the owning Unit or null.
func _pick_unit_at(screen_pos: Vector2) -> Node:
	var space := _camera.get_world_3d().direct_space_state
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 1000.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = UNIT_PICK_MASK
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	# The SelectionArea's parent is the Unit scene root.
	var collider = hit.get("collider")
	if collider and collider.get_parent() and collider.get_parent().get("unit_stats") != null:
		return collider.get_parent()
	return null


## Build a UnitInfoPresenter view from a live Unit's components. Reads our own
## UnitStats / progression / status — never FFT's ROM BattleUnitData.
static func view_from_unit(unit: Node) -> Dictionary:
	var view := {"name": str(unit.name)}
	var sprite_id = unit.get("body_sprite_id")
	if sprite_id != null:
		view["sprite_id"] = int(sprite_id)
	# The unit's OWNED portrait source (#205): a unique resolves to a template
	# folder at spawn, generics to "". The info window fronts the flat sprite
	# sheet with `<folder>/portrait.tga` when present, else falls back to sprite_id.
	var template_folder = unit.get("template_folder")
	if template_folder != null:
		view["template_folder"] = str(template_folder)
	var stats = unit.get("unit_stats")
	if stats:
		view["current_hp"] = stats.current_hp
		view["max_hp"] = stats.max_hp
		view["current_mp"] = stats.current_mp
		view["max_mp"] = stats.max_mp
	var prog = unit.get("unit_progression")
	if prog:
		view["level"] = prog.level
		view["brave"] = prog.brave
		view["faith"] = prog.faith
		var job: Dictionary = JobDatabase.get_job(prog.current_job_id)
		view["job"] = job.get("name", prog.current_job_id)
	var status = unit.get_node_or_null("UnitStatusManager")
	if status:
		var names: Array = []
		for s in status.get_all_statuses():
			names.append(str(s).capitalize())
		view["statuses"] = names
	return view
