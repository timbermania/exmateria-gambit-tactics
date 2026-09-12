extends RefCounted

## Rule group D — conditions. See [code]docs/gambit-rules.md[/code].
##
## D-group witnesses condition evaluation: does ALWAYS always pass; do
## HP_BELOW/ABOVE and MP_BELOW/ABOVE evaluate against percentage (not absolute);
## do HAS_STATUS / MISSING_STATUS read the unit's status set; do multiple
## conditions AND-combine.
##
## D2 covers four HP scopes (SELF / ALLY / ENEMY / TARGET) per the acceptance
## criteria. On the GPU side these all collapse to [code]COND_HP_BELOW[/code]
## (the shader's [code]target_id[/code] is whichever candidate the slot is
## currently evaluating against) — what differentiates the scope is the
## [code]condition_target[/code] selector. Each D2 scenario varies that
## selector so the rule's documented intent is exercised end-to-end.
##
## D4 (HAS_STATUS / MISSING_STATUS) translates StringName status_id →
## bit index via [code]StatusRegistry[/code] in
## [code]GambitEncoder._encode_gambit_condition[/code] (#67); the shader at
## [code]stage_compute.glsl:100-104[/code] reads [code]condition_value[/code]
## as that bit index.
##
## D7 / D8 (#1102) are the two conditions the kernel always answered and nobody could ask.
## D7's subject is as much the target POOL as the condition: [code]COND_IS_DEAD[/code] was
## decidable and unreachable, because every pool filtered KO'd candidates before a condition
## ever saw them. D8 pins [code]TARGET_DISTANCE[/code] to MANHATTAN tiles — one of the three
## distances the kernel keeps apart (see [code]docs/gambit-rules.md[/code] D8).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const StatusRegistry = ExMateriaAlmanac.StatusRegistry
const TargetSelector = ExMateriaAlmanac.TargetSelector


const ABILITY_CURE := 1            # mp_cost=6, range=4, vertical=1

## Monk skill. mp_cost=0, range=3, vertical=3, and `vertical_tolerance` TRUE — which is what
## makes it the D6 vertical witness: [constant ABILITY_CURE] carries the flag FALSE, so its
## reach is not height-bounded at all and it could not tell the two halves apart.
const ABILITY_WAVE_FIST := 102


static func scenarios() -> Array:
	return [
		_d1_always_passes(),
		_d2_self_hp_below_triggers(),
		_d2_ally_hp_below_triggers(),
		_d2_enemy_hp_below_triggers(),
		_d2_target_hp_below_triggers(),
		_d3_self_mp_below_triggers(),
		_d4_has_status_self_haste_fires_slot_zero(),
		_d4_has_status_self_poison_fires_self_cure(),
		_d4_has_status_self_regen_fires_self_cure(),
		_d4_has_status_self_reraise_fires_self_cure(),
		_d4_has_status_self_transparent_fires_self_cure(),
		_d4_missing_status_self_silence_falls_through(),
		_d5_and_combine_both_pass(),
		_d5_and_combine_one_false_falls_through(),
		_d6_weapon_in_range_fires_slot_zero(),
		_d6_weapon_out_of_range_falls_through(),
		_d6_ability_within_vertical_fires_slot_zero(),
		_d6_ability_beyond_vertical_falls_through(),
		_d7_is_ko_fires_only_over_a_ko_inclusive_pool(),
		_d8_distance_thresholds_gate_the_slot(),
	]


# === D1 ===============================================================

static func _d1_always_passes() -> Dictionary:
	# Pure D1 witness: single-slot ALWAYS condition. Slot 0 must fire; no
	# fallback to a slot 1 because there isn't one. A1 already covers
	# "lower slot wins" — D1's distinct contribution is "ALWAYS is the
	# fall-through condition that NEVER fails."
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D1",
		"name": "always_condition_passes_slot_fires",
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
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === D2 ===============================================================

