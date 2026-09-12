extends RefCounted

## Mints an owned `Character` for every catalogue **variant** — the roster behind the
## formation "show all templates" view (ADR-0081). A sibling of [StoryMutationScript]:
## where that seeds a hand-authored squad, this enumerates the whole derived template
## store and owns one unit per **variant** (identity), not per appearance folder.
##
## A *variant* is the thing the catalogue lists; it RESOLVES a folder (+ palette row) and
## carries a DERIVED display name. Both the name and the folder come *from* the variant
## key, never the key itself — so Ramza Ch1/2/3 are three variants all named "Ramza"
## (special_names 1/2/3, folders ramza_1/2/3), and Black Chocobo is one variant (monster
## job `5f` → shared CYOKO sheet + palette row 1). Variants come from three sources, each
## routed through a dialect [CharacterTemplateResolver] already dispatches:
##   - **unique** (folder-sourced) — a `unique` template folder. `special_name` = the
##       folder's decimal `template_key`, routed back to that folder by [ResidueManifest];
##       the display NAME is the canonical [UnitNames] name (fixes uniques showing a folder
##       token like `adramelk`). Slug `unique:<special_name>`.
##   - **appearance** (folder-sourced) — a `generic-human` template folder that **no
##       generic job reaches**: a true *appearance-type*, carrying a [template_token] =
##       the folder's own name (ADR-0081). The townsperson sheets render directly.
##       Slug `appearance:<folder>`. The job-reachability test is ADR-0081 dec. 8's
##       — `template.json.category` is a body-SHAPE axis and matches the wardrobe too.
##   - **generic-human** (job-sourced) — one variant per wardrobe sheet, keyed `(job,
##       gender)`. NO token: these job-route, so a job change changes the sheet, which is
##       ADR-0072 dec.1. Slug `generic:<job>[:m|:f]`.
##   - **monster** (job-sourced) — one variant per RENDERABLE monster job, NOT per folder.
##       This surfaces the sprite-sharing families (Chocobo/Black/Red) as distinct rows:
##       each carries its real `current_job_id`, so the resolver's GENERIC_MONSTER branch
##       supplies the shared sprite + the job's palette row. Slug `monster:<job>`.
##   - `generic-monster` folders are DROPPED (monsters are job-sourced); `cutscene-face`
##       folders have no `body.tga` and are skipped either way.
##
## Slugs are variant-unique (the namespaced forms above) so the owned overlay does not
## collapse sprite-sharing variants back into one. Each Character carries identity +
## appearance handle + a MINIMAL `progression` so the formation info/vitals panels
## populate (§14.6). The template store holds no per-unit stat data, so job/stats are
## neutral catalogue defaults; what IS real is the display NAME and a unique's ZODIAC
## (FFT derives it from the birthday, looked up by `special_name` via [UnitBirthdays]).

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase
const SpriteDatabase = ExMateriaAlmanac.SpriteDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression

# ADR-0118 dec. 1's TWELFTH schema row (ADR-0294 dec. 2) — the base-stat body is a
# value set and is the kernel's; `UnitProgression` above is still named, because
# this file genuinely constructs one.
const BaseStatType = ExMateriaSchema.BaseStatType.Type


const CatalogueContent = preload("res://addons/exmateria_catalogue/install/CatalogueContent.gd")

# The template store is HOST CONTENT: ROM-derived, regenerable and gitignored, so it
# cannot travel into the addon (ADR-0202 dec. 5). A `static var` and not a `const`
# because the value is read from `ProjectSettings` rather than written here, and every
# call site keeps the spelling it already had.
static var TEMPLATE_ROOT: String = CatalogueContent.resolve(CatalogueContent.TEMPLATES_SUBPATH)
# The flat body sheets, SHARED with `exmateria_sprite_rig` and five host readers —
# the same host-injected root, a different subpath.
static var _TEXTURE_DIR: String = CatalogueContent.resolve(CatalogueContent.TEXTURES_SUBPATH)
# SIBLING MEMBERS of this addon, by path. A member declares no `class_name` — the
# folder-named facade holds the addon's ONE global (ADR-0212 dec. 1) — so an
# intra-addon reference preloads its sibling, which is `exmateria_almanac`'s own
# idiom (`items/EquipStatDelta.gd:33`). Outside the addon the same names come
# off `ExMateriaCatalogue`; inside it there is no facade to go through.
const CatalogueRegistry = preload("res://addons/exmateria_catalogue/registry/CharacterCatalog.gd")
const Character = preload("res://addons/exmateria_catalogue/identity/Character.gd")
const CharacterTemplateResolver = preload("res://addons/exmateria_catalogue/templates/CharacterTemplateResolver.gd")
const UnitBirthdays = preload("res://addons/exmateria_catalogue/identity/UnitBirthdays.gd")
const UnitNames = preload("res://addons/exmateria_catalogue/identity/UnitNames.gd")

