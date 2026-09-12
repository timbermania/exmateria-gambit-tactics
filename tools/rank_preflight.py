#!/usr/bin/env python3
"""Rank EVERY step of the static pre-flight by cost, from the run that actually happened.

    uv run python tools/rank_preflight.py              # run and rank
    uv run python tools/rank_preflight.py --top 40     # deeper table
    uv run python tools/rank_preflight.py --tsv <path> # also write a register

WHY THIS IS A SUITE COST. `tools/run_tests_parallel.py` shells out to
`run_all_tests.sh --preflight-only` and WAITS for it before the first test process
starts, so the pre-flight is serial time at the head of every full run: a minute here
costs a minute of wall clock at any N. That is the opposite of a test, where a minute
costs a minute divided by N.

🔴 IT MEASURES THE RUN, NOT THE SOURCE, AND THAT IS THE WHOLE POINT. The obvious
instrument greps `run_all_tests.sh` for `uv run python …` and re-runs each match on its
own. `tools/time_preflight.py` (#958) does exactly that, and its per-LINE regex cannot
match a command that wraps across a `\\` continuation. There are two such steps and one
of them — line 242, the parallel-arm tests — is **67% of the pre-flight**. Three
consecutive sessions optimised 24 s and 18 s steps off that tool's ranking while a 153 s
step sat directly above them, unranked and unnamed. A source scan is a claim about what
the file looks like; this is a claim about what ran.

    HOW. `bash -x` with `PS4='+@${EPOCHREALTIME}@${LINENO}@'`. A trace event's cost is
    the gap to the NEXT event, so the last command before a long-running child is billed
    for that child. Measured overhead: 229.7 s traced against 232.4 s / 226.9 s
    untraced — inside the run-to-run spread, so the ranking is not paying for itself.

🔴 THE PRE-FLIGHT RUNS ITSELF THREE TIMES, and every ranking here has to be read in that
light. `test_run_tests_parallel.SequentialArmIsGated` has two arms that invoke
`run_all_tests.sh` as a subprocess to prove the gate refuses — each pays the whole guard
block again, with `FFT_SUITE_NESTED=1` skipping only that one step so it does not
recurse forever. So the block runs once directly and twice nested: **a second cut from
an ordinary guard is worth three seconds of pre-flight wall clock**, and this table's
face values understate every row except line 242's by 3x.

⚠️ THE TWO NESTED RUNS CANNOT BE PARALLELISED, and this is measured, not assumed.
14 of the 20 pre-flight `unittest` modules seed fixed-name files into the REAL tree
(`tools/check__registry_seed.py`, `tests/_registry_seed_runner.sh`, …) and assert
`not path.exists()` on the way in. Two pre-flights in one tree collide: run concurrently,
the no-arguments arm died at `check_guard_registry` with "a previous run leaked". Worse,
it dies in a way `_skip_if_preflight_aborted` converts to a SKIP — a silenced gate arm
looks exactly like a passing one. `test_check_lattice_publish`'s module docstring names
the serialism as load-bearing for the same reason.

⚠️ IT IS A REAL-TIME MEASUREMENT AND RUN ORDER LIES. Taken while another session holds
the box, every number is inflated and the ranking may reorder. Check `pgrep -x godot`
first, and say what the box was doing when you quote a number from this tool.

⚠️ IT IS NOT A VERDICT. A guard that costs 40 s may be worth 40 s. This ranks cost so
the question can be ASKED; the three answers for an expensive guard are make it cheaper,
move it off the critical path, or keep it and say why.

Pure stdlib. Run from the package root.
"""
import argparse
import collections
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUNNER = ROOT / "tests" / "run_all_tests.sh"
EVENT = re.compile(r"^\++@(\d+\.\d+)@(\d+)@\s?(.*)$")


