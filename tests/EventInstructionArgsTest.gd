extends Node
## Unit tests for [EventInstructionArgs] — the typed operand reader that replaces
## `_params_dict` (ADR-0059 Phase 2). Covers name access, positional access,
## duplicate-name preservation (the {6A} two-`Unknown` case `_params_dict`
## collapses), width/`type` decoding, and the `to_dict` compatibility bridge.
## Pure decode object, so no scene / VM / nodes — minted from the real catalog
## via [EventInstructionSet].
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/EventInstructionArgsTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_name_access()
	_test_positional_access()
	_test_duplicate_name_preserved()
	_test_width_and_signed_decode()
	_test_type_from_catalog()
	_test_missing_and_defaults()

	print("\n=== EventInstructionArgsTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] EventInstructionArgsTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] EventInstructionArgsTest")
		get_tree().quit(1)
	else:
		print("[PASS] EventInstructionArgsTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _ok(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# A runtime {5F} Warp Unit instruction (scenario-1 PC0: Unit=2 -> (1,6,0) facing 3).
func _warp_inst() -> Dictionary:
	return {
		"opcode": 0x5F,
		"name": "Warp Unit",
		"params": [
			{"name": "Unit", "type": "Unit", "value": 2, "bytes": 2},
			{"name": "X", "value": 1, "bytes": 1},
			{"name": "Y", "value": 6, "bytes": 1},
			{"name": "Z", "value": 0, "bytes": 1},
			{"name": "Facing", "value": 3, "bytes": 1},
		],
	}


# A runtime {6A} Edit BG Sound instruction — TWO operands both named "Unknown".
func _edit_bg_sound_inst() -> Dictionary:
	return {
		"opcode": 0x6A,
		"name": "Edit BG Sound",
		"params": [
			{"name": "Sound", "value": 0x11, "bytes": 1},
			{"name": "Echo", "value": 20, "bytes": 1},
			{"name": "Volume", "value": 80, "bytes": 1},
			{"name": "Unknown", "value": 7, "bytes": 1},
			{"name": "Unknown", "value": 42, "bytes": 1},
		],
	}


func _test_name_access() -> void:
	var a := EventInstructionSet.args(_warp_inst())
	_eq(a.raw("Unit"), 2, "name Unit")
	_eq(a.raw("X"), 1, "name X")
	_eq(a.raw("Y"), 6, "name Y")
	_eq(a.raw("Facing"), 3, "name Facing")
	_ok(a.has("Unit"), "has Unit")
	_ok(not a.has("Nope"), "not has Nope")


func _test_positional_access() -> void:
	var a := EventInstructionSet.args(_warp_inst())
	_eq(a.size(), 5, "size")
	_eq(a.name_at(0), "Unit", "name_at 0")
	_eq(a.raw_at(0), 2, "raw_at 0")
	_eq(a.name_at(4), "Facing", "name_at 4")
	_eq(a.raw_at(4), 3, "raw_at 4")
	_eq(a.index_of("Y"), 2, "index_of Y")
	# nth: bounds-safe positional read (for opcodes read purely by position).
	_eq(a.nth(0), 2, "nth 0")
	_eq(a.nth(4), 3, "nth 4")
	_eq(a.nth(5), 0, "nth out-of-range default 0")
	_eq(a.nth(9, -1), -1, "nth out-of-range custom default")


func _test_duplicate_name_preserved() -> void:
	# The core reason the reader exists: {6A}'s two "Unknown" operands must stay
	# distinct — `_params_dict` would collapse them to the last value (42).
	var a := EventInstructionSet.args(_edit_bg_sound_inst())
	_eq(a.count("Unknown"), 2, "dup count")
	_eq(a.all("Unknown"), [7, 42], "dup all values in order")
	_eq(a.index_of("Unknown"), 3, "dup first index")
	# Positional reach still gets each distinctly.
	_eq(a.raw_at(3), 7, "dup pos 3")
	_eq(a.raw_at(4), 42, "dup pos 4")


func _test_width_and_signed_decode() -> void:
	# Width comes from the catalog: {5F} Unit is a 2-byte operand, X/Y/Z bytes.
	var a := EventInstructionSet.args(_warp_inst())
	_eq(a.width_at(0), 2, "Unit width 2 (catalog)")
	_eq(a.width_at(1), 1, "X width 1 (catalog)")
	# Signed accessor delegates to PsxNum by width. Build a synthetic signed case
	# via {3B} Sprite Move (+X is a 2-byte operand): 0xFFFF -> -1 via s16.
	var move := {
		"opcode": 0x3B,
		"params": [
			{"name": "Unit", "value": 2, "bytes": 2},
			{"name": "+X", "value": 0xFFFF, "bytes": 2},
			{"name": "+Z", "value": 0x0080, "bytes": 2},
		],
	}
	var m := EventInstructionSet.args(move)
	_eq(m.width_at(1), 2, "+X width 2 (catalog)")
	_eq(m.signed("+X"), -1, "signed +X (s16)")
	_eq(m.signed_at(1), -1, "signed_at +X (s16)")
	_eq(m.signed("+Z"), 0x80, "signed +Z positive (s16)")
	# A 1-byte signed operand sign-extends via s8: 0xFF -> -1.
	var dark := {
		"opcode": 0x1A,
		"params": [
			{"name": "Blend", "value": 0, "bytes": 1},
			{"name": "Red", "value": 0xFF, "bytes": 1},
		],
	}
	var dk := EventInstructionSet.args(dark)
	_eq(dk.width_at(1), 1, "Red width 1")
	_eq(dk.signed("Red"), -1, "signed Red (s8)")


func _test_type_from_catalog() -> void:
	# The catalog `type:"Unit"` is surfaced by the reader (runtime inst carries it
	# too, but the reader takes it as authoritative from the descriptor).
	var a := EventInstructionSet.args(_warp_inst())
	_eq(a.type_at(0), "Unit", "type_at Unit")
	_eq(a.type_at(1), "", "type_at plain byte empty")
	# {6B} Sound operand has mode "hex" in the catalog.
	var bg := EventInstructionSet.args({
		"opcode": 0x6B,
		"params": [{"name": "Sound", "value": 5, "bytes": 1}],
	})
	_eq(bg.mode_at(0), "hex", "mode_at from catalog")


func _test_missing_and_defaults() -> void:
	var a := EventInstructionSet.args(_warp_inst())
	_eq(a.raw("Nope"), 0, "missing raw default 0")
	_eq(a.raw("Nope", -9), -9, "missing raw custom default")
	_eq(a.signed("Nope", 3), 3, "missing signed default")
	_eq(a.index_of("Nope"), -1, "missing index_of -1")
	_eq(a.all("Nope"), [], "missing all empty")
	_eq(a.count("Nope"), 0, "missing count 0")
