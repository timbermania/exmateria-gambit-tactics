"""Tests for the run-time harness stamps — #454, map #450.

These two lines are the difference between a register whose provenance is
CHECKABLE and one whose provenance is assumed. The failure they exist to prevent
is quiet: a register read months later against a tree whose addon copy has since
been resynced and whose `.godot/` has since been wiped, with nothing in the file
saying either happened.
"""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import harness_stamp
import suite_register


class TheCacheStampSaysWhatTheEngineHadToRedo(unittest.TestCase):

    def test_no_dot_godot_is_cold_and_says_the_wall_clock_is_not_comparable(self):
        with tempfile.TemporaryDirectory() as tmp:
            s = harness_stamp.godot_cache_stamp(tmp)
            self.assertTrue(s.startswith("COLD"))
            self.assertIn("not comparable", s)

    def test_an_empty_import_cache_is_cold_not_warm_with_zero(self):
        """`warm — 0 imported files` would read as a warm run. It is a cold one."""
        with tempfile.TemporaryDirectory() as tmp:
            (pathlib.Path(tmp) / ".godot" / "imported").mkdir(parents=True)
            self.assertTrue(harness_stamp.godot_cache_stamp(tmp).startswith("COLD"))

    def test_a_populated_import_cache_is_warm_and_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp) / ".godot" / "imported"
            d.mkdir(parents=True)
            for i in range(3):
                (d / f"x{i}.md5").write_text("")
            (pathlib.Path(tmp) / ".godot" / "shader_cache").mkdir()
            s = harness_stamp.godot_cache_stamp(tmp)
            self.assertIn("warm", s)
            self.assertIn("3 imported", s)
            self.assertIn("shader cache present", s)

    def test_a_missing_shader_cache_is_named_rather_than_omitted(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp) / ".godot" / "imported"
            d.mkdir(parents=True)
            (d / "x.md5").write_text("")
            self.assertIn("NO shader cache", harness_stamp.godot_cache_stamp(tmp))


class TheBannerLinesAreWhatTheRegisterReads(unittest.TestCase):
    """The contract between the runners and `suite_register.take`."""

    def test_both_lines_are_at_the_indent_the_register_parses(self):
        for line in harness_stamp.banner_lines().splitlines():
            self.assertIsNotNone(suite_register.FIELD_RE.match(line),
                                 f"{line!r} is not a banner field the register reads")

    def test_neither_line_can_be_mistaken_for_a_test_verdict(self):
        """`  -> WORD` is what `freeze_test_baseline.verdicts()` pairs with a
        `Running` line. A banner line in that shape corrupts the register it was
        added to make trustworthy."""
        for line in harness_stamp.banner_lines().splitlines():
            self.assertIsNone(suite_register.VERDICT_RE.match(line))

    def test_the_addon_line_is_the_owning_tools_stamp_not_a_restatement(self):
        import check_addon_sync
        self.assertIn(check_addon_sync.stamp(), harness_stamp.banner_lines())


if __name__ == "__main__":
    unittest.main()


class TheCoverageStampIsTheRunsReadingOfTheTree(unittest.TestCase):
    """#417's triple, stamped by the run rather than derived when it is read."""

    def test_it_counts_the_owning_guards_states_and_does_not_re_derive_them(self):
        import check_test_list_coverage as ctlc
        states = ctlc.classify()
        s = harness_stamp.test_coverage_stamp()
        self.assertIn(f"{len(states)} scenes on disk", s)
        listed = sum(1 for st, _ in states.values() if st == "listed")
        self.assertIn(f"{listed} listed", s)

    def test_the_four_states_sum_to_the_total(self):
        """744 = 687 + 33 + 24 + 0 is the shipped rule (#417). A stamp whose
        parts do not add up is quoting a filter, not a partition."""
        import re
        s = harness_stamp.test_coverage_stamp()
        total = int(re.match(r"(\d+) scenes", s).group(1))
        parts = [int(n) for n in re.findall(r"(\d+) (?:listed|declares|skipped|unclassified)", s)]
        self.assertEqual(len(parts), 4)
        self.assertEqual(sum(parts), total)

    def test_a_tree_with_no_tests_dir_stamps_zero_rather_than_throwing(self):
        """A stamp runs inside the banner. It must never be the thing that
        aborts a 100-minute suite."""
        with tempfile.TemporaryDirectory() as tmp:
            s = harness_stamp.test_coverage_stamp(tmp)
            self.assertTrue(s.startswith("0 scenes on disk") or s.startswith("UNKNOWN"), s)
