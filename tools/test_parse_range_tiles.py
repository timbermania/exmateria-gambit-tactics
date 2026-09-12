"""Unit tests for tools/parse_range_tiles.py — the feedback-HUD sprite metadata
(issue #88): the damage-digit strip and the status-bubble icon set that the
parser emits into RANGETILE.json alongside the existing tile + cursor rects.

Pure-geometry tests run on synthetic values; the real-asset classes validate
the measured cells against the on-disk RANGETILE.tga / retail BATTLE.BIN and
skip if those are absent (mirrors test_parse_placement.py).

Uses stdlib unittest so there's no pytest dep on the tools venv.

Run from tools/:
    uv run python -m unittest test_parse_range_tiles
"""

from __future__ import annotations

import unittest

import parse_range_tiles as p
import _repo_paths as rp


def _load_atlas_indices():
    """The committed RANGETILE.tga as a 256x256 grid of 4bpp indices
    (it is 8bpp grayscale, value = index * 17). Skips if the asset is absent."""
    tga = rp.assets_dir("sprites/textures") / "RANGETILE.tga"
    if not tga.exists():
        raise unittest.SkipTest(f"atlas missing: {tga}")
    from PIL import Image
    import numpy as np
    a = np.array(Image.open(tga))
    if a.ndim == 3:
        a = a[:, :, 0]
    return ((a.astype(int) + 8) // 17)


class FixedPitchCells(unittest.TestCase):
    """The shared fixed-pitch cell layout used for the digit strip: a row of
    `count` equal cells at `pitch_x` from an origin (glyphs nearly touch, so the
    strip is measured as fixed pitch from an origin, not split by gaps)."""

    def test_count_and_first_cell(self):
        cells = p.fixed_pitch_cells(168, 52, 8, 11, 8, 11)
        self.assertEqual(len(cells), 11)
        self.assertEqual(cells[0], {"x": 168, "y": 52, "w": 8, "h": 11})

    def test_pitch_advances_x_only(self):
        cells = p.fixed_pitch_cells(168, 52, 8, 11, 8, 11)
        self.assertEqual(cells[1]["x"], 176)
        self.assertEqual(cells[10]["x"], 168 + 10 * 8)
        self.assertTrue(all(c["y"] == 52 for c in cells))


class DigitSet(unittest.TestCase):
    """The damage/HP digit strip: glyphs 0-9 and '/', emitted as one cell per
    glyph with the measured atlas origin/pitch."""

    def test_glyphs_are_ten_digits_plus_slash(self):
        ds = p.digit_set()
        self.assertEqual(ds["glyphs"], "0123456789/")
        self.assertEqual(len(ds["cells"]), 11)

    def test_cells_use_measured_origin_and_pitch(self):
        ds = p.digit_set()
        self.assertEqual(ds["cells"][0]["x"], p.DIGIT_ORIGIN[0])
        self.assertEqual(ds["cells"][0]["y"], p.DIGIT_ORIGIN[1])
        # fixed pitch — last glyph ('/') sits at origin + 10*pitch
        self.assertEqual(ds["cells"][-1]["x"],
                         p.DIGIT_ORIGIN[0] + 10 * p.DIGIT_PITCH_X)
        # the strip stays inside the 256-wide atlas
        self.assertLessEqual(ds["cells"][-1]["x"] + ds["cells"][-1]["w"], 256)

    def test_number_clut_is_0x7d7c_single_pass(self):
        ds = p.digit_set()
        # The number is one textured pass through CLUT 0x7d7c (VRAM read), NOT a
        # two-layer shadow(0x7d7c)+fill(0x7c3c) render — corrected 2026-07-25.
        self.assertEqual(ds["clut"], 0x7D7C)
        self.assertNotIn("shadow_clut", ds)

    def test_number_clut_colors_match_vram(self):
        ds = p.digit_set()
        cols = ds["colors"]
        self.assertEqual(len(cols), 16)
        # idx0 transparent; idx2 white fill; idx1 dark outline (the ground-truth
        # entries the dmg_steady.png capture samples). 5->8 bit expanded.
        self.assertEqual(cols[0], [0, 0, 0, 0])
        self.assertEqual(cols[2], [239, 239, 239, 255])   # white fill
        self.assertEqual(cols[1], [41, 41, 33, 255])      # dark outline
        # idx5/6 are the cool-grey AA edges the capture shows.
        self.assertEqual(cols[6], [181, 189, 198, 255])


class ZodiacSet(unittest.TestCase):
    """The formation zodiac-sign glyphs (§14.3): 13 signs (Aries..Serpentarius)
    across two fixed-pitch atlas rows, one 24x20 cell per sign in reading order,
    emitted like the digit strip (cells + CLUT + colours)."""

    def test_thirteen_signs_in_reading_order(self):
        z = p.zodiac_set()
        self.assertEqual(len(z["names"]), 13)
        self.assertEqual(len(z["cells"]), 13)
        self.assertEqual(z["names"][0], "Aries")
        self.assertEqual(z["names"][6], "Libra")           # last of row 1
        self.assertEqual(z["names"][7], "Scorpio")         # first of row 2
        self.assertEqual(z["names"][-1], "Serpentarius")

    def test_cells_are_plausible_size_and_two_rows(self):
        z = p.zodiac_set()
        for c in z["cells"]:
            self.assertEqual((c["w"], c["h"]),
                             (p.ZODIAC_CELL_W, p.ZODIAC_CELL_H))
        # row 1 = 7 cells at y42 on a 24px pitch from x0; row 2 = 6 cells at y62
        self.assertEqual([c["y"] for c in z["cells"][:7]], [42] * 7)
        self.assertEqual([c["y"] for c in z["cells"][7:]], [62] * 6)
        self.assertEqual([c["x"] for c in z["cells"][:7]],
                         [i * p.ZODIAC_PITCH_X for i in range(7)])
        self.assertEqual([c["x"] for c in z["cells"][7:]],
                         [i * p.ZODIAC_PITCH_X for i in range(6)])
        # both strips stay inside the 256-wide atlas
        for c in z["cells"]:
            self.assertLessEqual(c["x"] + c["w"], 256)

    def test_clut_and_colors_default_to_number_palette(self):
        z = p.zodiac_set()
        # documented fallback: reuse the number CLUT until the panel menu CLUT is read
        self.assertEqual(z["clut"], p.DIGIT_CLUT)
        self.assertEqual(len(z["colors"]), 16)
        self.assertEqual(z["colors"][0], [0, 0, 0, 0])     # idx0 transparent


class IconCellsFromArrays(unittest.TestCase):
    """The status-bubble grid: BATTLE.BIN's parallel X/Y byte arrays map to
    atlas cells. BOTH bytes are already atlas texels — Y a row (176/188/200), X
    a column — so the mapping is the identity, not a snap onto a synthetic grid
    (AT_MARKER_RENDERING.md §8.2: the live GPU packet draws u=114, which is the
    ROM's own table byte for entry 8)."""

    def test_x_is_used_directly_as_atlas_column(self):
        # table X 0,16,30 are atlas columns 0,16,30 — the strip's first cell is
        # 16 wide and the rest are 14, so there is no single column pitch to snap to.
        cells = p.icon_cells_from_arrays([0, 16, 30], [176, 176, 176])
        self.assertEqual([c["x"] for c in cells], [0, 16, 30])

    def test_y_is_used_directly_as_atlas_row(self):
        cells = p.icon_cells_from_arrays([0, 0, 86], [176, 188, 200])
        self.assertEqual([c["y"] for c in cells], [176, 188, 200])

    def test_uniform_cell_size(self):
        cells = p.icon_cells_from_arrays([0], [176])
        self.assertEqual((cells[0]["w"], cells[0]["h"]),
                         (p.ICON_CELL_W, p.ICON_CELL_H))


class WordLabelSet(unittest.TestCase):
    """The vitals-readout word-labels (Hp/Mp/Ct/Lv./Exp.) — ROM-authoritative
    RANGETILE sprite cells decoded from the live GPU primitives the draw fn
    (0x801352BC) builds, NOT the earlier atlas segmentation. Each carries a UV
    rect, primitive kind (SPRT/POLY_FT4) and the shared text CLUT 0x7cbc."""

    def _by_name(self):
        return {l["name"]: l for l in p.word_label_set()["labels"]}

    def test_hp_cell_is_rom_box(self):
        hp = self._by_name()["Hp"]
        self.assertEqual((hp["x"], hp["y"], hp["w"], hp["h"]), (168, 32, 16, 9))

    def test_all_five_labels_present(self):
        labels = self._by_name()
        for name in ("Exp.", "Hp", "Mp", "Ct", "Lv."):
            self.assertIn(name, labels, f"missing word-label {name!r}")

    def test_y32_band_shares_baseline_and_clut(self):
        s = p.word_label_set()
        labels = {l["name"]: l for l in s["labels"]}
        self.assertEqual(s["clut"], 0x7cbc)
        # the four y=32-band labels sit on one baseline (sizes differ per glyph)
        self.assertTrue(all(labels[n]["y"] == 32
                            for n in ("Exp.", "Hp", "Mp", "Ct")))

    def test_primitive_kinds(self):
        labels = self._by_name()
        # confirmed via the GPU "disable textures for sprites" toggle
        for n in ("Hp", "Mp", "Ct"):
            self.assertEqual(labels[n]["prim"], "SPRT", f"{n} should be SPRT")
        for n in ("Lv.", "Exp."):
            self.assertEqual(labels[n]["prim"], "POLY_FT4", f"{n} should be POLY_FT4")


class DigitStripReproduces(unittest.TestCase):
    """Real-asset validation: the measured digit cells land on the actual
    glyphs in the committed RANGETILE.tga (skips if the atlas is absent)."""

    @classmethod
    def setUpClass(cls):
        cls.idx = _load_atlas_indices()

    def test_glyph_zero_block_matches_fixture(self):
        ds = p.digit_set()
        c = ds["cells"][0]
        block = [[int(self.idx[y, x]) for x in range(c["x"], c["x"] + c["w"])]
                 for y in range(c["y"], c["y"] + c["h"])]
        self.assertEqual(block, p.DIGIT_ZERO_FIXTURE)

    def test_every_digit_cell_has_texels(self):
        # no blank cell -> origin/pitch hit a glyph for all 11 entries
        for i, c in enumerate(p.digit_set()["cells"]):
            sub = self.idx[c["y"]:c["y"] + c["h"], c["x"]:c["x"] + c["w"]]
            self.assertTrue((sub > 0).any(), f"digit cell {i} is blank")


class ZodiacReproduces(unittest.TestCase):
    """Real-asset validation: the 13 zodiac cells land on non-blank glyph texels
    in the committed RANGETILE.tga (skips if the atlas is absent)."""

    @classmethod
    def setUpClass(cls):
        cls.idx = _load_atlas_indices()

    def test_every_zodiac_cell_has_texels(self):
        for i, c in enumerate(p.zodiac_set()["cells"]):
            sub = self.idx[c["y"]:c["y"] + c["h"], c["x"]:c["x"] + c["w"]]
            self.assertTrue((sub > 0).any(), f"zodiac cell {i} is blank")


class WordLabelsReproduce(unittest.TestCase):
    """Real-asset validation: the measured word-label cells land on the actual
    glyphs in the committed RANGETILE.tga (skips if the atlas is absent)."""

    @classmethod
    def setUpClass(cls):
        cls.idx = _load_atlas_indices()
        cls.labels = p.word_label_set()["labels"]

    def test_every_label_cell_has_texels(self):
        for l in self.labels:
            sub = self.idx[l["y"]:l["y"] + l["h"], l["x"]:l["x"] + l["w"]]
            self.assertTrue((sub > 0).any(), f"label {l['name']!r} cell is blank")

    def test_hp_block_matches_fixture(self):
        hp = next(l for l in self.labels if l["name"] == "Hp")
        block = [[int(self.idx[y, x]) for x in range(hp["x"], hp["x"] + hp["w"])]
                 for y in range(hp["y"], hp["y"] + hp["h"])]
        self.assertEqual(block, p.HP_LABEL_FIXTURE)


class StatusIconsReproduce(unittest.TestCase):
    """Real-asset validation: the table-derived icon cells land on actual icon
    boxes in the committed atlas, and the table reads from the retail ROM."""

    @classmethod
    def setUpClass(cls):
        cls.idx = _load_atlas_indices()
        bb = rp.battle_bin()
        if not bb.exists():
            raise unittest.SkipTest(f"BATTLE.BIN missing: {bb}")
        cls.icons = p.status_icon_set(bb.read_bytes())

    def test_twenty_icons_across_three_rows(self):
        self.assertEqual(len(self.icons["cells"]), 20)
        rows = sorted({c["y"] for c in self.icons["cells"]})
        self.assertEqual(rows, [176, 188, 200])

    def test_every_icon_cell_has_texels(self):
        for i, c in enumerate(self.icons["cells"]):
            sub = self.idx[c["y"]:c["y"] + c["h"], c["x"]:c["x"] + c["w"]]
            self.assertTrue((sub > 0).any(), f"icon cell {i} at {c} is blank")

    def test_entry_eight_is_the_at_glyph(self):
        """CELL IDENTITY, not mere non-blankness. `test_every_icon_cell_has_texels`
        cannot discriminate a shifted strip: the icons abut on a 14px grid, so a cell
        off by one column lands on its neighbour and is still non-blank (the shifted
        (16,176) reads 123 non-zero texels, the true (0,176) reads 48 — both "pass").
        Entry 8's ROM bytes are (114,176), which is the "AT" glyph itself; shift the
        strip and it becomes the flare icon at (128,176)."""
        c = self.icons["cells"][8]
        self.assertEqual((c["x"], c["y"]), (114, 176))
        block = [[int(self.idx[y, x]) for x in range(c["x"], c["x"] + c["w"])]
                 for y in range(c["y"], c["y"] + c["h"])]
        self.assertEqual(block, p.AT_MARKER_FIXTURE_A)


class ActiveTurnMarker(unittest.TestCase):
    """The "AT" active-turn marker (AT_MARKER_RENDERING.md): carousel slot 21,
    whose cell is a CODE LITERAL (0x8007EF10/0x8007EF2C), not a table entry — the
    table's own entries 20/21 are (0,0xB0) and (0,0). Two 14x12 frames one row
    apart, flipped every 16 video frames, drawn through the menu CLUT 0x7D7C."""

    @classmethod
    def setUpClass(cls):
        cls.idx = _load_atlas_indices()
        cls.at = p.active_turn_set()

    def test_two_frames_one_row_apart(self):
        frames = self.at["frames"]
        self.assertEqual(len(frames), 2)
        self.assertEqual((frames[0]["x"], frames[0]["y"]), (114, 176))
        self.assertEqual((frames[1]["x"], frames[1]["y"]), (114, 188))
        for f in frames:
            self.assertEqual((f["w"], f["h"]), (p.ICON_CELL_W, p.ICON_CELL_H))

    def test_frames_are_the_at_glyph(self):
        expected = [p.AT_MARKER_FIXTURE_A, p.AT_MARKER_FIXTURE_B]
        for f, want in zip(self.at["frames"], expected):
            block = [[int(self.idx[y, x]) for x in range(f["x"], f["x"] + f["w"])]
                     for y in range(f["y"], f["y"] + f["h"])]
            self.assertEqual(block, want, f"AT frame at ({f['x']},{f['y']}) is not the glyph")

    def test_frames_differ(self):
        """The flip is a real shading change, so the fixtures must not be equal —
        otherwise `test_frames_are_the_at_glyph` would pass on a single-frame port."""
        self.assertNotEqual(p.AT_MARKER_FIXTURE_A, p.AT_MARKER_FIXTURE_B)

    def test_menu_clut_carried(self):
        self.assertEqual(self.at["clut"], p.DIGIT_CLUT)
        self.assertEqual(len(self.at["colors"]), 16)
        self.assertEqual(self.at["colors"][0], [0, 0, 0, 0])   # idx0 transparent

    def test_offsets_cover_every_shp_type(self):
        """The switch's jump table has eight entries (SHP types 0..7); anything >= 8
        falls through to the default row, so the map must be TOTAL over the eight and
        must name a fallback for the rest."""
        off = self.at["offsets"]
        self.assertEqual(sorted(off["shp_case"]),
                         sorted(["TYPE1", "TYPE2", "CYOKO", "MON", "OTHER",
                                 "RUKA", "ARUTE", "KANZEN"]))
        for case in off["shp_case"].values():
            self.assertIn(case, off["rows"])
        self.assertIn(off["fallback_case"], off["rows"])

    def test_every_row_has_a_reachable_default(self):
        """`anim_else` is the ONLY branch the port can reach today (the three anim ids
        are unnamed), so a row without one would be a row the marker cannot render."""
        for name, row in self.at["offsets"]["rows"].items():
            for cond, branches in row.items():
                self.assertIn("anim_else", branches, f"{name}/{cond} has no anim_else")

    def test_the_slope_test_cannot_move_the_common_case(self):
        """Measured consequence, and the reason decoding the anim ids is the unlock:
        with no special anim, human-scale is -40 whether the tile is raised or flat, so
        the slope branch changes nothing until an anim id can be answered."""
        human = self.at["offsets"]["rows"]["human"]
        self.assertEqual(human["raised"]["anim_else"], human["flat"]["anim_else"])
        self.assertEqual(human["flat"]["anim_else"], [0, -40])

    def test_the_distinct_heights_the_port_can_reach(self):
        """The five rows the SHP type alone selects — this is what actually ships."""
        off = self.at["offsets"]
        got = {shp: off["rows"][case][list(off["rows"][case])[0]]["anim_else"][1]
               for shp, case in off["shp_case"].items()}
        self.assertEqual(got, {"TYPE1": -40, "TYPE2": -40, "CYOKO": -50, "MON": -50,
                               "RUKA": -50, "OTHER": -25, "ARUTE": -70, "KANZEN": -120})

    def test_slope_mask_splits_the_twelve_slope_codes(self):
        """`tile[+3] & 0xE0` is NOT "is it sloped". Two of the port's twelve slope-type
        bytes (ConvexSoutheast 0x11, ConvexSouthwest 0x14) are zero under the mask and
        take the FLAT branch — which is what makes the mask exact rather than a guess."""
        mask = self.at["offsets"]["slope_mask"]
        self.assertEqual(mask, 0xE0)
        flat_under_mask = [b for b in (0x85, 0x52, 0x25, 0x58, 0x41, 0x11,
                                       0x14, 0x44, 0x96, 0x66, 0x69, 0x99)
                           if not (b & mask)]
        self.assertEqual(flat_under_mask, [0x11, 0x14])

    def test_bob_is_one_pixel_every_sixteen_frames(self):
        """§6.2: one bit — (counter >> 4) & 1 — picks the frame AND lifts 1px."""
        self.assertEqual(self.at["phase_frames"], 16)
        self.assertEqual(self.at["bob_px"], 1)


class BarSet(unittest.TestCase):
    """The HP/MP/CT vitals bars: one shared RANGETILE swatch + a per-stat CLUT,
    drawn as a value/max-width SPRT (confirmed via the GPU 'disable textures for
    sprites' toggle — the bars vanish, the POLY_FT4 numbers don't). Geometry +
    CLUT ids are module constants; colours are read from the ISO asset."""

    def test_three_stats_with_distinct_cluts(self):
        self.assertEqual([s["name"] for s in p.BAR_STATS], ["HP", "MP", "CT"])
        cluts = [s["clut"] for s in p.BAR_STATS]
        self.assertEqual(cluts, [0x7efc, 0x7f3c, 0x7f7c])
        self.assertEqual(len(set(cluts)), 3, "each stat needs its own CLUT")

    def test_swatch_and_fill_model(self):
        self.assertEqual(p.BAR_SWATCH, {"x": 216, "y": 202, "w": 38, "h": 6})
        self.assertEqual(p.BAR_FILL, "value/max")

    def test_bar_set_decodes_clut_colours(self):
        # synthetic asset: HP CLUT bytes at BAR_CLUT_OFFSET -> decoded RGBA
        asset = bytearray(p.BAR_CLUT_OFFSET + 3 * p.BAR_CLUT_STRIDE)
        asset[p.BAR_CLUT_OFFSET:p.BAR_CLUT_OFFSET + p.BAR_CLUT_STRIDE] = \
            bytes.fromhex(p.BAR_HP_CLUT_HEX)
        hp = p.bar_set(bytes(asset))["stats"][0]
        self.assertEqual(hp["name"], "HP")
        self.assertEqual(hp["colors"][0][3], 0)           # idx0 transparent
        # idx3 = BGR555 0x18c5 -> proper 5->8 expansion -> teal body
        self.assertEqual(hp["colors"][3][:3], (41, 49, 49))


class BarSwatchReproduces(unittest.TestCase):
    """Real-asset validation: the bar swatch lands on the actual rounded-bar
    texels in the committed RANGETILE.tga (skips if the atlas is absent)."""

    @classmethod
    def setUpClass(cls):
        cls.idx = _load_atlas_indices()

    def test_swatch_block_matches_fixture(self):
        sw = p.BAR_SWATCH
        block = [[int(self.idx[sw["y"] + j, sw["x"] + i]) for i in range(6)]
                 for j in range(6)]
        self.assertEqual(block, p.BAR_SWATCH_FIXTURE)


class SortHeaderSet(unittest.TestCase):
    """The formation sort-tab header (#174 v2, §12.3.2): four ROM CLUTs + the six
    sort labels + the two textured L2/R2 buttons, re-derived from the VRAM oracle.
    CLUT colours are decoded from a synthetic asset carrying the byte-exact
    fixtures; the label/button layout is validated as module constants."""

    def _synthetic_asset(self):
        # An asset large enough to hold the header CLUT block, filled with the
        # byte-exact fixtures at their real offsets.
        end = max(hc["off"] for hc in p.HEADER_CLUTS) + p.PAL_BYTES
        a = bytearray(end)
        for hc in p.HEADER_CLUTS:
            a[hc["off"]:hc["off"] + p.PAL_BYTES] = bytes.fromhex(p.HEADER_CLUT_HEX[hc["name"]])
        return bytes(a)

    def test_four_named_cluts_at_asset_tail(self):
        names = [c["name"] for c in p.HEADER_CLUTS]
        self.assertEqual(names, ["inactive_label", "active_label", "button", "button_pressed"])
        # asset offset == VRAM row mapping: asset + 0x9000 + (row-496)*32
        self.assertEqual([c["off"] for c in p.HEADER_CLUTS], [0x9000, 0x9040, 0x90a0, 0x9120])
        self.assertEqual([c["clut"] for c in p.HEADER_CLUTS], [0x7c3c, 0x7cbc, 0x7d7c, 0x7e7c])

    def test_cluts_decode_the_2tone_emboss(self):
        sh = p.sort_header_set(self._synthetic_asset())
        inactive = sh["cluts"]["inactive_label"]["colors"]
        active = sh["cluts"]["active_label"]["colors"]
        self.assertEqual(inactive[0][3], 0)                 # idx0 transparent
        # inactive idx1 = dark ink (48,40,32); idx4 = the bar's own tan (152,144,120)
        self.assertEqual(tuple(inactive[1][:3]), (49, 41, 33))
        self.assertEqual(tuple(inactive[4][:3]), (156, 148, 123))
        # active idx1 = white; idx4 = dark fill (the highlighted "Hp")
        self.assertEqual(tuple(active[1][:3]), (239, 239, 231))
        self.assertEqual(tuple(active[4][:3]), (33, 24, 16))

    def test_six_sort_labels_in_order(self):
        names = [l["name"] for l in p.HEADER_SORT_LABELS]
        self.assertEqual(names, ["Hp", "Mp", "Ct", "Lv.", "Exp.", "Br"])
        bf = p.HEADER_SORT_LABELS[-1]
        self.assertEqual(bf["x2_name"], "Fa")               # brave_faith pairs Br + Fa
        # every named cell must exist in WORD_LABELS (the atlas source of truth)
        wl = {l["name"] for l in p.WORD_LABELS}
        for l in p.HEADER_SORT_LABELS:
            self.assertIn(l["name"], wl)
            if "x2_name" in l:
                self.assertIn(l["x2_name"], wl)

    def test_buttons_are_textured_atlas_cells(self):
        b = p.HEADER_BUTTONS
        self.assertEqual(b["tpage"], 0x1F)                  # page (960,256), abr=0 opaque
        for side in ("left", "right"):
            pieces = b[side]["pieces"]
            frame = [pc for pc in pieces if pc[3] == 128]   # v=128 -> the 3-slice frame
            self.assertEqual(len(frame), 3)
            caps = [pc for pc in pieces if pc[3] != 128]     # captions at v<128
            self.assertTrue(len(caps) >= 2)


class SortHeaderClutsReproduce(unittest.TestCase):
    """Real-ISO validation: the four header CLUTs land byte-exact in the LBA 0xE68
    asset palette tail (skips if the ISO is absent)."""

    @classmethod
    def setUpClass(cls):
        iso = p.iso_path(None)
        if not iso.exists():
            raise unittest.SkipTest(f"ISO missing: {iso}")
        cls.asset = p.read_lba(iso, p.TEXTURE_LBA, p.ASSET_SECTORS)

    def test_each_header_clut_matches_fixture(self):
        for hc in p.HEADER_CLUTS:
            got = self.asset[hc["off"]:hc["off"] + p.PAL_BYTES].hex()
            self.assertEqual(got, p.HEADER_CLUT_HEX[hc["name"]],
                             f"{hc['name']} (0x{hc['clut']:x}) drifted at +{hc['off']:#x}")


class DetailPagerButtons(unittest.TestCase):
    """The Status/detail screen's own ◄L1 / R1► unit-pager buttons (§15.22, RE
    round 18). Same RANGETILE page + button CLUT as the formation L2/R2 buttons,
    but at the Status corners and with single-cell captions (the 1-vs-2 digit is
    a compositing difference, not separate art). Layout validated as data."""

    def test_page_and_cluts(self):
        s = p.detail_pager_set()
        self.assertEqual(s["tpage"], 0x1F)                  # RANGETILE (960,256), abr=0 opaque
        self.assertEqual(s["clut"], 0x7D7C)                 # foreground button CLUT (== L2/R2)
        self.assertEqual(s["clut_bg"], 0x7DFC)              # §15.21 backgrounded twin (blue)

    def test_corner_origins(self):
        s = p.detail_pager_set()
        # real screen space (draw-env +0x80 X bias already removed): hard into the corners,
        # further out than the formation L2/R2 (x 38/194).
        self.assertEqual((s["left"]["origin_x"], s["left"]["y"]), (12, 14))
        self.assertEqual((s["right"]["origin_x"], s["right"]["y"]), (224, 14))

    def test_frame_is_shared_three_slice(self):
        s = p.detail_pager_set()
        for side in ("left", "right"):
            frame = [pc for pc in s[side]["pieces"] if pc[3] == 128]   # v=128 → 3-slice frame
            self.assertEqual(len(frame), 3)
            self.assertEqual([pc[2] for pc in frame], [176, 184, 180])  # leftcap/body/rightcap u

    def test_single_cell_captions(self):
        s = p.detail_pager_set()
        left_caps = [pc for pc in s["left"]["pieces"] if pc[3] != 128]
        right_caps = [pc for pc in s["right"]["pieces"] if pc[3] != 128]
        self.assertEqual(len(left_caps), 1)                 # ◄L1: ONE 16x5 cell
        self.assertEqual(len(right_caps), 1)                # R1►: ONE 15x5 cell
        self.assertEqual(tuple(left_caps[0]), (4, 5, 218, 93, 16, 5))
        self.assertEqual(tuple(right_caps[0]), (5, 5, 218, 88, 15, 5))


if __name__ == "__main__":
    unittest.main()
