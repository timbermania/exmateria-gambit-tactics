extends SceneTree
## THROWAWAY — wayfinder ticket 15 round-trip proof. Delete after verifying.
##
## Decisively isolates the game-side seed→fold→resolve wiring the ticket adds, WITHOUT the effect/pool
## system: a known GRAY opaque scene + one minimal `compositor_layer` carrier covering the screen RIGHT
## half, driven by the PRODUCTION FoldSurface (Pass A authors the gray seed into the layer's
## seed_texture; the engine copies it into the held-out target and folds the carrier over it; Pass C
## resolves the target back into color). Then reads the root viewport and compares LEFT (seed only) vs
## RIGHT (seed + carrier):
##   add:  RIGHT must be BRIGHTER than LEFT  → carrier folded + resolved into the final frame.
##   sub:  RIGHT must be DARKER than LEFT but > 0 → the carrier subtracted from a REAL seed (a CLEAR/
##         black seed would leave RIGHT ~0; a mid-gray RIGHT proves Pass A's TEXTURE seed reached the pass).
##
## Run (windowed, Forward+, fork engine):
##   BIN=~/Repos/godot-compositor-consume-material/bin/godot.linuxbsd.editor.dev.x86_64
##   # from the package root
##   WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
##     "$BIN" --path . --rendering-method forward_plus -s res://tools/probe_ticket15_roundtrip.gd -- add
##   ... -- sub

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const CARRIER_ADD := "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_add, compositor_layer;\nvoid fragment() { ALBEDO = vec3(0.30); ALPHA = 1.0; }\n"
const CARRIER_SUB := "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_sub, compositor_layer;\nvoid fragment() { ALBEDO = vec3(0.30); ALPHA = 1.0; }\n"
const CARRIER_MIX := "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, compositor_layer;\nvoid fragment() { ALBEDO = vec3(0.30); ALPHA = 0.5; }\n"

var _mode := "add"
var _fs                # production FoldSurface (installs Pass A/C on the camera)
var _cam: Camera3D
var _f := 0
var _quit := false
var _done := false
var _readback_installed := false


# Diagnostic: reads the engine-owned layer TARGET (after the engine folded the carrier over the seed,
# before/independent of Pass C) and logs a right-region (carrier) RGBA texel, so we can see what the
# blend actually wrote to the coverage-alpha. Appended AFTER ResolvePass so it runs late in the frame.
class TargetReadback:
	extends CompositorEffect
	var reported := false
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
		render_layers = [Fold.FOLD_LAYER]
	func _render_callback(cb: int, rd_data: RenderData) -> void:
		if cb != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or reported:
			return
		var rb := rd_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if rb == null:
			return
		var tex := get_layer_texture(Fold.FOLD_LAYER)
		if not tex.is_valid():
			return
		var rd := RenderingServer.get_rendering_device()
		var size := rb.get_internal_size()
		var data := rd.texture_get_data(tex, 0)   # RGBA8, tightly packed
		var w := int(size.x)
		var h := int(size.y)
		var px := int(w * 0.72)
		var py := int(h * 0.5)
		var off := (py * w + px) * 4
		reported = true
		print("[t15] TARGET right texel @(%d,%d) RGBA8 = (%d,%d,%d,%d)" % [px, py,
			data[off], data[off + 1], data[off + 2], data[off + 3]])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = String(args[0])
	root.content_scale_size = Vector2i(256, 240)
	root.size = Vector2i(256, 240)

	# A known gray opaque scene = the seed Pass A will author.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0

	# Orthographic camera looking down -Z; a full-view quad split so the carrier covers the RIGHT half.
	# current=true so the CompositorAutopilot autoload attaches the PRODUCTION EngineFoldCompositor +
	# FoldSurface (the code under test) to it — the real path, not a hand-installed compositor.
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 2.0
	_cam.position = Vector3(0, 0, 5)
	_cam.environment = env
	_cam.current = true
	root.add_child(_cam)

	# One compositor_layer carrier over the right half (x in [0..1]), z just in front of the camera.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position = Vector3(0.5, 0.0, 0.0)   # right half in the ortho view (size=2 → x∈[-1,1])
	mi.custom_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CARRIER_MIX if _mode == "mix" else (CARRIER_SUB if _mode == "sub" else CARRIER_ADD)
	mat.shader = sh
	root.add_child(mi)
	Fold.add(mi, mat, 0.0, 0)               # stamps render_layer=FOLD_LAYER + int order key

	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[t15] round-trip probe mode=%s (gray seed 0.5, carrier right-half)" % _mode)


func _process(_dt: float) -> bool:
	if _quit:
		quit()
		return true
	return false


func _on_post_draw() -> void:
	_f += 1
	# Once the autopilot has installed the production compositor, append our target readback so it
	# runs after Pass C in the same POST_TRANSPARENT stage.
	if not _readback_installed and _cam != null and _cam.compositor != null:
		var effs := _cam.compositor.compositor_effects
		effs.append(TargetReadback.new())
		_cam.compositor.compositor_effects = effs
		_readback_installed = true
	if _f < 20 or _done:     # let the autopilot attach + the fold settle
		return
	_done = true
	var img := root.get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var y := h / 2
	# Sample a strip on each side, away from the seam.
	var left := _avg(img, int(w * 0.20), int(w * 0.35), y)
	var right := _avg(img, int(w * 0.65), int(w * 0.80), y)
	print("[t15] %s | left(seed)=%s right(carrier)=%s" % [_mode, _fmt(left), _fmt(right)])
	var lb := left.r + left.g + left.b
	var rb := right.r + right.g + right.b
	var verdict := "?"
	if _mode == "add":
		verdict = "PASS (right brighter → add folded + resolved)" if rb > lb + 0.02 else "FAIL (no additive contribution)"
	elif _mode == "mix":
		verdict = "PASS (right differs from seed → mix folded + resolved)" if abs(rb - lb) > 0.02 else "FAIL (no mix contribution)"
	else:
		# sub: right darker than the seed, but still clearly > 0 (proves the seed was real, not CLEAR/black)
		verdict = "PASS (right darker than seed AND >0 → subtracted from a REAL seed)" if (rb < lb - 0.02 and rb > 0.05) else "FAIL (coverage lost: sub drove alpha to 0 → resolve discarded it)"
	print("[t15] %s VERDICT: %s  (lum left=%.3f right=%.3f)" % [_mode, verdict, lb, rb])
	img.save_png("/tmp/t15_%s.png" % _mode)
	_quit = true


func _avg(img: Image, x0: int, x1: int, y: int) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for x in range(x0, x1):
		var c := img.get_pixel(x, y)
		r += c.r; g += c.g; b += c.b; n += 1
	return Color(r / n, g / n, b / n)


func _fmt(c: Color) -> String:
	return "(%.3f,%.3f,%.3f)" % [c.r, c.g, c.b]
