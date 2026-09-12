extends Node3D
## #589 — the assembler block that carries `Battlefield`'s three outputs to the
## host systems that consume them, now that the addon no longer names them.
##
## `check_addon_portability.py` enforces the SEVERANCE: the three reaches are
## gone and their `ARM1_BURN_DOWN` rows are deleted, so re-adding either goes
## red. What no static guard can see is whether the values still ARRIVE — and
## the failure mode is silent. A missed wiring site does not error; the map
## simply stops tinting during effects and the sky keeps the fallback blue.
##
## Five arms. Four drive a duck-typed stand-in, because the semantics under test
## are the WIRING's (replay, connect, idempotence, the empty-gradient case) and
## a real map build cannot isolate them. The sixth drives a REAL `MapComposer`
## that auto-built its default map, and it is not optional: without it the other
## four are a closed loop asserting that a fake this file wrote matches a fake
## this file wrote. Arm 6 is the only one that can say the addon's published
## halves are non-empty on a map the game actually composes.
##
## Run: <GODOT> --path . res://tests/BattlefieldWiringTest.tscn

var _failed := 0
var _passed := 0


## Duck-typed stand-in for MapComposer's published half — the same shape
## MapDebugPanelMountTest's FakeComposer uses, for the same reason.
class FakeComposer extends Node:
	signal map_material_created(material: ShaderMaterial)
	signal map_gradient_resolved(top: Color, bottom: Color)

	var materials: Array[ShaderMaterial] = []
	var gradient: Array[Color] = []

	func map_materials() -> Array[ShaderMaterial]:
		return materials

	func map_gradient() -> Array[Color]:
		return gradient


func _ready() -> void:
	_test_replay_drains_existing_materials()
	_test_connect_delivers_later_materials()
	_test_unbuilt_composer_pushes_no_gradient()
	_test_replay_pushes_a_resolved_gradient()
	await _test_a_real_composer_publishes_both_halves()

	print("\n=== BattlefieldWiringTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] BattlefieldWiringTest")
		get_tree().quit(1)
	else:
		print("[PASS] BattlefieldWiringTest")
		get_tree().quit(0)


## Every scene root wires AFTER composition — the builder is constructed inside
## `_build_map`, so nothing outside the addon can connect before the first
## materials exist. A connect-only wiring would register none of them.
func _test_replay_drains_existing_materials() -> void:
	var composer := FakeComposer.new()
	var mat := ShaderMaterial.new()
	composer.materials.append(mat)
	add_child(composer)

	BattlefieldWiring.wire_map(composer)
	_expect(_is_registered(mat), "replay registers a material built before the wiring ran")
	composer.queue_free()


## ...and materials are created lazily per surface type on every `rebuild_mesh`,
## including doodad add/remove long after the map composed. A drain-only wiring
## would go stale on the first one of those.
func _test_connect_delivers_later_materials() -> void:
	var composer := FakeComposer.new()
	add_child(composer)
	BattlefieldWiring.wire_map(composer)

	var mat := ShaderMaterial.new()
	_expect(not _is_registered(mat), "the later material is not registered before it is created")
	composer.map_material_created.emit(mat)
	_expect(_is_registered(mat), "connect registers a material built after the wiring ran")
	composer.queue_free()


