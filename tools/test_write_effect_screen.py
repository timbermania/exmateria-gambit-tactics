"""Unit tests for the byte-exact SCREEN-section writer (#255 slice 5).

`write_effect_screen.patch_screen_section` is the inverse of
`parse_effect.parse_all_screen_keyframes`: it takes the base `E###.BIN` bytes,
the parsed (possibly edited) `screen` block, and the header's
`timeline_section_ptr`, and returns a NEW byte buffer in which the three screen
colour channels (for_each / phase1 / phase2) are re-serialized from their
authoritative `raw` sub-blocks (#254 decision 2). Every byte outside the
written screen fields is preserved verbatim (#254 decision 4 — partial patch).

Expected values come from an independent source of truth — the literal ROM byte
offsets recomputed here, and byte-level diffs against the source buffer — NOT
from the writer's own computation.

Run from tools/:
    uv run python -m unittest test_write_effect_screen
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_screen as wes
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


# Screen-channel field offsets relative to a channel base (an independent copy
# of the ROM layout, mirroring parse_screen_channel; see slice-4 guard).
_OFF_TIME = 0x00     # + i*2, signed 16-bit
_OFF_START = 0x42    # + i*3, u8 R/G/B
_OFF_END = 0xA5      # + i*3, u8 R/G/B
_OFF_CTRL = 0x108    # + i,   u8
_OFF_MAX_KF = 298    # s16 at end of a phase1/phase2 channel

# Per-context channel base math (mirrors parse_all_screen_keyframes).
_FOR_EACH_DATA = 0x057E   # relative to timeline_ptr + 8
_FOR_EACH_MAXKF = 0x06A8  # relative to timeline_ptr + 8
_PHASE1_DATA = 0x1036     # relative to timeline_ptr
_PHASE2_DATA = 0x13BA     # relative to timeline_ptr

_TIMELINE_PTR = 0x100


def _synthetic_base() -> bytearray:
    """A base buffer big enough for all three channels, filled with a
    deterministic non-trivial pattern so untouched regions are verifiable."""
    size = _TIMELINE_PTR + _PHASE2_DATA + 300 + 64
    buf = bytearray((i * 7 + 3) & 0xFF for i in range(size))
    return buf


def _diff_indices(a: bytes, b: bytes) -> list:
    assert len(a) == len(b)
    return [i for i in range(len(a)) if a[i] != b[i]]


class ScreenWriterRoundTrip(unittest.TestCase):
    def test_unchanged_roundtrip_is_byte_identical(self):
        """parse -> patch (no edit) reproduces the source buffer exactly."""
        base = bytes(_synthetic_base())
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)
        out = wes.patch_screen_section(base, screen, _TIMELINE_PTR)
        self.assertEqual(out, base)

    def test_patch_does_not_mutate_input(self):
        base_ba = _synthetic_base()
        base_snapshot = bytes(base_ba)
        screen = pe.parse_all_screen_keyframes(bytes(base_ba), _TIMELINE_PTR)
        wes.patch_screen_section(bytes(base_ba), screen, _TIMELINE_PTR)
        self.assertEqual(bytes(base_ba), base_snapshot)

    def test_single_u8_edit_touches_exactly_one_byte(self):
        """Editing one raw colour byte changes exactly that ROM byte."""
        base = bytes(_synthetic_base())
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)

        i = 2  # keyframe index, to exercise the stride
        channel = _TIMELINE_PTR + 8 + _FOR_EACH_DATA
        target = channel + _OFF_START + i * 3 + 1  # start_g of keyframe i
        new_val = base[target] ^ 0xFF

        screen["for_each"]["keyframes"][i]["raw"]["start_g"] = new_val
        out = wes.patch_screen_section(base, screen, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_val)
        # Re-parse confirms the round-trip through the raw block.
        reparsed = pe.parse_all_screen_keyframes(out, _TIMELINE_PTR)
        self.assertEqual(
            reparsed["for_each"]["keyframes"][i]["raw"]["start_g"], new_val
        )

    def test_time_value_s16_edit_touches_exactly_two_bytes(self):
        """time_value is a signed 16-bit field — an edit writes 2 LE bytes."""
        base = bytes(_synthetic_base())
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)

        i = 0
        channel = _TIMELINE_PTR + _PHASE1_DATA
        target = channel + _OFF_TIME + i * 2
        orig_u16 = struct.unpack_from("<H", base, target)[0]
        new_u16 = orig_u16 ^ 0xFFFF  # both bytes differ
        new_s16 = struct.unpack("<h", struct.pack("<H", new_u16))[0]

        screen["phase1"]["keyframes"][i]["raw"]["time_value"] = new_s16
        out = wes.patch_screen_section(base, screen, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target, target + 1])
        self.assertEqual(struct.unpack_from("<h", out, target)[0], new_s16)

    def test_max_keyframe_edit_writes_explicit_foreach_offset(self):
        """for_each max_keyframe lives at its own offset, not data+298."""
        base = bytes(_synthetic_base())
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)

        target = _TIMELINE_PTR + 8 + _FOR_EACH_MAXKF
        orig_u16 = struct.unpack_from("<H", base, target)[0]
        new_u16 = orig_u16 ^ 0xFFFF
        new_s16 = struct.unpack("<h", struct.pack("<H", new_u16))[0]

        screen["for_each"]["max_keyframe"] = new_s16
        out = wes.patch_screen_section(base, screen, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target, target + 1])

    def test_max_keyframe_edit_writes_phase_tail_offset(self):
        """phase1/phase2 max_keyframe lives at channel data + 298."""
        base = bytes(_synthetic_base())
        screen = pe.parse_all_screen_keyframes(base, _TIMELINE_PTR)

        target = _TIMELINE_PTR + _PHASE2_DATA + _OFF_MAX_KF
        orig_u16 = struct.unpack_from("<H", base, target)[0]
        new_u16 = orig_u16 ^ 0xFFFF
        new_s16 = struct.unpack("<h", struct.pack("<H", new_u16))[0]

        screen["phase2"]["max_keyframe"] = new_s16
        out = wes.patch_screen_section(base, screen, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target, target + 1])


_E015 = str(_effect_dir() / "E015.BIN")


class ScreenWriterRealBin(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(_E015), "E015.BIN not available")
    def test_real_e015_unchanged_roundtrip_is_byte_identical(self):
        """On a real proven screen effect (Holy/E015), an unedited
        parse -> patch reproduces the whole file byte-for-byte, proving both
        the screen section round-trips and untouched sections stay verbatim."""
        with open(_E015, "rb") as f:
            base = f.read()
        header = pe.parse_header(base)
        timeline_ptr = header["timeline_section_ptr"]
        screen = pe.parse_all_screen_keyframes(base, timeline_ptr)
        out = wes.patch_screen_section(base, screen, timeline_ptr)
        self.assertEqual(out, base)


_E001 = str(_effect_dir() / "E001.BIN")


def _flatten_screen(screen: dict) -> dict:
    """The game's write-back shape: flat keyframe fields only, NO `raw` block —
    so the CLI must rebuild `raw` from the flat bytes (start_r == the raw byte)."""
    out = {}
    for ctx, c in screen.items():
        kfs = []
        for kf in c["keyframes"]:
            k = dict(kf)
            k.pop("raw", None)
            kfs.append(k)
        out[ctx] = {"context": c.get("context", ctx),
                    "max_keyframe": c["max_keyframe"], "keyframes": kfs}
    return out


class ScreenWriterCLI(unittest.TestCase):
    """The `json -> bin` CLI (`write_effect_screen.main`): reads the base BIN +
    a flat screen.json + header.json (timeline_section_ptr) and writes a patched
    BIN. This is the second half of the game->json->bin save loop."""

    @unittest.skipUnless(os.path.exists(_E001), "E001.BIN not available")
    def test_cli_unedited_flat_json_roundtrip_is_byte_identical(self):
        """An unedited flat screen.json re-packed onto the real base reproduces
        E001.BIN byte-for-byte — the byte-perfect round-trip at the CLI boundary."""
        import json
        import tempfile
        from pathlib import Path

        base = Path(_E001).read_bytes()
        tptr = pe.parse_header(base)["timeline_section_ptr"]
        flat = _flatten_screen(pe.parse_all_screen_keyframes(base, tptr))
        with tempfile.TemporaryDirectory() as d:
            sj = Path(d) / "screen.json"; sj.write_text(json.dumps(flat))
            hj = Path(d) / "header.json"
            hj.write_text(json.dumps({"header": {"timeline_section_ptr": tptr}}))
            out = Path(d) / "out.bin"
            rc = wes.main([str(_E001), str(sj), str(hj), str(out)])
            self.assertEqual(rc, 0)
            self.assertEqual(out.read_bytes(), base)

    @unittest.skipUnless(os.path.exists(_E001), "E001.BIN not available")
    def test_cli_edited_start_r_changes_only_that_byte(self):
        """Editing for_each kf0's start_r in the flat screen.json changes exactly
        one BIN byte — at the independently-computed for_each start-R offset."""
        import json
        import tempfile
        from pathlib import Path

        base = Path(_E001).read_bytes()
        tptr = pe.parse_header(base)["timeline_section_ptr"]
        flat = _flatten_screen(pe.parse_all_screen_keyframes(base, tptr))
        orig_r = flat["for_each"]["keyframes"][0]["start_r"]
        new_r = (orig_r + 7) & 0xFF
        flat["for_each"]["keyframes"][0]["start_r"] = new_r
        with tempfile.TemporaryDirectory() as d:
            sj = Path(d) / "screen.json"; sj.write_text(json.dumps(flat))
            hj = Path(d) / "header.json"
            hj.write_text(json.dumps({"header": {"timeline_section_ptr": tptr}}))
            out = Path(d) / "out.bin"
            wes.main([str(_E001), str(sj), str(hj), str(out)])
            ob = out.read_bytes()
        expected_off = (tptr + 8) + _FOR_EACH_DATA + _OFF_START  # kf0 start_r
        self.assertEqual(_diff_indices(base, ob), [expected_off])
        self.assertEqual(ob[expected_off], new_r)


if __name__ == "__main__":
    unittest.main()
