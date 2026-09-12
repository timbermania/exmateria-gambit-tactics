"""Tests for tools/parse_evtchr_frames.py.

Validates the Block-Pointers + Block-Data decode at +0x500..+0x77F of
each EVTCHR.BIN segment. Sources of truth:

- Block descriptor bit layout — identical to TYPE1 SHP, see `parse_shp.py`
  docstring. Cross-verified by computing the same source rect under the
  SHP convention as `parse_evtchr_frames.decode_block` and matching.
- Frame byte 0xE0 of segment 0 — the same block data that disc index 7
  (formerly keyed 0xD9 before the +7 runtime shift was decoded) emits;
  it's the Ovelia "kneel" pose. The bytecode for chapel scenario 1's
  segment-0 anim 0 names this runtime byte.
- Frame byte 0xF3 of segment 0 — the Ovelia head-bowed pose sourced from
  disc index 0xEC, used by anim 0x263 (`F3 06 F4 02 FF FF`).

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_evtchr_frames
"""

from __future__ import annotations

import unittest

import parse_evtchr_frames as pef
from _repo_paths import event_dir


EVTCHR_PATH = event_dir() / "EVTCHR.BIN"


@unittest.skipUnless(EVTCHR_PATH.exists(), f"EVTCHR.BIN not present at {EVTCHR_PATH}")
class ParseAllSegmentsShape(unittest.TestCase):
    """137 segments × 40 frames; every frame must decode (block lists may be empty)."""

    def test_137_segments(self) -> None:
        table = pef.parse_evtchr_frames(EVTCHR_PATH)
        self.assertEqual(len(table), 137)
        for seg_id in range(137):
            self.assertIn(seg_id, table, f"segment {seg_id} missing")
            self.assertEqual(
                len(table[seg_id]), 40,
                f"segment {seg_id} has {len(table[seg_id])} frames, expected 40",
            )

    def test_frame_id_range_is_d2_to_f9(self) -> None:
        table = pef.parse_evtchr_frames(EVTCHR_PATH)
        for seg_id, frames in table.items():
            self.assertEqual(
                sorted(frames.keys()), list(range(0xD2, 0xFA)),
                f"segment {seg_id} frame ids != 0xD2..0xF9",
            )


