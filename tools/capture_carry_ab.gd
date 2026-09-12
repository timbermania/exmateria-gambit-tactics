extends SceneTree
## [Scale-free carry A/B capture] Renders scenario 6 at PSX-NATIVE resolution
## (256x256 via content_scale_size, the user's directive) so a screenshot can be
## laid DIRECTLY over the PSX 256x240 framebuffer with NO per-axis normalization.
## Parks at a target PC via the F3 rewind path (same as probe_carry_beat.gd),
## recolors Delita=green / Ovelia=magenta / chocobo=yellow, and reports each
## unit's unproject screen position (in native render px) + the Delita<->chocobo
## screen distance — the single number used to match the ortho camera `size` to
## the PSX GTE scale (PSX Delita<->chocobo = 107.1 px at the carry savestate).
##
## Run (NOT headless):
##   PC=216 CAM_SIZE=11.48 RES=256 SHOT=/tmp/sxs/godot_carry_native.png \
##     godot --path . -s res://tools/capture_carry_ab.gd
## Env: PC(216) CAM_SIZE(keep scene default) RES(256) SHOT

var _scene: Node
var _vm: Node
var _f := 0
var _pc := 216
var _res := 256
var _cam_size := -1.0
var _shot := "/tmp/sxs/godot_carry_native.png"
var _done := false
var _reported := false

func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	if OS.has_environment("RES"): _res = int(OS.get_environment("RES"))
	if OS.has_environment("CAM_SIZE"): _cam_size = float(OS.get_environment("CAM_SIZE"))
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	root.content_scale_size = Vector2i(_res, _res)
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _pc
	else:
		push_error("[cab] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[cab] booting scn6 pc=%d res=%dx%d cam_size=%s" % [_pc, _res, _res, str(_cam_size)])

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

func _cam() -> Camera3D:
	return root.get_viewport().get_camera_3d()

func _screen_of(u) -> Vector2:
	var mesh = u.get("mesh_instance")
	if mesh == null or not is_instance_valid(mesh): return Vector2(-1, -1)
	var cam := _cam()
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
	var facing = u.get("facing_direction")
	var fang = u.get("facing_angle")
	var flip := "?"
	var mat = u.get("material")
	if mat != null:
		flip = str(mat.get_shader_parameter("flip_h"))
	return "U%-2d anim=%d(0x%X) facing=%s fang=%s flipH=%s gp=(%.3f,%.3f,%.3f) home=(%.2f,%.2f,%.2f) off=(%.3f,%.3f,%.3f) screen=(%.2f,%.2f)" % [
		uid, u.current_anim_id, u.current_anim_id, str(facing), str(fang), flip, gp.x, gp.y, gp.z,
		home.x, home.y, home.z, off.x, off.y, off.z, sp.x, sp.y]

