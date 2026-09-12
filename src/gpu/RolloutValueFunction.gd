class_name RolloutValueFunction
extends RolloutObjective

## GambitBattle §8's value function `f`, read from its calibrated artifact.
##
## `f` answers ONE question about a rollout slot: **what is the probability that
## this team wins from here?** Not "how good does this look" — an actual
## probability, fit against recorded outcomes of battles played to completion by
## `tools/rollout_corpus.tscn` and `tools/fit_value_function.py`.
##
## 🔴 THAT IT IS A PROBABILITY IS THE POINT, NOT AN IMPLEMENTATION DETAIL. §8
## chose `P(victory)` over a hand-weighted score so that **the terminal win/loss
## bonus disappears**. A score built from HP and standing counts needs some
## invented weight big enough to make winning outrank having more HP, and that
## weight is unknowable — too small and the AI trades the win for damage, too
## large and every non-terminal difference is noise. A probability is already
## calibrated and already comparable, so ranking candidates is just comparing
## numbers in [0, 1].
##
## 🔴 IT SCORES A RESULT RECORD, NOT A BATTLE. The input is one row from
## `RolloutHarness.run`, which is one slice of the bulk result-buffer read.
## ADR-0237 dec. 7 measured the alternative and this class exists downstream of
## that measurement: a scorer that reached back into unit blocks would cost
## 33-51 ms per feature across a 1024-battle fleet, as much as running the whole
## horizon. Every feature it needs is in the record.
##
## 🔴 THE HARNESS DOES NOT CALL THIS, AND THAT IS DELIBERATE. ADR-0246 dec. 6
## keeps ranking out of `RolloutHarness` so the H-sweep can vary the scorer
## without touching the machine that produces the rows. #897 is what joins them.
##
## Not calibrated for the shipping game yet. §8 asks for **one refit** after the
## real AI ships, because the AI changes the distribution of positions it is
## asked about — one refit, not a loop; self-play refinement is a research
## project and not this ticket.
##
## 🔴 AND UNTIL THAT REFIT LANDS, THIS IS NOT THE OBJECTIVE THE SEARCH RUNS.
## #897's AI is the first thing to actually maximise `f`, and what it maximises
## is a fit taken before #939 changed the tempo ~48x: `mp_frac_self` +2.23,
## `hp_frac_self` +2.05, `engage_self` +0.0495 per tile — spend no MP, take no
## damage, stand off. [ProvisionalObjective] stands in for the length of the
## rebalancing map (#1101) and ADR-0274 says why. This class stays loadable,
## stays guarded and stays the destination; it is the ARTIFACT that is stale, so
## the refit is the only thing owed here.

const ARTIFACT_PATH := "res://assets/gambit/rollout_value_function.json"

## The id a run records when this objective produced it, when the artifact does
## not name itself. Bump the suffix when the FEATURE SET changes — a refit of the
## same features is the same objective and keeps the name; a different feature
## set is a different function wearing it.
const DEFAULT_ID := "fitted-logistic-v1"

var _intercept: float = 0.0
## feature name -> coefficient, in logits per unit of the feature.
var _coefficients: Dictionary = {}
var _features: PackedStringArray = PackedStringArray()
var _loaded: bool = false
var _calibration: Dictionary = {}
var _id: String = DEFAULT_ID


func _init(path: String = ARTIFACT_PATH) -> void:
	_loaded = _load(path)


## Did the artifact load? A caller that ranks with an unloaded value function is
## ranking by a constant, and every candidate ties — so this is worth checking
## rather than trusting.
func is_loaded() -> bool:
	return _loaded


## The artifact's own name for itself, falling back to [constant DEFAULT_ID].
## Read from the file rather than hard-coded so a refit that changes the feature
## set can rename the objective in the one place that already has to change.
func id() -> String:
	return _id


## CALIBRATED, at the knee its own H-sweep chose.
func horizon_stance() -> Dictionary:
	var knee: Variant = _calibration.get("knee_horizon", null)
	if knee == null:
		return {
			"kind": Horizon.UNCALIBRATED,
			"why": "the artifact carries no knee_horizon — it is a fit with its H-sweep missing, not a hand-written objective",
		}
	return {
		"kind": Horizon.CALIBRATED,
		"knee": int(knee),
		"why": "ADR-0253 dec. 9's knee, chosen by the H-sweep in this artifact's calibration block",
	}


