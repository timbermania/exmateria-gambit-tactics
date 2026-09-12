class_name PromotedRosterSeeder
extends RefCounted

## Promotes catalogue **variants** into real, mutable **units** — the roster behind any
## screen that EDITS a unit (change-job, equip), as opposed to the one that BROWSES the
## template store.
##
## [AllTemplatesSeeder] answers "what sheets exist": its rows are a catalogue, minted
## `Provenance.FIXED` with a MINIMAL progression, and ADR-0081 dec. 5 is explicit that
## it "is a catalogue view, not a roster editor" whose job/stats are "honest catalogue
## defaults, not per-unit truths". A screen that mutates a unit needs the other thing: an
## identity with a real progression that can take a job change and keep it.
##
## The two used to share `AllTemplatesSeeder.build_roster()`, which is why the change-job
## screen was editing catalogue rows. This is the seam between them.
##
## **What promotion preserves, and what it does not** — the appearance-vs-identity axis
## (ADR-0081 dec. 10, its one rule):
##
##   > Only a generic human's look follows their job.
##
##   - a **unique** keeps its `special_name`, so it keeps routing to its own folder and its
##       look is job-invariant (Agrias-as-Wizard looks like Agrias — ADR-0072 dec.1). Its
##       name stays `Provenance.FIXED`: canonical, ROM-derived, not player-editable.
##   - a **generic-wardrobe** unit carries job + gender and **no token**, so `(job, gender)`
##       routes its body and a job change actually changes the sheet.
##   - a **monster** keeps its monster job — which IS its species, so it never changes job
##       and keeps its sheet.
##   - a true **appearance-type** keeps its `template_token`: no job reaches that sheet, so
##       there is nothing else to route by. Promoting it grants the identity the SHEET does
##       not have (ADR-0081: many instances share one token) — the identity lives in the
##       slug, exactly as the model says.
##
## The progression is the real one ([Character.create_default]) — base stats for the job and
## gender, the job's starting weapon, a live `job_levels` — not the catalogue's minimal stub.

const Character = ExMateriaCatalogue.Character
const AllTemplatesSeeder = ExMateriaCatalogue.AllTemplatesSeeder
## Promote one catalogue variant into a real unit. Pure — returns a NEW `Character`, leaves
## the variant untouched. Identity (slug) and appearance handle (`special_name` /
## `template_token`) carry over verbatim; the progression is rebuilt as a real one.
static func promote(variant) -> Character:
	var job: String = variant.progression.current_job_id
	# A unique's name is canonical and ROM-derived, so it stays FIXED (ADR-0066 dec.11);
	# everyone else's is player-authored and editable.
	var provenance := Character.Provenance.FIXED if variant.special_name != 0 \
		else Character.Provenance.PLAYER

	var c := Character.create_default(
		variant.display_name, job, variant.is_female, provenance)
	c.slug = variant.slug
	c.special_name = variant.special_name
	c.template_token = variant.template_token
	c.forms = variant.forms.duplicate()
	# Zodiac is DERIVED from the ROM birthday upstream (ADR-0081 dec. 6) — a real
	# per-unit truth, unlike the catalogue's stat defaults, so it carries over.
	c.progression.zodiac = variant.progression.zodiac
	return c


## The whole promoted roster: every catalogue variant as a real unit. Pure — touches no
## catalog.
static func build_roster() -> Array:
	var out: Array = []
	for variant in AllTemplatesSeeder.build_roster():
		out.append(promote(variant))
	return out


## Register the promoted roster into the catalog and mark each owned. Returns the number
## owned. The mutating-screen counterpart of `AllTemplatesSeeder.seed()`.
static func seed(catalog = null) -> int:
	if catalog == null:
		catalog = CharacterCatalog
	var roster := build_roster()
	for c in roster:
		catalog.register(c)
		catalog.add_owned(c.slug)
	return roster.size()
