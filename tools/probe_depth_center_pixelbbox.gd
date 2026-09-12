extends SceneTree
## Diagnose the depth-center heuristic for the scenario-6 chocobo (uid 0x8B).
## Rewinds to PC 316 (beside-chocobo carry), then for the carry pair + chocobo
## reads back the LIVE TYPE1 shader arrays (rects/rect_sizes/locs) and the bound
## atlas image, and computes TWO candidate centers:
##   (A) piece-rectangle bbox center   (current heuristic, from location_y+height)
##   (B) NON-TRANSPARENT PIXEL bbox center (proposed: scan atlas index!=0)
## for both the vertical (loc_y) and horizontal (loc_x) axes, and the resulting
## depth_center_height each would produce. No edits — pure measurement.
##
## Run: godot --path . -s res://tools/probe_depth_center_pixelbbox.gd  (NOT headless)

const DEPTH_CENTER_DIV := 32.0
const DEPTH_CENTER_BIAS := 0.0625

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _rewound := false
var _settle_at := -1
var _pc := 316
var _img_cache := {}

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
	if _settle_at >= 0 and _f == _settle_at + 1:
		var dc := root.get_node_or_null("/root/DebugConfig")
		if dc != null: dc.set("show_depth_center", true)
	if _f < _settle_at + 40:
		_hide_overlays(_scene)
		return
	_dump()
	_hide_overlays(_scene)
	var img := root.get_texture().get_image()
	var w := img.get_width(); var h := img.get_height()
	img.save_png("/tmp/dch_pc%d_marker.png" % _pc)
	print("[dch] screenshot -> /tmp/dch_pc%d_marker.png (%dx%d)" % [_pc, w, h])
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
	print("\n[dch] ======== DEPTH-CENTER PIXEL-BBOX DIAG @ PC=%d ========" % _pc)
	for k in [0x05, 0x0C, 0x8B]:
		if not ubid.has(k):
			print("[dch] uid=0x%02X <absent>" % k); continue
		var u = ubid[k]
		if u == null or not is_instance_valid(u):
			print("[dch] uid=0x%02X <invalid>" % k); continue
		var mat: ShaderMaterial = u.get("material")
		if mat == null:
			print("[dch] uid=0x%02X <no material>" % k); continue
		var aid = u.get("current_anim_id")
		var rects = mat.get_shader_parameter("type1_rects")
		var sizes = mat.get_shader_parameter("type1_rect_sizes")
		var locs = mat.get_shader_parameter("type1_locs")
		var live_dch = mat.get_shader_parameter("depth_center_height")
		var tex = mat.get_shader_parameter("type1_tex") as Texture2D
		print("[dch] uid=0x%02X '%s' anim=0x%03X live_dch=%s atlas=%s" % [
			int(k), u.name, int(aid) if aid != null else -1, str(live_dch),
			tex.resource_path.get_file() if tex != null else "<none>"])
		if rects == null or sizes == null or locs == null:
			print("[dch]     <no tile arrays>"); continue

		# (A) piece-rectangle bbox
		var a_top := INF
		var a_bot := -INF
		var a_left := INF
		var a_right := -INF
		var n_tiles := 0
		for i in range(sizes.size()):
			if sizes[i].x <= 0.0: continue
			n_tiles += 1
			a_top = min(a_top, locs[i].y)
			a_bot = max(a_bot, locs[i].y + sizes[i].y)
			a_left = min(a_left, locs[i].x)
			a_right = max(a_right, locs[i].x + sizes[i].x)
		var a_cy := (a_top + a_bot) * 0.5
		var a_cx := (a_left + a_right) * 0.5

		# (B) non-transparent pixel bbox
		var img := _get_image(tex)
		var b_top := INF
		var b_bot := -INF
		var b_left := INF
		var b_right := -INF
		var visible_px := 0
		if img != null:
			var iw := img.get_width()
			var ih := img.get_height()
			for i in range(sizes.size()):
				if sizes[i].x <= 0.0: continue
				var rx := int(rects[i].x)
				var ry := int(rects[i].y)
				var w := int(sizes[i].x)
				var h := int(sizes[i].y)
				for py in range(h):
					var ay := ry + py
					if ay < 0 or ay >= ih: continue
					for px in range(w):
						var ax := rx + px
						if ax < 0 or ax >= iw: continue
						var c := img.get_pixel(ax, ay)
						# BODY layer atlas is indexed-grayscale: idx = round(r*15),
						# idx 0 == transparent (shader convention). Fall back to
						# alpha for pre-baked RGBA atlases.
						var idx := int(c.r * 15.0 + 0.5)
						var opaque := (idx != 0) if c.a > 0.5 else false
						if not opaque: continue
						visible_px += 1
						var lx := float(locs[i].x) + float(px)
						var ly := float(locs[i].y) + float(py)
						b_top = min(b_top, ly)
						b_bot = max(b_bot, ly + 1.0)
						b_left = min(b_left, lx)
						b_right = max(b_right, lx + 1.0)
		var b_cy: float = (b_top + b_bot) * 0.5 if visible_px > 0 else a_cy
		var b_cx: float = (b_left + b_right) * 0.5 if visible_px > 0 else a_cx

		var a_height := DEPTH_CENTER_BIAS - a_cy / DEPTH_CENTER_DIV
		var b_height := DEPTH_CENTER_BIAS - b_cy / DEPTH_CENTER_DIV
		print("[dch]   tiles=%d visible_px=%d" % [n_tiles, visible_px])
		print("[dch]   (A) piece-rect:  loc_y[%.1f..%.1f] cy=%.2f cx=%.2f -> dch=%.4f" % [a_top, a_bot, a_cy, a_cx, a_height])
		print("[dch]   (B) pixel-bbox:  loc_y[%.1f..%.1f] cy=%.2f cx=%.2f -> dch=%.4f" % [b_top, b_bot, b_cy, b_cx, b_height])
		print("[dch]   delta cy=%.2f  delta dch=%.4f" % [b_cy - a_cy, b_height - a_height])
	print("[dch] ======================================================\n")

func _get_image(tex: Texture2D) -> Image:
	if tex == null: return null
	var key := tex.resource_path
	if _img_cache.has(key): return _img_cache[key]
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	_img_cache[key] = img
	return img

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
