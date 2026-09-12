"""Seed-red tests for the guard registry (#770, ADR-0233).

🔴 THIS FILE IS THE REGISTRY'S OWN INSTANCE OF ITS OWN FINDING. The guard exists because
a guard nobody runs is not a guard; an ARM nobody has seen fire is not an arm, and this
repo has paid for that at least six times (`test_check_lattice_scene.py`'s docstring
counts them). So every arm below CONSTRUCTS the state it grades — a seeded guard file, a
seeded row, a seeded runner — and not one of them reads a row off the shipped
`NOT_IN_PREFLIGHT`. They must still fire on the day the owed set reaches zero.

Run from tools/:
    uv run python -m unittest test_check_guard_registry
"""

from __future__ import annotations

import contextlib
import io
import pathlib
import re
import sys
import unittest

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

import check_guard_registry as reg

SEED = "check__registry_seed.py"
SEED_ROW = ("#0 — a constructed row", "seeded by the test, never read off the tree")


class SeedGuard:
    """A `tools/check_*.py` written into the REAL tree. A scratch directory would prove
    the code path, which is not the claim: the claim is that the registry, over THIS
    package's `tools/`, notices a guard that arrived and was wired to nothing."""

    def __init__(self, name: str = SEED):
        self.path = TOOLS_DIR / name

    def __enter__(self):
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        self.path.write_text("#!/usr/bin/env python3\nraise SystemExit(0)\n",
                             encoding="utf-8")
        return self.path

    def __exit__(self, *exc):
        self.path.unlink(missing_ok=True)
        return False


class SeedRunner:
    """A stand-in `run_all_tests.sh`. The registry reads ONE file to decide what is
    invoked, so pointing it at a constructed one is how an arm about the PREDICATE gets
    tested without editing the real pre-flight."""

    def __init__(self, body: str):
        self.path = PROJECT_DIR / "tests" / "_registry_seed_runner.sh"
        self.body = body
        self.prev = None

    def __enter__(self):
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        self.path.write_text(self.body, encoding="utf-8")
        self.prev, reg.RUNNER = reg.RUNNER, self.path
        return self.path

    def __exit__(self, *exc):
        reg.RUNNER = self.prev
        self.path.unlink(missing_ok=True)
        return False


def _rows(**extra):
    """Start from the SHIPPED register and add. Replacing it wholesale makes the four
    real owed guards read as unregistered, and then arm 1 reds for a reason the arm
    under test had nothing to do with — which is a green-looking red, the exact failure
    mode this file exists to rule out."""
    return {**reg.NOT_IN_PREFLIGHT, **extra}


def _run(rows=None):
    buf = io.StringIO()
    prev = reg.NOT_IN_PREFLIGHT
    if rows is not None:
        reg.NOT_IN_PREFLIGHT = rows
    try:
        with contextlib.redirect_stdout(buf):
            rc = reg.main()
    finally:
        reg.NOT_IN_PREFLIGHT = prev
    return rc, buf.getvalue()


class BothDirectionsFail(unittest.TestCase):
    """A ratchet has two arms. Arm 1 catches a guard that arrived unwired; arm 2 catches
    a row that outlived its reason. Without the second, the excuse list can only grow —
    which is how a register turns into a place to put things."""

    def test_an_UNREGISTERED_guard_is_RED(self):
        with SeedGuard():
            rc, out = _run(rows=_rows())
        self.assertIn("arm 1 — 1 guard(s) in NO pre-flight and on NO row", out)
        self.assertIn(SEED, out)
        self.assertEqual(rc, 1, out)

    def test_a_DECLARED_guard_is_GREEN(self):
        """The control. Same seeded file, same tree, same run — the ONLY difference is
        the row, so arm 1's red cannot be firing on the seeding."""
        with SeedGuard():
            rc, out = _run(rows=_rows(**{SEED: (reg.OWED, "#0 — a constructed row",
                                                "seeded by the test")}))
        self.assertNotIn("in NO pre-flight and on NO row", out)
        self.assertEqual(rc, 0, out)

    def test_a_row_naming_a_guard_THAT_DOES_NOT_EXIST_is_RED(self):
        rc, out = _run(rows=_rows(**{"check__gone_forever.py":
                                     (reg.EXEMPT, "#0", "a row that outlived its file")}))
        self.assertIn("STALE row(s) naming a guard that does not exist", out)
        self.assertIn("check__gone_forever.py", out)
        self.assertEqual(rc, 1, out)

    def test_a_row_excusing_a_guard_the_PREFLIGHT_NOW_INVOKES_is_RED(self):
        """🔴 THE ARM THAT MAKES THE REGISTER SHRINKABLE. Paying the debt — wiring the
        guard in — must DELETE the row, and the only thing that forces that is the guard
        going red on the leftover. `check_lattice_scene`'s arm 1 has the same shape and
        the same reason: the debt is PAID; the row is the leftover."""
        wired = sorted(reg.invoked())[0]
        rc, out = _run(rows=_rows(**{wired: (reg.EXEMPT, "#0", "already wired in")}))
        self.assertIn("row(s) excusing a guard the pre-flight NOW INVOKES", out)
        self.assertIn(wired, out)
        self.assertEqual(rc, 1, out)


