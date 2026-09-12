extends SceneTree
## DIAGNOSTIC (READY!-fade-out freeze + camera jerk): drive the REAL
## linear walk into a battle group at time_scale 1.0 and record, per frame, the
## UNSCALED wall-clock cost of that frame and the camera's pose — so the stall and
## the pan can both be located against the event script's PC.
##
## The beat under investigation (scn 10, Gariland's opener, is the intro template):
##   {78} 00 3C   READY!      -> {E5} 38 00 -> {77} Remove Dark Screen -> {E5} 36 00
##   -> {DB} Event End -> run_pre_battle -> run_combat
##
## Run (headful, never --headless):
##   godot --path . -s res://tools/probe_ready_freeze.gd -- --battle=9 --watch-opener
##
## Env: OUT=/tmp/readyfreeze.csv  MAXS=150  (wall-clock seconds before it gives up)

var _nav: Node = null
var _vm = null
var _runner = null
var _f := 0
var _last_us := 0
var _out := "/tmp/readyfreeze.csv"
var _max_s := 150
var _start_us := 0
var _rows: Array[String] = []
var _quit := false
var _prev_cam_pos := Vector3.ZERO
var _prev_cam_fwd := Vector3.ZERO
var _have_prev_cam := false
## pc -> the first frame index it was observed at, so the CSV can be read against the script.
var _pc_first := {}
var _done_reason := "max time"
## `HEASE` override for `camera.handoff_ease_seconds`; NAN means "leave the default alone".
var _hease := NAN
var _hease_pushed := false
var _skip_pushed := false
## `FILM` output directory; empty means "do not film". See `_initialize`.
var _film_dir := ""
var _skip_pre_battle := false
var _film_armed := -1
var _film_saved := 0


func _initialize() -> void:
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	if OS.has_environment("MAXS"): _max_s = int(OS.get_environment("MAXS"))
	# HEASE=<seconds> sweeps `camera.handoff_ease_seconds` without an F3 scrub, so the
	# duration can be chosen from a series of traces rather than from an opinion.
	if OS.has_environment("HEASE"):
		_hease = float(OS.get_environment("HEASE"))
	# FILM=<dir> saves the reveal as a strip of PNGs. The scene screenshots ITSELF, so the
	# window never has to be on the user's workspace — `grim` aimed at an off-screen window
	# silently returns whatever IS visible instead, which looks like a successful capture.
	# OFF by default and it must stay that way: `save_png` costs ~10 ms a frame, which is
	# the same order as the hitches this probe exists to measure.
	# SKIPPB=1 arms `navigator.skip_pre_battle` — the OTHER handoff path, where
	# `run_pre_battle` returns before the loop and the cursor and `run_combat` builds both
	# instead. The seat and the glide are the same call; what surrounds them is not.
	_skip_pre_battle = OS.has_environment("SKIPPB")
	if OS.has_environment("FILM"):
		_film_dir = OS.get_environment("FILM")
		DirAccess.make_dir_recursive_absolute(_film_dir)
	Engine.time_scale = 1.0
	var scene: PackedScene = load("res://assets/scenes/NavigatorMain.tscn")
	_nav = scene.instantiate()
	root.add_child(_nav)
	_start_us = Time.get_ticks_usec()
	_last_us = _start_us
	print("[ready-freeze] probe up — recording to %s" % _out)


