extends Node
## Tests for ScenarioVM's {0x32} Color Unit — the Orbonne door-exit per-unit
## palette tint (the "fade" the priest + attendants do as they walk out).
##
## FFT decode + LIVE PSX capture (research/working_documents/
## UNIT_FADE_COLOR_UNIT_OPCODE.md): DAT_800e4ea4 is the unit's 16-colour BGR555
## CLUT. The tint engine (FUN_8008f710 setup + FUN_800912a4 ramp) rewrites each
## entry per frame; for the whole palette every non-luma mode is the same
## per-channel affine map (tinted = base*scale + bias), so ScenarioColorTint
## models (scale,bias) and the unit shader applies it to the sampled palette.
##
## Golden vector below is the LIVE pcsx capture of unit 23 (slot 3) on the
## `orbonne_three_actors_walk_in` savestate: SET mode=1/time=0 (snap to half)
## then SET mode=8/time=2 (ramp back to base). Mode 1 is a per-channel >>1 halve
## (verified byte-exact); mode 8 restores to the base palette.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioColorUnitTest.tscn

const ScenarioVMClass = preload("res://src/scenarios/ScenarioVM.gd")
const Tint = preload("res://src/scenarios/ScenarioColorTint.gd")
const Recipe = ExMateriaSchema.ColorRecipe

# Live capture — unit-23 CLUT colours 1..15 (colour 0 is transparent = 0x0000).
# base = palette at rest; halved = after `Color=1 Time=0` (per-channel >>1).
const GOLDEN_BASE := [
	0x90A5, 0xD77C, 0x90CA, 0x952D, 0xA190, 0xA634, 0x952E, 0x95F6,
	0xA6FD, 0x9D29, 0xADD0, 0xCEB7, 0x9552, 0xAE19, 0xCAFF]
const GOLDEN_HALVED := [
	0x8842, 0xA9AE, 0x8865, 0x8886, 0x90C8, 0x910A, 0x8887, 0x88EB,
	0x916E, 0x8C84, 0x94E8, 0xA54B, 0x88A9, 0x950C, 0xA56F]

var _passed: int = 0
var _failed: int = 0
var _vms: Array = []


func _ready() -> void:
	_test_ramp_frames_for_time()
	_test_mode1_snap_halves_golden()
	_test_mode8_restores_to_base()
	_test_time0_snaps_no_ramp()
	_test_fast_ramp_is_eight_frames()
	_test_luma_mode_flagged()
	_test_handler_registered_and_applies()
	_test_reset_palette_clears_tint()

	for vm in _vms:
		if is_instance_valid(vm):
			vm.queue_free()

	print("\n=== ScenarioColorUnitTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioColorUnitTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioColorUnitTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioColorUnitTest")
		get_tree().quit(0)


# --- assert helpers ----------------------------------------------------------

func _assert_eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _assert_true(cond: bool, name: String) -> void:
	_assert_eq(cond, true, name)


## ADR-0067: the VM pushes the {32} tint as color_layer_* uniforms (unit.gdshader
## folds them via color_apply). Read the affine scale back out of the pushed layer
## arrays (the affine layer is the one with div 0 in rgb1.w).
func _affine_scale(mat) -> Vector3:
	var rgb0 = mat.params.get("color_layer_rgb0")
	var rgb1 = mat.params.get("color_layer_rgb1")
	var count: int = mat.params.get("color_layer_count", 0)
	for i in range(count):
		if rgb1[i].w == 0.0:
			return Vector3(rgb0[i].x, rgb0[i].y, rgb0[i].z)
	return Vector3.ONE


## Fold the material's pushed color_layer_* uniforms over `base` for surface 0 —
## the CPU mirror of color_apply, reading the RAW uniforms the shader sees (not a
## ColorStack's internal layers). Used to assert the reset invariant behaviourally
## ("the tint is truly cleared") instead of via _affine_scale's identity-default,
## which passes trivially when NO affine layer is present (review finding #8 tautology).
func _fold_material(mat, base: Vector3) -> Vector3:
	var rgb0 = mat.params.get("color_layer_rgb0")
	var rgb1 = mat.params.get("color_layer_rgb1")
	var meta = mat.params.get("color_layer_meta")
	var count: int = mat.params.get("color_layer_count", 0)
	var quant: bool = mat.params.get("quantize", false)
	if rgb0 == null or count == 0:
		return base
	var c := base
	for i in range(count):
		if (meta[i] & 0x1) == 0:  # this layer does not touch surface 0
			continue
		var progress: float = rgb0[i].w
		var recipe_out: Vector3
		if rgb1[i].w == 0.0:  # affine: c*scale + bias
			recipe_out = Vector3(c.x * rgb0[i].x, c.y * rgb0[i].y, c.z * rgb0[i].z) \
				+ Vector3(rgb1[i].x, rgb1[i].y, rgb1[i].z)
		else:  # luma
			var from_base: bool = (int(meta[i]) & (1 << 3)) != 0
			var src := base if from_base else c.clamp(Vector3.ZERO, Vector3.ONE)
			var s5 := Vector3i((src.clamp(Vector3.ZERO, Vector3.ONE) * 31.0).round())
			var lo: Vector3i = Recipe.luma_out5(s5, int(rgb1[i].w),
				Vector3i(roundi(rgb0[i].x), roundi(rgb0[i].y), roundi(rgb0[i].z)))
			recipe_out = Vector3(lo) / 31.0
		c = c.lerp(recipe_out, progress)
	if quant:
		c = (c.clamp(Vector3.ZERO, Vector3.ONE) * 31.0).round() / 31.0
	return c


