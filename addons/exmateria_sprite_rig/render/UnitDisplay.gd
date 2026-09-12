extends RefCounted

## The per-unit render module (issue #144, ADR-0020 / ADR-0025 / ADR-0053) — the
## single owner of everything between an *animation intent* and pixels on the
## shader. A RefCounted held as a private field on `Unit`; it references the
## Unit's existing `SpriteLayerManager` Node and body `ShaderMaterial` (through
## the `_unit` back-ref) rather than owning scene nodes, so the scene tree is
## untouched.
##
## It owns: the [AnimationClock], both [PlaybackSet]s (normal + React), the body
## / secondary painters (pose-octant / cardinal dispatch, frame lookup, palette +
## frame offset, layer priority), the React cascade + its `_react_active` /
## countdown, `current_anim_id` + its clock-arming setter, and all
## `load_frame_by_id` wiring.
##
## C2a is a RELOCATION: the painter still reads *view state* (facing, camera
## quadrant, PSX angle) and the WEP1/EFF1 offset caches from `Unit` temporarily —
## C2b pushes the view in through `advance_frame(view)`. `Unit` stays the sole
## facade; consumers never name `UnitDisplay`.
## Vault: [[Scenario 6 Ride Off]]
## Vault: [[Unit Anim Opcode]]
## Vault: [[Walk To Opcode]]
## Vault: [[Weapon Animation System]]

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const WeaponAnimationSelector = preload("res://addons/exmateria_sprite_rig/layers/WeaponAnimationSelector.gd")
const CinematicPoseLUT = preload("res://addons/exmateria_sprite_rig/state/CinematicPoseLUT.gd")
const AnimationStateController = preload("res://addons/exmateria_sprite_rig/state/AnimationStateController.gd")
const DisplayActivity = preload("res://addons/exmateria_sprite_rig/state/DisplayActivity.gd")
const AnimationPlayback = preload("res://addons/exmateria_sprite_rig/sequence/AnimationPlayback.gd")
const AnimationFrameCalculator = preload("res://addons/exmateria_sprite_rig/sequence/AnimationFrameCalculator.gd")
const PlaybackSet = preload("res://addons/exmateria_sprite_rig/sequence/PlaybackSet.gd")
const AnimationClock = preload("res://addons/exmateria_sprite_rig/sequence/AnimationClock.gd")

## `AnimationOpcodes` is `addons/exmateria_sprite_rig`'s now, published on the
## addon's one global name; this aliases it back so every use site below keeps
## the spelling it had (ADR-0211 dec. 4, ADR-0217 dec. 6).
const RigDebug = preload("res://addons/exmateria_sprite_rig/install/RigDebug.gd")
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction
## The cardinal->12-bit table lives beside `Direction` on the same kernel class
## (#744). An alias is a per-CLASS declaration (ADR-0211 dec. 4), and this file
## needs the class itself, not only its inner enum.
const Facing = ExMateriaSchema.Facing
const SpriteLayer = ExMateriaSchema.SpriteLayer.Kind

const REACT_DURATION_TICKS: int = 20
const BALL_ITEM_TYPE_ID: int = 33  # Ball item type for thrown projectiles

# Back-reference to the owning Unit. C2a reads view state (facing_direction,
# facing_angle, get_camera_quadrant()), the render targets (material,
# sprite_layers, animation_set, anim_state), the WEP1/EFF1 offset caches, the
# activity-state fields, and Unit signals through this. Progressive commits push
# these across the seam (view in C2b; the rest in C3).
# Untyped. `Unit` is `Battle`'s `class_name` and annotating with it is a
# compile-time edge from the painter to the combat unit — one of ADR-0215 P3a's
# 27, and the reason this addon would not parse in a project with no `Unit`. The
# painter only ever reads `name`, pushes fields and emits the unit's signals, so
# the annotation bought a type check on a seam that is deliberately duck-typed.
# `ScenarioVM.CinematicWalkState.unit` carries the same comment for the same reason.
var _unit  # Battle's Unit -- untyped, see above

# --- pushed-in view (C2b) -----------------------------------------------------
#
# Paint is a pure function of intent + view: the painters read the current
# facing + camera from THIS dict rather than reaching live into `_unit` /
# `DebugConfig` / `camera_renderer`. `Unit` refreshes it (`set_view`, or the
# `view` arg to `advance_frame`) on every repaint trigger — the four camera/
# facing handlers, the delta-mode `_process` tick, and the tick-mode
# `advance_frame` — so it always reflects the unit's live orientation at paint
# time. Keys: `facing` (FacingDirection cardinal), `facing_angle` (12-bit, -1 =
# combat sentinel), `camera_quadrant` (0-3), `camera_angle_12bit` (the camera yaw).
#
# 🔴 `camera_angle_12bit`, NOT `psx_angle` (goal #7, ADR-0234). Three of this
# addon's twelve rig-owned platform-jargon lines were this key and its two readers.
# The key is a CONTRACT with `src/units/Unit.gd:_build_view`, so it is renamed on
# both sides in one commit, and `tests/UnitDisplayPaintGoldenTest.gd` /
# `tests/UnitThrowBodyDispatchTest.gd` hand-build the same dict.
var _view: Dictionary = {
	"facing": FacingDirection.NORTH,
	"facing_angle": -1,
	"camera_quadrant": 0,
	"camera_angle_12bit": 0,
}

