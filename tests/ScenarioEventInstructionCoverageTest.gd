extends Node
## Coverage gate (ADR-0059): every `verified:true` EventInstruction must be
## bound-or-skipped in the ScenarioVM registrar — i.e., its opcode byte key is
## present in `_handlers` (a `_bind` handler or a `_skip` clean-skip). A verified
## opcode that is neither would HALT mid-scene. Complements the soft boot
## push_warning the VM emits for the same set.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioEventInstructionCoverageTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var vm := ScenarioVMClass.new()
	add_child(vm)  # triggers _ready -> handler registration

	var verified: Array = []
	var descriptors: Dictionary = EventInstructionSet.all()
	for op in descriptors:
		if descriptors[op].get("verified", false):
			verified.append(op)
	verified.sort()

	# The catalog carries 25 verified:true instructions today. 0x47 Add Ghost Unit
	# was verified once its handler landed (ADD_GHOST_UNIT_OPCODE_47.md); 0x48 Wait
	# Add Unit, 0x4E Unit Shadow and 0x69 Face Tile joined 2026-07-05 once bound
	# (FACE_TILE_UNIT_SHADOW_WAIT_ADD_UNIT.md); 0x63 Camera Speed Curve + 0x73 Camera
	# Move (relative) joined 2026-07-06 (CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md);
	# 0x66 Commit Palette + the scenario-6 quintet {6C}{6D}{71}{7C}{82} joined 2026-07-10
	# (SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md) — 6 more → 25.
	# 0x3E Color Screen joined 2026-07-11 once RE'd byte-exact live + implemented
	# (COLOR_SCREEN_OPCODE_3E.md) — 1 more → 26.
	# 0x50 Portrait Row joined 2026-07-11 once RE'd byte-exact live + implemented
	# (PORTRAIT_ROW_OPCODE_50_EVTFACE.md) — 1 more → 27.
	# 0x68 Mirror Sprite joined 2026-09-02 once RE'd and implemented
	# (MIRROR_SPRITE_OPCODE_68.md) — 1 more → 28.
	# 0x76 Dark Screen, 0x77 Remove Dark Screen and 0x78 Display Conditions joined
	# 2026-09-10 — 3 more → 31. {76}'s row had carried "UNRECONCILED — provisional
	# until the 0x76 dispatcher case is statically confirmed", which
	# DARKSCREEN_OPCODE_76_INVESTIGATION.md §13 then confirmed: the 0x76 arm at
	# 0x80145280 spawns 0x8013BD94, whose only reference in all 2 MB of RAM is that
	# arm. {78} is verified with a correction rather than a confirmation — its first
	# operand is a MODE, not a conditions id (BATTLE_RESULTS_SCREEN.md §13).
	_eq(verified.size(), 31, "verified opcode count")

	# Every verified opcode is bound-or-skipped (byte key present).
	var unbound: Array = []
	for op in verified:
		if not vm._handlers.has(op):
			unbound.append(op)
			print("  [FAIL] verified 0x%02X (%s) is neither bound nor skipped" %
				[op, EventInstructionSet.name_of(op)])
	_eq(unbound.size(), 0, "every verified opcode bound-or-skipped")

	# The VM's own audit (which feeds the soft boot warning) agrees.
	_eq(vm.unbound_verified_opcodes().size(), 0, "VM audit: no verified-but-unbound")

	vm.queue_free()

	print("\n=== ScenarioEventInstructionCoverageTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioEventInstructionCoverageTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioEventInstructionCoverageTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioEventInstructionCoverageTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
