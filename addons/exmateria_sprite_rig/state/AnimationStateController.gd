@tool
extends Node

## Controls animation state machine and state-to-animation mappings
## Handles state transitions and camera-relative animation selection
## Animation ID lookups are in StateAnimationDatabase (auto-generated).
## Vault: [[Inflict Status Opcode]]
## Vault: [[Rotate Unit Interpolation]]
## Vault: [[Sprite Cardinal Pose Selection]]
## Vault: [[Unit Anim Opcode]]
## Vault: [[Unit Sprite Render Pipeline]]
## Vault: [[Walk To Opcode]]

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const DisplayActivity = preload("res://addons/exmateria_sprite_rig/state/DisplayActivity.gd")

## Locked State Transitions
##
## Some states have restricted exit transitions. Once a unit enters these states,
## only specific transitions are allowed. This prevents bugs like dead units
## showing IDLE animation.
##
## Format: { locked_state: [allowed_next_states] }
## - DYING can only transition to DEAD
## - DEAD is terminal (no transitions allowed)
const RigDebug = preload("res://addons/exmateria_sprite_rig/install/RigDebug.gd")
const LOCKED_TRANSITIONS = {
	DisplayActivity.Activity.DYING: [DisplayActivity.Activity.DEAD],
	DisplayActivity.Activity.DEAD: [],  # Terminal state - no exit
}

## States that support ability-specific animation overrides
## When in these states with a valid active_ability_id, the animation
## is looked up from AbilityDatabase instead of state_animations.
const ABILITY_OVERRIDE_STATES = [
	DisplayActivity.Activity.SPELL_CHARGING,
	DisplayActivity.Activity.SPELL_CASTING,
]

## Animation State Categories
##
## States are categorized by their lifecycle and ownership:
##
## PERSISTENT STATES - Should never be forcibly overridden by cleanup code
##   - DYING: Death animation playing
##   - DEAD: Corpse state (unit eliminated)
##   - IDLE_LOW_HEALTH: Low HP idle stance (persistent until healed)
##   - GETTING_UP: Revival/resurrection animation
##   Future: STUNNED, POISONED, PARALYZED, PETRIFIED, etc.
##
## TRANSIENT STATES - Temporary states that should return to IDLE when complete
##   Movement: WALKING, JUMPING, LANDING
##   Combat: ATTACKING
##   Abilities: SPELL_CHARGING, SPELL_CASTING
##   Other: USING_ITEM
##
## STATE OWNERSHIP RULE:
##   Systems that set a transient state must check the unit is still in that state
##   before forcing back to IDLE. This respects:
##   - Persistent states (death, status effects)
##   - Interruptions from other systems (damage during movement)
##   - State transitions during async operations
##
##   Use return_to_idle_if_transient() helper to enforce this pattern.

# Animation activity values now live in DisplayActivity (source: tools/activity_taxonomy.yaml).
# Reference them as DisplayActivity.Activity.IDLE / .WALKING / etc.

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the four world cardinals are a VALUE SET,
## not a contract, so they are the kernel's; this class keeps its name and all of
## its behaviour (the snap, the camera-relative resolve, the state machine) and
## names the kernel for its own internal control flow. The local spelling is
## unchanged, so no call site below moves (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction


# Snap a PSX 12-bit angle to a WORLD cardinal FacingDirection using the PSX
# truncate formula `(angle >> 10) & 3`. Sectors are byte-boundary aligned and
# follow the CANONICAL raw-PSX world wheel `0x0=E, 0x4=S, 0x8=W, 0xC=N` (CCW) —
# the SAME wheel `ScenarioPlayerScene.initial_spawn_facing_12bit` (spawn seed),
# `PlayerCamera` yaw, and `Unit.facing_angle_to_world_radians` (the yellow
# arrow) use:
#
#     [0x000, 0x400) → EAST    (truncate 0)
#     [0x400, 0x800) → SOUTH   (truncate 1)
#     [0x800, 0xC00) → WEST    (truncate 2)
#     [0xC00, 0x1000) → NORTH  (truncate 3)
#
# Harmonized 2026-06-30: previously this mapped truncate 0→SOUTH, 1→EAST (an
# E/S swap that conflated the PSX *sprite-pose* index numbering — see
# `CinematicPoseLUT` cardinal_idx `0=S,1=E,…` — with the *world* enum). That
# made `current_facing` disagree with the arrow and made the combat render
# fallback (`Unit._CARDINAL_TO_12BIT`) pick the perpendicular cardinal at E/S.
# The body pose is unaffected either way (it reads `pose_octant >> 2` directly,
# never this enum); only the world-enum consumers (debug label, weapon/react
# `get_camera_variant`, `facing_angle<0` render fallback) were corrected.
#
# `(angle >> 10) & 3` is the formula the PSX sprite renderer (`FUN_8006bbfc` at
# `0x8006bbfc`, see `battle_disassembly.txt:8006bc3c..8006bc40`:
# `srl v0, v0, 0xa; andi v0, v0, 0xff`) feeds to `FUN_8017fddc`. It is a pure
# TRUNCATE, NOT a center-snap — byte 0x3 still maps to EAST, byte 0x7 still
# maps to SOUTH, etc. Prior revisions used center-snap (each cardinal owning
# ±0x200 around its byte anchor), which produced a half-sector offset from PSX
# and a visible sprite-vs-arrow desync mid-rotation (the arrow uses the uniform
# 22.5°/byte wheel). See `HANDOFF_sprite_cardinal_mapping.md` Path A finding.
static func angle_12bit_to_facing(angle_12bit: int) -> FacingDirection:
	var a := ((angle_12bit % 0x1000) + 0x1000) % 0x1000  # wrap to [0, 0x1000)
	match (a >> 10) & 0x3:
		0:
			return FacingDirection.EAST
		1:
			return FacingDirection.SOUTH
		2:
			return FacingDirection.WEST
		_:
			return FacingDirection.NORTH


## Render class (ADR-0057): orientation direction -> raw cardinal BUCKET.
##
## The camera-INDEPENDENT truncate `(angle >> 10) & 3`, numbered `0=E, 1=S,
## 2=W, 3=N` — the value FUN_8006bbfc computes and the ScenarioVM trace records
## as `pose_idx`. It is a *derived view* of the single-truth orientation angle:
## the SAME truncate `angle_12bit_to_facing` uses, in a different numbering (the
## world enum is N=0,E=1,S=2,W=3). Keeping the two numberings distinct — and
## never crossing them — is exactly what retires the E/S-swap category error.
##
## Distinct from the camera-RELATIVE render/atlas cardinal
## (`pose_octant_to_atlas_cardinal`), which composes the live camera in and uses
## the sprite-LUT's own numbering — do not assume the two share a numbering.
##
## THE single home of the inline `(angle >> 10) & 3` truncate — never re-derive
## a cardinal bucket inline; route through this converter.
static func angle_12bit_to_cardinal_bucket(angle_12bit: int) -> int:
	var a := ((angle_12bit % 0x1000) + 0x1000) % 0x1000  # wrap to [0, 0x1000)
	return (a >> 10) & 0x3


## Render class (ADR-0057): pose octant -> sprite-LUT cardinal index.
##
## Reduces the 4-bit camera-COMPOSED pose octant (get_pose_octant, which folds
## the live camera in) to the cardinal index the SEQ-range dispatcher
## (CinematicPoseLUT) uses to pick the sprite's front/back + mirror — indexing
## SUB_E_CARDINAL_OFFSET / SUB_F_CARDINAL_MIRROR in the LUT's transcribed-from-
## ROM numbering (see CinematicPoseLUT). `octant >> 2` is the documented
## invariant of get_pose_octant (cycles 0..3 as facing walks the circle). This
## is the camera-RELATIVE render direction — do not conflate its numbering with
## the camera-independent bucket above. Route every `pose_octant >> 2` here.
static func pose_octant_to_atlas_cardinal(pose_octant: int) -> int:
	return (pose_octant >> 2) & 0x3


# Signals
signal activity_changed(old_state: DisplayActivity.Activity, new_state: DisplayActivity.Activity)
signal facing_direction_changed(old_dir: FacingDirection, new_dir: FacingDirection)

# Current state (exported for editor preview)
@export var current_state: DisplayActivity.Activity = DisplayActivity.Activity.IDLE:
	set(value):
		var old = current_state
		current_state = value
		if old != value:
			activity_changed.emit(old, value)


@export var current_facing: FacingDirection = FacingDirection.NORTH:
	set(value):
		var old = current_facing
		current_facing = value
		if old != value:
			facing_direction_changed.emit(old, value)

