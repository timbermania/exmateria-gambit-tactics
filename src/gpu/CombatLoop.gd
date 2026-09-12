class_name CombatLoop
extends Node3D

## The combat Node that owns the whole game-visible battle (ADR-0018, C7).
##
## It owns the GPU simulator / state reader / distance field, the battle setup
## (set_battle_units / set_battle_from_units + gambits), BOTH interpreters with
## [GPUVisualBridge], the effect / projectile / reaction managers, the per-tick
## pump ([method tick] → interpret → apply → projectiles → victory), the
## animation apply ([method _update_unit_animation], [method _start_attack_animation],
## cast-complete / effect-spawn), and the victory check.
##
## It DRIVES the [Unit] nodes a **host** hands it via [method start_battle] and
## emits **one signal per semantic event** so a consumer connects only to what it
## needs. **Composed, not inherited**: a host (the test base, or [GPUArena]) holds
## a CombatLoop and wires its signals; it never subclasses one.
##
## Regression logging: the host owns the [RegressionLogger] and injects it as
## [member _rlog]; the apply pump and managers log through it. The loop itself is
## logging-agnostic — inject a disabled logger (as production does) and it is
## silent. The loop never holds the host's `on_*` assertion hooks or test-config
## dict shapes — those stay host-side, driven by the signals below.

const EffectManager = ExMateriaEffects.EffectManager

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

## `AnimationOpcodes` is `addons/exmateria_sprite_rig`'s now, published on the
## addon's one global name; this aliases it back so every use site below keeps
## the spelling it had (ADR-0211 dec. 4, ADR-0217 dec. 6).
const AnimationOpcodes = ExMateriaSpriteRig.AnimationOpcodes

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell


const GPUBatchSimulatorClass = preload("res://src/gpu/GPUBatchSimulator.gd")
const GPUStateReaderClass = preload("res://src/gpu/GPUStateReader.gd")
const GPUCombatInterpreterClass = preload("res://src/gpu/GPUCombatInterpreter.gd")
const WeaponAnimationSelectorClass = ExMateriaSpriteRig.WeaponAnimationSelector

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const AbilityFamily = ExMateriaAlmanac.AbilityFamily
const JobDatabase = ExMateriaAlmanac.JobDatabase
const ReactionType = ExMateriaAlmanac.ReactionType
const UnitProgression = ExMateriaAlmanac.UnitProgression
const ProjectileManagerClass = preload("res://src/projectiles/ProjectileManager.gd")
const EffectManagerClass = ExMateriaEffects.EffectManager
const AttackSfxResolver = preload("res://src/audio/AttackSfxResolver.gd")
const CinematicManagerClass = preload("res://src/gpu/CinematicManager.gd")

# === Per-event semantic signals (ADR-0018 dec. 9) =============================
# One signal per semantic combat event — production connects only to what it
# needs (death cue / UI / end-screen) instead of a generic firehose.
signal unit_died(unit_index: int)
signal hp_changed(unit_index: int, prev_hp: int, new_hp: int, delta: int)
signal state_changed(unit_index: int, prev_state: int, new_state: int)
signal mp_changed(unit_index: int, prev_mp: int, new_mp: int)
signal stat_changed(unit_index: int, stat_key: String, stat_label: String, prev_value: int, new_value: int)
signal cast_began(unit_index: int, ability_id: int, target: int)
signal action_committed(unit_index: int, ability_id: int, target: int)
signal projectile_fired(unit_index: int)
signal victory(winner: int, team0_alive: int, team1_alive: int)
# Loop-lifecycle (not a combat event): the pump hit max_ticks without a result.
signal timed_out(tick: int)

# Timing windows for hit detection (in GPU ticks)
const MELEE_HIT_WINDOW_TICKS: int = 10
# ADR-0038 binds projectile landing-tick = GPU damage-tick by construction
# (both derive from damage_frame - anim_frame snapshotted at spawn, advanced
# one tick per step_tick). The window is slack over that invariant, not a
# guess. Known edge case: two firers landing on the same target within the
# window — the per-target cache (_last_damage_tick / _last_evade_type) can
# mis-attribute. A fix would need a per-projectile attack id threaded into
# the GPU outcome stamp; not worth the shader change until observed in play.
const PROJECTILE_HIT_WINDOW_TICKS: int = 2

# Effect cleanup polling constants
const EFFECT_INITIAL_WAIT_SEC: float = 0.5
const EFFECT_POLL_INTERVAL_SEC: float = 0.1
const EFFECT_POLL_TIMEOUT: int = 100
const EFFECT_MIN_FRAME_FOR_CLEANUP: int = 50

# PSX head height: 24 PSX units / 28 divisor ≈ 0.857
const HEAD_HEIGHT_PSX: float = 24.0 / 28.0

# GPU flags bit masks
const GPU_FLAGS_DEAD_BIT: int = 1

# Fixed tick rate - decouple simulation from frame rate
const TICK_INTERVAL: float = 1.0 / 60.0  # 60 ticks per second

# Injected by the host: the regression logger and a battle label for log prefixes.
var _rlog: RegressionLogger = null
var battle_name: String = "CombatLoop"
# Overridable presentation seam (ADR-0018): the host supplies the spell-effect
# spawn so a test can wrap it (e.g. to inspect the spawned EffectInstance). A
# Callable injects cleanly — the loop never references the host's type.
var spell_effect_hook: Callable = Callable()
# Overridable presentation seam (ADR-0018), sibling of spell_effect_hook: the
# host supplies the HIT CLOUD spawn so a test can observe it. The hit cloud is
# FFT's non-E###.BIN impact VFX (FUN_8006894c), triggered at the attacker's
# PostGenericAttack (0xDE) frame — see _trigger_physical_reaction. Only that
# opcode-triggered cloud routes through here; the ranged (_on_projectile_landed)
# and deferred-weapon (fire_pending_trap) trap spawns stay direct.
var hit_cloud_hook: Callable = Callable()
# Injection seam for cinematic camera takeover (Phase 4.5). The host (GPUArena)
# sets this to its $PlayerCamera; the test base leaves it null so the cinematic
# spell still plays but the camera stays put. Untyped to avoid coupling the loop
# to the PlayerCamera script class.
var player_camera: Node = null

# Host-tunable pump knobs (mirrors of the old base @exports, set at start_battle).
var ticks_per_frame: int = 1
var max_ticks: int = 6000

## Ceiling on the REAL wall clock a single frame may bank into fixed ticks (W6).
##
## Both drains in `tick()` convert `delta` into whole `TICK_INTERVAL` steps with no
## ceiling, so one long frame schedules more ticks, which makes the next frame longer
## still. That is a design decision, not a bug: bounding it means the simulation runs
## SLOW under load rather than catching up. It is the choice this loop already
## advertises — `playback_scale` below documents that a beat is a function of ticks and
## never of wall clock (ADR-0065), so no rate, including a rate the machine imposes,
## can change an outcome.
##
## Denominated in REAL seconds. `delta` arrives already multiplied by
## `Engine.time_scale`, so the ceiling is multiplied by it too — the same unscaling
## `DebugConfig`'s quit timer does. A deliberate fast-forward is a REQUEST to decouple
## sim time from real time, and it keeps today's throughput unchanged: the four
## `SIM_TIME_SCALE := 40.0` navigator proofs and the 4.0x gambit runner never reach the
## clamp. On the shipped path (`time_scale == 1`) it is fully active.
##
## `playback_scale` multiplies AFTER the clamp, so a 4x playback rate asked for four
## times the sim per real second and still gets it.
##
## ⚠ **Why one second, and not a tight budget.** The ceiling has to sit above every
## frame rate this project NORMALLY runs at, or the guard stops being a guard and
## becomes a behaviour change on the ordinary path — which is the whole reason this
## was a ruling and not a bugfix. Two normal rates are far below the 144 Hz budget:
## the arena measures `tpf: 1.0` at 60 fps, ~59x of headroom here, but an
## agent-launched headful session reports 1-2 fps through a Wayland present block,
## and at time_scale 1 that arrives as a full second of delta per frame. A 0.25 s
## ceiling would have quartered the sim rate of every combat test run that way. One
## second bounds the thing worth bounding — a multi-second stall arriving as one
## enormous delta — and leaves the ordinary path alone.
##
## A host that deliberately hands `tick()` a fat frame raises this (`TurnDirectorTest`
## does, so its 60-tick single-frame arm keeps its stated margin).
var max_catchup_real_s: float = 1.0

## Wall-clock multiplier on the delta this loop drains into fixed ticks — the
## between-turn playback rate (ADR-0239). 1.0 is real time; 4.0 runs the same
## ticks four times faster. It scales how fast you WATCH the sim, never what the
## sim does: `_tick_accumulator` still drains in whole `TICK_INTERVAL` steps and
## every outcome is a function of tick count, so no rate can change a result
## (ADR-0065's principle — a beat is a function of ticks, not wall clock).
## `TurnDirector` owns the tunable; this is only the multiply.
var playback_scale: float = 1.0

## Optional per-tick stop predicate, consulted at the END of each tick-loop
## iteration (ADR-0239). Returning true BREAKS the frame's tick loop, leaving the
## accumulator remainder intact, so the world halts on the exact tick the
## predicate fired rather than at the next frame boundary — the frame runs ~16
## ticks here and a turn is ~13, so a frame-granular stop would routinely overrun
## a whole turn. Called with the three lean columns `_read_tick_columns` already
## has in hand — turn meter, flags, and state — so the gate costs no readback of
## its own. STATE is there for the settled test: a gate that freezes a unit
## mid-movement-step lands the world on a taker whose sprite is a tile short of the
## logical cell every reader places it on, because logical position is the
## DESTINATION for a whole step.
##
## `CombatLoop` supplies the hook and the granularity; the POLICY is the
## caller's, and a gate that wants to freeze does so from inside its own call
## (synchronously, before any further tick) rather than relying on node order.
var turn_gate: Callable = Callable()

# When the GPU reports a unit has settled into the battle-won state
# (LOGICAL_ACTIVITY_CELEBRATING — the handshake stage_victory keys on), this
# picks what the unit RENDERS. `true` = the made-up victory dance (ADR-0026, the
# arena's "for fun" behaviour); `false` (default, "faithful") = the unit returns
# to its normal HP-appropriate pose (see `settled_victory_activity`). The GPU
# victory handshake is decoupled from this — the sim declares the winner either
# way; only the on-screen pose changes. Hosts that want the dance (GPUArena, the
# ADR-0026 combat-suite invariant) opt in by setting this true.
var celebrate_on_victory: bool = false

## SETTLE BEFORE VICTORY: hold the win until every unit has finished what it was
## visibly doing, instead of declaring it over a unit mid-step.
##
## The kernel already had the right handshake and the wrong "settled". `stage_victory`
## reports a win only when every survivor is CELEBRATING, but `stage_compute`'s #897
## flip writes CELEBRATING over a unit mid-step BY FIAT — and a state that leaves the
## movement set is [GPUVisualBridge]'s cue to drop the visualizer and snap the sprite
## to the GPU tile, which is the DESTINATION of the abandoned step. So the sprite
## teleports one tick BEFORE [signal victory] is emitted, which is why no host-side
## gate on that signal can prevent it: by the time a host hears, it has happened.
##
## Setting this arms `settle_brake_battle`, which buys the flip back for a unit that
## is WALKING / WALKING_TO_CAST / APPROACHING / ACTING and brakes it so it starts
## nothing new. It finishes its step or its swing, drains into IDLE, and is flipped
## there — on its own tile. The win is reported when the LAST one lands, so the whole
## handback (camera return, victory beat, pan) waits without any host knowing it did.
##
## OFF BY DEFAULT and armed per battle: a host that does not set it runs the flip
## exactly as before. MEASURED at Gariland: the win is reported ~0.5 s later than it
## used to be, that being how long the last walker had left to walk.
##
## See [member settle_backstop_seconds] for what happens if settling ever stalls.
var settle_before_victory: bool = false:
	set(value):
		if settle_before_victory == value:
			return
		settle_before_victory = value
		_settle_expired = false
		_settle_wait = 0.0
		_apply_settle_brake()

## How long the loop will wait for the last unit to settle before giving up on it.
##
## A BACKSTOP, NOT A FEEL KNOB. Termination is meant to come from the brake — an
## awaited unit finishes what it is on, cannot start another, and drains into the one
## state the flip catches — so this firing means the brake is broken, and the warning
## it prints (naming the units and their states) is the whole point of it. Gariland's
## measured worst case is 0.65 s, so this is generous by 3x. On expiry the brake is
## disarmed and the very next tick flips everyone, i.e. the pre-settle behaviour.
var settle_backstop_seconds: float = 2.0

var _settle_wait: float = 0.0
var _settle_expired: bool = false

var gpu_simulator = null
var gpu_state_reader = null
var distance_field: DistanceFieldGenerator = null
var lattice: Lattice = null
var map: Node3D = null

var units: Array = []
var team0_units: Array = []
var team1_units: Array = []

## GPU per-battle unit capacity (buffer size AND the team split midpoint — team0
## fills [0, units_per_battle/2), team1 [units_per_battle/2, …)). Default 8 = 4v4, the
## roster arena. A host with more/asymmetric units (the ENTD navigator: Orbonne 9v7)
## sets this so team0.size() == units_per_battle/2, keeping the GPU slots contiguous
## with CombatLoop's `team0 + team1` global order.
var units_per_battle: int = 8

## Battles this loop's simulator allocates, INCLUDING the live one at slot 0.
## Zero (the default) means one battle — the shape every host in the tree has had
## since the simulator was written, and the shape every host except a rollout host
## still wants.
##
## §7's enemy AI needs `K * M` slots to fill with candidate gambit edits, and it
## fills battle 0 among them because `step_tick` dispatches over the whole batch
## anyway — see `RolloutHarness`. Set this BEFORE `setup_gpu_simulator`; the
## buffers are sized once.
##
## 🔴 NO DEFAULT FLEET, DELIBERATELY. ADR-0237 dec. 8: a discovered size ceiling
## belongs in an ADR-0068 `static var` published by whoever wires the AI (#897),
## and shipping a number here now would ship a default nobody chose to every host
## that never runs a rollout — paying its VRAM on a box where a lost Vulkan device
## is how the suite fails.
var rollout_fleet_size: int = 0

var combat_active: bool = false:
	set(value):
		if combat_active == value:
			return
		combat_active = value
		# ADR-0037 dec. 3: drive the combat_visuals group's process_mode in
		# lockstep with the freeze predicate — every axis refreshes at its edge.
		_refresh_combat_visuals_freeze()
var victory_achieved: bool = false:
	set(value):
		if victory_achieved == value:
			return
		victory_achieved = value
		_refresh_combat_visuals_freeze()
var current_tick: int = 0

# Visual tracking (shared via GPUVisualBridge)
var _visual_bridge: GPUVisualBridge = GPUVisualBridge.new()
var _all_states: Array = []  # Current frame GPU states (set in _check_state_changes)
# Per-battle header snapshot (tick, result, flags, seed). Refreshed alongside
# _all_states each tick. The cinematic-spell header pair retired in #118 in
# favor of per-unit U_CINEMATIC_TIMER (read off _all_states[i].cinematic_timer).
# ADR-0031: no CPU flag, read it off the snapshot.
var _battle_state: Dictionary = {}
# ADR-0018: the pure combat interpreter owns per-frame snapshot->event detection
# and ALL the cross-frame sample buffers (_prev_hp/state/mp/pos/anim_flags/stats/
# casting); _check_state_changes is now interpret->apply.
var _combat_interp = GPUCombatInterpreterClass.new()
var _last_damage_tick: Dictionary = {}  # target_idx → tick when last damaged (for reaction hit detection)
var _hp_before_last_damage: Dictionary = {}  # target_idx → HP before last damage (for projectile hit detection)
var _last_evade_type: Dictionary = {}  # target_idx → last non-zero evade_type from GPU roll_evasion

