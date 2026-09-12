extends CharacterBody3D

## Vault: [[Scenario Camera Framing]]

## Path to the procedural map for calculating terrain bounds

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const DisplayPort = ExMateriaPlatform.DisplayPort
const PsxNum = ExMateriaPlatform.PsxNum
const TunePort = ExMateriaPlatform.TunePort

# ADR-0211 dec. 2 — the addon publishes ONE global name; its internals are
# reached by path. A `preload` const is a full type: it annotates, `is`-checks
# and `.new()`s exactly as the deleted `class_name` did.
const DeadzoneBoxOverlay = preload("res://addons/exmateria_battlefield/camera/DeadzoneBoxOverlay.gd")
const Lattice = preload("res://addons/exmateria_battlefield/lattice/Lattice.gd")
const Tile = preload("res://addons/exmateria_battlefield/lattice/Tile.gd")

@export_node_path("Node3D") var procedural_map_path: NodePath

enum CameraMode { CURSOR, TAKEOVER }

## Fires on every mode transition (CURSOR ↔ TAKEOVER). TileCursor and any
## future listener connects here instead of polling camera_mode. The signal
## does NOT fire for the initial default-value assignment in _ready — readers
## should treat CURSOR as the initial mode.
signal camera_mode_changed(new_mode: CameraMode)

var camera_mode: CameraMode = CameraMode.CURSOR:
	set(value):
		if camera_mode == value:
			return
		camera_mode = value
		camera_mode_changed.emit(value)

var x_target_rot: float = -26.54
var y_target_rot: float = -45
var y_height = 15
var translation_speed = 20

# --- camera.* "feel" tunables (ADR-0068) ------------------------------------
# Each slug's home lives HERE (not in CameraFeelDebugPanel): a static-var DEFAULT
# (materializable, R1 — a literal the codemod can rewrite) + a HINT const, bound in
# register_tunables(); the panel reads both back as a pure view. The @export vars below
# initialize from these static-var defaults (probe-confirmed the inspector default resolves),
# so the @export slider stays but the ONE code literal is the static var.
const ROT_SPEED_SLUG := "camera.rot_speed"
static var ROT_SPEED_DEFAULT := 10.0
const ROT_SPEED_HINT := {"min": 1.0, "max": 50.0, "step": 0.5}
const DEADZONE_WIDTH_SLUG := "camera.deadzone_width"
static var DEADZONE_WIDTH_DEFAULT := 0.5
const DEADZONE_HEIGHT_SLUG := "camera.deadzone_height"
static var DEADZONE_HEIGHT_DEFAULT := 0.4
const DEADZONE_FRAC_HINT := {"min": 0.05, "max": 1.0, "step": 0.01}  # shared width/height
const FOLLOW_EASE_FRAMES_SLUG := "camera.follow_ease_frames"
static var FOLLOW_EASE_FRAMES_DEFAULT := 18
const FOLLOW_EASE_FRAMES_HINT := {"min": 1, "max": 60, "step": 1}
## The BATTLE HANDOFF's ease, in SECONDS — deliberately a second knob rather than a reuse of
## `camera.follow_ease_frames`, and deliberately a different UNIT. Both halves are measured;
## see the 🔴 on [method ease_onto].
const HANDOFF_EASE_SECONDS_SLUG := "camera.handoff_ease_seconds"
static var HANDOFF_EASE_SECONDS_DEFAULT := 0.80
const HANDOFF_EASE_SECONDS_HINT := {"min": 0.1, "max": 2.5, "step": 0.05}
const ROTATION_CONCURRENT_TRANSLATE_SLUG := "camera.rotation_concurrent_translate"
static var ROTATION_CONCURRENT_TRANSLATE_DEFAULT := false  # bool → checkbox, no hint
const ROTATION_KICKOFF_SLUG := "camera.rotation_kickoff_remaining_deg"
static var ROTATION_KICKOFF_DEFAULT := 2.86
const ROTATION_KICKOFF_HINT := {"min": 0.0, "max": 30.0, "step": 0.1}
const SHOW_DEADZONE_BOX_SLUG := "camera.show_deadzone_box"
# bool, no hint. Was seeded from is_deadzone_box_visible() (the overlay's boot state = hidden);
# now a false literal home the slug DRIVES via on_update, so the tunable owns the overlay state.
static var SHOW_DEADZONE_BOX_DEFAULT := false

# --- FFT's low framing datum ---------------------------------------------------
#
# How far BELOW the frame midpoint this camera puts the point it is framing, in native
# 256x240 px. FFT frames its optical centre at native-Y 160, not 120: the GTE
# translation decomposes as `TR = -R*work_position + (256, 160, 640)`, so the aim point
# projects to (128, 160). The reasoning and the ROM citations live on the constant this
# defaults to — `DisplayPort.VERTICAL_DATUM_PX`, the home the CINEMATIC rig
# (`src/scenarios/ScenarioCameraDirector.gd`) reads as well, so the two rigs cannot
# frame one tile two ways. Vault: [[Scenario Camera Framing]].
#
# 🔴 THE DEFAULT IS A NAMED CONST, NOT A LITERAL, AND THAT IS DELIBERATE. Every other
# `camera.*` home above spells a literal so `tools/materialize_tunables.py` can bake a
# scrub back into it (ADR-0068 R1). This one must not be baked: the number is a ROM
# measurement shared with another package, so materializing here would fork it. The
# codemod SKIPS a non-literal default with a warning and leaves it alone, which is
# exactly the behaviour this wants — it is a knob for LOOKING, not for keeping.
#
# 0 is the control arm: it puts the framed tile back on the viewport midpoint, i.e. the
# framing this camera shipped before the datum, so an A/B is one field away.
const VERTICAL_DATUM_SLUG := "camera.vertical_datum_px"
static var VERTICAL_DATUM_DEFAULT := DisplayPort.VERTICAL_DATUM_PX
const VERTICAL_DATUM_HINT := {"min": -60.0, "max": 60.0, "step": 1.0}

# --- the free-pan override, owned HERE ----------------------------------------
# ADR-0140 dec. 5. This gate is read on 3 lines and all three are Battlefield's: two
# in this file and one in TileCursor. `Battlefield` reaching `Debug` for it was the
# gate living outside the system it switches. The home is now the production owner,
# on the camera's own `camera.*` namespace beside the other feel tunables. Third
# instance of dec. 5, after `ExMateriaEffectSfx.audio_monitor_enabled` (#408) and
# `SkirtGeometryGenerator.land_skirt_debug` (#500).
#
# THE SIGNAL IS GONE, AND IT NEVER DELIVERED ANYTHING. `DebugConfig` declared
# `free_camera_enabled_changed`, emitted it from `_apply_free_camera`, and bound that
# through `Tune.bind_update` — and its own comment claimed the signal is what "reaches
# PlayerCamera/TileCursor". Nothing ever connected to it: the only reference outside
# DebugConfig was `tests/DebugSignalFlagsTunableTest.gd`, naming it as a data string.
# All three readers POLL. So the push machinery was removed rather than relocated.
#
# The read is a PULL for the same reason the skirt gate is: it is consulted inside
# input dispatch, so it must see a scrub on the very next event without a restart.
const FREE_CAMERA_SLUG := "camera.free_camera_enabled"
static var FREE_CAMERA_DEFAULT := false  # bool -> checkbox, no hint

## Camera-rotation lerp speed (per-second multiplier on the remaining angle).
## Higher = snappier yaw on Q/E (rot_speed * delta is the per-frame interp
## fraction); about 10 = ~half a second to settle a 90° yaw.
@export_range(1.0, 50.0, 0.5) var rot_speed: float = ROT_SPEED_DEFAULT

