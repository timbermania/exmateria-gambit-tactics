#!/usr/bin/env python3
"""Sentinel: a suite RUN must leave the box's machine-scoped state exactly as it found it.

    uv run python tools/machine_state_sentinel.py --snapshot <statefile>
    uv run python tools/machine_state_sentinel.py --compare  <statefile>

NOT a `tools/check_*.py`, and deliberately not named like one: `check_guard_registry.py`
registers STATIC guards, which answer a question about the TREE and run in the pre-flight.
This one answers a question about the RUN — it has to bracket the test loop, so a
pre-flight slot could not hold it. Both runners invoke it (`tests/run_all_tests.sh` and
`tools/run_tests_parallel.py`); an arm that skipped it would be #565's finding again.

WHY IT EXISTS. `config/tune_overrides.json` is machine-scoped developer state — the pins
one human dialed in the F3 panel, on one box — and it has poisoned this repo three times:

  * #614  `TileOverlayConfigTuneTest` drove a real `TilesDebugPanel`, whose AUTOSAVE edit
          committed, and the file went from ten entries to one. `git status` showed a
          modified file and nothing said a test had done it.
  * 90e593900  it churned on every boot, blocking three consecutive pulls on the asset hub.
          Fixed by UNTRACKING it — which cured the churn and removed the last signal that a
          run had written it, because an untracked-and-ignored file shows up nowhere.
  * #1149 the same test, now leaking into an ABSENT file (the case its own snapshot/restore
          early-returned on), produced NINE false reds mid-suite. They were attributed to
          the branch under test. Which tests flipped depended only on where the poison
          landed in the schedule, so two runs of the same tree disagreed.

WHY IT COMPARES RATHER THAN ASSERTING ABSENCE. #1149 asked whether the runner should
assert the file is absent and fail if a test leaves one behind. Absence is the wrong
predicate: a developer with pins dialed in has the file legitimately, and a pre-flight
that aborts on it would make the sanctioned workflow (ADR-0068 R6: scrub, then drain into
code) unrunnable beside the suite. What a run may never do is CHANGE it. So the sentinel
digests bytes-or-absence before, and again after, and reports the delta — a predicate that
is true for the developer with pins and for the fresh clone alike.

SCOPE. One path today, because it is the one with three recurrences. The list is the
extension point, and a path earns a row by being (a) machine-scoped, (b) not tracked, so
`git status` cannot report it, and (c) readable by a test process. Adding a file that a
test legitimately regenerates would buy a false red, which costs more than it catches.
"""
import argparse
import hashlib
import json
import pathlib
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# Machine-scoped, untracked, and read at boot by every Godot process — see SCOPE above.
WATCHED = ["config/tune_overrides.json"]

ABSENT = "<absent>"


def digest(path: pathlib.Path) -> str:
    """The file's sha256, or the ABSENT sentinel. Absence is a STATE, not a missing
    reading: "absent before and present after" is the exact shape of #1149's leak, and a
    snapshot that recorded nothing for a missing file could not see it."""
    if not path.exists():
        return ABSENT
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(root: pathlib.Path = PROJECT_DIR, watched=None) -> dict:
    return {rel: digest(root / rel) for rel in (watched or WATCHED)}


def drift(before: dict, after: dict) -> list[str]:
    """One line per path whose bytes-or-absence moved, in the words a reader needs: what
    it was, what it is, and that the RUN is what changed it."""
    out = []
    for rel in sorted(set(before) | set(after)):
        was = before.get(rel, ABSENT)
        now = after.get(rel, ABSENT)
        if was == now:
            continue
        if was == ABSENT:
            out.append(f"{rel}: ABSENT before the run, CREATED by it")
        elif now == ABSENT:
            out.append(f"{rel}: present before the run, DELETED by it")
        else:
            out.append(f"{rel}: rewritten by the run ({was[:12]} -> {now[:12]})")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--snapshot", metavar="STATEFILE",
                   help="record bytes-or-absence of the watched paths, before the run")
    g.add_argument("--compare", metavar="STATEFILE",
                   help="re-read them and report what the run changed; exit 1 on drift")
    args = ap.parse_args(argv)

    if args.snapshot:
        pathlib.Path(args.snapshot).write_text(json.dumps(snapshot(), indent=1))
        return 0

    state = pathlib.Path(args.compare)
    if not state.exists():
        # Not a verdict about the tree: the bracket is half-open, so say so and stay green.
        print(f"machine-state sentinel: no snapshot at {state} — nothing to compare",
              file=sys.stderr)
        return 0
    lines = drift(json.loads(state.read_text()), snapshot())
    state.unlink()
    if not lines:
        return 0
    print("ABORT: the run changed machine-scoped state (tools/machine_state_sentinel.py).",
          file=sys.stderr)
    for line in lines:
        print(f"       {line}", file=sys.stderr)
    print("       A test wrote a file the NEXT test reads at boot, so verdicts after the",
          file=sys.stderr)
    print("       write describe the poison and not the tree (#1149). Find the writer;",
          file=sys.stderr)
    print("       ADR-0281's seam is what is supposed to make this impossible.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
