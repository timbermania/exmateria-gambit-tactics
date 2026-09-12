extends RefCounted

## The formation ability-picker's full CATALOG source (ADR-0197) — a testing
## scaffold that lists every applicable option for a slot with NO progression
## gate, so the picker's 5-row scroll/render pipeline gets exercised before real
## learned/unlocked data exists. The ROM-faithful, gated sibling is
## `AbilityLoadout.candidates` (the learned/unlocked set), retained untouched;
## only one wiring seam switches to this. Mirrors the shipped equip picker's
## always-on `EquipCandidates.build_catalog` (all slot-legal items, ownership
## ignored).
##
## `build_catalog(slot)` is unit-independent and pure, returning picker rows
## `{id, name}` name-sorted ascending with `id` as the stable tie-break:
##   - REACTION/SUPPORT/MOVEMENT: every ability of the slot's type
##     (`AbilityDatabase.get_views_by_type`); `id` = the ability id.
##   - SECONDARY: one row per UNIQUE action-skillset name (many jobs share a
##     skillset), deduped from every job in jobs.json (generic + special + monster);
##     `id` = the skillset's representative job (prefer-generic-else-lowest, see
##     `_secondary_catalog`), committed as `sub_job_id`.
##   - PRIMARY / any non-editable slot: not handled -> `[]`.
##
## Placeholder rows are dropped as data hygiene (NOT a progression gate): a
## blank/whitespace name, or the ROM's unused-slot pad name "(Nothing)" (R/S/M
## skillsets pad with it), or a monster job whose skill_set_id points past the
## skillset table (no name at all). Commits stay unvalidated/sandbox by design.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")
# The slot vocabulary and its slot->type projection, reached at their home rather
# than through `AbilityLoadout`, which is `state`. (#1059 phase 3 would have moved
# that member to the Character Catalogue and ADR-0300 REJECTS the move, so this
# read no longer has a boundary to dodge — what survives is the plain reason, which
# is that a vocabulary should be read where it is published.) This file read
# `AbilityLoadout._SLOT_TYPE` across a file
# boundary through the leading underscore; `AbilitySlot.SLOT_TYPE` is the same table,
# published.
const AbilitySlot = preload("res://addons/exmateria_almanac/abilities/AbilitySlot.gd")
const AbilityType = preload("res://addons/exmateria_almanac/abilities/AbilityType.gd")
const JobDatabase = preload("res://addons/exmateria_almanac/jobs/JobDatabase.gd")

## The slot -> ability_type name string that `AbilityDatabase.get_views_by_type`
## keys on. Derived from `AbilitySlot.SLOT_TYPE` (slot -> AbilityType.Type)
## so the slot classification is not duplicated; this only names the enum.
const _TYPE_NAME := {
	AbilityType.Type.REACTION: "Reaction",
	AbilityType.Type.SUPPORT: "Support",
	AbilityType.Type.MOVEMENT: "Movement",
}

## The ROM pads unused R/S/M skillset slots with a "(Nothing)" ability; it is not
## a real pick, so it is dropped alongside genuinely blank names.
const _PLACEHOLDER_NAME := "(Nothing)"


static func build_catalog(slot: int) -> Array:
	if slot == AbilitySlot.Slot.SECONDARY:
		return _secondary_catalog()
	return _rsm_catalog(slot)


## Every ability of the slot's type, placeholder rows dropped, {id, name} sorted.
static func _rsm_catalog(slot: int) -> Array:
	if not AbilitySlot.SLOT_TYPE.has(slot):
		return []
	var type_name: String = _TYPE_NAME[AbilitySlot.SLOT_TYPE[slot]]
	var out: Array = []
	for view in AbilityDatabase.get_views_by_type(type_name):
		if _is_placeholder(view.name):
			continue
		out.append({"id": view.ability_id, "name": view.name})
	return _sorted(out)


## One row per UNIQUE skillset (ADR-0197 dec. 3): job->skillset is 1:1, but many
## jobs SHARE a skillset (24 map to "SkillSet_00"; Delita+Agrias+Wiegraf all to "Holy
## Sword"), so listing every job produced duplicate rows — noise. We dedup by
## skill_set_id, nameless jobs (monster skill_set_ids past the table) dropped, {id, name}
## sorted. The row `id` is the skillset's REPRESENTATIVE job, committed as sub_job_id:
## the GENERIC job (0x4A-0x5D) that owns it when one exists ("Item" -> Chemist 0x4b, the
## player-meaningful owner — NOT the lower non-generic 0x35), else the lowest job id for
## determinism (the story/boss-only skillsets — Holy Sword &c. — have no generic and are
## not legal secondaries anyway). Job<->character alignment is real (FFTPatcher
## SpecialNames: 0x1e = Agrias/Holy Sword) but non-unique, so generic-ownership is the
## meaningful key. Was one row PER JOB (ADR-0197 as first shipped).
static func _secondary_catalog() -> Array:
	# Keyed by NAME, not skill_set_id: the picker shows names, and distinct skillset
	# ids can carry the SAME display name (two "Yin Yang Magic" records), which would
	# still read as duplicate rows. Deduping by name is the visible-noise fix the user
	# asked for (112 jobs -> 51 unique names).
	var rep := {}   # skillset name -> representative job id (int)
	for job_id in JobDatabase.all_job_ids():
		var sid := int(JobDatabase.get_job(job_id).get("skill_set_id", 0))
		var name := str(AbilityDatabase.get_skill_set(sid).get("name", ""))
		if _is_placeholder(name):
			continue
		var jint: int = job_id.hex_to_int()
		rep[name] = jint if not rep.has(name) else _prefer_rep(rep[name], jint)
	var out: Array = []
	for name in rep:
		out.append({"id": rep[name], "name": name})
	return _sorted(out)


## Generic job id range — the only jobs that are legal secondaries in the real game, so
## the canonical owner of a skillset that has one (Chemist owns "Item").
const _GENERIC_JOB_LO := 0x4A
const _GENERIC_JOB_HI := 0x5D


## Choose the better representative between the incumbent and a challenger job for a
## shared skillset: a GENERIC job wins over a non-generic; between two of the same class,
## the lower id wins (deterministic fallback).
static func _prefer_rep(incumbent: int, challenger: int) -> int:
	var inc_generic := _is_generic_job(incumbent)
	var chl_generic := _is_generic_job(challenger)
	if inc_generic != chl_generic:
		return challenger if chl_generic else incumbent
	return mini(incumbent, challenger)


static func _is_generic_job(job_int: int) -> bool:
	return job_int >= _GENERIC_JOB_LO and job_int <= _GENERIC_JOB_HI


static func _is_placeholder(name: String) -> bool:
	var n := name.strip_edges()
	return n.is_empty() or n == _PLACEHOLDER_NAME


## Name ascending, id as the stable tie-break — deterministic across the shared
## skillset names (mirrors the ROM's fixed catalog order for the port).
static func _sorted(rows: Array) -> Array:
	rows.sort_custom(func(a, b):
		if String(a["name"]) == String(b["name"]):
			return int(a["id"]) < int(b["id"])
		return String(a["name"]) < String(b["name"]))
	return rows
