"""Unit tests for the byte-exact ANIMATION/SEQUENCE writer (#275).

`write_effect_animation.patch_animation_section` is the inverse of
`parse_effect.parse_animations_section`, restricted to v1's in-place-parameter-
edits-only scope (see write_effect_animation.py's module docstring). Given the
base E###.BIN bytes and the parsed (possibly edited) `animations` block, it
returns a NEW byte buffer in which only each opcode's parameter bytes are
rewritten — the sequence count, the per-sequence offset table, and every
non-FRAME opcode's type byte survive verbatim.

Expected byte offsets are computed here from an INDEPENDENT hand-built layout
(not the writer's own `_iter_opcode_offsets`), mirroring test_write_effect_frames.

Run from tools/:
    python3 -m unittest test_write_effect_animation
"""

from __future__ import annotations

import glob
import os
import struct
import unittest

import parse_effect as pe
import write_effect_animation as wea
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


ANIM_PTR = 0x40
SECTION_SIZE = 32

# Independent layout: 2 sequences. Offsets in the table are relative to
# animation_ptr + 4 (the byte after the u32 count), matching
# parse_animations_section's `animation_ptr + 4 + seq_offset`.
#
#   +0x00  u32 count = 2
#   +0x04  u16 offset[0] = 4   -> seq0 @ 0x40+4+4  = 0x48
#   +0x06  u16 offset[1] = 13  -> seq1 @ 0x40+4+13 = 0x51
#
#   seq0 @ 0x48: SET_OFFSET(5B) 0x48..0x4C | FRAME(3B) 0x4D..0x4F | LOOP(1B) 0x50
#   seq1 @ 0x51: ADD_OFFSET(3B) 0x51..0x53 | FRAME(3B) 0x54..0x56 | LOOP(1B) 0x57
_S0_SETOFF = 0x48       # op byte; x @ +1 (s16), y @ +3 (s16)
_S0_FRAME = 0x4D        # frameset byte; duration @ +1, depth_mode @ +2
_S0_LOOP = 0x50
_S1_ADDOFF = 0x51       # op byte; dx @ +1 (s8), dy @ +2 (s8)
_S1_FRAME = 0x54
_S1_LOOP = 0x57
_TOTAL_SIZE = ANIM_PTR + SECTION_SIZE


def _build_synthetic_animation_buffer() -> bytearray:
    """A deterministic non-trivial filler buffer with a valid animation section
    laid out at ANIM_PTR (see the layout comment above)."""
    buf = bytearray((i * 7 + 3) & 0xFF for i in range(_TOTAL_SIZE))
    struct.pack_into("<I", buf, ANIM_PTR + 0, 2)     # sequence count
    struct.pack_into("<H", buf, ANIM_PTR + 4, 4)     # seq0 offset
    struct.pack_into("<H", buf, ANIM_PTR + 6, 13)    # seq1 offset

    buf[_S0_SETOFF] = 0x82
    struct.pack_into("<h", buf, _S0_SETOFF + 1, -12)   # x
    struct.pack_into("<h", buf, _S0_SETOFF + 3, 5)     # y
    buf[_S0_FRAME] = 3          # frameset index (opcode byte IS the index)
    buf[_S0_FRAME + 1] = 8      # duration
    buf[_S0_FRAME + 2] = 1      # depth_mode
    buf[_S0_LOOP] = 0x81

    buf[_S1_ADDOFF] = 0x83
    buf[_S1_ADDOFF + 1] = 2 & 0xFF      # dx
    buf[_S1_ADDOFF + 2] = -1 & 0xFF     # dy
    buf[_S1_FRAME] = 5
    buf[_S1_FRAME + 1] = 0
    buf[_S1_FRAME + 2] = 2
    buf[_S1_LOOP] = 0x81
    return buf


def _diff_indices(a: bytes, b: bytes):
    return [i for i in range(min(len(a), len(b))) if a[i] != b[i]]


def _parse(buf) -> list:
    return pe.parse_animations_section(bytes(buf), ANIM_PTR, SECTION_SIZE)


