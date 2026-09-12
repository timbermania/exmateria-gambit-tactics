@tool
class_name Unit
extends Node3D

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const CrystalSprite3D = ExMateriaSpriteRig.CrystalSprite3D
const UnitDisplay = ExMateriaSpriteRig.UnitDisplay
const CameraRelativeRenderer = ExMateriaSpriteRig.CameraRelativeRenderer
const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver
const WeaponAnimationSelector = ExMateriaSpriteRig.WeaponAnimationSelector
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager
const AnimationResolutionMap = ExMateriaSpriteRig.AnimationResolutionMap
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity
const UnitAnimationSet = ExMateriaSpriteRig.UnitAnimationSet
const AnimationDatabase = ExMateriaSpriteRig.AnimationDatabase
const AnimationPlayback = ExMateriaSpriteRig.AnimationPlayback
const AnimationFrameCalculator = ExMateriaSpriteRig.AnimationFrameCalculator

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice


# Preload database classes (needed for static function access)
const SpriteDatabaseClass = ExMateriaAlmanac.SpriteDatabase
const UnitShadowClass = preload("res://src/units/UnitShadow.gd")
const UnitProgressionClass = ExMateriaAlmanac.UnitProgression
const DistortMovementControllerClass = ExMateriaSpriteRig.DistortMovementController
const DepthModeScript = ExMateriaSchema.DepthMode

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const DepthMode = ExMateriaSchema.DepthMode
const TerrainCell = ExMateriaSchema.TerrainCell

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const GambitList = ExMateriaAlmanac.GambitList
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const ReactionType = ExMateriaAlmanac.ReactionType
const UnitProgression = ExMateriaAlmanac.UnitProgression
const UnitRole = ExMateriaSchema.UnitRole
const WeaponGraphicData = ExMateriaAlmanac.WeaponGraphicData

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction
const ClockOwner = ExMateriaSchema.ClockOwner.Kind

# Signals for animation completion
signal activity_complete(state: DisplayActivity.Activity)    # State-based logic
signal animation_paused(animation_id: String)  # Emitted when PauseAnimation opcode executes

# Proxied from UnitProgression so UI can connect to Unit directly
signal stats_changed()

# Emitted when a reaction animation plays (for test verification)
signal reaction_animation_played(reaction_type: int)

## Re-emitted from the normal BODY playback (issue #144 C3a facade). The
## PlaybackSet cascade + painters live on `display`; Unit forwards the two
## BODY-clock events CombatLoop consumes for gameplay — `body_paused` clears the
## spell-cast-active flag (PauseAnimation ends a cast), `body_side_effect` carries
## POST_GENERIC_ATTACK (trap spawn + physical reaction). Consumers name `Unit`,
## never `display`; the display cascade listens to the same BODY signals internally.
signal body_paused()
signal body_side_effect(effect_type: int, params: Dictionary)

# Sprite ID - determines SEQ/SHP type and texture
# See SpriteDatabase for ID mappings (0x01=Ramza, 0x86=Chocobo, etc.)
# Post sprite-extract refactor (3da98be4) the ROM-faithful mapping starts at
# 0x01; 0x00 doesn't resolve, so the default falls on the first valid sprite.
@export var body_sprite_id: int = 0x01:
	set(value):
		var old_id = body_sprite_id
		body_sprite_id = value
		if DebugConfig.iteration_debug_enabled:
			print("[Unit] body_sprite_id setter: 0x%02X -> 0x%02X (initialized=%s)" % [old_id, value, str(_initialized)])
		if _initialized and old_id != value:
			_on_sprite_changed()

# ADR-0022: per-unit BODY palette row. 0-15 selects which row of the per-sprite
# palette table the BODY shader looks up at runtime. Default 0 for humanoids
# (their default palette baked into the SPR is row 0). For monster jobs, set
# from jobs.json's body_palette_row — e.g. Yellow Chocobo=0, Black=1, Red=2.
@export var body_palette_row: int = 0:
	set(value):
		body_palette_row = value
		if sprite_layers:
			sprite_layers.set_body_palette_row(value)

# ADR-0072 #203: the resolved template folder for a UNIQUE unit, or "" for a
# job-routed generic. When set, the BODY loader reads the unit's OWNED body sheet
# from this folder (the moddable read surface); when "" (or the folder holds no
# body.tga) it degrades to the flat `textures/NN.tga` store — the fallback is
# load-bearing (folders are generated + gitignored, #200). Populated from
# CharacterTemplateResolver at the spawn seam (UnitSpawn.build).
var template_folder: String = ""

# Scenario/cutscene team colour (ENTD flags2 bits 5..4: 0=Blue/player, 1=Red,
# 2=Green, 3=LightBlue). Plumbed by ScenarioPlayerScene at spawn so the event
# multi-unit broadcast selector ({2D}/{11}/{32}/{53}/{69} Units|Multi) can resolve
# team-set targets — the ROM reads the same field as structB[+0x5]&0x30 (which is
# team_color<<4). 0 for ghost / EVTCHR-fallback spawns. See ScenarioDecode.unit_set_*
# and EVENT_UNIT_SET_RESOLUTION.md. Unused by combat (that path has UnitStats.team).
var scenario_team_color: int = 0

# Scenario broadcast-roster PRESENCE — is this unit allocated in the (PSX) sprite
# list, INDEPENDENT of render visibility (`+0xa` / `visible`). Team-broadcast
# opcodes ({2D} Rotate / {11} Anim / {32} Color with Multi!=0) target PRESENT
# units, so a held-but-allocated principal (ENTD `always_present`, awaiting its
# {44} Draw) is a valid target while still hidden — e.g. scn6 Ovelia at the pc31
# player-team rotate. Set true at spawn for always_present units, and when
# {45} Add / {44} Draw / {47} introduces a unit. NOT the same as `visible`.
# See ScenarioWorld._unit_roster. (Provisional pending PSX confirmation — handoff
# /tmp/handoff_scn6_ovelia_pc31_broadcast_rotate_psx_capture.md.)
var scenario_present: bool = false

# Animation data resource
var animation_set: UnitAnimationSet

# Movement component (Phase 2 - Per-unit movement)
@onready var movement_component: MovementComponent = $MovementComponent

# Unit stats component (combat + movement stats)
@onready var unit_stats: UnitStats = $UnitStats

# Unit progression component (optional - FFT-style stats)
var unit_progression: Resource = null  # UnitProgression (a Resource shared with the roster entry; bound or minted)

# Sprite layer manager (Phase 3 - Refactored)
@onready var sprite_layers: SpriteLayerManager = $SpriteLayerManager

# Animation state controller (Phase 4 - Refactored)
@onready var anim_state: AnimationStateController = $AnimationStateController

# Camera-relative renderer (Phase 5 - Refactored)
@onready var camera_renderer: CameraRelativeRenderer = $CameraRelativeRenderer

# Equipped abilities (Phase 8 - Ability system)
@onready var equipped_abilities: EquippedAbilities = $EquippedAbilities

# Status manager component (Phase 9 - Status system refactoring)
@onready var unit_status: UnitStatusManager = $UnitStatusManager

# Gambit list (AI behavior configuration)
var gambit_list: GambitList = null

# Active ability ID for ability-specific animation lookup
# Set when casting begins, cleared when complete
# Used by AnimationStateController to select ability-specific SEQ slots
var active_ability_id: int = -1

# Debug: Current action being attempted (for Unit Inspector)
var debug_current_action: String = ""

# Debug: Rich action context for Unit Inspector
# Contains: gambit_triggered, goal_name, target, action_type, failure_reason
var debug_action_context: Dictionary = {}

# Dynamic shadow components
@onready var shadow_mesh: MeshInstance3D = $ShadowMesh
@onready var shadow_raycast: RayCast3D = $ShadowRaycast

# The per-unit render module (issue #144): owns the animation clock, both
# PlaybackSets, the body/secondary painters, the React cascade + countdown, and
# `current_anim_id`. Unit is the sole facade — consumers never name it. Created
# in `_init` so even a bare `Unit.new()` (no `_ready`) can drive `current_anim_id`.
# See `addons/exmateria_sprite_rig/render/UnitDisplay.gd` + CONTEXT.md "Animation playback".
var display: UnitDisplay

## True while the React PlaybackSet owns the body layer (issue #144 facade,
## read-only). The React window is owned by `display`; consumers (CombatLoop's
## REFRESH_TILE guard, EffectViewerScene, CinematicDebugProbe) read it here so
## they never name `display`. C3a retired the `_react_active` forwarding field.
var is_reacting: bool:
	get: return display._react_active if display else false

## COMMANDABLE (`docs/context/41-battle-mode-and-handback.md`): does this unit take the
## player's orders at all? A plain field on the UNIT, because that is what the fact is
## about — not a set held beside the battle, which is provenance ("how did it get here")
## wearing the name of ownership ("whose is it").
##
## TWO WRITERS, ONE FACT. A predetermined cast is written from its ENTD slot's control flag
## (`BattleDeployment.slot_is_commandable`); a roster-fed one is written by deployment. Both
## write it unconditionally at the same seam a unit is made combat-ready, so it can never be
## stale from a previous battle. Nobody derives it — deriving it from a deployment array is
## what left the one predetermined battle in the game unplayable (ADR-0265 Amendment 1).
##
## Default FALSE: a unit nobody has claimed is not yours. Distinct from Steerable, which
## asks whether THIS selection may be edited right now and takes this as one of its terms.
var commandable: bool = false

## Which pump owns this unit's animation clock (ADR-0083): SELF (delta / `_process`),
## SCENARIO (the ScenarioVM body pump), or COMBAT (the CombatLoop tick). Exactly one
## owner, so a unit can never ride both clocks. Facade over `display.anim_clock.owner`
## so GPU hosts / the scenario VM / test bases name their host without naming `display`.
## Getter reports SELF until `display` exists (bare `Unit.new()` in test harnesses);
## setter is a no-op until then, matching the old `tick_based` setter's guard.
var clock_owner: ClockOwner:
	get: return display.anim_clock.owner if display else ClockOwner.SELF
	set(value):
		if display:
			display.anim_clock.owner = value

## Host-pumped vs delta-pumped — the derived predicate `clock_owner != SELF`
## (ADR-0083). Read-only facade over `display.anim_clock.tick_based`; assign
## `clock_owner` to name the host. `Unit._process` reads it to no-op its delta pump
## when a host owns the clock.
var tick_based: bool:
	get: return display.anim_clock.tick_based if display else false

## Melee react duration in ticks. `UnitDisplay` owns the value + the countdown
## (folded into `display.advance_frame` in C3a); this alias exists only because
## GPUReactDurationTest asserts against `Unit.REACT_DURATION_TICKS`.
const REACT_DURATION_TICKS: int = UnitDisplay.REACT_DURATION_TICKS

# Per-unit render tunables (ADR-0068 R1–R8). Split cleanly: each slug is REGISTERED
# once at boot by _static_init (the pure `bind` — literal + affordance hint, the owner of
# the value, R2), and each spawned unit adds an owner-scoped `update` that lands the
# coalesced value on its OWN mesh/material (the per-instance apply, R3). Registration at
# boot — not per-spawn — is what lets the generated dashboard enumerate these knobs in
# EVERY scene before any unit exists, with no panel fan-out (decision 12). The mesh-scale /
# Y-lift literals MIRROR the Unit.tscn UnitMesh transform (scale 8, y 0.05) — keep them in
# sync. loc_offset's home is SpriteLayerManager.shared_loc_offset (a static var, R1); it is
# ONE Vector2 slug (the old x/y pair collapsed, R6) so there is a single typed literal.
const _MESH_SCALE_SLUG := "render.unit_mesh_scale"
const _Y_LIFT_SLUG := "render.unit_y_lift"
const _LOC_OFFSET_SLUG := "render.loc_offset"
const _OT_FORWARD_SLUG := "render.ot_unit_forward"


