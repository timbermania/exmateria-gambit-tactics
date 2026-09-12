"""Tests for tools/parse_formation_orb.py.

The FORMATION screen's glowing blue orb is a 12x12 sprite inside the shared
"FRAME sheet" / range-overlay texture (ShiShi RANGEFILE.TGA) -- the same
raw-sector disc asset parse_range_tiles.py reads at LBA 0xE68 +0x1000
(256x256 4bpp). The orb lives at rect (243,73)-(254,84); its CLUT is slot 20
of that asset's palette tail (payload offset 0x9280), byte-verified against the
runtime VRAM CLUT id 0x7F27. It is a SPRITE CLUT so index 0 is transparent.

Provenance: research/working_documents/FORMATION_SCREEN.md sec 10.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_formation_orb
"""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

import parse_formation_orb as orb
import parse_range_tiles as prt


ISO = prt.iso_path(None)

# The 16 orb CLUT words (BGR555 LE u16), pinned in FORMATION_SCREEN.md sec 10.1
# and byte-verified against the live VRAM CLUT id 0x7F27.
ORB_CLUT_DOC = [0x0000, 0x0C84, 0x8000, 0x72E4, 0x4189, 0x5A2A, 0x72CC, 0x2615,
                0x8C20, 0x9040, 0x9880, 0xA8C0, 0x7FE4, 0x0000, 0x90C9, 0x992C]


class GeometryConstantsTest(unittest.TestCase):
    """Tracer bullet: the texel rect + CLUT offset are inside the known asset."""

    def test_orb_rect_is_within_the_256x256_sheet(self) -> None:
        self.assertEqual((orb.ORB_X, orb.ORB_Y, orb.ORB_W, orb.ORB_H),
                         (243, 73, 12, 12))
        self.assertLessEqual(orb.ORB_X + orb.ORB_W, prt.TEX_W)
        self.assertLessEqual(orb.ORB_Y + orb.ORB_H, prt.TEX_H)

    def test_orb_clut_is_slot_20_of_the_palette_tail(self) -> None:
        tail = prt.TEXELS_OFFSET + prt.TEXELS_SIZE  # 0x9000
        self.assertEqual(orb.ORB_CLUT_OFFSET, tail + 20 * 32)
        self.assertEqual(orb.ORB_CLUT_OFFSET, 0x9280)


@unittest.skipUnless(ISO.exists(), f"raw ISO not present at {ISO}")
class ByteExactTest(unittest.TestCase):
    """Pinned byte-for-byte to the LBA 0xE68 disc asset."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.asset = prt.read_lba(ISO, prt.TEXTURE_LBA, prt.ASSET_SECTORS)

    def test_orb_clut_matches_the_documented_vram_palette(self) -> None:
        self.assertEqual(orb.read_orb_clut(self.asset), ORB_CLUT_DOC)

    def test_orb_indices_match_asset_nibbles(self) -> None:
        idx = orb.decode_orb_indices(self.asset)
        self.assertEqual(idx.shape, (orb.ORB_H, orb.ORB_W))
        texels = self.asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE]
        for ty, tx in [(0, 0), (6, 6), (11, 11), (3, 8)]:
            gx, gy = orb.ORB_X + tx, orb.ORB_Y + ty
            self.assertEqual(idx[ty, tx], prt.nibble(texels, gx, gy))

    def test_corners_are_transparent_index_zero(self) -> None:
        """A radially-symmetric orb has transparent corners (index 0)."""
        idx = orb.decode_orb_indices(self.asset)
        for cy, cx in [(0, 0), (0, 11), (11, 0), (11, 11)]:
            self.assertEqual(idx[cy, cx], 0, f"corner ({cy},{cx}) should be idx 0")

    def test_index0_is_punched_transparent_in_rgba(self) -> None:
        rgba = orb._clut_rgba(self.asset)
        self.assertEqual(rgba[0, 3], 0, "index 0 must be transparent (sprite CLUT)")
        # A lit interior index should be opaque.
        self.assertGreater(rgba[3, 3], 0)


@unittest.skipUnless(ISO.exists(), f"raw ISO not present at {ISO}")
class EmitTest(unittest.TestCase):
    """parse() writes the three ADR-0022 artifacts with the right shapes."""

    def test_emit_writes_indexed_sprite_palette_and_manifest(self) -> None:
        asset = prt.read_lba(ISO, prt.TEXTURE_LBA, prt.ASSET_SECTORS)
        with tempfile.TemporaryDirectory() as d:
            out = Path(d)
            manifest = orb.parse(asset, out)
            for name in ("ORB.tga", "ORB.palette.tga", "ORB.json"):
                self.assertTrue((out / name).exists(), name)
            self.assertEqual(manifest["source"]["texel_rect"], [243, 73, 12, 12])
            self.assertEqual(manifest["source"]["clut_slot"], 20)
            # Indexed sprite recovers the same indices (pixel = index*17).
            raw = (out / "ORB.tga").read_bytes()[18:]
            px = struct.unpack_from("<B", raw, 0)[0]  # BGRA -> B of first pixel
            self.assertEqual(px // 17, orb.decode_orb_indices(asset)[0, 0])


if __name__ == "__main__":
    unittest.main()
