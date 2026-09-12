"""Unit tests for the per-section serializer registry (F1 #264).

`effect_writer_registry` generalizes the byte-exact SCREEN writer
(`write_effect_screen.patch_screen_section`) into a REGISTRY: each subsystem
registers `serialize_<section>(buf, header, block)` that partial-patches ITS
section's bytes into a shared `bytearray` from an (edited) parsed block, leaving
every other byte verbatim. The save loop `patch_all(base, sections, header)`
runs every registered serializer whose section is present in the edit set and
returns a NEW buffer. `parse_effect` offsets stay the single geometry source
(carried in the parsed `header`).

Expected values come from independent sources — the proven direct screen writer
(`write_effect_screen`), literal recomputed ROM offsets, and byte-level diffs —
NOT the registry's own math.

Run from tools/:
    uv run python -m unittest test_effect_writer_registry
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_screen as wes
import effect_writer_registry as reg
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


_TIMELINE_PTR = 0x100
_FOR_EACH_DATA = 0x057E   # relative to timeline_ptr + 8 (independent copy)
_OFF_START = 0x42         # + i*3 within a screen channel


def _synthetic_base() -> bytes:
    """A base buffer big enough for all three screen channels, deterministically
    patterned so untouched regions are verifiable (mirrors the screen writer's)."""
    size = _TIMELINE_PTR + 0x13BA + 300 + 64
    return bytes((i * 7 + 3) & 0xFF for i in range(size))


def _synthetic_header() -> dict:
    """A minimal parsed header carrying just the geometry the screen serializer
    needs. patch_all passes this verbatim to each serializer."""
    return {"timeline_section_ptr": _TIMELINE_PTR}


def _diff_indices(a: bytes, b: bytes) -> list:
    assert len(a) == len(b)
    return [i for i in range(len(a)) if a[i] != b[i]]


class RegistryContract(unittest.TestCase):
    def test_screen_is_registered_out_of_the_box(self):
        self.assertIn("screen", reg.registered_sections())
        self.assertTrue(callable(reg.serializer_for("screen")))

    def test_time_scale_is_registered(self):
        self.assertIn("time_scale", reg.registered_sections())
        self.assertTrue(callable(reg.serializer_for("time_scale")))

    def test_frames_is_registered(self):
        self.assertIn("frames", reg.registered_sections())
        self.assertTrue(callable(reg.serializer_for("frames")))

    def test_animation_is_registered(self):
        self.assertIn("animation", reg.registered_sections())
        self.assertTrue(callable(reg.serializer_for("animation")))

    def test_empty_edit_set_is_identity(self):
        base = _synthetic_base()
        out = reg.patch_all(base, {}, _synthetic_header())
        self.assertEqual(out, base)

    def test_patch_all_does_not_mutate_input(self):
        base = _synthetic_base()
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)
        snapshot = bytes(base)
        reg.patch_all(base, {"screen": screen}, _synthetic_header())
        self.assertEqual(base, snapshot)

    def test_unregistered_section_raises(self):
        base = _synthetic_base()
        with self.assertRaises(KeyError):
            reg.patch_all(base, {"nope": {}}, _synthetic_header())

    def test_returns_new_buffer_not_alias(self):
        base = _synthetic_base()
        out = reg.patch_all(base, {}, _synthetic_header())
        self.assertIsNot(out, base)
        self.assertIsInstance(out, (bytes, bytearray))


class ScreenViaRegistry(unittest.TestCase):
    """The registry's screen path must be byte-for-byte identical to the proven
    direct writer — same geometry, same partial-patch semantics."""

    def test_registry_screen_matches_direct_writer_unedited(self):
        base = _synthetic_base()
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)
        via_reg = reg.patch_all(base, {"screen": screen}, _synthetic_header())
        direct = wes.patch_screen_section(base, screen, _TIMELINE_PTR)
        self.assertEqual(via_reg, direct)
        self.assertEqual(via_reg, base)  # no edit → identity

    def test_registry_screen_matches_direct_writer_edited(self):
        base = _synthetic_base()
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)
        i = 2
        chan = _TIMELINE_PTR + 8 + _FOR_EACH_DATA
        target = chan + _OFF_START + i * 3 + 1  # start_g of kf i
        screen["for_each"]["keyframes"][i]["raw"]["start_g"] = base[target] ^ 0xFF

        via_reg = reg.patch_all(base, {"screen": screen}, _synthetic_header())
        direct = wes.patch_screen_section(base, screen, _TIMELINE_PTR)
        self.assertEqual(via_reg, direct)
        self.assertEqual(_diff_indices(base, via_reg), [target])


