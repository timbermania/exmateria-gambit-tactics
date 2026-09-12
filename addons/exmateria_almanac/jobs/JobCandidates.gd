extends RefCounted

## The formation Learn job-picker's full CATALOGUE source — the job-domain sibling of
## [AbilityCandidates] (ADR-0197's scaffold, one domain over). A testing scaffold that
## lists EVERY job carrying a learnable ability with NO progression gate, so the
## picker's 11-row scroll/render pipeline and the four number columns get exercised
## against the real data instead of the ~13 jobs a seeded unit has unlocked.
##
## The ROM-faithful, gated sibling is [code]UnitProgression.get_unlocked_jobs()[/code]
## (generic jobs the unit has unlocked), retained UNTOUCHED as the revert seam — only
## [code]FormationDetailTransition._open_job_picker()[/code] switches to this, exactly
## as ADR-0197 kept [code]AbilityLoadout.candidates[/code] alive.
##
## [method build_catalog] is unit-independent and pure, returning picker rows
## [code]{id, name}[/code] name-sorted ascending with the JOB INDEX as the stable
## tie-break. [code]id[/code] is the HEX-STRING job index — the picker's key, which the
## host uses to read this unit's Lv./Total/Next/Jp off its progression. Those
## per-unit numbers are deliberately NOT here: the picker is a renderer and the host
## owns the progression read (LEARN_PICKER.md round 10 #5).
##
## Scope is every job in jobs.json — generic, special AND monster (160), filtered to
## the 80 that carry at least one JP-costed learnable. Dropping the other 80 is DATA
## HYGIENE, not a gate: a job with an empty learn list renders a dead row that can
## never commit. No filter by [code]kind[/code] — "every option" means every option.
##
## The name column collides on purpose. 19 display names are shared by more than one
## job index; six jobs are named "Squire" (01/02/03/04/07/4a) with genuinely different
## learn lists — 03 carries Ultima at 9999 JP, the generic 4a does not. The catalogue
## shows all six as plain identical "Squire" rows (a deliberate UI decision: the JOB
## column's ~90 px cannot take a suffix without colliding with the Lv. column, and the
## four number columns already distinguish them). That is why the sort tie-break is
## the index and why the row key is the index rather than the name.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")
const JobDatabase = preload("res://addons/exmateria_almanac/jobs/JobDatabase.gd")


## The catalogue is pure and unit-independent (see the class docs), but it costs 8.6 ms to
## build: it walks all 160 jobs and asks AbilityDatabase for each one's learnables. The Learn
## press paid that on EVERY open — a quarter of the press's whole synchronous cost. Since the
## answer cannot change unless the job/ability data is reloaded, it is computed once and
## memoized. Callers get a fresh copy each time (an 80-row duplicate is ~0.1 ms), so nobody can
## sort, splice or re-key the shared answer out from under the next caller.
static var _catalog_cache: Array = []


## Discard the memoized catalogue. Wired to [method JobDatabase.reload], the debug-only path
## that can change the answer; nothing in normal play needs it.
static func clear_cache() -> void:
	_catalog_cache = []


static func build_catalog() -> Array:
	if _catalog_cache.is_empty():
		_catalog_cache = _build_catalog_uncached()
	return _catalog_cache.duplicate(true)


static func _build_catalog_uncached() -> Array:
	var out: Array = []
	for job_id in JobDatabase.all_job_ids():
		if not _has_learnable(job_id):
			continue
		var name := String(JobDatabase.get_job(job_id).get("name", "")).strip_edges()
		if name.is_empty():
			continue          # nameless record — same hygiene rule as an empty learn list
		out.append({"id": job_id, "name": name})
	return _sorted(out)


## A job earns a row only if its skillset yields at least one JP-costed ability —
## the same chain the picker's commit walks, so a listed job can always be acted on.
static func _has_learnable(job_id: String) -> bool:
	return not AbilityDatabase.get_learnable_abilities_for_job(job_id).is_empty()


## Name ascending, job index as the stable tie-break — a total order despite the 19
## colliding names, so the six Squires group deterministically instead of scattering.
static func _sorted(rows: Array) -> Array:
	rows.sort_custom(func(a, b):
		if String(a["name"]) == String(b["name"]):
			return String(a["id"]).hex_to_int() < String(b["id"]).hex_to_int()
		return String(a["name"]) < String(b["name"]))
	return rows
