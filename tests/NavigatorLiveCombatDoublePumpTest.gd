extends Node
# test-kind: logic
# seeded-break: invert ScenarioVM._advance_scenario_anim's `if survey_frozen: return` gate to `if not survey_frozen: return` — the pump then advances every tick regardless of the Pause freeze, redding the freeze-frame + ambient-breathing assertions
## Regression guard for the "melee attacks spawn almost no trap particles" bug (import-godot-game),
## re-grounded on the ADR-0083 per-unit clock-owner model. Also absorbs the `survey_frozen` pump
## gate + the Space `_toggle_tactical_stop` path from the former NavigatorCommandModePauseFreezeTest.
##
## SYMPTOM (user's repro): NavigatorMain → Magic City Gariland → pre-battle → seek here → Tab to go
## live. The whole battle spawns only ONE hit-cloud trap, at full fps / foreground. Melee hits that
## should each spray a dust/flash cloud are silent.
##
## ROOT CAUSE: the combat units were driven by TWO independent body-anim clocks during LIVE combat —
## `CombatLoop.tick`'s per-tick `advance_frame` AND `ScenarioVM._advance_scenario_anim`'s idle pump
## (which advances every `units_by_id` + `idle_only_units` node). Each combat body double-advanced,
## desyncing the SEQ 0xDE / PostGenericAttack opcode from the GPU damage tick: the attack anim raced
## ~2× and crossed its hit-cloud frame BEFORE the damage landed, so the
## `is_hit = (current_tick - last_damage_tick) <= MELEE_HIT_WINDOW_TICKS` gate in
## `CombatLoop._trigger_physical_reaction` read stale data → `is_hit` false → evade branch → NO trap.
##
## THE INVARIANT this guards (ADR-0083): each unit's animation clock has exactly ONE owner. At
## `_go_live` the whole loaded cast is handed off SCENARIO→COMBAT, and the VM body pump SKIPS
## COMBAT-owned units — so a combat body advances on exactly ONE clock (the CombatLoop tick), with no
## per-toggle freeze to forget. Independently, an ambient SCENARIO-owned NPC that is NOT a combat unit
## keeps breathing on the VM clock through live combat (the case the old global freeze could not
## express). Pause layers the survey freeze on top: the `survey_frozen` pump gate and the Esc
## `_toggle_tactical_stop` path are guarded here (folded in from the former
## NavigatorCommandModePauseFreezeTest; audit MERGE 2026-09-07).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/NavigatorLiveCombatDoublePumpTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []
var _frees: Array = []

const _DT := 1.0 / 60.0


# Minimal duck-typed Unit stand-in: `clock_owner` (settable) + `advance_frame()` (counted). Mirrors
# the real Unit — owner settable, tick_based derived (ADR-0083). Defaults SELF (the VM pump claims it
# for SCENARIO on first sight, as it does a real scenario unit).
class FakeAnimUnit extends Node3D:
	var clock_owner: ClockOwner = ClockOwner.SELF
	var tick_based: bool:
		get: return clock_owner != ClockOwner.SELF
	var advance_calls: int = 0
	func advance_frame(_normal_reps: int = 1, _react_reps: int = 1) -> void:
		advance_calls += 1


## A CombatLoop that stays quiet off-GPU (its combat_active setter's visuals-freeze refresh
## early-returns off-tree / no sim). Mirrors NavigatorCommandModeTest.RecordingLoop.
class QuietLoop:
	extends CombatLoop


func _ready() -> void:
	_test_go_live_hands_off_clocks_to_combat()
	_test_pause_resume_toggles_survey_freeze()
	_test_live_combat_body_advances_on_one_clock()
	_test_ambient_scenario_npc_keeps_breathing_during_live()
	# Folded from NavigatorCommandModePauseFreezeTest (audit MERGE 2026-09-07): the survey_frozen
	# pump gate and the full Space `_toggle_tactical_stop` path. PauseFreeze's `_set_combat_live`
	# toggle test duplicated `_test_pause_resume_toggles_survey_freeze` above, so it was dropped.
	_test_frozen_pump_advances_no_body_clock()
	_test_unfrozen_pump_still_breathes()
	_test_toggle_pause_freezes_and_resume_thaws()

	for n in _frees:
		if is_instance_valid(n):
			n.free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== NavigatorLiveCombatDoublePumpTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorLiveCombatDoublePumpTest: ran zero assertions"); get_tree().quit(1); return
	if _failed > 0:
		print("[FAIL] NavigatorLiveCombatDoublePumpTest"); get_tree().quit(1)
	else:
		print("[PASS] NavigatorLiveCombatDoublePumpTest"); get_tree().quit(0)


func _ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)   # _ready wires camera_director + box_pool
	_vms.append(vm)
	return vm


