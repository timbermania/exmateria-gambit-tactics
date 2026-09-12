"""Unit tests for tools/parse_frame_font.py — the HUD number font extracted from
EVENT/FRAME.BIN.

FFT composes the bottom-left vitals `cur/max` (and `Lv.`/`Exp.`) digits at runtime
by blitting a blocky two-tone menu/number font into a scratch VRAM page. The clean
source of that font is EVENT/FRAME.BIN, which holds TWO authored digit sets — a
BIG set (the `cur` size) and a SMALL set (the `max` size). See
docs/hud-number-font.md for the full provenance + the dynamic-analysis
faithfulness protocol.

Pure-geometry tests run on the measured cell tables; the real-asset classes
validate the extracted glyphs against the on-disk FRAME.BIN and the committed
dynamic scratch captures, and skip if those are absent (mirrors
test_parse_range_tiles.py).

Run from tools/:
    uv run python -m unittest test_parse_frame_font
"""

from __future__ import annotations

import gzip
import unittest

import parse_frame_font as p
import _repo_paths as rp


def _frame_path():
    f = rp.fft_extract_root() / "EVENT" / "FRAME.BIN"
    if not f.exists():
        raise unittest.SkipTest(f"FRAME.BIN missing: {f}")
    return f


def _scratch_reader(name: str):
    """A reader into a committed dynamic scratch-page capture (gzipped 1 MB VRAM
    dump). Returns nib(u, v) → 4bpp index at tpage 0x07 (VRAM halfword 448,0).
    Skips if the capture is absent."""
    cap = (rp.godot_root() / "tools" / "hud_digit_captures" / name)
    if not cap.exists():
        raise unittest.SkipTest(f"scratch capture missing: {cap}")
    data = gzip.open(cap, "rb").read()

    def nib(u: int, v: int) -> int:
        o = (v * 1024 + (448 + (u >> 2))) * 2
        w = data[o] | (data[o + 1] << 8)
        return (w >> (4 * (u & 3))) & 0xF
    return nib


def _palette_set(block) -> set:
    return {v for row in block for v in row if v}


def _idx4_frac(block) -> float:
    ink = sum(1 for row in block for v in row if v)
    four = sum(1 for row in block for v in row if v == 4)
    return four / ink if ink else 0.0


class BigDigitSet(unittest.TestCase):
    """The BIG (`cur`-size) digit set: glyphs 0-9 and '/', one cell per glyph at
    the measured FRAME.BIN origins."""

    def test_glyphs_are_ten_digits_plus_slash(self):
        ds = p.big_digit_set()
        self.assertEqual(ds["glyphs"], "0123456789/")
        self.assertEqual(len(ds["cells"]), 11)

    def test_cells_stay_inside_frame_bounds(self):
        ds = p.big_digit_set()
        for c in ds["cells"]:
            self.assertGreaterEqual(c["x"], 0)
            self.assertLessEqual(c["x"] + c["w"], 256)


class BigFontIsFaithfulToDynamicCapture(unittest.TestCase):
    """Dynamic-analysis faithfulness: the BIG digit extracted from FRAME.BIN must
    carry the same palette SIGNATURE the PSX renderer actually composed into the
    scratch page — index set {1,2,3,4} with a strong index-4 outline. That
    signature is structurally distinct from the RANGETILE damage font (indices
    {1,2,3,5}, no index 4), which proves the HUD font is FRAME.BIN, not the
    range-tile strip. (docs/hud-number-font.md, faithfulness protocol.)"""

    @classmethod
    def setUpClass(cls):
        grid = p.read_frame_indices(_frame_path())
        c0 = p.big_digit_set()["cells"][0]            # glyph '0'
        cls.frame0 = p.cell_block(grid, c0)
        nib = _scratch_reader("scratchpad_sstate1.bin.gz")  # sstate1 has '0'
        cls.scratch0 = [[nib(159 + x, y) for x in range(9)] for y in range(11)]

    def test_palette_signature_matches_capture(self):
        self.assertEqual(_palette_set(self.frame0), _palette_set(self.scratch0))
        self.assertEqual(_palette_set(self.frame0), {1, 2, 3, 4})

    def test_has_strong_index4_outline_like_capture(self):
        # both the FRAME source and the live capture draw a thick index-4 border
        self.assertGreater(_idx4_frac(self.frame0), 0.3)
        self.assertGreater(_idx4_frac(self.scratch0), 0.3)


