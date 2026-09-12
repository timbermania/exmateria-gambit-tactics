"""Unit tests for the TIER-3 `sound_def` section SPLICE writer (ADR-0085
amendment 2026-08-11, slice 4).

The edited feds blob replaces the bytes at [sound_def_ptr, texture_ptr). A
same-size patch is a pure splice; a RESIZE (ADR-0085 amendment 2026-08-18b —
prune-for-real shrinks the blob, structural insert grows it) additionally shifts
the file tail and repoints the one header pointer that lives after sound_def:
`texture_ptr`. The section is padded to a 4-byte multiple, which is the corpus
invariant (all 401 FEDS sections start, end and size 4-aligned). A non-feds blob
is still refused — a mis-addressed splice must not scribble — and so is a resize
whose header geometry does not agree with the bytes it is about to move.

The corpus guard closes the loop extractor→editor→writer: for every extracted
effect, the studio's feds.bin IS the base BIN's [sound_def_ptr, texture_ptr)
slice, so splicing it back unedited reproduces the source byte-for-byte.

Run from tools/:
    python3 -m unittest test_write_effect_sound_def
"""

from __future__ import annotations

import glob
import json
import os
import struct
import unittest
from pathlib import Path

import effect_writer_registry as ewr
import parse_effect as pe
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402

_EXTRACT_EFFECT_DIR = str(_effect_dir())
_ASSETS_EFFECTS = str(Path(__file__).resolve().parent.parent / "assets" / "effects")


def _synthetic_base() -> bytes:
    """A headerless stand-in for the splice tests: just a section at a known
    place. Its FEDS section is 4-aligned in start, end and size, as every one of
    the 401 real ones is."""
    base = bytearray(200)
    for i in range(200):
        base[i] = i % 251
    blob = bytearray(b"feds")
    blob += bytes(range(44))
    base[100:148] = blob
    return bytes(base)


_HEADER = {"sound_def_ptr": 100, "texture_ptr": 148}


# The header's ten section pointers, in file order.
_PTR_ORDER = ("frames_ptr", "animation_ptr", "script_data_ptr", "effect_data_ptr",
              "anim_table_ptr", "time_scale_ptr", "effect_flags_ptr",
              "timeline_section_ptr", "sound_def_ptr", "texture_ptr")


def _synthetic_effect(prologue: int = 0, feds_len: int = 48, tail_len: int = 64):
    """A real-SHAPED effect file: an optional MIPS prologue (CODE format), the
    40-byte header (pointers RELATIVE to it), filler sections, the feds section,
    a texture tail. Returns (bytes, header) with the header resolved to ABSOLUTE
    offsets — exactly what `parse_effect.parse_header` hands the writers."""
    rel = {
        "frames_ptr": 0x28, "animation_ptr": 0x30, "script_data_ptr": 0x38,
        "effect_data_ptr": 0x40, "anim_table_ptr": 0x48, "time_scale_ptr": 0,
        "effect_flags_ptr": 0x50, "timeline_section_ptr": 0x58,
        "sound_def_ptr": 0x60, "texture_ptr": 0x60 + feds_len,
    }
    size = prologue + rel["texture_ptr"] + tail_len
    buf = bytearray(size)
    if prologue:
        struct.pack_into("<I", buf, 0, 0x27BDFFE0)        # addiu sp, sp, -32
        for off in range(4, prologue, 4):
            struct.pack_into("<I", buf, off, 0xFFFFFFFF)  # never a plausible header
    for i, key in enumerate(_PTR_ORDER):
        struct.pack_into("<I", buf, prologue + i * 4, rel[key])
    for i in range(prologue + 0x28, prologue + rel["sound_def_ptr"]):
        buf[i] = 0xA5                                     # filler sections
    feds = bytearray(b"feds") + bytes((i * 7) % 251 for i in range(feds_len - 4))
    buf[prologue + rel["sound_def_ptr"]:prologue + rel["texture_ptr"]] = feds
    for i in range(prologue + rel["texture_ptr"], size):
        buf[i] = 0x5A                                     # the texture tail
    header = {k: (0 if v == 0 else prologue + v) for k, v in rel.items()}
    header["file_size"] = size
    return bytes(buf), header


def _rel_ptrs(data: bytes, prologue: int):
    """The ten header pointers as STORED (relative to the header base)."""
    return [struct.unpack_from("<I", data, prologue + i * 4)[0]
            for i in range(len(_PTR_ORDER))]


