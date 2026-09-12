extends Node
## JobCandidates guard — the Learn job-picker's full-CATALOG rules, the job-domain
## sibling of AbilityCandidatesTest (ADR-0197's scaffold shape one domain over).
## Pure, no GPU.
##
## build_catalog() is unit-independent and honors NO progression gate: it lists
## EVERY job in jobs.json that has at least one JP-costed learnable ability, so the
## picker's 11-row scroll/render pipeline is exercised against the real catalogue
## instead of the 13-ish jobs UnitProgression.get_unlocked_jobs() enumerates.
## Rows are {id, name} with `id` the HEX-STRING job index (the picker's key — the
## host reads progression numbers off it), name-sorted ascending with the job index
## as the stable tie-break.
##
## Expected literals below are derived INDEPENDENTLY from the asset data
## (jobs.json walked against AbilityDatabase.get_learnable_abilities_for_job), not
## recomputed from build_catalog:
##   160 jobs total (74 special + 20 generic_human + 66 monster); exactly 80 carry
##   >=1 learnable (56 special + 19 generic + 5 monster), so 80 are dropped. The
##   drop is DATA HYGIENE (an empty job would render a dead row), not a gate.
##
## The name-collision case the catalogue makes visible: 19 display names are shared
## by more than one job index. Six jobs are named "Squire" (01/02/03/04/07/4a) with
## genuinely different learn lists — the chapter/character Squires are separate job
## indices, which is why the index is the key and the tie-break must be total.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/JobCandidatesTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const JobCandidates = ExMateriaAlmanac.JobCandidates
const JobDatabase = ExMateriaAlmanac.JobDatabase



## Every job index named "Squire", ascending — the collision case, and the reason
## rows carry the index rather than leaning on the name.
const SQUIRE_IDS := ["01", "02", "03", "04", "07", "4a"]

## Jobs with NO learnable ability, dropped as hygiene. Sampled from the 80 excluded.
const EXCLUDED_IDS := ["00", "0a", "0e", "13", "31", "3e"]

## The 5 monster jobs that DO carry learnables (the other 61 monsters are dropped).
const MONSTER_LEARN_IDS := ["90", "91", "97", "99", "9a"]

var _passed := 0
var _failed := 0


func _ready() -> void:
	var rows := JobCandidates.build_catalog()
	_check_size(rows)
	_check_well_formed(rows)
	_check_sorted(rows)
	_check_squires(rows)
	_check_ultima_is_keyed_to_the_index()
	_check_hygiene(rows)
	_check_purity(rows)
	_check_cache_hands_out_private_copies()
	_check_cache_is_actually_used()

	if _failed > 0:
		print("[FAIL] JobCandidatesTest")
		get_tree().quit(1)
	else:
		print("[PASS] JobCandidatesTest: %d checks — full job catalogue + collision tie-break + hygiene" % _passed)
		get_tree().quit(0)


## Exactly the 80 learnable-bearing jobs, and MORE than the picker's visible window
## (the whole point of the scaffold — the scroll path gets exercised).
func _check_size(rows: Array) -> void:
	_expect(rows.size() == 80, "catalogue = 80 rows (the learnable-bearing jobs), got %d" % rows.size())
	_expect(rows.size() > JobPickerMenu.VISIBLE_ROWS,
		"catalogue must exceed the picker's %d visible rows so the scroll window is exercised"
			% JobPickerMenu.VISIBLE_ROWS)


func _check_well_formed(rows: Array) -> void:
	var ok := true
	var why := ""
	for r in rows:
		if not (r is Dictionary and r.has("id") and r.has("name")):
			ok = false
			why = "row is not {id,name}: %s" % [r]
			break
		if not (r["id"] is String) or String(r["id"]).is_empty():
			ok = false
			why = "id must be a non-empty hex STRING job index (the picker's key), got %s" % [r["id"]]
			break
		if String(r["name"]).strip_edges().is_empty():
			ok = false
			why = "blank name on job %s" % [r["id"]]
			break
	_expect(ok, "rows must all be {hex-string id, non-blank name} — %s" % why)


## Name ascending, JOB INDEX as the stable tie-break — total order despite 19
## colliding names (without the tie-break the six Squires would sort arbitrarily).
func _check_sorted(rows: Array) -> void:
	var ok := true
	for i in range(1, rows.size()):
		var pn := String(rows[i - 1]["name"])
		var cn := String(rows[i]["name"])
		if pn > cn:
			ok = false
			break
		if pn == cn and String(rows[i - 1]["id"]).hex_to_int() >= String(rows[i]["id"]).hex_to_int():
			ok = false
			break
	_expect(ok, "rows must be name-sorted ascending with the job index as tie-break")


## All six Squires survive as DISTINCT rows, adjacent, in ascending index order.
func _check_squires(rows: Array) -> void:
	var got := []
	for r in rows:
		if String(r["name"]) == "Squire":
			got.append(String(r["id"]))
	_expect(got == SQUIRE_IDS,
		"all six Squire job indices must appear as distinct rows in index order, want %s got %s"
			% [SQUIRE_IDS, got])
	# They are adjacent — the tie-break groups the collision, it does not scatter it.
	var first := _index_of_id(rows, SQUIRE_IDS[0])
	var contiguous := first >= 0
	for i in SQUIRE_IDS.size():
		if _index_of_id(rows, SQUIRE_IDS[i]) != first + i:
			contiguous = false
	_expect(contiguous, "the six Squire rows must be contiguous in the sorted catalogue")


