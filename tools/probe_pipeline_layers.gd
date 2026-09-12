extends SceneTree
## [Godot pipeline-layer probe] The Godot-side counterpart to
## tools/probe_pipeline_psx.lua. Parks scenario 6 at a target PC and dumps the
## coordinate/position state at EVERY stage of the sprite pipeline
## (docs/PSX_TO_GODOT_SPRITE_PIPELINE.md) for Delita(5) and Ovelia(12), so each
## layer can be diffed against the PSX read.
##
## Layers (§ = doc section):
##   A frame-select (§1-3): current_anim_id, facing_direction
##   B/E pieces + placement inputs (§4-5,7): per-piece type1_locs/rects/rect_sizes/
##       inversions/reversions/rotations/rot_points/loc_offsets, shared_loc_offset,
##       global_reversion, depth_center_height
##   C world-anchor (§8-9): mesh.global_position
##   D projection (§10-11): cam.unproject_position(anchor), horizontal px/world scale
##
## Run headful (never --headless):
##   PC=210 godot --path . -s res://tools/probe_pipeline_layers.gd
var _scene: Node
var _vm: Node
var _f := 0
var _pc := 210
var _done := false
var _reported := false

func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _pc
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[ppl] booting scn6 pc=%d" % _pc)

func _process(_dt: float) -> bool:
	if _done:
		quit()
		return true
	return false

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null

func _v2(a, i) -> Vector2:
	return a[i] if a != null and i < a.size() else Vector2.ZERO

func _dump_unit(uid: int, u) -> void:
	if u == null or not is_instance_valid(u):
		print("  U%d: absent" % uid); return
	var mat = u.get("material")
	var cam := root.get_viewport().get_camera_3d()
	var mesh = u.get("mesh_instance")
	print("===== U%d =====" % uid)

	# Layer A — frame select
	print("A frame-select: current_anim_id=%d(0x%X) facing=%s" % [
		u.current_anim_id, u.current_anim_id, str(u.get("facing_direction"))])
	# Layer A' — raw facing inputs driving the whole-sprite H-flip (compare vs PSX
	# unit +0x70 facing / +0x6E octant). Godot's flip resolves from these; a mismatch
	# here (e.g. a dropped Multi-broadcast rotate) is what mis-flips a cinematic pose.
	var _fd = u.get("facing_direction")
	var _fa = u.get("facing_angle") if ("facing_angle" in u) else "n/a"
	var _quad = u.get_camera_quadrant() if u.has_method("get_camera_quadrant") else -1
	print("A' facing: facing_direction=%s facing_angle=%s camera_quad=%s" % [
		str(_fd), str(_fa), str(_quad)])

	# Layer C — world anchor
	var gp := Vector3.ZERO
	if mesh != null and is_instance_valid(mesh):
		gp = mesh.global_position
	print("C world-anchor: mesh.global_position=(%.4f,%.4f,%.4f)" % [gp.x, gp.y, gp.z])

	# Layer D — projection
	if cam != null and mesh != null and is_instance_valid(mesh):
		var sp := cam.unproject_position(gp)
		# horizontal px per world-unit: unproject anchor vs anchor + camera-right
		var right := cam.global_transform.basis.x.normalized()
		var sp_r := cam.unproject_position(gp + right)
		print("D projection: screen_anchor=(%.2f,%.2f) px_per_world_x=%.2f cam_ortho_size=%.3f" % [
			sp.x, sp.y, absf(sp_r.x - sp.x),
			(cam.size if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else -1.0)])

	# Layer B/E — pieces + placement inputs
	if mat == null:
		print("  (no material)"); return
	var shared = mat.get_shader_parameter("shared_loc_offset")
	var grev = mat.get_shader_parameter("global_reversion")
	var dch = mat.get_shader_parameter("depth_center_height")
	print("B/E pieces: shared_loc_offset=%s global_reversion=%s depth_center_height=%s" % [
		str(shared), str(grev), str(dch)])
	var locs  = mat.get_shader_parameter("type1_locs")
	var rects = mat.get_shader_parameter("type1_rects")
	var sizes = mat.get_shader_parameter("type1_rect_sizes")
	var inv   = mat.get_shader_parameter("type1_inversions")
	var rev   = mat.get_shader_parameter("type1_reversions")
	var rots  = mat.get_shader_parameter("type1_rotations")
	var rpts  = mat.get_shader_parameter("type1_rot_points")
	var loffs = mat.get_shader_parameter("type1_loc_offsets")
	var n := 0
	if sizes != null:
		for i in range(sizes.size()):
			if sizes[i].x > 0.0: n = i + 1  # highest defined piece
	print("  count(defined)=%d" % n)
	for i in range(n):
		var iv = inv[i] if inv != null and i < inv.size() else null
		var rv = rev[i] if rev != null and i < rev.size() else null
		var ro = rots[i] if rots != null and i < rots.size() else 0.0
		print("  piece[%d] loc=(%.0f,%.0f) rect=(%.0f,%.0f) size=(%.0fx%.0f) flipX(rev)=%s flipY(inv)=%s rot=%.1f rot_pt=%s loc_off=%s" % [
			i, _v2(locs,i).x, _v2(locs,i).y, _v2(rects,i).x, _v2(rects,i).y,
			_v2(sizes,i).x, _v2(sizes,i).y, str(rv), str(iv), ro,
			str(_v2(rpts,i)), str(_v2(loffs,i))])

func _report() -> void:
	var ubid = _vm.get("units_by_id")
	print("[ppl] ===== PARKED pc=%d =====" % _vm.get_pc())
	print("(diff against tools/probe_pipeline_psx.lua — same layers A/B/C/D)")
	for uid in [5, 12]:
		if ubid.has(uid):
			_dump_unit(uid, ubid[uid])
		else:
			print("===== U%d absent =====" % uid)

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	if not _reported and _vm.get_pc() >= _pc and _vm.get("_paused"):
		_reported = true
		_report()
		_done = true
	elif _f > 4000 and not _reported:
		print("[ppl] TIMEOUT never parked at pc=%d (pc=%d)" % [_pc, _vm.get_pc()])
		_done = true

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
