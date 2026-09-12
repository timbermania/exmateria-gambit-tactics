extends RefCounted

## Rule group E — encoder UNSUPPORTED (ADR-0023). See [code]docs/gambit-rules.md[/code].
##
## E1 — A gambit authored with any UNSUPPORTED encoder feature is skipped at
## encode time with a [code]push_error[/code]; evaluation falls through to the
## next slot, the unit is not bricked. One scenario per entry in
## [code]GambitEncoder.UNSUPPORTED_*[/code], so promoting any feature out of
## an UNSUPPORTED set flips its scenario from PASS to a loud signal (the
## encoder now returns a valid Dict; the slot fires; gambit_fired_at_slot==0
## flips against the expected slot==1, and the suite reports FAIL — telling
## the author to retire the scenario or rewrite it). Coverage today:
##
##   UNSUPPORTED_CONDITION_TYPES → 7 scenarios (one per entry)
##   UNSUPPORTED_POOL_TYPES      → 1 scenario  (SPECIFIC_UNITS)
##   UNSUPPORTED_RESOLUTIONS     → 3 scenarios (HIGHEST_STAT / LOWEST_STAT / FIRST_IN_ROSTER)
##   UNSUPPORTED_TEAM_FILTERS    → 1 scenario  (ANY)
##   role_filter guard           → 1 scenario  (non-ANY role on TEAM_FILTER)
##
## E2 — Mixed scenario: an unsupported slot in the MIDDLE of the list does not
## break fall-through past it. Slot 0 falls through on a failing condition,
## slot 1 is encoder-skipped, slot 2 catches. The skip count is one
## (slot 1 only), not two, so [code]expect_encoder_skips[/code] still applies.
##
## Every scenario opts in to the [code]push_error[/code] via
## [code]expect_encoder_skips: true[/code] so the log stays clean and the
## runner asserts the skip actually happened (rather than the slot silently
## firing).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector
const UnitRole = ExMateriaSchema.UnitRole



static func scenarios() -> Array:
	return [
		_e1_unsupported_enemy_in_range(),
		_e1_unsupported_ally_in_range(),
		_e1_unsupported_in_range_of(),
		# TARGET_IN_RANGE's E1 scenario is GONE, not xfailed — ADR-0268 dec. 11 drained the
		# type out of `UNSUPPORTED_CONDITION_TYPES` and the kernel now answers it as
		# `COND_IN_RANGE`. A scenario asserting it SKIPS would be asserting the defect. Its
		# replacement is rule D6 in `scenarios_D_conditions.gd`, which witnesses what the type
		# does now — both halves of it, weapon reach and ability vertical.
		_e1_unsupported_enemy_count(),
		_e1_unsupported_ally_count(),
		_e1_unsupported_hp_missing(),
		_e1_unsupported_specific_units_pool(),
		_e1_unsupported_highest_stat_resolution(),
		_e1_unsupported_lowest_stat_resolution(),
		_e1_unsupported_first_in_roster_resolution(),
		_e1_unsupported_team_filter_any(),
		_e1_unsupported_non_any_role_filter(),
		_e2_unsupported_middle_slot_does_not_brick_fallthrough(),
	]


# === Helpers ==================================================================

static func _attack_enemy() -> Gambit:
	"""The supported slot-1 fall-through target reused by every E1 scenario."""
	return Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())


static func _wait() -> Gambit:
	"""WAIT-on-self loadout for the inert target unit."""
	return Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())


static func _skip_scenario(name: String, bad_slot: Gambit) -> Dictionary:
	"""Standard 2-unit MAP042 setup with [bad_slot, fallback ATTACK]. The
	expected verdict is PASS: encoder skips slot 0 → slot 1 fires by tick 150,
	[code]gambit_fired_at_slot[/code] witnesses slot==1."""
	return _multi_slot_scenario(name, [bad_slot, _attack_enemy()], 1)