## Register the per-unit render tunables ONCE at class load (ADR-0068 R2): `bind` is the
## pure literal + hint — no owner, no apply. Boot-time so the generated dashboard can
## enumerate them before any unit spawns. Editor-guarded: Unit is @tool and Tune is a
## non-@tool placeholder in the editor that cannot be called (the old _bind_visual guard).
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## The render.* binds, split out from _static_init as this owner's named registration entry
## point (ADR-0173): _static_init calls it at class load — the ONLY thing that does, now that
## the central replay is gone — and the guards call it to read back which slugs this owner
## binds, as data rather than as a hardcoded list. Editor-guarded by the caller.
static func register_tunables() -> void:
	Tune.bind(_MESH_SCALE_SLUG, 8.0, {"min": 1.0, "max": 20.0, "step": 0.1})
	Tune.bind(_Y_LIFT_SLUG, 0.0, {"min": -2.0, "max": 2.0, "step": 0.01})
	Tune.bind(_LOC_OFFSET_SLUG, SpriteLayerManager.shared_loc_offset,
		{"min": -128.0, "max": 128.0, "step": 1.0})
	# ⚠️ NOT LIKE shared_loc_offset ABOVE, AND THE CLAIM THAT IT WAS COST A DIAL. This line
	# used to say the materialize follower resolves DepthMode.UNIT_FORWARD to its static var.
	# It cannot. `SpriteLayerManager` is a `class_name`, so that one is the follower's
	# documented `Class.static_var` case, one hop. `DepthMode` is NOT a class_name — it is a
	# local alias (`const DepthMode = ExMateriaSchema.DepthMode`, line 37) for a façade const
	# that is itself a `preload`, so reaching the static var is THREE hops through two files.
	# R6 is deliberately one hop, which is what keeps the codemod unable to inline a literal
	# over a const. So `render.ot_unit_forward` self-skips with "non-literal default
	# (DepthMode.UNIT_FORWARD) — by hand", and every dial on it is hand-work until either the
	# follower learns alias chains or this home moves to a class_name owner.
	Tune.bind(_OT_FORWARD_SLUG, DepthMode.UNIT_FORWARD,
		{"min": 0.0, "max": 2.0, "step": 0.01})

# Distort movement (QueueDistortAnim - Dash, etc.)
var distort_offset: Vector3 = Vector3.ZERO
var _distort_controller = null  # DistortMovementController
var _distort_home_pos: Vector3 = Vector3.ZERO
var _distort_target_pos: Vector3 = Vector3.ZERO

# Base shared_loc_offset from material (captured at init, before move opcodes modify it)
var _base_loc_offset: Vector2 = Vector2.ZERO

# NOTE: the WEP1 render caches (weapon/shield frame offset, v_offset, palette row),
# the transient `_wep1_showing_shield` flag, and `_eff1_frame_offset` are all
# display-only render state — they live on `UnitDisplay`. C3b pushed the equip
# caches across the seam: `update_weapon_sprite`/`update_shield_sprite` compute
# them from the ROM tables and hand them to `display.set_weapon`/`set_shield`, so
# the painter reads its own copies instead of reaching back into Unit.

# Note: Combat signals (hp_changed, died, action_completed) are now handled
# through EventBus for cross-system communication. See EventBus singleton.

# Property accessors for unit stats (read-only)
var move: int:
	get: return unit_stats.move_range
var jump: float:
	get: return unit_stats.jump_height
var speed: float:
	get: return unit_stats.movement_speed
var team: UnitStats.Team:
	get: return unit_stats.team
var is_dead: bool:
	get:
		# Prefer status manager when available (Phase 9 - Status system)
		if unit_status:
			return unit_status.is_dead()
		return unit_stats.is_dead
var atb_speed: int:
	get: return unit_stats.atb_speed
var current_hp: int:
	get: return unit_stats.current_hp
var max_hp: int:
	get: return unit_stats.max_hp
var current_mp: int:
	get: return unit_stats.current_mp
var max_mp: int:
	get: return unit_stats.max_mp
var magic_attack: int:
	get: return unit_stats.magic_attack
var magic_defense: int:
	get: return unit_stats.magic_defense

# Animation state (delegated to AnimationStateController)
var activity: DisplayActivity.Activity:
	get:
		return anim_state.current_state if anim_state else DisplayActivity.Activity.IDLE
	set(value):
		if anim_state:
			anim_state.set_state(value)


var facing_direction: FacingDirection:
	get:
		# Derived view of the orientation source of truth (ADR-0057 Stage 2). With a
		# precise angle on file, derive the cardinal from `facing_angle`; else fall
		# back to the anim_state cache (a never-faced unit sitting at its default).
		if facing_angle >= 0:
			return AnimationStateController.angle_12bit_to_facing(facing_angle)
		return anim_state.current_facing if anim_state else FacingDirection.NORTH
	set(value):
		# Combat's source datum IS a cardinal — forward-convert it to the 12-bit
		# orientation angle (the single source of truth) and write THAT, so a combat
		# facing write can't leave `facing_angle` stale (the two stores stay locked).
		# This is a legitimate forward converter, not ADR-0057's forbidden backward
		# arrow: the cardinal is the input here, not a render view of a finer heading.
		var v := int(value)
		if v >= 0 and v < _CARDINAL_TO_12BIT.size():
			_write_facing_angle(_CARDINAL_TO_12BIT[v])
		elif anim_state:
			anim_state.set_facing(value)

## Precise facing angle in PSX 12-bit space (`0x000`=S, `0x400`=E, `0x800`=W,
## `0xC00`=N — see `event_unit_anim_decode.md` § "Rotate Unit decoded"). Set
## by `scenario_rotate` so the original target angle survives the cardinal
## snap done for sprite rendering — intermediate angles (e.g. `0x200`) are
## valuable to ScenarioVM's per-opcode trace and the per-tick interpolation
## driven by `_rotate_state`.
##
## `-1` is the sentinel for "no precise angle on file; fall back to the
## cardinal facing." Combat / gameplay code paths never set this; only the
## scenario VM does. Reset to `-1` if you want to drop back to cardinal-only
## semantics for a unit.
##
## NOTE (ADR-0057 Stage 2 in progress): the combat-vs-cinematic *render mode* has
## been split off this sentinel into `is_cinematic_unit` — read that flag for mode
## decisions, not `facing_angle >= 0`. `facing_angle == -1` will be retired once every
## unit carries an always-valid angle (Slice B).
var facing_angle: int = -1

## Render-mode flag: true for scenario/VM (cutscene) units, false for combat/gameplay
## units. Decouples the combat-vs-cinematic idle-pose choice (the pose-octant "at-ease"
## tent vs the real standing idle SEQ) from the `facing_angle == -1` sentinel, so
## `facing_angle` can become an always-valid single source of truth (ADR-0057) without
## flipping combat units into the cinematic tent. Set true by the scenario facing verbs
## (`scenario_set_facing`, `scenario_rotate`) and the ScenarioPlayer spawn seeds; stays
## false for combat units, which face via the plain `facing_direction` setter.
var is_cinematic_unit: bool = false

## Active per-tick rotation state for `scenario_rotate`. When non-null the
## scenario VM (or any host driving `_tick_rotate`) advances `facing_angle`
## one 16-direction step at a time, matching the FFT per-vsync consumer
## `FUN_8013f20c` decoded at `event_unit_anim_decode.md` § "Rotate Unit
## (0x2D) decoded" + `HANDOFF_rotation_interpolation.md`. Cleared to null on
## target-reached.
var _rotate_state: Dictionary = {}

## Emitted whenever `facing_angle` is written (either by an instant
## `scenario_rotate` snap or a per-tick step). Carries the new 12-bit
## value; subscribers can derive cardinal or precise rotation. Fires once
## per rotation step so trace tools / debug arrows see sub-cardinal
## resolution as the cascade plays out.
signal facing_angle_changed(new_angle_12bit: int)


## The single FFT anim-id field driving the body layer's renderer dispatch
## (ADR-0053). Mirrors PSX `unit+0x0c`. Two drivers, one renderer:
## `CombatLoop._update_unit_animation` sets it from the activity resolver;
## `ScenarioVM._op_unit_anim` sets the event-script opcode-0x11 value
## directly. Both go through `play_body`. The renderer in
## `_paint_body_variant` dispatches on the value range:
##   * `0`         → idle (Sub-tables A+B, pose-octant precision)
##   * `1..0x1f3`  → SEQ-range (Sub-tables E+F, cardinal precision)
##   * `>= 0x1f4`  → EVTCHR cinematic (mid + high bands; walker-driven)
##
## `play_body` re-arms the playback clock (`_arm_anim_id_clock`, mirrors PSX
## `FUN_80084818`); same-value writes are idempotent so paint-time pose
## resampling doesn't restart the clock.
##
## Owned by `display`; this property is a **read-only** forward of the getter
## (issue #152). The write half retired now that every driver (ScenarioVM,
## ScenarioWorld, `update_animation`, tests) funnels through `play_body` — the
## single seam that re-arms the clock + repopulates
## `current_animation_front`/`index`. Callers still read `unit.current_anim_id`
## freely; to set the body anim-id call `unit.play_body(anim_id)`.
var current_anim_id: int:
	get: return display.current_anim_id if display else 0


## Play a body animation (issue #144 facade over `display.play_body`). The single
## funnel that sets the body anim-id + re-arms the playback clock; production
## drivers (ScenarioVM, `update_animation`) call this rather than assigning the
## `current_anim_id` property so the funnel is explicit.
func play_body(anim_id: int) -> void:
	if display:
		display.play_body(anim_id)

## FFT `DAT_80169750` Speed-to-frames-per-step lookup (verified live in
## PCSX 2026-06-26 at real RAM 0x80169750 = `[4,2,1,0]`). Index by the
## opcode's `Speed` byte; the returned value is the per-tick counter
## threshold (the consumer fires a step once counter >= value).
const _ROTATE_SPEED_TABLE := [4, 2, 1, 0]

## Cardinal (FacingDirection enum: N,E,S,W) → raw-PSX WORLD 12-bit angle, on the
## CANONICAL wheel `0x000=E 0x400=S 0x800=W 0xC00=N`. This is the SINGLE facing
## convention (harmonized 2026-06-30): it is the inverse of
## `AnimationStateController.angle_12bit_to_facing` and matches the chapel
## spawn seed `ScenarioPlayerScene.initial_spawn_facing_12bit`, the camera yaw, and the
## yellow arrow. Serves BOTH the `scenario_rotate` stepper seed AND the
## pose-octant render fallback (combat units have `facing_angle == -1`). Local
## copy to keep `scenario_rotate` independent of ScenarioVM at parse time
## (avoids the cross-script load order for headless test runs that instantiate
## Unit without a VM).
const _CARDINAL_TO_12BIT := [0xC00, 0x000, 0x400, 0x800]  # NORTH, EAST, SOUTH, WEST


var current_animation_index: String = "0"
# Back-compat readout of the current body anim id — populated by
# `UnitDisplay.play_body` as `str(current_anim_id)`. Path-D (ADR-0053) derives
# the actual front/back SEQ slot + flip from `current_anim_id` at paint time
# (`_paint_body_variant`), so this is a viewer/test readout, not a render driver.
var current_animation_front: String = ""
var previous_activity: DisplayActivity.Activity = DisplayActivity.Activity.IDLE  # Track previous state for seamless transitions

var mesh_instance: MeshInstance3D
var material: ShaderMaterial

# Debug marker showing the computed OT depth-sample center (ADR-0009 tuning)
var _depth_center_marker: MeshInstance3D = null

# Track if initialization completed successfully (for @tool editor support)
var _initialized: bool = false

# Debug: Track original name to detect unexpected renames
var _original_name: String = ""

# Shadow renderer (extracted from Unit.gd - Phase 3 refactoring)
var _shadow  # UnitShadowClass instance

func _init() -> void:
	# Create the render module up front (issue #144) so even a bare `Unit.new()`
	# (no `_ready` — UnitCurrentAnimIdTest / UnitScenarioRotateTest) can drive
	# `current_anim_id` through the forwarding property. `display` owns the six
	# playbacks / two sets / clock; Unit reaches them via `display.type1_playback`
	# etc. (C3a retired the Unit-side mirror fields).
	display = UnitDisplay.new(self)


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("units")

	_initialize_mesh_and_rendering()
	if not _initialize_animation_set():
		push_warning("[Unit] Animation data failed to load - animations disabled")
		return
	_validate_components()
	_initialize_playback()  # New: Initialize AnimationPlayback instances
	_wire_component_signals()
	if not _initialize_materials():
		push_warning("[Unit] Materials failed to initialize - animations disabled")
		return

	_initialized = true

	# Store original name for debugging unexpected renames
	_original_name = name

	# Load correct sprite texture based on body_sprite_id
	# This handles the case where body_sprite_id was set before add_child()
	_load_initial_sprite_texture()

	# Seed the display's view before the first paint (C2b) so update_animation's
	# initial repaint reads the real facing + camera, not the _view defaults.
	display.set_view(_build_view())

	# Initialize animation with state-based system
	update_animation()


func _notification(what: int) -> void:
	"""Detect unexpected name changes for debugging.

	The 'Node3D ####' pattern suggests either the Unit is being freed
	and replaced, or something is clearing/resetting the name property.
	"""
	if what == NOTIFICATION_PATH_RENAMED:
		if _original_name != "" and name != _original_name:
			push_error("[UNIT NAME BUG] '%s' renamed to '%s'" % [_original_name, name])
			print_stack()


func _initialize_playback() -> void:
	"""Wire the distort movement controller into the BODY playback.

	The six playbacks / two PlaybackSets / clock are created by `display`
	(`UnitDisplay`) in `_init`; here we only attach the distort controller to the
	normal-set BODY (react SEQs don't carry QueueDistortAnim opcodes). Distort is
	a unit-position concern that stays on Unit (`_on_distort_requested` etc.).
	"""
	_distort_controller = DistortMovementControllerClass.new()
	display.type1_playback.distort_controller = _distort_controller

