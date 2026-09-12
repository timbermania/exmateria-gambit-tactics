extends SceneTree
## [Godot sync-frame A/B capture] Free-run counterpart to /tmp/psx_ab_capture.lua.
## Fast-plays scenario 6 to START_PC, releases into real-time free-run, and — mirroring
## the PSX capture — saves a 256x256 native-res screenshot on EVERY anim-id transition
## of Delita(5)/Ovelia(12)/chocobo(6). The two columns then self-align by anim triple
## (no vsync->PC mapping needed; the anim-id transition IS the shared sync anchor).
##
## Renders the REAL sprites (no recolor) so the visual A/B shows pose/facing/flip/camera.
## Overlays (fade/oxide/grid) are hidden once at release so the frame is clean.
##
## Run (NEVER headless), from the package root:
##   START_PC=130 STOP_PC=234 MAX_TICKS=360 OUTDIR=/tmp/sxs2/godot \
##     godot --path . -s res://tools/capture_carry_sync_ab.gd
var _scene: Node
var _vm: Node
var _f := 0
var _start_pc := 130
var _stop_pc := 234
var _max_ticks := 360
var _outdir := "/tmp/sxs2/godot"
var _done := false
var _released := false
var _released_tick := -1
var _idx := 0
var _prev := {5: -1, 12: -1, 6: -1}
var _manifest: Array = []
var _capturing := false

const UIDS := [5, 12, 6]

func _initialize() -> void:
	if OS.has_environment("START_PC"): _start_pc = int(OS.get_environment("START_PC"))
	if OS.has_environment("STOP_PC"): _stop_pc = int(OS.get_environment("STOP_PC"))
	if OS.has_environment("MAX_TICKS"): _max_ticks = int(OS.get_environment("MAX_TICKS"))
	if OS.has_environment("OUTDIR"): _outdir = OS.get_environment("OUTDIR")
	DirAccess.make_dir_recursive_absolute(_outdir)
	root.content_scale_size = Vector2i(256, 256)
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _start_pc
	else:
		push_error("[sab] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[sab] booting scn6, fast-play to pc=%d then free-run to pc=%d (max %d ticks), out=%s" % [
		_start_pc, _stop_pc, _max_ticks, _outdir])

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

func _anim(uid: int) -> int:
	var ubid = _vm.get("units_by_id")
	if ubid != null and ubid.has(uid) and is_instance_valid(ubid[uid]):
		return int(ubid[uid].current_anim_id)
	return -1

func _capture(t: int) -> void:
	var a5 := _anim(5); var a12 := _anim(12); var a6 := _anim(6)
	_idx += 1
	var name := "%s/godot_%02d_t%03d_d%d_o%d_c%d.png" % [_outdir, _idx, t, a5, a12, a6]
	root.get_texture().get_image().save_png(name)
	# screen positions of the three units (native px), for the compositor
	var s5 := Vector2(-1,-1); var s12 := Vector2(-1,-1); var s6 := Vector2(-1,-1)
	var ubid = _vm.get("units_by_id")
	if ubid != null:
		if ubid.has(5) and is_instance_valid(ubid[5]): s5 = _screen_of(ubid[5])
		if ubid.has(12) and is_instance_valid(ubid[12]): s12 = _screen_of(ubid[12])
		if ubid.has(6) and is_instance_valid(ubid[6]): s6 = _screen_of(ubid[6])
	_manifest.append("%d,%d,%d,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [
		_idx, t, a5, a12, a6, s5.x, s5.y, s12.x, s12.y, s6.x, s6.y])
	print("[sab] beat %02d t=%d d=%d o=%d c=%d -> %s" % [_idx, t, a5, a12, a6, name])

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	if not _released:
		if _vm.get_pc() >= _start_pc and _vm.get("_paused") and not _vm.is_fast_playing():
			_released = true
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			_hide_overlays(_scene)
			_vm.set("_paused", false)
			_released_tick = int(_vm.get("_vm_tick"))
			print("[sab] released at pc=%d vm_tick=%d f=%d; capturing..." % [_vm.get_pc(), _released_tick, _f])
		elif _f > 6000:
			print("[sab] TIMEOUT never parked at start (pc=%d)" % _vm.get_pc())
			_done = true
		return
	# free-run: detect anim-id transition of any of the three anchor units
	var t := int(_vm.get("_vm_tick"))
	var a5 := _anim(5); var a12 := _anim(12); var a6 := _anim(6)
	var changed: bool = (a5 != int(_prev[5])) or (a12 != int(_prev[12])) or (a6 != int(_prev[6]))
	_prev[5] = a5; _prev[12] = a12; _prev[6] = a6
	if changed and not _capturing:
		_capturing = true
		_capture(t)
		_capturing = false
	if _vm.get_pc() >= _stop_pc or (t - _released_tick) >= _max_ticks:
		_write_manifest()
		_done = true

func _write_manifest() -> void:
	var f := FileAccess.open(_outdir + "/manifest.csv", FileAccess.WRITE)
	if f == null:
		push_error("[sab] cannot write manifest")
		return
	f.store_line("idx,tick,a5,a12,a6,sp5x,sp5y,sp12x,sp12y,sp6x,sp6y")
	for r in _manifest: f.store_line(r)
	f.close()
	print("[sab] wrote %d beats + manifest -> %s" % [_idx, _outdir])

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
