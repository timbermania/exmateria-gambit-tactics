extends Node
## Tests for ScenarioVM's {53} Face Unit look-at math
## (`ScenarioVM.face_unit_look_at_12bit_psx`). The opcode makes the affected
## unit rotate to LOOK AT the faced unit's tile; the ROM handler
## evt0x53_face_unit @ 0x80148084 computes, in PSX tile coords,
##   Δx = affected.x − faced.x,  Δy = affected.y − faced.y
##   atan12 = ratan2_12bit(Δx, Δy)   ; 12-bit CW wheel, 0 at +Δy, 0x400 at +Δx
##   target_12bit = (0x1400 − atan12) & 0xF00
## Decode + the §8 controlled-call octant table this test pins against:
## research/working_documents/scenario_1_captures/face_unit_decode.md.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioFaceUnitTest.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_octant_table()
	_test_captured_geometry()
	_test_godot_geometry_transpose()
	_test_face_unit_single_vs_mutual()

	print("\n=== ScenarioFaceUnitTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioFaceUnitTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioFaceUnitTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioFaceUnitTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- §8 controlled-call octant table (SUB_8001d8e8 → path-B facing) ----------
# Each row is (Δx, Δy, expected facing12). Reproduced verbatim from
# face_unit_decode.md §8, where each was obtained by a controlled call to the
# PSX 12-bit arctangent and the path-B `(0x1400 − atan) & 0xF00` transform.
func _test_octant_table() -> void:
	var rows := [
		[0, 140, 0x400],     # +Δy   → East
		[0, -140, 0xC00],    # −Δy   → North
		[140, 0, 0x000],     # +Δx   → South
		[-140, 0, 0x800],    # −Δx   → West
		[100, 100, 0x200],
		[-100, 100, 0x600],
		[100, -100, 0xE00],
		[-100, -100, 0xA00],
	]
	for r in rows:
		var got: int = ScenarioVM.face_unit_look_at_12bit_psx(int(r[0]), int(r[1]))
		_assert_eq(got, int(r[2]),
			"face_unit_look_at_12bit_psx(Δx=%d, Δy=%d)" % [int(r[0]), int(r[1])])


# --- Captured scene ground truth (face_unit_decode.md §5 dynamic proof) ------
# affected 0x0c at (126,182), faced 0x84 at (126,42) ⇒ Δx=0, Δy=+140 ⇒ PCSX
# wrote facing nibble 0x04 (= 12-bit 0x400, East). Our math must reproduce it.
func _test_captured_geometry() -> void:
	_assert_eq(ScenarioVM.face_unit_look_at_12bit_psx(0, 140), 0x400,
		"captured 0x0c→0x84 (Δx=0, Δy=+140) → 0x400 (East), matches PCSX nibble 0x04")
	# Direction is symmetric: the faced unit looking back at the affected unit is
	# exactly 180° (path-A), so the reverse delta yields 0xC00 (West-of-East).
	_assert_eq(ScenarioVM.face_unit_look_at_12bit_psx(0, -140), 0xC00,
		"reverse delta (faced→affected) is 180° from 0x400")


# --- Godot→PSX axis transpose (the live-validated _face_unit_look_at_12bit) ---
# Guards the Godot-world → PSX-internal mapping (face_unit_decode.md §10 close):
# PSX-y = lateral = +ΔGodot_x, PSX-x = depth = −ΔGodot_z. In the captured scene
# affected 0x0c sits at Godot (x=6, z=5) and faced knight 0x84 at (x=0, z=5) —
# same row, knight to lateral −X — and must resolve to 0x400 (East), matching
# PCSX's written facing nibble 0x04 and the sibling {2D} ops that turn the other
# onlookers East to face her. A naive (no-transpose) mapping yields 0x000 (the
# bug this pins).
func _test_godot_geometry_transpose() -> void:
	var vm := ScenarioVM.new()
	var affected := Node3D.new()
	var faced := Node3D.new()
	# Nodes must be in-tree for global_position to resolve (else it returns 0).
	add_child(affected)
	add_child(faced)
	affected.global_position = Vector3(6.5, 1.0, 5.5)  # 0x0c seat (6,5)
	faced.global_position = Vector3(0.5, 1.0, 5.5)      # knight 0x84 (0,5)
	_assert_eq(vm._face_unit_look_at_12bit(affected, faced), 0x400,
		"Godot geometry 0x0c(6,5) → 0x84(0,5): same row, knight −X → 0x400 (East)")
	# Swapping affected/faced points the look-at the other way along the lateral
	# axis — exercises the +ΔGodot_x sign of the transpose (NOT a cardinal-opposite
	# claim; the S/E/W/N wheel encoding is non-uniform, so just lock the formula).
	_assert_eq(vm._face_unit_look_at_12bit(faced, affected), 0xC00,
		"Godot geometry reversed: knight→0x0c (knight +X) → 0xC00")
	affected.queue_free()
	faced.queue_free()
	vm.free()


# --- {53} single-turn vs {2C} mutual-turn (the Face Unit 2 port) --------------
# ROM: {2C} Face Unit 2 = the SAME evt0x53 handler dispatched with a1=0, whose
# a1==0 branch additionally rotates the FACED unit 180° back at the affected
# unit (face_unit_decode.md §11). So {53} rotates ONLY the affected unit; {2C}
# rotates BOTH, with the faced unit's target = the reverse look-at (180° from
# the affected's target). This pins the mutual behavior + the single-turn
# non-regression, using the same captured 0x0c/0x84 geometry.
func _test_face_unit_single_vs_mutual() -> void:
	# {53} Face Unit (mutual=false): affected turns, faced does NOT.
	var r53 := _run_face_unit(false)
	_assert_eq(r53["aff_turned"], true, "{53}: affected unit rotated")
	_assert_eq(r53["faced_turned"], false, "{53}: faced unit NOT rotated (single-turn)")
	_assert_eq(r53["aff_target"], 0x400, "{53}: affected target = 0x400 (East, look at knight)")

	# {2C} Face Unit 2 (mutual=true): BOTH turn; faced target is the 180° reverse.
	var r2c := _run_face_unit(true)
	_assert_eq(r2c["aff_turned"], true, "{2C}: affected unit rotated")
	_assert_eq(r2c["faced_turned"], true, "{2C}: faced unit ALSO rotated (mutual)")
	_assert_eq(r2c["aff_target"], 0x400, "{2C}: affected target = 0x400 (East)")
	_assert_eq(r2c["faced_target"], 0xC00, "{2C}: faced target = 0xC00 (180° reverse — they face each other)")
	# The two targets must be a 180° pair (0x800 apart in 12-bit space).
	_assert_eq((int(r2c["aff_target"]) + 0x800) & 0xFFF, int(r2c["faced_target"]),
		"{2C}: affected/faced targets are exactly 180° apart")


## Drive _do_face_unit with the captured 0x0c/0x84 geometry through a real VM +
## recording fake units. Returns which units rotated and to what target.
func _run_face_unit(mutual: bool) -> Dictionary:
	var vm := ScenarioVM.new()
	var affected := _RecordingUnit.new()
	var faced := _RecordingUnit.new()
	add_child(affected)
	add_child(faced)
	affected.global_position = Vector3(6.5, 1.0, 5.5)  # 0x0c seat (6,5)
	faced.global_position = Vector3(0.5, 1.0, 5.5)      # knight 0x84 (0,5)
	vm.units_by_id[0x0c] = affected
	vm.units_by_id[0x84] = faced
	var inst := {
		"name": ("Face Unit 2" if mutual else "Face Unit"),
		"offset": 0,
		"params": [
			{"name": "Faced Unit", "value": 0x84},
			{"name": "Units", "value": 0x0c},
			{"name": "Multi", "value": 0},
			{"name": "Direction", "value": 0},
			{"name": "Speed", "value": 0},
			{"name": "Delay", "value": 0},
		],
	}
	vm._do_face_unit(inst, mutual)
	var out := {
		"aff_turned": affected.rotate_calls.size() > 0,
		"faced_turned": faced.rotate_calls.size() > 0,
		"aff_target": (int(affected.rotate_calls[0][0]) if affected.rotate_calls.size() > 0 else -1),
		"faced_target": (int(faced.rotate_calls[0][0]) if faced.rotate_calls.size() > 0 else -1),
	}
	affected.queue_free()
	faced.queue_free()
	vm.free()
	return out


## Minimal Node3D that records scenario_rotate(target, dir, speed, delay) calls
## so the mutual-vs-single behavior can be asserted without the full unit stack.
class _RecordingUnit extends Node3D:
	var rotate_calls: Array = []
	func scenario_rotate(target_12bit: int, direction: int, speed: int, delay: int) -> void:
		rotate_calls.append([target_12bit, direction, speed, delay])
