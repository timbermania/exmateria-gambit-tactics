extends SceneTree
## [Ride-off investigation] Boots scenario 6, auto-advances the whole abduction
## cutscene, and traces the THREE ride-off actors — chocobo (unit 139), Ovelia
## (unit 12), Delita (unit 5) — through the tail Sprite-Move / Erase / Remove
## sequence (chunk instrs 344-401). For each unit it logs global_position,
## current_anim_id, and visible each time any of them changes materially, and
## captures PNG frames while the trio is moving (the "ride-off"), so we can
## compare the Godot render to the live PSX ground truth (Ovelia mounted + lifted
## on the chocobo, Delita on foot, all sliding off toward the exit).
##
## Run (NOT headless):
##   # from the package root
##   MAXF=9000 SHOTDIR=/tmp/godot_ride godot --path . -s res://tools/probe_scenario6_rideoff.gd
## Env: MAXF (frame cap, default 9000), SHOTDIR (dir for ride-off PNGs).

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 9000
var _shotdir := ""
var _watch := [5, 12, 139]
var _last := {}          # uid -> last logged signature
var _home := {}          # uid -> first-seen position (home)
var _moving_since := -1   # frame the ride-off motion began
var _shots := 0
var _next_shot_f := 0

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("SHOTDIR"): _shotdir = OS.get_environment("SHOTDIR")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[ride] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[ride] booting scenario 6 (maxf=%d) watching %s shotdir=%s" % [_maxf, str(_watch), _shotdir])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _pos(u) -> Vector3:
	if u == null or not is_instance_valid(u): return Vector3.ZERO
	return u.global_position

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			print("[ride] VM found at f=%d, auto-advance ON" % _f)
		return

	var ubid = _vm.get("units_by_id")
	var any_moving := false
	if ubid != null:
		for uid in _watch:
			if not ubid.has(uid): continue
			var u = ubid[uid]
			if u == null or not is_instance_valid(u): continue
			var p := _pos(u)
			if not _home.has(uid): _home[uid] = p
			var aid: int = u.current_anim_id
			var moved: float = p.distance_to(_home[uid])
			# key the ride-off on the CHOCOBO (unit 139) moving — it is stationary
			# until instr 348, so this excludes the earlier carry/escort moves.
			if uid == 139 and moved > 0.10: any_moving = true
			# log on material change of pos / anim / visibility
			var sig := "%d|%.2f,%.2f,%.2f|%s" % [aid, p.x, p.y, p.z, str(u.visible)]
			if _last.get(uid, "") != sig:
				_last[uid] = sig
				print("[ride] f=%d uid=%3d pos=(%6.2f,%6.2f,%6.2f) d_home=%5.2f anim=0x%X vis=%s" % [
					_f, uid, p.x, p.y, p.z, moved, aid, str(u.visible)])

	# detect ride-off start (any watched unit moving) and capture frames
	if any_moving and _moving_since < 0:
		_moving_since = _f
		_next_shot_f = _f
		print("[ride] ===== RIDE-OFF MOTION START f=%d =====" % _f)
	if _moving_since >= 0 and _shotdir != "" and _f >= _next_shot_f and _shots < 12:
		_capture("%s/godot_ride_%02d.png" % [_shotdir, _shots])
		_shots += 1
		_next_shot_f = _f + 6   # ~0.1s at 60Hz

	var done := false
	if _vm.has_method("is_finished"): done = _vm.is_finished()
	var ff = _vm.get("_finished")
	if ff != null and ff: done = true
	if (done or _f >= _maxf) and not _quit:
		print("[ride] ===== FINAL f=%d done=%s shots=%d =====" % [_f, str(done), _shots])
		_quit = true

func _capture(path: String) -> void:
	_hide_overlays(_scene)
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("[ride] shot f=%d -> %s" % [_f, path])

func _hide_overlays(n: Node) -> void:
	if n is CanvasLayer and (n.name == "FadeLayer" or n.name == "OxideLayer" \
			or n.name == "DialogueOverlay"):
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
		if r != null: return r
	return null
