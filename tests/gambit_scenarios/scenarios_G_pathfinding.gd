extends RefCounted

## Rule group G — pathfinding & terrain. See [code]docs/gambit-rules.md[/code].
##
## G1 — flat-axis Manhattan baseline (MAP042, jump=4 enough to absorb the z=4
## cliff via the x≥6 doorway).
##
## G2 — `|Δh| > jump` gates the per-step traversal check. Paired witnesses on
## MAP042's z=4 → z=5 wall (the cliff at columns x=3-5 has Δh=5, blocking any
## jump ≤ 4 from crossing those columns directly):
##
## - **G2a — low-jump detours**: Monk(jump=3) at (4, 3) attacks Knight at (5, 5).
##   Direct route (4,3)→(4,4)→(4,5) is blocked at (4,4)→(4,5) (Δh=5 > 3); same
##   for (5,4)→(5,5) (Δh=5 > 3) and (6,4)→(6,5) (Δh=4 > 3). The only z=4→z=5
##   doorway open to jump=3 is at x=7 (Δh=3 = jump). The pathfinder is forced
##   east to (7,4), climbs at (7,5), then walks back west across z=5/6 to an
##   attack tile adjacent to (5,5). Observed commit ~tick 227 (~8 walked steps
##   at ~28 ticks/step). Witness: ATTACK by tick 400 (leaves headroom for
##   pathfinder backtrack cost in the dead-end x=3,4,5,6 columns).
## - **G2b — high-jump steps direct**: same setup with Monk(jump=5). The
##   pathfinder takes the direct (4,3)→(4,4)→(4,5) route (Δh=5 ≤ jump) and
##   attacks from (4,5). Observed commit ~tick 108 (~3 walked steps).
##   Witness: ATTACK by tick 180 — tight enough to FAIL the east-doorway
##   detour (~227 ticks).
##
## The contrast is load-bearing in the G2b half: 180 ticks is too tight for
## the east-doorway detour but loose enough for the direct route, so G2b can
## only pass if the high-jump unit actually crossed the Δh=5 step. A
## regression that ignored jump on the per-step gate would still pass G2b
## (jump=5 unit doesn't care if it's checked) but would WRONGLY make G2a's
## detour disappear too — and since G2a's witness is just "commits eventually"
## (the predicate library has no "took the long way" expressivity), the G2a
## half degrades into a not-stuck check. That's still the right baseline: a
## regression that made jump=3 unreachable to the target (e.g. pathfinder
## gives up before finding the x=7 doorway) would silence G2a's commit and
## trip the witness. G2a is the "not stuck" half; G2b is the "actually used
## the high-jump" half.
##
## G3 — impassable tiles force the pathfinder to route around (`trace_stitched_path`
## with backtracking). Two witnesses on MAP100's row z=11 (the impassable
## pairs at x=5,6 and x=9,10 form natural 2-tile walls):
##
## - **G3a — west chokepoint**: Monk at (5, 10) attacks Knight at (5, 12).
##   Direct (5,10)→(5,11)→(5,12) is blocked at the impassable (5,11). The
##   pathfinder routes via (4,10)→(4,11)→(4,12) — Manhattan=2, actual=3.
##   Witness: ATTACK by tick 200.
## - **G3b — east chokepoint**: Monk at (10, 10) attacks Knight at (10, 12).
##   (10,11) is impassable; the detour is symmetric through (11,10)→(11,11)→
##   (11,12). Same 3-step detour, different position on the map, so a
##   chokepoint-detection regression localised to a coordinate range still
##   trips one or the other. Observed commit ~tick 93. Witness: ATTACK by
##   tick 200.
##
## Both G3 scenarios live on flat-enough terrain (heights 0-3 in the
## surrounding region) that the witness isolates impassable-handling from
## jump-handling.
##
## G4 — pass-through (allied tile is transparent for transit). On a flat-axis
## MAP042 row (z=4, heights 3-2-2-2-2-3 across x=3..8, jump=4 absorbing the
## ±1 Δh) an ally sits one tile east of the attacker, with an empty tile
## beyond. The pathfinder's [code]find_passthrough_destination[/code]
## returns the post-ally tile as the move-step destination, so
## [code]write_movement_step[/code] sets [code]U_PROPOSED_X[/code] to the
## post-ally tile — and the unit's per-tick snapshot
## [code]pos_x/pos_z[/code] jumps Manhattan-2 across the ally tile in one
## transition. The new [code]passes_through[/code] predicate witnesses
## that jump. Two scenarios per PRD acceptance:
##
## - **G4a — east pass-through**: Monk(jump=4) at (3,4) attacks enemy at
##   (7,4) with ally at (5,4). Observed commit ~tick 105; witness
##   [code]by_tick=180[/code]. Pass-through-broken regression would force
##   the unit to detour around (5,4) via z=3 or z=5 — z=5 is gated by Δh=5,
##   z=3 adds one step (~135 ticks) — and miss the budget.
## - **G4b — west pass-through**: geographic mirror, Monk at (8,4) attacks
##   enemy at (4,4) with ally at (6,4). Catches direction-asymmetric
##   pass-through bugs (e.g. a sign error in the scan-direction encoding).
##
## G5 — pass-through fails closed. On MAP100 row z=11 the impassable pair
## at x=5,6 sits one east of x=4. With an ally at (4,11), the scan east
## from x=3 finds the ally, calls [code]find_passthrough_destination[/code],
## walks (5,11) — which is impassable — and returns -1: the east direction
## is silently dropped, and the pathfinder must detour via z=10 or z=12.
## The negative form of [code]passes_through[/code] (with
## [code]expect_no_pass=true[/code]) witnesses that no Manhattan-≥2 jump
## across (4,11) ever happened.
##
## - **G5a — west chokepoint**: Monk(jump=4) at (3,11) attacks enemy at
##   (7,11). Ally at (4,11) flanked east by impassable (5,11). Detour
##   north via z=10 — ~5 steps, observed commit ~tick 180. Witness
##   [code]by_tick=300[/code] tight enough to fail any infinite stall.
##   The load-bearing assertion is [code]no_passes_through(Monk,
##   ally=[4,11])[/code] — a regression that ignored the impassable
##   filter and accepted (5,11) as a pass-through destination would land
##   the unit on (5,11) (Manhattan-2 jump across the ally) and trip this.
## - **G5b — east chokepoint**: geographic mirror at the x=9,10 impassable
##   strip. Monk at (7,11) attacks enemy at (11,11). Ally at (8,11)
##   flanked east by impassable (9,11). Same detour shape via z=10.
##
## G6 — reserved-tile contention. Reservation in this codebase is
## implemented by advancing [code]U_POS_X/Z[/code] at *move-start* (see
## [code]stage_resolve.glsl[/code] line 98: "CPU updates position at START
## of movement, not END"), so [code]get_tile_occupant[/code] — reading
## current [code]U_POS_X[/code] — immediately sees a moving unit at its
## destination. That's the "treated as occupied for pathfinding" half of
## G6. Two allies converge on the same nearest attack tile; the resolve
## pass picks one via lower-id tie-break, and on the very next tick the
## loser's [code]find_nearest_attack_position[/code] sees the winner's
## just-advanced position as occupied (line 288–289 of
## [code]stage_attack.glsl[/code]) and picks an alternate. Both commit
## ATTACK; a regression that ignored the mid-walk occupant would make the
## loser thrash on the contested tile and miss the tight budget.
##
## - **G6a — east-row contention on MAP042** (flat z=0/1 strip, all h=0
##   along x=4..9): Enemy at (6,0). Monk_A(unit 0) at (5,1) and Monk_B
##   (unit 1) at (7,1) are symmetric across the enemy — both pick (6,1)
##   as the nearest attack tile (Manhattan=1 each). Resolve gives (6,1)
##   to Monk_A (lower id), Monk_B replans next tick onto (7,0). Observed
##   commits ~tick 32 (Monk_A) / ~tick 70 (Monk_B); witness
##   [code]by_tick=180[/code] holds 100% headroom over Monk_B's commit
##   but fails any thrash cycle.
## - **G6b — north-row contention on MAP100** (z=3 flat region h=0 for
##   x=0..5): Enemy at (4,3). Monk_A(unit 0) at (3,4) and Monk_B(unit 1)
##   at (5,4) symmetric across enemy — both pick (4,4). Resolve gives
##   (4,4) to Monk_A; Monk_B replans onto (5,3). Same tick shape as G6a;
##   the MAP100 geometry catches map-localised regressions.
##
## G7 — no-thrash retry. The shader's
## [code]check_decision_thrash[/code] (stage_compute.glsl :348) walks the
## 6-entry decision ring buffer and sets bit 3 of
## [code]decision_meta[/code] (`thrash_flag`) when either the same target
## appears 3+ times across the 6 entries OR the last 3 entries cycle stuck
## reasons (NO_PATH / GAMBIT_FAILED / NO_GAMBIT) without any forward-
## progress entry between them. The new
## [code]no_thrash(unit, by_tick)[/code] predicate witnesses that the bit
## never flipped on within the window. Two scenarios cover the two retry
## archetypes:
##
## - **G7a — backtrack-heavy detour on jump=3 dead-end columns**: identical
##   positioning to G2a (Monk jump=3 at (4,3) attacks Knight at (5,5) on
##   MAP042). The east-doorway detour visits x=3,4,5,6 columns which are
##   dead-ends for jump=3 (Δh=5 wall to the north), so the pathfinder's
##   backtrack cost is empirically the highest of any G-scenario (~227
##   ticks for 8 steps). A regression in either the per-tick retry
##   bookkeeping or the ring-buffer write index could surface as a
##   spurious thrash_flag during the backtrack. Witness: no_thrash by tick
##   300 (tighter than G2a's 400-tick commit witness; post-commit the
##   Monk legitimately thrashes against the invincible 999-HP dummy
##   target, observed at tick ~392 — see the per-scenario docstring).
## - **G7b — reservation-contention retry**: identical positioning to G6a
##   (two allied Monks symmetric across an enemy on the MAP042 z=0/1
##   strip). Monk_B loses the contention for (6,1), reverts, and
##   re-decides at tick 1 — the canonical "retry without thrash" signal.
##   Witness: no_thrash on Monk_B by tick 180 (Monk_A is the contention
##   winner — see _g7b docstring for why it's excluded from the witness).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector



static func scenarios() -> Array:
	return [
		_g1_flat_terrain_manhattan_shortest_path(),
		_g2a_low_jump_detours_around_cliff(),
		_g2b_high_jump_steps_direct_over_cliff(),
		_g3a_impassable_west_chokepoint_forces_detour(),
		_g3b_impassable_east_chokepoint_forces_detour(),
		_g4a_east_pass_through_ally(),
		_g4b_west_pass_through_ally(),
		_g5a_pass_through_fails_closed_west(),
		_g5b_pass_through_fails_closed_east(),
		_g6a_two_allies_contend_for_same_attack_tile_map042(),
		_g6b_two_allies_contend_for_same_attack_tile_map100(),
		_g7a_no_thrash_in_jump3_dead_end_backtrack(),
		_g7b_no_thrash_during_reservation_retry(),
	]


# === Helpers ==================================================================

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


# === G1 =======================================================================

static func _g1_flat_terrain_manhattan_shortest_path() -> Dictionary:
	# Wide L-shape on MAP042: Monk at (2, 4), Knight at (8, 8). Manhattan
	# distance = |8-2| + |8-4| = 10 tiles. Multiple shortest paths exist (any
	# ordering of 6 east-steps + 4 north-steps), all of which are 10 steps; a
	# pathfinder that detours adds extra steps. weapon_range=1 so the Monk
	# must reach an adjacent attack tile before swinging.
	#
	# Budget: ~35 ticks/step × 10 steps + ~50 swing-setup slack ≈ 400 ticks
	# (observed commit ~tick 356 on the 1d isometric path). by_tick=1050 is
	# loose — a regression that introduced a several-step detour or stalled
	# the pathfinder would still need to fail this. max_ticks=1200 caps
	# runaway scenarios.
	#
	# Tick-budget-as-proxy caveat: the (2,4)=9 → (3,4)=3 step has Δh=6 (>jump=4),
	# so the actual path goes (2,4)→(2,5)→(3,5)→(4,5)→… traversing z=5 across
	# instead of z=4. Still 10 steps because of the lucky parallel-axis geometry.
	# G2 below witnesses the jump rule directly.
	return {
		"rule": "G1",
		"name": "flat_terrain_manhattan_shortest_path",
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


# === G2 — jump limit ==========================================================

static func _g2a_low_jump_detours_around_cliff() -> Dictionary:
	# MAP042 z=4 → z=5 cliff at x=3-5 (Δh=5). Monk(jump=3) starts at low
	# ground (4,3) h=2; Knight target sits on top of the cliff at (5,5) h=7.
	# Attack tiles adjacent to (5,5): (4,5)=7, (5,6)=7, (6,5)=6, (5,4)=2.
	#   - (5,4) blocks the attack-range check too (|2-7|=5 > jump=3), so
	#     standing south of the target doesn't help.
	#   - The other three attack tiles all sit on the upper plateau, so the
	#     unit must cross the z=4→z=5 wall to reach any of them.
	#
	# Open doorways z=4→z=5 by jump value:
	#   jump=3: x=7 (Δh=3) and x=8/9 (Δh=1/0) — east doorway only.
	#   jump=4: above + x=6 (Δh=4) — still east-side.
	#   jump=5+: above + x=3,4,5 (Δh=5) — anywhere across the cliff face.
	#
	# So jump=3 from (4,3) is forced east to ~(7,4), climbs at (7,5), and
	# walks back west on z=5/6 to an attack tile. Rough path:
	#   (4,3) → (5,3) → (6,3) → (7,3) → (7,4) → (7,5) → (7,6) → (6,6) → (5,6)
	# 8 steps; attack from (5,6). Observed commit ~tick 227 (~28 ticks/step).
	# by_tick=400 leaves ~70% headroom for pathfinder backtrack cost in the
	# dead-end x=3,4,5,6 columns; max_ticks=600 caps runaway.
	#
	# What this witnesses: jump=3 is not stuck — the pathfinder finds the
	# east doorway and reaches the target. Couples with G2b below to show the
	# jump value materially gates the route (G2b's tight budget can only be
	# hit by the direct path).
	return {
		"rule": "G2",
		"name": "low_jump_detours_around_cliff",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 600,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 3],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [5, 5],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 400,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Knight",
				"max_dist": 1, "by_tick": 400,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _g2b_high_jump_steps_direct_over_cliff() -> Dictionary:
	# Identical positioning to G2a — Monk at (4, 3), Knight at (5, 5) — but
	# Monk has jump=5. The Δh=5 step (4,4) h=2 → (4,5) h=7 is now within
	# range, opening the direct 2-step path (4,3)→(4,4)→(4,5), attack from
	# (4,5) at Δh=0 to target. Observed commit ~tick 108 (~3 walked steps).
	#
	# by_tick=180 is the load-bearing half of the G2 pair: it's tight enough
	# that the 8-step east-doorway detour (~227 ticks empirically) would
	# FAIL. So this scenario passes only if the pathfinder actually used the
	# Δh=5 direct step, which is exactly what G2's per-step jump check is
	# supposed to permit when jump ≥ Δh. A regression that disabled the
	# high-jump path (e.g. switched the check to a fixed cap) would force
	# jump=5 to detour like jump=3 and miss this budget.
	#
	# max_ticks=300 — leaves headroom above the witness for a NORAN signal
	# rather than a hard cut-off if the detour does happen.
	return {
		"rule": "G2",
		"name": "high_jump_steps_direct_over_cliff",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 3],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 5,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [5, 5],
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
				"unit": "Monk", "committed": "ATTACK",
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Knight",
				"max_dist": 1, "by_tick": 180,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === G3 — impassable detour ===================================================

static func _g3a_impassable_west_chokepoint_forces_detour() -> Dictionary:
	# MAP100 row z=11 has an impassable pair at x=5,6 (between walkable
	# x=0-4 and x=7-8). Monk at (5, 10), Knight at (5, 12). Manhattan = 2;
	# the direct path (5,10)→(5,11)→(5,12) hits the impassable (5,11) and
	# the pathfinder routes via (4,10) h=0 → (4,11) h=2 → (4,12) h=0 →
	# attack (5,12) from (4,12). 3 walked steps, attack from a tile
	# adjacent to the target. Heights along this detour are 0,0,2,0 (flat
	# enough that jump=4 absorbs them without question), so the witness
	# isolates impassable-handling from any height-step interaction.
	#
	# Budget: 3 × ~30 + ~30 swing slack ≈ 120 ticks observed. by_tick=200
	# gives headroom for the backtrack on the failed (5,11) probe;
	# max_ticks=400.
	#
	# What this witnesses: trace_stitched_path's `is_tile_traversable`
	# filter actually rejects impassable tiles and the backtrack found the
	# legal route. A regression that ignored the traversable bit would let
	# the unit "walk through" (5,11) and reach the target in 2 steps, which
	# the predicate library can't distinguish from a legal 3-step detour —
	# so G3 is, like G1, primarily a load-bearing it-doesn't-get-stuck
	# witness. The G3b mirror below catches localised coordinate bugs that
	# wouldn't trip this scenario.
	return {
		"rule": "G3",
		"name": "impassable_west_chokepoint_forces_detour",
		"map": "MAP100",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [5, 10],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [5, 12],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 200,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Knight",
				"max_dist": 1, "by_tick": 200,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _g3b_impassable_east_chokepoint_forces_detour() -> Dictionary:
	# MAP100 row z=11 also has a second impassable pair at x=9,10. Monk at
	# (10, 10), Knight at (10, 12). Same 2-tile Manhattan, same forced
	# 3-step detour shape — this time the pathfinder routes east via
	# (11,10) h=0 → (11,11) h=0 → (11,12) h=2 → attack (10,12) from (11,12).
	# Heights in this corner read 0/0/0/2/0/2 along the candidate route
	# (terrain barely matters).
	#
	# Why two G3 scenarios for the same shape: PRD acceptance asks for ≥2.
	# Geographically-distinct chokepoints catch coordinate-localised
	# regressions a single witness can miss (e.g. an off-by-one in the
	# is_tile_traversable lookup that flips only on the east half of the
	# map). The G3 pair is the matching-shape "spot-check both sides"
	# pattern; G4-G7 will introduce shape variety once their predicates
	# land.
	#
	# Budget: same as G3a — 3-step detour, ~120 tick target, by_tick=200.
	# Observed commit ~tick 93.
	return {
		"rule": "G3",
		"name": "impassable_east_chokepoint_forces_detour",
		"map": "MAP100",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [10, 10],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [10, 12],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 200,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Knight",
				"max_dist": 1, "by_tick": 200,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === G4 — pass-through allied ================================================

static func _g4a_east_pass_through_ally() -> Dictionary:
	# MAP042 z=10 between x=3 and x=8 is flat-enough for jump=4: heights
	# 3,2,2,2,2,3. Monk(team 0) at (3,10), Ally Knight(team 0) at (5,10),
	# Enemy Knight(team 1) at (7,10). Attack tile (6,10) is the nearest of
	# the four enemy-adjacents — Manhattan=3 from start.
	#
	# THE ROW MOVED, THE MAP DID NOT (2026-08-22). This scenario and its west
	# mirror were authored on 2026-06-16 against z=4, and the heights quoted above
	# — 3,2,2,2,2,3 — are still EXACTLY right, but they are the z=10 row now.
	# ADR-0052 landed on 2026-06-24 and made the terrain exporter mirror the depth
	# axis (`renumber_tile_z` + the row reversal in
	# `tools/fft_exporter/exporters/terrain.py`), so on a re-export every tile moved
	# from z to 14-z. `assets/maps/` is gitignored, so nothing moved until someone
	# re-ran the exporter — and then this pair went red on terrain that no longer
	# had a flat corridor at z=4 (it is 9,9,13,13,7,7 there, a 4-step wall the Monk
	# routes around, so it never reached the attack tile inside the tick budget and
	# never made the Manhattan-2 pass-through step). The fix is the mirror, z -> 14-z;
	# the layout, the heights and the whole argument below are unchanged.
	#
	# Expected get_next_step sequence:
	#   (3,10) → (4,10)             normal step east, Δh=1 (within jump=4)
	#   (4,10) → ally at (5,10):    scan east enters find_passthrough_destination,
	#                               finds (6,10) empty + traversable + Δh=0
	#                               → returns (6,10). Best move-step destination
	#                               becomes (6,10); write_movement_step proposes
	#                               (6,10) directly (Manhattan-2 from (4,10)).
	#   (6,10): can_attack_target → true; setup_attack_animation; ACTING.
	#
	# Snapshot positions over time: …(3,10) → (4,10) → (6,10)… The Manhattan-2
	# jump (4,10)→(6,10) with ally tile (5,10) on the axis-aligned segment is
	# the passes_through witness.
	#
	# Budget: 2 move-step ticks (each ~30 ticks: ~30 + ~30) + ~30 setup ≈
	# ~90 observed. by_tick=180 keeps headroom for the brief
	# walking-state setup before the first decision tick — but tight
	# enough that the broken-pass-through fallback (forced detour via
	# z=3) would not fit.
	#
	# Why this is load-bearing: a regression that disabled pass-through
	# would force the unit to detour around (5,10) via z=9, adding one
	# step to the route — the Monk would attack ~tick 135 instead of
	# ~105, missing this budget. Combined with the explicit
	# passes_through(ally=[5,4]) witness, both axis-aligned step-count
	# regressions AND silently-different-route regressions are caught.
	return {
		"rule": "G4",
		"name": "east_pass_through_ally",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [3, 10],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Ally", "team": 0, "tile": [5, 10],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
			{
				"name": "Enemy", "team": 1, "tile": [7, 10],
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
				"unit": "Monk", "committed": "ATTACK",
			}],
			"passes_through": [{
				"unit": "Monk", "ally_tile": [5, 10], "by_tick": 180,
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Enemy",
				"max_dist": 1, "by_tick": 180,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _g4b_west_pass_through_ally() -> Dictionary:
	# Geographic mirror of G4a on the same z=10 row. Monk(team 0) at (8,10)
	# h=3, Ally(team 0) at (6,10) h=2, Enemy(team 1) at (4,10) h=2.
	# Path: (8,10) → (7,10) Δh=1 normal step west, then (7,10) → ally at
	# (6,10): scan west pass-through finds (5,10) empty → next step lands
	# at (5,10). Attack (4,10) from (5,10) (Δh=0).
	#
	# Moved from z=4 to z=10 with G4a — see the ADR-0052 depth-mirror note there.
	#
	# Why mirror: catches direction-asymmetric pass-through bugs —
	# scan_adjacent_moves loops over ivec2[4] dirs = {(0,1), (1,0),
	# (0,-1), (-1,0)} and feeds the dir into find_passthrough_destination's
	# tile-walk increment. A sign or component-swap error in the
	# direction encoding could silently break only east-bound or only
	# west-bound pass-through; G4a alone wouldn't surface it.
	return {
		"rule": "G4",
		"name": "west_pass_through_ally",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [8, 10],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Ally", "team": 0, "tile": [6, 10],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
			{
				"name": "Enemy", "team": 1, "tile": [4, 10],
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
				"unit": "Monk", "committed": "ATTACK",
			}],
			"passes_through": [{
				"unit": "Monk", "ally_tile": [6, 10], "by_tick": 180,
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Enemy",
				"max_dist": 1, "by_tick": 180,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === G5 — pass-through fails closed ==========================================

static func _g5a_pass_through_fails_closed_west() -> Dictionary:
	# MAP100 row z=3 walkability `.....##..##....` — impassables at
	# x=5,6 and x=9,10. With ally(team 0) at (4,3) h=0 and impassable
	# (5,3) directly east, the scan from (3,3) east-then-pass-through
	# walks into (5,3) inside find_passthrough_destination, fails the
	# is_tile_traversable check (line 121 of stage_attack.glsl), and
	# returns ivec2(-1,-1). The east direction is silently dropped from
	# scan_adjacent_moves' candidates; the pathfinder picks the cheapest
	# remaining direction — the z=4 row — and walks the 5-step detour
	# (3,3)→(3,4)→(4,4)→(5,4)→(6,4)→(7,4) attack (7,3) from (7,4).
	#
	# THE ROW MOVED, THE MAP DID NOT (2026-09-06). This pair was authored
	# against z=11/z=10 and every height and impassable it quoted was correct
	# — for the PRE-MIRROR export. ADR-0052 landed on 2026-06-24 and made the
	# terrain exporter mirror the depth axis (`renumber_tile_z` + the row
	# reversal in `tools/fft_exporter/exporters/terrain.py`), so on a re-export
	# every tile moved from z to 14-z. G4 was mirrored for this on 2026-08-22
	# (see the note in _g4a_east_pass_through_ally); G5 was missed. At z=11 the
	# units stood on `...............` — flat, fully open, with NOTHING to fail
	# closed against — so the scenario turned on tie-breaking between equally
	# good directions and flipped run to run. `assets/maps/` is gitignored, so
	# the drift was silent and per-machine. Every coordinate below is now
	# verified against the shipped terrain.json rather than against this
	# comment's ancestor:
	#
	#   z=3  imp=.....##..##....   h=000002312463444
	#   z=4  imp=.##............   h=013011112233344
	#
	# Heights along the detour: the z=4 row is `013011112233344`, so
	# (3,4)=0, (4,4)=1, (5,4)=1, (6,4)=1, (7,4)=1 — all jump=4
	# absorbs trivially. Target (7,3) h=1 reached from (7,4) Δh=0.
	#
	# Why (7,4) is the attack tile: find_nearest_attack_position loops
	# dirs[4]={(0,1),(1,0),(0,-1),(-1,0)} applied to the enemy at (7,3),
	# yielding (7,4) h=1, (8,3) h=2, (7,2) h=1 and (6,3) — the last
	# impassable and skipped. The first three are all Manhattan-5 from
	# (3,3); the strict `<` at line 292 keeps the first, (7,4).
	#
	# Witness: no_passes_through(Monk, ally=[4,3]) — a regression that
	# ignored is_tile_traversable in find_passthrough_destination would
	# accept (5,3) (or, depending on the bug, a tile further along)
	# as the pass-through destination, propose a move-step into an
	# impassable, and either land the unit on the impassable (Manhattan-2
	# snapshot jump across ally) or cycle on path-retry. Either failure
	# mode shows up as a Manhattan-≥2 transition across (4,3) and trips
	# the expect_no_pass=true assertion.
	#
	# Budget: 5 detour steps + attack setup. MEASURED on the mirrored terrain,
	# three G-family runs on 2026-09-06: G5a commits at tick 154 and G5b at
	# tick 178, both identical to the tick in all three runs (the ±2 jitter is
	# in `reached_within`, not in the commit). by_tick=300 is therefore ~95%
	# headroom over G5a and ~69% over G5b, and still fails any infinite stall.
	# max_ticks=600 caps runaway in case of regression. The "~180 observed"
	# this replaced was an estimate carried over from the un-mirrored rows.
	return {
		"rule": "G5",
		"name": "pass_through_fails_closed_west",
		"map": "MAP100",
		"seed": 42,
		"max_ticks": 600,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [3, 3],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Ally", "team": 0, "tile": [4, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
			{
				"name": "Enemy", "team": 1, "tile": [7, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 300,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"passes_through": [{
				"unit": "Monk", "ally_tile": [4, 3],
				"by_tick": 300, "expect_no_pass": true,
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Enemy",
				"max_dist": 1, "by_tick": 300,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _g5b_pass_through_fails_closed_east() -> Dictionary:
	# Geographic mirror at MAP100's east impassable strip (x=9,10 on
	# z=3). Monk at (7,3) h=1, Ally(team 0) at (8,3) h=2, Enemy(team 1)
	# at (11,3) h=3. Scan east from (7,3): adjacent (8,3)=ally →
	# find_passthrough_destination walks east → (9,3) impassable →
	# returns -1, east direction dropped. Detour via z=4:
	# (7,3)→(7,4)→(8,4)→(9,4)→(10,4)→(11,4) attack (11,3) from
	# (11,4). z=4 heights along the detour: (7,4)=1, (8,4)=2,
	# (9,4)=2, (10,4)=3, (11,4)=3 — step deltas 0,1,0,1,0, all
	# absorbed by jump=4. (11,4) is the attack tile for the same
	# dirs[4]-order-plus-strict-`<` reason given in G5a: (11,4),
	# (12,3) and (11,2) are all Manhattan-5 from (7,3), (10,3) is
	# impassable, and the first candidate wins.
	#
	# Moved from z=11/z=10 to z=3/z=4 with G5a — see the ADR-0052 depth-mirror
	# note there. Every coordinate here is verified against the shipped
	# terrain.json.
	#
	# Why mirror G5b after G5a: same direction-asymmetry argument as the
	# G3 pair and G4 pair — a regression localised to one quadrant of
	# the map (e.g. an off-by-one in the impassable lookup that
	# manifests only at x≥9) would trip G5b while G5a passes.
	return {
		"rule": "G5",
		"name": "pass_through_fails_closed_east",
		"map": "MAP100",
		"seed": 42,
		"max_ticks": 600,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [7, 3],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Ally", "team": 0, "tile": [8, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
			{
				"name": "Enemy", "team": 1, "tile": [11, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 300,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"passes_through": [{
				"unit": "Monk", "ally_tile": [8, 3],
				"by_tick": 300, "expect_no_pass": true,
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Enemy",
				"max_dist": 1, "by_tick": 300,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === G6 — reserved-tile contention ===========================================

static func _g6a_two_allies_contend_for_same_attack_tile_map042() -> Dictionary:
	# Reservation is implemented by advancing U_POS_X/Z at *move-start*
	# (stage_resolve.glsl:98 "CPU updates position at START of movement,
	# not END"). The consequence: as soon as the resolve pass picks a
	# winner for a contended destination, the winner's U_POS_X jumps to
	# that tile, and every other unit's pathfinder — reading current
	# U_POS_X via get_tile_occupant — immediately sees the tile as
	# occupied. The loser's stage_attack at the next tick avoids the
	# contested tile and picks an alternate.
	#
	# Setup: MAP042 flat z=0/1 strip (heights are 0 along x=4..9 for both
	# rows — `0033000000` for z=0 and z=1). Enemy at (6,0) h=0 with no
	# move. Two allied Monks symmetric to the enemy across the (6,1)
	# axis:
	#   - Monk_A (team 0, unit_id 0) at (5,1) h=0
	#   - Monk_B (team 0, unit_id 1) at (7,1) h=0
	# find_nearest_attack_position loops dirs[4]={(0,1),(1,0),(0,-1),
	# (-1,0)} applied to target (6,0):
	#   - (6,1) h=0 valid; Manhattan dist from (5,1)=1, from (7,1)=1
	#   - (7,0) h=0 valid; dist from (5,1)=3, from (7,1)=1
	#   - (6,-1) off-map → !is_tile_traversable → skip
	#   - (5,0) h=0 valid; dist from (5,1)=1, from (7,1)=3
	# Loop builds best_pos by strict < (line 292): both Monks land on
	# best=(6,1) (first dist=1 candidate visited; later dist=1 tiles
	# become candidates but don't displace best). At tick 0 both propose
	# (6,1); stage_resolve sees a destination tie (both dist=1 from
	# (6,1)), lower unit_id wins → Monk_A gets (6,1), Monk_B's
	# proposal reverts, TIMER=1 retry. At tick 1 Monk_B re-runs scan:
	# get_tile_occupant(6,1) now returns Monk_A → line 289 skips that
	# candidate; best falls through to (7,0) dist=1. Monk_B walks (7,1)
	# → (7,0), attacks.
	#
	# Witnesses:
	#   - by_tick(Monk_A, ATTACK, 180): Monk_A's commit (arrives at
	#     (6,1) + setup). ~tick 32 observed.
	#   - by_tick(Monk_B, ATTACK, 180): Monk_B's commit. The
	#     load-bearing assertion — a regression where get_tile_occupant
	#     ignored mid-walk position updates would make Monk_B propose
	#     (6,1) every retry-tick, get blocked every resolve pass, and
	#     never commit. ~tick 70 observed.
	#   - gambit_slot for both: both attacks fire from slot 0 (sanity).
	#
	# Budget: 180 ticks gives ~2.5× headroom over Monk_B's empirical
	# commit but fails any persistent thrash. max_ticks=400 caps runaway.
	return {
		"rule": "G6",
		"name": "two_allies_contend_for_same_attack_tile_map042",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk_A", "team": 0, "tile": [5, 1],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Monk_B", "team": 0, "tile": [7, 1],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Enemy", "team": 1, "tile": [6, 0],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [
				{"kind": "by_tick", "tick": 180,
				 "unit": "Monk_A", "committed": "ATTACK"},
				{"kind": "by_tick", "tick": 180,
				 "unit": "Monk_B", "committed": "ATTACK"},
			],
			"position": [
				{"kind": "reached_within", "unit": "Monk_A",
				 "target": "Enemy", "max_dist": 1, "by_tick": 180},
				{"kind": "reached_within", "unit": "Monk_B",
				 "target": "Enemy", "max_dist": 1, "by_tick": 180},
			],
			"gambit_slot": [
				{"unit": "Monk_A", "slot": 0},
				{"unit": "Monk_B", "slot": 0},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _g6b_two_allies_contend_for_same_attack_tile_map100() -> Dictionary:
	# Geographic mirror of G6a on MAP100. Row z=3 of MAP100 is fully
	# walkable with heights `000000111122233` (x=0..5 are h=0); z=4 is
	# `000001111122233` (x=0..3 h=0, x=4 h=1, x=5 h=1). Enemy at (4,3)
	# h=0; allied Monks symmetric to the enemy across (4,4):
	#   - Monk_A (team 0, unit_id 0) at (3,4) h=0
	#   - Monk_B (team 0, unit_id 1) at (5,4) h=1
	# Attack tiles around (4,3) by loop order applied to target:
	#   - (4,4) h=1 valid; Δh=1 ≤ jump=4. Dist from (3,4)=1, from (5,4)=1.
	#   - (5,3) h=1 valid; Δh=1. Dist from (3,4)=3, from (5,4)=1.
	#   - (4,2) h=0 valid; Δh=0. Dist from (3,4)=3, from (5,4)=3.
	#   - (3,3) h=0 valid; Δh=0. Dist from (3,4)=1, from (5,4)=3.
	# Monk_A: best=(4,4) (first dist=1); (3,3) dist=1 displaces only by
	# strict <, so stays as candidate. Monk_B: best=(4,4) (first dist=1);
	# (5,3) dist=1 stays as candidate. Both want (4,4); tie at resolve;
	# Monk_A wins; Monk_B retries at tick 1, sees Monk_A at (4,4) via
	# get_tile_occupant, falls through to its (5,3) candidate.
	#
	# Why the MAP100 mirror: catches map-localised regressions in
	# get_tile_occupant or in resolve_conflicts that wouldn't trip the
	# MAP042 version (e.g. an off-by-one keyed to map width — MAP042 is
	# 10×15, MAP100 is 15×15).
	#
	# Budget: 180 ticks — same shape, same empirical-commit assumptions
	# as G6a (Monk_A's step (3,4)→(4,4) crosses Δh=1, Monk_B's eventual
	# (5,4)→(5,3) likewise). max_ticks=400.
	return {
		"rule": "G6",
		"name": "two_allies_contend_for_same_attack_tile_map100",
		"map": "MAP100",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk_A", "team": 0, "tile": [3, 4],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Monk_B", "team": 0, "tile": [5, 4],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Enemy", "team": 1, "tile": [4, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [
				{"kind": "by_tick", "tick": 180,
				 "unit": "Monk_A", "committed": "ATTACK"},
				{"kind": "by_tick", "tick": 180,
				 "unit": "Monk_B", "committed": "ATTACK"},
			],
			"position": [
				{"kind": "reached_within", "unit": "Monk_A",
				 "target": "Enemy", "max_dist": 1, "by_tick": 180},
				{"kind": "reached_within", "unit": "Monk_B",
				 "target": "Enemy", "max_dist": 1, "by_tick": 180},
			],
			"gambit_slot": [
				{"unit": "Monk_A", "slot": 0},
				{"unit": "Monk_B", "slot": 0},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === G7 — no-thrash retry =====================================================

static func _g7a_no_thrash_in_jump3_dead_end_backtrack() -> Dictionary:
	# Monk(jump=3) at (4,11) attacks Knight at (5,9) on MAP042. The pathfinder is
	# forced east via the x=7 doorway (the only z=10→z=9 opening that absorbs
	# jump=3) and walks back west across z=9/8. What makes this the right G7
	# geometry: x=3,4,5,6 form a dead-end column for jump=3 — the unit can stand on
	# those tiles at z=11,10 but cannot climb out northward (the Δh=5 wall closes
	# those columns), so any A*-style exploration that strays into them must
	# backtrack. Empirically the commit lands ~tick 227, so the backtrack is not
	# free — it's the highest-cost successful path in the G-group.
	#
	# MIRRORED z -> 14-z on 2026-08-22, for the ADR-0052 depth flip described on
	# _g4a_east_pass_through_ally. This scenario was authored at (4,3)/(5,5), and every
	# claim in the paragraph above is still exactly true of the terrain — of the z=10/z=9
	# rows. Check it against `assets/maps/MAP042/terrain.json`: the z=10 -> z=9 climbs are
	# Δ5, Δ5, Δ5, Δ4 at x=3,4,5,6 and Δ3 at x=7, so x=7 is the doorway and 3..6 is the
	# dead end, precisely as written. At the un-mirrored z=4/z=5 the same columns are
	# 9,9,13,13 against 9,9,11,11 — no wall, no doorway, no dead end, and the Monk
	# thrashed on NO_PATH at tick 239 instead of committing at ~227.
	#
	# NOTE: the header used to open "Same positioning as G2a". That is no longer true —
	# G2a and G2b still sit at (4,3)/(5,5). They are not mirrored here because they are
	# GREEN on the current terrain and this pass is not licensed to gamble greens; their
	# prose describes the pre-flip map the same way G1's does ("the (2,4)=9 -> (3,4)=3
	# step has Δh=6" is a z=10 fact, not a z=4 one), so the whole G file wants a
	# deliberate mirror sweep with a full run behind it.
	#
	# What this witnesses: even with the most backtrack-prone successful
	# geometry in the suite, `check_decision_thrash` never sets bit 3 of
	# decision_meta. The thrash detector trips on two patterns: (a) same
	# target appearing 3+ times in the 6-entry ring, or (b) the last 3
	# entries cycling stuck reasons (NO_PATH / GAMBIT_FAILED / NO_GAMBIT)
	# without forward-progress entries between them. A G2a-shape run emits
	# START_MOVING entries each step (forward-progress reason), so neither
	# pattern fires — but a regression in the ring-buffer write index, or
	# in the per-tick retry's reason-tagging, could falsely flip the bit.
	#
	# Budget: by_tick=400 mirrors G2a's commit witness window. The
	# no_thrash assertion is intentionally tighter at by_tick=300 — the
	# observed commit is ~tick 221, and once the Monk reaches the target
	# the gambit's per-tick re-evaluation against an invincible (999 HP)
	# dummy Knight eventually accumulates stuck reasons (the Monk can't
	# kill it, the attack cooldown gates re-fires) and the thrash_flag
	# legitimately sets in the post-commit stalemate — observed at tick
	# 392 here. That post-commit thrash is the "invincible dummy" rig
	# artifact, not the G7 rule failing: G7 concerns retry DURING the
	# approach to a commit, which the tighter window witnesses with
	# ~80-tick headroom past the empirical commit. max_ticks=600.
	return {
		"rule": "G7",
		"name": "no_thrash_in_jump3_dead_end_backtrack",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 600,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 11],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Knight", "team": 1, "tile": [5, 9],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 400,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"no_thrash": [{
				"unit": "Monk", "by_tick": 300,
			}],
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Knight",
				"max_dist": 1, "by_tick": 400,
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _g7b_no_thrash_during_reservation_retry() -> Dictionary:
	# Same positioning as G6a — two allied Monks at (5,1) and (7,1)
	# contending for (6,1) as the nearest attack tile against Enemy at (6,0)
	# on the MAP042 z=0/1 flat strip. Monk_A wins the resolve tie via
	# lower unit_id, jumps U_POS_X to (6,1) at tick 0; Monk_B's proposal
	# reverts and stage_attack at tick 1 picks the alternate (7,0)
	# candidate by reading the just-advanced Monk_A position.
	#
	# Why this is the right G7 geometry: the tick-1 retry on Monk_B is the
	# canonical "after a failed proposal, re-decide without thrashing"
	# pattern. Monk_B's decision history will include the reverted
	# START_MOVING followed by the new START_MOVING — distinct targets, so
	# neither thrash pattern (same-target 3+ or last-3-stuck-reasons)
	# fires. A regression in the resolve-revert path that tagged the
	# retry as GAMBIT_FAILED instead of re-emitting START_MOVING could
	# accumulate stuck reasons across consecutive ties and trip the
	# detector even though the unit is making progress.
	#
	# Budget: by_tick=180 mirrors G6a's commit window for both Monks.
	# Asserts no_thrash on Monk_B ONLY — Monk_A is the contention winner
	# and stalemates against the invincible 999-HP Enemy by ~tick 148
	# (within the by_tick=180 window), so its ring buffer can legitimately
	# accumulate stuck reasons that the predicate would flag as thrash.
	# Monk_B is the actual rule subject (the retrying loser); witness drift
	# to "both Monks" was copy-paste from G6b's symmetry, not deliberate.
	# max_ticks=400.
	return {
		"rule": "G7",
		"name": "no_thrash_during_reservation_retry",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk_A", "team": 0, "tile": [5, 1],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Monk_B", "team": 0, "tile": [7, 1],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [_attack_nearest_enemy_slot()],
			},
			{
				"name": "Enemy", "team": 1, "tile": [6, 0],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
			"trace": [
				{"kind": "by_tick", "tick": 180,
				 "unit": "Monk_A", "committed": "ATTACK"},
				{"kind": "by_tick", "tick": 180,
				 "unit": "Monk_B", "committed": "ATTACK"},
			],
			"no_thrash": [
				{"unit": "Monk_B", "by_tick": 180},
			],
			"position": [
				{"kind": "reached_within", "unit": "Monk_A",
				 "target": "Enemy", "max_dist": 1, "by_tick": 180},
				{"kind": "reached_within", "unit": "Monk_B",
				 "target": "Enemy", "max_dist": 1, "by_tick": 180},
			],
			"gambit_slot": [
				{"unit": "Monk_A", "slot": 0},
				{"unit": "Monk_B", "slot": 0},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}
