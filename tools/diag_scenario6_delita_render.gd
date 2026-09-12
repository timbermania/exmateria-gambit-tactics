extends SceneTree
## [Delita render diagnostic] Boots scenario 6, auto-advances the abduction
## cutscene, and — every time unit 5 (Delita) or unit 12 (Ovelia) changes its
## body animation — dumps the FULL live render state so we can see WHY Delita
## isn't drawing:
##   - is the unit node present in units_by_id, and is it .visible
##   - is the UnitMesh present + visible + where in world it sits
##   - body_sprite_id (which SPR is assigned)
##   - current_anim_id + whether a CinematicWalkState walker is armed
##   - the BODY (type1) texture actually bound to the shader: resource_path +
##     size  → tells us SPR atlas vs EVTCHR segment_NNN.tga vs null
##   - type1_palette path/size + body_palette_row
##   - the atlas source rects / sizes / dest locs (== the UV mapping): first
##     few blocks, or "<EMPTY>" if nothing is being sampled (→ transparent)
##
## Run (NOT headless):
##   # from the package root
##   MAXF=3000 SHOT=/tmp/delita_render.png godot --path . -s res://tools/diag_scenario6_delita_render.gd
## Env: MAXF (frame cap, default 3000), SHOT (png at SHOTF), SHOTF (frame to
## grab the shot at, default = MAXF), WATCH (comma uids, default "5,12").

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 3000
var _shot := ""
var _shotf := -1
var _watch := [5, 12]
var _last := {}    # uid -> last dumped signature
var _seen := {}    # uid -> has it ever been in units_by_id
var _shot_done := false

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	_shotf = _maxf
	if OS.has_environment("SHOTF"): _shotf = int(OS.get_environment("SHOTF"))
	if OS.has_environment("WATCH"):
		_watch = []
		for s in OS.get_environment("WATCH").split(","):
			_watch.append(int(s))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[diag] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[diag] booting scenario 6 (maxf=%d, shotf=%d) watching uids %s" % [_maxf, _shotf, str(_watch)])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _tex_desc(t) -> String:
	if t == null:
		return "<null>"
	if not (t is Texture2D):
		return "<%s>" % [str(t)]
	var tex := t as Texture2D
	var p := tex.resource_path
	if p == "":
		p = "<runtime, no path>"
	return "%s size=%s" % [p, str(tex.get_size())]

func _arr_head(a, n: int) -> String:
	if a == null:
		return "<null>"
	if not (a is Array):
		return "<%s>" % str(a)
	var arr := a as Array
	if arr.size() == 0:
		return "<EMPTY (0 blocks → nothing sampled)>"
	var head := []
	for i in range(min(n, arr.size())):
		head.append(arr[i])
	return "n=%d %s" % [arr.size(), str(head)]

func _dump_unit(uid: int, u) -> void:
	var mesh = u.get("mesh_instance")
	var mat = u.get("material")
	var aid: int = u.current_anim_id
	var la = _vm.peek_actor(uid)
	var has_walker := la != null and la.get("walker") != null

	print("──────── uid=%d  f=%d ────────" % [uid, _f])
	print("  unit.visible=%s  body_sprite_id=0x%02X  anim_id=%d (0x%X)  walker=%s" % [
		str(u.visible), u.body_sprite_id, aid, aid, str(has_walker)])
	if mesh != null and is_instance_valid(mesh):
		print("  UnitMesh: visible=%s  visible_in_tree=%s  gpos=%s  has_mesh=%s" % [
			str(mesh.visible), str(mesh.is_visible_in_tree()),
			str(mesh.global_position), str(mesh.mesh != null)])
	else:
		print("  UnitMesh: <MISSING>")
	if mat != null:
		var surf_mat = null
		if mesh != null and is_instance_valid(mesh) and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
			surf_mat = mesh.mesh.surface_get_material(0)
		print("  material==surface_mat? %s" % [str(surf_mat == mat)])
		print("  type1_tex     : %s" % _tex_desc(mat.get_shader_parameter("type1_tex")))
		print("  type1_tex_size: %s" % str(mat.get_shader_parameter("type1_tex_size")))
		print("  type1_palette : %s" % _tex_desc(mat.get_shader_parameter("type1_palette")))
		print("  body_palette_row: %s" % str(mat.get_shader_parameter("body_palette_row")))
		print("  type1_rects     (atlas src XY): %s" % _arr_head(mat.get_shader_parameter("type1_rects"), 4))
		print("  type1_rect_sizes(WxH)        : %s" % _arr_head(mat.get_shader_parameter("type1_rect_sizes"), 4))
		print("  type1_locs      (dest XY)    : %s" % _arr_head(mat.get_shader_parameter("type1_locs"), 4))
	else:
		print("  material: <null>")

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			# Enabling play-through now RE-ARMS `_running` on the OFF->ON edge (the
			# setter fix), so even if the VM autostarted in _ready and already
			# halted on some later unhandled opcode, flipping this on resumes it —
			# no manual force-resume hack needed. `Call Function` (0x43) no longer
			# halts at all (it has a loud, non-halting stub now), so scn6 reaches
			# Delita's Draw at pc=88 in normal play.
			_vm.play_through_skip_unknown = true
			print("[diag] VM found at f=%d, auto-advance ON, skip-unknown ON (setter re-arms _running)" % _f)
		return

	var ubid = _vm.get("units_by_id")
	if ubid != null:
		for uid in _watch:
			if not ubid.has(uid):
				if _seen.get(uid, false) and _last.get(uid, "") != "GONE":
					_last[uid] = "GONE"
					print("[diag] f=%d uid=%d  <<< no longer in units_by_id (removed) >>>" % [_f, uid])
				continue
			_seen[uid] = true
			var u = ubid[uid]
			if u == null or not is_instance_valid(u): continue
			var aid: int = u.current_anim_id
			var la = _vm.peek_actor(uid)
			var has_walker := la != null and la.get("walker") != null
			var sig := "%d|%s|%s" % [aid, str(has_walker), str(u.visible)]
			if _last.get(uid, "") != sig:
				_last[uid] = sig
				_dump_unit(uid, u)

	if _shot != "" and not _shot_done and _f >= _shotf:
		_shot_done = true
		_hide_overlays(_scene)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(_shot)
		print("[diag] captured -> %s (f=%d)" % [_shot, _f])

	var done := false
	if _vm.has_method("is_finished"):
		done = _vm.is_finished()
	var ff = _vm.get("_finished")
	if ff != null and ff: done = true
	if (done or _f >= _maxf) and not _quit:
		print("[diag] ===== FINAL f=%d done=%s =====" % [_f, str(done)])
		_quit = true

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer"):
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
