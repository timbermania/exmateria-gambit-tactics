#!/usr/bin/env python3
"""Fit GambitBattle §8's value function `f`, and print the H-sweep table.

`f` predicts **P(victory)** for the team whose perspective it is taken from.
That is the whole reason §8 chose a probability over a hand-weighted score: the
terminal win/loss bonus disappears, because the score already IS the probability
of winning — calibrated, comparable across positions, and needing no invented
weight to make winning outrank having more HP.

**H and f are substitutes.** At `H -> infinity` no formula is needed (you have
observed the winner); at `H -> 0` the formula carries everything. So `(H, f)` is
one joint choice trading compute against predictive error, and the primary
deliverable here is not the coefficients — it is the **accuracy-vs-cost table
across H**, read under the wall-clock cap from the budget measurement.

Inputs
------
The corpus written by `tools/rollout_corpus.tscn`: battles played to completion
on the GPU, sampled on a fixed tick grid, every sample labelled with its own
battle's eventual winner. One corpus at `stride = 100` serves every `H` that is
a multiple of 100, because a decision point `D` and its horizon state `D + H`
are both on the grid.

Outputs
-------
- the H-sweep table on stdout, cost axis joined from a bench log
- the fitted coefficients as a committed JSON artifact, the same pattern as
  `deployment_zones.json` / `battle_conditionals.json`

Usage
-----
Note `--project tools`, which the bare `uv run python tools/...` in CLAUDE.md
does not carry. `uv` discovers a project by walking UP from the working
directory, and `godot-learning/` has no `pyproject.toml` of its own, so from
there it finds the MONOREPO root and `numpy` — declared in `tools/pyproject.toml`
— is not in the environment. Every stdlib-only tool works either way, which is
why the short form reads as correct until the first tool with a dependency.

    uv run --project tools python tools/fit_value_function.py
    uv run --project tools python tools/fit_value_function.py --cost-log tools/logs/rollout_horizon.log
    uv run --project tools python tools/fit_value_function.py --check   # 1 if stale
"""

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CORPUS = ROOT / "tools" / "logs" / "rollout_corpus.csv"
# ADR-0132: an asset store is named for the SYSTEM THAT READS IT, never for
# where the bytes came from. The reader is the gambit-battle AI
# (`src/gpu/RolloutValueFunction.gd`), so the store is `assets/gambit/` — and a
# small committed JSON table is exactly the tracked half of that ADR's split.
DEFAULT_ARTIFACT = ROOT / "assets" / "gambit" / "rollout_value_function.json"
# The cross-language pin lives with the test that reads it, not with the
# artifact: it is a fixture, not game data, and nothing at runtime loads it.
DEFAULT_FIXTURE = ROOT / "tests" / "fixtures" / "rollout_value_function_cases.json"

# GambitBattle §8's sweep. Every entry must be a multiple of the corpus stride.
DEFAULT_HORIZONS = [100, 200, 400, 800]

# The four feature families §8 names, each split into a self/enemy pair so the
# vector MIRRORS: swap the team roles and it describes the same battle from the
# other side. A feature with no mirror can say how decided a battle is but never
# who is winning, and mirrored training rows drive its coefficient to zero.
#
# 🔴 THE `*_share_*` PAIRS ARE A FIX FOR A MEASURED DEFECT, NOT AN EXTRA. The
# first fit ran the four families alone and scored 0.7210 in the early stratum
# against a base-rate model's 0.6931 — WORSE THAN A COIN FLIP, and confidently
# so. The cause is that a fraction normalises absolute power away: at full
# health a 262-HP team and a 1690-HP team both read `hp_frac = 1.0`, so early on
# the only thing left for the model to look at is the standing count, and it
# duly learned "the bigger team wins" — which is false when the small team is
# the strong one. The shares put relative power back where the model can see it.
# §8's own rule for exactly this: the fix is A TERM, NOT A WEIGHT.
FEATURES = [
    "hp_frac_self",
    "hp_frac_enemy",
    "hp_share_self",
    "hp_share_enemy",
    "power_share_self",
    "power_share_enemy",
    "alive_self",
    "alive_enemy",
    "mp_frac_self",
    "mp_frac_enemy",
    "engage_self",
    "engage_enemy",
]