func _process(_delta: float) -> bool:
	if _quit:
		return true
	var now := Time.get_ticks_usec()
	var cost_ms := float(now - _last_us) / 1000.0
	_last_us = now
	_f += 1

	# `/root/Tune` is not resolvable at `_initialize()` — the autoload is not up yet — so the
	# override is pushed on the first real frame instead, long before the battle is reached.
	if not _hease_pushed and not is_nan(_hease):
		var tune := root.get_node_or_null("Tune")
		if tune != null:
			tune.set_value("camera.handoff_ease_seconds", _hease)
			_hease_pushed = true
			print("[ready-freeze] camera.handoff_ease_seconds := %.3f s" % _hease)
	if _skip_pre_battle and not _skip_pushed:
		var tune2 := root.get_node_or_null("Tune")
		if tune2 != null:
			tune2.set_value("navigator.skip_pre_battle", true)
			_skip_pushed = true
			print("[ready-freeze] navigator.skip_pre_battle := true")

	if _vm == null and _nav != null and "_vm" in _nav:
		_vm = _nav._vm
	if _runner == null and _nav != null and "_nav_runner" in _nav:
		_runner = _nav._nav_runner

	# --- camera ------------------------------------------------------------
	var cam := root.get_viewport().get_camera_3d()
	var cam_pos := Vector3.ZERO
	var cam_fwd := Vector3.ZERO
	var d_pos := 0.0
	var d_ang := 0.0
	# The THREE eases run on three separate counters. Read them straight off the rig
	# rather than inferring them from the pose — "do they line up" has to be a number.
	var follow_frame := -1
	var follow_total := -1
	var datum_blend := -1.0
	var follow_secs := 0.0
	var follow_secs_total := 0.0
	var returning := false
	var cam_mode := -1
	var datum_y := 0.0
	var yaw_deg := 0.0
	if cam != null:
		cam_pos = cam.global_position
		cam_fwd = -cam.global_transform.basis.z
		if _have_prev_cam:
			d_pos = cam_pos.distance_to(_prev_cam_pos)
			d_ang = rad_to_deg(_prev_cam_fwd.angle_to(cam_fwd))
		_prev_cam_pos = cam_pos
		_prev_cam_fwd = cam_fwd
		_have_prev_cam = true
		datum_y = cam.position.y
		var rig := cam.get_parent().get_parent() if cam.get_parent() != null else null
		if rig != null and "_follow_frame" in rig:
			follow_frame = int(rig._follow_frame)
			follow_total = int(rig.follow_ease_frames)
			# GUARDED FIELD BY FIELD, so this probe still runs against a rig that predates
			# the two-clock split — a trunk control arm is the whole reason it exists, and an
			# unguarded read errors EVERY FRAME while returning the type default, which reads
			# as a slow run rather than as a broken probe.
			if "_datum_blend_seconds" in rig:
				datum_blend = float(rig._datum_blend_seconds)
			elif "_datum_blend_frame" in rig:
				datum_blend = float(rig._datum_blend_frame)
			if "_follow_seconds" in rig:
				follow_secs = float(rig._follow_seconds)
				follow_secs_total = float(rig._follow_seconds_total)
			returning = bool(rig._returning)
			cam_mode = int(rig.camera_mode)
			if rig.focus_point != null:
				yaw_deg = rad_to_deg(rig.focus_point.global_rotation.y)

	# --- event script ------------------------------------------------------
	var pc := -1
	var op := ""
	var running := false
	if _vm != null and is_instance_valid(_vm):
		running = bool(_vm.is_running())
		pc = int(_vm.get_pc())
		if "_insts" in _vm and pc >= 0 and pc < _vm._insts.size():
			op = String(_vm._insts[pc].get("name", "?"))
		if not _pc_first.has(pc):
			_pc_first[pc] = [_f, op]

	# --- the two screens ---------------------------------------------------
	var res_live := false
	var res_mode := -1
	var res_elapsed := -1
	var dark_prog := -1.0
	var dark_settling := false
	if _vm != null and is_instance_valid(_vm):
		var rs = _vm._results_screen if "_results_screen" in _vm else null
		if rs != null and is_instance_valid(rs):
			res_live = bool(rs.is_live())
			res_mode = int(rs.mode())
			res_elapsed = int(rs.elapsed())
		var ds = _vm._dark_screen if "_dark_screen" in _vm else null
		if ds != null and is_instance_valid(ds):
			dark_prog = float(ds.progress())
			dark_settling = bool(ds.is_sweeping())

	# --- navigator ---------------------------------------------------------
	var nav_state := -1
	var nav_action := -1
	if _runner != null and is_instance_valid(_runner):
		nav_state = int(_runner.current_state)
		nav_action = int(_runner.current_action_index)
	var loop_up := false
	var combat_active := false
	if _nav != null and is_instance_valid(_nav):
		loop_up = _nav._combat_loop != null and is_instance_valid(_nav._combat_loop)
		combat_active = bool(_nav._combat_active)

	_rows.append(("%d,%.3f,%d,%d,%s,%d,%d,%d,%d,%.4f,%d,%d,%d,%d,%.4f,%.4f,%.3f,%.3f,%.3f"
		+ ",%d,%d,%.4f,%d,%d,%.4f,%.2f,%.4f,%.4f") % [
		_f, cost_ms, int(running), pc, op,
		int(res_live), res_mode, res_elapsed,
		int(dark_settling), dark_prog,
		nav_state, nav_action, int(loop_up), int(combat_active),
		d_pos, d_ang, cam_pos.x, cam_pos.y, cam_pos.z,
		follow_frame, follow_total, datum_blend, int(returning), cam_mode,
		datum_y, yaw_deg, follow_secs, follow_secs_total])

	# Stop a fixed distance PAST the handoff, so the trace always covers the whole
	# window and never only half of it. The loop coming up is the handoff's first
	# act on both paths (parked at Deployment, or straight through to combat).
	# Film the reveal: arm on the frame the retract clears, then every 3rd frame for ~1.6 s,
	# which covers the dead beat and the whole glide at either duration.
	if _film_dir != "":
		if _film_armed < 0 and dark_prog == 0.0 and loop_up:
			_film_armed = _f
		if _film_armed > 0 and _film_saved < 34 and (_f - _film_armed) % 3 == 0:
			# NO `await RenderingServer.frame_post_draw` HERE. `MainLoop._process` returns a
			# bool the SceneTree reads as "quit"; awaiting inside it makes it return a
			# coroutine instead and the run never ends. So the grab is of the frame just
			# PRESENTED — the strip is one frame behind its filename, which is irrelevant
			# to the thing it is for (what the reveal looks like).
			var img := root.get_texture().get_image()
			if img != null:
				img.save_png("%s/f%04d.png" % [_film_dir, _f])
				_film_saved += 1

	# ANCHOR ON THE REVEAL, NOT ON THE LOOP. `loop_up` was the handoff's first act for as long as
	# the battle was built after the event script ended; the build can now be PREWARMED under the
	# `{76}` dim (`NavigatorMain._prewarm_battle_under_the_dark`), which moves `loop_up` hundreds
	# of frames earlier and made this stop cut the trace off BEFORE the retract it exists to
	# measure — reported as "NO SUBJECT", which reads like a broken game rather than a mis-aimed
	# probe. The reveal is the subject either way, so anchor there: a dim went fully up, and has
	# now fully cleared, with a battle standing behind it.
	if dark_prog >= 0.99:
		_saw_dark = true
	if _saw_dark and loop_up and dark_prog <= 0.0:
		if _loop_frame < 0:
			_loop_frame = _f
		elif _f - _loop_frame > 180:
			_done_reason = "field revealed + 180 frames"
			_finish()
			return true
	if (Time.get_ticks_usec() - _start_us) > _max_s * 1000000:
		_finish()
		return true
	return false


