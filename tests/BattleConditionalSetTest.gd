extends Node
## Unit tests for [BattleConditionalSet] — the catalog loader/descriptor for the
## BattleConditionals mini-ISA (ADR-0059 sibling of [EventInstructionSet]). Asserts
## descriptor lookup BY OPCODE, that the generated [BattleConditionalOpcode] enum
## member value agrees with the descriptor opcode, and that `args()` mints the
## shared [EventInstructionArgs] reader so a requirement's operands read BY NAME
## (the win over the old hand-counted `params[i].value`).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/BattleConditionalSetTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_descriptor_by_opcode_name()
	_test_descriptor_params()
	_test_enum_member_value_matches_descriptor()
	_test_missing_opcode_returns_empty()
	_test_full_coverage()
	_test_args_reads_operands_by_name()

	print("\n=== BattleConditionalSetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] BattleConditionalSetTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] BattleConditionalSetTest")
		get_tree().quit(1)
	else:
		print("[PASS] BattleConditionalSetTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _test_descriptor_by_opcode_name() -> void:
	_eq(BattleConditionalSet.descriptor(0x0001).get("name"), "Variable =", "name@0x0001")
	_eq(BattleConditionalSet.descriptor(0x0004).get("name"), "Unit Present", "name@0x0004")
	_eq(BattleConditionalSet.descriptor(0x0019).get("name"), "Run Scenario", "name@0x0019")
	_eq(BattleConditionalSet.name_of(0x0005), "HP >=", "name_of@0x0005")


func _test_descriptor_params() -> void:
	# HP >= (0x0005) carries Unit then Value (both 2-byte).
	var params: Array = BattleConditionalSet.descriptor(0x0005).get("params", [])
	_eq(params.size(), 2, "0x0005 param count")
	_eq(params[0].get("name"), "Unit", "0x0005 param[0] name")
	_eq(params[1].get("name"), "Value", "0x0005 param[1] name")
	_eq(int(params[1].get("bytes")), 2, "0x0005 Value width 2 (catalog)")


func _test_enum_member_value_matches_descriptor() -> void:
	# The enum value IS the opcode, so descriptor(BattleConditionalOpcode.X).name
	# resolves the catalog name for X — a round-trip through the dispatch key.
	_eq(BattleConditionalSet.descriptor(BattleConditionalOpcode.RUN_SCENARIO).get("name"),
		"Run Scenario", "RUN_SCENARIO -> name")
	_eq(BattleConditionalSet.descriptor(BattleConditionalOpcode.VARIABLE_EQ).get("name"),
		"Variable =", "VARIABLE_EQ -> name")
	# Value equals the opcode for a collision-suffixed member too (HP% share "HP").
	_eq(BattleConditionalOpcode.HP_0X0007, 0x0007, "HP_0X0007 value")


func _test_missing_opcode_returns_empty() -> void:
	_true(BattleConditionalSet.descriptor(0x9999).is_empty(), "missing opcode -> {}")
	_true(BattleConditionalSet.has(0x0019), "has 0x0019")
	_true(not BattleConditionalSet.has(0x9999), "not has 0x9999")


func _test_full_coverage() -> void:
	_eq(BattleConditionalSet.all().size(), 22, "descriptor count")


func _test_args_reads_operands_by_name() -> void:
	# A runtime requirement record (as BattleConditionalDatabase serves): opcode +
	# positional param values. The reader zips values against the catalog by
	# position and exposes them BY NAME — the win over hand-counted params[i].
	var req := {
		"opcode": 0x0005,  # HP >=
		"params": [{"value": 12}, {"value": 1}],
	}
	var a := BattleConditionalSet.args(req)
	_eq(a.raw("Unit"), 12, "args HP>= Unit by name")
	_eq(a.raw("Value"), 1, "args HP>= Value by name")
	_eq(a.width_at(1), 2, "args Value width from catalog")
	# Gil >= puts Value at position 1 (position 0 is Unused) — named read still
	# targets the Value operand, not a hand-counted index.
	var gil := BattleConditionalSet.args({"opcode": 0x000E, "params": [{"value": 0}, {"value": 5000}]})
	_eq(gil.raw("Value"), 5000, "args Gil>= Value by name (pos 1)")
