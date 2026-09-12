extends SceneTree
## [DEBUG-wall9] THROWAWAY diag for the scn6 knockback "Ovelia vs wall" question.
## Captures are OFFSET-TRIGGERED (not frame/anim) so they match the PSX offset
## field exactly. At each target it logs both units' gp/home/off/screen/camdist,
## and RAYCASTS camera->Ovelia's screen pixel against the map's visual geometry to
## find the primitive at her pixel + its camera distance (nearer => it occludes
## her; farther => she should draw in front). Overlays hidden for a lit capture.
##   MAXF=2100 SHOTDIR=/tmp/sxs godot --path . -s res://tools/probe_ovelia_wall_diag.gd
var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 2100
var _shotdir := "/tmp/sxs"
var _added_collider := false
# targets: label -> Ovelia world offset from home (matched to PSX o=X,+Z,+Y field)
var _targets := [
	{"name":"pre",   "off":Vector3(0.0,   0.050, -0.143), "tol":0.045, "done":false},  # PSX o=0,0,4
	{"name":"knock", "off":Vector3(-0.143, 0.179, -0.571), "tol":0.055, "done":false},  # PSX o=-4,-5,16
	{"name":"lift",  "off":Vector3(0.143,  0.036, -0.821), "tol":0.060, "done":false},  # PSX o=4,-1,23
]

func _initialize() -> void:
	if OS.has_environment("SHOTDIR"): _shotdir = OS.get_environment("SHOTDIR")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null: sess.selected_scenario_id = 6
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[DEBUG-wall9] booting scn6 (offset-triggered capture)")

func _process(_delta: float) -> bool:
	if _quit: quit(); return true
	return false

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n): return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer"):
		(n as CanvasLayer).visible = false
	if n is ColorRect and (n.name == "FadeRect" or n.name == "OxideRect"):
		(n as ColorRect).color = Color((n as ColorRect).color.r, (n as ColorRect).color.g, (n as ColorRect).color.b, 0.0)
	if n.name == "MapGridOverlay" and ("visible" in n): n.visible = false
	for c in n.get_children(): _hide_overlays(c)

func _gp(u) -> Vector3:
	var mesh = u.get("mesh_instance")
	if mesh != null and is_instance_valid(mesh): return mesh.global_position
	return Vector3.ZERO

func _home(uid: int) -> Vector3:
	var la = _vm.peek_actor(uid)
	if la != null and la.get("has_home"): return la.get("home")
	return Vector3.ZERO

func _unit_str(uid: int, cam) -> String:
	var u = _vm.units_by_id[uid]
	var gp := _gp(u)
	var home := _home(uid)
	var scr: Vector2 = cam.unproject_position(gp)
	return "U%d anim=%d gp=(%.3f,%.3f,%.3f) off=(%.3f,%.3f,%.3f) screen=(%d,%d) camdist=%.3f" % [
		uid, u.current_anim_id, gp.x,gp.y,gp.z, gp.x-home.x,gp.y-home.y,gp.z-home.z,
		int(scr.x),int(scr.y), cam.global_position.distance_to(gp)]

func _raycast_wall(cam, screen: Vector2, ov_gp: Vector3) -> String:
	var space = _scene.get_world_3d().direct_space_state
	var o: Vector3 = cam.project_ray_origin(screen)
	var d: Vector3 = cam.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 300.0)
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty(): return "wall-ray: NO HIT"
	var hp: Vector3 = hit["position"]
	var wall_dist: float = cam.global_position.distance_to(hp)
	var ov_dist: float = cam.global_position.distance_to(ov_gp)
	var rel := "FARTHER-than-Ovelia (she should be IN FRONT)" if wall_dist > ov_dist else "NEARER-than-Ovelia (it occludes her)"
	return "wall-ray HIT (%.2f,%.2f,%.2f) camdist=%.3f  vs Ovelia camdist=%.3f  => wall is %s (Δ=%.3f)" % [
		hp.x,hp.y,hp.z, wall_dist, ov_dist, rel, wall_dist-ov_dist]

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	if not _added_collider and _vm.map_composer != null and _vm.map_composer.geometry_mesh != null:
		_vm.map_composer.geometry_mesh.create_trimesh_collision()
		_added_collider = true
		print("[DEBUG-wall9] added trimesh collider to map geometry_mesh")
	if not _vm.units_by_id.has(12):
		if _f >= _maxf: _quit = true
		return
	var cam = _vm._active_camera()
	if cam == null: return
	var ov = _vm.units_by_id[12]
	var off := _gp(ov) - _home(12)
	for t in _targets:
		if t["done"]: continue
		var tv: Vector3 = t["off"]
		if abs(off.x-tv.x) <= t["tol"] and abs(off.y-tv.y) <= t["tol"] and abs(off.z-tv.z) <= t["tol"]:
			t["done"] = true
			_hide_overlays(_scene)
			await RenderingServer.frame_post_draw
			print("[DEBUG-wall9] === TARGET %s  f=%d pc=%d ===" % [t["name"], _f, _vm.get_pc()])
			print("[DEBUG-wall9]   " + _unit_str(5, cam))
			print("[DEBUG-wall9]   " + _unit_str(12, cam))
			var ov_gp := _gp(ov)
			var ov_scr: Vector2 = cam.unproject_position(ov_gp)
			print("[DEBUG-wall9]   " + _raycast_wall(cam, ov_scr, ov_gp))
			var img := root.get_texture().get_image()
			img.save_png("%s/m_%s.png" % [_shotdir, t["name"]])
			print("[DEBUG-wall9]   shot -> %s/m_%s.png" % [_shotdir, t["name"]])
	var all_done := true
	for t in _targets:
		if not t["done"]: all_done = false
	if (all_done or _f >= _maxf) and not _quit:
		print("[DEBUG-wall9] FINAL f=%d pc=%d" % [_f, _vm.get_pc()])
		_quit = true
