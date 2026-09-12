"""Drift guard: FedsInstrumentNames.gd must match the DAW picker table it was
generated from (the feds.json table-sync lesson — a stale copy quietly lies).
Skips when the fft-plugin package is absent (e.g. a partial checkout).

Run from `tools/`:  uv run python -m unittest test_feds_instrument_names_drift
"""
import re
import unittest
from pathlib import Path

import generate_feds_instrument_names as gen


class TestFedsInstrumentNamesDrift(unittest.TestCase):
    def test_generated_file_matches_daw_table(self):
        if not gen.SOURCE.exists():
            self.skipTest("fft-plugin not present in this checkout")
        expected = gen.render(gen.parse_names(gen.SOURCE.read_text()))
        actual = gen.TARGET.read_text()
        self.assertEqual(
            expected, actual,
            "FedsInstrumentNames.gd is stale — regenerate with "
            "`uv run python tools/generate_feds_instrument_names.py`")

    def test_table_covers_the_byte_space_reasonably(self):
        if not gen.SOURCE.exists():
            self.skipTest("fft-plugin not present in this checkout")
        names = gen.parse_names(gen.SOURCE.read_text())
        self.assertGreater(len(names), 200, "picker table should name most ids")
        self.assertIn(64, names)
        self.assertIn("Timpani", names[64][0])


if __name__ == "__main__":
    unittest.main()
