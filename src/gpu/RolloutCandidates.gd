class_name RolloutCandidates
extends RefCounted

## The CANDIDATE SET for one rollout beat (#895, §7) — pure, no GPU.
##
## §7's enemy AI picks its move by running `K` candidate gambit edits x `M`
## common-random-number seeds for `H` ticks and scoring the fleet. This file is
## the `K`: given the acting unit's CURRENT gambit rows it enumerates the edits
## worth trying. `RolloutHarness` runs them; the value function that ranks the
## results is #896's.
##
## 🔴 A CANDIDATE IS AN ENCODED GAMBIT IMAGE, NOT A `GambitList`. The mutation
## domain is the buffer — `GAMBITS_PER_UNIT` ints, exactly the slice
## `snapshot_battle` hands back and `restore_battle` installs. Mutating domain
## objects instead would mean a `Gambit` -> encoder -> packer round trip per
## candidate, and every candidate would then be able to FAIL to encode
## (ADR-0023's faithful-or-explicit skip) in the middle of a thinking beat, with
## nothing to do about it. An image edit is definitionally installable. Authored
## postures still come in through the encoder (`RolloutPlaybook`) — that is the
## one place where a new gambit is spelled rather than edited, so it is the one
## place the encoder's verdict is available and useful.
##
## 🔴 THE LEGALITY PREFILTER IS STATIC-ONLY, AND THAT IS THE WHOLE DESIGN. §7
## says the prefilter "reuses `spell_pre_validate` / `cooldown_pre_validate`" —
## and those live in `stage_compute.glsl`, reading CURRENT MP and a live cooldown
## clock. A CPU copy of them would be a second implementation of a runtime rule,
## and the two copies would disagree (the same objection #894 raises against a
## cleverer imperative-gambit predicate). So this file prunes only what CANNOT
## change over the horizon:
##
##   - an ability the unit does not have;
##   - an ability whose `mp_cost` exceeds the unit's MAX MP, which no amount of
##     regeneration can pay.
##
## Both read the SAME ability table the shader reads (`GPUAbilityLoader.build`'s
## buffer), so they are not a copy of the rule — they are a ceiling test on the
## rule's own inputs. Everything dynamic stays in the shader, where a candidate
## whose slot cannot fire falls through to the next slot exactly as it would in a
## real battle. That fall-through is not waste: a candidate that is illegal for
## the whole horizon simply scores like the plan it degrades to, which is the
## truth about it.
##
## ⚠️ IMPERATIVE-ISSUE CANDIDATES ARE NOT HERE, AND CANNOT BE YET. §7's third
## family is "imperative-issue when charges remain" — a one-shot lock-on at top
## priority. A lock-on needs to name ONE unit, and no encodable target does:
## `TARGET_THEM` is the unit the condition matched, not a unit the issuer chose,
## and `TargetSelector.PoolType.SPECIFIC_UNITS` is in the encoder's UNSUPPORTED
## set (ADR-0023). The charge economy is #894's, and so is the target encoding it
## needs; this file gains a sixth family when that lands.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase
const StatusEncoder = ExMateriaAlmanac.StatusEncoder
const StatusRegistry = ExMateriaAlmanac.StatusRegistry

const MAX_USER_GAMBITS := GPUConstants.MAX_USER_GAMBITS
const GAMBIT_SIZE := GPUConstants.GAMBIT_SIZE
const GAMBITS_PER_UNIT := GPUCombatPacker.GAMBITS_PER_UNIT
const ABILITY_SIZE := GPUConstants.ABILITY_SIZE
const MAX_ABILITIES := GPUConstants.MAX_ABILITIES

## Mirror of `combat_common.glslinc`'s `ABFLAG_HEALING` (bit 2), the HP-write-
## direction predicate. `GPUAbilityLoader.build` mirrors the same bit when it
## PACKS the table; this reads it back out of the packed table, so the two agree
## by construction rather than by discipline.
const ABFLAG_HEALING := 4

## The two packed fields `ability_revives` reads (#1113 / ADR-0293), mirrored the
## same way `ABFLAG_HEALING` is — off the table the shader itself indexes, not off
## a second copy of the rule. `StatusRegistry`'s bits are held to the shader's by
## `tests/StatusRegistryTest.gd::_test_shader_parity`, so `bit(&"dead")` is a
## CHECKED mirror where a literal `0` would be an unchecked one.
const INFLICT_MODE_CANCEL := StatusEncoder.MODE_CANCEL

