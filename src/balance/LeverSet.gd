class_name LeverSet
extends RefCounted

## The LEVER LAYER (ADR-0277) — a hand-authored set of multipliers composed over
## the ROM tables, which stay immutable underneath it.
##
## Vocabulary (ADR-0277 dec. 1): the file is a **lever set**; one entry in it is a
## **lever**; the number a lever carries is its **factor**; the tiers are
## **global** / **category** / **record**; the product of all three for one
## quantity on one record is its **effective factor**; a value that has been
## through the layer is **levered**.
##
## 🔴 THE PACING PAIR IS NOT IN HERE. `pacing.move_time_scale` and
## `pacing.damage_scale` are a SEPARATE layer (ADR-0277 dec. 3): they ride the
## config buffer, they scale quantities no record has a field for
## (`scale_hp_transfer` / `scale_move_ticks`), and they stay live-scrubbable
## `Tune` slugs. They have no per-record form, so folding them in here would put
## two unlike things under one word. [method digest] covers BOTH layers, because
## a provenance stamp that certifies half a configuration is worse than none.
##
## Everything in the lever set is BAKED AT LOAD (ADR-0277 dec. 2) — ability
## quantities into the ability buffer by [GPUAbilityLoader], weapon quantities
## into the unit rows by [GPUCombatPacker]. A rollout forks those buffers, so it
## inherits the levers for nothing; what is given up is live scrub.

const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const ItemDatabase = ExMateriaAlmanac.ItemDatabase

const PATH := "res://assets/balance/levers.json"

## The pacing layer's two slugs, read for [method digest] only. Spelled here
## rather than imported from [GPUBatchSimulator] because that class consumes
## this one through [GPUAbilityLoader] and a class-level cycle is not worth a
## shared constant. `PACING_SLUGS` and their defaults are asserted against the
## simulator's own by `LeverSetTest`, so the two cannot drift silently.
const PACING_SLUGS := ["pacing.move_time_scale", "pacing.damage_scale"]

# === The closed quantity enum (ADR-0277 dec. 4) ===
#
# Six, and adding a seventh is a DECISION, not an edit. Each names a field the
# kernel already reads, and declares two things:
#
#   domain — `ability` quantities are baked into the ability buffer; `item`
#            quantities into the unit rows at pack time. A lever may only pair a
#            quantity with a category from its own domain, so `formula` x `wp` is
#            an error rather than a silent no-op.
#   kind   — CAPABILITY quantities floor at 1 when the ROM value was >= 1: a
#            lever may weaken a weapon and may never silently disarm one
#            (`Nagrarock` is `wp 1`, and `x0.9` on it rounds to 1, not 0). COST
#            quantities floor at 0, because free / instant / no-evasion are all
#            meaningful values.
#
# 🔴 A quantity that NAMES AN IDENTITY rather than a magnitude is deliberately
# absent: `formula_id`, `element`, `flags`, `effect_id`, `inflict_mask`,
# `inflict_mode`, `weapon_flags`, `weapon_type`. Scaling those is not balance,
# it is a different record.
const KIND_CAPABILITY := "capability"
const KIND_COST := "cost"
const DOMAIN_ABILITY := "ability"
const DOMAIN_ITEM := "item"

