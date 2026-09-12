"""Tests for tools/parse_cinematic_seq.py.

EVTCHR.BIN's per-segment Animation table (the cinematic SEQ data the
event-script `0x58 Load EVTCHR` opcode copies into RAM at 0x800AED3C
when `Block=2`). Layout per segment (offsets repeat every 0x7800 B):

    +0x0000 .. +0x00FF   64 u32 LE anim_offset entries
                         (relative to the anim-data region @ +0x0100)
    +0x0100 .. +0x04FF   1024 B variable-length bytecode
                         (FF FF / FF FE terminators, FFxx opcodes)
    +0x0500 .. +0x077F   block pointers + block data (not parsed here)
    +0x0780 ..           palettes + image (handled by parse_evtchr.py)

Authority: EVTCHR Frame Editor v1.1 by Xifanie (EVTCHR Addresses sheet),
cross-checked against RAM `0x800AED3C` in
`reference-assets/orbonne_prayer_mid_dialog.sstate` per
`research/working_documents/scenario_1_captures/cinematic_seq_source_decode.md`.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_cinematic_seq
"""

from __future__ import annotations

import struct
import unittest
from pathlib import Path

import parse_cinematic_seq as pc
from _repo_paths import event_dir


EVTCHR_PATH = event_dir() / "EVTCHR.BIN"


@unittest.skipUnless(EVTCHR_PATH.exists(), f"EVTCHR.BIN not present at {EVTCHR_PATH}")
class ParseAllSegmentsShape(unittest.TestCase):
    """The file holds 137 segments; each parses to 64 cinematic anims."""

    def test_137_segments(self) -> None:
        table = pc.parse_cinematic_seq(EVTCHR_PATH)
        self.assertEqual(len(table), 137)
        for seg_id in range(137):
            self.assertIn(seg_id, table, f"segment {seg_id} missing")
            self.assertEqual(len(table[seg_id]), 64, f"segment {seg_id} != 64 anims")


