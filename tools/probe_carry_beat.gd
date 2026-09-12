extends SceneTree
## [Carry-beat parity probe] Parks scenario 6 at a target PC using the SAME
## rewind path as the F3 ScenarioVM debug panel (ScenarioDebugSession.rewind_
## target_pc -> ScenarioPlayerScene -> _vm.set_rewind_target), then reports
## Delita(5) + Ovelia(12) world placement AND their camera-projected screen
## positions, so the Godot screen delta can be A/B'd against the PSX ground
## truth (PSX: Delita screen (263,136), Ovelia (265,139) -> delta (+2,+3)).
##
## Run (NOT headless):
##   PC=216 godot --path . -s res://tools/probe_carry_beat.gd
## Env: PC (target pc, default 216), SHOT (png path, default /tmp/sxs/godot_carry.png)

var _scene: Node
var _vm: Node
var _f := 0
var _pc := 216
var _shot := "/tmp/sxs/godot_carry.png"
var _done := false
var _reported := false

func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _pc
	else:
		push_error("[carry] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[carry] booting scn6, rewind target pc=%d" % _pc)

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

func _screen_of(u) -> Vector2:
	var mesh = u.get("mesh_instance")
	if mesh == null or not is_instance_valid(mesh): return Vector2(-1, -1)
	var cam := root.get_viewport().get_camera_3d()
	if cam == null: return Vector2(-2, -2)
	return cam.unproject_position(mesh.global_position)

func _line(uid: int, u) -> String:
	var mesh = u.get("mesh_instance")
	var gp := Vector3.ZERO
	if mesh != null and is_instance_valid(mesh): gp = mesh.global_position
	var la = _vm.peek_actor(uid)
	var home := Vector3.ZERO
	if la != null and la.get("has_home"): home = la.get("home")
	var off := gp - home
	var sp := _screen_of(u)
	return "U%-2d anim=%d(0x%X) gp=(%.3f,%.3f,%.3f) home=(%.2f,%.2f,%.2f) off=(%.3f,%.3f,%.3f) screen=(%.1f,%.1f) vis=%s" % [
		uid, u.current_anim_id, u.current_anim_id, gp.x, gp.y, gp.z,
		home.x, home.y, home.z, off.x, off.y, off.z, sp.x, sp.y, str(u.visible)]

func _dump_tiles(uid: int, u) -> void:
	var mat = u.get("material")
	if mat == null: return
	var rects = mat.get_shader_parameter("type1_rects")
	var sizes = mat.get_shader_parameter("type1_rect_sizes")
	var locs = mat.get_shader_parameter("type1_locs")
	var offs = mat.get_shader_parameter("type1_loc_offsets")
	var msz = mat.get_shader_parameter("mesh_size")
	var tsz = mat.get_shader_parameter("type1_tex_size")
	print("    U%d tiles mesh_size=%s tex_size=%s" % [uid, str(msz), str(tsz)])
	for i in range(min(3, (locs.size() if locs != null else 0))):
		var rs = sizes[i] if sizes != null else Vector2.ZERO
		if rs == Vector2.ZERO and i > 0: continue
		print("      tile[%d] src_rect=%s size=%s  loc(screen)=%s loc_off=%s" % [
			i, str(rects[i]) if rects != null else "?", str(rs),
			str(locs[i]) if locs != null else "?", str(offs[i]) if offs != null else "?"])

func _on_ready_report() -> void:
	var ubid = _vm.get("units_by_id")
	if ubid == null: return
	print("[carry] ===== PARKED pc=%d f=%d =====" % [_vm.get_pc(), _f])
	for uid in [5, 12, 6]:
		if ubid.has(uid) and ubid[uid] != null and is_instance_valid(ubid[uid]):
			print("  " + _line(uid, ubid[uid]))
			_dump_tiles(uid, ubid[uid])
	# screen delta Ovelia - Delita
	if ubid.has(5) and ubid.has(12):
		var d := _screen_of(ubid[5]); var o := _screen_of(ubid[12])
		print("  SCREEN delta Ovelia-Delita = (%.1f, %.1f)  [PSX ground truth = (+2, +3)]" % [o.x - d.x, o.y - d.y])

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer"):
		(n as CanvasLayer).visible = false
	if n is ColorRect and (n.name == "FadeRect" or n.name == "OxideRect"):
		(n as ColorRect).color = Color((n as ColorRect).color.r, (n as ColorRect).color.g, (n as ColorRect).color.b, 0.0)
	if n.name == "MapGridOverlay" and "visible" in n: n.visible = false
	for c in n.get_children(): _hide_overlays(c)

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	# wait until parked at (or past) target pc and paused
	if not _reported and _vm.get_pc() >= _pc and _vm.get("_paused"):
		_reported = true
		_on_ready_report()
		_hide_overlays(_scene)
		var ubid2 = _vm.get("units_by_id")
		# Recolor via the tint path (scale=0 -> flat bias color; pure magenta/cyan
		# survive the gamma pow(2.2) exactly). Ovelia=magenta, Delita=cyan.
		_flat(ubid2.get(12), Vector3(1, 0, 1))
		_flat(ubid2.get(5),  Vector3(0, 1, 0))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_shot)
		print("[carry] recolored shot -> %s (pc=%d)" % [_shot, _vm.get_pc()])
		_done = true

func _flat(u, col: Vector3) -> void:
	if u == null or not is_instance_valid(u): return
	var mat = u.get("material")
	if mat == null: return
	mat.set_shader_parameter("unit_tint_scale", Vector3(0, 0, 0))
	mat.set_shader_parameter("unit_tint_bias", col)
	mat.set_shader_parameter("unit_tint", Vector3(0, 0, 0))
	mat.set_shader_parameter("ambient_brightness", 1.0)
	if _f > 4000 and not _reported:
		print("[carry] TIMEOUT never parked at pc=%d (pc=%d paused=%s)" % [_pc, _vm.get_pc(), str(_vm.get("_paused"))])
		_done = true

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
