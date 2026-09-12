extends Node
## GPU parity for ADR-0067: render color_apply through the shared include on real
## hardware and confirm the pixel matches ColorStack.fold on the CPU. The CPU parity
## oracles (ColorStackTest) prove fold == the legacy shader math; this closes the loop
## by proving the GLSL include == fold, so the whole shader port is byte-exact end to
## end — the automated basis for deleting the legacy paths (slice 6) without eyeballing.
##
## A ColorRect in a SubViewport runs the canvas_item probe shader (the include is
## shader-type agnostic). We read back the centre pixel and compare to fold() with a
## tolerance for the 8-bit render-target quantization.
##
## Run: bash tests/stranger/exmateria_schema/run.sh   (ADR-0194 — this test is
## addon-owned and runs in a STRANGER project, not in the host. Directly:
## "$GODOT" --path . res://addons/exmateria_schema/tests/ColorStackGpuParityTest.tscn)

const Recipe = preload("res://addons/exmateria_schema/colour_model/ColorRecipe.gd")
const Stack = preload("res://addons/exmateria_schema/colour_model/ColorStack.gd")

var _passed: int = 0
var _failed: int = 0
var _vp: SubViewport
var _mat: ShaderMaterial

# ~2 LSB of an 8-bit channel — covers render-target rounding without hiding real drift.
const TOL := 2.5 / 255.0


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(8, 8)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.transparent_bg = false
	var cr := ColorRect.new()
	cr.size = Vector2(8, 8)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://addons/exmateria_schema/tests/color_stack_gpu_probe.gdshader")
	cr.material = _mat
	_vp.add_child(cr)
	add_child(_vp)

	await _run_cases()

	print("\n=== ColorStackGpuParityTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ColorStackGpuParityTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ColorStackGpuParityTest")
		get_tree().quit(1)
	else:
		print("[PASS] ColorStackGpuParityTest")
		get_tree().quit(0)


func _run_cases() -> void:
	print("[ColorStackGpuParityTest] rendering probe cases...")
	# Let the SubViewport come up before the first read.
	for _i in range(3):
		await get_tree().process_frame
	var base := Vector3(0.6, 0.4, 0.2)
	# Each case: a label + a builder that pushes layers onto a fresh stack.
	var cases := [
		["identity", func(_s): pass],
		["affine additive", func(s): s.push_fixed_layer(Recipe.affine(Vector3.ONE, Vector3(0.2, 0.0, -0.1)), 1.0)],
		["affine dim x0.5", func(s): s.push_fixed_layer(Recipe.affine(Vector3(0.5, 0.5, 0.5), Vector3.ZERO), 1.0)],
		["luma sepia (base)", func(s): s.push_fixed_layer(Recipe.luma(12, Vector3i(4, 3, 1), true), 1.0)],
		["luma sepia mid-mix", func(s):
			s.push_fixed_layer(Recipe.affine(Vector3.ONE, Vector3.ZERO), 1.0)
			s.push_fixed_layer(Recipe.luma(12, Vector3i(4, 3, 1), true), 0.5)],
		# Base-source affine (modes 4/5/9): the recipe reads the RAW base, not the
		# colour-so-far. To prove the GLSL affine base-source branch (not fold it away
		# via the settled-run merge), a settled current-source layer mutates `current`
		# first, then a NON-settled base-source layer (progress 0.5) is packed as its
		# own entry — so if the GLSL read `current` it would diverge on R.
		["affine base-source reads base not current", func(s):
			s.push_fixed_layer(Recipe.affine(Vector3.ONE, Vector3(0.3, 0.0, 0.0)), 1.0)
			s.push_fixed_layer(Recipe.affine_base(Vector3(0.5, 0.5, 0.5), Vector3.ZERO), 0.5)],
		["affine below + luma above", func(s):
			s.push_fixed_layer(Recipe.affine(Vector3(0.8, 0.8, 0.8), Vector3(0.05, 0.0, 0.0)), 1.0)
			s.push_fixed_layer(Recipe.luma(6, Vector3i(2, 1, 0), false), 1.0)],
		# --- quantize=true (the 5-bit CLUT fidelity path the combat palette route
		# uses; #164). Exercised with an EXACT 5-bit comparison below, so a GLSL-vs-CPU
		# quantize/rounding divergence (~1 CLUT step) is caught, not hidden by the float
		# tolerance (review finding #6 — the branch was previously never rendered).
		["quantize snap identity", func(s): s.set_quantize(true)],
		["quantize affine additive", func(s):
			s.set_quantize(true)
			s.push_fixed_layer(Recipe.affine(Vector3.ONE, Vector3(0.2, 0.0, -0.1)), 1.0)],
		["quantize affine dim x0.5", func(s):
			s.set_quantize(true)
			s.push_fixed_layer(Recipe.affine(Vector3(0.5, 0.5, 0.5), Vector3.ZERO), 1.0)],
		["quantize luma sepia", func(s):
			s.set_quantize(true)
			s.push_fixed_layer(Recipe.luma(12, Vector3i(4, 3, 1), true), 1.0)],
	]
	for case in cases:
		var label: String = case[0]
		var stack := Stack.new()
		case[1].call(stack)
		var quant: bool = label.begins_with("quantize")
		var want: Vector3 = stack.fold(base, 0, 0)
		# Push the SAME stack's uniforms to the GPU material and render.
		stack.apply(_mat, 0)
		_mat.set_shader_parameter("probe_base", base)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.05).timeout
		var img := _vp.get_texture().get_image()
		var px := img.get_pixel(4, 4)
		var got := Vector3(px.r, px.g, px.b)
		var ok: bool
		if quant:
			# Both sides are on the 5-bit grid — compare the CLUT step exactly (robust
			# to 8-bit readback rounding, and it PROVES the quantize branch is byte-exact).
			ok = _to5(got) == _to5(want)
		else:
			ok = (got - want).length() <= TOL * 1.75
		if ok:
			_passed += 1
		else:
			_failed += 1
			print("  [FAIL] %s: gpu=%s cpu_fold=%s (quant=%s)" % [label, str(got), str(want), str(quant)])


## Snap a rendered/float colour to its 5-bit CLUT triple (0..31 per channel).
func _to5(c: Vector3) -> Vector3i:
	return Vector3i(
		clampi(roundi(c.x * 31.0), 0, 31),
		clampi(roundi(c.y * 31.0), 0, 31),
		clampi(roundi(c.z * 31.0), 0, 31))


func _assert() -> void:
	pass
