extends Node3D
## The GAMEPLAY camera frames its tile on FFT's LOW optical centre — native-Y 160 of a
## 256x240 frame, not the midpoint 120 — and does it as a camera-LOCAL-up offset, so the
## framing survives yaw, pitch and zoom.
##
## `tests/ScenarioCameraVerticalDatumTest.gd` is this file's sibling and proves the same
## datum on the CINEMATIC rig, against the real chapel keyframe and a live-read PSX
## ground truth of 160. This one is the cursor rig's half, and it exists because the two
## rigs used to frame the same tile two different ways: `ScenarioCameraDirector` shifted
## its body pose while `PlayerCamera` hung its `Camera3D` at the body origin, so a tile
## sat at 160 during a cinematic and jumped to 120 the moment the player got the camera
## back. Both now read `DisplayPort.VERTICAL_DATUM_PX`.
##
## THE DATUM-OFF ARM IS THE GUARD. Asserting only "160" would pass on any rig that
## happens to sit a subject there — including one that never applies a datum at all if
## the scene's geometry cooperates. So every framing claim below is a PAIR: the value at
## `camera.vertical_datum_px = 40` and the value at 0, which must be ~40 native px higher
## and back on the midpoint. 0 is also the reviewer's A/B control on the Camera panel,
## so this file is what says that control still works.
##
## Four more properties, all sharing the one mounted camera (charter clause 13):
##
##   * YAW/PITCH INVARIANT. A constant WORLD-space nudge was tried on the cinematic rig
##     and deleted (ADR-0057): its projected screen shift rotates with the camera, so one
##     tuned value is wrong at every other pose. The arm re-poses the rig through four
##     yaws and a second pitch and demands the SAME native row every time — that is the
##     assertion a world-space regression fails and a local-up implementation passes.
##   * ZOOM INVARIANT. The shift scales with `camera.size`, so it is constant in PIXELS,
##     not in world units.
##   * THE DEADZONE BOX FOLLOWS THE FRAMING, and its overlay reads the same rect the
##     scroll math does. The box is centred on the framed row, and its height is clamped
##     to the room that leaves below — at datum 40 a `deadzone_height` of 1.0 would
##     otherwise put the box's lower edge off-screen, where the tile can never reach it
##     and the camera would stop scrolling down at all.
##   * ZERO UNDER TAKEOVER. The cinematic director bakes the datum into the body pose it
##     hands `apply_takeover()`; the rig offset must stand down while it does, or the
##     shot is framed 80 px low.
##
## Run: <GODOT> --path . res://tests/PlayerCameraVerticalDatumTest.tscn
# test-kind: logic
# seeded-break: make PlayerCamera._apply_vertical_datum() a no-op (`return` on entry) —
# the ON arms all read ~120 and every ON/OFF pair collapses.

# The HOST mount (ADR-0204 dec. 1), not the addon scene: it INHERITS the addon camera, so
# every node path is byte-identical, it is what production instances, and naming
# `addons/…/PlayerCamera.tscn` from `tests/` would be a criterion-4 site
# (tools/check_lattice_scene.py arm 1 enforces `tests/`).
const CAMERA_SCENE := "res://assets/scenes/CombatCamera.tscn"

const DATUM_SLUG := "camera.vertical_datum_px"
## The PSX ground truth this whole file is about: `TR = -R*work_position + (256, 160, 640)`.
const PSX_DATUM_ROW := 160.0
const MIDPOINT_ROW := 120.0
const NATIVE_H := 240.0
## Sub-pixel is the honest bar — this is arithmetic on an ortho projection, not a
## measurement off a savestate.
const TOL := 0.75
## The datum must MOVE the subject, not merely leave it near 160.
const MIN_DATUM_EFFECT := 30.0
## Frames to let the takeover return finish (PlayerCamera._return_total is 16).
const RETURN_FRAMES := 24
## PlayerCamera.ANGLE_LOW — the F-key pitch. Spelled here rather than read off the node
## so this file names no addon symbol; a drift makes the arm test a pitch the rig does
## not use, which still measures the invariance the arm is about.
const ANGLE_LOW := -39.37

## Where the "cursor" is. Off the origin on every axis so a rig that silently ignores the
## follow target cannot accidentally agree with one that honours it.
const TILE := Vector3(6.0, 2.0, 4.0)

var _passed: int = 0
var _failed: int = 0
var _cam


