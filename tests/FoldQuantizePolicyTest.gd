extends Node
## Goal #8 guard (ADR-0152): the fold's framebuffer quantization is a POLICY the bracket
## is given, not a constant welded into its GLSL.
##
## `quantize5()` used to hardcode `31.0` — the PSX RGB555 framebuffer. That is a PSX
## *compromise*, and goal #8 says a compromise is divorced: named, switchable, and its
## removal recorded as a known drop. This runs `foldsurface_resolve.glsl` on a LOCAL
## RenderingDevice with known input and proves the switch is real rather than declared:
##
##   * an input value OFF the 5-bit lattice moves when levels = 31 and does not when
##     levels = 0 — the quantizer is running and the policy reaches it;
##   * an input value ON the lattice is unchanged by either — the quantizer is a
##     quantizer and not some other transform that happens to differ;
##   * the default `FoldSurface.quantize_levels` is 31.0 — `Render` IS the PlayStation
##     look (ADR-0117 dec. 6, ADR-0150) and a drop here is a regression, so the PSX
##     value stays the default and any other value is a deliberate known drop.
##
## The pass writes `srgb_to_lin(quantize(c, levels))`, so the assertions are about
## whether the value MOVED, never about an absolute number — sRGB is not the subject.
##
## TRAP, paid for once: an edited `.glsl` runs from the STALE SPIR-V in `.godot/imported/`
## until Godot reimports it. The first run of this test failed with both levels producing
## the 31.0 result, because the cached shader still hardcoded `31.0` — a green/red that is
## about the import cache and not about the code. `touch` the file and run one
## `godot --path . --editor --quit` after editing any `.glsl`.
##
## Run: <GODOT> --path . --quit-after 10 res://tests/FoldQuantizePolicyTest.tscn

## The fold bracket, aliased back to its bare spelling through the addon's one
## global name (ADR-0212 dec. 1, ADR-0211 dec. 4). `addons/exmateria_render`
## used to declare `class_name FoldSurface`; it now declares only
## `ExMateriaRender`, so this line is what keeps every use site below spelled
## the way it was.
const FoldSurface = ExMateriaRender.FoldSurface

const RESOLVE := "res://addons/exmateria_render/fold_bracket/foldsurface_resolve.glsl"
const W := 4
const H := 1

var _passed: int = 0
var _failed: int = 0
var _rd: RenderingDevice


func _ready() -> void:
	_assert_true(is_equal_approx(FoldSurface.quantize_levels, 31.0),
		"FoldSurface.quantize_levels defaults to 31.0 (PSX RGB555)")

	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		_fail("could not create a local RenderingDevice")
		return _finish()

	# Two probes: 0.5 is NOT on the 5-bit lattice (0.5 * 31 = 15.5, snaps to 16/31);
	# 16.0/31.0 IS on it and must survive quantization untouched.
	var off_lattice := 0.5
	var on_lattice := 16.0 / 31.0

	var at31 := _resolve_once([off_lattice, on_lattice], 31.0)
	var at0 := _resolve_once([off_lattice, on_lattice], 0.0)
	if at31.is_empty() or at0.is_empty():
		return _finish()

	_assert_true(absf(at31[0] - at0[0]) > 0.002,
		"an off-lattice value MOVES at levels=31 and not at levels=0 (Δ=%.5f)"
			% absf(at31[0] - at0[0]))
	_assert_true(absf(at31[1] - at0[1]) < 0.0005,
		"an on-lattice value is identical at both levels (Δ=%.6f)"
			% absf(at31[1] - at0[1]))
	_finish()


## Run the resolve fragment over a 1-row RGBAF texture of `greys` and return the red
## channel it wrote, one entry per input.
func _resolve_once(greys: Array, levels: float) -> Array:
	var shader := _make_shader()
	if not shader.is_valid():
		return []

	var px := PackedFloat32Array()
	for i in W:
		var g: float = greys[i] if i < greys.size() else 0.0
		# alpha 1.0 — off the 0.5 coverage baseline, so the resolve does NOT discard.
		px.append_array([g, g, g, 1.0])
	var src := _texture(px.to_byte_array(), true)
	var dst := _texture(PackedByteArray(), false)
	var fb := _rd.framebuffer_create([dst])

	var sampler := _rd.sampler_create(RDSamplerState.new())
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = 0
	u.add_id(sampler)
	u.add_id(src)
	var uset := _rd.uniform_set_create([u], shader, 0)

	var blend := RDPipelineColorBlendState.new()
	blend.attachments.append(RDPipelineColorBlendStateAttachment.new())
	var pipeline := _rd.render_pipeline_create(shader, _rd.framebuffer_get_format(fb),
		RenderingDevice.INVALID_FORMAT_ID, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		RDPipelineRasterizationState.new(), RDPipelineMultisampleState.new(),
		RDPipelineDepthStencilState.new(), blend)

	var pc := PackedFloat32Array([float(W), float(H), levels, 0.0]).to_byte_array()
	var dl := _rd.draw_list_begin(fb)
	_rd.draw_list_bind_render_pipeline(dl, pipeline)
	_rd.draw_list_bind_uniform_set(dl, uset, 0)
	_rd.draw_list_set_push_constant(dl, pc, pc.size())
	_rd.draw_list_draw(dl, false, 1, 3)
	_rd.draw_list_end()
	_rd.submit()
	_rd.sync()

	var out := _rd.texture_get_data(dst, 0).to_float32_array()
	var reds := []
	for i in greys.size():
		reds.append(out[i * 4])
	for rid in [pipeline, sampler, src, dst, shader]:
		_rd.free_rid(rid)
	return reds


func _make_shader() -> RID:
	var file := load(RESOLVE) as RDShaderFile
	if file == null:
		_fail("could not load %s as an RDShaderFile" % RESOLVE)
		return RID()
	var spirv := file.get_spirv()
	if spirv.compile_error_vertex != "" or spirv.compile_error_fragment != "":
		_fail("resolve shader failed to compile: %s %s"
			% [spirv.compile_error_vertex, spirv.compile_error_fragment])
		return RID()
	return _rd.shader_create_from_spirv(spirv)


func _texture(data: PackedByteArray, sampled: bool) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = W
	fmt.height = H
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	if sampled:
		fmt.usage_bits |= RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	else:
		fmt.usage_bits |= RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	var payload: Array[PackedByteArray] = []
	if not data.is_empty():
		payload.append(data)
	return _rd.texture_create(fmt, RDTextureView.new(), payload)


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % label)


func _finish() -> void:
	# Give the local RenderingDevice back BEFORE quitting. The RIDs above were freed but
	# the device never was, and a live local device at process exit is what makes this
	# test dump core after printing [PASS] — see #471. The other four scenes that create
	# their own device (PipelineTest, ShaderCompileBench, ShaderCompileTest,
	# StartupDiagnostic) already do this; this one was the exception.
	if _rd:
		_rd.free()
		_rd = null
	print("\n=== FoldQuantizePolicyTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FoldQuantizePolicyTest")
		get_tree().quit(1)
	else:
		print("[PASS] FoldQuantizePolicyTest")
		get_tree().quit(0)