# --- owned playbacks / sets / clock (ADR-0020 / ADR-0025) ---------------------
var type1_playback: AnimationPlayback
var wep1_playback: AnimationPlayback
var eff1_playback: AnimationPlayback
var react_playback: AnimationPlayback        # React-set BODY
var react_wep1_playback: AnimationPlayback   # React-set WEAPON (shield_block etc.)
var react_eff1_playback: AnimationPlayback   # React-set EFFECT

var _normal_set: PlaybackSet
var _react_set: PlaybackSet
var anim_clock: AnimationClock

# --- owned render state -------------------------------------------------------

## The single FFT anim-id field driving the body layer's renderer dispatch
## (ADR-0053). Mirrors PSX `unit+0x0c`. READ-ONLY to consumers: written only by
## the `play_body` funnel (which re-arms the clock). See the dispatch ranges
## documented on `_paint_body_variant`.
var current_anim_id: int = 0

var _react_active: bool = false  # When true, painting reads the React set
var _react_ticks_remaining: int = 0  # >0 = melee react with tick countdown; 0 = no timer (spell reacts)

# Active reaction SEQ slot (-1 = none). The front/back variant + reversion are
# recomputed per paint from the live view in `_paint_body_variant`, so no variant
# is cached here.
var _react_seq_animation_id: int = -1

# Track if this is the first frame of an animation (for disabling wep/eff layers)
var _is_first_frame: bool = true

var apply_reversion: bool = false

# WEP1 shield-vs-weapon render flag + EFF1 frame offset. Display-only render
# state: written by the body-lead cascade below, read by `_paint_secondary_variant`.
var _wep1_showing_shield: bool = false
var _eff1_frame_offset: int = 0

# --- equip caches, pushed from Unit's equip path (C3b) -----------------------
#
# The WEP1 sprite-row / palette / frame offset for the equipped weapon and shield.
# Unit's `update_weapon_sprite` / `update_shield_sprite` compute these from the ROM
# tables and push them in via `set_weapon` / `set_shield` — the painter reads its
# OWN copies rather than reaching back across the seam into `_unit.*`. Defaults
# mirror Unit's old fields: shield frame offset -1 = "no shield equipped" (the
# `>= 0` test in `_on_set_body_side_effect` gates the shield-display flag).
var _wep1_frame_offset: int = 0
var _weapon_wep1_v_offset: int = 0
var _weapon_wep1_palette_row: int = 0
var _shield_wep1_frame_offset: int = -1
var _shield_wep1_v_offset: int = 0
var _shield_wep1_palette_row: int = 0


func _init(unit) -> void:  # Battle's Unit -- untyped, see `_unit`
	_unit = unit

	# Six playbacks: the normal set (type1 / wep1 / eff1) and the parallel React
	# set (react / react_wep1 / react_eff1). The body-lead rule applies inside
	# each set independently; cross-set side-effects are forbidden.
	type1_playback = AnimationPlayback.new()
	wep1_playback = AnimationPlayback.new()
	eff1_playback = AnimationPlayback.new()
	react_playback = AnimationPlayback.new()
	react_wep1_playback = AnimationPlayback.new()
	react_eff1_playback = AnimationPlayback.new()

	# Group the six into the normal + React PlaybackSets (ADR-0025); the one clock
	# pumps the two sets (ADR-0020). Callers drive the clock, not the six.
	_normal_set = PlaybackSet.new(type1_playback, wep1_playback, eff1_playback, false)
	_react_set = PlaybackSet.new(react_playback, react_wep1_playback, react_eff1_playback, true)
	anim_clock = AnimationClock.new(_normal_set, _react_set)

	# The body-lead cascade + secondary paints are ONE parameterized
	# implementation, bound to each PlaybackSet (ADR-0025) — the set's `is_react`
	# flag carries every normal-vs-React difference. The normal BODY's
	# state-completion / distort / move signals stay on Unit (wired there); the
	# React BODY's completion ends the react window (wired here).
	_wire_playback_set(_normal_set)
	_wire_playback_set(_react_set)
	if react_playback:
		react_playback.animation_complete.connect(_on_react_complete)
		# Note: animation_paused is NOT connected on the React BODY - hold-forever
		# poses should stay until timeout fires, not end immediately when paused.


# -----------------------------------------------------------------------------
# View push (C2b)
# -----------------------------------------------------------------------------

func set_weapon(frame_offset: int, palette_row: int, v_offset: int) -> void:
	"""Push the equipped weapon's WEP1 render caches (C3b). `Unit.update_weapon_sprite`
	computes these from the ROM tables and calls this; `_paint_secondary_variant`
	reads them for the weapon (non-shield) branch."""
	_wep1_frame_offset = frame_offset
	_weapon_wep1_palette_row = palette_row
	_weapon_wep1_v_offset = v_offset


