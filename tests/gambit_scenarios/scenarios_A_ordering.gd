extends RefCounted

## Rule group A — slot evaluation order. See [code]docs/gambit-rules.md[/code].
##
## A1 — Lower-index slots are evaluated before higher. The Monk's slot 0 is
## "Attack the nearest enemy, always", which always passes its conditions; the
## fired-slot must therefore be 0, not the slot-1 fallback.
##
## A2 — A disabled slot is skipped entirely (no condition eval, no target
## select). Slot 0 is enabled=false but its condition would otherwise pass;
## slot 1 fires. The encoder still emits a config Dict for the disabled slot
## (enabled=0 in the GPU buffer), so it is NOT an encoder-skip — the shader
## must respect the enabled flag during evaluate_gambits_up_to.
##
## A3 — All conditions on a slot must AND-pass before the action commits.
## Slot 0 has two conditions: ALWAYS (passes) + TARGET_HP < 50% (fails when
## the target is at full HP). The AND fails so slot 0 falls through; slot 1
## (unconditional ATTACK) catches. Distinct from B2 (single condition false):
## A3 specifically witnesses the AND-combine across multiple conditions on
## one slot (rule D5 ∩ rule A).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector



static func scenarios() -> Array:
	return [
		_a1_lower_slot_wins(),
		_a2_disabled_slot_skipped(),
		_a3_and_condition_fails_falls_through(),
	]


static func _a1_lower_slot_wins() -> Dictionary:
	# Slot 0: attack nearest enemy, always. Slot 1: wait on self (fallback).
	# Both gambits run through GambitEncoder (no flat-dict helpers — issue #57).
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	var slot1 := Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1,
			TargetSelector.self_())

	# Knight (enemy) on the same MAP042 baseline tile pair the existing tests
	# use, with a single WAIT gambit so it stands still and the Monk's Attack
	# resolves cleanly.
	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "A1",
		"name": "lower_index_slot_evaluated_first",
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
			"gambit_slot": [{"unit": "Monk", "slot": 0}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _a2_disabled_slot_skipped() -> Dictionary:
	# Slot 0 would normally fire (ATTACK NEAREST_ENEMY, always-pass) but is
	# disabled at the domain layer. The encoder still emits a config Dict — it
	# does NOT skip — so this is distinct from rule E1 (encoder-skip). The
	# shader must read [code]enabled[/code] from the gambit buffer and skip the
	# slot during evaluate_gambits_up_to. Slot 1 (also ATTACK) catches and
	# fires; gambit_fired_at_slot witnesses slot==1.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	slot0.enabled = false
	var slot1 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())

	var wait := Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())

	return {
		"rule": "A2",
		"name": "disabled_slot_not_evaluated",
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
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _a3_and_condition_fails_falls_through() -> Dictionary:
	# Slot 0 carries TWO conditions on the same slot: ALWAYS + TARGET_HP < 50%.
	# Rule D5 says they AND-combine; the second fails against the full-HP
	# Target so the slot drops out of pass-1 and slot 1 (unconditional ATTACK)
	# fires. Distinct from B2 (single-condition false): A3 specifically pins
	# the multi-condition AND-combine inside rule-A's slot ordering.
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always(), GambitCondition.target_hp_below(50.0)],
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
		"rule": "A3",
		"name": "and_condition_false_falls_through_to_next_slot",
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
		},
		"xfail": [],
		"xfail_reason": "",
	}
