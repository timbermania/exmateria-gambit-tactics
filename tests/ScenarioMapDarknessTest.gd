extends Node
## Tests for ScenarioVM's {1A} Map Darkness ("oxide") screen-tint opcode — the
## Orbonne prayer-scene darken/untint that brackets the prayer text.
##
## FFT decode (research/working_documents/scenario_1_captures/
## map_darkness_oxide_decode.md + HANDOFF): the opcode's real applier
## FUN_80090840 selects 1 of 11 Blend modes; scenario 1 uses Blend==4 ("byte-
## register add"): target = rest_baseline + signed(R,G,B), animated over Time*8
## frames. Rest baseline (live-captured) = (20,4,0). The two scenario-1 arms
## darken to (40,35,31) then untint back to (20,4,0).
##
## Render (2026-07-05): the {1A} subtractive quad is a PHANTOM — PSX savestates +
## live pokes across scn4/scn6/scn1 prove it moves ~0 px, and the real map darken is
## the {33} CLUT fade. So the faithful default renders NOTHING (transparent black);
## the accumulator ramp is still maintained (it mirrors PSX RAM state). The old
## opt-in legacy subtract (env `SCN_OXIDE_RENDER=1`) has been removed now that the
## phantom conclusion is final. See MAP_FLASH_SCENARIO4_PERSISTENT_DARK.md §4.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioMapDarknessTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const CHUNK_PATH := "res://assets/scenarios/scenario_1_chunk.json"

## Minimal stand-in for DialogueOverlay: reports `is_active()` for a fixed number
## of ticks to model the prayer typewriter still printing. The overlay is
## NON-blocking — the VM does NOT arm a wait_until on it, so the post-prayer
## Wait/untint/re-orient opcodes keep dispatching while this still reports active.
## Mirrors the real overlay's interface (DialogueOverlay.gd): `advance_frames(n)`
## drives the type-out clock (the VM ticks it once per frame) and `is_active()` is
## a side-effect-free poll — the two must be distinct or the barrier poll double-
## counts the countdown.
class StubOverlay extends Node:
	var _ticks_active: int = 0
	var active_ticks: int = 150
	## Signature must track `DialogueOverlay.show_overlay`. `ScenarioWorld` calls it with
	## FIVE arguments (`tokens, psx_x, psx_y, 0, dialog`); this took three, so the call
	## threw, the production function aborted, and `_ticks_active` was never set — leaving
	## `is_active()` false from the first tick. The "typewriter longer than the Wait 86 —
	## must NOT gate the untint" assertion below was therefore vacuous: there was no
	## typewriter running to fail to gate anything. #466.
	func show_overlay(_tokens, _x, _y, _color_palette: int = 0, _dialog: int = 0x09) -> void:
		_ticks_active = active_ticks
	func clear() -> void:
		pass
	func advance_frames(n: int) -> void:
		_ticks_active = maxi(0, _ticks_active - n)
	func is_active() -> bool:
		return _ticks_active > 0

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_handler_registered()
	_test_signed_byte()
	_test_blend4_target_math()
	_test_duration_is_time_times_eight()
	_test_time_zero_snaps()
	_test_darken_untint_ramps_accumulator()
	_test_real_chunk_arms_do_not_halt()
	_test_prayer_overlay_untint_fires_during_typewriter()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioMapDarknessTest: %d passed, %d failed ===" %
		[_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioMapDarknessTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioMapDarknessTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioMapDarknessTest")
		get_tree().quit(0)


func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


# --- Fixture builders --------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _darken_inst() -> Dictionary:
	# Scenario-1 PC 250: `1a 04 14 1f 1f 04` — Blend=4 R=20 G=31 B=31 Time=4.
	return {
		"name": "Map Darkness", "opcode": 0x1A, "offset": 250,
		"params": [
			{"name": "Blend", "value": 4},
			{"name": "Red", "value": 20},
			{"name": "Green", "value": 31},
			{"name": "Blue", "value": 31},
			{"name": "Time", "value": 4},
		],
	}


func _untint_inst() -> Dictionary:
	# Scenario-1 PC 274: `1a 04 00 00 00 04` — Blend=4 R=G=B=0 Time=4 (target=rest).
	return {
		"name": "Map Darkness", "opcode": 0x1A, "offset": 274,
		"params": [
			{"name": "Blend", "value": 4},
			{"name": "Red", "value": 0},
			{"name": "Green", "value": 0},
			{"name": "Blue", "value": 0},
			{"name": "Time", "value": 4},
		],
	}


# --- Cycle 1: dispatch-table wiring ------------------------------------------

func _test_handler_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.MAP_DARKNESS),
		"_handlers has 'Map Darkness'")
	# Prove it is the real handler, not the _op_skip no-op: dispatching the darken
	# arm must arm the fade ticker (a no-op would leave it at 0).
	vm._op_map_darkness(_darken_inst())
	_assert_true(vm._oxide_remaining_ticks > 0,
		"Map Darkness handler armed the oxide fade ticker (not a no-op)")


