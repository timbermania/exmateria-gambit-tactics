extends RefCounted

## A unit's 5-slot ability loadout — the port model of the ROM `unit+0x5e`
## record (ABILITY_PICKER.md §2). The formation ability "Set" flow reads the
## current slot values from here and commits the picked id back.
##
##   [0] PRIMARY   skillset id  — job-fixed, NOT editable (ROM "slot 0 unselectable")
##   [1] SECONDARY job id       — the sub-job whose action skillset is equipped
##   [2] REACTION  ability id
##   [3] SUPPORT   ability id
##   [4] MOVEMENT  ability id
##
## Slot 0 holds a SKILLSET id; slot 1 holds a JOB id (the port stores the secondary
## as `UnitProgression.sub_job_id`, a job — and job→skillset is 1:1 via jobs.json
## `skill_set_id`, so "Chemist" ⇒ Item, "Ninja" ⇒ Throw, "Holy Knight" ⇒ Holy Sword);
## slots 2/3/4 hold ABILITY ids. 0 = none/empty. Standalone + fixture-testable.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const _Self = preload("res://addons/exmateria_almanac/abilities/AbilityLoadout.gd")
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")
const AbilityType = preload("res://addons/exmateria_almanac/abilities/AbilityType.gd")
const JobDatabase = preload("res://addons/exmateria_almanac/jobs/JobDatabase.gd")

# `Slot` and the slot->type projection are FIXED VOCABULARY and live in the almanac
# (#1059 phase 3): this member is `state` and was to move to the Character Catalogue,
# while `abilities/AbilityCandidates.gd` reads both names and stays. ADR-0300 REJECTS
# that move and this member stays too — the split is still right, for the reason
# `AbilitySlot.gd` gives, and it no longer anticipates a boundary. Re-exported, so every
# `AbilityLoadout.Slot.*` site and the two `_SLOT_TYPE` reads below are unchanged.
# `_SLOT_TYPE` is now `AbilitySlot.SLOT_TYPE` at its home — AbilityCandidates was
# reading it THROUGH THE UNDERSCORE, so it was never really private.
const AbilitySlot = preload("res://addons/exmateria_almanac/abilities/AbilitySlot.gd")
const Slot = AbilitySlot.Slot
const _SLOT_TYPE = AbilitySlot.SLOT_TYPE

var _values := {
	Slot.PRIMARY: 0,
	Slot.SECONDARY: 0,
	Slot.REACTION: 0,
	Slot.SUPPORT: 0,
	Slot.MOVEMENT: 0,
}

## Ability ids the unit has learned — the source R/S/M candidates are drawn
## from (the port model of the `+0x7a` learned masks). Order-preserving.
var _learned: Array = []

## Secondary-slot candidate rows `{id: job_id, name: skillset_name}` — the jobs
## the unit may equip as its sub-job (the port model of the secondary-skillset
## enumeration, ROM `FUN_80122790`). Order-preserving.
var _secondary_candidates: Array = []


func _init(primary_skillset: int = 0) -> void:
	_values[Slot.PRIMARY] = primary_skillset


## The R/S/M slot -> its persistent UnitProgression field. Secondary is handled
## separately (it writes sub_job_id, a job — not an equipped_* ability field).
const _PROG_FIELD := {
	Slot.REACTION: "equipped_reaction",
	Slot.SUPPORT: "equipped_support",
	Slot.MOVEMENT: "equipped_movement",
}


## Build a loadout from a live unit's persistent state (UnitProgression). Primary
## = the job's skillset (jobs.json skill_set_id); R/S/M current values mirror the
## equipped_* fields (-1 none -> 0 none); R/S/M candidates draw from learned_abilities;
## secondary candidates = the unlocked GENERIC jobs (minus the current job), each
## keyed by job id and shown by its skillset name (job→skillset is 1:1).
static func from_progression(prog) -> _Self:
	var primary := int(JobDatabase.get_job(prog.current_job_id).get("skill_set_id", 0))
	var lo := _Self.new(primary)
	for slot in _PROG_FIELD:
		var v := int(prog.get(_PROG_FIELD[slot]))
		lo._values[slot] = 0 if v < 0 else v
	lo.set_learned_abilities(prog.learned_abilities.keys())
	# Secondary: the current sub-job (job id, 0 = none) + the candidate sub-jobs.
	var sub := str(prog.sub_job_id)
	lo._values[Slot.SECONDARY] = 0 if sub.is_empty() else sub.hex_to_int()
	lo.set_secondary_candidates(_secondary_jobs_for(prog))
	return lo


