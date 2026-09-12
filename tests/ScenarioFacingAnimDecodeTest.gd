extends Node
## Pure tests for ScenarioVM's Unit Anim (0x11) + Rotate Unit (0x2D) decoders.
## Vectors are live-captured PCSX bytes from the orbonne-prayer cinematic
## (see `research/working_documents/scenario_1_captures/event_unit_anim_decode.md`,
## 2026-06-24 "later" sections). These pin the u16 chunk_unit_id reconstruction
## (`Units | Multi<<8`), the u16 anim_id, and the Facing-mode dispatch table.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioFacingAnimDecodeTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")


# Minimal stand-in for AnimationPlayback / UnitAnimationSet that captures the
# arguments `_op_unit_anim` passes to `unit.type1_playback.start(key, seqs)`.
class FakeAnimSet extends RefCounted:
	var type1_seq: Dictionary = {}

class FakePlayback extends RefCounted:
	var last_start_key: String = ""
	var last_start_seqs: Dictionary = {}
	var start_count: int = 0
	func start(new_anim_id: String, seqs: Dictionary, _start_frame: int = 0) -> void:
		last_start_key = new_anim_id
		last_start_seqs = seqs
		start_count += 1

# The render module now owns the BODY playback (issue #144). ScenarioVM's
# readiness guard + cinematic pause read `unit.display.type1_playback`, so the
# fake models the same seam rather than a Unit-level `type1_playback` mirror.
class FakeDisplay extends RefCounted:
	var type1_playback: FakePlayback
	func _init(pb: FakePlayback) -> void:
		type1_playback = pb

class FakeUnit extends RefCounted:
	var animation_set: FakeAnimSet
	var display: FakeDisplay
	var type1_playback: FakePlayback
	var scenario_rotate_calls: Array = []
	# Path D (ADR-0053): _op_unit_anim writes current_anim_id directly. EVTCHR
	# range (>= 0x258) writes the raw id; low range writes `event_anim_id + 1`
	# (mirroring hardware unit+0x0C). Mirrors the real Unit.current_anim_id.
	var current_anim_id: int = 0
	# `_op_rotate_unit` reads `facing_angle` (-1 sentinel) and `anim_state`
	# (null OK — the elif fires anim_state.current_facing only when non-null);
	# declare both so the strict member-access check on RefCounted passes.
	var facing_angle: int = -1
	var anim_state = null
	func _init() -> void:
		animation_set = FakeAnimSet.new()
		type1_playback = FakePlayback.new()
		display = FakeDisplay.new(type1_playback)
	# The VM funnels body anims through the facade `play_body` (issue #144, C3b);
	# the double mirrors it onto `current_anim_id` the way real Unit does.
	func play_body(anim_id: int) -> void:
		current_anim_id = anim_id
	func scenario_rotate(target_12bit: int, direction: int, speed: int,
			delay: int) -> void:
		scenario_rotate_calls.append({
			"target_12bit": target_12bit,
			"direction": direction,
			"speed": speed,
			"delay": delay,
		})

var _failed: int = 0
var _passed: int = 0


# Build the inst dict in the same shape the JSON pipeline (disasm_event.py)
# emits: chunk_unit_id is split across `Units` (low byte) and `Multi` (high
# byte); anim_id is a u16 in `Animation`; the per-unit flag is `Unknown` u8.
func _make_unit_anim_inst(chunk_unit_id: int, anim_id: int, flag: int) -> Dictionary:
	return {
		"name": "Unit Anim",
		"opcode": 0x11,
		"offset": 0,
		"params": [
			{"name": "Units", "value": chunk_unit_id & 0xFF},
			{"name": "Multi", "value": (chunk_unit_id >> 8) & 0xFF},
			{"name": "Animation", "value": anim_id},
			{"name": "Unknown", "value": flag},
		],
	}


func _make_rotate_unit_inst(chunk_unit_id: int, facing: int, direction: int,
		speed: int, delay: int) -> Dictionary:
	return {
		"name": "Rotate Unit",
		"opcode": 0x2D,
		"offset": 0,
		"params": [
			{"name": "Units", "value": chunk_unit_id & 0xFF},
			{"name": "Multi", "value": (chunk_unit_id >> 8) & 0xFF},
			{"name": "Facing", "value": facing},
			{"name": "Direction", "value": direction},
			{"name": "Speed", "value": speed},
			{"name": "Delay", "value": delay},
		],
	}


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	return vm


