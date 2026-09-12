"""Unit tests for the EventInstruction enum generator in gen_opcode_catalog.py.

Locks the Option-A slug rule (ADR-0059 / issue #145): unique display-name
slug verbatim, hex-suffix on collision, the six-entry Variable comparison
symbol map, and post-disambiguation uniqueness. Uses stdlib unittest so there
is no pytest dep on the tools venv.

Run from tools/:
    uv run python -m unittest test_gen_opcode_catalog
"""

from __future__ import annotations

import unittest

import gen_opcode_catalog as g


class EventSlug(unittest.TestCase):
    """The base slug transform (display name -> UPPER_SNAKE identifier),
    before collision disambiguation."""

    def test_multiword_name_upper_snakes(self):
        self.assertEqual(g.event_slug("Face Unit 2"), "FACE_UNIT_2")

    def test_two_word_name(self):
        self.assertEqual(g.event_slug("BG Sound"), "BG_SOUND")

    def test_hyphen_becomes_underscore(self):
        self.assertEqual(g.event_slug("No-op"), "NO_OP")

    def test_unknown_slugs_to_unknown(self):
        self.assertEqual(g.event_slug("Unknown"), "UNKNOWN")

    def test_variable_comparison_symbol_map(self):
        self.assertEqual(g.event_slug("Variable <="), "VARIABLE_LE")
        self.assertEqual(g.event_slug("Variable >="), "VARIABLE_GE")
        self.assertEqual(g.event_slug("Variable =="), "VARIABLE_EQ")
        self.assertEqual(g.event_slug("Variable !="), "VARIABLE_NE")
        self.assertEqual(g.event_slug("Variable <"), "VARIABLE_LT")
        self.assertEqual(g.event_slug("Variable >"), "VARIABLE_GT")
        # BattleConditionals' 0x0001 uses a bare "=" (not "==") — map it to EQ so
        # the enum reads VARIABLE_EQ rather than the bare, would-be-clearer-as-EQ
        # VARIABLE. Only "Variable =" (BC) carries a lone "=" (no event name does).
        self.assertEqual(g.event_slug("Variable ="), "VARIABLE_EQ")


class EventEnumMembers(unittest.TestCase):
    """Collision disambiguation + post-disambiguation uniqueness."""

    def test_unique_slug_used_verbatim(self):
        members = g.event_enum_members({0x2C: "Face Unit 2", 0x6B: "BG Sound"})
        self.assertEqual(members[0x2C], "FACE_UNIT_2")
        self.assertEqual(members[0x6B], "BG_SOUND")

    def test_collision_gets_hex_suffix_on_every_sharer(self):
        members = g.event_enum_members({0x12: "Unknown", 0x14: "Unknown"})
        self.assertEqual(members[0x12], "UNKNOWN_0X12")
        self.assertEqual(members[0x14], "UNKNOWN_0X14")

    def test_non_colliding_neighbour_keeps_bare_slug(self):
        # A unique slug next to a colliding family is NOT suffixed.
        members = g.event_enum_members(
            {0x12: "Unknown", 0x14: "Unknown", 0x2C: "Face Unit 2"}
        )
        self.assertEqual(members[0x2C], "FACE_UNIT_2")
        self.assertEqual(members[0x12], "UNKNOWN_0X12")

    def test_variable_family_stays_distinct_without_hex(self):
        members = g.event_enum_members(
            {0xA0: "Variable <=", 0xA1: "Variable >=", 0xA2: "Variable =="}
        )
        self.assertEqual(members[0xA0], "VARIABLE_LE")
        self.assertEqual(members[0xA2], "VARIABLE_EQ")


class CommittedCatalogGeneratesCleanEnum(unittest.TestCase):
    """Belt-and-suspenders against the real checked-in catalog: all 176
    instructions get a unique, valid-identifier member whose value is the byte."""

    def test_real_catalog_members(self):
        catalog = g.build_catalog(g.CATALOGS["event"])
        names_by_op = {
            int(h, 16): e["name"] for h, e in catalog["opcodes"].items()
        }
        members = g.event_enum_members(names_by_op,
                                       width=catalog["_opcode_width"])
        # Every catalog entry is covered (all 176 -> the 48 Unknown auto-skip).
        self.assertEqual(len(members), 176)
        # Members are unique valid identifiers.
        self.assertEqual(len(set(members.values())), 176)
        self.assertTrue(all(m.isidentifier() for m in members.values()))
        # The key IS the opcode byte, so a member's dispatch value == its byte.
        self.assertIn("FACE_UNIT_2", members.values())
        self.assertEqual(members[0x2C], "FACE_UNIT_2")

    def test_real_bc_catalog_members(self):
        # The sibling BattleConditionals mini-ISA (2-byte opcodes) generates a
        # clean enum too (ADR-0059 — same pattern on a second language).
        catalog = g.build_catalog(g.CATALOGS["bc"])
        names_by_op = {
            int(h, 16): e["name"] for h, e in catalog["opcodes"].items()
        }
        members = g.event_enum_members(names_by_op,
                                       width=catalog["_opcode_width"])
        self.assertEqual(len(set(members.values())), len(members))
        self.assertTrue(all(m.isidentifier() for m in members.values()))
        # Run Scenario is the result opcode the director keys on; value == opcode.
        self.assertEqual(members[0x0019], "RUN_SCENARIO")
        # The bare "=" equality op reads VARIABLE_EQ (via the "=" symbol map).
        self.assertEqual(members[0x0001], "VARIABLE_EQ")
        # HP% (0x0007/0x0008) collide to HP and get 2-byte hex suffixes.
        self.assertEqual(members[0x0007], "HP_0X0007")


if __name__ == "__main__":
    unittest.main()
