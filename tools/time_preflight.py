#!/usr/bin/env python3
"""Time every step of the static pre-flight, ranked — where the ~6 minutes go.

    uv run python tools/time_preflight.py                 # run and rank
    uv run python tools/time_preflight.py --list          # the steps, no run
    uv run python tools/time_preflight.py --tsv <path>    # also write a register

WHY THIS IS A SUITE COST AND NOT A SIDE ISSUE. `tools/run_tests_parallel.py`
shells out to `run_all_tests.sh --preflight-only` and WAITS for it before the
first test process starts. The pre-flight is therefore serial time at the head of
every full run — it does not overlap the N-way pool, so a minute here costs a
minute of wall clock no matter what N is. That is the opposite of a test, where a
minute costs a minute divided by N.

WHAT IT MEASURES. Every `uv run python …` invocation in the pre-flight region of
`run_all_tests.sh` (the part above the `TESTS=(` array), in file order, each timed
on its own. It re-runs them rather than instrumenting the script, so a step's cost
is measured the same way whichever guard it belongs to.

⚠️ IT IS A REAL-TIME MEASUREMENT AND RUN ORDER LIES. Taken while another session
holds the box, every number here is inflated and the RANKING may reorder — this
package has already had a metrics test read PASS solo and 2/3 FAIL interleaved on
the same tree. Check `pgrep -af godot` first, and say what the box was doing when
you quote a number from this tool.

⚠️ IT IS NOT A VERDICT. A guard that costs 40 s may be worth 40 s. The output
ranks cost so the question can be ASKED, and answers nothing on its own: the three
outcomes for an expensive guard are make it cheaper, move it off the critical path,
or keep it and say why.

Pure stdlib. Run from the package root.
"""
import argparse
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUNNER = ROOT / "tests" / "run_all_tests.sh"

# The pre-flight is everything above the test array. `_runner_tests` anchors on the
# same token for the same reason — one reading of where the array starts.
ARRAY_TOKEN = "TESTS=("
STEP_RE = re.compile(r"uv run python (?P<cmd>[^)&|;]+?)\s*\)")


def steps() -> list[tuple[int, str]]:
    """(line number, argv-after-`uv run python`) for each pre-flight invocation."""
    out, src = [], RUNNER.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(src, 1):
        if line.startswith(ARRAY_TOKEN):
            break
        m = STEP_RE.search(line)
        if m:
            out.append((i, m.group("cmd").strip()))
    return out


def label(cmd: str) -> str:
    if cmd.startswith("-m unittest"):
        return "unittest " + cmd[len("-m unittest"):].strip()
    return cmd.split()[0].replace("tools/", "")


def run(cmd: str) -> tuple[float, int]:
    """Wall clock and exit code for one step, in the cwd the runner uses."""
    cwd = ROOT / "tools" if cmd.startswith("-m unittest") else ROOT
    start = time.monotonic()
    p = subprocess.run(["uv", "run", "python", *cmd.split()],
                       cwd=cwd, capture_output=True, text=True)
    return time.monotonic() - start, p.returncode


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--tsv")
    args = ap.parse_args()

    found = steps()
    if args.list:
        for line, cmd in found:
            print(f"{RUNNER.name}:{line}\t{label(cmd)}")
        print(f"\n{len(found)} pre-flight invocations")
        return 0

    busy = subprocess.run(["pgrep", "-af", "godot"], capture_output=True, text=True).stdout
    others = [l for l in busy.splitlines() if l.strip()]
    if others:
        print(f"⚠️  {len(others)} godot process(es) on the box — every number below is "
              f"inflated and the ranking may reorder. Re-take when quiet.\n")

    rows = []
    for n, (line, cmd) in enumerate(found, 1):
        secs, code = run(cmd)
        rows.append({"line": line, "label": label(cmd), "cmd": cmd,
                     "seconds": secs, "exit": code})
        print(f"  [{n:>2}/{len(found)}] {secs:6.2f}s  {label(cmd)}"
              f"{'  (exit %d)' % code if code else ''}", flush=True)

    total = sum(r["seconds"] for r in rows)
    rows.sort(key=lambda r: -r["seconds"])
    print(f"\n{'':>8}{'secs':>8}{'share':>8}{'cum':>8}  step")
    cum = 0.0
    for i, r in enumerate(rows, 1):
        cum += r["seconds"]
        print(f"{i:>8}{r['seconds']:>8.2f}{r['seconds'] / total:>7.1%}"
              f"{cum / total:>8.1%}  {r['label']}")
    print(f"\n{len(rows)} steps, {total / 60:.1f} min total.")
    half = next(i for i, _ in enumerate(rows, 1)
                if sum(x["seconds"] for x in rows[:i]) >= total / 2)
    print(f"Half the pre-flight is its {half} slowest step(s) of {len(rows)}.")

    if args.tsv:
        p = pathlib.Path(args.tsv)
        p.write_text("line\tstep\tseconds\texit\n" + "".join(
            f"{r['line']}\t{r['label']}\t{r['seconds']:.2f}\t{r['exit']}\n"
            for r in rows), encoding="utf-8")
        print(f"wrote {p}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