class AnimationWriterSynthetic(unittest.TestCase):
    def setUp(self):
        self.base = bytes(_build_synthetic_animation_buffer())
        self.animations = _parse(self.base)

    def test_layout_fixture_parses_to_the_expected_opcode_stream(self):
        """Guards the hand-built layout itself — if this drifts, every offset
        assertion below is meaningless."""
        self.assertEqual(len(self.animations), 2)
        self.assertEqual([o["type"] for o in self.animations[0]["opcodes"]],
                         ["SET_OFFSET", "FRAME", "LOOP"])
        self.assertEqual([o["type"] for o in self.animations[1]["opcodes"]],
                         ["ADD_OFFSET", "FRAME", "LOOP"])
        self.assertEqual(self.animations[0]["opcodes"][0], {"type": "SET_OFFSET", "x": -12, "y": 5})
        self.assertEqual(self.animations[0]["opcodes"][1],
                         {"type": "FRAME", "frameset": 3, "duration": 8, "depth_mode": 1})
        self.assertEqual(self.animations[1]["opcodes"][0], {"type": "ADD_OFFSET", "dx": 2, "dy": -1})

    def test_unedited_roundtrip_is_byte_identical(self):
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(patched, self.base)

    def test_editing_a_frame_duration_touches_only_the_duration_byte(self):
        self.animations[0]["opcodes"][1]["duration"] = 20
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(_diff_indices(self.base, patched), [_S0_FRAME + 1])
        self.assertEqual(patched[_S0_FRAME + 1], 20)

    def test_editing_a_frame_depth_mode_touches_only_the_depth_byte(self):
        self.animations[1]["opcodes"][1]["depth_mode"] = 5
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(_diff_indices(self.base, patched), [_S1_FRAME + 2])

    def test_editing_a_frameset_writes_the_opcode_byte_itself(self):
        """The FRAME opcode byte IS the frameset index — editing it is the one
        parameter write that lands on an opcode's type byte."""
        self.animations[0]["opcodes"][1]["frameset"] = 100
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(_diff_indices(self.base, patched), [_S0_FRAME])
        self.assertEqual(patched[_S0_FRAME], 100)

    def test_an_out_of_range_frameset_is_masked_so_it_can_never_become_another_opcode(self):
        """v1 forbids TYPE changes. A frameset >= 0x80 would re-encode the FRAME
        as LOOP/SET_OFFSET/ADD_OFFSET and desync every following opcode's offset,
        so the writer masks to 0x7F rather than emit a structure-breaking byte."""
        self.animations[0]["opcodes"][1]["frameset"] = 0x82
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertLessEqual(patched[_S0_FRAME], 0x7F)
        self.assertEqual([o["type"] for o in _parse(patched)[0]["opcodes"]],
                         ["SET_OFFSET", "FRAME", "LOOP"],
                         "the sequence still parses as the same opcode stream")

    def test_editing_set_offset_writes_signed_16_bit_little_endian(self):
        self.animations[0]["opcodes"][0]["x"] = -300
        self.animations[0]["opcodes"][0]["y"] = 1000
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(struct.unpack_from("<h", patched, _S0_SETOFF + 1)[0], -300)
        self.assertEqual(struct.unpack_from("<h", patched, _S0_SETOFF + 3)[0], 1000)
        self.assertEqual(patched[_S0_SETOFF], 0x82, "the SET_OFFSET type byte is never rewritten")

    def test_editing_add_offset_writes_signed_bytes(self):
        self.animations[1]["opcodes"][0]["dx"] = -128
        self.animations[1]["opcodes"][0]["dy"] = 127
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(patched[_S1_ADDOFF + 1], 0x80)
        self.assertEqual(patched[_S1_ADDOFF + 2], 0x7F)
        self.assertEqual(patched[_S1_ADDOFF], 0x83, "the ADD_OFFSET type byte is never rewritten")

    def test_the_count_and_offset_table_are_never_written(self):
        """Structural bytes are v1-immutable: they are how the writer LOCATES
        each opcode, so a parameter edit must never be able to move them."""
        self.animations[0]["opcodes"][1]["duration"] = 99
        self.animations[1]["opcodes"][1]["frameset"] = 7
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(patched[ANIM_PTR:ANIM_PTR + 8], self.base[ANIM_PTR:ANIM_PTR + 8])

    def test_loop_opcodes_are_left_verbatim(self):
        self.animations[0]["opcodes"][1]["duration"] = 42
        patched = wea.patch_animation_section(self.base, self.animations, ANIM_PTR, SECTION_SIZE)
        self.assertEqual(patched[_S0_LOOP], 0x81)
        self.assertEqual(patched[_S1_LOOP], 0x81)

    def test_a_short_animations_block_leaves_the_missing_sequences_untouched(self):
        """v1 never removes entries, but the writer degrades safely (no crash,
        no write) if `animations` is missing a sequence the base bytes have."""
        self.animations[0]["opcodes"][1]["duration"] = 30
        patched = wea.patch_animation_section(self.base, self.animations[:1], ANIM_PTR, SECTION_SIZE)
        self.assertEqual(patched[_S1_ADDOFF:_S1_LOOP + 1], self.base[_S1_ADDOFF:_S1_LOOP + 1])