class TimeScaleViaRegistry(unittest.TestCase):
    """The registry's time_scale path must be byte-for-byte identical to the
    proven direct writer (write_effect_time_scale)."""

    _TS_PTR = 0x100

    def _base(self):
        size = self._TS_PTR + 600 + 64
        return bytes((i * 7 + 3) & 0xFF for i in range(size))

    def _header(self):
        return {"time_scale_ptr": self._TS_PTR}

    def test_registry_time_scale_matches_direct_writer(self):
        import write_effect_time_scale as wts

        base = self._base()
        block = {
            "outer_phases": [2 + (i % 9) for i in range(600)],
            "for_each": [2 + ((i + 4) % 9) for i in range(600)],
        }
        via_reg = reg.patch_all(base, {"time_scale": block}, self._header())
        direct = wts.patch_time_scale_section(base, block, self._TS_PTR)
        self.assertEqual(via_reg, direct)
        # Writes stay inside the two 300-byte regions.
        span = set(range(self._TS_PTR, self._TS_PTR + 600))
        self.assertTrue(set(_diff_indices(base, via_reg)).issubset(span))


class MultiSectionSaveLoop(unittest.TestCase):
    """The save loop must run EVERY registered serializer present in the edit set,
    independently, over ONE shared buffer — proven with a second dummy serializer
    (registered into a LOCAL registry copy so the global stays clean)."""

    def test_two_serializers_both_patch_independently(self):
        base = _synthetic_base()
        header = dict(_synthetic_header())
        header["dummy_ptr"] = 0x40  # geometry for the dummy section

        def serialize_dummy(buf, hdr, block):
            buf[hdr["dummy_ptr"]] = block["byte"] & 0xFF

        local = dict(reg.REGISTRY)
        local["dummy"] = serialize_dummy

        # Edit both a screen byte and the dummy byte.
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)
        i = 0
        chan = _TIMELINE_PTR + 8 + _FOR_EACH_DATA
        s_target = chan + _OFF_START + i * 3 + 0  # start_r of kf 0
        screen["for_each"]["keyframes"][i]["raw"]["start_r"] = base[s_target] ^ 0xFF
        new_dummy = base[header["dummy_ptr"]] ^ 0xFF

        out = reg.patch_all(
            base,
            {"screen": screen, "dummy": {"byte": new_dummy}},
            header,
            registry=local,
        )
        self.assertEqual(
            _diff_indices(base, out), sorted([s_target, header["dummy_ptr"]])
        )
        self.assertEqual(out[header["dummy_ptr"]], new_dummy)

    def test_register_decorator_and_unregister(self):
        @reg.register("temp_probe")
        def _serialize_temp(buf, hdr, block):
            buf[0] = 0xEE

        try:
            self.assertIn("temp_probe", reg.registered_sections())
            out = reg.patch_all(_synthetic_base(), {"temp_probe": {}}, _synthetic_header())
            self.assertEqual(out[0], 0xEE)
        finally:
            reg.unregister("temp_probe")
        self.assertNotIn("temp_probe", reg.registered_sections())


_E015 = str(_effect_dir() / "E015.BIN")
_E001 = str(_effect_dir() / "E001.BIN")


class RealBinRoundTrip(unittest.TestCase):
    """On real proven screen effects, parse -> patch_all (no edit) reproduces the
    whole file byte-for-byte — the registry preserves every untouched section."""

    @unittest.skipUnless(os.path.exists(_E015), "E015.BIN not available")
    def test_e015_screen_roundtrip_byte_identical(self):
        base = __import__("pathlib").Path(_E015).read_bytes()
        header = pe.parse_header(base)
        screen = pe.parse_all_screen_keyframes(base, header["timeline_section_ptr"])
        out = reg.patch_all(base, {"screen": screen}, header)
        self.assertEqual(out, base)

    @unittest.skipUnless(os.path.exists(_E001), "E001.BIN not available")
    def test_e001_screen_roundtrip_byte_identical(self):
        base = __import__("pathlib").Path(_E001).read_bytes()
        header = pe.parse_header(base)
        screen = pe.parse_all_screen_keyframes(base, header["timeline_section_ptr"])
        out = reg.patch_all(base, {"screen": screen}, header)
        self.assertEqual(out, base)


if __name__ == "__main__":
    unittest.main()
