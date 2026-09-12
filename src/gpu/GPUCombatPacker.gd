class_name GPUCombatPacker
extends RefCounted

## GPU Combat Packer - the combat-buffer FORMAT and PACKING half.
##
## Extracted from GPUBatchSimulator (issue #153) so the buffer layout (field
## offsets, size constants, snapshot/state field-maps) and the config->bytes
## packing logic live apart from the GPU device lifecycle. Pure: no
## RenderingDevice, no instance device state -- every member here is a const,
## a static var, or a static function of its arguments, so the pure schema
## tests exercise it with no scene setup.
##
## GPUBatchSimulator depends on this one-directionally (a reader of the format
## depending on its writer); it aliases the layout symbols below via
## `const UnitField = GPUCombatPacker.UnitField` etc. so its device-read/upload
## method bodies stay unchanged.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const Lattice = ExMateriaBattlefield.Lattice

## And the same for `addons/exmateria_schema`, whose six generic-English globals
## collapsed onto one façade in the same pass (ADR-0212 dec. 1).
const TerrainCell = ExMateriaSchema.TerrainCell

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ElementEncoder = ExMateriaAlmanac.ElementEncoder
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const StatusEncoder = ExMateriaAlmanac.StatusEncoder
const StatusRegistry = ExMateriaAlmanac.StatusRegistry
const UnitProgression = ExMateriaAlmanac.UnitProgression


# === BEGIN GENERATED: combat buffer layout (tools/gen_gpu_layout.py) ===
# Source of truth: src/gpu/shaders/combat_common.glslinc
# Names/values/order are generated - DO NOT edit them here.
# Trailing # comments ARE preserved across regeneration; edit them freely.
# Regenerate: uv run python tools/gen_gpu_layout.py

const UNIT_SIZE = 104
const BATTLE_HEADER_SIZE = 4  # tick, result, flags, seed
const SHADER_VERSION = 35
const TURN_METER_FULL = 3600
const RESULT_SIZE = 14

enum UnitField {
	POS_X = 0,
	POS_Z = 1,
	HP = 2,
	MAX_HP = 3,
	PA = 4,
	MA = 5,
	WP = 6,  # Weapon Power
	BRAVE = 7,  # Brave stat
	FAITH = 8,  # Faith stat
	SPEED = 9,
	MOVE = 10,
	JUMP = 11,
	TEAM = 12,
	STATE = 13,
	TARGET = 14,
	TIMER = 15,
	DEST_X = 16,
	DEST_Z = 17,
	FLAGS = 18,
	C_EV = 19,  # Class Evade
	S_EV = 20,  # Shield Evade (physical block)
	W_EV = 21,  # Weapon Evade
	REACTION_TIMER = 22,  # Timer for damage reaction
	WEAPON_RANGE = 23,  # Weapon range (1-8 tiles)
	WEAPON_FLAGS = 24,  # GPU-internal packed protocol (NOT the ROM byte - see ADR-0013): bit0=striking, bit1=lunging, bit2=direct, bit3=arc. Encoded by _extract_unit_config from prog.get_weapon_flags() (the semantic dict).
	HEIGHT = 25,  # Tile height in half-steps
	PENDING_DAMAGE = 26,  # Damage queued for end-of-round application
	PROPOSED_X = 27,  # Proposed next X position
	PROPOSED_Z = 28,  # Proposed next Z position
	DAMAGE_TARGET = 29,  # Unit to deal damage to
	DAMAGE_AMOUNT = 30,  # Damage amount to deal
	DBG_CONFLICT_BLOCKED = 31,  # Was this unit blocked by conflict resolution?
	DBG_CONFLICT_BLOCKER = 32,  # Which unit blocked us? (-1 if none)
	DBG_PROPOSED_ACCEPTED = 33,  # Was proposed position accepted?
	DBG_STATE_REASON = 34,  # Why did state change? (enum)
	DBG_PATH_TRAVERSE = 35,  # Number of traversable neighbors (0-4)
	DBG_PATH_JUMP = 36,  # Number passing jump check
	DBG_PATH_UNOCC = 37,  # Number unoccupied
	DBG_PATH_DIST = 38,  # Number with valid distance
	DBG_BEST_DIST = 39,  # Best distance found (-1 if none)
	DBG_NEXT_X = 40,  # Returned next step X
	DBG_NEXT_Z = 41,  # Returned next step Z
	ANIM_ID = 42,  # Current animation ID (e.g., 122 for unarmed attack)
	ANIM_FRAME = 43,  # Current animation frame counter
	DAMAGE_FRAME = 44,  # Pre-computed PostGenericAttack frame position
	TOTAL_FRAMES = 45,  # Total animation duration in frames
	ANIM_FLAGS = 46,  # Bit 0: damage_triggered
	WEAPON_TYPE = 47,  # Weapon type for animation selection
	MP = 48,  # Current mana points
	MAX_MP = 49,  # Maximum mana points
	CASTING_ABILITY_ID = 50,  # Ability being charged (-1 = none)
	CAST_TARGET = 51,  # Target unit for spell
	CAST_TIMER = 52,  # Ticks remaining until cast completes
	ABILITY_FLAGS = 53,  # Bit flags: can_use_magic, can_use_items, etc.
	STATUS_FLAGS_LO = 54,  # Bits 0-31: poison, haste, slow, protect, shell, etc.
	STATUS_FLAGS_HI = 55,  # Bits 32-63: remaining statuses
	STATUS_TIMER_0 = 56,
	STATUS_TIMER_1 = 57,
	STATUS_TIMER_2 = 58,
	STATUS_TIMER_3 = 59,
	STATUS_TIMER_4 = 60,
	STATUS_TIMER_5 = 61,
	STATUS_TIMER_6 = 62,
	STATUS_TIMER_7 = 63,
	CURRENT_GAMBIT = 64,  # Which gambit slot triggered current action
	GAMBIT_COOLDOWN = 65,  # Ticks before re-evaluating gambits
	REACTION_ABILITY = 66,  # Equipped reaction ability ID
	SUPPORT_ABILITY = 67,  # Equipped support ability ID
	MOVEMENT_ABILITY = 68,  # Equipped movement ability ID
	PROJECTILE_FRAME = 69,  # Frame when projectile should spawn (ranged only)
	PENDING_HEAL_TARGET = 70,  # Target for deferred projectile healing (-1 = none)
	PENDING_HEAL_AMOUNT = 71,  # Amount to heal when projectile lands
	AOE_CENTER_X = 72,
	AOE_CENTER_Z = 73,
	AOE_ABILITY_ID = 74,
	S_EV_MAG = 75,  # Magic shield evade
	EVADE_TYPE = 76,  # 0=no evasion, 1=class evade, 2=shield block, 3=weapon parry
	DECISION_HIST_0 = 77,  # Decision ring buffer entries 0-1 (2 x 16-bit)
	DECISION_HIST_1 = 78,  # Decision ring buffer entries 2-3
	DECISION_HIST_2 = 79,  # Decision ring buffer entries 4-5
	DECISION_META = 80,  # Bits [2:0]=write_idx, bit 3=thrash_flag, [7:4]=thrash_count
	PREV_MOVE_POS = 81,  # (prev_x << 16) | prev_z - anti-backtrack
	MOVE_TOTAL_TICKS = 82,  # Total movement ticks for current step (after HASTE/SLOW)
	MOVE_STEP_ID = 83,  # Monotonic counter incremented each movement step
	PENDING_ACTION_TYPE = 84,  # Stage 2b scaffold - decide-stage output carrier (ACTION_NONE = none)
	CAST_STEP_ID = 85,
	PAUSED = 86,
	AOE_PENDING_CASTER = 87,
	AOE_PENDING_FIRE_FRAME = 88,
	WEAPON_INFLICT_MASK = 89,
	WEAPON_INFLICT_MODE = 90,
	ELEMENT_ABSORB_MASK = 91,
	ELEMENT_CANCEL_MASK = 92,
	ELEMENT_HALF_MASK = 93,
	ELEMENT_WEAK_MASK = 94,
	WEAPON_ELEMENT = 95,
	STRENGTHEN_MASK = 96,
	CINEMATIC_TIMER = 97,
	LEVEL = 98,
	DEST_LEVEL = 99,
	PROPOSED_LEVEL = 100,
	TURN_METER = 101,
	ATTACK_PERIOD_FACTOR_Q8 = 102,
	ATTACK_RECOVERY = 103,
}

enum BattleHeaderField {
	TICK = 0,
	RESULT = 1,
	FLAGS = 2,
	SEED = 3,
}

enum GambitField {
	ENABLED = 0,
	COND_TARGET_TYPE = 1,
	COND_COUNT = 2,
	COND_TYPE_0 = 3,
	COND_TYPE_1 = 4,
	COND_TYPE_2 = 5,
	COND_TYPE_3 = 6,
	COND_VAL_0 = 7,
	COND_VAL_1 = 8,
	COND_VAL_2 = 9,
	COND_VAL_3 = 10,
	ACTION_TYPE = 11,
	ACTION_ID = 12,
	ACTION_TARGET_TYPE = 13,
	RESERVED_14 = 14,  # ADR-0275 dec. 4: kernel-written VERDICT, one nibble set per gambit pass
	RESERVED_15 = 15,  # ADR-0275 dec. 4: kernel-written verdict PAYLOAD, the number that lost
}