func set_shield(frame_offset: int, palette_row: int, v_offset: int) -> void:
	"""Push the equipped shield's WEP1 render caches (C3b). `Unit.update_shield_sprite`
	calls this; the shield-block react paints from these. `frame_offset < 0` means
	no shield — the cascade's `_shield_wep1_frame_offset >= 0` gate then stays off."""
	_shield_wep1_frame_offset = frame_offset
	_shield_wep1_palette_row = palette_row
	_shield_wep1_v_offset = v_offset


func set_view(view: Dictionary) -> void:
	"""Push the current facing + camera view (see `_view`). `Unit` calls this
	before every repaint trigger so the pure painters read a fresh orientation
	without reaching live into `_unit`."""
	_view = view


func advance_frame(view: Dictionary, normal_reps: int = 1, react_reps: int = 1) -> void:
	"""Tick-mode pump (ADR-0020): push the view, then advance the clock, which
	drives the two PlaybackSets and repaints via the frame_changed cascade. The
	pushed view is what those repaints see, so a camera/facing change lands in the
	same frame it advances. `normal_reps`/`react_reps` are the two cadences the
	host distinguishes (see AnimationClock.advance_frame)."""
	set_view(view)
	anim_clock.advance_frame(normal_reps, react_reps)
	# Melee react duration countdown (spell reacts pass use_timer=false → 0, no
	# timer; they end via REFRESH_TILE / `_on_react_complete`). C3a folded this in
	# from the host: CombatLoop / GPUReactDurationTest used to decrement it right
	# after `advance_frame` — display owns the window now, so one tick = one
	# decrement here, ending react at 0.
	if _react_active and _react_ticks_remaining > 0:
		_react_ticks_remaining -= 1
		if _react_ticks_remaining <= 0:
			_on_react_complete()


# -----------------------------------------------------------------------------
# Intent drivers
# -----------------------------------------------------------------------------

func _stop_normal_secondaries() -> void:
	"""Tear down the normal-set WEP1/EFF1: stop the playbacks (clears `anim_id` so
	`_paint_secondary_variant` no-ops) and disable their layers. Shared by
	`apply_resolution` and `_arm_anim_id_clock`; a dropped copy of this once froze
	an attack slash on a corpse (see `_arm_anim_id_clock`)."""
	if wep1_playback:
		wep1_playback.stop()
	if eff1_playback:
		eff1_playback.stop()
	if _unit.sprite_layers:
		_unit.sprite_layers.enable_layer(SpriteLayer.WEP1, false)
		_unit.sprite_layers.enable_layer(SpriteLayer.EFF1, false)


func play_body(anim_id: int) -> void:
	"""The single funnel for the body layer's FFT anim-id (ADR-0053). Sets
	`current_anim_id` and re-arms the playback clock (`_arm_anim_id_clock`,
	mirrors PSX `FUN_80084818`). Same-value writes are idempotent so paint-time
	pose resampling doesn't restart the clock — this also covers the DYING → DEAD
	'don't replay the death clock' case (both resolve to the same anim_id)."""
	if current_anim_id == anim_id:
		return
	current_anim_id = anim_id
	# Back-compat: existing tests + viewer readouts read `current_animation_front`
	# as "the SEQ key the clock is running on." Post-Path-D the clock runs on a key
	# derived from `current_anim_id`, but the field stays populated so those readers
	# see something meaningful and the resolver-vs-Unit equality assertions hold.
	if _unit:
		_unit.current_animation_front = str(anim_id)
		_unit.current_animation_index = str(anim_id)
	_arm_anim_id_clock()


func apply_resolution(r) -> void:
	"""Drive BODY / WEP1 / EFF1 playbacks from a Resolution (ADR-0053 writer).
	Slots <0 mean 'no layer' — the corresponding layer is disabled. The body
	side is a single `current_anim_id` write; the renderer (`_paint_body_variant`)
	handles front/back/mirror dispatch."""
	if not _unit._initialized or not _unit.animation_set:
		return
	var animation_set = _unit.animation_set
	var sprite_layers = _unit.sprite_layers
	if r.body_slot >= 0:
		# Cancel react on state transition (was inside _start_state_animation;
		# Path D collapses that helper, so the cancel rides here).
		if _unit.activity != _unit.previous_activity:
			_cancel_react_if_active()
		# Stop weapon/effect layers; they re-queue when the new clock advances.
		_stop_normal_secondaries()
		_unit.previous_activity = _unit.activity
		play_body(r.body_slot)
	if r.wep1_slot >= 0:
		var wep_seqs: Dictionary = animation_set.wep_seq
		var wep_key := str(r.wep1_slot)
		if wep_seqs.has(wep_key):
			sprite_layers.enable_layer(SpriteLayer.WEP1, true)
			wep1_playback.start(wep_key, wep_seqs)
			_paint_secondary_variant(wep1_playback, SpriteLayer.WEP1)
	else:
		sprite_layers.enable_layer(SpriteLayer.WEP1, false)
		if wep1_playback:
			wep1_playback.stop()
	if r.eff1_slot >= 0:
		var eff_key := str(r.eff1_slot)
		if animation_set.eff1_seq.has(eff_key):
			sprite_layers.enable_layer(SpriteLayer.EFF1, true)
			eff1_playback.start(eff_key, animation_set.eff1_seq)
			_paint_secondary_variant(eff1_playback, SpriteLayer.EFF1)
	else:
		sprite_layers.enable_layer(SpriteLayer.EFF1, false)
		if eff1_playback:
			eff1_playback.stop()


