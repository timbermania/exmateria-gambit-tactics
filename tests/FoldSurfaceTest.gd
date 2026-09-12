extends Node
## The fold bracket as a SPEC: what each of FoldSurface's two passes is, stated as data.
##
## Pass A and Pass C used to be two ~90-line CompositorEffect classes that were byte-identical
## apart from five values. They now share one `FullscreenPass` implementation and each adapter
## supplies only its five: stage, shader, source, destination, quantization. This test asserts
## those five, because after the collapse they ARE the passes — everything else is shared code
## that a wrong adapter would run correctly against the wrong inputs.
##
## Coverage this closes: before it, `setup()` had no test at all, `foldsurface_seed.glsl` had no
## test at all (ShaderCompileTest now compiles it), and the only assertion anywhere near the
## bracket was FoldQuantizePolicyTest's — which runs the resolve GLSL on a local RenderingDevice
## but never touches the GDScript that decides what to feed it.
##
## Pure GDScript. No RenderingDevice, no scene, no GPU: a CompositorEffect is a Resource, so its
## spec is readable without ever entering a render callback. The pixels are FoldQuantizePolicyTest's
## job and the end-to-end seed->fold->resolve round trip is tools/probe_ticket15_roundtrip.gd's.
##
## Run: <GODOT> --path . res://tests/FoldSurfaceTest.tscn

## The fold bracket, aliased back to its bare spelling through the addon's one
## global name (ADR-0212 dec. 1, ADR-0211 dec. 4). `addons/exmateria_render`
## used to declare `class_name FoldSurface`; it now declares only
## `ExMateriaRender`, so this line is what keeps every use site below spelled
## the way it was.
const FoldSurface = ExMateriaRender.FoldSurface

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const Fold = ExMateriaSchema.Fold

const SEED_GLSL := "res://addons/exmateria_render/fold_bracket/foldsurface_seed.glsl"
const RESOLVE_GLSL := "res://addons/exmateria_render/fold_bracket/foldsurface_resolve.glsl"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var seed_pass := FoldSurface.SeedPass.new()
	var resolve_pass := FoldSurface.ResolvePass.new()

	# --- 1. the five values, Pass A (seed) -----------------------------------------------------
	_assert_true(seed_pass.effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE,
		"seed runs at POST_OPAQUE")
	_assert_true(seed_pass._shader_path() == SEED_GLSL, "seed runs foldsurface_seed.glsl")
	_assert_true(is_equal_approx(seed_pass._quantize_levels(), 0.0),
		"seed sends quantize 0.0 — the 5-bit crush is Pass C's, applied once")
	# The seed BINDS a layer texture (Fold.FOLD_LAYER.seed_texture) rather than CONSUMING a layer,
	# so it declares none. Declaring one here would make the engine hold the target out for it too.
	_assert_true(seed_pass.render_layers.is_empty(), "seed declares no consumed render layer")

	# --- 2. the five values, Pass C (resolve) --------------------------------------------------
	_assert_true(resolve_pass.effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT,
		"resolve runs at PRE_TRANSPARENT")
	_assert_true(resolve_pass._shader_path() == RESOLVE_GLSL, "resolve runs foldsurface_resolve.glsl")
	_assert_true(is_equal_approx(resolve_pass._quantize_levels(), FoldSurface.quantize_levels),
		"resolve sends FoldSurface.quantize_levels (read live, not baked at construction)")
	_assert_true(resolve_pass.render_layers == [Fold.FOLD_LAYER],
		"resolve declares Fold.FOLD_LAYER as the held-out layer it consumes")

	# `quantize_levels` is read every frame, not captured — a consumer setting it must take effect
	# without rebuilding the pass. (ADR-0152: it is a policy the bracket is GIVEN.)
	var restore := FoldSurface.quantize_levels
	FoldSurface.quantize_levels = 7.0
	_assert_true(is_equal_approx(resolve_pass._quantize_levels(), 7.0),
		"resolve re-reads quantize_levels live (a set takes effect without a rebuild)")
	FoldSurface.quantize_levels = restore

	# --- 3. the bracket ORDER — the whole reason there are two passes ---------------------------
	# Pass A seeds, the engine's held-out Pass B folds the carriers over the seed, Pass C resolves.
	# If the stages ever inverted, the resolve would read a target the seed had not authored yet.
	_assert_true(seed_pass.effect_callback_type < resolve_pass.effect_callback_type,
		"seed's stage precedes resolve's, so Pass B lands between them")

	# --- 4. the shaders the spec names actually exist -------------------------------------------
	# A typo in either path fails only at runtime today, silently: `_setup()` load()s null, the
	# shader RID stays invalid, and the render callback returns early forever — the fold just
	# stops, with no error.
	_assert_true(FileAccess.file_exists(SEED_GLSL), "%s exists" % SEED_GLSL)
	_assert_true(FileAccess.file_exists(RESOLVE_GLSL), "%s exists" % RESOLVE_GLSL)

	# --- 5. the push constant — the shared wire format ------------------------------------------
	# Exactly 16 bytes; the shaders declare Params as vec2 size + vec2, and slot 3 is where
	# ADR-0152 put the quantization policy that used to be welded into the GLSL as a literal 31.0.
	var pc := FoldSurface.FullscreenPass.push_constant(Vector2i(320, 224), 31.0)
	_assert_true(pc.size() == 16, "push constant is exactly 16 bytes (got %d)" % pc.size())
	var words := pc.to_float32_array()
	_assert_true(words.size() == 4 and is_equal_approx(words[0], 320.0) and is_equal_approx(words[1], 224.0),
		"push constant slots 0,1 are the render size")
	_assert_true(is_equal_approx(words[2], 31.0), "push constant slot 2 is the quantization policy")
	_assert_true(is_equal_approx(words[3], 0.0), "push constant slot 3 is the remaining pad word")

	# --- 6. setup() — the addon's published interface, previously untested ----------------------
	var cam := Camera3D.new()
	var fs := FoldSurface.new()
	fs.setup(cam)
	_assert_true(cam.compositor != null, "setup(cam) installs a Compositor on the camera")
	if cam.compositor != null:
		var fx := cam.compositor.compositor_effects
		_assert_true(fx.size() == 2, "setup installs exactly the two bracket passes (got %d)" % fx.size())
		if fx.size() == 2:
			# Order matters to the engine: it walks compositor_effects in order within a stage, and
			# the seed must be installed as the earlier effect as well as the earlier stage.
			_assert_true(fx[0] is FoldSurface.SeedPass, "the first installed effect is the seed pass")
			_assert_true(fx[1] is FoldSurface.ResolvePass, "the second installed effect is the resolve pass")
	cam.free()

	# A null camera is a documented no-op with a warning, not a crash — CompositorAutopilot calls
	# setup() before a camera exists in some boot orders. It must also not construct the passes:
	# a SeedPass built with nowhere to install would allocate a seed texture and bind it onto the
	# shared Fold.FOLD_LAYER that a REAL FoldSurface is using.
	var fs_null := FoldSurface.new()
	fs_null.setup(null)
	_assert_true(fs_null.get("_seed") == null and fs_null.get("_resolve") == null,
		"setup(null) is a no-op — no passes constructed, nothing bound onto Fold.FOLD_LAYER")

	_finish()


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	print("\n=== FoldSurfaceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FoldSurfaceTest")
		get_tree().quit(1)
	else:
		print("[PASS] FoldSurfaceTest")
		get_tree().quit(0)
