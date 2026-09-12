# test-kind: logic
# seeded-break: delete the `why` clause in LeverSet._validate — arm 3f goes green and reds
extends Node
## The LEVER LAYER's guard, taxonomy, composition and digest (ADR-0277).
##
## Pure GDScript — no GPU, no RenderingDevice, no scene setup. Every arm shares
## one setup (the ROM tables the almanac already holds), so they ride one
## process per the charter's clause 13.
##
## 🔴 EVERY GUARD ARM IS DIRECTION-TESTED. A validator arm that only ever sees
## valid input is the shape ADR-0277 dec. 9 exists to prevent: it passes because
## there was nothing to check. Each of arms 3a-3j authors a lever that is
## well-formed in every respect except the one under test, asserts the error,
## and then asserts the SAME lever with that one field corrected goes clean —
## so an arm cannot pass by rejecting everything.
##
##   1. The shipped lever set parses, is EMPTY, and is clean.
##   2. The taxonomy — strict partition over all 512 abilities and every weapon,
##      measured, not asserted from a remembered number.
##   3. The guard, ten seeded defects, each with its corrected control.
##   4. Composition — the three tiers multiply, and 1.0 is the identity.
##   5. Baking — rounding half away from zero, the capability floor, the cost floor.
##   6. Coverage — the partial case is reported and the hollow case is an error.
##   7. The digest — moves when a factor moves, stable when nothing does.
##   8. The pacing layer's slugs still exist on GPUBatchSimulator with the
##      spellings LeverSet copied, so the two registers cannot drift silently.

const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const ItemDatabase = ExMateriaAlmanac.ItemDatabase

var _asserts := 0
var _failed := false


func _ok(condition: bool, message: String) -> void:
	_asserts += 1
	if not condition:
		_failed = true
		print("[FAIL] %s" % message)


## A lever that is valid in every respect. Arms mutate one field of a copy.
func _valid_lever() -> Dictionary:
	return {
		"quantity": "cooldown_ticks",
		"by": "formula",
		"key": 8,
		"factor": 0.5,
		"why": "a fixture, not a balance claim",
		"evidence": "placeholder",
	}


func _errors_for(lever: Dictionary) -> PackedStringArray:
	return LeverSet.from_data({"levers": [lever]}).problems()["errors"]


## Seed one defect, assert it reds, then assert the corrected lever goes clean.
## The second half is the whole point: without it the arm cannot tell "rejected
## for the reason I seeded" from "rejects everything".
func _direction(name: String, broken: Dictionary) -> void:
	var bad := _errors_for(broken)
	_ok(not bad.is_empty(), "%s: seeded defect was ACCEPTED — %s" % [name, str(broken)])
	var good := _errors_for(_valid_lever())
	_ok(good.is_empty(), "%s: the CONTROL lever was rejected too (%s) — this arm rejects everything" % [
		name, ", ".join(good)])