# Deadzone scroll box — the central fraction of the viewport the active tile may
# roam before the camera scrolls to keep it inside (FFT-style: camera holds
# still until the cursor pushes the box edge, then catches up just enough). The
# box is evaluated in the camera's own right/up basis, so it stays a screen-
# aligned rectangle across yaw/pitch rotation and constrains BOTH axes (the
# vertical one captures world height and depth together). 1.0 = whole screen
# (camera only scrolls when the tile would leave view); smaller = tighter box.
@export_range(0.05, 1.0, 0.01) var deadzone_width: float = DEADZONE_WIDTH_DEFAULT:
	set(value):
		deadzone_width = value
		if _deadzone_overlay:
			_deadzone_overlay.queue_redraw()
@export_range(0.05, 1.0, 0.01) var deadzone_height: float = DEADZONE_HEIGHT_DEFAULT:
	set(value):
		deadzone_height = value
		if _deadzone_overlay:
			_deadzone_overlay.queue_redraw()

## Native px below the frame midpoint at which this camera frames the tile it follows —
## FFT's low optical centre (see VERTICAL_DATUM_SLUG). Applied by _apply_vertical_datum
## as a camera-LOCAL-up offset, so it is a screen-space shift that survives yaw, pitch
## and zoom. 0 = the centred framing this rig had before.
@export_range(-60.0, 60.0, 1.0) var vertical_datum_px: float = VERTICAL_DATUM_DEFAULT:
	set(value):
		vertical_datum_px = value
		_apply_vertical_datum(1.0)
		if _deadzone_overlay:
			_deadzone_overlay.queue_redraw()

# Camera angle toggle (F key)
const ANGLE_HIGH: float = -26.54  # Default angle
const ANGLE_LOW: float = -39.37   # Lower angle for steep walls
var is_low_angle: bool = false
var focus_point: Node3D
var camera: Camera3D

# --- FFT polygon visible-angles cull: PSX camera angle ----------------------
#
# The per-polygon cull (mesh-resource +0xB0 bitfield, mask 0x3FFC) runs in
# `fft_visible_angles.gdshaderinc` against a global `psx_camera_angle` int
# on the PSX 0..0xFFF scale (0x000=N, 0x400=E, 0x800=S, 0xC00=W). Derived
# every frame from `focus_point.global_rotation.y` so the cull tracks Q/E
# yawing without manual upkeep.
#
# There is no camera-angle fudge: the raw focus-yaw → PSX-angle conversion is
# the true PSX BATTLE camera angle (calibrated via the sprite pose-octant path),
# and the ROM-authored cull TABLE is indexed by exactly that angle — so the bits
# apply as-is with no offset. (The former `psx_camera_angle_offset` knob is
# deleted. Issue #135 briefly remapped the cull table in the parser on the theory
# that the ADR-0052 180°-about-X flip negated the view azimuth; that double-
# counted the flip and over-culled the parked quadrant — reverted. The flip is a
# geometry-display transform; the cull decision is an angle-vs-table test and
# both sides already live in PSX-angle space.)
var procedural_map: Node3D
var pivot_marker: MeshInstance3D  # Visual marker for focus point
var show_pivot_marker: bool = false  # Toggle for debug pivot marker

# Saved state for restoring after takeover mode. Yaw/pitch/zoom are always
# saved here. XYZ is only used as a fallback for hosts that have NO TileCursor
# (cinematic/effect-viewer test scenes); when a cursor exists, _follow_target
# takes precedence over _saved_global_pos on release_takeover (ADR-0041 /
# handoff Q9 — cursor is authoritative *when it exists*).
var _saved_global_pos: Vector3
var _saved_x_rot: float
var _saved_y_rot: float
var _saved_camera_size: float

# Smooth return from takeover mode
var _returning: bool = false
var _return_frame: int = 0
var _return_total: int = 16
var _return_from_pos: Vector3
var _return_from_rot: Vector3
var _return_from_size: float

# Datum-only ease for the BY-FIAT cursor resume (`resume_cursor_framing`), in SECONDS
# elapsed on the rig's unscaled wall clock. Negative means no blend is running and the datum
# plants at full strength — the state every scene boots in.
#
# Deliberately NOT `_returning`: that path also lerps body XYZ and `camera.size` toward
# `_saved_global_pos` / `_saved_camera_size`, and the by-fiat edge never latched those, so
# reusing it would fling the rig at whatever the last real `request_takeover` saved. It rides
# `handoff_ease_seconds` — the body glide armed on the same edge — so the two ways back into
# cursor framing read alike AND the entry is ONE curve. See _advance_datum_blend's 🔴.
var _datum_blend_seconds: float = -1.0

# Cursor-follow target — the world position the body eases toward in CURSOR
# mode. Set via follow_cursor() (push from TileCursor.cursor_moved signal).
# First non-snap follow_cursor seeds it; subsequent calls start a fresh ease.
var _follow_target: Vector3 = Vector3.ZERO
var _follow_has_target: bool = false
var _follow_from_pos: Vector3 = Vector3.ZERO
var _follow_frame: int = 0
## Cursor-follow ease duration in frames (60 Hz). Lower = snappier translation
## on Q/E and WASD-walk catch-up; higher = longer glide. 18 frames ≈ 0.30s
## cosine-eased single-tile step. Mutated live by the Camera tab slider.
@export_range(1, 60, 1) var follow_ease_frames: int = FOLLOW_EASE_FRAMES_DEFAULT
## Battle-handoff ease duration in SECONDS. Drives [method ease_onto] only; the tile-step
## path above is untouched. Mutated live by the Camera tab slider.
@export_range(0.1, 2.5, 0.05) var handoff_ease_seconds: float = HANDOFF_EASE_SECONDS_DEFAULT
## Wall-clock progress of a [method ease_onto] glide. `_follow_seconds_total > 0.0` is the
## flag that says "this ease is on the CLOCK", and `follow_cursor` clears it back to zero —
## so the two paths cannot both be live and the tile step keeps its frame counter.
var _follow_seconds: float = 0.0
var _follow_seconds_total: float = 0.0

# Last active-tile world pos handed to track_cursor — kept so the deadzone can be
# re-evaluated after a yaw/pitch rotation swings the tile around the focus point.
var _last_tracked_tile: Vector3 = Vector3.ZERO
var _has_tracked_tile: bool = false

# Camera-rotation feel toggle. When false (default, FFT-style), Q/E spins the
# camera first and only re-evaluates the cursor-tracking deadzone once the yaw
# settles — so the body translation runs AFTER the rotation finishes. When true,
# both transitions start on the Q/E press: the body eases toward its
# post-rotation deadzone target while the camera is still yawing. Toggle from
# the Camera tab to compare which feel is preferred.
var rotation_concurrent_translate: bool = ROTATION_CONCURRENT_TRANSLATE_DEFAULT

# Debug-only screen-space visualization of the deadzone box (Camera tab toggle).
var _deadzone_overlay: DeadzoneBoxOverlay

# Pivot locking - rapid rotation taps reuse same pivot
var locked_pivot: Vector3 = Vector3.ZERO
var pivot_lock_time: float = 0.0
const PIVOT_LOCK_DURATION: float = 0.4  # seconds

# Rotation settling - stop lerping once close enough to target
var rotation_settled: bool = false
const ROTATION_SETTLE_THRESHOLD: float = 0.001  # radians

# Translation kickoff threshold: fire the cursor recenter when the rotation has
# this much (or less) remaining (in DEGREES — UI-friendly; converted to rad in
# _maintain_rotation), instead of waiting for full settle. The rotation keeps
# lerping to its exact target, but the body translation begins overlapping the
# rotation tail — eliminating the perceptible "wait for rotation, then pan"
# gap. ~3° is well below user-noticeable for orthographic combat zoom; tune up
# (Camera tab slider) to start the pan earlier, down to delay it.
@export_range(0.0, 30.0, 0.1) var rotation_kickoff_remaining_deg: float = ROTATION_KICKOFF_DEFAULT