# Lean per-tick GPU columns (perf). The tick loop reads only a few unit fields per
# tick; building the full 99-field _all_states snapshot every tick cost ~0.6ms/tick
# in dict construction. Instead we pull just the hot columns off the version-cached
# region (one shared readback/tick, no dict build) and refresh the full _all_states
# ONCE per frame after the loop. _tick_cinematic_timer / _tick_paused back the
# cinematic edge + anim-freeze reads that used to go through _all_states.
var _tick_cinematic_timer: PackedInt32Array = PackedInt32Array()
var _tick_paused: PackedInt32Array = PackedInt32Array()
# The turn gate's two inputs (ADR-0239). Same version-cached region as the five
# above, so they are a read, not a round trip. Republished every tick because the
# gate is consulted every tick.
var _tick_turn_meter: PackedInt32Array = PackedInt32Array()
var _tick_flags: PackedInt32Array = PackedInt32Array()
# The gate's third input (the turn brake). The state column is read below anyway,
# for the lean state-change edge — publishing it costs the assignment and no
# readback at all, which is why the settled test is affordable per tick.
var _tick_state: PackedInt32Array = PackedInt32Array()
# Intra-unit field offsets into the GPU unit record (from the generated map, so
# they can't drift from the shader layout).
var _col_hp: int = GPUBatchSimulator.SNAPSHOT_FIELDS["hp"]
var _col_evade_type: int = GPUBatchSimulator.SNAPSHOT_FIELDS["evade_type"]
var _col_cinematic_timer: int = GPUBatchSimulator.SNAPSHOT_FIELDS["cinematic_timer"]
var _col_paused: int = GPUBatchSimulator.SNAPSHOT_FIELDS["paused"]
var _col_state: int = GPUBatchSimulator.SNAPSHOT_FIELDS["state"]
var _col_turn_meter: int = GPUBatchSimulator.SNAPSHOT_FIELDS["turn_meter"]
var _col_flags: int = GPUBatchSimulator.SNAPSHOT_FIELDS["flags"]
## Last state value this loop has OBSERVED per unit, mirrored off the lean per-tick column.
## Distinct from the interpreter's `_prev_state` (which is what it has EMITTED). The two
## diverge exactly when a unit enters and leaves a state inside one frame's tick batch —
## see `_state_edge_this_tick`.
var _tick_prev_state: PackedInt32Array = PackedInt32Array()
## The three spans `edge` aggregates, timed separately (W7/R26 — `edge` was 94 ms of a
## 132 ms `GPU` bucket at 96 units and the report could not say which call owned it).
var _perf_chk_times: Array = []
var _perf_cine_times: Array = []
var _perf_proj_times: Array = []
## True when the lean state column moved on THIS tick, so the frame-end snapshot would
## coalesce a transition away if we waited for it.
var _state_edge_this_tick: bool = false
## HOW MANY units' state moved on this tick (W9). `_state_edge_this_tick` is exactly
## `_state_movers_this_tick > 0` — the bool is what the gate reads, the count is what
## SIZES the fix: a gate that opens because one unit of 80 moved still pays for all 80.
var _state_movers_this_tick: int = 0
## W9's decomposition. `chk` is reported per FRAME, which is the product of three factors
## moving together (per-call cost x gate-open rate x ticks per frame) and no counter
## separated them. These two do: opens per frame, and movers summed over those opens.
var _perf_chk_calls: Array[int] = []
var _perf_chk_movers: Array[int] = []
## What ONE `_check_state_changes` is made of, in usec over a report interval: the
## 39-field snapshot BUILD, the interpreter's detection pass, and the apply pump's side
## effects. Index 0 is the per-FRAME call after the tick loop, index 1 the gated per-TICK
## call — not the same call twice: the gated one lands on a fresh `_battle_version`, so it
## pays a cold build and sees every delta since the last call, while the per-frame one
## usually finds the cache warm and nothing moved. R27 measured apply at 75-80% of the
## gated call at every cast size, which is why the split below exists at all.
var _chk_build_us: Array[int] = [0, 0]
var _chk_interp_us: Array[int] = [0, 0]
var _chk_apply_us: Array[int] = [0, 0]
var _chk_events: Array[int] = [0, 0]
var _chk_all_calls: Array[int] = [0, 0]
## Apply-pump cost and count per EventKind (9 kinds), summed over a report interval.
## `apply` is ~75-80% of a gated call at every cast size, so the bucket that names a
## function is the HANDLER, not the call.
var _chk_ev_us: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var _chk_ev_n: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
## `ActivityTranslator.translate` cost per `_update_unit_animation` call. Slot [0] held the
## full-snapshot fetch this function used to make per event; W12/#934 deleted the fetch.
var _ua_us: Array[int] = [0, 0]
var _ua_n: int = 0
## Inside `_start_attack_animation` (the ACTING routing, and R27's cliff): [0] snapshot +
## vertical angle, [1] unit.attack(), [2] the swing-SFX slug resolve, [3] the SfxRouter
## play. [3] is the one that grows — 0.3 ms at the shipped cast, 12+ ms once the sound
## engine is carrying a hundred live sessions.
var _atk_us: Array[int] = [0, 0, 0, 0]
var _atk_n: int = 0
# W11 step 1 — previous sample of ExMateriaEffectSfx.audition_split_stats(). The
# engine's counters are CUMULATIVE (it has no notion of this window), so the
# per-window split is a diff taken here.
var _sfx_split_prev: Dictionary = {}

# Cast animation coordination (NOT detection — that's the interpreter's CAST_STEP_ID
# dedup): true while a cast animation plays, cleared by the animation-complete/paused
# signal so _update_unit_animation doesn't cut the cast short.
var _spell_cast_active: Dictionary = {}  # unit_idx -> bool

# Composition managers (initialized in start_battle after GPU battle init).
# Reaction routing is inlined as _trigger_*_reaction / _on_ability_react /
# _on_refresh_tile below — see "Reaction routing" section.
var projectile_manager: ProjectileManager
var effect_manager: EffectManager
# Sibling manager — owns the cinematic-spell EffectInstance lifecycle, edge
# detection on the GPU's per-unit cinematic_timer (#118 lifted the single-
# cinematic invariant; CinematicManager picks the spotlight caster), and
# PlayerCamera takeover. See ADR-0018 cluster + ADR-0025; ADR-0037 dec. 7.
var cinematic_manager: CinematicManager

# Debug-only cinematic-spell instrumentation. Constructed lazily the first time
# iteration_debug_enabled is observed true; null otherwise so production carries
# zero overhead. Probe is a RefCounted, so dropping the ref frees it.
var _debug_probe: CinematicDebugProbe = null

# Debug counters for animation/projectile tracking
var _debug_animation_starts: Dictionary = {}  # unit_idx -> count
var _debug_projectile_spawns: Dictionary = {}  # unit_idx -> count
var _debug_action_start_tick: Dictionary = {}  # unit_idx -> tick when ACTING started

var _tick_accumulator: float = 0.0

## The fraction of one TICK_INTERVAL banked since the last logical tick, in [0, 1] — i.e.
## `_tick_accumulator` expressed as a share of a tick, refreshed once per FRAME at the
## visual seam below. Read-only to everyone including this file: it is a VIEW of the
## accumulator, never a second copy of it.
##
## It exists because the render clock is not phase-locked to the tick (#1206). Whatever the
## display does, a rendered frame banks a fractional number of ticks, and the ones that bank
## less than a whole tick used to redraw every unit bit-identically. On this box's 144 Hz
## panel that is 58% of frames — a permanent 60 Hz strobe over a 144 Hz presentation. This
## is the quantity that lets the visual path draw between two ticks instead of on one.
var tick_alpha: float = 0.0

# Frame timing diagnostics
var _perf_gpu_tick_times: Array[float] = []  # ms per FRAME in the whole tick while-loop
# The `gpu` bucket above is the whole tick loop, not the GPU. These four split it, so a
# report says WHICH of its four jobs cost the frame. Accumulated in usec per frame and
# flushed with the rest; the four sum to `gpu` minus the loop's own overhead.
var _perf_step_times: Array[float] = []  # ms/frame in gpu_simulator.step_tick (submit+sync)
var _perf_cols_times: Array[float] = []  # ms/frame in _read_tick_columns (lean readback)
var _perf_anim_times: Array[float] = []  # ms/frame in the per-unit advance_frame loop
var _perf_edge_times: Array[float] = []  # ms/frame in per-tick state edge + cinematic + projectile
var _perf_state_check_times: Array[float] = []  # ms per _check_state_changes
var _perf_visual_update_times: Array[float] = []  # ms per _update_visual_positions
var _perf_total_frame_times: Array[float] = []  # ms total tick() time
var _perf_frame_deltas: Array[float] = []  # actual delta between frames
var _perf_ticks_per_frame: Array[int] = []  # how many ticks ran each frame
var _perf_report_interval: float = 3.0  # seconds between reports
var _perf_report_timer: float = 0.0
var _perf_report_count: int = 0

# Thrash detection tracking
var _prev_thrash_flag: Dictionary = {}  # unit_idx -> previous thrash flag (0 or 1)
var _last_thrash_log_tick: Dictionary = {}  # unit_idx -> tick when last thrash was logged


## The loop's label for log prefixes. The managers read it via `_base.get_test_name()`.
func get_test_name() -> String:
	return battle_name


# === Setup ====================================================================
# Split so a host that drives the GPU directly (the determinism harness) can
# stand up the simulator without running the pump.

func setup_distance_field() -> void:
	print("[%s] Generating distance field..." % battle_name)
	distance_field = DistanceFieldGenerator.new()
	distance_field.generate(lattice, 3)


## Give the GPU simulator's local RenderingDevice back when this node leaves the tree.
##
## `GPUBatchSimulator.cleanup()` had ZERO CALLERS, so every battle leaked its device —
## and a live local RenderingDevice at process exit is what makes 64 of the suite's
## tests dump core (#471). At shutdown `Main::cleanup -> finalize_display ->
## ~RenderingContextDriverVulkan -> vkDestroyInstance` dlcloses the NVIDIA ICD while the
## device is still open, a destructor inside libnvidia-glcore segfaults, and Godot's
## crash handler turns that SIGSEGV into an abort — `dumped core`, exit 134, AFTER the
## test has already asserted and printed its verdict.
##
## `_exit_tree` is the right seam and PREDELETE is not: a RefCounted's script instance is
## already coming apart by then and the call out to `cleanup()` fails outright (measured).
## Here the simulator is still a whole object and the tree is still standing.
##
## It is not only a test fix. `NavigatorMain:791` `queue_free()`s the loop when a battle
## ENDS, so a campaign was leaking one local RenderingDevice per battle for as long as the
## process lived. That path now returns it.
##
## `_exit_tree` also fires on a REPARENT, which would leave the simulator uninitialised.
## No caller does that today — the four `add_child(combat_loop)` sites (GPUArena,
## NavigatorMain, GPUCombatTestBase, GambitScenarioRunner) each build a loop and never
## move it — so this is a note for whoever adds the fifth, not a live hazard.
func _exit_tree() -> void:
	if gpu_simulator:
		gpu_simulator.cleanup()


func setup_gpu_simulator() -> void:
	if not distance_field:
		push_error("[%s] No distance field" % battle_name)
		return

	print("[%s] Initializing GPU simulator..." % battle_name)
	gpu_simulator = GPUBatchSimulatorClass.new()

	if not gpu_simulator.initialize(lattice, distance_field, maxi(1, rollout_fleet_size), units_per_battle):
		# Give the device back FIRST, then drop the reference. Four of initialize()'s
		# five `return false` paths are reached AFTER the local device was created
		# (shader load, buffer creation, uniform set), so nulling without cleanup()
		# would leak exactly the device #471 went to the trouble of returning.
		# cleanup() is null-safe, so the one pre-device path is fine too.
		gpu_simulator.cleanup()
		# Then drop it. `gpu_simulator` is assigned above BEFORE initialize() runs, so
		# leaving the half-built object in place lets every downstream
		# `if not gpu_simulator:` guard in this file pass and the battle proceed on a
		# simulator that never came up (#430).
		gpu_simulator = null
		push_error("[%s] GPU simulator init failed" % battle_name)
		return

	gpu_state_reader = GPUStateReaderClass.new()
	print("[%s] GPU simulator ready" % battle_name)


## Start a battle. The host hands the loop the live [Unit] nodes (split by team),
## a per-unit gambit array (global-index → encoded gambits), the terrain / map,
## and a seed. `gpu_spec` is the optional battle spec (per-unit GPU config dicts,
## the [code]_build_gpu_config[/code] output) — when present the loop configures
## from it (the config-driven test host); when absent it reads the live Unit nodes
## (the roster-driven arena). Either way `start_battle` speaks Unit nodes + a spec,
## never test dict shapes.
func start_battle(p_team0_units: Array, p_team1_units: Array, p_gambits: Array,
		p_lattice: Lattice, p_map: Node3D, p_seed: int,
		p_gpu_spec: Dictionary = {}) -> void:
	# Boot the simulator (units loaded, idle) then arm combat gambits + go live.
	# The two halves stay split because `NavigatorMain` still uses them separately:
	# it boots on the walk's units and arms only at its own go-live.
	boot_battle(p_team0_units, p_team1_units, p_lattice, p_map, p_seed, p_gpu_spec)
	if not gpu_simulator:
		return
	arm_combat_gambits(p_gambits)


## Boot the simulator without arming combat gambits: load units into the GPU
## battle buffer (on their current logical tiles), build the distance field, wire
## managers + animation signals, seed the interpreter. Units idle (empty gambit
## set) until [code]arm_combat_gambits[/code]. This is the "boot" half of the
## ADR-0042 start_battle split, which OUTLIVES the deployment march ADR-0042 built it
## for (ADR-0258): `NavigatorMain` boots here and arms at its own go-live.
func boot_battle(p_team0_units: Array, p_team1_units: Array,
		p_lattice: Lattice, p_map: Node3D, p_seed: int,
		p_gpu_spec: Dictionary = {}) -> void:
	lattice = p_lattice
	map = p_map
	team0_units = p_team0_units
	team1_units = p_team1_units
	units = team0_units + team1_units

	if gpu_simulator == null:
		setup_distance_field()
		setup_gpu_simulator()
	if not gpu_simulator:
		push_error("[%s] boot_battle: no GPU simulator" % battle_name)
		return

	if p_gpu_spec.has("team0"):
		gpu_simulator.set_battle_units(0, p_gpu_spec["team0"], p_gpu_spec["team1"], p_seed)
	else:
		gpu_simulator.set_battle_from_units(0, team0_units, team1_units, p_seed)

	# Idle every unit until gambits are armed.
	for i in range(units.size()):
		gpu_simulator.set_unit_gambits(0, i, [])

	gpu_state_reader.initialize(gpu_simulator, 0)

	# Wire each unit's animation signals to the loop's apply (the loop drives the
	# Unit nodes; the host merely built them). `bind(i)` tags the global index.
	for i in range(units.size()):
		var unit = units[i]
		unit.activity_complete.connect(_on_unit_animation_complete.bind(i))
		# Facade forwards (issue #144): the BODY playback lives on `unit.display`;
		# Unit re-emits its pause / side-effect so the loop names Unit, not display.
		unit.body_paused.connect(_on_unit_animation_paused.bind(i))
		unit.body_side_effect.connect(_on_unit_type1_side_effect.bind(i))

	# Initialize visual tracking
	for i in range(units.size()):
		var cell: Vector3i = units[i].movement_component.current_cell
		if cell != TerrainCell.NONE and lattice != null:
			_visual_bridge.init_unit_tracking(i, lattice.world_position_at(cell))

	# Seed the interpreter from the initial states so its first interpret()
	# compares against them (ADR-0018).
	var states = gpu_state_reader.get_all_unit_states()
	for i in range(states.size()):
		_combat_interp.seed_unit(i, states[i])

	# The flag can be set before there is a simulator to write it to (a host that
	# configures the loop and boots the battle later), so the arm is re-applied here
	# rather than only in the setter — the same reason `TurnDirector._apply_brake` is
	# idempotent and re-run.
	_apply_settle_brake()

	print("[%s] GPU battle configured with %d units\n" % [battle_name, units.size()])
	_log_initial_state()

	_initialize_managers()