## Wire this unit's live apply for a render tunable (ADR-0068 R3): in game, subscribe an
## owner-scoped `update` to `slug` (registered at boot by _static_init) so a scrub reaches
## this unit's mesh/material now and on every change, until it leaves the tree — this is
## what makes the alignment knobs live in EVERY scene, owned by shared Unit code, not
## fanned out by one scene's panel (decision 12). In the @tool editor Tune is an uncallable
## placeholder, so apply `editor_fallback` once and skip. This helper is NOT a materialize
## target: the literal home is _static_init's bind (or the static var), never a forwarded
## param — the wrapper hazard the old _bind_visual introduced (M5) is gone.
func _apply_render_tunable(slug: String, editor_fallback: Variant, apply: Callable) -> void:
	if Engine.is_editor_hint():
		apply.call(editor_fallback)
		return
	Tune.on_update(self, slug, apply)

func _initialize_mesh_and_rendering() -> void:
	"""Initialize mesh instance and camera renderer"""
	self.mesh_instance = get_node("UnitMesh")

	# Duplicate the mesh to prevent sharing between unit instances
	# IMPORTANT: Without this, all units share the same mesh and material
	self.mesh_instance.mesh = self.mesh_instance.mesh.duplicate()

	# The UnitMesh basis scale + Y-lift were pure Unit.tscn scene data with no override
	# seam; a per-unit `update` lands the coalesced value on this mesh so the alignment
	# rig can scrub/pin them live in any scene (ADR-0068 R3). The slugs are registered at
	# boot by _static_init; the editor fallbacks MIRROR the .tscn transform (scale 8,
	# y 0.05) — keep them in sync or you reintroduce two homes.
	_apply_render_tunable(_MESH_SCALE_SLUG, 8.0, func(v: float) -> void:
		self.mesh_instance.scale = Vector3.ONE * v)
	_apply_render_tunable(_Y_LIFT_SLUG, 0.05, func(v: float) -> void:
		self.mesh_instance.position.y = v)

	# Initialize camera renderer
	if camera_renderer:
		camera_renderer.camera = get_viewport().get_camera_3d()

	# Initialize shadow renderer (Phase 3 - extracted shadow logic)
	_shadow = UnitShadowClass.new()
	_shadow.initialize(shadow_mesh, shadow_raycast, camera_renderer)

func _initialize_animation_set() -> bool:
	"""Resolve the unit's UnitAnimationSet from AnimationDatabase. Returns true on success."""
	# Get sprite type from SpriteDatabase
	var seq_type = SpriteDatabaseClass.get_seq_type(body_sprite_id)
	var shp_type = SpriteDatabaseClass.get_shp_type(body_sprite_id)

	# Default to TYPE1 if body_sprite_id not found
	if seq_type.is_empty():
		seq_type = "TYPE1"
	if shp_type.is_empty():
		shp_type = "TYPE1"

	# Shared set per (seq_type, shp_type) pair; type1 fallback handled inside.
	animation_set = AnimationDatabase.get_set(seq_type, shp_type)
	if animation_set.type1_seq.is_empty():
		push_error("[Unit] Failed to load animation data for %s/%s" % [seq_type, shp_type])
		return false

	return true

func _validate_components() -> void:
	"""Validate required components are present"""
	ValidationUtils.validate_required_components(self, [
		"MovementComponent",
		"UnitStats",
		"UnitStatusManager",
		"SpriteLayerManager",
		"AnimationStateController",
		"CameraRelativeRenderer"
	])

	# UnitProgression is a Resource (not a child node), set later by
	# bind_progression() for roster units or initialize_with_progression() for
	# standalone ones. Nothing to look up here.

func _wire_component_signals() -> void:
	"""Wire up all component signals"""
	# Combat stats signals - forward to EventBus for cross-system communication
	if unit_stats:
		unit_stats.hp_changed.connect(func(old_hp, new_hp):
			EventBus.emit_unit_hp_changed(self, old_hp, new_hp)
		)
		unit_stats.mp_changed.connect(func(old_mp, new_mp):
			EventBus.emit_unit_mp_changed(self, old_mp, new_mp)
		)
		unit_stats.died.connect(_on_unit_died)
		unit_stats.revived.connect(_on_unit_revived)

	# Status manager signals - connect incapacitation to death handling
	if unit_status:
		unit_status.unit_incapacitated.connect(_on_unit_incapacitated)

	# Animation state controller signals
	if anim_state:
		anim_state.activity_changed.connect(_on_animation_changed)
		# A facing change is a REPAINT, never an activity re-resolve. Routing it
		# through `_on_animation_changed` (→ `update_animation`) re-derives the
		# body slot from `activity` and, when the body anim was set OUT OF BAND —
		# the scenario VM writes `current_anim_id` directly (Path D), bypassing
		# `activity` — the re-resolve disagrees and CLOBBERS the scenario's anim
		# back to idle. That froze Gafgarion's Orbonne door-exit walk: a
		# concurrent `Rotate Unit` cascade flipped his cardinal mid-slide, each
		# flip resetting his walk (current_anim_id 4) to the idle at-ease pose so
		# he slid frozen. Facing never changes the resolved body slot anyway
		# (`AnimationResolutionMap.resolve_for_activity` is facing-independent),
		# so a repaint-only handler is equivalent for combat and correct for the
		# scenario. See ScenarioWalkFrameAdvanceTest (detector C).
		anim_state.facing_direction_changed.connect(_on_facing_direction_changed)

	# Precise facing repaint. `facing_direction_changed` (above) only fires on a
	# 4-way CARDINAL flip — sub-cardinal scenario_rotate steps (e.g. 0x000→0x200,
	# which collapse to the same cardinal) never trip it, and the body's pose
	# octant reads the precise 12-bit `facing_angle`. Without this hook a chapel
	# static-pose unit rotated AT A DIALOG BEAT (camera static, so the
	# `_on_camera_angle_changed` repaint never fires) freezes its sprite on
	# the old pose while the yellow facing arrow/label — wired to this same
	# signal in ScenarioPlayerScene — turn correctly. Mirrors the camera-angle
	# hook's rationale.
	facing_angle_changed.connect(_on_facing_angle_changed)

	# Camera renderer signals
	if camera_renderer:
		camera_renderer.camera_quadrant_changed.connect(_on_camera_quadrant_changed)
		camera_renderer.camera_angle_changed.connect(_on_camera_angle_changed)

	# Debug config signals (shader debugging)
	DebugConfig.show_depth_changed.connect(_on_show_depth_changed)

	# AnimationPlayback signals. The body-lead cascade + secondary paints + the
	# React BODY's completion are wired inside `display` (UnitDisplay). Unit keeps
	# only the normal BODY's state-completion / distort / move signals — these
	# drive Unit-owned activity + position state, not painting — plus the two
	# facade forwards (`body_paused` / `body_side_effect`) CombatLoop consumes.
	var body := display.type1_playback
	if body:
		body.animation_complete.connect(_on_playback_complete)
		body.animation_paused.connect(_on_playback_paused)
		body.side_effect.connect(_on_body_side_effect)
		body.distort_requested.connect(_on_distort_requested)
		body.move_offset_changed.connect(_on_move_offset_changed)

func _initialize_materials() -> bool:
	"""Initialize materials and sprite layers. Returns true on success.

	IMPORTANT: Requires animation_set to be loaded first.
	Call _initialize_animation_set() before this method.
	"""
	# Validate dependencies
	if not animation_set or animation_set.type1_shp.is_empty():
		push_error("[Unit] Cannot initialize materials - animation data not loaded! Call _initialize_animation_set() first.")
		return false

	# Load base material and duplicate it for this unit instance
	# IMPORTANT: duplicate() creates a unique material per unit to prevent shader parameter conflicts
	# The PATH is `UnitAssets`' — one host-side address for what used to be four independent
	# `load()`s of the same literal (ADR-0217 dec. 12). `Sprite Rig` takes it as an argument.
	var base_material := UnitAssets.base_material()
	self.material = base_material.duplicate()

	# ambient_brightness (1.0, calibrated to PSX) comes from unit.tres, backed by the
	# shader default — a version-controlled single source, not per-machine config.

	# Depth is the unified OT model (ADR-0009): the UNIT-mode forward nudge comes
	# from the shader's ot_unit_forward (tunable via UnitShaderDebugPanel), not
	# a per-material NDC bias.
	self.material.set_shader_parameter("debug_show_depth", DebugConfig.show_depth)

	# Base shared_loc_offset comes from the single source of truth
	# (SpriteLayerManager.shared_loc_offset, a static var — ADR-0036 no-"third-home" +
	# ADR-0068 R1), NOT the per-material .tscn literal. ONE Vector2 slug now (the old x/y
	# pair collapsed, R6): a per-unit `update` lands the coalesced offset on this unit's
	# _base_loc_offset (the base for move-opcode offsets) then re-pushes to the material;
	# move opcodes re-add their delta on the next frame (_on_move_offset_changed).
	_apply_render_tunable(_LOC_OFFSET_SLUG, SpriteLayerManager.shared_loc_offset,
		func(v: Vector2) -> void:
			_base_loc_offset = v
			self.material.set_shader_parameter("shared_loc_offset", _base_loc_offset))

	# The UNIT-mode forward nudge (ot_unit_forward, ADR-0009) is OWNED here now
	# (ADR-0068 move 2): a per-unit `update` lands the coalesced value onto this unit's
	# material at spawn AND a scrub live-updates every unit in any scene — instead of
	# UnitShaderDebugPanel fanning the write out over a units accessor (dead in a scene
	# without that panel). The DepthMode const supplies the boot default (in _static_init).
	_apply_render_tunable(_OT_FORWARD_SLUG, DepthModeScript.UNIT_FORWARD,
		func(v: float) -> void:
			self.material.set_shader_parameter("ot_unit_forward", v))

	# Initialize sprite layer manager (after material is loaded)
	sprite_layers.initialize(animation_set, material)

	# Set default paint priority in case there is no SetLayerPriority at the start of the first animation
	self.material.set_shader_parameter("priority", [0,1,2,3])
	# Initialize global reversion to false (will be set by load_frame_wait functions)
	self.material.set_shader_parameter("global_reversion", false)
	self.mesh_instance.mesh.surface_set_material(0, material)

	# Register with TintedSurfaces for spell effect tinting (caster/target flashing).
	# The registry is handed the MATERIAL and never dereferences the id (#1223).
	if not Engine.is_editor_hint():
		TintedSurfaces.register_surface(get_instance_id(), material)

	return true


func _exit_tree() -> void:
	"""Clean up when unit is removed from scene tree"""
	# The progression Resource is shared/persistent and outlives this node, so
	# drop our signal connections to it (don't free it — the roster owns it).
	_disconnect_progression_signals()

	# Unregister from TintedSurfaces to prevent memory leaks
	if not Engine.is_editor_hint():
		TintedSurfaces.unregister_surface(get_instance_id())


func _update_depth_center_marker() -> void:
	# Debug-only: visualize (and live-tune) the OT depth-sample center. Gated, so
	# it costs nothing when the toggle is off. See ADR-0009 / UnitShaderDebugPanel.
	if not DebugConfig.show_depth_center:
		if _depth_center_marker and _depth_center_marker.visible:
			_depth_center_marker.visible = false
		return
	if not _initialized or not material:
		return
	# Read the final center the body shader is using (SpriteLayerManager sets it
	# per body frame, live center_bias included) and put the marker there. Updates
	# on the next body-frame load after a bias change (units animate, so promptly).
	var hv = material.get_shader_parameter("depth_center_height")
	if hv == null:
		return
	_ensure_depth_center_marker()
	# Marker is a child of this unit (tile origin); the depth point is the mesh
	# origin (UnitMesh at +0.05) plus the center height.
	_depth_center_marker.position = Vector3(0.0, 0.05 + float(hv), 0.0)
	_depth_center_marker.visible = true


func _ensure_depth_center_marker() -> void:
	if _depth_center_marker:
		return
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	# psx-ot-depth-exempt: debug depth-center marker (no_depth_test, always-on-top), not battle geometry
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.0, 1.0)  # magenta
	mat.no_depth_test = true  # always visible, even through the sprite
	sphere.material = mat
	_depth_center_marker = MeshInstance3D.new()
	_depth_center_marker.mesh = sphere
	_depth_center_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_depth_center_marker)


func get_camera_quadrant() -> int:
	"""Delegate to CameraRelativeRenderer for camera quadrant calculation"""
	return camera_renderer.get_camera_quadrant() if camera_renderer else 0


