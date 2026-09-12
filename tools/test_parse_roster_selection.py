"""Tests for tools/parse_roster_selection.py.

The party/formation "sort list" screen resolves each cell's pose + palette from
three static tables in WORLD/WORLD.BIN (overlay @0x800E0000):

    DESC  0x8018DA44  84 x 12B   sprite descriptors (atlas U,V,W,H + tail)
    REMAP 0x8018DE34  256 B      class/job byte -> descriptor idx
    PAL   0x8018A168  256 x u16  CLUT selector -> palette id

Byte-verified vs the live pcsx dump; the resolver is checked against the 8/8
cell reconciliation in FORMATION_SCREEN.md §13.5. ROM-parsed per ADR-0001.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_roster_selection
"""

from __future__ import annotations

import re
import struct
import unittest

import parse_roster_selection as prs
from _repo_paths import godot_root, world_bin

WORLD = world_bin()
# Symlinked into the formation worktree from the game worktree; optional.
ORACLE = (godot_root().parent / "research" / "working_documents"
          / "roster_catalogue_captures" / "roster_selection_tables.txt")

# §13.5 golden: (cell, job, +0x72 class, +0x70 flags, expected idx, atlas U, V).
CELLS_13_5 = [
    (0, 0x01, 0x01, 0x80, 0x00, 0, 0),      # Ramza  (story: REMAP[1]=0)
    (1, 0x4A, 0x80, 0x90, 0x18, 96, 80),    # Squire male
    (2, 0x4A, 0x80, 0x90, 0x18, 96, 80),    # same pose, diff palette
    (3, 0x4B, 0x80, 0x90, 0x1A, 144, 80),   # job 0x4B male
    (4, 0x4A, 0x81, 0x50, 0x19, 120, 80),   # Squire female (+1)
    (5, 0x4A, 0x81, 0x50, 0x19, 120, 80),   # female
    (6, 0x4B, 0x81, 0x50, 0x1B, 168, 80),   # job 0x4B female
    (7, 0x04, 0x04, 0x81, 0x03, 72, 0),     # Delita (story: REMAP[4]=3)
]


class FormatConstantsTest(unittest.TestCase):
    """Tracer bullet: the table extents tile the overlay without gap/overlap."""

    def test_desc_region_ends_exactly_at_remap(self) -> None:
        # 84 x 12 = 0x3F0 -> the descriptor table butts right up to REMAP.
        self.assertEqual(prs.DESC_ADDR + prs.DESC_BYTES, prs.REMAP_ADDR)

    def test_file_offset_formula(self) -> None:
        self.assertEqual(prs.file_offset(prs.DESC_ADDR), 0xADA44)
        self.assertEqual(prs.file_offset(prs.REMAP_ADDR), 0xADE34)
        self.assertEqual(prs.file_offset(prs.PAL_ADDR), 0xAA168)


