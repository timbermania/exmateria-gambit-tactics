extends Node

## TDD guard for the "show all templates" roster seeder (ADR-0081, formation all-154 view).
##
## Seam 2 (behavioral): the seeder enumerates the derived template store and mints ONE
## owned `Character` per **body-bearing** template, routed so that EVERY one resolves to a
## real folder — a unique by its `special_name` (residue → folder), an appearance-type /
## generic by its `template_token` (folder-named). Cutscene-faces (portrait-only, no
## `body.tga`) are NOT body-bearing and must be skipped.
##
## The load-bearing assertion is filesystem-independent of the seeder's own dispatch: for
## every minted Character, `resolve().template_folder + body.tga` must EXIST on disk — the
## "no un-routable unit" spec. We also cross-check the covered folder SET against an
## independent DirAccess scan (surjective onto the body-bearing folders, no dup/drop), and
## spot-check one known appearance-type + one known unique against known-good literals.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/AllTemplatesSeederTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression
const AllTemplatesSeeder = ExMateriaCatalogue.AllTemplatesSeeder
const CharacterTemplateResolver = ExMateriaCatalogue.CharacterTemplateResolver
const UnitNames = ExMateriaCatalogue.UnitNames


const TEMPLATE_ROOT := "res://assets/characters/templates/"

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_roster_enumerates_every_variant_exactly_once()
	_test_every_minted_character_renders()
	_test_known_appearance_type_and_unique_are_routed_by_their_dialect()
	_test_seed_populates_the_owned_overlay()
	_test_every_minted_character_carries_a_populatable_progression()
	_test_unique_zodiac_comes_from_the_real_birthday()
	_test_chocobo_family_surfaces_as_three_variants()
	_test_variant_slugs_do_not_collapse_in_the_owned_overlay()
	_test_uniques_carry_their_canonical_derived_name()
	_test_no_leftover_plain_monster_folder_rows()
	_test_all_uniques_resolve_via_unit_names()
	_test_uniques_carry_their_entd_job()
	_test_wardrobe_rows_job_route_and_carry_no_token()
	_test_no_wardrobe_sheet_is_minted_as_an_appearance_type()

	print("\n=== AllTemplatesSeederTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] AllTemplatesSeederTest")
		get_tree().quit(1)
	else:
		print("[PASS] AllTemplatesSeederTest")
		get_tree().quit(0)


## The variant key OBSERVED from a minted Character's public fields (independent of the
## seeder's slug string): a unique keys on its `special_name`, a true appearance-type on its
## `template_token`, a monster on its `current_job_id`, and a generic-wardrobe row on
## `(job, gender)` — the ADR-0072 dec.1 key. This is the identity the catalogue enumerates,
## the four-source axis read back off the Character.
func _variant_key(c) -> String:
	if c.special_name != 0:
		return "unique:%d" % c.special_name
	if c.template_token != "":
		return "appearance:%s" % c.template_token
	var job: String = c.progression.current_job_id
	if JobDatabase.is_generic_human(job):
		# Gender is part of the key only when the sheet actually differs by it (Bard/Dancer
		# hold one id in both slots) — the same axis `_has_gender_axis` reads.
		if JobDatabase.get_sprite_id(job, false) == JobDatabase.get_sprite_id(job, true):
			return "generic:%s" % job
		return "generic:%s:%s" % [job, "f" if c.is_female else "m"]
	return "monster:%s" % job