# -----------------------------------------------------------------------------
# Semantic activity entry points (ADR-0024).
#
# These are the canonical surface for parameterized activity changes:
# Unit reads its own unit state (equipped weapon / shield), Unit consults the
# AnimationResolutionMap, Unit drives playback. Callers (Unit Animation Viewer
# panel, gameplay code) do not consult the map themselves.
#
# Parameterless activities (IDLE, WALKING, DYING, …) continue to use the
# existing `unit.activity = X` property setter — they don't need extra inputs.
#
# `last_resolution` exposes the Resolution returned by the most recent
# semantic-method call, for the viewer's readout. Null between calls or after
# a parameterless activity change.
# -----------------------------------------------------------------------------

var last_resolution = null  # AnimationResolutionMap.Resolution | null


func attack(vertical: int) -> void:
	"""Drive an ATTACKING animation resolved from the equipped weapon.

	Args:
		vertical: target tile elevation relative to this unit. 0=HIGH, 1=MID, 2=LOW.

	The resolved BODY / WEP1 slots come from `AnimationResolutionMap.resolve_attack`,
	which reads ROM-parsed `weapon_animation_ids.json` for the BODY base and
	delegates WEP1 to `WeaponAnimationSelector`.
	"""
	var sprite_type := get_seq_type()
	var item_type_id := _equipped_item_type_id(UnitProgression.EquipSlot.RIGHT_HAND)
	# Always resolve the FRONT variant (use_back=false). _apply_resolution stores
	# front_slot + back_slot (front+1) on the unit; _paint_body_variant picks
	# between them per frame based on the live camera quadrant — so post-attack
	# camera rotation keeps repainting the right variant from the held final frame.
	var r = AnimationResolutionMap.resolve_attack(sprite_type, item_type_id, vertical, false)
	last_resolution = r
	previous_activity = activity
	anim_state.current_state = DisplayActivity.Activity.ATTACKING
	display.apply_resolution(r)


func cast_spell(ability_id: int) -> void:
	"""Drive a SPELL_CASTING animation resolved from the ability's effect_anim_id.

	Args:
		ability_id: AbilityDatabase id. `effect_anim_id * 2` is the BODY slot
					for spells with their own pose; falls back to the
					per-sprite-type SPELL_CASTING default.
	"""
	var sprite_type := get_seq_type()
	# Always resolve the FRONT variant; the camera-variant pick happens at paint time.
	var r = AnimationResolutionMap.resolve_spell_casting(sprite_type, ability_id, false)
	anim_state.current_state = DisplayActivity.Activity.SPELL_CASTING
	last_resolution = r
	previous_activity = activity
	display.apply_resolution(r)


func use_item(ability_id: int) -> void:
	"""Drive a USING_ITEM animation. Items use the per-sprite-type USING_ITEM
	row from the animation resolution map (TYPE1_ITEM_USE = 114 on humanoids).

	Args:
		ability_id: AbilityDatabase id in the item-ability range [368, 381].
					Stored on active_ability_id so the resolver / observers can
					tell which item is being used.
	"""
	active_ability_id = ability_id
	var sprite_type := get_seq_type()
	var r = AnimationResolutionMap.resolve_using_item(sprite_type, false)
	anim_state.current_state = DisplayActivity.Activity.USING_ITEM
	last_resolution = r
	previous_activity = activity
	display.apply_resolution(r)


func charge_ability(ability_id: int) -> void:
	"""Drive a SPELL_CHARGING animation for the given ability.

	Args:
		ability_id: AbilityDatabase id. Resolves to the per-sprite-type
					SPELL_CHARGING slot; per-ability charging poses await
					the BATTLE.BIN 0x2ce10 table parser.
	"""
	var sprite_type := get_seq_type()
	# Always resolve the FRONT variant; the camera-variant pick happens at paint time.
	var r = AnimationResolutionMap.resolve_spell_charging(sprite_type, ability_id, false)
	anim_state.current_state = DisplayActivity.Activity.SPELL_CHARGING
	last_resolution = r
	previous_activity = activity
	display.apply_resolution(r)


func _equipped_item_type_id(slot: int) -> int:
	if not unit_progression:
		return 0
	var item_id: int = unit_progression.get_equipped_item(slot)
	if item_id < 0:
		return 0  # Unarmed
	return ItemDatabase.get_item_type_id(item_id)


func get_weapon_graphic() -> int:
	"""Equipped right-hand weapon's `graphic` id (0 = unarmed/fists). This is the
	key FFT's basic-attack dispatcher uses to pick the swing/hit SFX class — see
	AttackSfxResolver (sound follows the WEAPON, not the sprite)."""
	if not unit_progression:
		return 0
	var item_id: int = unit_progression.get_equipped_item(UnitProgression.EquipSlot.RIGHT_HAND)
	if item_id < 0:
		return 0  # unarmed -> graphic 0 -> fists
	return ItemDatabase.get_weapon_graphic(item_id)


func start_attack_with_anim_id(anim_id: int) -> void:
	"""Start an attack whose body animation is a fixed Path-D anim-id, bypassing
	the state-based StateAnimationDatabase lookup (issue #151).

	Used where the body anim doesn't map from the activity — the item throw
	(`TYPE1_THROW_WEAPON`, anim_id 77 → SEQ slots 152/153). Sets activity to
	ATTACKING for tracking/cleanup, then funnels the body id through
	`display.play_body` — the single Path-D seam (ADR-0053) that arms the clock
	AND updates `current_anim_id`, so the painter (`_paint_body_variant`) and the
	clock resolve the SAME anim. The predecessor `start_attack_with_animation`
	ran the clock on a raw SEQ slot without touching `current_anim_id`, so the
	painter kept dispatching off the stale id — the throw dispatch bug this
	retires.

	Args:
		anim_id: Path-D body anim-id (e.g. 77 for Throw Weapon). The painter
			derives front/back + flip per facing; no separate back operand.
	"""
	# Set state for tracking (direct current_state write — the activity setter
	# would re-trigger the state-based animation we're deliberately overriding).
	var old_state = activity
	anim_state.current_state = DisplayActivity.Activity.ATTACKING
	if old_state != activity:
		display._cancel_react_if_active()
	previous_activity = activity
	# Reset the movement lerp offset when starting the attack (parity with the
	# retired `_start_state_animation`).
	if material:
		material.set_shader_parameter("shared_loc_offset", _base_loc_offset)

	if DebugConfig.iteration_debug_enabled:
		print("[UNIT_ANIM_DEBUG] %s: start_attack_with_anim_id(%d)" % [name, anim_id])

	# Funnel: play_body arms the clock on the anim-id's canonical slot AND sets
	# current_anim_id, keeping painter + clock on one source of truth.
	display.play_body(anim_id)


func update_animation():
	"""Update display when activity or facing direction changes.

	The logical clock runs the canonical FRONT body anim for the current
	activity. A state change (front id changes) restarts the clock; a
	facing/camera change only re-renders the variant (no restart), keeping
	all layers in sync.

	Parameterless activities (IDLE/WALKING/DYING/etc.) route through
	`AnimationResolutionMap.resolve_for_activity` per ADR-0024 — the
	resolver is the single authority, `state_animations.json` is the
	single authoring file, and `last_resolution` carries the viewer
	readout. Parameterized activities (ATTACKING / SPELL_CASTING /
	CHARGING) are driven by `unit.attack(...)` / `unit.cast_spell(...)` /
	`unit.charge_ability(...)` and set `last_resolution` themselves
	before delegating to `_apply_resolution`, so this function is a
	no-op for them.
	"""
	# IDLE -> IDLE_LOW_HEALTH auto-pick: FFT-faithful AutoPotion threshold
	# hp < max_hp / 4 (see stage_damage.glsl:187). The resolver does the
	# dispatch; we just hand it the precomputed flag so it stays HP-agnostic.
	var low_health: bool = unit_stats != null \
		and unit_stats.max_hp > 0 \
		and unit_stats.current_hp < unit_stats.max_hp / 4
	# Cinematic idle (the pose-octant "at-ease" tent) is reserved for scenario
	# VM units; combat / gameplay units get their real standing idle SEQ instead
	# (see AnimationResolutionMap._resolve_state_for_type). The mode is carried by
	# the explicit `is_cinematic_unit` flag — NOT `facing_angle >= 0`, which is
	# being retired as a mode discriminator (ADR-0057 Stage 2) so `facing_angle`
	# can become an always-valid single source of truth.
	var cinematic_idle: bool = is_cinematic_unit
	var r = AnimationResolutionMap.resolve_for_activity(
		activity, get_seq_type(), false, low_health, cinematic_idle
	)
	if r.body_slot < 0:
		# MISS or parameterized — nothing to do here.
		return
	last_resolution = r
	# Path D: single anim_id write. The setter no-ops on same-value (covers
	# the DYING → DEAD "don't restart the clock" case — both resolve to the
	# same anim_id so DEAD holds the final death frame instead of replaying).
	# Facing/camera-only changes don't update `current_anim_id`, so the
	# setter doesn't fire and the camera repaint goes through the normal
	# `_render_camera_variant` path on quadrant changes.
	if current_anim_id == r.body_slot:
		previous_activity = activity
		_render_camera_variant()
	else:
		if activity != previous_activity:
			display._cancel_react_if_active()
		previous_activity = activity
		display.play_body(r.body_slot)


## Snapshot the unit's live facing + camera into the view dict the pure painters
## consume (C2b). Unit owns the orientation sources (`anim_state`, `facing_angle`,
## `camera_renderer`, and the `PSXDisplay.live_camera_angle` mirror the
## PlayerCamera publishes through the port); it reads them HERE and pushes the result into
## `display`, so the painters never reach live for view state. Keep the keys in
## sync with `UnitDisplay._view`.
func _build_view() -> Dictionary:
	return {
		"facing": facing_direction,
		"facing_angle": facing_angle,
		"camera_quadrant": get_camera_quadrant(),
		# 🔴 NOT `PSXDisplay.live_camera_angle if PSXDisplay else 0`. This was
		# the last copy in the tree of a ternary that cannot fire — a bare autoload
		# identifier is resolved at COMPILE time, so where the name is bound the
		# guard is dead weight and where it is not the file does not parse (#848,
		# ADR-0234). The HOST declares the autoload, so here the name simply
		# resolves; an ADDON must go through `ExMateriaPlatform.DisplayPort`.
		"camera_angle_12bit": PSXDisplay.live_camera_angle,
	}


## Tick-mode animation pump (CombatLoop). Builds + pushes the current view, then
## advances the clock — so the frame_changed repaints see this tick's facing +
## camera. `normal_reps`/`react_reps` are the two cadences (ADR-0025); see
## AnimationClock.advance_frame.
func advance_frame(normal_reps: int = 1, react_reps: int = 1) -> void:
	display.advance_frame(_build_view(), normal_reps, react_reps)


## Current normal BODY clock frame (issue #144 facade, read-only). GPURiseTimingTest
## latches the first tick this advances past 0 (the rise becoming visible).
var anim_frame: int:
	get: return display.type1_playback.anim_frame if display and display.type1_playback else 0


## Camera-relative rendering
##
## The painters live on `display` (UnitDisplay). Unit keeps this thin delegator
## because reach-ins still call `unit._render_camera_variant()` directly
## (ScenarioVMDebugPanel, UnitEffectCleanupOnStateChangeTest, the C0 golden) —
## migrated to a facade verb in a later step. It pushes a fresh view first so the
## repaint is a pure function of the unit's current orientation.
func _render_camera_variant() -> void:
	display.set_view(_build_view())
	display._render_camera_variant()

## Signal Handlers

func _on_unit_died() -> void:
	"""Handle unit death - add dead status and play death animation

	Called when CombatStats.died signal fires.
	Adds the &"dead" status to the status manager, which triggers
	the incapacitation path and death animation.

	Also forces animation playbacks to complete so any systems awaiting
	on this unit's animations are unblocked.
	"""
	if DebugConfig.iteration_debug_enabled:
		print("[%s] _on_unit_died - state=%s, is_reacting=%s" % [
			name, DisplayActivity.Activity.keys()[activity], is_reacting])

	# Add dead status to status manager (triggers unit_incapacitated signal)
	if unit_status:
		unit_status.add_status(&"dead", null)

	# Force animation playbacks to complete so awaiters unblock.
	# react_wep1/eff1 don't need force_complete — _cancel_react_if_active stops them.
	if display.type1_playback:
		display.type1_playback.force_complete()
	if display.react_playback:
		display.react_playback.force_complete()

	# Cancel any react animation - death takes priority
	display._cancel_react_if_active()

	activity = DisplayActivity.Activity.DYING

	# Emit through EventBus for cross-system communication
	EventBus.emit_unit_died(self)


func _on_unit_revived(_new_hp: int) -> void:
	"""Reverse _on_unit_died — confirm the carrier lands on IDLE post-revive.

	Fires when UnitStats.revived emits (from Reraise / Phoenix Down etc.).
	For cinematic Raise, the rise pose has already run: HIT_REACT on the
	cinematic effect drove `rise_from_dead()` mid-spell and the GETTING_UP
	one-shot SEQ has long since completed into IDLE via
	`_on_playback_complete`, so this call is a no-op overlay.

	For any future revive path that bypasses the cinematic (e.g. a quick
	Phoenix Down item without an EffectInstance), this is the only
	transition out of DYING/DEAD — the AnimationStateController locks both
	as terminal in normal play, so `set_state(IDLE)` would be rejected;
	bypass via `revive_to_idle()`.
	"""
	if DebugConfig.iteration_debug_enabled:
		print("[%s] _on_unit_revived - state=%s" % [
			name, DisplayActivity.Activity.keys()[activity]])

	if anim_state and activity != DisplayActivity.Activity.IDLE:
		anim_state.revive_to_idle()


