extends SceneTree
## Force Ovelia (uid 0x0C)'s global_reversion=true at PC=316 and screenshot the
## tableau, to confirm that flipping her un-mirrors the carry pose to match PSX.
## Saves A (as-shipped) and B (Ovelia flipped) crops.
## Run: OUT=/tmp godot --path . -s res://tools/probe_scenario6_ovelia_flip.gd

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _rewound := false
var _settle_at := -1
var _pc := 316
var _stage := 0
var _out := "/tmp"

func _initialize() -> void:
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
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
	if _settle_at < 0:
		if paused == true: _settle_at = _f
		return
	if _f < _settle_at + 40:
		_hide_overlays(_scene); return
	match _stage:
		0:
			_capture("A_shipped"); _stage = 1
		1:
			var ub = _vm.get("units_by_id")
			var ov = ub.get(0x0C)
			if ov != null:
				var m: ShaderMaterial = ov.get("material")
				if m != null: m.set_shader_parameter("global_reversion", true)
			_stage = 2
		2:
			_capture("B_ovelia_flipped"); _quit = true

func _capture(tag: String) -> void:
	_hide_overlays(_scene)
	var img := root.get_texture().get_image()
	var w := img.get_width(); var h := img.get_height()
	var crop := img.get_region(Rect2i(int(w*0.55), int(h*0.40), int(w*0.43), int(h*0.52)))
	crop.save_png("%s/ovflip_%s.png" % [_out, tag])
	print("[ovflip] saved %s (%dx%d full)" % [tag, w, h])

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
