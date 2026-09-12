extends Node3D

## Guard (ADR-0088 Amendment 5 §3): the element ROLE criterion — the gate that lets the
## widget world join through the base-swap without every UIComponent registering.
##   A. VALIDATION IS ROLE-GATED — an ELEMENT spec requires id+rect (+the enum criteria);
##      a PAYLOAD spec with NEITHER is valid (no boot assert). The code-built default
##      (no role key) is ELEMENT, so the existing construction surface is unchanged.
##   B. PAYLOAD NEVER ENTERS THE INDEX — a widget-path element (empty spec, answers
##      nothing) answers PAYLOAD, does not register, and is not placed.
##   C. ELEMENT STILL REGISTERS — a code-built element with no role key registers as before.
##   D. PAYLOAD IS SKIPPED IN THE ANCESTOR CHAIN — a PAYLOAD UI3Element between two
##      ELEMENTs does not become anyone's parent_element.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/UI3ElementRoleTest.tscn

var _failed := false


func _ready() -> void:
	_test_validation_is_role_gated()
	_test_code_built_default_is_element()
	await _test_payload_never_registers()
	await _test_payload_skipped_as_parent_element()

	if _failed:
		push_error("[FAIL] UI3ElementRoleTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3ElementRoleTest")
		get_tree().quit(0)


## A. ELEMENT requires id+rect (+enum criteria); PAYLOAD requires neither.
func _test_validation_is_role_gated() -> void:
	# An explicit ELEMENT with nothing else reports all 5 required criteria.
	var el_errors := UI3Element.validate_spec({"role": UI3Element.Role.ELEMENT})
	_expect(el_errors.size() == 5,
		"ELEMENT-role empty spec must report all 5 required criteria, got %d: %s" % [el_errors.size(), el_errors])

	# A PAYLOAD with neither id nor rect is VALID (it cannot boot-assert).
	var pl_errors := UI3Element.validate_spec({"role": UI3Element.Role.PAYLOAD})
	_expect(pl_errors.is_empty(),
		"PAYLOAD-role spec with no id/rect must be valid, got: %s" % [pl_errors])

	# An out-of-range role is itself a reported problem.
	var bad_role := UI3Element.validate_spec({"role": 99})
	_expect(_any_contains(bad_role, "role"),
		"an out-of-range role must be reported, got: %s" % [bad_role])


## A/C. The code-built default (no role key) stays ELEMENT — the existing surface is
## untouched, so validate_spec({}) still reports all 5 required criteria.
func _test_code_built_default_is_element() -> void:
	var errors := UI3Element.validate_spec({})
	_expect(errors.size() == 5,
		"the no-role default must be ELEMENT (5 required criteria), got %d: %s" % [errors.size(), errors])

	var el := _valid_element("t.role.element", Rect2(10, 20, 30, 40))
	_expect(el.role() == UI3Element.Role.ELEMENT, "code-built element role must be ELEMENT")
	el.free()


## B/C. A widget-path element (empty spec) answers PAYLOAD, never registers, and is not
## placed; a code-built element registers as before.
func _test_payload_never_registers() -> void:
	var registered: Array = []
	var cb := func(e: UI3Element) -> void: registered.append(e)
	UI3Registry.element_registered.connect(cb)

	# Widget path: no spec, no answers -> PAYLOAD.
	var payload := UI3Element.new()
	payload.name = "PayloadWidget"
	add_child(payload)
	await get_tree().process_frame
	_expect(payload.role() == UI3Element.Role.PAYLOAD, "empty-spec element must answer PAYLOAD")
	_expect(not UI3Registry.elements().has(payload), "PAYLOAD must never enter the registry index")
	_expect(not registered.has(payload), "element_registered must not fire for a PAYLOAD")

	# Code-built ELEMENT still registers.
	var elem := _valid_element("t.role.reg", Rect2(0, 0, 8, 8))
	add_child(elem)
	await get_tree().process_frame
	_expect(UI3Registry.elements().has(elem), "code-built ELEMENT must register")

	payload.free()
	elem.free()
	UI3Registry.element_registered.disconnect(cb)


## D. A PAYLOAD UI3Element between two ELEMENTs is transparently skipped as a parent.
func _test_payload_skipped_as_parent_element() -> void:
	var top := _valid_element("t.role.top", Rect2(0, 0, 100, 100))
	add_child(top)

	var payload := UI3Element.new()   # PAYLOAD widget in the middle of the chain
	payload.name = "MiddlePayload"
	top.add_child(payload)

	var child := _valid_element("t.role.top.child", Rect2(10, 10, 20, 20))
	payload.add_child(child)
	await get_tree().process_frame

	_expect(child.parent_element() == top,
		"child must resolve the ELEMENT ancestor, skipping the PAYLOAD in between")

	child.free()
	payload.free()
	top.free()


func _valid_element(id: String, rect: Rect2) -> UI3Element:
	return UI3Element.new({
		"id": id,
		"rect": rect,
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})


func _any_contains(arr: PackedStringArray, needle: String) -> bool:
	for e in arr:
		if String(e).contains(needle):
			return true
	return false


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("[UI3ElementRoleTest] %s" % msg)