static func _d2_self_hp_below_triggers() -> Dictionary:
	# SELF scope: condition_target=SELF, cond evaluates HP% of the actor.
	# Caster seeded at hp=50/max_hp=200 (25%) so SELF_HP < 50% is true. Slot 0
	# casts Cure on self. Witness via gambit_fired_at_slot — the trace
	# logger's first_commit fires on the first state transition into either
	# SPELL_CHARGING or ACTING, which is the cleanest "slot 0 committed"
	# signal here. We don't add a trace.committed(...) rail because the
	# assertion's ACTION_ANY only matches ACTING (not SPELL_CHARGING), and
	# the Cure-SELF path enters SPELL_CHARGING first; gambit_slot already
	# captures the commit tick in its detail message.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.new(
					GambitCondition.Type.SELF_HP,
					GambitCondition.Comparator.LESS_THAN, 50.0)],
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
		"rule": "D2",
		"name": "self_hp_below_triggers_self_heal",
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
				# Out of range so the Priest never gets distracted into an
				# attack path. Standard inert knight for 2-team baseline.
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


static func _d2_ally_hp_below_triggers() -> Dictionary:
	# ALLY scope: condition_target=friendlies with MOST_CRITICAL resolution
	# picks the lowest-HP ally; cond=ALLY_HP < 50% evaluates against that pick.
	# A low-HP ally (25%) is in the pool so slot 0 fires Cure on TRIGGERING.
	# Witness: gambit_fired_at_slot(slot=0). See the SELF-scope sibling for
	# why the trace.committed rail is omitted (SPELL_CHARGING transition).
	var ally_cond_target := TargetSelector.friendlies().with_resolution(
			TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var slot0 := Gambit.create(
			ally_cond_target,
			[GambitCondition.new(
					GambitCondition.Type.ALLY_HP,
					GambitCondition.Comparator.LESS_THAN, 50.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D2",
		"name": "ally_hp_below_triggers_heal_on_low_ally",
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
				"gambits": [slot0, slot1],
			},
			{
				# Low-HP ally — MOST_CRITICAL picks this one out of the two
				# friendlies (Priest is at 100% so the ally is more critical).
				"name": "BleedingAlly", "team": 0, "tile": [4, 6],
				"job": "4e", "max_hp": 200, "hp": 50, "max_mp": 0,
				"pa": 5, "ma": 5, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [wait],
			},
			{
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


static func _d2_enemy_hp_below_triggers() -> Dictionary:
	# ENEMY scope: condition_target=enemies with MOST_CRITICAL picks the
	# lowest-HP enemy; cond=ENEMY_HP < 50% evaluates against that pick. A
	# bleeding enemy (25%) is in the pool so slot 0 attacks the TRIGGERING
	# target. Witness: damage on the bleeding enemy; full-HP enemy untouched.
	var enemy_cond_target := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var slot0 := Gambit.create(
			enemy_cond_target,
			[GambitCondition.new(
					GambitCondition.Type.ENEMY_HP,
					GambitCondition.Comparator.LESS_THAN, 50.0)],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D2",
		"name": "enemy_hp_below_triggers_attack_on_low_enemy",
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
				# Full HP — MOST_CRITICAL must NOT pick this one.
				"name": "FullHpKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Low HP — MOST_CRITICAL picks this; condition passes.
				"name": "BleedingKnight", "team": 1, "tile": [3, 7],
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
					"target": "BleedingKnight", "by_tick": 150,
				},
				{
					"kind": "damage_dealt_to",
					"target": "FullHpKnight", "by_tick": 150,
					"expect_no_damage": true,
				},
			],
		},
		"xfail": [
			"no_damage_dealt_to(target='FullHpKnight', by_tick=150)",
		],
		"xfail_reason": "Same open bug as B7 (see its xfail_reason). MOST_CRITICAL correctly picks BleedingKnight and the Wizard does hit it at tick 42 — for delta=0 — and then hits FullHpKnight for -56 at tick 68, one beat later. So the target pick is right and something re-targets after the first swing. Marked XFAIL, NOT fixed.",
	}


static func _d2_target_hp_below_triggers() -> Dictionary:
	# TARGET scope: uses the target-agnostic factory
	# [code]GambitCondition.target_hp_below(50)[/code] (which emits
	# [code]Type.TARGET_HP[/code]). The condition_target is the standard enemies
	# pool — pass-1 picks NEAREST. The condition fires against the candidate
	# under test. Seeded at 25% HP, the slot fires. The enemy takes damage.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D2",
		"name": "target_hp_below_triggers_attack",
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
				# Low HP (25%) so the TARGET_HP < 50 condition passes against
				# the NEAREST_ENEMY pick.
				"name": "BleedingKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "hp": 50, "max_mp": 0,
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
					"target": "BleedingKnight", "by_tick": 150,
				},
			],
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === D3 ===============================================================

