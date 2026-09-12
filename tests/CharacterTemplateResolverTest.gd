extends Node3D
# test-kind: logic
# seeded-break: CharacterTemplateResolver.resolve's generic-human branch resolves the body sprite as JobDatabase.get_sprite_id(job, false) instead of JobDatabase.get_sprite_id(job, character.is_female) - drops the gender axis from the sprite lookup; 'female Squire resolves to sprite 0x61' + 'sprite parity for job 4a female=true' RED (expected 97, got 96 - the male sprite); male/monster/unique/appearance-type keys, the palette-row-owner half, the folder routes and the template.json cache all stay green; GREEN unbroken on the reverted tree

## TDD guard for the character asset template resolver (ADR-0072, issue #198).
##
## The resolver is the seam BETWEEN a `Character` and its visual template — part
## of neither (glossary: `resolver`). It maps
##   `Character (identity + job) → template key → assets`.
## This is the thin vertical slice: **generics only, zero new artifacts**. The
## polymorphic template key (ADR-0072 dec.1) has two in-scope shapes, chosen by
## whether the sprite is gender-variant (data-derived, no hardcoded job lists):
##   - generic-human `(job, gender)` — the sprite differs by gender (Squire 60/61)
##   - generic-monster `(job)`       — gender-invariant sprite (Chocobo 86/86)
## and resolution routes through the *existing* job tables (`JobDatabase`) — so a
## roster unit resolves to exactly today's sprite. Uniques `(character_id, version)`
## are NOT in scope here (#202).
##
## THE BODY PALETTE ROW IS NOT PART OF THE ANSWER (#1071, ADR-0272) and this file
## asserts the absence rather than assuming it. The row is a render fact owned by
## `SpritePaletteResolver.job_body_palette_row`; the resolver carried it as a
## pass-through nothing read, and it was `exmateria_catalogue`'s only cross-addon
## reach. `_test_resolve_does_not_answer_the_palette_row` takes both halves — the
## key is gone AND the same jobs still get the same rows from the owner — so
## "severed" cannot be confused with "the value changed".
##
## Run: <GODOT> --path . --quit-after 4 res://tests/CharacterTemplateResolverTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase

const CharacterClass = ExMateriaCatalogue.Character
const CharacterTemplateResolver = ExMateriaCatalogue.CharacterTemplateResolver
const ResidueManifest = ExMateriaCatalogue.ResidueManifest
var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_generic_human_key_is_job_and_gender()
	_test_generic_monster_key_is_job_only()
	_test_resolve_generic_human_matches_job_table()
	_test_resolve_monster_is_gender_invariant()
	_test_resolve_matches_legacy_inline_formula()
	_test_resolve_does_not_answer_the_palette_row()
	_test_unique_key_is_special_name_alone()
	_test_unique_resolves_through_the_residue_manifest()
	_test_unique_dispatch_ignores_job_and_gender()
	_test_appearance_type_key_is_token_alone()
	_test_appearance_type_resolves_to_token_folder()
	_test_read_template_json_parses_and_caches()

	print("\n=== CharacterTemplateResolverTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] CharacterTemplateResolverTest")
		get_tree().quit(1)
	else:
		print("[PASS] CharacterTemplateResolverTest")
		get_tree().quit(0)


## A gendered generic (Squire, sprites 0x60 M / 0x61 F) keys on `(job, gender)`:
## category GENERIC_HUMAN, the job hex, and the gender axis reflecting is_female.
func _test_generic_human_key_is_job_and_gender() -> void:
	var male: CharacterClass = CharacterClass.create_default("Marcus", "4a", false)  # Male Squire
	var k_m := CharacterTemplateResolver.template_key(male)
	_assert_eq(k_m.get("category"), CharacterTemplateResolver.Category.GENERIC_HUMAN,
		"gendered generic is GENERIC_HUMAN")
	_assert_eq(k_m.get("job"), "4a", "human key carries the job hex")
	_assert_eq(k_m.get("gender"), "male", "male authored gender in the key")

	var female: CharacterClass = CharacterClass.create_default("Elena", "4a", true)
	_assert_eq(CharacterTemplateResolver.template_key(female).get("gender"), "female",
		"female authored gender in the key")


## A monster (Red Chocobo, gender-invariant sprite 0x86 for both) keys on `(job)`
## alone: category GENERIC_MONSTER and NO gender axis in the key.
func _test_generic_monster_key_is_job_only() -> void:
	var mon: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Cuar", "is_female": true, "current_job_id": "60"})  # Red Chocobo
	var k := CharacterTemplateResolver.template_key(mon)
	_assert_eq(k.get("category"), CharacterTemplateResolver.Category.GENERIC_MONSTER,
		"gender-invariant sprite is GENERIC_MONSTER")
	_assert_eq(k.get("job"), "60", "monster key carries the job hex")
	_assert_true(not k.has("gender"), "monster key has NO gender axis (job only)")


