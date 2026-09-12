extends Node
## Guard — the deployed owned squad march-idles on the ONE ScenarioVM 60 Hz tick.
##
## The bug: `_deploy_owned_units` makes each owned unit `tick_based` (combat determinism),
## so its `Unit._process` delta pump no-ops; and only the LEADER is registered in
## `_units_by_id`, so the ScenarioVM's `_advance_scenario_anim` (which pumps `units_by_id`
## once per 60 Hz tick) misses the generic squadmates. Between deploy and the CombatLoop
## taking over, nothing advances their frame clock — they freeze on frame 0 at the
## deployment pause while Ramza + the ENTD cast march.
##
## The fix (ADR-0065 — ONE vblank-quantized tick): the strays ride the SAME VM tick, not a
## second hand-rolled accumulator in NavigatorMain. ScenarioVM grows an `idle_only_units`
## register that `_advance_scenario_anim` advances every tick (in lockstep with `units_by_id`,
## but addressable by nothing else); NavigatorMain registers the deployed generics there at
## deploy and clears them on free. This guards BOTH sides of that seam:
##   - VM side: `idle_only_units` advance in LOCKSTEP with `units_by_id` on the one quantized
##     tick (same count), and a stray in `idle_only_units` only is advanced once per tick.
##   - Cadence: driving the real host->tick quantizer (`_advance_frame`) at a NON-60 host rate
##     advances the strays at the 60 Hz VM cadence, NOT the host frame rate.
##   - NavigatorMain side: deploy registers the REMAINDER — every deployed unit that did not
##     get an event id — onto the VM, and `_free_deployed_owned` clears the register.
##
## ⚠️ THE REMAINDER IS NOT "EVERYONE BUT THE LEADER". It was, for as long as `0x01` was the
## only event id the deploy seam handed out; the squad now takes `0x78`+ ids too, because 28
## of 72 battle openers address it there. Whoever holds an id rides the `units_by_id` pump and
## must stay OFF this list — registering a unit on both double-pumps it. So the two arms below
## are two cases of one rule, not one rule and an exception.
##
## Run: "$GODOT" --path . --quit-after 6 res://tests/NavigatorDeployedIdlePumpTest.tscn

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

const NavigatorMainClass = preload("res://src/scenarios/NavigatorMain.gd")
const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

## Minimal stand-in for a deployed Unit: counts frame advances, carries `tick_based`, and
## satisfies `has_method("advance_frame")` + `is_instance_valid`.
class StubUnit extends Node:
	# Deployed units breathe via the VM (SCENARIO-owned) during Deployment (ADR-0083);
	# owner is settable, tick_based derived — mirrors the real Unit.
	var clock_owner: ClockOwner = ClockOwner.SCENARIO
	var tick_based: bool:
		get: return clock_owner != ClockOwner.SELF
	var frames: int = 0
	func advance_frame(_normal := 1, _react := 1) -> void:
		frames += 1

var _failed := 0
var _passed := 0


func _ready() -> void:
	_test_vm_lockstep()
	_test_alias_is_one_body()
	_test_quantizer_cadence()
	_test_navigator_registration()
	_test_navigator_registration_full_squad()
	_finish()


## VM side: the idle-only strays advance in lockstep with `units_by_id` on the one tick, and
## a stray that is ONLY in `idle_only_units` is pumped exactly once per tick (not double).
func _test_vm_lockstep() -> void:
	var vm = ScenarioVMClass.new()  # not in tree: drive `_advance_scenario_anim` directly
	var leader := StubUnit.new()
	var g1 := StubUnit.new()
	var g2 := StubUnit.new()
	vm.units_by_id = {NavigatorMainClass.RAMZA_EVENT_UID: leader}  # the VM already pumps the leader
	vm.idle_only_units = [g1, g2]                                  # the strays ride the SAME tick

	for _i in range(30):
		vm._advance_scenario_anim()

	_expect(g1.frames == 30 and g2.frames == 30,
		"idle-only strays advance one frame per VM tick (g1=%d g2=%d, expected 30)" % [g1.frames, g2.frames])
	_expect(leader.frames == g1.frames,
		"strays advance in LOCKSTEP with units_by_id on the one clock (leader=%d strays=%d)" % [leader.frames, g1.frames])

	leader.free(); g1.free(); g2.free(); vm.free()