func _wait_inst(t: int) -> Dictionary:
	return {"name": "Wait", "opcode": EventInstruction.WAIT, "offset": 0,
		"params": [{"name": "Time", "value": t}]}


func _new_nav() -> Node:
	return load("res://src/scenarios/NavigatorMain.gd").new()


func _live_vm() -> ScenarioVMClass:
	# A VM parked on a long Wait (so its pump runs each tick).
	var vm := _make_vm()
	vm._insts = [_wait_inst(10_000_000)]
	vm.start()
	return vm


# Deployment→Live (`_go_live`, the Tab that "starts the battle") must hand the whole loaded cast off
# to COMBAT ownership — the CombatLoop tick becomes their sole clock. Live is NOT survey-frozen (that
# is a Pause-only presentation freeze); the single-clock guarantee comes from ownership.
func _test_go_live_hands_off_clocks_to_combat() -> void:
	var nav := _new_nav()
	var vm := _live_vm()
	nav._vm = vm
	var loop := QuietLoop.new()
	add_child(loop)
	_frees.append(loop)
	nav._combat_loop = loop
	nav._pending_gambits = []

	var a := FakeAnimUnit.new()
	var b := FakeAnimUnit.new()
	add_child(a); add_child(b)
	_frees.append(a); _frees.append(b)
	loop.units = [a, b]

	nav._go_live()

	_ok(a.clock_owner == ClockOwner.COMBAT and b.clock_owner == ClockOwner.COMBAT,
		"_go_live: whole loaded cast handed off SCENARIO→COMBAT (a=%d b=%d)" % [a.clock_owner, b.clock_owner])
	_ok(not vm.survey_frozen,
		"_go_live (Deployment→Live): NOT survey-frozen — combat bodies single-clocked by ownership, not a freeze")
	nav.free()


# Pause/resume toggles ONLY the survey freeze now (ADR-0083): Live→Paused freezes the ambient pump;
# Paused→Live thaws it. Combat bodies stay single-clocked across both because they are COMBAT-owned.
func _test_pause_resume_toggles_survey_freeze() -> void:
	var nav := _new_nav()
	var vm := _make_vm()
	nav._vm = vm

	nav._set_combat_live(false)   # Live → STOPPED
	_ok(vm.survey_frozen, "_set_combat_live(false): ambient pump frozen (Pause = freeze-frame)")
	nav._set_combat_live(true)    # STOPPED → Live
	_ok(not vm.survey_frozen,
		"_set_combat_live(true): ambient pump thaws (combat bodies single-clocked by COMBAT ownership)")
	nav.free()


# The symptom, end to end: a combat body that lives in BOTH the CombatLoop's unit set AND the VM idle
# pump (as a deployed generic does) is advanced EXACTLY ONCE per frame during live combat — the
# CombatLoop drive — because the handoff made it COMBAT-owned and the VM pump skips COMBAT-owned.
func _test_live_combat_body_advances_on_one_clock() -> void:
	var nav := _new_nav()
	var vm := _live_vm()
	nav._vm = vm
	var loop := QuietLoop.new()
	add_child(loop)
	_frees.append(loop)
	nav._combat_loop = loop
	nav._pending_gambits = []

	# One combat body, both a CombatLoop unit (handed off at go-live) and on the VM idle pump.
	var body := FakeAnimUnit.new()
	add_child(body)
	_frees.append(body)
	loop.units = [body]
	vm.idle_only_units = [body]

	nav._go_live()  # Deployment → Live (hands `body` off to COMBAT)

	# Simulate 60 combat frames: CombatLoop drives the body once/frame; the VM pump also runs and MUST
	# skip the COMBAT-owned body.
	var combatloop_advances := 0
	for _i in range(60):
		body.advance_frame()          # the CombatLoop.tick per-frame drive (stand-in)
		combatloop_advances += 1
		vm._advance_frame(_DT)        # the VM idle pump — MUST NOT touch a COMBAT-owned body

	_ok(body.advance_calls == combatloop_advances,
		"live combat: body advances on ONE clock (calls=%d, expected=%d) — no VM double-drive" % [
			body.advance_calls, combatloop_advances])
	nav.free()