func _on_unit_incapacitated() -> void:
	"""Handle unit incapacitation (from status manager).

	Called when UnitStatusManager.unit_incapacitated signal fires.
	This provides a single entry point for handling incapacitation
	from any source (death, petrify, stop, etc.)

	Cancels the action token so any async operations on this unit
	can exit cleanly.
	"""
	if DebugConfig.iteration_debug_enabled:
		print("[%s] _on_unit_incapacitated - current statuses: %s" % [
			name, unit_status.get_all_statuses() if unit_status else []])

func _on_animation_changed(_old_value = null, _new_value = null):
	"""Called when animation state or facing direction changes"""
	if not _initialized:
		return

	# Scale walking animation speed based on unit's movement speed
	_update_animation_speed_multiplier()

	update_animation()


func _update_animation_speed_multiplier() -> void:
	"""Set animation playback speed based on current state and movement speed

	Walking animations are synced to tile crossing time - one animation cycle
	completes exactly as the unit crosses one tile. This ensures the walk
	cycle never gets cut off mid-stride.
	"""
	if not display.type1_playback:
		return

	if activity == DisplayActivity.Activity.WALKING:
		# Calculate time to cross one tile at current speed
		var tile_time = 1.0 / unit_stats.movement_speed

		# Get walking animation's natural duration (front/back durations are identical).
		var anim_id = current_animation_front if current_animation_front != "" else display.type1_playback.anim_id
		var frame_count = AnimationFrameCalculator.get_duration(anim_id, animation_set.type1_seq)
		var anim_duration = float(frame_count) * AnimationPlayback.FRAME_DURATION

		# Scale so animation completes exactly when tile crossing completes
		# multiplier = natural_duration / desired_duration
		display.anim_clock.speed_multiplier = anim_duration / tile_time
	else:
		# Reset to normal speed for non-walking animations
		display.anim_clock.speed_multiplier = 1.0

func _on_camera_quadrant_changed(_new_quadrant: int):
	"""Called when camera quadrant changes (handled by CameraRelativeRenderer).

	Pure re-render — no playback restart — so this works identically whether the
	sim is running or paused, and keeps body/weapon/effect/react in sync.
	"""
	if not _initialized:
		return
	_render_camera_variant()

func _on_camera_angle_changed(_new_angle_12bit: int) -> void:
	"""Repaint when the live PSX camera angle moves within a cardinal quadrant.

	Combat units get this repaint incidentally via their looping idle anim's
	`frame_changed` tick heartbeat (which calls `_paint_body_variant` ~constantly,
	always reading the live angle). Chapel static-pose units (Path D `aid=2`
	single-`LoadFrameWait`) emit `frame_changed` only at load — without this
	hook they freeze on their spawn-time pose_octant through the entire
	intro camera pan. See CameraRelativeRenderer.camera_angle_changed.
	"""
	if not _initialized:
		return
	_render_camera_variant()

func _on_facing_direction_changed(_old_dir = null, _new_dir = null) -> void:
	"""Cardinal (4-way) facing flipped — REPAINT only, never re-resolve the body
	anim. Unlike `_on_animation_changed`, this does NOT call `update_animation()`:
	the resolved body slot is facing-independent, so re-resolving can only match
	(combat) or wrongly clobber an out-of-band scenario anim (see the connect-site
	comment). Keeps the walk-speed multiplier synced for combat walk turns."""
	if not _initialized:
		return
	_update_animation_speed_multiplier()
	_render_camera_variant()

func _on_facing_angle_changed(_new_angle_12bit: int) -> void:
	"""Repaint the body when the precise 12-bit facing changes (scenario_rotate /
	scenario_set_facing). Keeps the sprite pose in lock-step with the yellow
	facing arrow during a rotation that lands on a sub-cardinal byte or happens
	while the camera is static (a dialog beat). See the connect-site comment."""
	if not _initialized:
		return
	_render_camera_variant()

func _on_show_depth_changed(show: bool) -> void:
	"""Called when depth visualization is toggled"""
	if material:
		material.set_shader_parameter("debug_show_depth", show)

## AnimationPlayback Signal Handlers
##
## The body-lead cascade + secondary paints + the React BODY completion moved to
## `display` (UnitDisplay). Unit keeps only the NORMAL BODY's state / distort /
## move handlers below — they drive Unit-owned activity + position, not painting.

func _on_playback_complete() -> void:
	"""Called when type1 animation completes (non-looping, non-pausing).

	This is the real animation-completion source (the state controller can't
	know playback timing), so locked-state transitions happen here.
	"""
	clear_distort()
	var completed_state = activity
	# DYING → DEAD: when the death animation finishes, advance to the terminal
	# corpse state (otherwise the unit stays stuck on the death anim's last frame).
	if completed_state == DisplayActivity.Activity.DYING:
		activity = DisplayActivity.Activity.DEAD
	# GETTING_UP → IDLE: the rise SEQ is one-shot; when it completes the
	# carrier is back on its feet, so resolve to the normal idle stance.
	elif completed_state == DisplayActivity.Activity.GETTING_UP:
		activity = DisplayActivity.Activity.IDLE
	# Notify external listeners with the state that just completed.
	activity_complete.emit(completed_state)

func _on_playback_paused() -> void:
	"""Called when type1 animation pauses (PauseAnimation opcode)"""
	clear_distort()
	animation_paused.emit(current_animation_index)
	body_paused.emit()  # facade forward (issue #144): CombatLoop clears the spell-cast flag


func _on_body_side_effect(effect_type: int, params: Dictionary) -> void:
	"""Forward the normal BODY playback's side-effect up as `body_side_effect`
	(issue #144 facade). Two independent listeners share the same BODY side_effect:
	`display`'s cascade consumes QUEUE_SPRITE_ANIM / SET_LAYER_PRIORITY internally,
	CombatLoop consumes POST_GENERIC_ATTACK off this forward."""
	body_side_effect.emit(effect_type, params)

## Distort Movement Methods (QueueDistortAnim - Dash, etc.)

func _on_distort_requested(type: int, frame_count: int) -> void:
	"""Handle QueueDistortAnim opcode from type1 playback."""
	if _distort_controller:
		_distort_controller.start(type, frame_count, _distort_home_pos, _distort_target_pos)


func set_distort_context(home: Vector3, target: Vector3) -> void:
	"""Set positions for distort movement calculations.

	Called by GPUCombatTestBase when a cast starts, providing the
	home tile position and target tile position.
	"""
	_distort_home_pos = home
	_distort_target_pos = target


func clear_distort() -> void:
	"""Reset distort movement state and offset."""
	if _distort_controller:
		_distort_controller.reset()
	distort_offset = Vector3.ZERO


## SEQ Movement Opcode Handler (pixel nudges for attack wind-up/lunge/settle)

func _on_move_offset_changed(offset: Vector2) -> void:
	"""Apply movement opcode pixel offset to shared_loc_offset shader uniform."""
	if material:
		material.set_shader_parameter("shared_loc_offset", _base_loc_offset + offset)


## Force the normal BODY clock to its final frame (issue #144 facade). ScenarioVM
## calls this to freeze the per-tick painter before a cinematic walker takes the
## BODY shader; awaiters on death unblock the same way (`_on_unit_died`).
func force_complete_body() -> void:
	if display.type1_playback:
		display.type1_playback.force_complete()


## End an in-flight React window now (issue #144 facade). CombatLoop's REFRESH_TILE
## path + EffectViewerScene call this when the driving effect ends; the melee tick
## countdown ends the window internally (folded into `display.advance_frame`).
func end_reaction() -> void:
	display._on_react_complete()


func _process(delta):
	# Don't process if initialization failed (prevents errors with uninitialized data)
	if not _initialized:
		return

	# Delta-mode pump of both playback sets (ADR-0025) through the single clock
	# (ADR-0020). Idle playbacks (no anim_id) consume the tick as a no-op;
	# tick_based playbacks no-op here (advance_frame drives them instead).
	# Push the current view first so a delta-mode BODY's frame_changed repaint
	# paints this frame's facing + camera (C2b). Skip in tick mode: `tick()` is a
	# no-op there and `advance_frame()` pushes the view instead — building it here
	# too would allocate a wasted dict per unit per frame in the combat hot loop.
	if not display.anim_clock.tick_based:
		display.set_view(_build_view())
	display.anim_clock.tick(delta)

	_update_depth_center_marker()

	# Distort movement advances in lockstep inside AnimationPlayback.advance_frame
	# (BODY drives it), which the clock now pumps in BOTH modes — so there is no
	# separate delta-mode advance here anymore, only the per-frame offset sync.
	if _distort_controller:
		distort_offset = _distort_controller.get_offset()

	# Update dynamic shadow position, and hand it the sprite's OT depth key so the
	# shadow co-sorts with the unit (PSX inserts the shadow at the unit's own OT slot —
	# UNIT_SHADOW_RENDERING.md §2). The key is the exact point unit.gdshader projects:
	# the sprite mesh origin (== MODEL_MATRIX[3].xyz) + (0, depth_center_height, 0).
	if _shadow:
		var depth_point: Vector3 = global_position
		if mesh_instance and material:
			var hv = material.get_shader_parameter("depth_center_height")
			depth_point = mesh_instance.global_position
			if hv != null:
				depth_point.y += float(hv)
		_shadow.update(global_position, depth_point)


## Combat Methods (Phase 1.3 - Refactored to use CombatStats component)

func take_damage(amount: int) -> void:
	"""Apply damage to unit with logging"""
	unit_stats.take_damage(amount)


func heal(amount: int) -> void:
	"""Restore HP to unit with logging"""
	unit_stats.heal(amount)


func get_unit_stats() -> UnitStats:
	return unit_stats


func initialize_with_progression(base_stat_type: int, job_id: String, unit_team: UnitStats.Team,
		start_level: int = 1, mov_speed: float = 3.0) -> void:
	"""Initialize unit with FFT-style progression stats.

	Creates a UnitProgression component if not present, initializes it with the
	specified base type and job, then links it to UnitStats.

	Args:
		base_stat_type: UnitProgression.BaseStatType (0=MALE, 1=FEMALE, 2=MONSTER)
		job_id: Job ID as hex string (e.g., '4a' for Squire)
		unit_team: PLAYER or ENEMY
		start_level: Starting level (default 1)
		mov_speed: Movement animation speed
	"""
	# Mint a fresh progression Resource for a standalone (non-roster) unit.
	var progression = UnitProgressionClass.new()
	progression.initialize(base_stat_type, job_id)

	# Level up to starting level
	for i in range(start_level - 1):
		progression.level_up()

	_attach_progression(progression, unit_team, mov_speed)


func bind_progression(progression: Resource, unit_team: UnitStats.Team, mov_speed: float = 3.0) -> void:
	"""Bind this unit to an already-populated UnitProgression (shared by reference).

	Used by rosters: the live unit and the persistent roster entry share the
	SAME progression object, so menu/combat edits persist with no copy-back.
	"""
	_attach_progression(progression, unit_team, mov_speed)


func _attach_progression(progression: Resource, unit_team: UnitStats.Team, mov_speed: float = 3.0) -> void:
	"""Wire a progression (minted or bound) into this unit and connect its signals.

	The progression Resource outlives this Unit, so connections are torn down in
	_exit_tree to avoid a freed unit's handlers firing on the shared object.
	"""
	if unit_progression and unit_progression != progression:
		_disconnect_progression_signals()

	unit_progression = progression

	# Connect equipment_changed (weapon sprite updates) and forward stats_changed
	# so UI can connect to the Unit directly. Bound methods, not free lambdas, so
	# Godot also auto-disconnects them when this Unit is freed.
	if unit_progression.has_signal("equipment_changed") \
			and not unit_progression.equipment_changed.is_connected(_on_equipment_changed):
		unit_progression.equipment_changed.connect(_on_equipment_changed)
	if unit_progression.has_signal("stats_changed") \
			and not unit_progression.stats_changed.is_connected(_forward_progression_stats_changed):
		unit_progression.stats_changed.connect(_forward_progression_stats_changed)

	# Link to UnitStats
	unit_stats.initialize_from_progression(unit_progression, unit_team, mov_speed)

	# Refresh the weapon/shield sprite now that equipment is known. Roster spawn
	# binds the progression AFTER _ready's sprite-init already ran update_weapon_sprite()
	# with no progression bound (weapon_id resolved to -1, so the WEP1 layer was left
	# on the type-0 Knife frames). Without this re-load every equipped weapon rendered
	# as a dagger. equipment_changed only fires on later changes, not on initial bind.
	update_weapon_sprite()
	var shield_id := unit_progression.get_equipped_item(1) as int  # 1 = LEFT_HAND
	if shield_id >= 0:
		update_shield_sprite(shield_id)


