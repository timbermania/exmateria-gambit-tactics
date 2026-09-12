extends SceneTree
## [Godot pace recorder] Free-run counterpart to the PSX single-pass poller
## (tmp_pace/psx_score.json). Fast-plays scenario 6 to a pre-beat PC, RELEASES
## the park into real-time free-run, and records — keyed on the VM's monotonic
## 60 Hz `_vm_tick` (the analogue of a PSX vsync) — every unit's anim id + world
## pos + screen pos as the carry choreography plays through. Emits a CSV timeline
## that lines up 1:1 with the PSX vsync score once anchored on a shared anim
## transition (e.g. Delita 4->516).
##
## Why free-run, not per-PC park: parking reload-per-PC distorts pace (user's
## load-vs-step note). A single continuous playthrough records the true in-order
## trajectory, exactly like the PSX poller.
##
## Run (NEVER headless), from the package root:
##   START_PC=130 MAX_TICKS=420 OUT=tmp_pace/godot_timeline.csv \
##     godot --path . -s res://tools/record_carry_timeline.gd
## Env: START_PC(130) MAX_TICKS(420) STOP_PC(225) OUT

var _scene: Node
var _vm: Node
var _f := 0
var _start_pc := 130
var _stop_pc := 225
var _max_ticks := 420
var _out := "tmp_pace/godot_timeline.csv"
var _done := false
var _released := false
var _last_tick := -1
var _rows: Array = []
var _released_tick := -1

const UIDS := [5, 12, 6]

func _initialize() -> void:
	if OS.has_environment("START_PC"): _start_pc = int(OS.get_environment("START_PC"))
	if OS.has_environment("STOP_PC"): _stop_pc = int(OS.get_environment("STOP_PC"))
	if OS.has_environment("MAX_TICKS"): _max_ticks = int(OS.get_environment("MAX_TICKS"))
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = 6
		sess.rewind_target_pc = _start_pc
	else:
		push_error("[rec] ScenarioDebugSession autoload not found")
	root.content_scale_size = Vector2i(256, 256)
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	print("[rec] booting scn6, fast-play to pc=%d then free-run to pc=%d (max %d ticks)" % [
		_start_pc, _stop_pc, _max_ticks])

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

func _screen_of(u) -> Vector2:
	var mesh = u.get("mesh_instance")
	if mesh == null or not is_instance_valid(mesh): return Vector2(-1, -1)
	var cam := _cam()
	if cam == null: return Vector2(-2, -2)
	return cam.unproject_position(mesh.global_position)

func _record() -> void:
	var t := int(_vm.get("_vm_tick"))
	if t == _last_tick:
		return
	_last_tick = t
	var ubid = _vm.get("units_by_id")
	var row := {"tick": t, "pc": _vm.get_pc()}
	for uid in UIDS:
		if ubid != null and ubid.has(uid) and is_instance_valid(ubid[uid]):
			var u = ubid[uid]
			row["a%d" % uid] = int(u.current_anim_id)
			var gp: Vector3 = u.global_position
			row["gp%d" % uid] = gp
			var sp := _screen_of(u)
			row["sp%d" % uid] = sp
		else:
			row["a%d" % uid] = -1
			row["gp%d" % uid] = Vector3.ZERO
			row["sp%d" % uid] = Vector2(-1, -1)
	_rows.append(row)

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
		return
	if not _released:
		# Wait for the fast-play to park at START_PC, then release into free-run.
		if _vm.get_pc() >= _start_pc and _vm.get("_paused") and not _vm.is_fast_playing():
			_released = true
			_vm.dialog_auto_advance = true
			_vm.play_through_skip_unknown = true
			_vm.set("_paused", false)   # release the park -> real-time 60Hz advance
			_released_tick = int(_vm.get("_vm_tick"))
			print("[rec] released at pc=%d vm_tick=%d (f=%d); recording..." % [
				_vm.get_pc(), _released_tick, _f])
			_record()
		elif _f > 6000:
			print("[rec] TIMEOUT never parked at start (pc=%d paused=%s ff=%s)" % [
				_vm.get_pc(), str(_vm.get("_paused")), str(_vm.is_fast_playing())])
			_done = true
		return
	_record()
	var t := int(_vm.get("_vm_tick"))
	if _vm.get_pc() >= _stop_pc or (t - _released_tick) >= _max_ticks:
		_write()
		_done = true

func _write() -> void:
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f == null:
		push_error("[rec] cannot open %s" % _out)
		return
	f.store_line("tick,pc,a5,a12,a6,gp5x,gp5y,gp5z,gp12x,gp12y,gp12z,gp6x,gp6y,gp6z,sp5x,sp5y,sp12x,sp12y,sp6x,sp6y")
	for r in _rows:
		var g5: Vector3 = r["gp5"]; var g12: Vector3 = r["gp12"]; var g6: Vector3 = r["gp6"]
		var s5: Vector2 = r["sp5"]; var s12: Vector2 = r["sp12"]; var s6: Vector2 = r["sp6"]
		f.store_line("%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [
			r["tick"], r["pc"], r["a5"], r["a12"], r["a6"],
			g5.x, g5.y, g5.z, g12.x, g12.y, g12.z, g6.x, g6.y, g6.z,
			s5.x, s5.y, s12.x, s12.y, s6.x, s6.y])
	f.close()
	print("[rec] wrote %d rows -> %s (first tick=%d last tick=%d)" % [
		_rows.size(), _out, _rows[0]["tick"] if _rows.size() > 0 else -1,
		_rows[-1]["tick"] if _rows.size() > 0 else -1])

func _init() -> void:
	RenderingServer.frame_post_draw.connect(_on_post_draw)
