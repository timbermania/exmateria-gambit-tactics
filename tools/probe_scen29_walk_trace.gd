extends SceneTree
## Scenario 29 PC 148 `{28} Walk To` / PC 173 `{29} Wait Walk` probe — the
## reproduction instrument for research/scenario29_walk_vs_jump/README.md.
## Boots scenario 29 LIVE (no fast-play, no rewind: fast-play forces
## `play_through_skip_unknown`, which clamps every motion to 1 s and would
## manufacture the very symptom under investigation) and logs unit 0x30's
## per-frame world position + motion state from PC 140 to PC 178.
##
##   # from the package root
##   godot --path . -s res://tools/probe_scen29_walk_trace.gd 2>&1 | tee /tmp/w29j.log
##
## Env:
##   SCEN=29        scenario id
##   FROM_PC=140    start logging once the main context reaches this PC
##   TO_PC=178      quit once it reaches this one
##   UID=48         unit to follow (0x30 = Alma)
##   MAXF=12000     safety frame cap
##   REWIND_PC=N    reach the beat by REWIND instead of playing it, reproducing
##                  what the F3 panel's double-click-PC does (README section 3
##                  reading 2 -- the fast-play clamps every motion to
##                  `play_through_max_ticks`, so the walk plays 3.7x too fast)
##   SHOT_DIR=/dir  drop a unit-centred 192x192 PNG crop every SHOT_STRIDE frames
##   SHOT_STRIDE=8  of walk progress

var _scene: Node
var _vm: Node
var _f := 0
var _quit := false
var _from := 140
var _to := 178
var _uid := 48
var _maxf := 12000
var _seen_motion := false
var _last_pc := -1
var _shot_dir := ""
var _shot_stride := 8
var _shot_n := 0
var _rewind_pc := -1
var _rewind_sent := false

func _initialize() -> void:
	var scen := 29
	if OS.has_environment("SCEN"): scen = int(OS.get_environment("SCEN"))
	if OS.has_environment("FROM_PC"): _from = int(OS.get_environment("FROM_PC"))
	if OS.has_environment("TO_PC"): _to = int(OS.get_environment("TO_PC"))
	if OS.has_environment("UID"): _uid = int(OS.get_environment("UID"))
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	if OS.has_environment("SHOT_DIR"): _shot_dir = OS.get_environment("SHOT_DIR")
	if OS.has_environment("SHOT_STRIDE"): _shot_stride = int(OS.get_environment("SHOT_STRIDE"))
	if OS.has_environment("REWIND_PC"): _rewind_pc = int(OS.get_environment("REWIND_PC"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = scen
	else:
		push_error("[w29j] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[w29j] booting scenario %d, trace pc %d..%d uid 0x%02X" % [scen, _from, _to, _uid])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if _f > _maxf:
		print("[w29j] frame cap")
		_quit = true
		return
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			_vm.dialog_auto_advance = true
			print("[w29j] VM found at f=%d" % _f)
		return
	# REWIND arm: reproduce what the F3 debug panel's double-click-PC does, so the
	# "reached the beat by rewinding" reading of the report can be told apart from
	# the "watched it play" reading.
	if _rewind_pc >= 0 and not _rewind_sent:
		if not _vm.is_fast_playing():
			_vm.set_rewind_target(_rewind_pc)
			if _vm.is_fast_playing() or _vm.get_pc() >= _rewind_pc:
				_rewind_sent = true
				print("[w29j] rewind -> pc=%d sent at f=%d" % [_rewind_pc, _f])
		return
	if _rewind_pc >= 0 and _vm.is_fast_playing():
		return
	var pc: int = _vm.get_pc()
	if pc != _last_pc:
		_last_pc = pc
	if pc < _from:
		if _f % 600 == 0:
			print("[w29j] warmup f=%d pc=%d" % [_f, pc])
		return
	var unit = _vm.units_by_id.get(_uid)
	var a = _vm.peek_actor(_uid)
	var mdesc := "none"
	if a != null and a.motion != null:
		var m = a.motion
		mdesc = "%s done=%s dur=%.3f" % [m.get_script().resource_path.get_file(),
			str(m.is_done()), float(m.dur_s)]
		if "total_frames" in m:
			mdesc += " tf=%.1f hf=%.1f wp=%d" % [m.total_frames, m._hf, m.waypoints.size()]
			if not _seen_motion:
				_seen_motion = true
				print("[w29j] MOTION ARMED at f=%d pc=%d fpt=%.2f tf=%.1f dur=%.3f" %
					[_f, pc, m.frames_per_tile, m.total_frames, m.dur_s])
				for i in m.waypoints.size():
					print("[w29j]   wp[%d] = %s" % [i, str(m.waypoints[i])])
	var pos := Vector3.ZERO
	var anim := -1
	# `facing_angle` is the ORIENTATION source of truth (ADR-0057) — the value a
	# zero-length `{28}` used to overwrite with the zero-vector NORTH. Traced because
	# position and anim alone cannot see a unit that stands still facing the wrong way,
	# which is exactly the scenario-29 pc 388 hug (`ScenarioZeroLengthWalkTest`).
	var facing := -1
	if unit != null and is_instance_valid(unit):
		pos = unit.global_position
		if "current_anim_id" in unit:
			anim = int(unit.current_anim_id)
		if "facing_angle" in unit:
			facing = int(unit.facing_angle)
	print("[w29j] f=%d pc=%d pos=(%.3f,%.3f,%.3f) anim=%d facing=0x%03X motion=%s" %
		[_f, pc, pos.x, pos.y, pos.z, anim, facing, mdesc])
	if _shot_dir != "" and a != null and a.motion != null and "total_frames" in a.motion:
		var hf := int(a.motion._hf)
		if hf % _shot_stride == 0:
			var f := "%s/hf%03d.png" % [_shot_dir, hf]
			var img := root.get_texture().get_image()
			var cam: Camera3D = root.get_viewport().get_camera_3d()
			if cam != null and unit != null and not cam.is_position_behind(pos):
				var sp: Vector2 = cam.unproject_position(pos)
				var r := Rect2i(int(sp.x) - 96, int(sp.y) - 150, 192, 192)
				r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
				if r.size.x > 8 and r.size.y > 8:
					img = img.get_region(r)
			img.save_png(f)
			_shot_n += 1
			print("[w29j] SHOT %s" % f)
	if pc >= _to:
		print("[w29j] reached TO_PC")
		_quit = true

func _find_vm(n: Node) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("ScenarioVM.gd"):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
