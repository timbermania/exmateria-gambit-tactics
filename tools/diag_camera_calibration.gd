extends SceneTree
## Single-axis camera CALIBRATION RIG (opcode-tweak variant).
##
## Per the user's steer (2026-06-29): don't synthesize a top-down pose. Instead
## re-apply the REAL settled chapel keyframe opcode (scenario_1 PC48:
## X=840 Z=-220 Y=504 Angle=302 MapRot=3584 CamRot=0 Zoom=4096) through the REAL
## transform (`ScenarioVM._compute_camera_godot_pose` -> `apply_takeover`), with
## ONE field overridable via env var. Camera keyframes are ABSOLUTE, so only this
## one frame matters -- no swoop replay. This isolates each axis's screen
## sensitivity inside the production pipeline (not a synthetic bypass).
##
## Procedure: let the cinematic run + units settle, latch the settled pose, then
## every frame re-apply OUR (possibly tweaked) keyframe so the cinematic can't
## clobber it. (It used to also zero `camera_position_offset`; that member no
## longer exists anywhere in src/ and the re-applied pose is absolute anyway.) Capture on
## frame_post_draw: screenshot + each unit's `unproject_position`, reported in
## native 256x240 px (native = viewport.x*0.2, viewport.y*0.25; center 128,120).
##
## Run (NOT headless):
##   godot --path . -s res://tools/diag_camera_calibration.gd
## Env (each defaults to the settled keyframe value; set ONE to sweep an axis):
##   CAMX  CAMY  CAMZ  CAMANG  CAMMAP  CAMROLL  CAMZOOM   -- opcode fields (ints)
##   BACKROT=0|1   -- override vm.camera_backrotate_pivot (exact-R orientation)
##   SHOT=/tmp/godot_calib.png

# Settled chapel keyframe (scenario_1_chunk.json instructions[48]).
const DEF := {
	"X": 840, "Y": 504, "Z": -220,
	"ANG": 302, "MAP": 3584, "ROLL": 0, "ZOOM": 4096,
}
# PSX ground truth — LIVE-READ from the settled savestate's per-unit screen store
# (node +0x120 − 128 = on-screen-X, +0x122 = on-screen-Y), F19. Supersedes the
# stale F7 hand-reads (which had Ovelia at 136 — actually 147 — corrupting the
# per-unit residual analysis until F19).
const PSX_REF := {
	0x34: Vector2(107, 160),   # Agrias (blue Holy Knight)  node 0x800b7748
	0x0C: Vector2(147, 114),   # Ovelia                     node 0x800ba608
	0x13: Vector2(68, 142),    # priest                     node 0x800b7308
}

var _scene: Node
var _vm: Node
var _f := 0
var _settled_at := -1
var _max_frame := 2600
var _shot := "/tmp/godot_calib.png"
var _did := false
var _quit := false
var _pose := {}
var _booted := false
var _pin_scenario := 2
var _stable := 0
var _last_bx := INF
var _last_ortho := INF
var _last_ag := Vector3(INF, INF, INF)