func _ready() -> void:
	# reset_overrides(), not reset(): the overrides go, the `_static_init` boot
	# registration stands, so every `camera.*` slug the spawned rig reads still coalesces
	# onto a REGISTERED default rather than Nil (ADR-0068 R3 / ADR-0173).
	Tune.reset_overrides()
	_cam = load(CAMERA_SCENE).instantiate()
	add_child(_cam)
	await get_tree().process_frame

	# The slug has to be REGISTERED or every scrub below writes into a void and the
	# assertions pass against a rig nobody drove — the failure mode ADR-0208 dec. 1 was
	# written for.
	_assert_true(Tune.is_registered(DATUM_SLUG),
		"camera.vertical_datum_px is registered by PlayerCamera at class load")
	_assert_true(_cam.camera != null and _cam.focus_point != null,
		"the mount carries FocusPoint/Camera")
	if _cam.camera == null:
		_finish()
		return

	# Hold the pose still: `_maintain_rotation` would otherwise lerp toward the rig's
	# default yaw/pitch every frame and each arm would read a different pose.
	_cam.rotation_settled = true

	await _test_the_datum_puts_the_followed_tile_on_the_psx_row()
	await _test_the_framing_survives_yaw_pitch_and_zoom()
	await _test_the_deadzone_box_follows_the_framing()
	await _test_the_datum_stands_down_under_takeover()

	_finish()


## ON -> the followed tile lands on native 160; OFF -> back on the midpoint, ~40px higher.
func _test_the_datum_puts_the_followed_tile_on_the_psx_row() -> void:
	await _pose(-45.0, -26.54)

	var on_y: float = await _framed_row(40.0)
	_assert_near(on_y, PSX_DATUM_ROW, TOL,
		"datum 40: the followed tile sits on the PSX optical row")

	var off_y: float = await _framed_row(0.0)
	_assert_near(off_y, MIDPOINT_ROW, TOL,
		"datum 0: the followed tile is back on the viewport midpoint")
	_assert_true(on_y - off_y >= MIN_DATUM_EFFECT,
		"the datum DROPS the tile by >=%.0fpx (OFF=%.1f ON=%.1f)" % [
			MIN_DATUM_EFFECT, off_y, on_y])


## The shift is applied along camera-LOCAL up, post-rotation, scaled by the ortho size —
## so the native row is the same at every pose and every zoom. A world-space offset
## (ADR-0057) reds this arm and passes the one above.
func _test_the_framing_survives_yaw_pitch_and_zoom() -> void:
	for yaw in [-45.0, 45.0, 135.0, -135.0]:
		await _pose(yaw, -26.54)
		var y: float = await _framed_row(40.0)
		_assert_near(y, PSX_DATUM_ROW, TOL,
			"yaw %.0f: still framed on the PSX row (%.1f)" % [yaw, y])

	# The F-key low angle — the other pitch this rig actually uses (PlayerCamera.ANGLE_LOW).
	await _pose(-45.0, ANGLE_LOW)
	var pitched: float = await _framed_row(40.0)
	_assert_near(pitched, PSX_DATUM_ROW, TOL,
		"pitch %.2f (ANGLE_LOW): still framed on the PSX row (%.1f)" % [ANGLE_LOW, pitched])

	await _pose(-45.0, -26.54)
	var base_size: float = _cam.camera.size
	_cam.camera.size = base_size * 2.5
	var zoomed: float = await _framed_row(40.0)
	_assert_near(zoomed, PSX_DATUM_ROW, TOL,
		"ortho size x2.5: the offset is px-constant, not world-constant (%.1f)" % zoomed)
	_cam.camera.size = base_size


