extends Node
## Regression: ScenarioVM.start() must clear a leftover fast-play/park pause.
##
## Bug (seek → combat → victory freeze, /diagnosing-bugs 2026-07-18): on the
## navigator SEEK path, `run_combat` settles the battle world by FAST-FORWARDING the
## opener cinematic on `_vm` (`_settle_world_via_opener` → `ScenarioPathApplier.
## fast_forward_member`). Fast-play ends in `_finish_fast_play()`, which sets
## `_paused = true` (the step/rewind halt). The victory beat then REUSES that same
## `_vm`: `play_beat(scn6)` → `_play_member(6)` + `_vm.start(false)`. But `start()`
## did not clear `_paused`, so scenario-6 dispatched under `paused=true` — `_tick_once`
## returns at its `if paused: return` gate — and the VM sat frozen at pc 0, never
## reaching instr 7 `{43} Call Function 4` (the dead-unit fade). Result: no fade, and
## the whole scene (rain included) frozen. The play-from-top path plays the opener at
## NORMAL speed (never fast-plays), so `_paused` was never set and the fade fired —
## exactly the seek-vs-play-from-start asymmetry the user reported.
##
## Fix: `start()` clears the fast-play/park halt (`_paused = false`) — a fresh member
## start is the ADR-0064 single reset path, so no debug-park/fast-play state may leak
## across it. This test drives the real state transition: finish a fast-play (leaves
## the VM paused), then start the next member and assert it is dispatch-ready.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioStartClearsPauseTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_finish_fast_play_leaves_vm_paused()
	_test_start_clears_the_leftover_pause()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioStartClearsPauseTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioStartClearsPauseTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioStartClearsPauseTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioStartClearsPauseTest")
		get_tree().quit(0)


func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)  # _ready → handler registration + a valid _current_ctx
	_vms.append(vm)
	return vm


## Precondition guard: the opener fast-forward genuinely leaves the VM paused. If this
## ever changes, the fix below is moot and the test should be revisited.
func _test_finish_fast_play_leaves_vm_paused() -> void:
	var vm := _make_vm()
	vm._finish_fast_play()  # what `ScenarioPathApplier.fast_forward_member` bottoms out in
	_assert_true(vm.paused, "fast-play halt (_finish_fast_play) leaves the VM paused")


## The fix: starting the next member on a VM left paused by a prior fast-forward must
## clear the halt so its opcodes dispatch (else scn6 freezes at pc 0 and the fade never
## fires).
func _test_start_clears_the_leftover_pause() -> void:
	var vm := _make_vm()
	vm._finish_fast_play()          # opener fast-forward ends here → _paused = true
	_assert_true(vm.paused, "precondition: VM is paused after the fast-forward")
	vm.start(false)                 # play_beat(scn6) → _play_member + _vm.start(false)
	_assert_true(not vm.paused, "start() clears the leftover fast-play pause (scn6 can dispatch)")
	_assert_true(vm._running, "start() leaves the VM running")
