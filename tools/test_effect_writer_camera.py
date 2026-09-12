"""Byte-exact round-trip tests for the CAMERA section writer (wayfinder #267).

`write_effect_camera.patch_camera_section` is the inverse of
`parse_effect.parse_camera_keyframes`: given base `E###.BIN` bytes, a parsed
(possibly edited) camera block, and the header's `timeline_section_ptr`, it
re-serializes the three camera SoA tables (for_each / phase1 / phase2) and leaves
every other byte verbatim (partial patch — the screen-writer pattern, #255).

The camera keyframe's authoritative raw is `command_raw` (the full u16 command
word) plus the raw s16 arrays (end_frame / angle / position / zoom); the decoded
sibling fields (channel_mask / source_mode / interpolation / …) are ignored by
the writer, exactly as the screen writer ignores mode/blend_mode.

Expected values come from INDEPENDENT sources — the real E019 bytes (identity
round-trip) and struct-recomputed ROM offsets (edit diff) — never the writer's
own math.

Run from tools/:
    uv run python -m unittest test_effect_writer_camera
"""

from __future__ import annotations

import os
import struct
import unittest
from pathlib import Path

import parse_effect as pe
import write_effect_camera as wec
import effect_writer_registry as reg
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


_ROOT = str(_effect_dir())
_E019 = os.path.join(_ROOT, "E019.BIN")   # Fire 4 — the ticket's sample (live camera tables)
_E015 = os.path.join(_ROOT, "E015.BIN")
_E001 = os.path.join(_ROOT, "E001.BIN")


def _diff_indices(a: bytes, b: bytes) -> list:
    assert len(a) == len(b)
    return [i for i in range(len(a)) if a[i] != b[i]]


class RegistryWiring(unittest.TestCase):
    def test_camera_is_registered(self):
        self.assertIn("camera", reg.registered_sections())
        self.assertTrue(callable(reg.serializer_for("camera")))


class RealBinRoundTrip(unittest.TestCase):
    """parse -> patch (no edit) reproduces the whole file byte-for-byte on real
    effects — the camera writer preserves every untouched byte."""

    def _roundtrip_identity(self, path: str) -> None:
        base = Path(path).read_bytes()
        header = pe.parse_header(base)
        tp = header["timeline_section_ptr"]
        camera = pe.parse_camera_keyframes(base, tp)
        # Standalone writer.
        out = wec.patch_camera_section(base, camera, tp)
        self.assertEqual(out, base, "standalone camera round-trip is byte-identical")
        # Via the registry save loop.
        via_reg = reg.patch_all(base, {"camera": camera}, header)
        self.assertEqual(via_reg, base, "registry camera round-trip is byte-identical")

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_e019_camera_roundtrip_byte_identical(self):
        self._roundtrip_identity(_E019)

    @unittest.skipUnless(os.path.exists(_E015), "E015.BIN not available")
    def test_e015_camera_roundtrip_byte_identical(self):
        self._roundtrip_identity(_E015)

    @unittest.skipUnless(os.path.exists(_E001), "E001.BIN not available")
    def test_e001_camera_roundtrip_byte_identical(self):
        self._roundtrip_identity(_E001)


