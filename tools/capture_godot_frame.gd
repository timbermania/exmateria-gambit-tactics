extends SceneTree
## Color-calibration capture: boot a scenario, halt on the first SETTLED dialogue
## box, force PSX dither OFF, and screenshot. Pairs with the PSX-side
## research/scripts/color_calibration/capture_psx.py for a frame-matched compare.
##
## Grab happens on RenderingServer.frame_post_draw (a -s viewport grab read
## mid-_process is blank), a few frames AFTER the box stops typing so open-tweens
## and palette fades settle. Screenshot is the whole 1280x960 (4:3, PAR baked in).
##
## Run (NOT headless):
##   # from the package root
##   godot --path . -s res://tools/capture_godot_frame.gd
## Env:
##   SCEN=2                         scenario id (default 2 = Orbonne chapel)
##   SHOT=/tmp/godot_cal.png        output PNG
##   MATCH=alright                  capture the box whose text CONTAINS this
##                                  (case-insensitive); empty = first settled box.
##                                  With MATCH set, dialogue auto-advances until
##                                  the target box, then freezes on it.
##   SETTLE=20                      frames to wait after the box settles
##   MAXF=2600                      safety cap: capture anyway at this frame

var _scene: Node
var _vm: Node
var _f := 0
var _settled_at := -1
var _did := false
var _quit := false
var _shot := "/tmp/godot_cal.png"
var _match := ""
var _settle := 20
var _maxf := 2600

func _initialize() -> void:
	_shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else _shot
	if OS.has_environment("MATCH"):
		_match = OS.get_environment("MATCH").to_lower()
	if OS.has_environment("SETTLE"):
		_settle = int(OS.get_environment("SETTLE"))
	if OS.has_environment("MAXF"):
		_maxf = int(OS.get_environment("MAXF"))
	var scen := 2
	if OS.has_environment("SCEN"):
		scen = int(OS.get_environment("SCEN"))
	# Autoload globals aren't registered as identifiers in a -s mainloop script;
	# reach the singleton as a node instead.
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = scen
	else:
		push_error("[cal] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	# Dither OFF for calibration (both sides run dither-off; compare also downsamples).
	RenderingServer.global_shader_parameter_set("psx_dither_enabled", false)
	print("[cal] booting scenario %d, dither OFF, shot -> %s" % [scen, _shot])

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
			# No target text: hold on the first box. With a target: let dialogue
			# auto-advance until we reach the matching box, then freeze on it.
			_vm.dialog_auto_advance = _match != ""
			print("[cal] VM found at f=%d (match=\"%s\")" % [_f, _match])
			# Optional A/B: PERVERTEX=0 forces the old per-pixel lighting path so
			# the dark-band artifact can be captured at the exact calibrated beat.
			# Applied here (well before the grab) so the uniform is live on capture.
			if OS.has_environment("PERVERTEX"):
				var pv := OS.get_environment("PERVERTEX") != "0"
				var n := 0
				for m in _collect_map_mats(_scene):
					m.set_shader_parameter("lighting_per_vertex", pv)
					n += 1
				print("[cal] lighting_per_vertex=%s on %d map mats" % [str(pv), n])

	var box: Node = null
	var settled: bool = false
	if _vm != null and _vm.box_pool != null:
		box = _vm.box_pool._foreground_box()
		settled = box != null and box.is_open() and not box.is_typing()
		if settled and _settled_at < 0:
			var txt := ""
			if "_text" in box and box._text != null:
				txt = str(box._text.text)
			var is_target: bool = _match == "" or _match in txt.to_lower()
			if is_target:
				_settled_at = _f
				_vm.dialog_auto_advance = false  # freeze on the target box
				print("[cal] target box settled at f=%d: \"%s\"" % [_f, txt])

	if _f % 120 == 0:
		var bs := "none"
		if box != null:
			bs = "open=%s typing=%s" % [str(box.is_open()), str(box.is_typing())]
		print("[cal] f=%d vm=%s box=%s settled_at=%d" % [
			_f, str(_vm != null), bs, _settled_at])

	# Terminal capture — reachable even if the VM/box is never found (MAXF).
	var ready: bool = (_settled_at >= 0 and _f >= _settled_at + _settle) or (_f >= _maxf)
	if ready and not _did:
		_did = true
		_capture(box)
		_quit = true

func _capture(box: Node) -> void:
	var img := root.get_texture().get_image()
	img.save_png(_shot)
	var vp := root.get_viewport().get_visible_rect().size
	var txt := ""
	if box != null and "_text" in box and box._text != null:
		txt = str(box._text.text)
	print("[cal] ===== CAPTURED f=%d viewport=%s =====" % [_f, str(vp)])
	print("[cal] shot -> %s" % _shot)
	print("[cal] box_text=\"%s\"" % txt)
	print("[cal] units=%d settled_at=%d" % [_vm.units_by_id.size(), _settled_at])
	_probe_unit_mats(_scene)

func _probe_unit_mats(n: Node, seen: Dictionary = {}) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var mat := mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.get_active_material(0)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
			var sp := (mat as ShaderMaterial).shader.resource_path
			if sp.findn("unit") >= 0:
				var ab = (mat as ShaderMaterial).get_shader_parameter("ambient_brightness")
				var key := "%s|%s" % [sp, str(ab)]
				if not seen.has(key):
					seen[key] = true
					print("[probe] node=%s shader=%s ambient_brightness=%s" % [n.name, sp, str(ab)])
	for c in n.get_children():
		_probe_unit_mats(c, seen)

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
	# Duck-type, not `is ScenarioVM`: the VM is instantiated via preload().new()
	# (ScenarioPlayerScene.gd:248), whose script identity doesn't match the global
	# class_name, so `is` returns false.
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
