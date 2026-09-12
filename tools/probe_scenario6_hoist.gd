extends SceneTree
## Rewind scenario-6 ScenarioVM to the HOIST beat (PC 219) and dump the carry
## pair (Delita uid 0x05, Ovelia uid 0x0C): world/mesh origin, anim id, facing,
## depth_center_height, global_reversion, and the carry-pose Y offset. Also
## captures a screenshot so we can eyeball the two-separated-sprites gap vs the
## PSX single-hoist silhouette (reference-assets/scenario6_carry_hoist_pc219.sstate).
##
## Run: godot --path . -s res://tools/probe_scenario6_hoist.gd   (NOT headless)

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _rewound := false
var _settle_at := -1
var _pc := 219

func _initialize() -> void:
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null: sess.selected_scenario_id = 6
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _process(_d: float) -> bool:
	if _quit: quit(); return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null: _vm.dialog_auto_advance = false
		return
	if not _rewound:
		if _vm.has_method("set_rewind_target"):
			_vm.set_rewind_target(_pc); _rewound = true
		return
	var paused = _vm.get("paused")
	var ff = _vm.get("_ff_active")
	if _settle_at < 0:
		if (paused == true) and (ff == false or ff == null):
			_settle_at = _f
		return
	if _f < _settle_at + 40:
		_hide_overlays(_scene); return
	_dump()
	_hide_overlays(_scene)
	var img := root.get_texture().get_image()
	var w := img.get_width(); var h := img.get_height()
	img.save_png("/tmp/hoist_pc%d_full.png" % _pc)
	var crop := img.get_region(Rect2i(int(w*0.28), int(h*0.20), int(w*0.44), int(h*0.60)))
	crop.save_png("/tmp/hoist_pc%d_crop.png" % _pc)
	print("[hoist] screenshot -> /tmp/hoist_pc%d_full.png (+crop) (%dx%d)" % [_pc, w, h])
	_quit = true

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer" or n.name == "DialogueOverlay"):
		(n as CanvasLayer).visible = false
	if n is ColorRect and (n.name == "FadeRect" or n.name == "OxideRect"):
		(n as ColorRect).color = Color((n as ColorRect).color.r, (n as ColorRect).color.g, (n as ColorRect).color.b, 0.0)
	for c in n.get_children():
		_hide_overlays(c)

func _dump() -> void:
	var ubid = _vm.get("units_by_id")
	print("\n[hoist] ============ SCENARIO-6 HOIST DUMP @ PC=%d ============" % _pc)
	var cur_pc = _vm.get("pc") if ("pc" in _vm) else _vm.get("_pc")
	print("[hoist] vm reports pc=%s" % str(cur_pc))
	for k in [0x05, 0x0C, 0x8B]:
		if not ubid.has(k):
			print("[hoist] uid=0x%02X  <not in units_by_id>" % k)
			continue
		var u = ubid[k]
		if u == null or not is_instance_valid(u):
			print("[hoist] uid=0x%02X  <invalid>" % k)
			continue
		var mat: ShaderMaterial = u.get("material")
		var aid = u.get("current_anim_id")
		var fa = u.get("facing_angle")
		var gp = u.global_position if ("global_position" in u) else Vector3.ZERO
		var mm = u.global_transform if u is Node3D else Transform3D()
		var origin = mm.origin
		var dch = mat.get_shader_parameter("depth_center_height") if mat != null else null
		var gr = mat.get_shader_parameter("global_reversion") if mat != null else null
		var uf = mat.get_shader_parameter("ot_unit_forward") if mat != null else null
		var slm = u.get("sprite_layers")
		print("[hoist] uid=0x%02X '%s' visible=%s" % [int(k), u.name, str(u.visible)])
		print("[hoist]     anim=0x%03X facing=0x%03X" % [int(aid) if aid != null else -1, (int(fa) & 0xFFF) if fa != null else -1])
		print("[hoist]     global_pos=%s  origin=%s" % [str(gp), str(origin)])
		print("[hoist]     depth_center_height=%s global_reversion=%s unit_forward=%s" % [str(dch), str(gr), str(uf)])
		# carry-pose Y offset / sprite layer state
		if slm != null:
			var so = slm.get("sprite_offset") if ("sprite_offset" in slm) else null
			var ao = slm.get("anim_offset") if ("anim_offset" in slm) else null
			print("[hoist]     slm.sprite_offset=%s slm.anim_offset=%s apply_reversion=%s" % [str(so), str(ao), str(slm.get("apply_reversion"))])
	print("[hoist] ======================================================\n")

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
