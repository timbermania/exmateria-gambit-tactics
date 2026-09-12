extends Node
## Tests for {92} Inflict Status (opcode 0x92), Status=0 only — the revive/normalise
## branch that covers 139/141 {92}-using scenarios (incl. scenario 6). This opcode
## was enumerated (EventInstruction.gd:139) but unhandled, so the VM would halt on it.
##
## FFT decode (research/working_documents/scenario_1_captures/
## inflict_status_op92_decode.md, dynamically validated on scenario 6): the PSX
## handler (0x80145EE0) spawns a fire-and-forget cooperative task whose body
## (FUN_80148E88) branches on Status. We reproduce the stock `Status == 0` branch:
## revive-if-dead(1 HP), force a clean Standing pose (Critical if HP low), play a
## revive SFX only if the unit was dead, and record a per-event block-HP-restore
## flag. It is NOT a status bit and NOT body removal.
##
## `Status == 2` (Poison+Critical) is also implemented (scenario 354): add the
## &"poison" status, force the Critical kneel pose (IDLE_LOW_HEALTH, no HP change),
## and apply poison's static green sprite recolor (live-measured; §11.2 / §12).
## `Status == 1` (Crystal) is also implemented (scenarios 194/479/480): the body
## sprite is hidden and replaced by an animated diamond billboard ([CrystalSprite3D],
## 8-frame forward loop @ 4 vblanks/frame — RE'd live per-vblank, §12.7/§12.8). It is
## NOT a GPU status bit (the 32-bit set is full) — a Unit-owned scenario visual. The
## 0x80+ single-status range is dead code on stock; it must FAIL LOUD (push_error +
## halt) rather than silently advance past an unmodelled status (issue #154).
##
## Three layers:
##   A. Apply layer (FakeScenarioWorld) — the pure verb wiring, no scene.
##   B. VM dispatch: Status 0/1/2 don't halt; FAIL-LOUD halt on 0x80+ — ScenarioVM.
##   C. Real Unit behaviour — revive (SS=0) + poison/kneel (SS=2) + crystal (SS=1).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioInflictStatusTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const CrystalSprite3D = ExMateriaSpriteRig.CrystalSprite3D
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const UNIT_SCENE_PATH := "res://assets/scenes/Unit.tscn"
const UnitProgressionClass = ExMateriaAlmanac.UnitProgression
const CHUNK6_PATH := "res://assets/scenarios/chunks/scenario_006_chunk.json"

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	# A. Apply layer (no scene).
	_test_apply_resolves_then_normalises()
	_test_apply_noops_when_absent()
	_test_apply_status2_inflicts_poison_critical()
	_test_apply_status1_inflicts_crystal()
	# B. VM dispatch + fail-loud.
	_test_handler_registered()
	_test_status0_does_not_halt()
	_test_status1_does_not_halt()
	_test_status2_does_not_halt()
	_test_unmodelled_status_fails_loud()
	_test_real_chunk6_three_sites_do_not_halt()
	# C. Real Unit behaviour.
	await _test_dead_unit_revives_to_1hp_and_stands()
	await _test_living_unit_normalises_without_revive()
	await _test_status2_poisons_and_kneels()
	await _test_status1_crystallizes_and_hides_body()
	await _test_reset_cutscene_state_uncrystallizes()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioInflictStatusTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioInflictStatusTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioInflictStatusTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioInflictStatusTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


# --- Fixture builders --------------------------------------------------------

func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)
	_vms.append(vm)
	return vm


func _add_stub_unit(vm: ScenarioVMClass, uid: int) -> Node3D:
	# Lacks scenario_revive_and_normalise, so the world verb no-ops on it — enough to
	# prove dispatch + the fail-loud gate without booting a Unit.
	var u := StubUnit.new()
	add_child(u)
	vm.units_by_id[uid] = u
	return u


## A stand-in for Unit. It deliberately does NOT carry `scenario_revive_and_normalise`
## — that refusal is what these tests prove.
##
## It DOES carry the three fields the VM's animation and rotation paths read, held null,
## because a bare Node3D lacked them and the READ threw. A GDScript error aborts the
## production function, so `_apply_unit_animation` returned the `bool` default `false` —
## which happens to equal its own "unit not ready" answer. The degrade therefore looked
## correct while being an accident, and the WARN that branch exists to print never
## printed. Held null, the documented branch is the one that actually runs. #466.
class StubUnit extends Node3D:
	var animation_set = null
	var display = null
	var anim_state = null


