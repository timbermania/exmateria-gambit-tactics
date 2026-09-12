extends SceneTree
## [Park-freeze detector] The Phase-1 feedback loop for the scn6 "park doesn't
## freeze the frame" bug (HANDOFF_scn6_pace_alignment.md §3.1).
##
## Parks scenario 6 at a target PC (same F3 rewind path the capture rig uses),
## then samples every unit's rendered state across N consecutive host frames and
## asserts NOTHING drifts. If a Sprite-Move keeps interpolating, the camera keeps
## lerping, or a body/cinematic anim clock keeps advancing AFTER the VM parks,
## this prints RED with the first drift per field. A clean freeze prints GREEN.
##
## Fields watched per unit (5=Delita, 12=Ovelia, 6=chocobo):
##   gp        world position (catches Sprite-Move / Walk overrun)
##   anim      current_anim_id (static, sanity)
##   frame     rendered body/cinematic frame index (catches slow-mo anim)
##   motion    in-flight motion elapsed_s (catches un-frozen interpolation)
## Plus camera position + ortho size (catches camera lerp).
##
## Run (NEVER headless), from the package root:
##   PC=211 FRAMES=40 godot --path . -s res://tools/probe_park_freeze.gd
## Env: PC(211) FRAMES(40) — how many frames to watch after park.

var _scene: Node
var _vm: Node
var _f := 0
var _pc := 211
var _frames := 40
var _done := false
var _parked := false
var _watch_start := 0
var _base := {}            # field -> baseline value at park instant
var _drift := {}           # field -> [first_frame, base, now] on first change

const UIDS := [5, 12, 6]

func _initialize() -> void:
	if OS.has_environment("PC"): _pc = int(OS.get_environment("PC"))
	if OS.has_environment("FRAMES"): _frames = int(OS.get_environment("FRAMES"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _pc
	else:
		push_error("[pf] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[pf] booting scn6, park pc=%d, watch %d frames" % [_pc, _frames])

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

func _cam() -> Camera3D:
	return root.get_viewport().get_camera_3d()

## Rendered-frame reader: the per-unit anim_clock (Unit.gd:1083) pumps the three
## AnimationPlaybacks every render frame independent of VM paused. Read all three
## (body/weapon/effect) so slow-mo body-anim drift shows even for cinematic ids.
## Returns "body|wep|eff" frame indices as a Vector3i (== comparison catches drift).
func _frame_of(u) -> Vector3i:
	var disp = u.get("display") if ("display" in u) else null
	if disp == null: return Vector3i(-1, -1, -1)
	var out := Vector3i(-1, -1, -1)
	var pbs := [disp.get("type1_playback"), disp.get("wep1_playback"), disp.get("eff1_playback")]
	for i in 3:
		var pb = pbs[i]
		if pb != null and is_instance_valid(pb) and pb.has_method("get_current_frame"):
			out[i] = pb.get_current_frame()
	return out

func _snapshot() -> Dictionary:
	var s := {}
	var ubid = _vm.get("units_by_id")
	for uid in UIDS:
		if ubid == null or not ubid.has(uid) or not is_instance_valid(ubid[uid]):
			continue
		var u = ubid[uid]
		var gp: Vector3 = u.global_position
		s["u%d.gp" % uid] = gp
		s["u%d.anim" % uid] = int(u.current_anim_id)
		s["u%d.frame" % uid] = _frame_of(u)
		var a = _vm.peek_actor(uid)
		if a != null:
			var m = a.get("motion")
			s["u%d.motion_el" % uid] = (m.get("elapsed_s") if m != null else -1.0)
	var cam := _cam()
	if cam != null:
		s["cam.pos"] = cam.global_position
		s["cam.size"] = cam.size
	return s

func _differs(a, b) -> bool:
	if a is Vector3 and b is Vector3:
		return (a as Vector3).distance_to(b) > 0.0005
	if a is float and b is float:
		return absf(a - b) > 0.0005
	return a != b

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
			_watch_start = _f
			_base = _snapshot()
			print("[pf] PARKED at pc=%d (f=%d). baseline captured, watching %d frames..." % [
				_vm.get_pc(), _f, _frames])
			var bk: Array = _base.keys()
			bk.sort()
			for k in bk:
				print("[pf]   base %-16s = %s" % [k, str(_base[k])])
			# Full motion detail for u5/u12 — which move (if any) is frozen and where.
			for uid in [5, 12]:
				var a = _vm.peek_actor(uid)
				if a == null:
					print("[pf]   motion u%d: <no actor>" % uid); continue
				var m = a.get("motion")
				if m == null:
					print("[pf]   motion u%d: none (settled) home=%s" % [uid, str(a.get("home"))])
				else:
					print("[pf]   motion u%d: start=%s target=%s dur=%.4f el=%.4f done=%s" % [
						uid, str(m.get("start")), str(m.get("target")),
						m.get("dur_s"), m.get("elapsed_s"), str(m.is_done())])
			var mc = _vm.get("_contexts")
			if mc != null and mc.size() > 0:
				print("[pf]   main_ctx pc=%d wait_ticks=%s wait_until_valid=%s" % [
					mc[0].pc, str(mc[0].wait_ticks), str(mc[0].wait_until.is_valid())])
		elif _f > 4000:
			print("[pf] TIMEOUT never parked (pc=%d paused=%s)" % [
				_vm.get_pc(), str(_vm.get("_paused"))])
			_done = true
		return
	# Parked: sample and compare to baseline.
	var now := _snapshot()
	for k in _base.keys():
		if not now.has(k):
			continue
		if _drift.has(k):
			continue
		if _differs(_base[k], now[k]):
			_drift[k] = [_f - _watch_start, _base[k], now[k]]
	if _f - _watch_start >= _frames:
		_report()
		_done = true

func _report() -> void:
	print("\n[pf] ================ FREEZE VERDICT (pc=%d, %d frames) ================" % [_pc, _frames])
	if _drift.is_empty():
		print("[pf] GREEN — nothing drifted after park. Clean freeze.")
	else:
		print("[pf] RED — %d field(s) drifted after park (frame is NOT frozen):" % _drift.size())
		var keys: Array = _drift.keys()
		keys.sort()
		for k in keys:
			var d = _drift[k]
			print("[pf]   %-16s first moved @+%d frame:  %s  ->  %s" % [k, d[0], str(d[1]), str(d[2])])
	print("[pf] ==================================================================\n")

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
