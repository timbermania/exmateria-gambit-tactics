extends Node
# test-kind: gpu
# seeded-break: in foldsurface_resolve.glsl put back the coverage gate — `if (abs(s.a - 0.5) <= 0.1) { discard; }` before the write — and reimport. Both "no pixel is discarded" arms red (their destinations read back the out-of-range sentinel) while the two quantize arms stay green, because those feed alpha 1.0. A second, independent seed: change `floor(c * levels + 0.5)` to `floor(c * levels)` — all four lattice assertions red on the value (0.19941 against the wanted 0.22927) while the two quantize arms stay green, because those ask only whether the value MOVED and a truncation moves it too.
## Goal #8 guard (ADR-0152): the fold's framebuffer quantization is a POLICY the bracket
## is given, not a constant welded into its GLSL — and (ADR-0309) it is applied to EVERY
## PIXEL, because the PlayStation's framebuffer was 15-bit for the whole screen.
##
## `quantize5()` used to hardcode `31.0` — the PSX RGB555 framebuffer. That is a PSX
## *compromise*, and goal #8 says a compromise is divorced: named, switchable, and its
## removal recorded as a known drop. This runs `foldsurface_resolve.glsl` on a LOCAL
## RenderingDevice with known input and proves the switch is real rather than declared:
##
##   * NO PIXEL IS DISCARDED — including the two the retired coverage gate used to throw
##     away (alpha sitting exactly on the old 0.5 baseline). The destination is pre-filled
##     with an out-of-range sentinel and the draw list does not clear, so "was not written"
##     is observable rather than inferred;
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

## What the destination texture holds BEFORE the draw. Above 1.0, so it cannot be confused with
## anything the pass writes (`srgb_to_lin` of a clamped value never exceeds 1.0) — a pixel still
## reading this was NOT WRITTEN. The draw list does not clear, so it survives into the readback.
const DST_SENTINEL := 2.0

## The alpha the retired coverage gate read as "nothing drew here" (foldsurface_seed.glsl used to
## seed it). Kept as a named value because it is what the no-discard arms have to feed to mean
## anything: a pixel at any OTHER alpha was resolved by the old shader too.
const RETIRED_COVERAGE_BASELINE := 0.5

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

	_test_no_pixel_is_discarded()
	_finish()


## ADR-0309 — the resolve has NO coverage mark, so every pixel is written.
##
## The two pixels this arm cares about are the ones the retired gate threw away: alpha sitting
## exactly on the old 0.5 baseline. One of them is the bug that killed the mark — {76} Dark
## Screen's `blend_mix ALPHA = 0.5` over a unit's `blend_sub` ground shadow mapped the coverage
## alpha back ONTO the baseline (0.5 + 0*(1 - 0.5) = 0.5), so both contributions were discarded
## and the shadow's footprint came back as the raw undrawn scene, BRIGHTER than the dim around it.
## The other is a genuinely untouched background pixel, which the old shader was RIGHT to discard
## under its own contract and which this one resolves on purpose.
##
## Asserted at levels = 31, so a written pixel proves the 5-bit crush reached it and not merely
## that something was written: the input is off-lattice and the readback must be ON it.
func _test_no_pixel_is_discarded() -> void:
	var off_lattice := 0.5                      # 0.5 * 31 = 15.5 -> snaps to 16/31
	var snapped := 16.0 / 31.0
	var px := PackedFloat32Array([
		off_lattice, off_lattice, off_lattice, RETIRED_COVERAGE_BASELINE,   # the collision / untouched case
		off_lattice, off_lattice, off_lattice, 0.0,                          # a sub carrier drove alpha to 0
		off_lattice, off_lattice, off_lattice, RETIRED_COVERAGE_BASELINE,   # the same, a second time
		off_lattice, off_lattice, off_lattice, 1.0,                          # the ordinary case
	])
	var out := _run_resolve(px, 31.0)
	if out.is_empty():
		return
	var want := srgb_to_lin_scalar(snapped)
	for i in W:
		var got: float = out[i * 4]
		_assert_true(absf(got - want) < 0.002,
			("pixel %d (alpha %.2f) is RESOLVED, not discarded, and lands on the 5-bit "
			+ "lattice — want %.5f, got %.5f") % [i, px[i * 4 + 3], want, got])
		_assert_true(absf(got - DST_SENTINEL) > 0.5,
			"pixel %d does not read back the untouched-destination sentinel" % i)


## The shader's own transfer function, so the expected value is derived and not a magic number.
static func srgb_to_lin_scalar(c: float) -> float:
	c = clampf(c, 0.0, 1.0)
	return c / 12.92 if c < 0.04045 else pow((c + 0.055) / 1.055, 2.4)


## Run the resolve fragment over a 1-row RGBAF texture of `greys` and return the red
## channel it wrote, one entry per input. Alpha 1.0 throughout, so these arms are about
## quantization and never about which pixels get written.
func _resolve_once(greys: Array, levels: float) -> Array:
	var px := PackedFloat32Array()
	for i in W:
		var g: float = greys[i] if i < greys.size() else 0.0
		px.append_array([g, g, g, 1.0])
	var out := _run_resolve(px, levels)
	if out.is_empty():
		return []
	var reds := []
	for i in greys.size():
		reds.append(out[i * 4])
	return reds


## One draw of the resolve fragment over a W-wide RGBAF row, returning the full RGBA readback.
## The destination is pre-filled with [constant DST_SENTINEL] and the draw list does NOT clear,
## so a pixel the shader skipped reads back as the sentinel and a written one cannot.
func _run_resolve(px: PackedFloat32Array, levels: float) -> PackedFloat32Array:
	var shader := _make_shader()
	if not shader.is_valid():
		return PackedFloat32Array()

	var fill := PackedFloat32Array()
	for i in W:
		fill.append_array([DST_SENTINEL, DST_SENTINEL, DST_SENTINEL, DST_SENTINEL])

	var src := _texture(px.to_byte_array(), true)
	var dst := _texture(fill.to_byte_array(), false)
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
	for rid in [pipeline, sampler, src, dst, shader]:
		_rd.free_rid(rid)
	return out


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