# True once the cursor recenter has fired for the current rotation, so kickoff
# doesn't re-fire every frame in the tail. Reset by _rotate_yaw /
# _toggle_camera_angle when a new rotation starts.
var _translation_kicked_off: bool = false

# Unscaled delta tracking (for camera rotation while paused)
var _last_frame_usec: int = 0

func _ready():
	focus_point = $FocusPoint
	camera = $FocusPoint/Camera

	# Create a visual marker for the pivot point
	_create_pivot_marker()

	# Create the (hidden) deadzone-box debug overlay
	_create_deadzone_overlay()

	# Get procedural map reference
	if procedural_map_path:
		procedural_map = get_node_or_null(procedural_map_path)

	# Auto-find if not set
	if not procedural_map:
		procedural_map = get_tree().get_first_node_in_group("procedural_map")
		if not procedural_map:
			procedural_map = get_node_or_null("../ProceduralMap")

	_bind_tunables()
	# Plant the framing before the first frame draws — _process is too late for a host
	# that reads the projection on frame 0, and for a test that never ticks _process.
	_apply_vertical_datum(1.0)


## Bind the cursor-follow "feel" knobs to their `camera.*` Tune slugs (ADR-0068).
## The camera OWNS these values, so a committed override coalesces at boot AND a live
## scrub re-drives the camera in EVERY scene — the Camera Feel panel is just a view
## (decision 12). `bind` (not read-once of()) because each value is read every frame
## off the property (or applied once to the overlay), so a scrub must re-drive it.
## bind is SPLIT from on_update (ADR-0068): register_tunables() binds the static-var homes +
## hints ONCE at class load (below); each instance subscribes an on_update push here. Not
## @tool-guarded: PlayerCamera never runs in the editor (no @tool).
func _bind_tunables() -> void:
	TunePort.on_update(self, DEADZONE_WIDTH_SLUG, func(v: float) -> void: deadzone_width = v)
	TunePort.on_update(self, DEADZONE_HEIGHT_SLUG, func(v: float) -> void: deadzone_height = v)
	TunePort.on_update(self, ROT_SPEED_SLUG, func(v: float) -> void: rot_speed = v)
	TunePort.on_update(self, FOLLOW_EASE_FRAMES_SLUG, func(v: int) -> void: follow_ease_frames = v)
	TunePort.on_update(self, HANDOFF_EASE_SECONDS_SLUG, func(v: float) -> void: handoff_ease_seconds = v)
	TunePort.on_update(self, ROTATION_CONCURRENT_TRANSLATE_SLUG,
		func(v: bool) -> void: rotation_concurrent_translate = v)
	TunePort.on_update(self, ROTATION_KICKOFF_SLUG, func(v: float) -> void: rotation_kickoff_remaining_deg = v)
	TunePort.on_update(self, SHOW_DEADZONE_BOX_SLUG, func(v: bool) -> void: set_deadzone_box_visible(v))
	# on_update, not a read-once: the datum is consumed every frame by _apply_vertical_datum,
	# so a scrub (and the 40 <-> 0 A/B the Framing section exists for) has to re-drive it.
	TunePort.on_update(self, VERTICAL_DATUM_SLUG, func(v: float) -> void: vertical_datum_px = v)


## Register the camera.* slugs to their static-var homes + hints ONCE at class load (R2), so a
## committed override coalesces at boot and the dashboard can enumerate the knobs before any
## camera spawns. Split from _bind_tunables (the per-instance on_update push) so
## it is this owner's named registration entry point — _static_init calls it at class load, and
## the ADR-0173 guards call it to read back which slugs this owner binds.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	TunePort.bind(DEADZONE_WIDTH_SLUG, DEADZONE_WIDTH_DEFAULT, DEADZONE_FRAC_HINT)
	TunePort.bind(DEADZONE_HEIGHT_SLUG, DEADZONE_HEIGHT_DEFAULT, DEADZONE_FRAC_HINT)
	TunePort.bind(ROT_SPEED_SLUG, ROT_SPEED_DEFAULT, ROT_SPEED_HINT)
	TunePort.bind(FOLLOW_EASE_FRAMES_SLUG, FOLLOW_EASE_FRAMES_DEFAULT, FOLLOW_EASE_FRAMES_HINT)
	TunePort.bind(HANDOFF_EASE_SECONDS_SLUG, HANDOFF_EASE_SECONDS_DEFAULT, HANDOFF_EASE_SECONDS_HINT)
	TunePort.bind(ROTATION_CONCURRENT_TRANSLATE_SLUG, ROTATION_CONCURRENT_TRANSLATE_DEFAULT)
	TunePort.bind(ROTATION_KICKOFF_SLUG, ROTATION_KICKOFF_DEFAULT, ROTATION_KICKOFF_HINT)
	TunePort.bind(SHOW_DEADZONE_BOX_SLUG, SHOW_DEADZONE_BOX_DEFAULT)
	TunePort.bind(FREE_CAMERA_SLUG, FREE_CAMERA_DEFAULT)
	TunePort.bind(VERTICAL_DATUM_SLUG, VERTICAL_DATUM_DEFAULT, VERTICAL_DATUM_HINT)


## The free-pan gate. Reads the coalesced override live, so a scrub in the generated
## dashboard reaches the next input event. Static so `TileCursor` — the one reader
## outside this file — can consult it without holding a camera instance.
static func free_camera() -> bool:
	if Engine.is_editor_hint():
		return FREE_CAMERA_DEFAULT
	return TunePort.get_value(FREE_CAMERA_SLUG, FREE_CAMERA_DEFAULT)


func _create_pivot_marker():
	# Create a small sphere to show where the focus point is
	pivot_marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	pivot_marker.mesh = sphere

	# Make it bright red and unlit
	# psx-ot-depth-exempt: debug focus-point marker, not battle render geometry
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.RED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pivot_marker.material_override = material

	focus_point.add_child(pivot_marker)


func _create_deadzone_overlay() -> void:
	# CanvasLayer so the Control draws over the game viewport regardless of where
	# the camera node sits in the tree. Hidden until toggled from the debug tab.
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_deadzone_overlay = DeadzoneBoxOverlay.new()
	_deadzone_overlay.setup(self)
	_deadzone_overlay.visible = false
	layer.add_child(_deadzone_overlay)


## Show/hide the screen-space deadzone-box debug overlay (Camera tab checkbox).
func set_deadzone_box_visible(value: bool) -> void:
	if _deadzone_overlay == null:
		return
	_deadzone_overlay.visible = value
	if value:
		_deadzone_overlay.queue_redraw()


func is_deadzone_box_visible() -> bool:
	return _deadzone_overlay != null and _deadzone_overlay.visible


func request_takeover(_driver: Object) -> void:
	"""Save yaw/pitch/zoom (+ XYZ as a no-cursor fallback) and switch to
	takeover-controlled camera.

	`driver` is typed as Object (NOT Node) because the live drivers
	(CinematicManager extends RefCounted; EffectViewerScene extends Node) are
	in different branches of the type hierarchy — Object is the common
	ancestor. The param is captured for future bookkeeping/logging; today it
	is unused and not routed anywhere. When a TileCursor exists,
	release_takeover lerps the body back to the cursor's tile; when there is
	no cursor (test scenes that don't instantiate one), it lerps back to the
	saved XYZ. (ADR-0041 — cursor is authoritative when it exists.) See
	CONTEXT.md `Takeover mode`."""
	_saved_global_pos = global_position
	_saved_x_rot = x_target_rot
	_saved_y_rot = y_target_rot
	_saved_camera_size = camera.size
	camera_mode = CameraMode.TAKEOVER
	# Disable collision during takeover so physics doesn't fight direct positioning
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = true