## An INDEPENDENT enumeration of the expected variants — computed a different way than the
## seeder (a direct directory scan + a jobs.json walk, not the seeder's dispatch). The
## catalogue enumerates VARIANTS from FOUR sources: every `unique` template folder (keyed by
## its `special_name`), every `generic-human` folder **no generic job reaches** (a true
## appearance-type, keyed by folder — ADR-0081 dec. 8), every generic-human **wardrobe**
## entry keyed `(job, gender)`, and every RENDERABLE monster job (real body sprite id, i.e.
## not the `Unknown_*` sprite-0 jobs). `generic-monster` folders are NOT a source (their
## monsters are job-sourced), and neither are the wardrobe folders (job-sourced likewise).
##
## The wardrobe sprite set is rebuilt HERE from the job tables rather than calling the
## seeder's helper, so the job-reachability test is genuinely checked twice.
func _expected_variant_keys() -> Dictionary:
	var wardrobe := {}
	for job in JobDatabase.all_job_ids():
		if JobDatabase.is_generic_human(job):
			wardrobe[JobDatabase.get_sprite_id(job, false)] = true
			wardrobe[JobDatabase.get_sprite_id(job, true)] = true

	var out := {}
	var dir := DirAccess.open(TEMPLATE_ROOT)
	if dir != null:
		for folder in dir.get_directories():
			if not ResourceLoader.exists(TEMPLATE_ROOT + folder + "/body.tga"):
				continue
			var m := CharacterTemplateResolver.read_template_json(TEMPLATE_ROOT + folder + "/")
			var cat := String(m.get("category", ""))
			if cat == "unique":
				out["unique:%d" % int(str(m.get("template_key", "0")))] = true
			elif cat == "generic-human":
				var sid = m.get("sprite_id")
				var id: int = str(sid).hex_to_int() if sid is String else int(sid if sid != null else -1)
				if not wardrobe.has(id):
					out["appearance:%s" % folder] = true
	for job in JobDatabase.all_job_ids():
		if JobDatabase.is_monster(job) and JobDatabase.get_sprite_id(job) != 0:
			out["monster:%s" % job] = true
		elif JobDatabase.is_generic_human(job):
			if JobDatabase.get_sprite_id(job, false) == JobDatabase.get_sprite_id(job, true):
				out["generic:%s" % job] = true
			else:
				out["generic:%s:m" % job] = true
				out["generic:%s:f" % job] = true
	return out


## The minted roster enumerates every expected VARIANT exactly once, and no stray rows:
## surjective onto (uniques ∪ generic-human folders ∪ renderable monster jobs), no dup, no
## extras. This is the ADR-0081 axis change — the catalogue lists identities, so the sprite-
## sharing monster families surface as distinct rows while the shared folders collapse away.
func _test_roster_enumerates_every_variant_exactly_once() -> void:
	var expected := _expected_variant_keys()
	_assert_true(expected.size() > 150, "sanity: >150 variants expected (%d)" % expected.size())

	var roster: Array = AllTemplatesSeeder.build_roster()
	var covered := {}
	for c in roster:
		var key := _variant_key(c)
		if covered.has(key):
			_assert_true(false, "duplicate variant in roster: %s" % key)
		covered[key] = true

	_assert_eq(roster.size(), expected.size(),
		"one Character per variant (uniques ∪ generic-human folders ∪ renderable monster jobs)")
	for key in expected:
		_assert_true(covered.has(key), "variant %s is enumerated" % key)
	for key in covered:
		_assert_true(expected.has(key), "roster variant %s is expected (no stray rows)" % key)


## The "no un-renderable unit" spec: every minted Character resolves to a body sheet that
## actually renders — `FormationScene.resolve_body_render().ok`, the same seam the formation
## cells draw through. Covers both dialects: a folder variant (body.tga + seq/shp) and a
## job-routed monster variant (a real body sprite).
func _test_every_minted_character_renders() -> void:
	var roster: Array = AllTemplatesSeeder.build_roster()
	var broken := 0
	for c in roster:
		if not FormationScene.resolve_body_render(c).get("ok", false):
			broken += 1
			if broken <= 5:
				print("  [detail] does not render: slug=%s" % c.slug)
	_assert_eq(broken, 0, "every minted Character renders (resolve_body_render().ok)")