func _arm_anim_id_clock() -> void:
	"""Re-arm the body-layer playback clock when `current_anim_id` changes
	(ADR-0053). Mirrors PSX `FUN_80084818`: pose state zeroed, frame counter
	seeded. The renderer picks the actual SEQ slot per paint from the
	dispatch table in `_paint_body_variant`; the clock just runs on the
	canonical slot for the anim_id range so the same `anim_frame` drives all
	repaints of this anim.
	"""
	var animation_set = _unit.animation_set
	if not _unit._initialized or not animation_set or not type1_playback:
		# Pre-initialization writes (test scaffolding, scenario VM landing
		# before scene-ready) just store the value; the first paint after
		# init will arm the clock through the renderer.
		return
	# A new body anim_id makes any WEP1/EFF1 sprite from the prior anim (an
	# attack swing's weapon + slash, a cast trail) stale — tear down the stale
	# secondaries. ADR-0053 routed the parameterless state path (DYING /
	# CELEBRATING / IDLE / WALKING) through this setter but dropped the teardown
	# that `_start_state_animation` used to do; `apply_resolution` (the
	# parameterized path) re-starts its secondaries right after this runs.
	_stop_normal_secondaries()
	# Canonical slot per dispatch range — keeps the clock keyed off a slot
	# that actually exists in the seq table.
	var clock_key: String
	if current_anim_id == 0:
		clock_key = "1"  # idle frame_base 1 is the always-authored anchor
	elif current_anim_id < 0x1f4:
		clock_key = str((current_anim_id - 1) * 2)
	else:
		clock_key = str(current_anim_id - 1)  # EVTCHR direct index (>= 0x1f4)
	if not animation_set.type1_seq.has(clock_key):
		return  # No SEQ for this anim_id (EVTCHR stub etc.)
	type1_playback.start(clock_key, animation_set.type1_seq)
	_is_first_frame = true
	_paint_body_variant()


# -----------------------------------------------------------------------------
# Camera-relative rendering
#
# Presentation is decoupled from the logical clock: these methods paint the
# current frame of each layer for the current facing+camera by choosing the
# front/back variant and horizontal flip. No playback is restarted, so camera
# rotation (even while the sim is paused) keeps the whole ensemble in sync.
# -----------------------------------------------------------------------------

func _render_camera_variant() -> void:
	"""Repaint every layer for the current view, picking the active playback
	set (ADR-0025) per `_react_active`."""
	_paint_body_variant()
	var wep_src: AnimationPlayback = react_wep1_playback if _react_active else wep1_playback
	var eff_src: AnimationPlayback = react_eff1_playback if _react_active else eff1_playback
	_paint_secondary_variant(wep_src, SpriteLayer.WEP1)
	_paint_secondary_variant(eff_src, SpriteLayer.EFF1)