## The scroll box is centred on the FRAMED row, and `deadzone_box_screen_rect()` — the one
## description of it — is what both the scroll math and the debug overlay read.
func _test_the_deadzone_box_follows_the_framing() -> void:
	await _pose(-45.0, -26.54)
	await _framed_row(40.0)

	Tune.set_value("camera.deadzone_height", 0.4)
	await get_tree().process_frame
	var box: Rect2 = _cam.deadzone_box_screen_rect()
	var centre := box.position.y + box.size.y * 0.5
	_assert_near(centre * NATIVE_H, PSX_DATUM_ROW, TOL,
		"the box's centre IS the framed row, not the viewport midpoint (%.1f)" % (
			centre * NATIVE_H))

	# The half-extent the scroll math uses must be the same box the overlay draws.
	var half: Vector2 = _cam.deadzone_half_extents()
	_assert_near(box.size.y, (2.0 * half.y) / _cam.camera.size, 0.001,
		"the drawn box height is the scroll math's half-extent, doubled")

	# The clamp: at datum 40 only 80 of the 240 rows remain below the box's centre, so a
	# full-height box is cut to fit rather than hanging its lower edge off-screen.
	Tune.set_value("camera.deadzone_height", 1.0)
	await get_tree().process_frame
	var full: Rect2 = _cam.deadzone_box_screen_rect()
	_assert_true(full.position.y + full.size.y <= 1.0 + 0.001,
		"deadzone_height 1.0 is clamped to the room the framing leaves (bottom=%.3f)" % (
			full.position.y + full.size.y))
	_assert_true(full.size.y > 0.5,
		"...and clamped, not collapsed (height=%.3f)" % full.size.y)

	# And with the datum off there is nothing to clamp against — the same 1.0 fills the
	# frame. Without this the clamp above would pass on a rig that always shrinks the box.
	Tune.set_value(DATUM_SLUG, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var centred: Rect2 = _cam.deadzone_box_screen_rect()
	_assert_near(centred.size.y, 1.0, 0.001,
		"datum 0: deadzone_height 1.0 is the whole frame again (%.3f)" % centred.size.y)

	Tune.set_value("camera.deadzone_height", 0.4)
	await get_tree().process_frame


## The cinematic director already bakes the datum into the pose it hands apply_takeover(),
## so the rig offset must be zero while a driver owns the camera — and must ease back in
## over the return rather than snapping, since at release the body still carries it.
func _test_the_datum_stands_down_under_takeover() -> void:
	await _pose(-45.0, -26.54)
	await _framed_row(40.0)
	var live: float = _cam.vertical_datum_offset()
	_assert_true(live > 0.0, "the datum offset is live in CURSOR mode (%.3f)" % live)

	_cam.request_takeover(self)
	await get_tree().process_frame
	_assert_near(_cam.vertical_datum_offset(), 0.0, 0.0001,
		"TAKEOVER: the rig offset stands down so the director's baked datum is not doubled")

	_cam.release_takeover()
	await get_tree().process_frame
	_assert_true(_cam.vertical_datum_offset() < live,
		"the return EASES the datum back in rather than snapping it (%.3f < %.3f)" % [
			_cam.vertical_datum_offset(), live])

	for _i in RETURN_FRAMES:
		await get_tree().process_frame
	_assert_near(_cam.vertical_datum_offset(), live, 0.001,
		"...and lands on the full offset once the return finishes")


# --- rig ---------------------------------------------------------------------------

## Hold a yaw/pitch. `rotation_settled` stays true so `_maintain_rotation` leaves it be.
func _pose(yaw_deg: float, pitch_deg: float) -> void:
	_cam.rotation_settled = true
	_cam.x_target_rot = pitch_deg
	_cam.y_target_rot = yaw_deg
	_cam.focus_point.global_rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)
	await get_tree().process_frame


## Scrub the datum, snap the camera onto TILE, and return the native row TILE projects to.
## Two frames: one for the tunable push, one for `_process` to plant the offset.
func _framed_row(datum_px: float) -> float:
	Tune.set_value(DATUM_SLUG, datum_px)
	await get_tree().process_frame
	_cam.follow_cursor(TILE, true)
	await get_tree().process_frame
	return _native_y(TILE)


## Viewport pixels -> the 240-line native frame the PSX ground truth is quoted in.
## Normalised by the live viewport height rather than the x0.25 the cinematic test uses,
## so this does not silently depend on the window being 1280x960.
func _native_y(world: Vector3) -> float:
	var vp: Vector2 = _cam.camera.get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return NAN
	return _cam.camera.unproject_position(world).y / vp.y * NATIVE_H


func _assert_near(actual: float, expected: float, tol: float, label: String) -> void:
	if not is_nan(actual) and absf(actual - expected) <= tol:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s +/- %s)" % [label, actual, expected, tol])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _finish() -> void:
	print("\n=== PlayerCameraVerticalDatumTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0 or _passed == 0:
		print("[FAIL] PlayerCameraVerticalDatumTest")
		get_tree().quit(1)
	else:
		print("[PASS] PlayerCameraVerticalDatumTest")
		get_tree().quit(0)
