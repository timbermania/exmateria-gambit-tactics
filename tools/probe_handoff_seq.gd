extends SceneTree
## Probe: WHAT ADVANCES, per rendered frame, across the story→battle handoff.
##
## The transition report ("two kinds of stutters… maybe just smooth out the transition") is
## not a frame-cost claim, and a frame-cost trace cannot settle it: one of the two candidate
## stutters is a single ~60 ms frame and the other is six ORDINARY frames in which nothing
## moves. Only a trace of what ADVANCED tells them apart, so this probe records, per rendered
## frame and per unit, the sprite-sequence handle, the sprite FRAME COUNTER behind it, the
## clock owner, and the world position — and scores the arms against the CLOCK OWNER, never
## against the frame number (the whole window is ~200 ms inside a multi-second trace).
##
## What it settles:
##   RATE   — sprite frames advanced per second in each clock-owner arm. The standing
##            suspicion is SCENARIO 45/s vs COMBAT 60/s; this answers it with a number.
##   PHASE  — whether the flip frame itself loses or repeats a sprite frame.
##   DEAD   — the longest run of consecutive rendered frames in which NOTHING advanced
##            (no unit frame, no position) — the "dead beat", which is not a cost.
##   COST   — worst frames, reported WITH what they froze. Context, never the verdict.
##
## Run (NEVER --headless):
##   # from the package root
##   OUT=/tmp/hs.csv godot --path . -s res://tools/probe_handoff_seq.gd -- --battle=9
##
## Env:
##   OUT=<csv>      where the per-frame trace lands (default /tmp/handoffseq.csv)
##   MAXS=<s>       wall-clock ceiling before it gives up (default 180)
##   HOLDF=<n>      frames to hold at Deployment before leaving it (default 90)
##   AFTERF=<n>     frames to record after combat goes live (default 240)
##   SKIPPB=1       arm `navigator.skip_pre_battle` — the direct-seek handoff path instead
##
## ⚠️ A probe window renders at ~63 Hz, not the user's 144 Hz. Every rate below is a
## property of the CLOCK, which is host-rate-independent by construction; the per-frame
## duplicate SHARE is not, and is not reported as one.

const AnimationFrameCalculator = preload("res://addons/exmateria_sprite_rig/sequence/AnimationFrameCalculator.gd")

const OWNER_NAMES := ["SELF", "SCENARIO", "COMBAT"]
## Unit columns in the CSV. Enough for a 4v4 plus scenario extras; overflow is named in the log.
const MAX_UNITS := 10

var _nav: Node = null
var _runner = null
var _vm = null
var _out := "/tmp/handoffseq.csv"
var _max_s := 180
var _hold_frames := 90
var _after_frames := 240
var _skip_pre_battle := false

var _f := 0
var _start_us := 0
var _last_us := 0
var _quit := false
var _rows: Array[String] = []
var _done_reason := "max time"
var _skip_pushed := false

## Stable unit slot assignment: name → column. Assigned on first sight and never reused, so a
## unit that appears mid-trace does not shuffle the columns underneath the earlier rows.
var _slot_of := {}
var _slot_names: Array[String] = []

## Per-slot carry for the cumulative advance count (anim_frame wraps at the SEQ's duration).
var _prev_anim_id := {}
var _prev_anim_frame := {}
var _cum := {}

## Per-frame scored history, parallel arrays so the verdict is plain arithmetic.
var _h_us: Array[int] = []
var _h_cost: Array[float] = []
var _h_owner: Array = []      # Array[Array[int]]  -1 = absent
var _h_cum: Array = []        # Array[Array[int]]
var _h_anim: Array = []       # Array[Array[int]]
var _h_pos: Array = []        # Array[Array[Vector3]]
var _h_state: Array[int] = []

var _live_frame := -1
var _deploy_frame := -1
var _left_deploy := false