## The special_name -> real job bridge (2-hex jobs.json key), derived from the
## dominant ENTD job per Form by tools/derive_template_jobs.py. A SIBLING of the
## residue/assets bridges kept OUT of the assets-only template.json (ADR-0072
## dec.2). Read once, cached; a unique Form seeds THIS job so the nameplate +
## ability menu show its real job instead of the Squire placeholder below.
const _JOBS_PATH := "res://addons/exmateria_catalogue/seeding/template_jobs.json"
static var _jobs_by_special: Dictionary = {}
static var _jobs_loaded := false

## The stat job a human catalogue row (unique / appearance) is seeded with: the template
## store names no job, so this is a neutral default that lets the vitals HP/MP compute and
## the info panel's job line render. NOT a per-unit truth — a unique's real job is not in
## this data. Monster variants instead carry their REAL monster job (below).
const _DEFAULT_HUMAN_JOB := "4a"  # Squire


## Build one Character per catalogue variant. Pure — touches no catalog. Four sources:
## folder-sourced uniques + true appearance-types, then the job-sourced generic-human
## wardrobe and the job-sourced renderable monster variants.
static func build_roster() -> Array:
	var out: Array = []
	out.append_array(_folder_variants())
	out.append_array(_generic_human_job_variants())
	out.append_array(_monster_job_variants())
	return out


## The folder-sourced variants: a `unique` folder mints a unique variant, a
## `generic-human` folder mints an appearance variant. `generic-monster` folders are
## dropped (their monsters are job-sourced) and `cutscene-face` folders carry no
## `body.tga`. Directory order; skips a folder with no `template.json` or no `body.tga`.
static func _folder_variants() -> Array:
	var out: Array = []
	var dir := DirAccess.open(TEMPLATE_ROOT)
	if dir == null:
		push_warning("[AllTemplatesSeeder] template store not found at %s" % TEMPLATE_ROOT)
		return out
	for folder in dir.get_directories():
		if not ResourceLoader.exists(TEMPLATE_ROOT + folder + "/body.tga"):
			continue  # no body sheet (cutscene-face) — not renderable in a body view
		var meta := _read_template(folder)
		if meta.is_empty():
			continue
		var category := String(meta.get("category", ""))
		if category == "unique":
			out.append(_unique_variant(folder, meta))
		elif category == "generic-human" and not _is_generic_wardrobe(meta):
			out.append(_appearance_variant(folder, meta))
		# generic-monster → dropped (job-sourced below); cutscene-face → no body, skipped;
		# generic WARDROBE sheets → dropped here, job-sourced by _generic_human_job_variants
	return out


## Is this folder a **generic-wardrobe** sheet — the body of a `generic_human` job — rather
## than an [appearance-type]? ADR-0081 dec. 8: the test is data-derived JOB-REACHABILITY,
## never `template.json.category` (that field is the transform's SHP *body-shape* axis — is
## the skeleton humanoid — and matches all 77 human sheets, 38 of which a job does reach).
## A wardrobe sheet must NOT carry a `template_token`: the token would pin the unit to one
## sprite for life, defeating ADR-0072 dec.1 (for a generic, `job` is data AND the router).
static func _is_generic_wardrobe(meta: Dictionary) -> bool:
	var sprite_id = meta.get("sprite_id")
	if sprite_id == null:
		return false
	# template.json stores the id as a HEX STRING ("60", "4F"); the job tables hold ints.
	var id: int = str(sprite_id).hex_to_int() if sprite_id is String else int(sprite_id)
	return JobDatabase.generic_wardrobe_sprite_ids().has(id)