class BigZeroReproduces(unittest.TestCase):
    """Reproducibility fixture: the big '0' glyph at the measured origin is an
    exact, known texel block. Fails loud if an origin/cell ever drifts (wrong
    file / wrong coordinates)."""

    # glyph '0', BIG set — 8x16 indices (descriptor V=0,W=8,H=16). The '0' body
    # sits at rows 4-11 with transparent top/bottom padding; validated against the
    # dynamic capture's palette signature.
    FIXTURE = [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 4, 4, 4, 4, 0, 0],
        [0, 4, 2, 1, 1, 2, 4, 0],
        [4, 2, 1, 3, 3, 1, 2, 4],
        [4, 1, 2, 4, 4, 2, 1, 4],
        [4, 1, 2, 4, 4, 2, 1, 4],
        [4, 2, 1, 3, 3, 1, 2, 4],
        [0, 4, 2, 1, 1, 2, 4, 0],
        [0, 0, 4, 4, 4, 4, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
    ]

    def test_big_zero_block_matches_fixture(self):
        grid = p.read_frame_indices(_frame_path())
        block = p.cell_block(grid, p.big_digit_set()["cells"][0])
        self.assertEqual(block, self.FIXTURE)


class GeometryMatchesDisassembly(unittest.TestCase):
    """Lock the CODE-CONFIRMED glyph grid so it can never drift back to the old
    hand-measured origins. The BATTLE.BIN digit routines compute source U as
    `base + digit*pitch`: big `FUN_8014ac30` uses `digit*8 + 0x78`, small
    `FUN_8014aec0` uses `digit*6 + 0x78`. See docs/frame-bin-number-font.md."""

    def test_base_u_is_0x78(self):
        self.assertEqual(p.BASE_U, 0x78)  # 120

    def test_big_origins_are_pitch_8_from_120(self):
        xs = [c["x"] for c in p.big_digit_set()["cells"]]
        self.assertEqual(xs, [120 + 8 * i for i in range(11)])
        self.assertEqual(p.big_digit_set()["cells"][0]["w"], 8)
        self.assertEqual(p.big_digit_set()["cells"][0]["h"], 16)

    def test_small_origins_are_pitch_6_from_120(self):
        # 13 pitch-6 strip glyphs: 0-9, '/', the roster CT dash '-' (index 11, U=186),
        # and '%' (index 12, U=192). The '+' (U=200) and dot-leader '…' are appended
        # OFF-grid special cells, so check only the strip prefix here.
        strip = p.small_digit_set()["cells"][:len(p.SMALL_GLYPHS)]
        xs = [c["x"] for c in strip]
        self.assertEqual(xs, [120 + 6 * i for i in range(13)])
        # user-validated exact cell for '0'..'2'
        self.assertEqual(xs[0:3], [120, 126, 132])
        c0 = p.small_digit_set()["cells"][0]
        self.assertEqual((c0["w"], c0["h"], c0["y"]), (6, 10, 16))


class SmallDigitSet(unittest.TestCase):
    """The SMALL (`max`-size) digit set: the HUD draws `cur` big and `max` small;
    FFT authored BOTH sizes in FRAME.BIN (not one scaled). Same glyphs, same
    blocky font family, shorter cells."""

    def test_glyphs_are_ten_digits_plus_slash_and_dash(self):
        ds = p.small_digit_set()
        # 0-9, '/', the roster CT dash '-', '%', the equip-delta '+' marker, and the
        # stats-band dot-leader '…' (the BIG set stops at '/').
        self.assertEqual(ds["glyphs"], "0123456789/-%+…")
        self.assertEqual(len(ds["cells"]), 15)
        # '+' must be its OFF-grid cell (U=200 = 0xC8), not a pitch-6 strip index.
        plus_cell = ds["cells"][ds["glyphs"].index("+")]
        self.assertEqual(plus_cell["x"], 200)

    def test_cells_are_shorter_than_big(self):
        # the whole reason there are two sets: max is a smaller authored size
        self.assertLess(p.small_digit_set()["cells"][0]["h"],
                        p.big_digit_set()["cells"][0]["h"])