class SoundDefSpliceTest(unittest.TestCase):
    def test_splice_replaces_section_and_preserves_the_rest(self):
        base = _synthetic_base()
        edited = bytearray(base[100:148])
        edited[10] = 0xAB          # one studio byte patch
        out = ewr.patch_all(base, {"sound_def": bytes(edited)}, _HEADER)
        self.assertEqual(out[100:148], bytes(edited))
        self.assertEqual(out[:100], base[:100])
        self.assertEqual(out[148:], base[148:])

    def test_unedited_splice_is_byte_identical(self):
        base = _synthetic_base()
        out = ewr.patch_all(base, {"sound_def": base[100:148]}, _HEADER)
        self.assertEqual(out, base)

    def test_resize_without_header_geometry_is_refused(self):
        """A resize has to move `texture_ptr`, so it needs the real header base.
        `_HEADER` is a bare two-pointer geometry stub (no `frames_ptr`) over a
        headerless synthetic base — refuse rather than guess where to write."""
        base = _synthetic_base()
        with self.assertRaises(ValueError):
            ewr.patch_all(base, {"sound_def": base[100:144]}, _HEADER)

    def test_non_feds_blob_is_refused(self):
        base = _synthetic_base()
        bogus = b"XXXX" + base[104:148]
        with self.assertRaises(ValueError):
            ewr.patch_all(base, {"sound_def": bogus}, _HEADER)

    def test_missing_section_is_refused(self):
        base = _synthetic_base()
        with self.assertRaises(ValueError):
            ewr.patch_all(base, {"sound_def": base[100:148]},
                          {"sound_def_ptr": 0, "texture_ptr": 0})


class SoundDefResizeTest(unittest.TestCase):
    """The RELOCATION path (ADR-0085 amendment 2026-08-18b): a length change
    splices, shifts the tail, and repoints `texture_ptr` — the only header
    pointer after `sound_def_ptr`. DATA and CODE format differ in exactly one
    thing: the header base the stored pointers are relative to."""

    def _check_resize(self, prologue: int, delta: int) -> None:
        base, header = _synthetic_effect(prologue=prologue)
        sd, tx = header["sound_def_ptr"], header["texture_ptr"]
        section = base[sd:tx]
        blob = section + bytes(delta) if delta > 0 else section[:delta]
        out = ewr.patch_all(base, {"sound_def": blob}, header)

        self.assertEqual(len(out), len(base) + delta, "file did not resize by delta")
        self.assertEqual(out[sd:sd + len(blob)], blob, "the section is not the new blob")
        # The tail moved WHOLE — same content at the new texture_ptr.
        self.assertEqual(out[tx + delta:], base[tx:], "the texture tail did not shift cleanly")
        # Everything before the section is untouched except the one moved pointer.
        before, after = _rel_ptrs(base, prologue), _rel_ptrs(out, prologue)
        self.assertEqual(before[:9], after[:9], "a pointer at or before sound_def moved")
        self.assertEqual(after[9], before[9] + delta, "texture_ptr was not repointed")
        self.assertEqual(out[prologue + 0x28:sd], base[prologue + 0x28:sd],
                         "the sections between the header and feds were disturbed")

    def test_data_format_grow(self):
        self._check_resize(prologue=0, delta=4)

    def test_data_format_shrink(self):
        self._check_resize(prologue=0, delta=-4)

    def test_code_format_grow(self):
        self._check_resize(prologue=64, delta=8)

    def test_code_format_shrink(self):
        self._check_resize(prologue=64, delta=-8)

    def test_resize_pads_the_section_to_a_four_byte_multiple(self):
        """Every FEDS section in the corpus starts, ends and sizes 4-aligned (the
        0-3 slack bytes the amendment measured ARE that padding), so a blob of an
        odd length is zero-padded up rather than misaligning the texture."""
        base, header = _synthetic_effect()
        sd, tx = header["sound_def_ptr"], header["texture_ptr"]
        blob = base[sd:tx][:-6]          # 42 bytes -> padded to 44
        out = ewr.patch_all(base, {"sound_def": blob}, header)
        self.assertEqual(len(out), len(base) - 4)
        self.assertEqual(out[sd:sd + len(blob)], blob)
        self.assertEqual(out[sd + len(blob):sd + len(blob) + 2], b"\x00\x00")
        self.assertEqual(_rel_ptrs(out, 0)[9], _rel_ptrs(base, 0)[9] - 4)

    def test_resize_is_a_noop_when_padding_absorbs_it(self):
        """A blob 2 bytes short of the section pads back to the SAME size — a
        splice, not a relocation, and byte-identical when the tail bytes match."""
        base, header = _synthetic_effect()
        sd, tx = header["sound_def_ptr"], header["texture_ptr"]
        blob = base[sd:tx][:-2]
        out = ewr.patch_all(base, {"sound_def": blob}, header)
        self.assertEqual(len(out), len(base))
        self.assertEqual(_rel_ptrs(out, 0), _rel_ptrs(base, 0))

    def test_resize_refused_when_the_header_disagrees_with_the_bytes(self):
        """The geometry check: the stored pointers at the derived header base must
        resolve to the very section about to be moved. A shifted `frames_ptr` (so a
        wrong base) must refuse, not scribble a pointer into the middle of a section."""
        base, header = _synthetic_effect()
        bogus = dict(header)
        bogus["frames_ptr"] = header["frames_ptr"] + 4     # base is now 4 too high
        with self.assertRaises(ValueError):
            ewr.patch_all(base, {"sound_def": base[header["sound_def_ptr"]:
                                                   header["texture_ptr"]] + b"\x00\x00\x00\x00"},
                          bogus)

    def test_same_size_never_touches_the_header(self):
        base, header = _synthetic_effect()
        sd, tx = header["sound_def_ptr"], header["texture_ptr"]
        edited = bytearray(base[sd:tx])
        edited[9] = 0xAB
        out = ewr.patch_all(base, {"sound_def": bytes(edited)}, header)
        self.assertEqual(len(out), len(base))
        self.assertEqual(out[:sd], base[:sd])
        self.assertEqual(out[tx:], base[tx:])


