extends RefCounted

## Rule group K — the aim a DEFAULT authors. See [code]docs/gambit-rules.md[/code].
##
## Every other group asks what the kernel does with a rule someone wrote on purpose. K asks what
## it does with the rule the SCREEN wrote — the aim a slot carries because nobody changed it.
## Both cells here were reported by a player against the live gambit surface, and both are the
## same shape: [b]the row reads back correctly and the turn is spent on nothing.[/b]
##
## === WHY THESE CANNOT LIVE IN `GambitEncoderTest` ===========================================
##
## They round-trip. `Move / Self` and `ThrowStone / Self` encode with no E1 skip, pack into the
## buffer, pass `execute_gambit_action`'s target resolution, and commit. Every layer that has an
## opinion says yes. The defect is downstream of all of them, so the witness has to be the
## EFFECT — did the unit move, did anyone take damage — and that needs the kernel.
##
## `GambitEncoderTest`'s ADR-0276 audit is the other half: it grades the whole (verb x aim)
## space statically and cheaply, and these two scenarios are what root its grades in something
## the GPU actually did.
##
## === WHY K1 HAS A CONTROL ===================================================================
##
## K1 asserts two absences — the Monk did not move, the Knight was not hit. An absence from a
## blind instrument reads exactly like an absence from a working one, so K1c is the same
## fixture, the same unit and the same stats with the no-op slot removed: the Monk walks and the
## Knight bleeds. Without it, a fixture that silently failed to encode any gambit at all would
## pass K1 perfectly.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector


## Basic Skill, skillset 5. `dont_hit_caster: true`, `effect_area: 0`, range 4, MP 0,
## `formula: 55`, `effect_anim_id: 76` (a projectile).
const ABILITY_THROW_STONE := 148


## Punch Art, skillset 11. `range: 0`, `effect_area: 1`, MP 0, CT 0, `formula: 52`, all three
## `dont_hit_*` false. One of the fifteen range-0 ally-side abilities ADR-0278 dec. 8 named.
const ABILITY_CHAKRA := 106


static func scenarios() -> Array:
	return [
		_k1_move_at_self_fires_and_moves_nowhere(),
		_k1c_control_the_same_monk_moves_and_hits(),
		_k2_throw_stone_at_self_lands_on_the_caster(),
		_k3_range_zero_inherits_the_weapon_reach_and_fires(),
	]


# === K1 ===============================================================

