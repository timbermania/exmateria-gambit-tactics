"""Tests for tools/parse_unit.py.

EVENT/UNIT.BIN is the FORMATION-screen sprite atlas: the small unit poses shown
in the party/formation "sort list" grid (one pose per class + monsters, plus a
few UI strings and panel bits). Layout (byte-verified vs the real UNIT.BIN in
the local extract):

    pixels   0x0000 .. 0xF000   256 x 480, 4bpp, low-nibble-first  (61440 B)
    palettes 0xF000 .. 0x10000  128 x (16 x BGR555 LE)             ( 4096 B)

Every palette's entry 0 is 0x0000 (the transparent index-0 marker every FFT
sprite CLUT carries), which is how the pixel/palette split is pinned to the
disc rather than to an imagined shape.

Full RE + provenance:
    research/working_documents/FORMATION_SCREEN.md

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_unit
"""

from __future__ import annotations

import struct
import unittest

import parse_unit as pu
from _repo_paths import event_dir


UNIT = event_dir() / "UNIT.BIN"


class FormatConstantsTest(unittest.TestCase):
    """Tracer bullet: the constants tile the file exactly, no gaps/overlap."""

    def test_pixels_plus_palettes_fill_the_file(self) -> None:
        self.assertEqual(pu.PIXEL_BYTES + pu.NUM_PALETTES * pu.PALETTE_BYTES,
                         pu.FILE_SIZE)

    def test_pixel_region_is_width_x_height_4bpp(self) -> None:
        self.assertEqual(pu.WIDTH * pu.HEIGHT // 2, pu.PIXEL_BYTES)

    def test_palette_offset_formula(self) -> None:
        self.assertEqual(pu.palette_offset(0), 0xF000)
        self.assertEqual(pu.palette_offset(1), 0xF020)
        self.assertEqual(pu.palette_offset(127), 0xFFE0)


@unittest.skipUnless(UNIT.exists(), f"UNIT.BIN not present at {UNIT}")
class DecodeByteExactTest(unittest.TestCase):
    """Decode pinned byte-for-byte to the disc bytes at the formula offsets."""

    def setUp(self) -> None:
        self.data = UNIT.read_bytes()

    def test_file_is_expected_size(self) -> None:
        self.assertEqual(len(self.data), pu.FILE_SIZE)

    def test_every_palette_entry0_is_transparent_marker(self) -> None:
        # The disc-pinned invariant that locates the palette table: all 128
        # CLUTs begin with the 0x0000 transparent index-0 word.
        for p in range(pu.NUM_PALETTES):
            self.assertEqual(struct.unpack_from("<H", self.data,
                                                pu.palette_offset(p))[0], 0x0000,
                             f"palette {p} entry0 not 0x0000")

    def test_read_clut_is_raw_bgr555_words(self) -> None:
        # No remap, no reorder: the 16 CLUT words are the raw little-endian u16s.
        off = pu.palette_offset(5)
        expect = list(struct.unpack_from("<16H", self.data, off))
        self.assertEqual(pu.read_clut(self.data, 5), expect)

    def test_decoded_indices_match_nibbles(self) -> None:
        # Low nibble = left pixel, high nibble = right pixel; shape (H, W).
        idx = pu.decode_indices(self.data)
        self.assertEqual(idx.shape, (pu.HEIGHT, pu.WIDTH))
        # First byte -> pixels (0,0) and (0,1).
        b0 = self.data[0]
        self.assertEqual(int(idx[0, 0]), b0 & 0x0F)
        self.assertEqual(int(idx[0, 1]), (b0 >> 4) & 0x0F)
        # A byte mid-atlas -> the two pixels it covers.
        boff = 1000
        b = self.data[boff]
        y, x = divmod(boff * 2, pu.WIDTH)
        self.assertEqual(int(idx[y, x]), b & 0x0F)
        self.assertEqual(int(idx[y, x + 1]), (b >> 4) & 0x0F)

    def test_populated_palette_count_is_disc_fact(self) -> None:
        # 122 of the 128 CLUTs carry real colour beyond the transparent index 0;
        # a golden that fails loudly if the split or file ever drifts.
        populated = sum(
            1 for p in range(pu.NUM_PALETTES)
            if any(w != 0 for w in pu.read_clut(self.data, p)[1:])
        )
        self.assertEqual(populated, 122)


if __name__ == "__main__":
    unittest.main()