func _ready() -> void:
	# --- 1. The shipped lever set ---------------------------------------------
	var shipped := LeverSet.shared()
	var shipped_problems := shipped.problems()
	_ok(shipped_problems["errors"].is_empty(),
		"the shipped lever set has errors: %s" % ", ".join(shipped_problems["errors"]))
	_ok(shipped.levers.is_empty(),
		"the shipped lever set is not empty (%d levers) — ADR-0277 dec. 12 ships it EMPTY; the first factors belong to #1107/#1108" % shipped.levers.size())
	_ok(LeverSet.cooldown_ceiling() > 0,
		"MAX_COOLDOWN_ABILITIES did not scan out of the kernel — an unread ceiling must not read as 'everything is reachable'")

	# --- 2. The taxonomy is a strict partition --------------------------------
	# Measured over the live tables. A remembered number here would be a claim
	# about the tree the day it was written, not about this one.
	var by_formula := 0
	var by_type := 0
	var classes := {}
	for aid in AbilityDatabase.ability_ids():
		var cat := LeverSet.ability_category(aid)
		classes["%s|%s" % [cat[0], str(cat[1])]] = true
		if cat[0] == LeverSet.BY_FORMULA:
			by_formula += 1
		elif cat[0] == LeverSet.BY_ABILITY_TYPE:
			by_type += 1
		else:
			_ok(false, "ability %d fell into neither namespace (%s)" % [aid, str(cat)])
	_ok(by_formula + by_type == AbilityDatabase.ability_ids().size(),
		"the partition is not total: %d formula + %d ability_type != %d abilities" % [
			by_formula, by_type, AbilityDatabase.ability_ids().size()])
	_ok(by_formula > 0 and by_type > 0,
		"one half of the partition is empty (%d formula / %d ability_type) — a tagged key with one live tag is not a tagged key" % [by_formula, by_type])
	# The zero-member case ADR-0277 dec. 7 names by hand: every `Normal` ability
	# carries a formula, so the `ability_type: Normal` category has no members.
	_ok(LeverSet._members_of(LeverSet.BY_ABILITY_TYPE, "Normal", LeverSet.DOMAIN_ABILITY).is_empty(),
		"`ability_type: Normal` has members — the partition is not strict, and dec. 7's whole argument fails")

	# --- 3. The guard, direction-tested ---------------------------------------
	_ok(_errors_for(_valid_lever()).is_empty(),
		"the valid fixture itself is rejected: %s" % ", ".join(_errors_for(_valid_lever())))

	var l: Dictionary = _valid_lever(); l["quantity"] = "hit_rate"
	_direction("3a unknown quantity", l)
	l = _valid_lever(); l["by"] = "job"
	_direction("3b unknown by", l)
	l = _valid_lever(); l["quantity"] = "wp"
	_direction("3c domain mismatch (item quantity, ability category)", l)
	l = _valid_lever(); l.erase("key")
	_direction("3d category with no key", l)
	l = _valid_lever(); l["factor"] = 0.0
	_direction("3e factor below the floor", l)
	l = _valid_lever(); l.erase("why")
	_direction("3f no why", l)
	l = _valid_lever(); l["why"] = "   "
	_direction("3f2 whitespace why", l)
	l = _valid_lever(); l["evidence"] = "vibes"
	_direction("3g unknown evidence class", l)
	l = _valid_lever(); l["by"] = "ability_type"; l["key"] = "Normal"
	_direction("3h zero-member category", l)
	l = _valid_lever(); l["by"] = "ability_type"; l["key"] = "Support"
	_direction("3i hollow category — the kernel never dispatches Support", l)
	l = _valid_lever(); l["by"] = "ability"; l["key"] = 999999
	_direction("3j record id out of range", l)

	# A duplicate needs two levers, so it does not go through `_direction`.
	var dupe := LeverSet.from_data({"levers": [_valid_lever(), _valid_lever()]})
	_ok(not dupe.problems()["errors"].is_empty(),
		"3k two levers on the same (quantity, category) were ACCEPTED — they would silently multiply")

	# --- 4. Composition -------------------------------------------------------
	# One ability that is definitely in formula 8 and definitely under the
	# cooldown ceiling, found rather than hard-coded.
	var subject := -1
	for aid in AbilityDatabase.ability_ids():
		var cat := LeverSet.ability_category(aid)
		if cat[0] == LeverSet.BY_FORMULA and LeverSet.ability_reaches("cooldown_ticks", aid):
			subject = aid
			break
	_ok(subject >= 0, "no ability is both formula-keyed and cooldown-reachable — arms 4 and 7 have no subject")
	if subject >= 0:
		var subject_formula: int = LeverSet.ability_category(subject)[1]
		var empty := LeverSet.from_data({"levers": []})
		_ok(is_equal_approx(empty.ability_factor("cooldown_ticks", subject), 1.0),
			"an empty lever set is not the identity")
		var tiers := LeverSet.from_data({"levers": [
			{"quantity": "cooldown_ticks", "by": "all", "factor": 0.5,
				"why": "fixture", "evidence": "placeholder"},
			{"quantity": "cooldown_ticks", "by": "formula", "key": subject_formula,
				"factor": 0.5, "why": "fixture", "evidence": "placeholder"},
			{"quantity": "cooldown_ticks", "by": "ability", "key": subject,
				"factor": 0.5, "why": "fixture", "evidence": "placeholder"},
		]})
		_ok(tiers.problems()["errors"].is_empty(),
			"the three-tier fixture is invalid: %s" % ", ".join(tiers.problems()["errors"]))
		_ok(is_equal_approx(tiers.ability_factor("cooldown_ticks", subject), 0.125),
			"the tiers do not MULTIPLY: expected 0.125, got %f" % tiers.ability_factor("cooldown_ticks", subject))
		# A lever on one quantity must not leak into another.
		_ok(is_equal_approx(tiers.ability_factor("mp_cost", subject), 1.0),
			"a cooldown_ticks lever moved mp_cost")

	# --- 5. Baking ------------------------------------------------------------
	# Round HALF AWAY FROM ZERO, not truncate. `wp 3 x 0.9` is 2.7: truncation
	# gives 2 (a 33% cut from a 10% lever), rounding gives 3.
	_ok(LeverSet.bake("wp", 3, 0.9) == 3, "wp 3 x0.9 baked to %d, expected 3 (rounded, not truncated)" % LeverSet.bake("wp", 3, 0.9))
	_ok(LeverSet.bake("wp", 10, 0.9) == 9, "wp 10 x0.9 baked to %d, expected 9" % LeverSet.bake("wp", 10, 0.9))
	# THE CAPABILITY FLOOR. `Nagrarock` is wp 1; a nerf may weaken a weapon and
	# may never disarm one.
	_ok(LeverSet.bake("wp", 1, 0.05) == 1, "wp 1 x0.05 baked to %d — a capability quantity must floor at 1" % LeverSet.bake("wp", 1, 0.05))
	_ok(LeverSet.bake("weapon_range", 1, 0.05) == 1, "weapon_range floored below 1")
	# A ROM zero stays zero: the floor lifts a value that WAS >= 1, it does not
	# invent a capability the record never had.
	_ok(LeverSet.bake("wp", 0, 2.0) == 0, "wp 0 x2.0 invented a weapon")
	# THE COST FLOOR is 0 — free / instant / no-evasion are meaningful values.
	_ok(LeverSet.bake("cooldown_ticks", 300, 0.05) == 15, "cooldown_ticks 300 x0.05 baked to %d, expected 15" % LeverSet.bake("cooldown_ticks", 300, 0.05))
	_ok(LeverSet.bake("mp_cost", 2, 0.05) == 0, "mp_cost did not reach 0 — a cost quantity floors at 0, not 1")
	# 1.0 is the identity at every magnitude.
	for v in [0, 1, 3, 99, 300]:
		_ok(LeverSet.bake("cooldown_ticks", v, 1.0) == v, "bake is not the identity at factor 1.0 for %d" % v)

	# --- 5b. attack_period crosses as a Q8 FACTOR, not a value (#1107) --------
	# The seventh quantity is the one whose ROM base this side does not hold —
	# it is a SEQ length in the anim-timings buffer — so the packer bakes
	# `item_factor_q8` into the unit row and the kernel does the multiply. What
	# is testable here is the arithmetic; the realised tick gap is the GPU half
	# and lives in AttackPeriodTest.
	_ok(LeverSet.QUANTITIES.has("attack_period"),
		"attack_period is not in the quantity enum")
	_ok(LeverSet.QUANTITIES["attack_period"]["domain"] == LeverSet.DOMAIN_ITEM,
		"attack_period must be an ITEM quantity — it is keyed off the right hand")
	_ok(LeverSet.QUANTITIES["attack_period"]["kind"] == LeverSet.KIND_COST,
		"attack_period must be a COST quantity, like cooldown_ticks")
	# THE UNARMED IDENTITY. `item_id < 0` has no record and therefore no lever,
	# and it must answer 256 rather than 0 — a zero period is an infinite attack
	# rate, which is the one value this whole layer must not be able to produce.
	_ok(LeverSet.from_data({"levers": []}).item_factor_q8("attack_period", -1) == 256,
		"an unarmed unit's attack_period factor is not the Q8 identity")
	# Find a real weapon and its item_type by MEASUREMENT, so the arm cannot go
	# stale against a remembered id the way a hard-coded 83 would.
	# ⚠️ `get_weapons()` returns item RECORDS, not ids. Writing `int(records[0])`
	# here did not fail the test — it threw, aborted before `get_tree().quit()`,
	# and the scene HUNG to the runner's 360 s kill. A hang is the absence of a
	# verdict, not a red one, so the id is taken off the record by key.
	var wpn_records: Array = ItemDatabase.get_weapons()
	var subject_item := -1
	for rec in wpn_records:
		if rec is Dictionary and int(rec.get("id", -1)) >= 0:
			subject_item = int(rec["id"])
			break
	_ok(subject_item >= 0,
		"no weapon record with an id in ItemDatabase — this arm examined nothing")
	if subject_item >= 0:
		var subject_type: String = str(LeverSet.item_category(subject_item)[1])
		var empty_set := LeverSet.from_data({"levers": []})
		_ok(empty_set.item_factor_q8("attack_period", subject_item) == 256,
			"an un-levered weapon's attack_period factor is not the Q8 identity (got %d)"
				% empty_set.item_factor_q8("attack_period", subject_item))
		var doubled := LeverSet.from_data({"levers": [{
			"quantity": "attack_period", "by": "item_type", "key": subject_type,
			"factor": 2.0, "why": "a fixture, not a balance claim",
			"evidence": "placeholder"}]})
		_ok(doubled.problems()["errors"].is_empty(),
			"an attack_period lever on item_type '%s' does not validate: %s" % [
				subject_type, ", ".join(doubled.problems()["errors"])])
		_ok(doubled.item_factor_q8("attack_period", subject_item) == 512,
			"attack_period x2.0 baked to Q8 %d, expected 512"
				% doubled.item_factor_q8("attack_period", subject_item))
		# A lever on one quantity must not leak into another, in the item domain
		# too — the ability-domain twin of this is arm 4 above.
		_ok(doubled.item_factor_q8("wp", subject_item) == 256,
			"an attack_period lever moved wp")
		# ⚠️ THE CLAMP IS NOT THE VALIDATOR. `from_data` would refuse a factor
		# outside [0.05, 20.0], so this arm reaches `item_factor_q8` the only way
		# an out-of-range factor ever could — by composing two in-range tiers,
		# 20.0 x 20.0 = 400.0, which no single lever can state.
		var stacked := LeverSet.from_data({"levers": [
			{"quantity": "attack_period", "by": "all",
			 "factor": 20.0, "why": "a fixture", "evidence": "placeholder"},
			{"quantity": "attack_period", "by": "item_type", "key": subject_type,
			 "factor": 20.0, "why": "a fixture", "evidence": "placeholder"}]})
		_ok(stacked.problems()["errors"].is_empty(),
			"the stacked fixture is invalid: %s" % ", ".join(stacked.problems()["errors"]))
		_ok(is_equal_approx(stacked.item_factor("attack_period", subject_item), 400.0),
			"the two tiers did not multiply to 400.0 (got %f)"
				% stacked.item_factor("attack_period", subject_item))
		_ok(stacked.item_factor_q8("attack_period", subject_item) == roundi(LeverSet.FACTOR_MAX * 256.0),
			"a composed factor of 400.0 reached the kernel as Q8 %d rather than clamping to FACTOR_MAX"
				% stacked.item_factor_q8("attack_period", subject_item))

	# --- 6. Coverage ----------------------------------------------------------
	# The PARTIAL case: a category straddling the cooldown ceiling is legal, and
	# reported. Found by measurement, not asserted from a remembered formula id.
	var straddler := -1
	var straddle_members := 0
	var straddle_reaches := 0
	for cls in classes.keys():
		var bits: PackedStringArray = str(cls).split("|")
		if bits[0] != LeverSet.BY_FORMULA:
			continue
		var members := LeverSet._members_of(LeverSet.BY_FORMULA, int(bits[1]), LeverSet.DOMAIN_ABILITY)
		var reaches := 0
		for m in members:
			if LeverSet.ability_reaches("cooldown_ticks", m):
				reaches += 1
		if reaches > 0 and reaches < members.size():
			straddler = int(bits[1])
			straddle_members = members.size()
			straddle_reaches = reaches
			break
	_ok(straddler >= 0,
		"no formula class straddles the cooldown ceiling — the partial-coverage arm has no subject and would pass vacuously")
	if straddler >= 0:
		var partial := LeverSet.from_data({"levers": [
			{"quantity": "cooldown_ticks", "by": "formula", "key": straddler,
				"factor": 0.5, "why": "fixture", "evidence": "measured"}]})
		_ok(partial.problems()["errors"].is_empty(),
			"a PARTIALLY-applying lever was rejected — dec. 9 reports it, it does not block authoring")
		_ok(partial.problems()["warnings"].size() == 1,
			"a partially-applying lever produced %d warnings, expected 1" % partial.problems()["warnings"].size())
		var cov: Array = partial.coverage()
		_ok(cov.size() == 1 and cov[0]["reaches"] == straddle_reaches and cov[0]["members"] == straddle_members,
			"coverage misreported formula %d: %s (measured %d of %d)" % [
				straddler, str(cov), straddle_reaches, straddle_members])
	# The REALISED factor is reported and differs from the authored one where the
	# integer cannot hold it. Rods are wp 3, so x0.9 realises as 1.0.
	var rods := LeverSet.from_data({"levers": [
		{"quantity": "wp", "by": "item_type", "key": "Rod", "factor": 0.9,
			"why": "fixture", "evidence": "measured"}]})
	_ok(rods.problems()["errors"].is_empty(),
		"the Rod fixture is invalid: %s" % ", ".join(rods.problems()["errors"]))
	if not rods.coverage().is_empty():
		_ok(not is_equal_approx(rods.coverage()[0]["realised"], 0.9),
			"the realised factor equals the authored one on wp 3 — either the report is not computing it, or the table changed")

	# --- 7. The digest --------------------------------------------------------
	var d_empty := LeverSet.from_data({"levers": []}).digest()
	var d_empty2 := LeverSet.from_data({"levers": []}).digest()
	_ok(d_empty == d_empty2, "the digest is not stable across two identical lever sets")
	if subject >= 0:
		var moved := LeverSet.from_data({"levers": [
			{"quantity": "cooldown_ticks", "by": "ability", "key": subject,
				"factor": 0.5, "why": "fixture", "evidence": "placeholder"}]})
		_ok(moved.digest() != d_empty, "the digest did NOT move when a factor moved")
		# Hashing the OUTPUT, not the input: a reworded `why` changes the file
		# and changes nothing the kernel sees, so the digest must not move.
		var reworded := LeverSet.from_data({"levers": [
			{"quantity": "cooldown_ticks", "by": "ability", "key": subject,
				"factor": 0.5, "why": "a completely different sentence",
				"evidence": "measured"}]})
		_ok(moved.digest() == reworded.digest(),
			"the digest moved on a reworded `why` — it is hashing the INPUT, and dec. 10 says the output")

	# --- 8. The pacing layer's spellings --------------------------------------
	# LeverSet copies these two slugs rather than importing them, to avoid a
	# class-level cycle. That copy is only safe if something reconciles it.
	_ok(LeverSet.PACING_SLUGS.has(GPUBatchSimulator.MOVE_TIME_SCALE_SLUG),
		"GPUBatchSimulator.MOVE_TIME_SCALE_SLUG ('%s') is not in LeverSet.PACING_SLUGS %s" % [
			GPUBatchSimulator.MOVE_TIME_SCALE_SLUG, str(LeverSet.PACING_SLUGS)])
	_ok(LeverSet.PACING_SLUGS.has(GPUBatchSimulator.DAMAGE_SCALE_SLUG),
		"GPUBatchSimulator.DAMAGE_SCALE_SLUG ('%s') is not in LeverSet.PACING_SLUGS %s" % [
			GPUBatchSimulator.DAMAGE_SCALE_SLUG, str(LeverSet.PACING_SLUGS)])
	_ok(LeverSet.PACING_SLUGS.size() == 2,
		"LeverSet.PACING_SLUGS has %d entries — a third pacing slug landed and the digest does not cover it" % LeverSet.PACING_SLUGS.size())

	# --- 9. The derived cooldown floor and the deleted ceiling (#1108) --------
	# Rides here rather than in a new process: this test already holds the two
	# things the arm needs (the ROM ability table and the scanned ceiling), and
	# the charter's clause 13 costs a whole ~2.3 s boot for a split.
	var TICKS_PER_CT := 30
	var FLOOR := 300
	var cooldowns := {}
	var ct_bearing := 0
	var overridden := 0        # cooldown longer than the ability's own charge period
	var under_floor := 0       # a ct-less / unlearnable ability below the #93 window
	for aid in AbilityDatabase.ability_ids():
		var view = AbilityDatabase.get_ability_view(aid)
		var cd: int = view.cooldown_ticks
		cooldowns[cd] = true
		# AbilityView's generated getters read the record with a 0 default, so an
		# absent `ct` (the 144 non-Normal records) arrives here as 0 and is held
		# to the floor by 9c — which is exactly the intended treatment.
		var ct: int = view.ct
		if ct > 0:
			ct_bearing += 1
			if cd > ct * TICKS_PER_CT:
				overridden += 1
		elif cd < FLOOR:
			under_floor += 1

	# 9a. It is no longer one number. Before #1108 every one of the 512 read 300.
	_ok(cooldowns.size() >= 10,
		"cooldown_ticks has only %d distinct values across the ability table — the derivation has collapsed back to a flat default" % cooldowns.size())

	# 9b. THE REGRESSION GUARD FOR THE REFUTED CLAIM. ADR-0047 dec. 2 asserted a
	# flat 300 was a no-op for CT-bearing abilities; measured, it overrode 123 of
	# 144, because the charge period is ct * 30 and only exceeds 300 above ct 10.
	# The floor must never again outlast the cadence the ROM already set.
	_ok(overridden == 0,
		"%d of %d CT-bearing abilities have a cooldown LONGER than their charge period (ct * %d) — the floor is overriding FFT's own cadence again" % [
			overridden, ct_bearing, TICKS_PER_CT])

	# 9c. ...and the #92 / #93 fall-through window still holds for everything the
	# ROM does not price with time, or a CT=0 ability's own ~60-tick cast
	# animation leaves the slot-1 ATTACK fallback no room to commit.
	_ok(under_floor == 0,
		"%d abilities with no charge period sit below the %d-tick fall-through window" % [under_floor, FLOOR])

	# 9d. The ceiling is gone: it now covers the WHOLE ability table, so no real
	# ability escapes the veto by id. Two registers hold this number (the shader
	# and GPUBatchSimulator) and only the host guard reconciles them.
	_ok(LeverSet.cooldown_ceiling() == GPUBatchSimulator.MAX_COOLDOWN_ABILITIES,
		"the kernel's scanned ceiling (%d) and GPUBatchSimulator.MAX_COOLDOWN_ABILITIES (%d) have drifted" % [
			LeverSet.cooldown_ceiling(), GPUBatchSimulator.MAX_COOLDOWN_ABILITIES])
	_ok(LeverSet.cooldown_ceiling() == GPUConstants.MAX_ABILITIES,
		"the cooldown ceiling (%d) no longer covers the ability table (%d) — ids in the gap fall through the veto un-gated" % [
			LeverSet.cooldown_ceiling(), GPUConstants.MAX_ABILITIES])

	# 9e. CONTROL for 9d, because "the ceiling is big enough" is only meaningful
	# if the reachability predicate can still say NO. Reaction / Support /
	# Movement reach no quantity at all (ADR-0277), so a predicate that answered
	# yes to everything would sail through 9d and every coverage arm with it.
	var refused := 0
	var reached_above_old_ceiling := 0
	for aid in AbilityDatabase.ability_ids():
		if LeverSet.ability_reaches("cooldown_ticks", aid):
			if aid >= 128:
				reached_above_old_ceiling += 1
		else:
			refused += 1
	_ok(refused > 0,
		"the cooldown reachability predicate refuses NOTHING — it has gone blind, and every coverage number above is vacuous")
	_ok(reached_above_old_ceiling > 0,
		"no ability id at or above the old 128 ceiling reaches cooldown_ticks — raising the ceiling changed nothing")

	# --- verdict --------------------------------------------------------------
	if _asserts == 0:
		print("[FAIL] LeverSet test made ZERO assertions — a green summary is not a run")
		_failed = true
	if _failed:
		print("[FAIL] LeverSet: %d assertions, at least one red" % _asserts)
	else:
		print("[PASS] LeverSet: %d assertions — %d ability categories over %d abilities, %d weapons, cooldown ceiling %d" % [
			_asserts, classes.size(), AbilityDatabase.ability_ids().size(),
			ItemDatabase.get_weapons().size(), LeverSet.cooldown_ceiling()])
	get_tree().quit()
