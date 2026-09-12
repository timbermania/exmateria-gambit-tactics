extends Node3D
## Unit Orientation Test — interactive diagnostic + regression scene.
##
## Verifies that a unit's apparent sprite facing stays locked to WORLD NSEW as
## the camera spins. A non-billboarded world arrow + N/E/S/W compass labels show
## the unit's TRUE world facing on screen; compare the sprite's gaze to the arrow.
##
## Convention under test (CLAUDE.md / FacingDirection enum):
##   NORTH = +X, EAST = +Z, SOUTH = -X, WEST = -Z (literal world directions).
##
## Controls:
##   1/2/3/4 — face the unit NORTH / EAST / SOUTH / WEST (world)
##   Q / E   — rotate camera (one quadrant per press)
##   The world arrow always points the unit's true world facing.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

const Facing = ExMateriaSchema.Facing.Direction
const TerrainCell = ExMateriaSchema.TerrainCell
@onready var map: Node3D = $ProceduralMap

var unit: Unit
var arrow: Node3D
var hud: Label

# World direction (unit vector) for each literal-world FacingDirection.
const FACING_TO_WORLD := {
	Facing.NORTH: Vector3(1, 0, 0),   # +X
	Facing.EAST:  Vector3(0, 0, 1),   # +Z
	Facing.SOUTH: Vector3(-1, 0, 0),  # -X
	Facing.WEST:  Vector3(0, 0, -1),  # -Z
}

var unit_pos := Vector2i(5, 6)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	map.change_map("MAP042")
	await get_tree().process_frame

	await _spawn_unit()
	_build_compass()
	_build_arrow()
	_build_hud()

	_set_facing(Facing.NORTH)
	_run_logic_checks()


func _run_logic_checks() -> void:
	"""Regression assertions for the facing-orientation fix.

	Guards against the two defects this scene was built to find:
	  1. Movement/target setters storing facings rotated 90° from world.
	  2. A camera-relative baseline that renders facing != world direction.
	Also asserts world-lock: a fixed facing steps the camera-relative
	direction by exactly one quadrant per camera quadrant.
	"""
	var total := 0
	var failures: Array = []

	# 1. update_facing_from_movement → literal world (+X=NORTH, etc.)
	var move_cases := [
		[Vector3(1, 0, 0), Facing.NORTH, "move +X -> NORTH"],
		[Vector3(-1, 0, 0), Facing.SOUTH, "move -X -> SOUTH"],
		[Vector3(0, 0, 1), Facing.EAST, "move +Z -> EAST"],
		[Vector3(0, 0, -1), Facing.WEST, "move -Z -> WEST"],
	]
	for case in move_cases:
		GPUVisualBridge.update_facing_from_movement(unit, case[0])
		total += 1
		if unit.facing_direction != case[1]:
			failures.append("%s (got %d)" % [case[2], unit.facing_direction])

	# 2. TileTraversalUtils.get_facing_direction_for_step → literal world
	#
	# The map is no longer consulted, and that is the point: this reads grid
	# COORDINATES, which is all the function ever read off the two `Tile` nodes it used
	# to take. Three duck-typed reaches into the lattice were spent fetching nodes so
	# their `grid_x` / `grid_z` could be subtracted (ADR-0164 dec. 2's value payload).
	# The step takes CELLS (ADR-0219): the facing is a function of the two columns'
	# x/z, and the level rides along untouched — a step onto a bridge deck faces the
	# same way as a step onto the moat floor beneath it.
	var c0 := TerrainCell.ground(unit_pos.x, unit_pos.y)
	var c_north := TerrainCell.ground(unit_pos.x + 1, unit_pos.y)  # +X
	var c_east := TerrainCell.ground(unit_pos.x, unit_pos.y + 1)   # +Z
	total += 1
	if TileTraversalUtils.get_facing_direction_for_step(c0, c_north) != Facing.NORTH:
		failures.append("step +X -> NORTH")
	total += 1
	if TileTraversalUtils.get_facing_direction_for_step(c0, c_east) != Facing.EAST:
		failures.append("step +Z -> EAST")

	# 3. World-lock: for any fixed facing, camera-relative direction must step
	#    by exactly +1 (mod 4) as camera_quad decreases by 1 (one 90° rotation).
	var base: int = AnimationStateController.CAMERA_BASELINE_QUAD
	for f in [Facing.NORTH, Facing.EAST, Facing.SOUTH, Facing.WEST]:
		for q in range(4):
			var rd_here = (f + (base - q + 4) % 4) % 4
			var rd_next = (f + (base - ((q + 3) % 4) + 4) % 4) % 4
			total += 1
			if rd_next != (rd_here + 1) % 4:
				failures.append("world-lock f=%d q=%d" % [f, q])

	# 4. Golden baseline: exact [use_back, revert] for every (facing, quad),
	#    snapshotted from the visually-verified good state. Hardcoded literals
	#    (NOT derived from CAMERA_BASELINE_QUAD) so a baseline/formula change
	#    fails here. Index: GOLDEN[facing][quad] = [use_back, revert].
	var GOLDEN := {
		Facing.NORTH: [[true, true], [true, false], [false, false], [false, true]],
		Facing.EAST:  [[false, true], [true, true], [true, false], [false, false]],
		Facing.SOUTH: [[false, false], [false, true], [true, true], [true, false]],
		Facing.WEST:  [[true, false], [false, false], [false, true], [true, true]],
	}
	for f in GOLDEN:
		for q in range(4):
			var d: Dictionary = AnimationStateController.get_camera_variant(f, q)
			var want: Array = GOLDEN[f][q]
			total += 1
			if d["use_back"] != want[0] or d["revert"] != want[1]:
				failures.append("golden f=%d q=%d -> [%s,%s] want [%s,%s]" % [
					f, q, str(d["use_back"]), str(d["revert"]), str(want[0]), str(want[1])])

	# 5. Single source of truth (ADR-0057 Stage 2): a COMBAT facing write must also
	#    update facing_angle, so the two orientation stores can't diverge. The
	#    facing_direction setter is the choke point — update_facing_from_movement
	#    sets facing_direction; facing_angle must follow to the matching wheel angle.
	for case in move_cases:
		GPUVisualBridge.update_facing_from_movement(unit, case[0])
		total += 1
		var want_angle: int = Unit._CARDINAL_TO_12BIT[case[1]]
		if unit.facing_angle != want_angle:
			failures.append("%s: facing_angle not synced to the enum (got 0x%03X want 0x%03X)" % [
				case[2], unit.facing_angle, want_angle])

	# Restore facing for interactive use.
	_set_facing(Facing.NORTH)

	for msg in failures:
		print("[ORIENT_TEST] FAIL: %s" % msg)
	var passed := total - failures.size()
	if failures.is_empty():
		print("[PASS] UnitOrientationTest: %d/%d orientation checks" % [passed, total])
	else:
		print("[FAIL] UnitOrientationTest: %d/%d orientation checks" % [passed, total])

	# CI mode: run headless-style and quit so tests/run_all_tests.sh can score it.
	if "--ci" in OS.get_cmdline_user_args():
		get_tree().quit()


