extends Node
## Guard for the DERIVED mutation script (ADR-0216) — [StoryMutationScript], which
## replaced the two hand-authored tables this file used to guard.
##
## The authored table had the first two groups BACKWARDS: it seeded four invented
## generics at Gariland (whose ENTD record grants nobody) and joined Delita at the
## Orbonne prologue (where he does not appear). The ROM grants six cadets at the
## Military Academy, root 7, and Delita with them. This test folds the REAL plan
## through [CatalogueReplay] into a FRESH CharacterCatalog and asserts that, plus the
## three decisions the consumer makes on top of the derivation:
##
##   own     -- a recruit is owned EXCEPT one of [constant StoryMutationScript.NEVER_OWNED]
##              (ADR-0078: catalogue-yes / owned-no; Delita is the ENTD-blue unit Gariland
##              spawns itself, so owning him would deploy a second one)
##   repeat  -- a guest re-appearance never re-registers over a levelled Character
##   ramza   -- the protagonist's new-game progression is authored, because his
##              position-0 ENTD slot is a CH2 cinematic one (ADR-0079 forbids stamping
##              its special_name at mint)
##
## Plus the APPEARANCE half, which is now DERIVED too (the three hand-typed Orbonne rows
## are gone): every named unit a battle's ENTD spawns enters the catalogue at that
## battle's opener, bound once and never owned.
##
## And one declared contradiction, guarded as a BURN-DOWN of exactly 1: Rafa is derived
## as a recruit at story position 72 and stands Red at 107. Her real recruit point is a
## guest-vs-join call the ENTD flags cannot make (she carries the flag again at 108, which
## the generator now emits, but her FIRST flagged occurrence is still 72). The guard
## shrinks when RECRUIT_AT gains her, and catches any new unit developing the same shape.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/StoryMutationScriptTest.tscn

const CatalogScript = ExMateriaCatalogue.CharacterCatalog
const Character = ExMateriaCatalogue.Character
const CatalogueReplay = ExMateriaCatalogue.CatalogueReplay
## The six cadets ENTD 392 grants at the Military Academy, in slot order.
const ACADEMY_SLUGS := ["entd392_2", "entd392_3", "entd392_4",
	"entd392_5", "entd392_6", "entd392_7"]

var _passed: int = 0
var _failed: int = 0
var _cats: Array = []


