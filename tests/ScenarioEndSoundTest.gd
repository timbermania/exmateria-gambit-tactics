extends Node
## Tests for ScenarioVM's {7C} End Sound — the scenario-tail opcode that stops
## the currently-playing event SFX/BGM before the battle hand-off (scenario 6
## "Abducting the Princess", idx 455).
##
## FFT decode + LIVE PSX validation (research/working_documents/
## SCENARIO6_UNKNOWN_OPCODES_6D_71_7C_82_INVESTIGATION.md §4): {7C} dispatches to
## SUB_800440cc, which zeroes the active-sound handle (DAT_8004599c) and runs an
## 8-voice teardown (FUN_80012860) — i.e. stop all currently-playing event sound.
## The Godot mirror is SfxRouter.stop_all_event_sound() (stop every tracked bg
## voice + clear the tracked handle); the VM handler also drops its live bg ramps.
##
## Backend-independent: SfxRouter/ExMateriaEffectSfx tolerate a null SPU (stop calls
## no-op on unknown handles), and observability rides the bg_sound_changed signal.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioEndSoundTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const BgSound = preload("res://src/scenarios/ScenarioBgSound.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []
var _bg_events: Array = []


func _ready() -> void:
	_test_stop_all_event_sound_stops_tracked_voice()
	_test_op_end_sound_clears_live_bg_ramps()
	_test_op_end_sound_tears_down_router_voices()
	_test_handler_registered_and_named()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioEndSoundTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioEndSoundTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioEndSoundTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioEndSoundTest")
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


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _on_bg_event(action: String, sound_id: int, stacking: int, handle: int) -> void:
	_bg_events.append([action, sound_id, stacking, handle])


# --- SfxRouter teardown ------------------------------------------------------

func _test_stop_all_event_sound_stops_tracked_voice() -> void:
	# Seed a live tracked bg voice + an overlay voice (backend-independent: the
	# stop calls no-op on unknown handles when no SPU is up).
	SfxRouter._bg_by_sound = {7: 111, 9: 222}
	SfxRouter._bg_tracked_handle = 111
	_bg_events.clear()
	SfxRouter.bg_sound_changed.connect(_on_bg_event)
	SfxRouter.stop_all_event_sound()
	SfxRouter.bg_sound_changed.disconnect(_on_bg_event)
	# Every tracked voice is torn down and the tracked-handle cache cleared.
	_assert_true(SfxRouter._bg_by_sound.is_empty(), "stop_all clears every tracked bg voice")
	_assert_eq(SfxRouter._bg_tracked_handle, 0, "stop_all clears the tracked handle")
	# A "stop" cue is emitted for each torn-down sound (observability).
	var stopped := {}
	for e in _bg_events:
		if e[0] == "stop":
			stopped[e[1]] = true
	_assert_true(stopped.has(7) and stopped.has(9), "stop_all emits a stop cue per tracked sound")
	# Leave the shared autoload clean for other tests.
	SfxRouter._bg_by_sound = {}
	SfxRouter._bg_tracked_handle = 0


# --- VM handler --------------------------------------------------------------

func _test_op_end_sound_clears_live_bg_ramps() -> void:
	# A live {6B} ramp in flight must be dropped by {7C} so it stops ticking
	# against a torn-down voice (VM-side scheduler state, ADR-0058).
	var vm := _make_vm()
	var bg = BgSound.new()
	bg.sound_id = 5
	bg.handle = 0
	bg.start_ramp(0, 24, 24)
	vm._bg_sounds[5] = bg
	vm._op_end_sound({"name": "End Sound", "opcode": 0x7C, "offset": 0, "params": []})
	_assert_true(vm._bg_sounds.is_empty(), "{7C} drops all live bg ramps")


func _test_op_end_sound_tears_down_router_voices() -> void:
	# The handler must route through _world → SfxRouter.stop_all_event_sound(),
	# tearing down voices the router tracks (not just the VM's own ramps).
	var vm := _make_vm()
	SfxRouter._bg_by_sound = {3: 333}
	SfxRouter._bg_tracked_handle = 333
	_bg_events.clear()
	SfxRouter.bg_sound_changed.connect(_on_bg_event)
	vm._op_end_sound({"name": "End Sound", "opcode": 0x7C, "offset": 0, "params": []})
	SfxRouter.bg_sound_changed.disconnect(_on_bg_event)
	_assert_true(SfxRouter._bg_by_sound.is_empty(), "{7C} tears down router-tracked voices")
	_assert_eq(SfxRouter._bg_tracked_handle, 0, "{7C} clears the router tracked handle")
	var saw_stop := false
	for e in _bg_events:
		if e[0] == "stop" and e[1] == 3:
			saw_stop = true
	_assert_true(saw_stop, "{7C} emits a stop cue for the tracked voice")


func _test_handler_registered_and_named() -> void:
	# {7C} is dispatched (bound), NOT auto-skipped, and no longer "Unknown".
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.END_SOUND), "{7C} End Sound handler registered")
	_assert_eq(EventInstructionSet.name_of(EventInstruction.END_SOUND), "End Sound",
		"{7C} named 'End Sound' in the catalog")
	_assert_true(not EventInstructionSet.is_unknown(EventInstruction.END_SOUND),
		"{7C} no longer classed Unknown (won't auto-skip)")
