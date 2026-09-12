class_name GPUBatchSimulator
extends RefCounted

## GPU Batch Combat Simulator - Double-Buffer Parallel Architecture
##
## Uses a ping-pong buffer approach for true simultaneity:
## 1. All units read from current buffer (same snapshot)
## 2. All units compute their next state IN PARALLEL
## 3. All units write to next buffer
## 4. Conflicts resolved, damage applied, victory checked
## 5. Buffers swapped (next becomes current)
##
## This achieves CPU parity because the CPU processes all units in the
## same frame via async/await - they all see the same game state.
##
## Usage:
##   var sim = GPUBatchSimulator.new()
##   sim.initialize(lattice, distance_field, 1, 8)
##   sim.set_battle_units(0, team0_configs, team1_configs, randi())
##
##   # Step simulation one tick at a time (interactive/visual mode)
##   sim.step_tick(1)
##
##   # Read unit states for visual sync
##   var states = reader.get_all_unit_states()

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell


#region Map Buffer Layout
## THE MAP STORAGE BUFFER IS LEVEL-MAJOR (ADR-0224 dec. 2), and that is the whole
## reason it could widen in a commit that moves no behaviour.
##
## With `T = map_width * map_height` (the PER-LEVEL tile count) and
## `idx = gz * map_width + gx`, level `L`'s block starts at
## `L * MAP_PLANES_PER_LEVEL * T` and holds:
##
##     +0*T   heights                    [idx]
##     +1*T   traversable                [idx]
##     +2*T   cliff edge -> level 0      [idx * 4 + dir]
##     +6*T   cliff edge -> level 1      [idx * 4 + dir]
##
## `dir` is this file's own order, N(+X) E(+Z) S(-X) W(-Z), and the shader's
## `get_move_direction` agrees with it.
##
## 🔴 LEVEL 0'S FIRST SIX PLANES ARE THE PRE-ADR-0224 BUFFER, BYTE FOR BYTE.
## `heights`, `traversable` and `cliff -> level 0` sit at exactly the offsets they
## sat at before this buffer knew about levels, so every existing shader offset —
## `total_tiles * 2 + idx * 4 + dir` and friends — keeps reading level 0 and keeps
## reading it unchanged. `tests/GPUMapBufferLevelRatchetTest.gd` is the ratchet on
## that claim, over all 119 exported maps.
##
## Cliff edges are 8 per cell rather than 4 (ADR-0224 dec. 3): a step now has up
## to two destinations per direction, so a per-direction verdict cannot state the
## answer. They are laid out as two 4-wide groups BY TARGET LEVEL, not one 8-wide
## group per cell, because the target-level-0 group has to keep the stride the
## shader already computes. The verdict itself stays the port's `is_cliff_edge`
## (ADR-0164 dec. 2) — it is decided from `tile_vertices` and the tile transform,
## which are terrain facts this system cannot see.
##
## ⚠️ NOTHING READS THE UPPER BLOCK YET. The compute shader still column-indexes,
## so all twelve ADR-0224 slots misbehave exactly as they did before this widening
## (ADR-0224 P2). The reader is the shader pass, and it is a separate PR.
const MAP_CLIFF_DIRECTIONS := 4
## `heights + traversable + cliff x 4 directions x LEVEL_COUNT target levels`.
const MAP_PLANES_PER_LEVEL := 2 + MAP_CLIFF_DIRECTIONS * TerrainCell.LEVEL_COUNT
#endregion


#region Instance State
var _rd: RenderingDevice = null
var _shaders: Array[RID] = []       # 5 shader RIDs (one per pass)
var _pipelines: Array[RID] = []     # 5 pipeline RIDs (one per pass)

# Buffers
var _config_buffer: RID
# Batched multi-tick-per-submit (Phase 2a). A CPU `buffer_update` can't flip
# `current_buffer` mid-compute-list (all dispatches in one submission would alias
# the last-written value), so the batched path pre-bakes two config buffers that
# differ ONLY in `current_buffer` (0/1) and parallel uniform sets bound to each.
# A K-tick run then flips the ping-pong per tick by binding the matching set
# instead of updating a shared uniform. See _create_batched_uniform_sets /
# _run_ticks_batched.
var _config_buffer_pair: Array = []   # [RID current_buffer=0, RID current_buffer=1]
# Last config block uploaded into `_config_buffer_pair`, `current_buffer`
# normalised out (the pair BAKES that one, so it is the only index that legally
# differs between the two members). Empty so the first `_update_config` always
# writes through.
#
# It is the WHOLE block and not the two pacing ints it used to be: a comparison
# that names specific fields silently drops every field added after it, and
# `turn_brake_battle` was exactly that field — dropped on every `step_tick(K>1)`,
# which is most ticks.
var _last_pair_data: PackedInt32Array = PackedInt32Array()
var _uniform_sets_pair: Array = []    # [[8 sets bound to cb=0], [8 sets bound to cb=1]]
# Readback cache. Each `buffer_get_data` is a blocking full device sync (~150µs
# on a 5090 — 2x a step_tick fence), and a combat frame re-reads the SAME
# unchanged battle buffer several times: the per-tick loop reads a handful of lean
# columns (read_unit_column: HP / EVADE_TYPE / CINEMATIC_TIMER / PAUSED), then
# after the loop _check_state_changes + visual read the full snapshot. We read the
# whole single-battle region ONCE per _battle_version and serve read_unit_column /
# get_battle_unit_states / get_battle_state / get_battle_tick / is_battle_finished
# from it — so a tick's lean columns all share one sync. Every _battle_buffer write
# bumps the version, so a mid-frame apply_pending_heal correctly forces a re-read
# while an unchanged buffer is a free cache hit.
var _battle_version: int = 0
var _rb_cache_version: int = -1
var _rb_cache_battle_id: int = -1
var _rb_cache_data: PackedInt32Array = PackedInt32Array()
# Higher-level caches keyed by the same version: the fully BUILT unit-state array
# and battle-state dict. Measurement showed the ~150µs/call cost of
# get_battle_unit_states is dominated by the GDScript dict-BUILDING (~130µs), not
# the GPU readback (~20µs) — so caching only the raw bytes barely helped. Callers
# treat the returned snapshot as READ-ONLY (ADR-0018: side-effects go through
# events, never by mutating a snapshot), so the shared reference is safe.
var _rb_states_version: int = -1
var _rb_states_battle_id: int = -1
var _rb_states_cache: Array[Dictionary] = []
var _rb_bstate_version: int = -1
var _rb_bstate_battle_id: int = -1
var _rb_bstate_cache: Dictionary = {}

# Lean per-frame snapshot cache (W1). Separate from _rb_states_* on purpose: the
# two per-frame callers share THIS one, so the first of them after a version bump
# pays the 39-field build and the second is free — while a cold caller asking for
# the full 101-field form does not evict it, and does not get served a lean dict.
var _rb_hot_version: int = -1
var _rb_hot_battle_id: int = -1
var _rb_hot_cache: Array[Dictionary] = []

## TEST-ONLY. When true, the LEAN per-frame snapshot carries all 101 keys instead
## of 39, with every key OUTSIDE SNAPSHOT_HOT_UNION set to POISON_VALUE. A seeded
## battle must then reach the same outcome as a clean one — if it does not, some
## per-frame consumer reads a field the union omits, which is exactly W1's silent
## failure mode, made loud.
## Driven by tests/GPUSnapshotUnionTest.tscn; never set in production.
var debug_poison_non_union: bool = false
const POISON_VALUE: int = -999_777_333
var _map_buffer: RID
var _distance_buffer: RID
var _battle_buffer: RID
var _results_buffer: RID
var _anim_timings_buffer: RID
var _gambit_buffer: RID      # Binding 6: Per-unit gambit data
var _ability_buffer: RID     # Binding 7: Ability database
var _effect_timings_buffer: RID  # Binding 8: Per-effect cinematic timings (issue #53)
var _cooldown_buffer: RID    # Binding 9: Per-(unit, ability_id) cooldown_ready_at (ADR-0047 / issue #85)

# Uniform sets (one per shader variant for RD compatibility)
var _uniform_sets: Array[RID] = []

# Cached ability data for CPU-side access
var _ability_database: Dictionary = {}

# Configuration
var _num_battles: int = 0
var _units_per_battle: int = 8
var _map_width: int = 0
var _map_height: int = 0
#endregion

#region Constants & Enums (must match shader)
# The per-battle RESULT RECORD's width. Shader-authoritative (ADR-0001) and
# generated into `GPUCombatPacker` by `tools/gen_gpu_layout.py`, so the one place
# it is written is `combat_common.glslinc`. It used to be a GD-only `4` here,
# sitting opposite a literal `battle_id * 4` in `stage_victory.glsl` — the same
# number authored twice, which is exactly the shape widening the record for
# #896's value function would have broken silently.
const RESULT_SIZE = GPUCombatPacker.RESULT_SIZE

# Animation timing buffer size
const MAX_ANIMATIONS = GPUConstants.MAX_ANIMATIONS

# Gambit buffer constants (canonical values in GPUConstants)
const MAX_GAMBITS = GPUConstants.MAX_GAMBITS
const GAMBIT_SIZE = GPUConstants.GAMBIT_SIZE
const GAMBITS_PER_UNIT = MAX_GAMBITS * GAMBIT_SIZE  # 96 ints per unit

# Ability buffer constants (canonical values in GPUConstants)
const MAX_ABILITIES = GPUConstants.MAX_ABILITIES
const ABILITY_SIZE = GPUConstants.ABILITY_SIZE

# Cooldown SSBO width (ADR-0047 / issue #85). Mirrors the shader value;
# kept here rather than in GPUConstants because only the simulator needs
# it (buffer sizing + per-battle reset). If you change this, update
# combat_common.glslinc to match.
#
# 128 until #1108. It is now the FULL ability table, so no ability id falls
# through the cooldown veto un-gated — 240 of the 384 ids that used to sit above
# the ceiling are ordinary `Normal` abilities, not the summons the old comment
# assumed. Costs `total_units * this * 4` bytes of VRAM (4 MiB -> 16 MiB on the
# default 1024x8 fleet) and nothing per tick, because this buffer is
# deliberately outside `copy_unit_to_next`.
const MAX_COOLDOWN_ABILITIES = 512

# Shader pass modes. The integer values index into _pipelines / _uniform_sets,
# which are populated from `STAGE_FILES` by `_build_stages` — so the order here
# MUST match the file order in that array. The dispatch order in _run_tick() is
# independent and can call passes in any sequence.
const PASS_COMPUTE_STATE = 0
const PASS_RESOLVE_CONFLICTS = 1
const PASS_POST_CONFLICT_ATTACKS = 2
const PASS_APPLY_DAMAGE = 3
const PASS_CHECK_VICTORY = 4
# Stage 2b Phase 3 — ACTION_ATTACK dispatch runs in its own pipeline,
# one thread per unit, right after PASS_COMPUTE_STATE.
const PASS_ATTACK = 5
# Stage 2b Phase 4 — spell/ability/item + LOGICAL_ACTIVITY_SPELL_CHARGING completion,
# one thread per unit, right after PASS_ATTACK.
const PASS_SPELL = 6
# Stage 2b Phase 5 — pathfinding (MOVE_TO / PATHFIND_MOVE / PATHFIND_CAST),
# one thread per unit, right after PASS_SPELL.
const PASS_PATHFIND = 7

# --- Pacing tunables (ADR-0068) ----------------------------------------------
# FFT's numbers were calibrated against a TURN. This kernel is turnless, so the
# same numbers resolve far faster than the ROM's pace. These two knobs re-time
# that balance rather than re-authoring it; they ride the config buffer (see
# `scale_move_ticks` / `scale_hp_transfer` in combat_common.glslinc) so a rollout
# battle forks a world with the SAME pacing as the live one.
#
# `static var` and not `const` because a `const` is frozen at parse time and a
# scrub could never reach its readers (ADR-0068 dec. 13). `_update_config` is the
# reader, and it PULL-READS `Tune.get_value` every pass rather than taking an
# `on_update` write-back: `Tune.on_update` is Node-scoped (it hangs the
# unsubscribe off `tree_exited`) and this is a RefCounted.

const MOVE_TIME_SCALE_SLUG := "pacing.move_time_scale"
const DAMAGE_SCALE_SLUG := "pacing.damage_scale"

## Multiplier on how long one movement step takes. >1.0 = slower travel, which
## lengthens the approach against a fixed action period and favours ranged.
static var move_time_scale: float = 1.0

## Multiplier on every HP transfer -- damage AND healing, so the ratio between
## them is preserved. <1.0 = more hits to kill, which is what buys the fight room
## for more to happen in it.
static var damage_scale: float = 1.0

# Q8 fixed point: the shader reads these as ints, 256 == 1.0x.
const _PACING_Q8 := 256


## THE TURN BRAKE: the battle index that stops for turns, or -1 for none.
##
## Set by [TurnDirector] when its host [member TurnDirector.stops_the_world], so a
## ready unit in that battle settles into IDLE instead of starting another
## movement step and the freeze lands on a unit that is exactly on its tile. See
## the long note on `turn_brake_battle` in `combat_common.glslinc` for why this is
## a config uniform and not a unit field — a unit field would ride
## `snapshot_battle`/`restore_battle` into every rollout candidate, where nothing
## consumes turns, and brake the whole fleet.
##
## A plain member and not a `static var` tunable: it names a BATTLE in THIS
## simulator, not a global pacing knob, and two simulators can disagree.
var turn_brake_battle: int = -1:
	set(value):
		if turn_brake_battle == value:
			return
		turn_brake_battle = value
		# The batched path never calls `_update_config`, so without this the brake
		# would reach `_config_buffer` and no further.
		_refresh_live_config_in_pair()


