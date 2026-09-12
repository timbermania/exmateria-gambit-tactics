extends Node
# test-kind: logic
# seeded-break: PSXDisplay.set_camera_angle's mirror half stopped updating (live_camera_angle stays 0 while the shader-global push still happens) — the mirror arm, Unit._build_view's camera_angle_12bit, and the CameraRelativeRenderer seed arm all red (got 0x000, want 0x777); the DebugConfig severance arm stays green; GREEN unbroken on the reverted tree
## #590 — the camera angle is the PORT's, and both halves of it are.
##
## `psx_camera_angle` is the sixth global shader parameter this codebase pushes.
## Until #590 it was the ONLY one pushed from outside `PSXDisplay`, and its
## runtime mirror lived on `DebugConfig.psx_camera_angle_12bit` — `Debug` acting
## as a global variable for camera state, read by `Battle` (`Unit._build_view`)
## and `Sprite Rig` (`CameraRelativeRenderer`). That mirror was
## `addons/exmateria_battlefield/`'s last reach into one of the eleven systems
## that a port could answer (ADR-0175 dec. 4, ADR-0171 dec. 1).
##
## `tools/check_addon_portability.py` already enforces the SEVERANCE — delete
## the reach and it goes red, delete the burn-down row and it goes red. What no
## guard can see is whether the value still ARRIVES, and this test is that:
## `set_camera_angle` must drive the shader global AND the mirror, and both
## downstream readers must see it. A `live_camera_angle` that quietly stopped
## updating (dedup'd, Tune-ified, reset per scene) would leave every guard green
## and freeze every unit on its spawn-time pose octant.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/CameraAnglePortTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const CameraRelativeRenderer = ExMateriaSpriteRig.CameraRelativeRenderer

const PROBE := 0x777

var _failed := 0
var _passed := 0


func _ready() -> void:
	var boot: int = PSXDisplay.live_camera_angle

	PSXDisplay.set_camera_angle(PROBE)

	# 1. The mirror. The port holds it now; nothing else may.
	_expect(PSXDisplay.live_camera_angle == PROBE,
		"set_camera_angle drives live_camera_angle (got 0x%03X)" % PSXDisplay.live_camera_angle)

	# 2. THE PUSH HALF IS NOT ASSERTABLE FROM HERE, and finding that out is the
	#    reason the mirror above exists at all. This arm was written as
	#    `global_shader_parameter_get(&"psx_camera_angle") == PROBE` on the
	#    reasoning that a value pushed through the RenderingServer registry can
	#    be read back out of it (TunePsxParTest only claims the getter is null
	#    for BOOT defaults). It is not: at runtime the engine raises
	#    "This function should never be used outside the editor, it can severely
	#    damage performance" and returns null for a value pushed one line
	#    earlier. Editor-only means editor-only.
	#
	#    So the push side has a different owner, and it already has one:
	#    `tools/check_addon_portability.py` arm 4 scans BOTH sides of every
	#    `[shader_globals]` name and reports this exact line — a declaration-only
	#    arm would have been blind to it (ADR-0171 dec. 5). After #590 it names
	#    `addons/exmateria_platform/display_port/PSXDisplay.gd` and nothing else,
	#    which is the assertion "the port is the only pusher" in the one place
	#    that can make it.

	# 3. The `Battle` reader — the view dict the pure painters consume.
	var u := Unit.new()
	_expect(int(u._build_view()["camera_angle_12bit"]) == PROBE,
		"Unit._build_view reads the port mirror (got 0x%03X)"
		% int(u._build_view()["camera_angle_12bit"]))
	u.free()

	# 4. The `Sprite Rig` reader — seeded in `_ready` so the first `_process`
	#    tick does not fire a spurious `camera_angle_changed`. Since #848 it
	#    seeds through `ExMateriaPlatform.DisplayPort.live_camera_angle()` rather
	#    than the bare autoload identifier, so this arm is now also the assertion
	#    that the port's READ half forwards (ADR-0234).
	var crr := CameraRelativeRenderer.new()
	add_child(crr)
	_expect(crr.last_camera_angle_12bit == PROBE,
		"CameraRelativeRenderer seeds from the port mirror (got 0x%03X)"
		% crr.last_camera_angle_12bit)
	crr.queue_free()

	# 5. The reach is gone at the source, not merely unread. `Debug` no longer
	#    declares the member, so a reader that regressed would be a hard error
	#    rather than a silent zero.
	_expect(not ("psx_camera_angle_12bit" in DebugConfig),
		"DebugConfig no longer declares psx_camera_angle_12bit")

	PSXDisplay.set_camera_angle(boot)  # restore shared autoload state

	print("\n=== CameraAnglePortTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CameraAnglePortTest")
		get_tree().quit(1)
	else:
		print("[PASS] CameraAnglePortTest")
		get_tree().quit(0)


func _expect(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % what)
