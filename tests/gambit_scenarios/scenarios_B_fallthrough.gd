extends RefCounted

## Rule group B — fall-through. See [code]docs/gambit-rules.md[/code].
##
## Every scenario in this file uses the same shape: a higher-priority slot 0
## that is expected to fall through (no candidate, condition false, MP veto,
## status veto, or no executable position) followed by a slot 1 that catches
## the actor and produces a state-change the trace logger can witness. The
## predicate then checks: did the unit reach slot 1's action, on which tick.
##
## Why the spec's slot-1 verbs are not always preserved verbatim:
##   B5 says "MOVE_TO_UNIT (slot 0) + WAIT (slot 1)". A WAIT-only fallback
##   loops IDLE→IDLE without emitting a state_changed event, which trips the
##   NORAN baseline ("no gambit eval recorded") and makes the verdict
##   ambiguous. Using ATTACK on an adjacent enemy as the slot-1 verb
##   preserves the spec intent (slot 0 vetoed → slot 1 fires) and gives the
##   trace logger a state change to anchor against.
##
## Why item-action is not exercised in B4:
##   [code]Gambit.ActionKind[/code] does not include ITEM today; the encoder
##   route from author → GPU passes through ATTACK / WAIT / MOVE / ABILITY
##   only. B4's "items still pass" half of the spec is therefore
##   uncoverable from the scenario suite until that gap closes — recorded
##   in the scenario's [code]xfail_reason[/code] as a TODO.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const StatusRegistry = ExMateriaAlmanac.StatusRegistry
const TargetSelector = ExMateriaAlmanac.TargetSelector



const ABILITY_CURE := 1            # mp_cost=6, range=4, vertical=1
const ABILITY_FIRE := 16           # mp_cost=6, range=4, vertical=1
const ABILITY_SECRET_FIST := 104   # range=1, vertical=0, vertical_tolerance=true
const ABILITY_REPEATING_FIST := 101  # mp_cost=0, ct=0, range=1, vertical=1, vertical_tolerance=true

# Status seeding routes through [code]StatusRegistry[/code] (#67) — the
# single source of truth that mirrors [code]combat_common.glslinc[/code].


static func scenarios() -> Array:
	return [
		_b1_no_candidate_falls_to_attack(),
		_b2_condition_false_falls_to_attack(),
		_b3_mp_veto_falls_to_attack(),
		_b4_silence_vetoes_spell_falls_to_attack(),
		_b5_immobilize_vetoes_move_falls_to_attack(),
		_b6_secret_fist_no_fallback(),
		_b6_secret_fist_target_no_same_height_neighbor(),
		_b6_fire_los_blocked_by_terrain(),
		_b7_nearest_enemy_pass2_pivots_to_rank1(),
		_b8_ct_zero_ability_respects_cooldown(),
		_b8_secret_fist_alternates_with_attack(),
		_b9_dead_authored_gambit_falls_to_safety_net(),
		_b10_strict_depth_does_not_retry(),
		_b10c_control_the_same_strict_row_fires_at_rank_zero(),
	]


# === B1 ===============================================================

