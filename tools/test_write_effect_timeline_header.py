"""Unit tests for the byte-exact TIMELINE-HEADER writer (#271).

`write_effect_timeline_header.patch_timeline_header_section` is the inverse of the
header half of `parse_effect.parse_timeline`: given the base `E###.BIN` bytes, the
parsed (possibly edited) timeline block, and the header's `timeline_section_ptr`,
it returns a NEW buffer in which ONLY the three phase-duration u16s
(phase1_duration @+0x04, spawn_delay @+0x06, phase2_delay @+0x0A) are rewritten.
Every other byte — the engine-ignored header words (0x00-0x03, 0x08-0x09), the
particle channels, and the whole rest of the file — is preserved verbatim (a
partial patch, mirroring write_effect_particle_timeline).

Expected offsets are an INDEPENDENT copy of the layout recomputed here, NOT the
writer's own constants.

Run from tools/:
    python3 -m unittest test_write_effect_timeline_header
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_timeline_header as wth


# --- Independent layout (recomputed, not imported from the writer) ------------
_OFF_PHASE1 = 0x04
_OFF_SPAWN = 0x06
_OFF_PHASE2 = 0x0A
_TIMELINE_PTR = 0x100  # arbitrary base for synthetic buffers

_EXTRACT = os.path.join(
    os.path.dirname(__file__), "..", "..", "project-assets", "fft-extract", "EFFECT", "E019.BIN"
)


def _synthetic_base() -> bytearray:
    """A blob big enough to hold a timeline header at _TIMELINE_PTR, junk-filled so
    any stray write shows up as a diff."""
    size = _TIMELINE_PTR + 0x40
    return bytearray((i * 7 + 3) & 0xFF for i in range(size))


def _header_block(p1: int, spawn: int, p2: int) -> dict:
    return {"header": {"phase1_duration": p1, "spawn_delay": spawn, "phase2_delay": p2}}


class SyntheticPrecision(unittest.TestCase):
    def test_only_the_three_durations_change(self):
        base = _synthetic_base()
        block = _header_block(120, 15, 4)
        out = wth.patch_timeline_header_section(bytes(base), block, _TIMELINE_PTR)

        # The three u16s are the NEW values...
        self.assertEqual(struct.unpack_from("<H", out, _TIMELINE_PTR + _OFF_PHASE1)[0], 120)
        self.assertEqual(struct.unpack_from("<H", out, _TIMELINE_PTR + _OFF_SPAWN)[0], 15)
        self.assertEqual(struct.unpack_from("<H", out, _TIMELINE_PTR + _OFF_PHASE2)[0], 4)

        # ...and EVERY OTHER byte is verbatim (diff only at the 6 patched bytes).
        changed = [i for i in range(len(base)) if out[i] != base[i]]
        expected = list(range(_TIMELINE_PTR + _OFF_PHASE1, _TIMELINE_PTR + _OFF_PHASE1 + 2)) \
            + list(range(_TIMELINE_PTR + _OFF_SPAWN, _TIMELINE_PTR + _OFF_SPAWN + 2)) \
            + list(range(_TIMELINE_PTR + _OFF_PHASE2, _TIMELINE_PTR + _OFF_PHASE2 + 2))
        self.assertEqual(changed, sorted(expected))

    def test_engine_ignored_header_words_are_preserved(self):
        base = _synthetic_base()
        # bytes 0x00-0x03 (unknown_00/02) and 0x08-0x09 (unknown_08) must be untouched.
        untouched = list(range(_TIMELINE_PTR, _TIMELINE_PTR + 0x04)) \
            + list(range(_TIMELINE_PTR + 0x08, _TIMELINE_PTR + 0x0A))
        out = wth.patch_timeline_header_section(bytes(base), _header_block(99, 1, 2), _TIMELINE_PTR)
        for i in untouched:
            self.assertEqual(out[i], base[i], "byte 0x%X (engine-ignored) preserved" % (i - _TIMELINE_PTR))


@unittest.skipUnless(os.path.exists(_EXTRACT), "E019 ROM extract not present")
class RealE019RoundTrip(unittest.TestCase):
    def _ptr(self, data: bytes) -> int:
        return pe.parse_header(data)["timeline_section_ptr"]

    def test_unedited_reserialize_is_byte_identical(self):
        data = open(_EXTRACT, "rb").read()
        ptr = self._ptr(data)
        header = pe.parse_timeline(data, ptr, 64)["header"]
        block = {"header": header}
        out = wth.patch_timeline_header_section(data, block, ptr)
        self.assertEqual(out, data, "re-serializing unedited durations round-trips byte-exact")

    def test_edit_phase1_changes_only_two_bytes(self):
        data = open(_EXTRACT, "rb").read()
        ptr = self._ptr(data)
        header = pe.parse_timeline(data, ptr, 64)["header"]
        header["phase1_duration"] = int(header["phase1_duration"]) + 24
        out = wth.patch_timeline_header_section(data, {"header": header}, ptr)
        changed = [i for i in range(len(data)) if out[i] != data[i]]
        # A partial patch touches AT MOST phase1_duration's own 2 bytes (fewer when a
        # byte is unchanged — 96->120 leaves the zero high byte alone) and nothing else.
        self.assertTrue(changed, "the edit changed something")
        self.assertTrue(set(changed).issubset({ptr + _OFF_PHASE1, ptr + _OFF_PHASE1 + 1}),
                        "editing phase1_duration touches only its own 2 bytes, got %s" % changed)
        # And it reads back through the parser as the edited value.
        self.assertEqual(pe.parse_timeline(out, ptr, 64)["header"]["phase1_duration"],
                         int(header["phase1_duration"]))


if __name__ == "__main__":
    unittest.main()