func _paint_body_variant() -> void:
	"""Paint the TYPE1 layer (body, or react when active) for the current view.

	Path D dispatch on `current_anim_id` (ADR-0053) mirrors PSX `FUN_80085c0c`
	with one Godot-side accommodation for chapel-style static poses:
	  * `0`         → idle, Sub-tables A+B (pose-octant precision, 5 frame bases)
	  * `1..0x1f4`  → SEQ-range. Two sub-cases:
	      - single-LoadFrameWait SEQ (chapel `aid=2` style static pose):
	        route through Sub-tables A+B so the yellow facing arrow + camera
	        octant pick from the 5 authored poses, not just the 2-slot
	        cardinal pair `(anim-1)*2`/+1`.
	      - multi-frame SEQ (combat walking/attacking): Sub-tables E+F
	        cardinal LUT (PSX path) so the opcode stream plays.
	  * `>= 0x1f5`  → EVTCHR (deferred — push_error stub)

	React (post-attack hit/evade animations) keeps its pre-Path-D cardinal flow
	since reactions don't go through `current_anim_id` today."""
	var animation_set = _unit.animation_set
	if not _unit._initialized or not _unit.material or not animation_set:
		return
	var camera_quad: int = _view["camera_quadrant"]

	# React owns the body layer while active.
	if _react_active and _react_seq_animation_id >= 0:
		var display := AnimationStateController.get_camera_variant(_view["facing"], camera_quad)
		var use_back_react: bool = display["use_back"]
		apply_reversion = display["revert"]
		_unit.sprite_layers.set_global_reversion(apply_reversion)
		var react_anim := str(_react_seq_animation_id * 2 + (1 if use_back_react else 0))
		if not animation_set.type1_seq.has(react_anim):
			react_anim = str(_react_seq_animation_id * 2)
		if animation_set.type1_seq.has(react_anim):
			var rframe := AnimationFrameCalculator.get_frame_at(react_anim, react_playback.anim_frame, animation_set.type1_seq)
			if rframe >= 0:
				_unit.sprite_layers.load_frame_by_id(SpriteLayer.TYPE1, rframe, false)
		return

	var seq_key: String = ""

	# Path D PSX-faithful pose composition (ADR-0053). Both idle and
	# SEQ-range branches consume the SAME continuous PSX camera angle the
	# polygon-cull shader uses — one angle convention across both
	# renderers. Live calibration knob:
	# RigDebug.pose_octant_offset_12bit() (F3 panel).
	var view_angle: int = _view["facing_angle"]
	var fa: int = view_angle if view_angle >= 0 else int(Facing.CARDINAL_TO_12BIT[_view["facing"]])
	# The camera yaw is pushed in via `_view` (Unit reads it from the display
	# calibration autoload, where PlayerCamera publishes it every frame through
	# `DisplayPort.set_camera_angle`) — the painter never reaches for the global
	# itself, so paint stays a pure function of the pushed view.
	var camera_angle_12bit: int = _view["camera_angle_12bit"]
	var pose_octant := AnimationStateController.get_pose_octant(fa, camera_angle_12bit)

	if current_anim_id == 0:
		# Idle: Sub-tables A+B (pose-octant precision, 5 frame bases, tent
		# walk produces the chapel rotate-cascade).
		seq_key = str(CinematicPoseLUT.SUB_A_FRAME_BASE[pose_octant])
		var mirror_bit: int = CinematicPoseLUT.SUB_B_MIRROR[pose_octant]
		apply_reversion = (mirror_bit & 0x02) != 0
		_unit.sprite_layers.set_global_reversion(apply_reversion)
	elif current_anim_id < 0x1f4:
		# Low-range SEQ anim. PSX FUN_80085c0c dispatches per-animation, NOT on
		# whether the SEQ is single-frame: `event_anim_id == 2` (current_anim_id
		# == 3, the chapel "at-ease" stance) takes the pose-octant tent; every
		# other anim renders its own authored frame (`event_anim_id*2 +
		# frontback[cardinal]`). The kneel (`event_anim_id 0x24` →
		# current_anim_id 37) is CASE B → SHP frame 72. See
		# `CinematicPoseLUT.resolve_low_range_seq_key` for the full RE citation.
		var res := CinematicPoseLUT.resolve_low_range_seq_key(
			current_anim_id, pose_octant, animation_set.type1_seq)
		seq_key = res["seq_key"]
		apply_reversion = res["mirror"]
		_unit.sprite_layers.set_global_reversion(apply_reversion)
	else:
		# EVTCHR cinematic-range Unit Anim (`>= 0x1f4`, PSX band boundary — both the
		# mid `[0x1F4,0x258)` and high `[0x258,…)` cinematic tables): the scenario
		# VM's CinematicWalkState drives the BODY shader from the EVTCHR atlas —
		# Unit's per-tick painter stays out of the way. Cinematic ids are written
		# RAW (no low-range `+1`), so the boundary is 0x1F4, not 0x1F5; the only
		# aliasing value, low-range event 499 (`+1`→0x1F4), is unused. See
		# ScenarioVM._play_cinematic_unit_anim, ADR-0053, and
		# `SCENARIO6_CARRY_POSE_EVTCHR_RENDER.md`.
		return

	if seq_key != "" and animation_set.type1_seq.has(seq_key):
		var bframe := AnimationFrameCalculator.get_frame_at(seq_key, type1_playback.anim_frame, animation_set.type1_seq)
		if bframe >= 0:
			_unit.sprite_layers.load_frame_by_id(SpriteLayer.TYPE1, bframe, _is_first_frame)
			_is_first_frame = false
	_apply_variant_layer_priority(seq_key, type1_playback.anim_frame)


func _paint_secondary_variant(playback: AnimationPlayback, layer: int) -> void:
	"""Paint a wep1/eff1 layer for the current view (back variant = front id + 1)."""
	if not _unit._initialized or not _unit.material or not _unit.animation_set:
		return
	if not playback or playback.anim_id.is_empty():
		return
	var animation_set = _unit.animation_set
	var sprite_layers = _unit.sprite_layers
	var use_back: bool = AnimationStateController.get_camera_variant(_view["facing"], _view["camera_quadrant"])["use_back"]
	var seqs: Dictionary = animation_set.wep_seq if layer == SpriteLayer.WEP1 else animation_set.eff1_seq
	var anim := playback.anim_id
	if use_back:
		var back := str(int(anim) + 1)
		if seqs.has(back):
			anim = back
	if not seqs.has(anim):
		return
	var frame := AnimationFrameCalculator.get_frame_at(anim, playback.anim_frame, seqs)
	if frame < 0:
		return
	if layer == SpriteLayer.WEP1:
		# WEP1 paints either the equipped weapon or the shield. Push every
		# frame so leaving shield mode restores the weapon's row + palette
		# (the prior single-direction swap left both stale until equip-change).
		var offset = _shield_wep1_frame_offset if _wep1_showing_shield else _wep1_frame_offset
		sprite_layers.wep1_v_offset_pixels = _shield_wep1_v_offset if _wep1_showing_shield else _weapon_wep1_v_offset
		sprite_layers.set_wep1_palette_row(_shield_wep1_palette_row if _wep1_showing_shield else _weapon_wep1_palette_row)
		sprite_layers.load_frame_by_id(SpriteLayer.WEP1, frame + offset)
	else:
		sprite_layers.load_frame_by_id(SpriteLayer.EFF1, frame + _eff1_frame_offset)


