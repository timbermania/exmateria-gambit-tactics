extends Node
## Calibration REGRESSION test for the VERTICAL scenario-camera fix
## (`camera_vertical_datum`, living doc F20 — the "framed ~40px too high" bug that
## flipping `camera_aim_floor_y` OFF (F19b) exposed).
##
## Load the REAL
## `ScenarioPlayer.tscn`, let the chapel cinematic settle, then re-apply the settled
## keyframe (scenario 2, instruction 48) through the REAL transform
## (`ScenarioVM._compute_camera_godot_pose` → `apply_takeover`) with
## and project Agrias (unit 0x34) into native 256×240 px
## — once with the vertical-datum fix OFF and once ON.
##
## NB: native-Y needs NO `pixel_aspect` correction — the shader stretch is X-ONLY (F17), so
## the rendered native-Y is `unproject_position.y · 0.25` directly (unlike the X gate).
##
## The bug & fix (F20): FFT's sprite projection is pure affine ortho
## `screen = R·SV/4096 + TR`; decomposing `TR = −R·work_position + (256, 160, …)` shows
## work_position projects to native (128, 160) — horizontally centred but VERTICALLY at
## 160, not the frame midpoint 120. Godot's ortho rig centres at 120, so every unit
## lands ~40px too HIGH (Agrias native-Y ≈120 vs PSX 160). The fix shifts the body along
## camera-local-up (post-rotation, yaw-independent like the GTE's TR) by the world
## distance for 160−120 = 40 native px, dropping the subject to the PSX datum. Asserts:
##   - flag ON  → Agrias native-Y near PSX ground truth 160 (within TOL_ON), AND
##   - flag ON  → ≥ MIN_FLAG_EFFECT px BELOW (larger native-Y than) flag OFF — proving
##     the datum shift is what moves her, not the scene on its own.
## PSX 160 is the LIVE-read per-unit screen store (node +0x122) at the settled
## savestate, which equals the GTE projection of her feet SVECTOR (F20).
##
## Horizontal X is the separate axis and it NO LONGER HAS A GATE. Its sibling,
## `ScenarioCameraLateralCalibTest` (the F19 X gate), was deleted on 2026-08-22 by
## user decision after it was brought back to life and still failed. What it measured,
## on the real chapel cinematic at the settled keyframe, is recorded in living doc
## `camera_framing_pivot_decode.md` §F19c and repeated here so the number is not
## only in a deleted file: with `camera_flip_body_depth` OFF Agrias lands at
## PAR-corrected native-X 96.0 and with it ON at 75.6, against a PSX ground truth of
## 107 — so the flag moves her ~20px in the WRONG direction and neither state is
## within 30px of the truth. Anything touching `camera_flip_body_depth` or
## `_compute_camera_godot_pose`'s X is currently UNGUARDED on that axis; use
## `tools/diag_camera_calibration.gd` (repaired 2026-08-22, same scenario pin and
## settle rule as this file) to re-measure before and after.
##
## Run headful (NEVER --headless). Picked up by tests/run_all_tests.sh.

# Settled chapel keyframe (scenario_002_chunk.json instructions[48]).
const DEF := {"X": 840, "Y": 504, "Z": -220, "ANG": 302, "MAP": 3584, "ROLL": 0, "ZOOM": 4096}
const CHAPEL_SCENARIO_ID := 2   # TEST.EVT event 2 — the chapel CINEMATIC (see _update_settle)
## The cinematic must have DISPATCHED the keyframe this test calibrates against before any
## stillness counts as "settled" — see `_update_settle`.
const SETTLE_MIN_PC := 49
const AGRIAS_ID := 0x34
## SETTLE, defined as "the scene stopped changing" — see `_update_settle`.
const SETTLE_STABLE_FRAMES := 45   # consecutive still frames that count as settled
const SETTLE_MIN_FRAME := 150      # never latch during the boot / fade-in
const SETTLE_EPS := 0.001          # world units / ortho units below which "no change"
const SETTLE_TAG := "[vertical]"
const PSX_REF_Y := 160.0            # Agrias screen-Y, native px (live savestate +0x122)
const TOL_ON := 3.0                 # ON near PSX; F20 diag measured Δ≈−0.3px + margin
const MIN_FLAG_EFFECT := 30.0       # ON must sit well BELOW OFF (≈120) — the datum fired

enum Phase { WAIT_SETTLE, CAPTURE_OFF, CAPTURE_ON, DONE }

