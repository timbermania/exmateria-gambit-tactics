extends Node
## Tests for ScenarioVM's {6B} BG Sound / {6A} Edit BG Sound — the Orbonne-battle
## ambient cues (scenario 4 PC 5 = Rain, Sound 1, fade 0→24 over 255 frames).
##
## FFT decode + LIVE PSX validation (D1–D6, research/working_documents/
## BGSOUND_OPCODE_6B_INVESTIGATION.md): {6B} spawns a cooperative task (kind
## 0x35) that plays env-bank sound `Sound` (handle 0x10000|Sound) and runs a
## linear volume ramp StartVol→Volume over Time frames — one step per 60 Hz
## vsync, intermediates floored at 1, landing on the exact Volume (which may be
## 0 = key-off). `Time=0` snaps. {6A} Edit BG Sound is the SAME ramp on an
## already-playing bg sound, no re-trigger. op[1] is the ramp START volume, NOT
## "Echo" (wiki wrong — the min-1 guard is the tell).
##
## Backend-independent: the ramp MODEL (ScenarioBgSound) is pure; the VM handler
## is exercised via the bg_sound_changed signal + a handle-0 ticker so the test
## is green whether or not a live SPU is up.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioBgSoundTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const BgSound = preload("res://src/scenarios/ScenarioBgSound.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []
var _bg_events: Array = []


func _ready() -> void:
	# Pure-model.
	_test_min1_guard_initial()
	_test_time0_snap()
	_test_fade_in_0_to_24_steps()
	_test_fade_out_to_zero_keys_off()
	_test_idle_after_settle()
	# Operand parsing (positional — the {6A} two-"Unknown" collision case).
	_test_operands_positional_6b()
	_test_operands_positional_6a_two_unknowns()
	# VM integration.
	_test_handlers_registered()
	_test_op_bg_sound_dispatch_and_registers()
	_test_op_edit_bg_sound_reramps_no_retrigger()
	_test_op_edit_missing_sound_is_noop()
	_test_vm_ticker_advances_ramp()
	_test_task_kind_0x35_registered_and_liveness()
	_test_restart_clears_bg_sounds()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioBgSoundTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioBgSoundTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioBgSoundTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioBgSoundTest")
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


# --- pure-model tests --------------------------------------------------------

func _test_min1_guard_initial() -> void:
	# StartVol=0 must begin AUDIBLE at 1 (vol 0 keys the just-started voice off).
	var bg = BgSound.new()
	bg.start_ramp(0, 24, 255)
	_assert_eq(bg.vol, 1, "StartVol=0 initial vol floored to 1")
	# A non-zero StartVol is used verbatim as the initial volume.
	var bg2 = BgSound.new()
	bg2.start_ramp(7, 24, 10)
	_assert_eq(bg2.vol, 7, "StartVol=7 initial vol = 7")


func _test_time0_snap() -> void:
	var bg = BgSound.new()
	bg.start_ramp(0, 24, 0)
	_assert_eq(bg.vol, 24, "Time=0 snaps straight to Volume")
	_assert_true(not bg.tick(), "Time=0 arms no ramp")


func _test_fade_in_0_to_24_steps() -> void:
	# Clean 0→24 over 24 frames: integer ramp 1,2,...,24, monotone, exact target.
	var bg = BgSound.new()
	bg.start_ramp(0, 24, 24)
	_assert_eq(bg.vol, 1, "initial floored to 1")
	var seq: Array = []
	var prev: int = bg.vol
	var monotone := true
	while bg.tick():
		if bg.vol < prev:
			monotone = false
		prev = bg.vol
		seq.append(bg.vol)
	_assert_true(monotone, "fade-in is monotone non-decreasing")
	_assert_eq(seq.size(), 24, "fade-in runs Time (24) frames")
	_assert_eq(bg.vol, 24, "fade-in lands on exact Volume=24")
	_assert_eq(seq[seq.size() - 1], 24, "last frame is exact target")
	# The 255-frame scenario-4 rain: stays at 1 until the lerp crosses 1, then
	# climbs to exactly 24. (24*k/255 == 0 for k<=10 → floored to 1.)
	var rain = BgSound.new()
	rain.start_ramp(0, 24, 255)
	var frames := 0
	var maxv: int = rain.vol
	while rain.tick():
		frames += 1
		maxv = maxi(maxv, rain.vol)
	_assert_eq(frames, 255, "rain ramp runs 255 frames")
	_assert_eq(rain.vol, 24, "rain lands on exact 24")
	_assert_eq(maxv, 24, "rain never overshoots 24")