func _on_ready_report() -> void:
	var ubid = _vm.get("units_by_id")
	if ubid == null: return
	var cam := _cam()
	print("[cab] ===== PARKED pc=%d f=%d cam.size=%.4f render=%s =====" % [
		_vm.get_pc(), _f, cam.size if cam else -1.0, str(root.get_texture().get_size())])
	var ids: Array = ubid.keys()
	ids.sort()
	print("  UNIT IDS present: %s" % str(ids))
	for uid in [5, 12, 6]:
		if ubid.has(uid) and ubid[uid] != null and is_instance_valid(ubid[uid]):
			print("  " + _line(uid, ubid[uid]))
	# px-per-tile Jacobian at Delita: unproject 1-tile steps in world X / Z / +Y(height)
	if cam != null and ubid.has(5) and is_instance_valid(ubid[5]):
		var m = ubid[5].get("mesh_instance")
		if m != null and is_instance_valid(m):
			var p: Vector3 = m.global_position
			var s0 := cam.unproject_position(p)
			var sx := cam.unproject_position(p + Vector3(1, 0, 0)) - s0
			var sz := cam.unproject_position(p + Vector3(0, 0, 1)) - s0
			var sy := cam.unproject_position(p + Vector3(0, 1, 0)) - s0
			print("  JAC px/tile  dX=(%.2f,%.2f)|%.2f|  dZ=(%.2f,%.2f)|%.2f|  dY=(%.2f,%.2f)|%.2f|" % [
				sx.x, sx.y, sx.length(), sz.x, sz.y, sz.length(), sy.x, sy.y, sy.length()])
			print("  [PSX px/tile  dX=(-19.80,8.84)|21.68|  dZ=(19.77,8.84)|21.66|  dHt=(0,-10.72)|10.72|]")
	if ubid.has(5) and ubid.has(12):
		var d := _screen_of(ubid[5]); var o := _screen_of(ubid[12])
		print("  SCREEN delta Ovelia-Delita = (%.2f, %.2f)" % [o.x - d.x, o.y - d.y])
	# motion state for Delita(5) + Ovelia(12): is a slide still in flight at the beat?
	for uid in [5, 12]:
		var a = _vm.peek_actor(uid)
		if a == null: continue
		var m = a.get("motion")
		if m == null:
			print("  MOTION U%d: none (settled)  home=%s" % [uid, str(a.get("home"))])
		else:
			print("  MOTION U%d: ACTIVE start=%s target=%s dur=%.3f elapsed=%.3f done=%s home=%s" % [
				uid, str(m.get("start")), str(m.get("target")), m.get("dur_s"),
				m.get("elapsed_s"), str(m.is_done()), str(a.get("home"))])

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer"):
		(n as CanvasLayer).visible = false
	if n is ColorRect and (n.name == "FadeRect" or n.name == "OxideRect"):
		(n as ColorRect).color = Color((n as ColorRect).color.r, (n as ColorRect).color.g, (n as ColorRect).color.b, 0.0)
	var nm := String(n.name)
	var spath := ""
	var scr = n.get_script()
	if scr != null and scr.has_method("get_path"): spath = String(scr.resource_path)
	if ("visible" in n) and (nm.contains("Grid") or nm.contains("Compass") or nm.contains("Overlay") \
			or spath.to_lower().contains("grid") or spath.to_lower().contains("compass")):
		n.set("visible", false)
	for c in n.get_children(): _hide_overlays(c)

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			# SEG env forces the EVTCHR cinematic segment for ALL cinematic units
			# (A/B seg 0 vs seg 1). Set BEFORE the rewind playthrough applies the
			# carry anims so the walker arms with this segment. -1 = use resolver.
			if OS.has_environment("SEG"):
				_vm.cinematic_segment_override = int(OS.get_environment("SEG"))
				print("[cab] cinematic_segment_override = %d" % _vm.cinematic_segment_override)
		return
	if not _reported and _vm.get_pc() >= _pc and _vm.get("_paused"):
		_reported = true
		# Override the ortho camera size AFTER the director has settled it.
		if _cam_size > 0.0:
			var cam := _cam()
			if cam != null: cam.size = _cam_size
		_on_ready_report()
		# If forcing a segment, re-arm the last cinematic anim (Ovelia's PC202 510
		# for this beat) at the parked frame so the render reflects SEG even if the
		# override landed after the rewind consumed it.
		if OS.has_environment("SEG") and _vm.has_method("reapply_last_cinematic"):
			print("[cab] reapply_last_cinematic -> %s" % str(_vm.reapply_last_cinematic()))
		_hide_overlays(_scene)
		var ubid2 = _vm.get("units_by_id")
		if OS.has_environment("SETTLE_MOTIONS"):
			# Force any in-flight Sprite Move to its target so the captured frame is
			# the SETTLED beat (drops the 1-frame capture-phase; matches PSX savestate).
			for uid in [5, 12]:
				var a = _vm.peek_actor(uid)
				if a == null: continue
				var m = a.get("motion")
				if m != null and ubid2.has(uid) and is_instance_valid(ubid2[uid]):
					ubid2[uid].global_position = m.get("target")
					a.set("motion", null)
					print("  SETTLED U%d -> %s" % [uid, str(m.get("target"))])
		if OS.has_environment("ONLY_UID"):
			var keep := int(OS.get_environment("ONLY_UID"))
			for k in ubid2.keys():
				if k != keep and ubid2[k] != null and is_instance_valid(ubid2[k]):
					var m = ubid2[k].get("mesh_instance")
					if m != null and is_instance_valid(m): m.visible = false
		if OS.has_environment("BRIGHT"):
			# Full-brightness, REAL palette (kills map-darkness confound; keeps the
			# unit's own SPR colors so the rendered sprite can be color-diffed vs PSX CLUT).
			for uid in [5, 12, 6]:
				var uu = ubid2.get(uid)
				if uu != null and is_instance_valid(uu):
					var mm = uu.get("material")
					if mm != null: mm.set_shader_parameter("ambient_brightness", 1.0)
		elif not OS.has_environment("NORECOLOR"):
			_flat(ubid2.get(12), Vector3(1, 0, 1))
			_flat(ubid2.get(5),  Vector3(0, 1, 0))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_shot)
		print("[cab] shot -> %s (pc=%d)" % [_shot, _vm.get_pc()])
		_done = true
	elif _f > 4000 and not _reported:
		print("[cab] TIMEOUT never parked at pc=%d (pc=%d paused=%s)" % [_pc, _vm.get_pc(), str(_vm.get("_paused"))])
		_done = true

func _flat(u, col: Vector3) -> void:
	if u == null or not is_instance_valid(u): return
	var mat = u.get("material")
	if mat == null: return
	mat.set_shader_parameter("unit_tint_scale", Vector3(0, 0, 0))
	mat.set_shader_parameter("unit_tint_bias", col)
	mat.set_shader_parameter("unit_tint", Vector3(0, 0, 0))
	mat.set_shader_parameter("ambient_brightness", 1.0)

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
