extends RefCounted

## Rule group F — action execution paths. See [code]docs/gambit-rules.md[/code].
##
## F-group witnesses each [code]Gambit.ActionKind[/code] verb routes to the
## state-machine path the spec promises. Most cases PASS on the current
## shader — the suite mostly documents baseline routing rather than driving
## fixes.
##
## What's NOT covered (gaps documented inline):
##
## - **F3 (ITEM)** — [code]Gambit.ActionKind[/code] has no ITEM verb today;
##   the gambit author API can't reach the item-action path. Same blocker as
##   B4's "items still pass" sub-clause. No scenario is authored; a comment-
##   only placeholder lives at the top of the F3 section.
##
## - **F5 (MOVE_TO absolute tile)** — [code]GambitEncoder[/code]'s comment at
##   L153 spells it out: "Absolute-tile moves are a separate program-built
##   command path (ACTION_MOVE_TO) that does not pass through this encoder."
##   The scenario suite drives gambits through the encoder, so MOVE_TO is
##   uncoverable from here. Document-only.
##
## F2 sub-modes (issue #63 acceptance criteria call for three witnesses —
## instant / charged-non-cinematic / cinematic):
##
##   Today the shader collapses "charged non-cinematic" and "cinematic" into
##   one branch — [code]stage_spell.glsl:623[/code] routes every
##   [code]charge_time > 0[/code] ability through [code]cast_cinematic_spell[/code].
##   So the two charged scenarios witness the same code path. We still author
##   both as the rule spec lists them separately; F2b's [code]xfail_reason[/code]
##   notes the collapse so a future shader split that separates the paths
##   surfaces the gap rather than silently passing both witnesses.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector



# Ability ids — Monk/White Mage/Wizard kit, matches the B/D files.
const ABILITY_CURE := 1            # mp_cost=6, range=4, vertical=1, ct=4
const ABILITY_FIRE := 16           # mp_cost=6, range=4, vertical=1, ct=4
const ABILITY_WAVE_FIST := 102     # range=3, ct=0, mp_cost=0 — instant Monk skill

## The two halves of the F7 control (#1113). Both are `cancel`-mode abilities whose ROM
## inflict list names `Dead` — the whole permission to land on a corpse — and they take
## DIFFERENT routes to the target, which is why both are authored:
##
## - [constant ABILITY_RAISE] ct=4, so charge_time > 0 and the cast goes through
##   [code]cast_cinematic_spell[/code] -> [code]run_cinematic_orchestrator[/code], whose
##   per-target walk skipped every dead unit.
## - [constant ABILITY_REVIVE] ct=0 and range=1, so it lands in
##   [code]cast_instant_spell[/code] instead — and it is NOT `ABFLAG_HEALING`
##   (`target_reaction_type` is `taking_damage`), so before #1113 the fork inside that
##   function routed it into the DAMAGE arm and stage_damage dropped the write for being
##   aimed at a corpse. Its range of 1 is also what makes it the cheap walk-to-cast
##   witness: any corpse more than one tile away forces WALKING_TO_CAST.
##
## [constant ABILITY_CURE] is the negative arm: `receive_heal`, no inflict list at all, so
## the gate must not open for it.
const ABILITY_RAISE := 5           # mp_cost=10, range=4, ct=4, formula 0x0D y=50 (50% maxHP)
const ABILITY_REVIVE := 107        # mp_cost=0, range=1, ct=0, NOT flagged healing


static func scenarios() -> Array:
	return [
		_f1_in_range_attack_swings_immediately(),
		_f1_out_of_range_attack_walks_then_swings(),
		_f2_instant_ability_casts_without_charging(),
		_f2_charged_ability_enters_spell_charging(),
		_f2_cinematic_ability_lands_damage(),
		_f7_cancel_dead_ability_revives_the_corpse(),
		_f7_plain_heal_at_a_corpse_leaves_it_dead(),
		_f8_a_reviving_cast_walks_to_the_corpse(),
		_f4_move_to_unit_walks_adjacent_to_target(),
		_f6_wait_no_movement_no_swing(),
	]


# === F1 ===============================================================