func _test_fade_out_to_zero_keys_off() -> void:
	# Target=0 is a valid endpoint: fade to silence, final exactly 0 (key-off).
	var bg = BgSound.new()
	bg.start_ramp(10, 0, 4)
	while bg.tick():
		pass
	_assert_eq(bg.vol, 0, "fade to Target=0 ends at exactly 0")


func _test_idle_after_settle() -> void:
	var bg = BgSound.new()
	bg.start_ramp(0, 24, 3)
	_assert_true(not bg.is_idle(), "ramping bg is not idle")
	while bg.tick():
		pass
	_assert_true(bg.is_idle(), "settled bg is idle")


# --- operand parsing ---------------------------------------------------------

func _test_operands_positional_6b() -> void:
	# Scenario-4 PC 5: 6b 01 00 18 00 ff.
	var inst := {
		"name": "BG Sound", "opcode": 0x6B, "offset": 0,
		"params": [
			{"name": "Sound", "value": 1},
			{"name": "Echo", "value": 0},       # actually StartVol
			{"name": "Volume?", "value": 24},
			{"name": "Unknown", "value": 0},     # Stacking
			{"name": "Time?", "value": 255},
		],
	}
	# Read positionally through EventInstructionArgs — the path the handler now
	# takes (ADR-0059 Phase 2 retired the bespoke _bg_operands helper).
	var a := EventInstructionSet.args(inst)
	var op := [a.nth(0), a.nth(1), a.nth(2), a.nth(3), a.nth(4)]
	_assert_eq(op, [1, 0, 24, 0, 255], "{6B} operands parsed positionally")


func _test_operands_positional_6a_two_unknowns() -> void:
	# {6A} has TWO params both named "Unknown" (Stacking + Time) — a name-keyed
	# dict would collapse them; positional read keeps op[3] and op[4] distinct.
	var inst := {
		"name": "Edit BG Sound", "opcode": 0x6A, "offset": 0,
		"params": [
			{"name": "Sound", "value": 11},
			{"name": "Echo", "value": 36},
			{"name": "Volume", "value": 20},
			{"name": "Unknown", "value": 3},     # Stacking
			{"name": "Unknown", "value": 60},    # Time (would be lost if name-keyed)
		],
	}
	var a := EventInstructionSet.args(inst)
	_assert_eq(a.nth(3), 3, "{6A} op[3] Stacking distinct from op[4]")
	_assert_eq(a.nth(4), 60, "{6A} op[4] Time not clobbered by name collision")
	# The reader preserves the dup name distinctly (the crux _bg_operands hacked around).
	_assert_eq(a.all("Unknown"), [3, 60], "{6A} both Unknown operands preserved")


# --- VM integration ----------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _bg_inst(sound: int, start_vol: int, volume: int, stacking: int, time: int) -> Dictionary:
	return {
		"name": "BG Sound", "opcode": 0x6B, "offset": 0,
		"params": [
			{"name": "Sound", "value": sound},
			{"name": "Echo", "value": start_vol},
			{"name": "Volume?", "value": volume},
			{"name": "Unknown", "value": stacking},
			{"name": "Time?", "value": time},
		],
	}


func _test_handlers_registered() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.BG_SOUND), "{6B} BG Sound handler registered")
	_assert_true(vm._handlers.has(EventInstruction.EDIT_BG_SOUND), "{6A} Edit BG Sound handler registered")


func _test_op_bg_sound_dispatch_and_registers() -> void:
	var vm := _make_vm()
	_bg_events.clear()
	SfxRouter.bg_sound_changed.connect(_on_bg_event)
	vm._op_bg_sound(_bg_inst(1, 0, 24, 0, 255))
	SfxRouter.bg_sound_changed.disconnect(_on_bg_event)
	# The "play" cue fires pre-dispatch regardless of SPU readiness.
	var saw_play := false
	for e in _bg_events:
		if e[0] == "play" and e[1] == 1 and e[2] == 0:
			saw_play = true
	_assert_true(saw_play, "{6B} emits play cue (sound=1, stacking=0)")
	# If the SPU backend actually produced a handle, the ramp is tracked with the
	# right endpoints. (Skipped cleanly when no SPU is up.)
	if vm._bg_sounds.has(1):
		var bg: BgSound = vm._bg_sounds[1]
		_assert_eq(bg.sound_id, 1, "registered bg sound_id=1")
		_assert_eq(bg.stacking, 0, "registered bg stacking=0")
		_assert_true(bg.loop, "Rain 1 is a looping ambient")
		_assert_eq(bg.vol, 1, "initial vol floored to 1")


