class_name RolloutObjective
extends RefCounted

## WHAT THE ROLLOUT SEARCH MAXIMISES — the number a thinking beat ranks its
## candidates by, read off one `RolloutHarness.run` row.
##
## Two objectives ship, and they are NOT the same kind of object:
##
## - [RolloutValueFunction] — `f`, GambitBattle §8's fitted `P(victory)`. A
##   calibrated probability, logistic over the result record, refit from a
##   corpus (ADR-0253).
## - [ProvisionalObjective] — a hand-written ATTRITION ORDERING. Not a
##   probability, not fitted, and deliberately crude (ADR-0274).
##
## 🔴 THIS SUPERTYPE EXISTS BECAUSE ONE OF THEM IS STALE AND THE OTHER IS NOT
## CALIBRATED, SO A RUN HAS TO BE ABLE TO SAY WHICH ONE PRODUCED IT. `f` was fit
## before #939 changed the tempo ~48x and its coefficients pay a unit to spend no
## MP, take no damage and stand off; the refit needs a corpus at the settled
## tempo, which does not exist until the numbers are dialed. So the map's referee
## runs play against a stand-in — and a corpus whose objective is unrecorded is
## unattributable later, which is the whole reason [method id] is on the
## interface rather than in a comment.
##
## 🔴 EVERY OBJECTIVE IS PERSPECTIVE-COMPLEMENTARY: `v(state, TEAM_0) +
## v(state, TEAM_1) == 1`. ADR-0253 dec. 5's invariant, and it is not a property
## of the fit — it is a property of the FEATURES being per-team and mirrored, so
## a hand-written objective has to earn it the same way. A battle-wide term with
## no per-team split can say how DECIDED a battle is and never who is winning.
##
## 🔴 THE VALUE IS ALWAYS IN [0, 1] AND THE REFUSAL IS ALWAYS [constant
## CANNOT_SCORE]. Every value in [0, 1] is a legitimate answer for both members,
## so none of them can double as an error — an objective that reported 0.5 on a
## malformed row would rank a broken candidate exactly at the median and nothing
## downstream could tell.

## Team ids, as the result record's field names spell them.
enum Team { TEAM_0 = 0, TEAM_1 = 1 }

## What an objective can say about the horizon `H` it is about to be read at.
##
## `CALIBRATED` is a claim that an H-sweep chose this `H`; `UNCALIBRATED` is the
## explicit absence of one. There is no third state and no default: a guard that
## passes because there was nothing to check against is worse than no guard, so
## [method RolloutDriver.check_horizon] refuses to be silent about either.
enum Horizon { CALIBRATED, UNCALIBRATED }

## The one value [method score] returns when it cannot score. Outside [0, 1] on
## purpose — see the class header.
const CANNOT_SCORE := -1.0


## This objective's name, as a run records it. Stable across refits of the SAME
## objective; a different objective takes a different id.
func id() -> String:
	push_error("[RolloutObjective] id() was not overridden by %s" % get_script().resource_path)
	return ""


## Is this objective usable? A caller that ranks with an unusable objective ranks
## by a constant, every candidate ties, and the beat spends the whole horizon to
## return the incumbent by tie-break — an expensive way to do nothing, and
## indistinguishable in the log from a search that considered its options.
func is_loaded() -> bool:
	return false


## The value of `row` for `team`, in [0, 1], or [constant CANNOT_SCORE].
func score(_row: Dictionary, _team: int) -> float:
	push_error("[RolloutObjective] score() was not overridden")
	return CANNOT_SCORE


## The calibration block, empty for an objective that has none.
func calibration() -> Dictionary:
	return {}


## What this objective can say about the horizon it is read at:
## `{"kind": Horizon, "knee": int, "why": String}`. `knee` is present only for
## `CALIBRATED`.
func horizon_stance() -> Dictionary:
	return {
		"kind": Horizon.UNCALIBRATED,
		"why": "this objective declares no horizon stance",
	}


## Rank `RolloutHarness.run`'s rows for `team`, best first.
##
## Averages over the M common-random-number seeds per candidate, which is the
## whole reason the seeds are there: two candidates under seed m faced identical
## luck, so the mean over seeds is the candidate's own contribution with the luck
## averaged out. Ranking individual slots instead would hand the win to whichever
## candidate drew the kindest seed.
##
## 🔴 SHARED BY BOTH OBJECTIVES, AND THAT IS THE POINT OF THE SUPERTYPE. The
## averaging, the refusal filter and the tie-break are properties of the SEARCH,
## not of what it maximises — a second copy would be a second place for the
## incumbent's tie-break to be got wrong.
func rank_candidates(rows: Array, team: int) -> Array:
	var totals: Dictionary = {}
	var counts: Dictionary = {}
	for row in rows:
		var candidate := int((row as Dictionary).get("candidate", -1))
		if candidate < 0:
			continue
		var value := score(row, team)
		if value < 0.0:
			continue
		totals[candidate] = float(totals.get(candidate, 0.0)) + value
		counts[candidate] = int(counts.get(candidate, 0)) + 1
	var out: Array = []
	for candidate in totals:
		out.append({
			"candidate": candidate,
			"value": float(totals[candidate]) / float(counts[candidate]),
			"seeds": counts[candidate],
		})
	# Ties break toward the LOWER candidate index, which makes candidate 0 — the
	# unmutated incumbent (ADR-0246 dec. 2) — win a tie. Without that, an edit
	# scoring identically to leaving the gambits alone would still be applied,
	# and the AI would churn a working posture every turn for nothing.
	out.sort_custom(func(a, b):
		if a["value"] == b["value"]:
			return a["candidate"] < b["candidate"]
		return a["value"] > b["value"])
	return out


## `num / den`, and 0 rather than a NaN when the denominator is 0.
static func _frac(num: float, den: float) -> float:
	return num / den if den > 0.0 else 0.0


## The result-record keys `row` is missing, empty when it carries them all.
##
## Named rather than counted so the error says WHICH field is absent: the rows
## reaching an objective come from `RolloutHarness._rows_from_results`, which
## hands out whatever the generated `ResultField` enum declares, so a missing key
## means the record moved underneath a hand-written key list.
static func missing_record_fields(row: Dictionary, keys: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for key in keys:
		if not row.has(key):
			out.append(String(key))
	return out