## Has a `{76}` dim been fully established at any point? The reveal anchor's first half.
var _saw_dark := false


## The frame the revealed field first stood behind a cleared dim — the handoff's anchor.
var _loop_frame := -1


func _finish() -> void:
	_quit = true
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_line(_HEADER)
		for r in _rows:
			f.store_line(r)
		f.close()
	print("[ready-freeze] wrote %d frames to %s (stop: %s)" % [_rows.size(), _out, _done_reason])
	_verdict()


## The point of the run, in the log — so reading the CSV is optional. A frame over
## `FREEZE_MS` is the reported stall; the largest single-frame camera step is the
## reported jerk. Both are printed with the event-script PC they landed on, because
## "when" is the whole claim: the beat under investigation is the ONE frame between
## READY! dying and the battle standing up.
const FREEZE_MS := 100.0
const JERK_UNITS := 1.0

func _verdict() -> void:
	var worst_cost := 0.0
	var worst_cost_row := ""
	var worst_jump := 0.0
	var worst_jump_row := ""
	var over := 0
	# SCORE THE BEAT, NOT THE BOOT. The scene's first ~10 frames cost hundreds of ms
	# and move the camera 160 units as it is first placed — real, and not what this
	# probe is about. The window opens on the frame the intro's first {78} screen goes
	# live, which is the earliest frame the reported defect could possibly be on.
	var started := false
	for r in _rows:
		var f: PackedStringArray = r.split(",")
		if not started:
			if f[5] != "1":
				continue
			started = true
		var cost := float(f[1])
		var jump := float(f[14])
		if cost >= FREEZE_MS:
			over += 1
		if cost > worst_cost:
			worst_cost = cost
			worst_cost_row = r
		if jump > worst_jump:
			worst_jump = jump
			worst_jump_row = r
	if not started:
		print("[ready-freeze] VERDICT: NO SUBJECT — no {78} screen ever went live, "
			+ "so the intro never played and nothing was measured")
		return
	print("[ready-freeze] VERDICT: %d frame(s) over %.0f ms; worst %.1f ms; worst camera step %.3f units"
		% [over, FREEZE_MS, worst_cost, worst_jump])
	print("[ready-freeze]   slowest frame: %s" % worst_cost_row)
	print("[ready-freeze]   biggest jump:  %s" % worst_jump_row)
	print("[ready-freeze]   columns: %s" % _HEADER)
	_shape_verdict()