func release_takeover() -> void:
	"""Restore saved yaw/pitch/zoom and lerp the body back to the cursor's tile.

	The cursor is the sole authority on body XYZ — we lerp to _follow_target
	(its last-known world position), not a saved pre-takeover pos."""
	_return_from_pos = global_position
	_return_from_rot = focus_point.global_rotation
	_return_from_size = camera.size

	camera_mode = CameraMode.CURSOR
	x_target_rot = _saved_x_rot
	y_target_rot = _saved_y_rot
	_returning = true
	_return_frame = 0
	_datum_blend_seconds = -1.0  # `_returning` drives the datum here, not the fiat blend
	rotation_settled = true  # Suppress cursor-mode rotation lerp during return

	# Re-enable collision
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = false


## Hand the rig to a takeover driver BY FIAT — no `request_takeover` — without moving the
## framed point. [method NavigatorMain._return_camera] is the seam this exists for.
##
## 🔴 NOTHING ELSE RUNS ON THIS EDGE. `ScenarioCameraDirector` guards all four of its
## `request_takeover` calls behind `_camera_taken_over`, which it latches once in the
## group's opener and never resets, so on the victory beat the director takes the
## early-out and this assignment is the whole handback.
##
## [method _apply_vertical_datum] targets 0 in TAKEOVER and re-plants every frame in every
## mode, so a bare `camera_mode = TAKEOVER` drops `camera.position.y` by the full datum in
## ONE frame — 40 of 240 native px, 16.7 % of the view height at ortho 8.30, with nothing
## else on screen moving. On scenario 12 the beat's own `{19}` is 120 ticks (1.49 s) away,
## so that pop plays bare on the live battlefield. It is the reported "camera teleports".
##
## The answer is a FOLD, not a blend: slide the body up its own local Y by exactly the
## datum the Camera3D is about to give back. The Camera3D's WORLD position is then
## bit-identical across the flip, so the framed point is EXACTLY continuous — no easing
## needed, because nothing moves. The body is left `datum` above the cursor's tile, which
## is harmless here precisely because a driver is about to overwrite `global_position` on
## its next `apply_takeover`.
##
## ⚠️ THE MIRROR EDGE BLENDS INSTEAD, AND THE ASYMMETRY IS DELIBERATE — see [method
## resume_cursor_framing]. There no driver is about to overwrite the body, and
## `_execute_cursor_follow` no-ops once `_follow_frame` is spent, so an exact fold would
## leave the cursor framed 40 px low until the player next moved it. Each half matches its
## own hazard; this is not one of them done wrong.
##
## Does NOT latch `_saved_global_pos` / `_saved_x_rot` / `_saved_y_rot` /
## `_saved_camera_size` and does NOT disable collision, unlike [method request_takeover] —
## both are inert on this path and latching them would be a behaviour change bought with
## no defect. The saved pose is only ever read by [method release_takeover], which nothing
## on the scenario path calls (the director has no release site at all; FormationMapHost,
## CinematicManager and EffectViewerScene each `request_takeover` first). Collision is only
## consulted by `move_and_slide` in `_execute_translation`, which sits behind `_process`'s
## `camera_mode != CameraMode.CURSOR` return.
func enter_takeover_framing() -> void:
	if camera_mode == CameraMode.TAKEOVER:
		return
	if camera != null and focus_point != null:
		global_position += focus_point.global_basis.y * camera.position.y
		camera.position.y = 0.0
	_datum_blend_seconds = -1.0  # the fold already landed the datum; nothing left to ease
	camera_mode = CameraMode.TAKEOVER


## Take the rig back from a takeover driver BY FIAT — no `release_takeover` return lerp —
## easing the framing datum in and re-truthing the rotation targets. [method
## NavigatorMain._enter_command_cursor] is the seam: command mode forces CURSOR so the
## dagger shows and drives, and the group's opener left the rig in TAKEOVER.
##
## Two things are wrong with a bare `camera_mode = CURSOR`.
##
## THE DATUM steps 0 → full in one frame (measured 0 → 1.383 at Gariland). Unlike the exit
## edge we cannot fold it into the body: [method _execute_cursor_follow] returns
## immediately once `_follow_frame >= follow_ease_frames`, so a folded body would sit 40 px
## off-centre until the player next moved the cursor. So ease it in on the same curve, clock
## and length as the body glide this edge arms — [method release_takeover]'s return already
## does exactly this via `_apply_vertical_datum(ct)`, for exactly this reason. The 🔴 on
## [method _advance_datum_blend] is why sharing the LENGTH is load-bearing and not tidiness.
##
## THE ROTATION TARGETS still hold whatever the rig wanted before the opener took over,
## while `rotation_settled` is true — so [method _maintain_rotation] returns immediately and
## the targets are a LIE for the whole battle. Measured live: the rig holds `yaw=135.0`
## (the opener's terminal `{19}`, Map Rotation 5632) while `y_target_rot=-45.0`, so the
## first Q/E steps from a yaw the player is not looking at. Sync both from the held pose.
##
## ⚠️ `rotation_settled` STAYS TRUE. After the sync the pose IS the target, which is
## exactly what the flag claims; setting it false would assert something untrue in order to
## run a zero-length lerp whose only reachable effect is tripping `_maintain_rotation`'s
## kickoff `follow_cursor` and moving the body on the battle's first frame.
##
## ⚠️ EDGE-ONLY, and that guard is load-bearing: `_enter_command_cursor` runs TWICE per
## battle (once from `run_pre_battle`, once from `run_combat`). Syncing on the second call
## would capture a MID-LERP pose if the player pressed Q/E during deployment and abort
## their rotation.
##
## This does NOT fix the 180° yaw whip at the end of a battle. That whip is authored: the
## Gariland opener's terminal `{19}` is Map Rotation 5632 (yaw 135°) and the victory beat's
## sole Camera op is Map Rotation 3584 (yaw −45°, `Time=48`). The beat drives the rig
## through [method apply_takeover], which writes `focus_point.global_rotation` absolutely,
## so `x_target_rot` / `y_target_rot` are inert while it plays.
func resume_cursor_framing() -> void:
	if camera_mode == CameraMode.CURSOR:
		return
	if focus_point != null:
		x_target_rot = rad_to_deg(focus_point.global_rotation.x)
		y_target_rot = rad_to_deg(focus_point.global_rotation.y)
		rotation_settled = true
	_datum_blend_seconds = 0.0
	camera_mode = CameraMode.CURSOR


## Push from TileCursor.cursor_moved — the cursor's new world position. First
## call (or any call with snap=true) snaps the body; subsequent calls start a
## fresh cosine-eased lerp over follow_ease_frames frames. The body rises with
## the cursor walking up a ramp (full XYZ lerp, including Y).
func follow_cursor(world_pos: Vector3, snap: bool = false) -> void:
	_follow_target = world_pos
	# BACK TO THE FRAME COUNTER. A tile step is frame-quantised on purpose — it is the
	# cursor's own hop, and `TurnBeat` mirrors `follow_ease_frames` as a frame countdown to
	# ride it. Only the handoff runs on the clock (see `ease_onto`).
	_follow_seconds_total = 0.0
	_follow_seconds = 0.0
	if not _follow_has_target or snap:
		_follow_has_target = true
		global_position = world_pos
		_follow_frame = follow_ease_frames  # mark settled
		return
	_follow_from_pos = global_position
	_follow_frame = 0