## The key question the catalogue answers: Ultima is reachable because it hangs off a
## DIFFERENT job index, not because anything needed re-keying. Squire 03's skillset
## carries it; the generic Squire 4a's does not — same NAME, different learn list.
func _check_ultima_is_keyed_to_the_index() -> void:
	_expect(_learns("03", "Ultima"), "job 03 (Squire) must carry Ultima")
	_expect(not _learns("4a", "Ultima"), "generic Squire 4a must NOT carry Ultima")
	# ...and the two really are the same display name, which is what makes the index the key.
	_expect(String(JobDatabase.get_job("03").get("name", "")) == String(JobDatabase.get_job("4a").get("name", "")),
		"03 and 4a must share the display name 'Squire' — the collision the index disambiguates")


## Hygiene, not a gate: zero-learnable jobs are dropped; learnable-bearing MONSTER
## and SPECIAL jobs are kept (no kind filter — 'every option' means every option).
func _check_hygiene(rows: Array) -> void:
	for id in EXCLUDED_IDS:
		_expect(_index_of_id(rows, id) < 0,
			"job %s has no learnable ability and must be dropped" % id)
	for id in MONSTER_LEARN_IDS:
		_expect(_index_of_id(rows, id) >= 0,
			"monster job %s carries learnables and must be KEPT (no kind filter)" % id)
	# A special (story) job is in scope too — 07 reads as Delita's Squire.
	_expect(_index_of_id(rows, "07") >= 0, "special job 07 must be in the catalogue")
	# Every listed job really does carry at least one learnable.
	var barren := ""
	for r in rows:
		if AbilityDatabase.get_learnable_abilities_for_job(String(r["id"])).is_empty():
			barren = String(r["id"])
			break
	_expect(barren == "", "every catalogued job must carry >=1 learnable, got barren %s" % barren)


## Pure + unit-independent: repeated calls agree, and the rows carry NO progression
## numbers (the host reads Lv./Total/Next/Jp off the unit — the renderer contract).
func _check_purity(rows: Array) -> void:
	var again := JobCandidates.build_catalog()
	_expect(str(again) == str(rows), "build_catalog must be pure — two calls must agree")
	var leaked := ""
	for r in rows:
		for k in ["lv", "total", "next", "jp"]:
			if r.has(k):
				leaked = k
	_expect(leaked == "", "catalogue rows must carry no per-unit progression key, got '%s'" % leaked)


## The catalogue is MEMOIZED (build_catalog walks all 160 jobs asking AbilityDatabase for each
## one's learnables — 8.6 ms, and the Learn press paid it on every open). The cache is only
## safe if every caller gets its OWN copy: the picker assigns the result to `entries` and the
## host reads rows out of it, so a caller that sorted or spliced the shared answer in place
## would silently re-key every LATER open. Mutate a returned catalogue as hard as a caller
## plausibly could, then assert the next call is untouched.
func _check_cache_hands_out_private_copies() -> void:
	var pristine := JobCandidates.build_catalog()
	var mine := JobCandidates.build_catalog()
	_expect(str(mine) == str(pristine), "two calls must agree before any mutation")

	mine.reverse()                                  # re-order the array
	mine.remove_at(0)                               # drop a row
	if not pristine.is_empty():
		var row: Dictionary = JobCandidates.build_catalog()[0]
		row["name"] = "CLOBBERED"                   # write THROUGH into a row dictionary
		row["id"] = "ff"

	var after := JobCandidates.build_catalog()
	_expect(str(after) == str(pristine),
		"build_catalog must hand out a private copy — a caller's mutation leaked into the cache")
	_expect(after.size() == pristine.size(),
		"a caller removing a row must not shrink the next call (got %d, want %d)"
			% [after.size(), pristine.size()])
	var clobbered := ""
	for r in after:
		if String(r.get("name", "")) == "CLOBBERED" or String(r.get("id", "")) == "ff":
			clobbered = str(r)
	_expect(clobbered == "",
		"a caller writing into a returned ROW must not reach the cached row, found %s" % clobbered)


## ...and the cache is real: a warm call must be far cheaper than the cold walk, and dropping
## it must rebuild an identical answer (the JobDatabase.reload seam).
func _check_cache_is_actually_used() -> void:
	var _warm := JobCandidates.build_catalog()
	var best := INF
	for _i in range(5):
		var t := Time.get_ticks_usec()
		var r := JobCandidates.build_catalog()
		best = minf(best, float(Time.get_ticks_usec() - t) / 1000.0)
		r = r
	# Cold is ~8.6 ms; a warm call is the duplicate() alone (~0.1 ms). 3 ms is a wide,
	# jitter-proof band that still cannot be reached by the uncached 160-job walk.
	_expect(best <= 3.0,
		"a warm build_catalog must be a copy, not a rebuild — best-of-5 %.2f ms (cold walk is ~8.6 ms)" % best)

	var before := JobCandidates.build_catalog()
	JobCandidates.clear_cache()
	var rebuilt := JobCandidates.build_catalog()
	_expect(str(rebuilt) == str(before),
		"clear_cache() must rebuild an IDENTICAL catalogue — the cache would otherwise mask a data change")


func _learns(job_id: String, ability_name: String) -> bool:
	for a in AbilityDatabase.get_learnable_abilities_for_job(job_id):
		if String(a.name) == ability_name:
			return true
	return false


func _index_of_id(rows: Array, id: String) -> int:
	for i in rows.size():
		if String(rows[i].get("id", "")) == id:
			return i
	return -1


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
