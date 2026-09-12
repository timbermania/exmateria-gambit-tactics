"""Tests for tools/parse_evtchr.py.

EVTCHR.BIN holds cinematic-sprite image data. Per ShiShi (PSXImages.xml +
ShishiSpriteEditor/TestForm.cs's `EVTCHR` class):

    137 segments x 30,720 bytes = 4,208,640 bytes (= filesize)
    each segment:
      offset 1920, length 32x16 = 512 B  ->  16 palettes of 16 colors each
                                             (16-bit PSX TIM colors, 32 B/palette)
      offset 2432 (0x980), length 25,600 B       ->  256x200 4bpp paletted pixel page
                                             (2 pixels per byte)

The SEQ/SHP frame timing for cinematic anim_ids (0x200+) is NOT in this
file -- see /tmp/handoff_evtchr_loading.md for the dispatch chain.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_evtchr
"""

from __future__ import annotations

import unittest
from pathlib import Path

import parse_evtchr as ev
from _repo_paths import event_dir


EVTCHR_PATH = event_dir() / "EVTCHR.BIN"


@unittest.skipUnless(EVTCHR_PATH.exists(), f"EVTCHR.BIN not present at {EVTCHR_PATH}")
class ParseEvtchrSegmentTracerTest(unittest.TestCase):
    """Tracer bullet: parse the file, expose one segment with correct shape."""

    def test_segment_0_has_expected_shape(self) -> None:
        atlas = ev.parse_evtchr(EVTCHR_PATH)
        # File size already constrains this, but make the contract explicit.
        self.assertEqual(len(atlas.segments), 137)
        seg = atlas.segments[0]
        # 16 palettes of 32 B each (16 colors x 16 bits)
        self.assertEqual(len(seg.palettes), 16)
        for i, pal in enumerate(seg.palettes):
            self.assertEqual(len(pal), 32, f"palette {i} should be 32 bytes")
        # 256 x 200 4bpp = 25,600 bytes
        self.assertEqual(len(seg.pixels), 25_600)


class DecodePsxColorTest(unittest.TestCase):
    """PSX TIM 16-bit color = SBBBBBGG GGGRRRRR (LE u16).
    S = semi-transparent flag (ignored for RGB); each channel is 5-bit.
    """

    def test_known_colors(self) -> None:
        # Black (S=0): 0x0000 -> (0, 0, 0)
        self.assertEqual(ev.decode_psx_color(0x0000), (0, 0, 0))
        # Pure red 5-bit max: 0x001F -> R=31 -> 0xF8 (left-shift 3)
        self.assertEqual(ev.decode_psx_color(0x001F), (0xF8, 0, 0))
        # Pure green: 0x03E0 -> G=31
        self.assertEqual(ev.decode_psx_color(0x03E0), (0, 0xF8, 0))
        # Pure blue: 0x7C00 -> B=31
        self.assertEqual(ev.decode_psx_color(0x7C00), (0, 0, 0xF8))
        # STP bit set shouldn't leak into RGB.
        self.assertEqual(ev.decode_psx_color(0x801F), (0xF8, 0, 0))


@unittest.skipUnless(EVTCHR_PATH.exists(), f"EVTCHR.BIN not present at {EVTCHR_PATH}")
class DecodePixelsTest(unittest.TestCase):
    """4bpp = 2 pixels per byte. PSX convention: low nibble first (left pixel)."""

    def test_segment_0_pixel_indices_are_4bpp(self) -> None:
        atlas = ev.parse_evtchr(EVTCHR_PATH)
        seg = atlas.segments[0]
        indices = ev.decode_pixels(seg.pixels)
        self.assertEqual(len(indices), 256 * 200)  # 51,200 indices
        # Every index is 0..15.
        self.assertTrue(all(0 <= i < 16 for i in indices))
        # Sanity: not all the same value (would mean we mis-sliced).
        self.assertGreater(len(set(indices)), 1)


if __name__ == "__main__":
    unittest.main()
