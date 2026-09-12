"""Unit tests for the byte-exact PALETTE-section writer (Subsystem 1, #266).

`write_effect_palette.patch_palette_section` is the inverse of
`parse_effect.parse_all_palette_keyframes`: it takes the base `E###.BIN` bytes,
the parsed (possibly edited) `palette` block (3 phases x 3 channels), and the
header's `timeline_section_ptr`, and returns a NEW byte buffer in which the nine
palette/field-tint channels (for_each / phase1 / phase2 x affected_units /
caster / target) are re-serialized from their raw keyframe fields. Every byte
outside the written palette fields is preserved verbatim (partial patch).

Unlike screen, a palette keyframe has NO `raw` sub-block — its flat fields
(`time_value`, `rgb` list, `ctrl`) ARE the raw bytes on disk, so the writer
reads them directly (mirroring parse_palette_channel).

Expected values come from an independent copy of the ROM layout recomputed here,
NOT from the writer's own computation.

Run from tools/:
    python3 -m unittest test_write_effect_palette
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_palette as wep
import effect_writer_registry as ewr
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


# Palette-channel field offsets relative to a channel base (an independent copy
# of the ROM layout, mirroring parse_palette_channel).
_OFF_TIME = 0x00     # + i*2, signed 16-bit
_OFF_RGB = 0x42      # + i*3, u8 R/G/B
_OFF_CTRL = 0xA5     # + i,   u8
_OFF_MAXKF = 198     # s16 at end of a channel (base + PALETTE_TRACK_SIZE)

_MAX_KF = pe.MAX_PALETTE_KEYFRAMES  # 33

_TIMELINE_PTR = 0x100


def _channel_base(timeline_ptr: int, context: str, channel_name: str) -> int:
    """Independent copy of parse_all_palette_keyframes' per-channel base math."""
    base = timeline_ptr + 8 if context == "for_each" else timeline_ptr
    return base + pe.PALETTE_TRACK_OFFSETS[context][channel_name]


def _synthetic_base() -> bytearray:
    """A base buffer big enough for all nine channels, filled with a
    deterministic non-trivial pattern so untouched regions are verifiable. Each
    channel's max_keyframe word is forced in-range (the parser clamps an
    out-of-range max_keyframe to 0, which would defeat an unchanged round-trip)."""
    # phase2/target is the highest-addressed channel.
    hi = _channel_base(_TIMELINE_PTR, "phase2", "target")
    size = hi + pe.PALETTE_TRACK_SIZE + 2 + 64
    buf = bytearray((i * 7 + 3) & 0xFF for i in range(size))
    for context, offsets in pe.PALETTE_TRACK_OFFSETS.items():
        for channel_name in offsets:
            cb = _channel_base(_TIMELINE_PTR, context, channel_name)
            struct.pack_into("<h", buf, cb + _OFF_MAXKF, 5)  # in-range
    return buf


def _diff_indices(a: bytes, b: bytes) -> list:
    assert len(a) == len(b)
    return [i for i in range(len(a)) if a[i] != b[i]]


class PaletteWriterRoundTrip(unittest.TestCase):
    def test_unchanged_roundtrip_is_byte_identical(self):
        """parse -> patch (no edit) reproduces the source buffer exactly."""
        base = bytes(_synthetic_base())
        palette = pe.parse_all_palette_keyframes(base, _TIMELINE_PTR)
        out = wep.patch_palette_section(base, palette, _TIMELINE_PTR)
        self.assertEqual(out, base)

    def test_patch_does_not_mutate_input(self):
        base_ba = _synthetic_base()
        base_snapshot = bytes(base_ba)
        palette = pe.parse_all_palette_keyframes(bytes(base_ba), _TIMELINE_PTR)
        wep.patch_palette_section(bytes(base_ba), palette, _TIMELINE_PTR)
        self.assertEqual(bytes(base_ba), base_snapshot)

    def test_single_rgb_u8_edit_touches_exactly_one_byte(self):
        """Editing one raw RGB byte changes exactly that ROM byte."""
        base = bytes(_synthetic_base())
        palette = pe.parse_all_palette_keyframes(base, _TIMELINE_PTR)

        i = 2  # keyframe index, to exercise the stride
        cb = _channel_base(_TIMELINE_PTR, "phase1", "affected_units")
        target = cb + _OFF_RGB + i * 3 + 1  # G of keyframe i
        new_val = base[target] ^ 0xFF

        palette["phase1"]["affected_units"]["keyframes"][i]["rgb"][1] = new_val
        out = wep.patch_palette_section(base, palette, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_val)
        # Re-parse confirms the round-trip.
        reparsed = pe.parse_all_palette_keyframes(out, _TIMELINE_PTR)
        self.assertEqual(
            reparsed["phase1"]["affected_units"]["keyframes"][i]["rgb"][1], new_val
        )

    def test_ctrl_u8_edit_touches_exactly_one_byte(self):
        """The ctrl byte (enabled bit-7 + blend_mode bits 0-6) is a single u8."""
        base = bytes(_synthetic_base())
        palette = pe.parse_all_palette_keyframes(base, _TIMELINE_PTR)

        i = 4
        cb = _channel_base(_TIMELINE_PTR, "for_each", "caster")
        target = cb + _OFF_CTRL + i
        new_val = base[target] ^ 0x80  # flip the enabled bit

        palette["for_each"]["caster"]["keyframes"][i]["ctrl"] = new_val
        out = wep.patch_palette_section(base, palette, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_val)

    def test_time_value_s16_edit_touches_exactly_two_bytes(self):
        """time_value is a signed 16-bit field — an edit writes 2 LE bytes."""
        base = bytes(_synthetic_base())
        palette = pe.parse_all_palette_keyframes(base, _TIMELINE_PTR)

        i = 0
        cb = _channel_base(_TIMELINE_PTR, "phase2", "target")
        target = cb + _OFF_TIME + i * 2
        orig_u16 = struct.unpack_from("<H", base, target)[0]
        new_u16 = orig_u16 ^ 0xFFFF
        new_s16 = struct.unpack("<h", struct.pack("<H", new_u16))[0]

        palette["phase2"]["target"]["keyframes"][i]["time_value"] = new_s16
        out = wep.patch_palette_section(base, palette, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target, target + 1])
        self.assertEqual(struct.unpack_from("<h", out, target)[0], new_s16)

    def test_max_keyframe_edit_writes_channel_tail_offset(self):
        """max_keyframe lives at channel base + PALETTE_TRACK_SIZE (198)."""
        base = bytes(_synthetic_base())
        palette = pe.parse_all_palette_keyframes(base, _TIMELINE_PTR)

        cb = _channel_base(_TIMELINE_PTR, "phase1", "target")
        target = cb + _OFF_MAXKF
        orig_u16 = struct.unpack_from("<H", base, target)[0]  # seeded 5
        new_u16 = orig_u16 ^ 0xFFFF  # both LE bytes differ
        new_s16 = struct.unpack("<h", struct.pack("<H", new_u16))[0]

        palette["phase1"]["target"]["max_keyframe"] = new_s16
        out = wep.patch_palette_section(base, palette, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target, target + 1])
        self.assertEqual(struct.unpack_from("<h", out, target)[0], new_s16)


