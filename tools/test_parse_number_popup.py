"""Unit tests for tools/parse_number_popup.py — the damage/status number-popup
grow/reveal trending table.

FFT trends the floating damage number (grow → 1.5 overshoot → settle, digits
revealing right-to-left) from a Q12 scale-ramp table BATTLE.BIN ships, read by the
draw fn FUN_800810a4. Per ADR-0001/ADR-0046 the table is a reproducible extractor
output, not hardcoded literals. See
research/working_documents/DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md Rounds 4–5.

Pure-structure tests run on the canonical constants; the real-asset tests validate
the extracted ramp against the on-disk BATTLE.BIN and skip if it is absent
(mirrors test_parse_frame_font.py / test_parse_cursor_bob.py).

Run from tools/:
    uv run python -m unittest test_parse_number_popup
"""
from __future__ import annotations

import unittest

import parse_number_popup as p
import _repo_paths as rp


def _battle() -> bytes:
    f = rp.battle_bin()
    if not f.exists():
        raise unittest.SkipTest(f"BATTLE.BIN missing: {f}")
    return f.read_bytes()


class CanonicalRampStructure(unittest.TestCase):
    """Pure checks on the declared curve — no binary needed."""

    def test_ramp_is_small_overshoot_settle(self):
        f = [x / p.Q12 for x in p.CANONICAL_RAMP_Q12]
        self.assertAlmostEqual(f[0], 0.30, places=2)       # starts small
        self.assertEqual(max(f), 1.5)                       # single 1.5 overshoot
        self.assertEqual(f.index(max(f)), 4)                # peak mid-ramp
        self.assertAlmostEqual(f[-1], 1.0, places=3)        # settles at 1.0
        self.assertTrue(all(a < b for a, b in zip(f[:5], f[1:5])))  # monotone rise to peak

    def test_phase_bands_are_contiguous_and_ordered(self):
        b = p.PHASE_BANDS
        self.assertEqual(b["grow"][0], 0)
        self.assertEqual(b["grow"][1] + 1, b["steady"][0])
        self.assertEqual(b["steady"][1] + 1, b["fade"][0])
        self.assertEqual(b["fade"][1] + 1, b["teardown"])


class RealAssetRamp(unittest.TestCase):
    """Validate the extracted table against the on-disk BATTLE.BIN."""

    def setUp(self):
        self.data = p.parse(_battle())

    def test_each_scale_block_reproduces_canonical_ramp(self):
        # parse() already asserts this, but pin it explicitly per block.
        for label in p.SCALE_BLOCKS:
            hw = self.data["raw_blocks_q12"][label]
            s = hw.index(p.CANONICAL_RAMP_Q12[0])
            self.assertEqual(hw[s:s + len(p.CANONICAL_RAMP_Q12)], p.CANONICAL_RAMP_Q12,
                             f"{label} does not carry the canonical ramp")

    def test_reveal_stagger_is_right_to_left(self):
        st = self.data["grow"]["reveal_stagger_phase"]
        # ones (rightmost) reveals first, hundreds (leftmost) last.
        self.assertLess(st["ones"], st["tens"])
        self.assertLess(st["tens"], st["hundreds"])
        self.assertEqual((st["ones"], st["tens"], st["hundreds"]), (1, 7, 12))

    def test_all_digits_full_size_by_grow_band_end(self):
        # By the last grow phase (0x14 = 20) every digit must be at 1.0 (0x1000).
        end = p.PHASE_BANDS["grow"][1]
        for digit, seq in self.data["grow"]["scale_by_phase_q12"].items():
            self.assertEqual(seq[end], p.Q12, f"{digit} not full-size at phase {end}")

    def test_scale_by_phase_length_matches_grow_band(self):
        want = p.PHASE_BANDS["grow"][1] + 1
        for seq in self.data["grow"]["scale_by_phase_q12"].values():
            self.assertEqual(len(seq), want)

    def test_leading_pad_is_zero_before_reveal(self):
        # Everything before a digit's stagger must be scale 0 (invisible).
        for digit, label in zip(("ones", "tens", "hundreds"), p.SCALE_BLOCKS):
            seq = self.data["grow"]["scale_by_phase_q12"][digit]
            s = self.data["grow"]["reveal_stagger_phase"][digit]
            self.assertTrue(all(v == 0 for v in seq[:s]), f"{digit} not zero before reveal")


if __name__ == "__main__":
    unittest.main()
