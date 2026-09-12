"""Tests for tools/parse_formation_background.py.

The FORMATION screen's dark cobblestone background is a 128x32 tile inside the
shared "FRAME sheet" / range-overlay texture (ShiShi calls it RANGEFILE.TGA) --
the same raw-sector disc asset parse_range_tiles.py reads at LBA 0xE68 +0x1000
(256x256 4bpp). The tile lives at rect (88,216)-(215,247); its CLUT is slot 14
of that asset's palette tail (payload offset 0x91C0, right after the HP/MP/CT
bar CLUTs at 0x9160). On screen it is tiled to fill 256x240 with a vertical
gouraud darkening (which is why a framebuffer patch shows hundreds of colours
while the source stays 16-colour).

Provenance: research/working_documents/FORMATION_SCREEN.md sec 0 / sec 9.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_formation_background
"""

from __future__ import annotations

import struct
import unittest

import parse_formation_background as fb
import parse_range_tiles as prt


ISO = prt.iso_path(None)


class GeometryConstantsTest(unittest.TestCase):
    """Tracer bullet: the tile rect + CLUT offset are inside the known asset."""

    def test_tile_rect_is_within_the_256x256_sheet(self) -> None:
        self.assertEqual((fb.TILE_X, fb.TILE_Y, fb.TILE_W, fb.TILE_H),
                         (88, 216, 128, 32))
        self.assertLessEqual(fb.TILE_X + fb.TILE_W, prt.TEX_W)
        self.assertLessEqual(fb.TILE_Y + fb.TILE_H, prt.TEX_H)

    def test_stone_clut_is_slot_14_of_the_palette_tail(self) -> None:
        tail = prt.TEXELS_OFFSET + prt.TEXELS_SIZE  # 0x9000
        self.assertEqual(fb.STONE_CLUT_OFFSET, tail + 14 * 32)
        self.assertEqual(fb.STONE_CLUT_OFFSET, 0x91C0)
        # It sits right after the three bar CLUTs parse_range_tiles reads @0x9160.
        self.assertEqual(fb.STONE_CLUT_OFFSET, prt.BAR_CLUT_OFFSET + 3 * 32)


@unittest.skipUnless(ISO.exists(), f"raw ISO not present at {ISO}")
class ByteExactTest(unittest.TestCase):
    """Pinned byte-for-byte to the LBA 0xE68 disc asset."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.asset = prt.read_lba(ISO, prt.TEXTURE_LBA, prt.ASSET_SECTORS)

    def test_tile_indices_match_asset_nibbles(self) -> None:
        idx = fb.decode_tile_indices(self.asset)
        self.assertEqual(idx.shape, (fb.TILE_H, fb.TILE_W))
        # Spot-check corners + centre against a first-principles nibble read.
        for ty, tx in [(0, 0), (0, 1), (5, 40), (31, 127), (16, 64)]:
            gx, gy = fb.TILE_X + tx, fb.TILE_Y + ty
            self.assertEqual(int(idx[ty, tx]), prt.nibble(
                self.asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE],
                gx, gy))

    def test_stone_clut_bytes_are_raw_bgr555(self) -> None:
        got = fb.read_stone_clut(self.asset)
        expect = list(struct.unpack_from("<16H", self.asset, fb.STONE_CLUT_OFFSET))
        self.assertEqual(got, expect)
        # This is an OPAQUE background CLUT: index 0 is real stone (not the
        # transparent slot a sprite CLUT carries), STP bit clear.
        self.assertNotEqual(got[0], 0x0000)
        self.assertEqual(got[0] >> 15, 0)

    def test_stone_clut_is_dark_greenish_grey_not_a_range_panel(self) -> None:
        # The disc fact that pins WHY slot 14 (vs the blue/red/orange range
        # panels): the tile under this CLUT is dark, desaturated, and green>=blue
        # -- matching the on-screen cobblestone (framebuffer patch ~ (67,64,53)).
        rgb = fb.decode_tile_rgb(self.asset)  # (H, W, 3), index 0 -> black
        mean = rgb.reshape(-1, 3).mean(axis=0)
        r, g, b = mean
        self.assertGreaterEqual(g, b)                 # greenish-grey
        self.assertLess(abs(r - g), 20)               # desaturated
        self.assertLess(mean.mean(), 110)             # dark stone, not a bright panel


if __name__ == "__main__":
    unittest.main()
