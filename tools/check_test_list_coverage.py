"""Every scene under `tests/` is run, declares it asserts nothing, or is skipped WITH A REASON.

#417, map #450. `bash tests/run_all_tests.sh` is not "the suite" — it is a
hand-maintained bash array, and the tree grew faster than the hand. Measured on
trunk `6a25e54f7`: **744** scenes under `tests/`, **412** in the array, **300** of
the remaining 332 emitting `[PASS]`/`[FAIL]` markers and reachable by no runner
at all. 57.9% coverage, and nothing anywhere said so.

WHY A GUARD AND NOT JUST A LONGER ARRAY. Some of the 300 SHOULD be excluded —
red pending triage, environment-dependent, structurally broken. The defect is not
that they are excluded, it is that **an unlisted test and a deliberately-skipped
test are indistinguishable**: a test that silently stopped being run looks exactly
like a test that was never meant to run. Both are "absent from an array". This
guard makes the difference a written line with a name on it.

THE UNIVERSE IS EVERY `.tscn`, WITH NO FILTER. The tempting shape is "every scene
whose script emits markers must be listed", and it is wrong here for a reason this
repo has already paid for once: an exclusion rule that is a FILTER rather than a
NAMED LIST manufactured a tenth debt file in #424, and a filter has the specific
failure mode that a test which stops emitting markers silently leaves the required
set. So the rule quantifies over all 744 and every one of them lands in exactly
one of three states:

  1. **listed** in `tests/run_all_tests.sh`'s `TESTS=(` array — it runs;
  2. **declares** `[NOT_A_TEST] <why>` on `tests/lib/verdict.sh`'s own channel —
     it says it asserts nothing, in the place the runner already reads, and the
     `<why>` is required for the same reason it is required there;
  3. **skipped** in `tests/skip_tests.tsv` with a class and a reason.

State 2 is deliberately the EXISTING channel rather than a second list. #463 split
`NOT_A_TEST` out because nine capture rigs were scoring `NO_VERDICT` — the label
for a test that did not run — and their classification existed only as prose in
`freeze_test_baseline.RED_REASONS`. Giving rigs a second home here would put the
same fact in two places again.

THE DECLARATION IS READ BEFORE THE MARKERS HERE, WHICH IS THE OPPOSITE OF
`verdict.sh`, AND THAT IS DELIBERATE. The obvious tightening is "a scene that
emits markers may not buy its way out with a declaration", and it fires on
correct code: the whole population is `SfxLiveStressTest` and `SfxPopDiagTest`,
two rigs that declare honestly and also print `[FAIL] audio engines not ready` as
a setup guard-rail. Measured, not assumed — those two are it. The laundering
shape this rule could otherwise permit — a real test relabelling itself a rig —
is already refused by `tools/check_test_verdict_channel.py` rule 2, which fails a
scene that declares `[NOT_A_TEST]` while printing an assertion SUMMARY. Two
guards, one rule between them; the summary is the signal that separates a rig
with a guard-rail from a test in a disguise.

STATIC, AND NO GODOT. Reads the array, the tree and the skip file. It cannot know
whether a listed test passes — that is a run's job, and `tools/freeze_test_baseline.py`
is what reads one. This is the cheap half, and it is the half that catches the
scene that landed last week and joined nothing.

Usage:  uv run python tools/check_test_list_coverage.py [--root <dir>] [--tsv]
`--root` points at a project root holding `tests/` — it exists so this guard's own
tests can drive it against a synthesised tree, the same shape
`tools/check_test_verdict_channel.py` uses.
Pure stdlib. Run from the package root.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import _runner_tests as rt  # noqa: E402

# The closed vocabulary for `tests/skip_tests.tsv`'s second column. Closed on
# purpose: a new KIND of exclusion is a decision, and it should cost a code change
# and a line of prose here rather than being spelled into the data by whoever is
# in a hurry. Each is a different thing to do about it, which is the test for
# whether a class earns a slot.
SKIP_CLASSES = {
    # Runs, asserts something, and that something is FALSE today. Excluded so the
    # finding can be triaged as a finding instead of turning the suite red before
    # anyone has read it. A `red` row must name the ticket that holds it.
    "red",
    # The verdict is a property of the CHECKOUT, not of the code — a gitignored
    # asset, a ROM extract, a built native lib. `FedsInstrumentMetaTest` is the
    # documented example: it fails one assertion because `authored_effects/
    # E001.feds.bin` is gitignored.
    "environmental",
    # Structurally incapable of running: a scene whose script is not in the
    # repository, an unresolvable ext_resource. The population is EMPTY today —
    # #533 arm 1's `GPUCallbackE317Test.tscn` was the only member and it was
    # deleted (its script was never in git at any commit, so there was nothing to
    # write). The state stays because the next such scene should land here rather
    # than in `environmental`.
    "broken",
    # Asserts nothing, and has no `tests/*.gd` of its own to declare it in — the
    # four `tests/tools/` capture scenes mount their scripts from `tools/`. A rig
    # WITH a script belongs in state 2, not here.
    "rig",
    # Excluded for wall clock, with the measured cost in the reason. The suite's
    # budget is a decision this map owns (#454); a slow test hidden by omission is
    # not.
    "slow",
    # Replaced by another test, kept on disk for reference. The reason must name
    # the successor.
    "superseded",
    # Run by a STRANGER RIG instead of by the assembly suite (ADR-0194 dec. 4).
    # Not an exclusion for a defect, a cost or a checkout — an exclusion because
    # the scene asserts something the assembly project cannot host: it belongs to
    # a `tests/stranger/<addon>/run.sh` that builds its own throwaway project,
    # and running it as `res://tests/X.tscn` here would run it in exactly the
    # project whose absence is the whole claim. The reason must name the rig, and
    # that rig is what has to be green — dec. 10's runner phase is what makes
    # "skipped by the array" stop meaning "run by nothing".
    "stranger",
}

PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
TESTS_SH = "tests/run_all_tests.sh"
SKIP_TSV = "tests/skip_tests.tsv"


def _read(root: pathlib.Path):
    """The three readings, all of them somebody else's — see `_runner_tests`."""
    root = root or PROJECT_DIR
    return (rt.scene_stems(root / "tests"),
            rt.runner_tests(root / TESTS_SH),
            rt.skips(root / SKIP_TSV))


