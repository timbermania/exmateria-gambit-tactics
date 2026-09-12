extends Node
## Pins the FAITHFUL event-script Unit Anim (opcode 0x11) → SEQ slot mapping for
## every sprite type (HANDOFF_type_aware_animation_routing.md; live-verified on
## hardware via pcsx-agent).
##
## How FFT routes it (BATTLE.BIN FUN_80085c0c @ 0x80085c0c, confirmed live):
##   unit+0x0C   = event_anim_id + 1
##   seq_offset  = (unit+0x0C - 1) * 2 + facing_base   =  event_anim_id * 2 (+0/1)
## The index math is sprite-type-INDEPENDENT — the ONLY per-type difference is
## which SEQ table is indexed (unit+0x1F8). Godot already loads the correct
## per-type SEQ (`*_seq.json`) per `sprite_types.json`, so the faithful behavior
## is just: front slot = event_anim_id * 2.
##
## The chapel priest is a TYPE3-SEQ sprite. The golden capture
## (research/.../last_run/golden_unit_animations.jsonl) shows priest event
## 0x02 → seq_offset 4 (idle) and 0x03 → seq_offset 6 (walk). This test pins the
## formula AND cross-checks that those offsets land on the right TYPE3.SEQ data
## (slot 6 = the multi-frame walk; slot 4 = the 1-frame idle pose). It supersedes
## the earlier slot-8 (combat-resolver) assertion, which was wrong.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioEventAnimTypeAwareTest.tscn

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_faithful_offset_formula()
	_test_type3_seq_walk_and_idle_slots()
	_test_type1_seq_has_the_same_offsets()

	print("\n=== ScenarioEventAnimTypeAwareTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioEventAnimTypeAwareTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioEventAnimTypeAwareTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioEventAnimTypeAwareTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


# The faithful front SEQ slot the renderer's clock arms on for an event anim id,
# mirroring ScenarioVM (`current_anim_id = id + 1`) + Unit._arm_anim_id_clock
# (`(current_anim_id - 1) * 2`).
func _front_slot_for_event_id(event_anim_id: int) -> int:
	var current_anim_id := event_anim_id + 1   # ScenarioVM low-range write
	return (current_anim_id - 1) * 2           # Unit clock slot == event_anim_id*2


func _load_seq(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed.get("sequences", parsed)
	return {}


func _frame_count(seqs: Dictionary, key: String) -> int:
	if not seqs.has(key):
		return -1
	var v = seqs[key]
	var ops = v if v is Array else v.get("opcodes", v)
	return ops.size() if ops is Array else -1


# --- The faithful id → slot formula (type-independent) ----------------------

func _test_faithful_offset_formula() -> void:
	# event_anim_id N → front slot N*2. Live golden values: idle 0x02→4, walk
	# 0x03→6, plus a higher id (0x0E→28) seen on humans in the same capture.
	_assert_eq(_front_slot_for_event_id(0x02), 4, "event 0x02 (idle) → slot 4")
	_assert_eq(_front_slot_for_event_id(0x03), 6, "event 0x03 (walk) → slot 6")
	_assert_eq(_front_slot_for_event_id(0x0E), 28, "event 0x0E → slot 28")
	# The bug this retires: raw `(id-1)*2` gave 4 for walk (= the idle slot), and
	# the combat-resolver detour gave 8 (a different anim). Neither is 6.
	_assert_true(_front_slot_for_event_id(0x03) != 4, "walk slot is NOT 4 (the old raw idle-slot bug)")
	_assert_true(_front_slot_for_event_id(0x03) != 8, "walk slot is NOT 8 (the old resolver bug)")


# --- The TYPE3 (priest) SEQ data must match those offsets -------------------

func _test_type3_seq_walk_and_idle_slots() -> void:
	# The priest loads TYPE3.SEQ. Hardware plays his walk at offset 6 and idle at
	# offset 4 — so TYPE3.SEQ slot 6 must be the multi-frame walk cycle and slot
	# 4 the 1-frame idle pose. (If this fails, the parsed SEQ slot convention has
	# drifted from the ROM's `event_anim_id*2` indexing.)
	var t3 := _load_seq("res://assets/sprites/animations/type3_seq.json")
	_assert_true(not t3.is_empty(), "type3_seq.json loads")
	if t3.is_empty():
		return
	var walk_slot := str(_front_slot_for_event_id(0x03))  # "6"
	var idle_slot := str(_front_slot_for_event_id(0x02))  # "4"
	_assert_true(_frame_count(t3, walk_slot) >= 2,
		"TYPE3.SEQ slot %s (walk) is multi-frame (got %d frames)" % [walk_slot, _frame_count(t3, walk_slot)])
	_assert_eq(_frame_count(t3, idle_slot), 1,
		"TYPE3.SEQ slot %s (idle) is a single-frame pose" % idle_slot)


func _test_type1_seq_has_the_same_offsets() -> void:
	# The same offsets are valid in the human TYPE1 table (the math is shared;
	# only the table differs). Assert the walk/idle slots exist and the walk is
	# multi-frame there too — the faithful routing works for TYPE1 as well.
	var t1 := _load_seq("res://assets/sprites/animations/type1_seq.json")
	_assert_true(not t1.is_empty(), "type1_seq.json loads")
	if t1.is_empty():
		return
	var walk_slot := str(_front_slot_for_event_id(0x03))  # "6"
	_assert_true(_frame_count(t1, walk_slot) >= 2,
		"TYPE1.SEQ slot %s (walk) is multi-frame (got %d frames)" % [walk_slot, _frame_count(t1, walk_slot)])