## THE SETTLE BRAKE: the battle index that settles before it declares a winner,
## or -1 for none.
##
## Set by [CombatLoop] when its host asks for [member CombatLoop.settle_before_victory],
## so the kernel's by-fiat "the fight is over" flip leaves a unit mid-step or
## mid-swing alone and brakes it instead. See the long note on
## `settle_brake_battle` in `combat_common.glslinc` for what that buys and why it
## is a config uniform rather than a unit field.
##
## A plain member and not a `static var` tunable, for the same reason
## [member turn_brake_battle] is one: it names a BATTLE in THIS simulator, not a
## global pacing knob, and two simulators can disagree.
var settle_brake_battle: int = -1:
	set(value):
		if settle_brake_battle == value:
			return
		settle_brake_battle = value
		# Same reason as the turn brake's: the batched path binds the pair and
		# never calls `_update_config`.
		_refresh_live_config_in_pair()


static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## This owner's named registration entry point (ADR-0173): `_static_init` calls it
## at class load, and the guards call it to read back which slugs it binds.
static func register_tunables() -> void:
	Tune.bind(MOVE_TIME_SCALE_SLUG, move_time_scale,
		{"min": 0.25, "max": 6.0, "step": 0.25})
	Tune.bind(DAMAGE_SCALE_SLUG, damage_scale,
		{"min": 0.05, "max": 2.0, "step": 0.05})


## Q8 form of a pacing multiplier, floored at 1 so a scrub to 0 cannot make the
## shader divide the world away entirely.
static func _pacing_q8(slug: String, fallback: float) -> int:
	var v: float = float(Tune.get_value(slug)) if Tune.is_registered(slug) else fallback
	return maxi(1, int(round(v * float(_PACING_Q8))))


# Combat buffer layout + packing now live in GPUCombatPacker (issue #153). The
# device-read/upload code below references the layout through these one-line
# aliases, so its method bodies stay unchanged. GPUCombatPacker owns the format
# (the generated region moved there); this is a reader depending on the writer's
# definitions -- a one-directional GPUBatchSimulator -> GPUCombatPacker link.
const UNIT_SIZE = GPUCombatPacker.UNIT_SIZE
const BATTLE_HEADER_SIZE = GPUCombatPacker.BATTLE_HEADER_SIZE
const SHADER_VERSION = GPUCombatPacker.SHADER_VERSION
const UnitField = GPUCombatPacker.UnitField
const BattleHeaderField = GPUCombatPacker.BattleHeaderField
const SNAPSHOT_FIELDS = GPUCombatPacker.SNAPSHOT_FIELDS
# The hot-path union as parallel key/offset arrays. Walking two flat arrays skips
# the per-field hash lookup into SNAPSHOT_FIELDS that the full build pays, so the
# lean build is cheaper per field as well as building fewer of them.
const HOT_UNION_KEYS := GPUCombatPacker.SNAPSHOT_HOT_UNION
static var HOT_UNION_OFFSETS: PackedInt32Array = _resolve_hot_union_offsets()
const BATTLE_STATE_FIELDS = GPUCombatPacker.BATTLE_STATE_FIELDS


static func _resolve_hot_union_offsets() -> PackedInt32Array:
	"""Intra-unit offset for each SNAPSHOT_HOT_UNION key, in the same order.
	Resolved once at class load; a key that is not a SNAPSHOT_FIELDS name is a
	typo in the union and would silently read offset 0, so it asserts instead."""
	var out := PackedInt32Array()
	for key in GPUCombatPacker.SNAPSHOT_HOT_UNION:
		assert(GPUCombatPacker.SNAPSHOT_FIELDS.has(key),
			"SNAPSHOT_HOT_UNION names '%s', which is not a SNAPSHOT_FIELDS key" % key)
		out.append(GPUCombatPacker.SNAPSHOT_FIELDS[key])
	return out


# ActionType / TargetType / ConditionType used to be redefined here; they are now
# generated into GPUConstants (ACTION_* / TARGET_* / COND_*) from the shader.
# Reference GPUConstants.ACTION_ATTACK etc. directly.

# State change reasons (shader REASON_*) were redefined here as `enum StateReason`
# but never referenced — the DBG_STATE_REASON value is decoded for display via
# GPUConstants.REASON_NAMES. Dead enum removed (it had also drifted: missing
# THRASH_ABORT). Add REASON_* to GPUConstants if a typed reference is ever needed.


# Results
const RESULT_ONGOING = -1
const RESULT_TEAM_0_WINS = 0
const RESULT_TEAM_1_WINS = 1
const RESULT_DRAW = 2

var _lattice: Lattice = null
var _initialized: bool = false
var _current_buffer: int = 0  # Which buffer is "current" (0 or 1)
var _test_mode: bool = false  # When true, simulation ignores victory condition
#endregion


#region Initialization
## Per-stage shader files. Order MUST match the PASS_* constants above and the
## dispatch order in _run_tick(). Each file is independent — editing one only
## busts that one's SPIRV cache (was a whole-file MD5 before); editing the shared
## `combat_common.glsl` they all include busts all eight.
const STAGE_FILES := [
	"res://src/gpu/shaders/stage_compute.glsl",        # PASS_COMPUTE_STATE       = 0
	"res://src/gpu/shaders/stage_resolve.glsl",        # PASS_RESOLVE_CONFLICTS   = 1
	"res://src/gpu/shaders/stage_post_conflict.glsl",  # PASS_POST_CONFLICT_ATTACKS = 2
	"res://src/gpu/shaders/stage_damage.glsl",         # PASS_APPLY_DAMAGE        = 3
	"res://src/gpu/shaders/stage_victory.glsl",        # PASS_CHECK_VICTORY       = 4
	"res://src/gpu/shaders/stage_attack.glsl",         # PASS_ATTACK              = 5
	"res://src/gpu/shaders/stage_spell.glsl",          # PASS_SPELL               = 6
	"res://src/gpu/shaders/stage_pathfind.glsl",       # PASS_PATHFIND            = 7
]


## Compile every stage in [constant STAGE_FILES] onto `rd`, appending the results to
## `_shaders` / `_pipelines` in PASS_* order. Returns false (having reported) on the
## first stage that fails.
##
## Takes the device rather than reading `_rd` because the warm-up below runs this on a
## THROWAWAY device it then frees — one build path, so the warm-up can never drift out
## of step with the real one and warm the wrong eight shaders.
##
## `validate` gates the schema cross-checks: they are a property of the SOURCE, not of
## the device, so the warm-up passes false and leaves them to the real `initialize`.
func _build_stages(rd: RenderingDevice, validate: bool, subject: String) -> bool:
	var total_start = Time.get_ticks_msec()
	var did_validate := false
	for stage_path in STAGE_FILES:
		var stage_src = _load_shader_with_includes(stage_path)
		if stage_src.is_empty():
			push_error("[GPUBatchSimulator] Failed to load stage shader: %s" % stage_path)
			return false
		# Validate SHADER_VERSION / UNIT_SIZE against the first stage (all stages
		# include combat_common.glsl, so any one of them carries the canonical values).
		if validate and not did_validate:
			_validate_shader_constants(stage_src)
			_validate_unit_config_schema()
			_validate_gambit_config_schema()
			_validate_lever_set()
			did_validate = true
		# Strip Godot-specific #[compute] before feeding to glslang.
		stage_src = stage_src.replace("#[compute]\n", "").replace("#[compute]", "")
		var stage_name = stage_path.get_file().get_basename()  # e.g. "stage_compute"
		var result = _compile_stage_shader_cached(rd, stage_src, stage_name)
		if result.is_empty():
			return false
		_shaders.append(result[0])
		_pipelines.append(result[1])

	var total_ms = Time.get_ticks_msec() - total_start
	# `subject` is not decoration: the warm-up and the battle both print this line, and a
	# reader who cannot tell them apart reads the warm-up's 5.6 s as a still-frozen boot.
	print("[GPUBatchSimulator] All %d stages ready in %d ms (%s)" %
		[STAGE_FILES.size(), total_ms, subject])
	return true


#region Pipeline warm-up
## THE COST OF A BATTLE BOOT IS `compute_pipeline_create`, AND IT IS NOT OURS TO CACHE.
##
## `initialize()` builds a fresh local RenderingDevice and all eight pipelines on EVERY
## battle boot. Our own SPIRV cache covers glslang (`CACHE-HIT`, ~2 ms), but turning that
## SPIRV into machine code is the DRIVER's job, and the only thing that has ever made it
## cheap is the driver's own pipeline cache. Cold, that is ~5.5 s of frozen screen
## (stage_compute 1.8 s, stage_pathfind 1.9 s, stage_spell 0.9 s); warm it is ~11 ms.
##
## Two measured facts make this fix work, both from the same process:
##
##   1. A SECOND local device in the same process gets the driver's warm cache —
##      5486 ms on device A, then 10 ms on device B, same SPIRV.
##   2. That cold compile runs on a `Thread` WITHOUT stalling the main loop — 5.7 s of
##      compiling while the main loop held 57.8 fps.
##
## So: compile the eight stages once on a throwaway device on a background thread, throw
## the results away, and let the driver cache be the thing that survives. The battle's
## real build then costs milliseconds. This does not make the compile cheaper — it moves
## it off the frozen screen and onto a thread, which is the whole point.
##
## Started by the hosts that boot a battle SOME TIME after they load (NavigatorMain,
## GambitBattle). `GPUArena` deliberately does not: it sets its simulator up inside its
## own `_ready`, so there is no gap to hide the work in.
## `WorkerThreadPool` RATHER THAN A BARE `Thread`, and that is a lifetime decision, not a
## style one. A `Thread` held in a static var is only legal if someone calls
## `wait_to_finish()` on it — and a process that boots a host WITHOUT ever starting a
## battle (most of the Navigator test scenes) has nobody to do that, so it would exit on
## "Thread must be disposed of with wait_to_finish()". The pool is drained by the engine at
## shutdown, so fire-and-forget is actually forgettable here.
static var _warm_task_id: int = -1
static var _warm_started: bool = false

## THE PIPELINE COMPILE WAS NEVER THE WHOLE BOOT COST (#1168).
##
## Timed leaf by leaf against the READY!-fadeout freeze, `create_local_rendering_device()`
## itself is **208-560 ms** on the battle-boot frame — the biggest and by far the most
## variable leaf — and `GPUEffectTimingLoader.build()` is another 162 ms. Neither depends
## on which battle is being fought. So the prewarm has two halves, and WHICH THREAD EACH
## RUNS ON IS FORCED, not a preference:
##
##   - `warm_pipelines_async()` — worker thread. The stage compile (5.5 s cold) and the two
##     battle-independent CPU data builds. The device it makes is still a THROWAWAY whose
##     only product is the driver's warm pipeline cache.
##   - `prewarm_device()` — MAIN thread, and it has to be. A local RenderingDevice is
##     THREAD-AFFINE: hand one built on a `WorkerThreadPool` task to the main thread and
##     every call on it fails with *"This function (free_rid) can only be called from the
##     render thread"*, `buffer_get_data` comes back short, and the first read of a unit
##     state dies on `Invalid access of index '4'`. Measured, not assumed — it is what the
##     first cut of this fix did. So the ~180 ms is paid on the main thread either way; the
##     fix is to pay it in the host's `_ready`, inside the scene-load stall the player is
##     already waiting through, instead of on the frame a cinematic is retracting over.
##
## Claimed ONCE per process, deliberately. Re-arming after a claim would leave a parked
## device in every process that boots a battle — including the suite tests that call
## `initialize()` directly and have no host to release it — and a live local device at
## shutdown is an exit-134 abort, not a leak warning (#471, see `cleanup`). The battle this
## exists for is the FIRST one, which is the one with a cinematic retracting over it.
static var _prewarm_rd: RenderingDevice = null
## Set once a battle has taken the parked device, so `prewarm_device()` does not quietly
## make a second one behind it.
static var _prewarm_claimed: bool = false
## The eight stages, compiled onto the parked device by `prewarm_stages()`. Separate from
## `prewarm_device` because they have different EARLIEST moments: the device can be made
## the instant the host loads, but a stage build is only cheap once the worker warm-up has
## filled the driver's pipeline cache — before that it is the 5.5 s cold compile.
static var _prewarm_shaders: Array[RID] = []
static var _prewarm_pipelines: Array[RID] = []
## The two BATTLE-INDEPENDENT CPU data builds: effect timings (162 ms — 512
## `timeline.json` headers) and animation timings (12 ms). Pure functions of files on
## disk, so a parked copy cannot go stale within a process.
##
## `GPUAbilityLoader.build()` is deliberately NOT here despite being the same shape. It
## reads [LeverSet], which the F3 balance panel edits at run time, so a parked copy WOULD
## go stale — and it is 15 ms, already inside a frame's budget.
static var _prewarm_anim_timings: PackedInt32Array = PackedInt32Array()
static var _prewarm_effect_timings: PackedInt32Array = PackedInt32Array()
static var _prewarm_data_ready: bool = false


## Begin the warm-up, once per process. Cheap and safe to call from any host's `_ready`;
## every call after the first is a no-op, including the one after a scene reload.
static func warm_pipelines_async() -> void:
	if _warm_started:
		return
	_warm_started = true
	# Low priority: this is work with no deadline, and the high-priority lane is where
	# resource loading lives — a 5.5 s task parked in it would stall the boot it is meant
	# to speed up.
	_warm_task_id = WorkerThreadPool.add_task(_warm_body, false,
		"GPUBatchSimulator compute-pipeline warm-up")


