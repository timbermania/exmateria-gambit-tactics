extends SceneTree
## Guard (fork/Forward+): the engine refreshes a compositor_layer's per-frame "did this layer draw?"
## signal, so a held-out target does NOT go stale when its layer drops to zero members. Replaces the
## retired FoldKeepaliveTest, which guarded the game-side KEEPALIVE workaround for this same defect;
## with the engine fix (get_compositor_layer_texture(id) const returns RID() on a zero-member frame)
## the keepalive is gone and this asserts the real behavior instead of the crutch.
##
## The game analog of the engine minimal repro: a gray seed + ONE real compositor_layer carrier driven
## by the PRODUCTION FoldSurface (SEED_SOURCE_TEXTURE Pass A/C). A readback effect appended after Pass C
## logs get_layer_texture(Fold.FOLD_LAYER) validity + center texel every frame.
##
## Timeline: carrier VISIBLE, then HIDDEN (sole member -> 0). This is the tile-cursor-hides moment.
##   BUG (pre-fix / keepalive as crutch): after hide, valid=1 with the frozen last texel  -> STALE.
##   FIXED engine:                        after hide, valid=0 (empty RID)                  -> REVERTS.
##
## Run (windowed, Forward+, fork engine):
##   BIN=~/Repos/godot-compositor-consume-material/bin/godot.linuxbsd.editor.dev.x86_64
##   # from the package root
##   WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
##     "$BIN" --path . --rendering-method forward_plus -s res://tools/probe_fold_stale_revert.gd

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const CARRIER_ADD := "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_add, compositor_layer;\nvoid fragment() { ALBEDO = vec3(0.30); ALPHA = 1.0; }\n"

var _cam: Camera3D
var _carrier: MeshInstance3D
var _f := 0
var _hidden := false
var _readback_installed := false
var _saw_stale_after_hide := false
var _saw_valid_before_hide := false
var _samples_after_hide := 0


# Reads the engine-owned layer target on the render thread each POST_TRANSPARENT (appended AFTER Pass C).
class Readback:
	extends CompositorEffect
	var log_line := ""
	var last_valid := -1
	var last_texel := ""
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
		render_layers = [Fold.FOLD_LAYER]
	func _render_callback(cb: int, rd_data: RenderData) -> void:
		if cb != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
			return
		var rb := rd_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if rb == null:
			return
		var tex := get_layer_texture(Fold.FOLD_LAYER)
		if not tex.is_valid():
			last_valid = 0
			last_texel = "-"
			return
		var rd := RenderingServer.get_rendering_device()
		var size := rb.get_internal_size()
		var data := rd.texture_get_data(tex, 0)
		var w := int(size.x)
		var h := int(size.y)
		var off := (int(h * 0.5) * w + int(w * 0.5)) * 4
		last_valid = 1
		last_texel = "(%d,%d,%d,%d)" % [data[off], data[off + 1], data[off + 2], data[off + 3]]


var _readback: Readback


func _initialize() -> void:
	root.size = Vector2i(256, 240)
	root.content_scale_size = Vector2i(256, 240)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 2.0
	_cam.position = Vector3(0, 0, 5)
	_cam.environment = env
	_cam.current = true   # CompositorAutopilot attaches the PRODUCTION FoldSurface (keepalive now gone)
	root.add_child(_cam)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_carrier = MeshInstance3D.new()
	_carrier.mesh = quad
	_carrier.custom_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CARRIER_ADD
	mat.shader = sh
	root.add_child(_carrier)
	Fold.add(_carrier, mat, 0.0, 0)

	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[revert] setup done (carrier visible; production FoldSurface, keepalive removed)")


func _on_post_draw() -> void:
	_f += 1
	# Append the readback after the autopilot installs Pass A/C, so it runs after Pass C in POST_TRANSPARENT.
	if not _readback_installed and _cam.compositor != null:
		_readback = Readback.new()
		var effs := _cam.compositor.compositor_effects
		effs.append(_readback)
		_cam.compositor.compositor_effects = effs
		_readback_installed = true
		return
	if _readback == null:
		return
	var phase := "HIDDEN" if _hidden else "visible"
	print("[revert] f=%d %s valid=%d texel=%s" % [_f, phase, _readback.last_valid, _readback.last_texel])
	if not _hidden and _readback.last_valid == 1:
		_saw_valid_before_hide = true
	if _hidden:
		_samples_after_hide += 1
		if _readback.last_valid == 1:
			_saw_stale_after_hide = true
	if _f == 12 and not _hidden:
		_carrier.visible = false
		_hidden = true
		print("[revert] --- hid carrier (sole member -> 0) ---")
	if _samples_after_hide >= 6:
		var ok := _saw_valid_before_hide and not _saw_stale_after_hide
		print("[revert] VERDICT: %s (valid-while-present=%s, stale-after-hide=%s)" % [
			"PASS (target reverts to empty RID when member count hits 0)" if ok else "FAIL",
			_saw_valid_before_hide, _saw_stale_after_hide])
		quit()


func _process(_dt: float) -> bool:
	return false
