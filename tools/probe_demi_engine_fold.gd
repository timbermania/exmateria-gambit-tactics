extends SceneTree
## DEMI 2 (E046) through the NEW 4.8-dev ENGINE Pass B fold (design engine-shaded-display-fold.md).
##
## Scoped validation: instead of the raw-GLSL compositor fold, re-materialize E046's routed
## transparent prims as per-run MultiMeshInstance3D + `compositor_fold` materials, stamp each run's
## sorting_offset = its OTDepthPrimOrder fold index, and let the ENGINE fold them into a
## compositor-owned display scratch (Pass A seeds it black/α=0; the engine draws with DRAW_LOAD).
## Then read the scratch back and check the DEMI signature: the white/magenta additive core (R≈B ≫ G)
## survives ON TOP of the black subtractive cloud — the same age-DESC tie-break the raw-GLSL fold
## already gets right (research/working_documents/DEMI2_E046_ADDITIVE_SUBTRACTIVE_ORDERING.md §5a).
##
## `correct` (default) stamps sorting_offset = fold index (add-newer folds last → core survives).
## `swapped` negates it (sub folds last → core clobbered) — proving order, not depth, controls it.
##
## MUST run on the 4.8-dev engine, Forward+ (the fold is Forward+-only), NEVER headless:
##   BIN=~/Repos/godot-compositor-consume-material/bin/godot.linuxbsd.editor.dev.x86_64
##   # from the package root
##   "$BIN" --path . --rendering-method forward_plus -s res://tools/probe_demi_engine_fold.gd -- correct
##   "$BIN" --path . --rendering-method forward_plus -s res://tools/probe_demi_engine_fold.gd -- swapped

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 46
const SEEKS := [36, 39, 42, 45]
const KEEP := [1, 3]              # keep emitter idx1 (black sub) + idx3 (white add)
const ALL_EMITTERS := 5
const OUT_DIR := "/tmp/demi_engine_fold"

## Preloaded `Shader` objects, not `String` paths — ADR-0191 dec. 11. A `load()` on a
## mistyped path returns null, a null shader does not raise, and the fold "just stops, with no
## error" — which in a capture probe means a silently WRONG frame written to disk and compared
## against an oracle. The same three EngineFoldCompositor materialises.
const FOLD_ADD := preload("res://addons/exmateria_effects/render/effect_fold_add.gdshader")
const FOLD_SUB := preload("res://addons/exmateria_effects/render/effect_fold_sub.gdshader")
const FOLD_MIX := preload("res://addons/exmateria_effects/render/effect_fold_mix.gdshader")
const SETTLE := 8                 # post-draw ticks to hold a seek before capturing

# ADD_ISH modes fold as additive material; 2 = subtractive; 0 = mix.
const ADD_MODES := [1, 3]

var _order := "correct"
var _scene: Node
var _cam: Camera3D
var _fold_root: Node3D
var _quad: QuadMesh
var _pool: Node
var _seed: CompositorEffect
var _readback: CompositorEffect
var _mat_add: ShaderMaterial
var _mat_sub: ShaderMaterial
var _mat_mix: ShaderMaterial

var _f := 0
var _played := false
var _si := -1
var _hold := 0
var _quit := false
var _dumped := false

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

