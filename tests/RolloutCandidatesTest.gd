extends Node
# test-kind: logic
# seeded-break: aim the withdraw posture at the caster in src/gpu/RolloutPlaybook.gd:297 (`TargetSelector.triggering()` -> `TargetSelector.self_()`) — 'a retreat is aimed at the CASTER' reds in all five roles, which is property 6: retreat_step_cell refuses flee_from == unit_id, so the row encodes cleanly and can never fire
# seeded-break: stop appending the incumbent in src/gpu/RolloutCandidates.gd:259 (`out.append(incumbent)` -> `pass`), leaving the `seen[_key(incumbent)]` mark in place so it can never rejoin the list — 'candidate 0 must be the UNMUTATED incumbent' reds, which is property 1: without it the beat has no leave-it-alone arm

## Pure `RolloutCandidates` test (#895, §7). No GPU / RenderingDevice / scene.
##
## Guards the candidate set's four load-bearing properties:
##
##   1. **The incumbent is candidate 0.** Without it the beat has no "leave it
##      alone" arm and the AI must change its gambits every turn.
##   2. **The safety net is never edited.** Every operator works on user slots
##      only; slot `MAX_USER_GAMBITS` is ADR-0048's terminal candidate, and a
##      rollout that mutated it would be scoring a unit that can strand itself.
##   3. **The list is deterministic and duplicate-free.** §7's second reason for
##      common random numbers is that the AI's choice be reproducible, and a
##      duplicated candidate spends a battle slot to learn a number it already has.
##   4. **The prefilter is static-only and it BITES.** An ability the unit cannot
##      have, and one whose `mp_cost` exceeds its MAX MP, never appear in any
##      candidate's action field. Nothing dynamic is checked here — that stays in
##      the shader (see `RolloutCandidates`' header).
##   5. **A revive is only ever aimed at a corpse (#1104).** Its own bucket, split
##      off by the ability table's inflict list, and one posture per unit that can
##      raise — in every role, because the raisers sit on a MAGE job. A revive filed
##      by its HEALING bit alone is a posture that encodes cleanly and cannot work.
##   6. **A retreat is never aimed at the caster, and the verb is playbook-only
##      (#1104 / ADR-0301).** `retreat_step_cell` refuses `flee_from == unit_id`, so
##      a withdraw posture aimed at `self_()` is a row that can never fire. And no
##      mutation family can introduce `ACTION_RETREAT_STEP` into a list that has
##      none — which is what the posture is FOR, and what makes its position at the
##      head of the playbook load-bearing rather than cosmetic.
##
## Plus the interleave: a K smaller than the full enumeration must still touch
## several families, because dropping whole families biases the search.

const GF := GPUCombatPacker.GambitField
const GAMBITS_PER_UNIT := GPUCombatPacker.GAMBITS_PER_UNIT
const GAMBIT_SIZE := GPUConstants.GAMBIT_SIZE
const MAX_USER_GAMBITS := GPUConstants.MAX_USER_GAMBITS
const ABILITY_SIZE := GPUConstants.ABILITY_SIZE
const MAX_ABILITIES := GPUConstants.MAX_ABILITIES

# Three ids planted in a synthetic ability table: one affordable attack spell,
# one affordable heal, one whose MP cost is out of reach forever.
const ID_CHEAP := 16
const ID_HEAL := 17
const ID_UNAFFORDABLE := 18
const UNIT_MAX_MP := 50

# The revive pair (#1104). `ID_REVIVE` carries ABFLAG_HEALING **as well as** the
# cancel-Dead inflict list, because the shipped `Raise` does: it is
# `receive_heal` with `inflict_statuses: ["Dead"], inflict_mode: "cancel"`. So
# this id is also the arm that says which bucket WINS — get that backwards and
# `_mend_postures` spends a posture casting a raise at the worst-off LIVING ally.
const ID_REVIVE := 19
const ID_REVIVE_UNAFFORDABLE := 20

const UnitRole = ExMateriaSchema.UnitRole
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const TargetSelector = ExMateriaAlmanac.TargetSelector

