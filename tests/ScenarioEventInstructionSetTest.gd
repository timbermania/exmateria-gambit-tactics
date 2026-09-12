extends Node
## Unit tests for [EventInstructionSet] — the catalog loader/descriptor for the
## event-script ISA (ADR-0059). Asserts descriptor lookup BY BYTE returns the
## expected name/params/verified for known opcodes, that the [EventInstruction]
## enum member value agrees with the descriptor byte, and that the Unknown set
## (the 48 unnamed opcodes) is what the commit-4 auto-skip loop will read.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioEventInstructionSetTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_descriptor_by_byte_name()
	_test_descriptor_params()
	_test_verified_flag()
	_test_enum_member_value_matches_descriptor()
	_test_missing_opcode_returns_empty()
	_test_full_coverage()
	_test_unknown_set()

	print("\n=== ScenarioEventInstructionSetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioEventInstructionSetTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioEventInstructionSetTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioEventInstructionSetTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _test_descriptor_by_byte_name() -> void:
	_eq(EventInstructionSet.descriptor(0x2C).get("name"), "Face Unit 2", "name@0x2C")
	_eq(EventInstructionSet.descriptor(0x10).get("name"), "Display Message", "name@0x10")
	_eq(EventInstructionSet.descriptor(0x6B).get("name"), "BG Sound", "name@0x6B")
	_eq(EventInstructionSet.name_of(0x12), "Unknown", "name_of@0x12")


func _test_descriptor_params() -> void:
	# Display Message (0x10) carries a Dialog param at index 1 (the routing byte).
	var params: Array = EventInstructionSet.descriptor(0x10).get("params", [])
	_true(params.size() >= 2, "0x10 has params")
	_eq(params[1].get("name"), "Dialog", "0x10 param[1] name")


func _test_verified_flag() -> void:
	_eq(EventInstructionSet.descriptor(0x10).get("verified"), true, "0x10 verified")
	_eq(EventInstructionSet.descriptor(0x12).get("verified"), false, "0x12 unverified")


func _test_enum_member_value_matches_descriptor() -> void:
	# The enum value IS the opcode byte, so descriptor(EventInstruction.X).name
	# resolves the catalog name for X — a round-trip through the dispatch key.
	_eq(EventInstructionSet.descriptor(EventInstruction.FACE_UNIT_2).get("name"),
		"Face Unit 2", "FACE_UNIT_2 -> name")
	_eq(EventInstructionSet.descriptor(EventInstruction.BG_SOUND).get("name"),
		"BG Sound", "BG_SOUND -> name")
	_eq(EventInstructionSet.descriptor(EventInstruction.EVENT_END).get("name"),
		"Event End", "EVENT_END -> name")
	# Value equals the byte for a collision-suffixed member too.
	_eq(EventInstruction.UNKNOWN_0X12, 0x12, "UNKNOWN_0X12 value")


func _test_missing_opcode_returns_empty() -> void:
	_true(EventInstructionSet.descriptor(0x999).is_empty(), "missing opcode -> {}")
	_true(EventInstructionSet.has(0x2C), "has 0x2C")
	_true(not EventInstructionSet.has(0x999), "not has 0x999")


func _test_full_coverage() -> void:
	# All 176 catalog instructions get a descriptor (required so the 48 Unknown
	# bytes have entries the byte-keyed dispatch can auto-skip).
	_eq(EventInstructionSet.all().size(), 176, "descriptor count")


func _test_unknown_set() -> void:
	var unknown: Array = EventInstructionSet.unknown_opcodes()
	# 40: was 48 before {73} Camera Move (relative) / {63} Camera Speed Curve were
	# named (CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md) → 46, then 0x66 Commit
	# Palette + the scenario-6 quintet {6C}{6D}{71}{7C}{82} were named 2026-07-10
	# (SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md) → 40. Naming moves each
	# out of the auto-skip set so the registrar's explicit _bind / _skip wins.
	_eq(unknown.size(), 40, "unknown count")
	_true(unknown.has(0x12), "0x12 in unknown set")
	_true(not unknown.has(0x2C), "0x2C not unknown")
	_true(not unknown.has(0x73), "0x73 Camera Move (relative) not unknown (bound)")
	_true(not unknown.has(0x63), "0x63 Camera Speed Curve not unknown (bound)")
	_true(not unknown.has(0x7C), "0x7C End Sound not unknown (bound)")
	_true(not unknown.has(0x6D), "0x6D Set Unit Event Hold not unknown (documented no-op)")
	_true(not unknown.has(0x82), "0x82 Add Unit Path Setup not unknown (documented no-op)")
	_true(EventInstructionSet.is_unknown(0x12), "is_unknown 0x12")
	_true(not EventInstructionSet.is_unknown(0x2C), "not is_unknown 0x2C")
