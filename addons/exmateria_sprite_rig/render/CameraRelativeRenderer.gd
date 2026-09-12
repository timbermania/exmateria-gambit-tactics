@tool
extends Node

## Handles camera quadrant tracking and rotation detection
## Monitors camera rotation and emits signals when the view quadrant changes

## 🔴 `DisplayPort`, NOT `PSXDisplay` (#848, ADR-0234). `PSXDisplay` is an
## autoload, and an `[autoload]` line can only be written by the CONSUMING game:
## naming it here made this file fail to parse in a project that did not declare
## it, which `tests/stranger/exmateria_sprite_rig/` measured as a hard compile
## error taking the addon's one published global name down with it.
##
## The two lines below used to be spelled `PSXDisplay.live_camera_angle if
## PSXDisplay else 0`, and that ternary CANNOT FIRE: a bare autoload identifier is
## resolved at COMPILE time, so with the name unbound there is nothing for the
## guard to evaluate and the file does not parse at all. The author's intention to
## degrade gracefully was written into the source and the source could not run it.
## `DisplayPort` is where that intention actually executes — a soft-bind by node
## path at call time, with `0` as the defined absent value (ADR-0175 dec. 2).
##
## NOT the other conformant-looking shape. Writing
## `get_tree().root.get_node_or_null(^"PSXDisplay")` here would trade the parse
## error for a `check_addon_portability.py` arm 2b finding: arm 2b's free set is
## the kernel, the platform PORT and an addon reaching its OWN singleton, and this
## addon is none of those — it is a SYSTEM, and `PSXDisplay.gd` is shipped by
## `exmateria_platform`, not by this addon. ADR-0202 dec. 7 rules that spelling
## conformant for `TunePort.gd` because `TunePort` IS the port. `RigDebug.gd` and
## `layers/SpriteLayerManager.gd` are this addon's precedents for the alias below.
const DisplayPort = ExMateriaPlatform.DisplayPort

# Camera reference
var camera: Camera3D

# State tracking
var last_quadrant: int = 0
## 🔴 SPELLED WITHOUT `psx` (goal #7, ADR-0234). This and the signal below
## were four of the twelve rig-owned platform-jargon lines `tools/score_goals.py`
## charges this addon. The concept is the camera yaw, the port already publishes it
## as `live_camera_angle` with no prefix, and the `psx` was this addon's own local
## spelling rather than an echo of the port's — so it could be dropped here without
## waiting on #583's rename of the autoload.
var last_camera_angle_12bit: int = -1

# Debug
@export var debug_camera_rotation: bool = false

# Signals
signal camera_quadrant_changed(new_quadrant: int)
## Fires when the 12-bit PSX camera angle the display port mirrors
## (`DisplayPort.live_camera_angle()`, written by PlayerCamera every frame through
## `DisplayPort.set_camera_angle`)
## changes value. Path D's pose_octant LUT (`AnimationStateController.get_pose_octant`)
## reads this angle continuously; without a per-int-change repaint trigger,
## static-pose units (chapel `aid=2` single-`LoadFrameWait`) freeze on
## their spawn-time octant because `AnimationPlayback.frame_changed`
## emits ONCE for them. Combat units get the same repaint incidentally
## via their multi-frame idle anims' tick heartbeat, so this signal is
## the static-pose equivalent.
signal camera_angle_changed(new_angle_12bit: int)

func _ready():
	# Initialize last quadrant + last PSX angle so the first _process tick
	# doesn't fire a spurious "changed" signal.
	last_quadrant = get_camera_quadrant()
	last_camera_angle_12bit = DisplayPort.live_camera_angle()

func _process(_delta):
	"""Monitor camera for rotation changes"""
	if camera == null:
		return

	var current_quad = get_camera_quadrant()
	var current_angle_12bit: int = DisplayPort.live_camera_angle()
	if current_angle_12bit != last_camera_angle_12bit:
		last_camera_angle_12bit = current_angle_12bit
		camera_angle_changed.emit(current_angle_12bit)

	if debug_camera_rotation:
		var cam_rot = rad_to_deg(camera.global_rotation.y)
		# Normalize the rotation for display (same as get_camera_quadrant does)
		var normalized_rot = cam_rot
		while normalized_rot < 0:
			normalized_rot += 360
		while normalized_rot >= 360:
			normalized_rot -= 360
		print("Frame: quad=", current_quad, " last_quad=", last_quadrant,
			  " raw_rot=", snappedf(cam_rot, 0.1), "° normalized=", snappedf(normalized_rot, 0.1), "°")

	if current_quad != last_quadrant:
		# Camera quadrant change debug (DISABLED for stress test)
		# var cam_rot = rad_to_deg(camera.global_rotation.y)
		# var normalized_rot = cam_rot
		# while normalized_rot < 0:
		# 	normalized_rot += 360
		# while normalized_rot >= 360:
		# 	normalized_rot -= 360
		# print("\n=== Camera quadrant changed: ", last_quadrant, " -> ", current_quad, " ===")
		# print("  Raw rotation: ", snappedf(cam_rot, 0.1), "°")
		# print("  Normalized rotation: ", snappedf(normalized_rot, 0.1), "°")

		last_quadrant = current_quad
		camera_quadrant_changed.emit(current_quad)

func get_camera_quadrant() -> int:
	"""Calculate which camera quadrant (0-3) the camera is in

	Returns 0-3 based on camera Y rotation:
	- 0 = looking NE to SW (-45° = 315°) - [270°, 360°)
	- 1 = looking SE to NW (-135° = 225°) - [180°, 270°)
	- 2 = looking SW to NE (135°) - [90°, 180°)
	- 3 = looking NW to SE (45°) - [0°, 90°)
	"""
	if camera == null:
		return 0

	var cam_rot_deg: float = rad_to_deg(camera.global_rotation.y)

	# Normalize to [0, 360]
	while cam_rot_deg < 0:
		cam_rot_deg += 360
	while cam_rot_deg >= 360:
		cam_rot_deg -= 360

	# Determine quadrant based on 90° boundaries centered on key angles
	# Quadrant centers: 315° (0), 45° (3), 135° (2), 225° (1)
	# Boundaries at: 0°, 90°, 180°, 270°
	#
	# Quadrant 0 centered at 315°: [270°, 360°)
	# Quadrant 3 centered at 45°: [0°, 90°)
	# Quadrant 2 centered at 135°: [90°, 180°)
	# Quadrant 1 centered at 225°: [180°, 270°)

	if cam_rot_deg >= 270:
		return 0  # [270°, 360°)
	elif cam_rot_deg >= 180:
		return 1  # [180°, 270°)
	elif cam_rot_deg >= 90:
		return 2  # [90°, 180°)
	else:
		return 3  # [0°, 90°)