const QUANTITIES := {
	"wp": {"domain": DOMAIN_ITEM, "kind": KIND_CAPABILITY},
	"weapon_range": {"domain": DOMAIN_ITEM, "kind": KIND_CAPABILITY},
	"w_ev": {"domain": DOMAIN_ITEM, "kind": KIND_COST},
	# THE SEVENTH, and it is a DECISION rather than an edit — dec. 4 above closed
	# the enum for exactly this. #1107, ADR-0279.
	#
	# 🔴 ITS ROM BASE IS NOT ZERO, WHICH IS WHY IT IS `attack_period` AND NOT
	# `attack_recovery`. A lever multiplies and never replaces, so a quantity
	# whose base is 0 could not be authored at all — every factor would multiply
	# to 0. The base is the weapon's SEQ-derived attack period, which already
	# exists and is already per-weapon-type: 38 ticks for all nine melee types,
	# 40 unarmed, 44 Gun, 52 Crossbow/Bow, plus a distance-proportional flight
	# tail for the three ranged types. #1107 opened on the premise that reach had
	# no rate cost; it has one, it is 2.0x at a Bow's native range, and what it
	# lacked was an author.
	#
	# COST, for the same reason `cooldown_ticks` is: ticks the unit owes, higher
	# is worse, and 0 is a meaningful floor rather than a disarmed weapon.
	#
	# ⚠️ UNLIKE THE OTHER FIVE ITEM QUANTITIES, THIS ONE IS NOT BAKED AS A VALUE.
	# The packer bakes its Q8 FACTOR into `U_ATTACK_PERIOD_FACTOR_Q8` and the
	# kernel does the multiply, because the base lives on the GPU — it is SEQ
	# frame data in the anim-timings buffer, reachable here only by mirroring
	# `get_attack_anim_id`, and #1147 has just established that predicate is
	# wrong. Dec. 2's PURPOSE survives intact: baked at load, not live-scrubbable,
	# riding the unit row, so a rollout that forks the unit buffer inherits it.
	# The cost is that [method problems] cannot report a realised factor for it —
	# a named soft spot, not an oversight.
	"attack_period": {"domain": DOMAIN_ITEM, "kind": KIND_COST},
	"cooldown_ticks": {"domain": DOMAIN_ABILITY, "kind": KIND_COST},
	"charge_time": {"domain": DOMAIN_ABILITY, "kind": KIND_COST},
	"mp_cost": {"domain": DOMAIN_ABILITY, "kind": KIND_COST},
}

# === The tiers (ADR-0277 dec. 5) ===
#
# `by` names the namespace the `key` is in, always explicitly — a reader should
# never have to infer which space an integer lives in. Tiers multiply:
#
#     effective = rom x global x category x record
#
# so 1.0 is the identity at every tier and a sweep at one tier still moves the
# records another tier has touched.
const BY_ALL := "all"
const BY_FORMULA := "formula"
const BY_ABILITY_TYPE := "ability_type"
const BY_ITEM_TYPE := "item_type"
const BY_ABILITY := "ability"
const BY_ITEM := "item"

## Tier, keyed by `by`. `all` is the global tier and is domain-agnostic — the
## QUANTITY decides which records it reaches.
const TIER_GLOBAL := 0
const TIER_CATEGORY := 1
const TIER_RECORD := 2
const BYS := {
	BY_ALL: {"tier": TIER_GLOBAL, "domain": ""},
	BY_FORMULA: {"tier": TIER_CATEGORY, "domain": DOMAIN_ABILITY},
	BY_ABILITY_TYPE: {"tier": TIER_CATEGORY, "domain": DOMAIN_ABILITY},
	BY_ITEM_TYPE: {"tier": TIER_CATEGORY, "domain": DOMAIN_ITEM},
	BY_ABILITY: {"tier": TIER_RECORD, "domain": DOMAIN_ABILITY},
	BY_ITEM: {"tier": TIER_RECORD, "domain": DOMAIN_ITEM},
}

## Evidence class (ADR-0277 dec. 6). `why` alone degenerates into restating the
## number in words; the class is what makes the file auditable, because the rig
## can then report "N of M factors are still placeholders" as a number.
const EVIDENCE := ["measured", "rom-faithful", "placeholder"]

## A factor is strictly positive and bounded. Deletion is not a balance
## operation and must not be reachable by typing a small number.
const FACTOR_MIN := 0.05
const FACTOR_MAX := 20.0

## Ability types the kernel never dispatches, so NO quantity reaches them
## (ADR-0277 dec. 8). Reaction abilities do reach the kernel, but through
## `U_REACTION_ABILITY` and its own 7-entry `REACT_*` enum — none of the six
## quantities is consulted on that path. Support and Movement are `live: false`
## in `UNIT_CONFIG_SCHEMA` with no extractor at all.
const UNREACHABLE_ABILITY_TYPES := ["Reaction", "Support", "Movement", "None"]

## Where the cooldown ceiling is READ FROM, not where it is stated. Scanned out
## of the kernel source the way `overlay_behaviour_problems` derives its floor,
## so the day #1108 raises or removes the ceiling the coverage report moves with
## it and nobody has to remember this file exists.
const COOLDOWN_CEILING_SOURCE := "res://src/gpu/shaders/combat_common.glslinc"

