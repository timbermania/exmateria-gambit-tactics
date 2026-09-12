extends RefCounted

## The seam between a `Character` and its visual template (ADR-0072).
##
## A `Character` (identity + data) is a *materialized instance* of an immutable
## asset **template** — the resolver is the one place that maps
##   `Character (identity + job) → template key → assets`
## and is part of neither the character nor the template (glossary: `resolver`).
##
## Dispatch is a pure function of the `Character`'s materialized params, no story
## context. An explicit **appearance-type** token (ADR-0081) wins first; otherwise
## the ADR-0072 **unique vs job-routed** bit (dec.1, #199) decides:
##
##   - **appearance-type** `(template_token)` — a sheet reachable by neither a
##       `special_name` (not an identity) nor a job (the townsperson sheets, Holy
##       Dragon): `resolve()` routes `TEMPLATE_ROOT + token` to the same template
##       **folder** shape a unique returns. Set only on such a Character; "" otherwise.
##
##   - **unique** `(special_name)`  — the `special_name` (materialized at the
##       seeding seam, #202) is present in the [ResidueManifest]; it is the WHOLE
##       key (one ROM token packing identity + Form). Routes by `special_name`
##       ALONE — `job`/`gender`/`slug` never enter the key. `resolve()` returns
##       the unique's derived **template folder** (the #203 loaders read it).
##   - **job-routed** — the `special_name` is not in the residue. Data-derived by
##       whether the sprite is gender-variant (no hardcoded job lists), #198:
##       - generic-human  `(job, gender)` — sprite differs by gender (Squire 60/61)
##       - generic-monster `(job)`        — gender-invariant sprite (Chocobo 0x86
##             both; also ungendered `special` sprites like Holy Dragon 0x48).
##       `resolve()` returns the existing-asset ids the flat loaders consume.
##
## Monsters stay job-routed even when named — a named boss simply isn't in the
## residue, so the one dispatch handles it with no special case (#199 dec.4).

# SIBLING MEMBERS of this addon, by path. A member declares no `class_name` — the
# folder-named facade holds the addon's ONE global (ADR-0212 dec. 1) — so an
# intra-addon reference preloads its sibling, which is `exmateria_almanac`'s own
# idiom (`items/EquipStatDelta.gd:33`). Outside the addon the same names come
# off `ExMateriaCatalogue`; inside it there is no facade to go through.
const ResidueManifest = preload("res://addons/exmateria_catalogue/templates/ResidueManifest.gd")

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase

## The category of a template key — its *shape*. UNIQUE is the residue-routed
## branch; GENERIC_HUMAN/GENERIC_MONSTER are the two job-routed outcomes;
## APPEARANCE_TYPE (ADR-0081) is the token-routed branch — a sheet that is neither
## an identity nor a job, keyed by its semantic `template_token` alone.
enum Category { GENERIC_HUMAN, GENERIC_MONSTER, UNIQUE, APPEARANCE_TYPE }


## True when a job's body sprite differs by gender — the data-derived test that
## decides whether the template key carries a gender axis. Generic humans author
## distinct M/F sprites (Squire 0x60/0x61); monsters and ungendered specials hold
## the same id in both slots, so they key on `(job)` alone.
static func _has_gender_axis(job_id: String) -> bool:
	return JobDatabase.get_sprite_id(job_id, false) != JobDatabase.get_sprite_id(job_id, true)


## The polymorphic template key for a `Character` (ADR-0072 dec.1). A unique
## (its materialized `special_name` is in the residue) keys on `special_name`
## ALONE; otherwise a job-routed key carries `job`, plus `gender` for a
## GENERIC_HUMAN. The residue membership IS the dispatch — a pure static lookup
## over the materialized `special_name`, the same shape as the gender-axis test.
static func template_key(character) -> Dictionary:
	if character.template_token != "":
		return {"category": Category.APPEARANCE_TYPE, "token": character.template_token}
	if ResidueManifest.has(character.special_name):
		return {"category": Category.UNIQUE, "special_name": character.special_name}
	var job: String = character.progression.current_job_id
	if _has_gender_axis(job):
		return {
			"category": Category.GENERIC_HUMAN,
			"job": job,
			"gender": "female" if character.is_female else "male",
		}
	return {"category": Category.GENERIC_MONSTER, "job": job}


## Resolve a `Character` to the address of its owned assets (ADR-0072 dec.2/3).
## A **unique** resolves through the residue manifest to its derived template
## **folder** (`special_name → manifest → folder`, #202) — job-invariant, so
## Ramza-as-Monk == Ramza-as-Wizard; the #203 loaders read assets from it. A
## **job-routed** unit returns the body sprite id read through the existing job
## tables; the gender axis flips it for generic humans, and is inert for a
## gender-invariant sprite.
##
## IT DOES NOT ANSWER THE BODY PALETTE ROW, and the absence is the decision
## (#1071, ADR-0272). The row is a RENDER fact whose rule lives in exactly one
## place — `SpritePaletteResolver.job_body_palette_row` in `exmateria_sprite_rig`
## — and every consumer of this dict handed the value straight to a sprite-layer
## setter without reading it. Answering it here bought them nothing and cost this
## addon its ONLY cross-addon reach (`ARM1_BURN_DOWN`'s one row). Both consumers
## already hold the `Character`, so they ask the rig with the job themselves:
## [UnitSpawn.build] and [FormationScene.resolve_body_render]. A key that is
## carried but never read is a dependency with no consumer.
static func resolve(character) -> Dictionary:
	if character.template_token != "":
		return {
			"template_folder": ResidueManifest.TEMPLATE_ROOT + character.template_token + "/",
			"template_token": character.template_token,
		}
	if ResidueManifest.has(character.special_name):
		return {
			"template_folder": ResidueManifest.folder_of(character.special_name),
			"special_name": character.special_name,
		}
	var job: String = character.progression.current_job_id
	return {
		"body_sprite_id": JobDatabase.get_sprite_id(job, character.is_female),
	}


## The template store's on-disk metadata, keyed by folder. `_template_json_cache`
## holds the parsed `template.json` per folder so the readers below hit disk ONCE
## per template for the whole process — the formation scroll used to re-parse every
## cell's JSON on every rebuild. The store is immutable at runtime, so the cache is
## never invalidated.
static var _template_json_cache: Dictionary = {}


## Parse a template folder's `template.json` (ADR-0072 metadata), CACHED per folder.
## `template_folder` is the full `res://` path ending in "/". Returns {} if the file
## is missing or unparseable. This is the ONE reader of the template metadata — both
## the formation body-render resolution and [AllTemplatesSeeder] route here, so the
## per-cell disk IO the ADR-0081 scroll left on the table is read once and reused.
## READ-ONLY: the returned dict is the shared cached instance — callers must not mutate.
static func read_template_json(template_folder: String) -> Dictionary:
	if _template_json_cache.has(template_folder):
		return _template_json_cache[template_folder]
	var out: Dictionary = {}
	var f := FileAccess.open(template_folder + "template.json", FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			out = parsed
	_template_json_cache[template_folder] = out
	return out
