extends SceneTree
## A/B the map "dark band": capture the normal render + diffuse-only under both
## lighting_per_vertex=false (old per-pixel path, reproduces the band) and =true
## (faithful PSX per-vertex Gouraud). Same beat as capture_map_lighting_debug.gd.
##
## Run (NOT headless), from the package root:
##   godot --path . -s res://tools/capture_band_ab.gd
## Env: SCEN=2  OUT=/tmp/band_ab  WAIT=520

var _scene: Node
var _vm: Node
var _f := 0
var _mats: Array = []
# (per_vertex, debug_mode, tag)
var _steps := [
	[false, 0, "pp_normal"],
	[true, 0, "pv_normal"],
	[false, 4, "pp_diffuse"],
	[true, 4, "pv_diffuse"],
]
var _i := -1
var _shot_at := -1
var _quit := false
var _out := "/tmp/band_ab"
var _wait := 520

func _initialize() -> void:
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	if OS.has_environment("WAIT"): _wait = int(OS.get_environment("WAIT"))
	var scen := 2
	if OS.has_environment("SCEN"): scen = int(OS.get_environment("SCEN"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null: sess.selected_scenario_id = scen
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[band_ab] booting scenario %d" % scen)

func _process(_delta: float) -> bool:
	if _quit:
		quit(); return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		return
	if _f < _wait:
		return
	if _i < 0:
		_mats = _collect(_scene)
		_kill_overlays()
		print("[band_ab] map materials=%d, starting at f=%d" % [_mats.size(), _f])
		_i = 0
		_apply(_steps[0])
		_shot_at = _f
		return
	if _f >= _shot_at + 5:
		var step: Array = _steps[_i]
		var path := "%s_%s.png" % [_out, step[2]]
		root.get_texture().get_image().save_png(path)
		print("[band_ab] %s -> %s" % [step[2], path])
		_i += 1
		if _i >= _steps.size():
			_quit = true
			return
		_apply(_steps[_i])
		_shot_at = _f

func _apply(step: Array) -> void:
	for m in _mats:
		m.set_shader_parameter("lighting_per_vertex", step[0])
		m.set_shader_parameter("map_light_debug", step[1])
		m.set_shader_parameter("map_light_boost", 1.0)

func _kill_overlays() -> void:
	for prop in ["oxide_rect", "fade_rect", "oxide_layer"]:
		if prop in _vm and _vm.get(prop) != null:
			var n = _vm.get(prop)
			if n is CanvasItem:
				n.visible = false

func _collect(n: Node, acc: Array = []) -> Array:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var mat := mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.get_active_material(0)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
				and (mat as ShaderMaterial).shader.resource_path.findn("indexed_color") >= 0:
			acc.append(mat)
	for c in n.get_children():
		_collect(c, acc)
	return acc

func _find_vm(nn: Node) -> Node:
	if ("box_pool" in nn) and ("units_by_id" in nn) and ("map_composer" in nn):
		return nn
	for c in nn.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