# --- BGR555 <-> normalized helpers -------------------------------------------

static func _decode(word: int) -> Vector3:
	return Vector3(word & 0x1F, (word >> 5) & 0x1F, (word >> 10) & 0x1F)

## Apply a tint's affine map to a 5-bit base triple, floor to 5-bit (matching
## the PSX integer engine), and return (R,G,B) as ints.
static func _apply_5bit(base5: Vector3, scale: Vector3, bias: Vector3) -> Vector3i:
	return Vector3i(
		clampi(int(floor(base5.x * scale.x + bias.x * 31.0)), 0, 31),
		clampi(int(floor(base5.y * scale.y + bias.y * 31.0)), 0, 31),
		clampi(int(floor(base5.z * scale.z + bias.z * 31.0)), 0, 31))


# --- pure-model tests --------------------------------------------------------

func _test_ramp_frames_for_time() -> void:
	_assert_eq(Tint.ramp_frames_for_time(0), 0, "time0 -> snap (0 frames)")
	_assert_eq(Tint.ramp_frames_for_time(1), 8, "time1 -> fast 8 frames")
	_assert_eq(Tint.ramp_frames_for_time(2), 8, "time2 -> fast 8 frames")
	_assert_eq(Tint.ramp_frames_for_time(3), 8, "time3 -> fast 8 frames")
	_assert_eq(Tint.ramp_frames_for_time(4), 32, "time4 -> slow 32 frames")
	_assert_eq(Tint.ramp_frames_for_time(8), 64, "time8 -> slow 64 frames")


func _test_mode1_snap_halves_golden() -> void:
	# Color=1 Time=0: every CLUT entry becomes (current >> 1). The uniform
	# scale=0.5 must reproduce the byte-exact halved palette from the capture.
	var t = Tint.new()
	t.apply(1, 0, 0, 0, 0)
	_assert_true(t.scale.is_equal_approx(Vector3.ONE * 0.5), "mode1 scale = 0.5")
	_assert_true(t.bias.is_equal_approx(Vector3.ZERO), "mode1 bias = 0")
	var all_ok := true
	for i in range(GOLDEN_BASE.size()):
		var base5 := _decode(GOLDEN_BASE[i])
		var want := _decode(GOLDEN_HALVED[i])
		var got := _apply_5bit(base5, t.scale, t.bias)
		if got != Vector3i(int(want.x), int(want.y), int(want.z)):
			all_ok = false
			print("    entry %d: base=%04X got=%s want=%04X" %
				[i + 1, GOLDEN_BASE[i], str(got), GOLDEN_HALVED[i]])
	_assert_true(all_ok, "mode1 halve reproduces golden CLUT byte-exact")


func _test_mode8_restores_to_base() -> void:
	# Start from the halved state, then Color=8 Time=2 ramps back to base.
	var t = Tint.new()
	t.apply(1, 0, 0, 0, 0)        # snap to half
	t.apply(8, 0, 0, 0, 2)        # ramp to absolute base over the fast table
	# Run the whole ramp.
	var frames := 0
	while t.tick():
		frames += 1
		if frames > 64:
			break
	_assert_eq(frames, 8, "mode8/time2 ramp runs 8 frames")
	_assert_true(t.scale.is_equal_approx(Vector3.ONE), "mode8 end scale = 1 (base)")
	_assert_true(t.bias.is_equal_approx(Vector3.ZERO), "mode8 end bias = 0")
	# Final palette == base, byte-exact.
	var all_ok := true
	for i in range(GOLDEN_BASE.size()):
		var base5 := _decode(GOLDEN_BASE[i])
		var got := _apply_5bit(base5, t.scale, t.bias)
		if got != Vector3i(int(base5.x), int(base5.y), int(base5.z)):
			all_ok = false
	_assert_true(all_ok, "mode8 ramp lands exactly on base palette")