# --- instance state -----------------------------------------------------------

## The validated levers, in file order.
var levers: Array = []
## Errors and warnings from [method problems], computed once at construction.
var _problems: Dictionary = {}
## The composed half of [method digest], folded once — see the note there.
var _composed_digest: String = ""

static var _shared: LeverSet = null
static var _cooldown_ceiling: int = -1


## The lever set the bake sites read. Lazily loaded from [constant PATH] and
## cached, because both bake sites run inside buffer construction and neither is
## a place to be re-reading a file.
static func shared() -> LeverSet:
	if _shared == null:
		_shared = _load_from_path(PATH)
	return _shared


## Drop the cache and re-read the file. The reload affordance ADR-0277 dec. 2
## promises is a SEPARATE ticket and it refuses while a battle is live
## (dec. 11); this is the seam it will call, and the tests' way back to a known
## state.
static func reload_shared() -> LeverSet:
	_shared = null
	return shared()


## Build from an already-parsed payload. The pure entry point: every test
## constructs through this, so nothing in the validator needs a file.
static func from_data(data: Variant) -> LeverSet:
	var ls := LeverSet.new()
	ls._ingest(data)
	return ls


static func _load_from_path(path: String) -> LeverSet:
	if not FileAccess.file_exists(path):
		# An ABSENT lever set is not an empty one: absent means the layer was
		# deleted or the path moved, and every levered value would silently
		# revert to its ROM number. Loud, then identity.
		push_error("[LeverSet] no lever set at %s — every factor reads as 1.0" % path)
		return from_data({"levers": []})
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[LeverSet] %s is not valid JSON — every factor reads as 1.0" % path)
		return from_data({"levers": []})
	return from_data(parsed)


func _ingest(data: Variant) -> void:
	var rows: Array = []
	if data is Dictionary and data.has("levers") and data["levers"] is Array:
		rows = data["levers"]
	elif data is Array:
		rows = data
	levers = rows
	_problems = _validate(rows)


# --- composition --------------------------------------------------------------


## The effective factor for one quantity on one ability: global x category x record.
func ability_factor(quantity: String, ability_id: int) -> float:
	var cat := ability_category(ability_id)
	return _compose(quantity, DOMAIN_ABILITY, cat, BY_ABILITY, ability_id)


## The effective factor for one quantity on one item.
func item_factor(quantity: String, item_id: int) -> float:
	var cat := item_category(item_id)
	return _compose(quantity, DOMAIN_ITEM, cat, BY_ITEM, item_id)


func _compose(quantity: String, domain: String, category: Array,
		record_by: String, record_key: int) -> float:
	if not QUANTITIES.has(quantity) or QUANTITIES[quantity]["domain"] != domain:
		return 1.0
	var f := 1.0
	for lever in levers:
		if not (lever is Dictionary) or lever.get("quantity") != quantity:
			continue
		var by = lever.get("by")
		if by == BY_ALL:
			f *= float(lever.get("factor", 1.0))
		elif by == category[0] and _key_eq(lever.get("key"), category[1]):
			f *= float(lever.get("factor", 1.0))
		elif by == record_by and _key_eq(lever.get("key"), record_key):
			f *= float(lever.get("factor", 1.0))
	return f


