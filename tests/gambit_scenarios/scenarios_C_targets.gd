extends RefCounted

## Rule group C — target resolution. See [code]docs/gambit-rules.md[/code].
##
## C-group witnesses how the shader picks WHICH unit a gambit acts on, given
## the slot's [code]condition_target[/code] and [code]action_target[/code]
## selectors. The fixed shape across every scenario: a single attacking actor
## with one or two candidate targets, slot 0 pinned to the rule under test,
## damage_dealt_to / no_damage_dealt_to as the witness — "who got hit" is the
## direct answer to "who did the selector resolve to."
##
## Why no_stuck is not asserted here:
##   C-group scenarios all spec-PASS today (no shader fix pending), and the
##   stuck-actor case (no candidate found) is covered by B1. Adding no_stuck
##   to every C scenario just duplicates B's coverage with no new signal.
##
## Why C3's SELF half uses a heal ability:
##   To prove SELF resolves to the actor we need a self-targeting action.
##   The only [code]Gambit.ActionKind[/code] that takes a non-actor target
##   meaningfully today is ABILITY; using Cure on a low-HP caster gives a
##   positive HP event on the actor — the cleanest "SELF was the target" witness.
##   The TRIGGERING half is split into a sibling scenario for symmetry with
##   the rule index (C3 covers both).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector



const ABILITY_CURE := 1            # mp_cost=6, range=4, vertical=1


static func scenarios() -> Array:
	return [
		_c1_nearest_tie_break_by_unit_id(),
		_c2_lowest_hp_picks_by_percent_not_absolute(),
		_c3_self_resolves_to_actor(),
		_c3_triggering_resolves_to_condition_pick(),
		_c4_action_target_triggering_forwards_condition_pick(),
		_c5_action_target_independent_selector_resolves_separately(),
	]


# === C1 ===============================================================

