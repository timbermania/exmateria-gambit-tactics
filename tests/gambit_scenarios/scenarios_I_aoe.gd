extends RefCounted

## Rule group I — AoE / multi-target. See [code]docs/gambit-rules.md[/code].
##
## I-group witnesses what happens when an ability's [code]effect_area > 0[/code]
## causes a single chosen-target spell to hit (or heal) every unit within
## that Manhattan radius around the center. The fixed shape across the
## scenarios: an actor casts an AoE spell at one chosen target, and the
## scenario checks "which units took the hit / heal, and which did not."
##
## Why Fire is reused for I1 (vs picking a wider-radius spell):
##   Fire has [code]effect_area = 1[/code] and [code]charge_time = 4[/code],
##   so it routes through [code]cast_cinematic_spell[/code] (stage_spell.glsl
##   :515) — the cinematic per-target stamp path is the one the rule actually
##   describes ("picks one center target via [code]action_target_type[/code],
##   then hits every unit within radius"). Wider-radius spells use the same
##   code path; a tighter radius makes the fixture easier to author without
##   accidentally engulfing the caster.
##
## Why the caster team-filter doesn't need a separate witness:
##   The cinematic AoE walker at stage_spell.glsl :539-544 skips the caster's
##   own team when the ability isn't healing (and vice-versa for healing).
##   I1's not_targets list pins this: the Wizard is INSIDE the AoE radius
##   (Manhattan 1 from the Fire center), and the predicate asserts the
##   Wizard took no damage. If a regression dropped the team filter, the
##   Wizard would self-immolate and the not_targets check would catch it.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector



const ABILITY_CURE := 1            # mp_cost=6, ct=4, range=4, effect_area=1, healing
const ABILITY_FIRE := 16           # mp_cost=6, ct=4, range=4, effect_area=1, damaging


static func scenarios() -> Array:
	return [
		_i1_fire_aoe_hits_cluster_including_caster_misses_bystander(),
		_i2_cure_aoe_heals_enemy_in_radius_too(),
		_i3_cinematic_aoe_targets_fire_staggered(),
	]


# === I1 ===============================================================