var _scene: Node
var _vm: Node
var _f := 0
var _settled := false
var _stable := 0
var _last_bx := INF
var _last_ortho := INF
var _last_ag := Vector3(INF, INF, INF)
var _phase: int = Phase.WAIT_SETTLE
var _phase_start := 0
var _off_y := NAN
var _on_y := NAN
var _max_frame := 2600
var _passed := 0
var _failed := 0


func _ready() -> void:
	# Pin the CHAPEL CINEMATIC. This test calibrates against the settled chapel keyframe at
	# instruction 48 and projects Agrias, unit 0x34.
	#
	# Two wrong pins in a row, so be exact about which one this is. First, with no pick made
	# at all, `_boot` parks `DEFAULT_PATH_TARGET` (= 8) and PATH-walks group root 7,
	# 'Military Academy (Setup)' on MAP024 — a map whose ENTD spawns 0x01/0x04/0x80..0x87 and
	# no 0x34, so every projection came back NaN. Then the pin was set to 1, which is the
	# right MAP (MAP062, Orbonne) but the wrong CHUNK: `scenario_001_chunk.json` is
	# 'Orbonne Prayer (Setup)', SEVEN instructions long — No-op, Reveal, Wait, Event End —
	# with no camera keyframe and no cinematic. The scene stood still at the ENTD spawn and
	# Agrias projected to native-X -11.7 against a PSX ground truth of 107.
	#
	# The keyframe this file's DEF quotes is instruction 48 of `scenario_002_chunk.json`
	# (TEST.EVT event 2, 404 instructions): X=840 Z=65316 (= -220 unsigned) Y=504 Angle=302
	# MapRot=3584 CamRot=0 Zoom=4096 — every field matching DEF, and the only pc-48 Camera in
	# the whole chunk set that does. Unit 0x34 appears in 40 of its opcodes. So: 2.
	#
	# Setting selected_scenario_id also suppresses the DEFAULT_PATH_TARGET branch, which is
	# guarded on it being unset (ScenarioPlayerScene.gd:239-244).
	ScenarioDebugSession.path_target_scenario_id = CHAPEL_SCENARIO_ID
	_scene = load("res://assets/scenes/ScenarioPlayer.tscn").instantiate()
	add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _on_post_draw() -> void:
	_f += 1
	if _f > _max_frame:
		_fail("never settled / completed within %d frames (settled=%s phase=%d vm=%s pc=%s stable=%d)" % [
			_max_frame, str(_settled), _phase, str(_vm != null),
			str(_vm.get_pc()) if _vm != null else "?", _stable])
		_finish()
		return

	if _vm == null:
		_vm = _find_vm(_scene)
		return

	var cam = _vm.player_camera
	if cam == null or cam.camera == null:
		return
	var ortho: float = cam.camera.size
	var bx: float = cam.global_position.x

	if not _settled:
		if _update_settle(bx, ortho):
			_settled = true
			_phase = Phase.CAPTURE_OFF
			_phase_start = _f
		return

	match _phase:
		Phase.CAPTURE_OFF:
			_apply_override(false)
			if _f >= _phase_start + 8:
				_off_y = _agrias_native_y()
				print("[vertical] datum OFF: Agrias native-Y = %.1f" % _off_y)
				_phase = Phase.CAPTURE_ON
				_phase_start = _f
		Phase.CAPTURE_ON:
			_apply_override(true)
			if _f >= _phase_start + 8:
				_on_y = _agrias_native_y()
				var ag = _vm.units_by_id.get(AGRIAS_ID)
				if ag != null:
					print("[vertical] Agrias world=%s" % str(ag.global_position))
				print("[vertical] datum ON : Agrias native-Y = %.1f" % _on_y)
				_phase = Phase.DONE
				_evaluate()
				_finish()
		_:
			pass


## Drive OUR settled keyframe through the production transform with offset 0 and the
## vertical-datum flag set, so the live cinematic can't clobber the pose. The other
## camera flags are held at their defaults (lateral flip ON, floor-aim OFF).
func _apply_override(vertical_datum: bool) -> void:
	_vm.camera_director.camera_vertical_datum = vertical_datum
	var pose: Dictionary = _vm.camera_director._compute_camera_godot_pose(
		float(DEF["X"]), float(DEF["Y"]), float(DEF["Z"]),
		float(DEF["ANG"]), float(DEF["MAP"]), float(DEF["ROLL"]), float(DEF["ZOOM"]))
	_vm.player_camera.apply_takeover(pose["pos"], pose["rot"], pose["ortho"])