## The two dialects the ADR-0081 view exercises: an appearance-type (the 40-year-old woman
## townsperson, 0x4F) routes by `template_token`; a unique (Agrias, special_name 52) routes
## by `special_name` through the residue. Known-good literals from the folder store.
func _test_known_appearance_type_and_unique_are_routed_by_their_dialect() -> void:
	var by_folder := {}
	for c in AllTemplatesSeeder.build_roster():
		var folder: String = CharacterTemplateResolver.resolve(c).get("template_folder", "")
		by_folder[folder.trim_prefix(TEMPLATE_ROOT).trim_suffix("/")] = c

	_assert_true(by_folder.has("40_year_old_woman"), "appearance-type 40_year_old_woman present")
	var woman = by_folder.get("40_year_old_woman")
	if woman != null:
		_assert_eq(woman.template_token, "40_year_old_woman", "townsperson routed by template_token")
		_assert_eq(CharacterTemplateResolver.template_key(woman).get("category"),
			CharacterTemplateResolver.Category.APPEARANCE_TYPE, "townsperson key is APPEARANCE_TYPE")

	_assert_true(by_folder.has("agrias_52"), "unique agrias_52 present")
	var agrias = by_folder.get("agrias_52")
	if agrias != null:
		_assert_eq(agrias.special_name, 52, "Agrias routed by special_name 52 (decimal)")
		_assert_eq(agrias.template_token, "", "a unique carries NO appearance token")
		_assert_eq(CharacterTemplateResolver.template_key(agrias).get("category"),
			CharacterTemplateResolver.Category.UNIQUE, "Agrias key is UNIQUE")


## seed() lands the whole roster in the catalog's OWNED overlay, and every owned unit
## resolves — the projection the formation view binds via owned_units().
func _test_seed_populates_the_owned_overlay() -> void:
	CharacterCatalog.reset_to_new_game()
	var n: int = AllTemplatesSeeder.seed()
	var owned: Array = CharacterCatalog.owned_units()
	_assert_eq(owned.size(), n, "seed() owns exactly the roster it minted (%d)" % n)
	_assert_true(owned.size() > 100, "owned_units() holds the full template roster (%d)" % owned.size())
	var broken := 0
	for c in owned:
		if not FormationScene.resolve_body_render(c).get("ok", false):
			broken += 1
	_assert_eq(broken, 0, "every OWNED unit renders (resolve_body_render().ok)")


## Finding #1: the formation info + vitals panels null-guard a progression-less unit,
## so a bare template row rendered EMPTY. Every minted Character now carries a minimal
## progression — the panels populate — with the REAL display name off template.json.
func _test_every_minted_character_carries_a_populatable_progression() -> void:
	var roster: Array = AllTemplatesSeeder.build_roster()
	var missing := 0
	for c in roster:
		if c.progression == null or String(c.display_name).is_empty():
			missing += 1
	_assert_eq(missing, 0, "every minted Character has a progression + a display name")

	# The info-panel view (the thing that was empty) now resolves for a known unique.
	var agrias = _by_folder(roster).get("agrias_52")
	_assert_true(agrias != null and agrias.progression != null, "agrias_52 carries a progression")
	if agrias != null and agrias.progression != null:
		var view: Dictionary = FormationScene.info_view_from_character(agrias, 1)
		_assert_eq(view.get("name"), agrias.display_name, "info view carries the real name")


## Finding #2: a unique's zodiac is the REAL sign derived from its ENTD birthday (via
## the UnitBirthdays table), not the hardcoded ARIES default. Agrias (special 52, born
## 6/22) is Cancer.
func _test_unique_zodiac_comes_from_the_real_birthday() -> void:
	var agrias = _by_folder(AllTemplatesSeeder.build_roster()).get("agrias_52")
	_assert_true(agrias != null, "agrias_52 present")
	if agrias != null and agrias.progression != null:
		_assert_eq(agrias.progression.zodiac, UnitProgression.Zodiac.CANCER,
			"Agrias' zodiac is Cancer (birthday 6/22), not the ARIES default")