## Arm each unit's real combat gambits (global-index → encoded gambits). The
## "go live" half of the ADR-0042 split: called by start_battle immediately, or by
## `NavigatorMain` at its own go-live after an earlier `boot_battle`.
func arm_combat_gambits(p_gambits: Array) -> void:
	if not gpu_simulator:
		return
	# 🔴 THE LOOP WALKS `units` AND INDEXES `p_gambits`, so a caller whose two arrays describe
	# DIFFERENT battles used to surface as `Out of bounds get index '2' (on base: 'Array')`
	# three frames deep in a helper — an error that names neither the caller nor the mismatch,
	# and which cost two sessions to attribute. It is a CALLER bug every time: `p_gambits` is
	# documented as "global-index → encoded gambits", so its length is a claim about `units`.
	#
	# Reported and ARMED NOTHING, rather than clamped to the shorter of the two. A clamp would
	# leave the tail of the roster fighting with an empty gambit set — units that stand there
	# doing nothing, or fall through to ADR-0048's safety net — which is a battle nobody asked
	# for, running under a silent partial arm. That is the productive failure ADR-0275 dec. 10
	# rejects, arriving in the arming seam: the run continues and its verdicts describe an
	# experiment that was never set up.
	if p_gambits.size() != units.size():
		push_error(("[%s] arm_combat_gambits: %d gambit set(s) for %d unit(s) — the two describe "
			% [battle_name, p_gambits.size(), units.size()])
			+ "different battles, so NOTHING was armed. The usual cause is a host that re-booted "
			+ "while a previous boot was still awaiting its unit spawns; see "
			+ "`GambitLabScene._boot`'s generation guard for the shape of the fix.")
		return
	for i in range(units.size()):
		gpu_simulator.set_unit_gambits(0, i, p_gambits[i])


func _initialize_managers():
	projectile_manager = ProjectileManagerClass.new(self)
	effect_manager = EffectManagerClass.new(self)
	cinematic_manager = CinematicManagerClass.new(self)
	projectile_manager.projectile_landed.connect(_on_projectile_landed)
	effect_manager.ability_react_triggered.connect(_on_ability_react)
	effect_manager.hit_reaction_triggered.connect(_on_hit_reaction)
	effect_manager.refresh_tile_triggered.connect(_on_refresh_tile)
	cinematic_manager.cinematic_began.connect(_on_cinematic_manager_began)
	cinematic_manager.cinematic_ended.connect(_on_cinematic_manager_ended)
	# Initialize combat_visuals members that spawn mid-freeze (e.g. the {92}
	# crystal billboard) so they don't animate until the next transition refresh.
	var tree := get_tree()
	if tree and not tree.node_added.is_connected(_on_scene_node_added):
		tree.node_added.connect(_on_scene_node_added)


# === Pump =====================================================================
# The host's _process calls tick(delta); the loop has no _process of its own, so
# the host stays the single driver (a subclass `super._process(delta)` still
# pumps exactly once).

func tick(delta: float) -> void:
	if not gpu_simulator:
		return

	# W6 — bound the catch-up, at the ONE place both drains draw from. Clamping the
	# delta rather than capping the while-loop's iterations is what keeps ADR-0239
	# intact: the turn gate breaks out mid-drain and KEEPS the accumulator remainder
	# on purpose, so a post-loop "throw the excess away" would silently destroy that
	# seamless resume. With the delta bounded, each drain still runs to completion and
	# no frame can inherit debt from the last one.
	var _catchup_ceiling: float = max_catchup_real_s * maxf(Engine.time_scale, 0.0001)
	var capped_delta: float = minf(delta, _catchup_ceiling)

	# After victory, keep animations ticking but skip GPU/state processing
	if victory_achieved:
		_tick_accumulator += capped_delta
		while _tick_accumulator >= TICK_INTERVAL:
			_tick_accumulator -= TICK_INTERVAL
			for i in range(units.size()):
				var unit = units[i]
				if not is_instance_valid(unit):
					continue
				var speed = _get_unit_anim_speed(i)
				# The post-victory freeze advances both sets at the same repeat
				# count (its long-standing cadence — unlike the combat branch).
				unit.advance_frame(speed, speed)
			# ADR-0038: projectiles mid-flight at the moment of victory finish
			# naturally per ADR-0037 dec. 8 (post-victory does not freeze). Pump the manager so
			# their landings emit projectile_landed + queue_free; without
			# this, landed visuals would sit at end_pos forever.
			if projectile_manager:
				projectile_manager.update(current_tick, _all_states)
		return

	# ADR-0258: `combat_active` is the whole gate again. ADR-0042 had widened it to
	# `combat_active or deploy_active` so the deployment march could step the sim with
	# move-only gambits outside combat; the march is retired and nothing else ever set
	# that axis, so the sim ticks in combat and at no other time.
	if not combat_active or not projectile_manager:
		return

	var frame_start = Time.get_ticks_usec()

	# Accumulate time and run fixed-rate ticks. `playback_scale` is the between-turn
	# playback rate (ADR-0239): it changes how much wall clock one tick costs, never
	# how many ticks a stretch is, because the drain below is in whole TICK_INTERVAL
	# steps and every outcome downstream is a function of `current_tick`. Scaled
	# HERE and not at the top of the function so the post-victory freeze above
	# keeps real time — it is not a between-turn stretch.
	_tick_accumulator += capped_delta * playback_scale
	var ticks_this_frame = 0

	var gpu_start = Time.get_ticks_usec()
	var step_us: int = 0
	var cols_us: int = 0
	var anim_us: int = 0
	var edge_us: int = 0
	# `edge` is three calls, and at scale they do NOT cost the same (W7/R26). Split
	# them so the bucket names a function rather than a span: `chk` is the gated
	# `_check_state_changes` (the W1 snapshot, per TICK when the gate opens), `cine`
	# the cinematic edge scan, `proj` the projectile advance.
	var chk_us: int = 0
	var cine_us: int = 0
	var proj_us: int = 0
	var chk_calls: int = 0
	var chk_movers: int = 0
	var _t0: int = 0
	var _t1: int = 0
	while _tick_accumulator >= TICK_INTERVAL:
		_tick_accumulator -= TICK_INTERVAL
		_t0 = Time.get_ticks_usec()
		gpu_simulator.step_tick(1)
		step_us += Time.get_ticks_usec() - _t0
		current_tick += 1
		if _rlog:
			_rlog.current_tick = current_tick
		ticks_this_frame += 1
		# Quick damage detection: read GPU HP right after step_tick so
		# PostGenericAttack (in advance_tick below) can detect hits via _last_damage_tick.
		# Without this, _last_damage_tick is only set in _check_state_changes (after the
		# tick loop), so PostGenericAttack always sees stale data.
		_t0 = Time.get_ticks_usec()
		_read_tick_columns()
		cols_us += Time.get_ticks_usec() - _t0
		# EDGE-TRIGGERED state observation (#93). `_check_state_changes` normally runs once
		# per FRAME, after this loop — but this loop advances ~16 ticks per frame at the 15 fps
		# these combat scenes actually run at, so any state a unit ENTERS AND LEAVES inside one
		# batch is coalesced away and never emitted. The interpreter's own comment records the
		# symptom ("STATE_CHANGED gets coalesced when ACTING -> IDLE -> ACTING happens within
		# one host frame"). That is not only a test problem: LOGICAL_ACTIVITY_AWAITING_IMPACT is
		# the projectile-flight pose, so a missed edge means the firer never plays it on screen.
		#
		# The perf note on _read_tick_columns stands — we do NOT build the 99-field snapshot
		# every tick. We read one extra lean column (same version-cached region as HP/evade) and
		# pay for a full check ONLY on the ticks where a state actually moved, which is exactly
		# when the frame-end sample would have lost it. Steady-state cost is one column read.
		_t0 = Time.get_ticks_usec()
		_t1 = _t0
		if _state_edge_this_tick:
			chk_calls += 1
			chk_movers += _state_movers_this_tick
			_check_state_changes(true)
		chk_us += Time.get_ticks_usec() - _t1
		_t1 = Time.get_ticks_usec()
		# Cinematic edge detection runs after the snapshot refresh so handlers
		# (camera takeover / EffectInstance spawn) see this tick's GPU state.
		cinematic_manager.update_edge(current_tick)
		cine_us += Time.get_ticks_usec() - _t1
		_t1 = Time.get_ticks_usec()
		# ADR-0038: advance every projectile by one tick so flight stays
		# tick-locked with the GPU damage tick at any `Engine.time_scale`
		# (tests use 4.0x — driving from `_process(delta)` instead would
		# miss this lock-step). Dispatch is deferred to the
		# `projectile_manager.update()` call below the while-loop so
		# `_last_damage_tick` has settled across this whole frame's GPU
		# damage writes before the hit heuristic reads it.
		projectile_manager.advance_one_tick()
		proj_us += Time.get_ticks_usec() - _t1
		edge_us += Time.get_ticks_usec() - _t0
		# Advance all unit animations in lockstep with GPU ticks
		# Activity speed multiplier determines how many times to advance per tick
		_t0 = Time.get_ticks_usec()
		for i in range(units.size()):
			var unit = units[i]
			if not is_instance_valid(unit):
				continue
			var speed = _get_unit_anim_speed(i)
			# Normal set scales with the unit's gameplay anim speed; the React set
			# advances once per IRQ (authored cadence, ADR-0025: React is display-only).
			# Through Unit so the current view is pushed before the clock repaints (C2b).
			# advance_frame also decrements the melee react countdown and ends the
			# window at 0 — display owns it now (issue #144 C3a).
			unit.advance_frame(speed, 1)
		anim_us += Time.get_ticks_usec() - _t0
		# The turn gate (ADR-0239), LAST in the body: this tick is fully applied —
		# state edges, cinematic, projectiles, animation — before the world is
		# allowed to stop, so a frozen frame is a coherent one. Breaking (not
		# returning) leaves the rest of this frame's per-frame work to run and
		# keeps the accumulator remainder, which is what makes the resume seamless.
		if turn_gate.is_valid() and turn_gate.call(_tick_turn_meter, _tick_flags, _tick_state):
			break
	var gpu_ms = (Time.get_ticks_usec() - gpu_start) / 1000.0

	# Per-frame cinematic camera apply (Phase 4.5). Runs at host-process cadence
	# rather than per-IRQ so the camera advances at visual frame rate.
	cinematic_manager.apply_camera()

	if DebugConfig.iteration_debug_enabled:
		if _debug_probe == null:
			_debug_probe = CinematicDebugProbe.new()
		# _all_states / _battle_state are no longer refreshed each tick (perf: the
		# tick loop reads lean columns). Refresh here — debug-gated — so the probe
		# sees this frame's full snapshot.
		refresh_all_states_now()
		_battle_state = gpu_state_reader.get_battle_state()
		_debug_probe.probe(_battle_state, _all_states, units,
			cinematic_manager.prev_caster_idx(), current_tick,
			Callable(self, "_get_unit_anim_speed"), get_tree())

	# Dispatch any projectiles that finished flight during this frame's
	# while-loop ticks. Runs after the loop so `_last_damage_tick` reflects
	# all of this frame's GPU damage writes before the hit heuristic reads
	# it (ADR-0038).
	projectile_manager.update(current_tick, _all_states)

	var state_start = Time.get_ticks_usec()
	# Then check state changes - catches HP changes from both GPU and projectile heals
	_check_state_changes()
	# Live bit-edge for Reraise / Phoenix Down revives (issue #108). The
	# interpreter only emits DIED, so the reverse transition has to be observed
	# here against the snapshot _check_state_changes just refreshed.
	_handle_revives()
	var state_ms = (Time.get_ticks_usec() - state_start) / 1000.0

	var visual_start = Time.get_ticks_usec()
	# Lean 39-field snapshot (W1). Shares a version cache with _check_state_changes
	# above, so whichever of the two runs first this frame pays the build and the
	# other is free — the same sharing the full snapshot had, one third the fields.
	var vis_states = gpu_state_reader.get_all_unit_states_hot()
	# 🔴 A READ, NEVER A WRITE OR A RESET. The drain above deliberately leaves the remainder
	# in place — the ADR-0239 turn gate breaks out MID-drain and keeps it so the next frame
	# resumes seamlessly — so spending it here has to mean observing it. Clamped rather than
	# assumed in range for exactly that reason: a gate that broke out early can leave more
	# than one whole tick banked, and an alpha above 1 would run a unit past the tick the sim
	# is on. `playback_scale` already multiplied the delta going IN (ADR-0239), so this
	# fraction is in the same scaled time the visuals want.
	tick_alpha = clampf(_tick_accumulator / TICK_INTERVAL, 0.0, 1.0)
	_visual_bridge.update_visual_positions(vis_states, units, lattice, tick_alpha)
	var visual_ms = (Time.get_ticks_usec() - visual_start) / 1000.0

	_check_victory()

	var total_ms = (Time.get_ticks_usec() - frame_start) / 1000.0

	# Collect timing samples
	_perf_gpu_tick_times.append(gpu_ms)
	_perf_step_times.append(step_us / 1000.0)
	_perf_cols_times.append(cols_us / 1000.0)
	_perf_anim_times.append(anim_us / 1000.0)
	_perf_edge_times.append(edge_us / 1000.0)
	_perf_chk_times.append(chk_us / 1000.0)
	_perf_chk_calls.append(chk_calls)
	_perf_chk_movers.append(chk_movers)
	_perf_cine_times.append(cine_us / 1000.0)
	_perf_proj_times.append(proj_us / 1000.0)
	_perf_state_check_times.append(state_ms)
	_perf_visual_update_times.append(visual_ms)
	_perf_total_frame_times.append(total_ms)
	_perf_frame_deltas.append(delta * 1000.0)
	_perf_ticks_per_frame.append(ticks_this_frame)

	# Periodic report
	_perf_report_timer += delta
	if _perf_report_timer >= _perf_report_interval:
		_print_perf_report()
		_perf_report_timer = 0.0

	_tick_settle_backstop(delta)

	if current_tick >= max_ticks:
		combat_active = false
		timed_out.emit(current_tick)