func _test_time0_snaps_no_ramp() -> void:
	var t = Tint.new()
	var still_ramping := t.tick()   # nothing armed
	_assert_true(not still_ramping, "idle tick() returns false")
	t.apply(1, 0, 0, 0, 0)
	_assert_true(not t.tick(), "time0 apply arms no ramp")


func _test_fast_ramp_is_eight_frames() -> void:
	# Monotone brighten: half -> base should be non-decreasing each frame and
	# strictly reach base only on the last frame.
	var t = Tint.new()
	t.apply(1, 0, 0, 0, 0)
	t.apply(8, 0, 0, 0, 2)
	var prev: float = t.scale.x
	var frames := 0
	var monotone := true
	while t.tick():
		frames += 1
		var cur: float = t.scale.x
		if cur < prev - 0.0001:
			monotone = false
		prev = cur
	_assert_true(monotone, "mode8 restore ramp is monotone non-decreasing")
	_assert_eq(frames, 8, "fast ramp completes in 8 frames")


func _test_luma_mode_flagged() -> void:
	var t = Tint.new()
	var luma := t.apply(2, 0, 0, 0, 0)   # mode 2 = luma/6
	_assert_true(luma, "luma mode 2 returns unsupported flag")
	var not_luma := t.apply(1, 0, 0, 0, 0)
	_assert_true(not not_luma, "mode 1 is supported (no luma flag)")


# --- VM integration tests ----------------------------------------------------

class FakeMaterial extends RefCounted:
	var params: Dictionary = {}
	func set_shader_parameter(name: String, value) -> void:
		params[name] = value

class FakeUnit extends RefCounted:
	var material := FakeMaterial.new()
	var visible: bool = true


func _make_vm() -> ScenarioVMClass:
	var vm := ScenarioVMClass.new()
	add_child(vm)
	_vms.append(vm)
	return vm


func _color_unit_inst(units: int, mode: int, r: int, g: int, b: int, time: int) -> Dictionary:
	return {
		"name": "Color Unit", "opcode": 0x32, "offset": 0,
		"params": [
			{"name": "Units", "value": units},
			{"name": "Multi", "value": 0},
			{"name": "Color", "value": mode},
			{"name": "Red", "value": r},
			{"name": "Green", "value": g},
			{"name": "Blue", "value": b},
			{"name": "Time", "value": time},
		],
	}


func _test_handler_registered_and_applies() -> void:
	var vm := _make_vm()
	_assert_true(vm._handlers.has(EventInstruction.COLOR_UNIT), "Color Unit handler registered")
	var unit := FakeUnit.new()
	vm.units_by_id[23] = unit
	# Exit A first op: Color=1 Time=0 (snap to half).
	vm._op_color_unit(_color_unit_inst(23, 1, 0, 0, 0, 0))
	_assert_true(unit.material.params.has("color_layer_rgb0"), "shader got color-stack uniforms")
	var sc: Vector3 = _affine_scale(unit.material)
	_assert_true(sc.is_equal_approx(Vector3.ONE * 0.5), "door-fade snap pushes scale=0.5")


func _test_reset_palette_clears_tint() -> void:
	var vm := _make_vm()
	var unit := FakeUnit.new()
	vm.units_by_id[23] = unit
	vm._op_color_unit(_color_unit_inst(23, 1, 0, 0, 0, 0))
	var armed := vm.peek_actor(23)
	_assert_true(armed != null and armed.tint != null, "tint tracked after Color Unit")
	# Sample base that the mode-1 halve visibly changes — proves a tint is ACTIVE
	# before the reset, so the post-reset identity check below can't be a tautology.
	var probe := Vector3(20.0, 16.0, 12.0) / 31.0
	_assert_true(not _fold_material(unit.material, probe).is_equal_approx(probe),
		"mode-1 tint folds the probe away from base (tint active pre-reset)")
	# Reset Palette clears it and restores shader identity. Sub-state clear: the
	# tint field is nulled but the actor entry survives (only forget erases it).
	vm._op_reset_palette({
		"name": "Reset Palette", "opcode": 0x97, "offset": 0,
		"params": [{"name": "Unit", "value": 23}],
	})
	var after := vm.peek_actor(23)
	_assert_true(after == null or after.tint == null, "tint dropped after Reset Palette")
	# Behavioural invariant: the material now folds the probe back to itself (identity).
	# This FAILS if the reset left any stray layer (affine scale!=1, bias!=0, or a luma),
	# unlike _affine_scale which returns identity by default when no affine is present.
	_assert_true(_fold_material(unit.material, probe).is_equal_approx(probe),
		"Reset Palette folds to identity (probe unchanged)")
	_assert_true(_affine_scale(unit.material).is_equal_approx(Vector3.ONE),
		"Reset Palette restores scale=1")