## native-Y the user SEES: unproject (pre-shader) × 0.25 → native. Y has NO pixel_aspect
## stretch (the shader is X-only, F17), so this is the rendered native-Y directly.
func _agrias_native_y() -> float:
	var cam = _vm.player_camera
	var cam3d = cam.camera if cam else null
	if cam3d == null:
		return NAN
	var u = _vm.units_by_id.get(AGRIAS_ID)
	if u == null:
		return NAN
	return cam3d.unproject_position(u.global_position).y * 0.25


func _evaluate() -> void:
	if is_nan(_off_y) or is_nan(_on_y):
		_fail("could not project Agrias (off_y=%s on_y=%s) — unit 0x%02X missing?" % [
			str(_off_y), str(_on_y), AGRIAS_ID])
		return
	var d_on: float = absf(_on_y - PSX_REF_Y)
	_check(d_on <= TOL_ON,
		"datum ON Agrias native-Y %.1f within %.1fpx of PSX %.0f (Δ=%+.1f)" % [
			_on_y, TOL_ON, PSX_REF_Y, _on_y - PSX_REF_Y])
	_check(_on_y - _off_y >= MIN_FLAG_EFFECT,
		"vertical datum drops Agrias ≥%.0fpx (OFF=%.1f ON=%.1f Δ=%+.1f)" % [
			MIN_FLAG_EFFECT, _off_y, _on_y, _on_y - _off_y])


func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  [ok] %s" % name)
	else:
		_failed += 1
		print("  [FAIL] %s" % name)


func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % msg)


func _finish() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	print("\n=== ScenarioCameraVerticalDatumTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or _passed == 0:
		print("[FAIL] ScenarioCameraVerticalDatumTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCameraVerticalDatumTest")
		get_tree().quit(0)


## Latch when the SCENE STOPS CHANGING, rather than when the camera crosses a hand-fit pose.
##
## This replaced `ortho >= 8.2 and bx < 9.5`. Those two numbers were read off one chapel run
## and then frozen, and they are not a definition of "settled" — they are a fingerprint of
## one pose on one map at one moment. The trio spent this session failing on them with
## `settled=false phase=0` after 2600 frames: the chapel's settled body sits at bx≈10.0, so
## `bx < 9.5` was never true and the swoop it was meant to detect had long since finished.
## A threshold that can be wrong in that direction is worse than useless, because it reports
## "never settled" for a scene that settled 2000 frames ago.
##
## What these tests actually need from "settled" is not a camera pose at all — they OVERRIDE
## the camera every frame with the PC48 keyframe (`_apply_override`). They need Agrias to
## have finished WALKING, so the position they project is her final one. So latch on
## stillness: no camera-body, no ortho and no Agrias movement for SETTLE_STABLE_FRAMES
## consecutive frames, after a SETTLE_MIN_FRAME floor that rules out latching on the
## pre-cinematic pause. That is map-independent and pose-independent — there is no constant
## left that a re-export or a re-timed cinematic can falsify.
func _update_settle(bx: float, ortho: float) -> bool:
	var ag = _vm.units_by_id.get(AGRIAS_ID)
	var agp: Vector3 = ag.global_position if ag != null else Vector3(INF, INF, INF)
	var moved: bool = absf(bx - _last_bx) > SETTLE_EPS \
		or absf(ortho - _last_ortho) > SETTLE_EPS \
		or _last_ag.distance_to(agp) > SETTLE_EPS
	_last_bx = bx
	_last_ortho = ortho
	_last_ag = agp
	if ag == null or moved:
		_stable = 0
	else:
		_stable += 1
	if _f % 300 == 0:
		print("%s f=%d pc=%d still=%d/%d body.x=%.2f ortho=%.2f agrias=%s" % [
			SETTLE_TAG, _f, _vm.get_pc(), _stable, SETTLE_STABLE_FRAMES, bx, ortho, str(agp)])
	if _vm.get_pc() < SETTLE_MIN_PC:
		_stable = 0
		return false
	if _f < SETTLE_MIN_FRAME or _stable < SETTLE_STABLE_FRAMES:
		return false
	print("%s settled at f=%d pc=%d after %d still frames (body.x=%.2f ortho=%.2f agrias=%s)" % [
		SETTLE_TAG, _f, _vm.get_pc(), _stable, bx, ortho, str(agp)])
	return true


func _find_vm(n: Node) -> Node:
	if "camera_director" in n and n.camera_director != null:
		return n
	for c in n.get_children():
		var r := _find_vm(c)
		if r != null:
			return r
	return null
