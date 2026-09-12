extends SceneTree
## Probe: does the fixed-tick remainder actually freeze unit POSITIONS on screen?
##
## Issue #1206. `CombatLoop` drains whole `TICK_INTERVAL` steps out of an accumulator and
## `update_visual_positions` then recomputes from the resulting INTEGER tick. The claim
## under test is that a rendered frame which banks less than one tick redraws every walking
## unit at a bit-identical position — so the judder is a sampling artefact, not a cost.
##
## The prediction this exists to CONFIRM OR KILL: duplicate visual positions on exactly the
## zero-tick frames. If in-motion units duplicate at the same rate whether or not a tick
## drained, something downstream is already smoothing it and the subject is elsewhere.
##
## ⚠️ This probe scores SHAPE, not wall clock. Frame COST is recorded but is not the
## verdict — a cheaper frame makes this defect WORSE, because it raises the share of frames
## that bank less than a tick. Read `TICK DRAIN` and `FREEZE`, never the ms.
##
## Run (NEVER --headless):
##   # from the package root
##   OUT=/tmp/tj.csv godot --path . -s res://tools/probe_tick_jitter.gd -- --battle=9
##
## Env: OUT=<csv>  MAXS=<max seconds, default 150>  COMBATF=<frames of combat, default 900>

var _nav: Node = null
var _loop = null
var _f := 0
var _last_us := 0
var _start_us := 0
var _out := "/tmp/tickjitter.csv"
var _max_s := 150
var _combat_frames := 900
var _quit := false
var _rows: Array[String] = []
var _done_reason := "max time"

## Frame index combat first went live — the trace before it is boot and is not scored.
var _combat_frame := -1
var _prev_tick := -1

const MAX_UNITS := 8

## Parallel per-frame history, kept as typed arrays so the verdict is plain arithmetic.
var _h_dtick: Array[int] = []
var _h_pos: Array = []          # Array[Array[Vector3]] — per frame, per unit
var _h_alpha: Array[float] = []
var _h_cost: Array[float] = []


func _initialize() -> void:
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	if OS.has_environment("MAXS"): _max_s = int(OS.get_environment("MAXS"))
	if OS.has_environment("COMBATF"): _combat_frames = int(OS.get_environment("COMBATF"))
	Engine.time_scale = 1.0
	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	root.add_child(_nav)
	_start_us = Time.get_ticks_usec()
	_last_us = _start_us
	print("[tick-jitter] probe up — recording to %s" % _out)


func _process(_delta: float) -> bool:
	if _quit:
		return true
	var now := Time.get_ticks_usec()
	var cost_ms := float(now - _last_us) / 1000.0
	_last_us = now
	_f += 1

	# Skip the deployment hold: `run_pre_battle` returns early and `run_combat` builds the
	# cursor and the loop instead, which is how every seek and every autoplay path reaches a
	# battle anyway. Pushed on a real frame — `/root/Tune` is not up at `_initialize()`.
	var tune := root.get_node_or_null("Tune")
	if tune != null and not _skip_pushed:
		tune.set_value("navigator.skip_pre_battle", true)
		_skip_pushed = true

	if _loop == null and _nav != null and is_instance_valid(_nav) and "_combat_loop" in _nav:
		if _nav._combat_loop != null and is_instance_valid(_nav._combat_loop):
			_loop = _nav._combat_loop

	var combat_active := false
	if _nav != null and is_instance_valid(_nav):
		combat_active = bool(_nav._combat_active)

	var cur_tick := -1
	var alpha := -1.0
	var positions: Array = []
	if _loop != null and is_instance_valid(_loop):
		cur_tick = int(_loop.current_tick)
		# The remainder the render path currently throws away. Read only — the ADR-0239
		# turn gate keeps it across frames on purpose.
		alpha = float(_loop._tick_accumulator) / (1.0 / 60.0)
		var bridge = _loop._visual_bridge
		if bridge != null and is_instance_valid(bridge):
			for i in range(MAX_UNITS):
				positions.append(bridge.visual_positions.get(i, Vector3.INF))

	while positions.size() < MAX_UNITS:
		positions.append(Vector3.INF)

	var d_tick := 0
	if cur_tick >= 0 and _prev_tick >= 0:
		d_tick = cur_tick - _prev_tick
	_prev_tick = cur_tick

	# Only the LIVE stretch is scored. Boot, the opener fast-forward and the seat all move
	# the tick counter in ways that say nothing about rendered movement.
	if combat_active and cur_tick > 0:
		if _combat_frame < 0:
			_combat_frame = _f
			print("[tick-jitter] combat live at frame %d (tick %d)" % [_f, cur_tick])
		else:
			_h_dtick.append(d_tick)
			_h_pos.append(positions.duplicate())
			_h_alpha.append(alpha)
			_h_cost.append(cost_ms)

	var row := "%d,%.3f,%d,%d,%d,%.4f" % [_f, cost_ms, int(combat_active), cur_tick, d_tick, alpha]
	for p in positions:
		row += ",%.6f,%.6f,%.6f" % [p.x, p.y, p.z]
	_rows.append(row)

	if _combat_frame > 0 and _h_dtick.size() >= _combat_frames:
		_done_reason = "%d combat frames" % _combat_frames
		_finish()
		return true
	if (Time.get_ticks_usec() - _start_us) > _max_s * 1000000:
		_finish()
		return true
	return false


