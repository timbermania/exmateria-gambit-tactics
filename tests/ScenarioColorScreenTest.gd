extends Node
## Tests for ScenarioVM's {0x3E} Color Screen — the full-screen, fiber-driven
## colour ramp that fades the whole framebuffer from a start RGB to an end RGB
## over Time frames, composited with a PSX ABR blend (Mode). It is the
## SCREEN-SPACE sibling of {0x33} Color Field (which is a palette-domain CLUT
## tint) — a genuinely different render path (an overlay quad on top of the
## composed frame, NOT a change to the colour stack).
##
## FFT decode (research/working_documents/COLOR_SCREEN_OPCODE_3E.md, static +
## live-pcsx grounded): the event VM spawns a kind-0xC fiber (FUN_801467dc) that
## lerps start->end in 2-frame steps (Time=10 -> 0,51,102,153,204,255), each push
## drawn as a Gouraud quad via FUN_8008efb4; Mode goes verbatim into the GP0 E1h
## draw-mode ABR field (0=½B+½F, 1=B+F additive, 2=B-F subtractive, 3=B+¼F).
## scn8 instr 275 = Mode 2 white-ramp => subtractive fade to BLACK (proven live:
## framebuffer brightness 8181 -> 0). The following {E5} Wait Task=12 blocks the
## VM on the kind-0xC fiber until the ramp lands on `end`.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioColorScreenTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_decode_scn8_body()
	_test_ramp_step_sequence()
	_test_active_and_snap()
	_test_mode_selects_blend()
	_test_draw_skips_at_black()
	_test_op_registered_and_blocks_until_done()
	_test_scn8_real_chunk_does_not_halt()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioColorScreenTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioColorScreenTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioColorScreenTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioColorScreenTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


func _assert_vec_near(got, want: Vector3, name: String) -> void:
	if got is Vector3 and got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


# --- instruction builder -----------------------------------------------------

func _color_screen_inst(mode: int, r1: int, g1: int, b1: int, r2: int, g2: int,
		b2: int, time: int) -> Dictionary:
	return {
		"name": "Color Screen", "opcode": 0x3E, "offset": 0,
		"params": [
			{"name": "Mode", "value": mode},
			{"name": "Red (1)", "value": r1},
			{"name": "Green (1)", "value": g1},
			{"name": "Blue (1)", "value": b1},
			{"name": "Red (2)", "value": r2},
			{"name": "Green (2)", "value": g2},
			{"name": "Blue (2)", "value": b2},
			{"name": "Time", "value": time},
		],
	}


# --- tests -------------------------------------------------------------------

## The scn8 instr-275 body `3E 02 00 00 00 FF FF FF 0A 00` decodes to Mode 2, a
## black->white ramp over Time 10. Start/End are UNSIGNED 0..255 (not signed
## deltas like {32}/{33}); Time is a 2-byte value.
func _test_decode_scn8_body() -> void:
	var args := EventInstructionSet.args(_color_screen_inst(2, 0, 0, 0, 255, 255, 255, 10))
	var intent := ScenarioDecode.color_screen(args)
	_assert_eq(intent.mode, 2, "decode mode=2")
	_assert_vec_near(intent.start, Vector3(0, 0, 0), "decode start=(0,0,0)")
	_assert_vec_near(intent.end, Vector3(255, 255, 255), "decode end=(255,255,255)")
	_assert_eq(intent.time, 10, "decode time=10")


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _make_color_screen() -> ScenarioColorScreen:
	var cs := ScenarioColorScreen.new()
	add_child(cs)  # _ready() builds the (guarded) render node
	_vms.append(cs)
	return cs


func _intent(mode: int, start: Vector3, end: Vector3, time: int) -> ScenarioDecode.ColorScreenIntent:
	var i := ScenarioDecode.ColorScreenIntent.new()
	i.mode = mode
	i.start = start
	i.end = end
	i.time = time
	return i


## The worker (FUN_801467dc) lerps start->end in steps of 2 frames: iVar6 =
## 0,2,4,6,8 then snaps to end. For start=0 end=255 Time=10 that is the live-
## captured sequence 0,51,102,153,204,255 — one NEW step every 2 ticks, landing
## exactly on `end` at tick == Time.
func _test_ramp_step_sequence() -> void:
	var cs := _make_color_screen()
	cs.start(_intent(2, Vector3.ZERO, Vector3(255, 255, 255), 10))
	var seq := [0, 51, 102, 153, 204, 255]
	for i in range(seq.size()):
		var v := float(seq[i])
		_assert_vec_near(cs.current_color(), Vector3(v, v, v), "step %d @ %d ticks" % [i, i * 2])
		cs.tick()
		cs.tick()
	# Landed on end and stopped ramping.
	_assert_vec_near(cs.current_color(), Vector3(255, 255, 255), "holds end after ramp")