# Every role the playbook switches on. The revive posture is offered to all of
# them on purpose (#1104): `JobDatabase.JOB_ROLES` makes Priest — the job that
# learns Raise and Raise2 — a MAGE, so keying the verb to HEALER would withhold
# it from the only generic job whose own skill set can raise the dead.
const ALL_ROLES: Array[int] = [
	UnitRole.Role.MELEE, UnitRole.Role.RANGED, UnitRole.Role.MAGE,
	UnitRole.Role.HEALER, UnitRole.Role.HYBRID,
]

var _failed := false


func _ready() -> void:
	_test_prefilter()
	_test_incumbent_and_shape()
	_test_safety_net_untouched()
	_test_deterministic_and_deduped()
	_test_interleave()
	_test_unaffordable_never_offered()
	_test_revive_bucket_and_posture()
	_test_withdraw_posture()
	_test_rows_round_trip()
	if _failed:
		print("[FAIL] RolloutCandidates test")
	else:
		print("[PASS] RolloutCandidates: incumbent-first, safety-net intact, deterministic, static prefilter bites, a revive is only ever aimed at a corpse, a retreat never at the caster")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		print("[FAIL] %s" % msg)


## A minimal ability table with the same layout `GPUAbilityLoader.build` emits.
## Synthetic on purpose: the real table's costs move with the ROM data, and a
## prefilter test that depends on Fire costing 6 MP is a test of the ROM.
func _ability_buffer() -> PackedInt32Array:
	var buf := PackedInt32Array()
	buf.resize(MAX_ABILITIES * ABILITY_SIZE)
	buf[ID_CHEAP * ABILITY_SIZE + GPUCombatPacker.AbilityField.MP_COST] = 10
	buf[ID_HEAL * ABILITY_SIZE + GPUCombatPacker.AbilityField.MP_COST] = 12
	buf[ID_HEAL * ABILITY_SIZE + GPUCombatPacker.AbilityField.FLAGS] = RolloutCandidates.ABFLAG_HEALING
	buf[ID_UNAFFORDABLE * ABILITY_SIZE + GPUCombatPacker.AbilityField.MP_COST] = UNIT_MAX_MP + 1
	for revive_id in [ID_REVIVE, ID_REVIVE_UNAFFORDABLE]:
		var base: int = revive_id * ABILITY_SIZE
		buf[base + GPUCombatPacker.AbilityField.FLAGS] = RolloutCandidates.ABFLAG_HEALING
		buf[base + GPUCombatPacker.AbilityField.INFLICT_MODE] = RolloutCandidates.INFLICT_MODE_CANCEL
		buf[base + GPUCombatPacker.AbilityField.INFLICT_MASK] = \
			1 << ExMateriaAlmanac.StatusRegistry.bit(&"dead")
	buf[ID_REVIVE * ABILITY_SIZE + GPUCombatPacker.AbilityField.MP_COST] = 14
	buf[ID_REVIVE_UNAFFORDABLE * ABILITY_SIZE + GPUCombatPacker.AbilityField.MP_COST] = UNIT_MAX_MP + 1
	return buf


func _ctx() -> Dictionary:
	# '4a' is Squire. The role only selects which postures the playbook offers;
	# every assertion here holds for any of them.
	return RolloutCandidates.make_context(
		"4a", [ID_CHEAP, ID_HEAL, ID_UNAFFORDABLE], UNIT_MAX_MP, _ability_buffer())


## Two enabled user slots: attack-nearest, and a spell. Encoded through the real
## encoder path so the fixture is the shape a live unit actually carries —
## including ADR-0048's injected safety net at slot MAX_USER_GAMBITS.
func _fixture_rows() -> PackedInt32Array:
	var configs: Array = [
		{
			"enabled": true,
			"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
			"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
			"action_type": GPUConstants.ACTION_ATTACK,
			"action_id": 0,
			"action_target_type": GPUConstants.TARGET_THEM,
		},
		{
			"enabled": true,
			"cond_target_type": GPUConstants.TARGET_LOWEST_HP_ENEMY,
			"conditions": [{"type": GPUConstants.COND_HP_BELOW, "value": 40}],
			"action_type": GPUConstants.ACTION_SPELL,
			"action_id": ID_CHEAP,
			"action_target_type": GPUConstants.TARGET_THEM,
		},
		null, null, null,
		{
			"enabled": true,
			"cond_target_type": GPUConstants.TARGET_NEAREST_ENEMY,
			"conditions": [{"type": GPUConstants.COND_ALWAYS, "value": 0}],
			"action_type": GPUConstants.ACTION_ATTACK,
			"action_id": 0,
			"action_target_type": GPUConstants.TARGET_THEM,
		},
	]
	return GPUCombatPacker._pack_gambits(configs)