@unittest.skipUnless(EVTCHR_PATH.exists(), f"EVTCHR.BIN not present at {EVTCHR_PATH}")
class Segment0MatchesChapelCinematic(unittest.TestCase):
    """EVTCHR segment 0 is the cinematic anim set that gets loaded into the
    high-cinematic RAM table (0x800AED3C) for scenario 1's chapel prayer.
    The first 8 anims must byte-match what the savestate dump showed
    (Move B doc / cinematic_seq_source_decode.md §2-3).
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.seg0 = pc.parse_cinematic_seq(EVTCHR_PATH)[0]

    def test_anim_0_is_kneel(self) -> None:
        """anim 0 = frame 0xD9, hold 2 ticks, PauseAnimation — the kneel pose."""
        anim = self.seg0[0]
        self.assertEqual(len(anim), 2, f"expected 2 instructions, got {anim}")
        self.assertEqual(anim[0]["op_code_name"], "LoadFrameWait")
        self.assertEqual(anim[0]["op_code_param_0"], 0xD9)
        self.assertEqual(anim[0]["op_code_param_1"], 0x02)
        self.assertEqual(anim[1]["op_code_name"], "PauseAnimation")
        self.assertEqual(anim[1]["op_code_hex"], "0xFFFF")

    def test_anim_1_is_d5_hold(self) -> None:
        anim = self.seg0[1]
        self.assertEqual(anim[0]["op_code_param_0"], 0xD5)
        self.assertEqual(anim[1]["op_code_name"], "PauseAnimation")

    def test_anim_3_is_two_frame_hold(self) -> None:
        """anim 3 = `E7 08 E8 02 FF FF` — two LoadFrameWait + PauseAnimation."""
        anim = self.seg0[3]
        self.assertEqual(len(anim), 3)
        self.assertEqual(anim[0]["op_code_param_0"], 0xE7)
        self.assertEqual(anim[0]["op_code_param_1"], 0x08)
        self.assertEqual(anim[1]["op_code_param_0"], 0xE8)
        self.assertEqual(anim[1]["op_code_param_1"], 0x02)
        self.assertEqual(anim[2]["op_code_name"], "PauseAnimation")

    def test_anim_18_is_female_knight_walk(self) -> None:
        """anim 18 (event-script anim 0x26A) = the female knight's walk-in.

        Regression: this is the LAST used anim in segment 0 — local 19's
        pointer is 0, so the old "bound by ptrs[anim_idx+1]" logic computed
        end=0 and dropped it, leaving her with no oriented EVTCHR frames so
        she fell back to a wrong-facing SHP cardinal frame. The walk cycle is
        `DB 0C DC 08 DD 08 DE 0C DD 0A DC 0A FF D5 FF FF` — six oriented
        LoadFrameWait frames (0xDB..0xDE, all >= 0xD2 = EVTCHR atlas) then a
        loop + PauseAnimation.
        """
        anim = self.seg0[18]
        self.assertGreater(len(anim), 0, "female-knight walk dropped (parser bug)")
        frames = [i["op_code_param_0"] for i in anim
                  if i["op_code_name"] == "LoadFrameWait"]
        self.assertEqual(frames, [0xDB, 0xDC, 0xDD, 0xDE, 0xDD, 0xDC])
        self.assertTrue(all(f >= 0xD2 for f in frames),
                        "walk frames must be EVTCHR-range (>= 0xD2)")
        self.assertEqual(anim[-1]["op_code_name"], "PauseAnimation")

    def test_unused_slot_is_empty_not_anim0_dupe(self) -> None:
        """Slot 63 has pointer 0 (unused). It must decode to [] — NOT to a
        spurious duplicate of anim 0. The old code treated a 0 pointer as
        "start at data-region offset 0" for every slot, so every segment's
        slot 63 came out as a phantom copy of anim 0's bytecode.
        """
        self.assertEqual(self.seg0[63], [])


class DecodeBytecodeUnit(unittest.TestCase):
    """Pure-function tests over the bytecode decoder — no disc dependency."""

    def test_single_frame_then_pause(self) -> None:
        instrs = pc.decode_bytecode(b"\xD9\x02\xFF\xFF", seq_no=0)
        self.assertEqual(len(instrs), 2)
        self.assertEqual(instrs[0]["op_code_name"], "LoadFrameWait")
        self.assertEqual(instrs[0]["op_code_param_0"], 0xD9)
        self.assertEqual(instrs[1]["op_code_name"], "PauseAnimation")

    def test_end_animation_terminator(self) -> None:
        """0xFFFE is EndAnimation — also a terminator."""
        instrs = pc.decode_bytecode(b"\x10\x02\xFF\xFE", seq_no=0)
        self.assertEqual(instrs[-1]["op_code_name"], "EndAnimation")


class ParseSegmentBounds(unittest.TestCase):
    """Disc-independent tests over `_parse_segment` — synthetic 0x7800 buffer.

    Pins the pointer-bounding contract directly so the female-knight
    regression is guarded even when EVTCHR.BIN is absent.
    """

    @staticmethod
    def _make_segment(pointers: list[int], data: bytes) -> bytes:
        buf = bytearray(pc.SEGMENT_SIZE)
        ptrs = (pointers + [0] * pc.ANIMS_PER_SEGMENT)[: pc.ANIMS_PER_SEGMENT]
        struct.pack_into(f"<{pc.ANIMS_PER_SEGMENT}I", buf, 0, *ptrs)
        buf[pc.ANIM_DATA_OFF : pc.ANIM_DATA_OFF + len(data)] = data
        return bytes(buf)

    def test_last_anim_before_zero_run_is_kept(self) -> None:
        """anim 1 starts at 4 and is followed by a 0 pointer (anim 2 unused).
        It must still decode — the old end=ptrs[idx+1]=0 bound dropped it."""
        # anim 0: D9 02 FF FF (off 0), anim 1: DB 02 FF FF (off 4), rest unused.
        data = b"\xD9\x02\xFF\xFF\xDB\x02\xFF\xFF"
        seg = pc._parse_segment(self._make_segment([0, 4], data), seg_id=0)
        self.assertEqual(seg[0][0]["op_code_param_0"], 0xD9)
        self.assertEqual(seg[1][0]["op_code_param_0"], 0xDB,
                         "anim before a zero-pointer slot was dropped")
        self.assertEqual(seg[1][-1]["op_code_name"], "PauseAnimation")

    def test_zero_pointer_slot_is_empty(self) -> None:
        """A non-first slot with pointer 0 is unused → [] (not an anim-0 dupe)."""
        data = b"\xD9\x02\xFF\xFF"
        seg = pc._parse_segment(self._make_segment([0, 4], data), seg_id=0)
        self.assertEqual(seg[2], [])
        self.assertEqual(seg[63], [])


if __name__ == "__main__":
    unittest.main()
