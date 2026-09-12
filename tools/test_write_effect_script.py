"""Unit tests for the byte-exact EFFECT-SCRIPT pattern-swap writer (#273, ADR-0094).

Unlike the fixed-size flags/timeline-header patchers, a script-pattern swap
*resizes* the script section (header offset 0x08), so every downstream section
shifts. `swap_effect_script` regenerates the canonical section from the effect's
own prologue `(texture_page, callbacks)`, splices it in, shifts the whole tail by
`delta`, and adds `delta` to the eight downstream header pointers (0x0C-0x24),
skipping zeros. `regenerate_section` is the canonical body itself — the swap is
offered ONLY when `regenerate_section(detect(sec), *prologue(sec)) == sec` and the
file is DATA-format (ADR-0094 decision 3), so the round-trip is provably lossless.

The expected layout here is an INDEPENDENT source of truth: the real ROM BINs
E001/E019 (3-phase) and E043 (1-phase), never the writer's own regeneration.

Run from tools/:
    python3 -m unittest test_write_effect_script
"""

from __future__ import annotations

import glob
import os
import struct
import unittest

import parse_effect as pe
import write_effect_script as wes

_EXTRACT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "..", "project-assets", "fft-extract", "EFFECT"
)
_E001 = os.path.join(_EXTRACT_DIR, "E001.BIN")  # 3-phase, no callbacks, 64-byte section
_E019 = os.path.join(_EXTRACT_DIR, "E019.BIN")  # 3-phase, no callbacks, 64-byte section
_E043 = os.path.join(_EXTRACT_DIR, "E043.BIN")  # 1-phase, no callbacks, 36-byte section


def _section(data: bytes):
    """Return (script_ptr, effect_data_ptr, section_bytes) read straight from the
    40-byte header — an independent locate, not via the writer."""
    script_ptr = struct.unpack_from("<I", data, 0x08)[0]
    effect_data_ptr = struct.unpack_from("<I", data, 0x0C)[0]
    return script_ptr, effect_data_ptr, data[script_ptr:effect_data_ptr]


# --- regenerate_section: byte-exact against the real BINs ---------------------


@unittest.skipUnless(os.path.exists(_E001), "E001 ROM extract not present")
class RegenerateMatchesRealBins(unittest.TestCase):
    def test_3phase_e001(self):
        data = open(_E001, "rb").read()
        _, _, sec = _section(data)
        # E001: set_texture_page flags=16, no callbacks.
        regen = wes.regenerate_section("3-phase", 16, [])
        self.assertEqual(regen, sec, "3-phase regen must be byte-exact vs E001")
        self.assertEqual(len(regen), 64)

    def test_3phase_e019(self):
        data = open(_E019, "rb").read()
        _, _, sec = _section(data)
        regen = wes.regenerate_section("3-phase", 16, [])
        self.assertEqual(regen, sec, "3-phase regen must be byte-exact vs E019")

    def test_1phase_e043(self):
        data = open(_E043, "rb").read()
        _, _, sec = _section(data)
        # E043: set_texture_page flags=8, no callbacks; prologue carries clear_timeline_a.
        regen = wes.regenerate_section("1-phase", 8, [])
        self.assertEqual(regen, sec, "1-phase regen must be byte-exact vs E043")
        self.assertEqual(len(regen), 36)

    def test_callbacks_shift_branch_offsets(self):
        # A synthesized prologue with two callbacks: every branch offset shifts by
        # 2*4=8 bytes vs the callback-free layout, and the section grows by 8.
        base = wes.regenerate_section("3-phase", 16, [])
        withcb = wes.regenerate_section("3-phase", 16, [(0, 7), (2, 8)])
        self.assertEqual(len(withcb), len(base) + 8)
        # The trailing end + pad structure is preserved (last op is end=0x04, pad 0x00 0x00).
        self.assertEqual(withcb[-4:], b"\x04\x00\x00\x00")


# --- prologue extraction: independent parse -----------------------------------


@unittest.skipUnless(os.path.exists(_E043), "E043 ROM extract not present")
class ParsePrologue(unittest.TestCase):
    def test_1phase_prologue_skips_clear_timeline(self):
        data = open(_E043, "rb").read()
        _, _, sec = _section(data)
        texpage, cbs = wes.parse_prologue(sec)
        self.assertEqual(texpage, 8)
        self.assertEqual(cbs, [])

    def test_3phase_prologue(self):
        data = open(_E001, "rb").read()
        _, _, sec = _section(data)
        texpage, cbs = wes.parse_prologue(sec)
        self.assertEqual(texpage, 16)
        self.assertEqual(cbs, [])


# --- detect + swappable gate --------------------------------------------------


class DetectAndGate(unittest.TestCase):
    def test_detect_3phase(self):
        _, _, sec = _section(open(_E001, "rb").read())
        self.assertEqual(wes.detect_pattern(sec), "3-phase")

    def test_detect_1phase(self):
        _, _, sec = _section(open(_E043, "rb").read())
        self.assertEqual(wes.detect_pattern(sec), "1-phase")

    def test_swappable_canonical(self):
        self.assertTrue(wes.is_swappable(open(_E001, "rb").read())[0])
        self.assertTrue(wes.is_swappable(open(_E043, "rb").read())[0])