def trace(path: pathlib.Path) -> tuple[float, int]:
    """Run the pre-flight under xtrace, timestamps into `path`. Returns (wall, rc)."""
    env = dict(os.environ, PS4="+@${EPOCHREALTIME}@${LINENO}@")
    t0 = time.perf_counter()
    with open(path, "wb") as err:
        p = subprocess.run(["bash", "-x", str(RUNNER), "--preflight-only"],
                           cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=err)
    return time.perf_counter() - t0, p.returncode


def events(path: pathlib.Path) -> list[tuple[float, int, str]]:
    out = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = EVENT.match(raw)
        if m:
            out.append((float(m.group(1)), int(m.group(2)), m.group(3)))
    return out


def rank(evs):
    """{(line, command): seconds}, billing each event the gap to the next."""
    cost = collections.defaultdict(float)
    for i in range(len(evs) - 1):
        cost[(evs[i][1], evs[i][2])] += evs[i + 1][0] - evs[i][0]
    return cost


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--tsv")
    ap.add_argument("--trace", help="rank an existing trace instead of running one")
    args = ap.parse_args()

    busy = subprocess.run(["pgrep", "-x", "godot"], capture_output=True, text=True)
    if busy.stdout.strip():
        print(f"⚠️  {len(busy.stdout.split())} godot process(es) on the box — every number "
              f"below is inflated and the ranking may reorder. Re-take when quiet.\n")

    if args.trace:
        tf, wall, rc = pathlib.Path(args.trace), float("nan"), None
    else:
        tf = pathlib.Path(tempfile.mkstemp(prefix="rank_preflight.", suffix=".trace")[1])
        print(f"running the pre-flight under xtrace (~4 min)…", flush=True)
        wall, rc = trace(tf)
        print(f"pre-flight: {wall:.1f}s, exit {rc}\n")

    evs = events(tf)
    # 🔴 A CONFIDENT ZERO IS THIS TOOL'S FAILURE MODE. An empty parse and a pre-flight
    # with no steps in it produce the same clean, sorted, empty table — and two
    # instruments in this chain's history printed exactly that and exited 0. Refuse.
    if len(evs) < 50:
        sys.exit(f"only {len(evs)} trace events parsed from {tf} — the PS4 format did "
                 f"not survive. This is a broken instrument, not a cheap pre-flight.")

    cost = rank(evs)
    span = evs[-1][0] - evs[0][0]
    total = sum(cost.values())
    rows = sorted(cost.items(), key=lambda kv: -kv[1])

    print(f"{len(evs)} trace events over {len(cost)} distinct steps; "
          f"traced span {span:.1f}s, attributed {total:.1f}s ({total / span:.0%})\n")
    print(f"{'#':>3} {'secs':>8} {'x3':>8} {'share':>7} {'cum':>7}  line  step")
    cum = 0.0
    for i, ((line, cmd), secs) in enumerate(rows[:args.top], 1):
        cum += secs
        # `x3` is the wall clock this row really owns — see the 🔴 on recursion above.
        # Line 242 IS the recursion, so it is the one row that pays face value.
        x3 = secs if line == 242 else secs * 3
        print(f"{i:>3} {secs:>8.2f} {x3:>8.2f} {secs / total:>6.1%} {cum / total:>6.1%} "
              f"{line:>5}  {cmd[:78]}")
    rest = sum(s for _, s in rows[args.top:])
    print(f"\n  … {len(rows) - args.top} more steps, {rest:.1f}s ({rest / total:.1%}) combined")
    half = next(i for i, _ in enumerate(rows, 1)
                if sum(s for _, s in rows[:i]) >= total / 2)
    print(f"Half the pre-flight is its {half} slowest step(s) of {len(rows)}.")

    if args.tsv:
        pathlib.Path(args.tsv).write_text(
            "line\tseconds\tstep\n" + "".join(
                f"{line}\t{secs:.2f}\t{cmd}\n" for (line, cmd), secs in rows),
            encoding="utf-8")
        print(f"\nwrote {args.tsv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
