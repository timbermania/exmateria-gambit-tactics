extends GPUCombatTestBase
# test-kind: gpu
# seeded-break: CombatLoop's AOE effect-spawn gate — `AbilityFamily.is_ally_side(...)` -> `AbilityDatabase.is_healing(ability_id)` (the pre-#1148 spelling) — Chakra reads is_healing == false, so the gate keeps `unit_team != caster_team` and the two effects spawn on the FOES instead of the party -> `[FAIL] ... recipients were team 1`; GREEN unbroken on the reverted tree

## GPU AOE Effect-Side Test — which SIDE an AoE ability draws its effect on (#1148)
##
## `CombatLoop._on_spell_cast_complete` walks every unit inside `effect_area` and spawns
## the spell effect on the ones the ability is FOR. That side used to be read off
## `AbilityDatabase.is_healing`, which is the HP-WRITE DIRECTION and a different axis from
## the ability's FAMILY (`docs/context/07-ability-hit-policy.md`). ADR-0278 landed
## [AbilityFamily] as the member that answers the family question, and #1148 pointed this
## call site at it.
##
## === WHY `Chakra` AND NOT `Protect` =========================================================
##
## The branch is an `elif` under `is_cinematic` (`ct > 0 and not is_item`), so every CHARGED
## ability — `Protect`, `Shell`, `Haste`, `Esuna`, every Song — spawns through
## `CinematicManager` instead and never reaches this gate at all. Of the 193 records whose
## shape fits the branch only **77** are non-cinematic non-items, and the old gate is
## inverted on **15** of those: `Murasame`, `Kiyomori`, `Masamune`, `StigmaMagic`, `Chakra`
## and ten unreachable ones. Those five are the whole reachable blast radius, and `Chakra`
## is the cheapest of them (MP 0, CT 0, `effect_area` 1).
##
## === WHY A COUNT CANNOT BE THE REFEREE ======================================================
##
## The formation is symmetric about the caster, so **two** units receive the effect on BOTH
## sides of the fix — the inversion is invisible to `recipients.size()`. What the test asserts
## is the recipients' TEAM, observed at the `spell_effect_hook` seam (ADR-0018), which is the
## cheapest instrument that can actually see it.
##
## Setup — `Chakra` is `range 0`, so it centres on the caster's own tile:
##
##     (2,1) Foe        team 1, d=1
##     (2,2) Monk       team 0, d=0   <- caster, targets SELF
##     (2,3) Ally       team 0, d=1
##     (3,2) Foe2       team 1, d=1
##
## All four are inside `effect_area` 1. Ally-side -> {Monk, Ally}. Foe-side -> {Foe, Foe2}.

const ABILITY_CHAKRA = 106
const TEAM0_COUNT = 2

var _recipients: Array[int] = []
var _verdict_pending: bool = false
var _finished: bool = false


func get_test_name() -> String:
	return "GPU AOE Effect Side Test"


func get_team0_unit_configs() -> Array:
	return [
		{
			"name": "Monk",
			"pos_x": 2, "pos_z": 2,
			"hp": 200, "max_hp": 200,
			"pa": 10, "ma": 10, "wp": 5,
			"brave": 50, "faith": 50,
			"mp": 99, "max_mp": 99,
			"speed": 100,          # acts first, and often
			"move": 0, "jump": 3,  # pinned: the AoE must stay centred on (2,2)
			"weapon_range": 1, "weapon_flags": 1,
			"body_sprite_id": 0x02,
		},
		{
			"name": "Ally",
			"pos_x": 2, "pos_z": 3,
			"hp": 200, "max_hp": 200,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 10, "max_mp": 10,
			"speed": 1,            # never acts
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1,
			"body_sprite_id": 0x03,
		},
	]


func get_team1_unit_configs() -> Array:
	return [
		{
			"name": "Foe",
			"pos_x": 2, "pos_z": 1,
			"hp": 500, "max_hp": 500,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 10, "max_mp": 10,
			"speed": 1,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1,
			"body_sprite_id": 0x05,
		},
		{
			"name": "Foe2",
			"pos_x": 3, "pos_z": 2,
			"hp": 500, "max_hp": 500,
			"pa": 1, "ma": 1, "wp": 1,
			"brave": 50, "faith": 50,
			"mp": 10, "max_mp": 10,
			"speed": 1,
			"move": 0, "jump": 3,
			"weapon_range": 1, "weapon_flags": 1,
			"body_sprite_id": 0x06,
		},
	]


func get_gambits_for_unit(unit_idx: int, _team: int) -> Array:
	# Only the Monk acts. Everyone else waits, so the ONLY effect spawn in the run is
	# the one under test and the recipient set is unambiguous.
	if unit_idx == 0:
		return [make_spell_gambit(ABILITY_CHAKRA, GPUConstants.TARGET_SELF)]
	return [{
		"enabled": true,
		"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
		"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
		"action_type": GPUConstants.ACTION_WAIT,
		"action_id": 0,
		"action_target_type": GPUConstants.TARGET_SELF,
	}]


## Seam override (ADR-0018): record WHO got the effect, then forward.
##
## One cast spawns its whole recipient set inside a single synchronous walk, so the verdict
## is deferred by one frame rather than taken on the first spawn — taking it early would
## read a set of size 1 whichever side the gate picked.
func _spawn_spell_effect(caster: Unit, target: Unit, ability_id: int, effect_id: int):
	var idx := units.find(target)
	_recipients.append(idx)
	print("  [AOE_SIDE] effect for %s (unit %d, team %d)" % [
		target.name if is_instance_valid(target) else "?", idx, 0 if idx < TEAM0_COUNT else 1])
	super(caster, target, ability_id, effect_id)
	if not _verdict_pending:
		_verdict_pending = true
		_finish.call_deferred()


func _finish() -> void:
	if _finished:
		return
	_finished = true

	var teams := {}
	for idx in _recipients:
		teams[0 if idx < TEAM0_COUNT else 1] = true
	var failures: Array[String] = []
	var asserts := 0

	# 1. The side. This is the assertion #1148 is about.
	asserts += 1
	if teams.has(1):
		failures.append("a FOE received the ally-side Chakra effect")
	elif not teams.has(0):
		failures.append("no unit received the effect at all")

	# 2. The caster is IN its own range-0 AoE. Free on this setup (clause 13) and it is the
	#    half a side-only assertion misses: a gate that drew on the Ally alone would pass 1.
	asserts += 1
	if not _recipients.has(0):
		failures.append("the caster is at the centre of its own range-0 AoE and got nothing")

	# 3. Both team-0 units are in radius, so both must be drawn on — the symmetric count that
	#    proves the walk ran the whole radius rather than stopping at the centre. It is also
	#    the count that is EQUAL on both sides of the fix, which is why it cannot be alone.
	asserts += 1
	if _recipients.size() != 2 or not _recipients.has(1):
		failures.append("expected the effect on units 0 and 1")

	if failures.is_empty():
		print("\n[PASS] %d/%d assertions — AoE Chakra drew its effect on the caster's own party (units %s), not the enemy" % [
			asserts, asserts, str(_recipients)])
	else:
		print("\n[FAIL] %d/%d assertions — recipients=%s: %s" % [
			asserts - failures.size(), asserts, str(_recipients), "; ".join(failures)])
	get_tree().quit()


func on_victory(_winning_team: int):
	if not _finished:
		print("\n[FAIL] 0/3 assertions — combat ended without Chakra ever spawning an effect")
		get_tree().quit()