## resolve() returns the owned 1:1 body sprite id the generic resolves to through
## the existing job tables — the female variant flips it.
func _test_resolve_generic_human_matches_job_table() -> void:
	var male: CharacterClass = CharacterClass.create_default("Marcus", "4a", false)
	var r_m := CharacterTemplateResolver.resolve(male)
	_assert_eq(r_m.get("body_sprite_id"), 0x60, "male Squire resolves to sprite 0x60")

	var female: CharacterClass = CharacterClass.create_default("Elena", "4a", true)
	_assert_eq(CharacterTemplateResolver.resolve(female).get("body_sprite_id"), 0x61,
		"female Squire resolves to sprite 0x61")


## A female-flagged monster still resolves to the (gender-invariant) monster
## sprite and its variant palette row — the gender bit must not perturb it.
func _test_resolve_monster_is_gender_invariant() -> void:
	var mon: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Cuar", "is_female": true, "current_job_id": "60"})  # Red Chocobo, row 2
	var r := CharacterTemplateResolver.resolve(mon)
	_assert_eq(r.get("body_sprite_id"), 0x86, "Red Chocobo resolves to sprite 0x86 despite is_female")


## The seam must be byte-identical to the inline formula it replaces at
## [UnitSpawn.build] (`JobDatabase.get_sprite_id`) across a representative spread —
## this is what makes the slice a pure refactor (no visual regression). The palette
## row left this dict in #1071 and its parity is asserted where it now lives, in
## [CombatBodyPaletteRowTest], over this same job spread.
func _test_resolve_matches_legacy_inline_formula() -> void:
	var cases := [
		{"job": "4a", "female": false},  # Male Squire
		{"job": "4a", "female": true},   # Female Squire
		{"job": "50", "female": false},  # Male Wizard
		{"job": "60", "female": true},   # Red Chocobo (monster)
		{"job": "48", "female": false},  # Holy Dragon (special, ungendered)
	]
	for c in cases:
		var ch: CharacterClass = CharacterClass.from_dict(
			{"unit_name": "T", "is_female": c["female"], "current_job_id": c["job"]})
		var r := CharacterTemplateResolver.resolve(ch)
		var want_sprite: int = JobDatabase.get_sprite_id(c["job"], c["female"])
		_assert_eq(r.get("body_sprite_id"), want_sprite,
			"sprite parity for job %s female=%s" % [c["job"], c["female"]])
		_assert_true(not r.has("body_palette_row"),
			"and NO palette row for job %s female=%s" % [c["job"], c["female"]])


## #1071 / ADR-0272. BOTH HALVES, because either alone is misreadable.
##
## HALF ONE — the key is gone from every branch of `resolve()`. Asserted on the
## job-routed branch (where it used to live) and on a unique (where it never did),
## so a dict that answered it conditionally still fails.
##
## HALF TWO — the same jobs still resolve to the same rows, asked of the owner the
## two consumers now ask. This is the DoD's "Red Chocobo 2, humanoid 0" pinned
## here, in the file that used to hold it: without it, deleting the key reads as
## severing the edge when it could equally be losing the value.
func _test_resolve_does_not_answer_the_palette_row() -> void:
	var mon: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Cuar", "is_female": true, "current_job_id": "60"})
	var man: CharacterClass = CharacterClass.create_default("Marcus", "4a", false)
	_assert_true(not CharacterTemplateResolver.resolve(mon).has("body_palette_row"),
		"job-routed resolve() does not answer body_palette_row")
	_assert_true(not CharacterTemplateResolver.resolve(man).has("body_palette_row"),
		"neither does the generic human branch")
	var ramza: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Ramza", "current_job_id": "4a"})
	ramza.special_name = 3  # Ramza Ch4 form — the residue entry the unique arms use
	_assert_true(ResidueManifest.has(3), "the unique fixture is still in the residue")
	_assert_true(not CharacterTemplateResolver.resolve(ramza).has("body_palette_row"),
		"nor the unique branch, which never carried it")

	_assert_eq(SpritePaletteResolver.job_body_palette_row("60"), 2,
		"and the OWNER still answers Red Chocobo (job 0x60) with row 2")
	_assert_eq(SpritePaletteResolver.job_body_palette_row("4a"), 0,
		"and a humanoid (Squire, job 0x4A) with row 0")


## A unique (a materialized `special_name` in the residue) keys on `special_name`
## ALONE (#199): category UNIQUE, the special_name in the key, and NO job/gender
## axis — the slug never enters the key.
func _test_unique_key_is_special_name_alone() -> void:
	var agrias: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Agrias", "current_job_id": "42"})  # Holy Knight job — pure data
	agrias.special_name = 52  # Agrias (materialized at the seeding seam)
	var k := CharacterTemplateResolver.template_key(agrias)
	_assert_eq(k.get("category"), CharacterTemplateResolver.Category.UNIQUE,
		"a residue special_name is UNIQUE")
	_assert_eq(k.get("special_name"), 52, "unique key carries the special_name")
	_assert_true(not k.has("job"), "unique key has NO job axis")
	_assert_true(not k.has("gender"), "unique key has NO gender axis")