enum AbilityField {
	MP_COST = 0,
	CHARGE_TIME = 1,
	RANGE = 2,
	FORMULA_ID = 3,
	FORMULA_Y = 4,
	EFFECT_AREA = 5,
	FORMULA_X = 6,
	ELEMENT = 7,
	FLAGS = 8,
	EFFECT_ANIM_ID = 9,  # Cast animation = effect_anim_id * 2
	VERTICAL = 10,
	EFFECT_ID = 11,
	COOLDOWN_TICKS = 12,
	INFLICT_MASK = 13,
	INFLICT_MODE = 14,
}

enum ResultField {
	RESULT = 0,  # RESULT_ONGOING / RESULT_TEAM_*_WINS / RESULT_DRAW
	TICKS = 1,  # battle tick this record was written at
	TEAM0_HP = 2,  # sum of HP over living team-0 units
	TEAM1_HP = 3,  # sum of HP over living team-1 units
	TEAM0_ALIVE = 4,  # standing count, team 0
	TEAM1_ALIVE = 5,  # standing count, team 1
	TEAM0_MP = 6,  # sum of MP over living team-0 units
	TEAM1_MP = 7,  # sum of MP over living team-1 units
	TEAM0_MAX_HP = 8,  # sum of MAX HP over ALL team-0 slots, living or not
	TEAM1_MAX_HP = 9,  # sum of MAX HP over ALL team-1 slots, living or not
	TEAM0_ENGAGE = 10,  # sum over living team-0 units of manhattan distance to team 1's centroid
	TEAM1_ENGAGE = 11,  # and the mirror; both 0 once either team is wiped
	TEAM0_MAX_MP = 12,  # sum of MAX MP over ALL team-0 slots, living or not
	TEAM1_MAX_MP = 13,  # sum of MAX MP over ALL team-1 slots, living or not
}

# SNAPSHOT_FIELDS: snake_case key -> UnitField offset, every field.
const SNAPSHOT_FIELDS := {
	"pos_x": UnitField.POS_X,
	"pos_z": UnitField.POS_Z,
	"hp": UnitField.HP,
	"max_hp": UnitField.MAX_HP,
	"pa": UnitField.PA,
	"ma": UnitField.MA,
	"wp": UnitField.WP,
	"brave": UnitField.BRAVE,
	"faith": UnitField.FAITH,
	"speed": UnitField.SPEED,
	"move": UnitField.MOVE,
	"jump": UnitField.JUMP,
	"team": UnitField.TEAM,
	"state": UnitField.STATE,
	"target": UnitField.TARGET,
	"timer": UnitField.TIMER,
	"dest_x": UnitField.DEST_X,
	"dest_z": UnitField.DEST_Z,
	"flags": UnitField.FLAGS,
	"c_ev": UnitField.C_EV,
	"s_ev": UnitField.S_EV,
	"w_ev": UnitField.W_EV,
	"reaction_timer": UnitField.REACTION_TIMER,
	"weapon_range": UnitField.WEAPON_RANGE,
	"weapon_flags": UnitField.WEAPON_FLAGS,
	"height": UnitField.HEIGHT,
	"pending_damage": UnitField.PENDING_DAMAGE,
	"proposed_x": UnitField.PROPOSED_X,
	"proposed_z": UnitField.PROPOSED_Z,
	"damage_target": UnitField.DAMAGE_TARGET,
	"damage_amount": UnitField.DAMAGE_AMOUNT,
	"dbg_conflict_blocked": UnitField.DBG_CONFLICT_BLOCKED,
	"dbg_conflict_blocker": UnitField.DBG_CONFLICT_BLOCKER,
	"dbg_proposed_accepted": UnitField.DBG_PROPOSED_ACCEPTED,
	"dbg_state_reason": UnitField.DBG_STATE_REASON,
	"dbg_path_traverse": UnitField.DBG_PATH_TRAVERSE,
	"dbg_path_jump": UnitField.DBG_PATH_JUMP,
	"dbg_path_unocc": UnitField.DBG_PATH_UNOCC,
	"dbg_path_dist": UnitField.DBG_PATH_DIST,
	"dbg_best_dist": UnitField.DBG_BEST_DIST,
	"dbg_next_x": UnitField.DBG_NEXT_X,
	"dbg_next_z": UnitField.DBG_NEXT_Z,
	"anim_id": UnitField.ANIM_ID,
	"anim_frame": UnitField.ANIM_FRAME,
	"damage_frame": UnitField.DAMAGE_FRAME,
	"total_frames": UnitField.TOTAL_FRAMES,
	"anim_flags": UnitField.ANIM_FLAGS,
	"weapon_type": UnitField.WEAPON_TYPE,
	"mp": UnitField.MP,
	"max_mp": UnitField.MAX_MP,
	"casting_ability_id": UnitField.CASTING_ABILITY_ID,
	"cast_target": UnitField.CAST_TARGET,
	"cast_timer": UnitField.CAST_TIMER,
	"ability_flags": UnitField.ABILITY_FLAGS,
	"status_flags_lo": UnitField.STATUS_FLAGS_LO,
	"status_flags_hi": UnitField.STATUS_FLAGS_HI,
	"status_timer_0": UnitField.STATUS_TIMER_0,
	"status_timer_1": UnitField.STATUS_TIMER_1,
	"status_timer_2": UnitField.STATUS_TIMER_2,
	"status_timer_3": UnitField.STATUS_TIMER_3,
	"status_timer_4": UnitField.STATUS_TIMER_4,
	"status_timer_5": UnitField.STATUS_TIMER_5,
	"status_timer_6": UnitField.STATUS_TIMER_6,
	"status_timer_7": UnitField.STATUS_TIMER_7,
	"current_gambit": UnitField.CURRENT_GAMBIT,
	"gambit_cooldown": UnitField.GAMBIT_COOLDOWN,
	"reaction_ability": UnitField.REACTION_ABILITY,
	"support_ability": UnitField.SUPPORT_ABILITY,
	"movement_ability": UnitField.MOVEMENT_ABILITY,
	"projectile_frame": UnitField.PROJECTILE_FRAME,
	"pending_heal_target": UnitField.PENDING_HEAL_TARGET,
	"pending_heal_amount": UnitField.PENDING_HEAL_AMOUNT,
	"aoe_center_x": UnitField.AOE_CENTER_X,
	"aoe_center_z": UnitField.AOE_CENTER_Z,
	"aoe_ability_id": UnitField.AOE_ABILITY_ID,
	"s_ev_mag": UnitField.S_EV_MAG,
	"evade_type": UnitField.EVADE_TYPE,
	"decision_hist_0": UnitField.DECISION_HIST_0,
	"decision_hist_1": UnitField.DECISION_HIST_1,
	"decision_hist_2": UnitField.DECISION_HIST_2,
	"decision_meta": UnitField.DECISION_META,
	"prev_move_pos": UnitField.PREV_MOVE_POS,
	"move_total_ticks": UnitField.MOVE_TOTAL_TICKS,
	"move_step_id": UnitField.MOVE_STEP_ID,
	"pending_action_type": UnitField.PENDING_ACTION_TYPE,
	"cast_step_id": UnitField.CAST_STEP_ID,
	"paused": UnitField.PAUSED,
	"aoe_pending_caster": UnitField.AOE_PENDING_CASTER,
	"aoe_pending_fire_frame": UnitField.AOE_PENDING_FIRE_FRAME,
	"weapon_inflict_mask": UnitField.WEAPON_INFLICT_MASK,
	"weapon_inflict_mode": UnitField.WEAPON_INFLICT_MODE,
	"element_absorb_mask": UnitField.ELEMENT_ABSORB_MASK,
	"element_cancel_mask": UnitField.ELEMENT_CANCEL_MASK,
	"element_half_mask": UnitField.ELEMENT_HALF_MASK,
	"element_weak_mask": UnitField.ELEMENT_WEAK_MASK,
	"weapon_element": UnitField.WEAPON_ELEMENT,
	"strengthen_mask": UnitField.STRENGTHEN_MASK,
	"cinematic_timer": UnitField.CINEMATIC_TIMER,
	"level": UnitField.LEVEL,
	"dest_level": UnitField.DEST_LEVEL,
	"proposed_level": UnitField.PROPOSED_LEVEL,
	"turn_meter": UnitField.TURN_METER,
	"attack_period_factor_q8": UnitField.ATTACK_PERIOD_FACTOR_Q8,
	"attack_recovery": UnitField.ATTACK_RECOVERY,
}

# BATTLE_STATE_FIELDS: snake_case key -> BattleHeaderField offset, every field.
const BATTLE_STATE_FIELDS := {
	"tick": BattleHeaderField.TICK,
	"result": BattleHeaderField.RESULT,
	"flags": BattleHeaderField.FLAGS,
	"seed": BattleHeaderField.SEED,
}