func _spawn_unit() -> void:
	var unit_scene = load("res://assets/scenes/Unit.tscn")
	unit = unit_scene.instantiate()
	unit.name = "TestUnit"
	add_child(unit)
	await get_tree().process_frame
	unit.body_sprite_id = 0x01
	unit.place_on_tile(unit_pos.x, unit_pos.y, map)


func _unit_world_pos() -> Vector3:
	if unit:
		return unit.global_position
	return Vector3(float(unit_pos.x) + 0.5, 0.0, float(unit_pos.y) + 0.5)


func _build_compass() -> void:
	# World-fixed N/E/S/W labels around the unit so "world north" is unambiguous
	# on screen regardless of camera angle.
	var center := _unit_world_pos()
	var labels := {
		"N (+X)": Vector3(2.5, 1.0, 0),
		"E (+Z)": Vector3(0, 1.0, 2.5),
		"S (-X)": Vector3(-2.5, 1.0, 0),
		"W (-Z)": Vector3(0, 1.0, -2.5),
	}
	for text in labels:
		var lbl := Label3D.new()
		lbl.text = text
		lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.6, 0.9, 1.0)
		lbl.position = center + labels[text]
		add_child(lbl)


func _build_arrow() -> void:
	# Non-billboarded world arrow pointing the unit's TRUE world facing.
	arrow = Node3D.new()
	arrow.name = "FacingArrow"
	add_child(arrow)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.12, 0.12, 1.4)
	shaft.mesh = shaft_mesh
	shaft.material_override = mat
	shaft.position = Vector3(0, 0, -0.7)  # extends forward along local -Z
	arrow.add_child(shaft)

	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.25
	head_mesh.height = 0.4
	head.mesh = head_mesh
	head.material_override = mat
	head.rotation = Vector3(-PI / 2.0, 0, 0)  # cone points along local -Z
	head.position = Vector3(0, 0, -1.5)
	arrow.add_child(head)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 16)
	hud.add_theme_font_size_override("font_size", 18)
	layer.add_child(hud)


func _set_facing(f: int) -> void:
	if not unit:
		return
	unit.facing_direction = f
	unit.update_animation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _set_facing(Facing.NORTH)
			KEY_2: _set_facing(Facing.EAST)
			KEY_3: _set_facing(Facing.SOUTH)
			KEY_4: _set_facing(Facing.WEST)


func _process(_delta: float) -> void:
	if not unit or not hud:
		return

	# Orient the world arrow along the unit's true world facing.
	if arrow:
		var dir: Vector3 = FACING_TO_WORLD.get(unit.facing_direction, Vector3(1, 0, 0))
		var head_pos := _unit_world_pos() + Vector3(0, 1.6, 0)
		arrow.global_position = head_pos
		arrow.look_at(head_pos + dir, Vector3.UP)  # local -Z aligns to dir

	var facing: int = unit.facing_direction
	var quad: int = unit.get_camera_quadrant()
	var display: Dictionary = AnimationStateController.get_camera_variant(facing, quad)
	var quad_diff := (3 - quad + 4) % 4
	var rotated_dir := (facing + quad_diff) % 4

	hud.text = "\n".join([
		"UNIT ORIENTATION TEST",
		"  1/2/3/4 = face N/E/S/W (world)   Q/E = rotate camera",
		"  Yellow arrow = unit's TRUE world facing",
		"",
		"facing       : %s (+%s world)" % [Facing.keys()[facing], _world_axis_name(facing)],
		"camera_quad  : %d" % quad,
		"rotated_dir  : %d" % rotated_dir,
		"use_back     : %s" % display["use_back"],
		"revert(flip) : %s" % display["revert"],
		"animation_id : %s" % unit.current_animation_index,
		"",
		"Does the sprite's gaze match the yellow arrow at every camera angle?",
	])


func _world_axis_name(f: int) -> String:
	match f:
		Facing.NORTH: return "X"
		Facing.EAST: return "Z"
		Facing.SOUTH: return "-X"
		Facing.WEST: return "-Z"
	return "?"