## Block until a warm-up in flight has finished. Called by `initialize()`, which needs the
## driver cache filled before it builds — and must not race the warm-up for the SPIRV cache
## files. A no-op when nothing is warming, which is every call but the first.
static func join_pipeline_warm() -> void:
	if _warm_task_id == -1:
		return
	var task_id := _warm_task_id
	_warm_task_id = -1
	WorkerThreadPool.wait_for_task_completion(task_id)


static func _warm_body() -> void:
	var start_ms := Time.get_ticks_msec()
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		# Not an error worth shouting about: the real `initialize()` reports device
		# failure loudly (#430), and all this path loses is the warm cache. The CPU half
		# is independent of it and still worth having.
		_warm_prewarm_data()
		return
	# A bare instance purely to reach `_build_stages` — it holds no battle state, and its
	# `_shaders` / `_pipelines` die with it. The device (and every RID on it) goes too —
	# it CANNOT be handed to the battle, see the thread-affinity note above.
	var builder := GPUBatchSimulator.new()
	var ok := builder._build_stages(rd, false, "warm-up")
	# Hand every RID back before dropping the device. `rd.free()` alone reports them as
	# leaked ("8 RIDs of type Compute were leaked") — noise that reads like a real bug in
	# a log, from the one path whose entire job is to be invisible.
	for pipeline in builder._pipelines:
		rd.free_rid(pipeline)
	for shader in builder._shaders:
		rd.free_rid(shader)
	rd.free()
	var gpu_ms := Time.get_ticks_msec() - start_ms
	_warm_prewarm_data()
	print(("[GPUBatchSimulator] pipeline warm-up %s in %d ms + %d ms of battle-independent "
		+ "data (background thread)") %
		["done" if ok else "FAILED", gpu_ms, Time.get_ticks_msec() - start_ms - gpu_ms])


## The CPU half of the warm-up: the two pure, battle-independent data builds, off the
## battle-boot frame. Split out so a machine that cannot make a local device still gets
## it — losing the device is not a reason to pay 174 ms of file parsing on the boot frame.
static func _warm_prewarm_data() -> void:
	_prewarm_anim_timings = GPUAnimationTimingLoader.build()
	_prewarm_effect_timings = GPUEffectTimingLoader.build()
	_prewarm_data_ready = true


## Create the battle's local RenderingDevice NOW and park it for the first `initialize()`
## to claim. Called from the same host `_ready` that arms `warm_pipelines_async`.
##
## ⚠️ MAIN THREAD ONLY, and that is the whole design constraint — see the note above the
## statics. This BLOCKS the caller for ~180-560 ms, and that is the point: it is the cost
## `initialize()` would otherwise pay on the battle-boot frame, moved to a host boot where
## nothing is animating. Idempotent; a no-op after the first call and after a claim.
static func prewarm_device() -> void:
	if _prewarm_rd != null or _prewarm_claimed:
		return
	var start_ms := Time.get_ticks_msec()
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		# `initialize()` will try again and report the failure loudly (#430).
		return
	_prewarm_rd = rd
	print("[GPUBatchSimulator] battle rendering device prewarmed in %d ms (main thread)"
		% (Time.get_ticks_msec() - start_ms))


## Compile the eight compute stages onto the parked device now, so `initialize()` adopts
## them instead of spending ~31 ms on the battle-boot frame.
##
## ⚠️ MAIN THREAD (the device's affinity rule), and it JOINS the worker warm-up first — on
## a COLD driver cache that join is the whole 5.5 s compile. That is why the caller is the
## battle-WORLD boot (`NavigatorMain._boot_world_for`), which is already a loading stall
## with a black screen over it, and not the host's `_ready` (where the warm-up has only
## just started) nor the battle boot (where a cinematic is retracting). No-op without a
## parked device, and after the first call.
static func prewarm_stages() -> void:
	if _prewarm_rd == null or not _prewarm_pipelines.is_empty():
		return
	join_pipeline_warm()
	# A bare instance purely to reach `_build_stages`, which appends to the instance's own
	# arrays; the RIDs it makes live on the parked device, so they outlive it.
	var builder := GPUBatchSimulator.new()
	if not builder._build_stages(_prewarm_rd, false, "prewarm stages"):
		for pipeline in builder._pipelines:
			_prewarm_rd.free_rid(pipeline)
		for shader in builder._shaders:
			_prewarm_rd.free_rid(shader)
		return
	_prewarm_shaders = builder._shaders
	_prewarm_pipelines = builder._pipelines


## Free a parked device no battle ever claimed. THE HOST THAT ARMED THE PREWARM MUST CALL
## THIS ON THE WAY OUT — a live local RenderingDevice at process shutdown is not a leak
## warning, it is `exit 134` (#471, measured; see `cleanup`), and a host that boots no
## battle leaves exactly that. Main thread, for the same affinity reason. Idempotent, and
## a no-op once a battle has claimed the device.
static func release_prewarm() -> void:
	if _prewarm_rd == null:
		return
	for pipeline in _prewarm_pipelines:
		if pipeline.is_valid():
			_prewarm_rd.free_rid(pipeline)
	for shader in _prewarm_shaders:
		if shader.is_valid():
			_prewarm_rd.free_rid(shader)
	_prewarm_pipelines.clear()
	_prewarm_shaders.clear()
	_prewarm_rd.free()
	_prewarm_rd = null


## Take ownership of the parked device, or return false if there is none. MOVES it: the
## static is cleared, so `release_prewarm` becomes a no-op and `cleanup()` is the one and
## only thing that frees this device.
func _claim_prewarm() -> bool:
	if _prewarm_rd == null:
		return false
	_rd = _prewarm_rd
	_shaders = _prewarm_shaders
	_pipelines = _prewarm_pipelines
	_prewarm_rd = null
	_prewarm_shaders = []
	_prewarm_pipelines = []
	_prewarm_claimed = true
	return true


## The schema cross-checks `_build_stages(validate = true)` would have run. They are a
## property of the SOURCE, not of the device, so `prewarm_stages` skips them (it has no
## business warning twice) and a build that ADOPTED prewarmed stages runs them here
## instead — otherwise adopting would silently switch off the stale-layout net that
## catches an un-regenerated `gen_gpu_layout.py`. One cached file read.
func _validate_stage_sources() -> void:
	var src := _load_shader_with_includes(STAGE_FILES[0])
	if not src.is_empty():
		_validate_shader_constants(src)
	_validate_unit_config_schema()
	_validate_gambit_config_schema()
	_validate_lever_set()


#endregion


func initialize(lattice: Lattice, distance_field: DistanceFieldGenerator,
				num_battles: int = 1024, units_per_battle: int = 8) -> bool:
	# Kept so `set_battle_from_units` can resolve terrain `height` per unit: holder 4
	# is a coordinate now, so the height that used to come off the held tile is a port
	# question (ADR-0166 dec. 3).
	_lattice = lattice
	"""Initialize the batch simulator.

	Args:
		lattice: the terrain port (ADR-0164 dec. 2)
		distance_field: Precomputed distance field
		num_battles: Number of battles to simulate in parallel
		units_per_battle: Units per battle (default 8 = 4v4)

	Returns:
		true if initialization succeeded
	"""
	_num_battles = num_battles
	_units_per_battle = units_per_battle

	if DebugConfig.gpu_debug_enabled:
		print("[GPUBatchSimulator] Initializing for %d battles with %d units each (parallel architecture)..." % [num_battles, units_per_battle])

	# Create rendering device. LOCAL ONLY — there is deliberately no fallback to
	# RenderingServer.get_rendering_device(). The global device belongs to the
	# renderer and rejects submit()/sync() ("Only local devices can submit and
	# sync.", rendering_device.cpp), so a simulator holding it can record a compute
	# list and never drive it. That fallback used to live here and turned VRAM
	# exhaustion into a SILENT one: `initialize()` returned true on a device it
	# could not submit, the caller saw success, and the scene printed a green
	# verdict over 43,492 device errors (#430) / 5,698 (#547). Local or nothing.
	# A prewarm may be building these very stages on a background thread right now (see
	# `warm_pipelines_async`). JOIN IT BEFORE ASKING FOR A DEVICE — it is not only filling
	# the driver's pipeline cache, it has a finished device and the eight stages parked for
	# this call to claim, and claiming is what keeps the 208-560 ms `create_local_rendering
	# _device()` off the battle-boot frame. Two devices compiling the same SPIRV
	# concurrently would also just duplicate the work.
	join_pipeline_warm()
	# The parked device when a host armed one (`prewarm_device`) — that is the 208-560 ms
	# leaf, already paid at the host's `_ready` where nothing was animating. Otherwise make
	# one here, exactly as before.
	var claimed := _claim_prewarm()
	if not claimed:
		_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_error("[GPUBatchSimulator] Could not create a LOCAL rendering device "
			+ "(usually VRAM exhaustion). Not falling back to the global device — "
			+ "it cannot submit/sync. See #430.")
		return false

	if claimed and not _pipelines.is_empty():
		# The stages came with the device (`prewarm_stages`); only the source-schema
		# checks are still owed.
		_validate_stage_sources()
	elif not _build_stages(_rd, true, "battle device"):
		return false

	# Create buffers
	if not _create_buffers(lattice, distance_field):
		push_error("[GPUBatchSimulator] Failed to create buffers")
		return false

	# Create uniform set
	if not _create_uniform_set():
		push_error("[GPUBatchSimulator] Failed to create uniform set")
		return false

	_initialized = true
	if DebugConfig.gpu_debug_enabled:
		print("[GPUBatchSimulator] Initialized successfully (double-buffer parallel)")
	return true

func _validate_shader_constants(source: String) -> void:
	# Cheap inner-loop net: SHADER_VERSION / UNIT_SIZE here are GENERATED from the
	# shader (tools/gen_gpu_layout.py). A mismatch means the committed generated
	# region is STALE vs the shader you just edited - regenerate it. The thorough
	# per-field/per-enum check is the generator's --check (run in run_all_tests.sh).
	var re = RegEx.new()
	re.compile("const\\s+int\\s+SHADER_VERSION\\s*=\\s*(\\d+)")
	var m = re.search(source)
	if m:
		var ver = int(m.get_string(1))
		if ver != SHADER_VERSION:
			push_warning("Stale combat buffer layout: SHADER_VERSION shader=%d generated=%d - run tools/gen_gpu_layout.py" % [ver, SHADER_VERSION])
	re.compile("const\\s+int\\s+UNIT_SIZE\\s*=\\s*(\\d+)")
	m = re.search(source)
	if m:
		var sz = int(m.get_string(1))
		if sz != UNIT_SIZE:
			push_warning("Stale combat buffer layout: UNIT_SIZE shader=%d generated=%d - run tools/gen_gpu_layout.py" % [sz, UNIT_SIZE])


func _validate_unit_config_schema() -> void:
	# Cheap inner-loop net for the unit encode schema (ADR-0003), run once at
	# init alongside _validate_shader_constants. Errors are real mistakes
	# (duplicate offset / forgotten extractor); warnings are knowingly-unwired
	# live fields (e.g. equipped reaction). The same pure check backs the
	# round-trip test in UnitEncodeSchemaTest.
	var problems := GPUCombatPacker.unit_config_schema_problems()
	for w in problems["warnings"]:
		push_warning("[GPUBatchSimulator] " + w)
	for e in problems["errors"]:
		push_error("[GPUBatchSimulator] " + e)
	# Completeness net (ADR-0003): every offset in [0, UNIT_SIZE) is written by
	# _write_unit_data, so a new UnitField that gained an enum slot but no writer
	# is a boot error, not a silent zero. Errors only, like the gambit check.
	var coverage := GPUCombatPacker.unit_buffer_coverage_problems()
	for e in coverage["errors"]:
		push_error("[GPUBatchSimulator] " + e)
	# Reconfigure-classification net (ADR-0235): a field the SHADER writes is live
	# state, so it may not be `recompute` — `overlay_unit_config` would throw that
	# state away on the player's first job change, silently. The shader-write set
	# is scanned out of the kernel source, not hand-listed, and an empty scan is
	# itself an error so the net cannot go inert.
	var behaviour := GPUCombatPacker.overlay_behaviour_problems()
	for e in behaviour["errors"]:
		push_error("[GPUBatchSimulator] " + e)


func _validate_lever_set() -> void:
	# Boot net for the lever layer (ADR-0277 dec. 9), beside the unit and gambit
	# ones. THE GAME ONLY REPORTS — a typo in a balance file should not stop
	# somebody playing. A MEASURING tool calls `LeverSet.abort_if_invalid()`
	# instead and refuses to run, because a silently-inert factor corrupts a
	# measurement without failing it, which is worse than not running.
	LeverSet.shared().report()


func _validate_gambit_config_schema() -> void:
	# Boot net for the gambit encode schema (ADR-0016), beside the unit one.
	# Every problem is a real error here — the completeness check means an
	# unwritten GambitField is a mistake, not a knowingly-dormant field.
	var problems := GPUCombatPacker.gambit_config_schema_problems()
	for e in problems["errors"]:
		push_error("[GPUBatchSimulator] " + e)


const SPIRV_CACHE_DIR = "user://shader_cache"