## AN EVENT ID IS NOT A UNIT. The deployed leader answers to `0x78` AND to the `0x01`
## protagonist alias — one body under two keys — and the pump walks `units_by_id.keys()`. It
## used to advance as it walked, so that one body took TWO frames per tick: measured at
## Gariland, Ramza's idle ran at 120 sprite-frames/s against the other nine units' 60 for the
## whole opener and the whole Deployment hold, then halved at `_go_live` when the CombatLoop's
## single pump took over. A 2x animation-rate step on the protagonist, landing exactly on the
## story→battle handoff.
##
## ⚠️ ADR-0083 DOES NOT COVER THIS and that is why it went unseen: its invariant is one OWNER
## per unit, and both of these advances came from the same owner. The rule this arm states is
## the other one — one DECISION per body per tick.
##
## Arm 2 is why the dedupe collects the gates across every id rather than taking the first key
## it sees. `_units_by_id` is insertion-ordered and the squad's `0x78`+ ids are registered
## BEFORE the `0x01` alias, so a first-key-wins dedupe would walk past a `{11}` paint mark left
## on the alias and advance a body that is supposed to be holding its freshly-painted frame 0.
func _test_alias_is_one_body() -> void:
	var vm = ScenarioVMClass.new()
	var leader := StubUnit.new()
	var peer := StubUnit.new()
	# The shipped registration order (`NavigatorMain._deploy_owned_units`): squad ids first,
	# the protagonist alias last.
	vm.units_by_id = {
		NavigatorMainClass.SQUAD_EVENT_UID_BASE: leader,
		NavigatorMainClass.SQUAD_EVENT_UID_BASE + 1: peer,
		NavigatorMainClass.RAMZA_EVENT_UID: leader,
	}

	for _i in range(30):
		vm._advance_scenario_anim()

	_expect(leader.frames == 30,
		"a body under TWO event ids advances ONCE per tick (leader=%d, expected 30 — 60 is the double pump)"
			% leader.frames)
	_expect(leader.frames == peer.frames,
		"the aliased body and its single-id peer run at the SAME rate (leader=%d peer=%d)"
			% [leader.frames, peer.frames])

	# Arm 2 — the {11} paint mark sits on the ALIAS, which is the LAST key. The hold must still
	# take: the gates are collected across every id naming the body, not read off the first one.
	var before := leader.frames
	vm._painted_this_tick = {NavigatorMainClass.RAMZA_EVENT_UID: true}
	vm._advance_scenario_anim()
	_expect(leader.frames == before,
		"a {11} paint on the LAST key still holds the body's clock (advanced %d frame(s) through the hold)"
			% [leader.frames - before])
	_expect(peer.frames == before + 1,
		"the hold is the painted body's only — its peer still advances (peer=%d, expected %d)"
			% [peer.frames, before + 1])

	leader.free(); peer.free(); vm.free()


## Cadence: the strays ride the VM's host->tick quantizer, so at a NON-60 host rate they
## advance at the 60 Hz VM cadence, not once per host frame. Drives the REAL `_advance_frame`
## (VM added to the tree so `_ready` builds box_pool/camera_director; never started, so
## `_tick_once` early-returns and no dispatch/motion runs).
func _test_quantizer_cadence() -> void:
	var vm = ScenarioVMClass.new()
	add_child(vm)  # run _ready: box_pool + camera_director exist for `_advance_frame`
	var g1 := StubUnit.new()
	vm.idle_only_units = [g1]

	# Host running at 30 fps (delta = 1/30). One VM second = 60 ticks, so 30 host frames must
	# advance the stray ~60 times (the 60 Hz VM cadence), NOT 30 (the host frame count).
	for _i in range(30):
		vm._advance_frame(1.0 / 30.0)

	_expect(g1.frames >= 58 and g1.frames <= 62,
		"stray rides the 60 Hz VM quantizer, not the host frame rate (30 host frames @ 1/30 -> g1=%d, expected ~60)" % g1.frames)

	g1.free()
	vm.queue_free()


