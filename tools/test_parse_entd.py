"""Tests for tools/parse_entd.py.

Two layers:
  - Pure-function tests on a synthetic 40-byte EventUnit (verifies the
    field-order port of FFTPatcher's EventUnit.cs ctor in isolation).
  - Real-data sanity test against the retail extract: scenario 1's
    deployment record (entd_idx 256 → ENTD3 record 0) puts Princess
    Ovelia in slot 0 — sprite_set 0x0C, female, unit_id 0x0C, at (8,4)
    facing East.

Uses stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_entd
"""

from __future__ import annotations

import unittest
from dataclasses import asdict
from pathlib import Path

import parse_entd as p
import _repo_paths as rp


def _slot(**overrides: int) -> bytes:
    """Build a synthetic 40-byte slot, all zero by default. Pass byte
    indices as keyword names of the form `b<HEX>` (e.g. b00=0x0C)."""
    buf = bytearray(40)
    for k, v in overrides.items():
        assert k.startswith("b"), f"bad key {k!r}"
        buf[int(k[1:], 16)] = v
    return bytes(buf)


class ApplyChiralityFixToSlotTest(unittest.TestCase):
    """ADR-0052 in-place renumber on a parsed slot. y is the PSX-tile depth
    axis; after the 180° rotation around X it becomes `size_z - 1 - y`. Facing
    is a POSE (consumed raw, like the Camera opcode), so the fix leaves it —
    and facing_raw / facing_name — untouched."""

    def _slot_dict(self, **overrides):
        # build the slot via parse_slot to get all the fields, then override
        s = p.parse_slot(bytes(40))
        d = asdict(s)
        d.update(overrides)
        return d

    def test_y_renumbers_to_our_coord(self) -> None:
        d = self._slot_dict(y=4, unit_id=0x0C)
        out = p.apply_chirality_fix_to_slot(d, size_z_tiles=10)
        self.assertEqual(out["y"], 5)

    def test_facing_untouched(self) -> None:
        # Facing is a pose, consumed raw — the fix must not remap it. Check both
        # a depth-axis value (2 = North) and a lateral one (3 = East).
        for face, name in ((2, "North"), (3, "East"), (0, "South"), (1, "West")):
            d = self._slot_dict(facing=face, facing_raw=face,
                                facing_name=name, unit_id=0x0C)
            out = p.apply_chirality_fix_to_slot(d, size_z_tiles=10)
            self.assertEqual(out["facing"], face)
            self.assertEqual(out["facing_name"], name)
            self.assertEqual(out["facing_raw"], face)

    def test_unused_slot_skipped(self) -> None:
        # unit_id 0xFF marks an empty/unused slot — leave it alone.
        d = self._slot_dict(y=4, facing=2, unit_id=0xFF)
        out = p.apply_chirality_fix_to_slot(d, size_z_tiles=10)
        self.assertEqual(out["y"], 4)
        self.assertEqual(out["facing"], 2)

    def test_upper_level_bit_preserved(self) -> None:
        d = self._slot_dict(facing=3, facing_raw=0x83, facing_name="East",
                            upper_level=True, unit_id=0x0C)
        out = p.apply_chirality_fix_to_slot(d, size_z_tiles=10)
        # Facing untouched; upper_level bit (facing_raw bit 7) survives intact.
        self.assertEqual(out["facing"], 3)
        self.assertEqual(out["facing_raw"], 0x83)
        self.assertTrue(out["upper_level"])


