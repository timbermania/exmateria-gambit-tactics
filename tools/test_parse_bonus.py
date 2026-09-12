"""Tests for tools/parse_bonus.py — the {78} results/intro screen assets.

The screens `{78} Display Conditions` dispatches to draw from TWO disc files, and
this pins the parser to both of them rather than to imagined shapes:

    EVENT/BONUS.BIN    36 pages of 0x6800; rows 0-127 the results font sheet (only
                       TWO variants across the 36), rows 128-199 the per-battle
                       victory-condition banner, and one palette block shared by
                       every page.
    EVENT/REQUIRE.OUT  the results overlay, loaded at VA 0x801BF000 — the same base
                       tools/parse_show_graphics.py reads EVENT/ETC.OUT at. It
                       carries the glyph metric table, the cumulative string index,
                       the per-record colour records and the banner screen's tables.

⚠️ The load base is the load-bearing claim. Get it wrong and every table below
decodes to plausible-looking garbage, so the asserts anchor on values that were
read INDEPENDENTLY out of RAM in BATTLE_RESULTS_SCREEN.md (§4.2's decoded
"CONGRATULATIONS!" records, §4B's string index, §6's line-2 colours, §13's six
banner records). Matching them from the file is what proves the base.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_bonus
"""

from __future__ import annotations

import unittest

import parse_bonus as pb
from _repo_paths import event_dir


BONUS = event_dir() / "BONUS.BIN"
REQUIRE = event_dir() / "REQUIRE.OUT"