@unittest.skipUnless(EVTCHR_PATH.exists(), f"EVTCHR.BIN not present at {EVTCHR_PATH}")
class Segment0KneelFrame(unittest.TestCase):
    """Runtime byte 0xE0 of segment 0 is the chapel-kneel pose (disc index 7,
    formerly keyed as 0xD9 before the +7 runtime shift was decoded). Verifies
    one specific descriptor end-to-end against the byte sequence at file
    offset 0x5F4:

        00 00 EF DD 40 2D
        ^^ ^^                  count_minus_1=0 (1 block), pad
              ^^^^^^^^^^^      block: shift_x=-17, shift_y=-35,
                               flags=0x2D40 → src=(0, 80), size_index=11 → 32x40
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.seg0 = pef.parse_evtchr_frames(EVTCHR_PATH)[0]

    def test_frame_e0_one_block(self) -> None:
        blocks = self.seg0[0xE0]
        self.assertEqual(len(blocks), 1)

    def test_frame_e0_block_descriptor(self) -> None:
        block = self.seg0[0xE0][0]
        self.assertEqual(block["location_x"], -17)
        self.assertEqual(block["location_y"], -35)
        self.assertEqual(block["rectangle_x"], 0)
        self.assertEqual(block["rectangle_y"], 80)
        self.assertEqual(block["rectangle_width"], 32)
        self.assertEqual(block["rectangle_height"], 40)
        self.assertFalse(block["revert"])
        self.assertFalse(block["invert"])

    def test_frame_e1_steps_8px_right(self) -> None:
        """Adjacent kneel frame samples one cell (8 px) right of byte 0xE0
        — descriptor `EF DD 44 2D`, flags=0x2D44, tile_x bits = 4."""
        block = self.seg0[0xE1][0]
        self.assertEqual(block["rectangle_x"], 32)
        self.assertEqual(block["rectangle_y"], 80)

    def test_frame_f3_src_160_160(self) -> None:
        """Ovelia head-bowed pose. Runtime byte 0xF3 sources disc index 0xEC,
        which lives at src (160, 160), 32x40 — the first frame of the
        chapel anim 0x263 bytecode `F3 06 F4 02 FF FF`. Fail-fast sentinel
        for the disc-to-runtime +7 shift."""
        block = self.seg0[0xF3][0]
        self.assertEqual(block["rectangle_x"], 160)
        self.assertEqual(block["rectangle_y"], 160)
        self.assertEqual(block["rectangle_width"], 32)


class DecodeBlockUnit(unittest.TestCase):
    """Pure-function tests over the block decoder — no disc dependency."""

    def test_zero_offset_zero_flags(self) -> None:
        b = pef.decode_block(b"\x00\x00\x00\x00")
        self.assertEqual(b["location_x"], 0)
        self.assertEqual(b["location_y"], 0)
        self.assertEqual(b["rectangle_x"], 0)
        self.assertEqual(b["rectangle_y"], 0)
        self.assertEqual(b["rectangle_width"], 8)
        self.assertEqual(b["rectangle_height"], 8)
        self.assertFalse(b["revert"])
        self.assertFalse(b["invert"])

    def test_kneel_pose_descriptor(self) -> None:
        b = pef.decode_block(b"\xEF\xDD\x40\x2D")
        self.assertEqual(b["location_x"], -17)
        self.assertEqual(b["location_y"], -35)
        self.assertEqual(b["rectangle_x"], 0)
        self.assertEqual(b["rectangle_y"], 80)
        self.assertEqual(b["rectangle_width"], 32)
        self.assertEqual(b["rectangle_height"], 40)

    def test_flip_x_only(self) -> None:
        # flag bit 0x4000 set in flags LE u16 → high byte 0x40
        b = pef.decode_block(b"\x00\x00\x00\x40")
        self.assertTrue(b["revert"])
        self.assertFalse(b["invert"])

    def test_flip_y_only(self) -> None:
        # flag bit 0x8000 set in flags LE u16 → high byte 0x80
        b = pef.decode_block(b"\x00\x00\x00\x80")
        self.assertFalse(b["revert"])
        self.assertTrue(b["invert"])

    def test_size_index_11_is_32x40(self) -> None:
        # size_index=11 → bits 10..13 = 0xB → flags 0x2C00, high byte 0x2C
        b = pef.decode_block(b"\x00\x00\x00\x2C")
        self.assertEqual(b["rectangle_width"], 32)
        self.assertEqual(b["rectangle_height"], 40)


class DecodeFrameBlockListUnit(unittest.TestCase):
    """Walks header + N-block descriptor from a hand-constructed Block Data."""

    def test_one_block(self) -> None:
        # Block Data region: count_minus_1=0, pad=0, then 1 descriptor
        block_data = b"\x00\x00\xEF\xDD\x40\x2D" + b"\x00" * (pef.BLOCK_DATA_LEN - 6)
        # Build a fake segment buffer; only the Block Data region matters here.
        buf = b"\x00" * pef.BLOCK_DATA_OFF + block_data
        blocks = pef.decode_frame_block_list(buf, block_ptr=0)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0]["rectangle_y"], 80)

    def test_two_blocks(self) -> None:
        # count_minus_1=1 → 2 descriptors
        block_data = (
            b"\x01\x00"
            b"\x00\x00\x00\x00"
            b"\x08\x10\x00\x00"
            + b"\x00" * (pef.BLOCK_DATA_LEN - 10)
        )
        buf = b"\x00" * pef.BLOCK_DATA_OFF + block_data
        blocks = pef.decode_frame_block_list(buf, block_ptr=0)
        self.assertEqual(len(blocks), 2)
        self.assertEqual(blocks[1]["location_x"], 8)
        self.assertEqual(blocks[1]["location_y"], 16)

    def test_out_of_range_pointer_empty(self) -> None:
        buf = b"\x00" * (pef.BLOCK_DATA_OFF + pef.BLOCK_DATA_LEN)
        blocks = pef.decode_frame_block_list(buf, block_ptr=pef.BLOCK_DATA_LEN + 16)
        self.assertEqual(blocks, [])


if __name__ == "__main__":
    unittest.main()
