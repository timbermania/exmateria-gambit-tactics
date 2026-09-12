"""Tests for the sequential-vs-parallel verdict diff (#453, map #450).

WHAT THIS INSTRUMENT HAS TO GET RIGHT. #453's deliverable is not a speedup, it
is an attribution: every test whose verdict moves between the arms is a finding,
and a finding is only worth acting on once "parallelism changed it" has been
separated from "it was already flaky". Those two look identical in a single pair
of runs, so the diff takes REPEATS and refuses to call a mover without them.

The second thing it has to get right is the one the corpus taught this session:
the five archived suite runs are on DIFFERENT COMMITS, and reading them as five
samples of one tree reports 25 flaky tests where the three same-tree runs report
4. A verdict is only comparable to a verdict from the same tree, so the diff
never merges arms it was not told are the same tree.
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import diff_arm_verdicts as dav


def arm(*runs):
    """Each run is a dict stem -> verdict."""
    return list(runs)


class ClassifiesEachTest(unittest.TestCase):

    def test_same_everywhere_is_agree(self):
        c = dav.classify("T", arm({"T": "PASS"}, {"T": "PASS"}), arm({"T": "PASS"}))
        self.assertEqual(c.state, "AGREE")

    def test_constant_in_both_but_different_is_moved(self):
        c = dav.classify("T", arm({"T": "PASS"}, {"T": "PASS"}),
                              arm({"T": "FAIL"}, {"T": "FAIL"}))
        self.assertEqual(c.state, "MOVED")

    def test_varies_within_sequential_is_already_flaky(self):
        """The sequential arm disagreeing with ITSELF settles it — parallelism
        cannot be blamed for a verdict that was never stable to begin with."""
        c = dav.classify("T", arm({"T": "PASS"}, {"T": "FAIL"}), arm({"T": "FAIL"}))
        self.assertEqual(c.state, "FLAKY_SEQUENTIAL")

    def test_sequential_flake_wins_over_a_parallel_flake(self):
        c = dav.classify("T", arm({"T": "PASS"}, {"T": "FAIL"}),
                              arm({"T": "PASS"}, {"T": "FAIL"}))
        self.assertEqual(c.state, "FLAKY_SEQUENTIAL")

    def test_stable_sequential_unstable_parallel_is_flaky_parallel(self):
        c = dav.classify("T", arm({"T": "PASS"}),
                              arm({"T": "PASS"}, {"T": "FAIL"}, {"T": "PASS"}))
        self.assertEqual(c.state, "FLAKY_PARALLEL")

    def test_a_known_flake_is_never_called_a_mover(self):
        """One sequential run cannot see a flake. The corpus can, and passing it
        in is how a single-arm diff stays honest."""
        c = dav.classify("T", arm({"T": "PASS"}), arm({"T": "FAIL"}),
                         known_flakes={"T"})
        self.assertEqual(c.state, "FLAKY_SEQUENTIAL")

    def test_missing_from_an_arm_is_its_own_state(self):
        c = dav.classify("T", arm({"T": "PASS"}), arm({}))
        self.assertEqual(c.state, "MISSING")


class RefusesToOvercallOnOneRepeat(unittest.TestCase):
    """A single parallel run cannot distinguish a mover from a coin flip."""

    def test_one_parallel_repeat_is_flagged_unconfirmed(self):
        c = dav.classify("T", arm({"T": "PASS"}), arm({"T": "FAIL"}))
        self.assertEqual(c.state, "MOVED")
        self.assertFalse(c.confirmed)

    def test_two_agreeing_parallel_repeats_confirm_it(self):
        c = dav.classify("T", arm({"T": "PASS"}), arm({"T": "FAIL"}, {"T": "FAIL"}))
        self.assertTrue(c.confirmed)

    def test_agree_needs_no_confirmation(self):
        c = dav.classify("T", arm({"T": "PASS"}), arm({"T": "PASS"}))
        self.assertTrue(c.confirmed)


class ProposesTheLane(unittest.TestCase):
    """The lane is generated FROM the diff, with the counts in the reason."""

    def setUp(self):
        self.seq = arm({"A": "PASS", "B": "PASS", "C": "PASS", "D": "PASS"})
        self.par = arm({"A": "PASS", "B": "FAIL", "C": "PASS", "D": "FAIL"},
                       {"A": "PASS", "B": "FAIL", "C": "PASS", "D": "PASS"})

    def test_movers_and_parallel_flakes_are_laned(self):
        lane = dav.propose_lane(dav.diff(self.seq, self.par))
        self.assertEqual(set(lane), {"B", "D"})

    def test_agreeing_tests_are_not_laned(self):
        lane = dav.propose_lane(dav.diff(self.seq, self.par))
        self.assertNotIn("A", lane)
        self.assertNotIn("C", lane)

    def test_each_reason_carries_its_counts(self):
        lane = dav.propose_lane(dav.diff(self.seq, self.par))
        self.assertIn("2/2", lane["B"])
        self.assertIn("PASS", lane["B"])
        self.assertIn("FAIL", lane["B"])

    def test_a_known_flake_stays_out_of_the_lane(self):
        d = dav.diff(self.seq, self.par, known_flakes={"B", "D"})
        self.assertEqual(dav.propose_lane(d), {})

    def test_the_lane_is_valid_python_for_the_runner(self):
        lane = dav.propose_lane(dav.diff(self.seq, self.par))
        ns = {}
        exec("SEQUENTIAL_LANE = " + dav.render_lane(lane), ns)
        self.assertEqual(ns["SEQUENTIAL_LANE"], lane)


class ReadsRunsTheOneWay(unittest.TestCase):
    """Both arms are parsed by the reading the register already uses."""

    def test_parses_the_runner_stdout_shape(self):
        tmp = pathlib.Path(__file__).parent / ".dav_probe.log"
        tmp.write_text("[1/2] Running Alpha...\n  -> PASS\n"
                       "[2/2] Running Beta...\n  -> THREW\n")
        try:
            self.assertEqual(dav.read_run(tmp), {"Alpha": "PASS", "Beta": "THREW"})
        finally:
            tmp.unlink()

    def test_delegates_to_the_registers_reader(self):
        import freeze_test_baseline as fz
        real = fz.verdicts
        fz.verdicts = lambda p: {"SENTINEL": "PASS"}
        try:
            self.assertEqual(dav.read_run(pathlib.Path("/nonexistent")),
                             {"SENTINEL": "PASS"})
        finally:
            fz.verdicts = real


if __name__ == "__main__":
    unittest.main()