func _inflict_inst(uid: int, status: int, wait: int = 0x0C) -> Dictionary:
	# Catalog params for 0x92 are [Unit:2, Status:1, Unknown:2], zipped by position
	# (EventInstructionArgs), so the runtime params must be in that order.
	return {
		"name": "Inflict Status", "opcode": 0x92, "offset": 0x54,
		"params": [{"value": uid}, {"value": status}, {"value": wait}],
	}


# --- A. Apply layer ----------------------------------------------------------

func _test_apply_resolves_then_normalises() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.inflict_status(0x02, 0x00, 0x0C, world)
	_true(world.only_call("resolve_unit_key") != null, "apply resolves the key first")
	var normalised = world.only_call("revive_and_normalise")
	_true(normalised != null, "apply normalises once")
	_eq(normalised["uid"], 0x02, "normalises the resolved key")
	# resolution precedes normalise.
	var verbs := world.calls.map(func(e): return e["verb"])
	_true(verbs.find("resolve_unit_key") < verbs.find("revive_and_normalise"),
		"resolves before normalising")


func _test_apply_noops_when_absent() -> void:
	var world := FakeScenarioWorld.new()
	world.missing_units[0x02] = true
	ScenarioApply.inflict_status(0x02, 0x00, 0x0C, world)
	_true(world.only_call("resolve_unit_key") != null, "still resolves (returns -1)")
	_eq(world.calls_to("revive_and_normalise").size(), 0, "absent unit: no normalise")


func _test_apply_status2_inflicts_poison_critical() -> void:
	# Status=2 resolves the key then routes to the Poison+Critical world verb (NOT
	# revive_and_normalise), which drives the green tint + kneel pose.
	var world := FakeScenarioWorld.new()
	ScenarioApply.inflict_status(0x02, 0x02, 0x0C, world)
	_true(world.only_call("resolve_unit_key") != null, "SS=2 resolves the key first")
	var pc = world.only_call("inflict_poison_critical")
	_true(pc != null, "SS=2 calls inflict_poison_critical once")
	_eq(pc["uid"], 0x02, "SS=2 poisons the resolved key")
	_eq(world.calls_to("revive_and_normalise").size(), 0, "SS=2 does NOT run the SS=0 normalise")


func _test_apply_status1_inflicts_crystal() -> void:
	# Status=1 resolves the key then routes to the Crystal world verb (NOT
	# revive_and_normalise / poison), which hides the body + spawns the diamond.
	var world := FakeScenarioWorld.new()
	ScenarioApply.inflict_status(0x02, 0x01, 0x0C, world)
	_true(world.only_call("resolve_unit_key") != null, "SS=1 resolves the key first")
	var cr = world.only_call("inflict_crystal")
	_true(cr != null, "SS=1 calls inflict_crystal once")
	_eq(cr["uid"], 0x02, "SS=1 crystallizes the resolved key")
	_eq(world.calls_to("inflict_poison_critical").size(), 0, "SS=1 does NOT run the SS=2 poison")
	_eq(world.calls_to("revive_and_normalise").size(), 0, "SS=1 does NOT run the SS=0 normalise")


# --- B. VM dispatch + fail-loud ----------------------------------------------

func _test_handler_registered() -> void:
	var vm := _make_vm()
	_true(vm._handlers.has(EventInstruction.INFLICT_STATUS),
		"_handlers has 'Inflict Status'")


func _test_status0_does_not_halt() -> void:
	var vm := _make_vm()
	vm.start()
	_add_stub_unit(vm, 0x02)
	_true(vm._running, "VM running before Status=0")
	vm._op_inflict_status(_inflict_inst(0x02, 0x00))
	_true(vm._running, "Status=0 does NOT halt the VM")


