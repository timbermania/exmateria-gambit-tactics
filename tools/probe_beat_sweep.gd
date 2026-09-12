extends SceneTree
## [Beat sweep] Godot half of the H3 differential loop. Rewind-park at START, then
## step ONE opcode at a time to END, recording u5 (Delita) + u12 (Ovelia) observable
## state at EACH pc: world pos, anim id, body frame, in-flight motion elapsed. Prints
## a per-step table + flags which field CHANGED on each step (the "update" the user
## eyeballs). Diff this against the PSX per-step capture to locate the frame-spend gap.
##
## Run (NEVER headless):
##   START=200 END=217 godot --path . -s res://tools/probe_beat_sweep.gd
## Env: START(200) rewind-park pc, END(217) last pc to record.

var _scene: Node
var _vm: Node
var _f := 0
var _start := 200
var _end := 217
var _state := "boot"     # boot → park → record → stepping → done
var _rows: Array = []
var _prev: Dictionary = {}
var _done := false
var _step_wait := 0

const UIDS := [5, 12]

func _initialize() -> void:
	if OS.has_environment("START"): _start = int(OS.get_environment("START"))
	if OS.has_environment("END"): _end = int(OS.get_environment("END"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _start
	else:
		push_error("[bs] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[bs] booting scn6, sweep pc %d..%d" % [_start, _end])

func _process(_dt: float) -> bool:
	if _done:
		quit()
		return true
	return false

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null

func _snap(uid: int) -> Dictionary:
	var u = _vm.units_by_id.get(uid)
	if u == null or not is_instance_valid(u):
		return {}
	var frame := -1
	if u.display != null and u.display.type1_playback != null:
		frame = int(u.display.type1_playback.anim_frame)
	var a = _vm.peek_actor(uid)
	var mel := -1.0
	var walker_on := false
	if a != null:
		var m = a.get("motion")
		mel = (m.get("elapsed_s") if m != null else -1.0)
		walker_on = (a.get("walker") != null)
	var gp: Vector3 = u.global_position
	return {
		"pos": Vector3(snappedf(gp.x, 0.001), snappedf(gp.y, 0.001), snappedf(gp.z, 0.001)),
		"anim": int(u.current_anim_id), "frame": frame, "mel": snappedf(mel, 0.01),
		"walker": walker_on,
	}

func _record(pc: int) -> void:
	var row := {"pc": pc}
	for uid in UIDS:
		row["u%d" % uid] = _snap(uid)
	_rows.append(row)

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	match _state:
		"boot":
			if _vm.get_pc() >= _start and _vm.get("_paused"):
				_state = "record"
			elif _f > 5000:
				print("[bs] TIMEOUT never parked"); _done = true
		"record":
			_record(_vm.get_pc())
			if _vm.get_pc() >= _end:
				_report(); _done = true
				return
			_vm.step(1)
			_state = "stepping"
			_step_wait = 0
		"stepping":
			_step_wait += 1
			if _vm.get("_paused") and not _vm.get("_ff_active"):
				_state = "record"
			elif _step_wait > 1200:
				print("[bs] step stalled at pc=%d" % _vm.get_pc())
				_report(); _done = true

func _fmt(s: Dictionary) -> String:
	if s.is_empty(): return "—"
	return "pos%s a=%d f=%d mel=%s w=%s" % [str(s["pos"]), s["anim"], s["frame"], str(s["mel"]), ("Y" if s["walker"] else "n")]

func _changed(a: Dictionary, b: Dictionary) -> String:
	if a.is_empty() or b.is_empty(): return ""
	var ch: Array = []
	if (a["pos"] as Vector3).distance_to(b["pos"]) > 0.002: ch.append("POS")
	if a["anim"] != b["anim"]: ch.append("anim")
	if a["frame"] != b["frame"]: ch.append("frame")
	if a["walker"] != b["walker"]: ch.append("walker")
	return "+".join(ch)

func _report() -> void:
	print("\n[bs] ===== BEAT SWEEP pc %d..%d (Godot) =====" % [_start, _end])
	var prev: Dictionary = {}
	for row in _rows:
		var pc: int = row["pc"]
		var line := "[bs] pc=%3d | u5 %-40s | u12 %-40s" % [pc, _fmt(row["u5"]), _fmt(row["u12"])]
		if not prev.is_empty():
			var c5 := _changed(prev["u5"], row["u5"])
			var c12 := _changed(prev["u12"], row["u12"])
			var tag := ""
			if c5 != "": tag += " u5:" + c5
			if c12 != "": tag += " u12:" + c12
			if tag != "": line += "   <<<" + tag
		print(line)
		prev = row
	print("[bs] ==========================================\n")

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
