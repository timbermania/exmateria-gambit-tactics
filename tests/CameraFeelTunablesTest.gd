extends Node3D
## Move-2 guard for ADR-0068: the cursor-follow "feel" knobs (deadzone width/height,
## rotation speed, translation ease, concurrent rotate+translate, rotation kickoff,
## and the deadzone-box overlay toggle) are OWNED by PlayerCamera — it binds each to
## a `camera.*` Tune slug in _ready — so a committed override coalesces at boot AND a
## live scrub re-drives the camera in EVERY scene, with no CameraFeelDebugPanel
## fan-out (decision 12). Before this the panel wrote straight onto the camera node.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/CameraFeelTunablesTest.tscn

var _passed: int = 0
var _failed: int = 0

# The HOST mount (ADR-0204 dec. 1), not the addon scene: it INHERITS the addon's
# camera, so every node path is byte-identical, and it is what production instances.
const CAMERA_SCENE := "res://assets/scenes/CombatCamera.tscn"


func _ready() -> void:
	# Overrides live BEFORE the camera spawns so its _ready bind coalesces them.
	Tune.reset_overrides()
	# reset_overrides(), not reset(): the OVERRIDES go, the `_static_init` boot registration
	# stands. So every tunable this test's production scene reads — not just the ones it scrubs —
	# still coalesces onto a REGISTERED default rather than Nil (ADR-0068 R3), with
	# no central replay to call. This is the registration PRODUCTION runs on: nothing replays
	# there either (#535, ADR-0173). Plain reset() would clear the declarations and a
	# get_value() inside the spawned node would assert (R5).
	Tune.set_value("camera.deadzone_width", 0.8)
	Tune.set_value("camera.rot_speed", 25.0)
	Tune.set_value("camera.show_deadzone_box", true)

	var cam = load(CAMERA_SCENE).instantiate()
	add_child(cam)
	await get_tree().process_frame

	# --- Set-once at spawn: pre-spawn overrides coalesced on the first frame ---
	_assert_approx(cam.deadzone_width, 0.8,
		"camera.deadzone_width override coalesces at spawn")
	_assert_approx(cam.rot_speed, 25.0,
		"camera.rot_speed override coalesces at spawn")
	_assert_true(cam.is_deadzone_box_visible(),
		"camera.show_deadzone_box override shows the overlay at spawn")

	# --- Live re-apply (bind, not read-once): scrubbing AFTER spawn re-drives it ---
	Tune.set_value("camera.deadzone_width", 0.3)
	Tune.set_value("camera.deadzone_height", 0.6)
	Tune.set_value("camera.rot_speed", 40.0)
	Tune.set_value("camera.follow_ease_frames", 30)
	Tune.set_value("camera.rotation_concurrent_translate", true)
	Tune.set_value("camera.rotation_kickoff_remaining_deg", 12.0)
	Tune.set_value("camera.show_deadzone_box", false)
	await get_tree().process_frame

	_assert_approx(cam.deadzone_width, 0.3, "scrubbing camera.deadzone_width live-updates")
	_assert_approx(cam.deadzone_height, 0.6, "scrubbing camera.deadzone_height live-updates")
	_assert_approx(cam.rot_speed, 40.0, "scrubbing camera.rot_speed live-updates")
	_assert_eq(cam.follow_ease_frames, 30, "scrubbing camera.follow_ease_frames live-updates")
	_assert_true(cam.rotation_concurrent_translate,
		"scrubbing camera.rotation_concurrent_translate live-updates")
	_assert_approx(cam.rotation_kickoff_remaining_deg, 12.0,
		"scrubbing camera.rotation_kickoff_remaining_deg live-updates")
	_assert_true(not cam.is_deadzone_box_visible(),
		"scrubbing camera.show_deadzone_box hides the overlay")

	print("\n=== CameraFeelTunablesTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraFeelTunablesTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraFeelTunablesTest")
		get_tree().quit(0)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_eq(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s (got %s, want %s)" % [label, actual, expected])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
