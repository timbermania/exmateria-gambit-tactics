extends Node
## Regression tests for event opcode `{68} Mirror Sprite` and its composition rule.
##
## PSX (research/working_documents/MIRROR_SPRITE_OPCODE_68.md):
##   * `evt0x68_mirror_sprite_handler` @0x8013E65C latches `unit[+0x13F]`
##     (flip_xor_mask) = 0x02 when `Mirror == 1`, 0x00 otherwise.
##   * `unit_sprite_render_dispatch` composes the flip word it hands the packet
##     builder as `render_flags(+0x12) ^ flip_xor_mask(+0x13F)` — `xor` @0x80086764
##     (and again @0x8007F374 for the translucent pass). `render_flags` bit 1 is the
##     facing/camera-derived horizontal flip, recomputed EVERY frame from the
##     (camera yaw + unit facing) octant.
##
## So the rule under test is XOR, not override: a mirrored unit must stay mirrored
## while its natural flip is recomputed, and must flip to the OPPOSITE of whatever
## that recompute produced. A single facing cannot tell XOR from override, so the
## composition arms sweep all four camera quadrants against both mirror states.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ScenarioMirrorSpriteTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const SpriteLayerManagerClass = ExMateriaSpriteRig.SpriteLayerManager
## ADR-0189 dec. 8: a `.gd` outside Sprite Rig must not name a unit shader path —
## ask UnitMaterial for a variant instead.
const UnitMaterialVariant = ExMateriaSchema.UnitMaterialVariant.Kind
## ADR-0212 dec. 1 / #746 — the rig's classes are INTERNAL; reach them through the
## folder-named façade, not a bare global name.
const UnitMaterial = ExMateriaSpriteRig.UnitMaterial
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

var _passed: int = 0
var _failed: int = 0


## A stand-in for Unit that carries only what `_apply_cinematic_reversion` reads.
class FakeUnit extends Node:
	var facing_direction: int = 0
	var sprite_layers = null
	var camera_quadrant: int = 0

	func get_camera_quadrant() -> int:
		return camera_quadrant


