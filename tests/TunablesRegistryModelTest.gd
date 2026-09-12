extends Node
## Guard for the REGISTRY page projection (ADR-0068): TunablesRegistryModel.rows()
## enumerates every registered slug with its metadata (default, live value, type,
## range, dirty). Pure — no UI, no GPU.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TunablesRegistryModelTest.tscn

const Model = preload("res://src/debug/TunablesRegistryModel.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_rows_project_metadata()
	_test_dirty_and_value_reflect_overrides()
	_test_type_and_range_labels()

	print("\n=== TunablesRegistryModelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TunablesRegistryModelTest")
		get_tree().quit(1)
	else:
		print("[PASS] TunablesRegistryModelTest")
		get_tree().quit(0)


func _test_rows_project_metadata() -> void:
	Tune.reset()
	Tune.bind("render.mesh_scale", 8.0, {"min": 1.0, "max": 20.0, "step": 0.1})
	Tune.bind("debug.map", false)
	var rows := Model.rows(Tune)
	_check("one row per registered slug", rows.size(), 2)
	# Sorted by slug: debug.* before render.*
	_check("rows sorted by slug", rows[0]["slug"], "debug.map")
	_check("namespace split from slug", rows[1]["namespace"], "render")
	_check("default projected", rows[1]["default"], 8.0)


func _test_dirty_and_value_reflect_overrides() -> void:
	Tune.reset()
	Tune.bind("debug.map", false)
	var clean: Dictionary = Model.rows(Tune)[0]
	_check("no override -> value is the default", clean["value"], false)
	_check("no override -> not dirty", clean["dirty"], false)

	Tune.set_value("debug.map", true)
	var dirty: Dictionary = Model.rows(Tune)[0]
	_check("override -> value coalesces", dirty["value"], true)
	_check("override -> dirty", dirty["dirty"], true)
	Tune.clear("debug.map")


func _test_type_and_range_labels() -> void:
	_check("bool type label", Model.type_label(false, {}), "bool")
	_check("float type label", Model.type_label(1.0, {}), "float")
	_check("enum hint wins the type", Model.type_label(0, {"enum": {"A": 0}}), "enum")
	_check("scalar range label", Model.range_label({"min": 1.0, "max": 20.0, "step": 0.1}),
		"1.0..20.0 /0.1")
	_check("empty hint -> empty range", Model.range_label({}), "")


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