func _apply_variant_layer_priority(body_anim: String, anim_frame: int) -> void:
	"""Apply the SetLayerPriority active at anim_frame in body_anim's opcode stream."""
	var animation_set = _unit.animation_set
	if body_anim == "" or not animation_set or not _unit.material:
		return
	var opcodes: Array = animation_set.type1_seq.get(body_anim, [])
	var t := 0
	var active_priority := -1
	for op in opcodes:
		var op_id: int = op.get("op_code_id", 0)
		if op_id == AnimationOpcodes.Op.LOAD_FRAME_WAIT:
			t += op.get("op_code_param_1", 0)
			if t > anim_frame:
				break
		elif op_id == AnimationOpcodes.Op.SET_LAYER_PRIORITY:
			active_priority = int(op.get("op_code_param_0", 0))
	if active_priority < 0:
		return
	var key := str(active_priority)
	if animation_set.layer_priority.has(key):
		var pr: Array = animation_set.layer_priority[key].duplicate()
		var ip := PackedInt32Array()
		for v in pr:
			ip.append(int(v))
		_unit.material.set_shader_parameter("priority", ip)


# -----------------------------------------------------------------------------
# AnimationPlayback Signal Handlers
#
# The body-lead cascade + secondary paints are ONE implementation, connected
# for each PlaybackSet (ADR-0025). Every normal-vs-React difference is carried
# by the bound `PlaybackSet.is_react`: the paint gate (`set.is_react ==
# _react_active`), the shield-vs-weapon-remap branch, and which layers start.
# -----------------------------------------------------------------------------

func _wire_playback_set(set: PlaybackSet) -> void:
	"""Connect one PlaybackSet's cascade signals to the shared handlers (bound to
	the set). Called once per set; the body's state-completion / distort / move
	(on Unit) and the React body's completion are wired separately."""
	if set.body:
		set.body.frame_changed.connect(_on_body_frame_changed)
		set.body.side_effect.connect(_on_set_body_side_effect.bind(set))
	if set.wep1:
		set.wep1.frame_changed.connect(_on_set_wep1_frame_changed.bind(set))
		set.wep1.side_effect.connect(_on_set_wep1_side_effect.bind(set))  # wep1 → eff1
		set.wep1.animation_complete.connect(_on_set_wep1_complete.bind(set))
	if set.eff1:
		set.eff1.frame_changed.connect(_on_set_eff1_frame_changed.bind(set))
		set.eff1.animation_complete.connect(_on_set_eff1_complete.bind(set))
		set.eff1.animation_paused.connect(_on_set_eff1_complete.bind(set))  # EFF1 never holds


func _on_body_frame_changed(_frame_id: int) -> void:
	"""A BODY clock advanced (either set) — repaint the body for the current view.

	frame_id is advisory; _paint_body_variant recomputes the sprite frame from
	the clock's anim_frame and the chosen front/back variant (and defers to the
	React set when `_react_active`), so one handler serves both sets.
	"""
	_paint_body_variant()


func _on_set_body_side_effect(effect_type: int, params: Dictionary, set: PlaybackSet) -> void:
	"""BODY side effect for `set` — the body-lead cascade (start THIS set's WEP1/
	EFF1) and SetLayerPriority. `set.is_react` picks the shield-vs-remap branch."""
	# The cascade is wired at construction (Unit._init), so a not-yet-`_ready` Unit
	# whose clock is pumped could reach here with a null animation_set/material —
	# stay inert until initialized (pre-C2a the signal simply wasn't connected yet).
	if not _unit._initialized or not _unit.animation_set:
		return
	var animation_set = _unit.animation_set
	if effect_type == AnimationOpcodes.SideEffect.QUEUE_SPRITE_ANIM:
		var layer: SpriteLayer = params["layer"]
		var anim_id = params["anim_id"]
		if layer == SpriteLayer.WEP1:
			if set.is_react:
				# React BODY → React WEP1 (shield_block etc.): flag shield display,
				# no weapon remap.
				_wep1_showing_shield = _shield_wep1_frame_offset >= 0
			else:
				# TYPE1 body anims embed Swing WEP1 IDs for melee weapons; remap to
				# the correct category (Poke for polearms, Throw for bags, etc.).
				_wep1_showing_shield = false
				var item_type_id = _unit.get_weapon_item_type_id()
				if item_type_id > 0:
					var remapped = str(WeaponAnimationSelector.remap_wep_anim_id(int(anim_id), item_type_id))
					if RigDebug.iteration() and remapped != anim_id:
						print("[Unit] %s: WEP1 anim remap %s → %s (item_type=%d)" % [_unit.name, anim_id, remapped, item_type_id])
					anim_id = remapped
			set.wep1.start(anim_id, animation_set.wep_seq)
		elif layer == SpriteLayer.EFF1:
			# BODY → EFF1 direct triggers use Ball offset (thrown projectiles like stones)
			_eff1_frame_offset = WeaponAnimationSelector.get_eff1_frame_offset(BALL_ITEM_TYPE_ID)
			if RigDebug.iteration():
				print("[Unit] %s: BODY → EFF1, using Ball offset %d (react=%s)" % [_unit.name, _eff1_frame_offset, set.is_react])
			set.eff1.start(anim_id, animation_set.eff1_seq)
	elif effect_type == AnimationOpcodes.SideEffect.SET_LAYER_PRIORITY:
		var priority_index = int(params["priority"])
		var priority_key = str(priority_index)
		if animation_set.layer_priority.has(priority_key):
			var priority: Array = animation_set.layer_priority[priority_key].duplicate()
			var int_priority := PackedInt32Array()
			for v in priority:
				int_priority.append(int(v))
			_unit.material.set_shader_parameter("priority", int_priority)
			if RigDebug.iteration():
				var readback = _unit.material.get_shader_parameter("priority")
				print("[Unit] %s: SetLayerPriority idx=%d set=%s readback=%s" % [
					_unit.name, priority_index, str(int_priority), str(readback)])
		else:
			push_warning("Unit: Layer priority '%s' not found" % priority_key)