_EFFECT_DIR = str(_effect_dir())
_E019 = os.path.join(_EFFECT_DIR, "E019.BIN")


def _anim_geometry(base: bytes):
    header = pe.parse_header(base)
    return header["animation_ptr"], header["script_data_ptr"] - header["animation_ptr"]


class AnimationWriterRealFile(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_e019_unedited_roundtrip_is_byte_identical(self):
        with open(_E019, "rb") as f:
            base = f.read()
        ptr, size = _anim_geometry(base)
        animations = pe.parse_animations_section(base, ptr, size)
        self.assertTrue(len(animations) > 0, "E019 has at least one sequence")
        self.assertEqual(wea.patch_animation_section(base, animations, ptr, size), base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_e019_editing_one_duration_is_a_single_byte_diff(self):
        with open(_E019, "rb") as f:
            base = f.read()
        ptr, size = _anim_geometry(base)
        animations = pe.parse_animations_section(base, ptr, size)
        target = next((op for op in animations[0]["opcodes"] if op["type"] == "FRAME"), None)
        self.assertIsNotNone(target, "E019's first sequence has a FRAME opcode")
        target["duration"] = (target["duration"] + 1) % 256

        patched = wea.patch_animation_section(base, animations, ptr, size)

        self.assertEqual(len(_diff_indices(base, patched)), 1)
        reparsed = pe.parse_animations_section(patched, ptr, size)
        self.assertEqual([o["type"] for o in reparsed[0]["opcodes"]],
                         [o["type"] for o in animations[0]["opcodes"]])
        self.assertEqual(reparsed[0]["opcodes"], animations[0]["opcodes"])


class AnimationWriterCorpus(unittest.TestCase):
    """The real acceptance gate, mirroring ADR-0094's regenerator bar: an
    unedited parse -> write round-trip must be byte-identical for EVERY effect
    in the corpus, not just the sample. If the writer's opcode walk disagreed
    with the parser's anywhere, this catches it."""

    @unittest.skipUnless(os.path.isdir(_EFFECT_DIR), "effect corpus not available")
    def test_every_effect_roundtrips_byte_identically(self):
        files = sorted(glob.glob(os.path.join(_EFFECT_DIR, "E*.BIN")))
        self.assertTrue(files, "corpus is non-empty")
        checked, mismatches = 0, []
        for path in files:
            with open(path, "rb") as f:
                base = f.read()
            if len(base) < 40:
                continue
            try:
                ptr, size = _anim_geometry(base)
            except Exception:
                continue
            if ptr <= 0 or size <= 4 or ptr + size > len(base):
                continue
            animations = pe.parse_animations_section(base, ptr, size)
            if not animations:
                continue
            patched = wea.patch_animation_section(base, animations, ptr, size)
            checked += 1
            if patched != base:
                mismatches.append((os.path.basename(path), _diff_indices(base, patched)[:8]))
        self.assertEqual(mismatches, [], "every effect round-trips byte-identically")
        self.assertGreater(checked, 250, "the corpus scan actually covered the bulk of the effects")


if __name__ == "__main__":
    unittest.main()