func _test_prefilter() -> void:
	var split := RolloutCandidates.usable_abilities(
		[ID_CHEAP, ID_HEAL, ID_UNAFFORDABLE], UNIT_MAX_MP, _ability_buffer())
	_expect(split["offensive"] == [ID_CHEAP],
		"offensive should be [%d], got %s" % [ID_CHEAP, str(split["offensive"])])
	_expect(split["healing"] == [ID_HEAL],
		"healing should be [%d] (ABFLAG_HEALING), got %s" % [ID_HEAL, str(split["healing"])])

	# A too-small table is an error, not an empty roster silently returned as if
	# the unit had no abilities.
	var short := RolloutCandidates.usable_abilities([ID_CHEAP], UNIT_MAX_MP, PackedInt32Array())
	_expect(short["offensive"].is_empty() and short["healing"].is_empty()
			and short["revive"].is_empty(),
		"a malformed ability table must yield no abilities (it also push_errors)")


func _test_incumbent_and_shape() -> void:
	var rows := _fixture_rows()
	var cands := RolloutCandidates.generate(rows, _ctx(), 40)
	_expect(cands.size() > 1, "expected a populated candidate set, got %d" % cands.size())
	if cands.is_empty():
		return
	_expect((cands[0] as PackedInt32Array) == rows,
		"candidate 0 must be the UNMUTATED incumbent")
	for i in range(cands.size()):
		var c: PackedInt32Array = cands[i]
		_expect(c.size() == GAMBITS_PER_UNIT,
			"candidate %d is %d ints, expected %d" % [i, c.size(), GAMBITS_PER_UNIT])


func _test_safety_net_untouched() -> void:
	var rows := _fixture_rows()
	var net_base := MAX_USER_GAMBITS * GAMBIT_SIZE
	var net := rows.slice(net_base, net_base + GAMBIT_SIZE)
	_expect(net[GF.ENABLED] != 0, "fixture's safety net should be enabled (ADR-0048)")
	var cands := RolloutCandidates.generate(rows, _ctx(), 200)
	for i in range(cands.size()):
		var c: PackedInt32Array = cands[i]
		_expect(c.slice(net_base, net_base + GAMBIT_SIZE) == net,
			"candidate %d edited the safety-net slot %d" % [i, MAX_USER_GAMBITS])


func _test_deterministic_and_deduped() -> void:
	var rows := _fixture_rows()
	var a := RolloutCandidates.generate(rows, _ctx(), 64)
	var b := RolloutCandidates.generate(rows, _ctx(), 64)
	_expect(a.size() == b.size(), "two generations differ in size: %d vs %d" % [a.size(), b.size()])
	for i in range(mini(a.size(), b.size())):
		_expect((a[i] as PackedInt32Array) == (b[i] as PackedInt32Array),
			"candidate %d differs between two generations — the set is not reproducible" % i)

	var seen := {}
	for i in range(a.size()):
		var key: String = (a[i] as PackedInt32Array).to_byte_array().hex_encode()
		_expect(not seen.has(key), "candidate %d duplicates candidate %d" % [i, seen.get(key, -1)])
		seen[key] = i


