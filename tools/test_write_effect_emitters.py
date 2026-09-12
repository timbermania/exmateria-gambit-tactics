"""Unit tests for the byte-exact EMITTER-block writer (ADR-0089, slice 4).

`write_effect_emitters.patch_emitters_section` is the inverse of
`parse_effect.parse_all_emitters`: given the base `E###.BIN` bytes, the parsed
(possibly edited) emitter list, and the header's `effect_data_ptr`, it returns a
NEW buffer in which each 196-byte emitter record's KNOWN fields are re-serialized
from their raw values. Every byte the parser does not surface — unknown_12/13,
reserved 0x4D/0x50-0x53 halves, the 0x11 high nibble, reserved_C2/C3 — is
preserved verbatim (a partial patch, mirroring write_effect_palette). A dict key
absent from an emitter dict leaves its bytes untouched.

Expected offsets are an independent copy of the master_parser 196-byte layout
recomputed here, NOT the writer's own tables.

Run from tools/:
    python3 -m unittest test_write_effect_emitters
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_emitters as wee
import effect_writer_registry as ewr
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


_EFFECT_DATA_PTR = 0x40
_REC = pe.EMITTER_SIZE            # 196
_HDR = pe.PARTICLE_HEADER_SIZE    # 20


def _emitter_offset(index: int) -> int:
    """Independent record math: effect_data_ptr + particle header + index stride."""
    return _EFFECT_DATA_PTR + _HDR + index * _REC


def _base_buffer(n_emitters: int = 2) -> bytes:
    """A synthetic effect blob: junk preamble + particle header + N emitter records
    filled with a deterministic non-trivial byte pattern (so nibble halves and
    signed values are all exercised)."""
    size = _EFFECT_DATA_PTR + _HDR + n_emitters * _REC + 32
    return bytes((i * 7 + 3) & 0xFF for i in range(size))


class UnchangedRoundTrip(unittest.TestCase):
    def test_unedited_parse_patch_is_byte_identical(self):
        """parse_all_emitters -> patch (no edits) reproduces the base verbatim."""
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        self.assertEqual(out, base)

    def test_absent_keys_touch_nothing(self):
        """A sparse emitter dict (partial edit set) only writes the present keys."""
        base = _base_buffer()
        out = wee.patch_emitters_section(
            base, [{"index": 1, "anim_index": 0xAB}], _EFFECT_DATA_PTR)
        want = bytearray(base)
        want[_emitter_offset(1) + 0x01] = 0xAB
        self.assertEqual(out, bytes(want))


class SingleFieldDiffs(unittest.TestCase):
    """Each edit lands at its independently-computed offset and nowhere else."""

    def _diff(self, base: bytes, out: bytes):
        return [i for i in range(len(base)) if base[i] != out[i]]

    def test_weight_min_start_is_one_s16(self):
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[0]["weight"]["min_start"] = -1234
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        off = _emitter_offset(0) + 0x54
        self.assertEqual(set(self._diff(base, out)) - {off, off + 1}, set())
        self.assertEqual(struct.unpack_from("<h", out, off)[0], -1234)

    def test_curve_nibble_edit_diffs_exactly_one_byte(self):
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        raw = list(emitters[0]["curve_indices_raw"])
        raw[5] = (raw[5] & 0xF0) | 0x03    # lifetime nibble -> curve raw 3
        emitters[0]["curve_indices_raw"] = raw
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        self.assertEqual(self._diff(base, out), [_emitter_offset(0) + 0x08 + 5])

    def test_color_curve_patch_preserves_0x11_high_nibble(self):
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[0]["color_curves"] = dict(emitters[0]["color_curves"], b=0x0A)
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        off = _emitter_offset(0) + 0x11
        self.assertEqual(out[off] & 0x0F, 0x0A)
        self.assertEqual(out[off] & 0xF0, base[off] & 0xF0)
        self.assertEqual(self._diff(base, out), [off] if out[off] != base[off] else [])

    def test_child_wiring_byte(self):
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[1]["child_emitter_on_death"] = 0
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        self.assertEqual(self._diff(base, out), [_emitter_offset(1) + 0xC0])

    def test_interleaved_accel_component(self):
        """acceleration max_start Y lives at base+0x64 + 4*1 + 2 = +0x6A (the
        min/max interleave master_parser documents)."""
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[0]["raw"]["accel_max_start"] = list(emitters[0]["raw"]["accel_max_start"])
        emitters[0]["raw"]["accel_max_start"][1] = -77
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        off = _emitter_offset(0) + 0x6A
        self.assertEqual(set(self._diff(base, out)) - {off, off + 1}, set())
        self.assertEqual(struct.unpack_from("<h", out, off)[0], -77)

    def test_lifetime_u16(self):
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[0]["lifetime"]["max_end"] = 65535
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        off = _emitter_offset(0) + 0x9A
        self.assertEqual(struct.unpack_from("<H", out, off)[0], 65535)

    def test_lifetime_minus_one_writes_0xffff(self):
        """The -1 'dies with its animation' sentinel (how older emitters.json
        parses 0xFFFF) must land as 0xFFFF — signedness is interpretation, the
        bytes are the bytes."""
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[0]["lifetime"]["min_start"] = -1
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        off = _emitter_offset(0) + 0x94
        self.assertEqual(struct.unpack_from("<H", out, off)[0], 0xFFFF)

    def test_callback_param_a8_s16(self):
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[0]["callback_params"]["param_A8"] = -100
        out = wee.patch_emitters_section(base, emitters, _EFFECT_DATA_PTR)
        off = _emitter_offset(0) + 0xA8
        self.assertEqual(struct.unpack_from("<h", out, off)[0], -100)


class RegistryEntry(unittest.TestCase):
    def test_emitters_section_is_registered(self):
        self.assertIn("emitters", ewr.registered_sections())

    def test_patch_all_routes_emitters(self):
        base = _base_buffer()
        emitters = pe.parse_all_emitters(base, _EFFECT_DATA_PTR, 2)
        emitters[0]["anim_param"] = 0x5A
        header = {"effect_data_ptr": _EFFECT_DATA_PTR}
        out = ewr.patch_all(base, {"emitters": emitters}, header)
        self.assertEqual(out[_emitter_offset(0) + 0x04], 0x5A)


_E019 = str(_effect_dir() / "E019.BIN")


class RealE019(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_unchanged_roundtrip_is_byte_identical(self):
        """On the real Fire-4 sample (the emitter-rich tracker baseline), an
        unedited parse -> patch reproduces every one of the file's bytes."""
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base, 0)
        ph = pe.parse_particle_header(base, header["effect_data_ptr"])
        emitters = pe.parse_all_emitters(base, header["effect_data_ptr"], ph["emitter_count"])
        out = wee.patch_emitters_section(base, emitters, header["effect_data_ptr"])
        self.assertEqual(out, base)


if __name__ == "__main__":
    unittest.main()