# === END GENERATED ===


# === Hot-path snapshot union (W1 / ADR-0018) ==================================
# The subset of SNAPSHOT_FIELDS that the PER-FRAME combat path actually reads.
#
# `get_battle_unit_states()` builds a string-keyed Dictionary per unit for all
# 101 fields above, every ticking frame, for dead units and empty roster slots
# too — measured at ~1.8 ms/frame and, uniquely, it never decays as units die
# (docs/GPU-ARENA-PERF.md, F22/W1). The hot path wants 39 of those 101, so
# `get_battle_unit_states_hot()` builds only these and the frame pays about a
# third.
#
# ⚠ THIS LIST IS LOAD-BEARING AND ITS FAILURE MODE IS SILENT. A consumer that
# reads a field missing from here gets `state.get("x", default)` — the *default*,
# quietly, with no error. Two things defend it, and both must stay wired:
#
#   1. tools/check_snapshot_union.py — walks the call graph out of
#      CombatLoop._check_state_changes() / _handle_revives() and asserts every
#      field any hot-path consumer reads appears below. Runs in the pre-flight.
#   2. tests/GPUSnapshotUnionTest.tscn — replays a seeded battle with every
#      NON-union field poisoned, and fails if the simulation diverges. That is
#      the runtime proof that nothing outside this list is read.
#
# Provenance: round 21 of the perf investigation. Round 20 sized it at 15 fields
# by grepping the two files the snapshot is handed to by name; walking the call
# graph instead found five consumers — CombatLoop's own `_apply_*` pump (24
# fields), ProjectileManager (7) and CinematicDebugProbe (8) also receive it, as
# a parameter rather than by fetching it. Do not re-derive this by grepping
# `get_all_unit_states`; that finds the fetch sites, not the consumers — and do
# not re-derive it by hand at all. Run check_snapshot_union.py.
#
# Cold callers (the 82 in tests/, `_log_initial_state`, `refresh_all_states_now`
# for the rare cinematic edge) keep the full 101-field `get_battle_unit_states()`
# — it is unchanged and still available. Only the two per-frame callers moved.
# A plain Array literal, not PackedStringArray(...): a constructor call is not a
# constant expression, so `const x := PackedStringArray([...])` fails to fold and
# every cross-class reader dies with "Could not resolve external class member".
const SNAPSHOT_HOT_UNION := [
	# GPUCombatInterpreter.interpret() — the per-unit detection pass
	"anim_flags", "cast_step_id", "cast_target", "casting_ability_id",
	"flags", "hp", "mp", "pos_x", "pos_z", "state",
	# GPUVisualBridge — update_visual_positions / update_facing_toward_target
	"dbg_conflict_blocked", "level", "move_total_ticks", "target", "timer",
	# GPUMovementInterpreter.classify() — the bridge passes the snapshot ONE HOP
	# further out than the guard's receiver list reached, so these two were the
	# fifth miss and the only one a player could see. `prev_move_pos` defaulting
	# to -1 fails `from_packed >= 0`, so classify() returned NO_MOVE for every
	# unit on every frame: no visualizer was ever built, `_follow_visualizer`
	# never ran, and the bridge snapped each unit to its destination tile the
	# frame the GPU wrote it. Battles rendered as tile-to-tile teleports with no
	# walk animation and no facing-from-movement. Measured on seed
	# 3601067600983631927: 1607 combat frames, 0 with a live visualizer, 89
	# position deltas of which 0 were interpolated and the largest was 4.0 world
	# units. See tests/GPUVisualBridgeInterpolationTest.tscn.
	"prev_move_pos", "move_step_id",
	# CombatLoop's own _apply_* pump (_apply_combat_event -> 8 handlers)
	"anim_frame", "cast_timer", "damage_amount", "damage_frame",
	"damage_target", "decision_meta", "pending_heal_amount",
	"pending_heal_target", "projectile_frame", "team", "total_frames",
	"weapon_type",
	# _process_thrash_detection's decoded decision ring. Digit-suffixed, which is
	# how they escaped the round-21 hand census — its regex read `[a-z_]+` and the
	# names end in a number. check_snapshot_union.py caught all three on its first
	# run; that is the whole argument for the guard existing.
	"decision_hist_0", "decision_hist_1", "decision_hist_2",
	# ProjectileManager — spawn_from_gpu / update
	# (all of its 7 are already listed above)
	# CinematicDebugProbe — probe / on_cinematic_began / on_cinematic_ended
	"aoe_pending_caster", "aoe_pending_fire_frame", "cinematic_timer", "paused",
	# GPUCombatInterpreter.STAT_FIELDS — break detection, read through a COMPUTED
	# key (`state.get(sf[0], 0)`), so no grep for a quoted field name can see them
	# and neither could the round-21 census. Leaving them out did not read a wrong
	# number, it read the DEFAULT: every unit PA/MA/Speed/WP fell to 0 on tick
	# 1 and _sync_stat_to_unit wrote that into unit_stats. Caught by
	# tests/GPUSnapshotUnionTest.tscn on its first green run; check_snapshot_union.py
	# now refuses any computed-key read it has not been told how to resolve.
	"pa", "ma", "speed", "wp", "s_ev",
]


# === Unit encode schema (ADR-0003) ===
# The single source of truth for the config-derived fields of a unit record:
# how a live Unit (and a hand-built test config) lands in the combat buffer
# layout. ONE row per field; both the producer (_extract_unit_config) and the
# consumer (_write_unit_data) loop this list, so a field's key / offset /
# default exist in exactly one place and cannot drift apart — the input-side
# analogue of the generated SNAPSHOT_FIELDS on the output side.
#
# Each row:
#   "key"     unit_config string key (what callers pass / tests build)
#   "field"   UnitField offset it writes to (must be unique across rows)
#   "default" value used when the key is absent (test path, or a dormant field)
#   "extract" Callable(ctx) -> value pulling it off a real Unit, or omitted
#             when production doesn't supply it (ctx is built in
#             _extract_unit_config: unit/prog/cell/placed/height/evade/evade_mag/
#             packed_flags/weapon_type — accessed with bracket syntax, since
#             GDScript dicts don't take dot access)
#   "live"    true if the production path is EXPECTED to supply this today; a
#             live field with no producer is a mistake the schema check flags
#   "gap"     present on a live field that is KNOWINGLY unwired — turns the
#             schema-check error into a loud warning instead (see ADR-0003)
#   "behave"  what `overlay_unit_config` does with this field when a LIVE unit
#             is reconfigured mid-battle (ADR-0235). One of BEHAVE_RECOMPUTE
#             (rebuild from the new config), BEHAVE_CLAMP (keep the live value,
#             clamp it to the recomputed ceiling named by "clamp_to") or
#             BEHAVE_CARRY (leave the live value alone). REQUIRED on every row —
#             a row without one is a boot error, which is what makes a
#             newly-added field decide rather than default into a silent reset.
#   "clamp_to" UnitField offset holding the ceiling a BEHAVE_CLAMP row clamps to.
#             Required on clamp rows, rejected on the others.
#
# Scope is config-derived simple fields only. Init constants (STATE=0, the
# DBG_* block) and the status-timer bit-packer stay hand-written in
# _write_unit_data — they have no producer to drift against.
# FFT reaction-ability id -> shader REACT_* enum (combat_common.glslinc
# :211-218). Only the 7 reactions the shader actually resolves are mapped;
# every other reaction ability falls through to REACT_NONE (-1) and stays
# inert, exactly as before wiring. REACT_* are not generated into GPUConstants,
# so these mirror the shader by hand — keep in sync if that enum changes.
const REACT_NONE := -1
const REACTION_ABILITY_TO_REACT := {
	442: 0,  # Counter      -> REACT_COUNTER
	453: 1,  # Hamedo       -> REACT_FIRST_STRIKE
	438: 2,  # AbsorbUsedMP -> REACT_ABSORB_MP
	441: 3,  # AutoPotion   -> REACT_AUTO_POTION
	451: 4,  # BladeGrasp   -> REACT_BLADE_GRASP
	452: 5,  # ArrowGuard   -> REACT_ARROW_GUARD
	445: 6,  # MPSwitch     -> REACT_MANA_SHIELD
}

# === Reconfigure behaviour (ADR-0235) ===
# `reconfigure` overlays a fresh config onto a unit that is ALREADY FIGHTING, so
# each config-derived field has to say what happens to the value already in the
# buffer. Schema membership is the classification (ADR-0003 / #887): a field with
# a row is config-derived and answers here, a field without one is live state and
# is carried implicitly.
#
# THE FLOOR IS MECHANICAL, NOT EDITORIAL: any field the shader itself writes is
# live state, so it may not be BEHAVE_RECOMPUTE — `overlay_behaviour_problems()`
# derives that set from the shader source and errors on a violation. The three
# that only the shader-write scan surfaced were `wp`/`s_ev` (zeroed by Break
# Weapon / Break Shield, combat_combat.glslinc:254-256) and `pending_heal_*`.
const BEHAVE_RECOMPUTE := "recompute"
const BEHAVE_CLAMP := "clamp"
const BEHAVE_CARRY := "carry"
const BEHAVIOURS := [BEHAVE_RECOMPUTE, BEHAVE_CLAMP, BEHAVE_CARRY]