# The case the old global freeze could NOT express (ADR-0083): a non-combatant scenario NPC — an
# onlooker, a caged Ovelia — is registered on the VM (`units_by_id`) but is NOT a CombatLoop unit, so
# it stays SCENARIO-owned through the handoff and keeps breathing on the VM clock during LIVE combat,
# advancing exactly once per VM tick and never touched by the CombatLoop.
func _test_ambient_scenario_npc_keeps_breathing_during_live() -> void:
	var nav := _new_nav()
	var vm := _live_vm()
	nav._vm = vm
	var loop := QuietLoop.new()
	add_child(loop)
	_frees.append(loop)
	nav._combat_loop = loop
	nav._pending_gambits = []

	# A combat body (handed off) and an ambient NPC (never a combat unit).
	var body := FakeAnimUnit.new()
	var npc := FakeAnimUnit.new()
	add_child(body); add_child(npc)
	_frees.append(body); _frees.append(npc)
	loop.units = [body]
	vm.units_by_id[901] = body   # combat body also VM-registered (as the leader is)
	vm.units_by_id[902] = npc    # ambient onlooker, NOT a combat unit

	nav._go_live()  # body → COMBAT; npc stays SCENARIO

	var ticks_before := vm._vm_tick
	for _i in range(60):
		vm._advance_frame(_DT)      # only the VM pump runs (no CombatLoop stand-in here)
	var vm_ticks := vm._vm_tick - ticks_before

	_ok(npc.advance_calls == vm_ticks and npc.advance_calls > 0,
		"ambient NPC breathes on VM clock during Live (calls=%d, ticks=%d)" % [npc.advance_calls, vm_ticks])
	_ok(npc.clock_owner == ClockOwner.SCENARIO,
		"ambient NPC stays SCENARIO-owned through the handoff (owner=%d)" % npc.clock_owner)
	_ok(body.advance_calls == 0,
		"COMBAT-owned body is skipped by the VM pump (calls=%d) — CombatLoop is its sole clock" % body.advance_calls)
	nav.free()


# Absorbed from NavigatorCommandModePauseFreezeTest (seam 1a): while `survey_frozen`, the VM pump
# holds EVERY body clock — a registered battle unit AND a deployed idle-only unit both stop
# advancing. The load-bearing freeze-frame guarantee; the gate lives at the top of
# `_advance_scenario_anim`.
func _test_frozen_pump_advances_no_body_clock() -> void:
	var vm := _live_vm()
	var reg := FakeAnimUnit.new()
	var idle := FakeAnimUnit.new()
	reg.clock_owner = ClockOwner.SCENARIO
	idle.clock_owner = ClockOwner.SCENARIO
	add_child(reg); add_child(idle)
	_frees.append(reg); _frees.append(idle)
	vm.units_by_id[7] = reg
	vm.idle_only_units = [idle]

	vm.survey_frozen = true
	for _i in range(60):
		vm._advance_frame(_DT)

	_ok(reg.advance_calls == 0,
		"survey_frozen: registered battle unit body clock does not advance (calls=%d)" % reg.advance_calls)
	_ok(idle.advance_calls == 0,
		"survey_frozen: idle-only deployed unit body clock does not advance (calls=%d)" % idle.advance_calls)


# Absorbed from NavigatorCommandModePauseFreezeTest (seam 1b): default (frozen false) leaves the
# pump untouched — a scenario park still breathes, both clocks advancing once per VM tick
# (ADR-0065). Guards against over-freezing the non-Pause path.
func _test_unfrozen_pump_still_breathes() -> void:
	var vm := _live_vm()
	var reg := FakeAnimUnit.new()
	var idle := FakeAnimUnit.new()
	reg.clock_owner = ClockOwner.SCENARIO
	idle.clock_owner = ClockOwner.SCENARIO
	add_child(reg); add_child(idle)
	_frees.append(reg); _frees.append(idle)
	vm.units_by_id[7] = reg
	vm.idle_only_units = [idle]

	for _i in range(60):
		vm._advance_frame(_DT)

	_ok(reg.advance_calls == vm._vm_tick and reg.advance_calls > 0,
		"default: registered unit advances once/tick (calls=%d, ticks=%d)" % [reg.advance_calls, vm._vm_tick])
	_ok(idle.advance_calls == vm._vm_tick and idle.advance_calls > 0,
		"default: idle-only unit advances once/tick (calls=%d, ticks=%d)" % [idle.advance_calls, vm._vm_tick])


# Absorbed from NavigatorCommandModePauseFreezeTest (seam 2, the full Tab path): Live → Paused
# freezes the ambient VM cast; Paused → Live thaws it — the whole battlefield freeze-frames on
# Pause and resumes on continue. The narrow `_set_combat_live` toggle is already covered above, so
# only the `_toggle_tactical_stop` seam lands here.
func _test_toggle_pause_freezes_and_resume_thaws() -> void:
	var nav := _new_nav()
	var vm := _make_vm()
	nav._vm = vm
	var loop := QuietLoop.new()
	add_child(loop)  # in-tree so the loop's combat_active setter is quiet
	_frees.append(loop)
	nav._combat_loop = loop
	loop.combat_active = true
	nav._combat_active = true

	nav._toggle_tactical_stop()  # Live → STOPPED
	_ok(vm.survey_frozen, "Esc Live→Paused: ambient VM cast freeze-frames")
	nav._toggle_tactical_stop()  # STOPPED → Live
	_ok(not vm.survey_frozen, "Esc Paused→Live: ambient VM pump thaws (CombatLoop single-clocks the cast)")
	nav.free()
