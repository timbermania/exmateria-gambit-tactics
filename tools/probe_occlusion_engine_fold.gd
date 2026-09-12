extends SceneTree
## Occlusion guard for the ENGINE Pass B fold (design engine-shaded-display-fold.md; occlusion resolved
## 2026-07-27). Proves the depth-test that hides folded effects behind opaque geometry.
##
## THE CLAIM UNDER TEST: a `compositor_fold` prim is occluded PER-FRAGMENT by the opaque scene depth.
## The engine fold pass binds the shared opaque scene depth (rb->get_depth_texture(), LOADed) and the
## fold pipeline tests DEPTH with GREATER_OR_EQUAL; the fold shader writes DEPTH = ot_computed_depth
## (reversed-Z NDC), the same space the opaque scene writes. So a fold prim BEHIND an opaque wall must
## be culled and leave the scratch UNTOUCHED there (α stays 0), while the unoccluded half is TOUCHED.
##
## SETUP (orthographic camera at +Z looking -Z):
##   • opaque red occluder covering screen-LEFT (world x < 0), NEARER the camera (z=+8),
##   • a full-screen `effect_callback_fold` (white, additive) prim FARTHER back (z=0),
##   • Pass A seeds the compositor scratch black/α=0; the engine folds; Pass C reads it back.
## ASSERT: left-half pixels UNTOUCHED (α==0, occluded), right-half pixels TOUCHED (α>0, visible).
## Exits 0 on PASS, 1 on FAIL — a real regression guard for the depth-occlusion mechanism.
##
## MUST run on the 4.8-dev engine, Forward+ (the fold is Forward+-only), NEVER headless:
##   BIN=~/Repos/godot-compositor-consume-material/bin/godot.linuxbsd.editor.dev.x86_64
##   # from the package root
##   "$BIN" --path . --rendering-method forward_plus -s res://tools/probe_occlusion_engine_fold.gd

## Preloaded `Shader` objects, not `String` paths — ADR-0191 dec. 11. A `load()` on a
## mistyped path returns null, a null shader does not raise, and the fold "just stops, with no
## error". That hazard is a property of naming a fold shader from GDScript, not of picking
## between two, so it reaches this block even though dec. 2's rule does not.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode

const FOLD_SHADER := preload("res://addons/exmateria_effects/callbacks/effect_callback_fold.gdshader")
const OUT_DIR := "/tmp/occlusion_engine_fold"

var _cam: Camera3D
var _readback: ReadbackPass
var _seed: CompositorEffect
var _f := 0
var _quit := false
var _exit_code := 0


# ---- Pass A: allocate + seed the compositor-owned `compositor_fold`/`color` scratch (black, α=0) ----
class SeedPass:
	extends CompositorEffect
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	func _render_callback(cb: int, rd_data: RenderData) -> void:
		if cb != EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT:
			return
		var rb := rd_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if rb == null:
			return
		var usage := (RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT)
		var tex := rb.create_texture(&"compositor_fold", &"color",
			RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32, usage,
			RenderingDevice.TEXTURE_SAMPLES_1, rb.get_internal_size(), rb.get_view_count(), 1, false, false)
		var rd := RenderingServer.get_rendering_device()
		rd.texture_clear(tex, Color(0, 0, 0, 0), 0, 1, 0, rb.get_view_count())