## Family order. Also the interleave order, so a K too small to hold every
## candidate drops the TAIL OF EVERY FAMILY rather than whole families — §7's
## degradation reasoning ("bias is worse than variance") applied to the candidate
## set: losing every playbook posture biases the search toward small edits,
## losing the last two of each family only narrows it.
const FAMILIES: Array[String] = ["swap", "condition", "action", "delete", "insert", "playbook"]

## Condition replacements offered per enabled slot. Small and DECLARED: the
## search space of a one-step edit has to be readable, or a bad AI decision
## cannot be traced to the option that produced it.
const CONDITION_MENU: Array[Dictionary] = [
	{"type": GPUConstants.COND_ALWAYS, "value": 0},
	{"type": GPUConstants.COND_HP_BELOW, "value": 50},
	{"type": GPUConstants.COND_HP_BELOW, "value": 25},
	{"type": GPUConstants.COND_HP_ABOVE, "value": 50},
	{"type": GPUConstants.COND_DISTANCE_LESS, "value": 3},
	{"type": GPUConstants.COND_DISTANCE_GREATER, "value": 3},
]

## Who the replaced condition is checked against.
const CONDITION_TARGET_MENU: Array[int] = [
	GPUConstants.TARGET_NEAREST_ENEMY,
	GPUConstants.TARGET_LOWEST_HP_ENEMY,
	GPUConstants.TARGET_LOWEST_HP_ALLY,
	GPUConstants.TARGET_SELF,
]

## Openers an `insert` may put into a free slot, as (cond_target, cond) pairs
## with the action filled in per-unit. Kept to three because an insert lands at a
## slot's PRIORITY, so the family is already multiplied by the number of free
## slots.
const INSERT_CONDITION_MENU: Array[Dictionary] = [
	{"target": GPUConstants.TARGET_NEAREST_ENEMY, "type": GPUConstants.COND_ALWAYS, "value": 0},
	{"target": GPUConstants.TARGET_LOWEST_HP_ENEMY, "type": GPUConstants.COND_HP_BELOW, "value": 40},
	{"target": GPUConstants.TARGET_SELF, "type": GPUConstants.COND_HP_BELOW, "value": 40},
]


#region Context


## Bundle the acting unit's STATIC facts once, so every operator reads the same
## set and a caller cannot hand two families two different rosters.
##
## `ability_ids` is the unit's usable ability ids (equipped / learned — the
## caller's domain knowledge; nothing in the GPU unit block records it).
## `ability_buffer` is `GPUAbilityLoader.build()["buffer"]`, the very table the
## shader indexes.
static func make_context(job_id: String, ability_ids: Array, max_mp: int,
		ability_buffer: PackedInt32Array) -> Dictionary:
	var split := usable_abilities(ability_ids, max_mp, ability_buffer)
	return {
		"job_id": job_id,
		"role": JobDatabase.get_job_role(job_id),
		"offensive": split["offensive"],
		"healing": split["healing"],
		"revive": split["revive"],
	}


## The static prefilter. Returns `{offensive: [...], healing: [...], revive: [...]}`
## — the ids the unit has, that fit inside its MAX MP, split by the table's own
## healing bit and its own inflict list.
##
## 🔴 THE THREE BUCKETS ARE DISJOINT, AND THE REVIVE ONE IS CHECKED FIRST (#1104).
## A revive's target is a corpse, so a posture that aims one anywhere else is a
## plan with no effect at best — and both misfilings were live before the bucket
## existed. `Raise` is `receive_heal`, so it landed in `healing` and `_mend_postures`
## spent a posture casting it at the worst-off LIVING ally; `Revive` (107) is not,
## so it landed in `offensive` and `_ability_postures` authored "cast Revive at the
## nearest ENEMY, always" — a percentage-heal formula (0x35) pointed at the other
## team. Neither posture fails to encode, which is exactly why the split has to
## happen here rather than being left to the author of a posture.
##
## A malformed ability table is an ERROR, not a shrug: returning "no abilities"
## quietly would make every caster candidate an attack candidate and the rollout
## would confidently recommend melee for a Wizard.
static func usable_abilities(ability_ids: Array, max_mp: int,
		ability_buffer: PackedInt32Array) -> Dictionary:
	var out := {"offensive": [], "healing": [], "revive": []}
	if ability_buffer.size() < MAX_ABILITIES * ABILITY_SIZE:
		push_error("[RolloutCandidates] ability buffer is %d ints, expected %d (GPUAbilityLoader.build()['buffer']) — no ability candidate can be judged" % [
			ability_buffer.size(), MAX_ABILITIES * ABILITY_SIZE])
		return out
	for raw in ability_ids:
		var id := int(raw)
		if id < 0 or id >= MAX_ABILITIES:
			continue
		var base := id * ABILITY_SIZE
		if ability_buffer[base + GPUCombatPacker.AbilityField.MP_COST] > max_mp:
			continue
		var flags := ability_buffer[base + GPUCombatPacker.AbilityField.FLAGS]
		if ability_revives(id, ability_buffer):
			out["revive"].append(id)
		elif (flags & ABFLAG_HEALING) != 0:
			out["healing"].append(id)
		else:
			out["offensive"].append(id)
	return out