func _initialize() -> void:
	_shot = OS.get_environment("SHOT") if OS.has_environment("SHOT") else _shot
	# Pin the CHAPEL. This rig calibrates scenario_1 (PC48, Agrias 0x34 at native 107/158),
	# but ScenarioPlayer.tscn does not default to it: with no pick made, `_boot` parks
	# DEFAULT_PATH_TARGET (= 8) and PATH-walks group root 7, "Military Academy (Setup)" on
	# MAP024 — no 0x34 anywhere on it. The rig had no pin, so it silently booted the wrong
	# map and the whole calibration apparatus (this rig and the three
	# ScenarioCamera*CalibTest siblings promoted from it) was measuring a scene it was never
	# written against. SCENARIO=N overrides for sweeping another map.
	# Looked up by NODE PATH, not by the autoload identifier: this file runs as a `-s`
	# MainLoop, where autoload names are not compile-time globals — a bare
	# `ScenarioDebugSession` is a hard "Identifier not found" compile error that stops the
	# rig from loading at all.
	# 2, not 1. Scenario 1 is `scenario_001_chunk.json`, 'Orbonne Prayer (Setup)' — SEVEN
	# instructions (No-op, Reveal, Wait, Event End), no camera keyframe, no cinematic. The
	# PC48 keyframe in DEF above is instruction 48 of `scenario_002_chunk.json` (TEST.EVT
	# event 2, 404 instructions), the only pc-48 Camera in the chunk set whose fields match
	# DEF, and unit 0x34 appears in 40 of its opcodes.
	var scenario_id := 2
	if OS.has_environment("SCENARIO"):
		scenario_id = int(OS.get_environment("SCENARIO"))
	_pin_scenario = scenario_id
	RenderingServer.frame_post_draw.connect(_on_post_draw)

## Boot the world on the FIRST frame, not in _initialize.
##
## Autoloads do not exist yet when a `-s` MainLoop's _initialize runs — the lookup returned
## null there, so the pin was silently dropped and the rig booted ScenarioPlayer's
## DEFAULT_PATH_TARGET (= 8, the Military Academy) exactly as before. By the first _process
## the autoloads are up, so the pin lands and the scene is instantiated AFTER it.
func _boot_world() -> void:
	var sds := root.get_node_or_null("/root/ScenarioDebugSession")
	if sds == null:
		push_error("[calib] ScenarioDebugSession still absent on the first frame — cannot pin "
			+ "scenario %d; refusing to calibrate against an unknown map" % _pin_scenario)
		_quit = true
		return
	sds.path_target_scenario_id = _pin_scenario
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	if _quit:
		quit()
		return true
	if not _booted:
		_booted = true
		_boot_world()
	return false

func _envi(key: String, deflt: int) -> int:
	var name := "CAM" + key
	return int(OS.get_environment(name)) if OS.has_environment(name) else deflt

func _opcode() -> Dictionary:
	return {
		"X": _envi("X", DEF["X"]), "Y": _envi("Y", DEF["Y"]), "Z": _envi("Z", DEF["Z"]),
		"ANG": _envi("ANG", DEF["ANG"]), "MAP": _envi("MAP", DEF["MAP"]),
		"ROLL": _envi("ROLL", DEF["ROLL"]), "ZOOM": _envi("ZOOM", DEF["ZOOM"]),
	}

func _apply_override() -> void:
	# Force offset to zero (handoff: it can never be a persistent fix) and drive
	# OUR keyframe through the real transform so the cinematic can't clobber it.
	# `camera_position_offset` no longer exists on ANY object in src/ — it was removed with
	# the camera extraction, so the assignment here was dead. The pose is driven wholly by
	# the opcode below, which is what the offset was being zeroed to guarantee.
	var op := _opcode()
	_pose = _vm.camera_director._compute_camera_godot_pose(
		float(op["X"]), float(op["Y"]), float(op["Z"]),
		float(op["ANG"]), float(op["MAP"]), float(op["ROLL"]), float(op["ZOOM"]))
	# EXPERIMENT (F19): override the camera BODY depth (godot_pos.z) to test the
	# "body not depth-flipped like ADR-0052 units" hypothesis. BODYZ sets pos.z
	# absolutely; BODYZFLIP=<size> sets pos.z = size - pos.z (mirror the unit flip).
	if OS.has_environment("BODYZ"):
		var p: Vector3 = _pose["pos"]; p.z = float(OS.get_environment("BODYZ")); _pose["pos"] = p
	if OS.has_environment("BODYZFLIP"):
		var p2: Vector3 = _pose["pos"]; p2.z = float(OS.get_environment("BODYZFLIP")) - p2.z; _pose["pos"] = p2
	_vm.player_camera.apply_takeover(_pose["pos"], _pose["rot"], _pose["ortho"])

