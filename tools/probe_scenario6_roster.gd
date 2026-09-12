extends SceneTree
## [RE-SCOPE probe, 0x47 Add Ghost Unit] Boots scenario 6, auto-advances the
## whole abduction cutscene, and logs the live actor roster (units_by_id: uid,
## visible, tile/world pos) at every distinct dialogue box + periodically. Goal:
## answer whether Godot's ORDINARY units (esp. unit 5 = Delita) render/animate
## through the abduction, or the back-of-castle courtyard is empty — the
## re-scope check in research/working_documents/ADD_GHOST_UNIT_OPCODE_47.md §7.
##
## Run (NOT headless):
##   # from the package root
##   SHOT=/tmp/s6_tableau.png MAXF=6000 godot --path . -s res://tools/probe_scenario6_roster.gd
## Env: SHOT (final png), MAXF (frame cap), SETTLE (frames after last box).

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _shot := "/tmp/s6_tableau.png"
var _maxf := 6000
var _last_box_txt := ""
var _box_count := 0
var _seen_uids := {}          # uid -> bool ever-visible
var _last_box_frame := -1
var _match := ""              # if set, capture when a box text contains this
var _matched_at := -1
var _settle := 24

func _initialize() -> void:
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("MATCH"): _match = OS.get_environment("MATCH").to_lower()
	if OS.has_environment("SETTLE"): _settle = int(OS.get_environment("SETTLE"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[s6probe] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[s6probe] booting scenario 6 -> %s (maxf=%d)" % [_shot, _maxf])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _roster_line() -> String:
	if _vm == null: return "(no vm)"
	var ubid = _vm.get("units_by_id")
	if ubid == null: return "(no units_by_id)"
	var parts := []
	var keys: Array = ubid.keys()
	keys.sort()
	for uid in keys:
		var u = ubid[uid]
		if u == null or not is_instance_valid(u):
			parts.append("0x%02X=FREED" % uid)
			continue
		var vis = u.visible
		if vis: _seen_uids[uid] = true
		var p = u.global_position
		parts.append("0x%02X[%s @%.1f,%.1f,%.1f]" % [uid, ("V" if vis else "-"), p.x, p.y, p.z])
	return " ".join(parts)

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			print("[s6probe] VM found at f=%d, auto-advance ON" % _f)
		return

	# Log each distinct settled dialogue box + the roster at that beat.
	var box = null
	if _vm.box_pool != null:
		box = _vm.box_pool._foreground_box()
	if box != null and box.is_open() and not box.is_typing():
		var txt := ""
		if "_text" in box and box._text != null:
			txt = str(box._text.text)
		if txt != _last_box_txt and txt.strip_edges() != "":
			_last_box_txt = txt
			_box_count += 1
			_last_box_frame = _f
			print("[s6probe] BOX #%d f=%d: \"%s\"" % [_box_count, _f, txt])
			print("[s6probe]   roster: %s" % _roster_line())
			if _match != "" and _matched_at < 0 and _match in txt.to_lower():
				_matched_at = _f
				_vm.dialog_auto_advance = false
				print("[s6probe] MATCH box at f=%d — holding for capture" % _f)

	if _f % 300 == 0:
		print("[s6probe] f=%d boxes=%d roster: %s" % [_f, _box_count, _roster_line()])

	# End when the scenario reports done, or the frame cap hits.
	var done := false
	if _vm.has_method("is_finished"):
		done = _vm.is_finished()
	var finished_flag = _vm.get("_finished")
	if finished_flag != null and finished_flag:
		done = true
	var matched_ready: bool = _matched_at >= 0 and _f >= _matched_at + _settle
	if (done or matched_ready or _f >= _maxf) and not _quit:
		print("[s6probe] ===== FINAL f=%d boxes=%d done=%s =====" % [_f, _box_count, str(done)])
		print("[s6probe]   roster: %s" % _roster_line())
		print("[s6probe]   ever-visible uids: %s" % str(_seen_uids.keys()))
		# Hide full-screen fade/oxide overlays (opaque black at boot/transition)
		# so the capture shows the 3D tableau, not the fade rect.
		_hide_overlays(_scene)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(_shot)
		print("[s6probe] ===== CAPTURED -> %s =====" % _shot)
		_quit = true

func _hide_overlays(n: Node) -> void:
	# Neutralize the FadeLayer/OxideLayer CanvasLayers + any full-screen ColorRect
	# covering the frame so a capture reveals the underlying 3D scene.
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer" \
			or (OS.has_environment("HIDE_DIALOG") and n.name == "DialogueOverlay")):
		(n as CanvasLayer).visible = false
	if n is ColorRect:
		var cr := n as ColorRect
		if cr.name == "FadeRect" or cr.name == "OxideRect":
			cr.color = Color(cr.color.r, cr.color.g, cr.color.b, 0.0)
	for c in n.get_children():
		_hide_overlays(c)


func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
