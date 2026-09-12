#!/usr/bin/env python3
"""Guard for survey_camera_param_flags.py.

Runs the survey over the real vanilla effect set and asserts the aggregate
invariants that a prior manual scan established, plus the legit/suspect split
that the misparsed E471 table exposed. If the parser or the effect set changes
in a way that moves these numbers, this guard fires so the conclusion in the RE
writeup (param/flags are inert dead bits) can be re-checked.

Skips cleanly when the ROM-derived assets aren't present (e.g. CI without
project-assets).

Run:
    cd tools && uv run python -m unittest survey_camera_param_flags_test
"""

import unittest

import survey_camera_param_flags as S


def _assets_present() -> bool:
    return S._DEFAULT_EFFECT_DIR.is_dir() and S._DEFAULT_BATTLE_BIN.is_file()


@unittest.skipUnless(_assets_present(), "vanilla effect assets not present")
class SurveyInvariantsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = S.survey(S._DEFAULT_EFFECT_DIR, S._DEFAULT_BATTLE_BIN)

    def test_coverage_is_all_non_empty_effects(self):
        # 401 real effects + 111 empty (0-byte) slots = 512; no genuine parse failures.
        self.assertEqual(self.result.files_scanned, 401)
        self.assertEqual(len(self.result.files_empty), 111)
        self.assertEqual(self.result.files_failed, [])

    def test_keyframe_total_and_histograms(self):
        self.assertEqual(self.result.camera_keyframes_total, 23659)
        self.assertEqual(self.result.param_histogram, {0: 23564, 1: 49, 2: 7, 3: 39})
        self.assertEqual(self.result.flags_histogram, {0: 23639, 2: 1, 5: 1, 6: 1, 7: 17})

    def test_legit_vs_suspect_split(self):
        legit = [h for h in self.result.hits if not h.suspect]
        suspect = [h for h in self.result.hits if h.suspect]
        self.assertEqual(len(self.result.hits), 95)
        self.assertEqual(len(legit), 75)
        self.assertEqual(len(suspect), 20)

    def test_flags_is_never_set_on_a_legit_keyframe(self):
        # The whole non-functional-flags conclusion rests on this: every non-zero
        # flags value in the ROM comes from the misparsed E471 phase2 padding table.
        legit_flag_hits = [h for h in self.result.hits if not h.suspect and h.flags]
        self.assertEqual(legit_flag_hits, [])

    def test_all_suspect_hits_are_E471(self):
        suspect_files = {h.file for h in self.result.hits if h.suspect}
        self.assertEqual(suspect_files, {"E471.BIN"})

    def test_param_legit_source_mode_clusters(self):
        # param clusters by source_mode (a lead, not a proven semantic — the engine
        # never reads the bits, per the static RE). Lock the observed shape.
        from collections import Counter
        legit = [h for h in self.result.hits if not h.suspect and h.param]
        by = Counter((h.param, h.source_mode) for h in legit)
        self.assertEqual(by[(3, "CASTER")], 21)
        self.assertEqual(by[(1, "SLOT_COPY")], 30)
        self.assertEqual(by[(1, "MAP")], 15)


if __name__ == "__main__":
    unittest.main()
