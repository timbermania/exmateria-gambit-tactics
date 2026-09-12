extends SceneTree
## [Carry-pose EVTCHR investigation] Boots scenario 6, auto-advances the
## abduction cutscene, and logs — for the two lead actors, unit 5 (Delita) and
## unit 12 (Ovelia) — the live BODY animation branch each frame the value
## changes: current_anim_id (unit+0x0C mirror), whether a CinematicWalkState
## walker is armed, and which _paint_body_variant branch the renderer takes
## (idle / SEQ / EVTCHR-no-op). Proves whether the scn6 cinematic anims
## 500-527 reach the EVTCHR walker at all.
##
## Run (NOT headless):
##   # from the package root
##   MAXF=5000 godot --path . -s res://tools/probe_scenario6_carry_anim.gd
## Env: MAXF (frame cap), SHOT (optional final png).

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 5000
var _shot := ""
var _watch := [5, 12]
var _last := {}   # uid -> last logged "aid|walker" signature

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[carry] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[carry] booting scenario 6 (maxf=%d) watching uids %s" % [_maxf, str(_watch)])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _branch(aid: int) -> String:
	if aid == 0: return "IDLE"
	elif aid < 0x1f5: return "SEQ"
	else: return "EVTCHR-noop"

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			print("[carry] VM found at f=%d, auto-advance ON" % _f)
		return

	var ubid = _vm.get("units_by_id")
	if ubid != null:
		for uid in _watch:
			if not ubid.has(uid): continue
			var u = ubid[uid]
			if u == null or not is_instance_valid(u): continue
			var aid: int = u.current_anim_id
			var la = _vm.peek_actor(uid)
			var has_walker := la != null and la.walker != null
			var sig := "%d|%s" % [aid, str(has_walker)]
			if _last.get(uid, "") != sig:
				_last[uid] = sig
				print("[carry] f=%d uid=%d body_anim_id=%d (0x%X) branch=%s walker=%s vis=%s" % [
					_f, uid, aid, aid, _branch(aid), str(has_walker), str(u.visible)])

	var done := false
	if _vm.has_method("is_finished"):
		done = _vm.is_finished()
	var ff = _vm.get("_finished")
	if ff != null and ff: done = true
	if (done or _f >= _maxf) and not _quit:
		print("[carry] ===== FINAL f=%d done=%s =====" % [_f, str(done)])
		if _shot != "":
			_hide_overlays(_scene)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png(_shot)
			print("[carry] captured -> %s" % _shot)
		_quit = true

func _hide_overlays(n: Node) -> void:
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
		if r != null: return r
	return null