## Slice A (headline): a sprite-sharing monster FAMILY surfaces as DISTINCT variant rows,
## not one shared appearance folder. The Chocobo jobs 5e/5f/60 all draw the ONE CYOKO
## sheet and differ only by palette row — so the catalogue enumerates them as THREE
## variants (Chocobo / Black Chocobo / Red Chocobo, rows 0/1/2, each renderable), keyed
## by their monster job. This is the whole point of enumerating variants (identities)
## instead of appearance folders. Known-good names/rows straight from jobs.json.
func _test_chocobo_family_surfaces_as_three_variants() -> void:
	var chocobo_jobs := ["5e", "5f", "60"]
	var expected_name := {"5e": "Chocobo", "5f": "Black Chocobo", "60": "Red Chocobo"}
	var expected_row := {"5e": 0, "5f": 1, "60": 2}

	var by_job := {}
	for c in AllTemplatesSeeder.build_roster():
		if c.progression != null and chocobo_jobs.has(c.progression.current_job_id):
			by_job[c.progression.current_job_id] = c

	_assert_eq(by_job.size(), 3, "chocobo family surfaces as THREE job variants (5e/5f/60)")

	var sheets := {}
	for job in chocobo_jobs:
		var c = by_job.get(job)
		_assert_true(c != null, "chocobo variant %s present" % job)
		if c == null:
			continue
		_assert_eq(c.display_name, expected_name[job], "variant %s named %s" % [job, expected_name[job]])
		var render: Dictionary = FormationScene.resolve_body_render(c)
		_assert_true(render.get("ok", false), "chocobo variant %s renders" % job)
		_assert_eq(render.get("palette_row"), expected_row[job],
			"chocobo variant %s uses palette row %d" % [job, expected_row[job]])
		sheets[render.get("flat_texture_path", "")] = true

	_assert_eq(sheets.size(), 1, "all three chocobos share ONE sprite sheet (CYOKO)")


## Slice B (the collapse guard): the namespaced slugs are variant-unique, so the owned
## overlay does NOT de-dupe sprite-sharing variants back into one. All three chocobos —
## which share the CYOKO sheet — survive seed() as three distinct owned rows.
func _test_variant_slugs_do_not_collapse_in_the_owned_overlay() -> void:
	CharacterCatalog.reset_to_new_game()
	var minted: int = AllTemplatesSeeder.seed()
	var owned: Array = CharacterCatalog.owned_units()
	_assert_eq(owned.size(), minted, "owned overlay keeps every minted variant (no slug collapse)")
	_assert_eq(owned.size(), AllTemplatesSeeder.build_roster().size(),
		"owned_units() size == build_roster() size")
	var slugs := {}
	for c in owned:
		slugs[c.slug] = true
	for job in ["5e", "5f", "60"]:
		_assert_true(slugs.has("monster:%s" % job),
			"chocobo variant monster:%s survives into owned" % job)


## Slice C: a unique variant's display name is the CANONICAL name DERIVED from its
## `special_name` (via UnitNames), NOT the folder token that used to leak through
## (`adramelk`). A multi-Form character keeps its chapters as distinct variant rows all
## sharing the derived name: Ramza Ch1/2/3 → three rows, all "Ramza", slugs unique:1/2/3.
func _test_uniques_carry_their_canonical_derived_name() -> void:
	var by_slug := {}
	for c in AllTemplatesSeeder.build_roster():
		by_slug[c.slug] = c

	var adramelk = by_slug.get("unique:69")
	_assert_true(adramelk != null, "unique:69 present")
	if adramelk != null:
		_assert_eq(adramelk.display_name, "Adramelk", "unique 69 shows 'Adramelk', not a folder token")

	for sn in [1, 2, 3]:
		var ramza = by_slug.get("unique:%d" % sn)
		_assert_true(ramza != null, "Ramza Form unique:%d is its own row" % sn)
		if ramza != null:
			_assert_eq(ramza.display_name, "Ramza", "Ramza Form %d is named 'Ramza'" % sn)


## Slice D: the plain-monster APPEARANCE folders are dropped — monsters are enumerated
## from jobs — so no variant carries a `generic-monster` folder token (headline: "chocobo",
## and the general sweep over every appearance token).
func _test_no_leftover_plain_monster_folder_rows() -> void:
	var roster: Array = AllTemplatesSeeder.build_roster()
	var chocobo_token_rows := 0
	for c in roster:
		if c.template_token == "chocobo":
			chocobo_token_rows += 1
	_assert_eq(chocobo_token_rows, 0, "no variant carries the dropped generic-monster token 'chocobo'")

	for c in roster:
		if c.template_token != "":
			var m := CharacterTemplateResolver.read_template_json(TEMPLATE_ROOT + c.template_token + "/")
			_assert_true(String(m.get("category", "")) != "generic-monster",
				"appearance token %s is not a dropped generic-monster folder" % c.template_token)