func _print_perf_report():
	_perf_report_count += 1
	var n = _perf_gpu_tick_times.size()
	if n == 0:
		return

	var gpu_avg = _array_avg(_perf_gpu_tick_times)
	var gpu_max = _perf_gpu_tick_times.max()
	var state_avg = _array_avg(_perf_state_check_times)
	var visual_avg = _array_avg(_perf_visual_update_times)
	var total_avg = _array_avg(_perf_total_frame_times)
	var total_max = _perf_total_frame_times.max()
	var delta_avg = _array_avg(_perf_frame_deltas)
	var effective_fps = 1000.0 / delta_avg if delta_avg > 0 else 0.0
	var ticks_per_sec = effective_fps * ticks_per_frame

	# Also dump unit states for context
	var state_summary = ""
	if gpu_state_reader:
		var states = gpu_state_reader.get_all_unit_states()
		var state_counts = {}
		for s in states:
			var sname = GPUConstants.LOGICAL_ACTIVITY_NAMES[s["state"]] if s["state"] < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(s["state"])
			state_counts[sname] = state_counts.get(sname, 0) + 1
		var parts = []
		for key in state_counts:
			parts.append("%s=%d" % [key, state_counts[key]])
		# ALIVE, not just the histogram (W7/R26). The histogram counts SLOTS, and a
		# corpse and an unused slot both read as one of the activity names -- so
		# `IDLE=3` on a 16-slot 13-unit battle is the three empty slots, and three
		# deaths later it is still `IDLE=3`. The rig hygiene rule "read the Units
		# histogram before believing a run" cannot be followed without this number.
		var alive := 0
		for s2 in states:
			if int(s2.get("hp", 0)) > 0:
				alive += 1
		state_summary = " | Units: %d/%d alive: %s" % [alive, states.size(),
			", ".join(parts)]

	var tpf_avg = _array_avg_int(_perf_ticks_per_frame)
	var zero_tick_frames = _perf_ticks_per_frame.count(0)

	# Perf summary — gated (default OFF; toggle GPU in the F3 Logging tab). Counter
	# resets below still run so toggling it on mid-session reports accurately.
	if DebugConfig.gpu_debug_enabled:
		print("[PERF #%d] tick=%d frames=%d | GPU: avg=%.2fms max=%.2fms | state: %.2fms | visual: %.2fms | total: avg=%.2fms max=%.2fms | delta: %.1fms (%.0f fps) | tpf: %.1f (0-tick: %d)%s" % [
			_perf_report_count, current_tick, n,
			gpu_avg, gpu_max,
			state_avg, visual_avg,
			total_avg, total_max,
			delta_avg, effective_fps,
			tpf_avg, zero_tick_frames,
			state_summary
		])
		print("[PERF #%d]   gpu split: step=%.2fms cols=%.2fms edge=%.2fms anim=%.2fms (edge: chk=%.2f cine=%.2f proj=%.2f)" % [
			_perf_report_count,
			_array_avg(_perf_step_times), _array_avg(_perf_cols_times),
			_array_avg(_perf_edge_times), _array_avg(_perf_anim_times),
			_array_avg(_perf_chk_times), _array_avg(_perf_cine_times),
			_array_avg(_perf_proj_times),
		])
		# W9 — `chk` per frame is (per-call cost x gate-open rate x ticks per frame) and
		# the line above cannot separate them. This one does: how often the gate opened,
		# how many units actually moved when it did, and what one call costs.
		var chk_calls_total := _array_sum_int(_perf_chk_calls)
		var chk_ticks_total := _array_sum_int(_perf_ticks_per_frame)
		var chk_movers_total := _array_sum_int(_perf_chk_movers)
		var chk_ms_total := _array_sum(_perf_chk_times)
		print("[PERF #%d]   chk split: opens=%.2f/frame %.0f%% of ticks (%d/%d) | movers=%.2f/open of %d slots | per-call=%.3fms" % [
			_perf_report_count,
			float(chk_calls_total) / n,
			100.0 * float(chk_calls_total) / chk_ticks_total if chk_ticks_total > 0 else 0.0,
			chk_calls_total, chk_ticks_total,
			float(chk_movers_total) / chk_calls_total if chk_calls_total > 0 else 0.0,
			_all_states.size(),
			chk_ms_total / chk_calls_total if chk_calls_total > 0 else 0.0,
		])
		var _kind_names := ["DIED", "POS", "MP", "CAST_BEGAN", "ACTION_COMMITTED", "STATE_CHANGED", "PROJ_FIRED", "HP", "STAT"]
		var _parts: Array[String] = []
		for _e in range(_chk_ev_n.size()):
			if _chk_ev_n[_e] > 0:
				_parts.append("%s n=%d %.3fms/ev" % [_kind_names[_e], _chk_ev_n[_e],
					_chk_ev_us[_e] / 1000.0 / _chk_ev_n[_e]])
		print("[PERF #%d]   apply by kind: %s" % [_perf_report_count, " | ".join(_parts)])
		var _ua_c := maxi(_ua_n, 1)
		print("[PERF #%d]   _update_unit_animation (%d calls): translate=%.3f ms/call" % [
			_perf_report_count, _ua_n, _ua_us[1] / 1000.0 / _ua_c])
		var _ac := maxi(_atk_n, 1)
		print("[PERF #%d]   _start_attack_animation (%d calls): snapshot=%.3f unit.attack=%.3f sfx_resolve=%.3f sfx_play=%.3f ms/call" % [
			_perf_report_count, _atk_n, _atk_us[0] / 1000.0 / _ac, _atk_us[1] / 1000.0 / _ac,
			_atk_us[2] / 1000.0 / _ac, _atk_us[3] / 1000.0 / _ac])
		if ExMateriaEffectSfx != null:
			# Live session/voice count, because R27's `sfx_play` cost tracks it: the
			# engine reaps one-shot sessions on a render-clock cadence and combat can
			# open them faster than that.
			var _snap: Dictionary = ExMateriaEffectSfx.debug_snapshot()
			print("[PERF #%d]   sfx engine: sessions=%s voices=%s preempts=%s" % [
				_perf_report_count, _snap.get("sessions", -1), _snap.get("total_voices", -1),
				_snap.get("preempts", -1)])
			# W11 step 1 — the SPLIT inside that sfx_play number, which R27 read from
			# the source and never timed. Each bucket names a different fix: `load` a
			# bank cache, `lock` the scheduler's mutex hold (neither cache nor reap),
			# `bind` the unit pickers, `seq` the sequencer. Cumulative counters, so
			# diff against the previous window; `bkkp` is the under-lock remainder
			# (session dict churn) that bind+seq do not account for.
			if ExMateriaEffectSfx.has_method("audition_split_stats"):
				var _sp: Dictionary = ExMateriaEffectSfx.audition_split_stats()
				var _dn := int(_sp["n"]) - int(_sfx_split_prev.get("n", 0))
				var _dpp := int(_sp["pp_n"]) - int(_sfx_split_prev.get("pp_n", 0))
				var _dc := maxi(_dn, 1)
				var _dppc := maxi(_dpp, 1)
				var _d := func(k: String) -> float:
					return float(int(_sp[k]) - int(_sfx_split_prev.get(k, 0))) / 1000.0
				print("[PERF #%d]   sfx split (n=%d calls, pp=%d dispatches, binds=%d, miss=%d): load=%.3f lock=%.3f disp=%.3f (bind=%.3f seq=%.3f bkkp=%.3f) ms/call" % [
					_perf_report_count, _dn, _dpp,
					int(_sp["binds"]) - int(_sfx_split_prev.get("binds", 0)),
					int(_sp["miss"]) - int(_sfx_split_prev.get("miss", 0)),
					_d.call("load_us") / _dc, _d.call("lock_us") / _dc, _d.call("disp_us") / _dc,
					_d.call("bind_us") / _dppc, _d.call("seq_us") / _dppc,
					(_d.call("disp_us") - _d.call("bind_us") - _d.call("seq_us")) / _dc])
				# W11 step 1b — the OTHER side of that lock: what _scheduler_main
				# does while it holds the mutex the line above is waiting on.
				# `reap` is O(live sessions) and `walked` is its counted work.
				if _sp.has("sched_holds"):
					var _dh := int(_sp["sched_holds"]) - int(_sfx_split_prev.get("sched_holds", 0))
					var _dr := int(_sp["sched_reaps"]) - int(_sfx_split_prev.get("sched_reaps", 0))
					print("[PERF #%d]   sfx sched (holds=%d subs=%d reaps=%d): hold=%.3f ms/hold | reap=%.3f ms/reap | walked=%d killed=%d" % [
						_perf_report_count, _dh,
						int(_sp["sched_subs"]) - int(_sfx_split_prev.get("sched_subs", 0)), _dr,
						_d.call("sched_hold_us") / maxi(_dh, 1),
						_d.call("sched_reap_us") / maxi(_dr, 1),
						int(_sp["sched_walked"]) - int(_sfx_split_prev.get("sched_walked", 0)),
						int(_sp["sched_killed"]) - int(_sfx_split_prev.get("sched_killed", 0))])
					var _ds := int(_sp["sched_subs"]) - int(_sfx_split_prev.get("sched_subs", 0))
					var _di := func(k: String) -> int:
						return int(_sp[k]) - int(_sfx_split_prev.get(k, 0))
					# `entities/sub` is the sequencer work the scheduler does inside
					# the hold; the skip_* fields say which reap condition declined
					# each session that is still linked into a unit's list.
					print("[PERF #%d]   sfx reap: entities=%.1f/sub | skips: undisp=%d grace=%d voices=%d seq=%d" % [
						_perf_report_count,
						float(_di.call("sched_entities")) / maxi(_ds, 1),
						_di.call("skip_undisp"), _di.call("skip_grace"),
						_di.call("skip_voices"), _di.call("skip_seq")])
					if _sp.has("silence_freed"):
						print("[PERF #%d]   sfx reap: silence_freed=%d (one-shot casts reaped past the per-unit voice veto)" % [
							_perf_report_count, _di.call("silence_freed")])
				_sfx_split_prev = _sp
		for _k in range(2):
			var c := maxi(_chk_all_calls[_k], 1)
			print("[PERF #%d]   chk cost %s (%d calls): build=%.3f interp=%.3f apply=%.3f ms/call | events=%.2f/call" % [
				_perf_report_count, "per-TICK (gated)" if _k == 1 else "per-FRAME      ",
				_chk_all_calls[_k],
				_chk_build_us[_k] / 1000.0 / c,
				_chk_interp_us[_k] / 1000.0 / c,
				_chk_apply_us[_k] / 1000.0 / c,
				float(_chk_events[_k]) / c,
			])

	# Clear for next interval
	_perf_gpu_tick_times.clear()
	_perf_step_times.clear()
	_perf_cols_times.clear()
	_perf_anim_times.clear()
	_perf_edge_times.clear()
	_perf_chk_times.clear()
	_perf_cine_times.clear()
	_perf_proj_times.clear()
	_perf_state_check_times.clear()
	_perf_visual_update_times.clear()
	_perf_total_frame_times.clear()
	_perf_frame_deltas.clear()
	_perf_ticks_per_frame.clear()
	_perf_chk_calls.clear()
	_perf_chk_movers.clear()
	for _k in range(2):
		_chk_build_us[_k] = 0
		_chk_interp_us[_k] = 0
		_chk_apply_us[_k] = 0
		_chk_events[_k] = 0
		_chk_all_calls[_k] = 0
	for _e in range(_chk_ev_n.size()):
		_chk_ev_us[_e] = 0
		_chk_ev_n[_e] = 0
	_ua_us[0] = 0
	_ua_us[1] = 0
	_ua_n = 0
	for _e in range(_atk_us.size()):
		_atk_us[_e] = 0
	_atk_n = 0


