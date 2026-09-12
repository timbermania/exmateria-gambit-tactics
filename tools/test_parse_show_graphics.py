"""Tests for tools/parse_show_graphics.py.

The {7D} ShowGraphic effect is driven by the EVENT/ETC.OUT overlay worker
(base VA 0x801BF000). ETC.OUT carries a 13-row descriptor table at file
offset 0x18A8 (stride 0x20) that maps a graphic row -> {format, disc sector,
size, upload RECT, screen template}. The parser must regenerate every render
parameter deterministically from ETC.OUT + the graphic .BIN files -- no live
VRAM/savestate capture. Full RE + provenance:

    research/working_documents/scenario_1_captures/show_graphic_op7d_decode.md
    (Part III -- the ISO-deterministic parse recipe; every constant is cited)

These asserts byte-match the recipe against the real ETC.OUT / CHAPTER*.BIN in
the local extract, so the parser is pinned to the disc, not to imagined shapes.

Stdlib unittest. Run from tools/:
    uv run python -m unittest test_parse_show_graphics
"""

from __future__ import annotations

import unittest

import parse_show_graphics as sg
from _repo_paths import event_dir


ETC_OUT = event_dir() / "ETC.OUT"
CHAPTER1 = event_dir() / "CHAPTER1.BIN"


@unittest.skipUnless(ETC_OUT.exists(), f"ETC.OUT not present at {ETC_OUT}")
class DescriptorTableTest(unittest.TestCase):
    """Tracer bullet: the 13-row table decodes with row 0 = chapter1."""

    def test_truncated_etc_out_degrades_to_empty(self) -> None:
        # A short/unexpected ETC.OUT must not raise: the chapter PNGs decode
        # from CHAPTER*.BIN independently, so a bad table degrades to "no render
        # params" rather than aborting the whole asset regeneration.
        self.assertEqual(sg.parse_descriptor_table(b""), [])
        self.assertEqual(sg.parse_descriptor_table(b"\x00" * 0x100), [])

    def test_table_has_13_rows_and_row0_is_chapter1(self) -> None:
        rows = sg.parse_descriptor_table(ETC_OUT.read_bytes())
        self.assertEqual(len(rows), 13)
        r0 = rows[0]
        # chapter1: fmt-0 card, disc sector 0x1690, one 64x64 16bpp cell (0x2000 B).
        self.assertEqual(r0.format, 0)
        self.assertEqual(r0.sector, 0x1690)
        self.assertEqual(r0.size, 0x2000)

    def test_rect_derefs_to_upload_rectangle(self) -> None:
        data = ETC_OUT.read_bytes()
        rows = sg.parse_descriptor_table(data)
        # Chapters share one 64x64 upload cell at VRAM (384,0).
        self.assertEqual(sg.deref_rect(data, rows[0].rect_va), (384, 0, 64, 64))
        # The END-still (row 7, fmt-1) uploads a 128x256 cell.
        self.assertEqual(sg.deref_rect(data, rows[7].rect_va), (384, 0, 128, 256))
        # Movie rows (fmt-2) have a null RECT pointer -> None.
        self.assertIsNone(sg.deref_rect(data, rows[8].rect_va))

    def test_operand_maps_to_row_minus_one(self) -> None:
        # The BATTLE setup decrements the {7D} operand before ETC.OUT indexes
        # the table, so row = operand - 1 (III.2). Ground truth: operand 1
        # loaded chapter1.bin = row 0.
        self.assertEqual(sg.row_for_operand(0x01), 0)   # CHAPTER1
        self.assertEqual(sg.row_for_operand(0x07), 6)   # GAMEOVER (fmt-0, big)
        self.assertEqual(sg.row_for_operand(0x0C), 11)  # END5
        # Operand 0 (or below 1) has no row.
        self.assertIsNone(sg.row_for_operand(0x00))
        # World-map backgrounds (operand >= 0x10) are NOT in this battle table.
        self.assertIsNone(sg.row_for_operand(0x10))

    def test_template_grow_limit_is_248(self) -> None:
        # The reveal wipe grows to the card content width, stored at template
        # +0x1C (III.4). All fmt-0 chapters share the same template -> 248.
        data = ETC_OUT.read_bytes()
        rows = sg.parse_descriptor_table(data)
        self.assertEqual(sg.template_grow_limit(data, rows[0].tmpl_va), 248)

    def test_template_screen_top_is_78(self) -> None:
        # The card is NOT centered: ETC.OUT builder FUN_801bf3e0 places every
        # vertex Y = template(+0x0A) + 0x80 (128). The chapter template's min Y
        # field is -50, so the card's on-screen top row is -50 + 128 = 78 (of a
        # 240-tall framebuffer) -- upper third, not screen centre.
        data = ETC_OUT.read_bytes()
        rows = sg.parse_descriptor_table(data)
        self.assertEqual(sg.template_screen_top(data, rows[0].tmpl_va), 78)

    def test_template_screen_top_none_for_null_template(self) -> None:
        # Movie/END rows have a null template pointer -> None (not a struct.error
        # or a bogus top=0), so the manifest omits the screen block and the
        # controller falls back to a safe centred placement.
        data = ETC_OUT.read_bytes()
        rows = sg.parse_descriptor_table(data)
        self.assertIsNone(sg.template_screen_top(data, rows[8].tmpl_va))