static func _b1_no_candidate_falls_to_attack() -> Dictionary:
	# Slot 0 targets NEAREST_ALLY but the Monk has no allies — the team-filter
	# select returns < 0 and pass-1 skips slot 0 without running its action.
	# Slot 1 (ATTACK NEAREST_ENEMY) catches the actor and produces ACTING.
	var slot0 := Gambit.create(
			TargetSelector.friendlies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B1",
		"name": "no_candidate_for_condition_target_falls_through",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 1}],
			"no_safety_net_hit": [{"unit": "Monk"}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === B2 ===============================================================

static func _b2_condition_false_falls_to_attack() -> Dictionary:
	# Slot 0 attacks the nearest enemy ONLY when their HP is below 50%. The
	# Target spawns at full HP, so the condition pass fails and slot 0 is
	# skipped. Slot 1 (unconditional ATTACK) catches and fires.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B2",
		"name": "condition_false_falls_through",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 1}],
			"no_safety_net_hit": [{"unit": "Monk"}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === B3 ===============================================================

static func _b3_mp_veto_falls_to_attack() -> Dictionary:
	# Slot 0 is Cure on SELF (always-valid condition target). Caster's MP is
	# zero so [code]spell_pre_validate[/code] returns false (mp_cost > current_mp)
	# and pass-1 skips slot 0 without entering SPELL_CHARGING. Slot 1
	# (ATTACK NEAREST_ENEMY) catches the actor.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B3",
		"name": "mp_veto_falls_through",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Priest", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40,
				# mp:0 forces the MP veto on slot 0's Cure (mp_cost=6).
				"mp": 0,
				"pa": 5, "ma": 12, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 150,
				"unit": "Priest", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Priest", "slot": 1}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === B4 ===============================================================

static func _b4_silence_vetoes_spell_falls_to_attack() -> Dictionary:
	# Caster's status_flags_lo has the SILENCE bit set at battle start.
	# Slot 0 (Fire SPELL) is vetoed by the silence gate inside
	# [code]execute_gambit_action[/code]. Slot 1 (ATTACK NEAREST_ENEMY)
	# catches.
	#
	# Spec also says items still pass; that half is uncovered today —
	# [code]Gambit.ActionKind[/code] has no ITEM, so an item-action can't be
	# authored through [code]GambitEncoder[/code]. Noted in xfail_reason.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_FIRE,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B4",
		"name": "silence_vetoes_spell_falls_through_to_attack",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 8, "ma": 14, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"status_flags_lo": 1 << StatusRegistry.bit(&"silence"),
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Wizard", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Wizard", "slot": 1}],
		},
		"xfail": [],
		"xfail_reason": "B4 \"items still pass\" sub-clause is uncovered: Gambit.ActionKind has no ITEM, so the encoder pipeline can't author an item-action. Reopen this scenario when ACTION_ITEM lands in the Gambit domain.",
	}


# === B5 ===============================================================

static func _b5_immobilize_vetoes_move_falls_to_attack() -> Dictionary:
	# Caster has STATUS_IMMOBILIZE set at battle start. Slot 0
	# (MOVE_TO_UNIT NEAREST_ENEMY) is vetoed by the immobilize gate. Slot 1
	# (ATTACK NEAREST_ENEMY) catches — the Monk is adjacent to the target so
	# the attack executes from its starting tile (no movement needed, which
	# is the whole point of the test).
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.MOVE, -1,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B5",
		"name": "immobilize_vetoes_move_falls_through_to_attack",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"status_flags_lo": 1 << StatusRegistry.bit(&"immobilize"),
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 1}],
			"no_safety_net_hit": [{"unit": "Monk"}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === B6 ===============================================================

static func _b6_secret_fist_no_fallback() -> Dictionary:
	# Two-slot loadout: Secret Fist (slot 0) → Attack (slot 1). The shader
	# is supposed to fall through to slot 1 when slot 0 has no valid cast
	# position. Today it doesn't (and the test pins that as XFAIL).
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_SECRET_FIST,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B6",
		"name": "monk_secret_fist_out_of_range_falls_back_to_attack",
		"map": "MAP042",
		"seed": 42,
		# Bumped to 400 ticks (well past the K=10 fall-through window in the
		# spec) so a fixed shader has time to attack and the no_stuck/by_tick
		# predicates are decisive either way.
		"max_ticks": 400,
		"units": [
			# Monk at (5,7) on MAP042, vertical-tolerance terrain reused from
			# GPUVerticalToleranceTest: Secret Fist *will* find a cast position
			# at (4,6) — so this scenario today PASSES the no_stuck check. To
			# truly exercise "no cast position reachable" the scenario would
			# need a chokepoint setup; the variant below
			# (_b6_secret_fist_target_no_same_height_neighbor) gives that. The
			# scaffold's purpose here is to demonstrate the XFAIL machinery —
			# so we pin the by_tick(50): committed(ATTACK) expectation as the
			# xfail (Monk casts Secret Fist after walking, doesn't fall
			# through to Attack at <=K=10 ticks).
			{
				"name": "Monk", "team": 0, "tile": [5, 7],
				"job": "4e", "max_hp": 500, "max_mp": 50,
				"pa": 14, "ma": 10, "wp": 0, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 6],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 50,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"liveness": [{
				"kind": "no_stuck", "unit": "Monk",
				"max_idle_ticks": 10, "given": "any_enemy_alive",
			}],
		},
		"xfail": [
			"by_tick(50): unit('Monk').committed(ATTACK)",
		],
		"xfail_reason": "B6 — Secret Fist does NOT fall through to Attack within K=10; the first slot-1 ATTACK lands at tick 58, past this by_tick(50) bound. THE MARKER IS CORRECT; THE REPORTED XPASS IS NOT. Two defects sit on top of it. (a) #432: committed(ATTACK) never inspects the action — it matches any entry into ACTING, and this Monk commits slot 0 (ability 104, Secret Fist) at tick 2, so the predicate scores a cast as an Attack. (b) #433: these tiles predate ADR-0052's depth mirror, so (5,7)/(5,6) now read the mirror of the row they meant — post-flip the Monk stands adjacent at equal height 11 and casts in place instead of walking to a cast position, which is why the prose above no longer describes the run. Do NOT clear this xfail; fix #432 first. Shader fix tracked under #57's parent PRD (#56).",
	}


