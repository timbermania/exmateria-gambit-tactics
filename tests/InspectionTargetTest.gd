extends Node
## TDD guard for InspectionTarget — the generic `{kind, ref}` the Effect Studio
## inspector renders (generalizes ADR-0071's span→projector to target-kind→projector).
## Asserts the constructors, the opaque-ref accessors, value equality (back-stack
## dedupe), and the breadcrumb label. Pure value type, no scene. See ADR-0073.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/InspectionTargetTest.tscn

const Target = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_span_constructor()
	_test_emitter_constructor()
	_test_container_constructor()
	_test_ref_is_opaque_and_kind_specific()
	_test_is_empty()
	_test_equals_for_back_stack_dedupe()
	_test_label_breadcrumb_token()

	print("\n=== InspectionTargetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] InspectionTargetTest")
		get_tree().quit(1)
	else:
		print("[PASS] InspectionTargetTest")
		get_tree().quit(0)


func _test_span_constructor() -> void:
	var t := Target.span("p:fe:0#1")
	_assert_eq(Target.kind(t), "span", "span target has kind 'span'")
	_assert_eq(Target.ref(t).get("span_id", ""), "p:fe:0#1", "span ref carries span_id")


func _test_emitter_constructor() -> void:
	var t := Target.emitter(5)
	_assert_eq(Target.kind(t), "emitter", "emitter target has kind 'emitter'")
	_assert_eq(int(Target.ref(t).get("index", -1)), 5, "emitter ref carries 0-based index")


## The ADR-0085 TIER-2 drill target: a shared, effect-global SoundContainer reached by
## following a trigger's sound_id reference. Ref keys on the 0-based container index
## (== sound_id - 2), like emitter but its own kind.
func _test_container_constructor() -> void:
	var t := Target.container(2)
	_assert_eq(Target.kind(t), "container", "container target has kind 'container'")
	_assert_eq(int(Target.ref(t).get("index", -1)), 2, "container ref carries 0-based index")
	_assert_eq(Target.label(t), "container 2", "container breadcrumb names the index")
	_assert_true(not Target.is_empty(t), "a real container target is not empty")


## The ref is kind-specific: a span keys on span_id, an emitter on index — the
## registry never assumes a shared id field (opaque payload, grilling decision).
func _test_ref_is_opaque_and_kind_specific() -> void:
	_assert_true(Target.span("x").get("ref").has("span_id"), "span ref keys on span_id")
	_assert_true(Target.emitter(0).get("ref").has("index"), "emitter ref keys on index")
	_assert_true(not Target.emitter(0).get("ref").has("span_id"),
		"emitter ref does NOT borrow the span identity")


func _test_is_empty() -> void:
	_assert_true(Target.is_empty({}), "empty dict is empty")
	_assert_true(Target.is_empty({"kind": "", "ref": {}}), "blank kind is empty")
	_assert_true(not Target.is_empty(Target.emitter(0)), "a real target is not empty")


func _test_equals_for_back_stack_dedupe() -> void:
	_assert_true(Target.equals(Target.emitter(3), Target.emitter(3)), "same kind+ref are equal")
	_assert_true(not Target.equals(Target.emitter(3), Target.emitter(4)), "differing ref not equal")
	_assert_true(not Target.equals(Target.emitter(0), Target.span("x")), "differing kind not equal")


func _test_label_breadcrumb_token() -> void:
	_assert_eq(Target.label(Target.emitter(5)), "emitter 5", "emitter breadcrumb names the index")
	# A span borrows its lane id when the score context is present.
	_assert_eq(Target.label(Target.span("p:fe:0#2"), null, {"lanes": []}), "p:fe:0 span",
		"span breadcrumb borrows the lane id before the '#'")


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
