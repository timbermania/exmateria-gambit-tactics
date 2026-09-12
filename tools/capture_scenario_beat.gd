extends SceneTree
## Blessed scenario-beat capture (godot-learning). Deterministically boot a
## scenario, replay to a specific instruction PC, HOLD there with animation live,
## screenshot, and dump every unit's world pos / screen pos / current anim id.
##
## This is the standard way to grab or inspect a specific scenario beat for
## PSX-parity work. Prefer it over hand-rolling a capture.
##
## ⚠ WHY IT NEVER SETS `paused`: `ScenarioVM.paused = true` stops the 60 Hz tick,
## and unit animation clocks are tick-driven — so pausing FREEZES every unit
## mid-animation. A paused grab yields a mid-pose frame (a unit caught mid-fall,
## a lerp caught mid-slide) that reads as a *position/spacing* bug when it's just
## an unfinished animation. This tool instead holds the beat via the natural
## DIALOGUE GATE: `set_rewind_target(pc)` replays-and-halts, then with
## `dialog_auto_advance = false` the VM waits at the open dialogue box while the
## tick — and thus every unit animation — keeps running. That's exactly what the
## F3 debug panel's double-click-PC does. (Best for dialogue-gated beats, the
## usual inspection target; a beat with no box to gate on will drift past the PC,
## so target the display-message instruction of the line you want to see.)
##
## Run (NOT headless — a window opens; stdout/log still return to you):
##   # from the package root
##   SCEN=2 TARGET_PC=283 SHOT=/tmp/beat.png \
##     godot --path . -s res://tools/capture_scenario_beat.gd
##
## Env:
##   SCEN=2            scenario id (default 2 = Orbonne chapel)
##   TARGET_PC=N       instruction INDEX into _insts to replay through + halt at
##                     (the VM pc is an array index, NOT a byte offset). Aim one
##                     past the display-message you want (halt condition is
##                     pc >= target), so the box is up when we grab.
##   SHOT=/path.png    output PNG (default /tmp/beat.png)
##   SETTLE=90         frames to let animation settle after the halt before grab
##   MAXF=3000         safety frame cap
##
## To compare against PSX: load the matching savestate in pcsx-redux and dump the
## roster (base 0x800B7308, stride 0x440): +0x40 = base world pos (x,y,z),
## +0x60 = Sprite-Move draw offset, +0x06 = sprite id, +0x120/122 = screen x,y.
## world/28 = tile; apply the ADR-0052 z-flip (godot_z = size_z - psx_z).

var _scene: Node
var _vm: Node
var _f := 0
var _frozen_at := -1
var _did := false
var _quit := false
var _shot := "/tmp/beat.png"
var _target_pc := 283
var _rewind_sent := false
var _settle := 90
var _maxf := 3000

func _initialize() -> void:
	if OS.has_environment("SHOT"): _shot = OS.get_environment("SHOT")
	if OS.has_environment("TARGET_PC"): _target_pc = int(OS.get_environment("TARGET_PC"))
	if OS.has_environment("SETTLE"): _settle = int(OS.get_environment("SETTLE"))
	if OS.has_environment("MAXF"): _maxf = int(OS.get_environment("MAXF"))
	var scen := 2
	if OS.has_environment("SCEN"): scen = int(OS.get_environment("SCEN"))
	var sess: Node = root.get_node_or_null("ScenarioDebugSession")
	if sess != null:
		sess.selected_scenario_id = scen
	else:
		push_error("[beat] ScenarioDebugSession autoload not found")
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	RenderingServer.global_shader_parameter_set("psx_dither_enabled", false)
	print("[beat] booting scenario %d, target_pc=%d, shot -> %s" % [scen, _target_pc, _shot])

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _box_text(box: Node) -> String:
	if box != null and "_text" in box and box._text != null:
		return str(box._text.text)
	return ""

func _on_post_draw() -> void:
	_f += 1
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm != null:
			print("[beat] VM found at f=%d" % _f)
		return

	# Once the chunk is loaded, deterministically replay to the target PC and halt
	# (set_rewind_target no-ops with a warning until _insts is populated, so keep
	# trying until it takes).
	if not _rewind_sent:
		if _vm.is_fast_playing():
			pass  # a boot-time fast-play is running; wait it out
		else:
			_vm.dialog_auto_advance = false
			_vm.set_rewind_target(_target_pc)
			if _vm.is_fast_playing() or _vm.get_pc() >= _target_pc:
				_rewind_sent = true
				print("[beat] rewind → pc=%d sent at f=%d" % [_target_pc, _f])
		return

	# Wait for the replay to reach the target, then hold via the dialogue gate.
	if _frozen_at < 0:
		if not _vm.is_fast_playing() and _vm.get_pc() >= _target_pc:
			_frozen_at = _f
			# NEVER set `paused` here — it freezes the tick and every unit
			# animation clock mid-pose. `dialog_auto_advance = false` + the open
			# box holds opcode dispatch while animation keeps ticking to settle.
			_vm.dialog_auto_advance = false
			print("[beat] halted (gated, not paused) at pc=%d, f=%d" % [_vm.get_pc(), _f])

	if _f % 120 == 0:
		print("[beat] f=%d ff=%s pc=%d frozen_at=%d" % [
			_f, str(_vm.is_fast_playing()), _vm.get_pc(), _frozen_at])

	var box: Node = _vm.box_pool._foreground_box() if _vm.box_pool != null else null
	var ready: bool = (_frozen_at >= 0 and _f >= _frozen_at + _settle) or (_f >= _maxf)
	if ready and not _did:
		_did = true
		_capture(box)
		_quit = true

func _capture(box: Node) -> void:
	var img := root.get_texture().get_image()
	img.save_png(_shot)
	print("[beat] ===== CAPTURED f=%d frozen_at=%d =====" % [_f, _frozen_at])
	print("[beat] box_text=\"%s\"" % _box_text(box))
	if _vm != null:
		_dump_units()

func _dump_units() -> void:
	print("[beat] --- unit world + screen positions + anim ---")
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var vp := root.get_viewport().get_visible_rect().size
	for iid in _vm.units_by_id:
		var u: Node = _vm.units_by_id[iid]
		if u != null and u is Node3D:
			var p: Vector3 = (u as Node3D).global_position
			var scr := "n/a"
			if cam != null and not cam.is_position_behind(p):
				var s: Vector2 = cam.unproject_position(p)
				# normalize to a 256x240 frame for direct PSX-screen comparison
				scr = "scr256=(%.1f, %.1f)" % [s.x / vp.x * 256.0, s.y / vp.y * 240.0]
			var anim := "?"
			if "display" in u and u.display != null:
				anim = "anim=0x%X" % int(u.display.current_anim_id)
			print("[beat] iid=%s %s pos=(%.3f, %.3f, %.3f) %s %s" % [
				str(iid), u.name, p.x, p.y, p.z, scr, anim])

func _find_vm(n: Node) -> Node:
	# Duck-type: the VM is instantiated via preload().new(), so `is ScenarioVM`
	# returns false — match on its fields instead.
	if ("box_pool" in n) and ("units_by_id" in n) and ("dialog_auto_advance" in n):
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