# Strata by REMAINING battle length, in ticks. §8 is explicit that a predictor
# scored across all states looks excellent by nailing trivially-decided endgames
# while being useless in the mid-game where the decisions actually are.
STRATA = [
    ("endgame   (<500)", 0, 500),
    ("late      (500-1500)", 500, 1500),
    ("mid       (1500-3500)", 1500, 3500),
    ("early     (>=3500)", 3500, 10**9),
]

RESULT_ONGOING = -1
RESULT_TEAM_0_WINS = 0
RESULT_TEAM_1_WINS = 1


class FitError(Exception):
    pass


# ---------------------------------------------------------------- corpus ----


def load_corpus(path):
    """Corpus rows, as a list of dicts of ints."""
    if not path.exists():
        raise FitError(
            f"no corpus at {path} — generate one first:\n"
            f"  godot --path . tools/rollout_corpus.tscn"
        )
    with path.open(newline="") as fh:
        rows = [{k: int(v) for k, v in row.items()} for row in csv.DictReader(fh)]
    if not rows:
        raise FitError(f"{path} has a header and no rows")
    return rows


def _frac(num, den):
    return float(num) / float(den) if den > 0 else 0.0


def features_from(row, perspective):
    """The feature vector for one sample, seen from `perspective`'s side.

    Every term is a FRACTION or a per-unit MEAN, never a raw sum, so two battles
    with different rosters are comparable. A raw MP total says more about how
    many mages were seated than about who is winning.
    """
    s, e = (0, 1) if perspective == 0 else (1, 0)
    hp_self, hp_enemy = row[f"team{s}_hp"], row[f"team{e}_hp"]
    pool_self, pool_enemy = row[f"team{s}_max_hp"], row[f"team{e}_max_hp"]
    return {
        "hp_frac_self": _frac(hp_self, pool_self),
        "hp_frac_enemy": _frac(hp_enemy, pool_enemy),
        # Who is ahead in ABSOLUTE health, not in fraction of their own bar. The
        # fractions cannot tell a strong team from a weak one at full health.
        "hp_share_self": _frac(hp_self, hp_self + hp_enemy),
        "hp_share_enemy": _frac(hp_enemy, hp_self + hp_enemy),
        # The rosters' relative POWER, constant over a battle: which side was
        # stronger to begin with, independent of what has happened since.
        "power_share_self": _frac(pool_self, pool_self + pool_enemy),
        "power_share_enemy": _frac(pool_enemy, pool_self + pool_enemy),
        "alive_self": float(row[f"team{s}_alive"]),
        "alive_enemy": float(row[f"team{e}_alive"]),
        "mp_frac_self": _frac(row[f"team{s}_mp"], row[f"team{s}_max_mp"]),
        "mp_frac_enemy": _frac(row[f"team{e}_mp"], row[f"team{e}_max_mp"]),
        # Mean distance per living unit, so a big team is not automatically
        # "further away" than a small one.
        "engage_self": _frac(row[f"team{s}_engage"], row[f"team{s}_alive"]),
        "engage_enemy": _frac(row[f"team{e}_engage"], row[f"team{e}_alive"]),
    }


def label_for(row, perspective):
    """1 if `perspective` won that battle, 0 if it lost, None for a draw.

    A draw is DROPPED rather than scored 0.5. The model is binary, and a
    half-label is a third outcome smuggled into a two-outcome fit; the count is
    reported instead so a corpus that is mostly draws cannot pass unnoticed.
    """
    result = row["terminal_result"]
    if result == RESULT_TEAM_0_WINS:
        return 1 if perspective == 0 else 0
    if result == RESULT_TEAM_1_WINS:
        return 1 if perspective == 1 else 0
    return None


def build_design(rows):
    """(X, y, groups, ticks_remaining) over BOTH perspectives of every sample.

    `groups` is the battle each row came from. Every split downstream is by
    group, never by row: samples from one battle share a label and a roster, so
    a row-wise split puts near-duplicates on both sides and reports a score the
    model did not earn.
    """
    xs, ys, groups, remaining, draws = [], [], [], [], 0
    for row in rows:
        for perspective in (0, 1):
            y = label_for(row, perspective)
            if y is None:
                draws += 1
                continue
            feats = features_from(row, perspective)
            xs.append([feats[name] for name in FEATURES])
            ys.append(y)
            groups.append((row["round"], row["battle"]))
            remaining.append(row["ticks_remaining"])
    if not xs:
        raise FitError("every corpus row was a draw — nothing to fit")
    return (
        np.asarray(xs, dtype=float),
        np.asarray(ys, dtype=float),
        groups,
        np.asarray(remaining, dtype=int),
        draws,
    )


