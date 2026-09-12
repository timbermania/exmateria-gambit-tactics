extends Node
## Regression test for the COMBAT / roster-spawn BODY palette-row axis.
##
## Companion to ResolveBodyPaletteRowTest (which pins the two-axis SCENARIO rule).
## Combat has NO ENTD deployment record, so there is no team `palette` byte to
## clamp — the row is purely JOB-sourced. That job axis now lives in ONE owner,
## `SpritePaletteResolver.job_body_palette_row`, asked DIRECTLY by every consumer:
##   - Unit.change_job                     (a live unit changing job mid-game)
##   - UnitSpawn.build                     (a Character entering a battle)
##   - FormationScene.resolve_body_render  (a roster cell's render inputs)
##   - the two-axis `resolve_body_palette_row` monster branch (scenario/EVTCHR)
##
## #1071 / ADR-0272 put the middle two on that list. Both used to read the row off
## `CharacterTemplateResolver.resolve()`, which fetched it from this same owner and
## passed it through — an indirection no caller read, and the catalogue addon's
## only cross-addon reach. The key is gone; the value and its owner are unchanged,
## which is exactly what the arms below have to be able to tell apart.
##
## This test pins three things:
##   1. The primitive returns the JOB's authored row, unclamped — monsters get
##      their variant (Yellow Chocobo 0x5E=0 / Black 0x5F=1 / Red 0x60=2),
##      `special` non-humanoids get theirs (Holy Dragon 0x48=3), humanoids get 0.
##      NOTE the special case: `is_monster` is `kind=="monster"` only, so routing
##      the combat path through the two-axis resolver's monster branch would have
##      dropped Holy Dragon's row 3 to 0. The job-axis primitive is the reason it
##      doesn't. (Whether jobs.json's Holy Dragon row 3 vs SPR 0x48's authored
##      rows {0} is itself correct is a separate RE question — see the handoff.)
##   2. The spawn seam actually PROPAGATES the row onto the live Unit.
##      Latent today (no monster is in the owned overlay by default) — this is the
##      guard so it works the day one is, per the session's remit.
##   3. The FORMATION seam resolves the same row for the same jobs. It was the
##      un-pinned consumer: `resolve_body_render`'s `palette_row` had no test at
##      all, on either side of #1071, and it drives `set_body_palette_row` on every
##      roster cell.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/CombatBodyPaletteRowTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver
const Character = ExMateriaCatalogue.Character

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_job_axis_primitive()
	await _test_spawn_seam_propagates_row()
	_test_formation_seam_resolves_the_row()

	print("\n=== CombatBodyPaletteRowTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CombatBodyPaletteRowTest")
		get_tree().quit(1)
	else:
		print("[PASS] CombatBodyPaletteRowTest")
		get_tree().quit(0)


func _test_job_axis_primitive() -> void:
	# job_id_hex -> expected row, description
	var cases := [
		["5e", 0, "Yellow Chocobo job 0x5E -> row 0"],
		["5f", 1, "Black Chocobo job 0x5F -> row 1"],
		["60", 2, "Red Chocobo job 0x60 -> row 2"],
		["48", 3, "Holy Dragon (special) job 0x48 -> row 3 (NOT clamped away)"],
		["4c", 0, "Knight (humanoid) job 0x4C -> row 0"],
		["4a", 0, "Squire (humanoid) job 0x4A -> row 0"],
	]
	for c in cases:
		var got: int = SpritePaletteResolver.job_body_palette_row(c[0])
		_expect(got, c[1], c[2])


func _test_spawn_seam_propagates_row() -> void:
	# Through the REAL chokepoint, whatever host is calling it. This used to build a
	# detached PartyRoster and spawn by INDEX; ADR-0180 deleted the store and re-rooted
	# the seam on the Character it always actually needed, so the test asks the seam
	# directly and there is no fixture roster left to hand-build.
	var red_choco := Character.create_default("TestRedChoco", "60", false)  # row 2
	var knight := Character.create_default("TestKnight", "4c", false)        # row 0

	# Parented into the tree so each spawned Unit's _ready fires and
	# _load_initial_sprite_texture seeds the shader from the assigned row.
	var choco_unit := UnitSpawn.build(red_choco)
	var knight_unit := UnitSpawn.build(knight)
	add_child(choco_unit)
	add_child(knight_unit)
	await get_tree().process_frame
	UnitSpawn.bind_for_combat(choco_unit, red_choco, UnitStats.Team.ENEMY)
	UnitSpawn.bind_for_combat(knight_unit, knight, UnitStats.Team.PLAYER)

	_expect(choco_unit.body_palette_row, 2,
		"spawn seam: Red Chocobo unit carries job row 2 (was latent 0)")
	_expect(knight_unit.body_palette_row, 0,
		"spawn seam: humanoid Knight unit resolves to row 0")

	choco_unit.queue_free()
	knight_unit.queue_free()


## THE SECOND CONSUMER (#1071, ADR-0272). `FormationScene.resolve_body_render` is a
## static pure function of a `Character`, so it is asked directly — no scene, no
## roster. Its `palette_row` is what `_build_cell_body` hands to
## `set_body_palette_row`, and it was never pinned before this.
##
## The folder-routed case is asserted too, and it is the arm that would catch the
## obvious wrong fix: a unique has no job-routed sprite, its `palette_row` is a
## hardcoded 0, and reading the job's row there would repaint every unique.
func _test_formation_seam_resolves_the_row() -> void:
	var red_choco := Character.create_default("TestRedChoco", "60", false)  # row 2
	var knight := Character.create_default("TestKnight", "4c", false)        # row 0
	_expect(int(FormationScene.resolve_body_render(red_choco).get("palette_row", -1)), 2,
		"formation seam: Red Chocobo cell renders at job row 2")
	_expect(int(FormationScene.resolve_body_render(knight).get("palette_row", -1)), 0,
		"formation seam: humanoid Knight cell renders at row 0")

	var ramza := Character.from_dict({"unit_name": "Ramza", "current_job_id": "4a"})
	ramza.special_name = 3  # a residue unique — folder-routed, NOT job-routed
	var uniq := FormationScene.resolve_body_render(ramza)
	_expect(int(uniq.get("palette_row", -1)), 0,
		"formation seam: a folder-routed unique still renders at row 0")
	_expect(1 if not String(uniq.get("template_folder", "")).is_empty() else 0, 1,
		"and the unique fixture really did take the folder branch")


func _expect(got: int, want: int, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
