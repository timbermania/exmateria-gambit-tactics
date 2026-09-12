#!/usr/bin/env python3
"""Guard for the event-asset slicing (wayfinder #204, ADR-0072 dec.5).

Unit-tests the frame compositor + face re-indexer, and integration-tests the
emitters against the real EVTFACE cell / EVTCHR segment atlas so the round trip
(composite/reindex -> index-grayscale TGA + CLUT) is exercised end to end.

Run:  uv run python -m unittest test_event_asset_slicing
"""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

import event_asset_slicing as eas

TOOLS = Path(__file__).resolve().parent
GODOT = TOOLS.parent
FACES = GODOT / "assets" / "scenarios" / "faces"
EVTCHR = GODOT / "assets" / "sprites" / "textures" / "evtchr"


def _block(rx, ry, w, h, lx, ly, revert=False, invert=False):
    return {"rectangle_x": rx, "rectangle_y": ry,
            "rectangle_width": w, "rectangle_height": h,
            "location_x": lx, "location_y": ly,
            "revert": revert, "invert": invert}


def _read_tga(path: Path):
    d = path.read_bytes()
    w, h = struct.unpack("<HH", d[12:16])
    px = d[18:]
    return w, h, [(px[i + 2], px[i + 1], px[i], px[i + 3]) for i in range(0, len(px), 4)]


class CompositeTest(unittest.TestCase):
    def _atlas(self):
        # 2x2 BGRA atlas: (col,row) -> distinct index-grayscale pixels.
        #   (0,0)=idx1  (1,0)=idx2
        #   (0,1)=idx3  (1,1)=idx4
        def bgra(idx):
            v = idx * 17
            return bytes([v, v, v, 255])
        rows = [bgra(1) + bgra(2), bgra(3) + bgra(4)]
        return 2, 2, b"".join(rows)

    def test_single_block_copies_the_rect_verbatim(self):
        w, h, atlas = self._atlas()
        out = eas.composite_evtchr_frame(w, h, atlas, [_block(0, 0, 2, 2, 0, 0)])
        cw, ch, px = out
        self.assertEqual((cw, ch), (2, 2))
        self.assertEqual(px[0], (17, 17, 17, 255))   # idx1 top-left
        self.assertEqual(px[3], (68, 68, 68, 255))   # idx4 bottom-right

    def test_horizontal_flip_reverses_columns(self):
        w, h, atlas = self._atlas()
        out = eas.composite_evtchr_frame(w, h, atlas, [_block(0, 0, 2, 2, 0, 0, revert=True)])
        _cw, _ch, px = out
        self.assertEqual(px[0], (34, 34, 34, 255))   # idx2 now top-left
        self.assertEqual(px[1], (17, 17, 17, 255))   # idx1 now top-right

    def test_location_offsets_grow_the_canvas_and_leave_gaps_transparent(self):
        w, h, atlas = self._atlas()
        # Two 1x1 tiles at (0,0) and (2,2) -> a 3x3 canvas, corners set.
        out = eas.composite_evtchr_frame(w, h, atlas, [
            _block(0, 0, 1, 1, 0, 0), _block(1, 1, 1, 1, 2, 2)])
        cw, ch, px = out
        self.assertEqual((cw, ch), (3, 3))
        self.assertEqual(px[0], (17, 17, 17, 255))     # top-left tile
        self.assertEqual(px[8], (68, 68, 68, 255))     # bottom-right tile
        self.assertEqual(px[4], (0, 0, 0, 0))          # centre untouched -> transparent

    def test_empty_block_list_returns_none(self):
        self.assertIsNone(eas.composite_evtchr_frame(2, 2, b"\x00" * 16, []))


class ReindexTest(unittest.TestCase):
    def test_distinct_colours_map_to_first_seen_indices(self):
        pixels = [(10, 0, 0, 255), (0, 20, 0, 255), (10, 0, 0, 255), (0, 0, 0, 0)]
        idx, palette = eas.reindex_rgba_to_grayscale(pixels)
        self.assertEqual(palette, [(10, 0, 0, 255), (0, 20, 0, 255), (0, 0, 0, 0)])
        self.assertEqual(idx[0], (0, 0, 0, 255))     # index 0
        self.assertEqual(idx[1], (17, 17, 17, 255))  # index 1
        self.assertEqual(idx[2], (0, 0, 0, 255))     # index 0 again (deduped)
        self.assertEqual(idx[3], (34, 34, 34, 0))    # index 2, alpha carried

    def test_over_16_colours_is_rejected(self):
        with self.assertRaises(ValueError):
            eas.reindex_rgba_to_grayscale([(i, i, i, 255) for i in range(17)])


