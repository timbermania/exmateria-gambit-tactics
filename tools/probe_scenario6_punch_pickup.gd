extends SceneTree
## [Punch/pickup trajectory probe] Boots scenario 6, auto-advances, and logs the
## PC193-231 beat (Delita punches Ovelia -> knocks her back -> picks her up ->
## throws her over his shoulder -> turns to walk down the stairs). For units 5
## (Delita) and 12 (Ovelia) it logs, on ANY change of (pc | rounded world pos |
## anim | palette-row), a compact one-line record so we can diff the Godot
## trajectory against the PSX ground truth (offset triple in the living doc).
##
## Run (NOT headless):
##   # from the package root
##   MAXF=3200 godot --path . -s res://tools/probe_scenario6_punch_pickup.gd
## Env: MAXF (frame cap, default 3200), SHOTS (comma frames to PNG-capture,
##      default "none"), SHOTDIR (default /tmp).

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 3200
var _watch := [5, 12]
var _last := {}
var _shots := []
var _shotdir := "/tmp"
var _shot_done := {}

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("SHOTDIR"): _shotdir = OS.get_environment("SHOTDIR")
	if OS.has_environment("SHOTS") and OS.get_environment("SHOTS") != "none":
		for s in OS.get_environment("SHOTS").split(","):
			_shots.append(int(s))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[probe] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[probe] booting scenario 6 (maxf=%d) shots=%s" % [_maxf, str(_shots)])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _pal_desc(u) -> String:
	var mat = u.get("material")
	if mat == null: return "<nomat>"
	var pal = mat.get_shader_parameter("type1_palette")
	var row = mat.get_shader_parameter("body_palette_row")
	var tex = mat.get_shader_parameter("type1_tex")
	var palname := "<null>"
	if pal != null and pal is Texture2D:
		palname = (pal as Texture2D).resource_path.get_file()
	var texname := "<null>"
	if tex != null and tex is Texture2D:
		var tp := (tex as Texture2D).resource_path.get_file()
		texname = tp if tp != "" else "<runtime>"
	return "pal=%s row=%s tex=%s" % [palname, str(row), texname]

func _sig(uid: int, u) -> String:
	var aid: int = u.current_anim_id
	var la = _vm.peek_actor(uid)
	var walker := la != null and la.get("walker") != null
	var mesh = u.get("mesh_instance")
	var gp := Vector3.ZERO
	if mesh != null and is_instance_valid(mesh):
		gp = mesh.global_position
	# Track the captured home + resulting sprite-move offset (gp - home). This is
	# the quantity to A/B against the PSX offset triple +0x60/62/64. `has_home`
	# tells us whether the actor has ever captured (Vector3.ZERO is a legal home).
	var home := Vector3.ZERO
	var has_home := false
	if la != null:
		home = la.get("home")
		has_home = la.get("has_home")
	var off := gp - home
	return "pc=%d gp=(%.2f,%.2f,%.2f) home=(%.2f,%.2f,%.2f)%s off=(%.2f,%.2f,%.2f) anim=%d(0x%X) walk=%s vis=%s %s" % [
		_vm.get_pc(), gp.x, gp.y, gp.z, home.x, home.y, home.z,
		"" if has_home else "?", off.x, off.y, off.z,
		aid, aid, str(walker), str(u.visible), _pal_desc(u)]

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			print("[probe] VM found f=%d, auto-advance + skip-unknown ON" % _f)
		return

	var ubid = _vm.get("units_by_id")
	if ubid != null:
		for uid in _watch:
			if not ubid.has(uid): continue
			var u = ubid[uid]
			if u == null or not is_instance_valid(u): continue
			# only log inside the beat window (pc 190..235) to stay compact
			var pc: int = _vm.get_pc()
			if pc < 188 or pc > 236: continue
			var sig := _sig(uid, u)
			var key := "u%d" % uid
			# strip the pc for the change-signature so we log on state change,
			# but include gp so motion is captured
			if _last.get(key, "") != sig:
				_last[key] = sig
				print("  U%-2d f=%-4d %s" % [uid, _f, sig])

	for sf in _shots:
		if not _shot_done.get(sf, false) and _f >= sf:
			_shot_done[sf] = true
			_hide_overlays(_scene)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var p := "%s/punch_f%d.png" % [_shotdir, sf]
			img.save_png(p)
			print("[probe] shot -> %s (pc=%d)" % [p, _vm.get_pc()])

	var done := false
	if _vm.has_method("is_finished"): done = _vm.is_finished()
	var ff = _vm.get("_finished")
	if ff != null and ff: done = true
	if (done or _f >= _maxf) and not _quit:
		print("[probe] ===== FINAL f=%d done=%s pc=%d =====" % [_f, str(done), _vm.get_pc()])
		_quit = true

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer"):
		(n as CanvasLayer).visible = false
	if n is ColorRect:
		var cr := n as ColorRect
		if cr.name == "FadeRect" or cr.name == "OxideRect":
			cr.color = Color(cr.color.r, cr.color.g, cr.color.b, 0.0)
	# hide the debug tile-grid overlay (MapGridOverlay) so captures match PSX
	if n is Node3D and ("MapGridOverlay" in str(n.get_script())):
		(n as Node3D).visible = false
	if n.name == "MapGridOverlay":
		if "visible" in n: n.visible = false
	for c in n.get_children():
		_hide_overlays(c)

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