func _on_set_wep1_frame_changed(_frame_id: int, set: PlaybackSet) -> void:
	"""A WEP1 clock advanced — repaint the weapon layer iff this set owns the
	pixels (ADR-0025): the React set paints while `_react_active`, the normal set
	otherwise. The unpainted set's counter keeps advancing so it stays in sync."""
	if set.is_react != _react_active:
		return
	_paint_secondary_variant(set.wep1, SpriteLayer.WEP1)


func _on_set_wep1_side_effect(effect_type: int, params: Dictionary, set: PlaybackSet) -> void:
	"""WEP1 → EFF1 cascade within `set` (wep1 can only trigger eff1, not wep1)."""
	if not _unit._initialized or not _unit.animation_set:
		return
	if effect_type == AnimationOpcodes.SideEffect.QUEUE_SPRITE_ANIM:
		var layer: SpriteLayer = params["layer"]
		var anim_id = params["anim_id"]
		if layer == SpriteLayer.EFF1:
			# WEP1 → EFF1 uses the equipped weapon's offset (weapon trails)
			var item_type_id = _unit.get_weapon_item_type_id()
			_eff1_frame_offset = WeaponAnimationSelector.get_eff1_frame_offset(item_type_id)
			if RigDebug.iteration():
				print("[Unit] %s: WEP1 → EFF1, weapon offset %d (type=%d, react=%s)" % [_unit.name, _eff1_frame_offset, item_type_id, set.is_react])
			set.eff1.start(anim_id, _unit.animation_set.eff1_seq)


func _on_set_wep1_complete(set: PlaybackSet) -> void:
	"""WEP1 completion — disable the layer. The React set only owns the slot
	while `_react_active`, so it defers when react has already ended."""
	if set.is_react and not _react_active:
		return
	_unit.sprite_layers.enable_layer(SpriteLayer.WEP1, false)


func _on_set_eff1_frame_changed(_frame_id: int, set: PlaybackSet) -> void:
	"""An EFF1 clock advanced — repaint the effect layer iff this set owns the
	pixels (same gate as `_on_set_wep1_frame_changed`)."""
	if set.is_react != _react_active:
		return
	_paint_secondary_variant(set.eff1, SpriteLayer.EFF1)


func _on_set_eff1_complete(set: PlaybackSet) -> void:
	"""EFF1 completion (or pause — EFF1 never holds) — disable the layer, iff the
	set owns the slot."""
	if set.is_react and not _react_active:
		return
	_unit.sprite_layers.enable_layer(SpriteLayer.EFF1, false)


# React BODY completion (visual-only reaction overlay). The React BODY's
# frame-changed + side-effect ride the shared _on_body_* handlers (bound to the
# React set); only its completion is React-specific — it ends the react window.

func _on_react_complete() -> void:
	"""Called when react animation completes or is cancelled.

	Returns display control to type1 layer and forces a frame refresh
	to resume showing the current type1 animation. Restores normal
	animation reversion based on current state and camera position.
	"""
	if RigDebug.action():
		print("[%s] React ENDED (ticks_remaining=%d)" % [_unit.name, _react_ticks_remaining])
	_react_active = false
	_react_ticks_remaining = 0
	_react_seq_animation_id = -1  # Clear stored state

	# Stop the entire React set (ADR-0025); painting flips back to the normal
	# set in `_render_camera_variant` below.
	_stop_react_set()

	# Clear shield display flag
	_wep1_showing_shield = false

	# Resume normal display for the current state animation (body + weapon + effect).
	_render_camera_variant()


func _cancel_react_if_active() -> void:
	"""Cancel react animation if active.

	Called when unit transitions to a new intentional state (death, etc.)
	to ensure react doesn't override the new state's display.
	"""
	if RigDebug.iteration():
		print("[%s] _cancel_react_if_active called - _react_active=%s" % [_unit.name, _react_active])
	if _react_active:
		if RigDebug.action():
			print("[%s] React CANCELLED (state change, ticks_remaining=%d)" % [_unit.name, _react_ticks_remaining])
		_react_active = false
		_react_ticks_remaining = 0
		_stop_react_set()


## Stop the entire React set (ADR-0025) — shared by react completion + cancel so
## a later-added React member can't be left live in one path (a stale shield /
## effect frame would then repaint over the resumed normal animation).
func _stop_react_set() -> void:
	if react_playback:
		react_playback.stop()
	if react_wep1_playback:
		react_wep1_playback.stop()
	if react_eff1_playback:
		react_eff1_playback.stop()