func _forward_progression_stats_changed() -> void:
	"""Re-emit the shared progression's stats_changed as the Unit's own signal."""
	stats_changed.emit()


func _disconnect_progression_signals() -> void:
	"""Drop this unit's connections to the (persistent) progression resource."""
	if not unit_progression:
		return
	if unit_progression.has_signal("equipment_changed") \
			and unit_progression.equipment_changed.is_connected(_on_equipment_changed):
		unit_progression.equipment_changed.disconnect(_on_equipment_changed)
	if unit_progression.has_signal("stats_changed") \
			and unit_progression.stats_changed.is_connected(_forward_progression_stats_changed):
		unit_progression.stats_changed.disconnect(_forward_progression_stats_changed)


## Progression Accessors

var level: int:
	get:
		if unit_progression:
			return unit_progression.level
		return 1

var job_name: String:
	get:
		if unit_progression:
			return unit_progression.get_current_job_name()
		return "None"

var job_id: String:
	get:
		if unit_progression:
			return unit_progression.current_job_id
		return ""

var role: UnitRole.Role:
	get:
		if unit_progression and not unit_progression.current_job_id.is_empty():
			return JobDatabase.get_job_role(unit_progression.current_job_id)
		return UnitRole.Role.HYBRID


func level_up() -> void:
	"""Level up the unit (requires UnitProgression)."""
	if unit_progression:
		unit_progression.level_up()
	else:
		push_warning("[Unit] Cannot level up - no UnitProgression component")


func change_job(new_job_id: String) -> bool:
	"""Change the unit's job (requires UnitProgression).

	ADR-0022: also applies the new job's BODY palette row (via the one owner,
	SpritePaletteResolver.job_body_palette_row) so monster color variants
	(Yellow / Black / Red Chocobo, Goblin variants, Holy Dragon, etc.) render
	correctly when the job changes mid-game. Humanoid jobs resolve to row 0.
	"""
	if not unit_progression:
		push_warning("[Unit] Cannot change job - no UnitProgression component")
		return false
	var job_data: Dictionary = JobDatabase.get_job(new_job_id)
	if job_data.is_empty():
		push_warning("[Unit] change_job: unknown job_id %s" % new_job_id)
		return false
	# Update visuals FIRST. unit_progression.change_job emits job_changed
	# synchronously mid-call; any listener (UICombatManager.portrait refresh,
	# stats panel re-render) reads back unit.body_sprite_id, so it has to be the
	# new value before the signal fires.
	var is_female: bool = unit_progression.base_stat_type == UnitProgression.BaseStatType.FEMALE
	body_sprite_id = JobDatabase.get_sprite_id(new_job_id, is_female)
	# The JOB (CONTENT) palette axis lives in ONE place — SpritePaletteResolver.
	# Combat has no ENTD deployment record, so the row is purely job-sourced:
	# monsters/special non-humanoids get their variant row, humanoids get 0.
	body_palette_row = SpritePaletteResolver.job_body_palette_row(new_job_id)
	return unit_progression.change_job(new_job_id)


func set_sub_job(job_id: String) -> bool:
	"""Set the unit's secondary job (requires UnitProgression)."""
	if unit_progression:
		return unit_progression.set_sub_job(job_id)
	push_warning("[Unit] Cannot set sub-job - no UnitProgression component")
	return false


func equip_item(slot: int, item_id: int) -> bool:
	"""Equip an item into a slot (requires UnitProgression).

	The durable progression is shared with the roster entry (ADR-0005), so this
	persists with no copy-back; the equipment_changed signal it emits drives the
	weapon-sprite update via _on_equipment_changed.
	"""
	if unit_progression:
		return unit_progression.equip_item(slot, item_id)
	push_warning("[Unit] Cannot equip - no UnitProgression component")
	return false


func unequip_item(slot: int) -> int:
	"""Unequip the item in a slot, returning the removed item id (-1 if none)."""
	if unit_progression:
		return unit_progression.unequip_item(slot)
	push_warning("[Unit] Cannot unequip - no UnitProgression component")
	return -1


func learn_ability(ability_id: int) -> bool:
	"""Learn an ability (requires UnitProgression)."""
	if unit_progression:
		return unit_progression.learn_ability(ability_id)
	push_warning("[Unit] Cannot learn ability - no UnitProgression component")
	return false


func learn_ability_from_job(ability_id: int, job_id: String) -> bool:
	"""Learn an ability charged against a specific job's JP (requires UnitProgression)."""
	if unit_progression:
		return unit_progression.learn_ability_from_job(ability_id, job_id)
	push_warning("[Unit] Cannot learn ability - no UnitProgression component")
	return false


func set_equipped_reaction(ability_id: int) -> bool:
	"""Set the equipped reaction ability (requires UnitProgression)."""
	if unit_progression:
		return unit_progression.set_equipped_reaction(ability_id)
	push_warning("[Unit] Cannot set reaction - no UnitProgression component")
	return false


func set_equipped_support(ability_id: int) -> bool:
	"""Set the equipped support ability (requires UnitProgression)."""
	if unit_progression:
		return unit_progression.set_equipped_support(ability_id)
	push_warning("[Unit] Cannot set support - no UnitProgression component")
	return false


func set_equipped_movement(ability_id: int) -> bool:
	"""Set the equipped movement ability (requires UnitProgression)."""
	if unit_progression:
		return unit_progression.set_equipped_movement(ability_id)
	push_warning("[Unit] Cannot set movement - no UnitProgression component")
	return false


## Weapon Sprite Methods

func _on_equipment_changed(slot: int, _old_item_id: int, new_item_id: int) -> void:
	"""Handle equipment changes from UnitProgression.

	Updates weapon sprite when right hand equipment changes.

	Args:
		slot: UnitProgression.EquipSlot value (0=RIGHT_HAND, etc.)
		_old_item_id: Previous item ID (unused)
		new_item_id: New item ID
	"""
	# UnitProgression.EquipSlot.RIGHT_HAND == 0, LEFT_HAND == 1
	if slot == 0:
		update_weapon_sprite(new_item_id)
	elif slot == 1 and new_item_id >= 0:
		update_shield_sprite(new_item_id)


func update_weapon_sprite(weapon_id: int = -1) -> void:
	"""Update weapon sprite texture based on equipped weapon.

	Loads the WEP1 texture and configures it for the equipped weapon.
	Called automatically when equipment changes or during initialization.

	Args:
		weapon_id: Item ID of weapon (-1 to auto-detect from UnitProgression)
	"""
	if not sprite_layers:
		return

	# Auto-detect weapon ID from progression if not specified
	if weapon_id < 0 and unit_progression:
		weapon_id = unit_progression.get_equipped_item(0)  # 0 = RIGHT_HAND

	# No weapon equipped
	if weapon_id < 0:
		return

	# Load weapon texture by ROM item_id (NOT items.json.graphic — that's the
	# menu-icon index, unrelated to battle render). The 0x2d3e4 ROM table keyed
	# by item_id determines which row of WEP1.tga this specific weapon samples,
	# plus the palette rows for the WEP1 + EFF1 overlays.
	var item_type_id = ItemDatabase.get_item_type_id(weapon_id)
	sprite_layers.load_weapon_texture(item_type_id, weapon_id)
	var v_offset := WeaponGraphicData.get_v_offset(weapon_id)
	var palette_row := WeaponGraphicData.get_wep1_palette(weapon_id)
	sprite_layers.set_wep1_palette_row(palette_row)
	sprite_layers.set_eff1_palette_row(WeaponGraphicData.get_eff1_palette(weapon_id))

	# Cache frame offset - use WEP2 offsets for TYPE2 sprites (different SHP frame boundaries)
	var uses_wep2 = animation_set.is_type2 if animation_set else false
	var frame_offset := WeaponAnimationSelector.get_wep_frame_offset(item_type_id, uses_wep2)

	# Push the render caches across the seam (C3b) — the painter owns them now.
	display.set_weapon(frame_offset, palette_row, v_offset)

	if DebugConfig.action_debug_enabled:
		var weapon_name = ItemDatabase.get_item_name(weapon_id)
		GameLogger.debug(GameLogger.Category.ANIMATION,
			"Loaded weapon %s (item_id=%d, type=%d, v_offset=%d, wep1_pal=%d, eff1_pal=%d)" % [
				weapon_name, weapon_id, item_type_id, sprite_layers.wep1_v_offset_pixels,
				WeaponGraphicData.get_wep1_palette(weapon_id),
				WeaponGraphicData.get_eff1_palette(weapon_id)],
			{"unit": self})


func update_shield_sprite(shield_id: int) -> void:
	"""Cache shield frame offset for shield_block reaction animation.

	The shield renders via WEP1 layer. During shield_block, the WEP1
	offsets are temporarily swapped to the shield's values.
	"""
	if not sprite_layers:
		return
	var item_type_id = ItemDatabase.get_item_type_id(shield_id)
	var uses_wep2 = animation_set.is_type2 if animation_set else false
	var frame_offset := WeaponAnimationSelector.get_wep_frame_offset(item_type_id, uses_wep2)
	# Same ROM-table lookup the weapon path uses (parse_weapon_graphic_data.py);
	# keyed by ROM item_id, NOT items.json.graphic (which is the menu icon).
	var v_offset := WeaponGraphicData.get_v_offset(shield_id)
	var palette_row := WeaponGraphicData.get_wep1_palette(shield_id)

	# Push the shield render caches across the seam (C3b) — the shield-block react
	# paints from the display's own copies now.
	display.set_shield(frame_offset, palette_row, v_offset)

	if DebugConfig.action_debug_enabled:
		var shield_name = ItemDatabase.get_item_name(shield_id)
		GameLogger.debug(GameLogger.Category.ANIMATION,
			"Cached shield %s (item_id=%d, type=%d, frame_offset=%d, v_offset=%d)" % [
				shield_name, shield_id, item_type_id, frame_offset, v_offset],
			{"unit": self})


func get_weapon_item_type_id() -> int:
	"""Get the item_type_id of the equipped weapon.

	Used by combat system to determine weapon animation category.

	Returns:
		Item type ID, or 0 if no weapon equipped
	"""
	if not unit_progression:
		if DebugConfig.iteration_debug_enabled:
			print("[Unit] %s: get_weapon_item_type_id() - no unit_progression" % name)
		return 0

	var weapon_id = unit_progression.get_equipped_item(0)  # 0 = RIGHT_HAND
	if weapon_id < 0:
		if DebugConfig.iteration_debug_enabled:
			print("[Unit] %s: get_weapon_item_type_id() - no weapon equipped (id=%d)" % [name, weapon_id])
		return 0

	var item_type_id = ItemDatabase.get_item_type_id(weapon_id)
	if DebugConfig.iteration_debug_enabled:
		print("[Unit] %s: get_weapon_item_type_id() = %d (weapon_id=%d)" % [name, item_type_id, weapon_id])
	return item_type_id


## Gambit Methods

func set_gambit_list(list: GambitList) -> void:
	"""Set this unit's gambit list directly.

	Args:
		list: Custom GambitList to use
	"""
	gambit_list = list
	if gambit_list:
		gambit_list.ensure_fixed_size()


## Positioning Methods

func place_on_tile(grid_x: int, grid_z: int, map: Node3D,
		level: int = TerrainCell.GROUND_LEVEL) -> bool:
	"""Position unit at the center of a tile at given grid coordinates

	Automatically determines the correct Y height from the map's lattice.

	Args:
		grid_x: Grid X coordinate (integer)
		grid_z: Grid Z coordinate (integer)
		map: Map node — untyped by construction (`$ProceduralMap` infers `Node`),
			exposing `lattice: Lattice`. THE SEAM: this is the one untyped step
			ADR-0192 dec. 3 permits, and it is taken HERE rather than at ~30 call
			sites, every one of which would otherwise be a duck-typed reach of its own.
		level: which of the column's terrain levels to stand on (ADR-0219 dec. 1).
			Defaults to the ground — the answer every caller got implicitly before
			the upper level was built, and still the right one for all of them.

	Returns:
		true if the cell exists and the unit was placed, false otherwise
	"""
	var lattice: Lattice = map.lattice if map != null and ("lattice" in map) else null
	var cell: Vector3i = Vector3i(grid_x, grid_z, level)
	if lattice == null or lattice.terrain_at(cell) == null:
		push_error("Unit.place_on_tile: No tile at (%d, %d, L%d)" % [grid_x, grid_z, level])
		return false

	# Position at tile center
	global_position = Vector3(
		float(grid_x) + 0.5,
		lattice.world_position_at(cell).y,
		float(grid_z) + 0.5
	)

	# No reservation: occupancy is `Battle`'s, arbitrated by
	# the deployment assignment at deployment and derived per tick from unit
	# positions during combat (ADR-0166 dec. 2 / dec. 5). The tile-side claim this
	# call used to make was written after `global_position` above, so it never
	# guarded the state it named, and no caller read its `false`.

	# Initialize MovementComponent
	if movement_component:
		movement_component.initialize_logical_position(level)
	else:
		push_warning("Unit.place_on_tile: No MovementComponent")

	return true