func _initialize() -> void:
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	if OS.has_environment("MAXS"): _max_s = int(OS.get_environment("MAXS"))
	if OS.has_environment("HOLDF"): _hold_frames = int(OS.get_environment("HOLDF"))
	if OS.has_environment("AFTERF"): _after_frames = int(OS.get_environment("AFTERF"))
	_skip_pre_battle = OS.has_environment("SKIPPB")
	Engine.time_scale = 1.0
	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	root.add_child(_nav)
	_start_us = Time.get_ticks_usec()
	_last_us = _start_us
	print("[handoff-seq] probe up — recording to %s" % _out)


func _process(_delta: float) -> bool:
	if _quit:
		return true
	var now := Time.get_ticks_usec()
	var cost_ms := float(now - _last_us) / 1000.0
	_last_us = now
	_f += 1

	# `/root/Tune` is not resolvable at `_initialize()`, so the override is pushed on the
	# first real frame — long before the battle is reached either way.
	if _skip_pre_battle and not _skip_pushed:
		var tune := root.get_node_or_null("Tune")
		if tune != null:
			tune.set_value("navigator.skip_pre_battle", true)
			_skip_pushed = true
			print("[handoff-seq] navigator.skip_pre_battle := true")

	if _runner == null and _nav != null and is_instance_valid(_nav) and "_nav_runner" in _nav:
		_runner = _nav._nav_runner
	if _vm == null and _nav != null and is_instance_valid(_nav) and "_vm" in _nav:
		_vm = _nav._vm

	var nav_state := -1
	if _runner != null and is_instance_valid(_runner):
		nav_state = int(_runner.current_state)
	var combat_active := false
	var loop_up := false
	if _nav != null and is_instance_valid(_nav):
		combat_active = bool(_nav._combat_active)
		loop_up = _nav._combat_loop != null and is_instance_valid(_nav._combat_loop)
	var dark_prog := -1.0
	if _vm != null and is_instance_valid(_vm) and "_dark_screen" in _vm:
		var ds = _vm._dark_screen
		if ds != null and is_instance_valid(ds):
			dark_prog = float(ds.progress())

	# --- the per-unit sample -------------------------------------------------
	var owners: Array[int] = []
	var cums: Array[int] = []
	var anims: Array[int] = []
	var poss: Array = []
	owners.resize(MAX_UNITS); cums.resize(MAX_UNITS); anims.resize(MAX_UNITS)
	for i in range(MAX_UNITS):
		owners[i] = -1; cums[i] = -1; anims[i] = -1
		poss.append(Vector3.INF)

	for unit in root.get_tree().get_nodes_in_group("units"):
		if unit == null or not is_instance_valid(unit) or not ("clock_owner" in unit):
			continue
		var key := String(unit.name)
		if not _slot_of.has(key):
			if _slot_names.size() >= MAX_UNITS:
				continue  # overflow, named in _finish
			_slot_of[key] = _slot_names.size()
			_slot_names.append(key)
			_prev_anim_id[key] = ""
			_prev_anim_frame[key] = -1
			_cum[key] = 0
		var slot: int = _slot_of[key]
		owners[slot] = int(unit.clock_owner)
		poss[slot] = unit.global_position

		var disp = unit.display if "display" in unit else null
		if disp == null or not is_instance_valid(disp):
			continue
		anims[slot] = int(disp.current_anim_id)
		var body = disp._normal_set.body if "_normal_set" in disp and disp._normal_set != null else null
		if body == null:
			continue
		# Cumulative sprite-frame advances. `anim_frame` steps by exactly one per
		# `advance_frame()` and WRAPS at the SEQ's duration, so a bare delta would read a
		# loop as a huge backwards jump; add the duration back on a wrap. A SEQ SWITCH
		# breaks the chain (the counter restarts against a different length), so that frame
		# contributes nothing rather than a fabricated delta.
		var cur_id := String(body.anim_id)
		var cur_frame := int(body.anim_frame)
		if cur_id == String(_prev_anim_id.get(key, "")) and int(_prev_anim_frame[key]) >= 0:
			var d := cur_frame - int(_prev_anim_frame[key])
			if d < 0:
				var dur := int(AnimationFrameCalculator.get_duration(cur_id, body.sequences))
				d += maxi(dur, 0)
			if d >= 0:
				_cum[key] = int(_cum[key]) + d
		_prev_anim_id[key] = cur_id
		_prev_anim_frame[key] = cur_frame
		cums[slot] = int(_cum[key])

	_h_us.append(now - _start_us)
	_h_cost.append(cost_ms)
	_h_owner.append(owners.duplicate())
	_h_cum.append(cums.duplicate())
	_h_anim.append(anims.duplicate())
	_h_pos.append(poss.duplicate())
	_h_state.append(nav_state)

	var row := "%d,%d,%.3f,%d,%d,%d,%.4f" % [
		_f, now - _start_us, cost_ms, nav_state, int(combat_active), int(loop_up), dark_prog]
	for i in range(MAX_UNITS):
		var p: Vector3 = poss[i]
		row += ",%d,%d,%d,%.5f,%.5f,%.5f" % [owners[i], anims[i], cums[i], p.x, p.y, p.z]
	_rows.append(row)

	# --- drive ---------------------------------------------------------------
	# Leave Deployment through the runner's own completion callback rather than by faking a
	# key event: it is the same edge Space takes (`on_pre_battle_finished` → `run_combat` →
	# `_go_live`) and it lands on a frame this probe chose, which is what makes the flip
	# frame findable in the trace.
	if nav_state == GameState.State.PRE_BATTLE and not _left_deploy:
		if _deploy_frame < 0:
			_deploy_frame = _f
			print("[handoff-seq] Deployment at frame %d" % _f)
		elif _f - _deploy_frame >= _hold_frames:
			_left_deploy = true
			print("[handoff-seq] leaving Deployment at frame %d" % _f)
			if _runner != null and is_instance_valid(_runner):
				_runner.on_pre_battle_finished()

	if combat_active:
		if _live_frame < 0:
			_live_frame = _f
			print("[handoff-seq] combat LIVE at frame %d" % _f)
		elif _f - _live_frame >= _after_frames:
			_done_reason = "%d frames past go-live" % _after_frames
			_finish()
			return true
	if (Time.get_ticks_usec() - _start_us) > _max_s * 1000000:
		_finish()
		return true
	return false