## A K too small for the full enumeration must still spread across families —
## taking the first K in family order would spend every slot on `swap`.
##
## 🔴 THE FIRST ARM IS THE ONE A SEEDED DEFECT FOUND MISSING. `families()`
## ENUMERATES and `FAMILIES` INTERLEAVES, and they are two lists. Drop a name
## from `FAMILIES` and its whole family becomes unreachable through `generate`
## while `families()` still cheerfully produces it — a search space that silently
## shrank, with every other assertion here still green (the earlier version of
## this test walked `FAMILIES` to check coverage, so removing a name removed the
## check along with the family). The enumeration's own keys are the oracle.
func _test_interleave() -> void:
	var rows := _fixture_rows()
	var ctx := _ctx()
	var fam := RolloutCandidates.families(rows, ctx)

	for name in fam.keys():
		_expect(RolloutCandidates.FAMILIES.has(name),
			"family '%s' is enumerated but not in FAMILIES — generate() can never offer it" % name)
	for name in RolloutCandidates.FAMILIES:
		_expect(fam.has(name), "FAMILIES names '%s', which families() does not produce" % name)

	var total := 0
	for name in fam.keys():
		_expect(not (fam[name] as Array).is_empty(), "family '%s' produced nothing" % name)
		total += (fam[name] as Array).size()
	_expect(total > 8, "the enumeration is only %d candidates — too small to test truncation" % total)

	# One incumbent plus one candidate per family: the smallest K at which every
	# family must be represented, and the tightest statement of "interleaved".
	var k := 1 + fam.size()
	var small := RolloutCandidates.generate(rows, ctx, k)
	_expect(small.size() == k, "K=%d should fill %d candidates, got %d" % [k, k, small.size()])
	var families_hit := {}
	for i in range(1, small.size()):
		var key: String = (small[i] as PackedInt32Array).to_byte_array().hex_encode()
		for name in fam.keys():
			for c in fam[name]:
				if (c as PackedInt32Array).to_byte_array().hex_encode() == key:
					families_hit[name] = true
					break
	_expect(families_hit.size() == fam.size(),
		"K=%d reached %d of %d families (%s) — truncation is dropping whole families" % [
			k, families_hit.size(), fam.size(), str(families_hit.keys())])


func _test_unaffordable_never_offered() -> void:
	var rows := _fixture_rows()
	var cands := RolloutCandidates.generate(rows, _ctx(), 300)
	var saw_cheap := false
	for i in range(cands.size()):
		var c: PackedInt32Array = cands[i]
		for slot in range(MAX_USER_GAMBITS):
			if c[slot * GAMBIT_SIZE + GF.ACTION_TYPE] != GPUConstants.ACTION_SPELL:
				continue
			var id := c[slot * GAMBIT_SIZE + GF.ACTION_ID]
			_expect(id != ID_UNAFFORDABLE,
				"candidate %d slot %d offers ability %d, whose MP cost exceeds the unit's MAX MP" % [
					i, slot, ID_UNAFFORDABLE])
			if id == ID_CHEAP:
				saw_cheap = true
	# The positive control: without it, "the unaffordable id never appears" would
	# also pass if NO ability were ever offered.
	_expect(saw_cheap, "no candidate offered the affordable ability %d — the arm above is blind" % ID_CHEAP)


