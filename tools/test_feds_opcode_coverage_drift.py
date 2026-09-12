"""Drift guard + correctness check for feds_opcode_coverage.json — the corpus
ordering behind the structural-authoring insert menu (ADR-0085 amendment
2026-08-18b §7).

Run from `tools/`:
    uv run python -m unittest test_feds_opcode_coverage_drift
"""
import json
import unittest

import generate_feds_opcode_coverage as gen


class TestFedsOpcodeCoverageDrift(unittest.TestCase):
    def setUp(self):
        if not gen.EFFECTS_DIR.exists():
            self.skipTest("assets/effects not present in this checkout")

    def test_committed_file_matches_corpus(self):
        self.assertEqual(
            gen.render(gen.build_doc()), gen.COVERAGE_PATH.read_text(),
            "feds_opcode_coverage.json is stale — regenerate with "
            "`uv run --project tools python tools/generate_feds_opcode_coverage.py`")

    def test_the_corpus_is_the_amendments_corpus(self):
        """The amendment measured 57 distinct opcodes over 2008 real tracks. Those
        two numbers ARE the menu's premise (offer what FFT writes, not what the
        decoder can name), so they are pinned, not left to drift silently."""
        doc = json.loads(gen.COVERAGE_PATH.read_text())
        self.assertEqual(doc["total_tracks"], 2008, "2018 slots minus the 10 null ones")
        self.assertEqual(len(doc["opcodes"]), 57, "57 distinct opcodes occur in the corpus")

    def test_ordering_is_by_track_coverage_with_a_long_tail(self):
        doc = json.loads(gen.COVERAGE_PATH.read_text())
        rows = doc["opcodes"]
        covers = [r["tracks"] for r in rows]
        self.assertEqual(covers, sorted(covers, reverse=True), "most-covered first")
        self.assertEqual(rows[0]["opcode"], "0x90", "EndBar leads — nearly every track ends")
        head = {r["opcode"] for r in rows[:8]}
        for op in ("0xAC", "0x94", "0xBA", "0xE0", "0xD4"):
            self.assertIn(op, head, "%s is one of the amendment's head opcodes" % op)
        # The long tail is the other half of the premise: a menu ordered by coverage
        # puts Detune-once-in-the-corpus at the bottom, not beside Instrument.
        self.assertLessEqual(rows[-1]["tracks"], 2, "the tail is genuinely rare")

    def test_track_coverage_never_exceeds_occurrences_or_the_corpus(self):
        doc = json.loads(gen.COVERAGE_PATH.read_text())
        for r in doc["opcodes"]:
            self.assertLessEqual(r["tracks"], r["occurrences"],
                                 "%s: a track counted once can occur many times" % r["opcode"])
            self.assertLessEqual(r["tracks"], doc["total_tracks"],
                                 "%s: cannot cover more tracks than exist" % r["opcode"])
            self.assertGreaterEqual(int(r["opcode"], 16), 0x80,
                                    "%s: note-form events are not opcodes" % r["opcode"])


if __name__ == "__main__":
    unittest.main()
