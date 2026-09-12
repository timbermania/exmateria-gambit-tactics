"""Tests for tools/parse_formation_zodiac.py.

The FORMATION info panel's zodiac symbol comes from the shared FRAME/range sheet
(RANGETILE.tga, LBA 0xE68 +0x1000, 256x256 4bpp), in two 24x20 rows:

    signs 0-6  (Aries..Libra)          sheet (0,42)-(167,61)
    signs 7-12 (Scorpio..Serpentarius) sheet (0,62)-(142,81)

The glyph indices are byte-exact ROM; the CLUT is slot 0 of the palette tail
(0x9000, the tail base), a sprite CLUT (index 0 transparent) rendering muted
tan/olive icons -- pixel-matched vs t04.png. Provenance: FORMATION_SCREEN.md §14.3.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_formation_zodiac
"""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

import parse_formation_zodiac as z
import parse_range_tiles as prt

ISO = prt.iso_path(None)

# The 16 zodiac CLUT words (BGR555 LE u16), slot 0 of the sheet palette tail.
ZODIAC_CLUT_DOC = [0x0000, 0x10A6, 0x214A, 0x35F0, 0x3E53, 0x256C, 0x2DAE,
                   0x3A11, 0x4274, 0x08AD, 0x1D2F, 0x35F1, 0x4695, 0x0864,
                   0x29AE, 0x573A]


class GeometryConstantsTest(unittest.TestCase):
    """Tracer bullet: rects + CLUT offset sit inside the known 256x256 asset."""

    def test_thirteen_signs_named(self) -> None:
        self.assertEqual(z.NUM_SIGNS, 13)
        self.assertEqual(len(z.SIGN_NAMES), 13)
        self.assertEqual(z.SIGN_NAMES[0], "Aries")
        self.assertEqual(z.SIGN_NAMES[12], "Serpentarius")

    def test_source_rows_match_spec(self) -> None:
        # Row 0 spans (0,42)-(167,61): 7 cells of 24x20 -> ends at x168.
        self.assertEqual(z.sign_source_rect(0), (0, 42, 24, 20))
        self.assertEqual(z.sign_source_rect(6), (144, 42, 24, 20))
        # Row 1 starts at y62 with Scorpio.
        self.assertEqual(z.sign_source_rect(7), (0, 62, 24, 20))
        self.assertEqual(z.sign_source_rect(12), (120, 62, 24, 20))

    def test_every_source_rect_inside_sheet(self) -> None:
        for s in range(z.NUM_SIGNS):
            x, y, w, h = z.sign_source_rect(s)
            self.assertLessEqual(x + w, prt.TEX_W, f"sign {s} x")
            self.assertLessEqual(y + h, prt.TEX_H, f"sign {s} y")

    def test_atlas_is_7x2_grid(self) -> None:
        self.assertEqual((z.ATLAS_W, z.ATLAS_H), (168, 40))
        self.assertEqual(z.sign_atlas_rect(0), (0, 0, 24, 20))
        self.assertEqual(z.sign_atlas_rect(7), (0, 20, 24, 20))
        self.assertEqual(z.sign_atlas_rect(12), (120, 20, 24, 20))

    def test_clut_is_slot_0_of_the_palette_tail(self) -> None:
        tail = prt.TEXELS_OFFSET + prt.TEXELS_SIZE  # 0x9000
        self.assertEqual(z.ZODIAC_CLUT_OFFSET, tail + 0 * 32)
        self.assertEqual(z.ZODIAC_CLUT_OFFSET, 0x9000)


@unittest.skipUnless(ISO.exists(), f"raw ISO not present at {ISO}")
class ByteExactTest(unittest.TestCase):
    """Pinned byte-for-byte to the LBA 0xE68 disc asset."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.asset = prt.read_lba(ISO, prt.TEXTURE_LBA, prt.ASSET_SECTORS)

    def test_clut_matches_documented_slot0(self) -> None:
        self.assertEqual(z.read_zodiac_clut(self.asset), ZODIAC_CLUT_DOC)

    def test_atlas_indices_match_source_nibbles(self) -> None:
        idx = z.decode_atlas_indices(self.asset)
        self.assertEqual(idx.shape, (z.ATLAS_H, z.ATLAS_W))
        texels = self.asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE]
        # Sample each sign's top-left + a mid texel against the sheet nibbles.
        for s in range(z.NUM_SIGNS):
            sx, sy, w, h = z.sign_source_rect(s)
            ax, ay, _, _ = z.sign_atlas_rect(s)
            for dy, dx in [(0, 0), (h // 2, w // 2), (h - 1, w - 1)]:
                self.assertEqual(idx[ay + dy, ax + dx],
                                 prt.nibble(texels, sx + dx, sy + dy),
                                 f"sign {s} texel ({dy},{dx})")

    def test_unused_14th_cell_is_transparent(self) -> None:
        # The 7x2 grid has one empty slot (row1 col6); the sheet holds foreign
        # art there, so the atlas cell must stay index 0 (not baked in).
        idx = z.decode_atlas_indices(self.asset)
        self.assertTrue((idx[20:40, 144:168] == 0).all(),
                        "unused grid cell must be transparent")

    def test_index0_is_punched_transparent(self) -> None:
        rgba = z._clut_rgba(self.asset)
        self.assertEqual(rgba[0, 3], 0, "index 0 must be transparent (sprite CLUT)")
        self.assertGreater(int(rgba[1:, 3].max()), 0, "some colour must be opaque")


@unittest.skipUnless(ISO.exists(), f"raw ISO not present at {ISO}")
class EmitTest(unittest.TestCase):
    """parse() writes the three ADR-0022 artifacts with the right shapes."""

    def test_emit_writes_indexed_atlas_palette_and_manifest(self) -> None:
        asset = prt.read_lba(ISO, prt.TEXTURE_LBA, prt.ASSET_SECTORS)
        with tempfile.TemporaryDirectory() as d:
            out = Path(d)
            manifest = z.parse(asset, out)
            for name in ("ZODIAC.tga", "ZODIAC.palette.tga", "ZODIAC.json"):
                self.assertTrue((out / name).exists(), name)
            self.assertEqual(len(manifest["signs"]), 13)
            self.assertEqual(manifest["source"]["clut_slot"], 0)
            self.assertEqual(manifest["atlas_size"], [168, 40])
            # Indexed atlas recovers the same indices (pixel = index*17).
            raw = (out / "ZODIAC.tga").read_bytes()[18:]
            first_b = struct.unpack_from("<B", raw, 0)[0]  # BGRA -> B
            self.assertEqual(first_b // 17, z.decode_atlas_indices(asset)[0, 0])


if __name__ == "__main__":
    unittest.main()