static func _f1_in_range_attack_swings_immediately() -> Dictionary:
	# Adjacent Knight, weapon_range=1 — the ATTACK slot picks the target and
	# enters ACTING on the first eval tick. Witness: committed(ATTACK) by tick
	# 50 (no walk required, so the swing should land well before the
	# walk-and-attack variant's tick budget). gambit_slot pins slot 0 so a
	# regression where slot 1 (none here) somehow caught the actor would
	# still trip the verdict — A1/D1 cover slot ordering proper.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "F1",
		"name": "in_range_attack_swings_immediately",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 200,
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
				"name": "Knight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 50,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _f1_out_of_range_attack_walks_then_swings() -> Dictionary:
	# Same loadout as the in-range sibling, but the Knight is 4 tiles away
	# (Manhattan 4, weapon_range=1) — the actor MUST walk to an adjacent
	# attack tile before swinging. Observed walk-then-attack on MAP042 flat
	# terrain commits around tick 390 (each move step ≈ 85 ticks under the
	# 4× time-scale runner default); witness budget set at 450 to leave
	# headroom for re-pathing / minor variance. If the shader regressed to
	# "out-of-range → stay idle" the actor's first_commit never fires and
	# the predicate trips well within the budget.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "F1",
		"name": "out_of_range_attack_walks_then_swings",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 500,
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
			"trace": [{
				"kind": "by_tick", "tick": 450,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === F2 ===============================================================

static func _f2_instant_ability_casts_without_charging() -> Dictionary:
	# Wave Fist (ability_id=102, range=3, ct=0, mp_cost=0) — Monk skill with
	# zero charge time. Slot 0 ABILITY → Knight at adjacent (within range=3).
	# Witness: committed("ABILITY") by tick 50. The trace predicate's ABILITY
	# branch keys off [code]cast_events[/code] which fires from
	# [code]cast_began[/code]; for ct=0 abilities that signal fires the same
	# tick the unit enters ACTING (no SPELL_CHARGING prelude).
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_WAVE_FIST,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "F2",
		"name": "instant_ability_casts_without_charging",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 200,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 14, "ma": 10, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0],
			},
			{
				"name": "Knight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 50,
				"unit": "Monk", "committed": "ABILITY",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _f2_charged_ability_enters_spell_charging() -> Dictionary:
	# Cure (ability_id=1, ct=4 → charge_time=120, mp_cost=6) on SELF — slot 0
	# fires unconditionally so the witness is "first_commit happened on slot 0"
	# (D2's SELF-cure scenarios use the same pattern). The shader transitions
	# IDLE → SPELL_CHARGING for ct>0 abilities, and [code]first_commit[/code]
	# in the trace logger captures the SPELL_CHARGING transition explicitly.
	# Note the shader collapse: [code]stage_spell.glsl:623[/code] routes every
	# charge_time>0 ability through [code]cast_cinematic_spell[/code], so this
	# scenario witnesses the same code path the cinematic F2c sibling does.
	# Authored separately because gambit-rules.md lists them as distinct sub-
	# modes; if/when the shader splits them, both witnesses stay load-bearing.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "F2",
		"name": "charged_ability_enters_spell_charging",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
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
				# Out of melee range so the Knight never distracts the witness;
				# Priest's SELF-cast doesn't need a hostile in range, but the
				# two-team setup invariant does.
				"name": "Knight", "team": 1, "tile": [3, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"gambit_slot": [{"unit": "Priest", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _f2_cinematic_ability_lands_damage() -> Dictionary:
	# Fire (ability_id=16, ct=4 → charge_time=120, mp_cost=6) — projectile-style
	# damage spell. Wizard adjacent to Knight (within range=4, no walking).
	# The current shader routes every charge_time>0 ability through
	# [code]cast_cinematic_spell[/code], so this is the canonical cinematic
	# witness. Cast resolves after the charge timer ticks down + animation
	# frames play — well under the 400-tick budget. Damage to Knight proves
	# the cast committed and the cinematic orchestrator stamped its hit frame.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_FIRE,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "F2",
		"name": "cinematic_ability_lands_damage",
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
				"name": "Knight", "team": 1, "tile": [5, 7],
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
				"unit": "Wizard", "committed": "ABILITY",
			}],
			"damage": [{
				"kind": "damage_dealt_to",
				"target": "Knight", "by_tick": 400,
			}],
			"gambit_slot": [{"unit": "Wizard", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === F7 / F8 ==========================================================
#
# #1113 — an ability that lands on a KO'd unit. #1102 opened the target POOL
# (TARGET_NEAREST_ALLY_OR_KO) so a `KO'd?` slot could SEE a corpse; the cast then
# committed, spent the MP, played the animation and changed nothing, because four
# more `is_unit_dead` gates sat between the commit and the HP write.
#
# 🔴 ONE OF THE FOUR IS NOT WITNESSED HERE AND CANNOT BE. `apply_attack_damage`
# (stage_compute.glsl) is the landing site for projectile-style casts, and the only
# cancel-Dead ability that reaches it is PhoenixDown (381) — an ITEM. As the F3
# section below records, `Gambit.ActionKind` has no ITEM verb, so no scenario in this
# repo can author that cast. The gate is opened in the kernel for uniformity and is
# UNWITNESSED; it becomes witnessable on the same day F3 does.

static func _f7_cancel_dead_ability_revives_the_corpse() -> Dictionary:
	# Cleric parks (move 0) two tiles from Bait, well inside Raise's range 4, so the
	# commit is a cast and not a walk — F8 owns the walk. Slot 1 is WAIT and bumps no
	# cast_step_id, so slot 0 can only win once a corpse exists in the pool.
	#
	# 🔴 THE ROSTER SITS IN THE (0, 0) CORNER ON PURPOSE, AND IT IS THE SECOND ARM OF
	# THIS SCENARIO. `set_battle_units` marks the battle's five unfilled slots FLAG_DEAD
	# with a zeroed record — so they are five team-0 "corpses" standing at tile (0, 0).
	# Anywhere else on MAP042 the real Bait wins the KO-inclusive pool's rank walk on
	# path cost and the phantoms are invisible; from (1, 0) a phantom is NEARER, so the
	# pool's `is_unit_slot_filled` clause becomes load-bearing. Measured both ways:
	# with the clause removed the Cleric casts Raise at `Unit3` at tick 10 — before
	# anyone has died — and Bait never comes back; with it, the slot cannot fire until
	# tick 23, when Bait is actually a corpse. `gambit_fired_at_slot`'s detail names the
	# cast target, so the red reads `target=Unit3` rather than leaving you to guess.
	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var cleric_slot0 := Gambit.create(
			TargetSelector.friendlies_or_ko(),
			[GambitCondition.is_ko()],
			Gambit.ActionKind.ABILITY, ABILITY_RAISE,
			TargetSelector.triggering())

	var kill := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	return {
		"rule": "F7",
		"name": "cancel_dead_ability_revives_the_corpse",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 900,
		"units": [
			{
				# max_hp 9999 is not decoration. The first draft gave the Cleric 200 and it
				# was DEAD at tick ~110, mid-charge — Raise's ct=4 is 120 ticks, and a
				# cast that never completes reads exactly like a revive that never lands.
				# The caster has to outlive its own charge for this scenario to be about
				# the revive at all.
				#
				# Tile (1, 0): one step from the phantom slots' (0, 0). See the header.
				"name": "Cleric", "team": 0, "tile": [1, 0],
				"job": "4f", "max_hp": 9999, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [cleric_slot0, wait],
			},
			{
				# Dies early: 20 HP, cannot flee, adjacent to Killer, and inside
				# Raise's range 4 of the Cleric.
				# 🔴 `hp` AND `max_hp` ARE BOTH LOAD-BEARING AND THEY DISAGREE ON PURPOSE.
				# `hp: 20` is what the Killer has to chew through, so Bait dies on the
				# first swing and the corpse exists early. `max_hp: 2000` is what the
				# REVIVE reads: both revive formulas here are a PERCENTAGE of max HP, so a
				# 20-max-HP Bait would come back at 10 HP and be re-killed inside one
				# host frame. The runner samples the per-tick snapshot once per host frame
				# and the GPU runs ~25 ticks in that time, so a revive that does not
				# SURVIVE a frame is a revive no predicate can see.
				"name": "Bait", "team": 0, "tile": [2, 1],
				"job": "4e", "max_hp": 2000, "hp": 20, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [wait],
			},
			{
				# pa*wp ~= 32: enough to drop a 20-HP Bait on the first swing, nowhere
				# near enough to matter to a 9999-HP Cleric or to re-kill a revived Bait
				# before the sampler sees it. The 40/12 of the first draft one-shot
				# everything on the field including the caster.
				"name": "Killer", "team": 1, "tile": [3, 1],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 8, "ma": 1, "wp": 4, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [kill],
			},
		],
		"expect": {
			# THE WHOLE POINT: FLAG_DEAD clears and the HP comes back. A commit
			# assertion alone passes today, on the kernel that no-ops at impact —
			# that half is already D7's, and repeating it here would hide the fix.
			"revived": [{"target": "Bait", "by_tick": 900}],
			"gambit_slot": [{"unit": "Cleric", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _f7_plain_heal_at_a_corpse_leaves_it_dead() -> Dictionary:
	# THE CONTROL. Same roster, same geometry, same slot — one constant changed.
	# Cure is `receive_heal` with no inflict list, so `ability_revives` is false for it
	# and every dead-filter stays shut. Without this arm, F7's positive result is
	# consistent with a kernel that revives on ANY heal landing at a corpse, which is
	# the half-fix the predicate's flag-not-HP reading is written to catch.
	#
	# `gambit_slot` is load-bearing here, not decoration: it proves the Cleric actually
	# COMMITTED the cast at the corpse. Without it, "Bait stayed dead" would also be the
	# verdict for a scenario where the cast never happened at all.
	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var cleric_slot0 := Gambit.create(
			TargetSelector.friendlies_or_ko(),
			[GambitCondition.is_ko()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	var kill := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	return {
		"rule": "F7",
		"name": "plain_heal_at_a_corpse_leaves_it_dead",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 900,
		"units": [
			{
				# max_hp 9999 is not decoration. The first draft gave the Cleric 200 and it
				# was DEAD at tick ~110, mid-charge — Raise's ct=4 is 120 ticks, and a
				# cast that never completes reads exactly like a revive that never lands.
				# The caster has to outlive its own charge for this scenario to be about
				# the revive at all.
				"name": "Cleric", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 9999, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [cleric_slot0, wait],
			},
			{
				# 🔴 `hp` AND `max_hp` ARE BOTH LOAD-BEARING AND THEY DISAGREE ON PURPOSE.
				# `hp: 20` is what the Killer has to chew through, so Bait dies on the
				# first swing and the corpse exists early. `max_hp: 2000` is what the
				# REVIVE reads: both revive formulas here are a PERCENTAGE of max HP, so a
				# 20-max-HP Bait would come back at 10 HP and be re-killed inside one
				# host frame. The runner samples the per-tick snapshot once per host frame
				# and the GPU runs ~25 ticks in that time, so a revive that does not
				# SURVIVE a frame is a revive no predicate can see.
				"name": "Bait", "team": 0, "tile": [4, 5],
				"job": "4e", "max_hp": 2000, "hp": 20, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [wait],
			},
			{
				# pa*wp ~= 32: enough to drop a 20-HP Bait on the first swing, nowhere
				# near enough to matter to a 9999-HP Cleric or to re-kill a revived Bait
				# before the sampler sees it. The 40/12 of the first draft one-shot
				# everything on the field including the caster.
				"name": "Killer", "team": 1, "tile": [4, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 8, "ma": 1, "wp": 4, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [kill],
			},
		],
		"expect": {
			"revived": [{"target": "Bait", "by_tick": 900, "expect_no_revive": true}],
			"gambit_slot": [{"unit": "Cleric", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _f8_a_reviving_cast_walks_to_the_corpse() -> Dictionary:
	# The walk-to-cast half. Revive's range is 1 and the Cleric starts three tiles
	# away, so the cast cannot resolve where it was authored: the Cleric enters
	# WALKING_TO_CAST, and `handle_moving_to_cast_state` re-asked "is my cast target
	# dead?" on every tick of that walk and abandoned the cast every time. A corpse is
	# the ONLY thing a revive ever walks toward, so this gate failed 100% of the time
	# it was reached.
	#
	# Revive also doubles as the `cast_instant_spell` witness: ct=0 routes it away from
	# the cinematic orchestrator F7 exercises, and its `taking_damage` reaction category
	# means it is not ABFLAG_HEALING, so it is the arm that proves the revive is taken
	# BEFORE the break/heal/damage fork rather than inside the heal arm.
	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var cleric_slot0 := Gambit.create(
			TargetSelector.friendlies_or_ko(),
			[GambitCondition.is_ko()],
			Gambit.ActionKind.ABILITY, ABILITY_REVIVE,
			TargetSelector.triggering())

	var kill := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	return {
		"rule": "F8",
		"name": "a_reviving_cast_walks_to_the_corpse",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 900,
		"units": [
			{
				# move 3, three tiles from Bait: out of Revive's range 1, in reach of one
				# walk. max_hp 9999 for the same reason F7's Cleric carries it — the caster
				# must outlive the walk AND the cast.
				"name": "Cleric", "team": 0, "tile": [4, 8],
				"job": "4f", "max_hp": 9999, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [cleric_slot0, wait],
			},
			{
				# 🔴 `hp` AND `max_hp` ARE BOTH LOAD-BEARING AND THEY DISAGREE ON PURPOSE.
				# `hp: 20` is what the Killer has to chew through, so Bait dies on the
				# first swing and the corpse exists early. `max_hp: 2000` is what the
				# REVIVE reads: both revive formulas here are a PERCENTAGE of max HP, so a
				# 20-max-HP Bait would come back at 10 HP and be re-killed inside one
				# host frame. The runner samples the per-tick snapshot once per host frame
				# and the GPU runs ~25 ticks in that time, so a revive that does not
				# SURVIVE a frame is a revive no predicate can see.
				"name": "Bait", "team": 0, "tile": [4, 5],
				"job": "4e", "max_hp": 2000, "hp": 20, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [wait],
			},
			{
				# pa*wp ~= 32: enough to drop a 20-HP Bait on the first swing, nowhere
				# near enough to matter to a 9999-HP Cleric or to re-kill a revived Bait
				# before the sampler sees it. The 40/12 of the first draft one-shot
				# everything on the field including the caster.
				"name": "Killer", "team": 1, "tile": [4, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 8, "ma": 1, "wp": 4, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [kill],
			},
		],
		"expect": {
			"revived": [{"target": "Bait", "by_tick": 900}],
			"position": [{
				"kind": "reached_within",
				"unit": "Cleric", "target": "Bait", "max_dist": 1, "by_tick": 900,
			}],
			"gambit_slot": [{"unit": "Cleric", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === F3 ===============================================================
#
# F3 (ITEM) is uncoverable from the scenario author API today. The
# [code]Gambit.ActionKind[/code] enum has no ITEM verb — same blocker as
# B4's "items still pass" sub-clause documents. The shader's
# [code]is_item_ability[/code] gate inside [code]start_spell[/code] /
# [code]cast_adjacent_item[/code] does exist (so item-actions could be
# witnessed if the encoder pipeline learned to author them), but no scenario
# can author one through the public [code]Gambit.create[/code] API in this
# repo. Reopen this section when ACTION_ITEM lands in the Gambit domain.


# === F4 ===============================================================

static func _f4_move_to_unit_walks_adjacent_to_target() -> Dictionary:
	# MOVE_TO_UNIT (ActionKind.MOVE with TargetSelector.enemies()) — encoder
	# routes this to ACTION_MOVE_TO_UNIT (GambitEncoder.gd:154, ADR-0062).
	# Knight stays put (single-slot WAIT) so the witness is unambiguous: did
	# the Monk walk from (4,7) to within Manhattan 1 of (4,3) within the
	# tick budget? The spec also wants re-pathing on a moving target — that
	# is an ADR-0062 follow-up; this scenario witnesses the baseline
	# stop-adjacent rule. A moving-target sibling is a natural F4 expansion
	# once the position-snapshot witness here proves out.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.MOVE, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "F4",
		"name": "move_to_unit_walks_adjacent_to_target",
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
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === F5 ===============================================================
#
# F5 (MOVE_TO absolute tile) is uncoverable from the scenario author API.
# [code]GambitEncoder.gd:153[/code] documents the gap: "Absolute-tile moves
# are a separate program-built command path (ACTION_MOVE_TO) that does not
# pass through this encoder." The scenario suite drives gambits through the
# encoder, so authoring a MOVE_TO is structurally impossible from here. The
# shader-side path is exercised by other tests that build the command
# directly; reopen this section if [code]Gambit.ActionKind[/code] grows a
# distinct MOVE_TO verb or [code]TargetSelector[/code] learns an absolute-
# tile pool type.


# === F6 ===============================================================

static func _f6_wait_no_movement_no_swing() -> Dictionary:
	# Both teams on a single-slot WAIT. The Monk's only gambit is WAIT-SELF,
	# the Knight's only gambit is WAIT-SELF, neither commits a damaging
	# action. Witness: no damage to either unit by max_ticks (proves no
	# swing) and the per-tick position-snapshot shows the Monk never left
	# its starting tile (proves no movement). [code]outcome.winner = -2[/code]
	# (unresolved) confirms the sim ran but no team killed the other; the
	# NORAN baseline still trips on [code]per_tick_snapshots > 0[/code] even
	# though [code]gambit_eval_events == 0[/code] (no WALKING/ACTING/
	# SPELL_CHARGING transitions to count).
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1,
			TargetSelector.self_())

	return {
		"rule": "F6",
		"name": "wait_no_movement_no_swing",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 200,
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
				"name": "Knight", "team": 1, "tile": [3, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [slot0],
			},
		],
		"expect": {
			"outcome": {"winner": -2},
			"damage": [
				{
					"kind": "damage_dealt_to",
					"target": "Knight", "by_tick": 200,
					"expect_no_damage": true,
				},
				{
					"kind": "damage_dealt_to",
					"target": "Monk", "by_tick": 200,
					"expect_no_damage": true,
				},
			],
			"position": [{
				"kind": "stayed_at",
				"unit": "Monk", "tile": [4, 7],
				"by_tick": 200,
			}],
		},
		"xfail": [],
		"xfail_reason": "",
	}
