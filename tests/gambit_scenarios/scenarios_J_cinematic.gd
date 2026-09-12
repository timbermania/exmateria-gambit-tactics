extends RefCounted

## Rule group J — cinematic-spell. See [code]docs/gambit-rules.md[/code].
##
## J-group witnesses the three observable side-effects of the cinematic-spell
## path (charge_time > 0 abilities routed through
## [code]cast_cinematic_spell[/code] at stage_spell.glsl :515):
##
##   J1: non-caster units have [code]U_PAUSED = 1[/code] for the duration of
##       the cinematic.
##   J2: the caster's [code]stage_compute[/code] / [code]stage_spell[/code]
##       keep running so the orchestrator advances and the cinematic ends.
##   J3: [code]cinematic_teardown[/code] (stage_spell.glsl :710) clears
##       [code]U_PAUSED[/code] on every unit and resets
##       [code]BH_CINEMATIC_CASTER_IDX = -1[/code].
##
## All three are folded into a single [code]cinematic_lifecycle[/code]
## predicate per (caster, non_caster) pair:
##   - The "paused during" half of the predicate satisfies J1.
##   - The "unpaused after" half satisfies J3 — and is only reachable if J2
##     held (a stuck cinematic would never tear down).
##
## Why Cure-on-SELF is the cradle (and the predecessor handoff said so):
##   Cure has [code]ct = 4[/code] which routes through the cinematic path,
##   and the SELF target avoids needing an injured-ally setup. The same
##   shape is used by H1 (scenarios_H_state_machine.gd); we just witness
##   different observables off the same cinematic window. A non-caster
##   ("DistantKnight" here, matching the H1 fixture spirit) is the unit
##   whose [code]U_PAUSED[/code] toggles.
##
## Why a "no-cinematic" negative control isn't included:
##   The instant-spell path (charge_time = 0) doesn't run cinematic_spell at
##   all, so the per-tick [code]cinematic_caster_idx[/code] stays -1 the
##   whole time and the predicate trivially fails its J1-half. A scenario
##   that pinned that would only re-check the trace-logger surface, not
##   any rule-J behavior. Skip until the J-group rule explicitly requires
##   the negation.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector



const ABILITY_CURE := 1            # mp_cost=6, ct=4, range=4, effect_area=1


static func scenarios() -> Array:
	return [
		_j1_non_caster_paused_during_cure_cinematic(),
		_j2_j3_caster_continues_and_teardown_clears_pause(),
	]


# Helper — the Cure-on-SELF gambit shape, shared across J1 and J2/J3.
# Carried inline rather than imported from scenarios_C / scenarios_H so the
# J-file stays self-contained per the rule-group isolation pattern (see
# scenarios_H_state_machine.gd, which similarly duplicates its Cure-on-SELF
# slot factory).
static func _cure_self_slot() -> Gambit:
	return Gambit.create(
			TargetSelector.self_(),
			[GambitCondition.always()],
			Gambit.ActionKind.ABILITY, ABILITY_CURE,
			TargetSelector.self_())


static func _wait_slot() -> Gambit:
	return Gambit.create(
			TargetSelector.self_(), [GambitCondition.always()],
			Gambit.ActionKind.WAIT, -1, TargetSelector.self_())


# === J1 ===============================================================

static func _j1_non_caster_paused_during_cure_cinematic() -> Dictionary:
	# Priest casts Cure on SELF (always-valid condition target). Cure's
	# ct=4 charge_time pushes the spell through cast_cinematic_spell, which
	# writes BH_CINEMATIC_CASTER_IDX = Priest and U_PAUSED = 1 on every other
	# unit (stage_spell.glsl :577-580). The non-caster DistantKnight at
	# (8, 4) sits well outside Cure's AoE radius so the heal-side state of
	# the AoE walker doesn't touch them — the only field the scenario cares
	# about is their U_PAUSED flag during the cinematic window.
	#
	# J1's witness is the "paused-during" half of cinematic_lifecycle. The
	# "unpaused-after" half also fires (the cinematic does tear down within
	# the budget), which doubles as a J3 sanity check, but J1's spec-aligned
	# half is the snapshot at which paused=1 lined up with cinematic_caster.
	return {
		"rule": "J1",
		"name": "non_caster_paused_during_cure_cinematic",
		"map": "MAP042",
		"seed": 42,
		# Charge (4 ticks of CT) + cinematic playback need a generous
		# budget; H1a's 130-tick SPELL_CHARGING window suggests the full
		# cycle lands well under 400 ticks but the non-caster's
		# U_PAUSED=1→0 round trip must be observable inside the trace.
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
				# Non-caster, sufficiently far from Priest that no Cure-AoE
				# radius could engulf them — only U_PAUSED gets written.
				"name": "DistantKnight", "team": 1, "tile": [8, 4],
				"job": "4c", "max_hp": 999, "max_mp": 0,
				"pa": 1, "ma": 1, "wp": 1, "move": 0, "jump": 3,
				"weapon_range": 1, "weapon_flags": 1, "weapon_type": 0,
				"body_sprite_id": 0x05,
				"gambits": [_wait_slot()],
			},
		],
		"expect": {
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


# === J2 + J3 ==========================================================

static func _j2_j3_caster_continues_and_teardown_clears_pause() -> Dictionary:
	# Same fixture as J1; the lifecycle predicate's two halves separately
	# cover J3 ("teardown clears U_PAUSED") and J2 ("caster's stage_compute
	# / stage_spell continue" — implicit, because if J2 regressed the
	# cinematic would never tear down).
	#
	# Authored as a second scenario rather than folded into J1's expect
	# block so the rule-index reporting matches gambit-rules.md one-to-one
	# (J1, J2, J3 are independent rules). The predicate result text makes
	# both halves observable in the verdict log.
	#
	# A future tighter J2 test would inspect the caster's per-tick state
	# transitions during the cinematic (ACTING → IDLE on cinematic end),
	# but the existing trace logger already records those state_events;
	# adding a J2-specific predicate would be duplicate machinery for a
	# rule that's already implicit in J3 holding.
	return {
		"rule": "J2_J3",
		"name": "caster_continues_and_teardown_clears_paused",
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
