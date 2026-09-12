class_name GPUConstants
extends RefCounted

## Centralized GPU simulation constants.
##
## Single source of truth for all constants that must match between
## the GPU compute shader and GDScript. All GPU-related scripts should
## reference these constants instead of defining their own.

# === BEGIN GENERATED: combat buffer layout (tools/gen_gpu_layout.py) ===
# Source of truth: src/gpu/shaders/combat_common.glslinc
# Names/values/order are generated - DO NOT edit them here.
# Trailing # comments ARE preserved across regeneration; edit them freely.
# Regenerate: uv run python tools/gen_gpu_layout.py

const MAX_GAMBITS = 6  # 5 authored + 1 encoder-injected safety net (ADR-0048)
const GAMBIT_SIZE = 16
const ABILITY_SIZE = 16
const MAX_ABILITIES = 512

# Action types (generated from shader ACTION_* - see header)
const ACTION_NONE = -1
const ACTION_ATTACK = 0
const ACTION_SPELL = 1
const ACTION_ITEM = 2
const ACTION_WAIT = 3
const ACTION_ABILITY = 4
const ACTION_MOVE_TO = 5
const ACTION_COMPLETE_SPELL = 6
const ACTION_PATHFIND_MOVE = 7
const ACTION_PATHFIND_CAST = 8
const ACTION_MOVE_TO_UNIT = 9
const ACTION_RETREAT_STEP = 10

# Target types (generated from shader TARGET_* - see header)
const TARGET_SELF = 0
const TARGET_NEAREST_ENEMY = 1
const TARGET_NEAREST_ALLY = 2
const TARGET_LOWEST_HP_ALLY = 3
const TARGET_HIGHEST_HP_ENEMY = 4
const TARGET_LOWEST_HP_ENEMY = 5
const TARGET_HIGHEST_HP_ALLY = 6
const TARGET_THEM = 7
const TARGET_NEAREST_ALLY_OR_KO = 8
const TARGET_NEAREST_ALLY_ONLY = 9
const TARGET_NEAREST_ENEMY_ONLY = 10

# Condition types (generated from shader COND_* - see header)
const COND_ALWAYS = 0
const COND_HP_BELOW = 1
const COND_HP_ABOVE = 2
const COND_DISTANCE_LESS = 3
const COND_DISTANCE_GREATER = 4
const COND_HAS_STATUS = 5
const COND_NOT_STATUS = 6
const COND_IS_DEAD = 7
const COND_IS_ALIVE = 8
const COND_MP_ABOVE = 9
const COND_MP_BELOW = 10
const COND_TEAM_ALLY = 11
const COND_TEAM_ENEMY = 12
const COND_IN_RANGE = 13

# === END GENERATED ===

# === BEGIN GENERATED: logical-activity (tools/gen_activity_taxonomy.py) ===
# Source of truth: tools/activity_taxonomy.yaml
# Names/values are generated - DO NOT edit them here.
# Regenerate: (cd tools && uv run python gen_activity_taxonomy.py)

const LOGICAL_ACTIVITY_IDLE = 0
const LOGICAL_ACTIVITY_WALKING = 1
const LOGICAL_ACTIVITY_ACTING = 2
const LOGICAL_ACTIVITY_PREEMPTIVE_COUNTER = 3
const LOGICAL_ACTIVITY_SPELL_CHARGING = 4
const LOGICAL_ACTIVITY_WALKING_TO_CAST = 5
const LOGICAL_ACTIVITY_DYING = 6
const LOGICAL_ACTIVITY_CELEBRATING = 7
const LOGICAL_ACTIVITY_APPROACHING = 8
const LOGICAL_ACTIVITY_AWAITING_IMPACT = 9
const LOGICAL_ACTIVITY_RETREATING = 10

const LOGICAL_ACTIVITY_NAMES = ["IDLE", "WALKING", "ACTING", "PREEMPTIVE_COUNTER", "SPELL_CHARGING", "WALKING_TO_CAST", "DYING", "CELEBRATING", "APPROACHING", "AWAITING_IMPACT", "RETREATING"]

