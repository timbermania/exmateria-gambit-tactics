extends Node
## Calibration REGRESSION test for the VERTICAL scenario-camera fix
## (`camera_aim_floor_y`, living doc F8/F9 +
## `handoff_scenario_camera_vertical_impl.md`).
##
## Promotes the headful rig `tools/diag_camera_calibration.gd` into a pass/fail
## gate: load the REAL `ScenarioPlayer.tscn`, let the chapel cinematic settle,
## then re-apply the settled keyframe (scenario_1 PC48) through the REAL
## transform (`ScenarioVM._compute_camera_godot_pose` → `apply_takeover`) with
## `camera_position_offset = 0` — once with the floor-aim flag OFF and once ON —
## and project Agrias (unit 0x34) into native 256×240 px.
##
## The fix aims the ortho centre at the framed tile's `floor_y` instead of the
## raw `−opcode_z/112` (which sits ~1 tile below the chapel floor, dropping the
## subject ~29px low → Agrias lands at ≈129 instead of PSX's 158). Asserts:
##   - flag ON  → Agrias native-Y near PSX ground truth 158 (within TOL_ON), AND
##   - flag ON  → ≥ MIN_FLAG_EFFECT px LOWER than flag OFF — proving the floor-aim
##     is what moves her, not the scene settling there on its own.
## Lateral X is the separate, still-open half (F9) — NOT asserted here, and as of
## 2026-08-22 not asserted ANYWHERE: `ScenarioCameraLateralCalibTest` was deleted by
## user decision. Its last measurement is in `ScenarioCameraVerticalDatumTest`'s
## header and living doc `camera_framing_pivot_decode.md` §F19c.
##
## Why TOL_ON is ~6px, not the ~2px F8 hoped for: at the settled pose the camera
## BODY hovers over tile (7,4) floor_y≈3.25, while Agrias stands on her own tile
## (5,6) floor_y≈3.036 — different heights (the chapel floor is not flat). Aiming
## at the BODY's framed-tile floor (the principled, general, subject-agnostic
## rule) therefore lands her ≈162 (Δ+4), whereas F8's hand-picked aim at *her*
## floor (3.036) gave 156.5 (Δ−1.5). The residual is contaminated by the still-
## open LATERAL chirality bug, which leaves the raw body over (7,4) rather than
## over Agrias' tile; once that lands, the framed tile becomes her tile and the
## vertical residual tightens toward F8's 1.5px on its own. The vertical mechanism
## here is correct as-is — so this test locks in "near PSX + big improvement over
## raw," not a sub-pixel match the ortho/lateral state can't yet deliver.
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
const SETTLE_TAG := "[floor-aim]"
const PSX_REF_Y := 158.0          # Agrias feet, native px (handoff F7/F9 live probe)
const TOL_ON := 6.0               # ON near PSX; ~4px honest residual (see header) + margin
const MIN_FLAG_EFFECT := 25.0     # ON must sit far below OFF (≈129) — the floor-aim fired

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
var _dbg_cam_seen := false
var _dbg_ortho := NAN
var _dbg_bx := NAN
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
		# Say WHICH precondition never came true. "never settled" alone cannot distinguish
		# "the VM was never found" from "the camera never widened", and those want opposite
		# fixes.
		_fail("never settled / completed within %d frames (settled=%s phase=%d vm=%s cam=%s last_ortho=%s last_bx=%s)" % [
			_max_frame, str(_settled), _phase, str(_vm != null), str(_dbg_cam_seen),
			str(_dbg_ortho), str(_dbg_bx)])
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
	_dbg_cam_seen = true
	_dbg_ortho = ortho
	_dbg_bx = bx

	# Latch the settled pose (swoop done: body arrived AND zoom widened) — same
	# criterion the rig uses.
	if not _settled:
		if _update_settle(bx, ortho):
			_settled = true
			_phase = Phase.CAPTURE_OFF
			_phase_start = _f
		return

	match _phase:
		Phase.CAPTURE_OFF:
			_apply_override(false)
			# Give the override a few frames to apply + render before sampling.
			if _f >= _phase_start + 8:
				_off_y = _agrias_native_y()
				print("[floor-aim] flag OFF: Agrias native-Y = %.1f" % _off_y)
				_phase = Phase.CAPTURE_ON
				_phase_start = _f
		Phase.CAPTURE_ON:
			_apply_override(true)
			if _f >= _phase_start + 8:
				_on_y = _agrias_native_y()
				var bpos: Vector3 = _vm.player_camera.global_position
				print("[floor-aim] settled body=%s%s" % [
					str(bpos), _vm.camera_director._describe_focal_tile_for_log(bpos)])
				var ag = _vm.units_by_id.get(AGRIAS_ID)
				if ag != null:
					print("[floor-aim] Agrias world=%s" % str(ag.global_position))
				print("[floor-aim] flag ON : Agrias native-Y = %.1f" % _on_y)
				_phase = Phase.DONE
				_evaluate()
				_finish()
		_:
			pass


## Drive OUR settled keyframe through the production transform with offset 0 and
## the floor-aim flag set, so the live cinematic can't clobber the pose.
func _apply_override(aim_floor: bool) -> void:
	_vm.camera_director.camera_aim_floor_y = aim_floor
	# Isolate the floor-aim mechanism: hold OFF the authentic vertical-datum fix (F20),
	# which targets the same gap and would otherwise land the OFF case at ~160 (not the
	# raw 120), defeating the flag-effect check below. Floor-aim is the A/B alternative.
	_vm.camera_director.camera_vertical_datum = false
	var pose: Dictionary = _vm.camera_director._compute_camera_godot_pose(
		float(DEF["X"]), float(DEF["Y"]), float(DEF["Z"]),
		float(DEF["ANG"]), float(DEF["MAP"]), float(DEF["ROLL"]), float(DEF["ZOOM"]))
	_vm.player_camera.apply_takeover(pose["pos"], pose["rot"], pose["ortho"])


func _agrias_native_y() -> float:
	var cam = _vm.player_camera
	var cam3d = cam.camera if cam else null
	if cam3d == null:
		return NAN
	var u = _vm.units_by_id.get(AGRIAS_ID)
	if u == null:
		return NAN
	# native_y = unproject_y * 0.25 (viewport 1280×960 → 256×240).
	return cam3d.unproject_position(u.global_position).y * 0.25


func _evaluate() -> void:
	if is_nan(_off_y) or is_nan(_on_y):
		_fail("could not project Agrias (off_y=%s on_y=%s) — unit 0x%02X missing?" % [
			str(_off_y), str(_on_y), AGRIAS_ID])
		return
	var d_on: float = absf(_on_y - PSX_REF_Y)
	_check(d_on <= TOL_ON,
		"flag ON Agrias native-Y %.1f within %.1fpx of PSX %.0f (Δ=%+.1f)" % [
			_on_y, TOL_ON, PSX_REF_Y, _on_y - PSX_REF_Y])
	_check(_on_y - _off_y >= MIN_FLAG_EFFECT,
		"floor-aim moves Agrias ≥%.0fpx lower (OFF=%.1f ON=%.1f Δ=%+.1f)" % [
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
	print("\n=== ScenarioCameraFloorAimCalibTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or _passed == 0:
		print("[FAIL] ScenarioCameraFloorAimCalibTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioCameraFloorAimCalibTest")
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