## Ease the body onto `world_pos` FROM WHERE IT STANDS — the same cosine lerp
## `follow_cursor` runs, but without its first-call snap.
##
## The distinction it exists for is the battle handoff (#1168): a cursor seeded on a
## freshly-booted bare scene has no prior framing to preserve and SHOULD snap, but a
## cursor seeded at the end of a battle intro is taking over a camera the cinematic
## deliberately posed ({19} at scn 10 pc 33 IS the battle's opening framing). There,
## `follow_cursor(pos, false)` still snapped — `_follow_has_target` is false, because
## nothing had driven the follow path while the opener held the camera in TAKEOVER —
## and the player saw a 6.64-unit hard cut the frame the dark screen finished
## retracting. The seat is the same either way; only the journey differs.
##
## 🔴 AND THE JOURNEY NEEDS ITS OWN CLOCK AND ITS OWN LENGTH. Easing instead of cutting fixed
## the teleport and the report MOVED rather than went away — "the jerk is now after the ready
## fade, and maybe the camera moves too fast". Both halves are measured, and both come from
## this call having borrowed `follow_ease_frames`, which is neither its duration nor its unit.
##
## LENGTH. `follow_ease_frames` is 18 frames because that is a good SINGLE-TILE step — its own
## doc says so ("18 frames ≈ 0.30s cosine-eased single-tile step"). The handoff is 6.699 units
## at Gariland, so the same 18 frames run it at ~27 u/s where a tile step runs at ~3. The
## reference for how fast this ought to be is the move the report named as the good one — the
## camera between combat and Ramza's dialogue at the end of a battle. That is an authored ROM
## `{19}`, and the victory beat's is `Time=48` ticks = **0.80 s**, which is this default.
##
## UNIT. `_execute_cursor_follow`'s counter advances once per FRAME, so the ease's wall-clock
## speed is whatever the frame pacing happens to be — fine at a steady 60 Hz, and wrong here.
## This ease is armed on the frame straight after `FormationMapHost._ready`'s ~60 ms hitch;
## the swapchain has drained, so Godot renders the next three frames in 2–3 ms each and the
## ease burns five of its eighteen steps in 37 ms instead of 83. Measured over three idle-box
## runs: peak 111–123 u/s against a 27 u/s mean, **2.0–4.5x**, always at step 1 or 2. The
## per-frame STEP stays a clean cosine throughout (2nd difference 3.1 % of peak), which is
## why the first pass's spike-shaped verdict could not see it. So this ease advances on the
## CLOCK. `ScenarioCameraDirector` reached the same conclusion for the cinematic rig and says
## so on `_cam_lerp_elapsed_s` — the exit the report compares against has been seconds-driven
## all along, and this is the entry catching up to it.
##
## ⚠️ NOT a reuse of `camera.follow_ease_frames` with a bigger number, and not a conversion of
## the tile-step path. A tile step is the cursor's hop and is frame-quantised deliberately;
## `TurnBeat` reads `follow_ease_frames` at arm time as a frame countdown to ride it. Two
## motions, two clocks, two knobs — `camera.handoff_ease_seconds` is the second.
func ease_onto(world_pos: Vector3) -> void:
	_follow_target = world_pos
	_follow_has_target = true
	_follow_from_pos = global_position
	_follow_frame = 0
	_follow_seconds = 0.0
	_follow_seconds_total = maxf(0.05, handoff_ease_seconds)


## Push from TileCursor.cursor_moved — the active tile's world position, run
## through the deadzone scroll box. The first call (no prior target) snaps the
## focus onto the tile. After that, the camera only scrolls when the tile would
## sit outside the central box, and then only far enough to bring it back to the
## box edge; while the tile stays inside the box the focus is left untouched, so
## the camera holds still. The catch-up reuses the existing cosine ease.
##
## NOTE: this is the WASD-walk path. Q/E rotation skips the deadzone entirely
## and recenters the camera on the cursor's tile via follow_cursor — FFT's
## rotation move is a full recenter, not a deadzone re-clamp.
func track_cursor(tile_world: Vector3) -> void:
	_last_tracked_tile = tile_world
	_has_tracked_tile = true
	if not _follow_has_target:
		follow_cursor(tile_world, true)  # seed: snap focus onto the tile
		return
	var new_focus := _deadzone_focus(tile_world, _follow_target)
	if new_focus.is_equal_approx(_follow_target):
		return  # tile is inside the box — don't disturb the held camera
	follow_cursor(new_focus)


## Given the active tile and the camera's current focus point, return the focus
## the camera should move to so the tile lands no further than the box edge. If
## the tile already projects inside the box the focus is returned unchanged.
## Worked entirely in the camera's right/up basis so it is correct under any yaw
## or pitch and naturally covers both screen axes (the up axis blends world
## height and depth, exactly as they share the vertical screen axis).
func _deadzone_focus(tile_world: Vector3, focus: Vector3) -> Vector3:
	if camera == null:
		return tile_world
	var cam_basis := camera.global_transform.basis
	var cam_right := cam_basis.x
	var cam_up := cam_basis.y
	var offset := tile_world - focus
	var off_right := offset.dot(cam_right)
	var off_up := offset.dot(cam_up)

	var half := deadzone_half_extents()
	var corr_right := _overshoot(off_right, half.x)
	var corr_up := _overshoot(off_up, half.y)
	return focus + corr_right * cam_right + corr_up * cam_up


## How far `v` lies outside the symmetric band [-half, half]; 0 while inside.
##
## The band stays SYMMETRIC about the focus even with the framing datum on, because the
## datum moves the RIG rather than the box: the focus is what got dropped down the
## screen, and the box is centred on the focus. The alternative — leaving the camera
## centred and skewing this band — was rejected, because the box is only one of three
## things that place the cursor. `track_cursor` goes through it; `follow_cursor(tile,
## true)` (the first-cursor snap) does not; and Q/E yaw skips the deadzone entirely for
## a full recenter (see `_rotate_yaw`). A skewed band fixes the first and leaves the
## other two yanking the cursor back to the midpoint on every rotation.
func _overshoot(v: float, half: float) -> float:
	if v > half:
		return v - half
	if v < -half:
		return v + half
	return 0.0


## The aspect ratio of the viewport this camera renders into; 1.0 with no viewport.
func _viewport_aspect() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 1.0
	var vp_size := viewport.get_visible_rect().size
	if vp_size.y <= 0.0:
		return 1.0
	return vp_size.x / vp_size.y


## The framing datum CURRENTLY APPLIED, in world units — how far up the camera sits from
## the point it frames. Read off the rig rather than recomputed, so the deadzone box and
## its overlay describe the framing that is actually on screen, including mid-blend
## during the takeover return and zero while a takeover driver owns the pose.
func vertical_datum_offset() -> float:
	return camera.position.y if camera != null else 0.0


## Half-extents of the deadzone box in the camera's right/up basis, world units.
##
## The vertical half-extent is CLAMPED to the room the framing leaves. With the datum on,
## the box centre sits `d` below the screen centre, so only `half_h - d` of view remains
## underneath it; at the shipped 40 px that caps `deadzone_height` at ~0.66 while the
## slider's hint still reaches 1.0. Clamping HERE rather than capping the hint is
## deliberate — `camera.vertical_datum_px` is itself live-scrubbable, so any fixed hint
## max would be wrong the moment the datum moves. Unclamped, a taller box puts its lower
## edge off-screen, where the tile can never reach it and the camera stops scrolling
## down at all.
func deadzone_half_extents() -> Vector2:
	var half_h: float = (camera.size if camera != null else 1.0) * 0.5
	var room := maxf(half_h - absf(vertical_datum_offset()), 0.0)
	return Vector2(
		half_h * _viewport_aspect() * deadzone_width,
		minf(half_h * deadzone_height, room))


## The deadzone box as VIEWPORT FRACTIONS (0..1, origin top-left) — one description of
## the box's screen geometry, shared by the world-space math above and by
## DeadzoneBoxOverlay's `_draw`. Its centre is the FRAMED point, which the datum puts
## below the viewport midpoint; an overlay that keeps drawing about `size * 0.5`
## contradicts the math it exists to illustrate.
func deadzone_box_screen_rect() -> Rect2:
	var view_h: float = maxf(camera.size if camera != null else 1.0, 0.0001)
	var half := deadzone_half_extents()
	var w := (2.0 * half.x) / maxf(view_h * _viewport_aspect(), 0.0001)
	var h := (2.0 * half.y) / view_h
	# Screen-Y grows DOWNWARD, and the framed point sits `d` BELOW the camera axis in
	# view space — so a positive datum moves the box's centre to a LARGER fraction.
	var cy := 0.5 + vertical_datum_offset() / view_h
	return Rect2(0.5 - w * 0.5, cy - h * 0.5, w, h)


