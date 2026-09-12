extends Node
## AbilityLoadout <-> UnitProgression adapter (slice 5a). The formation ability
## "Set" flow reads a live unit's loadout from its persistent UnitProgression
## (current_job_id -> primary skillset, learned_abilities, equipped_reaction/
## support/movement) and commits the picked id back. Pure GDScript — no GPU/scene.
##
## The R/S/M slots map 1:1 (equipped_* -1 = none <-> model 0 = none); the
## secondary-skillset slot has a skillset-vs-sub_job impedance mismatch and is
## adapted in a later slice.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/AbilityLoadoutProgressionTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityLoadout = ExMateriaAlmanac.AbilityLoadout
const UnitProgression = ExMateriaAlmanac.UnitProgression



func _ready() -> void:
	var failed := false

	# A live-ish Squire progression: learned Counter Tackle (Reaction 436), Equip Axe
	# (Support 460), Move+1 (Movement 486); currently equipping Equip Change (480, Support).
	var prog := UnitProgression.new()
	prog.current_job_id = "4a"                      # Squire -> skill_set_id 5 (Basic Skill)
	prog.learned_abilities = {436: true, 460: true, 486: true, 480: true}
	prog.equipped_support = 480                     # Equip Change
	prog.equipped_reaction = -1                     # none
	prog.equipped_movement = -1                     # none

	var lo := AbilityLoadout.from_progression(prog)

	# Primary = the job's skillset; R/S/M current values mirror equipped_* (-1 -> 0).
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.PRIMARY) == 5, "primary = Squire skillset 5", failed)
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.SUPPORT) == 480, "support slot = 480", failed)
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.REACTION) == 0, "empty reaction -> 0", failed)
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.MOVEMENT) == 0, "empty movement -> 0", failed)

	# Candidates come from the unit's learned set, filtered by class.
	failed = _expect(_ids(lo.candidates(AbilityLoadout.Slot.REACTION)) == [436], "reaction cands = [436]", failed)
	failed = _expect(_ids(lo.candidates(AbilityLoadout.Slot.MOVEMENT)) == [486], "movement cands = [486]", failed)
	var supp := _ids(lo.candidates(AbilityLoadout.Slot.SUPPORT))
	failed = _expect(supp.has(460) and supp.has(480), "support cands include 460 + 480", failed)

	# Commit writes back to the persistent progression (the equip picker's contract).
	AbilityLoadout.commit_to_progression(prog, AbilityLoadout.Slot.REACTION, 436)
	failed = _expect(prog.equipped_reaction == 436, "commit reaction -> prog.equipped_reaction 436", failed)
	AbilityLoadout.commit_to_progression(prog, AbilityLoadout.Slot.MOVEMENT, 486)
	failed = _expect(prog.equipped_movement == 486, "commit movement -> prog.equipped_movement 486", failed)

	# --- Secondary sub-job: candidates = unlocked generic jobs (≠ current), by skillset ---
	# A fresh Squire (only job_levels {4a:1}) can equip Chemist (Item) as secondary — Chemist
	# has no prerequisite, so it is always unlocked; the current job (Squire) is NOT offered.
	var fresh := UnitProgression.new()
	fresh.current_job_id = "4a"                 # Squire
	fresh.job_levels = {"4a": 1}
	fresh.sub_job_id = ""
	var lo2 := AbilityLoadout.from_progression(fresh)
	var sec_ids := _ids(lo2.candidates(AbilityLoadout.Slot.SECONDARY))
	failed = _expect(not sec_ids.has(0x4a), "secondary must NOT offer the current job (Squire)", failed)
	failed = _expect(sec_ids.has(0x4b), "secondary must offer Chemist (0x4b, no prereq)", failed)
	# The Chemist row shows its skillset name "Item".
	for e in lo2.candidates(AbilityLoadout.Slot.SECONDARY):
		if int(e.get("id")) == 0x4b:
			failed = _expect(str(e.get("name")) == "Item", "Chemist secondary row name = Item", failed)
	# Locked jobs (Knight needs Squire Lv2) are not offered to a fresh Squire.
	failed = _expect(not sec_ids.has(0x4c), "secondary must NOT offer a locked job (Knight)", failed)
	# Commit writes the sub-job back as the "%02x" job id UnitProgression stores.
	AbilityLoadout.commit_to_progression(fresh, AbilityLoadout.Slot.SECONDARY, 0x4b)
	failed = _expect(fresh.sub_job_id == "4b", "commit secondary -> sub_job_id '4b' (got '%s')" % fresh.sub_job_id, failed)

	# --- clear_in_progression: the ability "Remove" mechanic (the mirror of unequip_item) ---
	# Clears a slot to UnitProgression's OWN "none" sentinel (-1 for R/S/M, "" for secondary),
	# returns true iff something was actually cleared (an already-empty slot is a silent no-op,
	# like unequip_item returning -1). The job-fixed PRIMARY is never clearable.
	var rm := UnitProgression.new()
	rm.current_job_id = "4a"
	rm.equipped_support = 480                        # occupied
	rm.equipped_reaction = -1                        # already none
	rm.sub_job_id = "4b"                             # occupied secondary
	# Occupied R/S/M slot -> cleared to -1, reports true.
	failed = _expect(AbilityLoadout.clear_in_progression(rm, AbilityLoadout.Slot.SUPPORT) == true,
		"clear an occupied support slot reports true", failed)
	failed = _expect(rm.equipped_support == -1,
		"cleared support slot -> equipped_support -1 (got %d)" % rm.equipped_support, failed)
	# The model then reads it as empty (blank), matching the panel's value<=0 blank rule.
	failed = _expect(AbilityLoadout.from_progression(rm).get_slot(AbilityLoadout.Slot.SUPPORT) == 0,
		"cleared support slot reads as 0 (blank) via from_progression", failed)
	# Already-empty R/S/M slot -> silent no-op, reports false, stays -1.
	failed = _expect(AbilityLoadout.clear_in_progression(rm, AbilityLoadout.Slot.REACTION) == false,
		"clear an already-empty reaction slot reports false", failed)
	failed = _expect(rm.equipped_reaction == -1, "no-op clear leaves reaction -1", failed)
	# Occupied secondary -> cleared to "", reports true; a second clear is a no-op.
	failed = _expect(AbilityLoadout.clear_in_progression(rm, AbilityLoadout.Slot.SECONDARY) == true,
		"clear an occupied secondary reports true", failed)
	failed = _expect(rm.sub_job_id == "", "cleared secondary -> sub_job_id '' (got '%s')" % rm.sub_job_id, failed)
	failed = _expect(AbilityLoadout.clear_in_progression(rm, AbilityLoadout.Slot.SECONDARY) == false,
		"clear an already-empty secondary reports false", failed)
	# PRIMARY is job-fixed: never clearable.
	failed = _expect(AbilityLoadout.clear_in_progression(rm, AbilityLoadout.Slot.PRIMARY) == false,
		"clear PRIMARY reports false (job-fixed)", failed)

	if failed:
		print("[FAIL] AbilityLoadout<->UnitProgression adapter")
	else:
		print("[PASS] AbilityLoadout.from_progression + commit_to_progression OK")
	get_tree().quit()


func _ids(entries: Array) -> Array:
	var out := []
	for e in entries:
		out.append(int(e.get("id")))
	return out


func _expect(cond: bool, label: String, failed_so_far: bool) -> bool:
	if not cond:
		print("[FAIL] %s" % label)
		return true
	return failed_so_far
