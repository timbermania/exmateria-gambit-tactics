class_name ProvisionalObjective
extends RolloutObjective

## THE PROVISIONAL OBJECTIVE — *kill the enemy, don't die*, hand-written, with no
## fit behind it and nothing in it to tune. ADR-0274, #1109.
##
## Stands in for [RolloutValueFunction] for the length of the rebalancing map
## (#1101). `f` was fit against a corpus generated BEFORE #939 changed the tempo
## ~48x, and #897's AI is the first thing to actually maximise it: it pays
## `mp_frac_self` +2.23, `hp_frac_self` +2.05 and `engage_self` +0.0495 per tile,
## so over a 400-tick horizon it rewards spending no MP, taking no damage and
## STANDING OFF. Refitting needs a corpus at the settled tempo, which does not
## exist until the numbers are dialed — after that map. So a referee run against
## `f` would measure the staleness rather than the balance.
##
## 🔴 IT IS DELIBERATELY CRUDE, AND THAT IS THE ARGUMENT FOR IT RATHER THAN AN
## APOLOGY. Two scale-free terms, equal weight, ZERO free parameters. There is
## nothing here to over-fit to numbers that are about to move, so nothing here
## has to be thrown away when they do — which is exactly what a "minimal refit"
## pulled into scope would have bought and then spent.
##
## 🔴 IT IS AN ORDERING, NOT A PROBABILITY, AND THE TERMINAL BONUS STILL
## DISAPPEARS. ADR-0253's case for `P(victory)` was that a hand-weighted score
## needs an invented weight big enough to make WINNING outrank HAVING MORE HP,
## and no principled value for it exists. This dodges that without a fit: the
## terminal verdicts take the OUTER [constant TERMINAL_BAND] of the range at each
## end, and every ongoing state is squeezed strictly inside them. A win is not
## weighted above an ongoing state, it is OUT OF THE BAND an ongoing state can
## reach. The residual weighting — the 50/50 between the two terms — orders
## ongoing states against each OTHER and can never reorder a win against one.
##
## 🔴 A TERMINAL VERDICT IS A BAND AND NOT A POINT, AND THAT WAS MEASURED THE
## HARD WAY. The first cut mapped every win to exactly 1.0 and every loss to
## exactly 0.0. Instrumented at Gariland with the AI on, the FIRST beat came back
## `result=TEAM_0_WINS` on all 64 candidate rows with `t1_alive=0` — the AI's team
## annihilated in every rollout — so all 64 tied at 0.0 and the beat held the
## incumbent by tie-break. `f` scored the same rows 0.001127 and 0.002705: also
## near-zero, but DISTINCT, so it could still rank them.
##
## That is not a cosmetic difference. An objective that is flat across lost
## positions makes the AI stop trying the moment a battle is decided, which
## SHORTENS the battle — and battle length is the quantity this whole map exists
## to measure (#1101). The instrument would have biased its own reading. So a
## terminal verdict carries a secondary ordering *inside* its band: a loss that
## ground the enemy down further ranks above one that did not, and a win with
## more health left ranks above a pyrrhic one. Dominance is untouched, because
## the bands do not overlap the ongoing range.

## The outer slice of the range at each end, reserved for terminal verdicts:
## wins in `[1 - TERMINAL_BAND, 1]`, losses in `[0, TERMINAL_BAND]`.
##
## Narrow because it is a TIE-BREAK, not a trade: no ordering inside a band may
## ever be worth as much as changing which band you land in. It is a partition of
## the range, not a weight — there is nothing here to tune toward a better AI.
const TERMINAL_BAND := 0.001
##
## 🔴 NO MP TERM, NO ENGAGE TERM, NO POWER-SHARE TERM, and each omission is a
## decision:
##
## - **MP** and **ENGAGE** are the two features whose fitted coefficients became
##   perverse instructions the moment something maximised them. An objective for
##   measuring BATTLE LENGTH AND LETHALITY that pays a unit to stand off would
##   measure its own instruction.
## - **`power_share`** is a function of the rosters' MAX HP, so it is constant
##   across a battle — and therefore constant across the K candidates of one
##   beat. It cannot rank anything; it only compares two battles, which is not
##   what a beat does.
##
## 🔴 IT READS `result`, WHICH `f` NEVER DOES — AND `result`'s ZERO IS A
## LEGITIMATE VERDICT. `RESULT_TEAM_0_WINS == 0`, so a result record that was
## never written reads as a team-0 win rather than as missing data. `R_TICKS` is
## written as `tick + 1` by `stage_victory`, so it is >= 1 for every record the
## shader has touched, and a record claiming tick 0 is refused instead of scored.
## Nothing else in the tree reads `result` off a possibly-unwritten slot, which
## is why the guard lives here and not in the packer.

## The id a run records. Bump the suffix if the FORMULA changes; a corpus scored
## by two different formulas under one name is unattributable.
const ID := "provisional-attrition-v1"

## How far clear of the terminal bands an ongoing state is held, so a terminal
## win strictly outranks the best ongoing position and a terminal loss strictly
## underranks the worst. 1e-6 is far below any ranking difference a beat produces
## and far above float64 noise on a mean of four seeds.
const ONGOING_MARGIN := 1e-6

## Every field this objective reads. Deliberately much shorter than `f`'s twelve.
## The `max_hp` pair is read only by the terminal tie-break, which needs a
## FRACTION of a known pool rather than a share — at a loss this team's HP is 0,
## so a share carries no information at all.
const REQUIRED_FIELDS := [
	"result", "ticks",
	"team0_hp", "team1_hp",
	"team0_max_hp", "team1_max_hp",
	"team0_alive", "team1_alive",
]


func id() -> String:
	return ID