# The states in which a unit is BETWEEN TILES -- its logical position is the
# DESTINATION of a step rather than where the sprite is. Derived from the rows
# whose routing is `visualizer`. Read it through `is_movement_state()` below.
const LOGICAL_ACTIVITY_MOVEMENT_STATES = [LOGICAL_ACTIVITY_WALKING, LOGICAL_ACTIVITY_WALKING_TO_CAST, LOGICAL_ACTIVITY_APPROACHING, LOGICAL_ACTIVITY_RETREATING]
# === END GENERATED ===

# --- Weapon types ---
const RANGED_WEAPON_TYPES = [10, 11, 12]  # Gun, Bow, Crossbow

# --- Item/ability offsets ---
const ITEM_EFFECT_ID_OFFSET = 2048
const ITEM_ABILITY_ID_OFFSET = 128

# --- Timing ---
const TICKS_PER_SECOND = 60.0

# --- Gambit / Ability buffer sizes ---
# MAX_GAMBITS, GAMBIT_SIZE, ABILITY_SIZE, MAX_ABILITIES are generated from the
# shader into the region above (they define buffer strides — must match exactly).

# Authored gambit slots per unit (ADR-0048). The buffer (MAX_GAMBITS) holds one
# more — the encoder-injected safety-net gambit at slot MAX_USER_GAMBITS. This is
# an authoring-policy cap (the UI editor + the encoder's authored loop), NOT a
# buffer stride, so it is hand-authored here rather than generated. Derived from
# MAX_GAMBITS so bumping the buffer keeps the one-safety-net invariant.
const MAX_USER_GAMBITS = MAX_GAMBITS - 1

# --- Animation timings (GD-only; not defined in the shader) ---
const MAX_ANIMATIONS = 256  # Maximum animation IDs supported

# --- Effect timings (GD-only; not defined in the shader) ---
# Covers the FFT effect-id range E000..E511 (NUM_VFX in tools/parse_effect.py).
# Slots that don't correspond to a populated assets/effects/E###/timeline.json
# stay at the -1 sentinel; the cinematic-spell orchestrator (issue #53) reads
# first_hit_frame / for_each_delay / total_frames per effect from this buffer.
const MAX_EFFECTS = 512

# --- Flags ---
const FLAG_DEAD_BIT = 1           # flags & 1 != 0 means dead
const FLAG_PROJECTILE_TRIGGER = 2  # anim_flags bit 1

# --- Decision reasons (must match shader REASON_* constants) ---
const REASON_NAMES = [
	"NONE", "TIMER_EXPIRED", "CAN_ATTACK", "START_MOVING",
	"START_ATTACKING", "CONFLICT_BLOCKED", "NO_PATH", "ARRIVED",
	"ATTACK_ENDED", "WAITING_TARGET", "GAMBIT_FAILED", "SPELL_FAILED", "NO_GAMBIT",
	"THRASH_ABORT", "TARGET_DEAD", "TURN_PENDING"
]


## True when the unit is BETWEEN TILES — when its logical position is the
## DESTINATION of a step rather than where the sprite is.
##
## 🔴 THIS IS THE HOST'S ONLY DEFINITION OF "MOVING", AND IT USED TO BE THREE.
## [GPUMovementInterpreter], [TurnDirector]'s turn gate and [GPUVisualBridge]'s
## diagnostics each hand-listed the same states; each said so in its docstring,
## and they DID agree — which is exactly what hid the fourth. ADR-0301 added
## `LOGICAL_ACTIVITY_RETREATING` to the kernel's three lists and to none of
## these, so the interpreter classified every retreat `NO_MOVE`, the bridge
## dropped the visualizer and snapped to the GPU tile, and a retreating unit
## teleported while still facing what it was fleeing, in whatever pose it held.
## One omission, three symptoms, and no test in a position to see any of them.
##
## The members are GENERATED from the taxonomy rows whose `routing` is
## `visualizer` — the YAML's own declaration that the move visualizer authors
## that row's body activity, which is true of a row precisely when the unit is
## mid-step. So a fifth move state joins every consumer by being a row, and
## `is_movement_state` in `combat_common.glslinc` is the kernel's half of the
## same derivation.
static func is_movement_state(state: int) -> bool:
	return state in LOGICAL_ACTIVITY_MOVEMENT_STATES
