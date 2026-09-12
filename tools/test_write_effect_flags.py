"""Unit tests for the byte-exact EFFECT-FLAGS writer (#272).

`write_effect_flags.patch_effect_flags_section` is the inverse of the flags-byte
half of `parse_effect.parse_effect_flags`: given the base `E###.BIN` bytes, the
parsed (possibly edited) flags block (`{flags_byte: int}`), and the header's
`effect_flags_ptr`, it returns a NEW buffer in which ONLY the single flags byte
@ effect_flags_ptr + 0x00 is rewritten. Every other byte — the dead
`spawn_delay_override` @0x04, the 16 sound-channel bytes @0x08-0x17, and the
whole rest of the file — is preserved verbatim (a partial patch, mirroring
write_effect_timeline_header).

The critical invariant (ADR-0092): the engine-ignored bits 0-2 and 7 ride along
untouched, because the word is written from the raw byte the author seeded, not
re-derived from the four decoded bools. E001 stores flags 0x03 (bits 0,1 both
ignored); toggling an engine-read bit must keep those two set.

Expected offsets are an INDEPENDENT copy of the layout recomputed here, NOT the
writer's own constants.

Run from tools/:
    python3 -m unittest test_write_effect_flags
"""

from __future__ import annotations

import os
import unittest

import parse_effect as pe
import write_effect_flags as wef


# --- Independent layout (recomputed, not imported from the writer) ------------
_OFF_FLAGS = 0x00
_FLAGS_PTR = 0x100  # arbitrary base for synthetic buffers

_EXTRACT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "..", "project-assets", "fft-extract", "EFFECT"
)
_E001 = os.path.join(_EXTRACT_DIR, "E001.BIN")
_E019 = os.path.join(_EXTRACT_DIR, "E019.BIN")


def _synthetic_base() -> bytearray:
    """A blob big enough to hold the 24-byte effect_flags section at _FLAGS_PTR,
    junk-filled so any stray write shows up as a diff."""
    size = _FLAGS_PTR + 0x40
    return bytearray((i * 7 + 3) & 0xFF for i in range(size))


class SyntheticPrecision(unittest.TestCase):
    def test_only_the_flags_byte_changes(self):
        base = _synthetic_base()
        block = {"flags_byte": 0x68}  # bits 3,5,6
        out = wef.patch_effect_flags_section(bytes(base), block, _FLAGS_PTR)

        self.assertEqual(out[_FLAGS_PTR + _OFF_FLAGS], 0x68)
        changed = [i for i in range(len(base)) if out[i] != base[i]]
        self.assertEqual(changed, [_FLAGS_PTR + _OFF_FLAGS],
                         "only the single flags byte changes, got %s" % changed)

    def test_dead_byte_and_sound_channels_preserved(self):
        base = _synthetic_base()
        # 0x04 (dead spawn_delay_override) and 0x08-0x17 (sound channels) must be untouched.
        untouched = [_FLAGS_PTR + 0x04] + list(range(_FLAGS_PTR + 0x08, _FLAGS_PTR + 0x18))
        out = wef.patch_effect_flags_section(bytes(base), {"flags_byte": 0xFF}, _FLAGS_PTR)
        for i in untouched:
            self.assertEqual(out[i], base[i],
                             "byte 0x%X (dead/sound) preserved" % (i - _FLAGS_PTR))

    def test_only_low_byte_written(self):
        # A flags_byte with stray high bits set is masked to a single byte — never
        # spills into 0x01.
        base = _synthetic_base()
        out = wef.patch_effect_flags_section(bytes(base), {"flags_byte": 0x123}, _FLAGS_PTR)
        self.assertEqual(out[_FLAGS_PTR + _OFF_FLAGS], 0x23)
        self.assertEqual(out[_FLAGS_PTR + 0x01], base[_FLAGS_PTR + 0x01],
                         "the neighbouring byte is never touched")


@unittest.skipUnless(os.path.exists(_E019), "E019 ROM extract not present")
class RealE019RoundTrip(unittest.TestCase):
    def _ptr(self, data: bytes) -> int:
        return pe.parse_header(data)["effect_flags_ptr"]

    def test_unedited_reserialize_is_byte_identical(self):
        data = open(_E019, "rb").read()
        ptr = self._ptr(data)
        # E019 flags byte is 0x23 (bits 0,1,5) — independently confirmed.
        self.assertEqual(data[ptr], 0x23)
        out = wef.patch_effect_flags_section(data, {"flags_byte": data[ptr]}, ptr)
        self.assertEqual(out, data, "re-serializing the unedited flags byte round-trips byte-exact")

    def test_toggle_time_scale_3phase_off_changes_one_byte(self):
        data = open(_E019, "rb").read()
        ptr = self._ptr(data)
        # Clear bit5 (0x20, TIME_SCALE_3PHASE): 0x23 -> 0x03. Bits 0,1 (ignored) survive.
        new_byte = data[ptr] & ~0x20
        self.assertEqual(new_byte, 0x03)
        out = wef.patch_effect_flags_section(data, {"flags_byte": new_byte}, ptr)
        changed = [i for i in range(len(data)) if out[i] != data[i]]
        self.assertEqual(changed, [ptr], "editing the flags byte touches only its own byte")
        # And it reads back through the parser with bits 0,1 preserved, bit5 cleared.
        rt = pe.parse_effect_flags(out, ptr)
        self.assertEqual(rt["flags_byte"], 0x03)
        self.assertFalse(rt["time_scale_pattern1"])


@unittest.skipUnless(os.path.exists(_E001), "E001 ROM extract not present")
class IgnoredBitsSurviveE001(unittest.TestCase):
    def test_toggling_an_engine_bit_keeps_ignored_bits_0_and_1(self):
        data = open(_E001, "rb").read()
        ptr = pe.parse_header(data)["effect_flags_ptr"]
        self.assertEqual(data[ptr], 0x03, "E001 seeds ignored bits 0,1")
        # Author turns TIME_SCALE_3PHASE (bit5) ON over the raw byte: 0x03 -> 0x23.
        new_byte = data[ptr] | 0x20
        out = wef.patch_effect_flags_section(data, {"flags_byte": new_byte}, ptr)
        self.assertEqual(out[ptr], 0x23, "bit5 set AND ignored bits 0,1 preserved")
        # If the writer had re-derived the word from the four bools it would drop 0,1.
        self.assertEqual(out[ptr] & 0x03, 0x03)


if __name__ == "__main__":
    unittest.main()
