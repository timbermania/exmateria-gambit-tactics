"""Tests for the register's runner-provenance header (#453, map #450).

WHY THIS FILE EXISTS. `TEST-BASELINE-E2.tsv`'s header carries a `runner` line
reading `bash tests/run_all_tests.sh  sequential, never parallel`, and #453
adopts a SECOND arm — `tools/run_tests_parallel.py`. That line was a hardcoded
string: a register captured with the parallel runner would have claimed to be
sequential, and nothing in the file or the tool would have said otherwise.

A provenance field that cannot be wrong about the run it describes is the whole
point of the header — map #450 has already been burned once by comparing two
runs as one (#451's direction 1 was a provenance error, not a scoring bug). So
the field is DERIVED from the captured stdout's own banner, which both runners
now print, and a log with no banner says UNKNOWN rather than inheriting a claim.
"""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import freeze_test_baseline as f

# The sequential runner prints 27 pre-flights BEFORE its banner, so a
# fixed-size head window would miss it. That preamble is reproduced here.
SEQ_BANNER = """\
Checking combat buffer layout is up to date...
combat buffer layout: up to date
Checking ability database / view are up to date...
AbilityDatabase.gd / AbilityView.gd are up to date.
Running test-verdict reader tests...
OK
======================================
  GPU Combat Test Suite
  Running 412 tests
  code_commit c546fbbb4
  godot 4.8.dev.custom_build
  started 2026-08-24T10:00:00-07:00
======================================

[1/412] Running JsonAssetTest...
  -> PASS
"""

PAR_BANNER = """\
======================================
  GPU Combat Test Suite — PARALLEL
  Running 412 tests, 8 workers, 0 in the sequential lane
  code_commit c546fbbb4
  godot 4.8.dev.custom_build
======================================
[1/412] Running JsonAssetTest...
  -> PASS
"""

BINDER_LOG = """\
Running unlisted audio binders...
[1/21] Running FedsInstrumentMetaTest...
  -> PASS
"""


def _log(text):
    fh = tempfile.NamedTemporaryFile("w", suffix=".log", delete=False)
    fh.write(text)
    fh.close()
    return pathlib.Path(fh.name)


class RunnerProvenance(unittest.TestCase):
    def test_sequential_banner_reads_sequential(self):
        cmd, prop = f.runner_provenance([_log(SEQ_BANNER)])
        self.assertEqual(cmd, "bash tests/run_all_tests.sh")
        self.assertEqual(prop, "sequential")

    def test_parallel_banner_carries_its_worker_count(self):
        """N is the number the register is being read against — a parallel
        capture at N=8 and one at N=2 are not the same instrument."""
        cmd, prop = f.runner_provenance([_log(PAR_BANNER)])
        self.assertEqual(cmd, "uv run python tools/run_tests_parallel.py -N 8")
        self.assertEqual(prop, "parallel N=8, 0 in the sequential lane")

    def test_a_lane_entry_is_reported_not_dropped(self):
        """A laned test did NOT run under contention. Dropping that from the
        header would make two registers with different lanes look identical."""
        text = PAR_BANNER.replace("0 in the sequential lane",
                                  "3 in the sequential lane")
        _, prop = f.runner_provenance([_log(text)])
        self.assertEqual(prop, "parallel N=8, 3 in the sequential lane")

    def test_a_log_with_no_banner_is_unknown_not_assumed(self):
        """The binder runs print no banner. The old hardcoded line named
        `run_unlisted_audio_binders.sh` for them — true of the 2026-08-22
        capture and unfalsifiable for any other, which is the shape this
        header exists to prevent."""
        cmd, prop = f.runner_provenance([_log(BINDER_LOG)])
        self.assertEqual(cmd, "UNKNOWN")
        self.assertIn("no runner banner", prop)

    def test_two_logs_report_both_arms(self):
        """The register is captured from the suite run PLUS a separate binder
        run. One field, both provenances, neither invented."""
        cmd, prop = f.runner_provenance([_log(SEQ_BANNER), _log(BINDER_LOG)])
        self.assertIn("bash tests/run_all_tests.sh", cmd)
        self.assertIn("UNKNOWN", cmd)
        self.assertIn("sequential", prop)

    def test_a_scene_cannot_restate_the_provenance(self):
        """A test PRINTING the banner's words must not be able to relabel the
        run. The scan stops at the first `[1/N] Running` line — the banner
        always precedes it and test output always follows it."""
        text = SEQ_BANNER + "\n".join(
            ["  -> PASS"] * 200 + ["  GPU Combat Test Suite — PARALLEL",
                                   "  Running 412 tests, 99 workers, 0 in the sequential lane"])
        _, prop = f.runner_provenance([_log(text)])
        self.assertEqual(prop, "sequential")

    def test_the_preflights_do_not_hide_the_banner(self):
        """The bug this anchor replaced: a 12-line head window read the real
        sequential arm as UNKNOWN, because 27 pre-flights come first."""
        self.assertIn("Checking combat buffer layout", SEQ_BANNER)
        cmd, _ = f.runner_provenance([_log(SEQ_BANNER)])
        self.assertEqual(cmd, "bash tests/run_all_tests.sh")

    def test_frozen_e2_header_still_reads_sequential(self):
        """⚠️ `docs/TEST-BASELINE-E2.tsv` stays frozen and its own `runner`
        line stays true — this change may not rewrite history."""
        # `OUT` is relative — the tool is run from the package root, this test
        # from anywhere.
        tsv = pathlib.Path(__file__).resolve().parent.parent / f.OUT
        if not tsv.exists():
            self.skipTest("frozen register not in this checkout")
        line = next(l for l in tsv.read_text().splitlines()
                    if l.startswith("# runner"))
        self.assertIn("bash tests/run_all_tests.sh", line)
        self.assertIn("sequential", line)


if __name__ == "__main__":
    unittest.main()
