"""Tests for tools/parse_evtface.py.

The {50} Portrait Row opcode selects an EVTFACE.BIN row-block; {10}/{51} pick a
column. EVTFACE.BIN (EVENT/EVTFACE.BIN, 65536 B) is an 8x8 grid of 32x48 4bpp
portraits with an inline 16-colour CLUT per portrait. Offsets (byte-verified vs
the file AND live VRAM):

    pixel_offset   =        row*8192 + col*768     # 768 B contiguous 32x48 4bpp
    palette_offset = 6144 + row*8192 + col*32      # 32 B, 16x BGR555 little-endian

Full RE + provenance:
    research/working_documents/PORTRAIT_ROW_OPCODE_50_EVTFACE.md

These asserts byte-match the offset recipe against the real EVTFACE.BIN in the
local extract, so the parser is pinned to the disc, not to imagined shapes.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_evtface
"""

from __future__ import annotations

import unittest

import parse_evtface as ef
from _repo_paths import event_dir


EVTFACE = event_dir() / "EVTFACE.BIN"


class OffsetFormulaTest(unittest.TestCase):
    """Tracer bullet: the row*8192+col*768 / 6144+... offset formulas."""

    def test_pixel_offsets(self) -> None:
        self.assertEqual(ef.pixel_offset(0, 0), 0x0000)
        self.assertEqual(ef.pixel_offset(0, 1), 0x0300)
        self.assertEqual(ef.pixel_offset(0, 4), 0x0C00)
        self.assertEqual(ef.pixel_offset(1, 0), 0x2000)

    def test_palette_offsets(self) -> None:
        self.assertEqual(ef.palette_offset(0, 0), 0x1800)
        self.assertEqual(ef.palette_offset(0, 1), 0x1820)
        self.assertEqual(ef.palette_offset(1, 0), 0x1800 + 0x2000)


@unittest.skipUnless(EVTFACE.exists(), f"EVTFACE.BIN not present at {EVTFACE}")
class DecodeByteExactTest(unittest.TestCase):
    """The decode is pinned byte-for-byte to the disc bytes at the formula offsets."""

    def setUp(self) -> None:
        self.data = EVTFACE.read_bytes()

    def test_file_is_expected_size(self) -> None:
        self.assertEqual(len(self.data), 0x10000)

    def test_clut_is_raw_bgr555_words(self) -> None:
        # The 16 CLUT entries for (row0,col0) are the raw little-endian u16 words
        # at palette_offset -- no remap, no reorder.
        import struct
        off = ef.palette_offset(0, 0)
        expect = list(struct.unpack_from("<16H", self.data, off))
        self.assertEqual(ef.read_clut(self.data, 0, 0), expect)

    def test_decoded_pixels_match_nibbles_and_clut(self) -> None:
        # Decode (row0,col0) and verify a spread of pixels against a first-
        # principles nibble+CLUT read of the raw bytes (low-nibble = left pixel).
        img = ef.decode_portrait(self.data, 0, 0)
        self.assertEqual(img.size, (ef.FACE_W, ef.FACE_H))
        pm = img.load()
        pix = ef.pixel_offset(0, 0)
        clut = [ef._rgb555(v) for v in ef.read_clut(self.data, 0, 0)]
        bpr = ef.FACE_W // 2
        for (x, y) in [(0, 0), (1, 0), (31, 0), (0, 47), (17, 23)]:
            byte = self.data[pix + y * bpr + (x >> 1)]
            nib = (byte & 0xF) if (x & 1) == 0 else (byte >> 4)
            r, g, b = clut[nib]
            a = 0 if nib == 0 else 255
            self.assertEqual(pm[x, y], (r, g, b, a), "pixel (%d,%d)" % (x, y))


@unittest.skipUnless(EVTFACE.exists(), f"EVTFACE.BIN not present at {EVTFACE}")
class EmitTest(unittest.TestCase):
    """main() writes all 64 portrait PNGs + a (row,col)-keyed manifest."""

    def test_emit_writes_64_faces_and_manifest(self) -> None:
        import json
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as d:
            out = Path(d)
            ef.main(["--out", str(out)])
            manifest = json.loads((out / "evtface.json").read_text())
            faces = manifest["faces"]
            self.assertEqual(len(faces), ef.ROWS * ef.COLS)
            # Every listed PNG exists and the row/col keying is present.
            self.assertIn("0_0", faces)          # Balbanes (row0,col0)
            self.assertEqual(faces["0_0"]["row"], 0)
            self.assertEqual(faces["0_0"]["col"], 0)
            for key, entry in faces.items():
                self.assertTrue((out / entry["file"]).exists(), key)
                self.assertEqual([entry["w"], entry["h"]], [ef.FACE_W, ef.FACE_H])


if __name__ == "__main__":
    unittest.main()