## `ReactionType.Type.TAKING_DAMAGE`'s value, written out (#744).
##
## 🔴 THE RIG NEVER BRANCHES ON A REACTION TYPE. It takes the int, emits it back
## through `_unit.reaction_animation_played`, and prints it — the parameter's own
## docstring below says *"for logging"*. So naming `Battle`'s `ReactionType` bought
## a default and two prettier debug strings at the price of three of ADR-0215
## P3a's 27 reaches, and an addon that will not parse without the host's enum.
##
## The number is duplicated, and the duplication is PROVED rather than trusted:
## `tests/UnitDisplayReactionDefaultTest.gd` names both sides and fails if the host
## renumbers `Type`. A rig cannot check that itself — it is exactly the shape a
## host-side contract test exists for.
const REACTION_TAKING_DAMAGE: int = 1

func play_reaction_animation(seq_animation_id: int, reaction_type: int = REACTION_TAKING_DAMAGE, use_timer: bool = true) -> void:
	"""Trigger a React playback set (ADR-0025).

	Activates the React set (react_playback / react_wep1_playback /
	react_eff1_playback) for visual flinch / shield-block / heal-reception.
	The normal set keeps advancing in the background — its gameplay side
	effects (POST_GENERIC_ATTACK trap spawns, sound triggers, projectile
	spawns) still fire — but its pixels go unpainted until react ends.
	When react ends, painting flips back to the normal set; WEP1 / EFF1 cut
	back in sync because their counters rode along.

	Newest-wins overlap (ADR-0025): if a React is already in flight, this
	call replaces it. The previous React set is reset.

	The animation variant (front/back) and reversion are calculated from the
	camera-relative direction, matching how normal animations work:
	- rotated_dir 0 → front variant, no revert
	- rotated_dir 1 → back variant, no revert
	- rotated_dir 2 → back variant, revert
	- rotated_dir 3 → front variant, revert

	Args:
		seq_animation_id: Animation slot ID from the host's ReactionType.get_seq_id() (e.g., 25 for taking_damage)
		reaction_type: Type of reaction, FOR LOGGING ONLY -- an opaque int the rig
			emits back unread. The host's ReactionType.Type numbers it.
	"""
	if RigDebug.iteration():
		print("[%s] play_reaction_animation called - seq_id=%d, type=%s, state=%s, _react_active=%s" % [
			_unit.name, seq_animation_id, reaction_type,
			DisplayActivity.Activity.keys()[_unit.activity], _react_active])

	# Don't start react if current state is locked (DYING, DEAD) - use existing transition system
	if _unit.activity in AnimationStateController.LOCKED_TRANSITIONS:
		if RigDebug.iteration():
			print("[%s] play_reaction_animation skipped - state %s is locked" % [
				_unit.name, DisplayActivity.Activity.keys()[_unit.activity]])
		return

	var animation_set = _unit.animation_set
	if not animation_set:
		push_warning("[Unit] Cannot play reaction - no animation_set")
		return

	# Store reaction state for camera updates
	_react_seq_animation_id = seq_animation_id

	# Run the react clock on the canonical front variant; the render step picks
	# front/back + flip from the current camera (see _paint_body_variant).
	var front_key := str(seq_animation_id * 2)

	if animation_set.type1_seq.has(front_key):
		if react_playback:
			# Newest-wins overlap (ADR-0025): reset the React set's secondary
			# playbacks so a prior react's cascade doesn't bleed into this one.
			# The BODY playback is restarted on the next line.
			if react_wep1_playback:
				react_wep1_playback.stop()
			if react_eff1_playback:
				react_eff1_playback.stop()
			# Clear the WEP1 / EFF1 shader slots — the normal set's frame_changed
			# handlers no-op while `_react_active`, so without this the slots would
			# hold whatever frame the normal set last painted. React's own cascade
			# (e.g., shield_block) re-enables the slot as it paints.
			_unit.sprite_layers.enable_layer(SpriteLayer.WEP1, false)
			_unit.sprite_layers.enable_layer(SpriteLayer.EFF1, false)

			_react_active = true
			_react_ticks_remaining = REACT_DURATION_TICKS if use_timer else 0
			_unit.reaction_animation_played.emit(reaction_type)
			react_playback.start(front_key, animation_set.type1_seq)
			_paint_body_variant()
			if RigDebug.action():
				var cleanup_mode = "%d ticks" % REACT_DURATION_TICKS if use_timer else "REFRESH_TILE"
				print("[%s] React STARTED - seq_id=%d type=%s cleanup=%s" % [
					_unit.name, seq_animation_id, reaction_type, cleanup_mode])
	else:
		# Animation not found - clear stored state and log
		_react_seq_animation_id = -1
		if RigDebug.action():
			# The context dict this call used to pass was `GameLogger.debug`'s third
			# parameter; `RigDebug.log_animation` takes a message and nothing else, so
			# the unit goes INTO the message (#744).
			RigDebug.log_animation("[%s] Reaction animation %d not found, skipping visual reaction"
				% [_unit.name, seq_animation_id * 2])