# --------------------------------------------------------------- the fit ----


def _with_intercept(x):
    return np.hstack([np.ones((x.shape[0], 1)), x])


def fit_logistic(x, y, l2=1e-3, iters=100, tol=1e-10):
    """Newton / IRLS with a small ridge. Returns (intercept, coefficients).

    Ridged because two of §8's features are near-collinear in a decided
    position — a team at 0 HP also has 0 standing units — and an unpenalised
    Newton step on a separable subset runs the coefficients off to infinity.
    """
    design = _with_intercept(x)
    w = np.zeros(design.shape[1])
    penalty = l2 * np.eye(design.shape[1])
    penalty[0, 0] = 0.0  # never penalise the intercept
    for _ in range(iters):
        p = 1.0 / (1.0 + np.exp(-np.clip(design @ w, -30, 30)))
        weights = np.clip(p * (1.0 - p), 1e-9, None)
        gradient = design.T @ (p - y) + penalty @ w
        hessian = (design * weights[:, None]).T @ design + penalty
        step = np.linalg.solve(hessian, gradient)
        w = w - step
        if np.max(np.abs(step)) < tol:
            break
    return float(w[0]), w[1:].copy()


def predict(intercept, coefficients, x):
    return 1.0 / (1.0 + np.exp(-np.clip(intercept + x @ coefficients, -30, 30)))


def log_loss(y, p, eps=1e-12):
    """§8's metric, and NOT accuracy.

    Accuracy cannot tell a confidently wrong predictor from a hedging one: both
    can sit at 70%, and only one of them is safe to act on at a decision point.
    """
    p = np.clip(p, eps, 1.0 - eps)
    return float(-np.mean(y * np.log(p) + (1.0 - y) * np.log(1.0 - p)))


def split_by_group(groups, holdout=0.25, seed=12345):
    """Boolean train mask, split on whole battles."""
    unique = sorted(set(groups))
    rng = np.random.default_rng(seed)
    shuffled = list(unique)
    rng.shuffle(shuffled)
    n_test = max(1, int(len(shuffled) * holdout))
    test = set(shuffled[:n_test])
    return np.asarray([g not in test for g in groups], dtype=bool)


# ------------------------------------------------------------- the sweep ----


def load_cost_axis(path):
    """horizon -> measured thinking-beat milliseconds, from a bench log.

    The cost axis is MEASURED, never assumed. ADR-0237 published one, but #896
    widened the result record `stage_victory` writes every tick, so those numbers
    describe a shader that no longer exists. Re-take it with:

        for H in 100 200 400 800; do
            godot --path . tests/GPURolloutBudgetBench.tscn -- \\
                battles=256 units=12 horizon=$H
        done > tools/logs/rollout_horizon.log

    Read from the bench's own `BENCH_ROW` lines rather than its CSV, because the
    CSV carries no horizon column and is overwritten per run.

    🔴 THE COST IS `fill + run + results`, NOT THE BENCH'S OWN `beat_ms`. That
    field sums the per-battle `read_unit_column` scorer, which ADR-0237 dec. 7
    exists to REJECT — 33-51 ms across 1024 battles, as much as the whole
    horizon, for one feature. The shipped scorer is the bulk read of the result
    buffer (`results_ms`, ~0.11 ms), so using `beat_ms` here would price a
    thinking beat against a scorer nothing is going to use, and would flatten
    the H axis by burying it under a constant.
    """
    if path is None or not Path(path).exists():
        return {}
    out = {}
    for line in Path(path).read_text().splitlines():
        if not line.startswith("BENCH_ROW "):
            continue
        fields = {}
        for token in line.split()[1:]:
            if "=" in token:
                key, value = token.split("=", 1)
                fields[key] = value
        try:
            horizon = int(fields["horizon"])
            out[horizon] = (
                float(fields["fill_ms"])
                + float(fields["run_ms"])
                + float(fields["results_ms"])
            )
        except (KeyError, ValueError):
            continue
    return out


