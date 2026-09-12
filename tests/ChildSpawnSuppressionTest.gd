extends Node
## TDD guard for ADR-0075 per-edge child-spawn suppression — the SIM half. Asserts the two
## spawn sites in ParticleSubsystem skip a suppressed `(parent, edge)` spawn while leaving a
## non-suppressed edge untouched, plus the accessor round-trip and the reset() survival that
## makes it config (re-applied on every deterministic re-pump), not transient state.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/ChildSpawnSuppressionTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter
const ParticleSubsystem = preload("res://addons/exmateria_effects/subsystem/ParticleSubsystem.gd")

const EffectDataClass = ExMateriaEffects.EffectData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_accessor_round_trip()
	_test_suppression_survives_reset()
	_test_on_death_edge_suppressed_skips_spawn()
	_test_mid_life_edge_suppressed_skips_spawn()
	_test_suppression_is_per_edge()

	print("\n=== ChildSpawnSuppressionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ChildSpawnSuppressionTest")
		get_tree().quit(1)
	else:
		print("[PASS] ChildSpawnSuppressionTest")
		get_tree().quit(0)


func _test_accessor_round_trip() -> void:
	var sub := _subsystem_with_child(true, false)
	_assert_true(not sub.is_child_edge_suppressed(0, "death"), "edges start un-suppressed")
	sub.set_child_edge_suppressed(0, "death", true)
	_assert_true(sub.is_child_edge_suppressed(0, "death"), "set true → suppressed")
	_assert_true(not sub.is_child_edge_suppressed(0, "midlife"), "a different edge is independent")
	_assert_true(not sub.is_child_edge_suppressed(1, "death"), "a different parent is independent")
	sub.set_child_edge_suppressed(0, "death", false)
	_assert_true(not sub.is_child_edge_suppressed(0, "death"), "set false → restored")


## Suppression is CONFIG, not state: it must outlive reset() so every re-pump re-applies it.
func _test_suppression_survives_reset() -> void:
	var sub := _subsystem_with_child(true, false)
	sub.set_child_edge_suppressed(0, "death", true)
	sub.reset()
	_assert_true(sub.is_child_edge_suppressed(0, "death"), "suppression survives reset()")


## A dead parent particle whose on-death edge is NOT suppressed spawns its child; the same
## edge suppressed spawns nothing.
func _test_on_death_edge_suppressed_skips_spawn() -> void:
	var spawned_live := _run_death_spawn(false)
	_assert_true(spawned_live > 0, "a live on-death edge spawns children (%d)" % spawned_live)

	var spawned_suppressed := _run_death_spawn(true)
	_assert_eq(spawned_suppressed, 0, "a suppressed on-death edge spawns no children")


func _test_mid_life_edge_suppressed_skips_spawn() -> void:
	var spawned_live := _run_midlife_spawn(false)
	_assert_true(spawned_live > 0, "a live mid-life edge spawns children (%d)" % spawned_live)

	var spawned_suppressed := _run_midlife_spawn(true)
	_assert_eq(spawned_suppressed, 0, "a suppressed mid-life edge spawns no children")


## Suppressing the death edge leaves the mid-life edge of the SAME parent spawning.
func _test_suppression_is_per_edge() -> void:
	var sub := _subsystem_with_child(true, true)
	sub.set_child_edge_suppressed(0, "death", true)
	_assert_true(sub.is_child_edge_suppressed(0, "death"), "death edge suppressed")
	_assert_true(not sub.is_child_edge_suppressed(0, "midlife"), "mid-life edge of same parent stays live")


# --- fixtures -------------------------------------------------------------

## A ParticleSubsystem for a 2-emitter effect: parent (index 0) spawns child (index 1) on
## death and/or mid-life per the authored flags; the child emits 3 particles with no spawn
## interval so a single call produces a countable burst.
func _subsystem_with_child(death_enabled: bool, midlife_enabled: bool) -> ParticleSubsystem:
	var ed = EffectDataClass.new()
	var parent = EffectEmitter.new()
	parent.index = 0
	parent.flags = {"child_death_enabled": death_enabled, "child_midlife_enabled": midlife_enabled}
	parent.child_emitter_on_death = 1
	parent.child_emitter_mid_life = 1
	var child = EffectEmitter.new()
	child.index = 1
	child.particle_count_start = 3
	child.spawn_interval_start = 0
	child.lifetime_min_start = 30
	child.lifetime_max_start = 30
	ed.emitters.append(parent)
	ed.emitters.append(child)

	var sub := ParticleSubsystem.new()
	sub.rng = RandomNumberGenerator.new()
	sub.initialize(ed, 64)
	return sub


## Seed one DEAD parent particle (on-death edge), process deaths, return child spawn count.
func _run_death_spawn(suppressed: bool) -> int:
	var sub := _subsystem_with_child(true, false)
	if suppressed:
		sub.set_child_edge_suppressed(0, "death", true)
	var p = sub.particle_pool.acquire()
	p.active = true
	p.emitter_index = 0
	p.child_emitter_on_death = 1
	p.lifetime = 1
	p.age = 5  # age >= lifetime → dead
	p.position = Vector3.ZERO
	var before := sub.particle_pool.get_active_count()
	sub._process_particle_deaths()
	return sub.particle_pool.get_active_count() - before


## Seed one ALIVE parent particle (mid-life edge), process mid-life, return child spawn count.
func _run_midlife_spawn(suppressed: bool) -> int:
	var sub := _subsystem_with_child(false, true)
	if suppressed:
		sub.set_child_edge_suppressed(0, "midlife", true)
	var p = sub.particle_pool.acquire()
	p.active = true
	p.emitter_index = 0
	p.child_emitter_mid_life = 1
	p.lifetime = 60
	p.age = 0  # alive
	p.position = Vector3.ZERO
	var before := sub.particle_pool.get_active_count()
	sub._process_midlife_children()
	return sub.particle_pool.get_active_count() - before


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