func _ready() -> void:
	_test_unit_anim_decode_live_vectors()
	_test_rotate_unit_decode_live_vectors()
	_test_resolve_target_absolute_mode()
	_test_resolve_target_relative_mode()
	_test_resolve_target_camera_relative_mode()
	_test_op_unit_anim_dispatches_by_u16_id_to_high_range_anim()
	_test_op_unit_anim_low_range_writes_anim_plus_one()
	_test_op_rotate_unit_writes_absolute_target()
	_test_rotate_unit_registered_in_dispatch_table()

	print("\n=== ScenarioFacingAnimDecodeTest: %d passed, %d failed ===" %
		[_passed, _failed])
	# Treat zero assertions as failure too — a script error aborts mid-test
	# and would otherwise read PASS in the runner.
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioFacingAnimDecodeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioFacingAnimDecodeTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioFacingAnimDecodeTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- Cycle 1: Unit Anim decode -----------------------------------------------

func _test_unit_anim_decode_live_vectors() -> void:
	# Live PCSX captures from orbonne_prayer_mid_dialog.sstate. Raw bytes →
	# expected fields per `event_unit_anim_decode.md` § "Unit Anim handler
	# chain decoded".
	var vm := _make_vm()
	var cases := [
		# [raw_chunk_bytes_after_opcode, chunk_unit_id, anim_id, flag]
		[0x000C, 0x0259, 1],  # 11 0C 00 59 02 01 — Gafgarion narrator gesture
		[0x0034, 0x025B, 0],  # 11 34 00 5B 02 00 — chapel rotator (Priest or Agrias)
		[0x0034, 0x0002, 0],  # 11 34 00 02 00 00 — idle (anim < 0x1F4 path)
		[0x000C, 0x025D, 0],  # 11 0C 00 5D 02 00 — Gafgarion arrival
	]
	for c in cases:
		var inst := _make_unit_anim_inst(c[0], c[1], c[2])
		var out := ScenarioDecode.unit_anim(EventInstructionSet.args(inst))
		_assert_eq(out.units, c[0] & 0xFF, "Units 0x%02X" % (c[0] & 0xFF))
		_assert_eq(out.multi, (c[0] >> 8) & 0xFF, "Multi 0x%02X" % ((c[0] >> 8) & 0xFF))
		_assert_eq(out.anim_id, c[1],
			"anim_id 0x%04X" % c[1])
		_assert_eq(out.flag, c[2],
			"flag %d" % c[2])
	vm.queue_free()


# --- Cycle 2: Rotate Unit decode --------------------------------------------

func _test_rotate_unit_decode_live_vectors() -> void:
	# Live captures from SCUS94221.sstate9 BEFORE/AFTER `+0x70` diff (see
	# `event_unit_anim_decode.md` § "Rotate Unit (0x2D) decoded …").
	var vm := _make_vm()
	var cases := [
		# [chunk_unit_id, facing, direction, speed, delay]
		[0x0034, 0x04, 0x02, 0x01, 0x00],  # 2D 34 00 04 02 01 00
		[0x0013, 0x02, 0x01, 0x00, 0x00],  # 2D 13 00 02 01 00 00
	]
	for c in cases:
		var inst := _make_rotate_unit_inst(c[0], c[1], c[2], c[3], c[4])
		var out := ScenarioDecode.rotate_unit(EventInstructionSet.args(inst))
		_assert_eq(out.units, c[0] & 0xFF, "rot Units 0x%02X" % (c[0] & 0xFF))
		_assert_eq(out.multi, (c[0] >> 8) & 0xFF, "rot Multi 0x%02X" % ((c[0] >> 8) & 0xFF))
		_assert_eq(out.facing, c[1],
			"rot facing 0x%02X" % c[1])
		_assert_eq(out.direction, c[2],
			"rot direction %d" % c[2])
		_assert_eq(out.speed, c[3],
			"rot speed %d" % c[3])
		_assert_eq(out.delay, c[4],
			"rot delay %d" % c[4])
	vm.queue_free()


# --- Cycle 3: Rotate Unit absolute mode (Facing × 0x100) --------------------

