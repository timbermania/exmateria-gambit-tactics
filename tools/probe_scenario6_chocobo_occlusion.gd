extends SceneTree
## [Chocobo-vs-terrain occlusion] ONE bug, isolated: is the scenario-6 chocobo
## (unit 139) getting occluded by terrain, and why? Boots scenario 6, rewinds to
## PC 316 (Delita/Ovelia carry beat, no dialogue box), then:
##
##   * prints the chocobo's LOGICAL position facts (mesh origin, billboard basis,
##     depth_center_height, ground Y under it via the shadow raycast, and the OT
##     depth it computes at the shipped dch vs a normal dch)
##   * renders THREE frames for a differential eyeball diff:
##       A  choc_A_normal.png   — everything normal (bug state)
##       B  choc_B_dch.png      — chocobo depth_center_height forced to +0.10
##                                (a NORMAL standing raise instead of the monster
##                                 sprite's −1.44); isolates dch as the cause
##       C  choc_C_noterrain.png — terrain (GeometryMesh) hidden: the chocobo's
##                                 TRUE unoccluded footprint, real depth
##
## Red signal: in A the chocobo is eaten by terrain; in C you see its full body;
## if B looks like C (un-occluded) then the extreme dch (depth sample dragged
## ~1.44 units below its feet, into the ground) is the cause.
##
## Run (NOT headless):
##   # from the package root
##   OUT=/tmp godot --path . -s res://tools/probe_scenario6_chocobo_occlusion.gd
## Env: PC (default 316), OUT (dir for the 3 PNGs, default /tmp), SETTLE (40).

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

func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	if OS.has_environment("SETTLE"): _settle = int(OS.get_environment("SETTLE"))
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null: sess.selected_scenario_id = 6
	else: push_error("[choc] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[choc] booting scenario 6, PC=%d out=%s" % [_pc, _out])

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
			print("[choc] rewind → PC=%d" % _pc)
		return
	var ff = _vm.get("_ff_active")
	var paused = _vm.get("paused")
	if _settle_at < 0:
		if (paused == true) and (ff == false or ff == null):
			_settle_at = _f
		elif _f >= _maxf:
			print("[choc] TIMEOUT"); _quit = true
		return
	if _f < _settle_at + _settle:
		_hide_overlays(_scene)   # apply every frame so captures aren't caught mid-fade
		return
	# staged renders, one per post_draw tick so shader-param changes take effect
	match _stage:
		0:
			_diagnose()
			_capture("%s/choc_A_normal.png" % _out)
			_stage = 1
		1:
			# freeze the chocobo so its animation stops re-writing depth_center_height,
			# then force a NORMAL raise. Billboarding (vertex shader) is unaffected.
			if _choc != null and is_instance_valid(_choc):
				_choc.process_mode = Node.PROCESS_MODE_DISABLED
				var mat: ShaderMaterial = _choc.get("material")
				if mat != null: mat.set_shader_parameter("depth_center_height", 0.10)
			_stage = 2
		2:
			_capture("%s/choc_B_dch.png" % _out)
			# restore real dch, hide terrain → true footprint
			if _choc != null and is_instance_valid(_choc):
				var mat: ShaderMaterial = _choc.get("material")
				if mat != null: mat.set_shader_parameter("depth_center_height", _real_dch)
			_set_terrain_visible(_scene, false)
			_stage = 3
		3:
			_capture("%s/choc_C_noterrain.png" % _out)
			_quit = true

func _proj_base_depth(cam: Camera3D, world_pt: Vector3) -> float:
	var P: Projection = cam.get_camera_projection()
	var view: Transform3D = cam.get_camera_transform().affine_inverse()
	var vs: Vector3 = view * world_pt
	var cz: float = P.x.z * vs.x + P.y.z * vs.y + P.z.z * vs.z + P.w.z
	var cw: float = P.x.w * vs.x + P.y.w * vs.y + P.z.w * vs.z + P.w.w
	if absf(cw) < 1e-9: return 0.0
	return cz / cw

