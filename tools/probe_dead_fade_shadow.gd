extends SceneTree
## DIAGNOSTIC (shadow-outlives-corpse investigation): boot scenario 6, let the
## {43} Call Function 4 dead-unit fade sweep fire naturally at instr 7, and log
## per-frame what the faded unit's SPRITE and its SHADOW are each doing.
##
## Run (headful, never --headless):
##   godot --path . -s res://tools/probe_dead_fade_shadow.gd
##
## Env: SHOTDIR=/tmp/deadfade  MAXF=600
var _scene: Node
var _vm: Node
var _f := 0
var _sweep_f := -1
var _quit := false
var _shotdir := "/tmp/deadfade"
var _maxf := 600
var _shot_offsets := [0, 4, 8, 16, 24, 32, 40, 44, 60, 90, 150]
var _shots_done := {}

func _initialize() -> void:
	if OS.has_environment("SHOTDIR"): _shotdir = OS.get_environment("SHOTDIR")
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	DirAccess.make_dir_recursive_absolute(_shotdir)
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[deadfade] booting scenario 6, shots -> %s" % _shotdir)

func _process(_d: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		return
	var fades: Dictionary = _vm._dead_unit_fades if "_dead_unit_fades" in _vm else {}
	if _sweep_f < 0 and not fades.is_empty():
		_sweep_f = _f
		print("[deadfade] SWEEP armed at f=%d on %d unit(s)" % [_f, fades.size()])
	if _sweep_f >= 0:
		var off := _f - _sweep_f
		_log_targets(off, fades)
		if off in _shot_offsets and not _shots_done.has(off):
			_shots_done[off] = true
			root.get_texture().get_image().save_png("%s/f%03d.png" % [_shotdir, off])
	if _f >= _maxf or (_sweep_f >= 0 and _f - _sweep_f > 200):
		_quit = true

func _log_targets(off: int, fades: Dictionary) -> void:
	for uid in _vm.units_by_id:
		var u = _vm.units_by_id[uid]
		if u == null or not is_instance_valid(u) or not (u is Node3D):
			continue
		var tc := int(u.scenario_team_color) if "scenario_team_color" in u else 0
		if tc == 0:
			continue
		var sm: Node3D = u.get_node_or_null("ShadowMesh")
		var mat = u.get("material")
		var bias := "?"
		if mat is ShaderMaterial:
			var b = mat.get_shader_parameter("unit_tint_bias")
			var s = mat.get_shader_parameter("unit_tint_scale")
			bias = "scale=%s bias=%s shader=%s" % [str(s), str(b), str(mat.shader.resource_path).get_file()]
		print("[deadfade] off=%3d uid=%s unit.visible=%s in_tree=%s | shadow.visible=%s shadow.in_tree=%s layer=%s | phase=%s %s" % [
			off, str(uid), str(u.visible), str(u.is_visible_in_tree()),
			str(sm.visible) if sm != null else "n/a",
			str(sm.is_visible_in_tree()) if sm != null else "n/a",
			str(sm.render_layer != null) if (sm != null and "render_layer" in sm) else "n/a",
			str(fades.get(int(uid), "-")), bias])

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
