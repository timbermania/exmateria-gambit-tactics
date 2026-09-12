"""Parser fields the Effect Studio's Texture surface needs (#280 follow-up).

Two facts the studio could not show because no Godot-side asset carried them:

  * **dual-palette-in-use** — `flags_byte0 & 0x10` picks CLUT line 0x7B40
    (palette 2) over 0x7B00 (palette 1), per the sprite renderer at 0x801a5664.
    `parse_frame` decoded bits 0-3, 5-6 and 7 but never bit 4, so frames.json
    could not say which palette a sheet is actually drawn through.
  * **the texture's VRAM upload rectangle** — the 4-byte header at
    texture_ptr + 0x400. `extract_palette` emitted the CLUT but nothing emitted
    this, so the studio had no dimensions of its own.

Run from tools/:
    uv run python -m unittest test_parse_effect_texture_meta
"""

from __future__ import annotations

import os
import unittest

import parse_effect as pe

_CORPUS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "..", "project-assets", "fft-extract", "EFFECT")
_E019 = os.path.join(_CORPUS, "E019.BIN")


def _frame_bytes(flags_byte0: int) -> bytes:
    """A 24-byte frame whose only interesting byte is flags_byte0."""
    return bytes([flags_byte0]) + bytes(23)


class FramePaletteSelect(unittest.TestCase):
    """Bit 4 of flags_byte0 selects palette 2 (0x801a5664)."""

    def test_bit_4_clear_means_palette_1(self):
        fr = pe.parse_frame(_frame_bytes(0x80), 0, 0)
        self.assertFalse(fr["uses_palette_2"])

    def test_bit_4_set_means_palette_2(self):
        fr = pe.parse_frame(_frame_bytes(0x90), 0, 0)
        self.assertTrue(fr["uses_palette_2"])

    def test_the_new_bit_does_not_leak_into_the_neighbouring_fields(self):
        """palette_id is bits 0-3, depth is bit 7, blend is bits 5-6 — none of
        them may change when bit 4 flips."""
        without = pe.parse_frame(_frame_bytes(0b1010_0101), 0, 0)
        with_bit = pe.parse_frame(_frame_bytes(0b1011_0101), 0, 0)
        for key in ("palette_id", "is_8bpp", "semi_trans_mode", "blend_mode"):
            self.assertEqual(without[key], with_bit[key], key)
        self.assertEqual(without["palette_id"], 5)
        self.assertTrue(without["is_8bpp"])


@unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
class TextureMetaOnE019(unittest.TestCase):
    def setUp(self):
        with open(_E019, "rb") as fh:
            self.data = fh.read()
        self.header = pe.parse_header(self.data, pe.find_header_offset(self.data))
        self.meta = pe.parse_texture_meta(self.data, self.header["texture_ptr"])

    def test_the_0x400_word_is_the_PIXEL_DATA_SIZE_not_a_vram_y(self):
        """Measured over all 401 non-empty effects: the 24-bit value at +0x400
        equals the pixel plane's byte count exactly, every time. The format doc
        called it a 'VRAM Y coordinate'; it is a size, and the engine divides it
        by the row stride to recover height."""
        plane = len(self.data) - (self.header["texture_ptr"] + 0x404)
        self.assertEqual(self.meta["pixel_data_size"], plane)

    def test_it_reports_the_row_stride_and_row_count(self):
        self.assertEqual(self.meta["row_bytes"], 128)
        self.assertEqual(self.meta["height"], 256)
        self.assertEqual(self.meta["row_bytes"] * self.meta["height"],
                         self.meta["pixel_data_size"])

    def test_it_does_not_claim_a_texel_width(self):
        """A row is row_bytes wide in BYTES — that is row_bytes texels at 8bpp
        but twice that at 4bpp, and depth is a per-frame property this header
        does not carry. The caller derives width; the parser must not guess."""
        self.assertNotIn("width", self.meta)

    def test_it_reports_the_upload_x_and_admits_the_y_is_unknown(self):
        """The engine (0x801a0e80) uploads at a fixed VRAM X=0x180; the Y is NOT
        encoded in this header, so the parser must not invent one."""
        self.assertEqual(self.meta["vram_x"], 0x180)
        self.assertIsNone(self.meta["vram_y"])

    def test_it_reports_which_palettes_carry_data(self):
        self.assertTrue(self.meta["palette_1_nonzero"])
        self.assertIn("palette_2_nonzero", self.meta)


if __name__ == "__main__":
    unittest.main()