static func _d3_self_mp_below_triggers() -> Dictionary:
	# COND_MP_BELOW in the shader hard-codes the test target to the actor
	# (see stage_compute.glsl: [code]get_mp_percent(battle_id, unit_id)[/code]),
	# so MP scope is effectively single — the condition_target's selector is
	# advisory but the actual MP check is always on the actor. One scenario
	# per direction (BELOW) covers the rule.
	#
	# Setup: caster mp=5/40 (12%, well below 50%). Slot 0 ATTACK NEAREST_ENEMY
	# conditional on SELF_MP<50% → fires. Slot 1 (would catch on miss) doesn't
	# get invoked. The fallback ABILITY-Cure path is NOT used here because Cure
	# itself costs MP — the MP veto from B3 would brick the scenario. ATTACK has
	# no MP cost so the condition + action are decoupled and the witness is
	# clean.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.new(
					GambitCondition.Type.SELF_MP,
					GambitCondition.Comparator.LESS_THAN, 50.0)],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.enemies())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D3",
		"name": "self_mp_below_triggers_attack",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Priest", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40,
				# mp=5 → 12% MP; SELF_MP < 50 condition passes.
				"mp": 5,
				"pa": 12, "ma": 12, "wp": 2, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Knight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 100,
				"unit": "Priest", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Priest", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === D4 ===============================================================