class AnOwedRowMustNameAnIssue(unittest.TestCase):
    """`OWED` is the reported channel, and a reported channel is where debt goes to hide.
    An address is what stops it: a row owed to nobody is indistinguishable from a row
    nobody is going to pay."""

    def test_an_OWED_row_with_no_issue_number_is_RED(self):
        with SeedGuard():
            rc, out = _run(rows=_rows(**{SEED: (reg.OWED, "2026-09-05",
                                                 "no ticket anywhere")}))
        self.assertIn("OWED row(s) with no issue number", out)
        self.assertIn(SEED, out)
        self.assertEqual(rc, 1, out)

    def test_the_SAME_row_with_an_issue_number_is_GREEN(self):
        with SeedGuard():
            rc, out = _run(rows=_rows(**{SEED: (reg.OWED, "#12345, 2026-09-05",
                                                 "ticketed")}))
        self.assertNotIn("with no issue number", out)
        self.assertEqual(rc, 0, out)

    def test_an_EXEMPT_row_needs_no_issue_number(self):
        """The difference between the two kinds, asserted rather than described. EXEMPT
        is a permanent argument and has nothing to point at; OWED is a promise."""
        with SeedGuard():
            rc, out = _run(rows=_rows(**{SEED: (reg.EXEMPT, "2026-09-05",
                                        "not a pre-flight guard, and never will be")}))
        self.assertNotIn("with no issue number", out)
        self.assertEqual(rc, 0, out)


class TheInvocationPredicateReadsCALLSNotMENTIONS(unittest.TestCase):
    """A bare substring search would score a MENTION as a run, which is the same
    confusion the registry is about, one level down — and it is not hypothetical: the
    real runner names `check_tune_owner_self_registration.py` and
    `check_test_list_coverage.py` in prose beside other rules."""

    def test_a_comment_mentioning_a_guard_is_NOT_an_invocation(self):
        with SeedGuard(), SeedRunner("# see tools/%s for the rule\ntrue\n" % SEED):
            self.assertNotIn(SEED, reg.invoked())

    def test_an_actual_call_IS_an_invocation(self):
        with SeedGuard(), SeedRunner('if ! (uv run python tools/%s); then exit 1; fi\n'
                                     % SEED):
            self.assertIn(SEED, reg.invoked())

    def test_the_OTHER_spelling_the_runner_uses_is_an_invocation(self):
        """`python3 "$PROJECT_DIR/tools/check_addon_globals.py"` — two guards are called
        this way and a predicate that only knew `uv run python tools/…` would report
        both as unwired."""
        with SeedGuard(), SeedRunner('python3 "$PROJECT_DIR/tools/%s"\n' % SEED):
            self.assertIn(SEED, reg.invoked())


class TheShippedRegisterHoldsItsOwnShape(unittest.TestCase):
    """Read off the shipped register on purpose — these are claims about the ROWS, and a
    constructed row cannot make them. Every arm above is constructed; these four are the
    ones that must fail when somebody adds a row without an argument."""

    def test_every_row_names_a_guard_that_EXISTS(self):
        for g in reg.NOT_IN_PREFLIGHT:
            self.assertTrue((TOOLS_DIR / g).is_file(), g)

    def test_every_row_names_a_guard_the_preflight_does_NOT_invoke(self):
        run = reg.invoked()
        for g in reg.NOT_IN_PREFLIGHT:
            self.assertNotIn(g, run, "%s is wired in — delete its row" % g)

    def test_every_row_has_a_kind_an_owner_and_a_reason(self):
        for g, (kind, owner, why) in reg.NOT_IN_PREFLIGHT.items():
            self.assertIn(kind, (reg.EXEMPT, reg.OWED), g)
            self.assertTrue(owner, g)
            self.assertGreater(len(why), 60, (g, why))

    def test_every_OWED_row_names_an_issue(self):
        for g, (kind, owner, _) in reg.NOT_IN_PREFLIGHT.items():
            if kind == reg.OWED:
                self.assertRegex(owner, r"#\d+", g)

    def test_the_registry_is_GREEN_on_this_tree(self):
        """The guard is in the pre-flight itself, so this is also the arm that says the
        pre-flight can still start."""
        rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertIn("✅ check_guard_registry", out)

    def test_the_registry_INVOKES_ITSELF(self):
        """A registry exempt from its own rule is the rule with a hole in it."""
        self.assertIn("check_guard_registry.py", reg.invoked())

    def test_the_owed_count_is_PRINTED_and_never_reads_as_a_pass(self):
        """A REPORTED channel that prints a number and calls the run clean is how a
        number stops being read (ADR-0205 dec. 7's argument, applied here)."""
        rc, out = _run()
        n = len([1 for k, _, _ in reg.NOT_IN_PREFLIGHT.values() if k == reg.OWED])
        self.assertIn("%d OWED." % n, out)
        self.assertIn("is\n   not zero and is not a pass", out)
        self.assertEqual(rc, 0, out)


if __name__ == "__main__":
    unittest.main()