func _on_post_draw() -> void:
	_f += 1
	# The world is instantiated on the first _process now, so _scene is null for the first
	# frame or two — _find_vm(null) would throw inside a signal callback.
	if _scene == null:
		if _f % 180 == 0:
			print("[calib] f=%d waiting for world boot (scene=null)" % _f)
		return
	if _vm == null:
		_vm = _find_vm(_scene)
		if _vm == null and _f % 180 == 0:
			print("[calib] f=%d scene up but VM not found yet" % _f)
		if _vm != null and OS.has_environment("BACKROT"):
			_vm.camera_director.camera_backrotate_pivot = OS.get_environment("BACKROT") == "1"
			print("[calib] BACKROT override -> %s" % str(_vm.camera_director.camera_backrotate_pivot))
		return
	var cam = _vm.player_camera
	var ortho: float = cam.camera.size if (cam and cam.camera) else 0.0
	var bx: float = cam.global_position.x if cam else 0.0
	# Latch when the SCENE STOPS CHANGING, past the keyframe — not on a hand-fit pose.
	# `ortho >= 8.2 and bx < 9.5` was read off one run and frozen; the chapel's settled body
	# sits at bx = 7.94 during the cinematic and 10.00 on the bare setup chunk, so that gate
	# could and did report "never settled" for a scene that had settled long before. See the
	# same rewrite in the three ScenarioCamera*CalibTest siblings.
	if _settled_at < 0:
		var ag = _vm.units_by_id.get(0x34)
		var agp: Vector3 = ag.global_position if ag != null else Vector3(INF, INF, INF)
		var moved: bool = absf(bx - _last_bx) > 0.001 or absf(ortho - _last_ortho) > 0.001 \
			or _last_ag.distance_to(agp) > 0.001
		_last_bx = bx
		_last_ortho = ortho
		_last_ag = agp
		if ag == null or moved or _vm.get_pc() < 49:
			_stable = 0
		else:
			_stable += 1
		if _f >= 150 and _stable >= 45:
			_settled_at = _f
			print("[calib] settled latched at f=%d pc=%d (body.x=%.2f ortho=%.2f)" % [
				_f, _vm.get_pc(), bx, ortho])
	if _f % 180 == 0:
		print("[calib] f=%d units=%d body.x=%.2f ortho=%.2f settled_at=%d" % [
			_f, _vm.units_by_id.size(), bx, ortho, _settled_at])
	# Once latched, take ownership of the camera every frame.
	if _settled_at >= 0:
		_apply_override()
	# Capture 20 frames after latch (override applied + rendered), or at cap.
	var ready := (_settled_at >= 0 and _f >= _settled_at + 20) or (_f >= _max_frame)
	if ready and not _did:
		_did = true
		_capture()
		_quit = true

func _to_native(sp: Vector2) -> Vector2:
	return Vector2(sp.x * 0.2, sp.y * 0.25)

# Shader-corrected native: unproject_position uses ONLY the camera matrices, but
# the world shaders (unit.gdshader / Pattern-1 map) stretch clip.x by `pixel_aspect`
# (ADR-0036) AFTER MVP, about screen centre (native-X 128). So the ACTUAL on-
# screen anchor X = 128 + (raw_native_x - 128) * pixel_aspect. This is the number that
# matches what's rendered (and therefore what should be compared to the PSX
# framebuffer ground truth), NOT the raw unproject the diag printed before.
func _pixel_aspect() -> float:
	var v = RenderingServer.global_shader_parameter_get(&"pixel_aspect")
	return float(v) if v != null else 1.25

func _to_native_par(sp: Vector2) -> Vector2:
	var n := _to_native(sp)
	return Vector2(128.0 + (n.x - 128.0) * _pixel_aspect(), n.y)