func _array_avg(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var total = 0.0
	for v in arr:
		total += v
	return total / arr.size()


func _array_sum(arr: Array) -> float:
	var total = 0.0
	for v in arr:
		total += v
	return total


func _array_sum_int(arr: Array) -> int:
	var total = 0
	for v in arr:
		total += v
	return total


func _array_avg_int(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var total = 0
	for v in arr:
		total += v
	return float(total) / arr.size()


func _is_unit_dead(state: Dictionary) -> bool:
	return (state.get("flags", 0) & GPU_FLAGS_DEAD_BIT) != 0


func _read_tick_columns() -> void:
	"""Read the seven LEAN per-tick columns after step_tick, and derive the three
	edges that need them. Runs every tick, between step_tick and advance_tick.

	FIVE OUTPUTS, NOT ONE — and the name used to claim one (`_quick_damage_detect`):

	  _last_damage_tick / _hp_before_last_damage   HP fell this tick (set BEFORE
												   advance_tick fires PostGenericAttack)
	  _last_evade_type                             sticky evade snapshot, so a later
												   tick's evade_type=0 cannot erase a
	                                               miss before its reaction fires
	  _tick_cinematic_timer / _tick_paused         republished for the cinematic edge
	                                               (CinematicManager._pick_spotlight_caster)
	                                               and anim-freeze (_get_unit_anim_speed),
	                                               both of which run later in THIS tick
	  _state_edge_this_tick                        lean state-change edge for the
	                                               per-tick _check_state_changes
	  _tick_turn_meter / _tick_flags /             the turn gate's three inputs
	  _tick_state                                  (ADR-0239), consulted at the end
												   of this same tick iteration.
												   `_tick_state` is the SAME array
												   the state edge below derives from
												   — the gate's settled test is a
	                                               republish, not a fourth column.

	THEY ARE ONE FUNCTION BECAUSE THEY ARE ONE READ, which is the thing a split would
	throw away: all seven columns come from a single `buffer_get_data` off the version-
	cached region. Splitting this into five honestly-named functions buys five names and
	costs up to five round trips per tick, or else threads the cache through all of them,
	which is the coupling wearing a different shape.

	Perf: no per-tick 99-field dict build. The full `_all_states` snapshot is rebuilt
	once per FRAME in `_check_state_changes` (after the loop); mid-loop consumers read
	these columns instead."""
	var hp_col: PackedInt32Array = gpu_state_reader.get_unit_column(_col_hp)
	var evade_col: PackedInt32Array = gpu_state_reader.get_unit_column(_col_evade_type)
	# Refreshed here so the cinematic edge (CinematicManager._pick_spotlight_caster)
	# and anim-freeze (_get_unit_anim_speed) see THIS tick's values without the full
	# snapshot; both run later in the same tick iteration.
	_tick_cinematic_timer = gpu_state_reader.get_unit_column(_col_cinematic_timer)
	_tick_paused = gpu_state_reader.get_unit_column(_col_paused)
	# The turn gate's inputs. Read here rather than in the gate so the whole
	# per-tick GPU read stays ONE cache-served region (see the docstring): a gate
	# that fetched its own columns would be the round trip this function exists
	# to avoid.
	_tick_turn_meter = gpu_state_reader.get_unit_column(_col_turn_meter)
	_tick_flags = gpu_state_reader.get_unit_column(_col_flags)
	# Lean state-edge detection for the per-tick _check_state_changes above. Same cached
	# region as the four columns beside it, so this is a read, not a round trip.
	var state_col: PackedInt32Array = gpu_state_reader.get_unit_column(_col_state)
	# Republished for the turn gate's settled test (the turn brake). Same read.
	_tick_state = state_col
	_state_movers_this_tick = 0
	if _tick_prev_state.size() != state_col.size():
		_tick_prev_state = state_col.duplicate()
	else:
		for si in range(state_col.size()):
			if state_col[si] != _tick_prev_state[si]:
				_tick_prev_state[si] = state_col[si]
				_state_movers_this_tick += 1
	_state_edge_this_tick = _state_movers_this_tick > 0
	for i in range(mini(hp_col.size(), units.size())):
		var current_hp: int = hp_col[i]
		# Frame-start hp from the interpreter's sample buffer (it updates at end of
		# interpret(), so during the tick loop it still holds last frame's value).
		var prev_hp: int = _combat_interp.last_hp(i)
		# Snapshot evade_type every tick (fresh from GPU roll_evasion).
		# Only update when non-zero so a later tick's evade_type=0 (hit) doesn't
		# overwrite a miss result before the miss reaction fires.
		var evade_type: int = evade_col[i]
		if evade_type != 0:
			_last_evade_type[i] = evade_type
		if current_hp < prev_hp:
			_last_damage_tick[i] = current_tick
			_hp_before_last_damage[i] = prev_hp


func refresh_all_states_now() -> void:
	"""Rebuild the full 99-field _all_states snapshot on demand (in place, so a host
	holding the reference sees it — ADR-0018). Used by CinematicManager._handle_began,
	which fires on a rare cinematic edge mid-tick-loop and needs field-heavy state
	(casting_ability_id / flags / cast_target …) that the lean per-tick columns omit.
	Serves off the version cache, so a later same-frame full read is a cache hit."""
	_all_states.assign(gpu_state_reader.get_all_unit_states())


func _check_state_changes(gated: bool = false):
	# Lean 39-field snapshot (W1): building all 101 fields for 16 units every
	# ticking frame measured ~1.8 ms and was the one cost that never decayed as
	# units died (F22). The full form stays one call away — refresh_all_states_now()
	# above — for the rare cinematic edge that needs the field-heavy dictionary.
	var _k := 1 if gated else 0
	_chk_all_calls[_k] += 1
	var _b0 := Time.get_ticks_usec()
	_all_states.assign(gpu_state_reader.get_all_unit_states_hot())
	_chk_build_us[_k] += Time.get_ticks_usec() - _b0

	var _i0 := Time.get_ticks_usec()
	var _apply_local := 0
	for i in range(mini(_all_states.size(), units.size())):
		var state = _all_states[i]
		# ADR-0018: the pure interpreter does detection; we only apply. It returns
		# the frame's ordered events (death suppresses the rest), in the same order
		# as the old steps 1-8.
		for ev in _combat_interp.interpret(i, state):
			var _a0 := Time.get_ticks_usec()
			_apply_combat_event(i, state, ev)
			var _adt := Time.get_ticks_usec() - _a0
			_apply_local += _adt
			_chk_events[_k] += 1
			_chk_ev_us[ev.kind] += _adt
			_chk_ev_n[ev.kind] += 1
		# Step 9 — thrash detection is diagnostic ring-buffer decoding, not a
		# snapshot reaction, so it stays here. Dead units skip it (the old loop's
		# death `continue` skipped it too).
		if not _is_unit_dead(state):
			_process_thrash_detection(i, state)
	_chk_apply_us[_k] += _apply_local
	_chk_interp_us[_k] += Time.get_ticks_usec() - _i0 - _apply_local


# === Apply pump (ADR-0018) =====================================================
# The side-effect half of the old _process_* steps. Each handler reads the typed
# event payload (and the snapshot / _all_states for apply-only reads); none
# re-derives detection. Each emits the matching per-event signal so the host can
# project it (assertion hooks / production UI), and logs the regression trace
# through the injected `_rlog`.

func _apply_combat_event(i: int, state: Dictionary, ev) -> void:
	match ev.kind:
		GPUCombatInterpreterClass.EventKind.DIED:
			_apply_death(i, state, ev)
		GPUCombatInterpreterClass.EventKind.POSITION_CHANGED:
			if _rlog:
				_rlog.log_move(i, ev.from_pos, ev.to_pos)
		GPUCombatInterpreterClass.EventKind.MP_CHANGED:
			if _rlog:
				_rlog.log_mp_change(i, ev.prev_value, ev.new_value, state.get("casting_ability_id", -1))
			units[i].unit_stats.current_mp = ev.new_value
			mp_changed.emit(i, ev.prev_value, ev.new_value)
		GPUCombatInterpreterClass.EventKind.CAST_BEGAN:
			_apply_cast_began(i, state, ev)
		GPUCombatInterpreterClass.EventKind.ACTION_COMMITTED:
			action_committed.emit(i, ev.ability_id, ev.target)
		GPUCombatInterpreterClass.EventKind.STATE_CHANGED:
			_apply_state_changed(i, state, ev)
		GPUCombatInterpreterClass.EventKind.PROJECTILE_FIRED:
			_apply_projectile_fired(i, state)
		GPUCombatInterpreterClass.EventKind.HP_CHANGED:
			_apply_hp_change(i, state, ev)
		GPUCombatInterpreterClass.EventKind.STAT_CHANGED:
			_apply_stat_change(i, ev)


func _apply_death(i: int, state: Dictionary, ev) -> void:
	var current_state = state.get("state", 0)
	if DebugConfig.simulation_debug_enabled:
		print("[Tick %d] [DEATH] %s died! (was %s, gpu_state=%s)" % [
			current_tick, units[i].name,
			DisplayActivity.Activity.keys()[units[i].activity],
			GPUConstants.LOGICAL_ACTIVITY_NAMES[current_state] if current_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(current_state)])
	units[i].unit_stats.current_hp = 0
	units[i].unit_stats.hp_changed.emit(ev.prev_value, 0)
	units[i].unit_stats.die()
	_spell_cast_active.erase(i)
	effect_manager.stop_charge_vfx(i)
	if _rlog:
		_rlog.log_entry("DEATH", {"unit": i, "tick": current_tick})
	unit_died.emit(i)


func _apply_cast_began(i: int, state: Dictionary, ev) -> void:
	if DebugConfig.iteration_debug_enabled:
		_debug_action_start_tick[i] = current_tick
		_debug_animation_starts[i] = _debug_animation_starts.get(i, 0) + 1
	# Animation-coordination flag (its detection-dedup role is now the GPU's
	# CAST_STEP_ID): tells _update_unit_animation a cast animation is playing.
	_spell_cast_active[i] = true
	cast_began.emit(i, ev.ability_id, ev.target)
	_on_spell_cast_complete(i, ev.ability_id, ev.target, _all_states)
	# Defer TRAP for weapon-range non-damage abilities (breaks, holy sword) to the
	# weapon-impact frame; the pump builds the payload from live node positions.
	if ev.defers_trap and ev.target >= 0 and ev.target < units.size():
		var target_unit = units[ev.target]
		if is_instance_valid(target_unit):
			var caster_unit = units[i]
			var impact_dir = _compute_impact_direction(caster_unit.global_position, target_unit.global_position) if is_instance_valid(caster_unit) else Vector3.FORWARD
			effect_manager.set_pending_trap(i, {
				"position": target_unit.global_position,
				"impact_dir": impact_dir,
				"target_unit": target_unit,
				"ability_id": ev.ability_id,
				"is_melee": true,
			})


func _apply_state_changed(i: int, state: Dictionary, ev) -> void:
	var prev_state = ev.prev_state
	var current_state = ev.new_state
	_log_state_change(i, prev_state, current_state, state)
	state_changed.emit(i, prev_state, current_state)

	# Clear spell-cast-active when GPU exits ACTING (safety net + discard pending trap).
	if prev_state == GPUConstants.LOGICAL_ACTIVITY_ACTING and current_state != GPUConstants.LOGICAL_ACTIVITY_ACTING:
		if _spell_cast_active.get(i, false):
			_clear_spell_cast_active(i)

	var current_pos = Vector2i(state.get("pos_x", 0), state.get("pos_z", 0))
	if _rlog:
		_rlog.log_state(i, prev_state, current_state, state.get("timer", 0), current_pos)

	# Charge start/end + charge VFX
	if current_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and prev_state != GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		var casting_id = state.get("casting_ability_id", -1)
		var cast_timer = state.get("cast_timer", 0)
		if _rlog:
			_rlog.log_charge_start(i, casting_id, cast_timer)
		if casting_id > 0:
			effect_manager.spawn_charge_vfx(i, casting_id)
	elif prev_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING and current_state != GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
		var casting_id = _combat_interp.last_casting_ability_id(i)
		if _rlog:
			_rlog.log_charge_end(i, casting_id)
		effect_manager.stop_charge_vfx(i)

	# Facing before animation — skip if a cast began this frame (it sets facing
	# itself, and the signal would overwrite thrown-item animations). At a state
	# transition the old `not _spell_cast_active` was true iff a cast began now.
	if not ev.cast_began_this_frame and (current_state == GPUConstants.LOGICAL_ACTIVITY_ACTING or current_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING):
		GPUVisualBridge.update_facing_toward_target(units[i], i, _all_states)

	_update_unit_animation(units[i], current_state, i, state)


func _apply_projectile_fired(i: int, state: Dictionary) -> void:
	if DebugConfig.iteration_debug_enabled:
		_debug_projectile_spawns[i] = _debug_projectile_spawns.get(i, 0) + 1
		var action_start = _debug_action_start_tick.get(i, current_tick)
		print("[Tick %d] [PROJ_DEBUG] %s: Spawning projectile #%d (anim_frame=%d, projectile_frame=%d, ticks_since_action=%d)" % [
			current_tick, units[i].name, _debug_projectile_spawns[i],
			state.get("anim_frame", -1), state.get("projectile_frame", -1), current_tick - action_start])
	projectile_manager.spawn_from_gpu(i, state, _all_states)
	projectile_fired.emit(i)


func _apply_hp_change(i: int, state: Dictionary, ev) -> void:
	var delta = ev.delta
	_log_hp_change(i, ev.prev_value, ev.new_value, delta)
	hp_changed.emit(i, ev.prev_value, ev.new_value, delta)
	if delta < 0:
		_last_damage_tick[i] = current_tick
	# Find attacker from GPU state (apply-only read of the snapshot set).
	var attacker_idx = -1
	for j in range(_all_states.size()):
		var attacker_state = _all_states[j]
		if attacker_state.get("damage_target", -1) == i or attacker_state.get("pending_heal_target", -1) == i:
			attacker_idx = j
			break
	if _rlog:
		if delta > 0:
			_rlog.log_heal(attacker_idx, i, delta, ev.prev_value, ev.new_value)
		else:
			_rlog.log_damage(attacker_idx, i, -delta, ev.prev_value, ev.new_value)
	# The hit cloud is NOT spawned here. It is triggered by the attacker's
	# PostGenericAttack (0xDE) SEQ opcode via _trigger_physical_reaction
	# (FFT-faithful: only strike anims carry 0xDE, so Dash and other non-0xDE
	# damaging anims produce no cloud). Attributing off the one-frame damage_target
	# pulse here was also unreliable — it is cleared before this read (attacker_idx
	# is routinely -1). See docs/VFX_TRIGGER_ARCHITECTURE.md.
	units[i].unit_stats.current_hp = ev.new_value
	units[i].unit_stats.hp_changed.emit(ev.prev_value, ev.new_value)


func _apply_stat_change(i: int, ev) -> void:
	var unit_name = units[i].name if i < units.size() else "Unit%d" % i
	var delta_val = ev.new_value - ev.prev_value
	print("[Tick %d] [STAT_BREAK] %s: %s %d -> %d (%s%d)" % [
		current_tick, unit_name, ev.stat_label, ev.prev_value, ev.new_value,
		"+" if delta_val > 0 else "", delta_val])
	if _rlog:
		_rlog.log_entry("STAT_CHANGE", {
			"unit": i, "stat": ev.stat_label,
			"old": ev.prev_value, "new": ev.new_value, "tick": current_tick
		})
	stat_changed.emit(i, ev.stat_key, ev.stat_label, ev.prev_value, ev.new_value)
	if i < units.size():
		_sync_stat_to_unit(i, ev.stat_key, ev.new_value)


func _process_thrash_detection(i: int, state: Dictionary) -> void:
	"""Check for thrash flag transitions and log decoded decision history."""

	var meta = state.get("decision_meta", 0)
	var thrash_flag = (meta >> 3) & 0x1
	var prev_flag = _prev_thrash_flag.get(i, 0)
	_prev_thrash_flag[i] = thrash_flag

	if thrash_flag != 1:
		return
	if prev_flag == 1:
		# Already thrashing — rate-limit logging to once per 200 ticks
		var last_log = _last_thrash_log_tick.get(i, -200)
		if current_tick - last_log < 200:
			return

	_last_thrash_log_tick[i] = current_tick
	var thrash_count = (meta >> 4) & 0xF
	var write_idx = meta & 0x7
	var hist = [
		state.get("decision_hist_0", 0),
		state.get("decision_hist_1", 0),
		state.get("decision_hist_2", 0),
	]

	var entries = []
	for j in range(6):
		# Read from oldest to newest: start from write_idx (oldest)
		var idx: int = (write_idx + j) % 6
		var slot: int = idx / 2
		var half: int = idx % 2
		var raw: int = hist[slot]
		var entry: int = (raw & 0xFFFF) if half == 0 else ((raw >> 16) & 0xFFFF)
		var reason = (entry >> 12) & 0xF
		var unit_state = (entry >> 9) & 0x7
		var target = (entry >> 5) & 0xF
		var pos_hash = entry & 0x1F
		var reason_name = GPUConstants.REASON_NAMES[reason] if reason < GPUConstants.REASON_NAMES.size() else str(reason)
		var state_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[unit_state] if unit_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(unit_state)
		entries.append("  [%d] %s in %s → tgt=%d pos_h=%d" % [j, reason_name, state_name, target, pos_hash])

	if DebugConfig.simulation_debug_enabled:
		var unit_name = units[i].name if i < units.size() else "Unit%d" % i
		print("[Tick %d] [THRASH] %s thrashing (count=%d)! Decision history:" % [current_tick, unit_name, thrash_count])
		for line in entries:
			print(line)


func _sync_stat_to_unit(unit_idx: int, stat_key: String, gpu_value: int) -> void:
	"""Sync a GPU stat value back to the CPU unit's progression/stats."""
	var unit = units[unit_idx]
	var progression = unit.unit_progression

	if progression:
		# Reverse-calculate raw stat from effective value
		var job = JobDatabase.get_job(progression.current_job_id)
		match stat_key:
			"pa":
				progression.raw_pa = _target_to_raw(gpu_value, job.get("pa_multiplier", 100))
			"ma":
				progression.raw_ma = _target_to_raw(gpu_value, job.get("ma_multiplier", 100))
			"speed":
				progression.raw_speed = _target_to_raw(gpu_value, job.get("speed_multiplier", 100))
			"wp":
				# WeaponBreak: WP=0 means weapon is broken — unequip it
				if gpu_value == 0:
					progression.unequip_item(UnitProgression.EquipSlot.RIGHT_HAND)
			"s_ev":
				# ShieldBreak: S_EV=0 means shield is broken — unequip it
				if gpu_value == 0:
					progression.unequip_item(UnitProgression.EquipSlot.LEFT_HAND)
	else:
		# No progression — set backing fields directly
		match stat_key:
			"pa":
				unit.unit_stats._attack = gpu_value
			"ma":
				unit.unit_stats._magic_attack = gpu_value
			"speed":
				unit.unit_stats._atb_speed = gpu_value


func _target_to_raw(target_effective: int, job_multiplier: int) -> int:
	"""Reverse-calculate raw stat from desired effective value and job multiplier."""
	if job_multiplier <= 0:
		return target_effective * 16384
	return (target_effective * 16384 * 100 + job_multiplier - 1) / job_multiplier


# === CinematicManager signal handlers =========================================
# CinematicManager owns edge detection + EffectInstance lifecycle + camera
# takeover (ADR-0018 cluster). Per-event signals route the side-effects the
# manager doesn't own: debug-probe routing and combat_visuals freeze refresh.

func _on_cinematic_manager_began(caster_idx: int, target_idx: int) -> void:
	if DebugConfig.iteration_debug_enabled:
		if _debug_probe == null:
			_debug_probe = CinematicDebugProbe.new()
		_debug_probe.on_cinematic_began(_all_states, units, caster_idx, target_idx, current_tick)
	# Cinematic-active is the second axis of the combat_visuals freeze predicate
	# (ADR-0037 dec. 7) — refresh the group now so the strategy-view spectacle
	# halts in lockstep with the cinematic edge.
	_refresh_combat_visuals_freeze()


func _on_cinematic_manager_ended(prev_caster_idx: int) -> void:
	if DebugConfig.iteration_debug_enabled:
		# cinematic_teardown ran in stage_spell this same tick, so every unit's
		# paused/AoE-pending should already read 0. The per-tick loop no longer
		# refills the full _all_states (perf: it reads lean columns), so refresh it
		# here — debug-gated — before the probe reads the field-heavy snapshot. If
		# any don't clear, the probe will flag it on the subsequent probe() call.
		if _debug_probe == null:
			_debug_probe = CinematicDebugProbe.new()
		refresh_all_states_now()
		_debug_probe.on_cinematic_ended(_all_states, units, prev_caster_idx, current_tick)
	# Cinematic-active flipped to false — resume the combat_visuals (subject to
	# the other axis, combat_active).
	_refresh_combat_visuals_freeze()


## Refresh each combat_visuals member's process_mode against the four-axis
## predicate (ADR-0037 decs. 3, 7, 8, 9):
##   should_run = victory_achieved OR (combat_active AND
##                (not cinematic_active OR member descends from the caster Unit))
## Two carve-outs preserve the cinematic spotlight subject: the cinematic
## EffectInstance opts out of the group itself (is_cinematic=true), and the
## caster's unit-owned Charge VFX is exempted here by parent-chain check —
## CPU mirror of the GPU's U_PAUSED exemption that keeps the caster's body
## pose animating (_get_unit_anim_speed).
func _refresh_combat_visuals_freeze() -> void:
	var tree := get_tree()
	if not tree:
		return
	for n in tree.get_nodes_in_group("combat_visuals"):
		n.process_mode = Node.PROCESS_MODE_INHERIT if _visuals_should_run(n) else Node.PROCESS_MODE_DISABLED


## The per-node freeze predicate, factored out so a newly-spawned member can be
## initialized to the same state without re-scanning the whole group (ADR-0037
## dec. 10 — see `_on_scene_node_added`).
func _visuals_should_run(n: Node) -> bool:
	if victory_achieved:
		return true
	if not combat_active:
		return false
	if cinematic_manager.is_active():
		# Cinematic spotlight: only the caster's own subtree keeps animating.
		var caster_idx := cinematic_manager.active_caster_idx()
		if caster_idx < 0 or caster_idx >= units.size():
			return false
		return _node_descends_from(n, units[caster_idx])
	return true


## A combat_visuals member spawned mid-cinematic (e.g. the {92} crystal billboard)
## defaults to PROCESS_MODE_INHERIT and would animate until the next
## transition-driven refresh. Initialize it against the current freeze once it has
## joined the group.
##
## Gated to `cinematic_manager.is_active()` — the ONLY freeze axis under which a
## fresh member spawns amid a running battlefield (the crystal's case). Outside a
## cinematic the INHERIT default is already right, so bail in O(1); this
## deliberately does NOT arm during the combat-inactive/pre-combat phase, where
## the whole scene tree is populating and a tree-wide `node_added` reaction would
## churn over hundreds of unrelated nodes. `cinematic_manager.is_active()` is the
## authority's own read (no duplicated freeze predicate to drift). CombatLoop
## stays the sole freeze authority (ADR-0037).
func _on_scene_node_added(n: Node) -> void:
	if not cinematic_manager.is_active():
		return
	# `add_to_group` runs in the member's `_ready`, which fires AFTER `node_added`;
	# defer to idle (past `_ready`) then apply. call_deferred leaves no lingering
	# per-node connection and self-drops if the node is freed first.
	_apply_spawn_freeze.call_deferred(n)


func _apply_spawn_freeze(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_in_group("combat_visuals"):
		return
	n.process_mode = Node.PROCESS_MODE_INHERIT if _visuals_should_run(n) else Node.PROCESS_MODE_DISABLED


func _node_descends_from(node: Node, ancestor: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


## Get animation speed multiplier for a unit based on its current activity.
## Uses cached state from previous frame (1-tick lag is negligible).
func _get_unit_anim_speed(unit_idx: int) -> int:
	# During a cinematic, U_PAUSED freezes the unit's animation playback so the
	# world stops moving around the cinematic spotlight (ADR-0031: the freeze is
	# GPU-derived; the loop just reads the snapshot).
	if cinematic_manager.is_active() and unit_idx < _tick_paused.size():
		if _tick_paused[unit_idx] != 0:
			return 0
	var prev_state = _combat_interp.last_state(unit_idx)
	match prev_state:
		GPUConstants.LOGICAL_ACTIVITY_WALKING, GPUConstants.LOGICAL_ACTIVITY_WALKING_TO_CAST:
			var visualizer = _visual_bridge.get_visualizer(unit_idx)
			if visualizer and visualizer.is_cliff_move:
				return MovementTimingConfig.VERTICAL_MOVE_SEQ_SPEED
			return MovementTimingConfig.HORIZONTAL_MOVE_SEQ_SPEED
		GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING:
			return MovementTimingConfig.CHARGE_SEQ_SPEED
		GPUConstants.LOGICAL_ACTIVITY_ACTING:
			return MovementTimingConfig.ABILITY_SEQ_SPEED
		_:
			return 1


# Sentinel returned by `settled_victory_activity` for "leave the unit's current
# activity as-is" — a KO'd unit holds its DEAD corpse frame instead of being
# forced into a pose. Distinct from every DisplayActivity.Activity value (which
# are all >= 0).
const LEAVE_ACTIVITY := -1


## Pure decision for the pose a unit RENDERS once the GPU reports it has settled
## into the battle-won state (LOGICAL_ACTIVITY_CELEBRATING). Decouples the win
## HANDSHAKE (stage_victory keys on the GPU state, untouched) from the on-screen
## pose:
##   - `celebrate` → the made-up victory dance (CELEBRATING) regardless of HP,
##     preserving the ADR-0026 arena behaviour.
##   - faithful (celebrate off) → a living unit returns to base IDLE (the
##     resolver then auto-picks IDLE_LOW_HEALTH kneel for a critical unit, plain
##     IDLE walk-in-place wait otherwise); a KO'd unit returns LEAVE_ACTIVITY so
##     it stays lying as its DEAD corpse.
static func settled_victory_activity(celebrate: bool, is_dead: bool) -> int:
	if celebrate:
		return DisplayActivity.Activity.CELEBRATING
	if is_dead:
		return LEAVE_ACTIVITY
	return DisplayActivity.Activity.IDLE


func _update_unit_animation(unit: Unit, gpu_state: int, unit_idx: int, state: Dictionary):
	# Victory is terminal and OVERRIDES (ADR-0026): the unit's team has won, so
	# the won-the-battle activity interrupts any lingering cast/attack just like
	# a normal state change. Handle it BEFORE the dead / cast-latch guards below
	# (it must not be gated by either), and clear the cast latch so a pending
	# cast can't re-apply next tick. What the settled unit RENDERS —  the made-up
	# victory dance vs the faithful HP-appropriate pose — is `celebrate_on_victory`,
	# resolved by `settled_victory_activity`; the GPU win handshake (stage_victory)
	# is untouched either way. The chosen activity resolves through the map like
	# every other activity — no raw type1_playback.start() on the BODY layer (that
	# was the recurrence ADR-0026 retires). Setting `activity` routes through
	# update_animation() → current_anim_id setter → _arm_anim_id_clock, which stops
	# the WEP1/EFF1 playbacks and disables those layers (the parameterless-state
	# teardown that ADR-0053's Path-D refactor folded into the clock arm), so no
	# manual layer teardown is needed here.
	if gpu_state == GPUConstants.LOGICAL_ACTIVITY_CELEBRATING:
		_clear_spell_cast_active(unit_idx)
		var settled := settled_victory_activity(celebrate_on_victory, unit.unit_stats.is_dead)
		if settled != LEAVE_ACTIVITY:
			unit.activity = settled
		return

	if unit.unit_stats.is_dead:
		return

	# Don't interrupt spell cast animation - wait for animation_paused signal
	# This prevents the cast animation from being cut short when GPU immediately
	# starts charging the next spell
	if _spell_cast_active.get(unit_idx, false):
		return

	# `state` is the CALLER's snapshot row, not a fresh fetch (W12/#934). This used to
	# open with `gpu_state_reader.get_all_unit_states()` — the FULL 101-field snapshot,
	# built for every slot, once per STATE_CHANGED event — to read, in the end,
	# `casting_ability_id`. That is F22's cost, which W1 took off the per-FRAME path,
	# still being paid on the per-EVENT path: 0.18 ms/event at 32 slots and 0.36-1.39 at
	# 80 (R27/F37), while the caller was already holding the hot 39-field row.
	# Everything this path reads is in SNAPSHOT_HOT_UNION — `casting_ability_id` here and
	# in tools/activity_taxonomy.yaml's two `param_field`s — so a hot row is sufficient
	# and check_snapshot_union.py / GPUSnapshotUnionTest are what keep that true.
	_ua_n += 1
	var _u0 := Time.get_ticks_usec()

	var old_anim_state = unit.activity

	# Logical -> Display dispatch lives in ActivityTranslator. The shell is
	# generated from tools/activity_taxonomy.yaml; per-routing impls are
	# hand-written there. CELEBRATING / dead / cast-latch guards above stay
	# at this call site because they consult CombatLoop-internal state
	# (_spell_cast_active in particular).
	ActivityTranslator.translate(unit, gpu_state, state, unit_idx,
		Callable(self, "_start_attack_animation"))
	_ua_us[1] += Time.get_ticks_usec() - _u0

	if DebugConfig.iteration_debug_enabled and old_anim_state != unit.activity:
		print("  [ANIM] %s: %s -> %s (GPU state: %s)" % [
			unit.name,
			DisplayActivity.Activity.keys()[old_anim_state],
			DisplayActivity.Activity.keys()[unit.activity],
			GPUConstants.LOGICAL_ACTIVITY_NAMES[gpu_state] if gpu_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(gpu_state)
		])


func _on_unit_animation_complete(anim_state: int, unit_idx: int):
	"""Handle animation completion signal - clears spell_cast_active flag."""
	if anim_state == DisplayActivity.Activity.SPELL_CASTING \
		or anim_state == DisplayActivity.Activity.USING_ITEM \
		or anim_state == DisplayActivity.Activity.ATTACKING:
		_clear_spell_cast_active(unit_idx)


func _on_unit_animation_paused(unit_idx: int):
	"""Handle animation paused signal - spell cast animations pause at end, not complete."""
	# Spell cast animations use PauseAnimation opcode - clear the flag when paused
	_clear_spell_cast_active(unit_idx)


func _on_unit_type1_side_effect(effect_type: int, _params: Dictionary, unit_idx: int):
	"""Handle PostGenericAttack opcode — spawn deferred TRAP effects and reaction animations."""
	if effect_type != AnimationOpcodes.SideEffect.POST_GENERIC_ATTACK:
		return

	# Spawn deferred TRAP particles (breaks / holy sword own their own cloud).
	var fired_pending := effect_manager.fire_pending_trap(unit_idx)

	# Trigger reaction animation on target + the hit cloud, unless a deferred trap
	# already fired for this same PostGenericAttack.
	_trigger_physical_reaction(unit_idx, not fired_pending)


# === Reaction routing (folded from tests/managers/ReactionManager.gd) =========
# Four entry points for hit/evade/block reaction animations:
#   _trigger_physical_reaction      — driven by POST_GENERIC_ATTACK SEQ side-effect
#   _trigger_projectile_reaction    — driven by projectile_landed
#   _on_ability_react               — driven by EffectManager.ability_react_triggered
#   _on_refresh_tile                — driven by EffectManager.refresh_tile_triggered
# All four are stateless routing → AbilityDatabase / ReactionType lookup →
# Unit.play_reaction_animation. Inlined here because every input
# (_last_damage_tick, _last_evade_type, _combat_interp, hit windows) already
# lives on CombatLoop; a separate manager carried no state, only forwarders.

func _trigger_physical_reaction(attacker_idx: int, spawn_hit_cloud: bool = true) -> void:
	"""Play hit/evade/block reaction animation on the target of a physical attack.

	`spawn_hit_cloud` also spawns the hit cloud when the blow lands — this is the
	FFT-faithful trigger (SEQ opcode 0xDE / PostGenericAttack, only 40/227 anims
	carry it), replacing the old damage-event spawn. The caller passes false when a
	deferred weapon trap (break / holy sword) already fired its own cloud for this
	same opcode. See docs/VFX_TRIGGER_ARCHITECTURE.md.

	damage_target is a single-frame GPU pulse cleared every tick, so it's always -1
	by the time we read it. HP comparison also fails because the interpreter's hp
	sample updates at end of frame, before PostGenericAttack fires (next frame).
	Instead, we use _last_damage_tick: when the combat pump applies an HP_CHANGED
	with a drop, it records the tick. If the target was damaged within the last N
	ticks, it's a hit.
	"""
	if attacker_idx >= _all_states.size() or attacker_idx >= units.size():
		return
	var attacker_state = _all_states[attacker_idx]
	var target_idx: int = attacker_state.get("target", -1)
	if target_idx < 0 or target_idx >= units.size():
		return
	var target_unit = units[target_idx]
	if not is_instance_valid(target_unit) or target_unit.unit_stats.is_dead:
		return

	var sprite_type = target_unit.get_seq_type().to_lower()

	# Hit detection: target was damaged within the last N ticks
	# _last_damage_tick is set by _read_tick_columns() right after step_tick,
	# before advance_tick fires PostGenericAttack, so it's always fresh.
	var last_dmg_tick: int = _last_damage_tick.get(target_idx, -999)
	var is_hit = (current_tick - last_dmg_tick) <= MELEE_HIT_WINDOW_TICKS
	var evade_type: int = _last_evade_type.get(target_idx, 0)
	if DebugConfig.reaction_debug_enabled:
		print("[Tick %d] [REACT] physical: attacker=%s target=%s last_dmg_tick=%d is_hit=%s evade_type=%d" % [
			current_tick, units[attacker_idx].name, target_unit.name, last_dmg_tick, is_hit, evade_type])

	if is_hit:
		var seq_id = ReactionType.get_seq_id(sprite_type, "taking_damage")
		if seq_id >= 0:
			target_unit.play_reaction_animation(seq_id, ReactionType.Type.TAKING_DAMAGE)
		# Hit cloud (FFT: 0xDE spawns it at the hit frame). Attribute via the
		# opcode's own attacker/target, not the one-frame damage_target pulse the
		# damage-event path can't see. ability_id -1 for a pure attack routes to the
		# default dust+flash handler.
		if spawn_hit_cloud:
			var attacker_unit: Unit = units[attacker_idx]
			if is_instance_valid(attacker_unit):
				var impact_dir := _compute_impact_direction(
					attacker_unit.global_position, target_unit.global_position)
				var ability_id := _combat_interp.last_casting_ability_id(attacker_idx)
				_spawn_hit_cloud(target_unit.global_position, impact_dir, target_unit, ability_id)
	else:
		_play_evasion_reaction(target_unit, evade_type, sprite_type)

	# Basic-melee HIT / BLOCK SFX at impact. Keyed off the ATTACKER's equipped
	# WEAPON graphic (FFT's dispatcher reads the attacker's unit+0x1ab = weapon
	# graphic — see AttackSfxResolver), NOT the target. Hit on a landed blow;
	# block when the target guards (shield evade_type 2 / blade-grasp 3); a pure
	# dodge is silent (the swing already played at onset).
	var atk_sounds: Dictionary = AttackSfxResolver.attack_sounds_for_weapon(units[attacker_idx].get_weapon_graphic())
	if is_hit:
		_play_attack_slug(atk_sounds.get("hit", ""), "hit", attacker_idx)
	elif evade_type == 2 or evade_type == 3:
		_play_attack_slug(atk_sounds.get("block", ""), "block", attacker_idx)


func _play_attack_slug(slug: String, kind: String, attacker_idx: int) -> void:
	if slug == "":
		return
	if DebugConfig.action_debug_enabled:
		print("[ATK-SFX] %s %s -> %s (weapon graphic 0x%02X)" % [
			units[attacker_idx].name, kind, slug, units[attacker_idx].get_weapon_graphic()])
	SfxRouter.play_system(slug)


func _trigger_projectile_reaction(attacker_idx: int, target_idx: int, _proj_data: Dictionary) -> void:
	"""Play hit/evade/block reaction when a projectile lands.

	Uses snapshotted evade_type from projectile spawn time since the GPU's
	live evade_type may have been overwritten by a different attack by now.
	"""
	if target_idx < 0 or target_idx >= units.size():
		return
	var target_unit = units[target_idx]
	if not is_instance_valid(target_unit) or target_unit.unit_stats.is_dead:
		return

	var sprite_type = target_unit.get_seq_type().to_lower()
	# Read evade_type at landing time (not spawn time) because for ranged attacks
	# the GPU rolls evasion at damage_frame, which is AFTER the projectile spawns.
	# By landing time, _read_tick_columns has snapshotted the correct evade_type.
	var evade_type: int = _last_evade_type.get(target_idx, 0)

	# Determine if this was a hit:
	# The GPU applies damage at damage_frame, which aligns with projectile landing
	# under SEQ-derived flight time (ADR-0038: visual flight time is the GPU's
	# damage_frame - anim_frame at spawn). Use a tight window (±N ticks) so hits
	# from OTHER arrows don't contaminate.
	var last_dmg_tick: int = _last_damage_tick.get(target_idx, -999)
	var is_hit = abs(current_tick - last_dmg_tick) <= PROJECTILE_HIT_WINDOW_TICKS

	if DebugConfig.reaction_debug_enabled:
		print("[Tick %d] [REACT] projectile: attacker=%s target=%s is_hit=%s evade_type=%d (snapshotted)" % [
			current_tick, units[attacker_idx].name if attacker_idx < units.size() else "?", target_unit.name, is_hit, evade_type])

	if is_hit:
		var seq_id = ReactionType.get_seq_id(sprite_type, "taking_damage")
		if seq_id >= 0:
			target_unit.play_reaction_animation(seq_id, ReactionType.Type.TAKING_DAMAGE)
	else:
		_play_evasion_reaction(target_unit, evade_type, sprite_type)


func _on_ability_react(_frame: int, target_idx: int, ability_id: int) -> void:
	"""Play reaction animation on target when spell effect reaches ability_react keyframe."""
	if target_idx < 0 or target_idx >= units.size():
		return
	var target_unit = units[target_idx]
	if not is_instance_valid(target_unit):
		return

	var sprite_type = target_unit.get_seq_type().to_lower()
	var ability := AbilityDatabase.get_ability_view(ability_id)
	var reaction_type_str := ability.target_reaction_type
	if reaction_type_str.is_empty():
		reaction_type_str = "taking_damage"

	if reaction_type_str == "none":
		return

	# Raise (ROM formula == 13) intentionally has NO react overlay here.
	# The rise pose is driven by the FLAG_DEAD bit-edge in `_handle_revives`
	# (which fires at first_hit_frame, aligned with the heal-applies beat),
	# not by the early ABILITY_REACT keyframe — that fires ~9 effect-frames
	# in, hundreds of frames before HP is restored, which felt wrong.
	if ability.formula == 13:
		return

	if target_unit.unit_stats.is_dead:
		return

	var seq_id = ReactionType.get_seq_id(sprite_type, reaction_type_str)
	if seq_id >= 0:
		if DebugConfig.iteration_debug_enabled:
			var paused_now: int = _all_states[target_idx].get("paused", 0) if target_idx < _all_states.size() else -1
			var cin_active: bool = cinematic_manager.is_active()
			print("[Tick %d] [REACT_FIRE] target=%s seq=%d type=%s cinematic_active=%s target_paused=%d" % [
				current_tick, target_unit.name, seq_id, reaction_type_str,
				str(cin_active), paused_now])
		target_unit.play_reaction_animation(seq_id, ReactionType.from_string(reaction_type_str), false)


func _on_hit_reaction(_frame: int, target_idx: int, ability_id: int) -> void:
	"""Drive the Raise rise pose off the CPU-side HIT_REACT keyframe.

	The cinematic spawns an EffectInstance whose PhaseBlock fires HIT_REACT
	(action_flag 0x10) at the runtime's "particles hit" beat. For Raise
	(ROM formula == 13) that is the moment the carrier should stand up —
	contemporaneous with the heal-applies beat the player sees.

	The GPU clears FLAG_DEAD later, on its own first_hit_frame schedule
	(~the cinematic teardown); `_handle_revives` still flips HP/is_dead on
	that bit-edge, but by then activity has already advanced GETTING_UP →
	IDLE via Unit._on_playback_complete, so `revive_to_idle()` is a no-op
	overlay rather than the trigger.
	"""
	if target_idx < 0 or target_idx >= units.size():
		return
	var target_unit = units[target_idx]
	if not is_instance_valid(target_unit):
		return
	var ability := AbilityDatabase.get_ability_view(ability_id)
	if ability.formula != 13:
		return
	if target_unit.anim_state:
		target_unit.anim_state.rise_from_dead()


func _on_refresh_tile(_frame: int, target_idx: int) -> void:
	"""End reaction animation on target when spell effect reaches REFRESH_TILE keyframe."""
	if target_idx < 0 or target_idx >= units.size():
		return
	var target_unit = units[target_idx]
	if not is_instance_valid(target_unit):
		return
	if target_unit.is_reacting:
		if DebugConfig.action_debug_enabled:
			print("[Tick %d] [REFRESH_TILE] %s: ending react (effect timeline)" % [
				current_tick, target_unit.name])
		target_unit.end_reaction()


func _play_evasion_reaction(target_unit, evade_type: int, sprite_type: String) -> void:
	"""Play the appropriate evasion animation based on GPU evade_type."""
	if evade_type == 2:
		var seq_id = ReactionType.get_seq_id(sprite_type, "shield_block_mid")
		if seq_id >= 0:
			target_unit.play_reaction_animation(seq_id, ReactionType.Type.SHIELD_BLOCK)
	elif evade_type == 3:
		var seq_id = ReactionType.get_seq_id(sprite_type, "receive_heal")
		if seq_id >= 0:
			target_unit.play_reaction_animation(seq_id, ReactionType.Type.BLADE_GRASP)
	else:
		var seq_id = ReactionType.get_seq_id(sprite_type, "evade")
		if seq_id >= 0:
			target_unit.play_reaction_animation(seq_id, ReactionType.Type.EVADE)


static func _compute_impact_direction(from_pos: Vector3, to_pos: Vector3) -> Vector3:
	var delta = to_pos - from_pos
	return delta.normalized() if delta.length_squared() > 0.001 else Vector3.FORWARD


func _clear_spell_cast_active(unit_idx: int):
	"""Clear spell cast active flag and resume GPU control."""
	# Safety net: discard any pending TRAP that never fired (e.g. interrupted animation)
	effect_manager.clear_pending_trap(unit_idx)
	if _spell_cast_active.get(unit_idx, false):
		_spell_cast_active[unit_idx] = false
		if DebugConfig.iteration_debug_enabled:
			var action_start = _debug_action_start_tick.get(unit_idx, current_tick)
			var anim_duration = current_tick - action_start
			print("[Tick %d] [ANIM_DEBUG] %s: Animation FINISHED (duration=%d ticks, animations=%d, projectiles=%d)" % [
				current_tick, units[unit_idx].name, anim_duration,
				_debug_animation_starts.get(unit_idx, 0),
				_debug_projectile_spawns.get(unit_idx, 0)])
		# Now that cast animation is done, sync animation to current GPU state
		var states = gpu_state_reader.get_all_unit_states()
		if unit_idx < states.size():
			var gpu_state = states[unit_idx].get("state", 0)
			# This site is off the per-event path (once per cast completion) and already
			# holds a snapshot row, so it hands its own down rather than re-fetching.
			_update_unit_animation(units[unit_idx], gpu_state, unit_idx, states[unit_idx])


func _start_attack_animation(unit: Unit, unit_idx: int):
	"""Start the correct attack animation based on weapon type."""
	_atk_n += 1
	var _p0 := Time.get_ticks_usec()
	# Get unit state for weapon type and target
	var states = gpu_state_reader.get_all_unit_states()
	var unit_state = states[unit_idx] if unit_idx < states.size() else {}
	var item_type_id = unit_state.get("weapon_type", 0)
	var target_idx = unit_state.get("target", -1)

	# Calculate vertical angle from height difference
	var vertical_angle = WeaponAnimationSelectorClass.VerticalAngle.MID
	if target_idx >= 0 and target_idx < units.size():
		var height_diff = units[target_idx].global_position.y - unit.global_position.y
		if height_diff >= 1.0:
			vertical_angle = WeaponAnimationSelectorClass.VerticalAngle.HIGH
		elif height_diff <= -1.0:
			vertical_angle = WeaponAnimationSelectorClass.VerticalAngle.LOW

	# Per ADR-0024: Unit owns the resolution-map call. unit.attack(vertical)
	# reads the equipped item from progression, consults AnimationResolutionMap
	# (ROM-parsed weapon_animation_ids.json for the BODY slot, WeaponAnimationSelector
	# for WEP1), and drives the layers. The local item_type_id we pulled from
	# the GPU state matches unit_progression's right-hand slot in steady state.
	_atk_us[0] += Time.get_ticks_usec() - _p0
	_p0 = Time.get_ticks_usec()
	unit.attack(vertical_angle)
	_atk_us[1] += Time.get_ticks_usec() - _p0
	_p0 = Time.get_ticks_usec()

	# Basic-melee SWING SFX at the attacking-animation onset. The sound class is
	# keyed off the attacker's EQUIPPED WEAPON graphic (see AttackSfxResolver —
	# FFT dispatcher FUN_80082620 reads unit+0x1ab = the weapon's graphic id). The
	# matching HIT/BLOCK plays at impact in _trigger_physical_reaction.
	var swing_slug: String = AttackSfxResolver.attack_sounds_for_weapon(unit.get_weapon_graphic()).get("swing", "")
	_atk_us[2] += Time.get_ticks_usec() - _p0
	_p0 = Time.get_ticks_usec()
	if swing_slug != "":
		if DebugConfig.action_debug_enabled:
			print("[ATK-SFX] %s swing -> %s (weapon graphic 0x%02X)" % [unit.name, swing_slug, unit.get_weapon_graphic()])
		SfxRouter.play_system(swing_slug)
	_atk_us[3] += Time.get_ticks_usec() - _p0

	# Regression logging for attack animation — read the slot Unit just resolved.
	if _rlog:
		var anim_name = "Weapon Attack (type %d)" % item_type_id
		var resolved_slot: int = unit.last_resolution.body_slot if unit.last_resolution else -1
		_rlog.log_anim(unit_idx, resolved_slot, anim_name)
		var unit_pos = Vector2i(unit_state.get("pos_x", 0), unit_state.get("pos_z", 0))
		_rlog.log_ability(unit_idx, -1, target_idx, unit_pos)


func _on_spell_cast_complete(caster_idx: int, ability_id: int, target_idx: int, _all_states: Array):
	"""Handle spell cast completion - play cast animation and spawn effect.

	Called when GPU transitions casting_ability_id from valid to -1.
	"""
	if caster_idx >= units.size():
		return

	var caster = units[caster_idx]
	if not is_instance_valid(caster):
		return

	# Set active ability for animation lookup
	caster.active_ability_id = ability_id

	# Look up ability data (used for item check, effect spawning, etc.)
	var ability := AbilityDatabase.get_ability_view(ability_id)

	# Face toward target for all abilities except self-targeted ones.
	if target_idx != caster_idx and target_idx >= 0 and target_idx < units.size():
		var target = units[target_idx]
		if is_instance_valid(target):
			caster.face_toward_unit(target)
	if DebugConfig.iteration_debug_enabled:
		print("  [FACING_DEBUG] %s: facing=%d camera_quad=%d target_idx=%d (self=%s)" % [
			caster.name, caster.facing_direction, caster.get_camera_quadrant(),
			target_idx, str(target_idx == caster_idx)])

	# Set distort context for movement opcodes (Dash, etc.)
	var caster_state_dc = _all_states[caster_idx] if caster_idx < _all_states.size() else {}
	# The GPU sim runs on the GROUND PLANE, so a unit state's `pos_x`/`pos_z` name a
	# level-0 cell by declaration, not by omission. ADR-0224 moved WHERE that
	# declaration is made: `build_map_data` carries two planes now, but every
	# accessor in `combat_common.glslinc` still indexes a column and
	# `DistanceFieldGenerator` still bakes one plane, so the sim's answer is
	# unchanged until the shader pass lands.
	var caster_cell_dc := TerrainCell.ground(
		caster_state_dc.get("pos_x", 0), caster_state_dc.get("pos_z", 0))
	# Existence and position are two questions on the port: `world_position_at` is a
	# scalar and cannot say "no cell" (ADR-0192 dec. 6). This is the ability path, not
	# the per-frame one, so the extra lookup is not on any hot loop.
	var home_pos = lattice.world_position_at(caster_cell_dc) \
		if lattice.terrain_at(caster_cell_dc) != null else caster.global_position
	var distort_target_pos = home_pos  # Default: no target movement
	if target_idx >= 0 and target_idx < units.size() and target_idx != caster_idx:
		var target_state_dc = _all_states[target_idx] if target_idx < _all_states.size() else {}
		var target_cell_dc := TerrainCell.ground(
			target_state_dc.get("pos_x", 0), target_state_dc.get("pos_z", 0))
		if lattice.terrain_at(target_cell_dc) != null:
			distort_target_pos = lattice.world_position_at(target_cell_dc)
	caster.set_distort_context(home_pos, distort_target_pos)

	# Regression logging for ability use
	var caster_state = _all_states[caster_idx] if caster_idx < _all_states.size() else {}
	var caster_pos = Vector2i(caster_state.get("pos_x", 0), caster_state.get("pos_z", 0))
	if _rlog:
		_rlog.log_ability(caster_idx, ability_id, target_idx, caster_pos)

	# Check if this is an item ability - items use WEP1 THROW animation, not TYPE1
	var is_item = ability.ability_type == "Item"

	# Cinematic (charged) casts already spawned their EffectInstance on the
	# cinematic-timer edge (CinematicManager._handle_began -> spawn_cinematic_effect,
	# issue #53). This resolution-time path must NOT spawn the same effect a second
	# time, or every charged spell plays its effect twice ("once during the
	# cinematic, once after"). The GPU routes charge_time > 0 abilities to
	# cast_cinematic_spell (stage_spell.glsl:633); packed charge_time == ct*30 for
	# non-items and is force-zeroed for items (GPUAbilityLoader), so the exact CPU
	# mirror of "did this go cinematic" is `ct > 0 AND not is_item`. Items are never
	# cinematic and keep their resolution spawn. The animation / facing / distort
	# side-effects below still run for cinematic casts — only the effect spawn is
	# owned exclusively by the cinematic path.
	var is_cinematic := ability.ct > 0 and not is_item

	if is_item:
		# Check distance to determine adjacent item use vs thrown item
		var target_state = _all_states[target_idx] if target_idx < _all_states.size() else {}
		var target_pos = Vector2i(target_state.get("pos_x", 0), target_state.get("pos_z", 0))
		var dist = abs(caster_pos.x - target_pos.x) + abs(caster_pos.y - target_pos.y)

		if DebugConfig.iteration_debug_enabled:
			print("  [ITEM_DEBUG] %s: ability_id=%d caster_pos=%s target_pos=%s dist=%d target_idx=%d" % [
				caster.name, ability_id, caster_pos, target_pos, dist, target_idx])
			print("  [ITEM_DEBUG] ability data: %s" % str(ability.to_dict()))

		if dist <= 1:
			# Adjacent item use — USING_ITEM state drives SEQ 114/115 via StateAnimationDatabase
			# update_animation() will re-derive correctly on camera rotation / facing change
			if _rlog:
				_rlog.log_anim(caster_idx, 114, "Item Use")
			if DebugConfig.iteration_debug_enabled:
				print("  [ITEM_DEBUG] ADJACENT item -> USING_ITEM state (SEQ 114/115)")
			if DebugConfig.iteration_debug_enabled:
				print("  [ANIM] %s: -> USING_ITEM" % caster.name)
			caster.active_ability_id = ability_id
			caster.activity = DisplayActivity.Activity.USING_ITEM

			# Spawn item effect directly — the generic spell effect path doesn't handle
			# item effect_ids (which have 2048 offset) and checks has_effect_file which
			# is false for items. spawn_item_effect handles the conversion correctly.
			var item_effect_id = ability.effect_id
			if item_effect_id is int and item_effect_id > GPUConstants.ITEM_EFFECT_ID_OFFSET:
				var effect_dir_num = item_effect_id - GPUConstants.ITEM_EFFECT_ID_OFFSET
				if target_idx >= 0 and target_idx < units.size():
					var target = units[target_idx]
					if is_instance_valid(target):
						if DebugConfig.iteration_debug_enabled:
							print("  [ITEM_DEBUG] Spawning adjacent item effect E%03d at %s" % [effect_dir_num, target.name])
						effect_manager.spawn_item_effect(target, effect_dir_num)
			# Return early — skip the generic spell effect path below
			return
		else:
			# Thrown item - Throw Weapon animation (Path-D anim_id 77 → SEQ slots
			# 152 front / 153 back; the painter derives front/back per facing).
			# Uses the fixed-anim-id attack path because item effect_anim_id doesn't
			# map to the throw animation — it's a fixed animation for all thrown
			# items. Protected from facing-change overwrite by spell_cast_triggered guard.
			const TYPE1_THROW_WEAPON_ANIM_ID = 77
			if _rlog:
				_rlog.log_anim(caster_idx, TYPE1_THROW_WEAPON_ANIM_ID, "Throw Weapon")
			if DebugConfig.iteration_debug_enabled:
				print("  [ITEM_DEBUG] THROWN item (dist=%d) -> TYPE1_THROW_WEAPON anim_id %d (SEQ 152/153)" % [dist, TYPE1_THROW_WEAPON_ANIM_ID])
			if DebugConfig.iteration_debug_enabled:
				print("  [ANIM] %s: -> THROW_WEAPON (Path-D anim_id %d)" % [caster.name, TYPE1_THROW_WEAPON_ANIM_ID])
			caster.start_attack_with_anim_id(TYPE1_THROW_WEAPON_ANIM_ID)
	else:
		# Check if this ability uses the weapon's range and attack animation.
		# weapon_range == true means the ability inherits from the equipped weapon -
		# it should play the weapon attack animation (swing/thrust).
		# Examples: Knight Breaks (138-145), Holy Swords (155-165)
		var uses_weapon_range = ability.weapon_range
		if uses_weapon_range:
			# Weapon ability - play weapon attack animation
			if DebugConfig.iteration_debug_enabled:
				var ability_name = ability.name if not ability.is_empty() else "Attack"
				print("  [ANIM] %s: -> ATTACKING (weapon ability: %s)" % [caster.name, ability_name])
			_start_attack_animation(caster, caster_idx)
		else:
			# Spell-like ability - play TYPE1 casting animation
			var anim_id = ability.effect_anim_id
			var ability_name = ability.name if not ability.is_empty() else "Spell"
			if _rlog:
				_rlog.log_anim(caster_idx, anim_id, ability_name)
			if DebugConfig.iteration_debug_enabled:
				print("  [ANIM] %s: -> SPELL_CASTING" % caster.name)
			# Parameterized activity per ADR-0024 — see LOGICAL_ACTIVITY_SPELL_CHARGING note.
			caster.cast_spell(ability_id)

	# Look up ability data for effect (reuse ability from above)
	if ability.is_empty():
		return

	# Get effect info
	var effect_id = ability.effect_id
	if effect_id == null:
		effect_id = 0
	var ability_name = ability.name if not ability.is_empty() else "Unknown"

	var has_effect = ability.has_effect_file
	if DebugConfig.iteration_debug_enabled:
		print("  [EFFECT_DEBUG] %s: effect_id=%s has_effect=%s is_item=%s ability_name=%s" % [
			caster.name, str(effect_id), str(has_effect), str(is_item), ability_name])
		if is_item and effect_id is int and effect_id > GPUConstants.ITEM_EFFECT_ID_OFFSET:
			print("  [EFFECT_DEBUG] Item effect_id %d > 2048, converted = E%03d (dir num %d)" % [
				effect_id, effect_id - GPUConstants.ITEM_EFFECT_ID_OFFSET, effect_id - GPUConstants.ITEM_EFFECT_ID_OFFSET])
			print("  [EFFECT_DEBUG] BUG: spell_effect_hook would use E%03d (WRONG) instead of E%03d" % [
				effect_id, effect_id - GPUConstants.ITEM_EFFECT_ID_OFFSET])

	if DebugConfig.iteration_debug_enabled:
		if has_effect and effect_id > 0:
			print("  [SPELL] %s casts %s (ID %d, effect E%03d)" % [caster.name, ability_name, ability_id, effect_id])
		else:
			print("  [ABILITY] %s uses %s (ID %d)" % [caster.name, ability_name, ability_id])

	# Spawn visual effect if ability has one — but NOT for cinematic casts, whose
	# effect is owned by CinematicManager (see is_cinematic note above).
	if is_cinematic:
		if DebugConfig.iteration_debug_enabled and has_effect and effect_id > 0:
			print("  [SPELL] %s: cinematic cast — effect E%03d owned by CinematicManager, skipping resolution spawn" % [caster.name, effect_id])
	elif has_effect and effect_id > 0 and target_idx >= 0 and target_idx < units.size():
		var effect_area = ability.effect_area
		if effect_area > 0:
			# AOE: spawn effect at every unit within manhattan distance of target
			var target_state = _all_states[target_idx] if target_idx < _all_states.size() else {}
			var center = Vector2i(target_state.get("pos_x", 0), target_state.get("pos_z", 0))
			var caster_team = _all_states[caster_idx].get("team", 0) if caster_idx < _all_states.size() else 0
			# WHICH SIDE the effect is drawn on is a FAMILY question — *who is this
			# ability for* — and since ADR-0278 [AbilityFamily] is what answers it.
			# It used to be read off `is_healing`, which is the HP-write DIRECTION and
			# a different axis (docs/context/07-ability-hit-policy.md retires exactly
			# that conflation from the kernel; this call site outlived it). The two
			# disagree on 32 of the 193 records this branch can reach and every one of
			# them is ally-side — `Protect`, `Shell`, `Haste`, `Esuna`, `Chakra`, every
			# Song — so an AoE buff sprayed its visual on the ENEMY party. See #1148.
			var is_ally_side = AbilityFamily.is_ally_side(AbilityFamily.of_id(ability_id))
			for i in range(mini(_all_states.size(), units.size())):
				if _is_unit_dead(_all_states[i]):
					continue
				var upos = Vector2i(_all_states[i].get("pos_x", 0), _all_states[i].get("pos_z", 0))
				var dist = abs(upos.x - center.x) + abs(upos.y - center.y)
				if dist > effect_area:
					continue
				var unit_team = _all_states[i].get("team", 0)
				if is_ally_side and unit_team != caster_team:
					continue
				if not is_ally_side and unit_team == caster_team:
					continue
				if is_instance_valid(units[i]):
					_spawn_spell_effect(caster, units[i], ability_id, effect_id)
		else:
			var target = units[target_idx]
			if is_instance_valid(target):
				if DebugConfig.iteration_debug_enabled:
					print("  [EFFECT_DEBUG] Calling spell_effect_hook with raw effect_id=%d -> path will be E%03d" % [effect_id, effect_id])
				_spawn_spell_effect(caster, target, ability_id, effect_id)


## Route the spell-effect spawn through the host-supplied seam so a test can wrap
## it (ADR-0018). Falls back to the effect manager when no host hook is set.
func _spawn_spell_effect(caster: Unit, target: Unit, ability_id: int, effect_id: int) -> void:
	if spell_effect_hook.is_valid():
		spell_effect_hook.call(caster, target, ability_id, effect_id)
	else:
		effect_manager.spawn_spell_effect(caster, target, ability_id, effect_id)


## Route the hit cloud through the host seam (sibling of _spawn_spell_effect) so
## a test can observe it. Falls back to the effect manager (is_melee=true) when
## no host hook is set. The handler (dust / Knight-Break triangles) is chosen
## from the ability formula inside spawn_trap_effect.
func _spawn_hit_cloud(position: Vector3, impact_dir: Vector3, target: Node, ability_id: int) -> void:
	if hit_cloud_hook.is_valid():
		hit_cloud_hook.call(position, impact_dir, target, ability_id)
	else:
		effect_manager.spawn_trap_effect(position, impact_dir, target, ability_id, true)


func _on_projectile_landed(caster_idx: int, target_idx: int, proj_data: Dictionary) -> void:
	"""Dispatch effects and reactions when a projectile reaches its target."""
	if target_idx < 0 or target_idx >= units.size():
		return
	var target = units[target_idx]
	if not is_instance_valid(target):
		return

	var ability_id = proj_data.get("ability_id", -1)
	var proj_type = proj_data.get("projectile_type", Projectile3D.ProjectileType.ARROW)

	if proj_type not in [Projectile3D.ProjectileType.POTION, Projectile3D.ProjectileType.ITEM]:
		# Attack projectile - spawn hit cloud and trigger reaction
		var start_pos = proj_data.get("start_pos", target.global_position)
		var impact_dir = _compute_impact_direction(start_pos, target.global_position)
		effect_manager.spawn_trap_effect(target.global_position, impact_dir, target, ability_id, false)
		if caster_idx >= 0:
			_trigger_projectile_reaction(caster_idx, target_idx, proj_data)

	if proj_type == Projectile3D.ProjectileType.ITEM and ability_id > 0:
		# Item ability - spawn item effect
		var ability := AbilityDatabase.get_ability_view(ability_id)
		var effect_id = ability.effect_id if ability.effect_id != null else 0
		if effect_id > GPUConstants.ITEM_EFFECT_ID_OFFSET:
			var effect_dir_num = effect_id - GPUConstants.ITEM_EFFECT_ID_OFFSET
			effect_manager.spawn_item_effect(target, effect_dir_num)

		# Apply deferred healing on hit
		if caster_idx >= 0 and proj_data.get("is_item_ability", false):
			_apply_projectile_heal(caster_idx, target_idx)


func _apply_projectile_heal(caster_idx: int, target_idx: int) -> void:
	"""Apply deferred healing when a healing projectile lands."""
	if not gpu_simulator or not gpu_state_reader:
		return
	var states = gpu_state_reader.get_all_unit_states()
	if caster_idx >= states.size():
		return
	var caster_state = states[caster_idx]
	var pending_target = caster_state.get("pending_heal_target", -1)
	var pending_amount = caster_state.get("pending_heal_amount", 0)
	if pending_target != target_idx or pending_amount <= 0:
		return
	gpu_simulator.apply_pending_heal(0, caster_idx, target_idx, pending_amount)
	if DebugConfig.iteration_debug_enabled:
		print("[Tick %d] [HEAL_ON_HIT] %s healed %s for %d (projectile landed)" % [
			current_tick, units[caster_idx].name, units[target_idx].name, pending_amount])


## Write this loop's settle-brake arm through to the kernel. Idempotent, and safe
## before the simulator exists — `boot_battle` re-runs it for exactly that case.
func _apply_settle_brake() -> void:
	if gpu_simulator == null:
		return
	gpu_simulator.settle_brake_battle = 0 if (settle_before_victory and not _settle_expired) else -1


## The units the settle brake is currently holding a decided battle open for, as
## `[{ "index": int, "name": String, "state": int }]`. Empty when the fight is not
## decided, when nothing is armed, or when everyone has landed.
##
## THE SAME POPULATION `stage_victory` IS COUNTING, read back so a human can be told
## WHO. That shader reports a win when every living unit of the surviving team is
## CELEBRATING; this returns the living units of that team which are not. There is no
## second idea of "settled" here and there must not be — the kernel decides, and this
## only names its answer (`settle_awaited_state` in `combat_common.glslinc`).
##
## The position half needs no term of its own: the brake leaves U_TIMER alone, so an
## awaited unit is flipped only once its step has fully drained, and
## `GPUMovementVisualizer.calculate_position(0)` returns `end_pos` exactly then. A
## kernel-settled unit is a unit standing on its own tile, by construction.
func settling_units() -> Array:
	var out: Array = []
	if gpu_state_reader == null or gpu_simulator == null:
		return out
	# The HOT snapshot (39 fields): `flags`, `state` and `team` are the only three
	# read here and all three are in `SNAPSHOT_HOT_UNION`. It shares a version cache
	# with the visual bridge, which has already built it this frame — so the
	# per-frame backstop below costs a dictionary walk and no device sync.
	var states: Array = gpu_state_reader.get_all_unit_states_hot()
	var alive := [0, 0]
	for i in range(mini(states.size(), units.size())):
		if not _is_unit_dead(states[i]):
			alive[int(states[i].get("team", 0)) & 1] += 1
	# Not decided (or a draw): nobody is being held for.
	if alive[0] > 0 and alive[1] > 0:
		return out
	if alive[0] == 0 and alive[1] == 0:
		return out
	var winner := 0 if alive[1] == 0 else 1
	for i in range(mini(states.size(), units.size())):
		var state: Dictionary = states[i]
		if _is_unit_dead(state) or (int(state.get("team", 0)) & 1) != winner:
			continue
		if int(state.get("state", 0)) == GPUConstants.LOGICAL_ACTIVITY_CELEBRATING:
			continue
		out.append({
			"index": i,
			"name": units[i].name if is_instance_valid(units[i]) else "<freed>",
			"state": int(state.get("state", 0)),
		})
	return out


## The [member settle_backstop_seconds] backstop. Counts only real time in which the
## brake was actually holding a decided battle open, so a battle that simply has not
## been won yet never burns it.
func _tick_settle_backstop(delta: float) -> void:
	if not settle_before_victory or _settle_expired or victory_achieved:
		return
	var pending: Array = settling_units()
	if pending.is_empty():
		_settle_wait = 0.0
		return
	_settle_wait += delta
	if _settle_wait < settle_backstop_seconds:
		return
	_settle_expired = true
	var who: Array = []
	for row in pending:
		var st: int = int(row["state"])
		var sname: String = GPUConstants.LOGICAL_ACTIVITY_NAMES[st] if st < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else str(st)
		who.append("%s(i=%d, %s)" % [row["name"], int(row["index"]), sname])
	push_warning(("[%s] SETTLE BACKSTOP after %.2fs — the battle is decided but %d unit(s) "
		% [battle_name, _settle_wait, pending.size()])
		+ "never settled: %s. " % ", ".join(who)
		+ "The kernel brake is meant to make this unreachable; declaring the win anyway.")
	_apply_settle_brake()


func _check_victory():
	# Use GPU battle result — victory is only reported after all survivors are VICTORIOUS
	if not gpu_state_reader.is_battle_finished():
		return

	var result = gpu_state_reader.get_battle_result()
	var winner = result.get("winner", -1)

	var states = gpu_state_reader.get_all_unit_states()
	var team0_alive = 0
	var team1_alive = 0
	for i in range(states.size()):
		var is_dead = _is_unit_dead(states[i])
		if not is_dead:
			if states[i].get("team", 0) == 0:
				team0_alive += 1
			else:
				team1_alive += 1

	victory_achieved = true
	combat_active = false
	_handle_deaths()

	# Host owns the regression-log victory entry, the print, and whether to quit
	# (the test base quits; the arena keeps the scene alive). The loop just reports.
	victory.emit(winner, team0_alive, team1_alive)


func _handle_deaths():
	var states = gpu_state_reader.get_all_unit_states()
	for i in range(mini(states.size(), units.size())):
		var state = states[i]
		var is_dead = _is_unit_dead(state)
		if is_dead and not units[i].unit_stats.is_dead:
			units[i].unit_stats.is_dead = true
			units[i].unit_stats.current_hp = 0
			units[i].activity = DisplayActivity.Activity.DYING
		elif not is_dead and units[i].unit_stats.is_dead:
			# Reraise revive backstop (issue #108). The per-tick _handle_revives
			# already catches the bit-edge live; this mirror in the end-of-battle
			# pass keeps the forward/reverse branches symmetric in case the GPU
			# revives a unit on the same tick the battle finishes.
			units[i].unit_stats.revive(int(state.get("hp", 0)))


func _handle_revives():
	"""Mirror of _handle_deaths for the alive transition (issue #108).

	Runs per-tick from `tick()` so the Reraise revive — GPU clears FLAG_DEAD
	at the E007 cinematic's first_hit_frame — is observed live, and the
	carrier visibly stands up while the cinematic is still tearing down.
	The interpreter only emits DIED events; there is no REVIVED kind, so
	the bit-edge is read directly off `_all_states` instead.
	"""
	for i in range(mini(_all_states.size(), units.size())):
		var state = _all_states[i]
		if _is_unit_dead(state):
			continue
		if not units[i].unit_stats.is_dead:
			continue
		var revive_hp: int = int(state.get("hp", 0))
		units[i].unit_stats.revive(revive_hp)
		if DebugConfig.iteration_debug_enabled:
			print("[Tick %d] [REVIVE] %s revived to hp=%d" % [
				current_tick, units[i].name, revive_hp])


func _log_initial_state():
	if not DebugConfig.iteration_debug_enabled:
		return

	var states = gpu_state_reader.get_all_unit_states()
	print("[%s] Initial State:" % battle_name)
	for i in range(mini(states.size(), units.size())):
		var s = states[i]
		print("  %s: pos=(%d,%d) hp=%d/%d team=%d weapon_range=%d weapon_flags=%d" % [
			units[i].name, s["pos_x"], s["pos_z"], s["hp"], s["max_hp"], s["team"],
			s.get("weapon_range", -1), s.get("weapon_flags", -1)
		])
	print("")


func _log_state_change(unit_idx: int, old_state: int, new_state: int, state: Dictionary):
	if not DebugConfig.iteration_debug_enabled:
		return

	var old_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[old_state] if old_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else "?"
	var new_name = GPUConstants.LOGICAL_ACTIVITY_NAMES[new_state] if new_state < GPUConstants.LOGICAL_ACTIVITY_NAMES.size() else "?"

	# Extended debug info
	var casting_id = state.get("casting_ability_id", -1)
	var cast_target = state.get("cast_target", -1)
	var anim_frame = state.get("anim_frame", 0)
	var damage_frame = state.get("damage_frame", 0)
	var total_frames = state.get("total_frames", 0)
	var anim_flags = state.get("anim_flags", 0)

	print("[Tick %d] %s: %s -> %s (timer=%d target=%d casting=%d cast_target=%d)" % [
		current_tick, units[unit_idx].name, old_name, new_name,
		state.get("timer", 0), state.get("target", -1), casting_id, cast_target
	])

	# Log animation state for ACTING
	if new_state == GPUConstants.LOGICAL_ACTIVITY_ACTING:
		print("  [DEBUG] ACTING: anim_frame=%d damage_frame=%d total_frames=%d anim_flags=%d" % [
			anim_frame, damage_frame, total_frames, anim_flags
		])


func _log_hp_change(unit_idx: int, old_hp: int, new_hp: int, delta: int):
	if not DebugConfig.iteration_debug_enabled:
		return

	var change_type = "healed" if delta > 0 else "took"

	# Also log attacker info from GPU state
	var states = gpu_state_reader.get_all_unit_states()
	var attacker_info = ""
	for i in range(states.size()):
		var state = states[i]
		var damage_target = state.get("damage_target", -1)
		var damage_amount = state.get("damage_amount", 0)
		if damage_target == unit_idx and damage_amount > 0:
			attacker_info = " (from unit %d, damage_amount=%d)" % [i, damage_amount]
			break

	print("[Tick %d] %s %s %d (HP: %d -> %d)%s" % [
		current_tick, units[unit_idx].name, change_type, abs(delta), old_hp, new_hp, attacker_info
	])