static func _b6_secret_fist_target_no_same_height_neighbor() -> Dictionary:
	# ⚠ STALE PREMISE — this scenario is GREEN while asserting nothing. See #433.
	# The heights below were authored against pre-ADR-0052 coordinates: all five
	# match z -> 14-z exactly ((8,10)=3, (7,10)=2, (9,10)=0, (8,11)=0, (8,9)=4)
	# and NONE match today's export, where (8,4)=7 and the Monk's own tile
	# (8,5)=7 is a valid same-height cast position. The Monk therefore casts at
	# tick 2 rather than falling through, and passes only because
	# committed(ATTACK) matches any ACTING entry (#432). Left green rather than
	# gambled, on the same grounds 13c097081 used for G1/G2/G3/G5/G6.
	#
	# Vertically-inaccessible cast target. On MAP042, tile (8,4) is h=3 with
	# neighbors (7,4)=2 / (9,4)=0 / (8,3)=0 / (8,5)=4 — none at h=3. Secret
	# Fist's vertical_tolerance=true + vertical=0 demands a same-height
	# adjacent tile, so NO cast position is reachable adjacent to the target.
	# A spec-faithful shader (B6: K=10 ticks) would fall through to slot 1
	# Attack. Today the unit retries forever (XFAIL).
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_SECRET_FIST,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B6",
		"name": "monk_secret_fist_target_on_peak_no_cast_position",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [8, 5],
				"job": "4e", "max_hp": 500, "max_mp": 50,
				"pa": 14, "ma": 10, "wp": 0, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [8, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 50,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"liveness": [{
				"kind": "no_stuck", "unit": "Monk",
				"max_idle_ticks": 10, "given": "any_enemy_alive",
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _b6_fire_los_blocked_by_terrain() -> Dictionary:
	# LOS-blocked spell. Wizard at (3,4) h=3 casts Fire at Target at (3,7)
	# h=9. The arc LOS check (combat_combat.glslinc / ARC_LOS_HEIGHT_PER_TILE)
	# rejects the line because the intermediate tile (3,5) h=9 sits well
	# above the parabolic arc at that step. The shader's pre-cast scan looks
	# for a reachable cast position with LOS within Fire's range=4; the
	# nearby tiles' arcs are similarly blocked by the (3,5)/(3,6) ridge, so
	# the slot retries forever. Spec says fall through to slot 1 within K=10.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_FIRE,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B6",
		"name": "wizard_fire_los_blocked_by_terrain",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [3, 4],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 8, "ma": 14, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [3, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 50,
				"unit": "Wizard", "committed": "ATTACK",
			}],
			"liveness": [{
				"kind": "no_stuck", "unit": "Wizard",
				"max_idle_ticks": 10, "given": "any_enemy_alive",
			}],
		},
		"xfail": [
			"by_tick(50): unit('Wizard').committed(ATTACK)",
		],
		"xfail_reason": "B6 LOS variant — Fire's arc LOS check rejects the line across the (3,5)/(3,6) ridge; today the shader keeps retrying slot 0 instead of falling through within K=10. The Wizard does eventually walk along the ridge and find a position with LOS, which makes no_stuck soft-pass once it casts; the by_tick(50): ATTACK expectation pins the fall-through gap.",
	}


