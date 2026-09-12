extends SceneTree
## [Ride-off FREEZE diagnosis] Boots scenario 6 on the REAL gameplay path —
## ONLY `dialog_auto_advance = true`, NO `play_through_skip_unknown` (that flag
## is the probe confound documented in the handoff: it caps waits + skips
## unknowns, hiding the freeze). Traces the four end-of-scene actors:
##   chocobo (139), Ovelia (12), Delita (5)  — the trio that FREEZES
##   Agrias  (2)                             — the control that MOVES
## For each it logs pos / anim / visible / has-motion on material change, and
## once the main context enters the block region (pc>=340) it dumps the live
## context list (label+pc+wait) each time it changes, plus a stall detector
## that prints a full state dump when nothing advances for STALL_FRAMES frames.
##
## Run (NOT headless):
##   # from the package root
##   MAXF=12000 godot --path . -s res://tools/probe_scenario6_freeze.gd 2>&1 | tee /tmp/freeze.log

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _maxf := 12000
var _watch := [2, 5, 12, 139]
var _last := {}            # uid -> last logged signature
var _home := {}            # uid -> first-seen position
var _last_ctx_sig := ""
var _verbose_from_pc := 340
var _stall_frames := 240   # ~4s of no progress => declare freeze
var _last_progress_f := 0
var _last_progress_sig := ""
var _froze := false
var _skipped_ops := {}     # pc -> true, one log line per skipped coverage gap

func _insts_size() -> int:
	var ins = _vm.get("_insts")
	return ins.size() if ins != null else 0

func _initialize() -> void:
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
	else:
		push_error("[freeze] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[freeze] booting scenario 6 (maxf=%d) watching %s" % [_maxf, str(_watch)])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _pos(u) -> Vector3:
	if u == null or not is_instance_valid(u): return Vector3.ZERO
	return u.global_position

func _has_motion(uid: int) -> bool:
	# peek_actor(uid).motion != null — ask the VM without mutating.
	if _vm == null or not _vm.has_method("peek_actor"): return false
	var a = _vm.peek_actor(uid)
	if a == null: return false
	return a.get("motion") != null

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			# DELIBERATELY NOT setting play_through_skip_unknown — real path.
			# Kill the SMD music engine: its synchronous 1500ms generation starves
			# the render loop to ~1fps, making the cutscene unwatchably slow. Audio
			# is irrelevant to this VM-execution freeze.
			var mp := root.get_node_or_null("/root/MusicPlayer")
			if mp != null and mp.has_method("stop"): mp.stop()
			print("[freeze] VM found at f=%d, auto-advance ON (play_through OFF), music STOPPED" % _f)
		return
	# {84} Play Song during the scene restarts music — keep it dead for speed.
	var mp2 := root.get_node_or_null("/root/MusicPlayer")
	if mp2 != null and mp2.has_method("is_playing") and mp2.is_playing():
		mp2.stop()

	# PROBE-SIDE "skip unhandled opcode" — WITHOUT the play_through wait-cap.
	# The VM sets `_running=false` when the main context hits an opcode that is
	# neither bound nor _skip'd (see _drain_context null-handler branch). That is
	# a coverage GAP, not the freeze we're hunting. We manually step main's PC
	# past the offending opcode and re-arm `_running`, so the cutscene plays
	# through to the ride-off blocks while every Wait / Wait-Sprite-Move barrier
	# stays UNCAPPED (INF) — the faithful condition the play-through probe destroys.
	if not _vm.get("_running"):
		var ctxs = _vm.get("_contexts")
		var main = ctxs[0] if (ctxs != null and ctxs.size() > 0) else null
		if main != null and main.alive and main.pc < _insts_size():
			var inst = _vm._insts[main.pc]
			var nm := str(inst.get("name", "Unknown"))
			if not _skipped_ops.has(main.pc):
				_skipped_ops[main.pc] = true
				print("[freeze] SKIP-UNHANDLED pc=%d '%s' (0x%X) — probe stepping over coverage gap" % [
					main.pc, nm, int(inst.get("opcode", 0))])
			main.pc += 1
			_vm.set("_running", true)

	var ubid = _vm.get("units_by_id")
	var progress_sig := ""

	# main context pc
	var snap: Array = _vm.get_contexts_snapshot()
	var main_pc := -1
	for c in snap:
		if c.label == "main": main_pc = c.pc
		progress_sig += "%s:%d/%d;" % [c.label, c.pc, c.wait_ticks]

	# per-unit logging
	if ubid != null:
		for uid in _watch:
			if not ubid.has(uid): continue
			var u = ubid[uid]
			if u == null or not is_instance_valid(u): continue
			var p := _pos(u)
			if not _home.has(uid): _home[uid] = p
			var aid: int = u.current_anim_id
			var moved: float = p.distance_to(_home[uid])
			var mot := _has_motion(uid)
			progress_sig += "u%d:%.1f,%.1f,%.1f;" % [uid, p.x, p.y, p.z]
			var sig := "%d|%.2f,%.2f,%.2f|%s|m%s" % [aid, p.x, p.y, p.z, str(u.visible), str(mot)]
			if _last.get(uid, "") != sig:
				_last[uid] = sig
				print("[freeze] f=%d uid=%3d pos=(%7.2f,%7.2f,%7.2f) d_home=%6.2f anim=0x%X vis=%s motion=%s" % [
					_f, uid, p.x, p.y, p.z, moved, aid, str(u.visible), str(mot)])

	# context-list change dump (once we're near the block region)
	if main_pc >= _verbose_from_pc:
		var ctx_sig := ""
		for c in snap:
			ctx_sig += "%s@%d(w%d,a%s) " % [c.label, c.pc, c.wait_ticks, str(c.alive)]
		if ctx_sig != _last_ctx_sig:
			_last_ctx_sig = ctx_sig
			print("[freeze] f=%d CTX: %s" % [_f, ctx_sig])

	# stall detector
	if progress_sig != _last_progress_sig:
		_last_progress_sig = progress_sig
		_last_progress_f = _f
	elif not _froze and main_pc >= _verbose_from_pc and (_f - _last_progress_f) >= _stall_frames:
		_froze = true
		print("[freeze] ===== STALL DETECTED f=%d (no progress for %d frames) =====" % [_f, _stall_frames])
		print("[freeze] main_pc=%d" % main_pc)
		for c in snap:
			print("[freeze]   ctx %-14s pc=%d wait_ticks=%d alive=%s" % [c.label, c.pc, c.wait_ticks, str(c.alive)])
		if ubid != null:
			for uid in _watch:
				if not ubid.has(uid):
					print("[freeze]   unit %3d: NOT in units_by_id" % uid); continue
				var u = ubid[uid]
				var valid = (u != null and is_instance_valid(u))
				print("[freeze]   unit %3d: valid=%s pos=%s anim=0x%X vis=%s motion=%s" % [
					uid, str(valid), str(_pos(u)) if valid else "-",
					(u.current_anim_id if valid else -1),
					str(u.visible) if valid else "-", str(_has_motion(uid))])
		# keep running a bit to see if it ever releases, then quit
		# (don't quit immediately — the stall might break)

	var done := false
	if _vm.has_method("is_finished"): done = _vm.is_finished()
	var ff = _vm.get("_finished")
	if ff != null and ff: done = true
	if (done or _f >= _maxf) and not _quit:
		print("[freeze] ===== FINAL f=%d done=%s froze=%s main_pc=%d =====" % [_f, str(done), str(_froze), main_pc])
		_quit = true

func _find_vm(n: Node) -> Node:
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null: return r
	return null
