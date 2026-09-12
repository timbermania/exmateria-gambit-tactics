"""Tests for tools/parse_formation_tables.py.

Pins the formation-screen ROM data tables to the disc (ADR-0046: parse the table,
don't transcribe it). The box-trail fade ramp is the gold selection-box glide
trail's per-slot grey MULTIPLY (FORMATION_SCREEN.md §11.5.3), read from WORLD.BIN's
world overlay (VA 0x8018C88C, base 0x800E0000 → file offset 0xAC88C).

The expected bytes {20,35,50,65,80,90,100,128} are the RE-confirmed const
(memory formation-gold-box-glide-trail-solved); asserting them against the real
WORLD.BIN is what keeps the Godot TRAIL_RAMP honest.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_formation_tables
"""

from __future__ import annotations

import unittest

import parse_formation_tables as pft
from _repo_paths import world_bin


WORLD = world_bin()

# The dynamically-verified fade ramp (§11.5.3), oldest→newest.
EXPECTED_RAMP = [20, 35, 50, 65, 80, 90, 100, 128]


class OffsetMathTest(unittest.TestCase):
    """The VA→file-offset resolves to the known WORLD.BIN offset."""

    def test_fade_ramp_offset(self) -> None:
        # 0x8018C88C − 0x800E0000 = 0xAC88C
        self.assertEqual(pft._file_off(pft.BOX_TRAIL_FADE_VA), 0xAC88C)

    def test_base_matches_cursor_bob(self) -> None:
        # Same world-overlay base ADR-0046 pinned for the glove-cursor tables.
        self.assertEqual(pft.WORLD_BASE, 0x800E0000)


@unittest.skipUnless(WORLD.exists(), f"WORLD.BIN not present: {WORLD}")
class ParseTest(unittest.TestCase):
    """Parsing the real WORLD.BIN yields the RE-confirmed ramp byte-for-byte."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.data = pft.parse_formation_tables(WORLD)

    def test_ramp_bytes_match_re(self) -> None:
        self.assertEqual(self.data["box_trail_fade"]["ramp"], EXPECTED_RAMP)

    def test_ramp_is_monotone_up_to_identity(self) -> None:
        ramp = self.data["box_trail_fade"]["ramp"]
        self.assertEqual(len(ramp), pft.BOX_TRAIL_FADE_COUNT)
        for a, b in zip(ramp, ramp[1:]):
            self.assertLess(a, b)                 # oldest dimmest → newest brightest
        self.assertEqual(ramp[-1], 128)           # slot7 = gouraud identity
        self.assertEqual(self.data["box_trail_fade"]["identity"], 128)

    def test_source_provenance_recorded(self) -> None:
        src = self.data["box_trail_fade"]["source"]
        self.assertEqual(src["binary"], "WORLD.BIN")
        self.assertEqual(src["table_va"], "0x8018C88C")


if __name__ == "__main__":
    unittest.main()
