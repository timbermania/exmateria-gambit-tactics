#!/usr/bin/env python3
"""Guard: every guard in `tools/` is either RUN by the pre-flight or DECLARED not to be.

    uv run python tools/check_guard_registry.py [--list]

THE RULE. For every `tools/check_*.py` in this package, `tests/run_all_tests.sh` either
invokes it, or `NOT_IN_PREFLIGHT` below carries a row for it with an owner and a reason.
There is no third state, and "nobody thought about it" is the state this guard exists to
delete.

🔴 THIS FILE IS THE FOURTH INSTANCE OF ONE SHAPE, and the first three were each found by
hand, months apart, by somebody looking for something else:

  * `check_vault_anchors.py` — registered nowhere, for months (#565).
  * `check_addon_portability.py` — root ADR-0003 dec. 7 measured the hole and NAMED this file,
    *"the 8 that never run include check_addon_portability.py, the existing addon guard"*.
    Two more arms were BUILT into it (ADR-0169 dec. 5, ADR-0171 dec. 5) before ADR-0175
    registered it. `run_all_tests.sh`'s own comment beside it says the sentence this
    guard mechanizes: **a guard the suite does not list is a guard nobody runs.**
  * `check_blueprint_walk.py` — calls itself *guard #24* (ADR-0144 dec. 9) and is in none
    of the pre-flight's invocations. #770 measured what that cost: two separate reds sat
    on trunk unseen, one of them (#728) predating the ticket that found it.

The measurement that made it a guard rather than a fourth ticket, taken at `de8ae7af4`:
**57 guards, 9 of them in no pre-flight, and 4 of those 9 RED right now** —
`check_focus_anchor`, `check_residue`, `check_root_set`, `check_test_baseline`. Nine
guards is not a slip anybody was going to notice; it is a population.

⚠️ AND COST IS NOT THE REASON ANY OF THEM WAS LEFT OUT. All nine were timed the same
afternoon: the slowest is 4 s and the nine together are ~10 s against a pre-flight that
measures 342. Whatever kept them out, it was not the clock — which is why this register
asks for a reason in words rather than offering a `slow` bucket.

TWO KINDS OF ROW, and the difference is the whole point of writing them down:

  EXEMPT  the guard is not a pre-flight guard and never will be. A permanent argument.
  OWED    it belongs in the pre-flight and is not there yet, with the ticket that says
          why not. REPORTED loudly on every run, and it must name an issue — a row that
          is owed to nobody is the state this register was built to replace.

ARMS.

  arm 1  ENFORCING. A `tools/check_*.py` that is neither invoked nor declared is RED.
  arm 2  ENFORCING, the other direction. A declared row naming a file that is gone, or
         naming a file the pre-flight now DOES invoke, is STALE and RED. A ratchet has
         two arms; without this one the register would keep excusing guards that had
         already been wired in, and the excuse list would only ever grow.
  arm 3  ENFORCING. An `OWED` row with no `#<n>` in its owner is RED. Debt with no
         address is the reported channel's own failure mode.
  arm 4  REPORTED, scores nothing. The `OWED` count, printed every run, so the number
         has to be looked at rather than discovered.

WHAT THIS GUARD CANNOT SEE, stated because this repo's blind spots have all scored
non-zero eventually:

  - **Guards outside `tools/`.** `tests/run_all_tests.sh` also invokes
    `../exmateria-sound/tools/check_globals.py`, which lives in another package. The
    subject here is THIS package's `tools/`; a guard added to the sibling package and run
    by nobody is invisible to this file, exactly as `_walk_roots.extracted_roots()`
    describes for every other instrument at that boundary.
  - **Whether a guard's own TESTS run.** `tools/test_score_goals.py` had never been run
    by anything, and 63 of its siblings still are not — that is **#876**, the same shape
    one level up, and it is deliberately NOT answered here. An invoked guard whose seeded
    red arms nobody runs is a guard that can silently stop firing.
  - **Whether an invoked guard is ENFORCING.** This asks only that the pre-flight calls
    it. A guard invoked without `if ! …; then exit 1; fi` would pass here.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RUNNER = ROOT / "tests" / "run_all_tests.sh"

EXEMPT, OWED = "EXEMPT", "OWED"

# 🔴 A REVIEWED LITERAL, exactly as `check_lattice_scene`'s registers are. Not a filter
# over names, not a `slow` heuristic: a filter manufactures its own exemptions and cannot
# tell a guard somebody ruled out from one that merely matches (#424).
#
# guard basename -> (kind, owner, why)
NOT_IN_PREFLIGHT: dict[str, tuple[str, str, str]] = {
    "check_focus_anchor.py": (
        OWED, "#879, 2026-09-05",
        "RED on trunk with 4 problems, and the cause is a MOVE, not new debt: "
        "`PlayerCamera.gd` and `TileCursor.gd` went into `addons/exmateria_battlefield/` "
        "and ADR-0177's grandfather list still names their `src/scenes/` addresses, so "
        "the same two files read as 2 GREW + 2 STALE. Wiring it in before the list is "
        "repointed would red the pre-flight on arrival, which is the failure #770 warned "
        "about in its own words: rule the reds FIRST, then add the invocation."),
    "check_residue.py": (
        OWED, "#880, 2026-09-05",
        "RED on trunk. `docs/RESIDUE.tsv` is GENERATED by `residue.py --tsv` and the "
        "committed copy has drifted from what the tree derives. Regenerating it moves a "
        "published register, which under ADR-0131 lands as its own change where it can "
        "be measured — not as a side effect of wiring a guard in."),
    "check_root_set.py": (
        OWED, "#881, 2026-09-05",
        "RED on trunk with 5 UNDECLARED SCENES, three of them the very mount scenes "
        "`check_lattice_scene`'s arm 2 declares (`CombatCamera`, `CombatCursor`, "
        "`ProceduralMap`) and two of them demo scenes inside the extracted sound package. "
        "Each needs a `docs/ROOT_SET.tsv` judgement — root, declined, or not a scene the "
        "walk owns — and pass 3's guard has no catch-all by design."),
    "check_test_baseline.py": (
        OWED, "#882, 2026-09-05",
        "RED on trunk with 3 problems. One is a typo with a measured cause: the "
        "`# moved ScenarioEventPathfinderTest` row names "
        "`addons/exmateria_battlefield/tests/ScenarioEventPathfinderTest.tscn` and the "
        "file that exists is `EventPathfinderTest.tscn` — the move dropped the "
        "`Scenario` prefix. The other two are UNRECORDED rows needing a deleted/moved "
        "ruling each (ADR-0194 dec. 10)."),
}


def guards() -> list[str]:
    """Every `tools/check_*.py` basename. `test_check_*.py` does not match, deliberately:
    a guard's own tests are #876's subject, not this one's."""
    return sorted(p.name for p in (ROOT / "tools").glob("check_*.py"))


