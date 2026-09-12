#!/usr/bin/env python3
"""Arms for `machine_state_sentinel.py` — the run-bracketing machine-state check (#1149).

DIRECTION-TESTED BOTH WAYS, because a sentinel that can only say "clean" is the defect it
exists to catch: `_restore_overrides` in `TileOverlayConfigTuneTest` passed every run it
ever made while leaking, since its repair early-returned on the one state that mattered.
So the four transitions of (before, after) x (absent, present) each get an arm, and the
no-drift arms are what prove the sentinel is not simply always red.
"""
import json
import pathlib
import tempfile
import unittest

import machine_state_sentinel as ms


class Digest(unittest.TestCase):
    def test_absent_file_is_a_state_not_a_missing_reading(self):
        with tempfile.TemporaryDirectory() as td:
            self.assertEqual(ms.digest(pathlib.Path(td) / "nope.json"), ms.ABSENT)

    def test_present_file_digests_its_bytes(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "f.json"
            p.write_text("{}")
            first = ms.digest(p)
            p.write_text("{} ")
            self.assertNotEqual(first, ms.ABSENT)
            self.assertNotEqual(first, ms.digest(p))


class Drift(unittest.TestCase):
    """The 2x2 of (before, after) x (absent, present). Only the diagonal is clean."""

    def test_absent_to_absent_is_clean(self):
        self.assertEqual(ms.drift({"f": ms.ABSENT}, {"f": ms.ABSENT}), [])

    def test_present_and_unchanged_is_clean(self):
        self.assertEqual(ms.drift({"f": "aa"}, {"f": "aa"}), [])

    def test_absent_to_present_names_the_creation(self):
        # 🔴 #1149's exact shape, and the one the old per-test restore could not see.
        lines = ms.drift({"f": ms.ABSENT}, {"f": "aa"})
        self.assertEqual(len(lines), 1)
        self.assertIn("CREATED", lines[0])

    def test_present_to_absent_names_the_deletion(self):
        lines = ms.drift({"f": "aa"}, {"f": ms.ABSENT})
        self.assertEqual(len(lines), 1)
        self.assertIn("DELETED", lines[0])

    def test_rewritten_names_both_digests(self):
        lines = ms.drift({"f": "a" * 64}, {"f": "b" * 64})
        self.assertEqual(len(lines), 1)
        self.assertIn("rewritten", lines[0])
        self.assertIn("aaaaaaaaaaaa", lines[0])
        self.assertIn("bbbbbbbbbbbb", lines[0])


class Cli(unittest.TestCase):
    def test_missing_statefile_is_not_a_verdict(self):
        """A half-open bracket (the snapshot never ran) must not score the tree red — it
        reports and stays green, or a runner edit turns into a suite-wide failure."""
        with tempfile.TemporaryDirectory() as td:
            self.assertEqual(ms.main(["--compare", str(pathlib.Path(td) / "gone.json")]), 0)

    def test_snapshot_writes_every_watched_path(self):
        with tempfile.TemporaryDirectory() as td:
            state = pathlib.Path(td) / "s.json"
            self.assertEqual(ms.main(["--snapshot", str(state)]), 0)
            self.assertEqual(sorted(json.loads(state.read_text())), sorted(ms.WATCHED))

    def test_compare_consumes_the_statefile(self):
        """It unlinks on read, so a stale snapshot from a killed run cannot referee the
        next one — a verdict only ever compares to one from the SAME run."""
        with tempfile.TemporaryDirectory() as td:
            state = pathlib.Path(td) / "s.json"
            ms.main(["--snapshot", str(state)])
            ms.main(["--compare", str(state)])
            self.assertFalse(state.exists())


class Scope(unittest.TestCase):
    def test_the_watched_path_is_the_one_with_three_recurrences(self):
        self.assertIn("config/tune_overrides.json", ms.WATCHED)


if __name__ == "__main__":
    unittest.main()