func _test_status1_does_not_halt() -> void:
	var vm := _make_vm()
	vm.start()
	_add_stub_unit(vm, 0x02)
	_true(vm._running, "VM running before Status=1")
	vm._op_inflict_status(_inflict_inst(0x02, 0x01))
	_true(vm._running, "Status=1 (Crystal) does NOT halt the VM")


func _test_status2_does_not_halt() -> void:
	var vm := _make_vm()
	vm.start()
	_add_stub_unit(vm, 0x02)
	_true(vm._running, "VM running before Status=2")
	vm._op_inflict_status(_inflict_inst(0x02, 0x02))
	_true(vm._running, "Status=2 (Poison+Critical) does NOT halt the VM")


func _test_unmodelled_status_fails_loud() -> void:
	# Status 0/1/2 are implemented; the 0x80+ single-status ROM-hack range is dead
	# code on stock — it must halt the VM rather than silently advance (issue #154).
	for status in [0x80, 0xFF]:
		var vm := _make_vm()
		vm.start()
		_add_stub_unit(vm, 0x02)
		_true(vm._running, "VM running before Status=0x%02X" % status)
		vm._op_inflict_status(_inflict_inst(0x02, status))
		_true(not vm._running, "Status=0x%02X FAILS LOUD (VM halted)" % status)


# --- B'. Real scenario-6 chunk: the three {92} dispatch without halting -------

func _test_real_chunk6_three_sites_do_not_halt() -> void:
	# Scenario 6's three consecutive {92} sit at instruction indices 21/22/23
	# (units 2/52/23, all Status=0), directly behind the {E5} WaitForInstruction
	# Task=1 dialog barrier at index 20. The full ScenarioPlayer path can't reach
	# them yet (an earlier unimplemented 'Call Function' at pc=7 halts first), so —
	# like ScenarioRemoveUnitTest's PC-382 test — we load the real chunk and jump
	# the main context straight onto the first {92}. Before this opcode was handled
	# the VM set _running=false on the unhandled 'Inflict Status'; now it must sail
	# through all three (Status=0) into the following {11} Unit Anim at index 24.
	var vm := _make_vm()
	var ok := vm.load_chunk_json(CHUNK6_PATH)
	_true(ok, "loaded real scenario_006_chunk.json")
	if not ok:
		return
	vm.start()
	# Spawn stubs for the three {92} targets + the {11}/{2D} targets that follow, so
	# the post-{92} opcodes have live units to act on (they'd warn-skip otherwise).
	for uid in [0x01, 0x02, 0x34, 0x17]:
		_add_stub_unit(vm, uid)
	vm._contexts[0].pc = 21   # the first {92} (Unit=2)

	var halted := false
	var crossed := false
	for _t in range(60):
		vm._tick_once()
		if not vm._running:
			halted = true
			break
		if vm._contexts[0].pc >= 24:   # past all three {92}, into {11} Unit Anim
			crossed = true
			break

	_true(not halted, "VM did NOT halt across the three scenario-6 {92} sites")
	_true(crossed, "main context advanced past all three {92} (pc >= 24)")
	_true(vm._running, "VM still running after the three {92}")


# --- C. Real Unit revive/normalise -------------------------------------------

func _make_real_unit() -> Node:
	var unit = load(UNIT_SCENE_PATH).instantiate()
	add_child(unit)
	await get_tree().process_frame  # let @onready + _ready sprite-init run
	# Give it real stats so take_damage can kill it and revive can restore HP.
	unit.initialize_with_progression(
		UnitProgressionClass.BaseStatType.MALE, "4a", UnitStats.Team.ENEMY)
	await get_tree().process_frame
	return unit


func _test_dead_unit_revives_to_1hp_and_stands() -> void:
	var unit = await _make_real_unit()
	# Kill it: HP -> 0 -> die() -> &"dead" status + DYING pose.
	unit.take_damage(unit.max_hp + 100)
	await get_tree().process_frame
	_true(unit.is_dead, "unit is dead before {92}")

	var was_dead: bool = unit.scenario_revive_and_normalise(1)
	await get_tree().process_frame

	_true(was_dead, "dead unit: scenario_revive_and_normalise reports it WAS dead")
	_true(not unit.is_dead, "revived: no longer dead")
	_eq(unit.current_hp, 1, "revived to exactly 1 HP")
	_eq(unit.activity, DisplayActivity.Activity.IDLE,
		"revived unit normalised to a Standing (IDLE) pose, not DYING/DEAD")
	unit.queue_free()