## The revive bucket and the posture it feeds (#1104).
##
## 🔴 THE BUCKET IS THE FIX, NOT THE POSTURE. Before it, a cancel-Dead ability was
## filed by its HEALING bit alone, and both answers were wrong in a way that
## ENCODES CLEANLY: `Raise` is `receive_heal`, so `_mend_postures` aimed it at the
## worst-off LIVING ally, and `Revive` (107) is not, so `_ability_postures` authored
## "cast it at the nearest ENEMY, always" — formula 0x35, a percentage heal, pointed
## at the other team. So the load-bearing arm here is the NEGATIVE one: every gambit
## that names a revive, in every posture of every role, must aim at the KO-inclusive
## ally pool under IS_KO and nothing else.
##
## The positive arm compares against the image `scenarios_F_actions.gd`'s F7/F8 watch
## revive a real corpse on the GPU, so what is asserted is not "some KO-ish gambit"
## but the exact three fields a battle has already run.
func _test_revive_bucket_and_posture() -> void:
	var buf := _ability_buffer()
	var split := RolloutCandidates.usable_abilities(
		[ID_CHEAP, ID_HEAL, ID_REVIVE, ID_REVIVE_UNAFFORDABLE, ID_UNAFFORDABLE],
		UNIT_MAX_MP, buf)
	_expect(split["revive"] == [ID_REVIVE],
		"revive should be [%d], got %s — the MP ceiling applies to this bucket too, so %d is out" % [
			ID_REVIVE, str(split["revive"]), ID_REVIVE_UNAFFORDABLE])
	_expect(split["healing"] == [ID_HEAL],
		"a cancel-Dead ability must LEAVE the healing bucket even though ABFLAG_HEALING is set on it — got %s" % str(split["healing"]))
	_expect(split["offensive"] == [ID_CHEAP],
		"offensive should be [%d], got %s" % [ID_CHEAP, str(split["offensive"])])
	_expect(RolloutCandidates.ability_revives(ID_REVIVE, buf)
			and not RolloutCandidates.ability_revives(ID_HEAL, buf),
		"ability_revives must read the cancel-Dead inflict list and nothing else")

	# The image F7/F8 prove in battle: KO-inclusive ally pool + IS_KO + the revive.
	var proven := GPUCombatPacker._pack_gambits(GambitEncoder.encode_gambits([
		Gambit.create(
			TargetSelector.friendlies_or_ko(), [GambitCondition.is_ko()],
			Gambit.ActionKind.ABILITY, ID_REVIVE, TargetSelector.triggering()),
	])).slice(0, GAMBIT_SIZE)
	_expect(proven[GF.COND_TARGET_TYPE] == GPUConstants.TARGET_NEAREST_ALLY_OR_KO
			and proven[GF.COND_TYPE_0] == GPUConstants.COND_IS_DEAD
			and proven[GF.ACTION_TYPE] == GPUConstants.ACTION_SPELL
			and proven[GF.ACTION_ID] == ID_REVIVE,
		"the reference image is not the revive triple — this arm's oracle is broken, not the playbook")

	for role in ALL_ROLES:
		var name: String = UnitRole.get_role_name(role)
		# The buckets are `split`'s, never literals: the negative arm below is only as
		# strong as the filing it reads, and a hand-written `[ID_HEAL]` cannot see a
		# revive that was filed into TWO buckets.
		var postures := RolloutPlaybook.postures_for(
			role, split["offensive"], split["healing"], split["revive"])
		var without := RolloutPlaybook.postures_for(
			role, split["offensive"], split["healing"], [])
		_expect(postures.size() == without.size() + 1,
			"%s: a revive ability should add exactly ONE posture (%d vs %d)" % [
				name, postures.size(), without.size()])
		_expect(not postures.is_empty(), "%s: no postures at all" % name)
		if postures.is_empty():
			continue

		# First, because no one-step mutation can reach it: neither COND_IS_DEAD nor
		# TARGET_NEAREST_ALLY_OR_KO is in RolloutCandidates' menus, so when K truncates
		# the playbook family this is the posture that must survive.
		var encoded: Array = GambitEncoder.encode_gambits(postures[0])
		for i in range(mini(postures[0].size(), encoded.size())):
			_expect(encoded[i] != null,
				"%s: the revive posture's gambit %d did not encode (ADR-0023 skip)" % [name, i])
		var head := GPUCombatPacker._pack_gambits(encoded).slice(0, GAMBIT_SIZE)
		_expect(head == proven,
			"%s: the revive posture's slot 0 is not the image F7/F8 prove in battle — got %s" % [
				name, str(head)])

		# The negative arm. A revive named anywhere else is the defect this ticket's
		# note predicts ("authored via a status check ... encodes cleanly and never
		# fires"), and it would sit inside a rollout nobody watches.
		var revive_sites := 0
		for posture in postures:
			var configs: Array = GambitEncoder.encode_gambits(posture)
			for i in range(mini(posture.size(), configs.size())):
				var cfg = configs[i]
				if cfg == null or int(cfg.get("action_id", -1)) != ID_REVIVE:
					continue
				if int(cfg.get("action_type", -1)) != GPUConstants.ACTION_SPELL:
					continue
				revive_sites += 1
				_expect(int(cfg["cond_target_type"]) == GPUConstants.TARGET_NEAREST_ALLY_OR_KO,
					"%s: a revive is aimed at pool %d, not the KO-inclusive ally pool" % [
						name, int(cfg["cond_target_type"])])
				var conds: Array = cfg.get("conditions", [])
				_expect(conds.size() == 1 and int(conds[0]["type"]) == GPUConstants.COND_IS_DEAD,
					"%s: a revive fires on %s, not on IS_KO" % [name, str(conds)])
		# Positive control for the loop above: with none, the arm is blind.
		_expect(revive_sites >= 1, "%s: no posture named the revive at all" % name)

	# End to end, through the path a live beat takes — `make_context` reading the
	# packed table, the playbook, the encoder, the packer. '4f' is Priest, which is
	# why the role gate had to go: it is a MAGE that learns Raise.
	var ctx := RolloutCandidates.make_context(
		"4f", [ID_CHEAP, ID_HEAL, ID_REVIVE], UNIT_MAX_MP, buf)
	_expect(int(ctx["role"]) == UnitRole.Role.MAGE,
		"Priest ('4f') should be a MAGE — if JOB_ROLES moved it, this arm's point moved with it")
	var playbook: Array = RolloutCandidates.families(_fixture_rows(), ctx)["playbook"]
	var reached := false
	for cand in playbook:
		if (cand as PackedInt32Array).slice(0, GAMBIT_SIZE) == proven:
			reached = true
	_expect(reached,
		"no playbook candidate opens with the revive — the posture never reached the candidate set")


