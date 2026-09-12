"""Unit tests for the effect_flags.json parse output (#272, ADR-0092).

`parse_effect.parse_effect_file` must include an `effect_flags` block, and
`save_effect` must write it as `effect_flags.json` (present in EVERY effect — it
carries the round-trip raw flags byte the Effect Studio flags editor seeds from).

Run from tools/:
    uv run python -m unittest test_parse_effect_flags_output
"""

from __future__ import annotations

import json
import os
import tempfile
import unittest

import parse_effect as pe

_EXTRACT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "..", "project-assets", "fft-extract", "EFFECT"
)
_E019 = os.path.join(_EXTRACT_DIR, "E019.BIN")
_BATTLE = os.path.join(_EXTRACT_DIR, "..", "BATTLE.BIN")


class FlagsOutputWiring(unittest.TestCase):
    def test_json_outputs_lists_effect_flags(self):
        names = [name for name, _key in pe._JSON_OUTPUTS]
        self.assertIn("effect_flags.json", names,
                      "effect_flags.json is an unconditional per-effect output")

    def test_parse_effect_flags_decodes_engine_bits(self):
        # 0x68 = bits 3,5,6 → terrain + both time-scale enables, no audio-fade.
        data = bytes([0x68])
        got = pe.parse_effect_flags(data, 0)
        self.assertEqual(got, {
            "flags_byte": 0x68,
            "terrain_height_adjust": True,
            "audio_fade": False,
            "time_scale_pattern1": True,
            "time_scale_pattern2": True,
        })


@unittest.skipUnless(os.path.exists(_E019) and os.path.exists(_BATTLE),
                     "E019 / BATTLE.BIN extract not present")
class RealE019EndToEnd(unittest.TestCase):
    def test_extract_writes_effect_flags_json_with_raw_byte(self):
        with tempfile.TemporaryDirectory() as out:
            parsed = pe.parse_effect_file(
                _E019, header_offset=pe.load_vfx_header_offset(_BATTLE, 19))
            self.assertIn("effect_flags", parsed, "parsed dict carries the effect_flags block")
            pe.save_effect(parsed, out)
            fp = os.path.join(out, "effect_flags.json")
            self.assertTrue(os.path.exists(fp), "save_effect wrote effect_flags.json")
            doc = json.loads(open(fp).read())
            # E019's raw flags byte is 0x23 (bits 0,1 ignored + bit5) — independently confirmed.
            self.assertEqual(doc["flags_byte"], 0x23)
            self.assertTrue(doc["time_scale_pattern1"])
            self.assertFalse(doc["time_scale_pattern2"])


if __name__ == "__main__":
    unittest.main()