static var UNIT_CONFIG_SCHEMA: Array = [
	# Position — DEST/PROPOSED alias pos_x/pos_z (same key, no own extractor).
	#
	# 🔴 `cell` IS A `Vector3i` AND ITS `.z` IS THE LEVEL, not a world Z and not a
	# height (ADR-0219 dec. 1). This schema packed `.x` and `.y` and dropped `.z`,
	# which is the loss site ADR-0224 names: the retired `ScenarioPlacementSource` seated an
	# enemy at `(x, z, 1)` from ENTD's `upper_level`, `height` below is read with
	# the FULL cell so it is the level-1 height, and the shader then answered
	# `get_tile_height(x, z)` — the level-0 height for the same column. The two
	# disagreed by up to 15 on the twelve reachable slots ADR-0224 measures.
	#
	# `pos_level` is one new extractor and two aliases, the same shape the X/Z
	# pairs already have (ADR-0224 dec. 4). An unplaced unit defaults to the
	# ground, matching `pos_x`/`pos_z`'s `0`.
	{"key": "pos_x", "field": UnitField.POS_X, "behave": BEHAVE_CARRY, "default": 0, "live": true, "extract": func(c): return c["cell"].x if c["placed"] else 0},
	{"key": "pos_z", "field": UnitField.POS_Z, "behave": BEHAVE_CARRY, "default": 0, "live": true, "extract": func(c): return c["cell"].y if c["placed"] else 0},
	{"key": "pos_level", "field": UnitField.LEVEL, "behave": BEHAVE_CARRY, "default": 0, "live": true, "extract": func(c): return c["cell"].z if c["placed"] else 0},
	{"key": "pos_x", "field": UnitField.DEST_X, "behave": BEHAVE_CARRY, "default": 0, "live": true},
	{"key": "pos_z", "field": UnitField.DEST_Z, "behave": BEHAVE_CARRY, "default": 0, "live": true},
	{"key": "pos_level", "field": UnitField.DEST_LEVEL, "behave": BEHAVE_CARRY, "default": 0, "live": true},
	{"key": "pos_x", "field": UnitField.PROPOSED_X, "behave": BEHAVE_CARRY, "default": 0, "live": true},
	{"key": "pos_z", "field": UnitField.PROPOSED_Z, "behave": BEHAVE_CARRY, "default": 0, "live": true},
	{"key": "pos_level", "field": UnitField.PROPOSED_LEVEL, "behave": BEHAVE_CARRY, "default": 0, "live": true},
	# Core stats.
	{"key": "hp", "field": UnitField.HP, "behave": BEHAVE_CLAMP, "clamp_to": UnitField.MAX_HP, "default": 100, "live": true, "extract": func(c): return c["unit"].unit_stats.current_hp},
	{"key": "max_hp", "field": UnitField.MAX_HP, "behave": BEHAVE_RECOMPUTE, "default": 100, "live": true, "extract": func(c): return c["unit"].unit_stats.max_hp},
	{"key": "pa", "field": UnitField.PA, "behave": BEHAVE_RECOMPUTE, "default": 10, "live": true, "extract": func(c): return c["unit"].unit_stats.attack},
	{"key": "ma", "field": UnitField.MA, "behave": BEHAVE_RECOMPUTE, "default": 10, "live": true, "extract": func(c): return c["unit"].unit_stats.magic_attack},
	# THE LEVER LAYER'S WEAPON BAKE SITE (ADR-0277 dec. 2). There is no weapon
	# TABLE on the GPU — a weapon reaches the kernel flattened into these three
	# unit fields — so the item quantities are levered in the extract, which
	# means each one inherits its row's ADR-0235 reconfigure behaviour. `wp`
	# CARRIES and the other two RECOMPUTE, so a lever set that changed under a
	# unit already fighting would leave it half-levered; that is why the reload
	# affordance refuses while a battle is live (ADR-0277 dec. 11).
	#
	# ⚠️ A LEVERED `wp` IS NO LONGER THE ITEM'S `wp`. Anything reading a unit's
	# stats for display, or diffing against the oracle, sees the levered number.
	# The word for that is `levered` (ADR-0277 dec. 1) and it is in the glossary.
	{"key": "wp", "field": UnitField.WP, "behave": BEHAVE_CARRY, "default": 1, "live": true, "extract": func(c): return c["levers"].levered_item("wp", c["weapon_id"], c["prog"].get_weapon_power()) if c["prog"] else 1},
	{"key": "brave", "field": UnitField.BRAVE, "behave": BEHAVE_RECOMPUTE, "default": 50, "live": true, "extract": func(c): return c["prog"].brave if c["prog"] else 50},
	{"key": "faith", "field": UnitField.FAITH, "behave": BEHAVE_RECOMPUTE, "default": 50, "live": true, "extract": func(c): return c["prog"].faith if c["prog"] else 50},
	{"key": "speed", "field": UnitField.SPEED, "behave": BEHAVE_RECOMPUTE, "default": 100, "live": true, "extract": func(c): return c["unit"].unit_stats.atb_speed},
	{"key": "move", "field": UnitField.MOVE, "behave": BEHAVE_RECOMPUTE, "default": 4, "live": true, "extract": func(c): return c["unit"].move},
	{"key": "jump", "field": UnitField.JUMP, "behave": BEHAVE_RECOMPUTE, "default": 3, "live": true, "extract": func(c): return c["unit"].jump},
	{"key": "mp", "field": UnitField.MP, "behave": BEHAVE_CLAMP, "clamp_to": UnitField.MAX_MP, "default": 50, "live": true, "extract": func(c): return c["unit"].unit_stats.current_mp},
	{"key": "max_mp", "field": UnitField.MAX_MP, "behave": BEHAVE_RECOMPUTE, "default": 50, "live": true, "extract": func(c): return c["unit"].unit_stats.max_mp},
	# Evasion (computed once into ctx.evade / ctx.evade_mag).
	{"key": "c_ev", "field": UnitField.C_EV, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["evade"]["c_ev"]},
	{"key": "s_ev", "field": UnitField.S_EV, "behave": BEHAVE_CARRY, "default": 0, "live": true, "extract": func(c): return c["evade"]["s_ev"]},
	{"key": "w_ev", "field": UnitField.W_EV, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["levers"].levered_item("w_ev", c["weapon_id"], c["evade"]["w_ev"])},
	{"key": "s_ev_mag", "field": UnitField.S_EV_MAG, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["evade_mag"]["s_ev"]},
	# Weapon / terrain.
	{"key": "weapon_range", "field": UnitField.WEAPON_RANGE, "behave": BEHAVE_RECOMPUTE, "default": 1, "live": true, "extract": func(c): return c["levers"].levered_item("weapon_range", c["weapon_id"], c["prog"].get_weapon_range()) if c["prog"] else 1},
	{"key": "weapon_flags", "field": UnitField.WEAPON_FLAGS, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["packed_flags"]},
	{"key": "weapon_type", "field": UnitField.WEAPON_TYPE, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["weapon_type"]},
	# THE ATTACK-PERIOD BAKE SITE (#1107). A FACTOR, not a value — the only one of
	# the six item quantities that crosses this way, because its ROM base is a SEQ
	# length the kernel holds and this side does not. See LeverSet.QUANTITIES.
	# RECOMPUTE like its two neighbours: a reconfigure re-derives it, so a unit
	# that changes weapon mid-battle gets the new weapon's factor.
	# `default: 256` is the identity and is what every test config that does not
	# mention the key receives.
	{"key": "attack_period_factor_q8", "field": UnitField.ATTACK_PERIOD_FACTOR_Q8, "behave": BEHAVE_RECOMPUTE, "default": 256, "live": true, "extract": func(c): return c["levers"].item_factor_q8("attack_period", c["weapon_id"])},
	# Per-swing scratch the kernel owns: `setup_attack_animation` writes it, the
	# IDLE edge spends it. Initialised here only because the layout guard requires
	# every offset in [0, UNIT_SIZE) to be written (ADR-0003).
	#
	# 🔴 CARRY, AND THE GUARD IS WHY. Written RECOMPUTE first, and
	# `GPUBatchSimulator`'s schema check refused it: *"'attack_recovery' is
	# 'recompute', but the shader WRITES it — a live field must be 'carry' or
	# 'clamp' or reconfigure silently resets it"*. It is right, and the case is
	# real: a turn is an opportunity to RECONFIGURE a unit (ADR-0260) and a unit
	# mid-swing still gets one (ADR-0236's design S3), so a RECOMPUTE here would
	# hand back a re-packed 0 and the recovery a levered weapon had just been
	# charged would evaporate at the one moment it mattered most.
	{"key": "attack_recovery", "field": UnitField.ATTACK_RECOVERY, "behave": BEHAVE_CARRY, "default": 0, "live": false},
	{"key": "height", "field": UnitField.HEIGHT, "behave": BEHAVE_CARRY, "default": 0, "live": true, "extract": func(c): return c["height"]},
	# Equipped reaction -> shader REACT_* enum via REACTION_ABILITY_TO_REACT.
	# Only the 7 shader-resolved reactions map; every other equipped reaction
	# falls through to REACT_NONE (-1) and stays inert (ADR-0003 gap closed).
	{"key": "reaction_ability", "field": UnitField.REACTION_ABILITY, "behave": BEHAVE_RECOMPUTE, "default": -1, "live": true, "extract": func(c): return REACTION_ABILITY_TO_REACT.get(c["prog"].equipped_reaction, REACT_NONE) if c["prog"] else REACT_NONE},
	# Dormant: shader can read these but there is no in-game source yet —
	# no support/movement-ability extraction, and status has neither an
	# ability->infliction path nor a pre-combat seed. Flip live=true + add an
	# extractor when the feature lands; the test/pending-heal fields stay
	# test-only.
	{"key": "support_ability", "field": UnitField.SUPPORT_ABILITY, "behave": BEHAVE_RECOMPUTE, "default": -1, "live": false},
	{"key": "movement_ability", "field": UnitField.MOVEMENT_ABILITY, "behave": BEHAVE_RECOMPUTE, "default": -1, "live": false},
	{"key": "status_flags_lo", "field": UnitField.STATUS_FLAGS_LO, "behave": BEHAVE_CARRY, "default": 0, "live": false},
	{"key": "status_flags_hi", "field": UnitField.STATUS_FLAGS_HI, "behave": BEHAVE_CARRY, "default": 0, "live": false},
	# Issue #98 -- equipped weapon's on-hit inflict mask + mode. Encoded by
	# _extract_unit_config from the right-hand item's items.json `weapon`
	# block via StatusEncoder. Zero / MODE_NONE for unarmed or for weapons
	# without inflict_statuses.
	{"key": "weapon_inflict_mask", "field": UnitField.WEAPON_INFLICT_MASK, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["weapon_inflict_mask"]},
	{"key": "weapon_inflict_mode", "field": UnitField.WEAPON_INFLICT_MODE, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["weapon_inflict_mode"]},
	# Issue #110 -- per-unit element-defense masks composed across every
	# equipped slot via ElementEncoder.defense_for_equipment. Zero on every
	# slot if the unit carries no element-defense entries (the majority).
	{"key": "element_absorb_mask", "field": UnitField.ELEMENT_ABSORB_MASK, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["element_absorb_mask"]},
	{"key": "element_cancel_mask", "field": UnitField.ELEMENT_CANCEL_MASK, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["element_cancel_mask"]},
	{"key": "element_half_mask", "field": UnitField.ELEMENT_HALF_MASK, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["element_half_mask"]},
	{"key": "element_weak_mask", "field": UnitField.ELEMENT_WEAK_MASK, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["element_weak_mask"]},
	# Issue #116 -- equipped right-hand weapon's element_id (1..8 per
	# ElementEncoder.ELEMENT_MAP) or 0 for non-elemental / unarmed.
	# Translated at the encode boundary from items.json weapon.elements; the
	# field-list is collapsed to a single element_id since a basic attack
	# carries one weapon's element. Consumed by apply_weapon_element_defense.
	{"key": "weapon_element", "field": UnitField.WEAPON_ELEMENT, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["weapon_element"]},
	# Issue #117 -- attacker-side BoostElem (Strengthen-Elem) OR-fold across
	# every equipped item's `strengthen_elements` byte (items.json). Composed
	# at the encode boundary by ElementEncoder.strengthen_for_equipment. Tested
	# at every damage-queue site by apply_strengthen_elem (1.25x AbPower when
	# the mask overlaps the spell/weapon element). Zero for the vast majority
	# of units (only 8 items in stock data carry strengthen).
	{"key": "strengthen_mask", "field": UnitField.STRENGTHEN_MASK, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": true, "extract": func(c): return c["strengthen_mask"]},
	{"key": "ability_flags", "field": UnitField.ABILITY_FLAGS, "behave": BEHAVE_RECOMPUTE, "default": 0, "live": false},
	{"key": "pending_heal_target", "field": UnitField.PENDING_HEAL_TARGET, "behave": BEHAVE_CARRY, "default": -1, "live": false},
	{"key": "pending_heal_amount", "field": UnitField.PENDING_HEAL_AMOUNT, "behave": BEHAVE_CARRY, "default": 0, "live": false},
]


static func unit_config_schema_problems() -> Dictionary:
	"""Validate UNIT_CONFIG_SCHEMA. Returns {errors, warnings} as PackedStringArrays.

	errors   — a real mistake: a duplicate offset, or a live field with no
	           producer and no `gap` note (someone added a field and forgot the
	           extractor). Pure, no GPU; shared by the boot check and the test.
	warnings — knowingly-unwired live fields (rows carrying a `gap`).
	"""
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var producible := {}
	for row in UNIT_CONFIG_SCHEMA:
		if row.get("extract") != null:
			producible[row["key"]] = true
	var seen_fields := {}
	for row in UNIT_CONFIG_SCHEMA:
		var f: int = row["field"]
		if seen_fields.has(f):
			errors.append("UNIT_CONFIG_SCHEMA: duplicate offset %d (key '%s')" % [f, row["key"]])
		seen_fields[f] = true
		# ADR-0235 — every row declares what `overlay_unit_config` does with it.
		# REQUIRED, not defaulted: a new config-derived field that forgot to answer
		# would silently reset itself on the player's first job change, and the
		# whole point of the column is that such a field cannot ship unnoticed.
		var behave = row.get("behave")
		if behave == null:
			errors.append("UNIT_CONFIG_SCHEMA: row '%s' (offset %d) has no 'behave' (one of %s)" % [row["key"], f, str(BEHAVIOURS)])
		elif not BEHAVIOURS.has(behave):
			errors.append("UNIT_CONFIG_SCHEMA: row '%s' (offset %d) has behave '%s'; expected one of %s" % [row["key"], f, str(behave), str(BEHAVIOURS)])
		elif behave == BEHAVE_CLAMP and not row.has("clamp_to"):
			errors.append("UNIT_CONFIG_SCHEMA: row '%s' (offset %d) is '%s' but names no 'clamp_to' ceiling" % [row["key"], f, BEHAVE_CLAMP])
		if row.has("clamp_to") and behave != BEHAVE_CLAMP:
			errors.append("UNIT_CONFIG_SCHEMA: row '%s' (offset %d) names a 'clamp_to' but is '%s', not '%s'" % [row["key"], f, str(behave), BEHAVE_CLAMP])
		if row.get("live", false) and not producible.has(row["key"]):
			if row.has("gap"):
				warnings.append("unit encode gap: '%s' is live but unextracted — %s" % [row["key"], row["gap"]])
			else:
				errors.append("unit encode: live field '%s' has no extractor (add one, or set live=false if dormant)" % row["key"])
	return {"errors": errors, "warnings": warnings}


# Where the combat kernel lives, for the shader-write scan below. One directory,
# globbed rather than listed: a new stage file must be scanned the day it lands.
const SHADER_DIR := "res://src/gpu/shaders"


static func shader_written_unit_fields() -> Dictionary:
	"""Every U_* field the SHADER itself writes, as {UnitField offset: "U_NAME"}.

	Derived by scanning `write_unit(battle_id, unit, U_X, ...)` call sites in the
	kernel source — the same single-source-of-truth move ADR-0003 made for the
	encode side, applied to the question "is this field live state?". A parallel
	hand-list would be a second drift surface, and the three rows this scan
	corrected (`wp`, `s_ev`, `pending_heal_*`) are exactly what a hand-audit had
	already missed.

	Returns {} only when the scan is broken, never as "the shader writes nothing";
	`overlay_behaviour_problems()` treats an empty scan as an error so the guard
	cannot go inert (an unreadable shader dir would otherwise read as clean)."""
	var written := {}
	var dir := DirAccess.open(SHADER_DIR)
	if dir == null:
		return written
	var by_name := {}
	for k in UnitField.keys():
		by_name["U_" + k] = UnitField[k]
	var rx := RegEx.new()
	rx.compile("write_unit\\s*\\([^,]+,[^,]+,\\s*(U_[A-Z0-9_]+)")
	for file_name in dir.get_files():
		if not (file_name.ends_with(".glsl") or file_name.ends_with(".glslinc")):
			continue
		var text := FileAccess.get_file_as_string(SHADER_DIR + "/" + file_name)
		for m in rx.search_all(text):
			var u_name := m.get_string(1)
			if by_name.has(u_name):
				written[by_name[u_name]] = u_name
	return written


static func overlay_behaviour_problems() -> Dictionary:
	"""Assert no SHADER-WRITTEN field is classified BEHAVE_RECOMPUTE (ADR-0235).

	A field the kernel writes during a battle is live state by definition; blindly
	recomputing it from config throws that state away, which is the exact
	failure #887 names ("my unit lost its cooldowns when I swapped a hat"), only
	silent. BEHAVE_CARRY and BEHAVE_CLAMP both keep the live value, so the rule is
	one-sided: shader-written implies NOT recompute.

	This does NOT rule the other direction — a field the shader never writes may
	still be BEHAVE_CARRY (`height` is: its extractor reads the CPU-side cell,
	which is stale the moment the unit moves)."""
	var errors := PackedStringArray()
	var written := shader_written_unit_fields()
	if written.is_empty():
		errors.append("shader-write scan found no write_unit() sites under %s — the guard is inert, not clean" % SHADER_DIR)
		return {"errors": errors, "warnings": PackedStringArray()}
	for row in UNIT_CONFIG_SCHEMA:
		var f: int = row["field"]
		if written.has(f) and row.get("behave") == BEHAVE_RECOMPUTE:
			errors.append(("UNIT_CONFIG_SCHEMA: '%s' (offset %d, %s) is '%s', but the shader WRITES it — "
				+ "a live field must be '%s' or '%s' or reconfigure silently resets it") % [
					row["key"], f, written[f], BEHAVE_RECOMPUTE, BEHAVE_CARRY, BEHAVE_CLAMP])
	return {"errors": errors, "warnings": PackedStringArray()}


static func overlay_unit_config(data: PackedInt32Array, offset: int, unit_config: Dictionary) -> void:
	"""Overlay a fresh config onto a unit block that is ALREADY FIGHTING (ADR-0235).

	The counterpart of `_write_unit_data`, and deliberately NOT a call to it:
	that one writes the whole 102-int block, resetting all 57 live-state fields to
	their init constants. Correct out of combat, where nothing is live; mid-battle
	it drops the unit's cast, animation, status timers and cooldowns.

	Only rows classified BEHAVE_RECOMPUTE are written. BEHAVE_CLAMP keeps the live
	value and clamps it to the freshly-recomputed ceiling (§4: clamp to the new
	max, NEVER scale — scaling makes toggling a +HP item a free heal). BEHAVE_CARRY
	rows, and all 57 offsets with no schema row at all, are not touched.

	The two passes are ordered, not stylistic: the clamp pass reads `max_hp` /
	`max_mp` out of the block, so the recompute pass has to have put the NEW
	ceilings there first."""
	for row in UNIT_CONFIG_SCHEMA:
		if row["behave"] == BEHAVE_RECOMPUTE:
			data[offset + row["field"]] = unit_config.get(row["key"], row["default"])
	for row in UNIT_CONFIG_SCHEMA:
		if row["behave"] == BEHAVE_CLAMP:
			var f: int = offset + row["field"]
			data[f] = mini(data[f], data[offset + row["clamp_to"]])


# Sentinels for the coverage probe — two distinct values, both outside every
# value _write_unit_data can legitimately write (defaults are small ints, 0, -1,
# or packed status timers). An offset counts as written only if it moved away
# from BOTH fills, so the check can't be fooled by a write that happens to store
# a sentinel's own value.
const _COVERAGE_SENTINEL_A := 0x5EEDFACE
const _COVERAGE_SENTINEL_B := 0x0DDBA11


static func unit_buffer_coverage_problems() -> Dictionary:
	"""Assert _write_unit_data touches every offset in [0, UNIT_SIZE) (ADR-0003).

	The unit buffer is fully dense: config-derived fields land via the
	UNIT_CONFIG_SCHEMA loop, everything else (init constants, the DBG_* block, the
	status-timer packer, reserved slots) via hand-written writes. A newly-added
	UnitField — regen puts it in the enum and in SNAPSHOT_FIELDS, so the *decode*
	side always sees it — that nobody wrote on the *encode* side would read back a
	silent zero. This net turns that into a boot error, the unit analogue of
	gambit_config_schema_problems()' completeness assertion.

	Verified dynamically (sentinel-fill a probe buffer, write, check nothing keeps
	the sentinel) rather than against a declared offset list: the init writes are
	scattered imperative assignments, so a parallel list would be a *new* drift
	surface — the opposite of the guarantee we want (see ADR-0003). Pure: a
	UNIT_SIZE-int probe, no RenderingDevice, so the boot net and the round-trip
	test share it. Does NOT catch a config-derived field hand-written into the init
	block instead of a schema row (it is written, just off the single source of
	truth) — the same residual documented for the gambit schema."""
	var errors := PackedStringArray()
	var probe_a := PackedInt32Array()
	probe_a.resize(UNIT_SIZE)
	probe_a.fill(_COVERAGE_SENTINEL_A)
	_write_unit_data(probe_a, 0, {}, 0)
	var probe_b := PackedInt32Array()
	probe_b.resize(UNIT_SIZE)
	probe_b.fill(_COVERAGE_SENTINEL_B)
	_write_unit_data(probe_b, 0, {}, 0)
	var name_by_offset := {}
	for k in SNAPSHOT_FIELDS:
		name_by_offset[SNAPSHOT_FIELDS[k]] = k
	for f in range(UNIT_SIZE):
		if probe_a[f] == _COVERAGE_SENTINEL_A and probe_b[f] == _COVERAGE_SENTINEL_B:
			var key: String = name_by_offset.get(f, "unnamed")
			errors.append("unit layout: offset %d (%s) in [0, %d) is never written by _write_unit_data (add a UNIT_CONFIG_SCHEMA row or an init write)" % [f, key, UNIT_SIZE])
	return {"errors": errors, "warnings": PackedStringArray()}


# === Turn meter seeding (ADR-0236) ===
# The shader's PCG hash, mirrored in GDScript. `initial_turn_meter` is exactly
# `rand_int(battle, unit_index, tick=0, TURN_METER_FULL)` as the kernel would
# compute it (combat_common.glslinc `pcg_hash` / `rand_int`), so the battle has
# ONE definition of randomness rather than a second, unrelated CPU generator.
# Mirrored rather than dispatched because the initial meter has to exist before
# the first tick: the turn-queue forecast is asked for at deployment, and a GPU
# init pass would make it a post-dispatch value.
const _U32 := 0xFFFFFFFF


static func _pcg_hash(seed: int) -> int:
	"""32-bit PCG output hash. Mirrors combat_common.glslinc's `pcg_hash`;
	GDScript ints are 64-bit signed, so every step masks back to 32 bits and the
	shifts stay logical (the masked value is never negative)."""
	var state: int = (seed * 747796405 + 2891336453) & _U32
	var word: int = ((((state >> ((state >> 28) + 4)) ^ state) & _U32) * 277803737) & _U32
	return ((word >> 22) ^ word) & _U32


static func initial_turn_meter(battle_seed: int, unit_index: int) -> int:
	"""A unit's starting TURN METER, seeded from the battle (ADR-0236 dec. 4).

	Uniform in `[0, TURN_METER_FULL)` and a pure function of
	`(battle_seed, unit_index)`, so a battle replayed under the same seed opens
	the same turn order and a rollout fork inherits it. An all-zero start would
	lock every equal-Speed unit into lockstep, which is both the least
	interesting opening and the one that maximises simultaneous readiness."""
	return _pcg_hash((battle_seed + unit_index * 1000) & _U32) % TURN_METER_FULL


static func _write_unit_data(data: PackedInt32Array, offset: int, unit_config: Dictionary, team: int, turn_meter: int = 0) -> void:
	"""Write unit data to buffer array.

	Config-derived fields come from UNIT_CONFIG_SCHEMA (ADR-0003) — one loop
	over the single source of truth, no hand-typed key/offset pairs. The rest
	below stays hand-written by design: pure init constants have no producer to
	drift against, and the status-timer packer isn't a simple key->offset write.

	`turn_meter` is a parameter and not a config key for the same reason `team`
	is: it is a per-SLOT value the caller knows (`initial_turn_meter(seed, idx)`)
	and a live Unit cannot supply. A schema row would also be wrong on the other
	side -- the meter is live state the shader writes, so `reconfigure` must
	never recompute it (ADR-0236 dec. 4).
	"""
	for row in UNIT_CONFIG_SCHEMA:
		data[offset + row["field"]] = unit_config.get(row["key"], row["default"])

	# --- Init constants (no config input) ---
	data[offset + UnitField.TEAM] = team
	data[offset + UnitField.TURN_METER] = turn_meter
	data[offset + UnitField.STATE] = 0  # IDLE
	data[offset + UnitField.TARGET] = -1
	data[offset + UnitField.TIMER] = 0
	data[offset + UnitField.FLAGS] = 0
	data[offset + UnitField.REACTION_TIMER] = 0
	data[offset + UnitField.PENDING_DAMAGE] = 0
	data[offset + UnitField.DAMAGE_TARGET] = -1
	data[offset + UnitField.DAMAGE_AMOUNT] = 0
	# Debug fields (initialized to 0)
	data[offset + UnitField.DBG_CONFLICT_BLOCKED] = 0
	data[offset + UnitField.DBG_CONFLICT_BLOCKER] = -1
	data[offset + UnitField.DBG_PROPOSED_ACCEPTED] = 0
	data[offset + UnitField.DBG_STATE_REASON] = 0
	data[offset + UnitField.DBG_PATH_TRAVERSE] = 0
	data[offset + UnitField.DBG_PATH_JUMP] = 0
	data[offset + UnitField.DBG_PATH_UNOCC] = 0
	data[offset + UnitField.DBG_PATH_DIST] = 0
	data[offset + UnitField.DBG_BEST_DIST] = 0
	data[offset + UnitField.DBG_NEXT_X] = 0
	data[offset + UnitField.DBG_NEXT_Z] = 0
	# Animation fields (initialized to defaults)
	data[offset + UnitField.ANIM_ID] = 0
	data[offset + UnitField.ANIM_FRAME] = 0
	data[offset + UnitField.DAMAGE_FRAME] = 0
	data[offset + UnitField.TOTAL_FRAMES] = 0
	data[offset + UnitField.ANIM_FLAGS] = 0

	# Spell/Ability state (Phase 1 expansion)
	data[offset + UnitField.CASTING_ABILITY_ID] = -1
	data[offset + UnitField.CAST_TARGET] = -1
	data[offset + UnitField.CAST_TIMER] = 0

	# Status countdowns — SIXTEEN 16-bit counters across the eight STATUS_TIMER
	# ints, addressed by the status's own slot (#1116, `StatusRegistry.TIMER_SLOT`):
	# slot s sits in int s >> 1, low half for even s and high half for odd.
	#
	# 🔴 THE OLD SHAPE WAS A FIRST-COME POOL OF (bit << 24) | ticks PAIRS, AND A
	# PRE-PACKED INT IN A CONFIG IS STILL SPELLED THAT WAY. It cannot be
	# reinterpreted — bit 19 (haste) in the high byte reads as a 16-bit counter of
	# 0x1300-odd ticks in somebody else's slot — so the int form is refused loudly
	# rather than silently mis-seeded. `{bit, ticks}` is the supported shape and the
	# only one any caller in the tree uses.
	var cfg_timers = unit_config.get("status_timers", [])
	for i in range(8):
		data[offset + UnitField.STATUS_TIMER_0 + i] = 0
	for entry in cfg_timers:
		if not (entry is Dictionary):
			push_error("[GPUCombatPacker] status_timers entry %s is not {bit, ticks} — the pre-packed (bit << 24) | ticks form is the pre-#1116 pool layout and would seed the wrong slot" % str(entry))
			continue
		var bit: int = int(entry.get("bit", -1))
		var ticks: int = int(entry.get("ticks", 0))
		if ticks <= 0:
			continue
		var slot: int = StatusRegistry.timer_slot_for_bit(bit)
		if slot < 0:
			push_error("[GPUCombatPacker] status bit %d has no countdown slot — the ROM never times it, so a seeded duration for it would decay something that cannot decay in a battle (StatusRegistry.TIMER_SLOT)" % bit)
			continue
		var field: int = offset + UnitField.STATUS_TIMER_0 + (slot >> 1)
		var clamped: int = clampi(ticks, 0, 0xFFFF)
		if (slot & 1) == 0:
			data[field] = (data[field] & ~0xFFFF) | clamped
		else:
			data[field] = (data[field] & 0xFFFF) | (clamped << 16)

	# Gambit state
	data[offset + UnitField.CURRENT_GAMBIT] = -1
	data[offset + UnitField.GAMBIT_COOLDOWN] = 0

	# Projectile and AOE fields. (reaction/support/movement abilities,
	# pending_heal_*, and s_ev_mag are config-derived and written by the schema
	# loop above — see UNIT_CONFIG_SCHEMA / ADR-0003.)
	data[offset + UnitField.PROJECTILE_FRAME] = -1
	data[offset + UnitField.AOE_CENTER_X] = -1
	data[offset + UnitField.AOE_CENTER_Z] = -1
	data[offset + UnitField.AOE_ABILITY_ID] = -1
	# Remaining reserved fields
	for i in range(76, 80):
		data[offset + i] = 0
	data[offset + UnitField.DECISION_META] = 0
	data[offset + UnitField.PREV_MOVE_POS] = -1  # No previous move
	data[offset + UnitField.MOVE_TOTAL_TICKS] = 0
	data[offset + UnitField.MOVE_STEP_ID] = 0
	data[offset + UnitField.CAST_STEP_ID] = 0
	# No action pending — matches stage_compute's idle reset (ACTION_NONE = -1).
	# Without this the field zero-inits to 0 = ACTION_ATTACK; benign only because
	# stage_compute rewrites it each tick before apply_pending_action reads it.
	data[offset + UnitField.PENDING_ACTION_TYPE] = GPUConstants.ACTION_NONE
	# Cinematic-spell orchestrator (issue #53; per-caster timer in #118).
	# Dormant defaults: not paused (ref-count starts at 0), no AoE stamp,
	# no cinematic running for this unit (sentinel -1).
	data[offset + UnitField.PAUSED] = 0
	data[offset + UnitField.AOE_PENDING_CASTER] = -1
	data[offset + UnitField.AOE_PENDING_FIRE_FRAME] = -1
	data[offset + UnitField.CINEMATIC_TIMER] = -1


static func _extract_unit_config(unit: Unit, lattice: Lattice = null) -> Dictionary:
	"""Build a unit_config dict from a live Unit by walking UNIT_CONFIG_SCHEMA.

	Computes the shared extract context once (tile / prog / evasion / packed
	weapon flags / weapon type), then fills the dict from each row's `extract`
	closure. Key/offset/default live in the schema, so this producer can't
	disagree with the _write_unit_data consumer about which keys exist
	(ADR-0003).
	"""
	var prog = unit.unit_stats.get_progression()

	# Pack weapon flags into bits: striking=1, lunging=2, direct=4, arc=8
	var packed_flags = 0
	var weapon_type = 0  # 0 = unarmed
	# Issue #98 -- right-hand weapon's on-hit inflict mask + mode, translated
	# at the encode boundary by StatusEncoder. Zero / NONE for unarmed.
	var weapon_inflict_mask := 0
	var weapon_inflict_mode := StatusEncoder.MODE_NONE
	# Issue #110 -- per-unit element-defense masks composed across every
	# equipped slot via ElementEncoder. Zero on every slot for the majority
	# of units without element-defense gear.
	var element_defense := {"absorb_mask": 0, "cancel_mask": 0, "half_mask": 0, "weak_mask": 0}
	# Issue #116 -- right-hand weapon's element_id (1..8) or 0 for non-elemental.
	# A basic attack carries one weapon's element, so collapse the (always
	# single-entry) items.json `weapon.elements` list to one element_id at the
	# encode boundary; consumed by apply_weapon_element_defense.
	var weapon_element := 0
	# Issue #117 -- attacker-side Strengthen-Elem (BoostElem) OR-fold across
	# every equipped slot's `strengthen_elements`. Mirrors the SCUS aggregation
	# loop at ram:8005C788 that fills unit +0x71. Consumed by
	# apply_strengthen_elem at the damage-queue sites.
	var strengthen_mask := 0
	# THE LEVER LAYER'S RECORD TIER NEEDS THE ITEM ID, not just its type
	# (ADR-0277 dec. 5). Hoisted out of the `if prog:` block below so the
	# extract context can carry it; -1 is unarmed, which has no record and
	# therefore no lever.
	var weapon_id := -1
	if prog:
		var flags = prog.get_weapon_flags()
		if flags.get("striking", false):
			packed_flags |= 1
		if flags.get("lunging", false):
			packed_flags |= 2
		if flags.get("direct", false):
			packed_flags |= 4
		if flags.get("arc", false):
			packed_flags |= 8

		# Get weapon type for animation selection
		weapon_id = prog.equipment.get(prog.EquipSlot.RIGHT_HAND, -1)
		if weapon_id >= 0 and ItemDatabase.is_weapon(weapon_id):
			weapon_type = ItemDatabase.get_item_type_id(weapon_id)
			var infl = StatusEncoder.weapon_inflict_for_item(weapon_id)
			weapon_inflict_mask = infl["mask"]
			weapon_inflict_mode = infl["mode"]
			var w_elements = ItemDatabase.get_elements(weapon_id).get("weapon_elements", [])
			var w_mask = ElementEncoder.mask_from_names(w_elements)
			# Pick the lowest set bit -- weapons carry at most one element.
			for b in range(1, 9):
				if (w_mask & (1 << b)) != 0:
					weapon_element = b
					break

		element_defense = ElementEncoder.defense_for_equipment(prog.equipment)
		strengthen_mask = ElementEncoder.strengthen_for_equipment(prog.equipment)

		# Issue #111 — OR job-innate element defenses on top of the equipment
		# union (Bomb absorbs Fire, etc.). ProgressionTester.gd:1177-1180 is the
		# truth model this mirrors.
		var job := JobDatabase.get_job(prog.current_job_id)
		element_defense["absorb_mask"] |= ElementEncoder.mask_from_names(job.get("absorb_elements", []))
		element_defense["cancel_mask"] |= ElementEncoder.mask_from_names(job.get("cancel_elements", []))
		element_defense["half_mask"]   |= ElementEncoder.mask_from_names(job.get("half_elements",   []))
		element_defense["weak_mask"]   |= ElementEncoder.mask_from_names(job.get("weak_elements",   []))

	# Holder 4 is a `Vector2i` now (ADR-0166 dec. 3), so terrain `height` is no longer
	# reachable off the held object — it is asked of the port with the coordinate. A
	# null lattice keeps the schema's own default (0) rather than inventing one.
	var cell: Vector3i = unit.movement_component.current_cell
	var placed := cell != TerrainCell.NONE
	var height_cell: TerrainCell = lattice.terrain_at(cell) \
		if (lattice != null and placed) else null
	var ctx := {
		"unit": unit,
		"prog": prog,
		"cell": cell,
		"placed": placed,
		"height": height_cell.height if height_cell != null else 0,
		"evade": _get_evade_breakdown(prog, false),
		"evade_mag": _get_evade_breakdown(prog, true),
		"packed_flags": packed_flags,
		"weapon_type": weapon_type,
		# -1 unless the right hand holds an actual weapon: `wp` / `weapon_range`
		# / `w_ev` are read off the right hand and nothing else, so a non-weapon
		# there has no lever record (ADR-0277 dec. 8).
		"weapon_id": weapon_id if (weapon_id >= 0 and ItemDatabase.is_weapon(weapon_id)) else -1,
		"levers": LeverSet.shared(),
		"weapon_inflict_mask": weapon_inflict_mask,
		"weapon_inflict_mode": weapon_inflict_mode,
		"element_absorb_mask": element_defense["absorb_mask"],
		"element_cancel_mask": element_defense["cancel_mask"],
		"element_half_mask": element_defense["half_mask"],
		"element_weak_mask": element_defense["weak_mask"],
		"weapon_element": weapon_element,
		"strengthen_mask": strengthen_mask,
	}

	var cfg := {}
	for row in UNIT_CONFIG_SCHEMA:
		var ex = row.get("extract")
		if ex != null and not cfg.has(row["key"]):
			cfg[row["key"]] = ex.call(ctx)
	return cfg


static func _get_evade_breakdown(prog: UnitProgression, is_magic: bool) -> Dictionary:
	"""Read evasion stats from progression for GPU config."""
	var c_ev = 0
	var s_ev = 0
	var w_ev = 0
	if prog:
		c_ev = prog.get_c_evade()
		s_ev = prog.get_magic_evade() if is_magic else prog.get_physical_evade()
		if not is_magic:
			w_ev = prog.get_weapon_evade()
	return {"c_ev": c_ev, "s_ev": s_ev, "w_ev": w_ev, "total": mini(c_ev + s_ev + w_ev, 99)}


# Gambit buffer sizing (canonical values in GPUConstants). Mirrors the
# device-side copy on GPUBatchSimulator, which keeps its own for buffer
# allocation; both derive from GPUConstants so they can't drift.
const MAX_GAMBITS = GPUConstants.MAX_GAMBITS
const GAMBIT_SIZE = GPUConstants.GAMBIT_SIZE
const GAMBITS_PER_UNIT = MAX_GAMBITS * GAMBIT_SIZE  # 80 ints per unit


# GAMBIT_CONFIG_SCHEMA — the gambit-encode analogue of UNIT_CONFIG_SCHEMA
# (ADR-0016). One {key, field, default} row per *flat* gambit field; the write
# loop in _pack_gambits writes each as int(g.get(key, default)). No `extract`
# Callable — the value is always a plain read from the already-encoded dict
# GambitEncoder produces — so this is a `const`, not a `static var`.
#
# Hand-packed by the same line ADR-0003 drew for the status-timer packer:
# COND_COUNT is derived (conditions.size()) and the COND_TYPE_*/COND_VAL_* block
# is a repeated, index-arithmetic write — neither is a simple key->offset read,
# so both stay hand-written in _pack_gambits (see _GAMBIT_HAND_PACKED).
const GAMBIT_CONFIG_SCHEMA := [
	{"key": "enabled", "field": GambitField.ENABLED, "default": true},
	{"key": "cond_target_type", "field": GambitField.COND_TARGET_TYPE, "default": GPUConstants.TARGET_NEAREST_ENEMY},
	{"key": "action_type", "field": GambitField.ACTION_TYPE, "default": GPUConstants.ACTION_ATTACK},
	{"key": "action_id", "field": GambitField.ACTION_ID, "default": 0},
	{"key": "action_target_type", "field": GambitField.ACTION_TARGET_TYPE, "default": GPUConstants.TARGET_THEM},
]

# GambitField offsets written outside the schema. The completeness check below
# asserts SCHEMA ∪ HAND_PACKED ∪ RESERVED covers every offset in [0, GAMBIT_SIZE)
# with no overlap, so an added-but-unwritten field is a boot error, not a silent
# zero — the main failure mode worth catching on this dense buffer.
const _GAMBIT_HAND_PACKED := [
	GambitField.COND_COUNT,
	GambitField.COND_TYPE_0, GambitField.COND_TYPE_1, GambitField.COND_TYPE_2, GambitField.COND_TYPE_3,
	GambitField.COND_VAL_0, GambitField.COND_VAL_1, GambitField.COND_VAL_2, GambitField.COND_VAL_3,
]
const _GAMBIT_RESERVED := [GambitField.RESERVED_14, GambitField.RESERVED_15]


static func gambit_config_schema_problems() -> Dictionary:
	"""Validate GAMBIT_CONFIG_SCHEMA (ADR-0016). Returns {errors, warnings}.

	Stronger than unit_config_schema_problems: besides rejecting a doubly-written
	offset, it asserts *completeness* — every offset in [0, GAMBIT_SIZE) is
	written exactly once (schema, the hand-packed condition block, or RESERVED).
	The dense gambit buffer (no dormant fields, no init constants) makes this
	whole-buffer net cheap and worth having; it catches the main failure mode —
	adding a GambitField and forgetting to pack it. Pure, no GPU; shared by the
	boot check and the round-trip test (GambitEncodeSchemaTest)."""
	var errors := PackedStringArray()
	var seen := {}  # offset -> source label
	for row in GAMBIT_CONFIG_SCHEMA:
		var f: int = row["field"]
		if seen.has(f):
			errors.append("gambit layout: offset %d written twice (%s and schema '%s')" % [f, seen[f], row["key"]])
		seen[f] = "schema '%s'" % row["key"]
	for f in _GAMBIT_HAND_PACKED:
		if seen.has(f):
			errors.append("gambit layout: offset %d written twice (%s and hand-packed)" % [f, seen[f]])
		seen[f] = "hand-packed"
	for f in _GAMBIT_RESERVED:
		if seen.has(f):
			errors.append("gambit layout: offset %d written twice (%s and reserved)" % [f, seen[f]])
		seen[f] = "reserved"
	for f in range(GAMBIT_SIZE):
		if not seen.has(f):
			errors.append("gambit layout: offset %d in [0, %d) is never written (add a schema row, hand-pack it, or mark RESERVED)" % [f, GAMBIT_SIZE])
	return {"errors": errors, "warnings": PackedStringArray()}


static func _pack_gambits(gambits: Array) -> PackedInt32Array:
	"""Pack gambit configs into the per-unit GambitField buffer (ADR-0016).

	Pure — no RenderingDevice, no instance state — so the round-trip test
	(GambitEncodeSchemaTest) exercises it directly. Flat fields come from
	GAMBIT_CONFIG_SCHEMA (one looped source of truth); COND_COUNT and the 4-slot
	condition block are hand-packed (derived / repeated, by the ADR-0003 line).
	Disabled or absent slots stay zero (PackedInt32Array zero-initializes)."""
	var data := PackedInt32Array()
	data.resize(GAMBITS_PER_UNIT)
	for slot in range(MAX_GAMBITS):
		if slot >= gambits.size() or gambits[slot] == null:
			continue  # disabled slot — already zero
		var g = gambits[slot]
		var offset = slot * GAMBIT_SIZE
		# Flat fields — single source of truth: GAMBIT_CONFIG_SCHEMA.
		for row in GAMBIT_CONFIG_SCHEMA:
			data[offset + row["field"]] = int(g.get(row["key"], row["default"]))
		# Hand-packed: condition count + the 4 condition slots.
		var conditions = g.get("conditions", [])
		data[offset + GambitField.COND_COUNT] = mini(conditions.size(), 4)
		for c in range(4):
			if c < conditions.size():
				data[offset + GambitField.COND_TYPE_0 + c] = conditions[c].get("type", GPUConstants.COND_ALWAYS)
				data[offset + GambitField.COND_VAL_0 + c] = conditions[c].get("value", 0)
			else:
				data[offset + GambitField.COND_TYPE_0 + c] = GPUConstants.COND_ALWAYS
				data[offset + GambitField.COND_VAL_0 + c] = 0
	return data