_E019 = str(_effect_dir() / "E019.BIN")


class PaletteWriterRealBin(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_unchanged_roundtrip_is_byte_identical(self):
        """On the real Fire-4 sample (E019), an unedited parse -> patch reproduces
        the whole file byte-for-byte, proving both the palette section round-trips
        and untouched sections stay verbatim."""
        with open(_E019, "rb") as f:
            base = f.read()
        timeline_ptr = pe.parse_header(base)["timeline_section_ptr"]
        palette = pe.parse_all_palette_keyframes(base, timeline_ptr)
        out = wep.patch_palette_section(base, palette, timeline_ptr)
        self.assertEqual(out, base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_edited_rgb_changes_only_that_byte(self):
        """Editing one enabled channel's kf0 R on the real base changes exactly
        one BIN byte at the independently-computed offset."""
        with open(_E019, "rb") as f:
            base = f.read()
        timeline_ptr = pe.parse_header(base)["timeline_section_ptr"]
        palette = pe.parse_all_palette_keyframes(base, timeline_ptr)
        cb = _channel_base(timeline_ptr, "phase1", "affected_units")
        target = cb + _OFF_RGB  # kf0 R
        orig = base[target]
        new_r = (orig + 7) & 0xFF
        palette["phase1"]["affected_units"]["keyframes"][0]["rgb"][0] = new_r
        out = wep.patch_palette_section(base, palette, timeline_ptr)
        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_r)


class PaletteThroughRegistry(unittest.TestCase):
    """The palette serializer plugged into the F1 per-section registry (#264):
    patch_all routes the "palette" section through serialize_palette."""

    def test_palette_registered(self):
        self.assertIn("palette", ewr.registered_sections())

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_registry_unchanged_roundtrip_is_byte_identical(self):
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base)
        timeline_ptr = header["timeline_section_ptr"]
        palette = pe.parse_all_palette_keyframes(base, timeline_ptr)
        out = ewr.patch_all(base, {"palette": palette}, header)
        self.assertEqual(out, base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_registry_screen_and_palette_together_roundtrip(self):
        """Screen + palette patched over ONE buffer both round-trip — the
        sections don't overlap, so a multi-section save stays byte-exact."""
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base)
        timeline_ptr = header["timeline_section_ptr"]
        screen = pe.parse_all_screen_keyframes(base, timeline_ptr)
        palette = pe.parse_all_palette_keyframes(base, timeline_ptr)
        out = ewr.patch_all(base, {"screen": screen, "palette": palette}, header)
        self.assertEqual(out, base)


class PaletteWriterCLI(unittest.TestCase):
    """The write_effect_palette.py CLI (ADR-0087 palette Save seam) the Studio's
    EffectPaletteSaver shells out to: base.bin + palette.json + header.json -> out.bin,
    reading the timeline pointer from header.timeline_section_ptr."""

    def test_cli_applies_an_edit_matching_the_library_call(self):
        import json
        import tempfile

        base = bytes(_synthetic_base())
        palette = pe.parse_all_palette_keyframes(base, _TIMELINE_PTR)
        # Edit one channel's kf0 time_value (a duration change) — the boundary-drag output.
        palette["phase1"]["affected_units"]["keyframes"][0]["time_value"] = 9
        expected = wep.patch_palette_section(base, palette, _TIMELINE_PTR)

        with tempfile.TemporaryDirectory() as d:
            base_p = os.path.join(d, "base.BIN")
            pal_p = os.path.join(d, "pal.json")
            hdr_p = os.path.join(d, "hdr.json")
            out_p = os.path.join(d, "out.BIN")
            with open(base_p, "wb") as f:
                f.write(base)
            with open(pal_p, "w") as f:
                json.dump(palette, f)
            with open(hdr_p, "w") as f:
                json.dump({"header": {"timeline_section_ptr": _TIMELINE_PTR}}, f)

            rc = wep.main([base_p, pal_p, hdr_p, out_p])
            self.assertEqual(rc, 0)
            with open(out_p, "rb") as f:
                got = f.read()
        self.assertEqual(got, expected)


if __name__ == "__main__":
    unittest.main()