## One variant per generic-human **wardrobe** entry — job-sourced, exactly as the monster
## variants below are, and for the same reason: the *variant* is what the catalogue is about,
## and for a generic the variant is `(job, gender)` — the ADR-0072 dec.1 key itself. Two rows
## for a job whose sheet differs by gender, ONE for a gender-invariant one (Bard 0x82 and
## Dancer 0x83 hold the same id in both slots), which is the same data-derived test the
## resolver's `_has_gender_axis` makes. 20 jobs → 38 rows, one per wardrobe sheet.
##
## These rows carry NO `template_token` (ADR-0081 dec. 8): they job-route, so changing the
## unit's job changes its sheet — which is the whole content of ADR-0072 dec.1 and what a
## token silently defeated.
static func _generic_human_job_variants() -> Array:
	var out: Array = []
	for job in JobDatabase.all_job_ids():
		if not JobDatabase.is_generic_human(job):
			continue
		if JobDatabase.get_sprite_id(job, false) == JobDatabase.get_sprite_id(job, true):
			out.append(_generic_human_variant(job, false, false))  # one gender-invariant row
		else:
			out.append(_generic_human_variant(job, false, true))
			out.append(_generic_human_variant(job, true, true))
	return out


## A generic-wardrobe variant: a job-routed `Character` with no token and no `special_name`,
## so [CharacterTemplateResolver] takes its GENERIC_HUMAN branch and `(job, gender)` picks the
## sheet. Slug `generic:<job>` (+`:f`/`:m` when the sheet is gender-variant) keeps the two
## gendered rows distinct in the owned overlay. The display name reproduces the wardrobe
## folder's own naming ("Male Squire"), which is what the catalogue listed before these rows
## became job-sourced; a gender-invariant sheet is just the job name ("Bard").
static func _generic_human_variant(job: String, female: bool, gendered: bool) -> Character:
	var job_name: String = JobDatabase.get_job(job).get("name", job)
	var display := job_name
	var slug := "generic:%s" % job
	if gendered:
		display = ("Female %s" if female else "Male %s") % job_name
		slug += ":f" if female else ":m"
	var c := Character.new(slug, display, Character.Provenance.FIXED)
	c.is_female = female
	c.progression = _minimal_progression(false, job, Character.SPECIAL_NAME_NONE, female)
	return c


## One variant per RENDERABLE monster job (data-derived, NOT a folder scan and NOT a
## hardcoded id range): every job whose `kind == "monster"` and whose resolved body
## sprite actually exists. The ~11 `Unknown_*` monster jobs carry sprite 0 (absent from
## the SpriteDatabase) and are skipped. This is the source that surfaces the sprite-
## sharing families (Chocobo/Black/Red) as distinct rows.
static func _monster_job_variants() -> Array:
	var out: Array = []
	for job in JobDatabase.all_job_ids():
		if not JobDatabase.is_monster(job):
			continue
		var c := _monster_variant(job)
		if _renders(c):
			out.append(c)
	return out


## Register the whole roster into the catalog and mark each owned — the projection the
## formation view binds via `owned_units()`. Returns the number owned. Idempotent
## (add_owned de-dupes; register replaces). `catalog` defaults to the autoload.
static func seed(catalog = null) -> int:
	if catalog == null:
		catalog = CatalogueRegistry.live()
	if catalog == null:
		return 0
	var roster := build_roster()
	for c in roster:
		catalog.register(c)
		catalog.add_owned(c.slug)
	return roster.size()


## Parse a template's `template.json`, or {} if unreadable — through the shared,
## per-folder-cached reader on the template-resolver seam (one disk read per template).
static func _read_template(folder: String) -> Dictionary:
	return CharacterTemplateResolver.read_template_json(TEMPLATE_ROOT + folder + "/")


## A unique variant: the folder's decimal `template_key` is its `special_name` (routed
## back to this folder by [ResidueManifest]); the display NAME is the canonical [UnitNames]
## name, DERIVED from that key — not the folder token. Slug `unique:<special_name>` keeps
## a multi-Form character's chapters (Ramza 1/2/3) as distinct variant rows.
static func _unique_variant(folder: String, meta: Dictionary) -> Character:
	var special := int(str(meta.get("template_key", "0")))
	var display := UnitNames.resolve(special)
	if display.is_empty():
		display = String(meta.get("name", folder))  # fallback (all 59 uniques resolve today)
	var c := Character.new("unique:%d" % special, display, Character.Provenance.FIXED)
	c.special_name = special
	c.progression = _minimal_progression(false, _job_for_special(special), special)
	return c