class EditedFieldPartialPatch(unittest.TestCase):
    """Editing one camera field patches EXACTLY its bytes and nothing else. The
    target offsets are recomputed here from parse_effect's SoA table constants —
    an independent source from the writer."""

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_edit_angle_pitch_diffs_two_bytes(self):
        base = Path(_E019).read_bytes()
        header = pe.parse_header(base)
        tp = header["timeline_section_ptr"]
        camera = pe.parse_camera_keyframes(base, tp)

        # phase1 table, keyframe 2, angle[0] (pitch): 2-byte s16 at a recomputed offset.
        off = pe.CAMERA_TRACK_TABLES["phase1"]
        i = 2
        target = tp + off["angle"] + i * 6  # angle[0] of kf i
        old = struct.unpack_from("<h", base, target)[0]
        new = (old ^ 0x1234)
        if new >= 0x8000:
            new -= 0x10000
        camera["phase1"]["keyframes"][i]["angle"][0] = new

        out = wec.patch_camera_section(base, camera, tp)
        self.assertEqual(_diff_indices(base, out), [target, target + 1],
                         "editing angle pitch patches exactly its two bytes")
        self.assertEqual(struct.unpack_from("<h", out, target)[0], new)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_edit_command_word_diffs_two_bytes(self):
        base = Path(_E019).read_bytes()
        header = pe.parse_header(base)
        tp = header["timeline_section_ptr"]
        camera = pe.parse_camera_keyframes(base, tp)

        off = pe.CAMERA_TRACK_TABLES["for_each"]
        i = 0
        target = tp + off["command"] + i * 2
        old = struct.unpack_from("<H", base, target)[0]
        new = old ^ 0xFFFF  # flip every bit so BOTH command bytes change
        camera["for_each"]["keyframes"][i]["command_raw"] = new

        out = wec.patch_camera_section(base, camera, tp)
        self.assertEqual(_diff_indices(base, out), [target, target + 1],
                         "editing the command word patches exactly its two bytes")
        self.assertEqual(struct.unpack_from("<H", out, target)[0], new)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_screen_path_still_byte_identical(self):
        """The camera writer must not disturb the screen section — the two
        serializers coexist over one buffer (regression guard for the ticket's
        'screen path still byte-identical')."""
        base = Path(_E019).read_bytes()
        header = pe.parse_header(base)
        tp = header["timeline_section_ptr"]
        screen = pe.parse_all_screen_keyframes(base, tp)
        camera = pe.parse_camera_keyframes(base, tp)
        out = reg.patch_all(base, {"screen": screen, "camera": camera}, header)
        self.assertEqual(out, base)