# ---- Pass C stand-in: read the folded scratch, log the signature + save a PNG, on request ----
class ReadbackPass:
	extends CompositorEffect
	var capture_tag := ""
	var out_dir := "/tmp/demi_engine_fold"
	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	func _render_callback(cb: int, rd_data: RenderData) -> void:
		if cb != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or capture_tag == "":
			return
		var tag := capture_tag
		capture_tag = ""
		var rb := rd_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if rb == null or not rb.has_texture(&"compositor_fold", &"color"):
			_log(tag, "NO fold scratch")
			return
		var tex := rb.get_texture(&"compositor_fold", &"color")
		var rd := RenderingServer.get_rendering_device()
		var size := rb.get_internal_size()
		var w := int(size.x)
		var h := int(size.y)
		var data := rd.texture_get_data(tex, 0)
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		var touched := 0
		var best := -1.0
		var br := 0.0
		var bg := 0.0
		var bb := 0.0
		var bx := 0
		var by := 0
		var maxr := 0.0
		var maxg := 0.0
		var maxb := 0.0
		for y in range(h):
			var row := y * w
			for x in range(w):
				var v := data.decode_u32((row + x) * 4)
				var r := float(v & 0x3FF) / 1023.0
				var g := float((v >> 10) & 0x3FF) / 1023.0
				var b := float((v >> 20) & 0x3FF) / 1023.0
				var a := (v >> 30) & 0x3
				img.set_pixel(x, y, Color(r, g, b))
				if a > 0:
					touched += 1
					maxr = max(maxr, r)
					maxg = max(maxg, g)
					maxb = max(maxb, b)
					var lum := r + g + b
					if lum > best:
						best = lum
						br = r; bg = g; bb = b; bx = x; by = y
		DirAccess.make_dir_recursive_absolute(out_dir)
		img.save_png("%s/%s.png" % [out_dir, tag])
		var sig := "core R=%.3f G=%.3f B=%.3f @(%d,%d) | maxRGB=(%.3f,%.3f,%.3f) touched=%d | %s" % [
			br, bg, bb, bx, by, maxr, maxg, maxb, touched,
			("MAGENTA/WHITE CORE (R,B >> G) ✓" if (br > 0.5 and bb > 0.5 and br - bg > 0.2) else "no bright R≈B core")]
		_log(tag, sig)
	func _log(tag: String, msg: String) -> void:
		var path := "%s/probe.log" % out_dir
		var f := FileAccess.open(path, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(path, FileAccess.WRITE)
		else:
			f.seek_end()
		f.store_line("[%s] %s" % [tag, msg])
		f.close()
		print("[fold] %s: %s" % [tag, msg])

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[0]) == "swapped":
		_order = "swapped"
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Raw display texels: no linearize, unit PAR (globals the stp include reads). psx_brightness was
	# deleted (ADR-0074 fold endgame — gain baked per-producer), so it is no longer set here.
	RenderingServer.global_shader_parameter_set("psx_gamma", 1.0)
	RenderingServer.global_shader_parameter_set("psx_fx_stretch", 1.0)
	RenderingServer.global_shader_parameter_set("pixel_aspect", 1.0)
	_mat_add = _make_mat(FOLD_ADD)
	_mat_sub = _make_mat(FOLD_SUB)
	_mat_mix = _make_mat(FOLD_MIX)
	_quad = QuadMesh.new()
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[fold] booting EffectViewer E%03d, order=%s, keep=%s" % [EFFECT_ID, _order, str(KEEP)])

func _make_mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("srgb_to_linear", false)
	m.set_shader_parameter("use_palette", false)
	return m

