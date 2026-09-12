"""Unit tests for the byte-exact PARTICLE-TIMELINE writer (ADR-0089
particle_timeline amendment, slice 1).

`write_effect_particle_timeline.patch_particle_timeline_section` is the inverse of
`parse_effect.parse_timeline`'s particle channels: given the base `E###.BIN`
bytes, the parsed (possibly edited) timeline block, and the header's
`timeline_section_ptr`, it returns a NEW buffer in which each 128-byte particle
channel's SoA arrays (time / emitter_id / action_flags + max_keyframe) are
re-serialized from their raw values. Every byte outside those fields — the
0x7C/0x7D gap, the tail past 0x7F, and any channel absent from the block — is
preserved verbatim (a partial patch, mirroring write_effect_camera).

THE RISK THIS GUARDS: the SoA `time[]` and `emitter_id[]` arrays share byte 0x31
(time[24].hi aliases emitter_id[0]). The round-trip guard is the gate that the
write order (time[] before emitter_id[]) reproduces that shared byte.

Expected offsets are an INDEPENDENT copy of the layout recomputed here, NOT the
writer's own constants.

Run from tools/:
    python3 -m unittest test_write_effect_particle_timeline
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_particle_timeline as wpt
import effect_writer_registry as ewr
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


# --- Independent layout (recomputed, not imported from the writer) ------------
_CH_SIZE = 128
_SLOTS = 25
_OFF_TIME = 0x00
_OFF_EMITTER = 0x31
_OFF_FLAGS = 0x4A
_OFF_MAXKF = 0x7E
_TIMELINE_PTR = 0x100  # arbitrary base for synthetic buffers


def _for_each_offset(idx: int) -> int:
    return _TIMELINE_PTR + 8 + [0x0004, 0x0084, 0x0104, 0x0184, 0x0204][idx]


def _synthetic_channel_bytes(seed: int) -> bytes:
    """128 deterministic bytes so signed times, the 0x31 overlap byte, and the
    0x7C/0x7D gap are all exercised."""
    return bytes((i * 13 + seed) & 0xFF for i in range(_CH_SIZE))


def _base_buffer() -> bytearray:
    """A blob big enough for a full for_each block, junk-filled everywhere so any
    stray write shows up as a diff."""
    size = _for_each_offset(4) + _CH_SIZE + 64
    return bytearray((i * 7 + 3) & 0xFF for i in range(size))


def _one_channel_block(idx: int, base: bytearray, context: str = "for_each"):
    """Parse one channel out of `base` at lane `idx` into a timeline block with a
    single channel — the minimal edit set the writer accepts."""
    off = _for_each_offset(idx)
    ch = pe.parse_particle_channel(bytes(base), off, context, idx)
    return {"particle_channels": [ch]}


class UnchangedRoundTrip(unittest.TestCase):
    def test_unedited_single_channel_is_byte_identical(self):
        base = _base_buffer()
        # stamp a realistic channel (non-trivial times incl. a high-byte value)
        off = _for_each_offset(0)
        base[off:off + _CH_SIZE] = _synthetic_channel_bytes(5)
        block = _one_channel_block(0, base)
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        self.assertEqual(out, bytes(base))

    def test_absent_channels_touch_nothing(self):
        """Only lane 0 is in the edit set; lanes 1-4's bytes are untouched."""
        base = _base_buffer()
        for i in range(5):
            off = _for_each_offset(i)
            base[off:off + _CH_SIZE] = _synthetic_channel_bytes(11 + i)
        block = _one_channel_block(0, base)
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        self.assertEqual(out, bytes(base))


class SharedByteOverlap(unittest.TestCase):
    """The time[24].hi / emitter_id[0] alias at byte 0x31: emitter_id owns it."""

    def test_emitter_id0_wins_shared_byte(self):
        base = _base_buffer()
        off = _for_each_offset(0)
        block = _one_channel_block(0, base)
        ch = block["particle_channels"][0]
        ch["keyframes"][0]["emitter_id"] = 0x07
        ch["keyframes"][24]["time"] = 0  # phantom slot; must not fight 0x31
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        self.assertEqual(out[off + _OFF_EMITTER], 0x07)

    def test_unedited_overlap_roundtrips_when_byte31_nonzero(self):
        """A channel whose emitter_id[0] != 0 (so byte 0x31 != 0, and time[24]
        over-reads it) still round-trips byte-identical unedited."""
        base = _base_buffer()
        off = _for_each_offset(0)
        base[off + _OFF_EMITTER] = 0x42  # emitter_id[0] = time[24].hi = 0x42
        block = _one_channel_block(0, base)
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        self.assertEqual(out[off:off + _CH_SIZE], bytes(base[off:off + _CH_SIZE]))