class ResolverTest(unittest.TestCase):
    """descriptor_index reproduces FUN_801256c8 on the §13.5 cells.

    Pure logic + the REMAP table -- runs against the real table when WORLD.BIN
    is present, else a tiny inline REMAP stub carrying just REMAP[1] and [4]."""

    def _remap(self) -> list[int]:
        if WORLD.exists():
            return prs.read_remap(WORLD.read_bytes())
        stub = [0] * 256
        stub[1] = 0x00   # story class 1 -> Ramza pose
        stub[4] = 0x03   # story class 4 -> Delita pose
        return stub

    def test_all_eight_cells_resolve(self) -> None:
        remap = self._remap()
        for cell, job, cls, flags, exp_idx, exp_u, exp_v in CELLS_13_5:
            female = bool(flags & prs.FEMALE_BIT)
            idx = prs.descriptor_index(job, cls, female, 0, remap)
            self.assertEqual(idx, exp_idx, f"cell {cell} idx")
            # Human cells: atlas U,V follow the (idx%10,idx//10) grid.
            self.assertEqual((idx % 10) * 24, exp_u, f"cell {cell} U")
            self.assertEqual((idx // 10) * 40, exp_v, f"cell {cell} V")

    def test_gender_bit_selects_adjacent_cell(self) -> None:
        remap = self._remap()
        male = prs.descriptor_index(0x4A, 0x80, False, 0, remap)
        female = prs.descriptor_index(0x4A, 0x80, True, 0, remap)
        self.assertEqual(female, male + 1)

    def test_monster_class_uses_special_subindex(self) -> None:
        # +0x72 == 0x82 -> idx = spc + 0x3D, bypassing job/remap entirely.
        idx = prs.descriptor_index(0x70, prs.MONSTER_CLASS, False, 5, [0] * 256)
        self.assertEqual(idx, 5 + prs.MONSTER_IDX_BASE)


@unittest.skipUnless(WORLD.exists(), f"WORLD.BIN not present at {WORLD}")
class DecodeByteExactTest(unittest.TestCase):
    """Decode pinned byte-for-byte to WORLD.BIN at the overlay offsets."""

    def setUp(self) -> None:
        self.data = WORLD.read_bytes()

    def test_descriptor_count_and_shape(self) -> None:
        descs = prs.read_descriptors(self.data)
        self.assertEqual(len(descs), 84)
        # idx 0 is the first Ramza pose at atlas origin, 24x40.
        self.assertEqual((descs[0]["u"], descs[0]["v"],
                          descs[0]["w"], descs[0]["h"]), (0, 0, 24, 40))

    def test_human_descriptors_follow_grid(self) -> None:
        descs = prs.read_descriptors(self.data)
        for idx in (0x00, 0x03, 0x18, 0x19, 0x1A, 0x1B):
            self.assertEqual((descs[idx]["u"], descs[idx]["v"]),
                             ((idx % 10) * 24, (idx // 10) * 40),
                             f"descriptor {idx:#x}")
            self.assertEqual((descs[idx]["w"], descs[idx]["h"]), (24, 40))

    def test_monster_descriptor_breaks_the_grid(self) -> None:
        # 0x52 (job 0x91) is a 48x48 monster cell -- the reason the port must
        # read u,v,w,h from the table, not recompute the human formula.
        d = prs.read_descriptors(self.data)[0x52]
        self.assertEqual((d["u"], d["v"], d["w"], d["h"]), (144, 136, 48, 48))

    def test_remap_and_palette_sizes(self) -> None:
        self.assertEqual(len(prs.read_remap(self.data)), 256)
        self.assertEqual(len(prs.read_palette_table(self.data)), 256)

    def test_remap_story_entries(self) -> None:
        remap = prs.read_remap(self.data)
        self.assertEqual(remap[0x01], 0x00)   # class 1 -> Ramza
        self.assertEqual(remap[0x04], 0x03)   # class 4 -> Delita


@unittest.skipUnless(ORACLE.exists(), f"oracle dump not linked at {ORACLE}")
class OracleByteMatchTest(unittest.TestCase):
    """The ROM-extracted tables equal the independent live pcsx dump, byte-for-byte."""

    def setUp(self) -> None:
        text = ORACLE.read_text()
        self.oracle = {
            label: bytes.fromhex(
                re.search(label + r"\s+([0-9A-Fa-f]+)", text).group(1))
            for label in ("DESC8018DA44", "REMAP8018DE34", "PAL8018A168")
        }
        self.data = WORLD.read_bytes()

    def _rom(self, addr: int, n: int) -> bytes:
        off = prs.file_offset(addr)
        return self.data[off:off + n]

    def test_descriptors_match_oracle(self) -> None:
        self.assertEqual(self._rom(prs.DESC_ADDR, prs.DESC_BYTES),
                         self.oracle["DESC8018DA44"][:prs.DESC_BYTES])

    def test_remap_matches_oracle(self) -> None:
        oracle = self.oracle["REMAP8018DE34"]
        self.assertEqual(self._rom(prs.REMAP_ADDR, len(oracle)), oracle)

    def test_palette_matches_oracle(self) -> None:
        oracle = self.oracle["PAL8018A168"]
        self.assertEqual(self._rom(prs.PAL_ADDR, len(oracle)), oracle)


if __name__ == "__main__":
    unittest.main()