func _test_op_edit_bg_sound_reramps_no_retrigger() -> void:
	var vm := _make_vm()
	# Seed a live bg sound directly (backend-independent).
	var bg = BgSound.new()
	bg.sound_id = 5
	bg.handle = 0  # set_bg_volume(0,...) is a safe no-op
	bg.start_ramp(1, 30, 10)
	vm._bg_sounds[5] = bg
	# {6A} Edit: re-ramp 30→8 over 4 frames, no re-trigger.
	var inst := {
		"name": "Edit BG Sound", "opcode": 0x6A, "offset": 0,
		"params": [
			{"name": "Sound", "value": 5},
			{"name": "Echo", "value": 30},
			{"name": "Volume", "value": 8},
			{"name": "Unknown", "value": 0},
			{"name": "Unknown", "value": 4},
		],
	}
	vm._op_edit_bg_sound(inst)
	# Same object re-ramped (no new handle / no new registry entry).
	_assert_true(vm._bg_sounds[5] == bg, "{6A} edits the same bg object (no retrigger)")
	while bg.tick():
		pass
	_assert_eq(bg.vol, 8, "{6A} re-ramp lands on new target 8")


func _test_op_edit_missing_sound_is_noop() -> void:
	var vm := _make_vm()
	var inst := {
		"name": "Edit BG Sound", "opcode": 0x6A, "offset": 0,
		"params": [
			{"name": "Sound", "value": 99},
			{"name": "Echo", "value": 1},
			{"name": "Volume", "value": 5},
			{"name": "Unknown", "value": 0},
			{"name": "Unknown", "value": 2},
		],
	}
	vm._op_edit_bg_sound(inst)  # must not crash / must not register
	_assert_true(not vm._bg_sounds.has(99), "{6A} on absent sound is a no-op")


func _test_vm_ticker_advances_ramp() -> void:
	# The bg ramp block in _tick_once runs BEFORE the _running guard, so a bare VM
	# advances it. handle=0 → set_bg_volume no-op, so this is backend-independent.
	var vm := _make_vm()
	var bg = BgSound.new()
	bg.sound_id = 5
	bg.handle = 0
	bg.start_ramp(0, 24, 24)
	vm._bg_sounds[5] = bg
	for i in range(24):
		vm._tick_once()
	_assert_eq(bg.vol, 24, "VM ticker drives the ramp to the target")
	_assert_true(bg.is_idle(), "ramp settled after Time ticks")


func _test_task_kind_0x35_registered_and_liveness() -> void:
	var vm := _make_vm()
	_assert_true(vm._task_liveness.has(vm.TASK_BGSOUND), "kind 0x35 registered in liveness registry")
	_assert_eq(vm.TASK_BGSOUND, 53, "TASK_BGSOUND == 0x35")
	# Live while a ramp is in flight; releases once settled.
	var bg = BgSound.new()
	bg.sound_id = 5
	bg.handle = 0
	bg.start_ramp(0, 24, 3)
	vm._bg_sounds[5] = bg
	_assert_true(vm._task_kind_live(vm.TASK_BGSOUND, null), "bg task live while ramping")
	for i in range(3):
		vm._tick_once()
	_assert_true(not vm._task_kind_live(vm.TASK_BGSOUND, null), "bg task clears once ramp settles")


func _test_restart_clears_bg_sounds() -> void:
	var vm := _make_vm()
	var bg = BgSound.new()
	bg.sound_id = 5
	bg.handle = 0
	bg.start_ramp(0, 24, 24)
	vm._bg_sounds[5] = bg
	vm.start()  # a (re)start must drop live ambients so a replay re-triggers them
	_assert_true(vm._bg_sounds.is_empty(), "start() clears _bg_sounds")


func _on_bg_event(action: String, sound_id: int, stacking: int, handle: int) -> void:
	_bg_events.append([action, sound_id, stacking, handle])