@unittest.skipUnless(os.path.isdir(_EXTRACT_EFFECT_DIR), "ROM extract not available")
@unittest.skipUnless(os.path.isdir(_ASSETS_EFFECTS), "extracted effects not available")
class SoundDefCorpusRoundTripTest(unittest.TestCase):
    """Extractor↔writer geometry agreement over the WHOLE corpus: every effect's
    feds.bin is the base BIN's [sound_def_ptr, texture_ptr) slice, and splicing
    it back unedited is byte-identical."""

    def test_corpus_round_trip_identity(self):
        checked = 0
        failures = []
        for feds_path in sorted(glob.glob(os.path.join(_ASSETS_EFFECTS, "E*", "feds.bin"))):
            eff_dir = os.path.dirname(feds_path)
            eff = os.path.basename(eff_dir)
            base_path = os.path.join(_EXTRACT_EFFECT_DIR, eff + ".BIN")
            header_path = os.path.join(eff_dir, "header.json")
            if not (os.path.exists(base_path) and os.path.exists(header_path)):
                continue
            with open(header_path) as f:
                header = json.load(f)["header"]
            with open(base_path, "rb") as f:
                base = f.read()
            with open(feds_path, "rb") as f:
                feds = f.read()
            start = int(header["sound_def_ptr"])
            end = min(int(header["texture_ptr"]), len(base))
            if base[start:end] != feds:
                failures.append("%s: feds.bin != base slice [%d:%d]" % (eff, start, end))
                continue
            out = ewr.patch_all(base, {"sound_def": feds}, header)
            if out != base:
                failures.append("%s: unedited splice not byte-identical" % eff)
            checked += 1
        self.assertEqual(failures, [])
        self.assertGreater(checked, 300, "corpus guard should cover the extracted effects")


