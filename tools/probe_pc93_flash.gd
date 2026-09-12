extends Node
## Scenario 29 pc 93 one-frame unit-flash probe — SCENE-HOSTED (a Node in a
## .tscn run as the main scene), NOT a `-s` SceneTree script. A `-s` custom
## MainLoop renders a DIFFERENT frame than the real main scene and has shown a
## clean picture through a real defect, so the pixels must come from here.
##
## Boots scenario 29 LIVE from pc 0 (no rewind: `set_rewind_target` forces
## `play_through_skip_unknown`, which clamps every motion to `play_through_max_ticks`
## and would fabricate the very timing symptom under investigation), auto-advancing
## the boxed dialogue, and records EVERY FRAME in [FROM_PC, TO_PC]:
## pc, and per unit — visible, world pos, tile, 256x240 screen pos, anim id.
##
##   # from the package root
##   FROM_PC=66 TO_PC=103 godot --path . res://tools/probe_pc93_flash.tscn 2>&1 | tee /tmp/f.log
##
## Env: SCEN=29 FROM_PC=66 TO_PC=103 MAXF=8000 SHOT_DIR=<dir> (per-frame PNGs)

var _scene: Node
var _vm: Node
var _f := 0
var _from := 66
var _to := 103
var _maxf := 8000
var _shot_dir := ""
var _shot_n := 0
var _armed := false
var _done := false
var _last_pc := -1

func _ready() -> void:
	var scen := 29
	if OS.has_environment("SCEN"): scen = int(OS.get_environment("SCEN"))
	if OS.has_environment("FROM_PC"): _from = int(OS.get_environment("FROM_PC"))
	if OS.has_environment("TO_PC"): _to = int(OS.get_environment("TO_PC"))
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("SHOT_DIR"): _shot_dir = OS.get_environment("SHOT_DIR")
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	var sess: Node = get_tree().root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = scen
	else:
		push_error("[flash] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[flash] booting scenario %d, trace pc %d..%d shots=%s" % [scen, _from, _to, _shot_dir])

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null

func _on_post_draw() -> void:
	_f += 1
	if _done:
		return
	if _f > _maxf:
		print("[flash] FRAME CAP at f=%d" % _f)
		_finish()
		return
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			# Auto-advance the boxed dialogue so the run is unattended. This only
			# shifts WHEN pc 67 starts; it cannot reorder 93..101 against itself.
			_vm.dialog_auto_advance = true
			print("[flash] VM found at f=%d" % _f)
		return
	_vm.dialog_auto_advance = true
	var pc: int = _vm.get_pc()
	if pc != _last_pc:
		print("[flash] f=%d PC -> %d" % [_f, pc])
		_last_pc = pc
	if pc < _from:
		return
	_armed = true
	_dump(pc)
	if _shot_dir != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/f%04d_pc%03d.png" % [_shot_dir, _shot_n, pc])
		_shot_n += 1
	if pc >= _to:
		print("[flash] reached TO_PC=%d at f=%d" % [_to, _f])
		_finish()

func _finish() -> void:
	_done = true
	get_tree().quit.call_deferred()

func _dump(pc: int) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var vp := get_viewport().get_visible_rect().size
	var parts: Array[String] = []
	var uids: Array = _vm.units_by_id.keys()
	uids.sort()
	for uid in uids:
		var u: Node = _vm.units_by_id[uid]
		if u == null or not is_instance_valid(u) or not (u is Node3D):
			continue
		var n3 := u as Node3D
		var p: Vector3 = n3.global_position
		var scr := "----,----"
		if cam != null and not cam.is_position_behind(p):
			var s: Vector2 = cam.unproject_position(p)
			scr = "%6.1f,%6.1f" % [s.x / vp.x * 256.0, s.y / vp.y * 240.0]
		var anim := -1
		if "display" in u and u.display != null:
			anim = int(u.display.current_anim_id)
		parts.append("u%02d[%s vis=%d pos=(%7.3f,%6.3f,%7.3f) scr=(%s) anim=0x%X]" % [
			uid, "V" if n3.visible else "-", 1 if n3.visible else 0,
			p.x, p.y, p.z, scr, anim])
	print("[flash] F f=%d pc=%d %s" % [_f, pc, " ".join(parts)])