func _ready() -> void:
	_test_composition_is_xor_not_override()
	_test_mirror_survives_the_per_frame_base_recompute()
	_test_mirror_zero_restores_the_default()
	_test_cinematic_walker_recompute_does_not_clobber_the_mirror()
	_test_opcode_68_is_bound_and_verified()

	print("\n=== ScenarioMirrorSpriteTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioMirrorSpriteTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioMirrorSpriteTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioMirrorSpriteTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got %s want %s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


## A live SpriteLayerManager bound to the real unit shader, so every assertion
## reads the shader uniform the GPU would sample — not just the GDScript field.
func _make_slm():
	var slm = SpriteLayerManagerClass.new()
	var mat := ShaderMaterial.new()
	mat.shader = UnitMaterial.shader_for(UnitMaterialVariant.OPAQUE)
	slm.material = mat
	return slm


func _bound(slm) -> bool:
	return bool(slm.material.get_shader_parameter("global_reversion"))


# --- 1. the composition rule ------------------------------------------------

func _test_composition_is_xor_not_override() -> void:
	var slm = _make_slm()
	# All four (base, mirror) pairs. Override would pin the last two rows to the
	# mirror value alone and lose the base — XOR does not.
	for base in [false, true]:
		for mirror in [false, true]:
			slm.set_global_reversion(base)
			slm.set_mirror_xor(mirror)
			_eq(_bound(slm), base != mirror,
				"compose base=%s mirror=%s" % [str(base), str(mirror)])
			_eq(slm.apply_reversion, base != mirror,
				"apply_reversion tracks the composed flip (base=%s mirror=%s)" % [str(base), str(mirror)])

	# Write order must not matter: the ROM keeps the two halves in separate
	# unit-struct fields precisely so neither write is a clobber.
	slm.set_mirror_xor(true)
	slm.set_global_reversion(true)
	_eq(_bound(slm), false, "mirror-then-base is the same composition")


# --- 2. the actual blocker --------------------------------------------------

func _test_mirror_survives_the_per_frame_base_recompute() -> void:
	var slm = _make_slm()
	slm.set_global_reversion(false)
	slm.set_mirror_xor(true)
	_eq(_bound(slm), true, "mirror applied over an un-reverted base")

	# 10 frames of the facing/camera recompute re-pushing the SAME base. Before the
	# fix this overwrote `global_reversion` on the very next rendered frame.
	for _i in range(10):
		slm.set_global_reversion(false)
	_eq(_bound(slm), true, "mirror survives 10 base recomputes")
	_eq(slm.mirror_xor, true, "mirror latch is untouched by a base write")

	# And when the recompute changes its mind, the mirror tracks it by XOR.
	slm.set_global_reversion(true)
	_eq(_bound(slm), false, "mirror XORs the NEW base, it does not override it")


func _test_mirror_zero_restores_the_default() -> void:
	var slm = _make_slm()
	slm.set_global_reversion(true)
	slm.set_mirror_xor(true)
	_eq(_bound(slm), false, "mirrored")
	# {68} Mirror=0 -> unit[+0x13F] = 0x00 = the unit-add default (0x80087C34).
	slm.set_mirror_xor(false)
	_eq(_bound(slm), true, "Mirror=0 restores the un-mirrored base exactly")
	_eq(slm.mirror_xor, false, "clear path drops the latch")


# --- 3. the cinematic path (the site that used to clobber it) ---------------

func _test_cinematic_walker_recompute_does_not_clobber_the_mirror() -> void:
	var unit := FakeUnit.new()
	add_child(unit)
	var slm = _make_slm()
	unit.sprite_layers = slm

	var walker = ScenarioVMClass.CinematicWalkState.new()
	walker.unit = unit

	slm.set_mirror_xor(true)
	# Sweep the camera quadrants: `get_camera_variant().revert` takes BOTH values
	# across them, so this arm distinguishes XOR from override rather than
	# confirming one facing twice.
	var reverts := {}
	for quad in range(4):
		unit.camera_quadrant = quad
		var want_base: bool = bool(AnimationStateController.get_camera_variant(
			unit.facing_direction, quad)["revert"])
		reverts[want_base] = true
		walker._apply_cinematic_reversion(slm)
		_eq(_bound(slm), not want_base,
			"cinematic quad=%d: mirror XORs the derived revert" % quad)
	_eq(reverts.size(), 2, "the quadrant sweep produced BOTH revert values")

	slm.set_mirror_xor(false)
	for quad in range(4):
		unit.camera_quadrant = quad
		var want_base: bool = bool(AnimationStateController.get_camera_variant(
			unit.facing_direction, quad)["revert"])
		walker._apply_cinematic_reversion(slm)
		_eq(_bound(slm), want_base,
			"cinematic quad=%d unmirrored: the derived revert stands alone" % quad)

	unit.queue_free()


# --- 4. dispatch ------------------------------------------------------------

func _test_opcode_68_is_bound_and_verified() -> void:
	var descriptors: Dictionary = EventInstructionSet.all()
	_true(descriptors.has(EventInstruction.MIRROR_SPRITE), "catalog has 0x68")
	var d: Dictionary = descriptors[EventInstruction.MIRROR_SPRITE]
	_eq(d.get("name", ""), "Mirror Sprite", "0x68 name")
	_true(d.get("verified", false), "0x68 is verified (arms the coverage invariant)")
	# Operand widths against the ROM size table: [0x68] = 3 -> 4-byte instruction.
	var params: Array = d.get("params", [])
	_eq(params.size(), 2, "0x68 operand count")
	_eq(int(params[0].get("bytes", 0)) + int(params[1].get("bytes", 0)), 3,
		"0x68 operand bytes == event_opcode_operand_size_table[0x68]")

	var vm := ScenarioVMClass.new()
	add_child(vm)  # _ready registers the handlers
	_true(vm._handlers.has(EventInstruction.MIRROR_SPRITE),
		"0x68 is bound (would halt the VM at scenario 29 PC 269 otherwise)")
	_true(not vm._skip_reasons.has(EventInstruction.MIRROR_SPRITE),
		"0x68 is a real handler, not a clean-skip")
	vm.queue_free()