## Plant the framing datum on the rig: slide the Camera3D up its own local Y, inside the
## rotated FocusPoint, so the body it hangs off projects `vertical_datum_px` native px
## BELOW the frame midpoint. Local-up and post-rotation, exactly like the GTE's TR —
## a WORLD-space nudge was tried and deleted (ADR-0057) because its projected screen
## shift rotates with the camera and one tuned value is then wrong at every other pose.
## Scaled by `camera.size` so the offset stays PIXEL-constant across zoom.
##
## 🔴 ZERO IN TAKEOVER, OR THE DATUM APPLIES TWICE. `ScenarioCameraDirector` bakes the
## same shift into the body pose it hands `apply_takeover()`; adding it here as well
## would frame the cinematic 80 px low. `blend` eases it back in over the takeover
## return for the same reason — at release the body is still on the cinematic pose,
## which already carries the datum, so snapping the rig offset on would jump the image.
## Step the by-fiat datum ease one frame and return the blend factor for this frame:
## 1.0 whenever no ease is running (the overwhelmingly common case), otherwise the same
## cosine curve `_returning` uses — over `handoff_ease_seconds`, on the WALL CLOCK.
##
## 🔴 IT RIDES THE BODY'S CLOCK, AND THAT IS THE POINT. This used to be its own 16-FRAME
## counter borrowed from `_return_total`, which read identically only while the body ease was
## also ~18 frames. Give the handoff its true length (0.80 s, see [method ease_onto]) and the
## two come apart: the datum's 1.383 units of vertical framing land inside the first third of
## an 800 ms glide, so the camera goes UP and then ALONG instead of straight. It is visible in
## the trace as ARC LENGTH — the Camera3D covered 7.509 units getting to a point 6.699 units
## away. Same duration, same curve, same start frame = one motion, which is what the exit
## (`_returning`) has always been and what the entry was asked to look like.
##
## Advancing here rather than in `_process` keeps the ease's whole lifetime — start, step,
## retire — inside one function with `resume_cursor_framing`, which is the only thing that
## arms it. If a real `release_takeover` return is ALSO in flight, `_returning`'s own
## `_apply_vertical_datum(ct)` further down `_process` overrides this frame's value; the
## counter still retires on schedule, and `release_takeover` disarms it anyway.
func _advance_datum_blend(delta: float) -> float:
	if _datum_blend_seconds < 0.0:
		return 1.0
	var total := maxf(0.05, handoff_ease_seconds)
	_datum_blend_seconds += delta
	if _datum_blend_seconds >= total:
		_datum_blend_seconds = -1.0
		return 1.0
	return 0.5 - 0.5 * cos(PI * (_datum_blend_seconds / total))


func _apply_vertical_datum(blend: float) -> void:
	if camera == null:
		return
	var target := 0.0
	if camera_mode == CameraMode.CURSOR:
		target = (vertical_datum_px / DisplayPort.NATIVE_VIEWPORT_HEIGHT) * camera.size
	camera.position.y = target * blend


func apply_takeover(pos: Vector3, rot: Vector3, ortho_size: float) -> void:
	"""Apply camera values from the active takeover driver (only works in TAKEOVER mode)"""
	if camera_mode != CameraMode.TAKEOVER:
		return
	global_position = pos
	focus_point.global_rotation = rot
	camera.size = ortho_size


## The free-pan directions currently down, accumulated from EVENTS, and the actions that
## drive them. `_execute_translation` used to read all four straight off the [Input] singleton
## every frame, and that poll is why `check_focus_anchor.py` listed this file: registering
## with Focus cannot discharge a poll, because the switch stops Godot CALLING a non-holder and
## cannot stop one ASKING.
const PAN_ACTIONS: Array[StringName] = [
	&"camera_up", &"camera_down", &"camera_left", &"camera_right",
]
var _pan_held: Array[StringName] = []


## Which free-pan directions are held. Public because it is the only observable a test has:
## the consumer is `move_and_slide()` on a body in a scene with no floor, so "the press was
## accepted" cannot be read off `global_position`.
func pan_directions_held() -> Array[StringName]:
	return _pan_held.duplicate()


## Fold one event into [member _pan_held].
##
## Called ABOVE `_input`'s CURSOR-mode return, and that is deliberate: the poll this replaces
## read the device whatever mode the camera was in, so a key held through a TAKEOVER was still
## held on the way back. Tracking only in CURSOR mode would have quietly dropped it.
func _track_pan(event: InputEvent) -> void:
	for action in PAN_ACTIONS:
		if event.is_action_pressed(action):
			if not _pan_held.has(action):
				_pan_held.append(action)
		elif event.is_action_released(action):
			_pan_held.erase(action)


## Alt-tab. The key comes up while the window is unfocused, the release is never delivered to
## anyone, and the poll simply saw it gone on the next frame; a tracked list has to be told,
## or free-pan comes back gliding on a key nobody is holding.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_pan_held.clear()


## The HOST's hand on the camera's ear — false while the host is running a beat the player may
## not interrupt (see `CursorRig.input_enabled`, which is the same flag on the cursor half).
## Nothing inside this addon writes it.
##
## It gates the ACTING half of `_input` and deliberately not `_track_pan`, which sits above it
## for the reason that function already states: a key held across a deafness has to be tracked
## through it, or its release is delivered to nobody and free-pan comes back gliding on a key
## nobody is holding.
##
## Why the camera needs its own flag at all, when the cursor already has one: Q/E do NOT reach
## the cursor. `_rotate_yaw` calls `follow_cursor(_last_tracked_tile)` when
## `rotation_concurrent_translate` is on, which re-aims a running travel at wherever the cursor
## was parked BEFORE the beat — so a beat that silenced only the cursor would be steerable by
## the one key it forgot.
var input_enabled: bool = true


func _input(event):
	_track_pan(event)
	if not input_enabled:
		return
	if camera_mode != CameraMode.CURSOR:
		return
	if event.is_action_pressed("rotate_camera_ccw"):
		_rotate_yaw(1)  # Counter-clockwise
	if event.is_action_pressed("rotate_camera_cw"):
		_rotate_yaw(-1)  # Clockwise
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_toggle_camera_angle()


## Q/E yaw dispatch. Cursor mode just increments the target yaw — no raycast,
## no pivot teleport, no pivot-lock cooldown; the body is already where the
## cursor sits. Free-pan mode uses the legacy raycast-pivot path
## (_rotate_around_terrain) so debug body-pan rotation stays orbital.
##
## FFT recenters the camera on the cursor every Q/E press (the deadzone is for
## WASD walk only). When `rotation_concurrent_translate` is on, the recenter
## starts on the press so the body eases in parallel with the yaw; when off
## (default FFT-sequential), _maintain_rotation fires it once the yaw settles.
func _rotate_yaw(direction: int) -> void:
	if free_camera():
		_rotate_around_terrain(direction)
		return
	y_target_rot = wrapf(y_target_rot + 90 * direction, -180, 180)
	rotation_settled = false  # Start lerping to new target
	_translation_kicked_off = false  # Allow kickoff to fire once for this rotation
	if rotation_concurrent_translate and _has_tracked_tile:
		follow_cursor(_last_tracked_tile)
		_translation_kicked_off = true


func _toggle_camera_angle():
	"""Toggle between high and low camera angles."""
	is_low_angle = not is_low_angle
	x_target_rot = ANGLE_LOW if is_low_angle else ANGLE_HIGH
	rotation_settled = false  # Start lerping to new target
	_translation_kicked_off = false  # Allow kickoff to fire once for this rotation


