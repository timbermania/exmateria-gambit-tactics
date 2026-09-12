extends SceneTree
## [Unit-forward vs terrain] Sweep `ot_unit_forward` on the scenario-6 carry
## tableau and measure, per value, whether the chocobo (139) still gets occluded
## by the foreground ledge terrain. The UNIT-mode nudge (ADR-0009) pulls every
## unit sprite toward the camera in front of its own tile by `uf * proj[2][2]`
## NDC; it shifts ALL units equally, so it fixes over-occlusion by terrain WITHOUT
## disturbing unit-vs-unit order. This finds the value that clears the ledge.
##
## For each uf in the sweep it prints the chocobo's rendered depth (base + nudge),
## the nearest occluding terrain face depth along the sprite axis, and the margin;
## and saves a screenshot so the un-occlusion can be eyeballed.
##
## Run (NOT headless):
##   # from the package root
##   OUT=/tmp godot --path . -s res://tools/probe_scenario6_unitforward_sweep.gd

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 6000
var _pc := 316
var _settle := 40
var _out := "/tmp"
var _rewound := false
var _settle_at := -1
var _stage := 0
var _choc = null
var _real_dch := 0.0
var _p22 := 0.0
var _sweep := [0.1, -1.0, -3.0, -5.0, -8.0]

func _initialize() -> void:
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null: sess.selected_scenario_id = 6
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[sweep] booting scenario 6, PC=%d out=%s" % [_pc, _out])

func _process(_delta: float) -> bool:
	if _quit:
		quit(); return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null: _vm.dialog_auto_advance = false
		return
	if not _rewound:
		if _vm.has_method("set_rewind_target"):
			_vm.set_rewind_target(_pc); _rewound = true
		return
	var ff = _vm.get("_ff_active")
	var paused = _vm.get("paused")
	if _settle_at < 0:
		if (paused == true) and (ff == false or ff == null):
			_settle_at = _f
		elif _f >= _maxf:
			print("[sweep] TIMEOUT"); _quit = true
		return
	if _f < _settle_at + _settle:
		_hide_overlays(_scene)
		return

	if _stage == 0:
		if not _bind():
			_quit = true; return
		_stage = 1
		return

	# stages 1.. : one sweep value per post_draw tick
	var i := _stage - 1
	if i >= _sweep.size():
		_quit = true; return
	var uf: float = _sweep[i]
	_apply_uf_all(uf)
	_measure(uf)
	_capture("%s/sweep_uf_%02d.png" % [_out, int(round(uf * 10))])
	_stage += 1

func _bind() -> bool:
	var ubid = _vm.get("units_by_id")
	if ubid == null or not ubid.has(139):
		print("[sweep] chocobo 139 MISSING"); return false
	_choc = ubid[139]
	var mat: ShaderMaterial = _choc.get("material")
	if mat != null:
		var v = mat.get_shader_parameter("depth_center_height")
		if v != null: _real_dch = float(v)
	var cam: Camera3D = root.get_camera_3d()
	var P: Projection = cam.get_camera_projection()
	_p22 = P.z.z
	print("[sweep] proj[2][2] = %.6f  → uf=0.1 adds %.6f NDC (larger=nearer)" % [_p22, 0.1 * _p22])
	return true

func _apply_uf_all(uf: float) -> void:
	var ubid = _vm.get("units_by_id")
	for k in ubid.keys():
		var u = ubid[k]
		if u != null and is_instance_valid(u):
			var m: ShaderMaterial = u.get("material")
			if m != null:
				m.set_shader_parameter("ot_unit_forward", uf)

func _proj_base_depth(cam: Camera3D, world_pt: Vector3) -> float:
	var P: Projection = cam.get_camera_projection()
	var view: Transform3D = cam.get_camera_transform().affine_inverse()
	var vs: Vector3 = view * world_pt
	var cz: float = P.x.z * vs.x + P.y.z * vs.y + P.z.z * vs.z + P.w.z
	var cw: float = P.x.w * vs.x + P.y.w * vs.y + P.z.w * vs.z + P.w.w
	if absf(cw) < 1e-9: return 0.0
	return cz / cw

func _measure(uf: float) -> void:
	var cam: Camera3D = root.get_camera_3d()
	var mesh: MeshInstance3D = _choc.get("mesh_instance")
	var origin: Vector3 = mesh.global_transform.origin
	var base := _proj_base_depth(cam, origin + Vector3(0, _real_dch, 0))
	var rendered := base + uf * _p22
	# nearest terrain occluder along the sprite axis (feet .. body)
	var feet_s: Vector2 = cam.unproject_position(origin)
	var head_s: Vector2 = cam.unproject_position(origin + Vector3(0, 1.6, 0))
	var worst := -2.0
	var worst_t := -1.0
	var gm := _find_geometry_mesh(_scene)
	if gm != null and gm.mesh != null:
		var xf := gm.global_transform
		var am: ArrayMesh = gm.mesh
		for t in [0.0, 0.15, 0.3, 0.5, 0.75]:
			var sp: Vector2 = feet_s.lerp(head_s, t)
			var nd := _nearest_face_depth_at(cam, am, xf, sp)
			if nd > worst:
				worst = nd; worst_t = t
	var margin := rendered - worst
	var verdict := "CLEAR (unit in front)" if margin > 0.0 else "OCCLUDED"
	print("[sweep] uf=%.2f  choc rendered=%.6f  worst terrain=%.6f (t=%.2f)  margin=%+.6f  → %s" % [
		uf, rendered, worst, worst_t, margin, verdict])

func _nearest_face_depth_at(cam: Camera3D, am: ArrayMesh, xf: Transform3D, sp: Vector2) -> float:
	var nearest := -2.0
	for si in am.get_surface_count():
		var arr := am.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx_raw = arr[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = idx_raw if idx_raw != null else PackedInt32Array()
		var n := idx.size() if idx.size() > 0 else verts.size()
		var i := 0
		while i < n:
			var ia := idx[i] if idx.size() > 0 else i
			var ib := idx[i + 1] if idx.size() > 0 else i + 1
			var ic := idx[i + 2] if idx.size() > 0 else i + 2
			i += 3
			var wa: Vector3 = xf * verts[ia]
			var wb: Vector3 = xf * verts[ib]
			var wc: Vector3 = xf * verts[ic]
			if cam.is_position_behind(wa) or cam.is_position_behind(wb) or cam.is_position_behind(wc):
				continue
			var pa := cam.unproject_position(wa)
			var pb := cam.unproject_position(wb)
			var pc := cam.unproject_position(wc)
			if not _tri_contains(sp, pa, pb, pc):
				continue
			var cen: Vector3 = (wa + wb + wc) / 3.0
			var d := _proj_base_depth(cam, cen)
			if d > nearest: nearest = d
	return nearest

func _tri_contains(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (neg and pos)

func _find_geometry_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == "GeometryMesh":
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_geometry_mesh(c)
		if r != null: return r
	return null

func _capture(path: String) -> void:
	_hide_overlays(_scene)
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("[sweep] shot -> %s" % path)

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