func _diagnose() -> void:
	var ubid = _vm.get("units_by_id")
	if ubid == null or not ubid.has(139):
		print("[choc] chocobo 139 MISSING"); return
	_choc = ubid[139]
	var cam: Camera3D = root.get_camera_3d()
	var mesh: MeshInstance3D = _choc.get("mesh_instance")
	var mat: ShaderMaterial = _choc.get("material")
	var origin: Vector3 = mesh.global_transform.origin if mesh else _choc.global_position
	var basis := (mesh.global_transform.basis if mesh else Transform3D().basis)
	_real_dch = 0.0
	if mat != null:
		var v = mat.get_shader_parameter("depth_center_height")
		if v != null: _real_dch = float(v)
	# ground Y under the chocobo via its own shadow raycast (points down)
	var ground_y := NAN
	var rc = _choc.get("shadow_raycast")
	if rc != null and is_instance_valid(rc):
		rc.enabled = true
		rc.force_raycast_update()
		if rc.is_colliding():
			ground_y = rc.get_collision_point().y
	print("\n[choc] ================ CHOCOBO (139) LOGICAL POSITION @ PC=%d ================" % _pc)
	print("[choc] node.global_position = %s" % str(_choc.global_position))
	print("[choc] mesh origin (MODEL[3]) = (%.3f, %.3f, %.3f)" % [origin.x, origin.y, origin.z])
	print("[choc] ground Y under it (raycast) = %s   →  feet-vs-ground ΔY = %s" % [
		("%.3f" % ground_y) if not is_nan(ground_y) else "n/a (no collider)",
		("%.3f" % (origin.y - ground_y)) if not is_nan(ground_y) else "n/a"])
	print("[choc] mesh basis scale = %s  (billboard sanity; expect ~uniform)" % str(basis.get_scale()))
	print("[choc] anim=0x%03X  depth_center_height(dch) = %+.4f" % [_choc.current_anim_id, _real_dch])
	print("[choc] → depth SAMPLE point Y = origin.y + dch = %.3f  (%.3f below feet)" % [
		origin.y + _real_dch, -_real_dch])
	if cam != null:
		var d_ship := _proj_base_depth(cam, origin + Vector3(0, _real_dch, 0))
		var d_feet := _proj_base_depth(cam, origin)
		var d_norm := _proj_base_depth(cam, origin + Vector3(0, 0.10, 0))
		print("[choc] OT base depth (reversed-Z, larger=nearer):")
		print("[choc]    shipped dch %+.3f → %.6f" % [_real_dch, d_ship])
		print("[choc]    at feet (0)      → %.6f" % d_feet)
		print("[choc]    normal +0.10     → %.6f" % d_norm)
	if cam != null and mesh != null:
		_scan_terrain_occluders(cam, origin, _proj_base_depth(cam, origin + Vector3(0, _real_dch, 0)))
	print("[choc] ==========================================================================\n")

func _find_geometry_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.name == "GeometryMesh":
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_geometry_mesh(c)
		if r != null: return r
	return null

func _tri_contains(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (neg and pos)

func _scan_terrain_occluders(cam: Camera3D, feet_world: Vector3, choc_depth: float) -> void:
	var gm := _find_geometry_mesh(_scene)
	if gm == null or gm.mesh == null:
		print("[choc] no GeometryMesh to scan"); return
	# sample a vertical column of screen points from the feet UP through the body
	var feet_s: Vector2 = cam.unproject_position(feet_world)
	var head_s: Vector2 = cam.unproject_position(feet_world + Vector3(0, 1.6, 0))  # ~body height
	var xf := gm.global_transform
	var am: ArrayMesh = gm.mesh
	print("[choc] --- terrain occluder scan (choc flat depth=%.6f, larger=nearer) ---" % choc_depth)
	print("[choc]     feet screen=%s  head screen=%s" % [str(feet_s.round()), str(head_s.round())])
	# probe 5 points along the sprite's vertical axis (feet=0 .. body=1)
	for t in [0.0, 0.15, 0.3, 0.5, 0.75]:
		var sp: Vector2 = feet_s.lerp(head_s, t)
		var nearest_depth := -2.0
		var nearest_y := 0.0
		var occ_count := 0
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
				# skip tris behind the camera
				if cam.is_position_behind(wa) or cam.is_position_behind(wb) or cam.is_position_behind(wc):
					continue
				var pa := cam.unproject_position(wa)
				var pb := cam.unproject_position(wb)
				var pc := cam.unproject_position(wc)
				if not _tri_contains(sp, pa, pb, pc):
					continue
				var cen: Vector3 = (wa + wb + wc) / 3.0
				var d := _proj_base_depth(cam, cen)
				if d > choc_depth:   # nearer than chocobo -> occludes it
					occ_count += 1
					if d > nearest_depth:
						nearest_depth = d
						nearest_y = cen.y
		var verdict := "OCCLUDED by %d face(s), nearest depth=%.6f (Δ=%+.6f nearer) at world Y=%.2f" % [
			occ_count, nearest_depth, nearest_depth - choc_depth, nearest_y] if occ_count > 0 else "clear"
		print("[choc]   sprite-axis t=%.2f screen=%s : %s" % [t, str(sp.round()), verdict])

func _capture(path: String) -> void:
	_hide_overlays(_scene)
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("[choc] shot f=%d stage=%d -> %s" % [_f, _stage, path])

func _set_terrain_visible(n: Node, vis: bool) -> void:
	if n is MeshInstance3D and n.name == "GeometryMesh":
		(n as MeshInstance3D).visible = vis
		print("[choc] terrain GeometryMesh.visible = %s" % str(vis))
	for c in n.get_children():
		_set_terrain_visible(c, vis)

func _hide_overlays(n: Node) -> void:
	if n is MeshInstance3D and n.name == "DarkScreenQuad":
		(n as MeshInstance3D).visible = false
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
