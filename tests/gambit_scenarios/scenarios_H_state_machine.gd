extends RefCounted

## Rule group H — gambit state machine. See [code]docs/gambit-rules.md[/code].
##
## H1–H5 cover the "a unit in <locked-state> does not re-evaluate gambits"
## invariants. The shader implements them structurally: `compute_unit_state`
## (stage_compute.glsl) only calls `evaluate_gambits` from the IDLE
## fall-through and the higher-priority WALKING re-eval; SPELL_CHARGING,
## ACTING, AWAITING_IMPACT, and U_PAUSED each return early without touching
## the eval path. The witness mechanism is the `state_inhibited` predicate:
## it walks `state_events` for the unit, finds the entry into the locked
## state, and asserts the NEXT state_event is a natural progression
## (prev == during_state) with the same `current_gambit` slot. A re-eval
## that committed a NEW gambit would either inject an intermediate
## state_event (different prev) OR overwrite U_CURRENT_GAMBIT; either mode
## trips the predicate.
##
## H1 — SPELL_CHARGING does not re-evaluate. Priest casting Cure on self
## enters SPELL_CHARGING for the charge duration (Cure has charge_time > 0
## per the FFT data). Natural exit is to ACTING (cinematic-spell path lands
## the caster in ACTING with U_TIMER = cinematic length).
##
## H2 — ACTING does not re-evaluate. Monk attacking a Knight enters ACTING
## for the swing duration (TICKS for the attack animation; melee swings
## end with state ACTING → IDLE on the timer-zero edge in
## stage_compute.glsl:1025).
##
## H3 — AWAITING_IMPACT does not re-evaluate. A ranged attacker (bow,
## weapon_type=12) at distance 5 on the MAP042 z=0 flat strip (heights are
## h=0 for x=4..9) fires at a Knight five tiles east. The ACTING SEQ ends
## before the 50-tick projectile flight lands, so stage_compute.glsl
## :1017–1022 transitions the firer from ACTING to AWAITING_IMPACT for the
## projectile tail. Natural exit is AWAITING_IMPACT → IDLE on the next
## timer-zero edge. The flat strip is required for LOS:
## `has_line_of_sight_direct` (combat_combat.glslinc :69) rasterises the
## projectile path and rejects any tile whose height exceeds the linear
## interpolation between attacker and target — z=7 of MAP042 has clamped
## ++ heights and would block any bow shot across it.
##
## H4 — REACTING (XFAIL). The shader has no LOGICAL_ACTIVITY_REACTING
## state; flinch animations are advanced via U_REACTION_TIMER (cosmetic
## tick at stage_compute.glsl:958) without gating gambit eval. The PRD
## rule is currently uncovered.
##
## H5 — U_PAUSED. U_PAUSED is set by `cast_cinematic_spell`
## (stage_spell.glsl:579) on every non-caster unit when a cinematic
## ability fires. compute_unit_state honors the gate at line 911:
## `if (BH_CINEMATIC_CASTER_IDX != -1 && U_PAUSED != 0) return;`, so
## witnessing that U_PAUSED was 1 on a non-caster while
## BH_CINEMATIC_CASTER_IDX named the caster IS the rule — the gate is
## structurally inseparable from U_PAUSED. The J1 fixture
## (`scenarios_J_cinematic.gd:_j1_non_caster_paused_during_cure_cinematic`)
## is the cradle; H5 uses the same Priest + DistantKnight shape and the
## same `cinematic_lifecycle` predicate that J1+J3 exercise.
##
## H6 — already shipped. See `_h6a_no_thrash_on_flat_axis_path` below.
##
## H7 — post-action IDLE return. After a Monk's first ACTING ends, the
## state machine writes IDLE (stage_compute.glsl:1025) and re-evaluates on
## the next gambit-eval tick. The witness asserts IDLE is reached within
## a budget tied to attack-animation length + a few re-eval ticks.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector



static func scenarios() -> Array:
	return [
		_h1a_priest_charging_does_not_reeval(),
		_h2a_monk_acting_does_not_reeval(),
		_h3a_archer_awaiting_impact_does_not_reeval(),
		_h4a_reacting_does_not_reeval_xfail(),
		_h5a_paused_does_not_reeval(),
		_h6a_no_thrash_on_flat_axis_path(),
		_h7a_monk_returns_to_idle_after_action(),
	]


# === Helpers ==================================================================
#
# Local copies of the same gambit factories used in scenarios_G_pathfinding.gd.
# Duplicated rather than pulled from a shared helper because the scenarios are
# explicitly per-rule-group: any cross-file helper drift would silently change
# the shape of the witness on the other side.

const ABILITY_CURE := 1            # mp_cost=6, range=4, vertical=1, charge_time > 0


static func _attack_nearest_enemy_slot() -> Gambit:
	return Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())


static func _wait_slot() -> Gambit:
	return Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())


static func _cure_self_slot() -> Gambit:
	# SELF target with always condition — Priest unconditionally casts Cure on
	# itself. Used by H1 to put the caster in SPELL_CHARGING regardless of
	# any incidental ally HP state.
	return Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())


# === H1 — SPELL_CHARGING inhibition ==========================================

static func _h1a_priest_charging_does_not_reeval() -> Dictionary:
	# Priest at (4,7) with slot 0 = Cure SELF (always condition). Cure has
	# charge_time > 0 in the FFT data, so stage_spell's start_spell path
	# (stage_spell.glsl :389) writes U_STATE = SPELL_CHARGING and sets
	# U_CAST_TIMER to the charge length. The Priest sits in SPELL_CHARGING
	# until cast_timer expires, then stage_spell's complete_spell_cast routes
	# Cure through cast_cinematic_spell (charge_time > 0 branch at :623) which
	# writes ACTING with a cinematic-length timer — the natural exit edge.
	#
	# The DistantKnight is positioned 4 tiles away (Manhattan distance 4) so
	# it never reaches the Priest within the scenario window; the H1 witness
	# is procedural (state transitions of the Priest), not numeric.
	#
	# Witness: state_inhibited(Priest, SPELL_CHARGING). The predicate finds
	# the first SPELL_CHARGING entry and verifies the next state_event is a
	# natural progression (prev == SPELL_CHARGING) with the SAME
	# current_gambit slot. A re-eval kicking in mid-charge would either
	# write a new slot via execute_gambit_action (different current_gambit
	# at exit) or commit a different action (different prev at exit) —
	# both trip the predicate.
	#
	# Budget: the Cure charge is bounded by the per-ability charge_time
	# from the FFT data; max_ticks=600 gives generous headroom for the
	# charge + the cinematic-ACTING tail without affecting the assertion
	# itself (the predicate only reads state_events).
	return {
		"rule": "H1",
		"name": "priest_charging_does_not_reeval",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 600,
		"units": [
			{
				"name": "Priest", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "hp": 50, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [_cure_self_slot(), _attack_nearest_enemy_slot()],
			},
			{
				"name": "DistantKnight", "team": 1, "tile": [3, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"gambit_slot": [{"unit": "Priest", "slot": 0}],
			"state_inhibited": [{
				"unit": "Priest", "during_state": "SPELL_CHARGING",
			}],
			"trace": [{
				"kind": "by_tick", "tick": 300,
				"unit": "Priest", "committed": "ABILITY",
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === H2 — ACTING inhibition ==================================================

static func _h2a_monk_acting_does_not_reeval() -> Dictionary:
	# Monk at (5,7) adjacent to Knight at (6,7) on MAP042 (z=7 flat heights
	# in the (5..6) corridor). Monk's slot 0 is ATTACK NEAREST_ENEMY (always
	# condition). The Knight is already in range (Manhattan=1), so the
	# Monk's first gambit eval routes through execute_attack_gambit
	# (stage_attack.glsl :439) which calls setup_attack_animation
	# (combat_combat.glslinc :294) — that writes U_STATE = ACTING and sets
	# U_TIMER to the swing duration. The Monk sits in ACTING for the swing
	# animation, then stage_compute.glsl :1025 writes IDLE on the timer-
	# zero edge.
	#
	# Witness: state_inhibited(Monk, ACTING). The Monk enters ACTING at
	# the first commit and stays until the swing finishes. A re-eval that
	# fired during ACTING would change current_gambit or inject a non-IDLE
	# transition; the predicate catches either.
	#
	# Budget: max_ticks=600 leaves room for the post-ACTING IDLE → re-eval
	# loop against an invincible 999-HP dummy. The state_inhibited
	# assertion fires on the FIRST ACTING window only — the predicate's
	# entry-search picks the earliest ACTING entry, so post-commit
	# stalemate doesn't affect the witness.
	return {
		"rule": "H2",
		"name": "monk_acting_does_not_reeval",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 600,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [5, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [6, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
			"state_inhibited": [{
				"unit": "Monk", "during_state": "ACTING",
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === H3 — AWAITING_IMPACT inhibition =========================================

static func _h3a_archer_awaiting_impact_does_not_reeval() -> Dictionary:
	# Bow attacker (weapon_type=12 WEAPON_TYPE_BOW, weapon_range=5) at
	# (4,0) firing at a Knight at (9,0) on MAP042's z=0 flat strip —
	# heights are h=0 for x=4..9 (per `preview_map.py MAP042`). Manhattan
	# distance = 5, within the bow's range; identical-height tiles mean
	# `has_line_of_sight_direct` (combat_combat.glslinc :69) accepts the
	# straight-line shot. weapon_flags=1 (STRIKING bit) falls through to
	# ATTACK_DIRECT for range >= 2 (combat_combat.glslinc :24–29).
	#
	# The ranged branch of setup_attack_animation
	# (combat_combat.glslinc :268) computes
	# damage_frame = projectile_frame + dist × FLIGHT_TICKS_PER_TILE
	# = projectile_frame + 50. The bow's bare-SEQ duration is ~30 ticks,
	# scaled by ABILITY_SEQ_SPEED (=1) and GLOBAL_SPEED_DIVISOR (=1.0) to
	# ~30 ticks. So at the ACTING timer-zero edge, anim_frame ≈ 30 and
	# damage_frame is ~50+, leaving a ~20-tick window of in-flight
	# projectile. stage_compute.glsl :1017–1022 catches that gap and
	# writes U_STATE = AWAITING_IMPACT with U_TIMER = flight_remaining.
	# When that timer expires the same handler writes IDLE at :1030–1041.
	#
	# Witness: state_inhibited(Archer, AWAITING_IMPACT). A re-eval
	# mid-flight would either change current_gambit (from execute_gambit_
	# action's U_CURRENT_GAMBIT write) or land an unexpected intermediate
	# state_event with prev != AWAITING_IMPACT — the predicate catches
	# both.
	#
	# Budget: trace.by_tick=180 leaves headroom for the bow's SEQ +
	# AWAITING_IMPACT tail (~30 + ~20 = ~50 ticks empirically) plus a
	# couple of frame-alignment slips at the 4× test_time_scale runner
	# cadence. max_ticks=600 caps any runaway scenario.
	return {
		"rule": "H3",
		"name": "archer_awaiting_impact_does_not_reeval",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 600,
		"units": [
			{
				"name": "Archer", "team": 0, "tile": [4, 0],
				"job": "4e", "max_hp": 200, "max_mp": 0,
				"pa": 10, "ma": 8, "wp": 4, "move": 4, "jump": 4,
				"weapon_range": 5, "weapon_flags": 1, "weapon_type": 12,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [9, 0],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 180,
				"unit": "Archer", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Archer", "slot": 0}],
			"state_inhibited": [{
				"unit": "Archer", "during_state": "AWAITING_IMPACT",
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === H4 — REACTING (XFAIL) ===================================================

static func _h4a_reacting_does_not_reeval_xfail() -> Dictionary:
	# H4 in gambit-rules.md says "a unit in REACTING (taking damage / playing
	# flinch) does not re-evaluate." The current shader has no
	# LOGICAL_ACTIVITY_REACTING state — flinch animations are driven via
	# U_REACTION_TIMER (combat_common.glslinc :59), which
	# stage_compute.glsl :958–961 ticks down each compute pass without
	# guarding gambit eval. There's no observable "REACTING window" to
	# witness, so this scenario stands as an XFAIL placeholder until the
	# shader grows the state OR the rule is reframed against
	# U_REACTION_TIMER directly.
	#
	# Setup mirrors H2 (Monk vs Knight, adjacent) so the SAME state_inhibited
	# spec can be wired in once REACTING exists; the predicate currently
	# fails with "unknown state 'REACTING'" which the xfail entry expects.
	return {
		"rule": "H4",
		"name": "reacting_does_not_reeval",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [5, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [6, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"state_inhibited": [{
				"unit": "Knight", "during_state": "REACTING",
			}],
		},
		"xfail": ["state_inhibited(unit='Knight', during_state='REACTING')"],
		"xfail_reason": "Shader has no LOGICAL_ACTIVITY_REACTING state. Flinch is driven by U_REACTION_TIMER without gating gambit eval; H4 is uncovered until a REACTING state lands or the rule is reframed against U_REACTION_TIMER.",
	}


# === H5 — U_PAUSED ===========================================================

static func _h5a_paused_does_not_reeval() -> Dictionary:
	# H5: "a unit with U_PAUSED == 1 (cinematic spotlight) does not
	# re-evaluate. Caster is exempt." Witness via the cinematic_lifecycle
	# predicate, which proves U_PAUSED was 1 on the non-caster while
	# BH_CINEMATIC_CASTER_IDX named the caster, then 0 after teardown.
	# Together with the structural gate in stage_compute.glsl :910–913
	# (`if (BH_CINEMATIC_CASTER_IDX != -1 && U_PAUSED != 0) return;`), that
	# round-trip IS the rule — the gate is unconditional once U_PAUSED is
	# set, so a snapshot where U_PAUSED == 1 mid-cinematic is equivalent
	# to "evaluate_gambits cannot run on this unit during this window."
	#
	# The fixture mirrors J1a (Priest casts Cure on SELF, ct=4 routes
	# through cast_cinematic_spell, DistantKnight sits well outside Cure's
	# AoE radius so the heal walker doesn't touch them). The snapshot_tick
	# extension landed in PR #82 (commit b97b0227) surfaces `paused` per
	# unit, which is exactly what cinematic_lifecycle reads.
	return {
		"rule": "H5",
		"name": "paused_does_not_reeval",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 500,
		"units": [
			{
				"name": "Priest", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [_cure_self_slot()],
			},
			{
				"name": "DistantKnight", "team": 1, "tile": [8, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"gambit_slot": [{"unit": "Priest", "slot": 0}],
			"cinematic_lifecycle": [{
				"kind": "cinematic_lifecycle",
				"caster": "Priest",
				"non_caster": "DistantKnight",
				"by_tick": 400,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === H6 — no-thrash baseline =================================================

static func _h6a_no_thrash_on_flat_axis_path() -> Dictionary:
	# G1's geometry — Monk(jump=4) at (2,4), Knight at (8,8) on MAP042 — is
	# the cleanest successful path in the suite (10 walked steps, no
	# backtrack, no contention, no impassable detour). The decision ring
	# buffer fills with START_MOVING / WALKING entries (all
	# forward-progress reasons), so neither thrash pattern can fire:
	#   - same-target appearing 3+ times across the 6-entry ring: each
	#     START_MOVING entry's target is the next step tile, distinct from
	#     the prior; the ring never accumulates 3 same-target entries.
	#   - last-3-entries cycling NO_PATH / GAMBIT_FAILED / NO_GAMBIT: a
	#     successful step emits REASON_START_MOVING, not a stuck reason;
	#     the last-3 window is always at least one progress entry.
	#
	# What this witnesses: the per-tick state-machine bookkeeping
	# (decision_meta write index, thrash_flag preservation across
	# record_decision writes, the prev_thrash latch in
	# check_decision_thrash) does not corrupt the bit even when nothing
	# interesting is happening. A regression that flipped the bit on
	# accidentally — e.g. an unsigned underflow in the stuck_count
	# accumulation, or a shift-mask mistake in `meta = (write_idx & 0x7) |
	# (meta & 0xF8)` (stage_compute.glsl:341) that leaked into bit 3 —
	# would trip this baseline.
	#
	# Budget: by_tick=1050 mirrors G1's commit window with 1.5× headroom
	# over the empirical ~359-tick commit. The no_thrash assertion is
	# intentionally tighter at by_tick=450 — once the Monk reaches the
	# adjacent attack tile and starts cycling attack/cooldown against the
	# invincible (999 HP) dummy Knight, the per-tick re-evaluation emits
	# stuck reasons under attack cooldown and the thrash_flag legitimately
	# sets in post-commit stalemate (observed tick 529 here). That's the
	# invincible-dummy rig artifact, not the H6 rule failing: H6 covers
	# the state-machine bookkeeping during ordinary play, which the
	# tighter window witnesses with ~90-tick headroom past the empirical
	# commit. max_ticks=1200.
	return {
		"rule": "H6",
		"name": "no_thrash_on_flat_axis_path",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 1200,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [2, 4],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [8, 8],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 1050,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"no_thrash": [{
				"unit": "Monk", "by_tick": 450,
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Knight",
				"max_dist": 1, "by_tick": 1050,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === H7 — post-action IDLE return ============================================

static func _h7a_monk_returns_to_idle_after_action() -> Dictionary:
	# Same H2 geometry — Monk at (5,7) adjacent to Knight at (6,7). After
	# the Monk's first ACTING window ends, stage_compute.glsl :1025 writes
	# U_STATE = IDLE and U_DBG_STATE_REASON = REASON_ATTACK_ENDED. The
	# IDLE entry is the H7 witness target.
	#
	# Predicate: returns_to_idle(Monk, after_state=ACTING, within_ticks=N).
	# The Monk's ACTING swing is ~120 ticks empirically (the attack
	# animation length, after MIN_ATTACK_DURATION clamping and
	# ABILITY_SEQ_SPEED / GLOBAL_SPEED_DIVISOR scaling). After ACTING
	# ends, the next compute IRQ runs the IDLE branch and evaluates
	# gambits — which re-commits ATTACK because Knight is still adjacent.
	# So state goes ACTING → IDLE → ACTING within ONE GPU tick, and the
	# CombatLoop's per-frame interpreter (GPUCombatInterpreter samples at
	# the end of each `tick(delta)` frame, NOT every GPU tick — see
	# CombatLoop.gd :628 `_check_state_changes`) only sees IDLE when a
	# frame boundary lands in the 1-tick IDLE window. At the runner's 4×
	# test_time_scale that boundary lands ~25% of attack cycles; the
	# FIRST observable IDLE may need several swing cycles before alignment
	# yields a visible sample. within_ticks=700 is loose enough to cover
	# that frame-alignment slip and still catch a real regression that
	# left the Monk structurally stuck in ACTING (which would never reach
	# IDLE within the trace window). Empirical: at within_ticks=400 the
	# scenario flakes ~1/5 runs; at 700 it survived 5/5 budget-bounded
	# runs once max_ticks was raised to admit the larger window.
	#
	# Pairs with H2's state_inhibited witness on the SAME scenario shape:
	# H2 asserts "no eval during ACTING," H7 asserts "eval resumes after
	# ACTING." A regression that broke the ACTING → IDLE transition would
	# trip H7 (Monk stuck in ACTING) but not H2 (state inhibition still
	# vacuously holds because there's never an exit). The two together
	# pin both invariants.
	#
	# Budget: max_ticks=1000 admits the within_ticks=700 IDLE-window
	# alignment budget (the trace must extend at least within_ticks past
	# the first ACTING entry, or the predicate fails with "never returned
	# to IDLE within trace"). The predicate fires on the FIRST ACTING
	# entry's IDLE successor so what the Monk does after that doesn't
	# matter.
	return {
		"rule": "H7",
		"name": "monk_returns_to_idle_after_action",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 1000,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [5, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [6, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
			"returns_to_idle": [{
				"unit": "Monk", "after_state": "ACTING",
				"within_ticks": 700,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}