def common_decision_points(rows, horizons, train_groups):
    """Held-out decision points that have a landed state for EVERY horizon.

    🔴 EVERY HORIZON MUST BE SCORED ON THE SAME DECISION POINTS. Taking each
    horizon's pairs independently silently changes the population underneath the
    table: a long horizon can only pair a decision point far enough from the end
    of its battle, so the H=800 column would be scored on earlier, longer,
    harder positions than the H=100 column. The losses would then differ for two
    reasons at once — the horizon, and the rows — and the table could not
    attribute the difference to either. Restricting to the common set makes the
    horizon the only thing that varies.
    """
    by_battle = {}
    for row in rows:
        by_battle.setdefault((row["round"], row["battle"]), {})[row["tick"]] = row
    reach = max(horizons)
    points = []
    for key, states in by_battle.items():
        if key in train_groups:
            continue
        for tick, decision in states.items():
            if all(tick + h in states for h in horizons if h > 0) and tick + reach in states:
                points.append((states, tick, decision))
    return points


def _score_states(states_at, intercept, coefficients):
    xs, ys = [], []
    for landed in states_at:
        for perspective in (0, 1):
            y = label_for(landed, perspective)
            if y is None:
                continue
            xs.append([features_from(landed, perspective)[n] for n in FEATURES])
            ys.append(y)
    if not xs:
        return None, 0
    x = np.asarray(xs, dtype=float)
    y = np.asarray(ys, dtype=float)
    return log_loss(y, predict(intercept, coefficients, x)), len(ys)


def sweep(rows, intercept, coefficients, train_groups, horizons, costs):
    """The accuracy-vs-cost table, on held-out battles and a common row set.

    `H = 0` is included as the reference end of §8's trade — the formula alone,
    read at the decision point, simulating nothing. Without it the table cannot
    say what the horizon BUYS, only how the horizons compare to each other.
    """
    points = common_decision_points(rows, horizons, train_groups)
    table = []
    for horizon in [0] + list(horizons):
        landed = [states[tick + horizon] for states, tick, _ in points]
        loss, n = _score_states(landed, intercept, coefficients)
        table.append(
            {
                "horizon": horizon,
                "n": n,
                "log_loss": loss,
                # H=0 runs no ticks: it pays the fill and the bulk read only.
                # Interpolating that from the bench's smallest horizon would be
                # inventing a measurement, so it stays blank.
                "beat_ms": costs.get(horizon),
            }
        )
    return table


def marginal_returns(table):
    """(horizon, log-loss gain per extra millisecond) for each step of the table."""
    scored = [r for r in table if r.get("n") and r.get("beat_ms")]
    out = []
    for prev, cur in zip(scored, scored[1:]):
        d_ms = cur["beat_ms"] - prev["beat_ms"]
        if d_ms <= 0:
            continue
        out.append((cur["horizon"], (prev["log_loss"] - cur["log_loss"]) / d_ms))
    return out


# A step returning less than this share of the BEST step's rate is past the knee.
KNEE_RETENTION = 0.2

# ADR-0237 dec. 6: §7 forks the LIVE battle at an enemy turn — units already
# engaged, some already dead — which is the expensive regime. A fresh-fork bench
# row is a FLOOR, not an expectation; budget against roughly twice it. Applying
# this is the difference between choosing a horizon the game can afford and
# choosing one the bench can.
FORK_COST_FACTOR = 2.0

# The wall-clock a thinking beat may take, in milliseconds, at the real forked
# cost. ADR-0237 publishes no cap — dec. 8 is explicit that a discovered ceiling
# belongs in an ADR-0068 `static var` set by whoever wires the AI (#897), and
# shipping one here would ship a number nobody chose. This is a REPORTING
# parameter for the sweep, not a published ceiling: dec. 5 measures the starting
# shape's beat at 64.7 ms and says a cinematic focus beat can hold that several
# times over, so a few multiples of it is the defensible reading.
DEFAULT_CAP_MS = 200.0


def affordable(table, cap_ms):
    """Rows whose FORKED beat fits the cap. H=0 is always affordable."""
    out = []
    for row in table:
        if row.get("beat_ms") is None:
            out.append(row)
        elif row["beat_ms"] * FORK_COST_FACTOR <= cap_ms:
            out.append(row)
    return out