## Whether this ability undoes death — the CPU reading of `combat_common.glslinc`'s
## `ability_revives` (#1113 / ADR-0293 dec. 1): FFT carries no "may target the dead"
## flag, it carries an inflict list, and the abilities that raise the fallen are
## exactly the ones whose list names `Dead` under mode `cancel`. Over the shipped
## database that is five — Raise (5), Raise2 (6), Revive (107), Oink (312),
## PhoenixDown (381).
##
## Not a second implementation of a runtime rule (this file's header bans those):
## both fields are STATIC table data, and this reads them out of the very buffer
## the shader indexes, so the two answers cannot disagree.
static func ability_revives(ability_id: int, ability_buffer: PackedInt32Array) -> bool:
	if ability_id < 0 or ability_id >= MAX_ABILITIES:
		return false
	var base := ability_id * ABILITY_SIZE
	if base + ABILITY_SIZE > ability_buffer.size():
		return false
	if ability_buffer[base + GPUCombatPacker.AbilityField.INFLICT_MODE] != INFLICT_MODE_CANCEL:
		return false
	var mask := ability_buffer[base + GPUCombatPacker.AbilityField.INFLICT_MASK]
	return (mask & (1 << StatusRegistry.bit(&"dead"))) != 0


#endregion


#region Image accessors


## The acting unit's gambit rows, cut out of a `snapshot_battle` gambit slice.
static func unit_rows(gambit_slice: PackedInt32Array, unit_idx: int) -> PackedInt32Array:
	var start := unit_idx * GAMBITS_PER_UNIT
	if start < 0 or start + GAMBITS_PER_UNIT > gambit_slice.size():
		push_error("[RolloutCandidates] unit %d has no rows in a %d-int gambit slice" % [
			unit_idx, gambit_slice.size()])
		return PackedInt32Array()
	return gambit_slice.slice(start, start + GAMBITS_PER_UNIT)


## Write a candidate image back over one unit's rows, in place.
static func write_unit_rows(gambit_slice: PackedInt32Array, unit_idx: int,
		rows: PackedInt32Array) -> bool:
	var start := unit_idx * GAMBITS_PER_UNIT
	if rows.size() != GAMBITS_PER_UNIT or start < 0 \
			or start + GAMBITS_PER_UNIT > gambit_slice.size():
		push_error("[RolloutCandidates] cannot write %d-int rows for unit %d into a %d-int slice" % [
			rows.size(), unit_idx, gambit_slice.size()])
		return false
	for i in range(GAMBITS_PER_UNIT):
		gambit_slice[start + i] = rows[i]
	return true


static func get_field(rows: PackedInt32Array, slot: int, field: int) -> int:
	return rows[slot * GAMBIT_SIZE + field]


static func set_field(rows: PackedInt32Array, slot: int, field: int, value: int) -> void:
	rows[slot * GAMBIT_SIZE + field] = value


