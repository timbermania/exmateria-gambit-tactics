extends Node
## Unit tests for ScenarioActor — the per-unit cutscene data bag (ADR-0064). One
## value holding everything a unit's cutscene *owns*: tint (ScenarioColorTint),
## motion (ScenarioMotion), walker (CinematicWalkState), atlas_y offset, home
## anchor + an owner_iid node guard. Holds no owner node — the VM resolves the
## node via units_by_id and passes it into the home-capture methods.
##
## Like ScenarioMotion the bag is pure/scene-free: most assertions need no scene,
## no VM, no nodes. The home-capture methods take a node, so those use a bare
## Node3D (get_instance_id + global_position work without being in the tree).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioActorTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")

var _passed: int = 0
var _failed: int = 0
var _nodes: Array = []
var _vms: Array = []


func _ready() -> void:
	_test_defaults()
	_test_sub_state_set_and_clear()
	_test_home_capture_first_move()
	_test_home_capture_re_captures_on_iid_change()
	_test_clear_home_forces_recapture_same_node()
	_test_home_or_current_falls_back_when_uncaptured()
	# VM verbs (need a VM instance, but the data bag stays the star of the file).
	_test_actor_get_or_create()
	_test_peek_actor_non_creating()
	_test_peek_distinguishes_cleared_from_forgotten()
	_test_forget_erases_entry()
	_test_forget_absent_is_noop()
	_test_forget_does_not_reset_unit_fields()
	_test_reset_all_clears_registry_and_unit_fields()
	_test_reset_all_resets_unit_without_actor()
	_test_reset_all_empty_is_noop()

	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioActorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioActorTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioActorTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioActorTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _veq(got: Vector3, want: Vector3, name: String) -> void:
	if got.is_equal_approx(want):
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _node_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)  # global_position only applies once the node is in the tree
	n.global_position = pos
	_nodes.append(n)
	return n


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	vm.set_process(false)  # deterministic timing, no auto _process
	_vms.append(vm)
	return vm


# --- Cycle 1: a fresh actor is empty --------------------------------------

func _test_defaults() -> void:
	var a := ScenarioActor.new()
	_eq(a.tint, null, "fresh actor: tint null")
	_eq(a.motion, null, "fresh actor: motion null")
	_eq(a.walker, null, "fresh actor: walker null")
	_eq(a.atlas_y, 0, "fresh actor: atlas_y 0")
	_eq(a.has_home, false, "fresh actor: has_home false")


# --- Cycle 2: each sub-state sets and clears independently -----------------

func _test_sub_state_set_and_clear() -> void:
	var a := ScenarioActor.new()
	a.tint = ScenarioColorTint.new()
	a.motion = ScenarioMotion.new()
	a.atlas_y = 7
	_eq(a.tint != null, true, "tint set")
	_eq(a.motion != null, true, "motion set")
	_eq(a.atlas_y, 7, "atlas_y set")
	# Clearing a sub-state nulls the field — the actor entry itself survives.
	a.tint = null
	_eq(a.tint, null, "tint cleared to null")
	_eq(a.motion != null, true, "clearing tint leaves motion intact")


# --- Cycle 3: home is captured at the first move ---------------------------

func _test_home_capture_first_move() -> void:
	var a := ScenarioActor.new()
	var node := _node_at(Vector3(10, 2, 30))
	var home := a.capture_home(node)
	_veq(home, Vector3(10, 2, 30), "capture_home returns the node's position")
	_eq(a.has_home, true, "has_home true after capture")
	_eq(a.owner_iid, node.get_instance_id(), "owner_iid stamped to the node")
	# A second capture from the SAME node does NOT move home even if the node did
	# (the +0x60 offset slid; the base/home is fixed until re-placement).
	node.global_position = Vector3(99, 99, 99)
	var home2 := a.capture_home(node)
	_veq(home2, Vector3(10, 2, 30), "capture_home is sticky for the same node")


# --- Cycle 4: a different node id re-captures (the owner_iid guard) ---------