## JSON gives every number back as a float, so a `formula` key authored as `8`
## arrives as `8.0` and would never match an int category. Compare ints as ints
## and everything else as strings.
static func _key_eq(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return int(a) == int(b)
	return str(a) == str(b)


## Bake one levered integer. Round half away from zero (`roundi`), then floor by
## the quantity's kind. 🔴 ROUNDING DOES NOT FIX THE RESOLUTION PROBLEM, IT ONLY
## STOPS TRUNCATION FROM COMPOUNDING IT — `wp 3` cannot express x0.9 at all, and
## [method problems] reports the worst REALISED factor per lever for exactly
## that reason.
static func bake(quantity: String, rom_value: int, factor: float) -> int:
	if not QUANTITIES.has(quantity):
		return rom_value
	var v := roundi(float(rom_value) * factor)
	if QUANTITIES[quantity]["kind"] == KIND_CAPABILITY and rom_value >= 1:
		return maxi(v, 1)
	return maxi(v, 0)


## Bake convenience for the ability bake site.
func levered_ability(quantity: String, ability_id: int, rom_value: int) -> int:
	return bake(quantity, rom_value, ability_factor(quantity, ability_id))


## Bake convenience for the packer bake site. `item_id < 0` is an unarmed unit,
## which has no record and therefore no lever.
func levered_item(quantity: String, item_id: int, rom_value: int) -> int:
	if item_id < 0:
		return rom_value
	return bake(quantity, rom_value, item_factor(quantity, item_id))


## Q8 fixed point — 256 == 1.0x. The ONE quantity whose base the kernel holds and
## this class does not (`attack_period`) crosses as a factor rather than a value,
## so the shader can do the multiply against a SEQ length that never leaves the
## GPU. Same encoding and same reason as `pacing.*`: at these magnitudes integer
## division would let rounding, not the factor, decide the ordering between two
## weapon types.
##
## `item_id < 0` is an unarmed unit — no record, no lever, and the IDENTITY, which
## is what keeps this a no-op for every unit in a game whose lever set ships empty.
## Clamped to Q8 of [constant FACTOR_MIN] / [constant FACTOR_MAX] so a malformed
## factor that somehow cleared validation still cannot reach the kernel as 0 (a
## zero period is not a balance operation, it is an infinite attack rate).
func item_factor_q8(quantity: String, item_id: int) -> int:
	if item_id < 0:
		return 256
	var f := item_factor(quantity, item_id)
	return clampi(roundi(f * 256.0), roundi(FACTOR_MIN * 256.0), roundi(FACTOR_MAX * 256.0))


# --- the taxonomy (ADR-0277 dec. 7) -------------------------------------------


## The ONE category an ability belongs to, as `[by, key]`.
##
## 🔴 STRICT PARTITION, NOT A MATCHING RULE. `formula` is present on exactly the
## 368 `Normal` abilities and absent on all 144 others, so the two never overlap
## and a record has exactly one category. That means
## `{"by": "ability_type", "key": "Normal"}` matches NOTHING — and the
## zero-member check in [method problems] is what makes that loud instead of
## silent.
static func ability_category(ability_id: int) -> Array:
	var view = AbilityDatabase.get_ability_view(ability_id)
	if view == null:
		return [BY_ABILITY_TYPE, ""]
	# `has()` and not `formula`, because `AbilityView.formula` answers 0 for an
	# absent key and 0 is a real formula (five abilities carry it).
	if view.has("formula"):
		return [BY_FORMULA, int(view.formula)]
	return [BY_ABILITY_TYPE, str(view.ability_type)]


## The ONE category an item belongs to, as `[by, key]`.
static func item_category(item_id: int) -> Array:
	var item: Dictionary = ItemDatabase.get_item(item_id)
	return [BY_ITEM_TYPE, str(item.get("item_type", ""))]


## The 128-ability cooldown ceiling, READ OUT OF THE KERNEL. Returns -1 if the
## scan finds nothing, and an empty scan is an ERROR in [method problems] rather
## than a pass — a net that silently stopped looking is the failure mode this
## whole map keeps re-finding.
static func cooldown_ceiling() -> int:
	if _cooldown_ceiling >= 0:
		return _cooldown_ceiling
	_cooldown_ceiling = -1
	if FileAccess.file_exists(COOLDOWN_CEILING_SOURCE):
		var src := FileAccess.get_file_as_string(COOLDOWN_CEILING_SOURCE)
		var re := RegEx.new()
		re.compile("const\\s+int\\s+MAX_COOLDOWN_ABILITIES\\s*=\\s*(\\d+)")
		var m := re.search(src)
		if m:
			_cooldown_ceiling = int(m.get_string(1))
	return _cooldown_ceiling


## Can the kernel consume `quantity` on this ability? Derived, never listed.
static func ability_reaches(quantity: String, ability_id: int) -> bool:
	var view = AbilityDatabase.get_ability_view(ability_id)
	if view == null:
		return false
	if UNREACHABLE_ABILITY_TYPES.has(str(view.ability_type)):
		return false
	if quantity == "cooldown_ticks":
		var ceiling := cooldown_ceiling()
		# A failed scan must not read as "everything is reachable".
		return ceiling > 0 and ability_id < ceiling
	return true


## Can the kernel consume `quantity` on this item? Only a weapon reaches the
## packer's weapon rows at all — `wp` / `weapon_range` / `w_ev` are read off the
## right hand and nothing else.
static func item_reaches(_quantity: String, item_id: int) -> bool:
	return ItemDatabase.is_weapon(item_id)


# --- the guard (ADR-0277 dec. 9) ----------------------------------------------


## `{errors, warnings, coverage, placeholders}` — pure, no GPU, shared by the
## boot check, [method abort_if_invalid] and `LeverSetTest`, the same shape
## `unit_config_schema_problems` established.
##
## ERRORS ABORT THE MEASURING TOOLS AND ONLY WARN THE GAME (ADR-0277 dec. 9). A
## silently-inert factor corrupts a measurement without failing it, which is
## worse than not running; a typo in a balance file should not stop somebody
## playing.
func problems() -> Dictionary:
	return _problems


## Every lever's static coverage, as `[{lever, reaches, members, realised}]`.
## Reported, never enforced — [#1108] exists to raise the cooldown ceiling that
## makes most of these partial, and a guard that blocked authoring on it would
## have to be un-written the day it lands.
func coverage() -> Array:
	return _problems.get("coverage", [])


## Push every error and warning through Godot's diagnostics and return true if
## the set is usable. The GAME calls this; a measuring tool calls
## [method abort_if_invalid] instead.
func report() -> bool:
	for w in _problems.get("warnings", PackedStringArray()):
		push_warning("[LeverSet] " + w)
	for e in _problems.get("errors", PackedStringArray()):
		push_error("[LeverSet] " + e)
	return _problems.get("errors", PackedStringArray()).is_empty()


## Print the problems and the coverage table, then return whether a MEASUREMENT
## may proceed. The rig, the corpus generator and the referee call this; a false
## return means stop, because a run under an invalid lever set produces numbers
## nobody can attribute.
func abort_if_invalid() -> bool:
	var errors: PackedStringArray = _problems.get("errors", PackedStringArray())
	var warnings: PackedStringArray = _problems.get("warnings", PackedStringArray())
	print("[LeverSet] %d levers, digest %s" % [levers.size(), digest()])
	for w in warnings:
		print("  warning: %s" % w)
	for e in errors:
		print("  ERROR: %s" % e)
	for c in coverage():
		var realised: String = "%.3f" % c["realised"] if c["reaches"] > 0 else "n/a"
		print("  %s x %s=%s: reaches %d of %d, worst realised factor %s (authored %.3f)" % [
			c["quantity"], c["by"], str(c["key"]), c["reaches"], c["members"],
			realised, c["factor"]])
	var placeholders: int = _problems.get("placeholders", 0)
	if levers.size() > 0:
		print("  %d of %d factors are still placeholders" % [placeholders, levers.size()])
	if not errors.is_empty():
		push_error("[LeverSet] %d error(s) — refusing to measure under an invalid lever set" % errors.size())
		return false
	return true


func _validate(rows: Array) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var coverage_rows: Array = []
	var placeholders := 0

	if cooldown_ceiling() <= 0:
		errors.append(("could not read MAX_COOLDOWN_ABILITIES out of %s — " +
			"cooldown coverage cannot be computed, and an unread ceiling must " +
			"not read as 'everything is reachable'") % COOLDOWN_CEILING_SOURCE)

	var seen := {}
	for i in range(rows.size()):
		var lever = rows[i]
		var where := "lever %d" % i
		if not (lever is Dictionary):
			errors.append("%s is not an object" % where)
			continue

		var quantity = lever.get("quantity")
		if not QUANTITIES.has(quantity):
			errors.append("%s names quantity '%s'; the enum is %s" % [
				where, str(quantity), str(QUANTITIES.keys())])
			continue
		var domain: String = QUANTITIES[quantity]["domain"]

		var by = lever.get("by")
		if not BYS.has(by):
			errors.append("%s names by '%s'; expected one of %s" % [
				where, str(by), str(BYS.keys())])
			continue
		var by_domain: String = BYS[by]["domain"]
		if by_domain != "" and by_domain != domain:
			errors.append(("%s pairs by '%s' (%s namespace) with quantity '%s' " +
				"(%s namespace) — a lever may only name a category from its " +
				"quantity's own domain") % [where, str(by), by_domain, str(quantity), domain])
			continue

		var key = lever.get("key")
		if by == BY_ALL:
			if key != null:
				errors.append("%s is by '%s' and must carry no key" % [where, BY_ALL])
				continue
		elif key == null:
			errors.append("%s is by '%s' and carries no key" % [where, str(by)])
			continue

		var dedupe := "%s|%s|%s" % [str(quantity), str(by), str(key)]
		if seen.has(dedupe):
			errors.append(("%s repeats %s, already authored as lever %d — two " +
				"levers on one (quantity, category) multiply, which is never " +
				"what somebody editing a file means") % [where, dedupe, seen[dedupe]])
			continue
		seen[dedupe] = i

		var factor = lever.get("factor")
		if not (factor is float or factor is int):
			errors.append("%s has no numeric factor" % where)
			continue
		var f := float(factor)
		if f < FACTOR_MIN or f > FACTOR_MAX:
			errors.append("%s has factor %s, outside [%s, %s]" % [
				where, str(f), str(FACTOR_MIN), str(FACTOR_MAX)])
			continue

		var why = lever.get("why")
		if not (why is String) or str(why).strip_edges().is_empty():
			errors.append(("%s carries no 'why'. A factor is a claim that the " +
				"ROM number is wrong for this kernel; an unexplained one is a " +
				"magic number with a category attached") % where)
			continue

		var evidence = lever.get("evidence")
		if not EVIDENCE.has(evidence):
			errors.append("%s names evidence '%s'; expected one of %s" % [
				where, str(evidence), str(EVIDENCE)])
			continue
		if evidence == "placeholder":
			placeholders += 1

		# --- coverage, and the hollow case ---
		var members := _members_of(by, key, domain)
		if members.is_empty():
			errors.append(("%s names %s '%s', which has NO MEMBERS. A lever on " +
				"an empty category encodes cleanly, passes every other check " +
				"and never fires") % [where, str(by), str(key)])
			continue
		var reaches: Array = []
		for m in members:
			var ok: bool = ability_reaches(quantity, m) if domain == DOMAIN_ABILITY \
				else item_reaches(quantity, m)
			if ok:
				reaches.append(m)
		if reaches.is_empty():
			errors.append(("%s names %s '%s' x '%s': the category exists (%d " +
				"members) and the kernel consumes that quantity on NONE of " +
				"them. This is the bit-0 trap one layer up") % [
					where, str(by), str(key), str(quantity), members.size()])
			continue
		if reaches.size() < members.size():
			warnings.append("%s x %s='%s' applies to %d of %d members" % [
				str(quantity), str(by), str(key), reaches.size(), members.size()])

		coverage_rows.append({
			"quantity": str(quantity),
			"by": str(by),
			"key": key,
			"factor": f,
			"members": members.size(),
			"reaches": reaches.size(),
			"realised": _worst_realised(quantity, domain, reaches, f),
		})

	return {
		"errors": errors,
		"warnings": warnings,
		"coverage": coverage_rows,
		"placeholders": placeholders,
	}


## Every record id in a category. `all` is the whole domain.
static func _members_of(by: Variant, key: Variant, domain: String) -> Array:
	var out: Array = []
	if domain == DOMAIN_ABILITY:
		for aid in AbilityDatabase.ability_ids():
			if by == BY_ALL:
				out.append(aid)
			elif by == BY_ABILITY:
				if _key_eq(key, aid):
					out.append(aid)
			else:
				var cat := ability_category(aid)
				if cat[0] == by and _key_eq(cat[1], key):
					out.append(aid)
		return out
	for item in ItemDatabase.get_weapons():
		var iid := int(item.get("id", -1))
		if iid < 0:
			continue
		if by == BY_ALL:
			out.append(iid)
		elif by == BY_ITEM:
			if _key_eq(key, iid):
				out.append(iid)
		else:
			var cat := item_category(iid)
			if cat[0] == by and _key_eq(cat[1], key):
				out.append(iid)
	return out


## The worst REALISED factor across a category — the biggest gap between what an
## author wrote and what the integer could hold. `wp 3 x 0.9` rounds to 3, a
## realised 1.0 against an authored 0.9, and only a report makes that visible.
static func _worst_realised(quantity: String, domain: String, ids: Array,
		factor: float) -> float:
	var worst := factor
	var worst_gap := 0.0
	for id in ids:
		var rom := _rom_value(quantity, domain, id)
		if rom <= 0:
			continue
		var realised := float(bake(quantity, rom, factor)) / float(rom)
		var gap: float = absf(realised - factor)
		if gap > worst_gap:
			worst_gap = gap
			worst = realised
	return worst


static func _rom_value(quantity: String, domain: String, id: int) -> int:
	if domain == DOMAIN_ITEM:
		match quantity:
			"wp":
				return ItemDatabase.get_weapon_power(id)
			"weapon_range":
				return ItemDatabase.get_weapon_range(id)
			"w_ev":
				return ItemDatabase.get_weapon_evade(id)
		return 0
	var view = AbilityDatabase.get_ability_view(id)
	if view == null:
		return 0
	match quantity:
		"cooldown_ticks":
			return int(view.cooldown_ticks) if view.has("cooldown_ticks") else 0
		"charge_time":
			# The BUFFER value, not the ROM's `ct` — `GPUAbilityLoader` converts
			# `ct * 30` before the lever sees it, and the levered quantity is
			# whatever the kernel actually reads. It matters for the realised
			# factor: `ct` spans 2..20 and would round terribly, `charge_time`
			# spans 60..600 and rounds fine.
			return (int(view.ct) * 30) if view.has("ct") else 0
		"mp_cost":
			return int(view.mp_cost) if view.has("mp_cost") else 0
	return 0


# --- provenance (ADR-0277 dec. 10) --------------------------------------------


## A digest of the COMPOSED EFFECTIVE FACTORS, plus the pacing layer's live
## values. Stamped on every corpus row so "are these two rows comparable?" is a
## check rather than an assumption.
##
## 🔴 THE OUTPUT IS HASHED, NOT THE INPUT. An input hash moves when a key is
## reordered or a `why` is reworded — changes that alter nothing — so people
## learn to ignore the column; and it stays still when a loader change alters
## behaviour without touching the file. Hashing the composed result means the
## digest moves exactly when the numbers the kernel sees move. The cost is that
## a corrupted loader hashes its own corruption confidently.
## 🔴 CHEAP ENOUGH TO CALL PER SAMPLE, WHICH IS THE POINT. The composed half is
## folded once per instance (the lever set is immutable at run time — the reload
## refuses while a battle is live), and only the pacing half is re-read. If this
## were computed at WRITE time instead of SAMPLE time the column would be
## constant by construction, and the "a run under two configurations says so"
## property above would be a claim no row could falsify.
func digest() -> String:
	if _composed_digest.is_empty():
		_composed_digest = _compose_digest()
	var pacing := PackedStringArray()
	for slug in PACING_SLUGS:
		pacing.append("%s=%.6f" % [slug, _pacing_value(slug)])
	return ("\n".join(pacing) + "\n" + _composed_digest).sha256_text().substr(0, 16)


func _compose_digest() -> String:
	var parts := PackedStringArray()
	for quantity in QUANTITIES.keys():
		var domain: String = QUANTITIES[quantity]["domain"]
		if domain == DOMAIN_ABILITY:
			for aid in AbilityDatabase.ability_ids():
				var f := ability_factor(quantity, aid)
				if not is_equal_approx(f, 1.0):
					parts.append("%s:a%d=%.6f" % [quantity, aid, f])
		else:
			for item in ItemDatabase.get_weapons():
				var iid := int(item.get("id", -1))
				if iid < 0:
					continue
				var f := item_factor(quantity, iid)
				if not is_equal_approx(f, 1.0):
					parts.append("%s:i%d=%.6f" % [quantity, iid, f])
	return "\n".join(parts).sha256_text()


static func _pacing_value(slug: String) -> float:
	# `Tune` is an autoload, so it is unreachable from a pure unit test that
	# never boots the project; fall back to the identity rather than throwing.
	if not Engine.get_main_loop():
		return 1.0
	var tune = Engine.get_main_loop().root.get_node_or_null("Tune") \
		if Engine.get_main_loop() is SceneTree else null
	if tune == null:
		return 1.0
	if tune.has_method("is_registered") and not tune.is_registered(slug):
		return 1.0
	return float(tune.get_value(slug))