def knee(table):
    """The largest horizon still buying a worthwhile share of the best step's rate.

    "Knee" means the point where marginal return collapses, so the rule has to be
    about the RATE and not about the level. An earlier version returned the last
    horizon whose step was merely an improvement at all, which selects the
    largest horizon in any monotone table — it picked H=800 off a step that
    bought 0.0022 of log-loss for 241 ms, a rate 22x worse than the step before
    it, which is the definition of past the knee rather than at it.
    """
    steps = marginal_returns(table)
    if not steps:
        return None
    best_rate = max(rate for _, rate in steps)
    if best_rate <= 0:
        return None
    chosen = None
    for horizon, rate in steps:
        if rate >= best_rate * KNEE_RETENTION:
            chosen = horizon
        else:
            break
    return chosen


# ------------------------------------------------------------- reporting ----


def report_strata(y, p, remaining, indent="  "):
    lines = []
    for name, lo, hi in STRATA:
        mask = (remaining >= lo) & (remaining < hi)
        if not mask.any():
            lines.append(f"{indent}{name:<24} (no samples)")
            continue
        base = float(y[mask].mean())
        # The always-predict-the-base-rate model. A stratum where `f` cannot beat
        # it is a stratum `f` knows nothing about, however good the total looks.
        baseline = log_loss(y[mask], np.full(mask.sum(), max(min(base, 1 - 1e-9), 1e-9)))
        lines.append(
            f"{indent}{name:<24} n={mask.sum():>7}  base_rate={base:.3f}  "
            f"log_loss={log_loss(y[mask], p[mask]):.4f}  (base_rate model {baseline:.4f})"
        )
    return lines


## The precision the artifact SHIPS at. Everything downstream must use the
## rounded values, not the raw fit — see `shipped_coefficients`.
ARTIFACT_PRECISION = 6


def shipped_coefficients(intercept, coefficients):
    """The fit as it will actually be READ, rounded exactly as the artifact is.

    🔴 THE FIXTURE MUST BE BUILT FROM THESE, NOT FROM THE RAW FIT. The artifact
    rounds to `ARTIFACT_PRECISION`, so GDScript scores with rounded coefficients
    while an unrounded fixture expects scores from full-precision ones. That
    disagreement measured 6.4e-7 — under the test's 1e-6 tolerance, so it passed,
    but it consumed most of the budget and left the cross-language pin far
    blunter than its tolerance implies. Rounding both sides once takes the
    disagreement to ~1e-9 and gives the arm back its sensitivity.
    """
    return (
        round(intercept, ARTIFACT_PRECISION),
        np.asarray(
            [round(float(c), ARTIFACT_PRECISION) for c in coefficients], dtype=float
        ),
    )