class ChangedKeyframeCountPartialPatch(unittest.TestCase):
    """The add/delete lane verbs (ADR-0085) are the first edits that change the
    COMPILED keyframe count. The camera SoA tables are FIXED native-slot arrays
    (21/17/21); a count change is expressed as a moved `max_keyframe` watermark
    plus shifted slot contents, NOT a longer `keyframes` list. These guards lock
    that contract semantically (ADR-0085 is semantic-equivalence, not byte-exact
    once the count moves): the writer must round-trip a grown/shrunk active
    window, and must REFUSE (not silently truncate) an over-capacity table."""

    def _phase1(self):
        base = Path(_E019).read_bytes()
        header = pe.parse_header(base)
        tp = header["timeline_section_ptr"]
        camera = pe.parse_camera_keyframes(base, tp)
        return base, tp, camera

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_over_capacity_table_raises_not_truncates(self):
        """A table with more keyframes than its native slots cannot be
        section-written — the writer must raise, not silently drop the tail
        (the ROM has no 22nd phase1 slot)."""
        base, tp, camera = self._phase1()
        cap = pe.CAMERA_TRACK_TABLES["phase1"]["count"]
        t = camera["phase1"]
        t["keyframes"].append(dict(t["keyframes"][0]))  # 22nd slot, past the 21-slot cap
        self.assertEqual(len(t["keyframes"]), cap + 1)
        with self.assertRaises(ValueError):
            wec.patch_camera_section(base, camera, tp)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_max_keyframe_past_capacity_raises(self):
        """`max_keyframe` must index inside the native slots; a watermark at or
        past the slot count is malformed and must be rejected."""
        base, tp, camera = self._phase1()
        cap = pe.CAMERA_TRACK_TABLES["phase1"]["count"]
        camera["phase1"]["max_keyframe"] = cap  # 21 — one past the last valid index 20
        with self.assertRaises(ValueError):
            wec.patch_camera_section(base, camera, tp)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_insert_keyframe_grows_active_window_semantic_roundtrip(self):
        """Insert a keyframe at an active index: shift the live slots up by one,
        seed the freed slot, bump `max_keyframe`. The reparsed active window must
        match the expected grown stream, still within the 21 physical slots and
        without changing the section byte length (no overflow)."""
        base, tp, camera = self._phase1()
        t = camera["phase1"]
        mk = t["max_keyframe"]                 # 6 → active indices 0..6
        kfs = t["keyframes"]
        cap = pe.CAMERA_TRACK_TABLES["phase1"]["count"]
        self.assertLess(mk + 1, cap, "room to grow the active window inside native slots")

        at = 3  # insert before active index 3
        new_kf = {
            "index": at, "end_frame": 40, "angle": [1, 2, 3], "position": [4, 5, 6],
            "zoom": [0, 0, 0], "command_raw": 0x0402,
        }
        # Independent expected active stream: slots 0..at-1 unchanged, new_kf at
        # `at`, old slots at..mk shifted up one → new watermark mk+1.
        expect = [dict(kfs[i]) for i in range(at)] \
            + [dict(new_kf)] \
            + [dict(kfs[i]) for i in range(at, mk + 1)]

        # Apply the insert to the fixed-slot array in place (shift up, seed slot).
        for i in range(cap - 1, at, -1):
            kfs[i] = dict(kfs[i - 1])
        kfs[at] = dict(new_kf)
        t["max_keyframe"] = mk + 1

        out = wec.patch_camera_section(base, camera, tp)
        self.assertEqual(len(out), len(base), "section byte length is unchanged (no overflow)")
        reparsed = pe.parse_camera_keyframes(out, tp)["phase1"]
        self.assertEqual(reparsed["max_keyframe"], mk + 1, "watermark grew by one")
        self._assert_active_window(reparsed, expect)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_delete_keyframe_shrinks_active_window_semantic_roundtrip(self):
        """Delete an active keyframe: shift the higher live slots down one and
        drop the watermark. The reparsed active window must be the expected
        shorter stream with the deleted keyframe gone."""
        base, tp, camera = self._phase1()
        t = camera["phase1"]
        mk = t["max_keyframe"]                 # 6 → active indices 0..6
        kfs = t["keyframes"]
        cap = pe.CAMERA_TRACK_TABLES["phase1"]["count"]

        at = 2  # delete active index 2
        # Independent expected active stream: slots 0..at-1 unchanged, slots
        # at+1..mk shifted down one → new watermark mk-1.
        expect = [dict(kfs[i]) for i in range(at)] \
            + [dict(kfs[i]) for i in range(at + 1, mk + 1)]

        # Apply the delete to the fixed-slot array (shift down, clear vacated tail).
        for i in range(at, cap - 1):
            kfs[i] = dict(kfs[i + 1])
        kfs[cap - 1] = {"index": cap - 1, "end_frame": 0, "angle": [0, 0, 0],
                        "position": [0, 0, 0], "zoom": [0, 0, 0], "command_raw": 0}
        t["max_keyframe"] = mk - 1

        out = wec.patch_camera_section(base, camera, tp)
        reparsed = pe.parse_camera_keyframes(out, tp)["phase1"]
        self.assertEqual(reparsed["max_keyframe"], mk - 1, "watermark shrank by one")
        self._assert_active_window(reparsed, expect)

    def _assert_active_window(self, reparsed, expect):
        """The reparsed keyframes over 0..len(expect)-1 match `expect` on the raw
        authoritative fields (end_frame / angle / position / zoom / command_raw)."""
        for i, want in enumerate(expect):
            got = reparsed["keyframes"][i]
            for f in ("end_frame", "angle", "position", "zoom", "command_raw"):
                self.assertEqual(got[f], want[f],
                                 "active slot %d field %s mismatch" % (i, f))


if __name__ == "__main__":
    unittest.main()