## SCORE THE SHAPE, NOT THE SPIKE (#1168 follow-up).
##
## The first pass took the worst frame from 469-1547 ms to ~60 ms and the worst camera
## step from 6.64 units to 0.625 — and the report did not go away, it MOVED: "the jerk
## is now after the ready fade". Neither number above can see that, because neither is
## a claim about MOTION. A beat can have every frame inside budget and still read as a
## lurch if the field sits dead still and then the camera snaps into a fast push-in.
##
## So this half scores the window that opens the frame the dark screen's retract ENDS:
##
## - DEAD BEAT — frames (and ms) between the full reveal and the camera's first move.
##   A static hold before a fast move is a jerk the per-frame budget cannot see.
## - JERK — the second difference of the per-frame step. A clean cosine ease has a
##   small, smooth third derivative; a clipped, restarted or overlapping ease spikes.
## - THE THREE EASES' WINDOWS — the body glide, the vertical framing datum and
##   the rotation lerp each ran on their own counter. "Do they line up" is printed as
##   three [start,end] pairs, not an opinion.
## - ROTATION — `d_cam_deg` has been recorded since the first pass and nothing had ever
##   read it. A yaw discontinuity under a moving body reads as the same defect.
const EPS_POS := 0.0005
const EPS_DEG := 0.01

