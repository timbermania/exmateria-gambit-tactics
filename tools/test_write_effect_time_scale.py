"""Unit tests for the byte-exact TIME-SCALE writer (#270).

`write_effect_time_scale.patch_time_scale_section` is the inverse of
`parse_effect.parse_time_scale`'s two curve regions: given the base `E###.BIN`
bytes, the parsed (possibly edited) time_scale block (with `outer_phases` and
`for_each`, each 600 ints), and the header's `time_scale_ptr`, it returns a NEW
buffer in which ONLY the two 300-byte nibble-packed regions are rewritten:

    outer_phases @ time_scale_ptr + 0x000   (600 nibbles -> 300 bytes)
    for_each     @ time_scale_ptr + 0x12C   (600 nibbles -> 300 bytes)

Every other byte — the effect_flags byte that carries the two enable bits (edited
in its own `effect_flags` channel, NOT here), and the whole rest of the file — is
preserved verbatim (a partial patch, mirroring write_effect_flags).

Expected packing is an INDEPENDENT copy of the nibble layout recomputed here, NOT
imported from the writer.

Run from tools/:
    python3 -m unittest test_write_effect_time_scale
"""

from __future__ import annotations

import os
import unittest

import parse_effect as pe
import write_effect_time_scale as wts


# --- Independent layout (recomputed, not imported from the writer) ------------
_REGION_BYTES = 300  # 600 nibbles / 2
_OFF_OUTER = 0x000
_OFF_FOR_EACH = 0x12C  # 300
_TS_PTR = 0x200  # arbitrary base for synthetic buffers


def _pack_region(values):
    """Independently pack 600 ints -> 300 bytes: even frame = low nibble,
    odd frame = high nibble (the inverse of parse_effect.unpack_region)."""
    out = bytearray(_REGION_BYTES)
    for frame, v in enumerate(values):
        b = frame // 2
        if (frame & 1) == 0:
            out[b] = (out[b] & 0xF0) | (v & 0x0F)
        else:
            out[b] = (out[b] & 0x0F) | ((v & 0x0F) << 4)
    return bytes(out)


def _ramp(seed):
    """A deterministic 600-int curve in the real 2..10 range."""
    return [2 + ((i + seed) % 9) for i in range(600)]


_EXTRACT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "..", "project-assets", "fft-extract", "EFFECT"
)
_E019 = os.path.join(_EXTRACT_DIR, "E019.BIN")


def _synthetic_base() -> bytearray:
    """A blob big enough to hold both 300-byte regions at _TS_PTR, junk-filled so
    any stray write shows up as a diff."""
    size = _TS_PTR + 2 * _REGION_BYTES + 0x40
    return bytearray((i * 7 + 3) & 0xFF for i in range(size))


class SyntheticPrecision(unittest.TestCase):
    def test_both_regions_packed_and_nothing_else_changes(self):
        base = _synthetic_base()
        outer, foreach = _ramp(0), _ramp(4)
        block = {"outer_phases": outer, "for_each": foreach}
        out = wts.patch_time_scale_section(bytes(base), block, _TS_PTR)

        self.assertEqual(
            out[_TS_PTR + _OFF_OUTER:_TS_PTR + _OFF_OUTER + _REGION_BYTES],
            _pack_region(outer))
        self.assertEqual(
            out[_TS_PTR + _OFF_FOR_EACH:_TS_PTR + _OFF_FOR_EACH + _REGION_BYTES],
            _pack_region(foreach))

        changed = [i for i in range(len(base)) if out[i] != base[i]]
        span = set(range(_TS_PTR, _TS_PTR + 2 * _REGION_BYTES))
        self.assertTrue(set(changed).issubset(span),
                        "writes stay inside the two curve regions, strayed: %s"
                        % [c for c in changed if c not in span])

    def test_low_nibble_only_for_out_of_range_value(self):
        # A value with stray high bits packs only its low nibble — never spills.
        base = _synthetic_base()
        vals = [0x1F] + [2] * 599  # frame0 = 0x1F -> low nibble 0xF
        block = {"outer_phases": vals, "for_each": [2] * 600}
        out = wts.patch_time_scale_section(bytes(base), block, _TS_PTR)
        # frame0 low nibble = 0xF, frame1 (=2) high nibble = 0x2 -> byte 0x2F.
        self.assertEqual(out[_TS_PTR + _OFF_OUTER], 0x2F)


@unittest.skipUnless(os.path.exists(_E019), "E019 ROM extract not present")
class RealE019RoundTrip(unittest.TestCase):
    def _block_and_ptr(self):
        data = open(_E019, "rb").read()
        header = pe.parse_header(data)
        ptr = header["time_scale_ptr"]
        self.assertNotEqual(ptr, 0, "E019 carries a live time-scale section")
        ts = pe.parse_time_scale(data, ptr, header["effect_flags_ptr"])
        return data, ptr, ts

    def test_unedited_reserialize_is_byte_identical(self):
        data, ptr, ts = self._block_and_ptr()
        out = wts.patch_time_scale_section(data, ts, ptr)
        self.assertEqual(out, data,
                         "re-serializing the unedited curves round-trips byte-exact")

    def test_edit_one_frame_touches_one_byte(self):
        data, ptr, ts = self._block_and_ptr()
        # Bump outer_phases frame 0 (even -> low nibble of byte ptr+0) from its
        # value to a distinct in-range value.
        old = ts["outer_phases"][0]
        new = 9 if old != 9 else 8
        ts["outer_phases"][0] = new
        out = wts.patch_time_scale_section(data, ts, ptr)
        changed = [i for i in range(len(data)) if out[i] != data[i]]
        self.assertEqual(changed, [ptr],
                         "editing one even frame touches only its packing byte")
        # And it parses back to the edited value.
        rt = pe.parse_time_scale(out, ptr, pe.parse_header(out)["effect_flags_ptr"])
        self.assertEqual(rt["outer_phases"][0], new)
        self.assertEqual(rt["outer_phases"][1], ts["outer_phases"][1])


if __name__ == "__main__":
    unittest.main()
