extends Node3D
## Move-1 guard for ADR-0068 batch 1: the Unit SPAWN PATH sources its per-unit
## visual defaults — mesh basis scale, mesh Y-lift, and the base shared_loc_offset —
## through the Tune registry, so a committed override coalesces onto a freshly
## spawned unit on its first frame. Before this migration those values were pure
## scene/const data (Unit.tscn UnitMesh transform + SpriteLayerManager.SHARED_LOC_
## OFFSET) with no override seam; this proves the seam exists end-to-end.
##
## Spawns a real Unit against a real map+camera (like UnitOrientationTest), NOT the
## GPUArena roster path, to dodge the roster-spawn native crash.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/UnitVisualDefaultsTuneTest.tscn

@onready var map: Node3D = $ProceduralMap

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# Overrides must be live BEFORE the unit spawns so its per-instance `update` coalesces
	# them on the first apply (ADR-0068 R3). We do NOT Tune.reset() here: the render slugs
	# are registered at BOOT by Unit._static_init (the `bind`), and reset() would clear that
	# registration out from under the unit's update (leaving a null default for any slug the
	# test doesn't override, e.g. render.ot_unit_forward). Clear only the overrides we exercise instead.
	for slug in ["render.unit_mesh_scale", "render.unit_y_lift", "render.loc_offset"]:
		Tune.clear(slug)
	Tune.set_value("render.unit_mesh_scale", 5.0)
	Tune.set_value("render.unit_y_lift", 0.5)
	# loc_offset is ONE Vector2 slug now (ADR-0068 R6 — the x/y pair collapsed so there
	# is a single typed literal to materialize and no .x/.y ambiguity).
	Tune.set_value("render.loc_offset", Vector2(30.0, 20.0))

	await get_tree().process_frame
	map.change_map("MAP042")
	await get_tree().process_frame

	var unit_scene = load("res://assets/scenes/Unit.tscn")
	var unit: Unit = unit_scene.instantiate()
	unit.name = "TestUnit"
	add_child(unit)
	await get_tree().process_frame
	unit.body_sprite_id = 0x01
	unit.place_on_tile(5, 6, map)
	await get_tree().process_frame

	_assert_approx(unit.mesh_instance.scale.x, 5.0,
		"mesh basis scale coalesces the render.unit_mesh_scale override")
	_assert_approx(unit.mesh_instance.position.y, 0.5,
		"mesh Y-lift coalesces the render.unit_y_lift override")
	_assert_approx(unit._base_loc_offset.x, 30.0,
		"base loc_offset X coalesces the render.loc_offset override")
	_assert_approx(unit._base_loc_offset.y, 20.0,
		"base loc_offset Y coalesces the render.loc_offset override")

	# LIVE re-apply (ADR-0068 R3.5 / bind): scrubbing a slug AFTER the unit has
	# spawned must update the already-on-screen unit — this is what makes the knobs
	# work in EVERY scene (GPUArena Tunables dashboard, scenario panel) with no
	# per-scene fan-out. A read-once bind at spawn would leave these stale.
	Tune.set_value("render.unit_mesh_scale", 7.0)
	Tune.set_value("render.unit_y_lift", 0.9)
	Tune.set_value("render.loc_offset", Vector2(40.0, 45.0))
	await get_tree().process_frame
	_assert_approx(unit.mesh_instance.scale.x, 7.0,
		"scrubbing render.unit_mesh_scale live-updates the spawned unit")
	_assert_approx(unit.mesh_instance.position.y, 0.9,
		"scrubbing render.unit_y_lift live-updates the spawned unit")
	_assert_approx(unit._base_loc_offset.x, 40.0,
		"scrubbing render.loc_offset live-updates the spawned unit (x)")
	_assert_approx(unit._base_loc_offset.y, 45.0,
		"scrubbing render.loc_offset live-updates the spawned unit (y)")

	print("\n=== UnitVisualDefaultsTuneTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UnitVisualDefaultsTuneTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitVisualDefaultsTuneTest")
		get_tree().quit(0)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%.4f, got %.4f" % [label, expected, actual])