func _process(_delta):
	# Use unscaled delta so camera rotation works while paused
	var now_usec = Time.get_ticks_usec()
	var unscaled_delta = (now_usec - _last_frame_usec) / 1_000_000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now_usec

	# Clamp to reasonable range (prevent huge jumps on first frame or after lag)
	unscaled_delta = clampf(unscaled_delta, 0.0, 0.1)

	_update_psx_camera_angle()
	# Ahead of the mode returns below, so the datum is re-planted in EVERY mode: it
	# tracks a live `camera.size` and a live scrub, and it must resolve to zero the
	# frame a takeover driver takes the pose over. The factor is 1.0 except while
	# `resume_cursor_framing`'s by-fiat ease is running.
	_apply_vertical_datum(_advance_datum_blend(unscaled_delta))

	# Smooth return from takeover mode. Cursor is XYZ authority — we lerp to
	# _follow_target (the cursor's last-known world position).
	if _returning:
		_return_frame += 1
		var t = float(_return_frame) / float(_return_total)
		var ct = 0.5 - 0.5 * cos(PI * t)  # Cosine ease in-out
		var target_xyz: Vector3 = _follow_target if _follow_has_target else _saved_global_pos
		global_position = _return_from_pos.lerp(target_xyz, ct)
		camera.size = lerpf(_return_from_size, _saved_camera_size, ct)
		var target_rot = Vector3(deg_to_rad(_saved_x_rot), deg_to_rad(_saved_y_rot), 0)
		focus_point.global_rotation = Vector3(
			lerp_angle(_return_from_rot.x, target_rot.x, ct),
			lerp_angle(_return_from_rot.y, target_rot.y, ct),
			lerp_angle(_return_from_rot.z, target_rot.z, ct))
		# Ease the datum in on the same curve — see _apply_vertical_datum's 🔴.
		_apply_vertical_datum(ct)
		if _return_frame >= _return_total:
			_returning = false
			global_position = target_xyz
			camera.size = _saved_camera_size
			focus_point.global_rotation = target_rot
			_apply_vertical_datum(1.0)
			rotation_settled = false  # Allow cursor-mode rotation again
			# Body now matches the follow target — mark BOTH clocks spent, or a handoff ease
			# armed before this return would resume against a body that already arrived.
			_follow_frame = follow_ease_frames
			_follow_seconds = _follow_seconds_total
		return

	# In takeover mode, skip cursor-mode controls (driver writes pos/rot directly)
	if camera_mode != CameraMode.CURSOR:
		return

	_maintain_rotation(unscaled_delta)
	_execute_cursor_follow(unscaled_delta)
	_execute_translation()
	_update_pivot_marker()


## Derive the PSX 12-bit camera angle from the live focus-point yaw and
## publish it to the global shader uniform consumed by
## `fft_visible_angles.gdshaderinc`.
##
## The formula is the mathematical inverse of ScenarioVM's
## `PsxChirality.psx_angles_to_godot_rotation`, which has been
## visually calibrated against the chapel cinematic — that path produces
## `godot.y = psx * TAU / 4096  (mod TAU)`, so the inverse is
## `psx = +yaw_rad / TAU * 4096  (mod 4096)`. No negation, no constant
## offset: trust the calibrated forward map. This yields the true PSX camera
## angle, which is exactly the index the ROM-authored cull table expects, so no
## runtime angle fudge (and no parser-side table remap — #135, reverted) is
## needed.
##
## Live `_psx_camera_angle_debug` is exposed for the F3 panel HUD so we
## can verify yaw → PSX-angle alignment visually as the camera rotates.
var _psx_camera_angle_debug: Dictionary = {
	"yaw_deg": 0.0, "psx_auto": 0, "psx_final": 0,
}
var _psx_camera_angle_last_logged: int = -1
var _psx_camera_angle_log_acc: float = 0.0

func _update_psx_camera_angle() -> void:
	if focus_point == null:
		return
	var yaw_rad: float = focus_point.global_rotation.y
	# The wheel's width is named, not spelled: `4096.0` and `4096` here were a raw PSX
	# magnitude re-derived outside the seam (ADR-0091). It went unreported until
	# extraction #3's loop pass 6 — `check_no_raw_psx_units.py` scans `src/effects`,
	# `src/scenarios`, `src/projectiles` and EVERY ADDON ROOT, and this file lived in
	# `src/scenes/`, which is in none of them. `PsxNum` is `platform`'s, so naming it
	# from inside the addon is a port reach and free on arm 1 (ADR-0139 dec. 12).
	var psx: int = posmod(int(round(yaw_rad / TAU * PsxNum.TURN_12BIT)), PsxNum.TURN_12BIT)
	# The push AND the runtime mirror are the PORT's, not this file's (#590,
	# ADR-0171 dec. 1). `psx_camera_angle` is the sixth global shader parameter
	# the codebase pushes and it was the only one pushed from outside the port
	# that owns the other five; the mirror it used to write —
	# `DebugConfig.psx_camera_angle_12bit` — was `Debug` being used as a global
	# variable for camera state, and was this addon's last reach into a SYSTEM
	# that a port could answer.
	DisplayPort.set_camera_angle(psx)
	_psx_camera_angle_debug.yaw_deg = rad_to_deg(yaw_rad)
	_psx_camera_angle_debug.psx_auto = psx
	_psx_camera_angle_debug.psx_final = psx
	# Log only when the value actually changes, capped to ~2Hz, to keep the
	# console from drowning in repeat lines while still surfacing every
	# scenario Camera-opcode rotation.
	var now := Time.get_ticks_msec()
	if psx != _psx_camera_angle_last_logged and (now - int(_psx_camera_angle_log_acc)) > 500:
		print("[PSXAngle] yaw=%.1f° psx=0x%03X" % [rad_to_deg(yaw_rad), psx])
		_psx_camera_angle_last_logged = psx
		_psx_camera_angle_log_acc = float(now)


## Cosine-eased lerp toward `_follow_target`. No-op if no cursor has ever pushed a position,
## or if the body is already on target.
##
## TWO CLOCKS, and which one is live is a property of the CALL that armed the ease:
## `follow_cursor` (the cursor's own tile hop) counts FRAMES over `follow_ease_frames`;
## `ease_onto` (the battle handoff) counts SECONDS over `handoff_ease_seconds`. `delta` is the
## rig's UNSCALED wall clock, already clamped to 0.1 s in `_process`, so a stall costs the
## glide dropped frames rather than a teleport. The 🔴 on [method ease_onto] is why.
func _execute_cursor_follow(delta: float) -> void:
	if not _follow_has_target:
		return
	var t := 0.0
	if _follow_seconds_total > 0.0:
		if _follow_seconds >= _follow_seconds_total:
			return
		_follow_seconds = minf(_follow_seconds + delta, _follow_seconds_total)
		t = _follow_seconds / _follow_seconds_total
	else:
		if _follow_frame >= follow_ease_frames:
			return
		_follow_frame += 1
		t = float(_follow_frame) / float(follow_ease_frames)
	var ct = 0.5 - 0.5 * cos(PI * t)
	global_position = _follow_from_pos.lerp(_follow_target, ct)
	if t >= 1.0:
		global_position = _follow_target


