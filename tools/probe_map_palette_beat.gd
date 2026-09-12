extends SceneTree
## Dump the MAP palette (base CLUT + {33} field-tint affine + composed final),
## the {2E} background gradient, and a screenshot at a parked scenario beat.
## Sibling of capture_scenario_beat.gd — for PSX-parity palette diffs.
##
## Run (headful; stdout/log return to you):
##   # from the package root
##   SCEN=4 TARGET_PC=49 SHOT=/tmp/pace/palette_diff/godot_beat.png \
##     godot --path . -s res://tools/probe_map_palette_beat.gd
##
## Env: SCEN, TARGET_PC, SHOT, SETTLE, MAXF, PALPNG(out palette png), DUMP(json out)

var _scene: Node
var _vm: Node
var _f := 0
var _frozen_at := -1
var _did := false
var _quit := false
var _shot := "/tmp/pace/palette_diff/godot_beat.png"
var _palpng := "/tmp/pace/palette_diff/godot_map_palette.png"
var _dump := "/tmp/pace/palette_diff/godot_palette_dump.json"
var _target_pc := 49
var _rewind_sent := false
var _settle := 90
var _maxf := 4000

func _initialize() -> void:
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	if OS.has_environment("PALPNG"): _palpng = OS.get_environment("PALPNG")
	if OS.has_environment("DUMP"): _dump = OS.get_environment("DUMP")
	if OS.has_environment("TARGET_PC"): _target_pc = int(OS.get_environment("TARGET_PC"))
	if OS.has_environment("SETTLE"): _settle = int(OS.get_environment("SETTLE"))
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	var scen := 4
	if OS.has_environment("SCEN"): scen = int(OS.get_environment("SCEN"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = scen
	else:
		push_error("[pal] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	RenderingServer.global_shader_parameter_set("psx_dither_enabled", false)
	print("[pal] booting scenario %d, target_pc=%d" % [scen, _target_pc])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		return
	if not _rewind_sent:
		if _vm.is_fast_playing():
			pass
		else:
			_vm.dialog_auto_advance = false
			_vm.set_rewind_target(_target_pc)
			if _vm.is_fast_playing() or _vm.get_pc() >= _target_pc:
				_rewind_sent = true
				print("[pal] rewind → pc=%d at f=%d" % [_target_pc, _f])
		return
	if _frozen_at < 0:
		if not _vm.is_fast_playing() and _vm.get_pc() >= _target_pc:
			_frozen_at = _f
			_vm.dialog_auto_advance = false
			print("[pal] halted at pc=%d f=%d" % [_vm.get_pc(), _f])
	# hide grid/compass overlays every settle frame (idempotent) so they're gone
	# well before the grab — for a clean terrain-hue comparison.
	if _frozen_at >= 0:
		_hide_overlays()
	if _f % 120 == 0:
		print("[pal] f=%d ff=%s pc=%d" % [_f, str(_vm.is_fast_playing()), _vm.get_pc()])
	var ready: bool = (_frozen_at >= 0 and _f >= _frozen_at + _settle) or (_f >= _maxf)
	if ready and not _did:
		_did = true
		_capture()
		_quit = true

func _c8(x: float) -> int:
	return clampi(int(round(x * 255.0)), 0, 255)

# RGB (0-255) -> BGR555 16-bit hex, matching PSX VRAM word layout (STP bit unset).
func _bgr555(r: int, g: int, b: int) -> int:
	return ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3)

func _hide_overlays() -> void:
	# compass: the scene exposes show_compass; flip it.
	if "show_compass" in _scene:
		_scene.show_compass = false
	# grid + compass layers + any MapGridOverlay: recursively hide.
	_hide_recursive(_scene)
	_hide_recursive(root)

func _hide_recursive(n: Node) -> void:
	for c in n.get_children():
		var cn := c.get_class()
		var nm := str(c.name)
		if cn == "MapGridOverlay" or nm.findn("grid") >= 0 or nm.findn("compass") >= 0:
			if c is CanvasItem: (c as CanvasItem).visible = false
			elif c is Node3D: (c as Node3D).visible = false
			elif c is CanvasLayer: (c as CanvasLayer).visible = false
		_hide_recursive(c)

func _log_applied_lighting() -> void:
	var mc: Node = _vm.map_composer
	if mc == null or not ("manifest_data" in mc): return
	var lt = mc.manifest_data.get("lighting", {})
	if typeof(lt) == TYPE_DICTIONARY and not lt.is_empty():
		var amb = lt.get("ambient", {})
		print("[pal] APPLIED map lighting: ambient=(%s,%s,%s)" % [str(amb.get("r")), str(amb.get("g")), str(amb.get("b"))])
		var dl = lt.get("directional_lights", [])
		for i in range(dl.size()):
			var col = dl[i].get("color", {})
			print("[pal]   dir_light[%d] color=(%s,%s,%s)" % [i, str(col.get("r")), str(col.get("g")), str(col.get("b"))])
		var grad = lt.get("gradient", {})
		if typeof(grad) == TYPE_DICTIONARY:
			print("[pal]   sky gradient top=%s bottom=%s" % [str(grad.get("top")), str(grad.get("bottom"))])
	else:
		print("[pal] APPLIED map lighting: <default / none in manifest_data>")

func _capture() -> void:
	_log_applied_lighting()
	var img := root.get_texture().get_image()
	img.save_png(_shot)
	print("[pal] ===== CAPTURED f=%d =====" % _f)

	var out := {}
	var mc: Node = _vm.map_composer
	print("[pal] scenario map_composer=%s" % (str(mc) if mc != null else "NULL"))

	# --- {33} field tint affine (applied as shader uniform on top of base CLUT) ---
	var ts := Vector3(1,1,1)
	var tb := Vector3(0,0,0)
	if "_field_tint" in _vm and _vm._field_tint != null:
		ts = _vm._field_tint.scale
		tb = _vm._field_tint.bias
	out["field_tint_scale"] = [ts.x, ts.y, ts.z]
	out["field_tint_bias"] = [tb.x, tb.y, tb.z]
	print("[pal] {33} field_tint scale=(%.4f,%.4f,%.4f) bias=(%.4f,%.4f,%.4f)" % [ts.x,ts.y,ts.z, tb.x,tb.y,tb.z])

	# --- {2E} background gradient ---
	if "_background" in _vm and _vm._background != null:
		var top: Vector3 = _vm._background.top
		var bot: Vector3 = _vm._background.bottom
		out["bg_top_rgb"] = [_c8(top.x), _c8(top.y), _c8(top.z)]
		out["bg_bottom_rgb"] = [_c8(bot.x), _c8(bot.y), _c8(bot.z)]
		print("[pal] {2E} background top RGB=(%d,%d,%d) bottom RGB=(%d,%d,%d)" % [
			_c8(top.x),_c8(top.y),_c8(top.z), _c8(bot.x),_c8(bot.y),_c8(bot.z)])
	else:
		print("[pal] {2E} background: none active (null)")

	# --- map palette: base CLUT + composed final ---
	if mc != null and mc.palette_texture != null:
		var pimg: Image = mc.palette_texture.get_image()
		pimg.save_png(_palpng)
		var w := pimg.get_width()
		var h := pimg.get_height()
		print("[pal] palette_texture %dx%d saved -> %s" % [w, h, _palpng])
		var base_rows := []
		var final_rows := []
		var nrows: int = mini(h, 16)  # base palettes rows 0-15
		for row in range(nrows):
			var base_cells := []
			var final_cells := []
			for col in range(mini(w, 16)):
				var px := pimg.get_pixel(col, row)
				var br := _c8(px.r); var bg := _c8(px.g); var bb := _c8(px.b)
				base_cells.append(_bgr555(br, bg, bb))
				# compose with field tint the way indexed_color.gdshader does:
				# final = clamp(base*scale + bias, 0, 1)
				var fr := clampf(px.r * ts.x + tb.x, 0.0, 1.0)
				var fg := clampf(px.g * ts.y + tb.y, 0.0, 1.0)
				var fb := clampf(px.b * ts.z + tb.z, 0.0, 1.0)
				final_cells.append(_bgr555(_c8(fr), _c8(fg), _c8(fb)))
			base_rows.append(base_cells)
			final_rows.append(final_cells)
		out["base_palette_bgr555"] = base_rows
		out["final_palette_bgr555"] = final_rows
		print("[pal] --- base palette (BGR555, rows 0-15) ---")
		for row in range(nrows):
			var s := ""
			for c in base_rows[row]: s += "%04X " % c
			print("  base%2d: %s" % [row, s])
		print("[pal] --- FINAL palette = base*scale+bias (BGR555) ---")
		for row in range(nrows):
			var s := ""
			for c in final_rows[row]: s += "%04X " % c
			print("  fin %2d: %s" % [row, s])
	else:
		print("[pal] map palette_texture: NULL")

	var jf := FileAccess.open(_dump, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(out, "  "))
		jf.close()
		print("[pal] json dump -> %s" % _dump)

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
