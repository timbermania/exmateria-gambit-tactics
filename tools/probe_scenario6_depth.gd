extends SceneTree
## [Depth-sort investigation] Boots scenario 6, rewinds the VM to a target PC
## (default 320 = the "Delita on chocobo carrying Ovelia" tableau, frozen on the
## Change-Dialog beat), lets the carry pose settle, then MEASURES the PSX
## ordering-table (OT) depth of the three composed units — chocobo (139),
## Ovelia (12), Delita (5) — the way the unit shader does it (ADR-0009):
##
##   depth_point = mesh_origin + (0, depth_center_height, 0)
##   base_depth  = (PROJ * VIEW * depth_point).z / .w      # reversed-Z NDC
##
## depth_center_height is set per-animation-frame by SpriteLayerManager from the
## body sprite ART's vertical center. This probe reports, per unit:
##   * mesh_origin (world), depth_center_height, anim id
##   * base_center : OT base depth using the shipped depth_center_height
##   * base_ground : OT base depth with depth_center_height forced to 0 (feet)
## and the SPREAD (max-min) of base_center vs base_ground across the trio.
##
## HYPOTHESIS (red signal): the three co-located carry units scatter widely in
## base_center (different OT buckets -> the wrong-depth-sort / wall-clip the user
## sees), and that scatter COLLAPSES in base_ground -> the divergence is the
## pose-art-derived depth_center_height leaking 2D art height into 3D OT depth,
## which PSX (grounded OTZ per unit) does not do.
##
## Run (NOT headless):
##   # from the package root
##   PC=320 SHOT=/tmp/s6_depth.png godot --path . -s res://tools/probe_scenario6_depth.gd
## Env: PC (target instruction, default 320), SHOT (PNG out), SETTLE (frames
##      after rewind completes, default 40), MAXF (frame cap, default 6000).

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 6000
var _pc := 320
var _settle := 40
var _shot := "/tmp/s6_depth.png"
var _watch := [139, 5, 12]          # chocobo, Delita, Ovelia
var _rewound := false
var _settle_at := -1

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	if OS.has_environment("SETTLE"): _settle = int(OS.get_environment("SETTLE"))
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[depth] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[depth] booting scenario 6, target PC=%d settle=%d shot=%s" % [_pc, _settle, _shot])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = false
			print("[depth] VM found at f=%d" % _f)
		return

	# 1) kick the rewind once
	if not _rewound:
		if _vm.has_method("set_rewind_target"):
			_vm.set_rewind_target(_pc)
			_rewound = true
			print("[depth] rewind → PC=%d issued at f=%d" % [_pc, _f])
		return

	# 2) wait for fast-play to complete (paused, not fast-forwarding)
	var ff = _vm.get("_ff_active")
	var paused = _vm.get("paused")
	var arrived: bool = (paused == true) and (ff == false or ff == null)
	if _settle_at < 0:
		if arrived:
			_settle_at = _f
			print("[depth] arrived+paused at f=%d, settling %d frames" % [_f, _settle])
		if _f >= _maxf:
			print("[depth] TIMEOUT before arrival f=%d" % _f); _quit = true
		return

	# 3) let the carry pose render so depth_center_height is populated
	if _f < _settle_at + _settle:
		return

	_measure_and_dump()
	_capture(_shot)
	_quit = true

func _proj_base_depth(cam: Camera3D, world_pt: Vector3) -> float:
	# Replicate ot_depth base: (PROJ * VIEW * pt).z / .w   (reversed-Z NDC).
	var P: Projection = cam.get_camera_projection()
	var view: Transform3D = cam.get_camera_transform().affine_inverse()
	var vs: Vector3 = view * world_pt            # view space (w=1)
	# clip = P * vec4(vs, 1)   (columns P.x/P.y/P.z/P.w are Vector4)
	var cz: float = P.x.z * vs.x + P.y.z * vs.y + P.z.z * vs.z + P.w.z
	var cw: float = P.x.w * vs.x + P.y.w * vs.y + P.z.w * vs.z + P.w.w
	if absf(cw) < 1e-9: return 0.0
	return cz / cw

func _measure_and_dump() -> void:
	var cam: Camera3D = root.get_camera_3d()
	if cam == null:
		print("[depth] NO CAMERA"); return
	var ubid = _vm.get("units_by_id")
	print("\n[depth] ================ OT-DEPTH MEASUREMENT @ PC=%d (f=%d) ================" % [_pc, _f])
	print("[depth] reversed-Z NDC: LARGER = nearer camera (drawn in front).")
	var centers: Array[float] = []
	var grounds: Array[float] = []
	var rows: Array = []
	for uid in _watch:
		if ubid == null or not ubid.has(uid):
			print("[depth] uid=%d MISSING" % uid); continue
		var u = ubid[uid]
		if u == null or not is_instance_valid(u):
			print("[depth] uid=%d invalid" % uid); continue
		var mesh: MeshInstance3D = u.get("mesh_instance")
		var mat: ShaderMaterial = u.get("material")
		var origin: Vector3 = mesh.global_transform.origin if mesh else u.global_position
		var dch: float = 0.0
		if mat != null:
			var v = mat.get_shader_parameter("depth_center_height")
			if v != null: dch = float(v)
		var aid: int = u.current_anim_id
		var vis = u.visible
		var base_center := _proj_base_depth(cam, origin + Vector3(0.0, dch, 0.0))
		var base_ground := _proj_base_depth(cam, origin)
		centers.append(base_center)
		grounds.append(base_ground)
		rows.append([uid, origin, dch, aid, vis, base_center, base_ground])
	for r in rows:
		print("[depth] uid=%3d anim=0x%03X vis=%s origin=(%6.2f,%6.2f,%6.2f) dch=%+.4f  base_center=%.6f  base_ground=%.6f" % [
			r[0], r[3], str(r[4]), r[1].x, r[1].y, r[1].z, r[2], r[5], r[6]])
	if centers.size() >= 2:
		var spread_c: float = centers.max() - centers.min()
		var spread_g: float = grounds.max() - grounds.min()
		print("[depth] ---- SPREAD across %d units ----" % centers.size())
		print("[depth] base_center spread (SHIPPED, pose-art center) = %.6f" % spread_c)
		print("[depth] base_ground spread (feet / PSX-like anchor)   = %.6f" % spread_g)
		var ratio := spread_c / spread_g if spread_g > 1e-9 else INF
		print("[depth] ratio center/ground = %.2fx   (>>1 ⇒ depth_center_height is the scatter source)" % ratio)
		# bucket estimate: units-per-bucket default 0.19 world; convert via proj[2][2]
		var P: Projection = cam.get_camera_projection()
		var per_bucket_ndc: float = absf(0.19 * P.z.z)
		if per_bucket_ndc > 1e-9:
			print("[depth] est OT-bucket span: center=%.2f buckets, ground=%.2f buckets (1 bucket≈0.19 world)" % [
				spread_c / per_bucket_ndc, spread_g / per_bucket_ndc])
	print("[depth] =====================================================================\n")

func _capture(path: String) -> void:
	_hide_overlays(_scene)
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("[depth] shot f=%d -> %s" % [_f, path])

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer" \
			or n.name == "DialogueOverlay"):
		(n as CanvasLayer).visible = false
	if n is ColorRect:
		var cr := n as ColorRect
		if cr.name == "FadeRect" or cr.name == "OxideRect":
			cr.color = Color(cr.color.r, cr.color.g, cr.color.b, 0.0)
	for c in n.get_children():
		_hide_overlays(c)

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