static func _k1_move_at_self_fires_and_moves_nowhere() -> Dictionary:
	# The player's first report: `Move / Self / Foe HP<25%`. The condition is `Always` here
	# because the condition is not what is under test — reaching the action is.
	#
	# ROOTED IN THE KERNEL, not inferred from the row. `GambitEncoder` maps ActionKind.MOVE to
	# ACTION_MOVE_TO_UNIT and MOVE inherits the `action_target` as its DESTINATION, so the
	# destination is the unit that is me. `execute_move_to_unit_gambit` then reads
	# `U_TARGET` == my own id, and its adjacency check fires on the first evaluation:
	#
	#     if (manhattan_distance(my_x, my_z, tx, tz) <= 1) { ... REASON_ARRIVED; idle }
	#
	# 0 <= 1. The slot COMMITS — `execute_gambit_action` returns true with VERDICT_FIRED, so
	# the walk stops and slot 1 is never reached — and the unit is standing where it started.
	# It re-arrives every TICKS_GAMBIT_REEVAL, forever.
	#
	# Slot 1 is an ordinary attack precisely so its silence is loud: the Monk has a foe four
	# tiles away, a working reason to walk to it, and does neither.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.MOVE, -1,
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
		"rule": "K1",
		"name": "move_at_self_fires_and_moves_nowhere",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
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
				"name": "Knight", "team": 1, "tile": [4, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"position": [{
				"kind": "stayed_at",
				"unit": "Monk", "tile": [4, 7], "by_tick": 400,
			}],
			"damage": [{
				"kind": "damage_dealt_to",
				"target": "Knight", "by_tick": 400,
				"expect_no_damage": true,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === K1c (control) ====================================================

static func _k1c_control_the_same_monk_moves_and_hits() -> Dictionary:
	# K1's positive arm, and the ONLY difference is the absent slot 0. Same map, same tiles,
	# same job, same stats, same tick budget. If this one also showed a Monk that never moved
	# and a Knight that never bled, K1's two absences would be measuring the fixture and not
	# the rule.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "K1",
		"name": "control_the_same_monk_moves_and_hits",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
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
				"name": "Knight", "team": 1, "tile": [4, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Knight",
				"max_dist": 1, "by_tick": 400,
			}],
			"damage": [{
				"kind": "damage_dealt_to",
				"target": "Knight", "by_tick": 400,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === K2 ===============================================================

static func _k2_throw_stone_at_self_lands_on_the_caster() -> Dictionary:
	# The player's second report: picking `ThrowStone` on a fresh slot left it aimed at `Self`.
	#
	# 🔴 THE ROM RECORD FORBIDS THIS AIM AND THE KERNEL DOES NOT ENFORCE IT.
	#
	# ThrowStone carries `dont_hit_caster: true`, which `GPUAbilityLoader` encodes to
	# ABFLAG_HIT_NO_CASTER and `hit_policy_allows` reads (ADR-0049). But that predicate has
	# exactly two call sites and BOTH are AoE distribution walks — `stage_damage.glsl` Phase 1
	# and `stage_spell.glsl`'s per-target fire-frame stamp — and both are entered only when
	# `effect_area > 0`. ThrowStone's effect_area is 0, so it takes the single-target path
	# (`apply_damage_to_target` -> `U_DAMAGE_TARGET` / `U_DAMAGE_AMOUNT` -> stage_damage
	# Phase 2), and NOTHING on that path consults the hit policy.
	#
	# So the stone does not miss and does not fizzle: [b]the Squire hits itself.[/b] This
	# scenario asserts what SHOULD happen — the caster takes no damage — and xfails it, so the
	# day the kernel enforces the policy single-target it reports XPASS and someone deletes the
	# xfail. See ADR-0276 dec. 5 and #1144.
	#
	# The Knight is a live enemy on the map so the battle does not end on tick 1; it is given
	# `move: 0` and a WAIT slot so nothing it does can put damage on the Squire and forge the
	# witness.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_THROW_STONE,
			TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "K2",
		"name": "throw_stone_at_self_lands_on_the_caster",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Squire", "team": 0, "tile": [4, 7],
				"job": "4a", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0],
			},
			{
				# Far enough that its own weapon can never reach the Squire — the only unit
				# that can put damage on the Squire in this fixture is the Squire.
				"name": "Knight", "team": 1, "tile": [4, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"damage": [{
				"kind": "damage_dealt_to",
				"target": "Squire", "by_tick": 400,
				"expect_no_damage": true,
			}],
		},
		"xfail": ["no_damage_dealt_to(target='Squire', by_tick=400)"],
		"xfail_reason":
			"ADR-0049's hit policy is enforced only on the AoE distribution walk"
			+ " (`effect_area > 0`). ThrowStone's effect_area is 0, so the single-target path"
			+ " applies the damage without ever calling `hit_policy_allows` and the caster hits"
			+ " itself. ADR-0276 dec. 5; kernel fix is #1144.",
	}


# === K3 ===============================================================

static func _k3_range_zero_inherits_the_weapon_reach_and_fires() -> Dictionary:
	# ADR-0276's SECOND candidate verdict class, and this is the scenario that grades it.
	#
	# That ADR found `range == 0` on 41 reachable abilities (every Draw Out, every Song and
	# Dance, `SpinFist`, `Chakra`, `StigmaMagic`), read `spell_pre_validate` as checking MP and
	# not range, and wrote down a CANDIDATE reading it deliberately refused to grade: *"the unit
	# walks toward a target it can never be in range of, forever."* ADR-0278 dec. 8 / S2 then
	# raised the stakes by pointing fifteen of them at `Nearest Ally`.
	#
	# SEEDED BREAK — disable the accessor's `base_range == 0` branch (`if (false)` around the
	# `return read_unit(..., U_WEAPON_RANGE)`): the Monk's closest approach becomes dist 2 at
	# tick 2 and nobody takes damage, so three of the four assertions red. That arm is also the
	# only way to reach the true-`spell_range == 0` path at all — `GPUCombatPacker`'s
	# `weapon_range` row is `BEHAVE_RECOMPUTE`, so a scenario cannot set it to 0.
	#
	# 🔴 THE CANDIDATE READING IS FALSE, AND ONE FUNCTION IS WHY.
	#
	# `start_spell` does not use the ability's range. It uses
	# `get_effective_ability_range` (`combat_common.glslinc:1512`), whose FIRST branch is:
	#
	#     if (base_range == 0) return read_unit(battle_id, unit_id, U_WEAPON_RANGE);
	#
	# `range == 0` is the ROM's "this ability inherits the wielder's reach", not a literal zero.
	# So `spell_range` at `find_cast_position` is the WEAPON's range, the search box is the
	# ordinary one, and a range-0 ability walks into weapon reach and fires like any other.
	# ADR-0276 read the field and not the accessor; the accessor is the answer.
	#
	# The Monk starts at Manhattan 2 — deliberately OUT of its weapon reach of 1 — so the
	# scenario has to watch it close the gap. "Reached within 1" and "the Ally took the hit" are
	# two different claims and both are asserted: a unit that arrived and then stalled would
	# satisfy the first alone.
	#
	# The Knight is the GEOMETRIC negative control, the half `get_effective_ability_range` has
	# no say over. Chakra carries `dont_hit_enemies: false`, so an in-radius enemy WOULD be hit
	# (ADR-0049's friendly fire is symmetric, asserted in I2) — it is untouched here because it
	# is Manhattan 6 from the centre and for no other reason.
	#
	# ⚠️ SLOT 1 IS A WAIT AND IT IS LOAD-BEARING FOR THAT CONTROL. Chakra's cooldown is 300
	# ticks and it is armed at COMMIT, so the re-evaluation after the first cast vetoes slot 0
	# (ADR-0047 B8) and the decision falls through. With slot 0 alone the fall-through reached
	# the SAFETY NET — `Attack / Nearest Foe / Always` (ADR-0273) — and the Monk walked across
	# the map and hit the Knight for 1 at tick 260, reddening the control for a reason that has
	# nothing to do with the radius. A WAIT in slot 1 absorbs the fall-through and the Knight
	# stays a geometric statement. Measured, not guessed: that red is what this comment is.
	#
	# ⚠️ The damage is REAL and it is not a bug in this scenario. Chakra is `formula: 52`, which
	# `calculate_spell_damage` does not rule, so it falls to `damage = formula_y` = 5; and its
	# `target_reaction_type` is `taking_damage`, so ABFLAG_HEALING is clear and the kernel
	# applies those 5 as a HIT. A Chakra that heals is a separate question about formula 52 —
	# what is under test here is whether the ability RESOLVES AT ALL, and a negative delta
	# witnesses that as well as a positive one would.
	var slot0 := Gambit.create(
			TargetSelector.friendlies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CHAKRA,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "K3",
		"name": "range_zero_inherits_the_weapon_reach_and_fires",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30, "mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, wait],
			},
			{
				# Manhattan 2 from the Monk: outside a weapon reach of 1, so the walk is
				# forced. `move: 0` keeps the gap the Monk's to close.
				"name": "Ally", "team": 0, "tile": [2, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0,
				"gambits": [wait],
			},
			{
				"name": "Knight", "team": 1, "tile": [4, 3],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"position": [{
				"kind": "reached_within",
				"unit": "Monk", "target": "Ally",
				"max_dist": 1, "by_tick": 400,
			}],
			"damage": [
				{"kind": "damage_dealt_to", "target": "Ally", "by_tick": 400},
				# The caster is inside its own radius — `dont_hit_caster` is false on Chakra,
				# and this is the assertion that would red if the AoE walk ever centred on the
				# CASTER rather than on the target while the Monk stood adjacent.
				{"kind": "damage_dealt_to", "target": "Monk", "by_tick": 400},
				{
					"kind": "damage_dealt_to", "target": "Knight",
					"by_tick": 400, "expect_no_damage": true,
				},
			],
		},
		"xfail": [],
		"xfail_reason": "",
	}