var _skip_pushed := false


func _finish() -> void:
	_quit = true
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_line(_header())
		for r in _rows:
			f.store_line(r)
		f.close()
	print("[tick-jitter] %d frames (%d scored) → %s  [%s]"
		% [_f, _h_dtick.size(), _out, _done_reason])
	_verdict()


func _header() -> String:
	var h := "frame,cost_ms,combat_active,current_tick,d_tick,alpha"
	for i in range(MAX_UNITS):
		h += ",u%d_x,u%d_y,u%d_z" % [i, i, i]
	return h


## A unit-frame counts as IN MOTION when the unit moved across a window CENTRED on it.
## Asking only "did it move since last frame" would be circular: that is the very quantity
## the defect zeroes, so every frozen frame would grade itself as "not moving" and the
## duplicate rate would come out at zero no matter how bad the freeze is.
const MOTION_HALF_WINDOW := 3
const EPS := 0.0001


func _in_motion(u: int, f: int) -> bool:
	var a := maxi(f - MOTION_HALF_WINDOW, 0)
	var b := mini(f + MOTION_HALF_WINDOW, _h_pos.size() - 1)
	var pa: Vector3 = _h_pos[a][u]
	var pb: Vector3 = _h_pos[b][u]
	if pa == Vector3.INF or pb == Vector3.INF:
		return false
	return pa.distance_to(pb) > EPS