class SmallFontIsSameBlockyFamily(unittest.TestCase):
    """The SMALL set is the same blocky FRAME font as the (dynamically-validated)
    BIG set: index signature {1,2,3,4} with a strong index-4 outline — NOT the
    soft RANGETILE damage font."""

    @classmethod
    def setUpClass(cls):
        grid = p.read_frame_indices(_frame_path())
        c0 = p.small_digit_set()["cells"][0]
        cls.small0 = p.cell_block(grid, c0)

    def test_palette_signature_is_blocky_family(self):
        # the family discriminator vs the soft RANGETILE font: a strong index-4
        # outline and NO index 5 (rangetile's tell). A small glyph may use a
        # subset of {1,2,3,4} (less antialiasing) — that's fine.
        sig = _palette_set(self.small0)
        self.assertIn(4, sig)
        self.assertNotIn(5, sig)
        self.assertTrue(sig <= {1, 2, 3, 4}, f"unexpected indices: {sig}")
        self.assertGreater(_idx4_frac(self.small0), 0.3)


class SmallLateGlyphsAreNotDrifted(unittest.TestCase):
    """Regression: the SMALL origins step ~6 px, so a too-wide step accumulates
    drift over the 11 glyphs and pushes the LATER cells off their glyphs — the
    classic failure was small '9' landing on the '/' (a NE→SW diagonal) and small
    '/' landing on the '=' operator (stacked horizontal bars). The weak
    idx-4-fraction guard below can't catch this (a slash and an '=' both have a
    strong index-4 outline), so assert the *shape* of the two tell-tale glyphs."""

    @classmethod
    def setUpClass(cls):
        grid = p.read_frame_indices(_frame_path())
        cells = p.small_digit_set()["cells"]
        cls.nine = p.cell_block(grid, cells[9])
        cls.slash = p.cell_block(grid, cells[10])

    def test_small_nine_has_a_left_stroke_in_its_upper_loop(self):
        # A '9' closes a loop in the top half -> its LEFT column carries ink in
        # the upper-middle rows. The '/' the drifted origin used to grab is empty
        # top-left (its ink is the top-RIGHT of a diagonal).
        upper_left = sum(1 for y in range(2, 5) if self.nine[y][0])
        self.assertGreaterEqual(
            upper_left, 2,
            "small '9' has no upper-left loop stroke — origin drifted onto the slash")

    def test_small_slash_is_a_diagonal_not_stacked_bars(self):
        # A '/' leans NE->SW: ink in the top third sits to the RIGHT of ink in the
        # bottom third. The '=' the drifted origin used to grab has its bars
        # vertically centred, so top and bottom centroids coincide.
        def centroid_x(rows):
            xs = [x for r in rows for x, v in enumerate(r) if v]
            return sum(xs) / len(xs) if xs else None
        top = centroid_x(self.slash[1:4])
        bot = centroid_x(self.slash[6:9])
        self.assertIsNotNone(top)
        self.assertIsNotNone(bot)
        self.assertGreater(
            top, bot + 1.0,
            f"small '/' is not a NE->SW diagonal (top cx={top:.1f}, bot cx={bot:.1f}) "
            "— origin drifted onto an operator")