## is_active() drives the {E5} Task=0x0C barrier: true while ramping, false once
## landed on end. Time=0 snaps instantly (PSX skips the ramp loop).
func _test_active_and_snap() -> void:
	var cs := _make_color_screen()
	cs.start(_intent(2, Vector3.ZERO, Vector3(255, 255, 255), 10))
	_assert_true(cs.is_active(), "active while ramping")
	# Still active partway.
	for _t in range(6):
		cs.tick()
	_assert_true(cs.is_active(), "still active mid-ramp")
	for _t in range(6):
		cs.tick()
	_assert_true(not cs.is_active(), "inactive after landing on end")

	# Time=0 => instant snap, never blocks.
	var cs0 := _make_color_screen()
	cs0.start(_intent(1, Vector3.ZERO, Vector3(100, 100, 100), 0))
	_assert_vec_near(cs0.current_color(), Vector3(100, 100, 100), "time=0 snaps to end")
	_assert_true(not cs0.is_active(), "time=0 not active")


## Mode picks the ABR blend shader (0=mix,1=add,2=sub,3=quarter-add), clamped to
## the 4-shader family; each mode shader loads/compiles.
func _test_mode_selects_blend() -> void:
	for m in [0, 1, 2, 3]:
		var cs := _make_color_screen()
		cs.start(_intent(m, Vector3.ZERO, Vector3(255, 255, 255), 10))
		_assert_eq(cs.blend_mode(), m, "mode %d selected" % m)
	var cs_hi := _make_color_screen()
	cs_hi.start(_intent(9, Vector3.ZERO, Vector3(255, 255, 255), 10))
	_assert_eq(cs_hi.blend_mode(), 3, "mode>3 clamps to 3")
	for p in ScenarioColorScreen.MODE_SHADER_PATHS:
		_assert_true((load(p) as Shader) != null, "blend shader loads: %s" % p)


## FUN_8008f208 skips the quad entirely at colour (0,0,0). The scn8 ramp starts
## at (0,0,0), so the overlay draws nothing until the colour climbs off black.
func _test_draw_skips_at_black() -> void:
	var cs := _make_color_screen()
	cs.start(_intent(2, Vector3.ZERO, Vector3(255, 255, 255), 10))
	_assert_true(not cs.is_drawing(), "no draw at black start (0,0,0)")
	cs.tick()
	cs.tick()  # -> (51,51,51)
	_assert_true(cs.is_drawing(), "draws once colour climbs off black")


## The {3E} handler is bound (not the null-halt path) and, being a kind-0xC fiber,
## the following {E5} Wait For Instruction(Task=12) blocks the VM until the ramp
## lands on `end`. Ticked via the unified _tick_once clock (outside the halt gate).
func _test_op_registered_and_blocks_until_done() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.COLOR_SCREEN),
		"Color Screen handler registered (not null-halt)")
	vm._op_color_screen(_color_screen_inst(2, 0, 0, 0, 255, 255, 255, 10))
	_assert_true(vm._task_kind_live(0x0C, null),
		"{E5} Task=12 blocks while the ramp is in flight")
	# Advance on the unified clock; the ramp ticks outside the halt gate.
	for _t in range(14):
		vm._tick_once()
	_assert_true(not vm._task_kind_live(0x0C, null),
		"{E5} Task=12 releases once the ramp lands on end")


## The real scenario-8 chunk carries the Color Screen op at instr 275 (the
## fade-to-black scene-out). Before this opcode was implemented the VM HALTED here
## (the first genuine gap after scenario 6). Dispatching it must keep the VM running.
const SCN8_CHUNK := "res://assets/scenarios/chunks/scenario_008_chunk.json"

func _test_scn8_real_chunk_does_not_halt() -> void:
	var vm := _make_vm()
	var ok := vm.load_chunk_json(SCN8_CHUNK)
	_assert_true(ok, "loaded real scenario_008_chunk.json")
	if not ok:
		return
	vm.start()
	var count := 0
	for inst in vm._insts:
		if str(inst.get("name", "")) != "Color Screen":
			continue
		vm._op_color_screen(inst)
		count += 1
		_assert_true(vm._running, "VM still running after the scn8 Color Screen op")
	_assert_true(count > 0, "scn8 chunk contains a Color Screen op")
