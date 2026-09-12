#!/usr/bin/env python3
"""Diff a sequential arm against a parallel arm, per test, and propose the lane — #453.

    uv run python tools/diff_arm_verdicts.py \
        --sequential /tmp/seq.log \
        --parallel /tmp/par-1.log /tmp/par-2.log /tmp/par-3.log \
        --known-flakes DetailStatsDeltaFrameRideTest,GPURangedCombatTest

WHY THIS IS NOT `diff <(verdicts a) <(verdicts b)`. Two runs of this suite differ
even when nothing changed. On a fixed tree, four tests are not constant across
the three same-tree archived runs — `DetailStatsDeltaFrameRideTest`,
`GPURangedCombatTest`, `GPUStatusNoDamageTest`, `ScenarioDoorwayRevealTest`. A
plain diff of one sequential run against one parallel run reports those four as
movers, and adopting parallelism on that reading would quarantine four innocent
tests while proving nothing about the ones that really moved.

So the classification takes REPEATS and answers a narrower question than "did it
change":

    AGREE             every run of both arms scored it the same.
    FLAKY_SEQUENTIAL  the sequential arm disagrees with ITSELF, or the test is a
                      known flake. Settled before parallelism is considered —
                      a verdict that was never stable cannot have been destabilised.
    FLAKY_PARALLEL    stable sequentially, unstable across the parallel repeats.
                      THE LANE'S MAIN POPULATION: contention that shows up
                      sometimes is worse than contention that shows up always.
    MOVED             constant in both arms, and different. The strongest finding.
    MISSING           scored in one arm and not the other.

`confirmed` is separate from `state` on purpose. One parallel repeat can produce
a MOVED that is really a coin flip; the field says whether the repeat count could
have told the difference, and `propose_lane` still lanes it — an unconfirmed
mover is a reason to run more repeats, not a reason to ignore it.

⚠️ SAME TREE, OR THIS TOOL LIES. The five archived suite runs span two commits;
read as five samples of one tree they report 25 flaky tests, where the three
same-tree runs report 4. This tool cannot tell — it is handed logs. Pin the
commit on every arm before believing an answer.

Pure stdlib. Run from the package root.
"""
import argparse
import collections
import dataclasses
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import freeze_test_baseline


@dataclasses.dataclass
class Verdict:
    test: str
    state: str
    sequential: dict          # verdict -> count
    parallel: dict            # verdict -> count
    confirmed: bool

    def reason(self) -> str:
        s = "/".join(sorted(self.sequential))
        p = ", ".join(f"{v} {n}/{sum(self.parallel.values())}"
                      for v, n in sorted(self.parallel.items(), key=lambda kv: -kv[1]))
        return f"{self.state}: sequential {s}; parallel {p}"


def read_run(path) -> dict:
    """stem -> verdict, by the reading `docs/TEST-BASELINE-E2.tsv` is built with.

    Not re-implemented here: `freeze_test_baseline.verdicts()` already pairs
    `[i/n] Running X...` with the following `  -> RESULT`, and the parallel
    runner prints that shape byte-for-byte so this one reader covers both arms.
    """
    return freeze_test_baseline.verdicts(pathlib.Path(path))


def classify(test, seq_runs, par_runs, known_flakes=frozenset()) -> Verdict:
    s = collections.Counter(r[test] for r in seq_runs if test in r)
    p = collections.Counter(r[test] for r in par_runs if test in r)

    if not s or not p:
        return Verdict(test, "MISSING", dict(s), dict(p), True)
    if len(s) > 1 or test in known_flakes:
        return Verdict(test, "FLAKY_SEQUENTIAL", dict(s), dict(p), True)
    if len(p) > 1:
        return Verdict(test, "FLAKY_PARALLEL", dict(s), dict(p), True)
    if set(s) == set(p):
        return Verdict(test, "AGREE", dict(s), dict(p), True)
    # Constant on both sides and different. With one parallel repeat that is
    # indistinguishable from a first-ever flake, so say so rather than imply a
    # confidence the sample size cannot carry.
    return Verdict(test, "MOVED", dict(s), dict(p), len(par_runs) >= 2)


LANED = ("MOVED", "FLAKY_PARALLEL")


def diff(seq_runs, par_runs, known_flakes=frozenset()) -> list:
    tests = set()
    for r in list(seq_runs) + list(par_runs):
        tests |= set(r)
    return [classify(t, seq_runs, par_runs, known_flakes) for t in sorted(tests)]


def propose_lane(verdicts) -> dict:
    """The `SEQUENTIAL_LANE` #453 asks for: named, with the reason, from the
    measurement. Nothing lands here by hand."""
    return {v.test: v.reason() for v in verdicts if v.state in LANED}


def render_lane(lane: dict) -> str:
    if not lane:
        return "{}"
    body = "".join(f'    {k!r}:\n        {v!r},\n' for k, v in sorted(lane.items()))
    return "{\n" + body + "}"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sequential", nargs="+", required=True, type=pathlib.Path)
    ap.add_argument("--parallel", nargs="+", required=True, type=pathlib.Path)
    ap.add_argument("--known-flakes", default="",
                    help="comma-separated stems already known to be unstable "
                         "SEQUENTIALLY, e.g. from the archived corpus")
    ap.add_argument("--all", action="store_true", help="also print AGREE rows")
    args = ap.parse_args(argv)

    seq = [read_run(p) for p in args.sequential]
    par = [read_run(p) for p in args.parallel]
    flakes = {s.strip() for s in args.known_flakes.split(",") if s.strip()}

    rows = diff(seq, par, flakes)
    tally = collections.Counter(r.state for r in rows)

    print(f"sequential arms: {len(seq)}  ({', '.join(str(p) for p in args.sequential)})")
    print(f"parallel arms:   {len(par)}  ({', '.join(str(p) for p in args.parallel)})")
    print(f"tests:           {len(rows)}")
    print()
    for state in ("MOVED", "FLAKY_PARALLEL", "FLAKY_SEQUENTIAL", "MISSING", "AGREE"):
        n = tally.get(state, 0)
        print(f"  {state:18s} {n}")
    print()
    for r in rows:
        if r.state == "AGREE" and not args.all:
            continue
        flag = "" if r.confirmed else "   [UNCONFIRMED — one parallel repeat]"
        print(f"{r.test:46s} {r.reason()}{flag}")

    lane = propose_lane(rows)
    print(f"\n# SEQUENTIAL_LANE — {len(lane)} entries, generated by this diff")
    print("SEQUENTIAL_LANE = " + render_lane(lane))
    return 0


if __name__ == "__main__":
    sys.exit(main())
