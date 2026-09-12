extends Node
# test-kind: logic
# seeded-break: in addons/exmateria_battlefield/camera/PlayerCamera.gd `enter_takeover_framing`, delete the two fold lines (`global_position += focus_point.global_basis.y * camera.position.y` and `camera.position.y = 0.0`) so the edge is a bare mode assignment again — that is the shipped defect; MEASURED 13/15 with 'exit fold: still continuous one frame later' reporting the full 1.3833 datum jump and 'exit fold: the BODY absorbed the datum' reporting that nothing was folded. Note the SAME-FRAME continuity arm stays green under this break and that is expected, not a hole: `_apply_vertical_datum` only re-plants in `_process`, so a bare assignment moves nothing until the next frame — which is exactly why the frame-later arm exists and is the load-bearing one

## The two BY-FIAT `camera_mode` edges the navigator drives, and the framing work each
## one owes. Not `request_takeover` / `release_takeover`: those hand the pose to a driver
## that immediately overwrites it, and `TileCursorTakeoverTest` already covers that
## round-trip. These two are the edges where NOTHING else runs.
##
## THE DEFECT THIS LOCKS. `camera_mode` is a plain property whose setter only emits a
## signal, so `camera_mode = TAKEOVER` compiles, flips the mode, and skips every piece of
## framing work the edge owns. It shipped that way at both of `NavigatorMain`'s sites:
##
##   * exit (`_return_camera`, the victory beat) — `_apply_vertical_datum` targets 0 in
##     TAKEOVER and re-plants every frame in every mode, so the datum fell 1.383 -> 0.000
##     in ONE frame. 40 of 240 native px, 16.7 % of the view height at ortho 8.30, and
##     scenario 12's next authored `{19}` is 120 ticks away, so it played bare. That was
##     the reported "the camera teleports to some position at the end".
##   * entry (`_enter_command_cursor`) — the mirrored step, plus the rotation targets
##     never re-synced, so the whole battle ran holding yaw 135 (the opener's terminal
##     `{19}`, Map Rotation 5632) while `y_target_rot` still read -45.
##
## CLAUSE 13 — one process, six arms. Every one of them shares this setup (a camera rig
## with a planted datum and a known held pose), so splitting them would cost a 2.3 s
## Godot boot each, forever.
##
## The static guard `tools/check_camera_mode_edges.py` is this test's other half: it
## asserts nobody re-introduces the bypass. This asserts the edges do the work.

# ADR-0211 dec. 4 — one alias line per file keeps every use site's spelling.
const DisplayPort = ExMateriaPlatform.DisplayPort

# The HOST mount (ADR-0204 dec. 1), not the addon scene — it INHERITS the addon's camera,
# so every node path is byte-identical, and it is what production instances. Same choice
# `TileCursorTakeoverTest` makes.
const PlayerCameraScene := preload("res://assets/scenes/CombatCamera.tscn")

const ORTHO_SIZE := 8.30      # the size measured live at the Gariland seam
const HELD_YAW_DEG := 135.0   # scn 10's terminal {19}: Map Rotation 5632
const HELD_PITCH_DEG := -30.0
const STALE_TARGET_YAW := -45.0  # what y_target_rot held for the whole battle
## Both by-fiat eases run on `handoff_ease_seconds` of WALL CLOCK, so the arms that watch one
## arrive are capped in frames rather than counted in them.
##
## ⚠️ 0.50 s IS A FLOOR, NOT A PREFERENCE, and 0.20 s was measured flaky. `_process` clamps
## its unscaled delta to 0.1 s, so the worst legal FIRST frame of an ease is 100 ms — and at
## 0.20 s that is `t = 0.5`, which lands the datum at exactly half strength and reds the
## "one frame in, still small" arm on a slow boot. At 0.50 s the same worst-case frame is
## `t = 0.2` → 9.5 %, comfortably under that arm's 25 % bar.
##
## The CAP is deliberately far above the ~30 frames 0.50 s needs at 60 Hz: the loop breaks on
## arrival, so the cap only bounds the FAILURE path, and a fast box renders 0.50 s in 200
## frames. Sizing it to 60 Hz would make a quick box fail a slow rig's test.
const TEST_EASE_SECONDS := 0.50
const BLEND_FRAME_CAP := 300
## The hitch arm 8 hands each clock. 50 ms is `FormationMapHost._ready`-sized — the measured
## ~60 ms stall the handoff ease is armed directly after.
const HITCH_S := 0.05

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _run()
	_finish()