static func _multi_slot_scenario(
		name: String, gambits: Array, expected_slot: int) -> Dictionary:
	"""Generalized helper for scenarios that need >2 slots (E2)."""
	return {
		"rule": "E1",  # Overridden by callers that test E2 specifically.
		"name": name,
		"map": "MAP042",
		"seed": 42,
		"max_ticks": 300,
		"expect_encoder_skips": true,
		"units": [
			{
				"name": "Monk", "team": 0, "tile": [4, 7],
				"job": "4e", "max_hp": 240, "max_mp": 30,
				"pa": 12, "ma": 8, "wp": 0, "move": 4, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 104,
				"gambits": gambits,
			},
			{
				"name": "Target", "team": 1, "tile": [5, 7],
				"job": "4c", "max_hp": 200, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 4,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 2,
				"body_sprite_id": 0,
				"gambits": [_wait()],
			},
		],
		"expect": {
			"trace": [{
				"kind": "by_tick", "tick": 150,
				"unit": "Monk", "committed": "ATTACK",
			}],
			"gambit_slot": [{"unit": "Monk", "slot": expected_slot}],
		},
		"xfail": [],
		"xfail_reason": "",
	}


static func _bad_cond_slot(cond_type: int) -> Gambit:
	"""Build a slot whose only condition is the given UNSUPPORTED type. The
	condition wouldn't otherwise fire in normal play — what we're witnessing
	is the encoder's [code]push_error[/code] at encode time, not the
	condition's runtime semantics."""
	var bad := GambitCondition.new(
			cond_type,
			GambitCondition.Comparator.LESS_THAN, 1.0)
	return Gambit.create(
			TargetSelector.enemies(),
			[bad],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())


# === E1 — UNSUPPORTED_CONDITION_TYPES (7 entries) =============================

static func _e1_unsupported_enemy_in_range() -> Dictionary:
	return _skip_scenario(
			"unsupported_enemy_in_range_skips_to_next_slot",
			_bad_cond_slot(GambitCondition.Type.ENEMY_IN_RANGE))


static func _e1_unsupported_ally_in_range() -> Dictionary:
	return _skip_scenario(
			"unsupported_ally_in_range_skips_to_next_slot",
			_bad_cond_slot(GambitCondition.Type.ALLY_IN_RANGE))


static func _e1_unsupported_in_range_of() -> Dictionary:
	return _skip_scenario(
			"unsupported_in_range_of_skips_to_next_slot",
			_bad_cond_slot(GambitCondition.Type.IN_RANGE_OF))


static func _e1_unsupported_enemy_count() -> Dictionary:
	return _skip_scenario(
			"unsupported_enemy_count_skips_to_next_slot",
			_bad_cond_slot(GambitCondition.Type.ENEMY_COUNT))


static func _e1_unsupported_ally_count() -> Dictionary:
	return _skip_scenario(
			"unsupported_ally_count_skips_to_next_slot",
			_bad_cond_slot(GambitCondition.Type.ALLY_COUNT))


static func _e1_unsupported_hp_missing() -> Dictionary:
	return _skip_scenario(
			"unsupported_hp_missing_skips_to_next_slot",
			_bad_cond_slot(GambitCondition.Type.HP_MISSING))


# === E1 — UNSUPPORTED_POOL_TYPES (1 entry) ====================================