## Slice E: every unique variant resolves its name through UnitNames — zero folder-token
## fallbacks. All 59 uniques carry a canonical name, so none shows a raw folder token.
func _test_all_uniques_resolve_via_unit_names() -> void:
	var uniques := 0
	var fallbacks := 0
	for c in AllTemplatesSeeder.build_roster():
		if c.special_name == 0:
			continue
		uniques += 1
		var canonical := UnitNames.resolve(c.special_name)
		if canonical.is_empty() or c.display_name != canonical:
			fallbacks += 1
			if fallbacks <= 5:
				print("  [detail] unique %d name=%s canonical=%s" % [c.special_name, c.display_name, canonical])
	_assert_eq(uniques, 59, "all 59 unique variants enumerated")
	_assert_eq(fallbacks, 0, "every unique's name is its UnitNames canonical (no folder-token fallback)")


## The catalogue-job fix: a unique Form is seeded with its REAL job (the dominant
## ENTD job baked into template_jobs.json), not the "Squire" placeholder — so the
## nameplate + ability menu show the right job everywhere they read current_job_id.
## Discriminating NON-Squire cases (a placeholder regression would read "Squire"):
## Agrias 52 → Holy Knight (0x34), Orlandu 13 → Holy Swordsman (0x0d). The nameplate
## check goes through JobDatabase.get_job(current_job_id).name — exactly what
## UIUnitNameplate renders. An appearance variant (no special_name) stays Squire.
func _test_uniques_carry_their_entd_job() -> void:
	var by_slug := {}
	for c in AllTemplatesSeeder.build_roster():
		by_slug[c.slug] = c

	var cases := {"unique:52": ["34", "Holy Knight"], "unique:13": ["0d", "Holy Swordsman"]}
	for slug in cases:
		var c = by_slug.get(slug)
		_assert_true(c != null and c.progression != null, "%s carries a progression" % slug)
		if c == null or c.progression == null:
			continue
		var want_job: String = cases[slug][0]
		var want_name: String = cases[slug][1]
		_assert_eq(c.progression.current_job_id, want_job,
			"%s seeded with its ENTD job 0x%s (not the Squire placeholder)" % [slug, want_job])
		_assert_eq(String(JobDatabase.get_job(c.progression.current_job_id).get("name", "")),
			want_name, "%s nameplate/ability-menu job word is '%s'" % [slug, want_name])

	# An appearance variant has no special_name -> no ENTD job -> keeps the Squire default.
	var woman = _by_folder(AllTemplatesSeeder.build_roster()).get("40_year_old_woman")
	_assert_true(woman != null and woman.progression != null, "40_year_old_woman carries a progression")
	if woman != null and woman.progression != null:
		_assert_eq(woman.progression.current_job_id, "4a",
			"an appearance variant (no special_name) keeps the Squire default")


## Map folder token -> minted Character, for spot-checks.
func _by_folder(roster: Array) -> Dictionary:
	var out := {}
	for c in roster:
		var folder: String = CharacterTemplateResolver.resolve(c).get("template_folder", "")
		out[folder.trim_prefix(TEMPLATE_ROOT).trim_suffix("/")] = c
	return out


const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")


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