func _finish() -> void:
	_quit = true
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_line(_header())
		for r in _rows:
			f.store_line(r)
		f.close()
	print("[handoff-seq] %d frames → %s  [%s]" % [_f, _out, _done_reason])
	print("[handoff-seq] slots: %s" % str(_slot_names))
	_verdict()


func _header() -> String:
	var h := "frame,us,cost_ms,nav_state,combat_active,loop_up,dark_prog"
	for i in range(MAX_UNITS):
		var n: String = _slot_names[i] if i < _slot_names.size() else "u%d" % i
		h += ",%s_owner,%s_anim,%s_cum,%s_x,%s_y,%s_z" % [n, n, n, n, n, n]
	return h


## A unit's frames-per-second in one clock-owner arm: total cumulative advance across the
## frames it spent in that arm, divided by the wall clock those frames took. Both halves are
## measured on the SAME frames, so a slow box shrinks numerator and denominator together and
## the rate is the clock's property rather than the run's.
func _verdict() -> void:
	if _h_us.size() < 30:
		print("[handoff-seq] VERDICT: only %d frames — nothing reached. Not a negative." % _h_us.size())
		return
	if _live_frame < 0:
		print("[handoff-seq] VERDICT: NO SUBJECT — combat never went live, so the handoff "
			+ "was never crossed. This is a blind run, not a clean one.")
		return

	var n := _h_us.size()
	# --- RATE per (unit, owner) ---------------------------------------------
	print("[handoff-seq] --- RATE (sprite frames advanced per second, by clock owner) ---")
	for s in range(_slot_names.size()):
		var adv := [0, 0, 0]
		var us := [0, 0, 0]
		for i in range(1, n):
			var o: int = _h_owner[i][s]
			if o < 0 or o > 2 or _h_owner[i - 1][s] != o:
				continue  # absent, or the flip frame itself — scored separately below
			var c: int = _h_cum[i][s]
			var pc: int = _h_cum[i - 1][s]
			if c < 0 or pc < 0:
				continue
			adv[o] += c - pc
			us[o] += _h_us[i] - _h_us[i - 1]
		var parts: Array[String] = []
		for o in range(3):
			if us[o] < 100000:
				continue  # under 0.1 s in that arm says nothing
			parts.append("%s %.1f/s (%d frames over %.2f s)"
				% [OWNER_NAMES[o], 1000000.0 * adv[o] / us[o], adv[o], us[o] / 1000000.0])
		if parts.is_empty():
			continue
		print("[handoff-seq]   %-22s %s" % [_slot_names[s], " | ".join(parts)])

	# --- PHASE at the flip ---------------------------------------------------
	print("[handoff-seq] --- FLIP (the frame each unit changed clock owner) ---")
	var flips := 0
	for s in range(_slot_names.size()):
		for i in range(1, n):
			var a: int = _h_owner[i - 1][s]
			var b: int = _h_owner[i][s]
			if a < 0 or b < 0 or a == b:
				continue
			flips += 1
			var d := -999
			if _h_cum[i][s] >= 0 and _h_cum[i - 1][s] >= 0:
				d = _h_cum[i][s] - _h_cum[i - 1][s]
			print("[handoff-seq]   f%d  %-20s %s→%s  advanced %d sprite frame(s) on the flip "
				% [i + 1, _slot_names[s], OWNER_NAMES[a], OWNER_NAMES[b], d]
				+ "(anim %d→%d)" % [_h_anim[i - 1][s], _h_anim[i][s]])
	if flips == 0:
		print("[handoff-seq]   NONE — no unit changed owner inside the trace. The handoff "
			+ "this probe exists to watch did not happen on a recorded frame.")

	# --- DEAD: the longest run of frames in which NOTHING advanced -----------
	# Scored over sprite frames AND positions together, because the dead beat is precisely a
	# stretch where the field is revealed and motionless — neither half moves.
	var best_len := 0
	var best_at := -1
	var run := 0
	var run_at := -1
	for i in range(1, n):
		var moved := false
		for s in range(_slot_names.size()):
			if _h_cum[i][s] > _h_cum[i - 1][s] and _h_cum[i - 1][s] >= 0:
				moved = true
				break
			var p: Vector3 = _h_pos[i][s]
			var q: Vector3 = _h_pos[i - 1][s]
			if p != Vector3.INF and q != Vector3.INF and p.distance_to(q) > 0.0001:
				moved = true
				break
		if moved:
			run = 0
			run_at = -1
		else:
			if run == 0:
				run_at = i
			run += 1
			if run > best_len:
				best_len = run
				best_at = run_at
	if best_len > 0:
		var ms := float(_h_us[mini(best_at + best_len - 1, n - 1)] - _h_us[best_at - 1]) / 1000.0
		print("[handoff-seq] --- DEAD: longest motionless run %d frames / %.0f ms, frames %d–%d "
			% [best_len, ms, best_at + 1, best_at + best_len]
			+ "(nav_state %d, %s go-live)"
			% [_h_state[best_at], "before" if best_at + 1 < _live_frame else "after"])

	# --- COST: context only --------------------------------------------------
	var worst := 0.0
	var worst_i := -1
	var over := 0
	for i in range(n):
		if _h_cost[i] >= 30.0:
			over += 1
		if _h_cost[i] > worst:
			worst = _h_cost[i]
			worst_i = i
	print("[handoff-seq] --- COST (context, NOT the verdict): %d frame(s) ≥ 30 ms; "
		% over + "worst %.1f ms at frame %d (nav_state %d)"
		% [worst, worst_i + 1, _h_state[maxi(worst_i, 0)]])