## Phase 3.2: Animation Duration API

## Spatial Helper Methods (Refactoring Phase 1)

func get_current_cell() -> Vector3i:
	"""This unit's current grid cell, or `TerrainCell.NONE` if none.

	Facade method to reduce deep object traversal. Instead of:
	  unit.movement_component.current_cell
	Use:
	  unit.get_current_cell()

	🔴 THE OLD NAME WAS `get_current_tile()` AND IT CARRIED A COMMENT SAYING IT COULD
	NOT BE TYPE-HINTED "due to circular dependency". Both are gone. ADR-0170 dec. 4
	found the circular dependency was `Tile.gd -> Unit.gd -> Tile.gd`, closed by
	ADR-0166 dec. 1 deleting the four occupancy lines in `Tile.gd` that named `Unit`;
	and ADR-0166 dec. 3 dissolved it a second, independent time by making this return
	a `Vector2i`, so there is no `Tile` left to annotate. The rename lands with the
	type change because every call site had to move anyway (`null` → `TerrainCell.NONE`) —
	ADR-0170 dec. 4's ⚠️ warned the name would otherwise keep meaning "scene node" in
	`Battle`'s vocabulary across 28 sites, and this is the moment it costs nothing.

	Returns:
		The cell this unit stands on, or `TerrainCell.NONE` if none
	"""
	if movement_component:
		return movement_component.current_cell
	return TerrainCell.NONE


func scenario_rotate(target_12bit: int, direction: int, speed: int,
		delay: int) -> void:
	"""Apply a PSX-style rotation target (12-bit angle, 0=S, 0x400=E, 0x800=W,
	0xC00=N) using the FFT per-vsync stepper. Called by ScenarioVM's 0x2D
	Rotate Unit handler.

	Spawns a `_rotate_state` that ticks one 16-direction step per call to
	`_tick_rotate` (driven by `ScenarioVM._tick_once` at 60 Hz). The cadence
	matches `FUN_8013f20c`: each tick increments `counter`; once
	`counter >= _ROTATE_SPEED_TABLE[speed]` a single ±0x100 step lands and
	`counter` resets. `delay` defers the FIRST step by `delay >> 2` ticks
	(matches the handler's `(Delay × counter) >> 2` write to slot+6 in the
	common Delay=0 case, where it degenerates to a literal countdown).

	Direction semantics (from `FUN_8013f20c` 0x8013f330..0x8013f388):
	  * 0 = shortest path (CW or CCW based on minimum mod-16 distance)
	  * 1 = CW (high nibble increases, +0x100 per step)
	  * 2 = CCW (high nibble decreases, -0x100 per step)

	`facing_angle` (precise 12-bit) is updated every step; the cardinal snap
	for sprite rendering happens on each step too, so the body sprite turns
	through its 4 cardinals as the cascade progresses. Callers reading
	`facing_angle` between steps see the intermediate target.
	"""
	is_cinematic_unit = true  # a scenario-rotated unit renders the cinematic pose
	if facing_angle < 0 and anim_state:
		# Seed from cardinal so the first relative-rotation has a baseline.
		var card := int(anim_state.current_facing)
		facing_angle = _CARDINAL_TO_12BIT[card] if (card >= 0 and card < _CARDINAL_TO_12BIT.size()) else 0
	var start_byte: int = (facing_angle & 0xF00) >> 8
	var target_byte: int = (target_12bit & 0xF00) >> 8
	var spd := int(speed) & 0xFF
	var speed_value: int = _ROTATE_SPEED_TABLE[clampi(spd, 0, _ROTATE_SPEED_TABLE.size() - 1)]
	if start_byte == target_byte:
		# Already aligned — clear any in-flight state and snap immediately.
		_rotate_state = {}
		_write_facing_angle(target_12bit)
		return
	_rotate_state = {
		"target_byte": target_byte,
		"direction": int(direction) & 0xFF,
		"speed_value": speed_value,
		"counter": 0,
		"delay_remaining": (int(delay) & 0xFF) >> 2,
	}
	# Don't snap to target yet — the per-tick stepper drives `facing_angle`
	# one 16-direction step at a time and the cardinal will update each step.
	if DebugConfig.iteration_debug_enabled:
		print("[Unit %s] scenario_rotate armed: byte 0x%X→0x%X dir=%d speed=%d (val=%d) delay=%d" % [
			name, start_byte, target_byte, int(direction), int(speed),
			speed_value, int(delay)])


func scenario_set_facing(target_12bit: int) -> void:
	"""Instant facing set (no interpolation). Used by ScenarioVM's {8C} Unit Anim
	Rotate handler, which mirrors PSX opcode 0x8C (handler 0x80147fac): it writes
	the target facing nibble to the shared rotate queue but clears the +4 "active"
	flag, so the per-vsync stepper `FUN_8013f20c` never steps it — the facing
	snaps in one frame. This is the same snap `scenario_rotate` performs on its
	already-aligned fast path; exposed separately so {8C} can set ANY facing
	instantly (not only one already equal to the current cardinal).

	Clears any in-flight `scenario_rotate` stepper so a queued interpolation can't
	fight the instant set.
	"""
	is_cinematic_unit = true  # a scenario-faced unit renders the cinematic pose
	_rotate_state = {}
	_write_facing_angle(target_12bit)


func scenario_spawn_facing(target_12bit: int) -> void:
	"""Combat-idle spawn seed — the FAITHFUL placement default (NOT a freeze).

	Mirrors the ROM: a battle sprite is built through the status-anim selector
	FUN_80082eec @ 0x80082EEC (via evtchr_unit_clut_writer @ 0x80087A28), so a
	healthy unit resolves to the combat-idle "march in place" pose the instant it's
	placed — before any event opcode runs (MARCH_OPCODE_80_SEMANTICS.md §2.1 / §4.1,
	pc_0 = all units cycling). It is a STATUS-default, not a deployment-inherited or
	scenario-set pose.

	So a spawned unit gets its precise 12-bit `facing_angle` (for the pose-octant idle
	precision + facing arrow) but STAYS `is_cinematic_unit = false` — it march-idles,
	not the cinematic tent. This is the non-freezing counterpart to `scenario_set_facing`
	(the {8C}/Warp verb, which DOES freeze into a cinematic pose). Cinematic freezes are
	applied by the pose opcodes ({11} Unit Anim on the dialogue speaker, {8C} Rotate),
	exactly as the ROM freezes only the addressed unit; {80} March then releases it.

	Repaints the idle so the march-in-place SEQ is on screen with the combat resolution
	(guarded on `_initialized`, since the spawn path faces the unit after `_ready`)."""
	is_cinematic_unit = false
	_rotate_state = {}
	_write_facing_angle(target_12bit)
	if _initialized:
		update_animation()


func _write_facing_angle(angle_12bit: int) -> void:
	"""THE single facing-write path (ADR-0057 Stage 2 — "one truth, derived views").

	Sets the orientation SOURCE OF TRUTH (`facing_angle`), syncs the derived cardinal
	cache on `anim_state` (so direct `anim_state.current_facing` readers stay
	consistent), and emits `facing_angle_changed`. Every facing write funnels here —
	the scenario verbs (`scenario_set_facing` / `scenario_rotate` / `_tick_rotate`) AND
	the combat `facing_direction` setter — so `facing_angle` and the enum can never
	diverge (the chocobo sideways-walk was the walk writing only the enum). Does NOT
	touch `is_cinematic_unit` or `_rotate_state`; callers own those.
	"""
	facing_angle = angle_12bit & 0xFFF
	if anim_state:
		anim_state.set_facing(AnimationStateController.angle_12bit_to_facing(facing_angle))
	facing_angle_changed.emit(facing_angle)


func scenario_revive_and_normalise(revive_hp: int = 1) -> bool:
	"""{92} Inflict Status (Status=0) reproduction — revive-if-dead + normalise to a
	clean Standing pose. Returns whether the unit was dead (the PSX plays a revive
	SFX only in that case; see inflict_status_op92_decode.md §4.1 / §5.1).

	PSX task body FUN_80148E88 SS=0 branch: HP←1 only if the unit is dead, then force
	a Standing animation via BATTLE_set_unit_anim_value (the Critical variant when HP
	is low). Here `unit_stats.revive` restores HP + drops the &"dead" status only when
	dead (a no-op otherwise), and `revive_to_idle()` forces the IDLE re-resolve —
	bypassing the DYING/DEAD terminal lock — which `update_animation` maps to the
	Standing-vs-Critical pose by HP. NOT a status bit and NOT body removal.
	"""
	var was_dead := is_dead
	if was_dead and unit_stats:
		unit_stats.revive(revive_hp)
	if anim_state:
		anim_state.revive_to_idle()
	return was_dead


func scenario_inflict_poison_critical() -> void:
	"""{92} Inflict Status (Status=2) — Poison + Critical, unit-level half.

	PSX task body FUN_80148E88 SS=2 branch (inflict_status_op92_decode.md §11.2):
	adds the Poison status (runtime idx 0x1f / render +0x5b bit7) and forces the
	Critical pose (anim 0x16). It does NOT touch HP. The green sprite tint is the
	*caller's* half (ScenarioWorld.inflict_poison_critical drives the palette
	engine) — on PSX poison bakes a green-shifted CLUT into VRAM and holds it
	(static, no pulse; live-measured §12). Here we set the poison status bit and
	drop to the low-health kneel stance; the tint is applied around this call.
	"""
	if unit_status:
		unit_status.add_status(&"poison")
	if anim_state:
		anim_state.to_critical_idle()


var _crystal_sprite: CrystalSprite3D = null


func scenario_inflict_crystal() -> void:
	"""{92} Inflict Status (Status=1) — Crystal, unit-level half.

	PSX task body FUN_80148E88 SS=1 (inflict_status_op92_decode.md §12.7) sets the
	unit's Crystal bit (+0x58 & 0x40) and pose-state +0x3b1 = 2. It does NOT swap
	the unit's own SHP (sprite fields +0x06/+0x1E0 unchanged) — instead the bespoke
	death/crystal VFX (FUN_8006d818) stops drawing the body and draws a separate
	animated diamond graphic keyed on the crystal bit. We reproduce that here: hide
	the body sprite and spawn a [CrystalSprite3D] billboard (8-frame forward loop,
	4 vblanks/frame — RE'd live per-vblank §12.8).

	Crystal is NOT a GPU combat status bit (the 32-bit STATUS_FLAGS_LO set is full;
	there is no free bit — see StatusRegistry). It is a scenario cutscene visual, so
	we track it as a Unit-owned flag + billboard rather than via `unit_status`.
	Idempotent: a second call is a no-op.
	"""
	if _crystal_sprite != null and is_instance_valid(_crystal_sprite):
		return
	# Hide the body sprite; the crystal replaces it. Weapon/shield are composited
	# into the same UnitMesh material by SpriteLayerManager (no separate nodes), so
	# hiding mesh_instance hides the whole unit graphic.
	if mesh_instance:
		mesh_instance.visible = false
	_crystal_sprite = CrystalSprite3D.new()
	add_child(_crystal_sprite)


func is_crystallized() -> bool:
	"""True while the {92} SS=1 crystal billboard is active (body hidden)."""
	return _crystal_sprite != null and is_instance_valid(_crystal_sprite)


func _clear_crystal() -> void:
	"""Reverse `scenario_inflict_crystal`: free the diamond billboard and un-hide
	the body sprite. Guarded on `_crystal_sprite` so it only touches visibility
	for a unit that was actually crystallized (a non-crystallized unit's body may
	be legitimately hidden by other cutscene state — don't clobber it). No-op
	otherwise. Called by `reset_scenario_cutscene_state` on VM restart/rewind."""
	if _crystal_sprite == null:
		return
	if is_instance_valid(_crystal_sprite):
		_crystal_sprite.queue_free()
	_crystal_sprite = null
	if mesh_instance:
		mesh_instance.visible = true