@unittest.skipUnless(REQUIRE.exists(), f"REQUIRE.OUT not present at {REQUIRE}")
class OverlayTableTest(unittest.TestCase):
    """The overlay's tables, read off the disc image at VA 0x801BF000."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.ov = pb.Overlay(REQUIRE.read_bytes())
        cls.t = pb.read_tables(cls.ov)

    def test_string_index_is_the_cumulative_table_read_out_of_ram(self) -> None:
        # §4B: `00 06 16 20 27 32 39 46 47 48 4A 51` — 11 strings + sentinel, and
        # string n owns glyph records tab[n]..tab[n+1]-1.
        firsts = [s["first"] for s in self.t["strings"]]
        self.assertEqual(firsts, [0, 6, 22, 32, 39, 50, 57, 70, 71, 72, 74])
        counts = {s["name"]: s["count"] for s in self.t["strings"]}
        self.assertEqual(counts["READY!"], 6)
        self.assertEqual(counts["CONGRATULATIONS!"], 16)
        self.assertEqual(counts["BONUS MONEY"], 10)
        self.assertEqual(counts["This Battle Is Complete!"], 1)
        self.assertEqual(len(self.t["glyphs"]), 81)

    def test_congratulations_records_match_the_ram_decode(self) -> None:
        # §4.2 decoded records 6..21 against the ss4 display list and every one of
        # the sixteen predicted screen x matched. Same table, from the file.
        want = {
            6: [16, 0, 16, 24, -114, -40],    # C
            7: [192, 0, 16, 24, -98, -40],    # O
            8: [176, 0, 16, 24, -83, -40],    # N
            9: [80, 0, 16, 24, -67, -40],     # G
            10: [224, 0, 16, 24, -52, -40],   # R
            11: [176, 24, 17, 24, -37, -40],  # A — the wide glyph, moved to row 1
            21: [146, 24, 10, 24, 104, -40],  # ! — a 16 px cell trimmed to its ink
        }
        for i, rec in want.items():
            self.assertEqual(self.t["glyphs"][i], rec, f"glyph record {i}")
        # Screen placement is (128 + dx, 120 + dy): record 6 lands at x 14, y 80.
        cx, cy = 128, 120
        self.assertEqual((cx + self.t["glyphs"][6][4], cy + self.t["glyphs"][6][5]), (14, 80))

    def test_line_two_is_one_pre_composed_blit_with_a_diagonal_gradient(self) -> None:
        # §6: ONE 128x32 quad at screen (64, 136) from uv (32, 80), TL/BR green and
        # TR/BL gold — NOT a font run, which is why a port that renders it from the
        # font will not match.
        rec = self.t["glyphs"][70]
        self.assertEqual(rec, [32, 80, 128, 32, -64, 16])
        self.assertEqual((128 + rec[4], 120 + rec[5]), (64, 136))
        col = self.t["glyph_colors"][70]
        self.assertTrue(col["gouraud"])
        self.assertEqual(col["corners"], [[48, 128, 128], [128, 128, 88],
                                          [128, 128, 88], [48, 128, 128]])

    def test_the_settled_glyph_gradient_is_the_x128_base(self) -> None:
        # §4.3/§5.1: top (98,78,0), bottom (148,128,208) on every CONGRATULATIONS
        # glyph, held at L = 128 = 1.0 — the table is static and the FADE scales it.
        for i in range(6, 22):
            self.assertEqual(self.t["glyph_colors"][i]["corners"],
                             [[98, 78, 0], [98, 78, 0], [148, 128, 208], [148, 128, 208]],
                             f"glyph {i} gradient")

    def test_the_gil_row_is_flat_not_gouraud(self) -> None:
        # §8.2: the reel's packets are POLY_FT4 (flat + textured) at a neutral
        # 0x808080 — the reel does NOT use the glyph gradient.
        for i in range(32, 39):
            col = self.t["glyph_colors"][i]
            self.assertFalse(col["gouraud"], f"glyph {i} must be flat")
            self.assertEqual(col["corners"], [[128, 128, 128]] * 4)
        # Digit cells are 13x23 at v=49 in the static layout; the comma is its own
        # narrow 6x10 cell, which is why the settled row's pitch is not uniform.
        self.assertEqual(self.t["glyphs"][32][:4], [0, 49, 13, 23])
        self.assertEqual(self.t["glyphs"][34][:4], [130, 64, 6, 10])

    def test_the_banner_is_two_lines_of_three_passes(self) -> None:
        # §13: six 232x31 blits — two subtractive shadow passes one pixel apart and
        # one additive gouraud pass, per line. Rows 128/160 of the page, reached by
        # the builder storing `record.v - 128` into an UNSIGNED byte.
        b = self.t["banner"]
        self.assertEqual(len(b), 6)
        self.assertEqual([r["abr"] for r in b], [2, 2, 1, 2, 2, 1])
        self.assertEqual([r["metric"] for r in b], [
            [16, 0, 232, 31, -122, -100], [16, 0, 232, 31, -121, -99],
            [16, 0, 232, 31, -122, -100], [16, 32, 232, 31, -121, -63],
            [16, 32, 232, 31, -122, -64], [16, 32, 232, 31, -122, -64],
        ])
        for i in (0, 1, 3, 4):
            self.assertFalse(b[i]["gouraud"], f"shadow pass {i} is flat")
            self.assertEqual(b[i]["corners"], [[128, 128, 128]] * 4)
        for i in (2, 5):
            self.assertTrue(b[i]["gouraud"], f"text pass {i} is gouraud")
            self.assertEqual(b[i]["corners"], [[88, 58, 10], [88, 58, 10],
                                               [168, 148, 120], [168, 148, 120]])
        # (v - 128) & 0xFF: v=0 -> sheet row 128, v=32 -> row 160.
        self.assertEqual([(r["metric"][1] - 128) & 0xFF for r in b],
                         [128, 128, 128, 160, 160, 160])

    def test_the_dim_colour_is_the_one_76_paints_with(self) -> None:
        # `0x801D0078..7A` — re-read into every {76} diamond and into its settled
        # quad every frame, and the same RGB the results overlay's tint measured.
        self.assertEqual(self.t["dim_rgb"], [48, 40, 16])

    def test_a_wrong_load_base_is_rejected_rather_than_decoded(self) -> None:
        with self.assertRaises(SystemExit):
            pb.Overlay(b"").metric(pb.METRICS_VA, 0)


@unittest.skipUnless(BONUS.exists(), f"BONUS.BIN not present at {BONUS}")
class BonusBinTest(unittest.TestCase):
    """BONUS.BIN's page geometry — §14."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.data = BONUS.read_bytes()
        cls.pages = [cls.data[i * pb.PAGE_SIZE:(i + 1) * pb.PAGE_SIZE]
                     for i in range(pb.PAGE_COUNT)]

    def test_thirty_six_pages_of_0x6800(self) -> None:
        self.assertEqual(len(self.data), pb.PAGE_SIZE * pb.PAGE_COUNT)
        # 0x6800 is exactly 13 x 2048, which is why 0x801C3AB0's argument is an LBA.
        self.assertEqual(pb.PAGE_SIZE, pb.DISC_LBA_STRIDE * 2048)

    def test_one_palette_block_shared_by_every_page(self) -> None:
        block = self.pages[0][pb.CLUT_DIGITS_OFF:pb.CLUT_LETTERS_OFF + 32]
        for i, p in enumerate(self.pages):
            self.assertEqual(p[pb.CLUT_DIGITS_OFF:pb.CLUT_LETTERS_OFF + 32], block,
                             f"page {i} CLUTs")

    def test_only_page_one_carries_a_different_results_sheet(self) -> None:
        # The game-complete sheet: line 2 reads "This Game Is Complete!". It is the
        # page `0x801CA6C8` loads when `0x8013B590(0x27) == 0x145`.
        sheet_bytes = pb.RESULTS_H * (pb.SHEET_W // 2)
        variants: dict[bytes, list[int]] = {}
        for i, p in enumerate(self.pages):
            variants.setdefault(p[:sheet_bytes], []).append(i)
        self.assertEqual(sorted(len(v) for v in variants.values()), [1, 35])
        self.assertEqual([v for v in variants.values() if len(v) == 1], [[1]])

    def test_the_objective_table_covers_every_page(self) -> None:
        self.assertEqual(len(pb.OBJECTIVES), pb.PAGE_COUNT)

    def test_the_sheet_decodes_with_index_zero_transparent(self) -> None:
        pal = pb._palette(self.pages[0], pb.CLUT_LETTERS_OFF)
        img = pb.decode_sheet(self.pages[0], pal, 0, pb.RESULTS_H)
        self.assertEqual(img.size, (pb.SHEET_W, pb.RESULTS_H))
        raw = img.tobytes()                      # RGBA, 4 bytes per texel
        alphas = set(raw[3::4])
        self.assertEqual(alphas, {0, 255})
        # The sheet is mostly background, and the ink is a minority of the page.
        inked = raw[3::4].count(255)
        self.assertTrue(0 < inked < img.size[0] * img.size[1] // 2, f"inked={inked}")


if __name__ == "__main__":
    unittest.main()
