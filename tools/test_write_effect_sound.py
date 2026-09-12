"""Unit tests for the byte-exact SOUND-TIMELINE writer (Subsystem 3, #268).

`write_effect_sound.patch_sound_section` is the inverse of
`parse_effect.parse_sound_keyframes`: it takes the base `E###.BIN` bytes, the
parsed (possibly edited) `sound` block (phase1/phase2/for_each, each a list of 3
channel dicts), and the header's `timeline_section_ptr`, and returns a NEW byte
buffer in which the six outer (30 B) + three for-each (54 B) SFX-trigger channels
are re-serialized from their raw keyframe fields. Every byte outside the written
sound fields is preserved verbatim (a partial patch, mirroring write_effect_
palette).

Only TIER-1 timeline tracks are written; a keyframe's editable fields are
`sound_id` (u8) and `duration_frames` (the s16 time_value). The FEDS opcode
stream (TIER-3) and the SoundContainers (TIER-2) are untouched.

Expected values come from an independent copy of the ROM layout recomputed here,
NOT from the writer's own computation.

Run from tools/:
    python3 -m unittest test_write_effect_sound
"""

from __future__ import annotations

import os
import struct
import unittest

import parse_effect as pe
import write_effect_sound as wesnd
import effect_writer_registry as ewr
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


_TIMELINE_PTR = 0x100

# Independent copy of the per-phase channel bases (mirror parse_sound_keyframes).
# Outer channels (phase1/phase2) are based at timeline_ptr; for_each at +8.
_PHASE_BASES = {
    "phase1": (_TIMELINE_PTR, pe.SOUND_PHASE1_OFFSETS, pe.SOUND_OUTER_KF, pe.SOUND_OUTER_MAXKF_OFF),
    "phase2": (_TIMELINE_PTR, pe.SOUND_PHASE2_OFFSETS, pe.SOUND_OUTER_KF, pe.SOUND_OUTER_MAXKF_OFF),
    "for_each": (_TIMELINE_PTR + 8, pe.SOUND_ANIMATE_OFFSETS, pe.SOUND_FOREACH_KF, pe.SOUND_FOREACH_MAXKF_OFF),
}


def _channel_base(phase: str, ci: int) -> int:
    base, offsets, _kf, _mk = _PHASE_BASES[phase]
    return base + offsets[ci]


def _sid_offset(phase: str, ci: int, i: int) -> int:
    """Byte offset of keyframe i's sound_id (u8): after the time block (KF*2)."""
    _base, _offs, kf, _mk = _PHASE_BASES[phase]
    return _channel_base(phase, ci) + kf * 2 + i


def _time_offset(phase: str, ci: int, i: int) -> int:
    """Byte offset of keyframe i's time_value / duration_frames (s16 LE)."""
    return _channel_base(phase, ci) + i * 2


def _maxkf_offset(phase: str, ci: int) -> int:
    _base, _offs, _kf, mk = _PHASE_BASES[phase]
    return _channel_base(phase, ci) + mk


def _synthetic_base() -> bytearray:
    """A base buffer big enough for all nine sound channels, filled with a
    deterministic non-trivial pattern so untouched regions are verifiable.

    The sound parser reads straight through with NO clamp (unlike palette's
    max_keyframe), so an unchanged round-trip is byte-exact regardless of the
    seeded values."""
    hi = max(
        _channel_base("phase2", 2) + pe.SOUND_OUTER_SIZE,
        _channel_base("for_each", 2) + pe.SOUND_FOREACH_SIZE,
    )
    size = hi + 64
    return bytearray((i * 11 + 5) & 0xFF for i in range(size))


def _diff_indices(a: bytes, b: bytes) -> list:
    assert len(a) == len(b)
    return [i for i in range(len(a)) if a[i] != b[i]]


