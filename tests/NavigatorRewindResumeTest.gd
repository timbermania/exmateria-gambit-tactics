extends Node
## A click-to-rewind staged from INSIDE a navigator walk resumes THAT walk, and does not
## fall back to the story start.
##
## The reported defect: seek to group root 28 (Citadel of Igros Castle), open F3 ->
## Scenario Playback, double-click PC 32 — and the reload booted the Chapel of Orbonne
## (group 1) instead. Two independent causes under the one symptom:
##
##   1. [code]ScenarioDebugSession.active_scenario_id[/code] had ONE write site, in
##      [code]ScenarioPlayerScene._ready[/code], which the navigator branch of
##      [code]NavigatorMain._ready[/code] returns before reaching. So it read -1 for the
##      whole walk and the rewind front-end could not see what was playing.
##   2. Nothing on the navigator boot path consumed [code]rewind_target_pc[/code], and
##      [code]navigator_start_root[/code] had already been consumed — so the reload fell
##      through to the hardcoded [code]START_ROOT[/code] = 1.
##
## TWO PASSES, because the hand-off it guards IS a `reload_current_scene`. Pass 1 boots the
## walk and drives the REAL [code]ScenarioVMDebugPanel._request_rewind[/code], whose own
## trailing reload re-enters this scene as pass 2. A `static var` survives that reload the
## same way the [ScenarioDebugSession] autoload does. Replicating the panel's field writes
## instead of calling it would guard a copy of the producer rather than the producer.
##
## HEADFUL — run standalone:
##   godot --path . --quit-after 900 res://tests/NavigatorRewindResumeTest.tscn

const TIMEOUT_MS := 120000
const SEEK_ROOT := 28    # Citadel of Igros Castle — the reported repro's group
const SEEK_ACTION := 0
const TARGET_PC := 32
const ORBONNE_ROOT := 1  # NavigatorMain.START_ROOT — the wrong answer this guards against

## Survives `reload_current_scene` (the script resource stays loaded), which is what lets
## pass 2 know it is the far side of the rewind rather than a fresh run.
static var _pass: int = 0

var _passed := 0
var _failed := 0
var _nav: Node = null


func _ready() -> void:
	_pass += 1
	if _pass == 1:
		await _stage_the_rewind()
	else:
		await _assert_the_walk_resumed()


# --- Pass 1: boot the walk, then click rewind --------------------------------

func _stage_the_rewind() -> void:
	ScenarioDebugSession.navigator_start_root = SEEK_ROOT
	ScenarioDebugSession.navigator_stop_root = SEEK_ROOT
	ScenarioDebugSession.navigator_start_action = SEEK_ACTION

	if not await _boot_navigator():
		print("[FAIL] NavigatorRewindResumeTest: pass 1 never registered the VM panel")
		get_tree().quit(1)
		return

	var vm_panel: Variant = _find("ScenarioVMDebugPanel")
	# The producer, called for real. Its trailing `reload_current_scene()` is deferred to
	# idle, so this returns and pass 2 begins on the next frame.
	vm_panel._request_rewind(TARGET_PC)


# --- Pass 2: the far side of the reload --------------------------------------

func _assert_the_walk_resumed() -> void:
	# ARM 1 — what the rewind parked. `path_target_scenario_id` must stay clear: setting it
	# is what would hand the next boot to `super._ready()` (plain ScenarioPlayerScene) and
	# drop the walk entirely, which is the same defect wearing a different hat.
	_eq(ScenarioDebugSession.rewind_target_pc, TARGET_PC, "the clicked PC survived the reload")
	_eq(ScenarioDebugSession.navigator_resume_root, SEEK_ROOT,
			"the walk's position was parked, so the reload has somewhere to resume")
	_eq(ScenarioDebugSession.navigator_resume_action, SEEK_ACTION, "and the action within it")
	_true("the rewind did NOT divert the boot into plain scenario playback",
			ScenarioDebugSession.path_target_scenario_id <= 0)

	# ARM 2 — the boot the user actually sees. This is the arm that fails on the reported
	# defect: without the resume the walk plans from START_ROOT and plays the Chapel.
	if not await _boot_navigator():
		_true("pass 2 booted a navigator world", false)
		_finish()
		return
	var active: int = ScenarioDebugSession.active_scenario_id
	var root: int = ScenarioGroupDatabase.root_for_scenario(active)
	_true("the scenario now playing belongs to group %d, not the Chapel (got scn %d -> root %d)"
			% [SEEK_ROOT, active, root], root == SEEK_ROOT)
	# `selected_scenario_id` is written by `_boot_world_for` on BOTH the working and the
	# broken path, so — unlike `active_scenario_id`, which reads a vacuous -1 while the
	# defect stands — this arm cannot pass by accident. On the defect it reads the Chapel.
	var booted: int = ScenarioDebugSession.selected_scenario_id
	var booted_root: int = ScenarioGroupDatabase.root_for_scenario(booted)
	_true("the world booted is group %d's and not group %d's (got scn %d -> root %d)"
			% [SEEK_ROOT, ORBONNE_ROOT, booted, booted_root], booted_root == SEEK_ROOT)

	# ARM 3 — the PC was not merely preserved, it was HANDED TO THE VM. Arm 1 alone passes
	# for a fix that resumes the walk and drops the rewind on the floor.
	var armed := await _await_rewind_armed()
	_true("the resumed member's VM was armed to rewind to PC %d (got %s)"
			% [TARGET_PC, str(armed)], armed == TARGET_PC)
	_finish()


# --- Helpers -----------------------------------------------------------------

## Boot NavigatorMain and wait until its debug panels register — they do so inside
## `_boot_scenario_world`, i.e. only once the walk's first action has a world up.
func _boot_navigator() -> bool:
	var t0 := Time.get_ticks_msec()
	_nav = load("res://assets/scenes/NavigatorMain.tscn").instantiate()
	add_child(_nav)
	while _find("ScenarioVMDebugPanel") == null \
			and (Time.get_ticks_msec() - t0) < TIMEOUT_MS:
		await get_tree().process_frame
	return _find("ScenarioVMDebugPanel") != null


## Poll for the VM's armed rewind target. The applier reaches the final member some frames
## after the world boots, so sampling once would read "not yet" on a working fix.
func _await_rewind_armed() -> int:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < TIMEOUT_MS:
		var vm: Variant = _nav._vm
		if vm != null and is_instance_valid(vm) and int(vm._ff_target_pc) == TARGET_PC:
			return int(vm._ff_target_pc)
		await get_tree().process_frame
	var vm2: Variant = _nav._vm
	return int(vm2._ff_target_pc) if vm2 != null and is_instance_valid(vm2) else -1


func _find(class_ident: String):
	for cat in DebugOverlay._panels.keys():
		for panel in DebugOverlay._panels[cat]:
			if is_instance_valid(panel) and panel.get_script() != null \
					and panel.get_script().get_global_name() == class_ident:
				return panel
	return null


func _true(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  [ok] %s" % label)
	else:
		_failed += 1
		print("  [XX] %s" % label)


func _eq(got: int, want: int, label: String) -> void:
	_true("%s (got %d, want %d)" % [label, got, want], got == want)


func _finish() -> void:
	print("\n=== NavigatorRewindResumeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorRewindResumeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorRewindResumeTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorRewindResumeTest")
		get_tree().quit(0)