# --- Cycle 2: signed-byte helper ---------------------------------------------

func _test_signed_byte() -> void:
	_assert_eq(ScenarioVMClass._signed_byte(0), 0, "signed_byte(0)")
	_assert_eq(ScenarioVMClass._signed_byte(31), 31, "signed_byte(31)")
	_assert_eq(ScenarioVMClass._signed_byte(127), 127, "signed_byte(127)")
	_assert_eq(ScenarioVMClass._signed_byte(128), -128, "signed_byte(128)")
	_assert_eq(ScenarioVMClass._signed_byte(255), -1, "signed_byte(255)")


# --- Cycle 3: Blend==4 target math (target = baseline + signed(R,G,B)) --------

func _test_blend4_target_math() -> void:
	var vm := _make_vm()
	vm._op_map_darkness(_darken_inst())
	# baseline (20,4,0) + (20,31,31) = (40,35,31)
	_assert_eq(vm._oxide_target_byte, Vector3(40, 35, 31),
		"Blend=4 target = baseline + signed(R,G,B)")


# --- Cycle 4: duration = Time*8 ----------------------------------------------

func _test_duration_is_time_times_eight() -> void:
	var vm := _make_vm()
	vm._op_map_darkness(_darken_inst())  # Time=4 -> 32 ticks
	_assert_eq(vm._oxide_duration_ticks, 32, "duration = Time*8 = 32")
	_assert_eq(vm._oxide_remaining_ticks, 32, "remaining seeded to full duration")


# --- Cycle 5: Time==0 snaps instantly ----------------------------------------

func _test_time_zero_snaps() -> void:
	var vm := _make_vm()
	var inst := _darken_inst()
	inst["params"][4]["value"] = 0  # Time=0
	vm._op_map_darkness(inst)
	_assert_eq(vm._oxide_remaining_ticks, 0, "Time=0 leaves no pending fade")
	_assert_eq(vm._oxide_current_byte, Vector3(40, 35, 31),
		"Time=0 snaps current straight to target")


# --- Cycle 6: accumulator ramps as pure RAM-state (no render surface) ---------

func _test_darken_untint_ramps_accumulator() -> void:
	var vm := _make_vm()
	# Arm DARKEN, then run the ticker to completion (32 ticks). The accumulator ramps
	# to the target — it mirrors PSX RAM state and gates the Task=54 barrier. There is
	# no render surface: the {1A} subtractive quad was a proven phantom (MAP_FLASH §4
	# fix option a) and has been removed; the real map darken is the {33} CLUT fade.
	vm._op_map_darkness(_darken_inst())
	for _t in range(32):
		vm._tick_once()
	_assert_eq(vm._oxide_remaining_ticks, 0, "darken fade completed")
	_assert_eq(vm._oxide_current_byte, Vector3(40, 35, 31),
		"darken ramped the accumulator to the target (40,35,31)")

	# Arm UNTINT (target back to rest); the accumulator returns to baseline.
	vm._op_map_darkness(_untint_inst())
	for _t in range(32):
		vm._tick_once()
	_assert_eq(vm._oxide_remaining_ticks, 0, "untint fade completed")
	_assert_eq(vm._oxide_current_byte, Vector3(20, 4, 0),
		"untint ramped the accumulator back to rest (20,4,0)")


# --- Cycle 7: the real chapel chunk's two arms don't halt the VM -------------