## ADR-0072 dec.1, mechanized: a generic-wardrobe row's BODY is a function of its job. Change
## the unit's job and the resolved body sprite must change with it — the property a
## `template_token` silently defeated (ADR-0081 dec. 8), and the reason the Change-Job
## commit's pixel dissolve had identical art on both sides.
##
## Asserted through `resolve_body_render`, the same seam the formation cell draws through, so
## this is the rendered sheet and not just the key.
func _test_wardrobe_rows_job_route_and_carry_no_token() -> void:
	var wardrobe := []
	for c in AllTemplatesSeeder.build_roster():
		if c.special_name == 0 and c.template_token == "" \
				and JobDatabase.is_generic_human(c.progression.current_job_id):
			wardrobe.append(c)
	_assert_eq(wardrobe.size(), 38, "38 generic-wardrobe rows (20 jobs; Bard/Dancer ungendered)")

	# Every one of them must be token-free — a token would pin the sheet for life.
	var tokened := 0
	for c in wardrobe:
		if c.template_token != "":
			tokened += 1
	_assert_eq(tokened, 0, "no wardrobe row carries a template_token")

	# And the body must actually FOLLOW the job. Squire -> Knight is a real sheet change
	# (0x60 -> 0x64); assert the rendered address moves with it.
	var squire = null
	for c in wardrobe:
		if c.progression.current_job_id == "4a" and not c.is_female:
			squire = c
	_assert_true(squire != null, "male Squire wardrobe row present")
	if squire == null:
		return
	var before: Dictionary = FormationScene.resolve_body_render(squire)
	squire.progression.current_job_id = "4c"  # Knight
	var after: Dictionary = FormationScene.resolve_body_render(squire)
	_assert_true(before.get("ok", false) and after.get("ok", false),
		"both jobs render (before=%s after=%s)" % [before.get("ok"), after.get("ok")])
	_assert_true(before.get("flat_texture_path", "") != after.get("flat_texture_path", ""),
		"changing job changes the body sheet (%s -> %s)" %
			[before.get("flat_texture_path", ""), after.get("flat_texture_path", "")])
	squire.progression.current_job_id = "4a"  # restore (build_roster is pure, but be tidy)


## The ADR-0081 dec. 8 invariant: `template_token` is carried by TRUE appearance-types only
## — sheets no job reaches. A sheet in the generic wardrobe must never be minted as one.
## The wardrobe set is recomputed from the job tables here, independent of the seeder helper.
func _test_no_wardrobe_sheet_is_minted_as_an_appearance_type() -> void:
	var wardrobe := {}
	for job in JobDatabase.all_job_ids():
		if JobDatabase.is_generic_human(job):
			wardrobe[JobDatabase.get_sprite_id(job, false)] = true
			wardrobe[JobDatabase.get_sprite_id(job, true)] = true

	var offenders := []
	var tokened := 0
	for c in AllTemplatesSeeder.build_roster():
		if c.template_token == "":
			continue
		tokened += 1
		var meta := CharacterTemplateResolver.read_template_json(
			TEMPLATE_ROOT + c.template_token + "/")
		var sid = meta.get("sprite_id")
		var id: int = str(sid).hex_to_int() if sid is String else int(sid if sid != null else -1)
		if wardrobe.has(id):
			offenders.append("%s (0x%02X)" % [c.template_token, id])

	_assert_eq(offenders.size(), 0,
		"no appearance-type is a generic-wardrobe sheet: %s" % ", ".join(offenders))

	# 39 tokened rows = the 21 TRUE appearance-types (no job reaches them) + the 18 STAGED
	# remainder ADR-0081 dec. 8 names: 15 story bodies (reached by a `special` job) and
	# 3 monster sheets (reached by a `monster` job). Those 18 are fixed-look either way, so
	# re-keying them changes no behaviour — they are a named remainder, not an oversight.
	# This number is a ratchet: it may only go DOWN, and only by retiring the remainder.
	_assert_eq(tokened, 39, "21 true appearance-types + the 18 staged story/monster remainder")

	var reached_by_a_job := 0
	for c in AllTemplatesSeeder.build_roster():
		if c.template_token == "":
			continue
		var meta := CharacterTemplateResolver.read_template_json(
			TEMPLATE_ROOT + c.template_token + "/")
		var sid = meta.get("sprite_id")
		var id: int = str(sid).hex_to_int() if sid is String else int(sid if sid != null else -1)
		for job in JobDatabase.all_job_ids():
			if JobDatabase.get_sprite_id(job, false) == id \
					or JobDatabase.get_sprite_id(job, true) == id:
				reached_by_a_job += 1
				break
	_assert_eq(reached_by_a_job, 18, "the staged remainder is exactly the 18 job-reached sheets")