class EmitFaceIntegrationTest(unittest.TestCase):
    def test_real_face_cell_reindexes_losslessly(self):
        src = FACES / "face_r0_c0.png"
        if not src.exists():
            self.skipTest("faces/ not generated (gitignored) -- run parse_evtface.py")
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            self.assertTrue(eas.emit_face_cell(out, 0, src))
            w, h, px = _read_tga(out / "00.tga")
            self.assertEqual((w, h), (32, 48))
            # index-grayscale: every pixel's channels are equal multiples of 17.
            for r, g, b, _a in px:
                self.assertEqual(r, g)
                self.assertEqual(g, b)
                self.assertEqual(r % 17, 0)
            # CLUT carries the source colours on row 0.
            _pw, _ph, clut = _read_tga(out / "00.palette.tga")
            self.assertTrue(any(a != 0 or (r, g, b) != (0, 0, 0)
                                for r, g, b, a in clut[:16]))


class PaletteRowThreadingTest(unittest.TestCase):
    """A {7F}-bound chr frame must carry ITS palette row (so units sharing one
    segment, told apart only by row, get distinct CLUTs); an unbound single-seg
    frame keeps the whole segment CLUT verbatim."""

    def _atlas(self):
        def bgra(idx):
            v = idx * 17
            return bytes([v, v, v, 255])
        return 1, 1, bgra(1)  # 1x1 atlas, index 1

    def _segment_palette(self, path: Path):
        # 16x16 CLUT; row r, col c -> a colour unique to (r, c) so a row is identifiable.
        pixels = []
        for r in range(16):
            for c in range(16):
                pixels.append((r * 8, c * 8, (r + c) & 0xFF, 255))
        eas.write_tga(str(path), 16, 16, pixels)
        return pixels

    def test_known_row_lands_that_segment_row_on_clut_row_0(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            segpal = out / "segment.palette.tga"
            seg_pixels = self._segment_palette(segpal)
            aw, ah, atlas = self._atlas()
            blocks = [_block(0, 0, 1, 1, 0, 0)]
            self.assertTrue(eas.emit_chr_frame(out, 0, (aw, ah, atlas), blocks,
                                               segpal, palette_row=4))
            _w, _h, clut = _read_tga(out / "00.palette.tga")
            # CLUT row 0 must equal segment CLUT row 4.
            expected_row4 = seg_pixels[4 * 16:4 * 16 + 16]
            self.assertEqual(clut[:16], expected_row4)

    def test_no_row_copies_the_full_segment_clut_verbatim(self):
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            segpal = out / "segment.palette.tga"
            self._segment_palette(segpal)
            aw, ah, atlas = self._atlas()
            blocks = [_block(0, 0, 1, 1, 0, 0)]
            self.assertTrue(eas.emit_chr_frame(out, 0, (aw, ah, atlas), blocks,
                                               segpal, palette_row=None))
            self.assertEqual((out / "00.palette.tga").read_bytes(), segpal.read_bytes())


class EmitChrIntegrationTest(unittest.TestCase):
    def test_real_segment_frame_composites_and_writes(self):
        import parse_evtchr_frames  # noqa
        atlas = EVTCHR / "segment_000.tga"
        pal = EVTCHR / "segment_000.palette.tga"
        if not atlas.exists():
            self.skipTest("evtchr/ not generated (gitignored) -- run parse_evtchr.py")
        import json
        frames = json.loads((GODOT / "assets" / "sprites" / "animations"
                             / "evtchr_frames.json").read_text())
        seg0 = frames["0"]
        # first frame id with a non-empty block list
        fid = next(k for k, v in seg0.items() if v)
        blocks = seg0[fid]
        aw, ah, abgra = eas.read_tga_bgra(atlas)
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            self.assertTrue(eas.emit_chr_frame(out, 0, (aw, ah, abgra), blocks, pal))
            w, h, px = _read_tga(out / "00.tga")
            self.assertGreater(w, 0)
            self.assertGreater(h, 0)
            for r, g, b, _a in px:                     # index-grayscale invariant
                self.assertEqual(r, g)
                self.assertEqual(g, b)
            self.assertTrue((out / "00.palette.tga").exists())


if __name__ == "__main__":
    unittest.main()
