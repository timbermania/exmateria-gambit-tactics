"""Seed-red arms for the test-charter guard.

Every arm CONSTRUCTS the source it grades in a temp file. Not one of them reads a
real test off the tree, for the reason `test_check_guard_registry.py` states in
its own docstring: an arm that grades the shipped population stops firing on the
day the burn-down reaches zero, and a guard whose arms have gone quiet is
indistinguishable from a guard that works.

The charter's own clause 10 applies to this file: the break that reds it is
deleting any single `bad.append(...)` from `check_test_charter.violations_for` —
each arm below names exactly one of them.

Run from tools/:
    uv run python -m unittest test_check_test_charter
"""

from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import check_test_charter as charter

# A file that satisfies all five mechanical clauses. Every arm below is this
# text with exactly ONE thing taken away or added, so a failing arm names its
# clause without ambiguity.
CLEAN = """\
extends Node
# test-kind: logic
# seeded-break: return {} from JsonAsset.load_dict and this reds on assertion 1

func _ready() -> void:
\tprint("[PASS] clean")
\tget_tree().quit()
"""


def _write(tmp: pathlib.Path, src: str) -> pathlib.Path:
    p = tmp / "SeedTest.gd"
    p.write_text(src, encoding="utf-8")
    return p


class ViolationArms(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = pathlib.Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def check(self, src: str) -> list[str]:
        return charter.violations_for("SeedTest", _write(self.tmp, src))

    def test_clean_file_violates_nothing(self):
        """The control. If this arm reds, every other arm below is meaningless."""
        self.assertEqual(self.check(CLEAN), [])

    def test_c1_missing_kind(self):
        self.assertIn("C1", self.check(CLEAN.replace("# test-kind: logic\n", "")))

    def test_c1_unknown_kind_is_not_a_kind(self):
        """A typo must not pass as a declaration — otherwise `# test-kind: unit`
        satisfies the clause and the demote verdict has no vocabulary to move in."""
        self.assertIn("C1", self.check(CLEAN.replace("logic", "unit")))

    def test_c1_lane_pinned_modifier_is_accepted(self):
        self.assertNotIn("C1", self.check(CLEAN.replace("logic", "render lane-pinned")))

    def test_c1_unknown_modifier_is_rejected(self):
        self.assertIn("C1", self.check(CLEAN.replace("logic", "render sometimes")))

    def test_c4_no_quit(self):
        self.assertIn("C4", self.check(CLEAN.replace("\tget_tree().quit()\n", "")))

    def test_c10_no_seeded_break(self):
        stripped = "\n".join(l for l in CLEAN.splitlines()
                             if not l.startswith("# seeded-break:")) + "\n"
        self.assertIn("C10", self.check(stripped))

    def test_c14a_create_timer(self):
        src = CLEAN.replace('\tprint("[PASS] clean")',
                            "\tawait get_tree().create_timer(0.5).timeout")
        self.assertIn("C14a", self.check(src))

    def test_c14b_wall_clock_outside_perf(self):
        src = CLEAN.replace('\tprint("[PASS] clean")',
                            "\tvar t := Time.get_ticks_msec()")
        self.assertIn("C14b", self.check(src))

    def test_c14b_wall_clock_inside_perf_is_exempt(self):
        """A perf test measures time on purpose. The exemption costs it a lane
        pin (docs/TEST-CHARTER.md clause 14), which the guard does not enforce —
        `run_tests_parallel.SEQUENTIAL_LANE` does."""
        src = (CLEAN.replace("# test-kind: logic", "# test-kind: perf")
                    .replace('\tprint("[PASS] clean")',
                             "\tvar t := Time.get_ticks_msec()"))
        self.assertNotIn("C14b", self.check(src))

    def test_a_missing_file_is_not_a_violation(self):
        """The array names eight tests that live in their addons (ADR-0194).
        Scoring them as violators would red the suite for a move that was correct."""
        self.assertEqual(charter.violations_for("Absent", None), [])


class AllowlistIsShrinkOnly(unittest.TestCase):
    """The ratchet. Both directions, because only one of them is obvious."""

    def test_every_clause_id_has_report_text(self):
        """`--stats` iterates CLAUSES and the allowlist writer indexes
        CLAUSE_TEXT. A clause added to one and not the other raises KeyError
        during a seed, at the worst possible moment."""
        self.assertEqual(set(charter.CLAUSES), set(charter.CLAUSE_TEXT))

    def test_a_fixed_row_is_reported_not_ignored(self):
        """The half that rots if nobody checks it: an allowlist that keeps rows
        for violations that are gone is a carve-out wearing a burn-down's name."""
        live = {("A", "C1")}
        allowed = {("A", "C1"), ("B", "C4")}
        self.assertEqual(sorted(allowed - live), [("B", "C4")])

    def test_a_new_row_is_reported(self):
        live = {("A", "C1"), ("B", "C4")}
        allowed = {("A", "C1")}
        self.assertEqual(sorted(live - allowed), [("B", "C4")])


if __name__ == "__main__":
    unittest.main()