class SoundWriterRoundTrip(unittest.TestCase):
    def test_unchanged_roundtrip_is_byte_identical(self):
        """parse -> patch (no edit) reproduces the source buffer exactly."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)
        out = wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)
        self.assertEqual(out, base)

    def test_patch_does_not_mutate_input(self):
        base_ba = _synthetic_base()
        base_snapshot = bytes(base_ba)
        sound = pe.parse_sound_keyframes(bytes(base_ba), _TIMELINE_PTR)
        wesnd.patch_sound_section(bytes(base_ba), sound, _TIMELINE_PTR)
        self.assertEqual(bytes(base_ba), base_snapshot)

    def test_single_sound_id_u8_edit_touches_exactly_one_byte(self):
        """Editing one raw sound_id byte changes exactly that ROM byte."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)

        i = 2  # keyframe index, to exercise the stride
        target = _sid_offset("phase1", 1, i)
        new_val = base[target] ^ 0xFF

        sound["phase1"][1]["keyframes"][i]["sound_id"] = new_val
        out = wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_val)
        reparsed = pe.parse_sound_keyframes(out, _TIMELINE_PTR)
        self.assertEqual(reparsed["phase1"][1]["keyframes"][i]["sound_id"], new_val)

    def test_duration_frames_s16_edit_touches_exactly_two_bytes(self):
        """duration_frames is the s16 time_value — an edit writes 2 LE bytes."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)

        i = 3
        target = _time_offset("for_each", 0, i)
        orig_u16 = struct.unpack_from("<H", base, target)[0]
        new_u16 = orig_u16 ^ 0xFFFF
        new_s16 = struct.unpack("<h", struct.pack("<H", new_u16))[0]

        sound["for_each"][0]["keyframes"][i]["duration_frames"] = new_s16
        out = wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target, target + 1])
        self.assertEqual(struct.unpack_from("<h", out, target)[0], new_s16)

    def test_max_keyframe_edit_writes_channel_tail_offset(self):
        """max_keyframe lives at the fixed tail offset (28 outer / 52 for_each)."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)

        target = _maxkf_offset("phase2", 2)
        orig_u16 = struct.unpack_from("<H", base, target)[0]
        new_u16 = orig_u16 ^ 0xFFFF
        new_s16 = struct.unpack("<h", struct.pack("<H", new_u16))[0]

        sound["phase2"][2]["max_keyframe"] = new_s16
        out = wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target, target + 1])
        self.assertEqual(struct.unpack_from("<h", out, target)[0], new_s16)

    def test_anchor_offset_key_is_dropped_byte_identical(self):
        """ADR-0085 anchor_offset is authoring-only metadata with NO ROM counterpart.
        A keyframe carrying it must serialize byte-identically to one without — the
        writer reads only sound_id + duration_frames, so the extra key is dropped and
        the trigger stays a plain early fire on disk (byte-faithful)."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)
        # Inject the authoring-only key on keyframes across phases/channels/bases.
        sound["phase1"][0]["keyframes"][1]["anchor_offset"] = 7
        sound["phase2"][2]["keyframes"][0]["anchor_offset"] = 255
        sound["for_each"][2]["keyframes"][3]["anchor_offset"] = 42
        out = wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)
        self.assertEqual(out, base)

    def test_over_native_keyframe_count_raises_not_truncates(self):
        """The ROM track has a FIXED slot budget (9 outer / 17 for-each). A channel
        carrying MORE keyframes than its native slots must raise — mirroring the
        camera writer's raise-over-cap — never silently drop the extras on disk."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)
        sound["phase1"][0]["keyframes"].append({"duration_frames": 1, "sound_id": 0})
        with self.assertRaises(ValueError):
            wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)

    def test_under_native_keyframe_count_raises_value_error(self):
        """A SHORT keyframes array is equally corrupt (the writer would leave stale
        slot bytes or IndexError mid-write) — refuse it explicitly up front."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)
        sound["for_each"][1]["keyframes"].pop()
        with self.assertRaises(ValueError):
            wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)

    def test_foreach_channel_uses_plus8_base(self):
        """for_each channels are based at timeline_ptr + 8, not timeline_ptr —
        a sound_id edit there lands at the +8-shifted offset."""
        base = bytes(_synthetic_base())
        sound = pe.parse_sound_keyframes(base, _TIMELINE_PTR)

        i = 5
        target = _sid_offset("for_each", 2, i)
        new_val = base[target] ^ 0x5A

        sound["for_each"][2]["keyframes"][i]["sound_id"] = new_val
        out = wesnd.patch_sound_section(base, sound, _TIMELINE_PTR)

        self.assertEqual(_diff_indices(base, out), [target])


_E019 = str(_effect_dir() / "E019.BIN")


class SoundWriterRealBin(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_unchanged_roundtrip_is_byte_identical(self):
        """On the real Fire-4 sample (E019), an unedited parse -> patch reproduces
        the whole file byte-for-byte, proving the sound section round-trips and
        untouched sections stay verbatim."""
        with open(_E019, "rb") as f:
            base = f.read()
        timeline_ptr = pe.parse_header(base)["timeline_section_ptr"]
        sound = pe.parse_sound_keyframes(base, timeline_ptr)
        out = wesnd.patch_sound_section(base, sound, timeline_ptr)
        self.assertEqual(out, base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_edited_sound_id_changes_only_that_byte(self):
        """Editing one fired keyframe's sound_id on the real base changes exactly
        one BIN byte at the independently-computed offset. E019 phase1 ch0 kf1
        fires (sound_id 2)."""
        with open(_E019, "rb") as f:
            base = f.read()
        timeline_ptr = pe.parse_header(base)["timeline_section_ptr"]
        sound = pe.parse_sound_keyframes(base, timeline_ptr)

        _base, offs, kf, _mk = (
            timeline_ptr, pe.SOUND_PHASE1_OFFSETS, pe.SOUND_OUTER_KF, pe.SOUND_OUTER_MAXKF_OFF)
        cb = timeline_ptr + offs[0]
        target = cb + kf * 2 + 1  # kf1 sound_id
        orig = base[target]
        new_sid = (orig + 5) & 0xFF
        sound["phase1"][0]["keyframes"][1]["sound_id"] = new_sid
        out = wesnd.patch_sound_section(base, sound, timeline_ptr)
        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_sid)


    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_anchor_offset_key_is_dropped_byte_identical(self):
        """On the real Fire-4 base, adding anchor_offset to a fired keyframe still
        reproduces the whole file byte-for-byte — the authoring-only key never
        reaches the ROM bytes."""
        with open(_E019, "rb") as f:
            base = f.read()
        timeline_ptr = pe.parse_header(base)["timeline_section_ptr"]
        sound = pe.parse_sound_keyframes(base, timeline_ptr)
        sound["phase1"][0]["keyframes"][1]["anchor_offset"] = 12
        out = wesnd.patch_sound_section(base, sound, timeline_ptr)
        self.assertEqual(out, base)


class SoundThroughRegistry(unittest.TestCase):
    """The sound serializer plugged into the F1 per-section registry (#264):
    patch_all routes the "sound" section through serialize_sound."""

    def test_sound_registered(self):
        self.assertIn("sound", ewr.registered_sections())

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_registry_unchanged_roundtrip_is_byte_identical(self):
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base)
        timeline_ptr = header["timeline_section_ptr"]
        sound = pe.parse_sound_keyframes(base, timeline_ptr)
        out = ewr.patch_all(base, {"sound": sound}, header)
        self.assertEqual(out, base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_registry_screen_palette_sound_together_roundtrip(self):
        """Screen + palette + sound patched over ONE buffer all round-trip — the
        sections don't overlap, so a multi-section save stays byte-exact."""
        with open(_E019, "rb") as f:
            base = f.read()
        header = pe.parse_header(base)
        timeline_ptr = header["timeline_section_ptr"]
        screen = pe.parse_all_screen_keyframes(base, timeline_ptr)
        palette = pe.parse_all_palette_keyframes(base, timeline_ptr)
        sound = pe.parse_sound_keyframes(base, timeline_ptr)
        out = ewr.patch_all(
            base, {"screen": screen, "palette": palette, "sound": sound}, header)
        self.assertEqual(out, base)


if __name__ == "__main__":
    unittest.main()