func _shape_verdict() -> void:
	var rows: Array[PackedStringArray] = []
	for r in _rows:
		rows.append(r.split(","))
	# The reveal: the first frame `dark_prog` reads 0 after having been above it.
	var reveal := -1
	var seen_dark := false
	for i in rows.size():
		var dp := float(rows[i][9])
		if dp > 0.001:
			seen_dark = true
		elif seen_dark and reveal < 0:
			reveal = i
	if reveal < 0:
		print("[ready-freeze] SHAPE: NO SUBJECT — the dark screen never retracted")
		return

	# --- the dead beat -----------------------------------------------------
	var move_start := -1
	for i in range(reveal, rows.size()):
		if float(rows[i][14]) > EPS_POS:
			move_start = i
			break
	var dead_ms := 0.0
	var dead_frames := 0
	if move_start > reveal:
		for i in range(reveal, move_start):
			dead_ms += float(rows[i][1])
			dead_frames += 1
	print("[ready-freeze] SHAPE: reveal at frame %d (cam %s,%s,%s)"
		% [int(rows[reveal][0]), rows[reveal][16], rows[reveal][17], rows[reveal][18]])
	print("[ready-freeze]   DEAD BEAT: %d frame(s) / %.1f ms of a revealed, motionless field"
		% [dead_frames, dead_ms])
	if move_start < 0:
		print("[ready-freeze]   the camera never moved after the reveal")
		return

	# --- the move ----------------------------------------------------------
	# It ends at the last frame of the run that starts at `move_start`, where a run is
	# broken by 8 consecutive still frames (the cosine's own tail is never that flat).
	var move_end := move_start
	var still := 0
	for i in range(move_start, rows.size()):
		if float(rows[i][14]) > EPS_POS:
			move_end = i
			still = 0
		else:
			still += 1
			if still >= 8:
				break
	var steps: Array[float] = []
	var travel := 0.0
	var ms := 0.0
	var peak := 0.0
	for i in range(move_start, move_end + 1):
		var d := float(rows[i][14])
		steps.append(d)
		travel += d
		ms += float(rows[i][1])
		peak = maxf(peak, d)
	print(("[ready-freeze]   MOVE: frames %d-%d (%d frames / %.1f ms), %.3f units, "
		+ "peak step %.4f u/frame, mean %.4f")
		% [int(rows[move_start][0]), int(rows[move_end][0]), steps.size(), ms, travel,
			peak, travel / maxf(1.0, float(steps.size()))])
	print("[ready-freeze]   JERK (pos): %s" % _jerk_line(steps))
	print("[ready-freeze]   CLOCK LAG: %s" % _clock_lag(rows, move_start, move_end))

	# 🔴 THE METRIC THE FIRST PASS DID NOT HAVE. Every ease on this rig is FRAME-COUNTED
	# (`_follow_frame`, `_return_frame`, `_datum_blend_frame`), so its wall-clock speed is
	# whatever the frame pacing happens to be. That is fine at a steady 60 Hz and wrong
	# straight after a hitch: the swapchain drains, Godot renders three or four frames in
	# a couple of ms each, and the ease burns a quarter of its travel in a fifth of its
	# budget. The per-frame STEP stays smooth (so `JERK` above reads clean) while the
	# thing the player actually sees — units per SECOND — spikes. Score the seconds.
	var vel: Array[float] = []
	for i in range(move_start, move_end + 1):
		# cost_ms[i+1] is the wall clock the step applied on frame i was on screen for.
		if i + 1 >= rows.size():
			break
		var dt := float(rows[i + 1][1]) / 1000.0
		if dt <= 0.0:
			continue
		vel.append(float(rows[i][14]) / dt)
	var v_peak := 0.0
	var v_at := -1
	for i in vel.size():
		if vel[i] > v_peak:
			v_peak = vel[i]
			v_at = i
	var v_nominal := travel / maxf(0.001, ms / 1000.0)
	print(("[ready-freeze]   VELOCITY: mean %.1f u/s over the move; PEAK %.1f u/s "
		+ "at step %d (%.2fx mean)")
		% [v_nominal, v_peak, v_at, v_peak / maxf(0.001, v_nominal)])

	# --- rotation, which nothing had ever read -----------------------------
	var rot: Array[float] = []
	var rot_total := 0.0
	var rot_peak := 0.0
	for i in range(reveal, mini(rows.size(), move_end + 9)):
		var d := float(rows[i][15])
		rot.append(d)
		rot_total += d
		rot_peak = maxf(rot_peak, d)
	if rot_total <= EPS_DEG:
		print("[ready-freeze]   ROTATION: still — %.3f deg total over the window" % rot_total)
	else:
		print("[ready-freeze]   ROTATION: %.3f deg total, peak %.4f deg/frame; %s"
			% [rot_total, rot_peak, _jerk_line(rot)])

	# --- the three counters ------------------------------------------------
	print("[ready-freeze]   EASES: body %s | datum %s | %s"
		% [_span(rows, reveal, 19, 20), _datum_span(rows, reveal), _rot_span(rows, reveal)])


## max |d[i] - 2*d[i-1] + d[i-2]| over a step series, plus how it compares to the peak
## step. A pure 18-frame cosine over this travel scores ~0.01; a restart or a clip spikes.
func _jerk_line(steps: Array[float]) -> String:
	if steps.size() < 3:
		return "too short to score (%d samples)" % steps.size()
	var worst := 0.0
	var at := -1
	for i in range(2, steps.size()):
		var j: float = absf(steps[i] - 2.0 * steps[i - 1] + steps[i - 2])
		if j > worst:
			worst = j
			at = i
	var peak := 0.0
	for d in steps:
		peak = maxf(peak, d)
	return "peak |2nd diff| %.5f at sample %d (%.1f%% of peak step)" % [
		worst, at, 100.0 * worst / maxf(1e-9, peak)]