func _test_real_chunk_arms_do_not_halt() -> void:
	# Before this opcode was implemented the VM set _running=false on the
	# unhandled 'Map Darkness'. Now both bracketing arms (chunk offsets 250/274)
	# must sail through with _running staying true.
	var vm := _make_vm()
	var ok := vm.load_chunk_json(CHUNK_PATH)
	_assert_true(ok, "loaded real scenario_1_chunk.json")
	if not ok:
		return
	# The decode places the two prayer arms at byte offsets 250 (darken) and 274
	# (untint), bracketing the prayer Display Message. (Later Map Darkness rows at
	# offsets 3154/6364 carry garbage Blend values — the disassembler walking past
	# valid code deeper in the chunk — and aren't the prayer effect.) Find the
	# prayer pair by their byte offset.
	var darken := {}
	var untint := {}
	for inst in vm._insts:
		if str(inst.get("name", "")) != "Map Darkness":
			continue
		if int(inst.get("offset", -1)) == 250:
			darken = inst
		elif int(inst.get("offset", -1)) == 274:
			untint = inst
	_assert_true(not darken.is_empty(), "darken arm present at byte offset 250")
	_assert_true(not untint.is_empty(), "untint arm present at byte offset 274")
	if darken.is_empty() or untint.is_empty():
		return
	# Dispatch each arm directly; neither should halt the VM.
	vm.start()
	vm._op_map_darkness(darken)
	_assert_true(vm._running, "VM still running after the darken arm")
	vm._op_map_darkness(untint)
	_assert_true(vm._running, "VM still running after the untint arm")


# --- Cycle 8: the prayer overlay is NON-blocking — the untint fires on schedule

func _test_prayer_overlay_untint_fires_during_typewriter() -> void:
	# The real prayer beat is: darken (idx 41) -> overlay Display Message (idx 42,
	# ~10 s of text) -> Wait 86 -> untint (idx 44). The overlay has NO advance gate
	# and does NOT lock the event queue: dynamic PSX capture shows the `Wait 0x56`
	# (idx 43) ran straight after the Display Message while the self-timed
	# typewriter kept printing (display_message_overlay_decode.md §round-2:
	# "event_dialogue_tick fired exactly 86 times = the Wait 0x56"). So the
	# darken->untint gap is just the Wait 86 (~87 ticks), NOT the typewriter
	# duration. The script's real wait on the prayer is the later Wait For
	# Instruction Task=1 at idx 50, not the Display Message. A regression that
	# re-armed a wait_until on the overlay froze idx 43-46 — including the praying
	# actor's cinematic re-orient at idx 46 — until the text ended.
	var vm := _make_vm()
	var ov := StubOverlay.new()
	ov.active_ticks = 150  # typewriter longer than the Wait 86 — must NOT gate the untint
	add_child(ov)
	vm.dialogue_overlay = ov
	vm.dialog_auto_advance = true
	var ok := vm.load_chunk_json(CHUNK_PATH)
	_assert_true(ok, "loaded real scenario_1_chunk.json")
	if not ok:
		return
	vm.start()
	vm._contexts[0].pc = 40  # Wait 180, just before the darken arm

	var darken_tick := -1
	var untint_tick := -1
	var typewriter_ran := false      # was the stub EVER active during the window?
	var typewriter_at_untint := false  # …and still running when the untint fired?
	for t in range(1, 2000):
		vm._tick_once()
		if ov.is_active():
			typewriter_ran = true
		if vm._oxide_remaining_ticks > 0 and darken_tick < 0 \
				and vm._oxide_target_byte == Vector3(40, 35, 31):
			darken_tick = t
		if darken_tick >= 0 and untint_tick < 0 \
				and vm._oxide_target_byte == Vector3(20, 4, 0) \
				and vm._oxide_remaining_ticks > 0:
			untint_tick = t
			typewriter_at_untint = ov.is_active()
			break

	_assert_true(darken_tick > 0, "darken arm fired")
	_assert_true(untint_tick > 0, "untint arm fired")
	# NON-VACUITY, asserted rather than assumed (#466). The stub's `show_overlay` used to
	# take three arguments where production passes five, so the call threw, `_ticks_active`
	# was never set, and `is_active()` was false from the first tick — the gap assertion
	# below then proved the untint is not gated by a typewriter that was never running.
	# These two make the premise a checked fact: if the stub ever silently stops being
	# driven again, THIS goes red rather than the claim going quiet.
	_assert_true(typewriter_ran,
		"the stub typewriter actually ran — the gap claim below has a premise")
	_assert_true(typewriter_at_untint,
		"…and was STILL running when the untint fired, which is what 'not gated' means")
	if darken_tick < 0 or untint_tick < 0:
		return
	var gap := untint_tick - darken_tick
	# Just the Wait 86 plus a few dispatch ticks. Crucially BELOW the 150-tick
	# typewriter, proving the overlay did not gate the untint (the regression gave
	# gap >= 236). Bracket loosely to avoid over-fitting the exact dispatch offset.
	_assert_true(gap >= 80 and gap < 130,
		"untint fires ~Wait-86 in, not gated by typewriter (gap=%d ticks, expected 80..130)" % gap)
	ov.queue_free()