class ParseSlotTest(unittest.TestCase):

    def test_synthetic_minimal(self) -> None:
        """An all-zero slot decodes to all-zero/default fields (no crashes,
        no negative values, all flags False, default enum names resolved)."""
        s = p.parse_slot(bytes(40))
        self.assertEqual(s.sprite_set, 0)
        self.assertEqual(s.flags1, 0)
        self.assertEqual(s.prereq_job_name, "Base")
        self.assertEqual(s.team_color_name, "Blue")
        self.assertEqual(s.facing_name, "South")
        self.assertFalse(s.upper_level)
        self.assertFalse(s.flags1_decoded["male"])
        self.assertFalse(s.flags1_decoded["female"])

    def test_byte_field_mapping(self) -> None:
        """Each byte should land in the right field per FFTPatcher
        EventUnit.cs ctor — spot-check the field-by-offset mapping.
        Byte indices: X=25(0x19), Y=26(0x1A), facing+upper=27(0x1B),
        unit_id=32(0x20)."""
        s = p.parse_slot(_slot(b00=0xC, b02=0xC, b03=10, b04=5, b05=11,
                               b06=70, b07=70, b08=2, b09=3, b0A=0xC,
                               b19=8, b1A=4,    # X=8, Y=4
                               b1B=0x83,         # facing 0x03 + upper_level bit
                               b20=0xC))         # unit_id
        self.assertEqual(s.sprite_set, 0xC)
        self.assertEqual(s.special_name, 0xC)
        self.assertEqual(s.level, 10)
        self.assertEqual(s.month, 5)
        self.assertEqual(s.day, 11)
        self.assertEqual(s.bravery, 70)
        self.assertEqual(s.faith, 70)
        self.assertEqual(s.prereq_job, 2)
        self.assertEqual(s.prereq_job_name, "Knight")
        self.assertEqual(s.prereq_job_level, 3)
        self.assertEqual(s.job, 0xC)
        self.assertEqual(s.x, 8)
        self.assertEqual(s.y, 4)
        self.assertEqual(s.facing, 3)
        self.assertEqual(s.facing_name, "East")
        self.assertTrue(s.upper_level)
        self.assertEqual(s.unit_id, 0xC)

    def test_msb_flag_decoding(self) -> None:
        """FFT packs flag bytes MSB-first — byte 0x40 → bit 6 set →
        names[1] (`female`) True, others False. Matches FFTPatcher's
        CopyByteToBooleans(b, ref Male, ref Female, ...)."""
        s = p.parse_slot(_slot(b01=0x40))
        self.assertTrue(s.flags1_decoded["female"])
        self.assertFalse(s.flags1_decoded["male"])
        self.assertFalse(s.flags1_decoded["monster"])

    def test_team_color_mask(self) -> None:
        """flags2 byte bits 5..4 (mask 0x30) decode as team_color."""
        # bits 5..4 == 0b01 → Red
        s = p.parse_slot(_slot(b18=0x10))
        self.assertEqual(s.team_color, 1)
        self.assertEqual(s.team_color_name, "Red")
        # bits 5..4 == 0b11 → LightBlue
        s = p.parse_slot(_slot(b18=0x30))
        self.assertEqual(s.team_color_name, "LightBlue")

    def test_unknown_prereq_job(self) -> None:
        """Unmapped PreRequisiteJob byte resolves to `Unknown_0xNN`."""
        s = p.parse_slot(_slot(b08=0x77))
        self.assertEqual(s.prereq_job_name, "Unknown_0x77")


class ParseEntdRealDataTest(unittest.TestCase):
    """Sanity-checks the parser against the retail extract: scenario 1's
    deployment record (entd_idx 256 → ENTD3 record 0) puts Princess Ovelia
    in slot 0 (sprite_set 0x0C, female, unit_id 0x0C, (8,4) East)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.entd3 = rp.fft_extract_root() / "BATTLE" / "ENTD3.ENT"
        if not cls.entd3.exists():
            raise unittest.SkipTest(f"ENTD3.ENT missing at {cls.entd3}")
        cls.records = p.parse_entd_file(cls.entd3)

    def test_scenario_1_ovelia_slot_0(self) -> None:
        slot = self.records[0][0]   # record 0, slot 0
        self.assertEqual(slot.sprite_set, 0x0C, "Ovelia spriteset")
        self.assertEqual(slot.unit_id, 0x0C, "Ovelia unit_id")
        self.assertEqual(slot.special_name, 0x0C, "Ovelia special_name")
        self.assertEqual(slot.job, 0x0C, "scenario-1 deployment job")
        self.assertTrue(slot.flags1_decoded["female"], "Ovelia is Female")
        self.assertFalse(slot.flags1_decoded["male"])
        self.assertEqual((slot.x, slot.y), (8, 4), "scenario-1 deploy pos")
        self.assertEqual(slot.facing_name, "East")
        self.assertFalse(slot.upper_level)

    def test_full_file_dimensions(self) -> None:
        self.assertEqual(len(self.records), p.RECORDS_PER_FILE)
        for rec in self.records:
            self.assertEqual(len(rec), p.SLOTS_PER_RECORD)


class ParseAllTest(unittest.TestCase):
    """Smoke-test the full 4-file parse: the 0x100 base offset for ENTD3
    must land scenario 1 (Ovelia) at key 256."""

    @classmethod
    def setUpClass(cls) -> None:
        battle = rp.fft_extract_root() / "BATTLE"
        if not (battle / "ENTD3.ENT").exists():
            raise unittest.SkipTest("BATTLE/ENTD*.ENT not extracted")
        cls.all = p.parse_all(battle)

    def test_record_count(self) -> None:
        self.assertEqual(len(self.all), 4 * p.RECORDS_PER_FILE)

    def test_entd_256_is_ovelia(self) -> None:
        slots = self.all[256]["slots"]
        self.assertEqual(slots[0]["sprite_set"], 0x0C)
        self.assertEqual(slots[0]["unit_id"], 0x0C)
        self.assertEqual(self.all[256]["file"], "ENTD3.ENT")
        self.assertEqual(self.all[256]["record_in_file"], 0)


if __name__ == "__main__":
    unittest.main()
