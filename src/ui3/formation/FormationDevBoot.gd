extends Node3D

## Standalone headful harness for the MUTATING Formation screen — the root of
## `assets/scenes/FormationDev.tscn`.
##
## Seeds a promoted roster ([PromotedRosterSeeder]), unlocks every job so the Change-Job ring
## is committable by hand, and mounts the coordinator over it. A thin iteration vehicle (NOT a
## test): it wires a fixture to a screen and does nothing else.
##
## [b]This is the sibling of [AllTemplatesFormationBoot], and the pair is the point.[/b]
## ADR-0081 dec. 5 splits the two seeders by what the screen DOES with the units:
## [AllTemplatesSeeder] answers "what sheets exist" and feeds the browsing view;
## [PromotedRosterSeeder] mints real mutable units and feeds this one, because change-job and
## equip cannot write into catalogue rows whose sheet can't follow their job. Until ADR-0181
## only the browsing half had a boot script — the mutating half's seeding lived inside
## `FormationDetailTransition._resolve_roster()`, i.e. inside the screen a navigator mounts.
##
## [b]Why that had to move, and it was not tidiness.[/b] The seeding opened with
## `CharacterCatalog.reset_to_new_game()`, which clears `_owned_order` and unregisters every
## slug outside the new-game baseline. The screen's own docstring said *"a real host would pass
## the live `CharacterCatalog.owned_units()`"* — so the first real host to mount it (the world
## map's START-menu row, ADR-0181) would have wiped the player's owned overlay, and anyone who
## joined during the walk, on the frame the screen opened. Moving the fixture into the SCENE
## makes that unreachable from a hosted mount rather than merely discouraged.
##
## [b]It gets its OWN scene, and that is the whole point of the split.[/b] `AllTemplatesFormation.tscn`
## does not take over `Formation.tscn` — it is a separate root beside it — and the first cut of
## ADR-0181 mirrored the wrong half of that precedent: it re-rooted `FormationDetailTransition.tscn`
## on this boot, which is the scene `NavigatorMain` mounts. Measured on the live route, the harness
## then ran on the PLAYER's path — `[FormationDevBoot] seeded 191 owned unit(s)` — so the destructive
## reset simply moved from one file to another, and `NavigatorWorldMapFormationTest` went 5/9 because
## a boot node carries no `dismissed` and the navigator's await released instantly.
##
## Run: <GODOT> --path . res://assets/scenes/FormationDev.tscn
##      then Enter/○ opens a unit's Status screen, Tab/△ the main menu, Backspace/✕ backs out.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobLevelsDatabase = ExMateriaAlmanac.JobLevelsDatabase


const FormationDetailTransitionScript = preload("res://src/ui3/formation/FormationDetailTransition.gd")


func _ready() -> void:
	# Seed BEFORE the coordinator enters the tree: its `_ready` reads the owned overlay
	# directly (ADR-0181 — one population, no injection seam), so the fixture has to be
	# standing by the time that runs.
	CharacterCatalog.reset_to_new_game()
	var seeded := PromotedRosterSeeder.seed()
	unlock_every_job(CharacterCatalog.owned_units())

	var host: Node3D = FormationDetailTransitionScript.new()
	host.name = "FormationDetailTransition"
	add_child(host)
	host.begin_screen_in()   # ADR-0172 — the harness sees the same entry the player does
	# HOST-side panel mount (#1267). `_ready` above built the coordinator's formation, so
	# `formation()` is live by now. This file is `assembler` (ADR-0135 dec. 10).
	FormationDebugPanels.register_formation_panels(host.formation())

	print("[FormationDevBoot] seeded %d owned unit(s); every generic job unlocked" % seeded)


## HARNESS ONLY: raise every seeded unit's job levels until every generic job's prerequisites are
## met, so the Change-Job ring is fully committable while the screen is being built and driven. It sits
## with the scene's OWN seeding (the reset_to_new_game/PromotedRosterSeeder pair above), not in shared
## progression, and it does NOT weaken the rule: `confirm_changejob` still asks `is_job_unlocked` —
## here the answer just happens to always be yes. A real game seeds a real roster and the gate bites.
##
## [b]Static, and public, because a test that COMMITS a job change is a harness too.[/b] ADR-0181
## moved this out of `FormationDetailTransition` and `FormationChangeJobConfirmTest` went red at
## *"○ did not start the commit cutscene"* — its own comment says the unlock gate is
## `confirm_changejob`'s, and it re-locks a job by hand to prove the gate bites, so it needs the
## other side of that gate open to start with. Reaching into this assembler for the fixture is
## right: ADR-0181 made this file the mutating screen's fixture OWNER, so one copy lives here
## rather than a second appearing in `tests/`.
static func unlock_every_job(units: Array) -> void:
	var jobs: Array = JobLevelsDatabase.get_all_generic_job_ids()
	# The single level that clears every prerequisite in the table — read from the data rather than
	# hardcoded, so a job_levels.json change cannot silently re-lock half the ring.
	var needed := 1
	for job_id in jobs:
		for required_level in JobLevelsDatabase.get_prerequisites(job_id).values():
			needed = maxi(needed, int(required_level))
	for character in units:
		if character == null or character.progression == null:
			continue
		for job_id in jobs:
			if int(character.progression.job_levels.get(job_id, 0)) < needed:
				character.progression.job_levels[job_id] = needed