## The unique Form's real job (its dominant ENTD job, from template_jobs.json), or
## the neutral Squire default when the Form is absent from the map (an all-sentinel
## Form, or the bridge missing). Loads the map once; NOT a per-unit stat truth for a
## default, but the real special job (Holy Knight, Holy Swordsman, ...) for a mapped Form.
static func _job_for_special(special: int) -> String:
	if not _jobs_loaded:
		_jobs_loaded = true
		_jobs_by_special = {}
		if ResourceLoader.exists(_JOBS_PATH) or FileAccess.file_exists(_JOBS_PATH):
			var f := FileAccess.open(_JOBS_PATH, FileAccess.READ)
			if f != null:
				var doc = JSON.parse_string(f.get_as_text())
				if doc is Dictionary:
					_jobs_by_special = doc.get("jobs", {})
	return String(_jobs_by_special.get(str(special), _DEFAULT_HUMAN_JOB))


## An appearance variant (ADR-0081): a `generic-human` sheet reachable by no job. Carries
## the folder-named `template_token`; its NAME is the folder's `template.json` name (or the
## folder token if unnamed — an appearance has no canonical identity). Slug `appearance:<folder>`.
static func _appearance_variant(folder: String, meta: Dictionary) -> Character:
	var display: String = meta.get("name", folder)
	var c := Character.new("appearance:%s" % folder, display, Character.Provenance.FIXED)
	c.template_token = folder
	c.progression = _minimal_progression(false, _DEFAULT_HUMAN_JOB, Character.SPECIAL_NAME_NONE)
	return c


## A monster variant: keyed by its real monster `job`, so the resolver's GENERIC_MONSTER
## branch supplies the shared sprite + the job's palette row (Chocobo/Black/Red all draw
## CYOKO, rows 0/1/2). NAME is the job's name. Slug `monster:<job>`.
static func _monster_variant(job: String) -> Character:
	var display: String = JobDatabase.get_job(job).get("name", job)
	var c := Character.new("monster:%s" % job, display, Character.Provenance.FIXED)
	c.progression = _minimal_progression(true, job, Character.SPECIAL_NAME_NONE)
	return c


## Data-derived renderability: does this Character resolve to a body sheet that EXISTS on
## disk? A folder-routed variant needs its `body.tga`; a job-routed monster needs its
## resolved body sprite's `.tga` texture. The `Unknown_*` monster jobs carry sprite id 0,
## whose `00.SPR` texture was never extracted — so they resolve to a missing sheet and are
## skipped. (SpriteDatabase carries a placeholder `00` metadata entry, so file existence —
## not entry presence — is the honest test.) Pure: resolver + data layer, no UI dependency.
static func _renders(c: Character) -> bool:
	var v := CharacterTemplateResolver.resolve(c)
	var folder: String = v.get("template_folder", "")
	if not folder.is_empty():
		return ResourceLoader.exists(folder + "body.tga")
	var spr_file: String = SpriteDatabase.get_sprite(v.get("body_sprite_id", 0)).get("spr_file", "")
	if spr_file.is_empty():
		return false
	return ResourceLoader.exists(_TEXTURE_DIR + spr_file.replace(".SPR", ".tga"))


## A minimal [UnitProgression] so the info + vitals panels render for a catalogue row.
## `is_monster` picks the base-stat body (MONSTER vs MALE); `job` is the stat job (a real
## monster job for monster variants, else the neutral human default). A non-generic
## `special_name` sets the real ZODIAC — FFT derives it from the birthday, looked up via
## [UnitBirthdays] (absent → keep default).
static func _minimal_progression(is_monster: bool, job: String, special_name: int,
		female: bool = false) -> UnitProgression:
	var prog := UnitProgression.new()
	var body := BaseStatType.MONSTER if is_monster \
		else (BaseStatType.FEMALE if female else BaseStatType.MALE)
	prog.initialize(body, job)
	if special_name != Character.SPECIAL_NAME_NONE:
		var z := UnitBirthdays.zodiac_of(special_name)
		if z >= 0:
			prog.zodiac = z
	return prog