func set_state(new_state: DisplayActivity.Activity) -> bool:
	"""Change animation state with transition validation.

	Returns true if transition was accepted, false if rejected due to locked state.
	"""
	# Check if current state has locked transitions
	if current_state in LOCKED_TRANSITIONS:
		var allowed = LOCKED_TRANSITIONS[current_state]
		if new_state not in allowed:
			# Reject transition - current state is locked
			if RigDebug.transition():
				print("[DisplayActivity.Activity] REJECTED: %s → %s (locked)" % [
					DisplayActivity.Activity.keys()[current_state],
					DisplayActivity.Activity.keys()[new_state]
				])
			return false

	current_state = new_state  # Setter handles signal emission
	return true

func rise_from_dead() -> void:
	"""Set activity to GETTING_UP, bypassing the DYING/DEAD lock.

	Used by Raise / Phoenix Down / Reraise (#108): the effect file's
	ABILITY_REACT keyframe fires mid-cinematic while the target is still
	FLAG_DEAD (HP isn't restored until first_hit_frame). The carrier stands
	up on the GETTING_UP SEQ (TYPE1 slot 1 — distinct from IDLE 6/7 and
	DYING 52/53). The eventual stat revive -> IDLE transition lands later
	via _handle_revives on first_hit_frame.
	"""
	current_state = DisplayActivity.Activity.GETTING_UP


func to_critical_idle() -> void:
	"""Force the activity to IDLE_LOW_HEALTH (the near-death kneel stance).

	The faithful analog of {92} Inflict Status SS=2's Critical branch, which on
	PSX forces the unit's Critical pose directly (anim 0x16 via
	BATTLE_set_unit_anim_value) — see inflict_status_op92_decode.md §11.2. Unlike
	the HP-driven auto-pick in Unit.update_animation, this forces the low-health
	idle explicitly (the resolver dispatches A.IDLE_LOW_HEALTH straight to the
	kneel, HP-agnostic), so a static cutscene unit holds the pose without a
	fabricated HP drop. The bare property assignment fires activity_changed, which
	routes the re-resolve through Unit.update_animation.
	"""
	current_state = DisplayActivity.Activity.IDLE_LOW_HEALTH


func revive_to_idle() -> void:
	"""Force the activity back to IDLE, bypassing the DYING/DEAD lock.

	The LOCKED_TRANSITIONS table treats DYING/DEAD as terminal so that
	cleanup code can't accidentally pop a corpse back to its idle pose.
	Reraise and Phoenix Down are the intentional exit: callers go through
	this helper to make the bypass explicit. The bare property assignment
	skips set_state's lock check while still firing activity_changed,
	which routes the IDLE re-resolve through Unit.update_animation.
	"""
	current_state = DisplayActivity.Activity.IDLE


func set_facing(new_facing: FacingDirection) -> void:
	"""Change facing direction"""
	current_facing = new_facing  # Setter handles signal emission

func return_to_idle_if_transient(expected_states: Variant) -> bool:
	"""Return to IDLE only if current state matches expected transient state(s)

	This helper enforces the STATE OWNERSHIP RULE: systems that temporarily
	change animation state must check the unit is still in that state before
	forcing back to IDLE.

	Use this instead of unconditional `set_state(IDLE)` to respect:
	- Persistent states (DYING, DEAD, status effects)
	- Interruptions from other systems (damage during movement)
	- State transitions during async operations

	Args:
		expected_states: DisplayActivity.Activity or Array[DisplayActivity.Activity] to check against

	Returns:
		true if state was changed to IDLE, false if state was preserved

	Example:
		# Combat system sets ATTACKING, then checks before cleanup:
		if anim_state.return_to_idle_if_transient(DisplayActivity.Activity.ATTACKING):
			print("Returned to IDLE")
		else:
			print("State preserved (unit died, interrupted, etc.)")

		# Movement system checks multiple states:
		anim_state.return_to_idle_if_transient([DisplayActivity.Activity.WALKING, DisplayActivity.Activity.JUMPING])
	"""
	var states_to_check = expected_states if expected_states is Array else [expected_states]

	if current_state in states_to_check:
		set_state(DisplayActivity.Activity.IDLE)
		return true

	return false

## Baseline quadrant offset that aligns a literal-world FacingDirection
## (NORTH=+X, etc.) with the on-screen sprite orientation. Calibrated visually
## via tests/UnitOrientationTest: with this value, a unit whose facing_direction
## is set to a world cardinal renders facing that same world cardinal, and stays
## world-locked as the camera rotates through all four quadrants.
const CAMERA_BASELINE_QUAD := 2