func _test_resolve_target_absolute_mode() -> void:
	# Hacktics disasm at 0x80148284: when Facing byte is NOT in 0x10..0x14, it's
	# an absolute 16-direction angle: target = Facing * 0x100. Two live BEFORE/
	# AFTER captures verify this is the dominant chapel path.
	var vm := _make_vm()
	# current_12bit and camera_yaw_12bit are inputs but unused on the absolute
	# path — pass distinct, non-zero values to flush out accidental returns.
	var cur := 0xC00  # current facing North; the BEFORE values in the doc
	var cam := 0x400  # camera yaw (anything; absolute mode ignores it)
	_assert_eq(vm._resolve_rotate_target_12bit(0x02, cur, cam), 0x200,
		"Facing 0x02 → 0x200 (S-SE)")
	_assert_eq(vm._resolve_rotate_target_12bit(0x04, cur, cam), 0x400,
		"Facing 0x04 → 0x400 (East)")
	# Boundary checks the other absolute Facing values from the doc.
	_assert_eq(vm._resolve_rotate_target_12bit(0x00, cur, cam), 0x000,
		"Facing 0x00 → 0x000 (South)")
	_assert_eq(vm._resolve_rotate_target_12bit(0x08, cur, cam), 0x800,
		"Facing 0x08 → 0x800 (West)")
	_assert_eq(vm._resolve_rotate_target_12bit(0x09, cur, cam), 0x900,
		"Facing 0x09 → 0x900 (W-NW)")
	_assert_eq(vm._resolve_rotate_target_12bit(0x0C, cur, cam), 0xC00,
		"Facing 0x0C → 0xC00 (North)")
	_assert_eq(vm._resolve_rotate_target_12bit(0x0D, cur, cam), 0xD00,
		"Facing 0x0D → 0xD00 (NNW)")
	vm.queue_free()


# --- Cycle 4: Rotate Unit relative mode (Facing 0x11-0x13) ------------------

func _test_resolve_target_relative_mode() -> void:
	# Per hacktics disasm: Facing 0x11..0x13 = relative rotation, adds
	# `(Facing & 0xF) * 0x100` to the unit's current facing. Wraps at 0xFFF
	# (12-bit space).
	var vm := _make_vm()
	# +0x100 from East (0x400) → S-SSE (0x500).
	_assert_eq(vm._resolve_rotate_target_12bit(0x11, 0x400, 0), 0x500,
		"Facing 0x11 + cur 0x400 → 0x500")
	# +0x200 from North (0xC00) → N-NNE? (0xE00 = 0xC00+0x200).
	_assert_eq(vm._resolve_rotate_target_12bit(0x12, 0xC00, 0), 0xE00,
		"Facing 0x12 + cur 0xC00 → 0xE00")
	# +0x300 wraps past 0xFFF: 0xE00 + 0x300 = 0x1100 → 0x100.
	_assert_eq(vm._resolve_rotate_target_12bit(0x13, 0xE00, 0), 0x100,
		"Facing 0x13 + cur 0xE00 → 0x100 (wrap)")
	vm.queue_free()


# --- Cycle 5: Rotate Unit camera-relative mode (Facing 0x10) ----------------

func _test_resolve_target_camera_relative_mode() -> void:
	# Mode 0x10: target = camera_yaw_12bit & 0xC00 (snaps to nearest cardinal
	# axis in PSX 12-bit angle space — verifies the 0xC00 mask).
	var vm := _make_vm()
	# Camera at exactly East (0x400) → masked = 0x400.
	_assert_eq(vm._resolve_rotate_target_12bit(0x10, 0, 0x400), 0x400,
		"Facing 0x10, cam 0x400 → 0x400 (East)")
	# Camera at 0x300 (between S and E) → 0x300 & 0xC00 = 0x000 (snap S).
	_assert_eq(vm._resolve_rotate_target_12bit(0x10, 0, 0x300), 0x000,
		"Facing 0x10, cam 0x300 → 0x000 (snaps South)")
	# Camera at 0xD00 (between W and N) → 0xD00 & 0xC00 = 0xC00 (snap N).
	_assert_eq(vm._resolve_rotate_target_12bit(0x10, 0, 0xD00), 0xC00,
		"Facing 0x10, cam 0xD00 → 0xC00 (snaps North)")
	vm.queue_free()


# --- Cycle 6: _op_unit_anim u16 lookup + high-range anim --------------------

func _test_op_unit_anim_dispatches_by_u16_id_to_high_range_anim() -> void:
	# `11 0C 00 59 02 00` → chunk_unit_id 0x000C, anim_id 0x0259 (= 601 dec).
	# Path D (ADR-0053): handler looks the unit up by the FULL u16
	# chunk_unit_id and writes `unit.current_anim_id = anim_id`. The renderer
	# dispatches on the value range; the event-script writer's only
	# observable side-effect is the anim-id field on Unit.
	var vm := _make_vm()
	var fake := FakeUnit.new()
	fake.animation_set.type1_seq = {"601": {}, "2": {}}  # cinematic + idle
	vm.units_by_id = {0x000C: fake}

	var inst := _make_unit_anim_inst(0x000C, 0x0259, 0)
	# {11} now LATCHES at dispatch and paints on the next elapsed tick (the
	# pending-anim latch, SCENARIO_WAIT_SEMANTICS.md §8i). This cycle asserts the
	# painted decode (u16 lookup → anim-id field), so drain the latch to paint it.
	vm._op_unit_anim(inst)
	vm._consume_pending_body_anims()
	_assert_eq(fake.current_anim_id, 0x0259,
		"unit anim: current_anim_id == 0x0259 (Path D: ADR-0053)")
	vm.queue_free()