## 🔴 THE METRIC THAT SEPARATES THE TWO CLOCKS, and the one to read first.
##
## `JERK` above is the second difference of the per-FRAME step, so it silently assumes every
## frame lasted the same. Under a frame-counted ease that assumption is what hides the defect
## (a burst of 3 ms frames advances the ease at four times its intended speed while every
## per-frame step stays a textbook cosine). Under a clock-driven ease it INVENTS one: a 28 ms
## frame legitimately carries a double-length step, which is the camera being in the right
## place at the right time, and `JERK` reports it as a 98 %-of-peak spike. Neither reading is
## about what the eye sees.
##
## What the eye sees is position as a function of WALL CLOCK. So: how far has the ease's own
## progress drifted from the wall clock elapsed since it started? A clock-driven ease tracks
## to within one frame by construction. A frame-counted one leads or lags by however much the
## frame pacing drifted — and LEADING is the reported jerk, because it means the camera got
## somewhere before the player's clock said it should.
##
## Reported in ms of drift and as a fraction of the whole ease. Needs the `follow_secs`
## column, so it says so rather than lying when the frame-counted path is the live one.
func _clock_lag(rows: Array[PackedStringArray], from: int, to: int) -> String:
	var total := float(rows[to][27])
	if total <= 0.0:
		# The frame-counted path. Reconstruct its nominal progress from the counter and
		# compare that against the wall clock the same way.
		total = float(rows[to][20]) / 60.0
		if total <= 0.0:
			return "no ease clock on either path"
		var wall_f := 0.0
		var worst_f := 0.0
		for i in range(from, to + 1):
			wall_f += float(rows[i][1]) / 1000.0
			var prog := float(rows[i][19]) / 60.0
			worst_f = maxf(worst_f, prog - wall_f)
		return ("frame-counted (%.0f ms nominal); ease LEADS the wall clock by up to "
			+ "%.1f ms (%.0f%% of the ease)") % [total * 1000.0, worst_f * 1000.0,
				100.0 * worst_f / total]
	var wall := 0.0
	var worst := 0.0
	for i in range(from, to + 1):
		wall += float(rows[i][1]) / 1000.0
		worst = maxf(worst, absf(float(rows[i][26]) - wall))
	return ("clock-driven (%.0f ms nominal); ease tracks the wall clock to %.1f ms "
		+ "(%.0f%% of the ease)") % [total * 1000.0, worst * 1000.0, 100.0 * worst / total]


## `_follow_frame` climbing 0 -> `follow_ease_frames`: [first frame it advanced, the
## frame it landed], as absolute frame numbers.
func _span(rows: Array[PackedStringArray], from: int, col: int, total_col: int) -> String:
	var start := -1
	var end := -1
	for i in range(from, rows.size()):
		# Whichever clock is live: `_follow_seconds_total > 0` means `ease_onto` armed the
		# wall-clock glide, otherwise the frame counter is the one advancing.
		var v := float(rows[i][col])
		var t := float(rows[i][total_col])
		if float(rows[i][27]) > 0.0:
			v = float(rows[i][26])
			t = float(rows[i][27])
		if v < 0.0 or t <= 0.0:
			continue
		if start < 0 and v > 0.0 and v < t:
			start = i
		if start >= 0 and v >= t:
			end = i
			break
	if start < 0:
		return "body: never eased"
	return "body: %d-%s (%s frames)" % [int(rows[start][0]),
		str(int(rows[end][0])) if end >= 0 else "?",
		str(end - start + 1) if end >= 0 else "?"]


func _datum_span(rows: Array[PackedStringArray], from: int) -> String:
	var start := -1
	var end := -1
	for i in range(from, rows.size()):
		var v := float(rows[i][21])
		if start < 0 and v >= 0.0:
			start = i
		elif start >= 0 and v < 0.0:
			end = i
			break
	if start < 0:
		return "datum: never blended"
	return "datum: %d-%s (%s frames)" % [int(rows[start][0]),
		str(int(rows[end][0])) if end >= 0 else "?",
		str(end - start + 1) if end >= 0 else "?"]


func _rot_span(rows: Array[PackedStringArray], from: int) -> String:
	var start := -1
	var end := -1
	for i in range(from, rows.size()):
		if float(rows[i][15]) > EPS_DEG:
			if start < 0:
				start = i
			end = i
	if start < 0:
		return "rot: never turned"
	return "rot: %d-%d (%d frames)" % [int(rows[start][0]), int(rows[end][0]), end - start + 1]


const _HEADER := ("frame,cost_ms,vm_running,pc,op,res_live,res_mode,res_elapsed,"
	+ "dark_settling,dark_prog,nav_state,nav_action,loop_up,combat_active,"
	+ "d_cam_pos,d_cam_deg,cam_x,cam_y,cam_z,"
	+ "follow_frame,follow_total,datum_blend,returning,cam_mode,datum_y,yaw_deg,"
	+ "follow_secs,follow_secs_total")