class SingleFieldDiffs(unittest.TestCase):
    def _diff(self, base, out):
        return [i for i in range(len(base)) if base[i] != out[i]]

    def test_time_edit_is_one_s16(self):
        base = _base_buffer()
        off = _for_each_offset(0)
        block = _one_channel_block(0, base)
        block["particle_channels"][0]["keyframes"][3]["time"] = 600
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        want = off + _OFF_TIME + 3 * 2
        self.assertEqual(set(self._diff(base, out)) - {want, want + 1}, set())
        self.assertEqual(struct.unpack_from("<h", out, want)[0], 600)

    def test_emitter_id_edit_is_one_byte(self):
        base = _base_buffer()
        off = _for_each_offset(0)
        block = _one_channel_block(0, base)
        block["particle_channels"][0]["keyframes"][2]["emitter_id"] = 9
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        self.assertEqual(self._diff(base, out), [off + _OFF_EMITTER + 2])

    def test_action_flags_edit_is_one_u16(self):
        base = _base_buffer()
        off = _for_each_offset(0)
        block = _one_channel_block(0, base)
        block["particle_channels"][0]["keyframes"][2]["action_flags"] = 0x10
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        want = off + _OFF_FLAGS + 2 * 2
        self.assertEqual(set(self._diff(base, out)) - {want, want + 1}, set())
        self.assertEqual(struct.unpack_from("<H", out, want)[0], 0x10)

    def test_max_keyframe_edit_is_one_s16(self):
        base = _base_buffer()
        off = _for_each_offset(0)
        block = _one_channel_block(0, base)
        block["particle_channels"][0]["max_keyframe"] = 4
        out = wpt.patch_particle_timeline_section(bytes(base), block, _TIMELINE_PTR)
        want = off + _OFF_MAXKF
        self.assertEqual(set(self._diff(base, out)) - {want, want + 1}, set())
        self.assertEqual(struct.unpack_from("<h", out, want)[0], 4)


class RegistryEntry(unittest.TestCase):
    def test_section_is_registered(self):
        self.assertIn("particle_timeline", ewr.registered_sections())

    def test_patch_all_routes_particle_timeline(self):
        base = _base_buffer()
        off = _for_each_offset(0)
        block = _one_channel_block(0, base)
        block["particle_channels"][0]["keyframes"][1]["emitter_id"] = 5
        header = {"timeline_section_ptr": _TIMELINE_PTR}
        out = ewr.patch_all(bytes(base), {"particle_timeline": block}, header)
        self.assertEqual(out[off + _OFF_EMITTER + 1], 5)


_E019 = str(_effect_dir() / "E019.BIN")
_E317 = str(_effect_dir() / "E317.BIN")


class RealEffectRoundTrip(unittest.TestCase):
    def _roundtrip(self, path):
        with open(path, "rb") as f:
            base = f.read()
        header = pe.parse_header(base, 0)
        tp = header["timeline_section_ptr"]
        tl = pe.parse_timeline(base, tp, header["sound_def_ptr"] - tp)
        out = wpt.patch_particle_timeline_section(base, tl, tp)
        self.assertEqual(out, base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_e019_all_channels_byte_identical(self):
        self._roundtrip(_E019)

    @unittest.skipUnless(os.path.exists(_E317), "E317.BIN not available")
    def test_e317_all_channels_byte_identical(self):
        self._roundtrip(_E317)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_edit_survives_and_neighbours_stay_identical(self):
        """The Studio save contract: parse a real effect (E019, emitter-rich, 15 channels),
        edit ONE channel's kf[1].time + emitter_id, write, re-parse — the edit is present and
        EVERY other channel is byte-for-byte what it was (a partial patch never corrupts a
        neighbour)."""
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base, 0)
        tp = header["timeline_section_ptr"]
        tl = pe.parse_timeline(base, tp, header["sound_def_ptr"] - tp)

        target = tl["particle_channels"][0]
        target["keyframes"][1]["time"] = 123
        target["keyframes"][1]["emitter_id"] = 4
        out = wpt.patch_particle_timeline_section(base, tl, tp)

        # Re-parse the patched bytes: the edit landed.
        tl2 = pe.parse_timeline(out, tp, header["sound_def_ptr"] - tp)
        self.assertEqual(tl2["particle_channels"][0]["keyframes"][1]["time"], 123)
        self.assertEqual(tl2["particle_channels"][0]["keyframes"][1]["emitter_id"], 4)

        # Every OTHER particle channel's on-disk bytes are unchanged (only channel 0 moved).
        edited_off = pe.particle_channel_offset(tp, "for_each", 0)
        for ctx, offs in (("for_each", pe.PARTICLE_FOR_EACH_OFFSETS),
                          ("phase1", pe.PARTICLE_PHASE1_OFFSETS),
                          ("phase2", pe.PARTICLE_PHASE2_OFFSETS)):
            for i in range(len(offs)):
                off = pe.particle_channel_offset(tp, ctx, i)
                if off == edited_off:
                    continue
                self.assertEqual(out[off:off + pe.PARTICLE_CHANNEL_SIZE],
                                 base[off:off + pe.PARTICLE_CHANNEL_SIZE],
                                 "channel %s[%d] must stay byte-identical" % (ctx, i))


if __name__ == "__main__":
    unittest.main()
