"""A scene that counts assertions must say so on a channel the runner can read.

#463, map #450. `tests/lib/verdict.sh` scores a run by reading its stdout. A
scene that asserts twelve things and prints `=== X: 12 passed, 0 failed ===`
without ever emitting `[PASS]`, `[FAIL]` or `[VERDICT]` is invisible to it: the
marker rules all decline and it scores `NO_VERDICT`, which is the label for a
test that DID NOT RUN. A green test filed as a non-verdict.

THAT IS NOT HYPOTHETICAL AND IT WAS NOT NOTICED FOR WEEKS. `ScenarioWalkToAnimTest`
printed `=== ScenarioWalkToAnimTest: 16 passed, 0 failed ===` then `RESULT: PASS`,
emitted no marker, and scored `NO_VERDICT` in the two oldest archived full runs.
It was found by hand, written into `docs/TEST-BASELINE-E2.tsv`'s `reason` column
as prose (*"a runner/test convention mismatch"*), and fixed by hand in
`2538dd4cc`. Nothing would have caught the next one — which is what this file is.

WHY THE COST OF A MISS IS ASYMMETRIC. A test that goes red is loud. A test that
goes NO_VERDICT looks exactly like a test that was broken by a refactor, so the
honest reading of the register is "something here may have stopped running" and
the dishonest one is "it has always been like that". The register's `reason`
column exists precisely because, after a code move, a `NO_VERDICT` cannot be told
from a break unless someone wrote down which it was.

TWO RULES, AND THE SECOND IS THE MIRROR OF THE FIRST:

  1. A script that prints an assertion summary (`N passed, M failed`, or
     `RESULT: PASS|FAIL`) must also print `[PASS]`, `[FAIL]` or `[VERDICT]`.
  2. A script that declares `[NOT_A_TEST]` must NOT print an assertion summary.
     `[NOT_A_TEST]` is read only when the log holds no marker at all, so a scene
     that asserts twelve things AND declares itself a rig would score NOT_A_TEST
     — laundering a real red into "asserts nothing by design". The declaration
     is for capture rigs, render tools and probes; a scene that counts
     assertions is a test and has to score like one.

`[NOT_A_TEST]` is deliberately NOT accepted as a verdict channel by rule 1, for
the same reason.

STATIC, AND IT SAYS SO. This reads sources, not run logs — it is a suite
pre-flight and must not need Godot. So it sees a `print()` that exists, not a
`print()` that executes: a scene whose marker sits behind a branch that never
runs is invisible here, and only a run can catch that. Both halves are needed and
this is the cheap one.

Usage:  uv run python tools/check_test_verdict_channel.py [--root <dir>]
Pure stdlib. Run from the package root.
"""
import pathlib
import re
import sys

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent

# An assertion summary: `=== X: 12 passed, 0 failed ===` in any of its spellings
# (the count is nearly always a `%d`), or the `RESULT: PASS` form that
# `ScenarioWalkToAnimTest` used. Loose on purpose — a near-miss spelling is
# exactly the drift this is here to catch.
SUMMARY_RE = re.compile(r"passed[^\"']{0,20}failed|RESULT:\s*(?:PASS|FAIL|%s)")

# The channels tests/lib/verdict.sh can actually score. `[NOT_A_TEST]` is NOT
# one of them — see rule 2 in the docstring.
VERDICT_RE = re.compile(r"\[(?:PASS|FAIL|VERDICT)\]")
RIG_RE = re.compile(r"\[NOT_A_TEST\]")


def _code_lines(text: str):
    """Source lines with whole-line comments dropped.

    A `##` docstring that quotes `[PASS]` must not satisfy the rule, and a
    commented-out summary must not trip it.
    """
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("#"):
            continue
        yield n, line


def check_file(path: pathlib.Path) -> list[str]:
    text = path.read_text(errors="replace")
    summary, verdict, rig = None, False, None
    for n, line in _code_lines(text):
        if summary is None and SUMMARY_RE.search(line):
            summary = (n, line.strip())
        if VERDICT_RE.search(line):
            verdict = True
        if rig is None and RIG_RE.search(line):
            rig = (n, line.strip())

    problems = []
    if summary and not verdict:
        problems.append(
            f"{summary[0]}: prints an assertion summary and NO [PASS]/[FAIL]/"
            f"[VERDICT] — the runner scores this NO_VERDICT\n"
            f"      {summary[1][:110]}")
    if summary and rig:
        problems.append(
            f"{rig[0]}: declares [NOT_A_TEST] but counts assertions at line "
            f"{summary[0]} — a rig does not assert\n"
            f"      {rig[1][:110]}")
    return problems


def main(argv: list[str]) -> int:
    root = PROJECT_DIR / "tests"
    if "--root" in argv:
        root = pathlib.Path(argv[argv.index("--root") + 1]).resolve()

    scanned = 0
    violations: dict[pathlib.Path, list[str]] = {}
    for path in sorted(root.rglob("*.gd")):
        scanned += 1
        problems = check_file(path)
        if problems:
            try:
                rel = path.relative_to(PROJECT_DIR)
            except ValueError:
                rel = path
            violations[rel] = problems

    if violations:
        print("Test scenes the verdict reader cannot score (#463):")
        for rel, problems in violations.items():
            for p in problems:
                print(f"  {rel}:{p}")
        print(
            "\nFix: print `[PASS] <name>` / `[FAIL] <what>` per assertion, or "
            "declare the aggregate once with `[VERDICT] PASS|FAIL` (#451). A "
            "scene that genuinely asserts nothing — a capture rig, a render "
            "tool, a probe — declares `[NOT_A_TEST] <why>` INSTEAD, and must not "
            "also print a summary. See tests/lib/verdict.sh."
        )
        return 1

    print(f"OK: all {scanned} scenes under {root.name}/ that count assertions "
          f"declare a verdict the runner can read (#463).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