def build_fixture(rows, intercept, coefficients, count=24):
    """Cases pinning THIS scorer against `src/gpu/RolloutValueFunction.gd`.

    🔴 THE TWO FEATURE BUILDERS ARE THE SAME FUNCTION WRITTEN TWICE, IN TWO
    LANGUAGES, AND NOTHING ELSE CAN CATCH THEM DIVERGING. Coefficients fitted
    against one definition and applied to another fail invisibly: every score is
    still a probability in [0, 1], every candidate still ranks, the AI just
    plays worse than its calibration says it does. There is no crash and no
    wrong-looking number to notice.

    So the fixture carries the INPUT ROW and the EXPECTED SCORE, not the feature
    vector alone — a fixture of vectors would pin the features while leaving the
    intercept and the coefficient lookup unpinned, and those are half the
    arithmetic.

    Cases are spread evenly across the corpus rather than taken off the front,
    which would sample one round's opening ticks and miss every decided
    position.
    """
    if not rows:
        return {"cases": []}
    step = max(1, len(rows) // count)
    cases = []
    for row in rows[::step][:count]:
        record = {k: v for k, v in row.items() if k not in ("round", "battle", "tick")}
        cases.append(
            {
                "row": record,
                "scores": {
                    str(team): round(
                        float(
                            predict(
                                intercept,
                                coefficients,
                                np.asarray(
                                    [[features_from(row, team)[n] for n in FEATURES]],
                                    dtype=float,
                                ),
                            )[0]
                        ),
                        9,
                    )
                    for team in (0, 1)
                },
            }
        )
    return {
        "_comment": (
            "Generated by tools/fit_value_function.py. Pins "
            "src/gpu/RolloutValueFunction.gd against the Python scorer that "
            "produced the coefficients. Do not hand-edit."
        ),
        "cases": cases,
    }


def build_artifact(intercept, coefficients, meta):
    return {
        "_comment": (
            "GambitBattle §8's value function f: P(victory) for the perspective "
            "team, logistic over the per-battle RESULT RECORD. Generated by "
            "tools/fit_value_function.py from a corpus written by "
            "tools/rollout_corpus.tscn. Do not hand-edit."
        ),
        "model": "logistic",
        # The name a run records when this objective produced it. Read by
        # `RolloutValueFunction.id()`; the fallback there is the same string, so
        # an older artifact without this key is still attributable. Bump the
        # suffix when FEATURES changes — a refit of the same features is the same
        # objective and keeps the name, a different feature set is a different
        # function wearing it.
        "objective": "fitted-logistic-v1",
        "features": list(FEATURES),
        "intercept": intercept,
        "coefficients": {
            name: float(value) for name, value in zip(FEATURES, coefficients)
        },
        "calibration": meta,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--artifact", type=Path, default=DEFAULT_ARTIFACT)
    parser.add_argument("--fixture", type=Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--cost-log", type=Path, default=None)
    parser.add_argument(
        "--cap-ms",
        type=float,
        default=DEFAULT_CAP_MS,
        help="wall-clock cap on the FORKED thinking beat, in ms",
    )
    parser.add_argument("--horizons", type=str, default=None)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if the artifact on disk differs from a fresh fit",
    )
    args = parser.parse_args(argv)

    horizons = (
        [int(h) for h in args.horizons.split(",") if h.strip()]
        if args.horizons
        else list(DEFAULT_HORIZONS)
    )

    rows = load_corpus(args.corpus)
    x, y, groups, remaining, draws = build_design(rows)
    train = split_by_group(groups)
    train_groups = {g for g, keep in zip(groups, train) if keep}

    intercept, coefficients = fit_logistic(x[train], y[train])
    # From here down, only the SHIPPED (rounded) fit is used — the artifact, the
    # fixture, the report and the sweep all have to describe the same numbers.
    intercept, coefficients = shipped_coefficients(intercept, coefficients)
    p_test = predict(intercept, coefficients, x[~train])

    print(f"corpus:  {args.corpus}")
    print(
        f"  {len(rows)} samples -> {len(y)} perspective rows over "
        f"{len(set(groups))} battles; {draws} dropped as draws"
    )
    print(
        f"  train {int(train.sum())} rows / {len(train_groups)} battles, "
        f"held out {int((~train).sum())} rows / {len(set(groups)) - len(train_groups)} battles"
    )
    print("\ncoefficients (per unit of the feature, in logits):")
    print(f"  {'intercept':<16} {intercept:+9.4f}")
    for name, value in zip(FEATURES, coefficients):
        column = x[:, FEATURES.index(name)]
        print(
            f"  {name:<16} {value:+9.4f}   (feature range "
            f"{column.min():.2f}..{column.max():.2f})"
        )

    print(f"\nheld-out log-loss (H=0, the formula alone): {log_loss(y[~train], p_test):.4f}")
    print("stratified by remaining battle length:")
    for line in report_strata(y[~train], p_test, remaining[~train]):
        print(line)

    costs = load_cost_axis(args.cost_log)
    points = common_decision_points(rows, horizons, train_groups)
    table = sweep(rows, intercept, coefficients, train_groups, horizons, costs)
    print("\n--- THE H-SWEEP: accuracy vs cost ---")
    if not costs:
        print("  (no --cost-log given, so the cost column is empty and there is")
        print("   no knee to read — the table is half a deliverable without it)")
    print("  (every H scored on the SAME held-out decision points; H=0 is the")
    print("   formula alone, simulating nothing, and runs no ticks to be priced)")
    print(
        f"  {'H':>6}  {'rows':>8}  {'log_loss':>9}  {'beat_ms':>8}  "
        f"{'forked':>8}  {'gain/ms':>10}  fits cap"
    )
    rates = dict(marginal_returns(table))
    fits = {row["horizon"] for row in affordable(table, args.cap_ms)}
    for row in table:
        if not row.get("n"):
            print(f"  {row['horizon']:>6}  {'-':>8}  {'-':>9}")
            continue
        beat = f"{row['beat_ms']:.1f}" if row.get("beat_ms") else "-"
        forked = f"{row['beat_ms'] * FORK_COST_FACTOR:.1f}" if row.get("beat_ms") else "-"
        rate = f"{rates[row['horizon']]:.6f}" if row["horizon"] in rates else "-"
        print(
            f"  {row['horizon']:>6}  {row['n']:>8}  {row['log_loss']:>9.4f}  "
            f"{beat:>8}  {forked:>8}  {rate:>10}  "
            f"{'yes' if row['horizon'] in fits else 'NO'}"
        )
    print(
        f"\n  cap {args.cap_ms:.0f} ms on the FORKED beat "
        f"(ADR-0237 dec. 6: a mid-battle fork costs ~{FORK_COST_FACTOR:g}x a fresh one)"
    )
    unconstrained = knee(table)
    chosen = knee(affordable(table, args.cap_ms))
    if unconstrained is not None:
        print(f"  knee ignoring the cap:  H = {unconstrained}")
    if chosen is not None:
        print(f"  KNEE UNDER THE CAP:     H = {chosen}")

    print("\n  by remaining battle length (log-loss; the mid-game is where decisions are):")
    print(
        f"    NOTE: the common row set needs a landed state at D+{max(horizons)}, so every"
    )
    print(
        f"    decision point here has at least {max(horizons)} ticks left and any stratum"
    )
    print("    below that floor is empty BY CONSTRUCTION, not for want of data.")
    header = "".join(f"{('H=%d' % r['horizon']):>10}" for r in table if r.get("n"))
    print(f"    {'stratum':<24}{header}")
    for name, lo, hi in STRATA:
        cells = ""
        for row in table:
            if not row.get("n"):
                continue
            landed = [
                states[tick + row["horizon"]]
                for states, tick, decision in points
                if lo <= decision["ticks_remaining"] < hi
            ]
            loss, n = _score_states(landed, intercept, coefficients)
            cells += f"{(('%.4f' % loss) if n else '-'):>10}"
        print(f"    {name:<24}{cells}")

    artifact = build_artifact(
        intercept,
        coefficients,
        {
            "corpus_rows": len(rows),
            "corpus_battles": len(set(groups)),
            "draws_dropped": draws,
            "holdout_log_loss": round(log_loss(y[~train], p_test), 6),
            "horizon_sweep": [
                {k: (round(v, 6) if isinstance(v, float) else v) for k, v in row.items()}
                for row in table
            ],
            "knee_horizon": chosen,
            "knee_horizon_uncapped": unconstrained,
            "cap_ms": args.cap_ms,
            "fork_cost_factor": FORK_COST_FACTOR,
        },
    )
    # `ensure_ascii=False` because this file is COMMITTED and read by people:
    # the default escapes the section signs in its own provenance note into
    # `§`, which is a diff nobody can review.
    text = json.dumps(artifact, indent=2, sort_keys=True, ensure_ascii=False) + "\n"

    fixture_text = (
        json.dumps(
            build_fixture(rows, intercept, coefficients),
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        )
        + "\n"
    )

    if args.check:
        if not args.fixture.exists() or args.fixture.read_text() != fixture_text:
            print(f"\nSTALE: {args.fixture} differs from a fresh fit")
            return 1
        if not args.artifact.exists():
            print(f"\nSTALE: {args.artifact} does not exist")
            return 1
        if args.artifact.read_text() != text:
            print(f"\nSTALE: {args.artifact} differs from a fresh fit")
            return 1
        print(f"\n{args.artifact}: up to date")
        return 0

    args.artifact.parent.mkdir(parents=True, exist_ok=True)
    args.artifact.write_text(text)
    args.fixture.parent.mkdir(parents=True, exist_ok=True)
    args.fixture.write_text(fixture_text)
    print(f"\nwrote {args.artifact}")
    print(f"wrote {args.fixture}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except FitError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(2)