## The withdraw posture and the two claims that justify its shape (#1104 / ADR-0301).
##
## 🔴 THE LOAD-BEARING ARM IS THE AIM. A retreat's `action_target` is the unit to
## move AWAY from, and `retreat_step_cell` refuses `flee_from == unit_id` outright —
## so a withdraw posture aimed at `self_()` encodes cleanly, packs cleanly, and is a
## guaranteed `VERDICT_NO_RETREAT` fall-through every evaluation forever.
## `GambitOptions.aim_verdict` grades that cell AIM_FORBIDDEN, but the surface is not
## the path a rollout takes: the playbook goes straight through the encoder into the
## buffer, so nothing between this file and the GPU would have said a word.
##
## The positive arm's oracle is `GPURetreatStepTest`'s own `flee` gambit — the
## `enemies()` / `target_within` / `RETREAT` / `triggering()` quadruple whose five
## arms watch a unit on the GPU step exactly one tile away and come to REST. So what
## is asserted is not "some retreat-ish gambit" but the shape a battle has run.
## Only its THRESHOLD differs (that test needs 4 for its rest arm), and the
## threshold has its own arm below, against the mutation menu it is pinned to.
##
## ⚠️ AND THE SECOND CLAIM IS MEASURED, NOT ARGUED. The posture exists because no
## one-step mutation can reach the verb, and it omits an HP-keyed sibling because one
## `condition` edit reaches the break-off once the verb is planted. Both halves are
## run here: the five mutation families over a retreat-free incumbent must produce no
## `ACTION_RETREAT_STEP` at all, and `_family_condition` over the PLANTED posture must
## produce `SELF / HP_BELOW` on the retreat's own slot.
func _test_withdraw_posture() -> void:
	var buf := _ability_buffer()

	# 1. THE THRESHOLD IS PINNED, NOT CHOSEN. `_family_condition` re-conditions any
	# enabled slot from CONDITION_MENU, whose two distance entries both read 3;
	# authoring the same number puts this posture's slot on the mutation lattice
	# instead of one step off it. A drift here would leave it a neighbour of nothing.
	var distance_entries := 0
	for entry in RolloutCandidates.CONDITION_MENU:
		var t := int(entry["type"])
		if t != GPUConstants.COND_DISTANCE_LESS and t != GPUConstants.COND_DISTANCE_GREATER:
			continue
		distance_entries += 1
		_expect(int(entry["value"]) == RolloutPlaybook.WITHDRAW_TILES,
			"CONDITION_MENU offers distance %d but the withdraw posture authors %d — the posture's slot is no longer a neighbour of the menu" % [
				int(entry["value"]), RolloutPlaybook.WITHDRAW_TILES])
	# Positive control for the loop above: with no distance entry it asserts nothing.
	_expect(distance_entries == 2,
		"CONDITION_MENU should hold two distance entries (LESS and GREATER), found %d — the pinning arm above just went blind" % distance_entries)

	# 2. THE VERB IS PLAYBOOK-ONLY. `_action_menu` holds ATTACK, WAIT and the unit's
	# spells; nothing offers ACTION_RETREAT_STEP. This is the whole reason the posture
	# exists and the reason it sits at the head where K cannot truncate it.
	var retreat_free := _fixture_rows()
	var fam := RolloutCandidates.families(retreat_free, _ctx())
	for family_name in ["swap", "condition", "action", "delete", "insert"]:
		for cand in fam[family_name]:
			var image: PackedInt32Array = cand
			for slot in range(MAX_USER_GAMBITS):
				_expect(image[slot * GAMBIT_SIZE + GF.ACTION_TYPE] != GPUConstants.ACTION_RETREAT_STEP,
					"the '%s' family introduced a retreat into a list that had none — the withdraw posture's whole justification is that no one-step edit can" % family_name)

	# The oracle: GPURetreatStepTest's `flee` gambit, at this file's threshold.
	var proven := GPUCombatPacker._pack_gambits(GambitEncoder.encode_gambits([
		Gambit.create(
			TargetSelector.enemies(),
			[GambitCondition.target_within(RolloutPlaybook.WITHDRAW_TILES)],
			Gambit.ActionKind.RETREAT, -1, TargetSelector.triggering()),
	])).slice(0, GAMBIT_SIZE)
	_expect(proven[GF.COND_TARGET_TYPE] == GPUConstants.TARGET_NEAREST_ENEMY
			and proven[GF.COND_TYPE_0] == GPUConstants.COND_DISTANCE_LESS
			and proven[GF.COND_VAL_0] == RolloutPlaybook.WITHDRAW_TILES
			and proven[GF.ACTION_TYPE] == GPUConstants.ACTION_RETREAT_STEP
			and proven[GF.ACTION_TARGET_TYPE] == GPUConstants.TARGET_THEM
			and proven[GF.ACTION_ID] == 0,
		"the reference image is not GPURetreatStepTest's flee quadruple — this arm's oracle is broken, not the playbook: got %s" % str(proven))

	var split := RolloutCandidates.usable_abilities(
		[ID_CHEAP, ID_HEAL, ID_REVIVE], UNIT_MAX_MP, buf)
	for role in ALL_ROLES:
		var role_name: String = UnitRole.get_role_name(role)
		var postures := RolloutPlaybook.postures_for(
			role, split["offensive"], split["healing"], split["revive"])
		var withdraw_at := -1
		var retreat_sites := 0
		for pi in range(postures.size()):
			var posture: Array = postures[pi]
			var configs: Array = GambitEncoder.encode_gambits(posture)
			for i in range(mini(posture.size(), configs.size())):
				var cfg = configs[i]
				_expect(cfg != null,
					"%s: posture %d gambit %d did not encode (ADR-0023 skip)" % [role_name, pi, i])
				if cfg == null or int(cfg.get("action_type", -1)) != GPUConstants.ACTION_RETREAT_STEP:
					continue
				retreat_sites += 1
				withdraw_at = pi
				# The trap. NOT the caster, and not a pool that could resolve to it.
				_expect(int(cfg["action_target_type"]) != GPUConstants.TARGET_SELF,
					"%s: a retreat is aimed at the CASTER — retreat_step_cell refuses flee_from == unit_id, so this row can never fire" % role_name)
				_expect(int(cfg["action_target_type"]) == GPUConstants.TARGET_THEM
						and int(cfg["cond_target_type"]) == GPUConstants.TARGET_NEAREST_ENEMY,
					"%s: a retreat flees (aim %d, subject %d), not the nearest enemy the condition matched" % [
						role_name, int(cfg["action_target_type"]), int(cfg["cond_target_type"])])

		# EVERY role, MELEE included. Withholding it would withhold the VERB from the
		# role for every beat of every rollout, and the break-off a melee unit wants is
		# one condition edit from this posture (arm 4) — but only once it is planted.
		_expect(retreat_sites == 1,
			"%s: expected exactly one retreat gambit across every posture, got %d" % [
				role_name, retreat_sites])
		if withdraw_at < 0:
			continue

		# Second when the unit can revive, first when it cannot: the head of the
		# playbook is the two verbs no edit can introduce, revive the scarcer plant.
		_expect(withdraw_at == 1,
			"%s: the withdraw posture is at index %d, not behind the revive at 1" % [
				role_name, withdraw_at])
		var no_revive := RolloutPlaybook.postures_for(
			role, split["offensive"], split["healing"], [])
		var head_cfgs: Array = GambitEncoder.encode_gambits(no_revive[0])
		_expect(not head_cfgs.is_empty() and head_cfgs[0] != null
				and int(head_cfgs[0]["action_type"]) == GPUConstants.ACTION_RETREAT_STEP,
			"%s: with no revive the withdraw posture should lead the playbook" % role_name)

		var withdraw: Array = postures[withdraw_at]
		var packed := GPUCombatPacker._pack_gambits(
			GambitEncoder.encode_gambits(withdraw)).slice(0, GAMBIT_SIZE)
		_expect(packed == proven,
			"%s: the withdraw posture's slot 0 is not the quadruple GPURetreatStepTest runs — got %s" % [
				role_name, str(packed)])

		# 3. A SLOT UNDER THE RETREAT, AND IT FIGHTS. ADR-0301 picks the cell in the
		# DECIDE stage precisely so a cornered unit falls through; with nothing beneath
		# it the fall-through lands on ADR-0048's safety net, which walks the unit back
		# toward the thing it was fleeing.
		var tail_cfgs: Array = GambitEncoder.encode_gambits(withdraw)
		var last := withdraw.size() - 1
		_expect(withdraw.size() >= 2 and tail_cfgs[last] != null
				and int(tail_cfgs[last]["action_type"]) == GPUConstants.ACTION_ATTACK,
			"%s: the withdraw posture has no ATTACK beneath its retreat — a cornered unit reaches the safety net instead" % role_name)

	# 4. THE HP-KEYED SIBLING IS ONE EDIT AWAY, so it is deliberately not authored.
	# Planted posture in, `condition` family out, looking for SELF / HP_BELOW on the
	# retreat's own slot. If this ever reds, the second posture has to be written.
	var melee_ctx := RolloutCandidates.make_context("4c", [ID_CHEAP], UNIT_MAX_MP, buf)
	var planted := PackedInt32Array()
	for cand in RolloutCandidates.families(retreat_free, melee_ctx)["playbook"]:
		if (cand as PackedInt32Array).slice(0, GAMBIT_SIZE) == proven:
			planted = cand
	_expect(not planted.is_empty(),
		"no playbook candidate opens with the withdraw quadruple — the posture never reached the candidate set")
	if planted.is_empty():
		return
	var reached_break_off := false
	for cand in RolloutCandidates.families(planted, melee_ctx)["condition"]:
		var image: PackedInt32Array = cand
		for slot in range(MAX_USER_GAMBITS):
			var base := slot * GAMBIT_SIZE
			if image[base + GF.ACTION_TYPE] == GPUConstants.ACTION_RETREAT_STEP \
					and image[base + GF.COND_TARGET_TYPE] == GPUConstants.TARGET_SELF \
					and image[base + GF.COND_TYPE_0] == GPUConstants.COND_HP_BELOW:
				reached_break_off = true
	_expect(reached_break_off,
		"no one-step condition edit turns the planted retreat into a self-HP break-off — the playbook now owes a second, HP-keyed withdraw posture")


func _test_rows_round_trip() -> void:
	var slice := PackedInt32Array()
	slice.resize(GAMBITS_PER_UNIT * 4)
	var rows := _fixture_rows()
	_expect(RolloutCandidates.write_unit_rows(slice, 2, rows), "writing unit 2's rows should succeed")
	_expect(RolloutCandidates.unit_rows(slice, 2) == rows, "unit 2's rows should read back identical")
	_expect(RolloutCandidates.unit_rows(slice, 1) != rows, "writing unit 2 must not touch unit 1")
	_expect(not RolloutCandidates.write_unit_rows(slice, 9, rows),
		"a unit index past the slice must be refused, not written out of bounds")
