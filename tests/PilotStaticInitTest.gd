extends Node
## Guard for ADR-0068 R1–R8 (pilot): Unit's render tunables are REGISTERED at boot by
## Unit._static_init (the pure `bind`), NOT lazily at unit spawn — this is what lets the
## generated dashboard and the alignment panel (a view, decision 12) enumerate/read the
## knobs in ANY scene before a unit exists. Loading the Unit class must run _static_init and
## leave render.unit_mesh_scale / render.unit_y_lift / render.loc_offset /
## render.ot_unit_forward registered with their hints, and loc_offset must be a Vector2.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/PilotStaticInitTest.tscn

# Preloading the script triggers its class load -> _static_init (headful run, so
# Engine.is_editor_hint() is false and the bind calls execute).
const UnitScript = preload("res://src/units/Unit.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# Do NOT Tune.reset() — that would clear the boot registration we are here to verify.
	var slugs := Tune.registered_slugs()
	for slug in ["render.unit_mesh_scale", "render.unit_y_lift", "render.loc_offset",
			"render.ot_unit_forward"]:
		_assert_true(slug in slugs, "%s is registered at boot by Unit._static_init" % slug)

	# The hint rode the bind (R2: bind carries meta), so the dashboard can clamp the spinbox.
	_assert_eq(Tune.meta_of("render.unit_mesh_scale"), {"min": 1.0, "max": 20.0, "step": 0.1},
		"the mesh-scale hint is registered at the owner's bind")
	# loc_offset is a single Vector2 slug (R6), so its control infers per-component spinboxes.
	var loc_default: Variant = Tune.default_of("render.loc_offset")
	_assert_true(loc_default is Vector2, "render.loc_offset is registered as a Vector2 literal")

	print("\n=== PilotStaticInitTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] PilotStaticInitTest")
		get_tree().quit(1)
	else:
		print("[PASS] PilotStaticInitTest")
		get_tree().quit(0)


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