## NavigatorMain side: deploy registers the deployed units that hold NO event id onto the
## VM's idle-only list (an id-holder rides units_by_id, so listing it too would double-pump),
## and `_free_deployed_owned` clears the register.
func _test_navigator_registration() -> void:
	var nav = NavigatorMainClass.new()  # NOT added to the tree: skip _ready's full walk plan
	var vm = ScenarioVMClass.new()
	var leader := StubUnit.new()
	var g1 := StubUnit.new()
	var g2 := StubUnit.new()
	nav._vm = vm
	nav._deployed_owned = [leader, g1, g2]
	nav._units_by_id = vm.units_by_id  # share the dict the VM pumps (mirrors _boot_scenario_world)
	nav._units_by_id[NavigatorMainClass.RAMZA_EVENT_UID] = leader

	# Mirror the tail of `_deploy_owned_units`: register the strays onto the VM's one-tick list.
	nav._register_deployed_idle_pump()
	_expect(vm.idle_only_units == [g1, g2],
		"deploy registers the un-addressed units (the id-holding leader excluded) on the VM idle-only tick (got %s)" % [vm.idle_only_units])

	nav._free_deployed_owned()
	_expect(vm.idle_only_units.is_empty(),
		"free clears the VM idle-only register (got %s)" % [vm.idle_only_units])

	leader.free(); g1.free(); g2.free(); vm.free(); nav.free()


## The SHIPPED shape since the opener-placement fix: the whole squad holds `0x78`+ event ids
## (plus the leader's `0x01` alias), so the VM's `units_by_id` pump advances all of them and
## the idle-only remainder is EMPTY. A stray that got no id still lands on the list — which is
## what proves the register is a remainder and not a hardcoded "slice off index 0".
##
## And `_free_deployed_owned` must drop EVERY registry entry pointing at a deployed unit, not
## just the `0x01` alias: `_teardown_world` sweeps `units_by_id` and frees what it finds, so a
## left-behind `0x78` entry is a second free of an already-freed unit.
func _test_navigator_registration_full_squad() -> void:
	var nav = NavigatorMainClass.new()
	var vm = ScenarioVMClass.new()
	var leader := StubUnit.new()
	var g1 := StubUnit.new()
	var g2 := StubUnit.new()
	var stray := StubUnit.new()   # deployed but past the squad id block — no event id
	nav._vm = vm
	nav._deployed_owned = [leader, g1, g2, stray]
	nav._units_by_id = vm.units_by_id
	nav._units_by_id[NavigatorMainClass.RAMZA_EVENT_UID] = leader
	for i in 3:
		nav._units_by_id[NavigatorMainClass.SQUAD_EVENT_UID_BASE + i] = nav._deployed_owned[i]

	nav._register_deployed_idle_pump()
	_expect(vm.idle_only_units == [stray],
		"an id-holding squad rides units_by_id; only the un-addressed stray is idle-pumped (got %s)"
			% [vm.idle_only_units])

	nav._free_deployed_owned()
	_expect(nav._units_by_id.is_empty(),
		"free drops EVERY registry entry pointing at a deployed unit (0x78+ and the 0x01 alias) — left %s"
			% [nav._units_by_id.keys()])
	_expect(vm.idle_only_units.is_empty(),
		"free clears the VM idle-only register (got %s)" % [vm.idle_only_units])

	leader.free(); g1.free(); g2.free(); stray.free(); vm.free(); nav.free()


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	print("\n=== NavigatorDeployedIdlePumpTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] NavigatorDeployedIdlePumpTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] NavigatorDeployedIdlePumpTest")
		get_tree().quit(1)
	else:
		print("[PASS] NavigatorDeployedIdlePumpTest")
		get_tree().quit(0)