func _load_shader_with_includes(shader_path: String, visited: Dictionary = {}) -> String:
	"""Read a .glsl file and recursively inline `#include "..."` directives.

	Godot's runtime `shader_compile_spirv_from_source` doesn't process #include
	— only the import-time RDShaderFile path does. Preprocessing here lets the
	shader source be modular (shared header + per-stage files) without changing
	the runtime compile path.

	Paths in #include are either absolute `res://...` or resolved relative to
	the including file. Cycles are detected and rejected.
	"""
	var abs_path = shader_path
	if visited.has(abs_path):
		push_error("[GPUBatchSimulator] Circular #include of %s" % abs_path)
		return ""
	visited[abs_path] = true

	var file = FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		push_error("[GPUBatchSimulator] Failed to open shader file: %s" % abs_path)
		return ""
	var src = file.get_as_text()
	file.close()

	var include_re := RegEx.new()
	include_re.compile('^\\s*#include\\s+"([^"]+)"\\s*$')
	var base_dir = abs_path.get_base_dir()
	var out: PackedStringArray = PackedStringArray()
	for line in src.split("\n"):
		var m = include_re.search(line)
		if m == null:
			out.append(line)
			continue
		var inc = m.get_string(1)
		if not inc.begins_with("res://"):
			inc = base_dir.path_join(inc)
		out.append("// ===== begin include %s =====" % inc)
		var inc_src = _load_shader_with_includes(inc, visited)
		if inc_src.is_empty():
			return ""
		out.append(inc_src)
		out.append("// ===== end include %s =====" % inc)
	return "\n".join(out)


func _compile_stage_shader_cached(rd: RenderingDevice, source: String, stage_name: String) -> Array:
	"""Compile a single stage shader with per-stage SPIRV caching.

	The cache key is the stage name + md5 of the (already preprocessed,
	#include-inlined) source. Per-stage keying is the whole point of the
	file split — editing one stage no longer busts the others' caches.

	Returns [shader_rid, pipeline_rid] on success, or [] on failure.
	"""
	var start_ms = Time.get_ticks_msec()
	var source_hash = source.md5_text()
	var cache_path = "%s/%s_%s.spirv_cache" % [SPIRV_CACHE_DIR, stage_name, source_hash]

	# Try loading from cache
	var shader_spirv: RDShaderSPIRV = _load_spirv_cache(cache_path)
	if shader_spirv:
		var t_create_us = Time.get_ticks_usec()
		var shader = rd.shader_create_from_spirv(shader_spirv)
		var create_us = Time.get_ticks_usec() - t_create_us
		if shader.is_valid():
			var t_pipe_us = Time.get_ticks_usec()
			var pipeline = rd.compute_pipeline_create(shader)
			var pipe_us = Time.get_ticks_usec() - t_pipe_us
			if pipeline.is_valid():
				var elapsed = Time.get_ticks_msec() - start_ms
				print("[GPUBatchSimulator][TIMING] %s CACHE-HIT total=%dms shader_create=%.1fms pipeline_create=%.1fms" % [
					stage_name, elapsed, create_us / 1000.0, pipe_us / 1000.0
				])
				return [shader, pipeline]
		# Cache invalid — fall through to recompile
		print("[GPUBatchSimulator] %s cache invalid, recompiling..." % stage_name)

	# Compile from source — instrument the two compile stages separately so we
	# can tell whether glslang (GLSL→SPIRV) or the driver (SPIRV→machine code)
	# is the bottleneck. See plan: stage 1a diagnosis.
	var shader_src = RDShaderSource.new()
	shader_src.source_compute = source
	var t_glslang_us = Time.get_ticks_usec()
	shader_spirv = rd.shader_compile_spirv_from_source(shader_src)
	var glslang_us = Time.get_ticks_usec() - t_glslang_us
	if not shader_spirv:
		push_error("[GPUBatchSimulator] Failed to compile %s to SPIRV" % stage_name)
		return []

	var compile_error = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if compile_error != "":
		push_error("[GPUBatchSimulator] %s compile error: %s" % [stage_name, compile_error])
		return []

	var t_create_us2 = Time.get_ticks_usec()
	var shader = rd.shader_create_from_spirv(shader_spirv)
	var create_us2 = Time.get_ticks_usec() - t_create_us2
	if not shader.is_valid():
		push_error("[GPUBatchSimulator] Failed to create %s shader from SPIRV" % stage_name)
		return []

	var t_pipe_us2 = Time.get_ticks_usec()
	var pipeline = rd.compute_pipeline_create(shader)
	var pipe_us2 = Time.get_ticks_usec() - t_pipe_us2
	if not pipeline.is_valid():
		push_error("[GPUBatchSimulator] Failed to create %s pipeline" % stage_name)
		return []

	var elapsed = Time.get_ticks_msec() - start_ms
	# Per-stage breakdown. glslang_ms = GLSL→SPIRV (CPU, embedded compiler).
	# pipeline_ms = driver SPIRV→machine code. shader_create_ms is usually
	# trivial but reported to be complete.
	print("[GPUBatchSimulator][TIMING] %s COMPILE total=%dms glslang=%.1fms shader_create=%.1fms pipeline_create=%.1fms" % [
		stage_name, elapsed,
		glslang_us / 1000.0, create_us2 / 1000.0, pipe_us2 / 1000.0
	])

	# Save SPIRV to cache for next time
	_save_spirv_cache(cache_path, shader_spirv)
	return [shader, pipeline]


func _load_spirv_cache(cache_path: String) -> RDShaderSPIRV:
	"""Load cached SPIRV bytes from disk. Returns null if not found."""
	if not FileAccess.file_exists(cache_path):
		return null
	var f = FileAccess.open(cache_path, FileAccess.READ)
	if not f:
		return null
	var spirv_bytes = f.get_buffer(f.get_length())
	f.close()
	if spirv_bytes.is_empty():
		return null
	var spirv = RDShaderSPIRV.new()
	spirv.set_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE, spirv_bytes)
	return spirv