func _ready() -> void:
	_test_gariland_owns_ramza_plus_the_six_academy_cadets()
	_test_ramza_is_minted_new_game_not_from_his_ch2_cinematic_slot()
	_test_cadets_are_the_roms_four_squires_and_two_chemists()
	_test_delita_is_catalogued_but_never_owned()
	_test_joins_land_at_the_group_end_not_its_start()
	_test_the_fold_agrees_with_the_derived_roster_before()
	_test_repeat_appearances_never_re_register()
	_test_orbonne_appearances_are_bound_but_not_owned()
	_test_named_enemies_are_catalogued_at_their_battle()
	_test_only_rafa_is_owned_and_red_at_the_same_battle()

	for c in _cats:
		if is_instance_valid(c):
			c.free()
	_cats.clear()

	print("\n=== StoryMutationScriptTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] StoryMutationScriptTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] StoryMutationScriptTest")
		get_tree().quit(1)
	else:
		print("[PASS] StoryMutationScriptTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)


func _catalog() -> Object:
	var cat = CatalogScript.new()
	_cats.append(cat)
	return cat


# A fresh catalogue with the whole story-to-Gariland plan folded into it.
func _folded(stop_root: int = 9) -> Object:
	var cat := _catalog()
	var plan := GameNavigator.new().plan_actions(1, stop_root, StoryMutationScript.build())
	CatalogueReplay.fold(plan, plan.size(), cat)
	return cat


# --- C1: Gariland grants nobody; the Academy grants six, and Ramza leads the roster ---
func _test_gariland_owns_ramza_plus_the_six_academy_cadets() -> void:
	var cat := _folded()
	var expected: Array = [StoryMutationScript.RAMZA_SLUG]
	expected.append_array(ACADEMY_SLUGS)
	_eq(cat.owned_slugs(), expected, "owned = ramza + the six Academy cadets (fold order)")
	_eq(cat.owned_units().size(), 7, "all 7 owned resolve to Characters")
	_eq(StoryMutationScript.deltas_for_group(9), [],
		"Gariland (root 9) grants nobody — its ENTD record has no join flag")
	_eq(StoryMutationScript.deltas_for_group(7).size(), 7,
		"the Military Academy (root 7) grants Delita + six cadets")


# --- C2: the protagonist is minted new-game, NOT read off his ENTD-256 Ch2 slot ---
func _test_ramza_is_minted_new_game_not_from_his_ch2_cinematic_slot() -> void:
	var cat := _folded()
	var ramza = cat.get_character(StoryMutationScript.RAMZA_SLUG)
	_true(ramza != null, "ramza registered")
	if ramza == null:
		return
	_true(ramza.progression != null, "ramza has a progression (not bare)")
	if ramza.progression == null:
		return
	_eq(ramza.progression.level, 1, "ramza lv1")
	_eq(ramza.progression.current_job_id, StoryMutationScript.JOB_SQUIRE,
		"ramza is a generic-table Squire (0x4a), not the ENTD's special job 0x02")
	# ADR-0079: the active Form is materialized at the deploy seam. Folding his ENTD-256
	# slot would have stamped special_name 2 — his CHAPTER 2 form — durably at mint.
	_eq(ramza.special_name, Character.SPECIAL_NAME_NONE,
		"ramza carries NO durable special_name (his Ch2 ENTD slot did not leak in)")
	_eq(ramza.active_special_name(1), 1, "ramza still selects his Ch1 Form at deploy")


# --- C3: the cadets are the ROM's, not the authored 2-Squire-2-Chemist M/F/M/F guess ---
func _test_cadets_are_the_roms_four_squires_and_two_chemists() -> void:
	var cat := _folded()
	var jobs: Array = []
	var genders: Array = []
	var levels: Array = []
	for slug in ACADEMY_SLUGS:
		var c = cat.get_character(slug)
		_true(c != null, "cadet %s registered" % slug)
		if c == null or c.progression == null:
			continue
		jobs.append(c.progression.current_job_id)
		genders.append(c.is_female)
		levels.append(c.progression.level)
	_eq(jobs, ["4a", "4a", "4b", "4a", "4a", "4b"], "ENTD 392: four Squires + two Chemists")
	_eq(genders, [false, false, false, true, true, true], "ENTD 392: three male, three female")
	_eq(levels, [1, 1, 1, 1, 1, 1], "all cadets lv1")
	# A cadet carries no Form set, so the deploy seam job-routes it (ADR-0079) — which is
	# the mechanism that keeps a generic generic. Asserted HERE, on a Character the fold
	# actually built from ENTD 392, rather than on a hand-minted stand-in: the walk's
	# generics come from the ENTD (ADR-0216 dec.1), so a stand-in could pass while the
	# real path regressed.
	for slug in ACADEMY_SLUGS:
		var cadet = cat.get_character(slug)
		if cadet == null:
			continue
		_eq(cadet.forms, [], "cadet %s carries no Form set" % slug)
		_eq(cadet.active_special_name(1), Character.SPECIAL_NAME_NONE,
			"cadet %s job-routes at deploy" % slug)


# --- C4: the guest/owned split — owning Delita would deploy a second one at Gariland ---
func _test_delita_is_catalogued_but_never_owned() -> void:
	var cat := _folded()
	_true(cat.get_character("delita") != null, "delita in the catalogue (root 7 grants him)")
	_true(not cat.is_owned("delita"), "delita NOT owned (Gariland's ENTD spawns him blue)")
	_eq(cat.classify("delita", 0), "guest", "delita classifies as guest (Blue + not owned)")
	_eq(cat.classify(StoryMutationScript.RAMZA_SLUG, 0), "player", "ramza classifies as player")

	# Both arms, because `not is_owned(slug)` ALONE cannot fail: a typo'd entry in
	# NEVER_OWNED names nobody, is never registered, and passes it. So check each entry is
	# a unit the ROM really grants and that its own delta carries no `own` — and check the
	# complement, which was otherwise unguarded: every canonical recruit NOT on the list
	# comes out owned.
	var guests_seen: Array = []
	var owned_seen: Array = []
	for root in RosterTimeline.order():
		for delta in StoryMutationScript.deltas_for_group(root):
			var slug := String(delta.get("slug", ""))
			if slug.begins_with("entd"):
				continue  # a generic cadet, not a named story unit
			if StoryMutationScript.NEVER_OWNED.has(slug):
				_true(not bool(delta.get("own", false)), "%s's delta is NOT owned (guest)" % slug)
				if not guests_seen.has(slug):
					guests_seen.append(slug)
			else:
				_true(bool(delta.get("own", false)), "%s's delta IS owned (permanent recruit)" % slug)
				if not owned_seen.has(slug):
					owned_seen.append(slug)
	guests_seen.sort()
	var expected_guests: Array = StoryMutationScript.NEVER_OWNED.duplicate()
	expected_guests.sort()
	_eq(guests_seen, expected_guests,
		"every NEVER_OWNED entry names a unit the ROM actually grants (a typo names nobody)")
	owned_seen.sort()
	# FFT canon: these ten are the units that permanently join a controllable party.
	_eq(owned_seen, ["agrias", "beowulf", "cloud", "malak", "meliadoul", "mustadio",
		"orlandu", "rafa", "ramza", "reis"],
		"the complement is exactly the ten permanently-joinable units")


# --- C5: a group grants its recruits at its END (you do not have them on arrival) ---
func _test_joins_land_at_the_group_end_not_its_start() -> void:
	var plan := GameNavigator.new().plan_actions(1, 9, StoryMutationScript.build())
	var academy := -1
	for i in range(plan.size()):
		if String(plan[i].get("kind", "")) == "scenario" and int(plan[i].get("root", -1)) == 7:
			academy = i
			break
	_true(academy >= 0, "the plan contains the Military Academy action")
	if academy < 0:
		return
	var before := _catalog()
	CatalogueReplay.fold(plan, academy, before)
	_true(not before.has_slug("delita"), "arriving AT the Academy, Delita has not joined yet")
	var after := _catalog()
	CatalogueReplay.fold(plan, academy + 1, after)
	_true(after.has_slug("delita"), "leaving the Academy, Delita has joined")


# --- C6: the fold IS `roster_before` — the script and the derived table cannot drift ---
func _test_the_fold_agrees_with_the_derived_roster_before() -> void:
	# Includes roots the story chain never reaches by chaining (373 = Orlandu's group),
	# which the replanned prologue this replaced could not fold at all.
	for root in [9, 116, 175, 373, 488]:
		var slugs: Array = []
		for delta in StoryMutationScript.seed_deltas_before(root):
			slugs.append(String(delta.get("slug", "")))
		_eq(slugs, RosterTimeline.roster_before(root),
			"seed_deltas_before(%d) == RosterTimeline.roster_before(%d)" % [root, root])


# --- C7: a guest RE-appearance is skipped, so it cannot clobber a levelled Character ---
func _test_repeat_appearances_never_re_register() -> void:
	# Root 116 carries Ramza and Agrias as `repeat` joins reading ENTD 272. Neither may
	# produce a delta: re-registering would overwrite whatever the player has been playing.
	var slugs: Array = []
	for delta in StoryMutationScript.deltas_for_group(116):
		slugs.append(String(delta.get("slug", "")))
	_true(not slugs.has("ramza"), "root 116's Ramza REPEAT emits no delta")
	_true(not slugs.has("agrias"), "root 116's Agrias REPEAT emits no delta")
	_true(slugs.has("gafgarion"), "root 116's Gafgarion RECRUIT still emits one")
	_true(RosterTimeline.joins_for(116).size() > slugs.size(),
		"the derived table carries more joins than the script folds (repeats dropped)")


# --- C8: the DERIVED appearances — the Orbonne trio bind, and are not owned ---
func _test_orbonne_appearances_are_bound_but_not_owned() -> void:
	var cat := _folded()
	for slug in ["agrias", "gafgarion", "ovelia"]:
		_true(cat.get_character(slug) != null, "%s appears in the catalogue at Orbonne" % slug)
		_true(not cat.is_owned(slug), "%s is an appearance, not a recruit — not owned" % slug)
	var agrias = cat.get_character("agrias")
	if agrias != null and agrias.progression != null:
		_eq(agrias.progression.current_job_id, "34",
			"Agrias binds with her real ENTD job (a HIT must not demote her to Squire)")
	# Derived, not typed: the three come off ENTD 387's always-present named slots, and
	# they key on the OPENER — the one action whose deltas land before the fight.
	var slugs: Array = []
	for delta in StoryMutationScript.appearance_deltas_for(3):
		slugs.append(String(delta.get("slug", "")))
	_eq(slugs, ["agrias", "gafgarion", "ovelia"], "Orbonne's appearances are derived")
	_eq(RosterTimeline.opener_scenario_id(3), 4, "and fold under `opener:4`")
	# ENTD 387 slot 0 is a PRESENT, named Ramza — his Ch2 cinematic form. Re-binding him
	# would overwrite the authored new-game protagonist (ADR-0079).
	_true(not slugs.has("ramza"), "the already-seeded protagonist is not re-bound")


# --- C9: a named ENEMY is catalogued too — the catalogue is the ONE population ---
func _test_named_enemies_are_catalogued_at_their_battle() -> void:
	# Wiegraf's first battle (root 33) spawns him Red. ADR-0078: class is DERIVED from
	# owned-membership x team_color, so being catalogued does not make him yours.
	var slugs: Array = []
	for delta in StoryMutationScript.appearance_deltas_for(33):
		slugs.append(String(delta.get("slug", "")))
	_true(slugs.has("wiegraf"), "Wiegraf is catalogued at his own battle")
	var cat := _catalog()
	CatalogueReplay.apply_action({"mutations": StoryMutationScript.appearance_deltas_for(33)}, cat)
	_true(cat.get_character("wiegraf") != null, "a named enemy registers")
	_true(not cat.is_owned("wiegraf"), "and is never owned")
	_eq(cat.classify("wiegraf", 1), "enemy", "Red + not owned classifies as enemy")


# --- C10: the declared contradiction, as a burn-down of exactly ONE ---
func _test_only_rafa_is_owned_and_red_at_the_same_battle() -> void:
	# The generator registers every RECRUITED-and-Red row without filtering by `own`,
	# because it asserts no deployability (ADR-0216 dec.8). This consumer is the only
	# thing that knows the never-owned set, so the narrowing is here — and Algus and
	# Gafgarion drop out as canon (they turn on you and were never yours).
	var owned_red: Array = []
	for row in RosterTimeline.recruited_red_conflicts():
		var slug := String(row.get("slug", ""))
		if StoryMutationScript.NEVER_OWNED.has(slug):
			continue
		if not owned_red.has(slug):
			owned_red.append(slug)
	_eq(owned_red, ["rafa"],
		"exactly ONE unit is owned and Red at the same battle — burn it down, do not grow it")
	# Anti-vacuity: the burn-down of 1 must not read 1 because the register went empty.
	# Stated as "the narrowing actually narrowed" rather than a row count — a count would
	# ratchet the WRONG way, failing when RECRUIT_AT['rafa'] lands and a row is legitimately
	# paid off. The burn-down itself is the arm above; this one only proves it is real.
	_true(RosterTimeline.recruited_red_conflicts().size() > owned_red.size(),
		"the raw register is wider than the narrowing — NEVER_OWNED really filtered")