## "No gradient" and "the fallback gradient" are different facts. `map_gradient()`
## returns EMPTY until a manifest resolves one, so wiring a host that has not
## composed a map must not paint the composer's fallback blue over whatever the
## host had. Without `_gradient_resolved` this arm is the one that fails.
func _test_unbuilt_composer_pushes_no_gradient() -> void:
	# THE SENTINEL IS LOAD-BEARING. This arm first read the overlay's CURRENT
	# gradient and asserted it did not move — and it was inert: seeded with the
	# empty-gradient guard removed, `MapComposer`'s fallback blue got pushed and
	# the arm still passed, because the overlay's boot state already WAS that
	# blue. Two different facts compared equal. A colour nothing else in the tree
	# uses is what makes "nothing was pushed" distinguishable from "the fallback
	# was pushed".
	const SENTINEL_TOP := Color(0.91, 0.07, 0.83)
	const SENTINEL_BOTTOM := Color(0.13, 0.87, 0.29)
	ScreenEffectOverlay.set_default_gradient(SENTINEL_TOP, SENTINEL_BOTTOM)

	var composer := FakeComposer.new()
	add_child(composer)
	BattlefieldWiring.wire_map(composer)   # map_gradient() == []

	_expect(ScreenEffectOverlay.get_default_top().is_equal_approx(SENTINEL_TOP)
			and ScreenEffectOverlay.get_default_bottom().is_equal_approx(SENTINEL_BOTTOM),
		"an unbuilt composer pushes no gradient at all (top is now %s)"
			% ScreenEffectOverlay.get_default_top())
	composer.queue_free()


func _test_replay_pushes_a_resolved_gradient() -> void:
	var top := Color(0.11, 0.22, 0.33)
	var bottom := Color(0.44, 0.55, 0.66)
	var resolved: Array[Color] = [top, bottom]
	var composer := FakeComposer.new()
	composer.gradient = resolved
	add_child(composer)

	BattlefieldWiring.wire_map(composer)
	_expect(ScreenEffectOverlay.get_default_top().is_equal_approx(top),
		"replay pushes the resolved gradient TOP (got %s)" % ScreenEffectOverlay.get_default_top())
	_expect(ScreenEffectOverlay.get_default_bottom().is_equal_approx(bottom),
		"replay pushes the resolved gradient BOTTOM (got %s)" % ScreenEffectOverlay.get_default_bottom())
	composer.queue_free()


## THERE IS NO "WIRING TWICE" ARM, and the reason is a finding rather than an
## omission. One was written — wire the same composer twice, assert one
## connection on each signal — and it CANNOT FAIL: seeded with both
## `is_connected` guards removed, it still read 1 and 1, because the ENGINE
## refuses a duplicate connection ("Signal 'map_material_created' is already
## connected to given callable"). The invariant is Godot's, not
## `BattlefieldWiring`'s, so an assertion on it is a tautology dressed as
## coverage.
##
## What the guards actually buy is the absence of those two ERROR lines on every
## re-wire — and roots DO re-wire (`ScenarioPlayerScene` is inherited by
## `NavigatorMain`, and a map change re-runs the path). That is a log-surface
## property, and the suite's SCRIPT-ERROR/ERROR grep is the instrument for it,
## not an `_expect` in here.


## THE ARM THE FAKES CANNOT REPLACE. A real `MapComposer` auto-builds its default
## map in its own `_ready`; both published halves must be non-empty by the time
## a parent root could wire it. If `map_materials()` filtered wrongly, or the
## gradient never resolved, every arm above would still pass.
func _test_a_real_composer_publishes_both_halves() -> void:
	var composer: Node = $ProceduralMap
	for _i in 4:
		await get_tree().process_frame

	_expect(composer.is_built, "the embedded MapComposer finished building")
	_expect(not composer.map_materials().is_empty(),
		"a built map publishes at least one ShaderMaterial (got %d)"
			% composer.map_materials().size())
	_expect(composer.map_gradient().size() == 2,
		"a built map publishes a resolved [top, bottom] gradient (got %s)"
			% [composer.map_gradient()])

	# ...and wiring it registers those real materials, which is the whole chain.
	BattlefieldWiring.wire_map(composer)
	var missing := 0
	for mat in composer.map_materials():
		if not _is_registered(mat):
			missing += 1
	_expect(missing == 0, "every real map material reaches TintedSurfaces.SURFACE_MAP (%d missing)" % missing)


func _is_registered(mat: ShaderMaterial) -> bool:
	# #1224: the map is the reserved SURFACE_MAP token of the merged registry, and its
	# materials are that surface's material ARRAY.
	return mat in TintedSurfaces._surface_materials.get(TintedSurfaces.SURFACE_MAP, [])


func _expect(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % what)