func _run() -> void:
	var cam = PlayerCameraScene.instantiate()
	add_child(cam)
	await get_tree().process_frame

	cam.camera.size = ORTHO_SIZE
	cam.handoff_ease_seconds = TEST_EASE_SECONDS
	# Park the rig on a known held pose and let `_process` plant the datum from it.
	cam.global_position = Vector3(10.0, 2.0, 10.0)
	cam.focus_point.global_rotation = Vector3(
		deg_to_rad(HELD_PITCH_DEG), deg_to_rad(HELD_YAW_DEG), 0.0)
	# The stale targets the opener leaves behind, and the flag that makes them unreachable.
	cam.x_target_rot = 0.0
	cam.y_target_rot = STALE_TARGET_YAW
	cam.rotation_settled = true
	await get_tree().process_frame

	# The datum this rig plants, from the same expression the rig uses. Spelled out rather
	# than read back off the camera so the rig is not allowed to grade its own homework.
	var expected_datum: float = (cam.vertical_datum_px / DisplayPort.NATIVE_VIEWPORT_HEIGHT) * ORTHO_SIZE
	_true(absf(cam.camera.position.y - expected_datum) < 0.001,
		"setup: CURSOR mode plants the datum (got %.4f, expected %.4f)"
			% [cam.camera.position.y, expected_datum])
	_true(expected_datum > 0.5,
		"setup: the datum is large enough for this test to mean anything (%.4f)" % expected_datum)

	# === ARM 1-2: the EXIT edge folds, so the framed point does not move ==============
	# The whole claim is about the Camera3D's WORLD position — the body and the local
	# offset are both allowed to change, and both do. What may not change is their sum.
	var before_world: Vector3 = cam.camera.global_position
	var before_body: Vector3 = cam.global_position
	cam.enter_takeover_framing()
	_true((cam.camera.global_position - before_world).length() < 0.0001,
		"exit fold: Camera3D world position is continuous across CURSOR->TAKEOVER (moved %.4f)"
			% (cam.camera.global_position - before_world).length())
	_true((cam.global_position - before_body).length() > 0.5,
		"exit fold: the BODY absorbed the datum — a no-op here would mean nothing was folded")

	# And it survives the frame: `_apply_vertical_datum` re-plants in every mode, so a
	# fold that only held until the next `_process` would not have fixed anything.
	await get_tree().process_frame
	_true(absf(cam.camera.position.y) < 0.0001,
		"exit fold: the local offset stays zero in TAKEOVER (got %.4f)" % cam.camera.position.y)
	_true((cam.camera.global_position - before_world).length() < 0.0001,
		"exit fold: still continuous one frame later (moved %.4f)"
			% (cam.camera.global_position - before_world).length())

	# === ARM 3: the ENTRY edge re-truths the rotation targets ==========================
	# Held pose is unchanged; only the targets were a lie.
	cam.resume_cursor_framing()
	_true(absf(angle_difference(deg_to_rad(cam.y_target_rot), deg_to_rad(HELD_YAW_DEG))) < 0.001,
		"entry sync: y_target_rot agrees with the held yaw (got %.1f, held %.1f)"
			% [cam.y_target_rot, HELD_YAW_DEG])
	_true(absf(angle_difference(deg_to_rad(cam.x_target_rot), deg_to_rad(HELD_PITCH_DEG))) < 0.001,
		"entry sync: x_target_rot agrees with the held pitch (got %.1f, held %.1f)"
			% [cam.x_target_rot, HELD_PITCH_DEG])
	_true(cam.rotation_settled,
		"entry sync: rotation_settled stays TRUE — after the sync the pose IS the target")

	# === ARM 4: the ENTRY edge EASES the datum in rather than stepping it ==============
	# One frame in, the datum must be present but nowhere near full. A bare mode flip
	# would land the whole thing on this very frame; that is the mirrored defect.
	await get_tree().process_frame
	var after_one: float = cam.camera.position.y
	_true(after_one < expected_datum * 0.25,
		"entry ease: one frame in, the datum is still small (%.4f of %.4f)"
			% [after_one, expected_datum])

	# ...and it is monotonically non-decreasing, i.e. an ease and not a wobble.
	#
	# ⚠️ FRAME-CAPPED, NOT FRAME-COUNTED (#1168 follow-up). This blend used to be a 16-frame
	# counter and 20 frames was a safe over-run; it now rides `handoff_ease_seconds` on the
	# rig's WALL CLOCK, so how many frames it takes is a property of the box, not of the rig.
	# Loop until it arrives with a generous cap — asserting a frame count here would be
	# asserting the box's frame pacing.
	var monotonic := true
	var prev := after_one
	var datum_frames := 0
	while datum_frames < BLEND_FRAME_CAP:
		await get_tree().process_frame
		datum_frames += 1
		var now: float = cam.camera.position.y
		if now < prev - 0.0001:
			monotonic = false
		prev = now
		if absf(prev - expected_datum) < 0.001:
			break
	_true(monotonic, "entry ease: the datum only ever rises across the blend")
	_true(absf(prev - expected_datum) < 0.001,
		"entry ease: the datum arrives at full strength (%.4f of %.4f, %d frames)"
			% [prev, expected_datum, datum_frames])

	# === ARM 5: the entry edge is EDGE-ONLY ===========================================
	# `_enter_command_cursor` runs TWICE per battle. A second call must not re-sync, or a
	# Q/E rotation started during deployment is aborted mid-lerp.
	cam.y_target_rot = STALE_TARGET_YAW   # stand in for "the player pressed Q"
	cam.rotation_settled = false
	cam.resume_cursor_framing()
	_true(is_equal_approx(cam.y_target_rot, STALE_TARGET_YAW),
		"edge-only: a second resume in CURSOR mode leaves an in-flight rotation alone")
	_true(not cam.rotation_settled,
		"edge-only: a second resume does not re-settle an in-flight rotation")

	# === ARM 7: the cursor SEAT eases rather than cuts =================================
	# The other half of "the camera teleports" (#1168), and the half the player reported as
	# "jerks into position on to the first unit". `CursorController.seed_from_map` frames
	# the seated tile, and out of a cinematic that must be a glide, not a cut.
	#
	# A FRESH rig is the whole point: `follow_cursor`'s "no prior target" branch snaps the
	# body outright, and nothing had driven the follow path while the opener held the
	# camera in TAKEOVER — so `follow_cursor(pos, false)` was still a hard cut, and the
	# trace caught 6.6425 units in zero frames on every run. `ease_onto` is the call with
	# no such branch. Same setup, same rig, so this arm is free (clause 13).
	var seat := PlayerCameraScene.instantiate()
	add_child(seat)
	await get_tree().process_frame
	seat.handoff_ease_seconds = TEST_EASE_SECONDS
	seat.global_position = Vector3(10.0, 2.0, 10.0)
	await get_tree().process_frame
	var seat_from: Vector3 = seat.global_position
	var seat_to := Vector3(16.6, 2.0, 10.0)   # 6.6 units, the measured step
	seat.ease_onto(seat_to)
	_true((seat.global_position - seat_from).length() < 0.0001,
		"seat ease: ease_onto does NOT move the body on the call frame (moved %.4f)"
			% (seat.global_position - seat_from).length())
	# One frame in it has started, and it is nowhere near arrived.
	await get_tree().process_frame
	var seat_step: float = (seat.global_position - seat_from).length()
	_true(seat_step > 0.0001 and seat_step < 6.6 * 0.5,
		"seat ease: one frame in, the body has moved but not arrived (%.4f of 6.6)" % seat_step)
	# ...and it does arrive, so the cursor is not left off-frame. Same frame CAP rather than
	# a frame COUNT: `ease_onto` runs on `handoff_ease_seconds`, not on `follow_ease_frames`.
	var seat_frames := 0
	while seat_frames < BLEND_FRAME_CAP:
		await get_tree().process_frame
		seat_frames += 1
		if (seat.global_position - seat_to).length() < 0.01:
			break
	_true((seat.global_position - seat_to).length() < 0.01,
		"seat ease: the body lands on the seated tile (%.4f off)"
			% (seat.global_position - seat_to).length())
	# THE CONTROL. A snapping seat is still available and still snaps — this arm is what
	# makes the one above a statement about `ease_onto` rather than about a camera that
	# cannot move fast. Bare scene boots (GPUArena, GambitBattle) still take this path.
	var cut := PlayerCameraScene.instantiate()
	add_child(cut)
	await get_tree().process_frame
	cut.global_position = Vector3(10.0, 2.0, 10.0)
	await get_tree().process_frame
	cut.follow_cursor(seat_to, false)
	_true((cut.global_position - seat_to).length() < 0.0001,
		"seat ease CONTROL: follow_cursor on a fresh rig still hard-cuts — which is why "
		+ "passing it `snap = false` was not the fix (%.4f off)"
			% (cut.global_position - seat_to).length())
	seat.queue_free()
	cut.queue_free()

	# === ARM 8: the handoff ease runs on the CLOCK; the tile step runs on FRAMES =======
	# The second half of #1168, and the one the first fix could not have caught. Easing
	# instead of cutting removed the 6.64-unit teleport and the report came back as "the
	# jerk moved to after the ready fade". Cause: `ease_onto` borrowed `follow_ease_frames`,
	# a FRAME counter, and it is armed on the frame straight after `FormationMapHost._ready`
	# costs ~60 ms. The swapchain has drained, so the next three frames render in 2-3 ms
	# each and the ease burns five of its eighteen steps in 37 ms rather than 83 — measured
	# 2.0-4.5x the intended speed over three idle-box runs, with every per-frame step still
	# a textbook cosine. The camera gets somewhere before the player's clock says it should.
	#
	# ONE 50 ms FRAME, TWO ARMS, TWO ANSWERS. `_execute_cursor_follow(delta)` is the seam and
	# is driven directly so the arm is deterministic and costs no wall clock at all — spinning
	# a real 50 ms hitch would need `Time.get_ticks_*`, which the charter reserves for `perf`
	# (clause 14), and would buy nothing this does not already prove.
	var clk := PlayerCameraScene.instantiate()
	add_child(clk)
	await get_tree().process_frame
	clk.handoff_ease_seconds = 0.40
	var clk_from := Vector3(10.0, 2.0, 10.0)
	var clk_to := Vector3(20.0, 2.0, 10.0)     # 10 units, so a fraction reads straight off
	clk.global_position = clk_from
	await get_tree().process_frame
	clk.global_position = clk_from             # re-plant after the rig's own first _process
	clk.ease_onto(clk_to)
	clk._execute_cursor_follow(HITCH_S)
	# 50 ms of a 400 ms ease is t=0.125, so the cosine has delivered 0.5-0.5*cos(PI*0.125).
	var want_clock: float = (0.5 - 0.5 * cos(PI * (HITCH_S / 0.40))) * 10.0
	var got_clock: float = (clk.global_position - clk_from).length()
	_true(absf(got_clock - want_clock) < 0.02,
		"two clocks: a 50 ms frame advances the HANDOFF ease by its 50 ms share "
		+ "(%.4f of 10, wanted %.4f)" % [got_clock, want_clock])

	# THE CONTROL, and it is the arm that makes the one above a claim about the CLOCK rather
	# than about any ease at all: the same 50 ms handed to a `follow_cursor` tile step moves
	# the body by exactly ONE FRAME's worth, because that path counts frames on purpose —
	# it is the cursor's own hop and `TurnBeat` mirrors `follow_ease_frames` to ride it.
	# On trunk BOTH arms answered this one, which is the defect stated as a number.
	var stp := PlayerCameraScene.instantiate()
	add_child(stp)
	await get_tree().process_frame
	stp.global_position = clk_from
	await get_tree().process_frame
	stp.global_position = clk_from
	stp.follow_cursor(clk_from, true)          # seed the target so the next call eases
	stp.follow_cursor(clk_to)
	stp._execute_cursor_follow(HITCH_S)
	var want_frame: float = (0.5 - 0.5 * cos(PI / float(stp.follow_ease_frames))) * 10.0
	var got_frame: float = (stp.global_position - clk_from).length()
	_true(absf(got_frame - want_frame) < 0.02,
		"two clocks CONTROL: the same 50 ms advances a TILE STEP by one frame's worth, "
		+ "not 50 ms' worth (%.4f of 10, wanted %.4f)" % [got_frame, want_frame])
	_true(got_clock > got_frame * 2.0,
		"two clocks: the hitch moves the handoff ease strictly further than the frame-"
		+ "counted step (%.4f vs %.4f) — if these agree, the handoff is back on frames"
			% [got_clock, got_frame])

	# === ARM 9: the datum and the body are ONE curve of ONE length ====================
	# `_advance_datum_blend` used to be its own 16-FRAME counter borrowed from
	# `_return_total`, which read identically only while the body ease was also ~18 frames.
	# Give the handoff its true 0.80 s and they come apart: the datum's 1.383 units of
	# vertical framing land inside the first third of the glide, so the camera goes UP and
	# then ALONG instead of straight. It showed up in the trace as ARC LENGTH — the Camera3D
	# covered 7.509 units reaching a point 6.699 units away, and sharing the duration put it
	# back to 6.686. Both edges are armed on the same frame by `_enter_command_cursor`, so
	# the same elapsed time must put both at the same point on the same cosine.
	#
	# No `await` inside this block: `_process` advances both clocks itself, and a frame
	# landing mid-block would retire one of them before it is read.
	var dtm := PlayerCameraScene.instantiate()
	add_child(dtm)
	await get_tree().process_frame
	dtm.handoff_ease_seconds = 0.40
	dtm.global_position = clk_from
	dtm.enter_takeover_framing()     # the opener's state: a driver holds the rig
	dtm.resume_cursor_framing()      # the entry edge — arms the datum blend
	# FROM WHERE THE FOLD LEFT IT, not from `clk_from`: `enter_takeover_framing` slides the
	# body up its own local Y by the datum it is handing back, so the glide's origin is not
	# where the body was parked. Reading the fraction against `clk_from` measured the fold
	# as ease progress and put the body at t=0.30 for a 50 ms step.
	var dtm_from: Vector3 = dtm.global_position
	var dtm_span: float = (clk_to - dtm_from).length()
	dtm.ease_onto(clk_to)            # ...and the body glide, same frame
	var datum_blend: float = dtm._advance_datum_blend(HITCH_S)
	dtm._execute_cursor_follow(HITCH_S)
	var body_frac: float = (dtm.global_position - dtm_from).length() / dtm_span
	_true(absf(datum_blend - body_frac) < 0.005,
		"one curve: after the same 50 ms the datum blend and the body glide are at the "
		+ "same point on the same cosine (%.4f vs %.4f)" % [datum_blend, body_frac])
	_true(absf(datum_blend - (0.5 - 0.5 * cos(PI * (HITCH_S / 0.40)))) < 0.005,
		"one curve: and that point is `handoff_ease_seconds`' cosine, not a 16-frame "
		+ "counter's (%.4f, wanted %.4f)"
			% [datum_blend, 0.5 - 0.5 * cos(PI * (HITCH_S / 0.40))])
	dtm.queue_free()

	clk.queue_free()
	stp.queue_free()

	# === ARM 6: the exit edge is idempotent ===========================================
	cam.enter_takeover_framing()
	var folded_body: Vector3 = cam.global_position
	cam.enter_takeover_framing()
	_true((cam.global_position - folded_body).length() < 0.0001,
		"exit fold: a second call in TAKEOVER folds nothing a second time")

	cam.queue_free()


func _true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL %s" % msg)


func _finish() -> void:
	if _passed == 0 and _failed == 0:
		print("[FAIL] PlayerCameraDatumEdgeTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] PlayerCameraDatumEdgeTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
	else:
		print("[PASS] PlayerCameraDatumEdgeTest — %d/%d" % [_passed, _passed])
		get_tree().quit(0)
