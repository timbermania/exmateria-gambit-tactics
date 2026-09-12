"""Tests for tools/parse_formation_box.py.

The FORMATION screen's gold selection box is a 32x16 QUARTER-diamond texel in
the shared "FRAME sheet" / range-overlay texture (ShiShi RANGEFILE.TGA) -- the
same raw-sector disc asset parse_range_tiles.py / parse_formation_orb.py read at
LBA 0xE68 +0x1000. The ¼ texel lives at rect (216,216)-(247,231). Its 16-colour
gold CLUT (clut-id 0x7F65) is NOT in the range sheet's palette tail; it lives in
the roster overlay WORLD/WORLD.BIN at 0x8018B9A4 (file offset 0xAB9A4), beside
the §13 selection tables. It is a SPRITE CLUT so index 0 is transparent.

Provenance: research/working_documents/FORMATION_SCREEN.md §11.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_formation_box
"""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

import parse_formation_box as box
import parse_range_tiles as prt
from _repo_paths import world_bin


ISO = prt.iso_path(None)
WORLD = world_bin(None)

# The 16 gold-box CLUT words (BGR555 LE u16), pinned in FORMATION_SCREEN.md §11.1
# and byte-verified against WORLD.BIN. idx0 transparent, idx1 brightest gold,
# idx15 near-black interior fill.
BOX_CLUT_DOC = [0x0000, 0xBF7F, 0x8F3D, 0x8EDB, 0x8A99, 0x8A57, 0x8615, 0x85D3,
                0x8591, 0x814F, 0x810D, 0x80CA, 0x8087, 0x8044, 0x8022, 0x8001]


class GeometryConstantsTest(unittest.TestCase):
    """Tracer bullet: the texel rect + CLUT offset land inside the known assets."""

    def test_box_rect_is_within_the_256x256_sheet(self) -> None:
        self.assertEqual((box.BOX_X, box.BOX_Y, box.BOX_W, box.BOX_H),
                         (216, 216, 32, 16))
        self.assertLessEqual(box.BOX_X + box.BOX_W, prt.TEX_W)
        self.assertLessEqual(box.BOX_Y + box.BOX_H, prt.TEX_H)

    def test_clut_offset_is_overlay_addr_minus_base(self) -> None:
        self.assertEqual(box.BOX_CLUT_OFFSET, 0xAB9A4)
        self.assertEqual(box.BOX_CLUT_ADDR - box.WORLD_OVERLAY_BASE,
                         box.BOX_CLUT_OFFSET)


@unittest.skipUnless(ISO.exists() and WORLD.exists(),
                     f"raw ISO / WORLD.BIN not present ({ISO} / {WORLD})")
class ByteExactTest(unittest.TestCase):
    """Pinned byte-for-byte to the LBA 0xE68 sheet + WORLD.BIN overlay."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.asset = prt.read_lba(ISO, prt.TEXTURE_LBA, prt.ASSET_SECTORS)
        cls.world = WORLD.read_bytes()

    def test_box_clut_matches_the_documented_vram_palette(self) -> None:
        self.assertEqual(box.read_box_clut(self.world), BOX_CLUT_DOC)

    def test_box_indices_match_asset_nibbles(self) -> None:
        idx = box.decode_box_indices(self.asset)
        self.assertEqual(idx.shape, (box.BOX_H, box.BOX_W))
        texels = self.asset[prt.TEXELS_OFFSET:prt.TEXELS_OFFSET + prt.TEXELS_SIZE]
        for ty, tx in [(0, 0), (8, 20), (15, 0), (15, 31)]:
            gx, gy = box.BOX_X + tx, box.BOX_Y + ty
            self.assertEqual(idx[ty, tx], prt.nibble(texels, gx, gy))

    def test_top_row_is_transparent_index_zero(self) -> None:
        """The ¼ texel's top edge is the diamond's transparent exterior."""
        idx = box.decode_box_indices(self.asset)
        self.assertTrue((idx[0] == 0).all(), "row 0 should be all transparent")

    def test_index0_transparent_and_gold_and_fill_present(self) -> None:
        rgba = box._clut_rgba(self.world)
        self.assertEqual(rgba[0, 3], 0, "index 0 must be transparent (sprite CLUT)")
        # idx1 = brightest gold. Every non-zero gold word has the STP bit set
        # (drawn under the ABR blend), so the encoded alpha is 128 (§ helper).
        self.assertEqual(tuple(rgba[1]), (255, 222, 123, 128))
        # idx15 = near-black interior fill: NOT the transparent slot (§11.3).
        self.assertNotEqual(rgba[15, 3], 0)

    def test_texel_has_both_a_gold_edge_and_an_idx15_fill(self) -> None:
        """§11.3: a gold diagonal edge (idx 1..14) plus an opaque idx15 fill."""
        idx = box.decode_box_indices(self.asset)
        self.assertTrue(((idx >= 1) & (idx <= 14)).any(), "expected a gold edge")
        self.assertTrue((idx == 15).any(), "expected an idx15 interior fill")


@unittest.skipUnless(ISO.exists() and WORLD.exists(),
                     f"raw ISO / WORLD.BIN not present ({ISO} / {WORLD})")
class EmitTest(unittest.TestCase):
    """parse() writes the three artifacts with the right shapes."""

    def test_emit_writes_indexed_texel_palette_and_manifest(self) -> None:
        asset = prt.read_lba(ISO, prt.TEXTURE_LBA, prt.ASSET_SECTORS)
        world = WORLD.read_bytes()
        with tempfile.TemporaryDirectory() as d:
            out = Path(d)
            manifest = box.parse(asset, world, out)
            for name in ("BOX.tga", "BOX.palette.tga", "BOX.json"):
                self.assertTrue((out / name).exists(), name)
            self.assertEqual(manifest["texel_source"]["texel_rect"],
                             [216, 216, 32, 16])
            self.assertEqual(manifest["clut_source"]["clut_vram_id"], "0x7F65")
            # Indexed texel recovers the same indices (pixel = index*17).
            raw = (out / "BOX.tga").read_bytes()[18:]
            px = struct.unpack_from("<B", raw, 0)[0]  # BGRA -> B of first pixel
            self.assertEqual(px // 17, box.decode_box_indices(asset)[0, 0])


if __name__ == "__main__":
    unittest.main()
