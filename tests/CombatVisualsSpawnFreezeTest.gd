extends Node
## Regression (code-review #2): a `combat_visuals` member that SPAWNS while a
## freeze is in effect — e.g. the {92} SS=1 crystal billboard appearing during a
## cast cinematic — must be frozen immediately, not animate until the next
## transition-driven `_refresh_combat_visuals_freeze()`. Guards CombatLoop's
## `_on_scene_node_added` / `_apply_spawn_freeze` (ADR-0037 dec. 10).
##
## Runs against a real CombatLoop with a stub cinematic manager (no GPU setup) —
## it drives the actual `SceneTree.node_added` path the fix wires up.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/CombatVisualsSpawnFreezeTest.tscn

const CombatLoopClass = preload("res://src/gpu/CombatLoop.gd")

var _passed: int = 0
var _failed: int = 0


# Minimal cinematic-manager stand-in: extends the real type (so it satisfies
# CombatLoop.cinematic_manager's static type) but overrides the two methods the
# freeze predicate calls with forced values. `_init(null)` is fine — the base is
# only read by the overridden methods.
class StubCinematic extends CinematicManager:
	var active: bool = false
	var caster_idx: int = -1
	func is_active() -> bool: return active
	func active_caster_idx() -> int: return caster_idx


# A combat_visuals member that joins the group in its OWN _ready (like
# CrystalSprite3D), so the deferred node_added→ready path is what's exercised.
class FakeVisual extends Node:
	func _ready() -> void:
		add_to_group("combat_visuals")


func _ready() -> void:
	await _test_spawn_during_cinematic_is_frozen()
	await _test_spawn_while_running_stays_inherit()
	_test_caster_subtree_keeps_running()

	print("\n=== CombatVisualsSpawnFreezeTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CombatVisualsSpawnFreezeTest")
		get_tree().quit(1)
	else:
		print("[PASS] CombatVisualsSpawnFreezeTest")
		get_tree().quit(0)


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


# Build a CombatLoop wired with a stub cinematic manager and the node_added
# listener the fix installs (mirrors `_initialize_managers`). Returns the loop.
func _make_loop(cinematic_active: bool, caster_idx: int) -> CombatLoopClass:
	var loop: CombatLoopClass = CombatLoopClass.new()
	add_child(loop)
	var stub := StubCinematic.new(null)
	stub.active = cinematic_active
	stub.caster_idx = caster_idx
	loop.cinematic_manager = stub
	loop.combat_active = true
	loop.get_tree().node_added.connect(loop._on_scene_node_added)
	return loop


# Immediate teardown: disconnect the tree listener and free NOW (not deferred), so
# one test's still-active loop can't intercept the next test's spawned nodes.
func _drop(loop: CombatLoopClass) -> void:
	var tree := loop.get_tree()
	if tree and tree.node_added.is_connected(loop._on_scene_node_added):
		tree.node_added.disconnect(loop._on_scene_node_added)
	loop.free()


func _test_spawn_during_cinematic_is_frozen() -> void:
	var loop := _make_loop(true, -1)  # cinematic up, no caster → non-caster members freeze
	var vis := FakeVisual.new()
	loop.add_child(vis)  # node_added → _apply_spawn_freeze.call_deferred
	await get_tree().process_frame  # let the deferred apply run (past the member's _ready)
	_assert(vis.is_in_group("combat_visuals"), "spawned member joined combat_visuals")
	_assert(vis.process_mode == Node.PROCESS_MODE_DISABLED,
		"crystal spawned mid-cinematic is frozen on spawn (not INHERIT)")
	_drop(loop)


func _test_spawn_while_running_stays_inherit() -> void:
	var loop := _make_loop(false, -1)  # combat live, no cinematic → listener bails, nothing frozen
	var vis := FakeVisual.new()
	loop.add_child(vis)
	await get_tree().process_frame
	_assert(vis.process_mode == Node.PROCESS_MODE_INHERIT,
		"spawn during normal combat keeps running (INHERIT, no needless freeze)")
	_drop(loop)


# The cinematic spotlight carve-out: a member under the caster's own subtree keeps
# running even during the freeze (mirrors the GPU U_PAUSED exemption). Exercises
# the freeze authority `_visuals_should_run` directly.
func _test_caster_subtree_keeps_running() -> void:
	var loop := _make_loop(true, 0)  # cinematic up, caster = unit 0
	var caster := Node3D.new()
	loop.add_child(caster)
	loop.units = [caster]
	var under_caster := FakeVisual.new()
	caster.add_child(under_caster)
	var elsewhere := FakeVisual.new()
	loop.add_child(elsewhere)
	_assert(loop._visuals_should_run(under_caster),
		"caster's own subtree keeps animating during its cinematic")
	_assert(not loop._visuals_should_run(elsewhere),
		"a non-caster member is frozen during the cinematic")
	_drop(loop)