static func _i1_fire_aoe_hits_cluster_including_caster_misses_bystander() -> Dictionary:
	# Wizard at (4,7) casts Fire on the nearest enemy. NearestEnemy resolves to
	# CenterKnight at (5,7) — Manhattan 1, the unambiguous closest. Fire's
	# AoE radius 1 then includes CenterKnight + the four Manhattan-1
	# neighbors, of which two are populated by EnemyN/EnemyS. BystanderFar
	# sits at (8,7) — Manhattan 3 from the center, outside the radius — and
	# is the negative-control witness.
	#
	# The Wizard at (4,7) is ALSO Manhattan 1 from the center, so it stands in its own
	# blast and takes the hit. That is the assertion now.
	#
	# It was the opposite until 2026-08-22, on the same stale premise as I2: this
	# comment used to read "the cinematic AoE walker (stage_spell.glsl :542-544) skips
	# the caster's own team when the ability is non-healing", and ADR-0049 (Accepted
	# 2026-06-18, two days after this file was written) retired that filter for the
	# ROM's `dont_hit_enemies` / `dont_hit_allies` / `dont_hit_caster` flags. Fire
	# (ability 16) has all three false, and the ADR's Consequences say it outright:
	# "FFT canon: friendly fire is on by default ... Fire on an ally tile damages the
	# ally." The single red verdict this scenario produced was `unexpected damage on:
	# 'Wizard'` — the caster, and nobody else. Not a stray hit; the decision.
	#
	# BystanderFar at (8,7) stays in not_targets and is untouched by any of this: it is
	# Manhattan 3 from the center, a GEOMETRIC negative control, which is the half of
	# this scenario that hit policy has no say over. Keeping it is what stops the
	# rewrite from turning "AoE has a radius" into an unasserted assumption.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_FIRE,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "I1",
		"name": "fire_aoe_hits_cluster_including_caster_misses_bystander",
		"map": "MAP042",
		"seed": 42,
		# Charge_time=4 + cinematic playback dominate; B4/B6's 100-tick
		# committed budget is too tight for a cinematic-path spell to land
		# damage. 400 matches H7's loose window.
		"max_ticks": 400,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 8, "ma": 14, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0],
			},
			{
				# Center of the AoE. Manhattan 1 from Wizard — unambiguous
				# nearest-enemy pick.
				"name": "CenterKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Manhattan 1 from center, in-radius hit.
				"name": "EnemyN", "team": 1, "tile": [5, 6],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Manhattan 1 from center, in-radius hit.
				"name": "EnemyS", "team": 1, "tile": [5, 8],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Manhattan 3 from center, OUT of radius. Negative-control.
				"name": "BystanderFar", "team": 1, "tile": [8, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 300,
				"unit": "Wizard", "committed": "ACTION_SPELL",
			}],
			"aoe_hits": [{
				"kind": "aoe_hits",
				"expected_targets": ["CenterKnight", "EnemyN", "EnemyS", "Wizard"],
				"not_targets": ["BystanderFar"],
				"by_tick": 400,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === I2 ===============================================================

static func _i2_cure_aoe_heals_enemy_in_radius_too() -> Dictionary:
	# Priest at (4,7) casts Cure on the most-injured ally — the gambit picks
	# WoundedKnight at (3,7) (HP 50/200 = 25%, the only candidate below the
	# 50% threshold). Cure's AoE radius 1 around (3,7) covers (3,7) itself
	# plus the four cardinal neighbors:
	#   (2,7) — NearbyEnemy (team 1)
	#   (4,7) — Priest (caster, team 0)
	#   (3,6) — WoundedScholar (team 0, hp 50/200)
	#   (3,8) — WoundedHealer (team 0, hp 50/200)
	#
	# EVERY unit in that radius is healed, the enemy included — that is FFT canon and
	# it is what this scenario now witnesses.
	#
	# It asserted the OPPOSITE until 2026-08-22, and was authored on 2026-06-16 against
	# a walker that "keeps only same-team units in the AoE". ADR-0049 (Accepted
	# 2026-06-18, two days later) retired that team filter: hit policy now reads the
	# ROM's `dont_hit_enemies` / `dont_hit_allies` / `dont_hit_caster` flags, and the
	# ADR's own Consequences name this exact case — "FFT canon: friendly fire is on by
	# default. Cure cast on an enemy tile heals the enemy; Fire on an ally tile damages
	# the ally." Cure (ability 1) has all three flags false in
	# `assets/abilities/ability_attributes.json`, and both AoE walkers
	# (`stage_spell.glsl` cast_cinematic_spell, `stage_damage.glsl` Phase 1) call
	# `hit_policy_allows`. So the heal on NearbyEnemy that this scenario reported as a
	# red verdict was the ADR being obeyed. The scenario was measuring a rule the
	# project had already decided against; it is inverted here rather than deleted,
	# because "an in-radius foe IS healed" is worth pinning — it is the surprising
	# direction, and it is the one a future team-lock toggle would break.
	#
	# NearbyEnemy sits at hp=200/999 precisely so the heal is OBSERVABLE: there is room
	# to heal without clamping to max_hp, so HP_CHANGED fires and the positive delta is
	# visible. The paired expect_no_damage stays — a heal must not arrive as damage.
	#
	# Priest at full HP IS in radius and IS same-team, so the orchestrator
	# applies the heal — but min(max_hp, current_hp + amount) clamps it to
	# max_hp and the interpreter's HP_CHANGED only fires when cur_hp differs
	# from prev. The Priest therefore stays out of healing_applied_to but is
	# silently fine; the predicate doesn't need to mention them.
	var slot0 := Gambit.create(
			TargetSelector.friendlies(),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "I2",
		"name": "cure_aoe_heals_enemy_in_radius_too",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Priest", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0],
			},
			{
				# Center pick (HP%-lowest ally adjacent). Manhattan 1 from
				# Priest, within range 4.
				"name": "WoundedKnight", "team": 0, "tile": [3, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0, "hp": 50,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				# Manhattan 1 from center, in-radius ally heal.
				"name": "WoundedScholar", "team": 0, "tile": [3, 6],
				"job": "4c", "max_hp": 200, "max_mp": 0, "hp": 50,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				# Manhattan 1 from center, in-radius ally heal.
				"name": "WoundedHealer", "team": 0, "tile": [3, 8],
				"job": "4c", "max_hp": 200, "max_mp": 0, "hp": 50,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				# Manhattan 1 from center, in-radius and on the ENEMY team — per
				# ADR-0049 the AoE walker heals them anyway. hp pre-set to 200
				# (out of 999) so the heal has somewhere to go: at full HP the
				# min(max_hp, ...) clamp would suppress HP_CHANGED and the event
				# would be invisible, making "healed" and "skipped" look identical
				# to the predicate. max_hp/hp split mirrors B7's BleedingKnight.
				"name": "NearbyEnemy", "team": 1, "tile": [2, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0, "hp": 200,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 300,
				"unit": "Priest", "committed": "ACTION_SPELL",
			}],
			"damage": [
				# NearbyEnemy is healed, not hurt. `damage_dealt_to` with
				# expect_no_damage filters only delta<0 events, so this pins the
				# SIGN: a Cure that reached an enemy as damage (an inverted
				# heal/damage branch, or the undead conversion firing on a living
				# unit) fails here while the positive `healing_applied_to` below
				# still passes. The pair is the load-bearing witness.
				{
					"kind": "damage_dealt_to", "target": "NearbyEnemy",
					"by_tick": 400, "expect_no_damage": true,
				},
			],
			"healing": [
				{"kind": "healing_applied_to", "target": "WoundedKnight", "by_tick": 400},
				{"kind": "healing_applied_to", "target": "WoundedScholar", "by_tick": 400},
				{"kind": "healing_applied_to", "target": "WoundedHealer", "by_tick": 400},
				# ADR-0049's named consequence, pinned: an in-radius ENEMY receives
				# the heal too. Friendly fire is symmetric — this is the assertion a
				# future team-lock toggle has to come back and change on purpose.
				{"kind": "healing_applied_to", "target": "NearbyEnemy", "by_tick": 400},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === I3 ===============================================================

static func _i3_cinematic_aoe_targets_fire_staggered() -> Dictionary:
	# Same fixture shape as I1, but witnessing the per-target stamp half of
	# the I3 rule instead of the per-target FIRE half.
	# cast_cinematic_spell at stage_spell.glsl :545-548 writes
	#   fire_frame = first_hit_frame + target_count * for_each_delay
	# per stamped target, so during the cinematic window (after stamp,
	# before fire) every target carries a DIFFERENT
	# aoe_pending_fire_frame. The predicate asserts those stamps are
	# pairwise distinct in a snapshot taken between stamp and fire.
	#
	# Why not assert the fire-tick spread directly: every effect timeline
	# in tree (401 files, all of them) ships for_each_delay = 1 PSX frame.
	# The runner samples per host frame at test_time_scale = 4.0, which
	# bundles ~4 IRQ ticks per frame, so three consecutive-tick fires fold
	# into one observed tick (all three hp_events carry the same
	# current_tick). The stamp witness catches the same regression — if the
	# per-target stride collapsed the stamps would equal — without needing
	# sub-frame interpreter sampling.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_FIRE,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "I3",
		"name": "cinematic_aoe_fires_per_target_staggered",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 8, "ma": 14, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0],
			},
			{
				"name": "CenterKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				"name": "EnemyN", "team": 1, "tile": [5, 6],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				"name": "EnemyS", "team": 1, "tile": [5, 8],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"aoe_stamps_differ": [{
				"kind": "aoe_stamps_differ",
				"targets": ["CenterKnight", "EnemyN", "EnemyS"],
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}
