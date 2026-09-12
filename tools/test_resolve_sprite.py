#!/usr/bin/env python3
"""Guard for the ENTD `sprite_set` -> flat-store `SPR` resolution (the redesign of
EVTCHR attribution keys identity on the resolved SPR, not `special_name`).

Mirrors `research/key_documents/SPRITE_SET_RESOLUTION.md` "The rule" and
`src/data/JobDatabase.gd::get_sprite_id` + `SPRITE_NAMES`.

Run:  uv run python -m unittest test_resolve_sprite
"""

from __future__ import annotations

import unittest

import resolve_sprite as rs


class NamedTest(unittest.TestCase):
    def test_named_story_unit_is_its_own_index(self):
        # sprite_set < 0x80 -> the byte IS the SPR; job is irrelevant to art.
        self.assertEqual(rs.resolve_sprite(0x05, job=0x05), 0x05)  # Delita Ch2/3
        self.assertEqual(rs.resolve_sprite(0x0C, job=0x5E), 0x0C)  # Ovelia (job=Princess)
        self.assertEqual(rs.resolve_sprite(0x24, job=0x24), 0x24)  # Vormav


class GenericHumanTest(unittest.TestCase):
    def test_female_knight_marker_plus_job_derives_0x65(self):
        # 0x81 Generic Female + job 0x4C (Knight): 0x60 + (0x4C-0x4A)*2 + 1 = 0x65.
        self.assertEqual(rs.resolve_sprite(0x81, job=0x4C), 0x65)

    def test_male_knight_marker_plus_job_derives_0x64(self):
        # 0x80 Generic Male + job 0x4C: 0x60 + (0x4C-0x4A)*2 = 0x64.
        self.assertEqual(rs.resolve_sprite(0x80, job=0x4C), 0x64)

    def test_male_squire_is_the_zero_point(self):
        self.assertEqual(rs.resolve_sprite(0x80, job=0x4A), 0x60)
        self.assertEqual(rs.resolve_sprite(0x81, job=0x4A), 0x61)


class MonsterTest(unittest.TestCase):
    def test_chocobo_marker_plus_job_derives_0x86(self):
        # 0x82 Monster + job 0x5E (Chocobo): 0x86 + floor((0x5E-0x5E)/3) = 0x86.
        self.assertEqual(rs.resolve_sprite(0x82, job=0x5E), 0x86)

    def test_three_job_family_shares_one_sheet(self):
        # jobs 0x5E/0x5F/0x60 all map to 0x86; 0x61 rolls to 0x87.
        self.assertEqual(rs.resolve_sprite(0x82, job=0x60), 0x86)
        self.assertEqual(rs.resolve_sprite(0x82, job=0x61), 0x87)


if __name__ == "__main__":
    unittest.main()