func _save_spirv_cache(cache_path: String, shader_spirv: RDShaderSPIRV) -> void:
	"""Save compiled SPIRV bytecode to disk."""
	var spirv_bytes = shader_spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_COMPUTE)
	if spirv_bytes.is_empty():
		return

	# Ensure cache directory exists
	if not DirAccess.dir_exists_absolute(SPIRV_CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(SPIRV_CACHE_DIR)

	var f = FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_buffer(spirv_bytes)
		f.close()
		print("[GPUBatchSimulator] Cached SPIRV for %s (%d bytes)" % [cache_path.get_file(), spirv_bytes.size()])
#endregion


#region Buffer Creation
## Build the map storage buffer for the compute shader — TWO LEVELS of
## `heights + traversability + 8×cliff-edge` per cell, laid out level-major
## (see the Map Buffer Layout region above, and ADR-0224 dec. 1/2/3).
##
## Indexed on the walkable-bounds grid [min_x..][min_z..] of size
## map_width × map_height, which is the PER-LEVEL grid and is still the grid the
## distance field is indexed on. The field stays one plane in this pass: its
## matrix STRIDE is `total_tiles`, so doubling its node count is not inert and
## belongs with the shader pass (ADR-0224 dec. 2).
static func build_map_data(lattice: Lattice, min_x: int, min_z: int, map_width: int, map_height: int) -> PackedInt32Array:
	var total_tiles := map_width * map_height
	var level_block := total_tiles * MAP_PLANES_PER_LEVEL
	var map_data := PackedInt32Array()
	map_data.resize(level_block * TerrainCell.LEVEL_COUNT)

	var cells := lattice.all_cells() if lattice != null else ([] as Array[TerrainCell])

	# Neighbour presence spans ALL cells — an in-bounds edge cell's neighbour may lie
	# just outside the grid and still contributes a real cliff edge. The cliff verdict
	# itself is the PORT's (`is_cliff_edge`), not ours: it is computed from
	# `tile_vertices` + the tile transform, which are terrain facts this system cannot
	# see and ADR-0164 dec. 2 put on the port for exactly that reason. This loop used
	# to call `TileTraversalUtils.do_edge_vertices_match(tile, neighbor)` — a
	# `Battle`-side function taking two `Tile` NODES.
	#
	# 🔴 THE GROUND-PLANE FILTER THAT USED TO STAND HERE IS GONE (ADR-0224 dec. 2).
	# It existed because this buffer held ONE slot per column, so the two cells
	# ADR-0219 dec. 5 lets a column hold would both resolve to `gz * map_width + gx`
	# and the last one written would win, silently and per-run. The buffer now has a
	# slot per CELL, so the collision the filter prevented cannot occur — the comment
	# it carried named this work as "a separate piece of work with no consumer yet",
	# and ADR-0224 counts twelve consumers. `DistanceFieldGenerator`'s filter STAYS:
	# its matrix stride is `total_tiles`, so widening it moves `get_distance` for
	# every reader and is not inert.
	var present: Dictionary = {}
	for cell in cells:
		present[cell.grid] = true

	# Direction vectors, as (x, z) offsets: N(+X), E(+Z), S(-X), W(-Z), and the same
	# four `EventPathfinder.DIRS` walks. A step is column to column and never changes
	# level in place (ADR-0219 dec. 6, adopted verbatim by ADR-0224 dec. 5), so a
	# direction moves x/z only — WHICH level the step can land on is the
	# `target_level` loop below, and that is exactly why the cliff table is
	# eight-wide per cell rather than four.
	#
	# ⚠️ The incoming text this replaced ended "and this buffer holds one level
	# anyway". That was true when it was written and is not true now.
	var directions := [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

	for cell in cells:
		# A level the buffer has no block for would index off the end — the level
		# axis's version of the index-936 crash. `DynamicTerrainBuilder.add_terrain`
		# asserts the same bound, but an `assert` is stripped from a release build
		# and this is not.
		var level := cell.grid.z
		if level < 0 or level >= TerrainCell.LEVEL_COUNT:
			continue
		var gx := cell.grid.x - min_x
		var gz := cell.grid.y - min_z
		# Bounds are the WALKABLE box (DistanceFieldGenerator); all_cells()
		# also returns impassable cells, which can sit outside it. Such a cell is
		# unreachable and has no slot in this grid — skip it, or its index runs
		# off the buffer (the index-936 crash) or wraps into another cell's slot.
		# Widening the index space makes this MORE necessary, not less: an
		# out-of-bounds upper cell would now wrap into a live upper slot.
		if gx < 0 or gx >= map_width or gz < 0 or gz >= map_height:
			continue
		var idx := gz * map_width + gx
		var base := level * level_block

		map_data[base + idx] = cell.height
		map_data[base + total_tiles + idx] = 0 if cell.impassable else 1

		# Eight verdicts per cell, as two 4-wide groups BY TARGET LEVEL — the
		# target-level-0 group keeps the `total_tiles * 2 + idx * 4 + dir` stride
		# the shader already computes, which is what makes level 0's block
		# byte-identical to the pre-ADR-0224 buffer.
		for target_level in range(TerrainCell.LEVEL_COUNT):
			var cliff_offset := base + total_tiles * 2 \
				+ target_level * total_tiles * MAP_CLIFF_DIRECTIONS \
				+ idx * MAP_CLIFF_DIRECTIONS
			for dir_idx in range(MAP_CLIFF_DIRECTIONS):
				var step: Vector2i = directions[dir_idx]
				var neighbor_pos := Vector3i(
					cell.grid.x + step.x, cell.grid.y + step.y, target_level)
				if present.has(neighbor_pos):
					map_data[cliff_offset + dir_idx] = 1 if lattice.is_cliff_edge(cell.grid, neighbor_pos) else 0
				else:
					map_data[cliff_offset + dir_idx] = 0
	return map_data


func _create_buffers(lattice: Lattice, distance_field: DistanceFieldGenerator) -> bool:
	var stats = distance_field.get_stats()
	_map_width = stats["bounds"]["max_x"] - stats["bounds"]["min_x"] + 1
	_map_height = stats["bounds"]["max_z"] - stats["bounds"]["min_z"] + 1
	var total_tiles = _map_width * _map_height

	# Config buffer (binding 0)
	var config_data := _build_config_data(PASS_COMPUTE_STATE)
	_config_buffer = _rd.storage_buffer_create(config_data.size() * 4, config_data.to_byte_array())

	# Map buffer (binding 1)
	var map_data := build_map_data(lattice, stats["bounds"]["min_x"], stats["bounds"]["min_z"], _map_width, _map_height)
	_map_buffer = _rd.storage_buffer_create(map_data.size() * 4, map_data.to_byte_array())
	if DebugConfig.gpu_debug_enabled:
		print("[GPUBatchSimulator] Map buffer: %d tiles x %d planes x %d levels (cliff: %d directions x %d target levels)" % [
			total_tiles, MAP_PLANES_PER_LEVEL, TerrainCell.LEVEL_COUNT,
			MAP_CLIFF_DIRECTIONS, TerrainCell.LEVEL_COUNT])

	# Distance field buffer (binding 2)
	var flat_distances = distance_field.get_flat_distances()
	_distance_buffer = _rd.storage_buffer_create(flat_distances.size() * 4, flat_distances.to_byte_array())

	# Battle buffer (binding 3) - DOUBLE SIZE for ping-pong
	# Two complete copies: buffer 0 and buffer 1
	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE
	var single_buffer_size = _num_battles * single_battle_size
	var battle_buffer_size = single_buffer_size * 2 * 4  # 2x for ping-pong, *4 for bytes
	_battle_buffer = _rd.storage_buffer_create(battle_buffer_size)

	# Results buffer (binding 4)
	var results_buffer_size = _num_battles * RESULT_SIZE * 4
	_results_buffer = _rd.storage_buffer_create(results_buffer_size)

	# Animation timings buffer (binding 5). The parked prewarm copy when there is one —
	# a pure function of files on disk, so it cannot have gone stale (#1168).
	var anim_data: PackedInt32Array = _prewarm_anim_timings if _prewarm_data_ready \
		else GPUAnimationTimingLoader.build()
	_anim_timings_buffer = _rd.storage_buffer_create(anim_data.size() * 4, anim_data.to_byte_array())

	# Gambit buffer (binding 6)
	# Per-unit: MAX_GAMBITS * GAMBIT_SIZE = 96 ints
	# Total: num_units_total * 80 ints (where num_units_total = num_battles * units_per_battle)
	var total_units = _num_battles * _units_per_battle
	var gambit_buffer_size = total_units * GAMBITS_PER_UNIT * 4  # bytes
	_gambit_buffer = _rd.storage_buffer_create(gambit_buffer_size)
	if DebugConfig.gpu_debug_enabled:
		print("[GPUBatchSimulator] Gambit buffer: %d units x %d ints = %d bytes" % [
			total_units, GAMBITS_PER_UNIT, gambit_buffer_size
		])

	# Ability buffer (binding 7)
	# MAX_ABILITIES * ABILITY_SIZE ints
	var ability_result = GPUAbilityLoader.build()
	var ability_data: PackedInt32Array = ability_result["buffer"]
	_ability_database = ability_result["cache"]
	_ability_buffer = _rd.storage_buffer_create(ability_data.size() * 4, ability_data.to_byte_array())
	if DebugConfig.gpu_debug_enabled:
		print("[GPUBatchSimulator] Ability buffer: %d abilities x %d ints" % [MAX_ABILITIES, ABILITY_SIZE])

	# Effect timings buffer (binding 8) — per-effect cinematic timings the
	# cinematic-spell orchestrator (issue #53) reads at run time. No shader
	# consumer yet; the SSBO declaration lands in the next commit so the buffer
	# is wired in advance of the orchestrator landing.
	# Parked by the prewarm when there is one — 512 `timeline.json` headers, 162 ms, and
	# the second-biggest leaf on the battle-boot frame before #1168.
	var effect_data: PackedInt32Array = _prewarm_effect_timings if _prewarm_data_ready \
		else GPUEffectTimingLoader.build()
	_effect_timings_buffer = _rd.storage_buffer_create(effect_data.size() * 4, effect_data.to_byte_array())

	# Cooldown buffer (binding 9) — per-(unit, ability_id) cooldown_ready_at
	# (ADR-0047 / issue #85). Pulled out of the unit struct so copy_unit_to_next
	# stops iterating 128 ints/unit/tick of per-commit state. Indexed
	# [unit_global_idx * MAX_COOLDOWN_ABILITIES + ability_id]. PackedInt32Array
	# zero-fills on resize, which gives "every ability off-cooldown at boot"
	# for free; per-battle zeroing on set_battle_units handles reruns.
	# #1108 removed the ceiling by making this the whole ability table. The two
	# numbers live in two files (the shader's own copy is scanned by
	# src/balance/LeverSet.gd, which needs a literal), so nothing but this holds
	# them together. If they drift, ability ids in the gap silently stop being
	# rate-limited — the exact failure the ceiling used to cause on purpose.
	if MAX_COOLDOWN_ABILITIES != MAX_ABILITIES:
		push_error(("[GPUBatchSimulator] MAX_COOLDOWN_ABILITIES (%d) != MAX_ABILITIES (%d) — " +
			"ability ids in the gap would fall through the cooldown veto un-gated. " +
			"Update combat_common.glslinc and this file together.") % [
			MAX_COOLDOWN_ABILITIES, MAX_ABILITIES])
		return false

	var cooldown_data = PackedInt32Array()
	cooldown_data.resize(total_units * MAX_COOLDOWN_ABILITIES)
	_cooldown_buffer = _rd.storage_buffer_create(cooldown_data.size() * 4, cooldown_data.to_byte_array())

	if DebugConfig.gpu_debug_enabled:
		print("[GPUBatchSimulator] Buffers created: map=%dx%d, battles=%d (ping-pong), anim_timings=%d entries, effect_timings=%d effects, cooldown=%d units x %d abilities" % [
			_map_width, _map_height, _num_battles, MAX_ANIMATIONS, GPUConstants.MAX_EFFECTS,
			total_units, MAX_COOLDOWN_ABILITIES
		])
	return true


func _create_uniform_set() -> bool:
	"""Create one uniform set per shader variant (required by Godot RD)."""
	_uniform_sets.clear()
	for shader in _shaders:
		var us = _create_uniform_set_for_shader(_config_buffer, shader)
		if not us.is_valid():
			return false
		_uniform_sets.append(us)
	return _create_batched_uniform_sets()


func _create_batched_uniform_sets() -> bool:
	"""Build the two fixed-`current_buffer` config buffers + parallel uniform sets
	the batched multi-tick path binds (Phase 2a).

	Each config is identical to the live `_update_config` output (which is fully
	static except `current_buffer`) with `current_buffer` baked to 0 or 1. A
	K-tick compute list flips the ping-pong per tick by binding
	`_uniform_sets_pair[current_buffer]` — no mid-list CPU config update, which
	would alias across the batched dispatches."""
	_config_buffer_pair.clear()
	_uniform_sets_pair.clear()
	for cb in range(2):
		var config_data := _build_config_data(PASS_COMPUTE_STATE)  # pass_mode unused by shaders
		config_data[7] = cb  # current_buffer
		var cfg := _rd.storage_buffer_create(config_data.size() * 4, config_data.to_byte_array())
		_config_buffer_pair.append(cfg)
		var sets: Array = []
		for shader in _shaders:
			var us = _create_uniform_set_for_shader(cfg, shader)
			if not us.is_valid():
				return false
			sets.append(us)
		_uniform_sets_pair.append(sets)
	return true


func _create_uniform_set_for_shader(cfg_buf: RID, shader: RID) -> RID:
	"""Create a uniform set bound to a specific shader variant."""
	var uniforms: Array[RDUniform] = []

	var config_uniform = RDUniform.new()
	config_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	config_uniform.binding = 0
	config_uniform.add_id(cfg_buf)
	uniforms.append(config_uniform)

	var map_uniform = RDUniform.new()
	map_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	map_uniform.binding = 1
	map_uniform.add_id(_map_buffer)
	uniforms.append(map_uniform)

	var dist_uniform = RDUniform.new()
	dist_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	dist_uniform.binding = 2
	dist_uniform.add_id(_distance_buffer)
	uniforms.append(dist_uniform)

	var battle_uniform = RDUniform.new()
	battle_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	battle_uniform.binding = 3
	battle_uniform.add_id(_battle_buffer)
	uniforms.append(battle_uniform)

	var results_uniform = RDUniform.new()
	results_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	results_uniform.binding = 4
	results_uniform.add_id(_results_buffer)
	uniforms.append(results_uniform)

	var anim_uniform = RDUniform.new()
	anim_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	anim_uniform.binding = 5
	anim_uniform.add_id(_anim_timings_buffer)
	uniforms.append(anim_uniform)

	var gambit_uniform = RDUniform.new()
	gambit_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	gambit_uniform.binding = 6
	gambit_uniform.add_id(_gambit_buffer)
	uniforms.append(gambit_uniform)

	var ability_uniform = RDUniform.new()
	ability_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ability_uniform.binding = 7
	ability_uniform.add_id(_ability_buffer)
	uniforms.append(ability_uniform)

	# Effect timings (binding 8) — see _create_buffers; issue #53.
	var effect_timings_uniform = RDUniform.new()
	effect_timings_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	effect_timings_uniform.binding = 8
	effect_timings_uniform.add_id(_effect_timings_buffer)
	uniforms.append(effect_timings_uniform)

	# Cooldown data (binding 9) — see _create_buffers; ADR-0047 / issue #85.
	var cooldown_uniform = RDUniform.new()
	cooldown_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cooldown_uniform.binding = 9
	cooldown_uniform.add_id(_cooldown_buffer)
	uniforms.append(cooldown_uniform)

	return _rd.uniform_set_create(uniforms, shader, 0)


func consume_turn(battle_id: int, unit_idx: int) -> int:
	"""Spend one taken turn off a unit's TURN METER (ADR-0236 dec. 2).

	Subtracts `TURN_METER_FULL` and CARRIES the overshoot, rather than resetting
	to zero: a unit whose Speed overshoots the threshold by 7 is 7 ticks into its
	next turn, and zeroing that would quantize turn spacing to whole tick counts
	and drift fast units off their true Speed ratio.

	The kernel stops accumulating at `TURN_METER_FULL`, so calling this on a unit
	that is not ready would push its meter NEGATIVE and hand it a longer wait than
	its Speed earns; a non-ready unit is left alone and the return is -1. Otherwise
	returns the new meter value.

	Whose turn it is, and when, is `TurnQueue`'s question — this is only the write
	that ends one."""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return -1
	if unit_idx < 0 or unit_idx >= _units_per_battle:
		return -1
	var col := read_unit_column(battle_id, UnitField.TURN_METER)
	if unit_idx >= col.size():
		return -1
	var meter: int = col[unit_idx]
	if meter < GPUCombatPacker.TURN_METER_FULL:
		return -1
	var next_meter: int = meter - GPUCombatPacker.TURN_METER_FULL
	_set_unit_field(battle_id, unit_idx, UnitField.TURN_METER, next_meter)
	return next_meter


func _set_unit_field(battle_id: int, unit_idx: int, field: int, value: int) -> void:
	"""Write one int field of one unit into both ping-pong buffers (so whichever
	is read next sees it; the compute copies the field forward each tick)."""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return
	if unit_idx < 0 or unit_idx >= _units_per_battle:
		return
	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE
	var field_offset = battle_id * single_battle_size + BATTLE_HEADER_SIZE \
		+ unit_idx * UNIT_SIZE + field
	var bytes := PackedInt32Array([value]).to_byte_array()
	_rd.buffer_update(_battle_buffer, (_get_buffer_offset(0) + field_offset) * 4, 4, bytes)
	_rd.buffer_update(_battle_buffer, (_get_buffer_offset(1) + field_offset) * 4, 4, bytes)
	_bump_battle_version()


func _get_single_buffer_size() -> int:
	"""Size of one complete set of battles (in ints)."""
	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE
	return _num_battles * single_battle_size


func _get_buffer_offset(buffer_id: int) -> int:
	"""Offset to a specific buffer (0 or 1) in ints."""
	return buffer_id * _get_single_buffer_size()
#endregion


#region Battle Configuration
func set_battle_units(battle_id: int, team0_units: Array, team1_units: Array, battle_seed: int = -1) -> void:
	"""Configure units for a specific battle.

	Args:
		battle_id: Which battle to configure (0 to num_battles-1)
		team0_units: Array of unit configs for team 0 (player)
		team1_units: Array of unit configs for team 1 (enemy)
		battle_seed: Random seed for this battle (-1 = use battle_id)
	"""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return

	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE

	# Prepare data for both buffers (start with identical state)
	var data = PackedInt32Array()
	data.resize(single_battle_size)

	# Header
	data[BattleHeaderField.TICK] = 0
	data[BattleHeaderField.RESULT] = RESULT_ONGOING
	data[BattleHeaderField.FLAGS] = 0
	var seed_used: int = battle_seed if battle_seed >= 0 else battle_id
	data[BattleHeaderField.SEED] = seed_used
	# Cinematic-spell orchestrator (issue #118): the per-cinematic frame
	# counter is per-unit (U_CINEMATIC_TIMER), not a battle-header field,
	# so simultaneous casters don't race for a single slot.

	# Team 0 units
	var unit_idx = 0
	for i in range(mini(team0_units.size(), _units_per_battle / 2)):
		var u = team0_units[i]
		var offset = BATTLE_HEADER_SIZE + unit_idx * UNIT_SIZE
		GPUCombatPacker._write_unit_data(data, offset, u, 0,
			GPUCombatPacker.initial_turn_meter(seed_used, unit_idx))
		unit_idx += 1

	# Team 1 units
	for i in range(mini(team1_units.size(), _units_per_battle / 2)):
		var u = team1_units[i]
		var offset = BATTLE_HEADER_SIZE + unit_idx * UNIT_SIZE
		GPUCombatPacker._write_unit_data(data, offset, u, 1,
			GPUCombatPacker.initial_turn_meter(seed_used, unit_idx))
		unit_idx += 1

	# Mark unused unit slots as dead (FLAG_DEAD = 1)
	# This prevents ghost units from interfering with target selection
	const FLAG_DEAD = 1
	while unit_idx < _units_per_battle:
		var offset = BATTLE_HEADER_SIZE + unit_idx * UNIT_SIZE
		data[offset + UnitField.FLAGS] = FLAG_DEAD
		data[offset + UnitField.HP] = 0
		unit_idx += 1

	# Upload to BOTH buffers (start with identical state)
	var battle_offset_in_buffer = battle_id * single_battle_size

	# Buffer 0
	var buffer0_offset = _get_buffer_offset(0) + battle_offset_in_buffer
	_rd.buffer_update(_battle_buffer, buffer0_offset * 4, data.size() * 4, data.to_byte_array())

	# Buffer 1 (identical initial state)
	var buffer1_offset = _get_buffer_offset(1) + battle_offset_in_buffer
	_rd.buffer_update(_battle_buffer, buffer1_offset * 4, data.size() * 4, data.to_byte_array())

	# Zero this battle's slice of the cooldown SSBO (ADR-0047 / issue #85).
	# The buffer is single-buffered, not in `data` — must clear separately so
	# test reruns on the same simulator don't see stale cooldown_ready_at
	# values from a prior run.
	var cooldown_slice = PackedInt32Array()
	cooldown_slice.resize(_units_per_battle * MAX_COOLDOWN_ABILITIES)
	var cooldown_battle_offset = battle_id * _units_per_battle * MAX_COOLDOWN_ABILITIES
	_rd.buffer_update(_cooldown_buffer, cooldown_battle_offset * 4,
		cooldown_slice.size() * 4, cooldown_slice.to_byte_array())

	_bump_battle_version()


func reconfigure_unit(battle_id: int, unit_idx: int, unit_config: Dictionary) -> bool:
	"""Apply a job / equipment / ability change to a unit that is ALREADY FIGHTING
	(ADR-0235). The keystone's second primitive; §4's "all adjustment types legal"
	rests on it.

	Read-modify-write of one unit block into BOTH ping-pong halves — the shape
	`apply_pending_heal` already uses for the read-modify-write and `_set_unit_field`
	already uses for the both-halves write. Deliberately NOT `set_battle_units`,
	whose whole-block write resets all 56 non-schema offsets to their init
	constants; correct out of combat, destructive mid-battle.

	Which offsets move is `UNIT_CONFIG_SCHEMA`'s call, not this function's — see
	`GPUCombatPacker.overlay_unit_config`. Returns false if the target is out of
	range."""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return false
	if unit_idx < 0 or unit_idx >= _units_per_battle:
		return false
	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE
	var block_offset = battle_id * single_battle_size + BATTLE_HEADER_SIZE + unit_idx * UNIT_SIZE
	# Read the LIVE block from the current half — the one the next tick reads.
	var live_offset = _get_buffer_offset(_current_buffer) + block_offset
	var live = _rd.buffer_get_data(_battle_buffer, live_offset * 4, UNIT_SIZE * 4).to_int32_array()
	GPUCombatPacker.overlay_unit_config(live, 0, unit_config)
	var bytes := live.to_byte_array()
	# Both halves, like every other partial write: the compute copies the block
	# forward each tick, so whichever half is current next must already see it.
	_rd.buffer_update(_battle_buffer, (_get_buffer_offset(0) + block_offset) * 4, UNIT_SIZE * 4, bytes)
	_rd.buffer_update(_battle_buffer, (_get_buffer_offset(1) + block_offset) * 4, UNIT_SIZE * 4, bytes)
	_bump_battle_version()
	return true


func reconfigure_unit_from(battle_id: int, unit_idx: int, unit: Unit) -> bool:
	"""`reconfigure_unit` from a live [Unit] node — the production entry point.

	The extractor reads the CPU-side `Unit`, whose position and HP are STALE
	mid-battle relative to the GPU. That staleness never lands: `pos_*` / `height`
	are BEHAVE_CARRY so the stale cell is discarded, and `hp` / `mp` are
	BEHAVE_CLAMP so the GPU-live value is what gets clamped (ADR-0235)."""
	return reconfigure_unit(battle_id, unit_idx, GPUCombatPacker._extract_unit_config(unit, _lattice))


func snapshot_battle(battle_id: int) -> Dictionary:
	"""Capture everything that determines a battle's future (ADR-0235).

	Serves the enemy's fork (§7), undo-on-cancel (§4) and battle save/load. Four
	slices, because the state is spread over four SSBOs:

	- `battle` — the battle slice (header + every unit block) from the CURRENT
	  ping-pong half only. The other half carries nothing into the future:
	  `compute_unit_state` opens every tick with `copy_header_to_next` +
	  `copy_unit_to_next`, both total over their whole record, so the write half
	  is fully overwritten from the read half before anything else runs. That is
	  also why `restore_battle` can write one image into both halves and why
	  `_current_buffer` is NOT part of a snapshot — a per-battle capture must not
	  carry a cursor shared by every battle in the batch.
	- `cooldowns` — the single-buffered cooldown SSBO (ADR-0047), which is not in
	  the battle slice at all.
	- `gambits` — the gambit SSBO. It is what the PLAYER edits, so undo-on-cancel
	  is meaningless without it, and a rollout candidate IS a gambit edit.
	  NOT `readonly` to the shader since ADR-0275 dec. 5: the kernel writes a
	  per-slot VERDICT into each slot's two reserved ints, so a snapshot taken
	  after a tick carries diagnostics as well as the program. Harmless to
	  restore — the next gambit evaluation clears and rewrites them — but a
	  caller diffing two snapshots for "did the program change" must mask
	  `GambitField.RESERVED_14`/`RESERVED_15` out.
	- `results` — the 4-int per-battle result record. Write-only from the shader,
	  so it does not affect determinism; captured so a restored battle does not
	  answer `_get_results()` out of a future it no longer has.

	There is no RNG stream to capture: `rand_int` is a stateless PCG hash of
	`(battle_seed, unit_id, tick)`, and both live in the header inside `battle`.

	The dict is plain data on purpose — a caller may edit
	`battle[BattleHeaderField.SEED]` before restoring, which is how §7 spaces its
	Common-Random-Numbers seeds. Returns {} if the battle id is out of range."""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return {}
	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE
	var per_battle_cooldowns = _units_per_battle * MAX_COOLDOWN_ABILITIES
	var per_battle_gambits = _units_per_battle * GAMBITS_PER_UNIT
	var battle_offset = _get_buffer_offset(_current_buffer) + battle_id * single_battle_size
	return {
		"units_per_battle": _units_per_battle,
		"unit_size": UNIT_SIZE,
		"shader_version": SHADER_VERSION,
		"battle": _rd.buffer_get_data(_battle_buffer, battle_offset * 4,
			single_battle_size * 4).to_int32_array(),
		"cooldowns": _rd.buffer_get_data(_cooldown_buffer,
			battle_id * per_battle_cooldowns * 4, per_battle_cooldowns * 4).to_int32_array(),
		"gambits": _rd.buffer_get_data(_gambit_buffer,
			battle_id * per_battle_gambits * 4, per_battle_gambits * 4).to_int32_array(),
		"results": _rd.buffer_get_data(_results_buffer,
			battle_id * RESULT_SIZE * 4, RESULT_SIZE * 4).to_int32_array(),
	}


func restore_battle(battle_id: int, snap: Dictionary) -> bool:
	"""Install a `snapshot_battle` image into a battle slot (ADR-0235).

	The target need not be the source: `restore_battle(k, snapshot_battle(0))` is
	how §7 forks the real battle into candidate slot k, and it is the reason this
	takes a battle id rather than reading one out of the snapshot.

	The battle slice goes into BOTH ping-pong halves — see `snapshot_battle` for
	why that is exact rather than approximate. Returns false and pushes an error
	if the snapshot came from a differently-shaped simulator; a silently-misapplied
	image is the invisible divergence §2 rejects a lossy round trip to avoid."""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return false
	if snap.is_empty():
		return false
	if snap.get("units_per_battle") != _units_per_battle \
			or snap.get("unit_size") != UNIT_SIZE \
			or snap.get("shader_version") != SHADER_VERSION:
		push_error("[GPUBatchSimulator] restore_battle: snapshot shape %s does not match this simulator (%d units x %d ints, shader v%d)" % [
			str({"units_per_battle": snap.get("units_per_battle"), "unit_size": snap.get("unit_size"), "shader_version": snap.get("shader_version")}),
			_units_per_battle, UNIT_SIZE, SHADER_VERSION])
		return false
	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE
	var per_battle_cooldowns = _units_per_battle * MAX_COOLDOWN_ABILITIES
	var per_battle_gambits = _units_per_battle * GAMBITS_PER_UNIT
	var battle_bytes: PackedByteArray = (snap["battle"] as PackedInt32Array).to_byte_array()
	var battle_offset_in_buffer = battle_id * single_battle_size
	_rd.buffer_update(_battle_buffer, (_get_buffer_offset(0) + battle_offset_in_buffer) * 4,
		single_battle_size * 4, battle_bytes)
	_rd.buffer_update(_battle_buffer, (_get_buffer_offset(1) + battle_offset_in_buffer) * 4,
		single_battle_size * 4, battle_bytes)
	_rd.buffer_update(_cooldown_buffer, battle_id * per_battle_cooldowns * 4,
		per_battle_cooldowns * 4, (snap["cooldowns"] as PackedInt32Array).to_byte_array())
	_rd.buffer_update(_gambit_buffer, battle_id * per_battle_gambits * 4,
		per_battle_gambits * 4, (snap["gambits"] as PackedInt32Array).to_byte_array())
	_rd.buffer_update(_results_buffer, battle_id * RESULT_SIZE * 4,
		RESULT_SIZE * 4, (snap["results"] as PackedInt32Array).to_byte_array())
	_bump_battle_version()
	return true


func set_battle_from_units(battle_id: int, team0: Array, team1: Array, battle_seed: int = -1) -> void:
	"""Configure a battle from actual Unit nodes.

	Args:
		battle_id: Which battle to configure
		team0: Array of Unit nodes for team 0
		team1: Array of Unit nodes for team 1
		battle_seed: Random seed (-1 = use battle_id)
	"""
	var team0_configs: Array = []
	var team1_configs: Array = []

	for unit in team0:
		team0_configs.append(GPUCombatPacker._extract_unit_config(unit, _lattice))

	for unit in team1:
		team1_configs.append(GPUCombatPacker._extract_unit_config(unit, _lattice))

	set_battle_units(battle_id, team0_configs, team1_configs, battle_seed)


#endregion


#region Simulation Execution
## The SimConfig block (binding 0), mirroring the struct in combat_common.glslinc
## by INDEX -- there is no generator for this one, so the two orders are kept in
## step by hand and a field appended here must be appended there.
func _build_config_data(pass_mode: int) -> PackedInt32Array:
	var config_data := PackedInt32Array()
	config_data.resize(13)
	config_data[0] = _num_battles
	config_data[1] = _units_per_battle
	config_data[2] = _map_width
	config_data[3] = _map_height
	config_data[4] = 42  # seed_base
	config_data[5] = 0   # movement_only
	config_data[6] = pass_mode
	config_data[7] = _current_buffer  # current_buffer (0 or 1)
	config_data[8] = 1 if _test_mode else 0  # test_mode
	# Pull-read per pass so a debug scrub lands on the very next tick with no
	# rebuild — the buffer is re-uploaded every pass anyway.
	config_data[9] = _pacing_q8(MOVE_TIME_SCALE_SLUG, move_time_scale)
	config_data[10] = _pacing_q8(DAMAGE_SCALE_SLUG, damage_scale)
	config_data[11] = turn_brake_battle
	config_data[12] = settle_brake_battle
	return config_data


func _update_config(pass_mode: int) -> void:
	"""Update config buffer with current settings and pass mode."""
	var config_data := _build_config_data(pass_mode)
	_rd.buffer_update(_config_buffer, 0, config_data.size() * 4, config_data.to_byte_array())
	_refresh_live_config_in_pair()


## 🔴 THE BATCHED PATH BINDS `_uniform_sets_pair`, NOT `_config_buffer`, AND IT
## NEVER CALLS `_update_config` — `_run_ticks_batched` builds its whole K-tick
## compute list up front precisely so there is no mid-list CPU config update. So
## a live config field that only ever reached `_config_buffer` is invisible to
## every batched tick, which is every tick a `step_tick(K>1)` caller runs. Both
## entry points call this; that is the reason it exists.
##
## Re-uploaded only when a value MOVES, so the pair stays what its builder calls
## it: fully static except `current_buffer`. A scrub is a human-rate event, so
## this costs nothing on the ticks between them.
##
## 🔴 THE COMPARISON IS THE WHOLE BLOCK, NOT A NAMED SUBSET. This used to test
## `Vector2i(pair_data[9], pair_data[10])` — the two pacing ints — and return early
## otherwise, which meant every field appended to `SimConfig` after those two was
## dropped on the batched path forever, silently, while working perfectly on the
## single-tick path nobody ships. `turn_brake_battle` was the field that found it.
## Compare the block and the next appended field is covered by construction.
func _refresh_live_config_in_pair() -> void:
	if _config_buffer_pair.is_empty():
		return
	var pair_data := _build_config_data(PASS_COMPUTE_STATE)  # pass_mode unused by shaders
	# `current_buffer` is BAKED per member below, so it is the one index that is
	# legally different between the two and must not enter the comparison.
	var key := pair_data.duplicate()
	key[7] = 0
	if key == _last_pair_data:
		return
	_last_pair_data = key
	for cb in range(_config_buffer_pair.size()):
		pair_data[7] = cb
		_rd.buffer_update(_config_buffer_pair[cb], 0, pair_data.size() * 4, pair_data.to_byte_array())


func _encode_pass(compute_list, pass_mode: int, work_groups: int) -> void:
	"""Encode one shader pass into an already-open compute list (no submit/sync).

	The whole tick is submitted as a single compute list (see _run_tick), so this
	only binds + dispatches. Ordering between passes is enforced by explicit
	memory barriers in _run_tick, not by separate submissions."""
	_encode_pass_with_sets(compute_list, pass_mode, work_groups, _uniform_sets)


func _encode_pass_with_sets(compute_list, pass_mode: int, work_groups: int, sets: Array) -> void:
	"""_encode_pass against a caller-chosen uniform-set array. The batched path
	passes `_uniform_sets_pair[current_buffer]` so the ping-pong is selected by
	which config-bound set is bound, not by a mid-list CPU config update."""
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipelines[pass_mode])
	_rd.compute_list_bind_uniform_set(compute_list, sets[pass_mode], 0)
	_rd.compute_list_dispatch(compute_list, work_groups, 1, 1)


func _run_tick() -> void:
	"""Run a single simulation tick (8 passes) as ONE submitted compute list.

	Every pass reads the previous pass's writes to the battle buffer (a
	read-after-write hazard), so a full memory barrier is inserted between
	consecutive passes. This replaces the former per-pass submit()/sync() —
	which measured as ~97% of tick wall time (8 CPU↔GPU round-trips) — with a
	single round-trip per tick. Config is identical across the tick's passes
	(pass_mode is unused by the shaders; current_buffer is constant until the
	end-of-tick swap), so it is uploaded once here instead of once per pass."""

	# Calculate work groups
	var units_work_groups = (_num_battles * _units_per_battle + 63) / 64
	var battles_work_groups = (_num_battles + 63) / 64

	_update_config(PASS_COMPUTE_STATE)

	var compute_list = _rd.compute_list_begin()

	# Pass 1: All units compute next state (one thread per unit)
	_encode_pass(compute_list, PASS_COMPUTE_STATE, units_work_groups)
	_rd.compute_list_add_barrier(compute_list)

	# Pass 1b: Run the deferred ACTION_ATTACK body for units that picked it
	# (Phase 3 extraction; reads U_PENDING_ACTION_TYPE / U_TARGET from NEXT)
	_encode_pass(compute_list, PASS_ATTACK, units_work_groups)
	_rd.compute_list_add_barrier(compute_list)

	# Pass 1c: Run the deferred ACTION_SPELL / ACTION_ABILITY / ACTION_ITEM
	# bodies + ACTION_COMPLETE_SPELL for charge completion (Phase 4
	# extraction; reads pending + U_CAST_TARGET / U_CASTING_ABILITY_ID).
	_encode_pass(compute_list, PASS_SPELL, units_work_groups)
	_rd.compute_list_add_barrier(compute_list)

	# Pass 1d: Run the deferred ACTION_MOVE_TO / ACTION_PATHFIND_MOVE /
	# ACTION_PATHFIND_CAST / ACTION_MOVE_TO_UNIT / ACTION_RETREAT_STEP bodies
	# (Phase 5 extraction; reads pending + U_DEST_X/Z/LEVEL / U_TARGET /
	# U_CAST_TARGET / U_CASTING_ABILITY_ID).
	_encode_pass(compute_list, PASS_PATHFIND, units_work_groups)
	_rd.compute_list_add_barrier(compute_list)

	# Pass 2: Resolve movement conflicts (one thread per battle)
	_encode_pass(compute_list, PASS_RESOLVE_CONFLICTS, battles_work_groups)
	_rd.compute_list_add_barrier(compute_list)

	# Pass 3: Check attacks after positions resolved (one thread per battle)
	_encode_pass(compute_list, PASS_POST_CONFLICT_ATTACKS, battles_work_groups)
	_rd.compute_list_add_barrier(compute_list)

	# Pass 4: Apply damage (one thread per battle)
	_encode_pass(compute_list, PASS_APPLY_DAMAGE, battles_work_groups)
	_rd.compute_list_add_barrier(compute_list)

	# Pass 5: Check victory (one thread per battle) — last pass, no trailing barrier
	_encode_pass(compute_list, PASS_CHECK_VICTORY, battles_work_groups)

	_rd.compute_list_end()

	_rd.submit()
	_rd.sync()

	# Swap buffers (next becomes current)
	_current_buffer = 1 - _current_buffer
	_bump_battle_version()


func _run_ticks_batched(k: int) -> void:
	"""Run K simulation ticks as ONE submitted compute list — the batched form of
	_run_tick (Phase 2a).

	Amortizes the single per-tick submit()/sync() fence — which Phase 1 measured
	as the dominant tick wall time (compute is ~10% of it) — over K ticks. It is
	byte-identical to K sequential _run_tick calls: a full memory barrier
	separates every pass AND every tick (each pass and each next tick has a
	read-after-write hazard on the battle buffer), and the ping-pong is flipped
	per tick by binding the config-baked uniform set for the current buffer rather
	than a mid-list CPU config update (which would alias across the batch)."""
	var units_work_groups = (_num_battles * _units_per_battle + 63) / 64
	var battles_work_groups = (_num_battles + 63) / 64

	# The only config write this path gets. It happens BEFORE compute_list_begin
	# because a buffer_update inside an open list would alias across the batch —
	# which is the same reason this path bakes `current_buffer` into the pair.
	_refresh_live_config_in_pair()

	var compute_list = _rd.compute_list_begin()
	for t in range(k):
		var sets: Array = _uniform_sets_pair[_current_buffer]
		# Same 8-pass sequence as _run_tick, bound to this tick's ping-pong config.
		_encode_pass_with_sets(compute_list, PASS_COMPUTE_STATE, units_work_groups, sets)
		_rd.compute_list_add_barrier(compute_list)
		_encode_pass_with_sets(compute_list, PASS_ATTACK, units_work_groups, sets)
		_rd.compute_list_add_barrier(compute_list)
		_encode_pass_with_sets(compute_list, PASS_SPELL, units_work_groups, sets)
		_rd.compute_list_add_barrier(compute_list)
		_encode_pass_with_sets(compute_list, PASS_PATHFIND, units_work_groups, sets)
		_rd.compute_list_add_barrier(compute_list)
		_encode_pass_with_sets(compute_list, PASS_RESOLVE_CONFLICTS, battles_work_groups, sets)
		_rd.compute_list_add_barrier(compute_list)
		_encode_pass_with_sets(compute_list, PASS_POST_CONFLICT_ATTACKS, battles_work_groups, sets)
		_rd.compute_list_add_barrier(compute_list)
		_encode_pass_with_sets(compute_list, PASS_APPLY_DAMAGE, battles_work_groups, sets)
		_rd.compute_list_add_barrier(compute_list)
		_encode_pass_with_sets(compute_list, PASS_CHECK_VICTORY, battles_work_groups, sets)
		# The next tick reads this tick's writes; the LAST tick needs no trailing
		# barrier (submit()/sync() closes the batch).
		if t < k - 1:
			_rd.compute_list_add_barrier(compute_list)
		_current_buffer = 1 - _current_buffer
	_rd.compute_list_end()

	_rd.submit()
	_rd.sync()
	_bump_battle_version()


func step_tick(ticks_to_run: int = 1) -> void:
	"""Run a fixed number of ticks for parity testing with shadow units.

	Args:
		ticks_to_run: Number of ticks to advance (default 1)

	A single tick uses _run_tick (one submit/sync); >1 uses the batched path
	(_run_ticks_batched — one submit/sync for the whole run), which is
	byte-identical but amortizes the fence over K ticks."""
	if not _initialized:
		return

	if ticks_to_run <= 1:
		if ticks_to_run == 1:
			_run_tick()
		return

	_run_ticks_batched(ticks_to_run)


#endregion


#region State Queries
func _bump_battle_version() -> void:
	"""Invalidate the readback cache — call after ANY write to _battle_buffer
	(a tick's compute writes, set_battle_units, _set_unit_field, apply_pending_heal)
	so the next state query re-reads instead of serving stale bytes.

	Every cache below keys off _battle_version, so the bump invalidates the region
	bytes, the full snapshot, the lean snapshot and the battle header together."""
	_battle_version += 1


func _read_battle_region(battle_id: int) -> PackedInt32Array:
	"""Return the full single-battle int32 region (header + all units) for
	`battle_id`, reading it from the GPU at most once per _battle_version. Repeat
	reads of an unchanged buffer are cache hits — this is the seam that collapses a
	frame's 2-4 redundant buffer_get_data into one blocking sync."""
	if _rb_cache_version == _battle_version and _rb_cache_battle_id == battle_id \
			and not _rb_cache_data.is_empty():
		return _rb_cache_data
	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE
	var buffer_offset = _get_buffer_offset(_current_buffer)
	var battle_offset = buffer_offset + battle_id * single_battle_size
	var bytes = _rd.buffer_get_data(_battle_buffer, battle_offset * 4, single_battle_size * 4)
	_rb_cache_data = bytes.to_int32_array()
	_rb_cache_version = _battle_version
	_rb_cache_battle_id = battle_id
	return _rb_cache_data


func get_battle_unit_states(battle_id: int) -> Array[Dictionary]:
	"""Get unit states for a specific battle (for shadow unit syncing).

	Args:
		battle_id: Which battle to get states from

	Returns:
		Array of unit state dictionaries (READ-ONLY — cached and shared per
		_battle_version; callers must not mutate the dicts, per ADR-0018)
	"""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return []

	# Built-array cache: skip both the readback AND the dict rebuild when the
	# buffer hasn't changed since the last query (the common per-frame re-read).
	if _rb_states_version == _battle_version and _rb_states_battle_id == battle_id \
			and not _rb_states_cache.is_empty():
		return _rb_states_cache

	# Whole-region read (cached per _battle_version); units start after the header.
	var data = _read_battle_region(battle_id)

	var result: Array[Dictionary] = []

	# Field set + snake_case key names come from the generated SNAPSHOT_FIELDS
	# map (tools/gen_gpu_layout.py), so every UnitField is always present and the
	# keys can't drift from the offsets. Read keys as state["pos_x"] etc.
	for i in range(_units_per_battle):
		var offset = BATTLE_HEADER_SIZE + i * UNIT_SIZE
		var unit_state := {}
		for key in SNAPSHOT_FIELDS:
			unit_state[key] = data[offset + SNAPSHOT_FIELDS[key]]
		result.append(unit_state)

	_rb_states_cache = result
	_rb_states_version = _battle_version
	_rb_states_battle_id = battle_id
	return result


func get_battle_unit_states_hot(battle_id: int) -> Array[Dictionary]:
	"""The PER-FRAME snapshot: one Dictionary per unit carrying only the 39 fields
	the per-frame combat path reads (GPUCombatPacker.SNAPSHOT_HOT_UNION), instead
	of all 101.

	Same values, same keys, same read-only contract as get_battle_unit_states —
	this is that function with the 62 keys it has no per-frame reader for left out.
	Building all 101 measured ~1.8 ms/frame and never decayed as units died (W1/F22).

	⚠ A consumer reading a field outside the union gets `.get()`'s DEFAULT, silently.
	Use this ONLY from the per-frame path. Cold and test callers want
	get_battle_unit_states(). tools/check_snapshot_union.py and
	tests/GPUSnapshotUnionTest.tscn are what keep the union honest — see the
	constant's own comment in GPUCombatPacker.gd.

	Returns:
		Array of unit state dictionaries (READ-ONLY — cached and shared per
		_battle_version; callers must not mutate the dicts, per ADR-0018)
	"""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return []

	if _rb_hot_version == _battle_version and _rb_hot_battle_id == battle_id \
			and not _rb_hot_cache.is_empty():
		return _rb_hot_cache

	var data = _read_battle_region(battle_id)

	var result: Array[Dictionary] = []
	for i in range(_units_per_battle):
		var offset = BATTLE_HEADER_SIZE + i * UNIT_SIZE
		var unit_state := {}
		for k in range(HOT_UNION_KEYS.size()):
			unit_state[HOT_UNION_KEYS[k]] = data[offset + HOT_UNION_OFFSETS[k]]
		if debug_poison_non_union:
			# Test mode: hand the per-frame consumers all 101 keys, but fill every
			# one OUTSIDE the union with garbage. Union reads are unaffected; a read
			# of anything else swings wildly instead of quietly taking `.get()`'s
			# default, so the battle diverges and the test catches it.
			for key in SNAPSHOT_FIELDS:
				if not unit_state.has(key):
					unit_state[key] = POISON_VALUE
		result.append(unit_state)

	_rb_hot_cache = result
	_rb_hot_version = _battle_version
	_rb_hot_battle_id = battle_id
	return result


func read_unit_column(battle_id: int, field_offset: int) -> PackedInt32Array:
	"""Return ONE field, for every unit in `battle_id`, as a lean int column —
	no per-unit Dictionary built.

	`get_battle_unit_states` builds an Array of ~99-field Dictionaries; profiling
	showed that string-keyed dict BUILD (not the GPU readback) is ~0.6 ms/call for
	8 units, and the per-tick combat loop only reads a handful of columns (HP,
	EVADE_TYPE, CINEMATIC_TIMER, PAUSED) each tick — the full 99-field snapshot is
	only needed once per FRAME (after the tick loop). This serves those hot per-tick
	reads straight off the version-cached region bytes, so a tick pays one shared
	`buffer_get_data` and a bare int copy instead of building N dicts.

	`field_offset` is the intra-unit offset (a SNAPSHOT_FIELDS / UnitField value).
	Shares `_read_battle_region`'s per-_battle_version cache with the full path.
	"""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return PackedInt32Array()
	var data := _read_battle_region(battle_id)
	var col := PackedInt32Array()
	col.resize(_units_per_battle)
	for i in range(_units_per_battle):
		col[i] = data[BATTLE_HEADER_SIZE + i * UNIT_SIZE + field_offset]
	return col


func get_battle_state(battle_id: int) -> Dictionary:
	"""Get per-battle header state (tick, result, cinematic, etc.) for a battle.

	Distinct from get_battle_unit_states (per-unit fields): this returns the
	BattleHeader's six per-battle scalars, keyed by BATTLE_STATE_FIELDS.
	"""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return {}

	if _rb_bstate_version == _battle_version and _rb_bstate_battle_id == battle_id \
			and not _rb_bstate_cache.is_empty():
		return _rb_bstate_cache

	# Header sits at the start of the cached whole-region read.
	var data = _read_battle_region(battle_id)

	var state := {}
	for key in BATTLE_STATE_FIELDS:
		state[key] = data[BATTLE_STATE_FIELDS[key]]
	_rb_bstate_cache = state
	_rb_bstate_version = _battle_version
	_rb_bstate_battle_id = battle_id
	return state


func get_battle_tick(battle_id: int) -> int:
	"""Get current tick for a specific battle."""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return 0

	return _read_battle_region(battle_id)[BattleHeaderField.TICK]


func get_cooldown_ready_at(battle_id: int, unit_id: int, ability_id: int) -> int:
	"""Read one (unit, ability) slot of the cooldown SSBO (ADR-0047 / issue #85).

	Scenario diagnostics — sampled by the gambit runner so the trace can store
	`cooldown_ready_at` alongside each cast event. Lets B8 distinguish a real
	cooldown violation (GPU commit at GPU tick < ready_at) from a frame-boundary
	trace-reporting drift (GPU tick was respected, but the host-frame report of
	the cast tick lags by the unconsumed remainder of the tick loop).
	"""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return 0
	if unit_id < 0 or unit_id >= _units_per_battle:
		return 0
	if ability_id < 0 or ability_id >= MAX_COOLDOWN_ABILITIES:
		return 0
	var unit_global_idx = battle_id * _units_per_battle + unit_id
	var byte_offset = (unit_global_idx * MAX_COOLDOWN_ABILITIES + ability_id) * 4
	var bytes = _rd.buffer_get_data(_cooldown_buffer, byte_offset, 4)
	return bytes.to_int32_array()[0]


func is_battle_finished(battle_id: int) -> bool:
	"""Check if a battle has finished."""
	if not _initialized or battle_id < 0 or battle_id >= _num_battles:
		return true

	return _read_battle_region(battle_id)[BattleHeaderField.RESULT] != RESULT_ONGOING


func _get_results() -> Dictionary:
	"""Get simulation results.

	Returns:
		Dictionary with:
		- total: Total number of battles
		- team0_wins: Number of team 0 wins
		- team1_wins: Number of team 1 wins
		- draws: Number of draws
		- avg_ticks: Average ticks per battle
		- battles: Array of per-battle results
	"""
	if not _initialized:
		return {}

	# Read results buffer
	var bytes = _rd.buffer_get_data(_results_buffer)
	var data = bytes.to_int32_array()

	var team0_wins = 0
	var team1_wins = 0
	var draws = 0
	var total_ticks = 0
	var battles: Array = []

	for i in range(_num_battles):
		var offset = i * RESULT_SIZE
		var result = data[offset + GPUCombatPacker.ResultField.RESULT]
		var ticks = data[offset + GPUCombatPacker.ResultField.TICKS]
		var team0_hp = data[offset + GPUCombatPacker.ResultField.TEAM0_HP]
		var team1_hp = data[offset + GPUCombatPacker.ResultField.TEAM1_HP]

		match result:
			RESULT_TEAM_0_WINS:
				team0_wins += 1
			RESULT_TEAM_1_WINS:
				team1_wins += 1
			_:
				draws += 1

		total_ticks += ticks

		battles.append({
			"battle_id": i,
			"winner": result,
			"ticks": ticks,
			"team0_hp": team0_hp,
			"team1_hp": team1_hp,
		})

	return {
		"total": _num_battles,
		"team0_wins": team0_wins,
		"team1_wins": team1_wins,
		"draws": draws,
		"win_rate": float(team0_wins) / float(_num_battles) * 100.0 if _num_battles > 0 else 0.0,
		"avg_ticks": float(total_ticks) / float(_num_battles) if _num_battles > 0 else 0.0,
		"battles": battles,
	}


func get_battle_result(battle_id: int) -> Dictionary:
	"""Get result for a specific battle."""
	var results = _get_results()
	if battle_id >= 0 and battle_id < results.get("battles", []).size():
		return results["battles"][battle_id]
	return {}


func read_all_gambits() -> PackedInt32Array:
	"""The WHOLE gambit SSBO in one read — `_num_battles * _units_per_battle *
	GAMBITS_PER_UNIT` ints, laid out by GLOBAL unit id.

	The fleet-side companion to `read_all_results`, and it exists for the same
	reason that one does. Since ADR-0275 dec. 5 the kernel writes a per-slot
	VERDICT into each slot's `RESERVED_14`/`RESERVED_15`, so this buffer is the
	only place the lab's answer lives — and the per-battle reader for it is
	`snapshot_battle`, which costs FOUR blocking `buffer_get_data` calls per
	battle. A 256-battle sweep that read the verdict through it would pay 1,024
	stalls per tick to learn 256 battles' worth of one nibble.

	Index it with `GambitVerdictReader.read_slot(words, global_unit, slot)` where
	`global_unit = battle_id * get_units_per_battle() + unit` — the same global id
	`set_unit_gambits` writes at, so the read and the write agree by construction
	rather than by a second offset formula living here.

	⚠️ A slot's verdict is only as fresh as the last evaluation that WALKED it
	(`clear_verdict` is scoped to `max_slot`). A caller that steps N ticks and then
	reads once has read the LAST decision, not the first; ADR-0275's scoring rule
	wants the first, which is why the sweeper reads every tick and latches."""
	if not _initialized:
		return PackedInt32Array()
	return _rd.buffer_get_data(_gambit_buffer).to_int32_array()


func read_all_results() -> PackedInt32Array:
	"""The WHOLE result buffer in one read — `_num_battles * RESULT_SIZE` ints,
	`[result, ticks, team0_hp, team1_hp]` per battle.

	This is the fleet-scoring shape ADR-0237 dec. 7 requires, and the reason it is
	a separate entry point from `get_battle_result`: that one calls `_get_results`,
	which re-reads AND re-parses the entire buffer into a Dictionary per battle
	on every call, so scoring a 256-battle fleet through it costs 256 whole-buffer
	reads. The buffer itself reads in 0.11 ms. A scorer that loops
	`get_battle_result` (or `read_unit_column`, at 33-51 ms for one column across
	1024 battles) is the shape that measurement exists to reject.

	Raw ints rather than Dictionaries on purpose — `_get_results`'s dict building
	was measured as the dominant cost of the per-battle readers, and #896's value
	function wants columns, not records."""
	if not _initialized:
		return PackedInt32Array()
	return _rd.buffer_get_data(_results_buffer).to_int32_array()


func is_initialized() -> bool:
	return _initialized


func get_num_battles() -> int:
	"""Fleet size: how many battles this simulator's buffers hold. One for every
	host in the tree today; sized by `CombatLoop.rollout_fleet_size` for a host
	that runs rollouts (#895 §7)."""
	return _num_battles


func get_units_per_battle() -> int:
	"""Allocated unit slots per battle — NOT the living unit count. Rollout cost
	scales with this (ADR-0237 dec. 2), and so does the CRN seed spacing
	(`RolloutHarness.crn_span`), because the RNG hashes `unit_id * 1000`."""
	return _units_per_battle


func get_result_size() -> int:
	"""Ints per battle in the result buffer, for a caller indexing
	`read_all_results` itself."""
	return RESULT_SIZE


#endregion


#region Gambit & Ability Configuration
func set_unit_gambits(battle_id: int, unit_idx: int, gambits: Array) -> void:
	"""Set gambit data for a specific unit.

	Args:
		battle_id: Which battle the unit is in
		unit_idx: Unit index within the battle (0-7)
		gambits: Array of gambit configurations (up to MAX_GAMBITS = 6 slots:
			5 authored + the encoder-injected safety net, ADR-0048)
	"""
	if not _initialized:
		return

	# Calculate global unit ID
	var global_unit_id = battle_id * _units_per_battle + unit_idx

	# Pack (pure, ADR-0016) then upload — the split mirrors the unit path's
	# _write_unit_data / buffer-upload separation and keeps packing GPU-free.
	var data := GPUCombatPacker._pack_gambits(gambits)
	var buffer_offset = global_unit_id * GAMBITS_PER_UNIT * 4  # bytes
	_rd.buffer_update(_gambit_buffer, buffer_offset, data.size() * 4, data.to_byte_array())


#endregion


#region Runtime Buffer Updates
func apply_pending_heal(battle_id: int, caster_idx: int, target_idx: int, amount: int) -> void:
	"""Apply deferred healing from a projectile ability landing.

	This is called by the CPU when a healing projectile lands on its target.
	It updates the target's HP and clears the caster's pending heal fields.

	Args:
		battle_id: Which battle
		caster_idx: The unit who cast the healing ability
		target_idx: The unit being healed
		amount: Amount to heal
	"""
	if not _initialized:
		return

	var single_battle_size = BATTLE_HEADER_SIZE + _units_per_battle * UNIT_SIZE

	# Update BOTH buffers for consistency
	for buf in [0, 1]:
		var buffer_offset = _get_buffer_offset(buf) + battle_id * single_battle_size

		# Read target's current data
		var target_offset = buffer_offset + BATTLE_HEADER_SIZE + target_idx * UNIT_SIZE
		var target_bytes = _rd.buffer_get_data(_battle_buffer, target_offset * 4, UNIT_SIZE * 4)
		var target_data = target_bytes.to_int32_array()

		# Apply healing (capped at max_hp)
		var current_hp = target_data[UnitField.HP]
		var max_hp = target_data[UnitField.MAX_HP]
		var new_hp = mini(max_hp, current_hp + amount)
		target_data[UnitField.HP] = new_hp

		# Write back target data
		_rd.buffer_update(_battle_buffer, target_offset * 4, target_data.size() * 4, target_data.to_byte_array())

		# Clear caster's pending heal fields
		var caster_offset = buffer_offset + BATTLE_HEADER_SIZE + caster_idx * UNIT_SIZE
		var caster_bytes = _rd.buffer_get_data(_battle_buffer, caster_offset * 4, UNIT_SIZE * 4)
		var caster_data = caster_bytes.to_int32_array()

		caster_data[UnitField.PENDING_HEAL_TARGET] = -1
		caster_data[UnitField.PENDING_HEAL_AMOUNT] = 0
		caster_data[UnitField.CASTING_ABILITY_ID] = -1  # Clear ability now that effect is complete
		caster_data[UnitField.CAST_TARGET] = -1

		_rd.buffer_update(_battle_buffer, caster_offset * 4, caster_data.size() * 4, caster_data.to_byte_array())

	_bump_battle_version()
#endregion


#region Cleanup
func cleanup() -> void:
	"""Free GPU resources."""
	if not _rd:
		return

	for us in _uniform_sets:
		if us.is_valid():
			_rd.free_rid(us)
	_uniform_sets.clear()
	if _cooldown_buffer.is_valid():
		_rd.free_rid(_cooldown_buffer)
	if _ability_buffer.is_valid():
		_rd.free_rid(_ability_buffer)
	if _gambit_buffer.is_valid():
		_rd.free_rid(_gambit_buffer)
	if _anim_timings_buffer.is_valid():
		_rd.free_rid(_anim_timings_buffer)
	# Binding 8. It was the ONE buffer `_create_buffers` makes that this never gave
	# back — "1 RID of type StorageBuffer was leaked" on every teardown, once per
	# battle in a campaign (`CombatLoop._exit_tree`) and once per configuration in
	# `GPURolloutBudgetBench`, which is where it finally became visible (#890).
	if _effect_timings_buffer.is_valid():
		_rd.free_rid(_effect_timings_buffer)
	if _results_buffer.is_valid():
		_rd.free_rid(_results_buffer)
	if _battle_buffer.is_valid():
		_rd.free_rid(_battle_buffer)
	if _distance_buffer.is_valid():
		_rd.free_rid(_distance_buffer)
	if _map_buffer.is_valid():
		_rd.free_rid(_map_buffer)
	if _config_buffer.is_valid():
		_rd.free_rid(_config_buffer)
	for cfg in _config_buffer_pair:
		if cfg.is_valid():
			_rd.free_rid(cfg)
	_config_buffer_pair.clear()
	_uniform_sets_pair.clear()
	for pipeline in _pipelines:
		if pipeline.is_valid():
			_rd.free_rid(pipeline)
	for shader in _shaders:
		if shader.is_valid():
			_rd.free_rid(shader)
	_pipelines.clear()
	_shaders.clear()

	# AND THE DEVICE ITSELF (#471). Freeing the RIDs is not what stops the crash — a
	# local RenderingDevice with NO rids on it at all reproduces it, and freeing the
	# device with no rid work reproduces the clean exit. Measured, 2 runs each, on a
	# three-line scene: create-and-leave = exit 134 twice, create-and-free = exit 0
	# twice, no-device control = exit 0 twice. A live local device at shutdown makes
	# `Main::cleanup -> finalize_display -> ~RenderingContextDriverVulkan ->
	# vkDestroyInstance` dlclose the NVIDIA ICD out from under it, and a destructor
	# inside libnvidia-glcore segfaults; Godot's handler turns that SIGSEGV into an
	# abort, which is the `dumped core` line and exit 134.
	if _rd:
		_rd.free()
	_rd = null

	_initialized = false


# NOT hooked to NOTIFICATION_PREDELETE, and that is measured rather than assumed: by
# the time PREDELETE arrives on a RefCounted the script instance is already coming
# apart, and calling out to `cleanup()` from there fails with "Attempt to call
# function 'cleanup' in base 'null instance'" — a SCRIPT ERROR that aborts the
# handler, leaks every RID, and leaves the device live anyway. The owner calls this;
# see `CombatLoop._exit_tree`. #471.
#endregion