func _test_living_unit_normalises_without_revive() -> void:
	var unit = await _make_real_unit()
	var hp_before: int = unit.current_hp
	_true(not unit.is_dead, "unit alive before {92}")

	var was_dead: bool = unit.scenario_revive_and_normalise(1)
	await get_tree().process_frame

	_true(not was_dead, "living unit: reports it was NOT dead (no revive SFX)")
	_eq(unit.current_hp, hp_before, "living unit: HP untouched (revive is a no-op)")
	_eq(unit.activity, DisplayActivity.Activity.IDLE,
		"living unit normalised to a Standing (IDLE) pose")
	unit.queue_free()


func _test_status2_poisons_and_kneels() -> void:
	# {92} SS=2 unit-level half: adds the Poison status + forces the Critical kneel
	# stance (IDLE_LOW_HEALTH), WITHOUT touching HP (PSX forces anim 0x16 directly;
	# §11.2). The green tint is the world verb's half (apply-layer test above).
	var unit = await _make_real_unit()
	var hp_before: int = unit.current_hp
	_true(not unit.unit_status.has_status(&"poison"), "not poisoned before {92} SS=2")

	unit.scenario_inflict_poison_critical()
	await get_tree().process_frame

	_true(unit.unit_status.has_status(&"poison"), "SS=2 adds the &\"poison\" status")
	_eq(unit.activity, DisplayActivity.Activity.IDLE_LOW_HEALTH,
		"SS=2 forces the Critical kneel stance (IDLE_LOW_HEALTH)")
	_eq(unit.current_hp, hp_before, "SS=2 does NOT change HP (pose forced directly)")
	unit.queue_free()


func _test_status1_crystallizes_and_hides_body() -> void:
	# {92} SS=1 unit-level half: hide the body sprite (+ weapon/shield layers) and
	# spawn the CrystalSprite3D diamond billboard. NOT a status bit, NOT an HP change.
	# Idempotent — a second call must not spawn a second billboard.
	var unit = await _make_real_unit()
	var hp_before: int = unit.current_hp
	_true(not unit.is_crystallized(), "unit not crystallized before {92} SS=1")
	_true(unit.mesh_instance.visible, "body sprite visible before {92} SS=1")

	unit.scenario_inflict_crystal()
	await get_tree().process_frame

	_true(unit.is_crystallized(), "SS=1 crystallizes the unit")
	_true(not unit.mesh_instance.visible, "SS=1 hides the body sprite")
	_true(unit._crystal_sprite is CrystalSprite3D, "SS=1 spawns a CrystalSprite3D child")
	_eq(unit.current_hp, hp_before, "SS=1 does NOT change HP")

	# Idempotency: a second SS=1 keeps the same billboard (no duplicate).
	var first = unit._crystal_sprite
	unit.scenario_inflict_crystal()
	_true(unit._crystal_sprite == first, "SS=1 is idempotent (no second billboard)")
	unit.queue_free()


func _test_reset_cutscene_state_uncrystallizes() -> void:
	# A crystallized unit must be fully restored by reset_scenario_cutscene_state()
	# (ScenarioVM.reset_all on start()/set_rewind_target) — else a VM restart/rewind
	# leaves the body hidden and the CrystalSprite3D billboard orphaned for the rest
	# of the session (the leak the code review flagged).
	var unit = await _make_real_unit()
	unit.scenario_inflict_crystal()
	await get_tree().process_frame
	_true(unit.is_crystallized(), "crystallized before reset")
	var billboard = unit._crystal_sprite

	unit.reset_scenario_cutscene_state()
	_true(not unit.is_crystallized(), "reset un-crystallizes the unit")
	_true(unit.mesh_instance.visible, "reset restores the body sprite visibility")
	_true(unit._crystal_sprite == null, "reset drops the crystal billboard reference")
	await get_tree().process_frame  # let queue_free settle
	_true(not is_instance_valid(billboard), "reset frees the CrystalSprite3D node")
	unit.queue_free()