func _maintain_rotation(delta):
	# Skip if already settled at target rotation
	if rotation_settled:
		return

	var target_rot = Vector3(
		deg_to_rad(x_target_rot),
		deg_to_rad(y_target_rot),
		0
	)

	var current_rot = focus_point.global_rotation

	# Check if close enough to target - settle and stop lerping
	var diff_x = abs(angle_difference(current_rot.x, target_rot.x))
	var diff_y = abs(angle_difference(current_rot.y, target_rot.y))
	var diff_z = abs(angle_difference(current_rot.z, target_rot.z))
	var max_diff = maxf(diff_x, maxf(diff_y, diff_z))

	# Kick off the cursor recenter once the rotation is visually almost done,
	# so the body translation overlaps the rotation's slow asymptotic tail
	# instead of waiting for full settle. Fires at most once per rotation
	# (the flag is reset by _rotate_yaw / _toggle_camera_angle).
	var kickoff_rad := deg_to_rad(rotation_kickoff_remaining_deg)
	if not _translation_kicked_off and max_diff < kickoff_rad:
		_translation_kicked_off = true
		if _has_tracked_tile:
			follow_cursor(_last_tracked_tile)

	if diff_x < ROTATION_SETTLE_THRESHOLD and diff_y < ROTATION_SETTLE_THRESHOLD and diff_z < ROTATION_SETTLE_THRESHOLD:
		rotation_settled = true
		focus_point.global_rotation = target_rot  # Snap to exact target
		# Safety re-fire: if the cursor moved (WASD) between kickoff and settle,
		# _last_tracked_tile updated but our earlier follow_cursor used the old
		# value. Re-fire so the body lands on the latest cursor pos. No-op when
		# nothing changed (follow_cursor lerps from current to same target).
		if _has_tracked_tile:
			follow_cursor(_last_tracked_tile)
		return

	var y_diff = angle_difference(current_rot.y, target_rot.y)
	var new_y = current_rot.y + y_diff * rot_speed * delta

	focus_point.global_rotation = Vector3(
		lerp_angle(current_rot.x, target_rot.x, rot_speed * delta),
		new_y,
		lerp_angle(current_rot.z, target_rot.z, rot_speed * delta)
	)


func _execute_translation():
	# In CURSOR mode the TileCursor handles WASD via _unhandled_input + drives
	# follow via the cursor_moved signal. The legacy direct body-pan only runs
	# while the free-pan debug override is on.
	#
	# The four directions are read off `_pan_held`, which events maintain — not off the
	# [Input] singleton. Four `if`s and up to four `move_and_slide()` calls on purpose: a
	# diagonal is two slides, and collapsing them into one vector would change the speed.
	if not free_camera():
		return

	var camera_transform = focus_point.global_transform
	var camera_forward = -camera_transform.basis.z
	var screen_forward = Vector3(camera_forward.x, 0, camera_forward.z).normalized()
	var screen_right = screen_forward.cross(Vector3.UP).normalized()

	if _pan_held.has(&"camera_up"):
		set_velocity(screen_forward * translation_speed)
		set_up_direction(Vector3.UP)
		move_and_slide()

	if _pan_held.has(&"camera_down"):
		set_velocity(-screen_forward * translation_speed)
		set_up_direction(Vector3.UP)
		move_and_slide()

	if _pan_held.has(&"camera_left"):
		set_velocity(-screen_right * translation_speed)
		set_up_direction(Vector3.UP)
		move_and_slide()

	if _pan_held.has(&"camera_right"):
		set_velocity(screen_right * translation_speed)
		set_up_direction(Vector3.UP)
		move_and_slide()


func _rotate_around_terrain(direction: int):
	var now = Time.get_ticks_msec() / 1000.0

	if now - pivot_lock_time > PIVOT_LOCK_DURATION:
		# Cooldown expired - recalculate pivot
		locked_pivot = _get_terrain_pivot()
		global_position = locked_pivot

	# Reset cooldown and rotate
	pivot_lock_time = now
	y_target_rot = wrapf(y_target_rot + 90 * direction, -180, 180)
	rotation_settled = false  # Start lerping to new target


func _update_pivot_marker():
	"""Update the pivot marker to show where rotation will occur."""
	if not pivot_marker:
		return

	pivot_marker.visible = show_pivot_marker
	if not show_pivot_marker:
		return

	var now = Time.get_ticks_msec() / 1000.0
	if now - pivot_lock_time < PIVOT_LOCK_DURATION:
		# Show locked pivot during cooldown
		pivot_marker.global_position = locked_pivot
	else:
		# Show live raycast pivot
		pivot_marker.global_position = _get_terrain_pivot()


func _get_terrain_pivot() -> Vector3:
	var result = _raycast_screen_center()
	if not result.is_empty():
		return result.position

	var plane_hit = _screen_center_ray_y0_intersection()
	if plane_hit != null:
		var snapped = _nearest_tile_position_to_xz(plane_hit)
		if snapped != null:
			return snapped
		# No tiles available — use the raw plane hit rather than the centroid.
		return plane_hit

	return _get_map_center()


func _nearest_tile_position_to_xz(target: Vector3):
	# Find the tile whose XZ is closest to `target`'s XZ, return its full global_position.
	# Returns null if no tiles are available.
	var tiles := _map_tiles()
	if tiles.is_empty():
		return null

	var tx = target.x
	var tz = target.z
	var best_pos: Vector3 = tiles[0].global_position
	var dx = best_pos.x - tx
	var dz = best_pos.z - tz
	var best_d2 = dx * dx + dz * dz
	for i in range(1, tiles.size()):
		var p: Vector3 = tiles[i].global_position
		dx = p.x - tx
		dz = p.z - tz
		var d2 = dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best_pos = p
	return best_pos


func _screen_center_ray() -> Array:
	# Returns [ray_origin: Vector3, ray_direction: Vector3] or [] if unavailable.
	if not camera:
		return []
	var viewport = get_viewport()
	if not viewport:
		return []
	var screen_center = viewport.get_visible_rect().size / 2.0
	return [camera.project_ray_origin(screen_center), camera.project_ray_normal(screen_center)]


func _raycast_screen_center() -> Dictionary:
	var ray = _screen_center_ray()
	if ray.is_empty():
		return {}

	var ray_origin: Vector3 = ray[0]
	var ray_direction: Vector3 = ray[1]
	var ray_end = ray_origin + ray_direction * 1000.0

	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return {}

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 2  # Layer 2: terrain tiles

	return space_state.intersect_ray(query)


func _screen_center_ray_y0_intersection():
	# Intersect the screen-center ray with the y=0 plane. Returns Vector3 or null.
	var ray = _screen_center_ray()
	if ray.is_empty():
		return null

	var ray_origin: Vector3 = ray[0]
	var ray_direction: Vector3 = ray[1]
	# Parallel to plane (or numerically close): no useful intersection.
	if absf(ray_direction.y) < 0.0001:
		return null
	var t = -ray_origin.y / ray_direction.y
	# Behind the camera: not what we want.
	if t <= 0.0:
		return null
	return ray_origin + ray_direction * t


func _get_map_center() -> Vector3:
	var tiles := _map_tiles()
	if tiles.is_empty():
		return Vector3.ZERO

	var min_pos = tiles[0].global_position
	var max_pos = tiles[0].global_position

	for tile in tiles:
		min_pos = min_pos.min(tile.global_position)
		max_pos = max_pos.max(tile.global_position)

	return (min_pos + max_pos) / 2.0


## Every tile on the map, through the port's addon-internal back door.
##
## 🔴 THIS USED TO BE `procedural_map.get_all_tiles()` BEHIND A `has_method` PROBE,
## and when ADR-0170 dec. 1 deleted that forwarder off `MapComposer` the probe kept
## the call from erroring — it simply started answering "no tiles" forever, which
## centres the camera on the world origin. A silent wrong answer, in an ADDON file,
## which `check_lattice_ports.py` did not scan: its subject excludes
## `addons/exmateria_battlefield/` because the addon owns the store. Arm 3 exists
## because of this line.
##
## Reading the raw nodes rather than `all_cells()` is deliberate: this wants
## `global_position` for every tile, and a cell-plus-`world_position_at` round trip
## would allocate one `TerrainCell` per tile to reach a field the node already has.
## An addon file may open that door; a host file may not.
func _map_tiles() -> Array[Tile]:
	var empty: Array[Tile] = []
	if procedural_map == null or not ("lattice" in procedural_map):
		return empty
	var lat: Lattice = procedural_map.lattice
	return lat._tiles() if lat != null else empty