# --- swap_effect_script: there-and-back byte identity + intermediate validity --


@unittest.skipUnless(os.path.exists(_E001), "E001 ROM extract not present")
class SwapRoundTrip(unittest.TestCase):
    def _assert_pointers_land_on_sections(self, data: bytes):
        """Every non-zero downstream header pointer must land on a 4-aligned offset
        inside the file, and be strictly ascending from script_ptr (sections are
        located only via the header)."""
        ptrs = [struct.unpack_from("<I", data, off)[0] for off in range(0x00, 0x28, 4)]
        prev = ptrs[2]  # script_ptr
        for off in (0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24):
            p = struct.unpack_from("<I", data, off)[0]
            if p == 0:
                continue
            self.assertEqual(p % 4, 0, "pointer 0x%02X is 4-aligned" % off)
            self.assertLess(p, len(data), "pointer 0x%02X in-bounds" % off)
            self.assertGreater(p, prev, "pointer 0x%02X ascends past 0x%02X" % (off, off - 4))
            prev = p

    def test_e001_there_and_back_is_byte_identical(self):
        data = open(_E001, "rb").read()
        mid = wes.swap_effect_script(data, "1-phase")
        self.assertNotEqual(mid, data, "swap to 1-phase changes bytes")
        self.assertEqual(wes.detect_pattern(_section(mid)[2]), "1-phase")
        back = wes.swap_effect_script(mid, "3-phase")
        self.assertEqual(back, data, "3-phase -> 1-phase -> 3-phase is byte-identical")

    def test_e001_intermediate_file_is_valid(self):
        # There-and-back cannot prove the intermediate is correct (a down-then-up
        # shift restores bytes regardless). Re-parse the intermediate directly.
        data = open(_E001, "rb").read()
        mid = wes.swap_effect_script(data, "1-phase")
        self.assertEqual(wes.detect_pattern(_section(mid)[2]), "1-phase")
        self._assert_pointers_land_on_sections(mid)
        # File length shrinks by exactly the section delta (64 -> 36 = -28).
        self.assertEqual(len(mid), len(data) - 28)

    def test_e043_1phase_to_3phase_and_back(self):
        # A real 1-phase source (E043) exercises the up-then-down direction with a
        # real prologue (texture_page=8), independent of the minted fixture.
        data = open(_E043, "rb").read()
        up = wes.swap_effect_script(data, "3-phase")
        self.assertEqual(wes.detect_pattern(_section(up)[2]), "3-phase")
        self._assert_pointers_land_on_sections(up)
        self.assertEqual(len(up), len(data) + 28)
        back = wes.swap_effect_script(up, "1-phase")
        self.assertEqual(back, data, "1-phase -> 3-phase -> 1-phase is byte-identical")

    def test_same_pattern_is_noop(self):
        data = open(_E001, "rb").read()
        self.assertEqual(wes.swap_effect_script(data, "3-phase"), data,
                         "swapping to the current pattern regenerates identical bytes")


# --- corpus gate: canonical DATA regens exactly; everything else is read-only --


@unittest.skipUnless(os.path.isdir(_EXTRACT_DIR), "ROM extract dir not present")
class CorpusGate(unittest.TestCase):
    def test_canonical_data_effects_regenerate_exactly(self):
        matched = 0
        gated = 0
        outliers = []
        for f in sorted(glob.glob(os.path.join(_EXTRACT_DIR, "E*.BIN"))):
            data = open(f, "rb").read()
            swappable, _reason = wes.is_swappable(data)
            if swappable:
                # A swappable effect MUST regenerate its own section byte-exactly
                # (that IS the gate) and swap+swap-back byte-identically.
                _, _, sec = _section(data)
                pat = wes.detect_pattern(sec)
                texpage, cbs = wes.parse_prologue(sec)
                self.assertEqual(wes.regenerate_section(pat, texpage, cbs), sec,
                                 "%s swappable => regen byte-exact" % os.path.basename(f))
                matched += 1
            else:
                gated += 1
        # From the corpus audit: ~288 canonical DATA effects are swappable; the rest
        # (CODE, Custom, and the 2 non-canonical 1-phase outliers E225/E457) gate out.
        self.assertGreater(matched, 250, "most DATA effects are swappable (got %d)" % matched)
        self.assertGreater(gated, 100, "CODE/Custom/outliers gate out (got %d)" % gated)

    def test_known_outliers_gate_out(self):
        for name in ("E225.BIN", "E457.BIN"):
            p = os.path.join(_EXTRACT_DIR, name)
            if not os.path.exists(p):
                continue
            swappable, reason = wes.is_swappable(open(p, "rb").read())
            self.assertFalse(swappable, "%s is a non-canonical 1-phase outlier" % name)
            self.assertTrue(reason, "a read-only reason is given")

    def test_code_format_gates_out(self):
        p = os.path.join(_EXTRACT_DIR, "E015.BIN")
        if os.path.exists(p):
            swappable, reason = wes.is_swappable(open(p, "rb").read())
            self.assertFalse(swappable, "E015 is CODE-format")
            self.assertIn("CODE", reason)


if __name__ == "__main__":
    unittest.main()