# === B7 ===============================================================

static func _b7_nearest_enemy_pass2_pivots_to_rank1() -> Dictionary:
	# Pass-2 retry on a NEAREST_ENEMY gambit. Slot 0 ATTACKs the nearest
	# enemy only if their HP < 50%. The closer enemy (BeefyKnight) is at
	# full HP so pass-1 skips slot 0 (condition false against rank-0).
	# Pass 2 retries the same slot against rank-1 (BleedingKnight at 20% HP)
	# and the condition passes — the Wizard attacks BleedingKnight even
	# though they are FARTHER than BeefyKnight.
	#
	# Witness: hp_events shows BleedingKnight took damage before
	# BeefyKnight (in fact BeefyKnight should never take damage on this
	# slot — there is no slot 1, so pass-1 cannot fire). If pass-2 is
	# broken, the Wizard idles indefinitely and [code]no_stuck[/code] trips.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B7",
		"name": "nearest_enemy_pass2_pivots_to_rank1_low_hp",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 12, "ma": 12, "wp": 4, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0],
			},
			{
				# Rank-0 nearest (Manhattan 1). Full HP — fails slot 0's
				# condition pass.
				"name": "BeefyKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Rank-1 nearest (Manhattan 2). Low HP — passes the condition
				# when pass-2 retries with this candidate.
				#
				# MOVED (3,7) -> (2,7) on 2026-08-22. The comment above always said
				# "Manhattan 2" and the header always said BleedingKnight is "FARTHER
				# than BeefyKnight", but (3,7) is Manhattan 1 from the Wizard at (4,7) —
				# a TIE with BeefyKnight, not a rank separation. A scenario whose whole
				# subject is "pass 2 retries against RANK 1" cannot be built on two
				# candidates at rank 0. (2,7) is h=8, the same height as (3,7), reachable
				# and strikeable (Δh 0 from (3,7)), so nothing else about the fixture
				# moves.
				"name": "BleedingKnight", "team": 1, "tile": [2, 7],
				"job": "4c", "max_hp": 100, "max_mp": 0, "hp": 20,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 200,
				"unit": "Wizard", "committed": "ATTACK",
			}],
			"damage": [
				{
					"kind": "damage_dealt_to",
					"target": "BleedingKnight", "by_tick": 300,
				},
				# Diagnostic counter-assertion: BeefyKnight must NOT be
				# damaged within the same window. If pass-2 is broken and
				# pass-1 mistakenly fires on rank-0, this assertion flips to
				# pass while the BleedingKnight one stays failing — which is
				# the failure shape we want to see when we regress the fix.
				# Inversion is encoded via `expect_no_damage: true`.
				{
					"kind": "damage_dealt_to",
					"target": "BeefyKnight", "by_tick": 300,
					"expect_no_damage": true,
				},
			],
			# no_stuck is deliberately omitted — after pass-2 kills
			# BleedingKnight (~tick 35) the Wizard's only remaining
			# slot-0 candidate is BeefyKnight at full HP, which fails the
			# HP_BELOW(50) condition. Spec-correct behavior is "idle
			# forever waiting for a low-HP enemy", which trips the
			# any_enemy_alive given but is NOT a B6/B7 bug. The pair
			# (committed(ATTACK), damage_dealt_to(BleedingKnight)) +
			# (no_damage_dealt_to(BeefyKnight)) is the load-bearing witness
			# of the pass-2 rank pivot.
		},
		"xfail": [
			"damage_dealt_to(target='BleedingKnight', by_tick=300)",
			"no_damage_dealt_to(target='BeefyKnight', by_tick=300)",
		],
		"xfail_reason": "The gambit picks the right unit and the swing lands on a different one. Pass 2 pivots to rank-1 (BleedingKnight) and execute_gambit_action writes U_TARGET to it, but the damage arrives on the rank-0 nearest instead. PRIME SUSPECT: stage_pathfind.glsl handle_moving_state opens with `nearest = find_nearest_enemy(); if (can_attack_target(nearest)) { write_unit(U_TARGET, nearest); state = IDLE; }` — a unit walking toward a gambit-CHOSEN target is hijacked into whatever nearest enemy it can already reach, discarding the pick, and the safety net then swings on it. NEXT EXPERIMENT (needs a GPU state dump, not more static reading): log U_TARGET and U_DBG_STATE_REASON per tick for the Wizard between commit (tick 15) and first damage (tick 42) and see whether REASON_CAN_ATTACK appears. Marked XFAIL, NOT fixed.",
	}