static func _c1_nearest_tie_break_by_unit_id() -> Dictionary:
	# Two enemies at IDENTICAL Manhattan distance from the actor (both at d=1).
	# Spec: ties broken by unit id, lower wins. The runner appends team0 first
	# then team1 in scenario-declaration order, so KnightA (declared before
	# KnightB) gets the lower unit_idx and the shader's find_unit_by_criteria
	# loop (strict `<` on best_val) keeps the first match. KnightA takes the
	# hit; KnightB does not.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "C1",
		"name": "nearest_enemy_ties_broken_by_unit_id",
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
				# Declared first → lower unit_idx → wins the tie.
				"name": "KnightA", "team": 1, "tile": [3, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Same Manhattan distance, higher unit_idx → loses the tie.
				"name": "KnightB", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
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
			"damage": [
				{
					"kind": "damage_dealt_to",
					"target": "KnightA", "by_tick": 150,
				},
				{
					"kind": "damage_dealt_to",
					"target": "KnightB", "by_tick": 150,
					"expect_no_damage": true,
				},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === C2 ===============================================================

static func _c2_lowest_hp_picks_by_percent_not_absolute() -> Dictionary:
	# Two enemies at EQUAL current HP (100) but very different max HP. The
	# MOST_CRITICAL resolution must pick by HP%, not absolute:
	#   BigKnight: 100/400 → 25%   ← lower percent, picked
	#   WeakKnight: 100/120 → 83%
	# If the shader compared absolute HP, neither candidate would be uniquely
	# "lower" (100 == 100) and the tie-break would land on unit_idx; we use
	# DIFFERENT distances so an accidental nearest-wins fallback would still
	# pick the wrong target (WeakKnight is closer). The witness is the same
	# either way: BigKnight takes damage first, WeakKnight does not.
	#
	# The `by_tick=80` window is narrow on purpose: after BigKnight's first
	# hit (tick ~35), it remains alive but the Wizard's next re-eval can
	# pivot — once one of either target dies, the surviving enemy gets
	# attacked next. Witnessing the FIRST pick is the load-bearing test for
	# C2; the post-kill pivot is downstream behavior and not part of the rule.
	var slot0_cond_target := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var slot0 := Gambit.create(
			slot0_cond_target,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "C2",
		"name": "most_critical_picks_by_hp_percent_not_absolute",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 14, "ma": 10, "wp": 4, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0],
			},
			{
				# Closer (d=1) BUT higher HP%; MOST_CRITICAL must NOT pick.
				"name": "WeakKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 120, "hp": 100, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Farther (d=2) but lower HP%; MOST_CRITICAL must pick this one.
				"name": "BigKnight", "team": 1, "tile": [3, 7],
				"job": "4c", "max_hp": 400, "hp": 100, "max_mp": 0,
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
					"target": "BigKnight", "by_tick": 80,
				},
				{
					"kind": "damage_dealt_to",
					"target": "WeakKnight", "by_tick": 80,
					"expect_no_damage": true,
				},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === C3 ===============================================================

static func _c3_self_resolves_to_actor() -> Dictionary:
	# condition_target=SELF + action_target=SELF on a Cure ability. The spec
	# half being tested: "SELF resolves to the actor." Witness:
	# gambit_fired_at_slot(slot=0) — the trace logger's `first_commit` fires
	# on any transition into an active state (ACTING / SPELL_CHARGING), which
	# is the cleanest "slot 0 committed to SELF" assertion. We don't pin a
	# trace.by_tick(...).committed(...) here because the assertion library's
	# ACTION_ANY only matches ACTING (not SPELL_CHARGING), and the Cure-on-
	# SELF path enters SPELL_CHARGING first; gambit_slot already captures
	# the commit tick in its detail message without needing the extra rail.
	#
	# Seeded HP=50/200 makes the SELF-Cure semantically meaningful (a
	# self-heal); the witness here is procedural, not numeric.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "C3",
		"name": "self_target_resolves_to_actor",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Priest", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "hp": 50, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0, slot1],
			},
			{
				# Out-of-range so the Priest never falls into an attack path —
				# pure SELF-witness on slot 0.
				"name": "DistantKnight", "team": 1, "tile": [3, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"gambit_slot": [{"unit": "Priest", "slot": 0}],
			"damage": [
				{
					# Priest must NOT take damage (no enemy in range). If a
					# regression made SELF resolve to "nearest enemy" the
					# DistantKnight would never reach the Priest either, so the
					# witness is asymmetric: Priest staying unhurt is necessary
					# but not sufficient. gambit_slot==0 is the load-bearing
					# assertion; this is a sanity counter.
					"kind": "damage_dealt_to",
					"target": "Priest", "by_tick": 200,
					"expect_no_damage": true,
				},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _c3_triggering_resolves_to_condition_pick() -> Dictionary:
	# action_target=TRIGGERING half of C3. condition_target selects an enemy
	# pool with NEAREST resolution → pass-1 picks NearestKnight. The
	# action_target marker TRIGGERING forwards that pick verbatim to the
	# action. Witness: NearestKnight is the one that takes damage. The
	# DistantKnight is there to prove the selector actually picked among
	# candidates rather than falling through to a default.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "C3",
		"name": "triggering_target_resolves_to_condition_pick",
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
				# Closer (d=1) — NEAREST picks this one; TRIGGERING forwards it.
				"name": "NearestKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Farther (d=3); must NOT take damage if TRIGGERING forwards
				# correctly.
				"name": "DistantKnight", "team": 1, "tile": [4, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
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
			"damage": [
				{
					"kind": "damage_dealt_to",
					"target": "NearestKnight", "by_tick": 150,
				},
				{
					"kind": "damage_dealt_to",
					"target": "DistantKnight", "by_tick": 150,
					"expect_no_damage": true,
				},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === C4 ===============================================================

static func _c4_action_target_triggering_forwards_condition_pick() -> Dictionary:
	# C4 zooms in on the case where condition_target's resolution would pick
	# DIFFERENTLY from a default-NEAREST action_target. We use MOST_CRITICAL
	# (lowest HP%) for condition_target so it lands on the FAR low-HP enemy;
	# action_target=TRIGGERING must forward THAT pick, not re-resolve to
	# nearest. Witness: the far low-HP enemy takes damage; the closer full-HP
	# enemy doesn't.
	#
	# Contrast with C5 (below), which holds the condition's pick identical but
	# flips action_target to NEAREST_ENEMY — the close enemy is hit instead.
	# The mirror pair pins the TRIGGERING-vs-independent distinction.
	#
	# Tile placement runs along z=7 — the known-walkable row B7 already uses.
	# An earlier draft placed FarLowHp at (4,4) on a different terrain band
	# where pathfinding from (4,7) stalled within the test window. Both
	# candidates on z=7 keeps the walk path simple and bounds the commit-by
	# tick to a comfortable window.
	var slot0_cond_target := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var slot0 := Gambit.create(
			slot0_cond_target,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "C4",
		"name": "action_target_triggering_forwards_lowhp_pick",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 14, "ma": 10, "wp": 4, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0],
			},
			{
				# Closer (d=1) but full HP. NEAREST would pick this; MOST_CRITICAL
				# does NOT. TRIGGERING must forward MOST_CRITICAL's pick.
				"name": "NearFullHp", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Farther (d=2) but 25% HP — MOST_CRITICAL picks this one.
				# Max HP bumped to 2000 so a single Wizard swing (~75 dmg)
				# doesn't one-shot FarLowHp; multiple swings keep MOST_CRITICAL
				# locked on the same target throughout the witness window
				# and stop the Wizard from re-picking NearFullHp once
				# FarLowHp dies.
				"name": "FarLowHp", "team": 1, "tile": [2, 7],
				"job": "4c", "max_hp": 2000, "hp": 500, "max_mp": 0,
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
					"target": "FarLowHp", "by_tick": 250,
				},
				{
					"kind": "damage_dealt_to",
					"target": "NearFullHp", "by_tick": 250,
					"expect_no_damage": true,
				},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === C5 ===============================================================

static func _c5_action_target_independent_selector_resolves_separately() -> Dictionary:
	# Mirror of C4: same unit layout (NearFullHp at d=1, FarLowHp at d=3,
	# 25% HP), same condition_target=MOST_CRITICAL ENEMIES — but action_target
	# carries a DIFFERENT selector (NEAREST_ENEMY). Spec: action_target with a
	# different selector resolves independently of the condition's pick. So the
	# attack lands on NearFullHp (NEAREST), even though the condition's pass
	# selected FarLowHp.
	#
	# This is the cleanest "independent resolution" witness: the same pool of
	# candidates yields different picks under different selectors, and the
	# action follows action_target's pick — not the condition's.
	var slot0_cond_target := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var slot0_action_target := TargetSelector.enemies()  # default NEAREST
	var slot0 := Gambit.create(
			slot0_cond_target,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			slot0_action_target)

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "C5",
		"name": "action_target_independent_selector_resolves_to_nearest",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 14, "ma": 10, "wp": 4, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0],
			},
			{
				# d=1 full HP — NEAREST picks this. Action lands here.
				"name": "NearFullHp", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# d=3, 25% HP — condition's MOST_CRITICAL picks this, but the
				# independent action_target re-resolves to NEAREST → not hit.
				"name": "FarLowHp", "team": 1, "tile": [4, 4],
				"job": "4c", "max_hp": 200, "hp": 50, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
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
			"damage": [
				{
					"kind": "damage_dealt_to",
					"target": "NearFullHp", "by_tick": 150,
				},
				{
					"kind": "damage_dealt_to",
					"target": "FarLowHp", "by_tick": 150,
					"expect_no_damage": true,
				},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}