def classify(root: pathlib.Path = None) -> dict:
    """stem -> (state, detail) for every scene under `tests/`."""
    scenes, listed, skipped = _read(root)
    listed_set = set(listed)
    out = {}
    for stem, path in scenes.items():
        if stem in listed_set:
            out[stem] = ("listed", str(path))
        elif rt.declares_not_a_test(path):
            out[stem] = ("declares", str(path))
        elif stem in skipped:
            out[stem] = ("skipped", skipped[stem][0])
        else:
            out[stem] = ("UNCLASSIFIED", str(path))
    return out


def findings(root: pathlib.Path = None) -> list:
    """The rule violations, as `(rule, stem, message)`. Empty means green."""
    scenes, listed, skipped = _read(root)
    listed_set = set(listed)
    bad = []

    # R1 — the whole point. A scene in none of the three states is an omission
    # nobody decided on.
    for stem, (state, detail) in sorted(classify(root).items()):
        if state == "UNCLASSIFIED":
            bad.append(("R1", stem,
                        f"{detail} is in no runner's list, declares no "
                        f"[NOT_A_TEST], and has no {SKIP_TSV} row"))

    # R2 — a skip without a reason is an omission with a filename. The class must
    # be one this file has thought about; the reason must be prose a human wrote.
    for stem, (klass, reason) in sorted(skipped.items()):
        if klass not in SKIP_CLASSES:
            bad.append(("R2", stem,
                        f"class {klass!r} is not one of {sorted(SKIP_CLASSES)}"))
        if len(reason) < 12:
            bad.append(("R2", stem,
                        f"reason is {len(reason)} chars — say why, not that"))

    # R3 — a skip row for a scene that no longer exists outlives its decision and
    # makes the file look more considered than it is.
    for stem in sorted(set(skipped) - set(scenes)):
        bad.append(("R3", stem, f"{SKIP_TSV} names a scene that is not on disk"))

    # R4 — listed AND skipped is two answers to one question. The array wins at
    # runtime, so the skip row is a lie that reads as a decision.
    for stem in sorted(listed_set & set(skipped)):
        bad.append(("R4", stem, f"is in {TESTS_SH}'s TESTS array AND in {SKIP_TSV}"))

    # R5 — the array's own integrity. Re-derived by hand at every re-census so far
    # ("0 duplicates, 0 dangling"); a number nobody derives is a number nobody can
    # re-derive.
    seen = set()
    for stem in listed:
        if stem in seen:
            bad.append(("R5", stem, f"appears twice in {TESTS_SH}'s TESTS array"))
        seen.add(stem)
        if stem not in scenes:
            bad.append(("R5", stem,
                        f"is listed in {TESTS_SH} and has no scene under tests/"))
    return bad


def main() -> int:
    root = None
    if "--root" in sys.argv:
        root = pathlib.Path(sys.argv[sys.argv.index("--root") + 1]).resolve()
    states = classify(root)
    tally = {}
    for state, _ in states.values():
        tally[state] = tally.get(state, 0) + 1

    if "--tsv" in sys.argv:
        print("stem\tstate\tdetail")
        for stem, (state, detail) in sorted(states.items()):
            print(f"{stem}\t{state}\t{detail}")
        return 0

    print(f"scenes under tests/          {len(states)}")
    for state in ("listed", "declares", "skipped", "UNCLASSIFIED"):
        print(f"  {state:<26} {tally.get(state, 0)}")

    bad = findings(root)
    if not bad:
        print("\nOK — every scene under tests/ is run, declares it asserts "
              "nothing, or is skipped with a reason.")
        return 0
    print(f"\n{len(bad)} finding(s):")
    for rule, stem, msg in bad:
        print(f"  [{rule}] {stem}: {msg}")
    print(f"\nFix by listing it in {TESTS_SH}, declaring `[NOT_A_TEST] <why>` in "
          f"its script,\nor adding a row to {SKIP_TSV} (stem<TAB>class<TAB>reason).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