static func _e1_unsupported_specific_units_pool() -> Dictionary:
	# condition_target is a SPECIFIC_UNITS pool — no GPU equivalent (ADR-0023).
	# Encoder returns null at _target_selector_to_gpu's pool-type guard.
	var names: Array[String] = ["Phantom"]
	var slot0 := Gambit.create(
			TargetSelector.specific(names),
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	return _skip_scenario(
			"unsupported_specific_units_pool_skips_to_next_slot",
			slot0)


# === E1 — UNSUPPORTED_RESOLUTIONS (3 entries) =================================

static func _e1_unsupported_highest_stat_resolution() -> Dictionary:
	# TEAM_FILTER + HIGHEST_STAT resolution — no GPU equivalent (the GPU's
	# target enums don't carry a stat axis).
	var sel := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.HIGHEST_STAT, &"PA")
	var slot0 := Gambit.create(
			sel,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	return _skip_scenario(
			"unsupported_highest_stat_resolution_skips_to_next_slot",
			slot0)


static func _e1_unsupported_lowest_stat_resolution() -> Dictionary:
	var sel := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.LOWEST_STAT, &"PA")
	var slot0 := Gambit.create(
			sel,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	return _skip_scenario(
			"unsupported_lowest_stat_resolution_skips_to_next_slot",
			slot0)


static func _e1_unsupported_first_in_roster_resolution() -> Dictionary:
	var sel := TargetSelector.enemies().with_resolution(
			TargetSelector.ResolutionStrategy.FIRST_IN_ROSTER)
	var slot0 := Gambit.create(
			sel,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	return _skip_scenario(
			"unsupported_first_in_roster_resolution_skips_to_next_slot",
			slot0)


# === E1 — UNSUPPORTED_TEAM_FILTERS (1 entry) ==================================

static func _e1_unsupported_team_filter_any() -> Dictionary:
	# No factory for TeamFilter.ANY (GPU targets are ally/enemy-specific, so
	# the domain factories only emit FRIENDLY / ENEMY). Build the selector by
	# hand to witness the UNSUPPORTED_TEAM_FILTERS guard.
	var sel := TargetSelector.new()
	sel.pool_type = TargetSelector.PoolType.TEAM_FILTER
	sel.team_filter = TargetSelector.TeamFilter.ANY
	sel.resolution = TargetSelector.ResolutionStrategy.NEAREST_FIRST
	var slot0 := Gambit.create(
			sel,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	return _skip_scenario(
			"unsupported_team_filter_any_skips_to_next_slot",
			slot0)


# === E1 — non-ANY role_filter guard (1 entry, code-path not value-set) ========

static func _e1_unsupported_non_any_role_filter() -> Dictionary:
	# A non-ANY role_filter has no GPU equivalent — guarded by an inline check
	# in _target_selector_to_gpu (not by a UNSUPPORTED_* const), so this
	# scenario covers a different code path from the four value-set scenarios
	# above. Any non-ANY role works; MELEE is convenient.
	var sel := TargetSelector.enemies(UnitRole.Role.MELEE)
	var slot0 := Gambit.create(
			sel,
			[GambitCondition.always()],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	return _skip_scenario(
			"unsupported_non_any_role_filter_skips_to_next_slot",
			slot0)


# === E2 — Mixed: unsupported MIDDLE slot doesn't brick fall-through past it ===

static func _e2_unsupported_middle_slot_does_not_brick_fallthrough() -> Dictionary:
	# Slot 0: ATTACK gated on TARGET_HP < 50% — fails against the full-HP
	#   target, so pass-1 skips slot 0 (normal B2-style fall-through).
	# Slot 1: ATTACK with an UNSUPPORTED ENEMY_COUNT condition — the encoder
	#   skips it (null in the GPU buffer).
	# Slot 2: ATTACK unconditional — catches; gambit_fired_at_slot witnesses
	#   slot==2.
	# Exactly one encoder skip (slot 1), so [code]expect_encoder_skips[/code]
	# stays asserting "≥ 1 skip observed."
	var slot0 := Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_hp_below(50.0)],
			Gambit.ActionKind.ATTACK, -1,
			TargetSelector.triggering())
	var slot1 := _bad_cond_slot(GambitCondition.Type.ENEMY_COUNT)
	var slot2 := _attack_enemy()
	var scenario := _multi_slot_scenario(
			"mixed_unsupported_middle_slot_does_not_brick_fallthrough",
			[slot0, slot1, slot2],
			2)
	scenario["rule"] = "E2"
	return scenario