## User slots that would actually be evaluated. The safety net at slot
## `MAX_USER_GAMBITS` is never in this list and no operator may touch it —
## ADR-0048 exists so the gambit pass always has a terminal candidate, and a
## rollout that mutated it would be measuring a unit that can strand itself.
static func enabled_slots(rows: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	for slot in range(MAX_USER_GAMBITS):
		if get_field(rows, slot, GPUCombatPacker.GambitField.ENABLED) != 0:
			out.append(slot)
	return out


static func free_slots(rows: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	for slot in range(MAX_USER_GAMBITS):
		if get_field(rows, slot, GPUCombatPacker.GambitField.ENABLED) == 0:
			out.append(slot)
	return out


#endregion


#region Generation


## The whole candidate set, family by family, in canonical order. Deterministic:
## the same rows and context always give the same list, which is what makes the
## AI's choice reproducible (§7's second reason for common random numbers).
static func families(rows: PackedInt32Array, ctx: Dictionary) -> Dictionary:
	return {
		"swap": _family_swap(rows),
		"condition": _family_condition(rows),
		"action": _family_action(rows, ctx),
		"delete": _family_delete(rows),
		"insert": _family_insert(rows, ctx),
		"playbook": _family_playbook(ctx),
	}


## The candidate list a beat runs: the INCUMBENT first, then up to `k - 1`
## mutations interleaved across families.
##
## 🔴 CANDIDATE 0 IS THE UNMUTATED LIST. Without it the comparison has no "leave
## it alone" arm, and the AI is forced to change its gambits every single turn —
## it would re-plan a working posture into a worse one the moment every mutation
## scored below the incumbent, because nothing would be carrying the incumbent's
## score. It also makes the fleet self-calibrating: #896's value function is
## scored against a number produced by the same H, the same seeds and the same
## code path.
##
## Duplicates are dropped (two operators can land on the same image, and an edit
## can reproduce the incumbent), so the returned list may be shorter than `k`.
## Shorter is correct — a duplicated candidate spends a battle slot to learn a
## number it already has.
static func generate(rows: PackedInt32Array, ctx: Dictionary, k: int) -> Array:
	var out: Array = []
	if rows.size() != GAMBITS_PER_UNIT:
		push_error("[RolloutCandidates] gambit image is %d ints, expected %d" % [
			rows.size(), GAMBITS_PER_UNIT])
		return out
	if k <= 0:
		return out
	var seen := {}
	var incumbent := rows.duplicate()
	out.append(incumbent)
	seen[_key(incumbent)] = true

	var fam := families(rows, ctx)
	var cursors := {}
	for name in FAMILIES:
		cursors[name] = 0
	var drained := false
	while out.size() < k and not drained:
		drained = true
		for name in FAMILIES:
			if out.size() >= k:
				break
			var list: Array = fam[name]
			var i: int = cursors[name]
			# Walk past this family's duplicates in the same pass — otherwise a
			# family whose head repeats an earlier candidate would surrender its
			# whole turn in the round robin and starve behind the others.
			while i < list.size():
				var cand: PackedInt32Array = list[i]
				i += 1
				var key := _key(cand)
				if seen.has(key):
					continue
				seen[key] = true
				out.append(cand)
				break
			if i < list.size():
				drained = false
			cursors[name] = i
	return out


static func _key(rows: PackedInt32Array) -> String:
	return rows.to_byte_array().hex_encode()


#endregion


#region Operators


## Swap two slots' priority. Both blocks move, so a swap of two enabled slots
## reorders the plan and a swap with a free slot moves one entry DOWN the list
## past the free one — which is a real priority change, not a no-op, because
## evaluation walks slots in order.
static func _family_swap(rows: PackedInt32Array) -> Array:
	var out: Array = []
	var live := enabled_slots(rows)
	if live.is_empty():
		return out
	for i in range(MAX_USER_GAMBITS):
		for j in range(i + 1, MAX_USER_GAMBITS):
			if not (live.has(i) or live.has(j)):
				continue
			var cand := rows.duplicate()
			for f in range(GAMBIT_SIZE):
				cand[i * GAMBIT_SIZE + f] = rows[j * GAMBIT_SIZE + f]
				cand[j * GAMBIT_SIZE + f] = rows[i * GAMBIT_SIZE + f]
			out.append(cand)
	return out


## Replace an enabled slot's condition — both the test and who it is tested
## against. Collapses the slot to ONE condition, matching what the packer writes
## for a single-condition gambit (`COND_COUNT = 1`, remaining slots ALWAYS/0), so
## a mutated image is byte-identical to an authored one that says the same thing.
static func _family_condition(rows: PackedInt32Array) -> Array:
	var out: Array = []
	var GF := GPUCombatPacker.GambitField
	for slot in enabled_slots(rows):
		for target in CONDITION_TARGET_MENU:
			for entry in CONDITION_MENU:
				var cand := rows.duplicate()
				set_field(cand, slot, GF.COND_TARGET_TYPE, target)
				set_field(cand, slot, GF.COND_COUNT, 1)
				set_field(cand, slot, GF.COND_TYPE_0, entry["type"])
				set_field(cand, slot, GF.COND_VAL_0, entry["value"])
				for c in range(1, 4):
					set_field(cand, slot, GF.COND_TYPE_0 + c, GPUConstants.COND_ALWAYS)
					set_field(cand, slot, GF.COND_VAL_0 + c, 0)
				out.append(cand)
	return out


## Replace an enabled slot's action. ATTACK and WAIT are in the menu alongside
## the unit's abilities even though neither is "another learned ability" (§7's
## words): they are the two verbs every unit always has, and a candidate set that
## cannot propose them cannot walk a unit back off a spell it should stop casting.
static func _family_action(rows: PackedInt32Array, ctx: Dictionary) -> Array:
	var out: Array = []
	var GF := GPUCombatPacker.GambitField
	for slot in enabled_slots(rows):
		for action in _action_menu(ctx):
			var cand := rows.duplicate()
			set_field(cand, slot, GF.ACTION_TYPE, action["type"])
			set_field(cand, slot, GF.ACTION_ID, action["id"])
			set_field(cand, slot, GF.ACTION_TARGET_TYPE, GPUConstants.TARGET_THEM)
			out.append(cand)
	return out


static func _action_menu(ctx: Dictionary) -> Array:
	var menu: Array = [
		{"type": GPUConstants.ACTION_ATTACK, "id": 0},
		{"type": GPUConstants.ACTION_WAIT, "id": 0},
	]
	for id in ctx.get("offensive", []):
		menu.append({"type": GPUConstants.ACTION_SPELL, "id": int(id)})
	for id in ctx.get("healing", []):
		menu.append({"type": GPUConstants.ACTION_SPELL, "id": int(id)})
	return menu


## Disable one enabled slot. Everything below it keeps its own slot — the shader
## skips a disabled slot rather than compacting, so a delete is a deletion and
## not also a reorder.
static func _family_delete(rows: PackedInt32Array) -> Array:
	var out: Array = []
	for slot in enabled_slots(rows):
		var cand := rows.duplicate()
		set_field(cand, slot, GPUCombatPacker.GambitField.ENABLED, 0)
		out.append(cand)
	return out


## Fill a free slot with a new entry. The slot index IS the priority, so the same
## opener in slot 0 and in slot 3 are different plans and both are offered.
static func _family_insert(rows: PackedInt32Array, ctx: Dictionary) -> Array:
	var out: Array = []
	var GF := GPUCombatPacker.GambitField
	for slot in free_slots(rows):
		for opener in INSERT_CONDITION_MENU:
			for action in _action_menu(ctx):
				if action["type"] == GPUConstants.ACTION_WAIT:
					continue  # inserting a WAIT is a delete with extra steps
				var cand := rows.duplicate()
				set_field(cand, slot, GF.ENABLED, 1)
				set_field(cand, slot, GF.COND_TARGET_TYPE, opener["target"])
				set_field(cand, slot, GF.COND_COUNT, 1)
				set_field(cand, slot, GF.COND_TYPE_0, opener["type"])
				set_field(cand, slot, GF.COND_VAL_0, opener["value"])
				for c in range(1, 4):
					set_field(cand, slot, GF.COND_TYPE_0 + c, GPUConstants.COND_ALWAYS)
					set_field(cand, slot, GF.COND_VAL_0 + c, 0)
				set_field(cand, slot, GF.ACTION_TYPE, action["type"])
				set_field(cand, slot, GF.ACTION_ID, action["id"])
				set_field(cand, slot, GF.ACTION_TARGET_TYPE, GPUConstants.TARGET_THEM)
				out.append(cand)
	return out


## Whole authored postures (`RolloutPlaybook`), encoded by the one encoder. A
## posture the GPU cannot express is dropped here with the encoder's own error —
## the ADR-0023 verdict, not a silent substitution.
static func _family_playbook(ctx: Dictionary) -> Array:
	var out: Array = []
	var postures := RolloutPlaybook.postures_for(
		int(ctx.get("role", -1)), ctx.get("offensive", []), ctx.get("healing", []),
		ctx.get("revive", []))
	for posture in postures:
		var configs := GambitEncoder.encode_gambits(posture)
		# A null in the AUTHORED region is the encoder's ADR-0023 skip verdict on a
		# gambit this posture spelled. A null PAST that region is just padding —
		# `encode_gambits` fills every unauthored user slot with one so the safety
		# net always lands at slot MAX_USER_GAMBITS. Only the first kind is a
		# rejection, and reading the second as one drops every posture shorter
		# than five gambits, which is all of them.
		var skipped := false
		for i in range(mini(posture.size(), configs.size())):
			if configs[i] == null:
				skipped = true
		if skipped:
			continue
		out.append(GPUCombatPacker._pack_gambits(configs))
	return out


#endregion
