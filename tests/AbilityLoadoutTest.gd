extends Node
## AbilityLoadout slot-model test (formation ability "Set" flow port).
## Pure GDScript — no AbilityDatabase, GPU, or scene. The 5-slot per-unit
## ability loadout mirrors the ROM `unit+0x5e` model (ABILITY_PICKER.md §2):
##   [0] primary skillset  (job-fixed, NOT editable — the ROM "slot 0 unselectable")
##   [1] secondary skillset
##   [2] Reaction  [3] Support  [4] Movement
## Slots 0/1 hold SKILLSET ids; 2/3/4 hold ABILITY ids; 0 = none/empty.
## Fixture values are the live oracle (unit "Boyce", a Squire): primary skillset
## 5 (Basic Skill), support 480 (Equip Change), secondary set to 6 (Item).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityLoadout = ExMateriaAlmanac.AbilityLoadout



func _ready() -> void:
	var failed := false

	var lo := AbilityLoadout.new(5)  # primary skillset = 5 (Basic Skill), job-fixed

	# Primary slot reads the job-fixed skillset and is NOT editable.
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.PRIMARY) == 5, "primary reads 5", failed)
	failed = _expect(not lo.is_editable(AbilityLoadout.Slot.PRIMARY), "primary is not editable", failed)

	# The four editable slots are editable and default to 0 (none).
	for s in [AbilityLoadout.Slot.SECONDARY, AbilityLoadout.Slot.REACTION,
			AbilityLoadout.Slot.SUPPORT, AbilityLoadout.Slot.MOVEMENT]:
		failed = _expect(lo.is_editable(s), "slot %d editable" % s, failed)
		failed = _expect(lo.get_slot(s) == 0, "slot %d defaults to none(0)" % s, failed)

	# Commit into editable slots reads back.
	lo.set_slot(AbilityLoadout.Slot.SECONDARY, 6)     # skillset 6 = Item
	lo.set_slot(AbilityLoadout.Slot.SUPPORT, 480)     # ability 480 = Equip Change
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.SECONDARY) == 6, "secondary commits to 6", failed)
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.SUPPORT) == 480, "support commits to 480", failed)

	# Committing the primary slot is rejected (job-fixed) — it stays 5.
	lo.set_slot(AbilityLoadout.Slot.PRIMARY, 9)
	failed = _expect(lo.get_slot(AbilityLoadout.Slot.PRIMARY) == 5, "primary commit rejected (stays 5)", failed)

	# --- Slice 2: R/S/M candidate lists = learned abilities filtered by class ---
	# Known-good learned set (types from abilities.json): 436 Counter Tackle (Reaction),
	# 460 Equip Axe (Support), 480 Equip Change (Support), 486 Move+1 (Movement),
	# 146 Accumulate (Normal — an action, belongs to NO R/S/M slot).
	lo.set_learned_abilities([436, 460, 480, 486, 146])

	failed = _expect(_ids(lo.candidates(AbilityLoadout.Slot.REACTION)) == [436],
		"reaction candidates = [436]", failed)
	failed = _expect(_ids(lo.candidates(AbilityLoadout.Slot.SUPPORT)) == [460, 480],
		"support candidates = [460,480]", failed)
	failed = _expect(_ids(lo.candidates(AbilityLoadout.Slot.MOVEMENT)) == [486],
		"movement candidates = [486]", failed)

	# The action ability (146 Normal) leaks into no R/S/M slot.
	for s in [AbilityLoadout.Slot.REACTION, AbilityLoadout.Slot.SUPPORT, AbilityLoadout.Slot.MOVEMENT]:
		failed = _expect(not _ids(lo.candidates(s)).has(146), "146 not in slot %d" % s, failed)

	# Entry carries the ability name from the runtime source (AbilityDatabase.gd
	# line 16783: 436 -> "CounterTackle"). NB the generated DB spells it without a
	# space while abilities.json says "Counter Tackle" — a generator discrepancy,
	# out of scope for this slice; the picker renders the DB name.
	var react := lo.candidates(AbilityLoadout.Slot.REACTION)
	failed = _expect(react.size() == 1 and str(react[0].get("name")) == "CounterTackle",
		"reaction entry name = CounterTackle (DB source)", failed)

	# --- Slice 3: secondary candidates are JOB rows {id: job_id, name: skillset} ---
	# The picker offers sub-JOBS (job→skillset is 1:1); the entry id is a job id and the
	# name is that job's action skillset. (from_progression computes the real list from
	# the unit's unlocked generic jobs; here we round-trip the standalone setter.)
	lo.set_secondary_candidates([
		{"id": 0x4b, "name": "Item"},          # Chemist
		{"id": 0x59, "name": "Throw"},         # Ninja
	])
	var sec := lo.candidates(AbilityLoadout.Slot.SECONDARY)
	failed = _expect(_ids(sec) == [0x4b, 0x59], "secondary candidates round-trip as job rows", failed)
	failed = _expect(sec.size() >= 1 and str(sec[0].get("name")) == "Item",
		"secondary entry name = Item (Chemist's skillset)", failed)

	if failed:
		print("[FAIL] AbilityLoadout slot model")
	else:
		print("[PASS] AbilityLoadout: 5-slot get/set + primary read-only OK")
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
