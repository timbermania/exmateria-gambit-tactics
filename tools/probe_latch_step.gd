extends SceneTree
## [Latch-step probe] Reproduce the user's report: double-click pc203 (park), then
## step to 204 — Ovelia's {11}@202 anim=510 latch should PAINT during the 203 Wait.
## Logs pending_anim + current_anim_id + walker per frame across the step so we see
## exactly whether/when `_consume_pending_body_anims` paints.
##
## Run (NEVER headless), from the package root:
##   PC=203 STEP_TO=204 godot --path . -s res://tools/probe_latch_step.gd
## Env: PC(203) park target, STEP_TO(PC+1) step target.

var _scene: Node
var _vm: Node
var _f := 0
var _pc := 203
var _step_to := -1
var _parked := false
var _stepped := false
var _watch := 0
var _done := false

var U := 12  # Ovelia (override with UID env)

func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	_step_to = _pc + 1
	if OS.has_environment("STEP_TO"): _step_to = int(OS.get_environment("STEP_TO"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _pc
	else:
		push_error("[ls] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[ls] booting scn6, park pc=%d, then step→%d" % [_pc, _step_to])

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

func _line(tag: String) -> void:
	var u = _vm.units_by_id.get(U)
	var a = _vm.peek_actor(U)
	var pend: int = (a.pending_anim if a != null else -999)
	var walker_on := (a != null and a.get("walker") != null)
	var anim: int = (int(u.current_anim_id) if u != null else -1)
	var frame := -1
	if u != null and u.display != null and u.display.type1_playback != null:
		frame = int(u.display.type1_playback.anim_frame)
	var mc = _vm.get("_contexts")
	var pc: int = (mc[0].pc if mc != null and mc.size() > 0 else -1)
	var wt: int = (mc[0].wait_ticks if mc != null and mc.size() > 0 else -1)
	print("[ls] %-10s f=%d pc=%d wait=%s paused=%s ff=%s | u12 pending=%d anim=%d frame=%d walker=%s" % [
		tag, _f, pc, str(wt), str(_vm.get("_paused")), str(_vm.get("_ff_active")),
		pend, anim, frame, str(walker_on)])

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	if not _parked:
		if _vm.get_pc() >= _pc and _vm.get("_paused"):
			_parked = true
			print("\n[ls] ===== PARKED at pc=%d =====" % _vm.get_pc())
			_line("parked")
		elif _f > 4000:
			print("[ls] TIMEOUT never parked (pc=%d)" % _vm.get_pc())
			_done = true
		return
	if not _stepped:
		_stepped = true
		print("[ls] ===== step(%d) → target %d =====" % [_step_to - _vm.get_pc(), _step_to])
		_vm.step(_step_to - _vm.get_pc())
		return
	_watch += 1
	_line("watch")
	if _vm.get("_paused") and _watch > 3:
		print("[ls] ===== settled (paused) =====")
		_done = true
	if _watch > 200:
		print("[ls] ===== watch cap =====")
		_done = true

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
