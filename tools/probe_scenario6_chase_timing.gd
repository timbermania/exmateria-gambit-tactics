extends SceneTree
## [Chase timing] Scenario-6 pre-ride-off chase (PC 327-346). Measures the GAP
## between Agrias's chase Walk To (PC 334, uid 2) and Delita's ride-off Block
## Start (PC 346, uid 5). On PSX the ride-off fires ~20 frames after the walk
## begins (Agrias gets a ~1.5-tile head start). This probe records, tick by tick
## through the window, the main-context PC + Agrias displacement + Delita motion,
## so we can see whether Godot instead stalls the ride-off until Agrias's walk
## COMPLETES (the reported bug: "Agrias walks all the way to him and past him,
## then he takes off").
##
## Boots on the REAL gameplay path (dialog_auto_advance only; NO
## play_through_skip_unknown), stepping over coverage-gap opcodes like the freeze
## probe so the cutscene reaches the ride-off with every Wait barrier UNCAPPED.
##
## Run (NOT headless):
##   # from the package root
##   MAXF=12000 godot --path . -s res://tools/probe_scenario6_chase_timing.gd 2>&1 | tee /tmp/chase.log

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 12000
var _skipped_ops := {}
var _last_main_pc := -1
var _agrias_home = null
var _delita_home = null
var _walk_start_f := -1        # frame Agrias's Walk To motion first appears (PC 334)
var _rideoff_start_f := -1     # frame Delita first gets ride-off motion (>= PC 346)
var _agrias_lead_at_rideoff := -1.0
var _pc334_f := -1
var _pc346_f := -1

func _insts_size() -> int:
	var ins = _vm.get("_insts")
	return ins.size() if ins != null else 0

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[chase] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[chase] booting scenario 6 (maxf=%d)" % _maxf)

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _pos(u) -> Vector3:
	if u == null or not is_instance_valid(u): return Vector3.ZERO
	return u.global_position

func _has_motion(uid: int) -> bool:
	if _vm == null or not _vm.has_method("peek_actor"): return false
	var a = _vm.peek_actor(uid)
	if a == null: return false
	return a.get("motion") != null

func _unit(uid: int):
	var ubid = _vm.get("units_by_id")
	if ubid == null or not ubid.has(uid): return null
	var u = ubid[uid]
	return u if (u != null and is_instance_valid(u)) else null

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			var mp := root.get_node_or_null("/root/MusicPlayer")
			if mp != null and mp.has_method("stop"): mp.stop()
			print("[chase] VM found at f=%d, auto-advance ON, music STOPPED" % _f)
		return
	var mp2 := root.get_node_or_null("/root/MusicPlayer")
	if mp2 != null and mp2.has_method("is_playing") and mp2.is_playing():
		mp2.stop()

	# step over coverage-gap opcodes (keep Wait barriers uncapped)
	if not _vm.get("_running"):
		var ctxs = _vm.get("_contexts")
		var main0 = ctxs[0] if (ctxs != null and ctxs.size() > 0) else null
		if main0 != null and main0.alive and main0.pc < _insts_size():
			var inst = _vm._insts[main0.pc]
			if not _skipped_ops.has(main0.pc):
				_skipped_ops[main0.pc] = true
				print("[chase] SKIP-UNHANDLED pc=%d '%s' (0x%X)" % [
					main0.pc, str(inst.get("name","?")), int(inst.get("opcode",0))])
			main0.pc += 1
			_vm.set("_running", true)

	var snap: Array = _vm.get_contexts_snapshot()
	var main_pc := -1
	var vm_tick = _vm.get("_vm_tick")
	for c in snap:
		if c.label == "main": main_pc = c.pc

	var ag = _unit(52)    # Agrias (chase) = chunk unit 0x34
	var dl = _unit(5)     # Delita
	if ag != null and _agrias_home == null and main_pc >= 333: _agrias_home = _pos(ag)
	if dl != null and _delita_home == null: _delita_home = _pos(dl)

	var ag_d := 0.0
	if ag != null and _agrias_home != null: ag_d = _pos(ag).distance_to(_agrias_home)
	var ag_mot := _has_motion(2)
	var dl_mot := _has_motion(5)

	# mark PC crossings
	if main_pc != _last_main_pc:
		if main_pc == 334 and _pc334_f < 0: _pc334_f = _f
		if main_pc == 346 and _pc346_f < 0: _pc346_f = _f
		# per-instruction stamp through the window
		if main_pc >= 325 and main_pc <= 360:
			var nm := "?"
			if main_pc >= 0 and main_pc < _insts_size():
				nm = str(_vm._insts[main_pc].get("name","?"))
			print("[chase] f=%4d tick=%s main_pc=%d  %s   | Agrias d_home=%.2f mot=%s  Delita d_home=%.2f mot=%s" % [
				_f, str(vm_tick), main_pc, nm, ag_d,
				str(ag_mot), (_pos(dl).distance_to(_delita_home) if dl != null and _delita_home != null else -1.0), str(dl_mot)])
		_last_main_pc = main_pc

	# detect Agrias walk motion start
	if _walk_start_f < 0 and ag_mot and main_pc >= 334:
		_walk_start_f = _f
		print("[chase] >>> Agrias WALK motion armed at f=%d (main_pc=%d)" % [_f, main_pc])
	# detect Delita ride-off motion start (block region)
	if _rideoff_start_f < 0 and dl_mot and main_pc >= 344:
		_rideoff_start_f = _f
		_agrias_lead_at_rideoff = ag_d
		print("[chase] >>> Delita RIDE-OFF motion armed at f=%d (main_pc=%d) | Agrias has moved d_home=%.2f tiles" % [
			_f, main_pc, ag_d])

	var done := false
	if _vm.has_method("is_finished"): done = _vm.is_finished()
	var ff = _vm.get("_finished")
	if ff != null and ff: done = true
	# quit shortly after the ride-off is under way (or at cap)
	if ((_rideoff_start_f > 0 and _f > _rideoff_start_f + 400) or done or _f >= _maxf) and not _quit:
		print("[chase] ===== SUMMARY =====")
		print("[chase] frame @ PC334 (Agrias Walk To) = %d" % _pc334_f)
		print("[chase] frame @ PC346 (Block Start / ride-off) = %d" % _pc346_f)
		print("[chase] Agrias walk motion armed @ f=%d" % _walk_start_f)
		print("[chase] Delita ride-off motion armed @ f=%d" % _rideoff_start_f)
		if _walk_start_f > 0 and _rideoff_start_f > 0:
			print("[chase] GAP walk->rideoff = %d frames" % (_rideoff_start_f - _walk_start_f))
		print("[chase] Agrias displacement when ride-off began = %.2f tiles" % _agrias_lead_at_rideoff)
		print("[chase] (PSX ground truth: ~20-frame gap, ~1.5-tile lead)")
		_quit = true

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
