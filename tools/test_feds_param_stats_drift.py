"""Drift guard + correctness check for feds_param_stats.json — the empirical
usage range behind ADR-0085's opcode-param honesty amendment (2026-08-12).

The committed JSON is the SHARED source for the empirical range AND per-param
signedness (the Python producer here and the GDScript descriptor read the same
file, so they can't disagree). This guards it against corpus drift and pins the
signed-space arithmetic with a hand-computed oracle.

Run from `tools/`:  uv run python -m unittest test_feds_param_stats_drift
"""
import unittest

import generate_feds_param_stats as gen


class TestFedsParamStatsDrift(unittest.TestCase):
    def test_committed_file_matches_corpus(self):
        if not gen.EFFECTS_DIR.exists():
            self.skipTest("assets/effects not present in this checkout")
        expected = gen.render(gen.build_doc())
        actual = gen.STATS_PATH.read_text()
        self.assertEqual(
            expected, actual,
            "feds_param_stats.json is stale — regenerate with "
            "`uv run python tools/generate_feds_param_stats.py`")

    # --- Correctness: an INDEPENDENT hand-computed oracle -------------------
    # 0xD3 PitchBend_Add_16bit is a signed 16-bit param (high<<8 | low). It
    # occurs exactly 15 times in the shipped corpus; hand-enumerating those 15
    # signed values (big-endian, two's-complement) gives:
    #   -759,-205,-96,-37,-3,-2,1,1,1,4,17,40,43,294,1536  (sorted)
    # → n=15, min=-759, max=1536, lower-median=1, mode=1 (the value 1 recurs 3x).
    # These literals come from the opcode spec + a by-hand corpus count, never
    # from the generator's own aggregation.
    def test_signed16_pitchbend_stats_are_hand_computed(self):
        if not gen.EFFECTS_DIR.exists():
            self.skipTest("assets/effects not present in this checkout")
        e = gen.build_doc()["stats"]["0xD3:0"]
        self.assertTrue(e["signed"], "0xD3 param is signed")
        self.assertEqual(e["bits"], 16, "0xD3 folds its two bytes into one signed word")
        self.assertEqual(e["n"], 15)
        self.assertEqual(e["min"], -759)
        self.assertEqual(e["max"], 1536)
        self.assertEqual(e["median"], 1)
        self.assertEqual(e["mode"], 1)

    # A signed-8 param whose raw bytes span 0..255 can only report a NEGATIVE
    # min if sign-extension actually happened (a raw byte is never < 0). This is
    # a behavioural check of the signed-space scan, independent of any literal.
    def test_signed8_params_are_scanned_in_signed_space(self):
        if not gen.EFFECTS_DIR.exists():
            self.skipTest("assets/effects not present in this checkout")
        stats = gen.build_doc()["stats"]
        d2 = stats["0xD2:0"]   # PitchBendRel — signed byte
        self.assertTrue(d2["signed"] and d2["bits"] == 8)
        self.assertLess(d2["min"], 0,
            "a signed byte reports negatives — impossible without sign-extension")
        self.assertLessEqual(d2["max"], 127, "signed byte tops out at +127")

    # --- Per-instrument bucket (ADR-0085 2026-08-12 amendment) --------------
    # The range is ALSO bucketed by the ACTIVE INSTRUMENT — the last 0xAC earlier
    # in the SAME track (per-TrackState runtime state). 0xD3 occurs 15× globally,
    # but only 8 of those samples follow an in-track 0xAC; the other 7 have no
    # active instrument and feed ONLY the global stats. Under instrument 119 the
    # four signed-word samples are [-2, 1, 1, 1] (hand-enumerated from the corpus,
    # big-endian two's-complement) → n=4, min=-2, max=1, median=1, mode=1. These
    # literals come from a by-hand corpus count, never the generator's own emit.
    def test_per_instrument_bucket_is_hand_computed(self):
        if not gen.EFFECTS_DIR.exists():
            self.skipTest("assets/effects not present in this checkout")
        e = gen.build_doc()["stats"]["0xD3:0"]
        self.assertIn("by_instrument", e, "every entry emits a per-instrument bucket")
        by = e["by_instrument"]
        self.assertIn("119", by, "instrument 119 used 0xD3 in the corpus")
        self.assertEqual(
            by["119"], {"min": -2, "max": 1, "median": 1, "mode": 1, "n": 4})

    # The None-instrument samples (no 0xAC yet in-track) are NOT a bucket — they
    # feed only the global stats. So the per-instrument buckets for 0xD3 sum to
    # strictly FEWER than the global n (8 bucketed < 15 global).
    def test_uninstrumented_samples_are_not_a_bucket(self):
        if not gen.EFFECTS_DIR.exists():
            self.skipTest("assets/effects not present in this checkout")
        e = gen.build_doc()["stats"]["0xD3:0"]
        bucketed = sum(int(b["n"]) for b in e["by_instrument"].values())
        self.assertEqual(bucketed, 8, "only the in-track-0xAC samples are bucketed")
        self.assertLess(bucketed, int(e["n"]),
            "uninstrumented samples feed global but no instrument bucket")

    # An uncurated UNSIGNED param still gets a range (that is the whole point —
    # confusing raw scalars like Portamento_Init's rate get an empirical range).
    def test_unsigned_params_get_a_range_too(self):
        if not gen.EFFECTS_DIR.exists():
            self.skipTest("assets/effects not present in this checkout")
        stats = gen.build_doc()["stats"]
        rate = stats["0xD4:1"]   # Portamento_Init param 1 = rate (the design example)
        self.assertFalse(rate["signed"])
        self.assertGreaterEqual(rate["min"], 0)
        self.assertGreater(rate["n"], 0)


if __name__ == "__main__":
    unittest.main()