## The calibration block: corpus size, held-out log-loss, the H-sweep and the
## knee it chose. #897 reads `knee_horizon` for its starting `H`.
func calibration() -> Dictionary:
	return _calibration.duplicate(true)


func features() -> PackedStringArray:
	return _features.duplicate()


func coefficient(feature: String) -> float:
	return float(_coefficients.get(feature, 0.0))


## P(victory) for `team`, from one `RolloutHarness.run` row.
##
## Returns -1.0 when it cannot score, and never a plausible-looking 0.5. A
## probability is the return type, so every value in [0, 1] is a legitimate
## answer and none of them can double as an error — a scorer that reported 0.5
## on a malformed row would rank a broken candidate exactly at the median and
## nothing downstream could tell.
func score(row: Dictionary, team: int) -> float:
	if not _loaded:
		return CANNOT_SCORE
	var vector := feature_vector(row, team)
	if vector.is_empty():
		return CANNOT_SCORE
	var logit := _intercept
	for name in _features:
		logit += float(_coefficients.get(name, 0.0)) * float(vector.get(name, 0.0))
	return 1.0 / (1.0 + exp(-clampf(logit, -30.0, 30.0)))


## The feature vector for one record row, seen from `team`'s side.
##
## Must agree EXACTLY with `features_from` in `tools/fit_value_function.py`.
## Coefficients fitted against one definition and applied to another are not
## wrong in any way that shows: every score stays in [0, 1], every candidate
## still ranks, and the AI simply plays worse than its calibration says it
## should. `RolloutValueFunctionTest` pins the two against a shared fixture.
func feature_vector(row: Dictionary, team: int) -> Dictionary:
	var s := "team0" if team == Team.TEAM_0 else "team1"
	var e := "team1" if team == Team.TEAM_0 else "team0"
	var missing := missing_record_fields(row, [
		s + "_hp", e + "_hp", s + "_max_hp", e + "_max_hp",
		s + "_alive", e + "_alive", s + "_mp", e + "_mp",
		s + "_max_mp", e + "_max_mp", s + "_engage", e + "_engage"])
	if not missing.is_empty():
		push_error("[RolloutValueFunction] row has no '%s' — it is not a result record from RolloutHarness.run" % ", ".join(missing))
		return {}

	var hp_self := float(row[s + "_hp"])
	var hp_enemy := float(row[e + "_hp"])
	var pool_self := float(row[s + "_max_hp"])
	var pool_enemy := float(row[e + "_max_hp"])
	return {
		"hp_frac_self": _frac(hp_self, pool_self),
		"hp_frac_enemy": _frac(hp_enemy, pool_enemy),
		"hp_share_self": _frac(hp_self, hp_self + hp_enemy),
		"hp_share_enemy": _frac(hp_enemy, hp_self + hp_enemy),
		"power_share_self": _frac(pool_self, pool_self + pool_enemy),
		"power_share_enemy": _frac(pool_enemy, pool_self + pool_enemy),
		"alive_self": float(row[s + "_alive"]),
		"alive_enemy": float(row[e + "_alive"]),
		"mp_frac_self": _frac(float(row[s + "_mp"]), float(row[s + "_max_mp"])),
		"mp_frac_enemy": _frac(float(row[e + "_mp"]), float(row[e + "_max_mp"])),
		"engage_self": _frac(float(row[s + "_engage"]), float(row[s + "_alive"])),
		"engage_enemy": _frac(float(row[e + "_engage"]), float(row[e + "_alive"])),
	}


func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("[RolloutValueFunction] no artifact at %s — regenerate it with tools/fit_value_function.py" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[RolloutValueFunction] %s is not a JSON object" % path)
		return false
	var data: Dictionary = parsed
	if not data.has("coefficients") or not data.has("features"):
		push_error("[RolloutValueFunction] %s has no coefficients/features" % path)
		return false

	_intercept = float(data.get("intercept", 0.0))
	_coefficients = data["coefficients"]
	_features = PackedStringArray()
	for name in data["features"]:
		_features.append(String(name))
	_calibration = data.get("calibration", {})
	_id = String(data.get("objective", DEFAULT_ID))

	# Every declared feature must carry a coefficient. A feature list and a
	# coefficient map are TWO LISTS, and a name in one and not the other scores
	# silently as zero — the term simply stops existing, every score stays in
	# [0, 1], and nothing downstream can tell. #895's own lesson.
	for name in _features:
		if not _coefficients.has(name):
			push_error("[RolloutValueFunction] feature '%s' has no coefficient in %s" % [name, path])
			return false
	return true
