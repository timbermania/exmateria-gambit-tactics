"""Unit tests for the byte-exact FRAMES/FRAMESET writer (#278).

`write_effect_frames.patch_frames_section` is the inverse of
`parse_effect.parse_frames_section`, restricted to v1's in-place-field-edits-
only scope (see write_effect_frames.py's module docstring). Given the base
E###.BIN bytes and the parsed (possibly edited) flat `framesets` block, it
returns a NEW byte buffer in which only each frame's editable field bytes
(palette_id, semi_trans_mode, semi_trans_on, is_8bpp, uv.x/y/width/height, the
4 vertex corners) are rewritten — every other byte (group table, per-frameset
offset table, header_flags, frame_count, texture_page, the width_signed/
height_signed flag bits) survives verbatim.

Expected byte offsets are computed here from an INDEPENDENT hand-built layout
(not the writer's own `_iter_frame_offsets`), mirroring test_write_effect_sound.

Run from tools/:
    python3 -m unittest test_write_effect_frames
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_frames as wef2
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


FRAMES_PTR = 0x40
FRAME_SIZE = 24
FRAMESET_HEADER_SIZE = 4

# Independent layout: group_count=1, 2 framesets (1 frame each) in group 0.
#   group_entries_end = 4 + 1*2 = 6; group_entry_offsets[0] = 6 (offset table starts there)
#   offset table @ +6, +8 (u16 each): raw_offset[0]=10 -> fs0 @ +14; raw_offset[1]=38 -> fs1 @ +42
#   terminator @ +10 = 0 (< first_offset=10, discovery stops at 2 framesets)
#   group_sizes[0] = (first_offset(10) - group_entry_offsets[0](6)) / 2 = 2 (both framesets)
#   fs0 header @ +14..+17 (header_flags, frame_count=1); its 1 frame @ +18..+41
#   fs1 header @ +42..+45 (header_flags, frame_count=1); its 1 frame @ +46..+69
_FS0_FRAME0_OFFSET = FRAMES_PTR + 18
_FS1_FRAME0_OFFSET = FRAMES_PTR + 46
_TOTAL_SIZE = FRAMES_PTR + 96


def _build_synthetic_frames_buffer() -> bytearray:
    """A deterministic non-trivial filler buffer with a valid frames-section
    structure laid out at FRAMES_PTR (see the layout comment above)."""
    buf = bytearray((i * 11 + 5) & 0xFF for i in range(_TOTAL_SIZE))
    buf[FRAMES_PTR + 0] = 1  # group_count
    struct.pack_into("<H", buf, FRAMES_PTR + 4, 6)    # group_entry_offsets[0]
    struct.pack_into("<H", buf, FRAMES_PTR + 6, 10)   # raw_offset[0] -> fs0 @ +14
    struct.pack_into("<H", buf, FRAMES_PTR + 8, 38)   # raw_offset[1] -> fs1 @ +42
    struct.pack_into("<H", buf, FRAMES_PTR + 10, 0)   # terminator
    struct.pack_into("<H", buf, FRAMES_PTR + 14, 0x1234)  # fs0 header_flags
    struct.pack_into("<H", buf, FRAMES_PTR + 16, 1)       # fs0 frame_count
    struct.pack_into("<H", buf, FRAMES_PTR + 42, 0x5678)  # fs1 header_flags
    struct.pack_into("<H", buf, FRAMES_PTR + 44, 1)       # fs1 frame_count
    return buf


def _diff_indices(a: bytes, b: bytes) -> list:
    assert len(a) == len(b)
    return [i for i in range(len(a)) if a[i] != b[i]]


class FramesWriterRoundTrip(unittest.TestCase):
    def test_synthetic_structure_parses_as_intended(self):
        """Sanity check on the hand-built layout itself, independent of the writer."""
        base = bytes(_build_synthetic_frames_buffer())
        framesets, group_sizes = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        self.assertEqual(len(framesets), 2)
        self.assertEqual(group_sizes, [2])
        self.assertEqual(len(framesets[0]["frames"]), 1)
        self.assertEqual(len(framesets[1]["frames"]), 1)

    def test_unchanged_roundtrip_is_byte_identical(self):
        """parse -> patch (no edit) reproduces the source buffer exactly."""
        base = bytes(_build_synthetic_frames_buffer())
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        patched = wef2.patch_frames_section(base, framesets, FRAMES_PTR)
        self.assertEqual(patched, base)

    def test_editing_palette_id_touches_only_byte0_of_that_frame(self):
        base = bytes(_build_synthetic_frames_buffer())
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        framesets[0]["frames"][0]["palette_id"] = (framesets[0]["frames"][0]["palette_id"] + 3) % 16

        patched = wef2.patch_frames_section(base, framesets, FRAMES_PTR)

        diffs = _diff_indices(base, patched)
        self.assertEqual(diffs, [_FS0_FRAME0_OFFSET], "only frameset 0 / frame 0's byte0 changes")
        # Independently-computed expected byte: low nibble = new palette_id, other bits preserved.
        expected_byte0 = (base[_FS0_FRAME0_OFFSET] & 0xF0) | framesets[0]["frames"][0]["palette_id"]
        self.assertEqual(patched[_FS0_FRAME0_OFFSET], expected_byte0)
        # frameset 1's frame is completely untouched.
        self.assertEqual(patched[_FS1_FRAME0_OFFSET:_FS1_FRAME0_OFFSET + FRAME_SIZE],
                          base[_FS1_FRAME0_OFFSET:_FS1_FRAME0_OFFSET + FRAME_SIZE])

    def test_editing_semi_trans_mode_preserves_bit4_and_other_byte0_bits(self):
        base = bytearray(_build_synthetic_frames_buffer())
        base[_FS0_FRAME0_OFFSET] = 0b1_01_1_0101  # is_8bpp=1, mode=01, bit4=1, palette=0101
        base = bytes(base)
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        framesets[0]["frames"][0]["semi_trans_mode"] = 2

        patched = wef2.patch_frames_section(base, framesets, FRAMES_PTR)

        # is_8bpp (bit7), bit4, and palette_id (bits0-3) must survive; only mode bits5-6 change.
        expected = 0b1_10_1_0101
        self.assertEqual(patched[_FS0_FRAME0_OFFSET], expected)
        self.assertEqual(_diff_indices(base, patched), [_FS0_FRAME0_OFFSET])

    def test_editing_uv_rect_touches_exactly_bytes_4_through_7(self):
        base = bytes(_build_synthetic_frames_buffer())
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        frame = framesets[1]["frames"][0]
        frame["uv"] = {"x": 10, "y": 20, "width": 30, "height": 40}

        patched = wef2.patch_frames_section(base, framesets, FRAMES_PTR)

        uv_start = _FS1_FRAME0_OFFSET + 4
        self.assertEqual(list(patched[uv_start:uv_start + 4]), [10, 20, 30, 40])
        self.assertEqual(_diff_indices(base, patched), list(range(uv_start, uv_start + 4)))

    def test_editing_a_negative_uv_width_masks_to_the_low_byte(self):
        base = bytes(_build_synthetic_frames_buffer())
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        framesets[0]["frames"][0]["uv"]["width"] = -5

        patched = wef2.patch_frames_section(base, framesets, FRAMES_PTR)

        self.assertEqual(patched[_FS0_FRAME0_OFFSET + 6], (-5) & 0xFF)
        self.assertEqual(patched[_FS0_FRAME0_OFFSET + 6], 251)

    def test_editing_a_vertex_corner_writes_signed_s16_le_and_leaves_siblings(self):
        base = bytes(_build_synthetic_frames_buffer())
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        frame = framesets[0]["frames"][0]
        before_top_right = list(frame["vertices"]["top_right"])
        frame["vertices"]["bottom_right"] = [-100, 200]

        patched = wef2.patch_frames_section(base, framesets, FRAMES_PTR)

        br_offset = _FS0_FRAME0_OFFSET + 8 + 3 * 4
        self.assertEqual(struct.unpack_from("<hh", patched, br_offset), (-100, 200))
        self.assertEqual(_diff_indices(base, patched), [br_offset, br_offset + 1, br_offset + 2, br_offset + 3])
        # A re-parse confirms the untouched top_right vertex is exactly what it was before.
        reparsed, _ = pe.parse_frames_section(patched, FRAMES_PTR, len(patched) - FRAMES_PTR)
        self.assertEqual(reparsed[0]["frames"][0]["vertices"]["top_right"], before_top_right)

    def test_texture_page_and_structural_bytes_are_never_touched(self):
        base = bytes(_build_synthetic_frames_buffer())
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        # Edit every editable field on both frames at once.
        for fs in framesets:
            for fr in fs["frames"]:
                fr["palette_id"] = 9
                fr["semi_trans_mode"] = 3
                fr["semi_trans_on"] = True
                fr["is_8bpp"] = not fr["is_8bpp"]
                fr["uv"] = {"x": 1, "y": 2, "width": 3, "height": 4}
                fr["vertices"] = {c: [7, 8] for c in fr["vertices"]}

        patched = wef2.patch_frames_section(base, framesets, FRAMES_PTR)

        # Structural bytes (group table, offset table, frameset headers) are byte-identical.
        self.assertEqual(patched[FRAMES_PTR:FRAMES_PTR + FRAMESET_HEADER_SIZE + 12],
                          base[FRAMES_PTR:FRAMES_PTR + FRAMESET_HEADER_SIZE + 12])
        # texture_page (+2/+3 of each frame) is byte-identical too.
        for off in (_FS0_FRAME0_OFFSET, _FS1_FRAME0_OFFSET):
            self.assertEqual(patched[off + 2:off + 4], base[off + 2:off + 4])

    def test_edited_block_shorter_than_base_leaves_missing_frames_untouched(self):
        """v1 never removes entries, but the writer degrades safely (no crash, no
        write) if `framesets` is missing a frameset/frame the base bytes have."""
        base = bytes(_build_synthetic_frames_buffer())
        framesets, _ = pe.parse_frames_section(base, FRAMES_PTR, len(base) - FRAMES_PTR)
        framesets[0]["frames"][0]["palette_id"] = 9
        short_framesets = framesets[:1]  # drop frameset 1 entirely

        patched = wef2.patch_frames_section(base, short_framesets, FRAMES_PTR)

        self.assertEqual(patched[_FS1_FRAME0_OFFSET:_FS1_FRAME0_OFFSET + FRAME_SIZE],
                          base[_FS1_FRAME0_OFFSET:_FS1_FRAME0_OFFSET + FRAME_SIZE])


_E019 = str(_effect_dir() / "E019.BIN")


class FramesWriterRealFile(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_e019_unedited_roundtrip_is_byte_identical(self):
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base)
        section_size = header["animation_ptr"] - header["frames_ptr"]
        framesets, _ = pe.parse_frames_section(base, header["frames_ptr"], section_size)
        self.assertTrue(len(framesets) > 0, "E019 has at least one frameset")
        patched = wef2.patch_frames_section(base, framesets, header["frames_ptr"])
        self.assertEqual(patched, base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_e019_editing_one_frames_palette_id_is_a_single_byte_diff(self):
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base)
        section_size = header["animation_ptr"] - header["frames_ptr"]
        framesets, _ = pe.parse_frames_section(base, header["frames_ptr"], section_size)
        frame = framesets[0]["frames"][0]
        frame["palette_id"] = (frame["palette_id"] + 1) % 16

        patched = wef2.patch_frames_section(base, framesets, header["frames_ptr"])

        diffs = _diff_indices(base, patched)
        self.assertEqual(len(diffs), 1, "editing one scalar field touches exactly one byte")
        # Re-parse confirms the edit round-trips and nothing else moved.
        reparsed, _ = pe.parse_frames_section(patched, header["frames_ptr"], section_size)
        self.assertEqual(reparsed[0]["frames"][0]["palette_id"], frame["palette_id"])
        self.assertEqual(len(reparsed), len(framesets))


if __name__ == "__main__":
    unittest.main()