# --- Cycle 6b: _op_unit_anim writes event_anim_id+1 for the low range --------

func _test_op_unit_anim_low_range_writes_anim_plus_one() -> void:
	# HANDOFF_type_aware_animation_routing.md (live-verified): hardware stores
	# `event_anim_id + 1` at unit+0x0C; the per-frame SEQ player then indexes
	# slot `(unit+0x0C - 1)*2 = event_anim_id*2` into the unit's OWN per-type
	# SEQ table. The index math is sprite-type-INDEPENDENT, so the faithful
	# behavior for EVERY type is simply: write `anim_id + 1`. EVTCHR-range
	# (>= 0x258) keeps the raw write (the cinematic walker owns it).
	var vm := _make_vm()
	var fake := FakeUnit.new()
	vm.units_by_id = {0x0013: fake}

	# {11} latches at dispatch; the consumer paints on the next tick (§8i). Drain
	# it after each dispatch to assert the painted event_anim_id+1 decode.
	# Walk (0x03) → current_anim_id 0x04 → clock slot (4-1)*2 = 6.
	vm._op_unit_anim(_make_unit_anim_inst(0x0013, 0x0003, 0))
	vm._consume_pending_body_anims()
	_assert_eq(fake.current_anim_id, 0x04,
		"unit anim: walk 0x03 → current_anim_id 0x04 (event_anim_id + 1)")
	_assert_eq((fake.current_anim_id - 1) * 2, 6,
		"unit anim: walk 0x03 → clock slot 6 (the faithful walk offset)")

	# Idle (0x02) → current_anim_id 0x03 → clock slot (3-1)*2 = 4.
	vm._op_unit_anim(_make_unit_anim_inst(0x0013, 0x0002, 0))
	vm._consume_pending_body_anims()
	_assert_eq(fake.current_anim_id, 0x03,
		"unit anim: idle 0x02 → current_anim_id 0x03 (event_anim_id + 1)")
	_assert_eq((fake.current_anim_id - 1) * 2, 4,
		"unit anim: idle 0x02 → clock slot 4 (the idle pose offset)")
	vm.queue_free()


# --- Cycle 7: _op_rotate_unit calls scenario_rotate(target_12bit, …) --------

func _test_op_rotate_unit_writes_absolute_target() -> void:
	# Live capture: 2D 34 00 04 02 01 00 → Facing=0x04 (absolute East) →
	# target_12bit=0x400. Handler should look up the unit by u16 chunk_unit_id
	# 0x0034 and forward (target, direction, speed, delay) to scenario_rotate.
	var vm := _make_vm()
	var fake := FakeUnit.new()
	vm.units_by_id = {0x0034: fake}

	var inst := _make_rotate_unit_inst(0x0034, 0x04, 0x02, 0x01, 0x00)
	vm._op_rotate_unit(inst)
	_assert_eq(fake.scenario_rotate_calls.size(), 1,
		"rotate unit: scenario_rotate called exactly once")
	if fake.scenario_rotate_calls.size() == 1:
		var call: Dictionary = fake.scenario_rotate_calls[0]
		_assert_eq(int(call["target_12bit"]), 0x400,
			"rotate unit: target_12bit = 0x400 (Facing 0x04 absolute East)")
		_assert_eq(int(call["direction"]), 0x02, "rotate unit: direction == 2")
		_assert_eq(int(call["speed"]), 0x01, "rotate unit: speed == 1")
		_assert_eq(int(call["delay"]), 0x00, "rotate unit: delay == 0")
	vm.queue_free()


# --- Cycle 8: Rotate Unit registered in the opcode dispatch table -----------

func _test_rotate_unit_registered_in_dispatch_table() -> void:
	# The chunk emits opcode-NAME-keyed instructions ("Rotate Unit"). Without
	# a handler entry in `_handlers`, the VM halts on the first 0x2D — even
	# though `_op_rotate_unit` exists. Cover the wiring too so a future rename
	# can't silently regress.
	var vm := _make_vm()
	_assert_eq(vm._handlers.has(EventInstruction.ROTATE_UNIT), true,
		"_handlers has 'Rotate Unit' entry")
	_assert_eq(vm._handlers.has(EventInstruction.UNIT_ANIM), true,
		"_handlers has 'Unit Anim' entry (regression guard)")
	vm.queue_free()