# ---- Pass C stand-in: read the folded scratch, assert the occlusion signature, on request ----
class ReadbackPass:
	extends CompositorEffect
	var armed := false
	var done := false
	var passed := false
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(cb: int, rd_data: RenderData) -> void:
		if cb != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not armed or done:
			return
		armed = false
		var rb := rd_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if rb == null or not rb.has_texture(&"compositor_fold", &"color"):
			_finish(false, "NO fold scratch")
			return
		var tex := rb.get_texture(&"compositor_fold", &"color")
		var rd := RenderingServer.get_rendering_device()
		var size := rb.get_internal_size()
		var w := int(size.x)
		var h := int(size.y)
		var data := rd.texture_get_data(tex, 0)
		# Save a PNG for eyeballing (touched pixels = white right half, black left half).
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var total_touched := 0
		for y in range(h):
			var row := y * w
			for x in range(w):
				var v := data.decode_u32((row + x) * 4)
				var r := float(v & 0x3FF) / 1023.0
				var g := float((v >> 10) & 0x3FF) / 1023.0
				var b := float((v >> 20) & 0x3FF) / 1023.0
				var a := float((v >> 30) & 0x3) / 3.0
				img.set_pixel(x, y, Color(r, g, b, a))
				if a > 0.0:
					total_touched += 1
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		img.save_png("%s/occlusion.png" % OUT_DIR)

		# Sample columns at 20% (behind the occluder → must be UNTOUCHED) and 80% (visible → TOUCHED),
		# across three rows to avoid a stray edge pixel deciding the verdict.
		var ys := [int(h * 0.35), int(h * 0.5), int(h * 0.65)]
		var left_touched := 0
		var right_touched := 0
		var samples := 0
		for y in ys:
			left_touched += _alpha_bits(data, w, int(w * 0.2), y)
			right_touched += _alpha_bits(data, w, int(w * 0.8), y)
			samples += 1
		# PASS: the occluded (left) samples are ALL untouched; the visible (right) samples are ALL touched.
		var ok := (left_touched == 0) and (right_touched == samples)
		_finish(ok, "left_touched=%d/%d (want 0) right_touched=%d/%d (want %d) total_touched=%d" % [
			left_touched, samples, right_touched, samples, samples, total_touched])
	func _alpha_bits(data: PackedByteArray, w: int, x: int, y: int) -> int:
		var v := data.decode_u32((y * w + x) * 4)
		return 1 if ((v >> 30) & 0x3) > 0 else 0
	func _finish(ok: bool, msg: String) -> void:
		passed = ok
		done = true
		var line := "[occlusion-fold] %s — %s" % ["PASS" if ok else "FAIL", msg]
		print(line)
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		var f := FileAccess.open("%s/probe.log" % OUT_DIR, FileAccess.WRITE)
		if f != null:
			f.store_line(line)
			f.close()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Raw display texels + identity PAR (globals the fold shader + pixel_aspect include read). psx_brightness
	# was deleted (ADR-0074 fold endgame — gain baked per-producer), so it is no longer set here.
	RenderingServer.global_shader_parameter_set("pixel_aspect", 1.0)

	# --- Orthographic camera at +Z looking down -Z (world +X = screen right). ---
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 8.0
	_cam.position = Vector3(0, 0, 10)
	root.add_child(_cam)
	_cam.make_current()

	# --- Opaque occluder covering screen-LEFT (world x in [-40, 0]), NEARER the camera (z=8). ---
	# Opaque → writes the shared scene depth in the opaque pass; the fold pass tests against it.
	var occ := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(40, 80)
	occ.mesh = qm
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.8, 0.1, 0.1)
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	occ.material_override = om
	occ.position = Vector3(-20, 0, 8)   # right edge at x=0 → covers all world x<0 = screen left half
	root.add_child(occ)

	# --- Full-screen `compositor_fold` prim FARTHER back (z=0): white, additive. ---
	var fold := MeshInstance3D.new()
	fold.mesh = _build_fold_quad()
	var fm := ShaderMaterial.new()
	fm.shader = FOLD_SHADER
	fm.set_shader_parameter("use_texture", false)
	fm.set_shader_parameter("use_psx_brightness", true)
	fold.material_override = fm
	fold.sorting_offset = 0.0
	fold.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	root.add_child(fold)

	# --- Compositor: Pass A seed + Pass C readback; the engine folds in between. ---
	# We own this camera's compositor directly (this probe reads the scratch back), so stand the
	# branch-wide CompositorAutopilot down for our camera — otherwise it re-attaches EngineFoldCompositor
	# and its SeedPass/ResolvePass over ours. The engine Pass B still folds our compositor_fold prim
	# (it's keyed on the render_mode flag, not on which compositor is attached).
	var autopilot := root.get_node_or_null("CompositorAutopilot")
	if autopilot != null:
		autopilot.set_process(false)
	_seed = SeedPass.new()
	_readback = ReadbackPass.new()
	var comp := Compositor.new()
	comp.compositor_effects = [_seed, _readback]
	_cam.compositor = comp
	print("[occlusion-fold] booted — occluder screen-left @z=8, fold prim full-screen @z=0")


func _build_fold_quad() -> ArrayMesh:
	# One flat quad in the XY plane at z=0, spanning the whole view. CUSTOM0 = the quad centroid on
	# every vertex (ADR-0009 flat depth), white vertex color so ALBEDO = white * psx_brightness.
	var v00 := Vector3(-40, -40, 0)
	var v01 := Vector3(-40, 40, 0)
	var v10 := Vector3(40, -40, 0)
	var v11 := Vector3(40, 40, 0)
	var centroid := DepthMode.quad_centroid(v00, v01, v10, v11)
	var pos := PackedVector3Array([v00, v01, v10, v01, v11, v10])
	var white := Color(1, 1, 1, 1)
	var col := PackedColorArray([white, white, white, white, white, white])
	var uv := PackedVector2Array([Vector2.ZERO, Vector2(0, 1), Vector2(1, 0),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
	var c0 := PackedFloat32Array()
	for _i in 6:
		c0.append(centroid.x); c0.append(centroid.y); c0.append(centroid.z)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	var cf := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, cf)
	return am


func _process(_dt: float) -> bool:
	if _quit:
		return true
	_f += 1
	if _readback != null and _readback.done:
		_exit_code = 0 if _readback.passed else 1
		_quit = true
		quit(_exit_code)
		return true
	# Keep the autopilot down and OUR compositor pinned (it may have attached after _initialize).
	var autopilot := root.get_node_or_null("CompositorAutopilot")
	if autopilot != null:
		autopilot.set_process(false)
	if _cam != null and _cam.compositor != null and not _cam.compositor.compositor_effects.has(_readback):
		var comp := Compositor.new()
		comp.compositor_effects = [_seed, _readback]
		_cam.compositor = comp
	# Let the scene settle, then arm one capture.
	if _f == 20:
		_readback.armed = true
	elif _f > 240:
		print("[occlusion-fold] FAIL — capture never completed")
		_quit = true
		quit(1)
		return true
	return false