func _capture() -> void:
	var img := root.get_texture().get_image()
	img.save_png(_shot)
	var vp := root.get_viewport().get_visible_rect().size
	var op := _opcode()
	print("[calib] ================= CALIBRATION FRAME f=%d =================" % _f)
	print("[calib] opcode  X=%d Y=%d Z=%d  Ang=%d Map=%d Roll=%d Zoom=%d  (set CAM* to sweep)" % [
		op["X"], op["Y"], op["Z"], op["ANG"], op["MAP"], op["ROLL"], op["ZOOM"]])
	print("[calib] deltas-from-default: %s" % str(_opcode_delta(op)))
	print("[calib] backrotate=%s flip_body_depth=%s" % [
		str(_vm.camera_director.camera_backrotate_pivot),
		str(_vm.camera_director.camera_flip_body_depth)])
	print("[calib] godot pose pos=%s rot(deg)=%s ortho=%.3f" % [
		str(_pose.get("pos")), str((_pose.get("rot", Vector3.ZERO)) * 57.2958), _pose.get("ortho", -1.0)])
	print("[calib] shot -> %s  viewport=%s  (native = vp*0.2, vp*0.25; center 128,120)" % [_shot, str(vp)])
	print("[calib] pixel_aspect=%.4f  (native_par = 128 + (native_raw-128)*pixel_aspect == rendered)" % _pixel_aspect())
	print("[calib] map_size_z=%s  camera_flip_body_depth=%s" % [
		str(_vm.map_size_z), str(_vm.camera_director.camera_flip_body_depth)])
	var cam = _vm.player_camera
	var cam3d = cam.camera if cam else null
	if cam3d:
		var cnat := _to_native(cam3d.unproject_position(cam.global_position))
		print("[calib] center-proj of body (native) = %s (expect ~128,120)" % str(cnat))
	for uid in _vm.units_by_id.keys():
		var u = _vm.units_by_id[uid]
		if u == null:
			continue
		var wp: Vector3 = u.global_position
		var nat := Vector2(-1, -1)
		var natp := Vector2(-1, -1)
		var behind := false
		if cam3d:
			var sp: Vector2 = cam3d.unproject_position(wp)
			nat = _to_native(sp)
			natp = _to_native_par(sp)  # shader-PAR corrected (== what's rendered)
			behind = cam3d.is_position_behind(wp)
		var ref_s := ""
		if PSX_REF.has(int(uid)):
			var r: Vector2 = PSX_REF[int(uid)]
			# Compare PSX framebuffer ground truth to the PAR-CORRECTED native.
			var dx := natp.x - r.x
			var dy_s := "?" if r.y < 0 else ("%+.1f" % (natp.y - r.y))
			ref_s = "  PSX=%s  dNATIVE_par=(%+.1f, %s)" % [str(r), dx, dy_s]
		print("[calib] unit 0x%02X world=%s native_raw=(%.1f,%.1f) native_par=(%.1f,%.1f) behind=%s%s" % [
			int(uid), str(wp), nat.x, nat.y, natp.x, natp.y, str(behind), ref_s])

func _opcode_delta(op: Dictionary) -> Dictionary:
	var d := {}
	for k in DEF.keys():
		if op[k] != DEF[k]:
			d[k] = op[k] - DEF[k]
	return d

## Find the ScenarioVM by a predicate that still EXISTS.
##
## This used to test `has_method("reapply_last_camera") and "camera_backrotate_pivot" in n`.
## Both of those moved onto `ScenarioVM.camera_director` when the camera code was extracted,
## so the predicate matched nothing, `_find_vm` returned null forever, and the rig sat
## printing "scene up but VM not found yet" for its whole 2600-frame budget. The three
## ScenarioCamera*CalibTest siblings promoted from this rig kept working because they use
## the predicate below — this file simply never got the update.
func _find_vm(n: Node) -> Node:
	if "camera_director" in n and n.camera_director != null:
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