## Always true. There is no artifact to fail to load — which is half of why this
## objective exists: it cannot be absent, stale or half-parsed.
func is_loaded() -> bool:
	return true


## UNCALIBRATED, and it says why rather than declining to answer.
##
## `H` under this objective is bounded by COST, not by a fit: a longer horizon
## resolves more of the battle, so more rows carry a terminal verdict and fewer
## rest on the two-term guess — strictly more information, with no knee to find.
## ADR-0256 dec. 6 already prices `H = 400` against a 250 ms cap, and that
## pricing is untouched by which objective reads the rows.
func horizon_stance() -> Dictionary:
	return {
		"kind": Horizon.UNCALIBRATED,
		"why": "hand-written: no H-sweep exists, so H is bounded by cost (ADR-0256 dec. 6) and not by a knee",
	}


## The value of `row` for `team`, in [0, 1].
func score(row: Dictionary, team: int) -> float:
	var missing := missing_record_fields(row, REQUIRED_FIELDS)
	if not missing.is_empty():
		push_error("[ProvisionalObjective] row has no '%s' — it is not a result record from RolloutHarness.run" % ", ".join(missing))
		return CANNOT_SCORE

	# `stage_victory` writes tick + 1, so 0 means the shader never wrote this
	# slot — and its zeroed `result` would otherwise read as a team-0 win.
	if int(row["ticks"]) <= 0:
		push_error("[ProvisionalObjective] a record at tick 0 was never written by stage_victory — its result field is zero, which spells TEAM_0_WINS")
		return CANNOT_SCORE

	var verdict := int(row["result"])
	var winner := -1
	if verdict == GPUBatchSimulator.RESULT_TEAM_0_WINS:
		winner = Team.TEAM_0
	elif verdict == GPUBatchSimulator.RESULT_TEAM_1_WINS:
		winner = Team.TEAM_1
	if winner >= 0:
		return _terminal(row, team, winner)
	# Mutual annihilation (or MAX_TICKS). Killed them AND died: exactly half the
	# objective met, and the one state the two terms cannot separate because both
	# teams' shares are undefined at once.
	if verdict == GPUBatchSimulator.RESULT_DRAW:
		return 0.5
	if verdict == GPUBatchSimulator.RESULT_ONGOING:
		return _ongoing(row, team)
	push_error("[ProvisionalObjective] result %d is not a verdict this kernel writes" % verdict)
	return CANNOT_SCORE


## A latched battle, ordered INSIDE its band by what it cost.
##
## The band is the verdict and the position inside it is the tie-break, so the
## only quantity needed is how much of the LOSER's pool the winner had to spend
## — read as the winner's remaining health fraction. A win keeping 90% of its
## health scores above one that scraped through; the mirrored loss scores below
## the loss that ground the winner down to 10%.
##
## `hp_frac` and not `hp_share`: at a latched battle the losing side's HP is 0, so
## every share is 1 or 0 and carries nothing. A fraction of a known pool is the
## only reading left, and `TEAM*_MAX_HP` sums ALL slots, living or not, so it is
## the same denominator before and after the battle.
func _terminal(row: Dictionary, team: int, winner: int) -> float:
	var w := "team0" if winner == Team.TEAM_0 else "team1"
	var kept := clampf(_frac(float(row[w + "_hp"]), float(row[w + "_max_hp"])), 0.0, 1.0)
	# `spent` is one number both perspectives read, which is what keeps the two
	# sides summing to 1: the winner sits `TERMINAL_BAND * spent` below the top and
	# the loser sits exactly that far above the bottom.
	var spent := 1.0 - kept
	if team == winner:
		return 1.0 - TERMINAL_BAND * spent
	return TERMINAL_BAND * spent


## The ongoing band: the mean of two mirrored shares, held strictly inside [0, 1].
##
## Both terms rise when the enemy loses and fall when we do, which is the whole
## objective in one sentence. They are SHARES rather than fractions of each
## team's own pool so that neither roster size nor total HP has to be known to
## compare two states of one battle.
##
## They are two terms and not one because HP alone cannot tell six units at half
## health from three corpses and three untouched units — the same `hp_share`, and
## in a game where a dead unit stops acting, very different positions.
func _ongoing(row: Dictionary, team: int) -> float:
	var s := "team0" if team == Team.TEAM_0 else "team1"
	var e := "team1" if team == Team.TEAM_0 else "team0"
	var hp_self := float(row[s + "_hp"])
	var hp_enemy := float(row[e + "_hp"])
	var alive_self := float(row[s + "_alive"])
	var alive_enemy := float(row[e + "_alive"])

	# EITHER share collapsing breaks the perspective invariant, not just both at
	# once: a term whose denominator is 0 contributes 0 to BOTH readings, so the
	# two perspectives sum to 0.5 instead of 1 and the enemy's loss stops being
	# this team's gain. Unreachable while a living unit has HP >= 1 and a wiped
	# battle latches to a verdict — which is exactly why it is asserted rather
	# than assumed.
	if hp_self + hp_enemy <= 0.0 or alive_self + alive_enemy <= 0.0:
		push_error("[ProvisionalObjective] an ONGOING record with no HP or nobody alive on either side — one share's denominator is 0, so the perspectives cannot mirror")
		return CANNOT_SCORE

	var hp_share := _frac(hp_self, hp_self + hp_enemy)
	var alive_share := _frac(alive_self, alive_self + alive_enemy)
	# Symmetric bounds, which is what keeps the perspectives summing to 1 even
	# when one of them is clamped: an ongoing state pinned to the floor has its
	# mirror pinned to the ceiling, and floor + ceiling is exactly 1.
	var lo := TERMINAL_BAND + ONGOING_MARGIN
	return clampf(0.5 * (hp_share + alive_share), lo, 1.0 - lo)