@unittest.skipUnless(os.path.isdir(_EXTRACT_EFFECT_DIR), "ROM extract not available")
@unittest.skipUnless(os.path.isdir(_ASSETS_EFFECTS), "extracted effects not available")
class SoundDefRelocationCorpusTest(unittest.TestCase):
    """The RELOCATION corpus gate (ADR-0085 amendment 2026-08-18b), over all 401
    effects that carry a FEDS section and BOTH file formats. Three claims:

      1. delta=0 reproduces the original E###.BIN byte-for-byte
         (`SoundDefCorpusRoundTripTest.test_corpus_round_trip_identity`).
      2. at delta!=0 every header pointer after `sound_def_ptr` still addresses the
         same CONTENT — compared as bytes, never as numbers.
      3. the rewritten file re-parses to the same effect.

    Claim 2 runs both directions (a structural insert grows, prune-for-real
    shrinks); claim 3 runs the grow, whose four appended bytes are more of the
    trailing alignment padding every section already carries, so the sound is
    unchanged and the whole parse must match.
    """

    def _corpus(self):
        """(effect, base bytes, header, header base) for every extracted effect
        that has a FEDS section and a real BIN behind it."""
        for header_path in sorted(glob.glob(os.path.join(_ASSETS_EFFECTS, "E*", "header.json"))):
            eff = os.path.basename(os.path.dirname(header_path))
            base_path = os.path.join(_EXTRACT_EFFECT_DIR, eff + ".BIN")
            if not os.path.exists(base_path):
                continue
            with open(header_path) as f:
                header = json.load(f)["header"]
            if int(header.get("sound_def_ptr", 0)) <= 0:
                continue
            with open(base_path, "rb") as f:
                base = f.read()
            yield eff, base, header, int(header["frames_ptr"]) - 0x28

    def test_corpus_has_both_formats(self):
        formats = {(hb > 0) for _e, _b, _h, hb in self._corpus()}
        self.assertEqual(formats, {False, True}, "the gate must cover DATA and CODE")

    def test_downstream_pointers_still_address_the_same_content(self):
        checked, failures = 0, []
        for delta in (4, -4):
            for eff, base, header, hbase in self._corpus():
                sd, tx = int(header["sound_def_ptr"]), int(header["texture_ptr"])
                section = base[sd:tx]
                blob = section + bytes(delta) if delta > 0 else section[:delta]
                out = ewr.patch_all(base, {"sound_def": blob}, header)
                before, after = _rel_ptrs(base, hbase), _rel_ptrs(out, hbase)
                if before[:9] != after[:9]:
                    failures.append("%s d%+d: a pointer at or before sound_def moved" % (eff, delta))
                elif after[9] != before[9] + delta:
                    failures.append("%s d%+d: texture_ptr %d -> %d, expected %+d"
                                    % (eff, delta, before[9], after[9], delta))
                elif out[tx + delta:] != base[tx:]:
                    failures.append("%s d%+d: the texture section is not the same bytes" % (eff, delta))
                elif out[:sd] != base[:sd][:hbase + 0x24] + out[hbase + 0x24:hbase + 0x28] + base[hbase + 0x28:sd]:
                    failures.append("%s d%+d: bytes before the section changed beyond texture_ptr" % (eff, delta))
                else:
                    checked += 1
        self.assertEqual(failures[:8], [])
        self.assertGreater(checked, 700, "both directions over the whole corpus")

    def test_rewritten_file_reparses_to_the_same_effect(self):
        import tempfile
        skip = {"filename", "feds", "feds_bin", "header", "sections"}
        checked, failures = 0, []
        with tempfile.TemporaryDirectory() as td:
            for eff, base, header, hbase in self._corpus():
                sd, tx = int(header["sound_def_ptr"]), int(header["texture_ptr"])
                out = ewr.patch_all(base, {"sound_def": base[sd:tx] + bytes(4)}, header)
                src = os.path.join(td, eff + ".BIN")
                Path(src).write_bytes(out)
                got = pe.parse_effect_file(src, header_offset=hbase)
                Path(src).write_bytes(base)
                want = pe.parse_effect_file(src, header_offset=hbase)
                diff = [k for k in want if k not in skip and got.get(k) != want[k]]
                if diff:
                    failures.append("%s: %s differ after relocation" % (eff, diff))
                elif got["header"]["texture_ptr"] != want["header"]["texture_ptr"] + 4:
                    failures.append("%s: texture_ptr did not move with the tail" % eff)
                else:
                    checked += 1
        self.assertEqual(failures[:8], [])
        self.assertGreater(checked, 300, "the whole extracted corpus")


class SoundSectionsCliTest(unittest.TestCase):
    """The unified sound-sections CLI (studio_save's json→bin half for the three
    sound seams): base + header + any of --sound/--containers/--feds → one
    patched output. Here: the feds splice path end-to-end through main()."""

    def test_cli_splices_feds_blob(self):
        import tempfile
        import write_effect_sound_sections as wess
        base = _synthetic_base()
        edited = bytearray(base[100:148])
        edited[20] = 0xCD
        with tempfile.TemporaryDirectory() as td:
            base_p = os.path.join(td, "base.bin")
            header_p = os.path.join(td, "header.json")
            feds_p = os.path.join(td, "feds.bin")
            out_p = os.path.join(td, "out.bin")
            Path(base_p).write_bytes(base)
            Path(header_p).write_text(json.dumps({"header": _HEADER}))
            Path(feds_p).write_bytes(bytes(edited))
            rc = wess.main([base_p, header_p, out_p, "--feds", feds_p])
            self.assertEqual(rc, 0)
            out = Path(out_p).read_bytes()
            self.assertEqual(out[100:148], bytes(edited))
            self.assertEqual(out[:100], base[:100])

    def test_cli_refuses_no_sections(self):
        import tempfile
        import write_effect_sound_sections as wess
        with tempfile.TemporaryDirectory() as td:
            base_p = os.path.join(td, "base.bin")
            header_p = os.path.join(td, "header.json")
            Path(base_p).write_bytes(_synthetic_base())
            Path(header_p).write_text(json.dumps({"header": _HEADER}))
            self.assertNotEqual(
                wess.main([base_p, header_p, os.path.join(td, "out.bin")]), 0)


if __name__ == "__main__":
    unittest.main()