func reset_scenario_cutscene_state(preserve_pose: bool = false) -> void:
	"""Zero the Unit-owned cutscene state — `facing_angle`, the in-flight
	`_rotate_state` stepper, `current_anim_id`, and the {92} SS=1 crystal billboard
	— so no stale facing, running rotation, event anim, or hidden-body crystal
	leaks across a live-VM restart (ADR-0064). Called by `ScenarioVM.reset_all` per
	live unit on `start()` / `set_rewind_target()`.

	Mirrors the PSX `FUN_8013f20c` teardown / the existing rotate-cancel (the
	`_rotate_state = {}` clear in `scenario_rotate`/`scenario_set_facing`). Keeps
	`Unit`'s private rotate/anim invariants inside `Unit`: the VM reaches rotate to
	reset it via this method, never poking `_rotate_state`/`current_anim_id`
	directly (ADR-0055's "reach rotate to reset, don't own it"). `facing_angle` goes
	to the `-1` sentinel (= "no precise cutscene facing"; the pose-octant render
	falls back to the cardinal). `play_body(0)` re-arms the idle clock on a live
	unit and is a no-op before scene init.

	`preserve_pose` is the combat->scenario POSE CARRY (the "dead units stand up
	before the scn6 fade" fix): when a woven victory beat re-enters scenario space
	on the SAME live combat units (decision #180), the combat side already left each
	unit's `current_anim_id` at the right real-SEQ pose — the KO'd unit's DEAD
	corpse slot, the critical survivor's kneel, the healthy unit's idle. Scenario
	mode has no dead/alive, only a unit and its anim-id, so we MIGRATE that pose
	across ONCE by NOT re-arming idle (which would stand a corpse up; re-arming from
	frame 0 would even replay the death fall). Facing/rotate/crystal STILL reset —
	a battle unit has no cutscene facing yet, so scn6's own rotate/face opcodes flip
	`is_cinematic_unit` per unit when they turn it. Off (default) everywhere else:
	the rewind/replay + non-victory paths keep their clean idle baseline.

	The re-arm goes through the resolver (`update_animation`), NOT a hardcoded
	`play_body(0)`: anim_id 0 is the cinematic TENT (AnimationResolutionMap slot 0),
	but `is_cinematic_unit` was just cleared, so the FAITHFUL baseline is the combat
	march-in-place idle (slot ≥1). The old hardcoded 0 silently re-froze every
	scenario-entry unit into the at-ease tent — clobbering `scenario_spawn_facing`'s
	march default the instant `ScenarioVM.start()` ran its `reset_all`, so units stood
	still all through an opener while only the {80}-March speaker moved
	(MARCH_OPCODE_80_SEMANTICS.md §5.2; ScenarioStartPreservesMarchIdleTest).
	"""
	facing_angle = -1
	is_cinematic_unit = false  # matches the -1 sentinel's old "combat idle" mode until re-warp
	_rotate_state = {}
	_clear_crystal()  # un-hide the body + free the {92} SS=1 billboard (no cross-restart leak)
	if not preserve_pose:
		if _initialized:
			update_animation()  # re-arm the march-in-place idle (is_cinematic_unit == false), not the tent
		elif display:
			display.play_body(0)  # pre-init: no-op idle-clock arm (display's play_body guards itself)


func _tick_rotate() -> void:
	"""Per-tick advance of an in-flight `scenario_rotate`. Mirrors the FFT
	per-vsync consumer `FUN_8013f20c` (see disassembly entry at 0x8013f20c
	+ static decode in `HANDOFF_rotation_interpolation.md`). Caller is
	expected to invoke once per 60 Hz tick (e.g. `ScenarioVM._tick_once`).
	No-op when no rotation is active.
	"""
	if _rotate_state.is_empty():
		return
	var st: Dictionary = _rotate_state
	var cur_byte: int = (facing_angle & 0xF00) >> 8
	if cur_byte == int(st["target_byte"]):
		_rotate_state = {}
		return
	# Delay first, then counter. Both happen in the same tick on FFT (the
	# consumer's `counter += 1` lives in the bne delay slot before the
	# delay-vs-step branch — see HANDOFF doc), but for visual purposes the
	# delay-countdown phase is just "skip step", which is what we do here.
	if int(st["delay_remaining"]) > 0:
		st["delay_remaining"] = int(st["delay_remaining"]) - 1
		return
	st["counter"] = int(st["counter"]) + 1
	if int(st["counter"]) < int(st["speed_value"]):
		return
	st["counter"] = 0
	var step_dir := _pick_step_direction(cur_byte, int(st["target_byte"]),
		int(st["direction"]))
	if step_dir == 0:
		# Unknown Direction value (not 0/1/2) — the FFT consumer holds at the
		# current facing rather than step. Match that.
		return
	var new_byte := (cur_byte + step_dir) & 0xF
	_write_facing_angle((new_byte << 8) & 0xFFF)


## Map a 12-bit angle to a Godot world Y-rotation in radians for debug-arrow
## visualization. Uses a UNIFORM 22.5°/byte rotation across the 16-direction
## FFT wheel — anchored at byte 0xC → Godot rotation 0° (the +X axis,
## marked "NORTH" in this project but actually screen-NE per the FFT
## isometric convention). Each decreasing byte advances Godot Y rotation
## by +π/8 (= +22.5°), which is the CCW direction from above and matches
## Direction=2 (the FFT-CCW convention in the consumer at 0x8013f20c).
##
## **Why uniform.** The polygon-visibility bitfield (per
## `DEPTH_MODE_RENDER_ORDER_GUIDE.md` §"Stage 4") splits the same 12-bit
## camera-angle space into 4 cardinal × 1024 + 8 octant × 512 + 16 sub-
## octant × 256 — a uniform geometric wheel where each byte = 22.5° and
## each cardinal label encodes a screen-aligned ORDINAL direction
## (NE/SE/SW/NW per the decomp comment), not a compass cardinal.
## Agrias's chapel cascade byte 0xC→0x4 (8 bytes, Direction=2) is
## therefore 180° rotation visually — matching the user observation that
## the prior cardinal-anchor lerp's 270° was wrong by-the-long-way-around.
##
## Since the 2026-06-30 harmonization, `AnimationStateController.
## angle_12bit_to_facing` shares THIS wheel's canonical convention
## (0x0=E, 0x4=S, 0x8=W, 0xC=N), so the cardinal labels and this arrow agree.
## The arrow uses the uniform geometric mapping and the yellow `DebugIdLabel`
## carries the byte index; any residual visual mismatch against PSX exposes a
## calibration offset. Cardinal-snap behavior is still available via the label.
static func facing_angle_to_world_radians(angle_12bit: int) -> float:
	var a: int = ((angle_12bit % 0x1000) + 0x1000) % 0x1000
	# Continuous byte position (high nibble + fractional from low byte) so
	# the per-tick stepper produces a smoothly-changing rotation. The
	# rotation rate is +22.5° per decreasing byte = +π/8 per byte step.
	var byte_continuous: float = float(a) / 256.0
	return (12.0 - byte_continuous) * (PI / 8.0)


# Returns +1 for CW step, -1 for CCW step, 0 for "hold" (unknown Direction).
# Mirrors the FFT consumer's Direction dispatch (FUN_8013f20c branches at
# 0x8013f330 / 0x8013f36c / 0x8013f380): Direction 0 picks the shorter of
# the two mod-16 paths to target; 1 = +1 (CW); 2 = -1 (CCW).
static func _pick_step_direction(cur_byte: int, target_byte: int, direction: int) -> int:
	if direction == 1:
		return 1
	if direction == 2:
		return -1
	if direction == 0:
		var cw_dist := (target_byte - cur_byte + 0x10) & 0xF
		var ccw_dist := (cur_byte - target_byte + 0x10) & 0xF
		return -1 if ccw_dist < cw_dist else 1
	return 0


func face_toward_unit(other: Unit) -> void:
	"""Face toward another unit

	Calculates the facing direction based on tile positions and updates
	this unit's facing direction accordingly.

	Args:
		other: Unit to face toward
	"""
	if not ValidationUtils.has_logical_position(self) or not ValidationUtils.has_logical_position(other):
		return

	facing_direction = TileTraversalUtils.get_facing_direction_for_step(
		get_current_cell(), other.get_current_cell())


## Sprite Identity Methods (Sprint 1 - Sprite-Aware Reactions)

func get_seq_type() -> String:
	"""Get the SEQ (sequence) type for this unit's sprite.

	Returns: Type name like "TYPE1", "TYPE2", "MON", "CYOKO", etc.
	"""
	return SpriteDatabaseClass.get_seq_type(body_sprite_id)

func get_shp_type() -> String:
	"""Get the SHP (shape) type for this unit's sprite.

	Returns: Type name like "TYPE1", "TYPE2", "MON", "CYOKO", etc.
	"""
	return SpriteDatabaseClass.get_shp_type(body_sprite_id)

func _load_initial_sprite_texture() -> void:
	"""Load sprite texture based on current body_sprite_id during initialization."""
	var sprite_data = SpriteDatabaseClass.get_sprite(body_sprite_id)
	if sprite_data.is_empty():
		return

	var spr_file = sprite_data.get("spr_file", "00.SPR")
	var texture_path = "res://assets/sprites/textures/%s" % spr_file.replace(".SPR", ".tga")

	if sprite_layers:
		# Prefer the unit's template folder (ADR-0072 #203); degrade to the flat
		# `texture_path` when it has no folder (generic) or the folder is absent.
		sprite_layers.load_body_sprite(template_folder, texture_path)
		# Re-apply the BODY palette row too: like body_sprite_id, it can be set
		# before add_child (e.g. roster spawn), when the setter's material didn't
		# exist yet. Seed the shader uniform now that sprite_layers is live so a
		# monster/special variant row survives the pre-_ready assignment.
		sprite_layers.set_body_palette_row(body_palette_row)
	# Animation data already loaded correctly in _initialize_animation_set()

	# Load weapon texture if unit has progression with equipped weapon
	update_weapon_sprite()

	# Cache shield offsets if unit has a shield equipped
	if unit_progression:
		var shield_id = unit_progression.get_equipped_item(1)  # 1 = LEFT_HAND
		if shield_id >= 0:
			update_shield_sprite(shield_id)

func _on_sprite_changed() -> void:
	"""Handle body_sprite_id changes - reload texture and animation data.

	Called automatically when body_sprite_id setter detects a change after initialization.
	"""
	print("[Unit] _on_sprite_changed called for body_sprite_id 0x%02X" % body_sprite_id)

	# Load the new sprite texture
	var sprite_data = SpriteDatabaseClass.get_sprite(body_sprite_id)
	if sprite_data.is_empty():
		push_warning("[Unit] Unknown body_sprite_id: 0x%02X" % body_sprite_id)
		return

	var spr_file = sprite_data.get("spr_file", "00.SPR")
	var texture_path = "res://assets/sprites/textures/%s" % spr_file.replace(".SPR", ".tga")
	print("[Unit] Loading texture: %s" % texture_path)

	if sprite_layers:
		# Prefer the unit's template folder (ADR-0072 #203); flat fallback stays.
		var loaded = sprite_layers.load_body_sprite(template_folder, texture_path)
		print("[Unit] Texture load result: %s" % str(loaded))

	# Reload animation set for the new sprite type
	animation_set = AnimationDatabase.get_set(get_seq_type(), get_shp_type())
	if not animation_set.type1_seq.is_empty():
		_reinitialize_playback()
	else:
		push_warning("[Unit] Failed to load animation data for %s/%s" % [get_seq_type(), get_shp_type()])

	if DebugConfig.action_debug_enabled:
		GameLogger.debug(GameLogger.Category.ANIMATION,
			"Sprite changed to 0x%02X (%s) - loaded %s" % [body_sprite_id, get_seq_type(), texture_path],
			{"unit": self})


func _reinitialize_playback() -> void:
	"""Reinitialize animation playback after the unit's UnitAnimationSet changed."""
	# Rebind sprite_layers to the new set (it holds the reference, not field copies).
	if sprite_layers and animation_set:
		sprite_layers.initialize(animation_set, material)

	# uses_wep2 may have flipped (TYPE1↔TYPE2), so the cached WEP1 zero_frame
	# offset and palette rows must refresh — otherwise the new sprite samples
	# WEP2.SHP through the old TYPE1 zero_frame (issue #41: Female Dancer +
	# Ryozan Silk renders the spear region of WEP2.SHP instead of cloth).
	update_weapon_sprite()
	if unit_progression:
		var shield_id := unit_progression.get_equipped_item(1) as int  # 1 = LEFT_HAND
		if shield_id >= 0:
			update_shield_sprite(shield_id)

	# Reset to IDLE to restart animation
	activity = DisplayActivity.Activity.IDLE
	update_animation()


## Reaction Animation Methods (Sprint 4)

func play_reaction_animation(seq_animation_id: int, reaction_type: int = ReactionType.Type.TAKING_DAMAGE, use_timer: bool = true) -> void:
	"""Trigger a React playback set (ADR-0025). Thin delegator — the React
	machinery (cascade, countdown, paint gate) lives on `display` (UnitDisplay).
	Kept on Unit because reach-ins + the C0 golden call `unit.play_reaction_animation(...)`;
	`display` emits Unit's `reaction_animation_played` signal for its listeners."""
	display.play_reaction_animation(seq_animation_id, reaction_type, use_timer)


## Debug Methods

# Target indicator for combat debug visualization
var _target_indicator: MeshInstance3D = null
