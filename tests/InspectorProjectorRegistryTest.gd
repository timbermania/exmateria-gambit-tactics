extends Node
## TDD guard for InspectorProjectorRegistry (ADR-0073) — the kind→projector routing that
## makes a new inspectable object kind a registration, not an inspector change. Asserts:
## built kinds resolve to a projector, declared-but-unbuilt seams are recognized yet yield
## null (inert, not a crash), unknown kinds are rejected, and dispatch of an unbuilt/unknown
## target returns empty rather than erroring.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/InspectorProjectorRegistryTest.tscn

const Registry = preload("res://src/effects/studio/InspectorProjectorRegistry.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_span_is_built()
	_test_seams_recognized_but_unbuilt()
	_test_unknown_kind_rejected()
	_test_dispatch_of_unbuilt_is_inert()

	print("\n=== InspectorProjectorRegistryTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] InspectorProjectorRegistryTest")
		get_tree().quit(1)
	else:
		print("[PASS] InspectorProjectorRegistryTest")
		get_tree().quit(0)


func _test_span_is_built() -> void:
	for kind in ["span", "emitter", "container", "frameset", "frame", "animation"]:
		_assert_true(Registry.has_kind(kind), "%s is a recognized kind" % kind)
		_assert_true(Registry.is_built(kind), "%s is built" % kind)
		_assert_true(Registry.projector_for(kind) != null, "%s resolves to a projector" % kind)


## The future object kinds are DECLARED (has_kind true) so the model can honestly answer
## for them, but not yet BUILT — their projector is null and renders nothing, so an
## un-built kind is inert rather than an error. Adding one = write the projector + flip it.
func _test_seams_recognized_but_unbuilt() -> void:
	# frameset/frame graduated to built (#278), animation (#275) — guarded by
	# _test_span_is_built above and by
	# EffectStudioFramesetEditTest's dedicated projector-shape assertions.
	for kind in ["curve", "callback"]:
		_assert_true(Registry.has_kind(kind), "%s is a declared seam" % kind)
		_assert_true(not Registry.is_built(kind), "%s is not yet built" % kind)
		_assert_true(Registry.projector_for(kind) == null, "%s has no projector yet" % kind)


func _test_unknown_kind_rejected() -> void:
	_assert_true(not Registry.has_kind("bogus"), "an unknown kind is not recognized")
	_assert_true(Registry.projector_for("bogus") == null, "an unknown kind has no projector")


func _test_dispatch_of_unbuilt_is_inert() -> void:
	# A curve target with any ref must not crash — the registry yields empty rows.
	var target := {"kind": "curve", "ref": {"index": 3}}
	_assert_eq(Registry.header(target, null, {}), [], "unbuilt kind → empty header")
	_assert_eq(Registry.sections(target, null, {}), [], "unbuilt kind → empty sections")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