## The sub-job candidates for a unit: every unlocked GENERIC job except the one it
## is currently in (the ROM never offers the primary back), each `{id, name}` where
## name is the job's action-skillset name. Special/monster jobs are NOT secondary-
## equippable (only generics 0x4A-0x5D), so Holy Sword & co. never appear here.
static func _secondary_jobs_for(prog) -> Array:
	var current := str(prog.current_job_id)
	var out: Array = []
	for job_id in JobDatabase.get_all_generic_jobs():
		if job_id == current:
			continue
		if not prog.is_job_unlocked(job_id):
			continue
		var sid := int(JobDatabase.get_job(job_id).get("skill_set_id", 0))
		out.append({"id": job_id.hex_to_int(), "name": str(AbilityDatabase.get_skill_set(sid).get("name", ""))})
	return out


## Commit a picked id into a unit's persistent state — the picker's ROM commit
## (`world_ability_slot_commit`) writing back to the equip-flow record. Secondary
## writes the sub-job (job id -> the "%02x" hex UnitProgression uses); R/S/M write
## the equipped_* ability field.
static func commit_to_progression(prog, slot: int, id: int) -> void:
	if slot == Slot.SECONDARY:
		prog.sub_job_id = "" if id <= 0 else "%02x" % id
		return
	if _PROG_FIELD.has(slot):
		prog.set(_PROG_FIELD[slot], id)


## Clear one slot back to UnitProgression's OWN "none" sentinel — the ability "Remove" mechanic
## (world_ability_slot_clear), the mirror of UnitProgression.unequip_item. R/S/M reset to -1, the
## secondary sub-job to ""; the job-fixed PRIMARY is never clearable. Returns true iff the slot was
## occupied (something was actually cleared) — an already-empty slot is a silent no-op (false),
## like unequip_item returning -1, so the caller can hold slot focus without a repaint.
static func clear_in_progression(prog, slot: int) -> bool:
	if slot == Slot.SECONDARY:
		if str(prog.sub_job_id).is_empty():
			return false
		prog.sub_job_id = ""
		return true
	if _PROG_FIELD.has(slot):
		if int(prog.get(_PROG_FIELD[slot])) < 0:
			return false
		prog.set(_PROG_FIELD[slot], -1)
		return true
	return false          # PRIMARY (job-fixed) and any non-slot value


func set_learned_abilities(ids: Array) -> void:
	_learned = ids.duplicate()


func set_secondary_candidates(entries: Array) -> void:
	_secondary_candidates = entries.duplicate()


## Candidate rows for an editable slot — the list the picker renders, each `{id, name}`.
## SECONDARY: the unlocked sub-jobs (by skillset name). R/S/M: the learned abilities
## whose class matches the slot.
func candidates(slot: int) -> Array:
	if slot == Slot.SECONDARY:
		return _secondary_candidates.duplicate()
	if not _SLOT_TYPE.has(slot):
		return []
	var want: int = _SLOT_TYPE[slot]
	var out: Array = []
	for id in _learned:
		var view := AbilityDatabase.get_ability_view(int(id))
		if AbilityType.from_string(view.ability_type) == want:
			out.append({"id": int(id), "name": view.name})
	return out


## The primary slot is job-fixed and cannot be edited by the picker.
func is_editable(slot: int) -> bool:
	return slot != Slot.PRIMARY


func get_slot(slot: int) -> int:
	return int(_values.get(slot, 0))


## Commit a picked id into a slot. A commit to the job-fixed primary slot is
## rejected (the ROM never lets the cursor land there).
func set_slot(slot: int, id: int) -> void:
	if not is_editable(slot):
		return
	_values[slot] = id