func _verdict() -> void:
	var n := _h_dtick.size()
	if n < 20:
		print("[tick-jitter] VERDICT: only %d scored frames — combat never went live. "
			% n + "Nothing measured; do not read this run as a negative.")
		return

	# --- TICK DRAIN: how many rendered frames advance the logical clock at all ----------
	var zero := 0
	var one := 0
	var many := 0
	for d in _h_dtick:
		if d <= 0: zero += 1
		elif d == 1: one += 1
		else: many += 1
	print("[tick-jitter] TICK DRAIN over %d frames: 0 ticks %.1f%%  1 tick %.1f%%  2+ %.1f%%"
		% [n, 100.0 * zero / n, 100.0 * one / n, 100.0 * many / n])

	# The BEAT — gaps between consecutive zero-tick frames. A metronome here is what makes
	# this a design fact rather than box noise.
	var gaps: Array[int] = []
	var last := -1
	for i in range(n):
		if _h_dtick[i] <= 0:
			if last >= 0:
				gaps.append(i - last)
			last = i
	if gaps.size() >= 3:
		gaps.sort()
		print("[tick-jitter] BEAT: %d zero-tick frames, gap median %d, min %d, max %d"
			% [zero, gaps[gaps.size() / 2], gaps[0], gaps[-1]])

	# --- FREEZE: the prediction ---------------------------------------------------------
	# Split in-motion unit-frames by whether a tick drained, and report the duplicate rate
	# of each arm. The defect predicts ~100% / ~0%. A pipeline that already smooths predicts
	# the two arms AGREE.
	var froz_z := 0
	var tot_z := 0
	var froz_t := 0
	var tot_t := 0
	var movers := {}
	for f in range(1, n):
		for u in range(MAX_UNITS):
			if not _in_motion(u, f):
				continue
			movers[u] = true
			var prev: Vector3 = _h_pos[f - 1][u]
			var cur: Vector3 = _h_pos[f][u]
			if prev == Vector3.INF or cur == Vector3.INF:
				continue
			var frozen := prev.distance_to(cur) <= EPS
			if _h_dtick[f] <= 0:
				tot_z += 1
				if frozen: froz_z += 1
			else:
				tot_t += 1
				if frozen: froz_t += 1

	if tot_z + tot_t == 0:
		print("[tick-jitter] VERDICT: NO UNIT EVER MOVED in %d combat frames. " % n
			+ "The freeze arm is unmeasured — this is a blind instrument, not a negative.")
		return

	print("[tick-jitter] MOVERS: units %s over %d in-motion unit-frames"
		% [str(movers.keys()), tot_z + tot_t])
	print("[tick-jitter] FREEZE | zero-tick frames: %d/%d duplicate positions (%.1f%%)"
		% [froz_z, tot_z, 100.0 * froz_z / maxi(tot_z, 1)])
	print("[tick-jitter] FREEZE | ticked frames   : %d/%d duplicate positions (%.1f%%)"
		% [froz_t, tot_t, 100.0 * froz_t / maxi(tot_t, 1)])

	var rate_z := 100.0 * froz_z / maxi(tot_z, 1)
	var rate_t := 100.0 * froz_t / maxi(tot_t, 1)
	if tot_z == 0:
		print("[tick-jitter] VERDICT: no zero-tick frame ever occurred — this display is "
			+ "phase-locked to the tick for this run. Not a negative for #1206.")
	elif rate_z > 90.0 and rate_t < 25.0:
		print("[tick-jitter] VERDICT: CONFIRMED. Walking units are bit-identical on "
			+ "%.1f%% of zero-tick frames and on only %.1f%% of ticked frames — " % [rate_z, rate_t]
			+ "the render clock is sampling an integer tick and #1206's fix is justified.")
	elif absf(rate_z - rate_t) < 15.0:
		# 🔴 READ THE DIRECTION BEFORE READING THIS LINE. Agreeing arms mean the tick drain
		# does not decide whether a unit redraws — which is the DEFECT ABSENT, not a failed
		# measurement. On a tree that carries the #1206 interpolation this is the PASS, and
		# the baseline it is compared against is 100.0%% vs 14.6%% (Gariland, 611 frames).
		# Only on a tree WITHOUT the fix does this reading kill the diagnosis.
		print("[tick-jitter] VERDICT: ARMS AGREE (%.1f%% vs %.1f%%). The position pipeline "
			% [rate_z, rate_t] + "is NOT quantised by the tick drain. If this tree carries "
			+ "the #1206 interpolation that is the PASS; if it does not, the diagnosis is "
			+ "KILLED and the subject is elsewhere.")
	else:
		print("[tick-jitter] VERDICT: PARTIAL (%.1f%% vs %.1f%%). Read the CSV."
			% [rate_z, rate_t])

	# The alpha actually observed — what the fix would have to spend. A run whose alpha
	# never leaves 0 has nothing to interpolate WITH.
	var a_min := 9.0
	var a_max := -9.0
	var a_sum := 0.0
	for a in _h_alpha:
		if a < 0.0:
			continue
		a_min = minf(a_min, a)
		a_max = maxf(a_max, a)
		a_sum += a
	print("[tick-jitter] ALPHA: min %.3f  mean %.3f  max %.3f (the remainder available "
		% [a_min, a_sum / maxi(_h_alpha.size(), 1), a_max] + "to interpolate with)")

	var c_sum := 0.0
	for c in _h_cost:
		c_sum += c
	print("[tick-jitter] frame cost mean %.2f ms (≈%.0f Hz) — CONTEXT ONLY, not the verdict"
		% [c_sum / n, 1000.0 * n / maxf(c_sum, 0.001)])