static func _calculate_camera_relative_direction(face_dir: FacingDirection, camera_quad: int) -> int:
	"""Calculate camera-relative direction from world direction

	Rotates the unit's world-space facing into the camera's frame so the
	correct front/back/flip sprite is chosen for the current view.

	Args:
		face_dir: Unit's world-space facing direction
		camera_quad: Current camera quadrant (0-3)

	Returns:
		Rotated direction index (0-3) relative to camera view
	"""
	var quad_diff = (CAMERA_BASELINE_QUAD - camera_quad + 4) % 4
	return (face_dir + quad_diff) % 4


## Baseline PSX camera angle at which the pose-octant composition reduces
## to facing_angle alone (i.e. camera contribution = 0). 0x400 = 90°, the
## start of the legacy CAMERA_BASELINE_QUAD=2 bucket. With this constant,
## the formula reproduces the OLD cardinal-quad behavior at cardinal yaws
## and extends continuously between them — the PSX-faithful behavior the
## map polygon cull already relies on.
const POSE_OCTANT_CAMERA_BASELINE_12BIT := 0x400


## Compute the 4-bit pose_octant the idle dispatcher uses to index
## CinematicPoseLUT.SUB_A_FRAME_BASE / SUB_B_MIRROR (ADR-0053).
##
## Returns 0..15 from the precise 12-bit facing_angle composed with the
## raw PSX camera angle — the SAME continuous angle the polygon-cull
## shader (`fft_visible_angles.gdshaderinc`) consumes via the global
## `psx_camera_angle` uniform. PSX-faithful formula:
##
##     composed     = (facing_angle + psx_camera_angle - 0x400) & 0xfff
##     pose_octant  = composed >> 8
##
## The -0x400 baseline reproduces the OLD CAMERA_BASELINE_QUAD=2 cardinal
## calibration at cardinal yaws (where psx=0x400 / 0x800 / 0xC00 / 0x000)
## while smoothly tracking the camera between cardinals. In ADR-0057 terms:
## both the polygon cull and the pose octant are Render directions derived from
## ONE orientation direction (the raw facing angle) composed with the live
## camera — so they now share a single angle convention instead of the two
## disagreeing cardinal numberings this once carried.
##
## Invariant: `get_pose_octant(...) >> 2` cycles through 0..3 as
## facing_angle walks the full circle — the cardinal_idx the SEQ-range
## dispatcher will use. Exact PSX-pose-octant calibration (which octant
## means "directly facing camera") is a chapel-verification step; the
## structural properties asserted in tests/GetPoseOctantTest.gd are what
## make the LUT-driven idle path PSX-faithful regardless of the baseline
## offset.
## 🔴 The second parameter is spelled `camera_angle_12bit`, not
## `psx_camera_angle_12bit` (goal #7, ADR-0234). Both call sites pass positionally,
## so this is a rename of a name and not of a signature.
static func get_pose_octant(facing_angle_12bit: int, camera_angle_12bit: int) -> int:
	var camera_offset_12bit := camera_angle_12bit - POSE_OCTANT_CAMERA_BASELINE_12BIT
	# Live calibration knob — F3 Scenario panel. See
	# RigDebug.pose_octant_offset_12bit().
	camera_offset_12bit += RigDebug.pose_octant_offset_12bit()
	var composed := facing_angle_12bit + camera_offset_12bit
	# Wrap to [0, 0x1000) — GDScript `%` keeps the sign of the dividend.
	composed = ((composed % 0x1000) + 0x1000) % 0x1000
	return (composed >> 8) & 0xf


static func get_camera_variant(face_dir: FacingDirection, camera_quad: int) -> Dictionary:
	"""Compute the camera-relative render variant for the unit.

	Returns the {use_back, revert} pair (see CONTEXT.md "Sprite variants" →
	"Camera variant"): which authored sprite to show (front vs back) and
	whether to horizontally mirror the whole sprite.

	Args:
		face_dir: Unit's world-space facing direction
		camera_quad: Current camera quadrant (0-3)

	Returns:
		Dictionary with "use_back" (bool) and "revert" (bool)
	"""
	var rotated_dir = _calculate_camera_relative_direction(face_dir, camera_quad)
	return {
		"use_back": (rotated_dir == 1 or rotated_dir == 2),
		"revert": (rotated_dir >= 2)
	}


# get_state_anim_pair + _get_ability_animation_pair retired with ADR-0021's
# resolver migration (task 24). All parameterless activity routing now goes
# through AnimationResolutionMap.resolve_for_activity, which reads map.tres
# (Inspector-edited Resource). Ability-driven casts/charges go through
# Unit.cast_spell / Unit.charge_ability (ADR-0024).


