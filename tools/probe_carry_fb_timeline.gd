extends SceneTree
## [Carry-pose parity] Boots scenario 6, auto-advances the abduction cutscene,
## and records — for Delita (uid5) and Ovelia (uid12) — the LIVE rendered
## cinematic frame each time it changes: VM pc, current_anim_id, and the
## walker's last_fb (the exact EVTCHR frame byte handed to the renderer).
##
## This is the Godot half of the PSX surgical primitive probe
## (/tmp/beat/prim.py). PSX ground truth (single-pass pc200-218):
##   Ovelia anim 509->510->511 loads EVTCHR frame 227->228->229 (UV col 96/128/160)
##   Delita anim 520->519       loads EVTCHR frame 243->242     (UV col 160/128)
## Parity holds iff Godot's walker.last_fb steps the same frames on the same
## anim-id beats.
##
## Run (NOT headless):
##   # from the package root
##   MAXF=6000 godot --path . -s res://tools/probe_carry_fb_timeline.gd
## Env: MAXF (frame cap).

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 6000
var _watch := [5, 12]
var _last := {}   # uid -> "anim|fb"
var _rows := []

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[fbtl] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[fbtl] booting scenario 6 (maxf=%d) watching uids %s" % [_maxf, str(_watch)])

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
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			print("[fbtl] VM found at f=%d, auto-advance ON" % _f)
		return

	var pc: int = _vm.get_pc() if _vm.has_method("get_pc") else -1
	var ubid = _vm.get("units_by_id")
	if ubid != null:
		for uid in _watch:
			if not ubid.has(uid): continue
			var u = ubid[uid]
			if u == null or not is_instance_valid(u): continue
			var aid: int = u.current_anim_id
			var la = _vm.peek_actor(uid)
			var fb := -99
			if la != null and la.walker != null:
				fb = la.walker.last_fb
			var sig := "%d|%d" % [aid, fb]
			if _last.get(uid, "") != sig:
				_last[uid] = sig
				var name := "Ovelia" if uid == 12 else "Delita"
				var line := "[fbtl] f=%d pc=%d %s(uid%d) anim=%d fb=%d" % [_f, pc, name, uid, aid, fb]
				print(line)
				_rows.append(line)

	var done := false
	if _vm.has_method("is_finished"):
		done = _vm.is_finished()
	var ff = _vm.get("_finished")
	if ff != null and ff: done = true
	if (done or _f >= _maxf) and not _quit:
		print("[fbtl] ===== FINAL f=%d done=%s rows=%d =====" % [_f, str(done), _rows.size()])
		_quit = true

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