static func _d4_has_status_self_haste_fires_slot_zero() -> Dictionary:
	# Caster has HASTE seeded; slot 0 says "if I HAS_STATUS(Haste), self-cast
	# Cure; else slot 1 attacks." Encoder routes status_id "haste" through
	# StatusRegistry.bit → 19, shader reads condition_value as a bit index, slot
	# 0 fires. Witness: gambit_fired_at_slot(slot=0) — the trace logger's
	# first_commit catches the SPELL_CHARGING transition for SELF Cure (same
	# pattern as D2's SELF-cure scenario). HASTE is chosen over SILENCE here
	# because silence would veto the Cure action and brick the witness — the
	# MISSING_STATUS sibling exercises silence as its seeded bit instead.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.has_status(&"haste")],
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
		"rule": "D4",
		"name": "has_status_self_haste_fires_slot_zero",
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
				"status_flags_lo": 1 << StatusRegistry.bit(&"haste"),
				"gambits": [slot0, slot1],
			},
			{
				# Out of melee range so slot 1 (ATTACK NEAREST_ENEMY) doesn't
				# win for the wrong reason — the witness should distinguish
				# slot 0 (Cure SELF) from slot 1 cleanly.
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


static func _d4_has_status_self_poison_fires_self_cure() -> Dictionary:
	# POISON-specific D4 witness. Mirrors the HASTE scenario above but exercises
	# the first per-status combat semantic (stage_damage Phase 1.5 — per-tick HP
	# delta) end-to-end with its gambit-side bit lookup. StatusRegistry routes
	# &"poison" → bit 15, the shader reads condition_value as 15, slot 0 fires.
	# Witness is gambit_fired_at_slot=0 (Cure cast on SELF). The per-tick HP loss
	# the mechanic itself produces is exercised in tests/GPUPoisonTest — this
	# scenario only needs to prove a slot conditional on HAS_STATUS(&"poison")
	# can fire, which is what the StatusRegistry integration buys.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.has_status(&"poison")],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D4",
		"name": "has_status_self_poison_fires_self_cure",
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
				"status_flags_lo": 1 << StatusRegistry.bit(&"poison"),
				"gambits": [slot0, slot1],
			},
			{
				# Out-of-range stub to satisfy the two-team setup invariant; can't
				# reach the Priest for an attack that would otherwise upstage the
				# slot-0 witness.
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


static func _d4_has_status_self_regen_fires_self_cure() -> Dictionary:
	# REGEN-specific D4 witness. Mirrors the POISON scenario above but exercises
	# the second consumer of stage_damage Phase 1.5 (status_system.md §2 per-tick
	# HP delta) and confirms StatusRegistry routes &"regen" → bit 16. The
	# encoder + shader are the same plumbing as POISON; this scenario isolates
	# the registry lookup for the regen name. The per-tick heal the mechanic
	# itself produces is exercised in tests/GPURegenTest — this scenario only
	# needs to prove a slot conditional on HAS_STATUS(&"regen") can fire.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.has_status(&"regen")],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D4",
		"name": "has_status_self_regen_fires_self_cure",
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
				"status_flags_lo": 1 << StatusRegistry.bit(&"regen"),
				"gambits": [slot0, slot1],
			},
			{
				# Out-of-range stub to satisfy the two-team setup invariant; can't
				# reach the Priest for an attack that would otherwise upstage the
				# slot-0 witness.
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


static func _d4_has_status_self_reraise_fires_self_cure() -> Dictionary:
	# RERAISE-specific D4 witness. Mirrors the POISON/REGEN scenarios above but
	# isolates the StatusRegistry lookup for &"reraise" → bit 22. RERAISE's
	# Phase 3 death-branch hook (status_system.md §2 "Re-targeting" row) is
	# exercised end-to-end in tests/GPUReraiseTest; this scenario only needs to
	# prove that a gambit slot conditional on HAS_STATUS(&"reraise") fires
	# through the encoder + shader plumbing.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.has_status(&"reraise")],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D4",
		"name": "has_status_self_reraise_fires_self_cure",
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
				"status_flags_lo": 1 << StatusRegistry.bit(&"reraise"),
				"gambits": [slot0, slot1],
			},
			{
				# Out-of-range stub to satisfy the two-team setup invariant; can't
				# reach the Priest for an attack that would otherwise upstage the
				# slot-0 witness.
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


static func _d4_has_status_self_transparent_fires_self_cure() -> Dictionary:
	# TRANSPARENT-specific D4 witness. Isolates the StatusRegistry lookup for
	# &"transparent" → bit 23 — the fourth single-status mechanic to ride the
	# plug-in convention. TRANSPARENT's target-selection + outgoing-action
	# consume + AOE-reveal hooks (status_system.md §2 "Target filter" row) are
	# exercised end-to-end in tests/GPUTransparentTest; this scenario only
	# needs to prove a gambit slot conditional on HAS_STATUS(&"transparent")
	# fires through the encoder + shader plumbing.
	#
	# Note the outgoing-action consume clears the bit on action commit. The
	# expected slot here is ABILITY → Cure (an outgoing action), so the bit
	# clears the same tick the gambit fires. The witness is the slot trigger
	# (gambit_fired_at_slot), not subsequent ticks — by tick 2 the carrier
	# would no longer match HAS_STATUS(&"transparent") and slot 1 would win.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.has_status(&"transparent")],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D4",
		"name": "has_status_self_transparent_fires_self_cure",
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
				"status_flags_lo": 1 << StatusRegistry.bit(&"transparent"),
				"gambits": [slot0, slot1],
			},
			{
				# Out-of-range stub matching the RERAISE/POISON/REGEN scenarios.
				# Out of melee range so the Knight can't upstage the slot-0
				# witness, and the Priest is TRANSPARENT anyway — the Knight's
				# nearest-enemy gambit would skip the Priest if it had one.
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


static func _d4_missing_status_self_silence_falls_through() -> Dictionary:
	# Symmetric MISSING_STATUS witness. Caster has SILENCE seeded; slot 0 says
	# "if I MISSING_STATUS(Silence), wait." With silence present, the condition
	# is false, slot 0 falls through to slot 1 (ATTACK). If MISSING_STATUS were
	# still pinned to value=0 (STATUS_DEAD), the alive caster would satisfy the
	# "missing dead" check and slot 0 would fire — so the slot-1 witness here is
	# load-bearing for the encoder fix, not just a coverage echo.
	var slot0 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.missing_status(&"silence")],
			Gambit.ActionKind.WAIT, -1,
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
		"rule": "D4",
		"name": "missing_status_self_silence_falls_through",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 200,
		"units": [
			{
				"name": "Wizard", "team": 0, "tile": [4, 7],
				"job": "50", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 12, "ma": 12, "wp": 4, "move": 4, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"status_flags_lo": 1 << StatusRegistry.bit(&"silence"),
				"gambits": [slot0, slot1],
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
				"kind": "by_tick", "tick": 100,
				"unit": "Wizard", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Wizard", "slot": 1}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === D5 ===============================================================

static func _d5_and_combine_both_pass() -> Dictionary:
	# Two conditions on slot 0: ALWAYS + ENEMY_HP < 50%. The bleeding knight at
	# 25% HP makes BOTH pass; AND-combine returns true; slot 0 fires. Mirror of
	# A3 but reframed as a D5 witness — A3 lives under "slot evaluation order,"
	# D5 explicitly pins "multiple conditions on one slot are AND-combined."
	# Coverage duplication is intentional (the rule index in
	# docs/gambit-rules.md is the contract, not the scenario count).
	var enemy_cond_target := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var slot0 := Gambit.create(
			enemy_cond_target,
			[
				GambitCondition.always(),
				GambitCondition.new(
						GambitCondition.Type.ENEMY_HP,
						GambitCondition.Comparator.LESS_THAN, 50.0),
			],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D5",
		"name": "and_combine_both_pass_slot_fires",
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
				"name": "BleedingKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "hp": 50, "max_mp": 0,
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
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _d5_and_combine_one_false_falls_through() -> Dictionary:
	# Same slot 0 as the "both pass" sibling, but the enemy is at FULL HP, so
	# ENEMY_HP < 50% is false. AND fails → slot 0 skips → slot 1 catches.
	# Together with the sibling, this pair shows AND's truth table without
	# either scenario passing for the wrong reason: the candidate exists in
	# both, only HP% differs.
	var enemy_cond_target := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.MOST_CRITICAL)
	var slot0 := Gambit.create(
			enemy_cond_target,
			[
				GambitCondition.always(),
				GambitCondition.new(
						GambitCondition.Type.ENEMY_HP,
						GambitCondition.Comparator.LESS_THAN, 50.0),
			],
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
		"rule": "D5",
		"name": "and_combine_one_false_falls_through",
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
				"gambits": [slot0, slot1],
			},
			{
				"name": "FullHpKnight", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "hp": 200, "max_mp": 0,
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
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === D6 ===============================================================
#
# `IN_RANGE` asks THE SLOT'S OWN ACTION whether it reaches the candidate from where the actor
# stands (ADR-0268 dec. 11). Four scenarios, in two PAIRS, because each half of the answer
# has to be shown to move on its own:
#
#   * weapon reach — in range fires slot 0, out of range falls to slot 1
#   * ability VERTICAL — within tolerance fires slot 0, beyond it falls through
#
# The vertical pair is the one that could not have been written before. The condition the screen
# used to offer encoded to `COND_DISTANCE_LESS`, a flat manhattan that never reads a height, so
# the "beyond vertical" scenario would have fired slot 0 and been WRONG while looking right.
# Its partner is the positive control: without a scenario in which WaveFist DOES fire, "slot 0
# never fired" is equally well explained by WaveFist never being castable here at all.
#
# MAP042 heights, read off `assets/maps/MAP042/terrain.json`: (2,7) and (3,7) are both 8 — a
# flat pair; (2,10) is 9 and (3,10) is 3 — a drop of SIX, against WaveFist's vertical of 3.


static func _d6_weapon_in_range_fires_slot_zero() -> Dictionary:
	# Slot 0 and slot 1 do the SAME THING, and that is deliberate: the only thing that can
	# distinguish them is which slot the GPU recorded in `current_gambit`, so this cannot pass
	# by the unit happening to attack.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_in_range()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D6",
		"name": "weapon_in_range_fires_slot_zero",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 200,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [2, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "Adjacent", "team": 1, "tile": [3, 7],
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
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _d6_weapon_out_of_range_falls_through() -> Dictionary:
	# Same two slots, and the foe moved four tiles away against a weapon that reaches one. The
	# unit still attacks — slot 1 walks it over — so what is under test is purely WHICH slot
	# bought that attack.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_in_range()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D6",
		"name": "weapon_out_of_range_falls_through",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [2, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "FarKnight", "team": 1, "tile": [2, 3],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"gambit_slot": [{"unit": "Monk", "slot": 1}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _d6_ability_within_vertical_fires_slot_zero() -> Dictionary:
	# THE POSITIVE CONTROL for the scenario below. Flat ground, one tile apart, well inside
	# WaveFist's range of 3 and its vertical of 3 — so slot 0 fires and the fall-through
	# scenario's silence cannot be explained by "WaveFist never casts here".
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_in_range()],
			Gambit.ActionKind.ABILITY, ABILITY_WAVE_FIST,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D6",
		"name": "ability_within_vertical_fires_slot_zero",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [2, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "LevelKnight", "team": 1, "tile": [3, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _d6_ability_beyond_vertical_falls_through() -> Dictionary:
	# ONE TILE APART and SIX HEIGHT UNITS DOWN, against a vertical of 3. Horizontally this is
	# the easiest shot on the map; the only thing that can refuse it is the height.
	#
	# Slot 1 is a WAIT, so the witness is `stayed_at` rather than a slot number: a WAIT never
	# enters ACTING and the trace records no commit for it. That is the sharper assertion here
	# anyway — if slot 0 fired, `start_spell` would find (4,10) at height 2 well inside
	# WaveFist's tolerance of the target and WALK THERE, so the unit holding its tile at (2,10)
	# for 300 ticks is exactly "the condition refused, and nothing downstream un-refused it".
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_in_range()],
			Gambit.ActionKind.ABILITY, ABILITY_WAVE_FIST,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "D6",
		"name": "ability_beyond_vertical_falls_through",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [2, 10],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [slot0, slot1],
			},
			{
				"name": "LowKnight", "team": 1, "tile": [3, 10],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"stayed_at": [{"unit": "Monk", "tile": [2, 10], "by_tick": 300}],
			"no_safety_net_hit": [{"unit": "Monk"}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === D7 ===============================================================

## D7 / D7a — [constant GambitCondition.Type.IS_KO] reaches the kernel, and the POOL is what
## decides whether it can (#1102).
##
## 🔴 THE WHOLE POINT IS THE PAIR. Cleric and Skeptic carry the SAME condition against the SAME
## corpse and differ in exactly one bit — `include_ko`. A scenario with only the Cleric would go
## green against a kernel where `COND_IS_DEAD` happened to be reachable everywhere; one with only
## the Skeptic would go green against the tree as it stood before this ticket, where it was
## reachable nowhere. Together they say: the condition works, and the KO-blind pool is why it
## did not.
##
## 🔴 THE CORPSE IS NOT SEEDED. `GPUCombatPacker` hard-zeroes the unit flag word at pack time, so
## `FLAG_DEAD` cannot be written from a unit cfg — Bait is killed IN SIM by Killer. That is the
## stronger arm anyway: seeding the state the assertion looks for is how a fixture fakes its own
## success.
##
## Shield exists to force B7's pass-2 rank walk: it is the nearest ally to both clerics and it is
## standing, so rank 0 fails the condition and only the rank walk reaches the corpse. Drop Shield
## and the scenario still passes while testing half of what it claims.
##
## The Cure never actually heals — `apply_attack_damage` refuses a dead target — so the witness
## is the COMMIT, not a heal. Landing an ability ON a KO'd unit is its own ticket.
static func _d7_is_ko_fires_only_over_a_ko_inclusive_pool() -> Dictionary:
	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	# Cleric: KO-INCLUSIVE pool. Slot 0 can see the corpse; slot 1 parks it until there is one
	# (WAIT bumps no cast_step_id, so it is not a commit and cannot steal `first_commit`).
	var cleric_slot0 := Gambit.create(
			TargetSelector.friendlies_or_ko(),
			[GambitCondition.is_ko()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())

	# Skeptic: KO-BLIND pool, same condition. Slot 1 ATTACKS so the unit commits SOMETHING —
	# `no_commit_at_slot` scores a unit that never committed as blind, not as green.
	var skeptic_slot0 := Gambit.create(
			TargetSelector.friendlies(),
			[GambitCondition.is_ko()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.triggering())
	var skeptic_slot1 := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	var kill := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())

	return {
		"rule": "D7",
		"name": "is_ko_fires_over_ko_inclusive_pool_and_never_over_the_blind_one",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 900,
		"units": [
			{
				"name": "Cleric", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [cleric_slot0, wait],
			},
			{
				"name": "Skeptic", "team": 0, "tile": [5, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 5, "ma": 12, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [skeptic_slot0, skeptic_slot1],
			},
			{
				# Standing, nearest, immovable — the rank-0 ally both clerics must look PAST.
				"name": "Shield", "team": 0, "tile": [4, 6],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
			{
				# Dies early: 20 HP, cannot flee, adjacent to Killer. Within Cure's range 4 of
				# the Cleric so the commit is a cast and not a walk-to-cast.
				"name": "Bait", "team": 0, "tile": [4, 5],
				"job": "4e", "max_hp": 20, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": [wait],
			},
			{
				"name": "Killer", "team": 1, "tile": [4, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 40, "ma": 1, "wp": 12, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [kill],
			},
		],
		"expect": {
			# POSITIVE: the Cleric's first commit is slot 0 — it has nothing else that commits,
			# so this fires only once a corpse exists in its pool.
			"gambit_slot": [{"unit": "Cleric", "slot": 0}],
			# NEGATIVE: over the WHOLE trace, the Skeptic's slot 0 never wins. Whole-trace and
			# not first-commit on purpose — the corpse outlives the Skeptic's first attack, so a
			# first-commit check would pass without the slot ever having met a KO'd unit.
			"no_commit_at_slot": [{"unit": "Skeptic", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


# === D8 ===============================================================

## D8 — [constant GambitCondition.Type.TARGET_DISTANCE] gates a slot on MANHATTAN tiles.
##
## Both arms in one scenario (charter clause 13 — they share the whole roster). The Archer's
## slot 0 demands the nearest enemy be FURTHER than 8 tiles; at 4 it is not, so that slot must
## lose and slot 1 must take the commit. The Scout's slot 0 demands NEARER than 8, which holds,
## so its slot 0 must win. Same enemy, same geometry, opposite thresholds: a kernel that read the
## value word as anything but a tile count, or that ignored the comparator, fails one arm rather
## than letting both agree.
static func _d8_distance_thresholds_gate_the_slot() -> Dictionary:
	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	var far_gate := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.target_beyond(8.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE, TargetSelector.self_())
	var attack := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering())
	var near_gate := Gambit.create(
			TargetSelector.enemies(), [GambitCondition.target_within(8.0)],
			Gambit.ActionKind.ABILITY, ABILITY_CURE, TargetSelector.self_())

	return {
		"rule": "D8",
		"name": "distance_thresholds_gate_the_slot_in_tiles",
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 400,
		"units": [
			{
				# Manhattan to Knight[3,4] is |4-3| + |7-4| = 4, so `> 8` is FALSE:
				# slot 0 must lose and slot 1 must be the commit.
				"name": "Archer", "team": 0, "tile": [4, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 8, "ma": 8, "wp": 1, "move": 3, "jump": 3,
				"weapon_range": 4, "weapon_flags": 8, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [far_gate, attack],
			},
			{
				# Same geometry, `< 8` is TRUE: slot 0 must win. Cure on SELF so the commit needs
				# no reach and cannot be confused with an attack falling through.
				"name": "Scout", "team": 0, "tile": [5, 7],
				"job": "4f", "max_hp": 200, "max_mp": 40, "mp": 40,
				"pa": 8, "ma": 8, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x06,
				"gambits": [near_gate, wait],
			},
			{
				"name": "Knight", "team": 1, "tile": [3, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0x05,
				"gambits": [wait],
			},
		],
		"expect": {
			"gambit_slot": [
				{"unit": "Archer", "slot": 1},
				{"unit": "Scout", "slot": 0},
			],
			"no_commit_at_slot": [{"unit": "Archer", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}