# === B8 ===============================================================

static func _b8_ct_zero_ability_respects_cooldown() -> Dictionary:
	# CT=0, MP=0 Punch Art (SecretFist) on an adjacent enemy. Real-time
	# gambit eval has no turn-based floor, so without the cooldown veto the
	# Monk re-fires the ability as fast as the cast animation +
	# TICKS_GAMBIT_REEVAL allow — gaps land around 30 ticks.
	# B8 asserts the cooldown veto ([code]cooldown_pre_validate[/code] in
	# stage_compute.glsl, mirror of B3's MP veto) holds the per-(unit,
	# ability) interval at the 60-tick floor (1 second at 60 Hz).
	#
	# Witness: at least 3 SecretFist casts observed for the Monk in the
	# 300-tick window, with every consecutive pair >= 60 ticks apart. The
	# predicate scores the spacing against GPU commit ticks (recovered from
	# the [code]cooldown_ready_at[/code] SSBO sample at cast emission) rather
	# than trace ticks: at the runner's Engine.time_scale=4 a host frame
	# spans 4+ GPU ticks, and CAST_BEGAN emits at end-of-frame, so the trace
	# tick lags the actual commit by up to (frame_size-1) ticks — under #86
	# the trace-tick view leaked sub-floor gaps (e.g. 48-56) while the GPU
	# was correctly enforcing 60. See ADR-0047 §Addendum for the diagnosis.
	# Target sits with max_hp 9999 so it never dies
	# before the window closes; otherwise the Monk's gambit would fall
	# through to slot 1 and the test would stop collecting cast events.
	#
	# Slot 1 is WAIT (not ATTACK) so the cooldown-vetoed fall-through emits
	# no [code]CAST_BEGAN[/code] event — the predicate counts cast_events
	# for (Monk, SecretFist), but the GPU interpreter carries forward the
	# prior [code]casting_ability_id[/code] when a fresh ACTING entry has
	# none (GPUCombatInterpreter line 178-184). An ATTACK fallback would
	# inherit ability_id=104 and emit a spurious cast event, making the
	# predicate look at a noisy mix of real-cast + fallback ticks. WAIT
	# never enters ACTING, so the trace stream is clean.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_SECRET_FIST,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1,
			TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B8",
		"name": "ct_zero_ability_respects_60_tick_cooldown",
		"map": "MAP042",
		"seed": 42,
		# Window must fit at least min_casts=3 observations at the cooldown
		# spacing — at cooldown_ticks=300 each cycle is ~300 ticks plus the
		# cast animation, so we need ~900-1000 ticks of room.
		"max_ticks": 1000,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 0],
				"job": "4e", "max_hp": 500, "max_mp": 0,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				# Punching-bag enemy. max_hp 9999 keeps the Monk's gambit
				# pinned to slot 0 across the whole window (otherwise an
				# early kill would drain the cast-event stream).
				"name": "Target", "team": 1, "tile": [5, 0],
				"job": "4c", "max_hp": 9999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
		],
		"expect": {
			"cooldown": [{
				"kind": "cooldown_respected",
				"unit": "Monk",
				"ability": ABILITY_SECRET_FIST,
				"min_spacing": 60,
				"min_casts": 3,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _b8_secret_fist_alternates_with_attack() -> Dictionary:
	# Companion to B8 (cooldown floor). B8 witnessed that consecutive Secret
	# Fist commits respect the 60-tick spacing — using slot 1 = WAIT to dodge
	# the [code]casting_ability_id[/code] carryover quirk
	# (GPUCombatInterpreter:178-184) that would emit spurious CAST_BEGAN events
	# when an ATTACK fallback inherited ability_id=104. This scenario picks up
	# what B8 deferred: with slot 1 = ATTACK, does the cooldown window admit
	# at least one ATTACK commit before Secret Fist re-fires?
	#
	# Issue #92's tuning concern: cooldown_ticks counts from COMMIT, so the
	# effective fallback window is
	# [code]cooldown_ticks - cast_animation_ticks - eval_lag[/code]. If
	# cooldown is so short the window collapses below the ATTACK animation,
	# ATTACK never fires and the cooldown does nothing the animation isn't
	# already doing. This predicate fails in that regime — it's the regression
	# guard the tuning lacks.
	#
	# Real ability commits are recognised by `current_gambit == 0` on
	# cast_events (the spurious ATTACK-as-ability_id=104 events from the
	# interpreter quirk carry `current_gambit == 1`, so dual-filtering on
	# (ability_id, current_gambit) cleanly separates the two streams).
	# Fallback ATTACKs are state_events `IDLE -> ACTING` with
	# `current_gambit == 1`.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_SECRET_FIST,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B8",
		"name": "secret_fist_alternates_with_attack_fallback",
		"map": "MAP042",
		"seed": 42,
		# Window must admit at least 2 cycles of (cooldown + animation) so the
		# predicate has consecutive ability commits to score spacing between.
		# At cooldown_ticks=300 plus ~60 ticks of animation, one cycle is ~360
		# ticks — 800 leaves comfortable headroom for 2-3 cycles.
		"max_ticks": 800,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 0],
				"job": "4e", "max_hp": 500, "max_mp": 0,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 0],
				"job": "4c", "max_hp": 9999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
		],
		"expect": {
			"alternates_with": [{
				"kind": "alternates_with",
				"unit": "Monk",
				"ability": ABILITY_SECRET_FIST,
				"ability_slot": 0,
				"fallback_slot": 1,
				"min_fallback_per_cycle": 1,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === B-SAFETYNET =======================================================

static func _b9_dead_authored_gambit_falls_to_safety_net() -> Dictionary:
	# ADR-0048 positive guard. The Monk's ONLY authored gambit heals a nearest
	# ALLY, but it has no allies, so pass-1 skips it (no candidate). With no
	# authored fallback the unit would idle forever — except the encoder injects
	# a safety-net gambit at slot MAX_USER_GAMBITS, which catches the actor and
	# drives an ATTACK on the adjacent enemy. Proves the GPU shader actually
	# evaluates the injected slot end-to-end (the pure-logic GambitSafetyNetTest
	# only proves the encoding).
	var slot0 := Gambit.create(
			TargetSelector.friendlies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B-SAFETYNET",
		"name": "dead_authored_gambit_falls_to_safety_net",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0],
			},
			{
				"name": "Target", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Monk", "committed": "ATTACK",
			}],
			# The commit comes from the injected safety-net slot, not an authored one.
			"gambit_slot": [{"unit": "Monk", "slot": GPUConstants.MAX_USER_GAMBITS}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === B10 ==============================================================
#
# ADR-0285 — STRICT DEPTH. B7 says a nearest-type slot RETRIES at ranks 1, 2, 3…; B10 is the
# other half of that sentence, and it did not exist in the kernel until ADR-0285:
# `TARGET_NEAREST_ALLY_ONLY` / `TARGET_NEAREST_ENEMY_ONLY` run the SAME search and are absent
# from Pass 2's retry guard, so rank 0 is the only candidate the slot ever sees.
#
# === WHY THE WITNESS IS "WHICH SLOT", AND WHY BOTH SLOTS ARE ON ONE UNIT =====================
#
# The two selectors differ in exactly one field — `NEAREST_ONLY` against `NEAREST_FIRST` — and
# they produce the SAME rank-0 candidate, the same ability, the same target, the same reach. So
# no observable OUTSIDE the slot can tell them apart: whichever one fires, the identical Cure
# lands on the identical ally. Pinning damage or healing or position here would be pinning a
# value both arms produce.
#
# What differs is WHICH SLOT the unit commits from, and `first_commit`'s `slot` is a discrete
# per-tick witness of exactly that. So slot 0 is the strict row, slot 1 is the pool row, and
# they are on ONE unit in ONE battle on ONE tick clock — not two fixtures compared across two
# runs, which is a provenance error dressed as an A/B.
#
#   slot 0  Cure · Nearest Ally · Their · HP<50%   rank 0 is HEALTHY -> must NOT fire
#   slot 1  Cure · Ally         · Their · HP<50%   retries to rank 1 -> FIRES
#
# If strict depth regressed — the type added back to Pass 2's guard, or the encoder collapsing
# `NEAREST_ONLY` onto `TARGET_NEAREST_ALLY` — slot 0 would walk to rank 1 itself, commit there,
# and `gambit_fired_at_slot(slot=1)` flips to a slot-0 failure while every other assertion in
# the file stays green. That is the whole diff, and it is one number.
#
# === THE TWO ALLIES ARE EQUIDISTANT, AND THE RANKS COME FROM C1'S TIE-BREAK ==================
#
# Both sit one tile from the Healer, east and west, and the rank order is the stable unit-id
# tie-break rule **C1** names: `find_unit_by_criteria` keeps the first strict minimum and
# `find_nth_nearest` selection-sorts the same way, so declaration order IS rank order here.
#
# Deliberate, and it replaces a fixture that put rank 1 two tiles out. THAT VERSION FAILED FOR A
# REASON THAT HAS NOTHING TO DO WITH THIS RULE, and the failure is worth writing down: with the
# wounded ally at distance 2 the Healer committed ONCE, at tick 61, and no heal landed on anyone
# by tick 300 — not on rank 1, and (asserted) not on rank 0 either, so it was not B7's
# target-hijack. Every distance-1 cast in this suite lands (B10c at tick 247, I2 at 246-253) and
# both distance-2 attempts produced a lone commit and no cast, which points at the cast-position
# search rather than at the rank walk. Equidistant ranks take that whole pathway out of a
# fixture whose subject is the CONDITION pass, where reach is not the question being asked.
#
# The two are 2 tiles apart, which matters: Cure's `effect_area` is 1, so neither cast splashes
# the other ally and a landing on rank 0 is distinguishable from a landing on rank 1.

static func _b10_strict_depth_does_not_retry() -> Dictionary:
	# THE STRICT ROW. `Nearest Ally` names ONE unit, and RankZero is at 75%, so the condition is
	# false and there is nowhere else for this slot to look.
	var slot0 := Gambit.create(
			TargetSelector.friendlies().with_resolution(
					TargetSelector.ResolutionStrategy.NEAREST_ONLY),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	# THE POOL ROW, and it is the control: byte-identical but for the resolution. Pass 2 retries
	# it past RankZero and reaches RankOne, one tile away on the other side — no walk intervenes,
	# so B7's open pathfind-hijack cannot reach this.
	var slot1 := Gambit.create(
			TargetSelector.friendlies().with_resolution(
					TargetSelector.ResolutionStrategy.NEAREST_FIRST),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B10",
		"name": "strict_depth_does_not_retry_past_rank_zero",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Healer", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 12, "ma": 12, "wp": 4, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0, slot1],
			},
			{
				# RANK 0. 150/200 = 75%: it fails HP<50%, which is what leaves the strict slot
				# with nothing to try — and it is DELIBERATELY not at full HP, so a heal that
				# landed here would show a positive delta instead of being capped away into an
				# absence that reads like "no cast happened".
				"name": "RankZero", "team": 0, "tile": [3, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0, "hp": 150,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				# RANK 1. 80/999 = 8%, and it stays under half after a Cure or two, so the pool
				# slot's condition does not go false underneath the assertion.
				"name": "RankOne", "team": 0, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0, "hp": 80,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				# Somebody has to be alive on team 1 or the battle is over before it starts.
				# Immobile, unarmed for practical purposes, and eight tiles away: nobody in this
				# fixture ever reaches it, so it changes no rank and no condition.
				"name": "Bystander", "team": 1, "tile": [8, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			# THE LOAD-BEARING ONE. Slot 1, not slot 0 — the strict row above it had a rank-0
			# candidate and rejected them, and did not go looking for a second.
			"gambit_slot": [{"unit": "Healer", "slot": 1}],
			# And not once across the WHOLE trace, not merely on the first commit. This
			# predicate fails rather than passes when the unit committed nothing at all, so it
			# cannot go green by the Healer being dead, silent or unencodable.
			"no_commit_at_slot": [{"unit": "Healer", "slot": 0}],
			# The commit came from an AUTHORED slot. Without this, a fixture whose gambits all
			# failed to encode would satisfy both assertions above from the injected net.
			"no_safety_net_hit": [{"unit": "Healer"}],
			# The positive half: rank 1 was actually REACHED and the sentence is runnable. An
			# absent heal here would mean both assertions above were describing a Healer that
			# never did anything, which is the blind-zero shape this pairing exists to rule out.
			# Paired with its own counter-assertion, because "rank 1 was healed" and "rank 0
			# was not healed instead" are two claims and B7 is open on exactly the second.
			"healing": [
				{"kind": "healing_applied_to", "target": "RankOne", "by_tick": 380},
				{"kind": "healing_applied_to", "target": "RankZero", "by_tick": 380,
					"expect_no_heal": true},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === B10c (control) ===================================================

static func _b10c_control_the_same_strict_row_fires_at_rank_zero() -> Dictionary:
	# B10's POSITIVE CONTROL, and it is the arm that keeps "the strict slot never fired" from
	# being a fact about a type that cannot fire AT ALL. A `TARGET_NEAREST_ALLY_ONLY` that
	# `select_target` answered -1 for, or that the encoder skipped as UNSUPPORTED, would satisfy
	# every one of B10's assertions perfectly.
	#
	# Same map, same tiles, same job, same stats, same two slots in the same order, same tick
	# budget. ONE difference: the 80 HP is on RankZero instead of RankOne, so rank 0 now PASSES
	# the condition — and the strict slot fires from slot 0, on the unit it named.
	var slot0 := Gambit.create(
			TargetSelector.friendlies().with_resolution(
					TargetSelector.ResolutionStrategy.NEAREST_ONLY),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	var slot1 := Gambit.create(
			TargetSelector.friendlies().with_resolution(
					TargetSelector.ResolutionStrategy.NEAREST_FIRST),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "B10",
		"name": "control_strict_depth_fires_when_rank_zero_passes",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Healer", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 12, "ma": 12, "wp": 4, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0, slot1],
			},
			{
				# THE ONE CHANGED PAIR OF FIELDS: the 80 HP is on RANK 0 now. Same tiles, same
				# order, same jobs, same everything else as B10.
				"name": "RankZero", "team": 0, "tile": [3, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0, "hp": 80,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				"name": "RankOne", "team": 0, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0, "hp": 150,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				"name": "Bystander", "team": 1, "tile": [8, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			# SLOT 0 — the strict row resolves, passes and fires. B10's slot-1 commit is
			# therefore a statement about the RETRY POLICY and not about the type being inert.
			"gambit_slot": [{"unit": "Healer", "slot": 0}],
			"no_safety_net_hit": [{"unit": "Healer"}],
			"healing": [{"kind": "healing_applied_to", "target": "RankZero", "by_tick": 380}],
		},
		"xfail": [],
		"xfail_reason": "",
	}