@unittest.skipUnless(CHAPTER1.exists(), f"CHAPTER1.BIN not present at {CHAPTER1}")
class ChapterClutTest(unittest.TestCase):
    """The chapter card's 16-entry grayscale CLUT is embedded at file 0x1FE0."""

    def test_clut_is_grayscale_ramp_idx0_transparent(self) -> None:
        clut = sg.parse_chapter_clut(CHAPTER1.read_bytes())
        self.assertEqual(len(clut), 16)
        # idx0 = 0x0000 = the transparent background (additive blend => nothing).
        self.assertEqual(clut[0], 0x0000)
        # idx15 = 0xFFFF = the white text peak.
        self.assertEqual(clut[15], 0xFFFF)
        # Monotonically increasing grayscale ramp in between.
        self.assertEqual(clut, sorted(clut))


@unittest.skipUnless(ETC_OUT.exists(), f"ETC.OUT not present at {ETC_OUT}")
class ChapterRenderParamsTest(unittest.TestCase):
    """The fmt-0 render-params block the manifest carries per graphic id.

    Every value is ISO-sourced (III.4/III.5): the grow-limit from the template,
    the phase/grey/edge/step constants from ETC.OUT's builder+loop, the dual
    additive/subtractive pass structural. The controller consumes these so the
    whole effect regenerates from files -- no framebuffer capture.
    """

    def test_chapter1_render_params(self) -> None:
        data = ETC_OUT.read_bytes()
        row = sg.parse_descriptor_table(data)[sg.row_for_operand(0x01)]
        p = sg.chapter_render_params(data, row)
        self.assertEqual(p["format"], 0)
        anim = p["animation"]
        self.assertEqual(anim["grow_limit"], 248)   # from the template (ISO)
        self.assertEqual(anim["grow_step"], 1)       # _DAT_80165f88 static-init
        self.assertEqual(anim["hold_frames"], 80)    # 0x50
        self.assertEqual(anim["fade_frames"], 128)   # 0x80
        self.assertEqual(anim["grey"], 128)          # 0x80 vertex grey
        self.assertEqual(anim["edge"], 32)           # 0x20 soft-edge kernel
        screen = p["screen"]
        self.assertEqual(screen["top"], 78)          # upper third, not centre
        self.assertEqual(screen["height"], 16)
        self.assertEqual(screen["ref_h"], 240)
        passes = p["passes"]
        self.assertTrue(passes["additive"])
        self.assertTrue(passes["subtractive"])
        self.assertEqual(passes["shadow_offset"], [1, 1])


if __name__ == "__main__":
    unittest.main()