func _test_home_capture_re_captures_on_iid_change() -> void:
	var a := ScenarioActor.new()
	var first := _node_at(Vector3(1, 0, 1))
	a.capture_home(first)
	# Same uid rebinding to a different node (Remove+Add reuse) — the live node's
	# iid no longer matches owner_iid, so home is re-captured from the new node.
	var second := _node_at(Vector3(5, 0, 5))
	var home := a.capture_home(second)
	_veq(home, Vector3(5, 0, 5), "re-captures home when the node iid changes")
	_eq(a.owner_iid, second.get_instance_id(), "owner_iid follows the new node")


# --- Cycle 5: clear_home forces re-capture for the SAME node ----------------

func _test_clear_home_forces_recapture_same_node() -> void:
	# Warp / Walk re-places the unit's base without swapping the node, so the iid
	# guard can't see it — clear_home() makes the next move re-capture the seat.
	var a := ScenarioActor.new()
	var node := _node_at(Vector3(0, 0, 0))
	a.capture_home(node)
	node.global_position = Vector3(20, 0, 20)  # unit warped to a new base
	a.clear_home()
	_eq(a.has_home, false, "clear_home drops the captured home")
	var home := a.capture_home(node)
	_veq(home, Vector3(20, 0, 20), "re-captures the new base after clear_home")


# --- Cycle 6: home_or_current falls back before any capture ----------------

func _test_home_or_current_falls_back_when_uncaptured() -> void:
	var a := ScenarioActor.new()
	var node := _node_at(Vector3(3, 4, 5))
	# No capture yet — returns the node's live position.
	_veq(a.home_or_current(node), Vector3(3, 4, 5), "home_or_current: current when uncaptured")
	a.capture_home(node)
	node.global_position = Vector3(7, 7, 7)
	_veq(a.home_or_current(node), Vector3(3, 4, 5), "home_or_current: captured home once set")


# --- Cycle 7: actor(uid) get-or-create ------------------------------------

func _test_actor_get_or_create() -> void:
	var vm := _make_vm()
	var a := vm.actor(0x13)
	_eq(a != null, true, "actor(uid) returns an actor")
	_eq(a is ScenarioActor, true, "actor(uid) returns a ScenarioActor")
	# Get-or-create: a second call returns the SAME instance, not a fresh one.
	var a2 := vm.actor(0x13)
	_eq(a2, a, "actor(uid) returns the same instance on re-get")
	# State set on the first get survives the second get.
	a.atlas_y = 5
	_eq(vm.actor(0x13).atlas_y, 5, "actor(uid) preserves state across gets")


# --- Cycle 8: peek_actor(uid) is non-creating ------------------------------

func _test_peek_actor_non_creating() -> void:
	var vm := _make_vm()
	_eq(vm.peek_actor(0x21), null, "peek_actor null before first actor(uid)")
	var a := vm.actor(0x21)
	_eq(vm.peek_actor(0x21), a, "peek_actor returns the created actor")
	# peek must NOT create — peeking an absent uid leaves it absent.
	_eq(vm.peek_actor(0x99), null, "peek_actor(absent) stays null (non-creating)")
	_eq(vm.peek_actor(0x99), null, "peek_actor(absent) still null after peeking")


# --- Cycle 9: "sub-state cleared" vs "forgotten" are distinct --------------

func _test_peek_distinguishes_cleared_from_forgotten() -> void:
	var vm := _make_vm()
	var a := vm.actor(0x30)
	a.tint = ScenarioColorTint.new()
	# Clearing a sub-state nulls the field but the entry survives — peek non-null.
	a.tint = null
	_eq(vm.peek_actor(0x30) != null, true, "sub-state cleared: entry survives")
	_eq(vm.peek_actor(0x30).tint, null, "sub-state cleared: tint is null")


# --- Cycle 10: forget(uid, node) erases the whole entry --------------------

func _test_forget_erases_entry() -> void:
	var vm := _make_vm()
	var node := _node_at(Vector3(1, 0, 1))
	var a := vm.actor(0x83)
	a.tint = ScenarioColorTint.new()
	a.motion = ScenarioMotion.new()
	a.atlas_y = 7
	a.capture_home(node)
	_eq(vm.peek_actor(0x83) != null, true, "armed actor present before forget")

	vm.forget(0x83, node)

	# "forgotten" == the entry is gone entirely (distinct from sub-state cleared).
	_eq(vm.peek_actor(0x83), null, "forget erases the actor entry")


# --- Cycle 11: forgetting a unit with no actor is a clean no-op ------------