def invoked() -> set[str]:
    """The guards `tests/run_all_tests.sh` actually CALLS.

    Comment lines are dropped first and the match requires an interpreter in front of the
    name. Both halves are load-bearing: the runner names `check_tune_owner_self_registration.py`
    and `check_test_list_coverage.py` in prose beside other rules, and a bare substring
    search would score a mention as a run — which is the exact confusion this file is
    about, one level down."""
    src = RUNNER.read_text(encoding="utf-8")
    code = "\n".join(ln for ln in src.splitlines() if not ln.lstrip().startswith("#"))
    return {g for g in guards()
            if re.search(r"python[0-9.]*\s+[^\s;|&()]*" + re.escape(g), code)}


def main() -> int:
    print("check_guard_registry.py — a guard the suite does not list is a guard nobody "
          "runs")
    all_guards, run = guards(), invoked()
    declared = set(NOT_IN_PREFLIGHT)
    print("  subject: %d guard(s) under tools/, against %s"
          % (len(all_guards), RUNNER.relative_to(ROOT).as_posix()))

    unregistered = sorted(g for g in all_guards if g not in run and g not in declared)
    stale_gone = sorted(g for g in declared if g not in all_guards)
    stale_wired = sorted(g for g in declared if g in run)
    owed = sorted(g for g, (k, _, _) in NOT_IN_PREFLIGHT.items()
                  if k == OWED and g in all_guards and g not in run)
    exempt = sorted(g for g, (k, _, _) in NOT_IN_PREFLIGHT.items()
                    if k == EXEMPT and g in all_guards and g not in run)
    unaddressed = sorted(g for g in owed if not re.search(r"#\d+", NOT_IN_PREFLIGHT[g][1]))

    print("\narm 1 — INVOKED by the pre-flight: %d of %d." % (len(run), len(all_guards)))
    print("arm 4 — DECLARED not to be, REPORTED: %d EXEMPT, %d OWED." % (len(exempt), len(owed)))
    for g in owed:
        _, owner, why = NOT_IN_PREFLIGHT[g]
        print("  OWED  %s\n      %s — %s" % (g, owner, why))
    for g in exempt:
        _, owner, why = NOT_IN_PREFLIGHT[g]
        print("  exempt %s\n      %s — %s" % (g, owner, why))
    if "--list" in sys.argv:
        print("\ninvoked:")
        for g in sorted(run):
            print("  %s" % g)

    rc = 0
    if unregistered:
        rc = 1
        print("\n❌ arm 1 — %d guard(s) in NO pre-flight and on NO row. A guard the suite\n"
              "   does not list is a guard nobody runs (#565, root ADR-0003 dec. 7, #770).\n"
              "   Invoke it in tests/run_all_tests.sh, or add a row here saying why not."
              % len(unregistered))
        for g in unregistered:
            print("  %s" % g)
    if stale_gone:
        rc = 1
        print("\n❌ arm 2 — %d STALE row(s) naming a guard that does not exist. The file\n"
              "   is gone; DELETE the row." % len(stale_gone))
        for g in stale_gone:
            print("  %s      was: %s" % (g, NOT_IN_PREFLIGHT[g][1]))
    if stale_wired:
        rc = 1
        print("\n❌ arm 2 — %d row(s) excusing a guard the pre-flight NOW INVOKES. The debt\n"
              "   is PAID; the row is the leftover. DELETE it — without this direction the\n"
              "   excuse list only ever grows." % len(stale_wired))
        for g in stale_wired:
            print("  %s      was: %s" % (g, NOT_IN_PREFLIGHT[g][1]))
    if unaddressed:
        rc = 1
        print("\n❌ arm 3 — %d OWED row(s) with no issue number in the owner. Debt with no\n"
              "   address is how a reported channel becomes a hiding place." % len(unaddressed))
        for g in unaddressed:
            print("  %s      owner: %s" % (g, NOT_IN_PREFLIGHT[g][1]))

    if rc == 0:
        print("\n✅ check_guard_registry: every guard under tools/ is INVOKED (%d) or\n"
              "   DECLARED with an owner and a reason (%d exempt, %d owed). ⚠️ %d owed is\n"
              "   not zero and is not a pass — see arm 4 above."
              % (len(run), len(exempt), len(owed), len(owed)))
    return rc


if __name__ == "__main__":
    sys.exit(main())
