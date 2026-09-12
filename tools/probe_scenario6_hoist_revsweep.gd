extends SceneTree
## At PC 219, render 4 reversion variants of the carry pair and crop each, to see
## which produces the tight PSX single-silhouette carry (Ovelia on Delita's
## shoulder) vs the separated-sprites bug.
##   A shipped        (Delita rev=false, Ovelia rev=true)  <- current
##   B ovelia_false   (Delita rev=false, Ovelia rev=false)
##   C both_true      (Delita rev=true,  Ovelia rev=true)
##   D delita_true    (Delita rev=true,  Ovelia rev=false)
## Run: godot --path . -s res://tools/probe_scenario6_hoist_revsweep.gd  (NOT headless)

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _rewound := false
var _settle_at := -1
var _pc := 219
var _stage := 0
var _variants := [
	["A_shipped", false, true],
	["B_ovelia_false", false, false],
	["C_both_true", true, true],
	["D_delita_true", true, false],
]

func _initialize() -> void:
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null: sess.selected_scenario_id = 6
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)

func _process(_d: float) -> bool:
	if _quit: quit(); return true
	return false

func _set_rev(uid: int, v: bool) -> void:
	var ub = _vm.get("units_by_id")
	var u = ub.get(uid)
	if u == null: return
	var m: ShaderMaterial = u.get("material")
	if m != null: m.set_shader_parameter("global_reversion", v)

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
	if _settle_at < 0:
		if paused == true: _settle_at = _f
		return
	if _f < _settle_at + 40:
		_hide_overlays(_scene); return
	if _stage >= _variants.size():
		_quit = true; return
	var v = _variants[_stage]
	_set_rev(0x05, v[1]); _set_rev(0x0C, v[2])
	# let the shader param apply for one extra frame before capture
	_hide_overlays(_scene)
	_capture(v[0])
	_stage += 1

func _capture(tag: String) -> void:
	var img := root.get_texture().get_image()
	var w := img.get_width(); var h := img.get_height()
	var crop := img.get_region(Rect2i(int(w*0.28), int(h*0.20), int(w*0.44), int(h*0.60)))
	crop.save_png("/tmp/hoistrev_%s.png" % tag)
	print("[revsweep] saved /tmp/hoistrev_%s.png" % tag)

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer" or n.name == "DialogueOverlay"):
		(n as CanvasLayer).visible = false
	if n is ColorRect and (n.name == "FadeRect" or n.name == "OxideRect"):
		(n as ColorRect).color = Color((n as ColorRect).color.r, (n as ColorRect).color.g, (n as ColorRect).color.b, 0.0)
	for c in n.get_children():
		_hide_overlays(c)

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
