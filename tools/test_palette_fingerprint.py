#!/usr/bin/env python3
"""Guard for the palette-fingerprint owner resolver.

A composite EVTCHR segment packs several characters' art into one sheet, told
apart by CLUT row. The redesign identifies a frame-band's true owner by matching
the segment CLUT row it renders with against every flat-store SPR palette
(exact / distance-0 match, ignoring near-black). This is the mechanism the
prototype de-risked (seg48 rows 0/1/2/3 -> SPR 0x18/0x05/0x24/0x0C, all dist-0).

Run:  uv run python -m unittest test_palette_fingerprint
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import palette_fingerprint as pf
from extract_spr import write_tga


def _clut16(rows_colors: dict) -> list:
    """16x16 CLUT pixels: rows_colors {row -> [(r,g,b,a), ...]} on that row, rest 0."""
    px = []
    for r in range(16):
        cols = rows_colors.get(r, [])
        for c in range(16):
            px.append(cols[c] if c < len(cols) else (0, 0, 0, 0))
    return px


class ColorSetDistanceTest(unittest.TestCase):
    def test_identical_sets_are_distance_zero(self):
        a = [(10, 20, 30, 255), (40, 50, 60, 255)]
        self.assertEqual(pf.color_set_distance(a, list(reversed(a))), 0.0)

    def test_disjoint_sets_are_far(self):
        a = [(10, 20, 30, 255)]
        b = [(200, 200, 200, 255)]
        self.assertGreater(pf.color_set_distance(a, b), 100.0)


class NearestSpriteTest(unittest.TestCase):
    def test_exact_match_wins_over_near_miss(self):
        target = [(100, 0, 0, 255), (0, 100, 0, 255)]
        palettes = {
            0x05: [(0, 100, 0, 255), (100, 0, 0, 255)],   # same set, shuffled -> dist 0
            0x0C: [(90, 10, 0, 255), (0, 90, 10, 255)],   # close but not exact
        }
        self.assertEqual(pf.nearest_sprite(target, palettes), 0x05)

    def test_no_exact_match_returns_none(self):
        target = [(100, 0, 0, 255)]
        palettes = {0x05: [(50, 50, 50, 255)]}
        self.assertIsNone(pf.nearest_sprite(target, palettes))

    def test_near_black_is_ignored_in_the_fingerprint(self):
        # A row's dark/transparent entries must not drag the match.
        target = [(100, 0, 0, 255), (2, 1, 0, 255)]     # 2nd is near-black
        palettes = {0x05: [(100, 0, 0, 255)]}            # only the bright color
        self.assertEqual(pf.nearest_sprite(target, palettes), 0x05)


class SegmentOwnerResolverTest(unittest.TestCase):
    def test_owner_of_reads_the_segment_clut_row_and_fingerprints_it(self):
        red = [(100, 0, 0, 255)] * 15
        green = [(0, 100, 0, 255)] * 15
        with tempfile.TemporaryDirectory() as d:
            evtchr = Path(d) / "evtchr"
            evtchr.mkdir()
            # segment 48: row 1 red, row 3 green.
            write_tga(str(evtchr / "segment_048.palette.tga"), 16, 16,
                      _clut16({1: red, 3: green}))
            resolver = pf.SegmentOwnerResolver(
                evtchr_dir=evtchr,
                sprite_palettes={0x05: [(100, 0, 0, 255)],
                                 0x0C: [(0, 100, 0, 255)]})
            self.assertEqual(resolver.owner_of(48, 1), 0x05)
            self.assertEqual(resolver.owner_of(48, 3), 0x0C)
            self.assertIsNone(resolver.owner_of(48, 0))   # empty row -> no owner


if __name__ == "__main__":
    unittest.main()
