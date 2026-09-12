extends Node
## Regression: rain must keep falling once combat begins on a SEEK to combat.
##
## Bug (navigator: "rain stops when combat begins", /diagnosing-bugs 2026-07-18):
## weather ({3C}) is a scenario-VM time-driven effect — `ScenarioVM._weather.tick()`
## runs inside `_tick_time_driven_effects`, which `_tick_once` calls only `if not
## paused`. On the navigator SEEK-to-combat path, `run_combat` settles the battle
## world by FAST-FORWARDING the opener cinematic (`_settle_world_via_opener` →
## `ScenarioPathApplier.fast_forward_member`). Fast-play bottoms out in
## `_finish_fast_play()`, which sets `_paused = true` (the step/rewind halt). Unlike
## the victory beat — which REUSES the VM via `_vm.start(false)` and so gets its pause
## cleared (ScenarioStartClearsPauseTest, commit 99639ef72) — combat NEVER calls
## `start()`. It calls `settle_screen_effects()` then hands the still-live world to a
## bare CombatLoop. So the VM sat `paused` for the whole battle, `_tick_once`'s
## `if not paused` gate froze `_tick_time_driven_effects`, and the rain (plus every
## other live overlay ramp) stopped dead the instant combat began. The play-from-top
## path plays the opener at NORMAL speed (never fast-plays), so `_paused` was never set
## and rain kept falling — the same seek-vs-play-from-start asymmetry as the fade bug.
##
## Fix: `settle_screen_effects()` — the unconditional pre-combat seam ("all pre-battle
## scenario effects are RESOLVED before the battle starts", called from run_combat on
## BOTH the linear and seek paths) — also clears the leftover fast-play/park halt
## (`_paused = false`). Combat is live gameplay on the shared world, not a debug
## freeze-frame, so the VM's persistent time-driven overlays (weather above all) must
## keep advancing through the battle.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioCombatWeatherKeepsFallingTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_finish_fast_play_leaves_vm_paused()
	_test_settle_screen_effects_clears_leftover_pause()
	_test_weather_frozen_while_paused_then_falls_after_settle()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioCombatWeatherKeepsFallingTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioCombatWeatherKeepsFallingTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioCombatWeatherKeepsFallingTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCombatWeatherKeepsFallingTest")
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


## Combat drives the VM through its normal per-frame pipeline; the weather tick lives
## behind `_tick_once`'s `if not paused` gate. Drive that gate directly.
func _combat_frame(vm: ScenarioVMClass) -> void:
	vm._tick_once()


## Precondition guard: the opener fast-forward genuinely leaves the VM paused. If this
## ever changes, the fix below is moot and the test should be revisited.
func _test_finish_fast_play_leaves_vm_paused() -> void:
	var vm := _make_vm()
	vm._finish_fast_play()  # what `ScenarioPathApplier.fast_forward_member` bottoms out in
	_assert_true(vm.paused, "fast-play halt (_finish_fast_play) leaves the VM paused")


## The fix: the pre-combat settle seam clears the leftover fast-play pause so the VM's
## live overlays keep advancing during the battle.
func _test_settle_screen_effects_clears_leftover_pause() -> void:
	var vm := _make_vm()
	vm._finish_fast_play()          # opener fast-forward ends here → _paused = true
	_assert_true(vm.paused, "precondition: VM is paused after the opener fast-forward")
	vm.settle_screen_effects()      # run_combat's unconditional pre-combat seam
	_assert_true(not vm.paused, "settle_screen_effects() clears the leftover fast-play pause")


## End-to-end at the tick gate: arm rain, leave the VM paused (as the seek settle does),
## show the rain is FROZEN while paused, then settle → rain falls again.
func _test_weather_frozen_while_paused_then_falls_after_settle() -> void:
	var vm := _make_vm()
	var w = vm.debug_force_weather(true, 3)  # lazily spawns + arms the rain node
	_assert_true(w != null, "precondition: weather node armed")
	if w == null:
		return

	vm._finish_fast_play()  # seek settle leaves the VM paused
	_assert_true(vm.paused, "precondition: VM paused (mirrors the seek→combat state)")

	# While paused, a combat frame must NOT advance the rain — this IS the reported bug.
	var frozen: PackedFloat32Array = w._psx_bottom.duplicate()
	for _i in 4:
		_combat_frame(vm)
	_assert_true(w._psx_bottom == frozen, "rain is frozen while the VM is paused (the bug)")

	# Settle for combat, then combat frames must advance the rain again.
	vm.settle_screen_effects()
	var before: PackedFloat32Array = w._psx_bottom.duplicate()
	for _i in 4:
		_combat_frame(vm)
	_assert_true(w._psx_bottom != before, "rain keeps falling once combat begins (after settle)")