func _test_forget_absent_is_noop() -> void:
	var vm := _make_vm()
	var node := _node_at(Vector3.ZERO)
	# 0x99 never had an actor — must not crash, must stay absent.
	vm.forget(0x99, node)
	_eq(vm.peek_actor(0x99), null, "forget(absent) is a no-op")


# --- Cycle 12: forget does NOT reset the unit's cutscene fields ------------

func _test_forget_does_not_reset_unit_fields() -> void:
	# The regression guard: forget stays behavior-identical to the former
	# _forget_unit — it un-registers the unit but never touches Unit state. Only
	# reset_all (scene rewind, units persist) resets the three Unit fields.
	var vm := _make_vm()
	var mock := MockUnit.new()
	vm.actor(0x40)
	vm.forget(0x40, mock)
	_eq(mock.reset_called, false, "forget did NOT call reset_scenario_cutscene_state")


# --- Cycle 13: reset_all clears the registry AND every unit's 3 fields ------

func _test_reset_all_clears_registry_and_unit_fields() -> void:
	# THE FIX. Today start()/set_rewind_target leak all but home; reset_all is the
	# one path that clears all eight per-unit things — the five actor structures
	# (tint, motion, walker, atlas, home) AND the three Unit fields.
	var vm := _make_vm()
	var mock := MockUnit.new()
	var units := {0x13: mock}
	# Arm all five actor structures on this unit.
	var node := _node_at(Vector3(1, 0, 1))
	var a := vm.actor(0x13)
	a.tint = ScenarioColorTint.new()
	a.motion = ScenarioMotion.new()
	a.walker = RefCounted.new()  # stand-in walker; reset only cares it's non-null
	a.atlas_y = 9
	a.capture_home(node)
	# Dirty all three Unit fields (a rotate left facing set, an anim was playing).
	mock.facing_angle = 0x400
	mock.current_anim_id = 15

	vm.reset_all(units)

	# Registry cleared → every actor structure gone with the entry.
	_eq(vm.peek_actor(0x13), null, "reset_all: actor entry (tint/motion/walker/atlas/home) cleared")
	# Unit fields reset via the Unit method.
	_eq(mock.facing_angle, -1, "reset_all: facing_angle reset")
	_eq(mock.current_anim_id, 0, "reset_all: current_anim_id reset")
	_eq(mock.reset_called, true, "reset_all: called reset_scenario_cutscene_state")


# --- Cycle 14: reset_all resets a dirtied unit that owns no actor -----------

func _test_reset_all_resets_unit_without_actor() -> void:
	# A unit can carry a stale facing (a bare {2D} Rotate) with no tint/motion
	# actor. reset_all must still zero its fields — it iterates units, not actors.
	var vm := _make_vm()
	var mock := MockUnit.new()
	mock.facing_angle = 0x800
	vm.reset_all({0x22: mock})
	_eq(mock.reset_called, true, "reset_all resets a unit with no actor entry")
	_eq(mock.facing_angle, -1, "reset_all: no-actor unit facing reset")


# --- Cycle 15: reset_all with nothing armed is a clean no-op ----------------

func _test_reset_all_empty_is_noop() -> void:
	var vm := _make_vm()
	vm.reset_all({})  # no units, no actors — must not crash
	_eq(vm.actors.is_empty(), true, "reset_all({}) leaves an empty registry empty")


# --- Mock unit ------------------------------------------------------------
# A stand-in for Unit carrying the three cutscene fields reset_all zeroes, plus a
# flag recording whether reset_scenario_cutscene_state() was invoked. Lets the
# scene-free tests prove forget never resets and reset_all always does — without
# booting a real Unit (sprite/anim deps).
class MockUnit extends RefCounted:
	var facing_angle: int = -1
	var current_anim_id: int = 0
	var reset_called: bool = false

	# Signature must track `Unit.reset_scenario_cutscene_state`. `reset_all` calls it with
	# `preserve_poses` (added by the scn6 pose-carry fix), and a dynamic call with the wrong
	# arity does not raise here — it prints a SCRIPT ERROR, returns, and leaves the mock
	# untouched, so the five reset assertions failed as if reset_all had done nothing.
	func reset_scenario_cutscene_state(_preserve_poses: bool = false) -> void:
		facing_angle = -1
		current_anim_id = 0
		reset_called = true
