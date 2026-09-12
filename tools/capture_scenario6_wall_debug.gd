extends SceneTree
## [DEBUG-wall6] Scenario-6 back-of-castle dark-wall probe. Boots scenario 6,
## halts on the "let go" box (the back-of-castle beat), then DUMPS every map
## material's field_tint / ambient / light params and screenshots. Optional
## MAPDBG=<0-5> forces map_light_debug on all map mats before the grab so the
## ambient-only (3) / albedo-only (5) contributions can be isolated.
##
## Run (NOT headless):
##   # from the package root
##   MAPDBG=0 SHOT=/tmp/wall6_normal.png godot --path . -s res://tools/capture_scenario6_wall_debug.gd
## Env: SHOT (png), MATCH (box text, default "let go"), SETTLE, MAXF, MAPDBG.

var _scene: Node
var _vm: Node
var _f := 0
var _settled_at := -1
var _did := false
var _quit := false
var _shot := "/tmp/wall6.png"
var _match := "let go"
var _settle := 20
var _maxf := 3000
var _mapdbg := -1
var _last_box_txt := ""
var _last_ft_sig := ""

func _initialize() -> void:
	_shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else _shot
	if OS.has_environment("MATCH"):
		_match = OS.get_environment("MATCH").to_lower()
	if OS.has_environment("SETTLE"):
		_settle = int(OS.get_environment("SETTLE"))
	if OS.has_environment("MAXF"):
		_maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("MAPDBG"):
		_mapdbg = int(OS.get_environment("MAPDBG"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[wall6] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	RenderingServer.global_shader_parameter_set("psx_dither_enabled", false)
	print("[wall6] booting scenario 6, match=\"%s\" mapdbg=%d shot -> %s" % [_match, _mapdbg, _shot])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = OS.get_environment("AUTOADV") != "0" if OS.has_environment("AUTOADV") else (_match != "")
			_vm.play_through_skip_unknown = OS.get_environment("SKIP") == "1"
			print("[wall6] VM found at f=%d (autoadv=%s skip=%s)" % [_f, str(_vm.dialog_auto_advance), str(_vm.play_through_skip_unknown)])

	# Log field-tint + map-mat tint transitions so we can see the prayer
	# arm/restore sequence and whether the MAP stays darkened.
	if _vm != null:
		var ft = _vm.get("_field_tint")
		var fs := "identity"
		if ft != null:
			fs = "scale=%s bias=%s" % [str(ft.scale), str(ft.bias)]
		var mats := _collect_map_mats(_scene)
		var msc = mats[0].get_shader_parameter("field_tint_scale") if mats.size() > 0 else null
		var sig := "%s|%s" % [fs, str(msc)]
		if sig != _last_ft_sig:
			_last_ft_sig = sig
			print("[wall6] f=%d FIELD_TINT %s  map_mat.field_tint_scale=%s" % [_f, fs, str(msc)])

	var box: Node = null
	var settled: bool = false
	if _vm != null and _vm.box_pool != null:
		box = _vm.box_pool._foreground_box()
		settled = box != null and box.is_open() and not box.is_typing()
		if settled and _settled_at < 0:
			var txt := ""
			if "_text" in box and box._text != null:
				txt = str(box._text.text)
			# Log EVERY distinct settled box so we can see the dialogue sequence.
			if txt != _last_box_txt:
				_last_box_txt = txt
				print("[wall6] BOX f=%d: \"%s\"" % [_f, txt])
			var is_target: bool = _match == "" or _match in txt.to_lower()
			if is_target:
				_settled_at = _f
				_vm.dialog_auto_advance = false
				print("[wall6] target box settled at f=%d: \"%s\"" % [_f, txt])

	if _f % 120 == 0:
		print("[wall6] f=%d vm=%s settled_at=%d" % [_f, str(_vm != null), _settled_at])

	var ready: bool = (_settled_at >= 0 and _f >= _settled_at + _settle) or (_f >= _maxf)
	if ready and not _did:
		_did = true
		_dump_and_capture()
		_quit = true

func _dump_and_capture() -> void:
	var mats := _collect_map_mats(_scene)
	print("[wall6] ===== map materials: %d =====" % mats.size())
	var seen := {}
	for m in mats:
		var sc = m.get_shader_parameter("field_tint_scale")
		var bi = m.get_shader_parameter("field_tint_bias")
		var amb = m.get_shader_parameter("ambient_light")
		var l1 = m.get_shader_parameter("light1_color")
		var l2 = m.get_shader_parameter("light2_color")
		var l3 = m.get_shader_parameter("light3_color")
		var mt = m.get_shader_parameter("map_tint")
		var key := str(amb) + str(sc)
		if seen.has(key):
			continue
		seen[key] = true
		print("[wall6]   field_tint_scale=%s bias=%s" % [str(sc), str(bi)])
		print("[wall6]   ambient=%s map_tint=%s" % [str(amb), str(mt)])
		print("[wall6]   light1=%s light2=%s light3=%s" % [str(l1), str(l2), str(l3)])
	if _mapdbg >= 0:
		for m in mats:
			m.set_shader_parameter("map_light_debug", _mapdbg)
		print("[wall6] set map_light_debug=%d on %d mats; forcing a redraw" % [_mapdbg, mats.size()])
		# force another frame so the debug uniform takes on the grab
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_shot)
	print("[wall6] ===== CAPTURED f=%d shot -> %s =====" % [_f, _shot])

func _collect_map_mats(n: Node, acc: Array = []) -> Array:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var mat := mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.get_active_material(0)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
				and (mat as ShaderMaterial).shader.resource_path.findn("indexed_color") >= 0:
			acc.append(mat)
	for c in n.get_children():
		_collect_map_mats(c, acc)
	return acc

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