class CompositionMetricsFromDynamicCapture(unittest.TestCase):
    """What only the dynamic capture encodes: the HUD composes the cur/max block
    by blitting each glyph at a FIXED advance (NOT pairwise side-bearing kerning),
    and staggers `max` a baseline below `cur`. The scratch page is a TIGHTER
    intermediate than the display, so its horizontal pitch is NOT the on-screen
    advance (that is read off the framebuffer + dialed headful — see
    ADVANCE_BIG/ADVANCE_SMALL). But two scale-stable facts hold here: the advance
    is UNIFORM for repeated digits, and the cur->max vertical stagger equals
    `MAX_BASELINE_DY` (vertical isn't compressed). (docs/hud-number-font.md.)"""

    def setUp(self):
        # instance attr (NOT a class attr — a class-level function would be
        # method-bound and swallow the first positional arg as `self`).
        self.nib = _scratch_reader("scratchpad_sstate1.bin.gz")

    def _run_starts(self, v, u0, u1):
        starts, prev = [], 0
        for u in range(u0, u1):
            cur = 1 if self.nib(u, v) else 0
            if cur and not prev:
                starts.append(u)
            prev = cur
        return starts

    def _top_row(self, u0, u1, v0, v1):
        for v in range(v0, v1):
            if any(self.nib(u, v) for u in range(u0, u1)):
                return v
        return None

    def test_repeated_digits_use_a_uniform_fixed_advance(self):
        # big cur "999" caps (scratch row v1) are evenly spaced -> the compositor
        # uses one fixed advance per glyph, not per-pair kerning. (Value is the
        # scratch's tight intermediate pitch, not the display advance.)
        caps = self._run_starts(1, 174, 196)
        self.assertEqual(len(caps), 3, f"expected 3 cur caps, got {caps}")
        pitches = [caps[i + 1] - caps[i] for i in range(len(caps) - 1)]
        self.assertEqual(pitches[0], pitches[1],
                         f"cur '999' cap spacing not uniform: {pitches}")

    def test_max_sits_max_baseline_dy_below_cur(self):
        # big cur block (u176..191) tops at one row; small max block (u196..210)
        # tops MAX_BASELINE_DY rows lower — the staggered cur/max look. Vertical
        # metrics survive into the display, so this pins p.MAX_BASELINE_DY.
        cur_top = self._top_row(176, 192, 0, 12)
        max_top = self._top_row(196, 211, 0, 12)
        self.assertEqual(max_top - cur_top, p.MAX_BASELINE_DY,
                         f"cur top v{cur_top}, max top v{max_top}: stagger "
                         f"{max_top - cur_top} != {p.MAX_BASELINE_DY}")


class EveryOriginLandsOnAGlyph(unittest.TestCase):
    """Drift guard for all 22 measured origins: each cell must land on a real
    blocky glyph (a strong index-4 outline), not a gap or a neighbour. Catches a
    mis-measured origin in either set without pinning sliver-prone raw blocks."""

    def test_all_cells_have_blocky_ink(self):
        grid = p.read_frame_indices(_frame_path())
        for ds in (p.big_digit_set(), p.small_digit_set()):
            for glyph, cell in zip(ds["glyphs"], ds["cells"]):
                block = p.cell_block(grid, cell)
                self.assertGreater(
                    _idx4_frac(block), 0.25,
                    f"{ds['size']} '{glyph}' at x={cell['x']} has weak index-4 "
                    f"outline — origin likely drifted off the glyph")


class FontAtlasBuild(unittest.TestCase):
    """The packed FRAMEFONT atlas: a grayscale (index×17) texture carrying both
    digit sets + a manifest the runtime loads (cells per size + the menu CLUT)."""

    @classmethod
    def setUpClass(cls):
        cls.grid = p.read_frame_indices(_frame_path())
        cls.w, cls.h, cls.gray, cls.man = p.build_font_atlas(cls.grid)

    def test_manifest_has_both_sets_and_menu_clut(self):
        self.assertEqual(self.man["clut"], 0x7CBC)
        self.assertEqual({s["size"] for s in self.man["sets"]}, {"big", "small"})
        by_size = {s["size"]: s for s in self.man["sets"]}
        # BIG (cur) stops at '/'; SMALL (max) adds '-', '%', the equip-delta '+', '…'.
        self.assertEqual(by_size["big"]["glyphs"], "0123456789/")
        self.assertEqual(len(by_size["big"]["cells"]), 11)
        self.assertEqual(by_size["small"]["glyphs"], "0123456789/-%+…")
        self.assertEqual(len(by_size["small"]["cells"]), 15)

    def test_grayscale_encodes_index_times_17(self):
        self.assertEqual(len(self.gray), self.w * self.h)
        self.assertTrue(all(v % 17 == 0 for v in self.gray))

    def test_packed_big_zero_round_trips_from_source(self):
        # the glyph stored in the atlas equals the glyph read from FRAME.BIN
        big = next(s for s in self.man["sets"] if s["size"] == "big")
        c = big["cells"][0]
        packed = [[self.gray[(c["y"] + y) * self.w + c["x"] + x] // 17
                   for x in range(c["w"])] for y in range(c["h"])]
        source = p.cell_block(self.grid, p.big_digit_set()["cells"][0])
        self.assertEqual(packed, source)
