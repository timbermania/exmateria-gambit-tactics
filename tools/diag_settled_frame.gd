extends SceneTree
## Ground-truth the SETTLED chapel pose (PC48 camera, pre-dialog) against the PSX
## framebuffer. Captures a screenshot AFTER frame_post_draw (the -s viewport grab
## is blank if read mid-_process) and dumps, for every spawned unit, its world
## position AND its on-screen projection (Camera3D.unproject_position) so we can
## measure exactly where each figure lands vs the PSX frame.
##
## Run (NOT headless):
##   godot --path . -s res://tools/diag_settled_frame.gd
## Env: SHOT=/tmp/godot_settled.png  CAP_FRAME=720  (frame to grab on)

var _scene: Node
var _vm: Node
var _f := 0
var _settle_x := 840         # PC48 cleanup camera X marks the settled pose
var _settled_at := -1
var _max_frame := 2600
var _shot := "/tmp/godot_settled.png"
var _did := false
var _quit := false

func _initialize() -> void:
	_shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else _shot
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null and (OS.has_environment("OFFX") or OS.has_environment("OFFY") or OS.has_environment("OFFZ")):
			_vm.camera_position_offset = Vector3(
				float(OS.get_environment("OFFX")) if OS.has_environment("OFFX") else _vm.camera_position_offset.x,
				float(OS.get_environment("OFFY")) if OS.has_environment("OFFY") else _vm.camera_position_offset.y,
				float(OS.get_environment("OFFZ")) if OS.has_environment("OFFZ") else _vm.camera_position_offset.z)
			print("[diag] OVERRODE offset -> %s" % str(_vm.camera_position_offset))
		return
	var cam = _vm.player_camera
	var ortho: float = cam.camera.size if (cam and cam.camera) else 0.0
	var bx: float = cam.global_position.x if cam else 0.0
	# Settled pose = swoop done: body has arrived (x≈8.5) AND zoom widened to the
	# settled ortho (~8.3). The fusion queue sets the x=840 TARGET immediately, so
	# detect the BODY arriving, not the target param.
	if _settled_at < 0 and ortho >= 8.2 and bx < 9.5:
		_settled_at = _f
		print("[diag] settled pose reached at f=%d (body.x=%.2f ortho=%.2f)" % [_f, bx, ortho])
	if _f % 180 == 0:
		print("[diag] f=%d units=%d body.x=%.2f ortho=%.2f settled_at=%d" % [
			_f, _vm.units_by_id.size(), bx, ortho, _settled_at])
	# Capture 90 frames after settling (let dialog + units settle), or at the
	# safety cap if we never detect it.
	var ready := (_settled_at >= 0 and _f >= _settled_at + 90) or (_f >= _max_frame)
	if ready and not _did:
		_did = true
		_capture()
		_quit = true

func _capture() -> void:
	var img := root.get_texture().get_image()
	img.save_png(_shot)
	var vp := root.get_viewport().get_visible_rect().size
	print("[diag] ===== SETTLED FRAME f=%d =====" % _f)
	print("[diag] shot -> %s  viewport=%s" % [_shot, str(vp)])
	if _vm == null:
		return
	var cam = _vm.player_camera
	var cam3d = cam.camera if cam else null
	if cam:
		print("[diag] camera body global_position=%s" % str(cam.global_position))
		print("[diag] focus rot(deg)=%s ortho=%.3f" % [
			str(cam.focus_point.global_rotation * 57.2958),
			cam3d.size if cam3d else -1.0])
	print("[diag] last_camera_params=%s" % str(_vm._last_camera_params))
	print("[diag] map_size_z=%d" % _vm.map_size_z)
	# Screen-center world point: project the camera body (== focus point == C).
	if cam3d:
		print("[diag] center proj of body = %s (expect ~viewport/2)" % str(cam3d.unproject_position(cam.global_position)))
	# Per-unit: world pos + screen projection.
	for uid in _vm.units_by_id.keys():
		var u = _vm.units_by_id[uid]
		if u == null:
			continue
		var wp: Vector3 = u.global_position
		var sp := Vector2(-1, -1)
		var behind := false
		if cam3d:
			sp = cam3d.unproject_position(wp)
			behind = cam3d.is_position_behind(wp)
		print("[diag] unit 0x%02X (%d) world=%s screen=%s behind=%s vis=%s" % [
			int(uid), int(uid), str(wp), str(sp), str(behind),
			str(u.visible) if "visible" in u else "?"])

func _find_vm(n: Node) -> Node:
	if n.has_method("reapply_last_camera") and "camera_backrotate_pivot" in n:
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