## resolve() routes a unique through the residue manifest to its template folder
## (`Character.special_name → manifest → folder`) — the #203 loaders read assets
## from that folder; the generic `body_sprite_id` shape is absent for a unique.
func _test_unique_resolves_through_the_residue_manifest() -> void:
	var ramza: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Ramza", "current_job_id": "4a"})
	ramza.special_name = 3  # Ramza Ch4 form
	var r := CharacterTemplateResolver.resolve(ramza)
	_assert_eq(r.get("template_folder"), ResidueManifest.folder_of(3),
		"unique resolves to its manifest folder")
	_assert_eq(r.get("special_name"), 3, "unique resolve carries the special_name")
	_assert_true(not r.has("body_sprite_id"),
		"a unique does NOT carry the flat-store body_sprite_id (folder-routed)")


## The unique dispatch is a pure function of the materialized `special_name`:
## the same identity (special_name) resolves to the SAME folder regardless of the
## Character's job or gender bit (a unique's job is data, never a router — #199).
func _test_unique_dispatch_ignores_job_and_gender() -> void:
	var as_knight: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Ramza", "current_job_id": "4c", "is_female": false})
	as_knight.special_name = 3
	var as_monk_female: CharacterClass = CharacterClass.from_dict(
		{"unit_name": "Ramza", "current_job_id": "4e", "is_female": true})
	as_monk_female.special_name = 3
	_assert_eq(CharacterTemplateResolver.resolve(as_knight).get("template_folder"),
		CharacterTemplateResolver.resolve(as_monk_female).get("template_folder"),
		"Ramza-as-Knight and Ramza-as-Monk resolve to the same unique folder")


## An appearance-type (ADR-0081) — a sheet reachable by neither special_name nor a
## job (the story-townsperson sheets 0x4A–0x5F, Holy Dragon 0x98) — carries a
## semantic `template_token` (the folder's own name). Its key is the token ALONE:
## a distinct APPEARANCE_TYPE category, the token in the key, and NO special_name /
## job / gender axis — the token is the whole appearance key, like special_name is
## for a unique.
func _test_appearance_type_key_is_token_alone() -> void:
	var woman: CharacterClass = CharacterClass.create_default("Townswoman", "4a", true)
	woman.template_token = "40_year_old_woman"
	var k := CharacterTemplateResolver.template_key(woman)
	_assert_eq(k.get("category"), CharacterTemplateResolver.Category.APPEARANCE_TYPE,
		"a template_token'd Character is APPEARANCE_TYPE")
	_assert_eq(k.get("token"), "40_year_old_woman", "appearance key carries the semantic token")
	_assert_true(not k.has("special_name"), "appearance key has NO special_name axis")
	_assert_true(not k.has("job"), "appearance key has NO job axis")
	_assert_true(not k.has("gender"), "appearance key has NO gender axis")


## resolve() routes an appearance-type through the token to its template folder
## (`TEMPLATE_ROOT + token + "/"`) — the SAME `template_folder` shape every other
## dialect returns into `load_body_sprite`; the flat-store `body_sprite_id` shape
## is absent (folder-routed, like a unique).
func _test_appearance_type_resolves_to_token_folder() -> void:
	var woman: CharacterClass = CharacterClass.create_default("Townswoman", "4a", true)
	woman.template_token = "40_year_old_woman"
	var r := CharacterTemplateResolver.resolve(woman)
	_assert_eq(r.get("template_folder"),
		ResidueManifest.TEMPLATE_ROOT + "40_year_old_woman/",
		"appearance-type resolves to TEMPLATE_ROOT + token folder")
	_assert_eq(r.get("template_token"), "40_year_old_woman",
		"appearance resolve carries the token")
	_assert_true(not r.has("body_sprite_id"),
		"an appearance-type does NOT carry the flat-store body_sprite_id (folder-routed)")


## Finding #3 (formation review): the on-disk template.json reader is now a single
## per-folder-CACHED helper on the resolver seam (was duplicated in FormationScene +
## AllTemplatesSeeder, re-parsed per cell per scroll). Pins: it parses a real
## template's metadata, and a second call for the SAME folder returns the SAME cached
## Dictionary instance (no re-read) — the byte-identical, disk-once guarantee.
func _test_read_template_json_parses_and_caches() -> void:
	var folder := ResidueManifest.TEMPLATE_ROOT + "40_year_old_woman/"
	var first := CharacterTemplateResolver.read_template_json(folder)
	_assert_eq(first.get("category"), "generic-human", "read_template_json parses the category")
	_assert_eq(String(first.get("name", "")), "40 year old woman", "parses the display name")
	var second := CharacterTemplateResolver.read_template_json(folder)
	_assert_true(second == first, "same folder returns the SAME cached dict (disk read once)")
	# A missing folder yields {} (and caches the miss) without erroring.
	_assert_true(CharacterTemplateResolver.read_template_json(
		ResidueManifest.TEMPLATE_ROOT + "does_not_exist_zzz/").is_empty(),
		"a missing template.json resolves to {}")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