func _process(_dt: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if not _played:
		var driver := _scene.get_node_or_null("CombatCompositeDriver")
		_cam = _scene.get_node_or_null("PlayerCamera/FocusPoint/Camera") as Camera3D
		var ready: bool = _scene.get("_caster") != null and _scene.get("_target") != null \
			and driver != null and _cam != null
		if ready and _f > 20:
			_pool = Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")
			# Take the camera off the raw-RD compositor (it errors under Forward+) and give it OUR
			# Pass A seed + readback. The engine folds the compositor_fold prims in between.
			driver.set_process(false)
			# ISOLATE ORDERING FROM OCCLUSION: the production fold shaders now depth-test against the
			# opaque scene (occlusion resolved 2026-07-27), which would cull E046's prims behind the map
			# and defeat this ordering-only probe. Hide the opaque ProceduralMap so nothing writes the
			# scene depth the fold tests against — the fold prims then draw unoccluded and the DEMI
			# add-over-sub signature is governed purely by sorting_offset. (Occlusion itself is covered by
			# probe_occlusion_engine_fold.gd + the E065 real-scene shot, not here.)
			var pmap := _scene.get_node_or_null("ProceduralMap")
			if pmap != null:
				pmap.visible = false
			_seed = SeedPass.new()
			_readback = ReadbackPass.new()
			_readback.out_dir = OUT_DIR
			var comp := Compositor.new()
			comp.compositor_effects = [_seed, _readback]
			_cam.compositor = comp
			_fold_root = Node3D.new()
			_fold_root.name = "EngineFoldPrims"
			_scene.add_child(_fold_root)
			_scene.call("play_effect", EFFECT_ID, true)
			_played = true
			_si = 0
			_seek_current()
		elif _f > 300:
			print("[fold] FAIL — never became ready")
			_quit = true
		return

	if _si >= SEEKS.size():
		return
	_rebuild_fold_prims()
	_hold -= 1
	if _hold == 2:
		_readback.capture_tag = "%s_f%02d" % [_order, SEEKS[_si]]
	elif _hold <= 0:
		_si += 1
		if _si >= SEEKS.size():
			print("[fold] done (%s)" % _order)
			_quit = true
		else:
			_seek_current()

func _seek_current() -> void:
	var eff: Node = _scene.get("_current_effect")
	if eff != null and is_instance_valid(eff):
		var dis := {}
		for k in range(ALL_EMITTERS):
			if not KEEP.has(k):
				dis[k] = true
		eff.call("set_debug_emitter_filter", dis)
		eff.call("seek", SEEKS[_si])
	_hold = SETTLE

# Rebuild the routed transparent prims as per-run MultiMesh + compositor_fold materials, stamping
# sorting_offset = fold order (negated for `swapped`). One MultiMeshInstance3D per OT run.
func _rebuild_fold_prims() -> void:
	if _pool == null or _fold_root == null:
		return
	for c in _fold_root.get_children():
		_fold_root.remove_child(c)
		c.free()
	var buckets: Array = _pool.call("get_active_effect_buckets")
	var fold_idx := 0
	for e in buckets:
		var bytes: PackedByteArray = e.get("unified_bytes", PackedByteArray())
		if bytes.is_empty():
			continue
		var all: PackedFloat32Array = bytes.to_float32_array()
		var tex: Texture2D = e.get("effect_tex_2d")
		var runs: Array = e["runs"]
		for run in runs:
			var mode: int = run["mode"]
			var base: int = run["base"]
			var cnt: int = run["count"]
			var stride: int = run.get("stride", 24)
			if cnt <= 0:
				continue
			var buf := PackedFloat32Array()
			buf.resize(cnt * 20)
			for i in range(cnt):
				var src := (base + i) * stride
				for fl in range(20):
					buf[i * 20 + fl] = all[src + fl]
			if _si == SEEKS.size() - 1 and not _dumped:
				var s0 := base * stride
				var so := float(-fold_idx if _order == "swapped" else fold_idx)
				print("[fold] DUMP run#%d mode=%d cnt=%d sorting_offset=%.0f  COLOR=(%.3f,%.3f,%.3f)  uv=(%.3f,%.3f,%.3f,%.3f)" % [
					fold_idx, mode, cnt, so,
					all[s0+12], all[s0+13], all[s0+14],
					all[s0+16], all[s0+17], all[s0+18], all[s0+19]])
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _quad
			mm.instance_count = cnt
			mm.buffer = buf
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			var mat: ShaderMaterial = _mat_sub if mode == 2 else (_mat_mix if mode == 0 else _mat_add)
			mat = mat.duplicate() as ShaderMaterial
			if tex != null:
				mat.set_shader_parameter("effect_texture", tex)
				mat.set_shader_parameter("texture_size", tex.get_size())
			inst.material_override = mat
			# The engine's fold list sorts by sorting_offset (uncapped float, NOT depth). Run order
			# from OTDepthPrimOrder IS the fold order (far→near, age-DESC tie-break within a bucket).
			inst.sorting_offset = float(-fold_idx if _order == "swapped" else fold_idx)
			# Guard against Godot frustum-culling a MultiMesh whose AABB it can't infer from the
			# shader-overwritten VERTEX; keep it always drawn.
			inst.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
			_fold_root.add_child(inst)
			fold_idx += 1
	if fold_idx > 0 and _si == SEEKS.size() - 1:
		_dumped = true
