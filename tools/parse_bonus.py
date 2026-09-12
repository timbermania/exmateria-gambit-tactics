"""Decode the {78} Display Conditions results/intro screens → PNG textures + manifest.

`{78}` is the event-script opcode behind the battle **intro** banner
("Conditions for Winning" / "Defeat all enemies!" / "READY!") and the whole battle
**outro** ("CONGRATULATIONS!", "This Battle Is Complete!", "BONUS MONEY" + the gil
reel, WAR TROPHIES, WARNING, PARTING SHOT!!, the recruit flow). Its first operand
byte is a **mode**, not a conditions id, and the dispatcher `0x801CAFD4` hands each
mode to its own screen body.

Full RE: research/working_documents/BATTLE_RESULTS_SCREEN.md (§3/§4/§4B/§5/§8 for
the text and the reel, §13 for the dispatcher and the banner screen, §14 for
BONUS.BIN, §17 for the live outro trace).

Everything this tool emits comes from TWO disc files — no savestate, no VRAM capture:

    EVENT/BONUS.BIN    958,464 B = 36 pages of 0x6800. Each page is a 256x200 4bpp
                       sheet plus its two 16-colour CLUTs. Rows 0-127 are the
                       results-screen font sheet (byte-identical to VRAM tpage 6,
                       §3.1); rows 128-199 are that battle's victory-condition
                       banner. The palette block is identical on all 36 pages and
                       only TWO variants of rows 0-127 exist — page 1 is the
                       game-complete sheet, whose second line reads "This Game Is
                       Complete!" instead of "This Battle Is Complete!".

    EVENT/REQUIRE.OUT  the results overlay itself, code `0x801C5000`-`0x801CB000`
                       and data `0x801D0000`-`0x801D9000`. It is a DMA overlay that
                       loads at **`0x801BF000`** — the same base
                       `tools/parse_map_titles.py` already reads EVENT/ATTACK.OUT at,
                       and confirmed here by the glyph metric table landing exactly
                       at file offset `0x11EE8` = VA `0x801D0EE8`. Every table below
                       is byte-identical to the same address in
                       reference-assets/battle_results_ss*.sstate.

⚠️ The tables were first read out of savestates (that is what the living doc cites).
Sourcing them from REQUIRE.OUT instead is what makes this asset ROM-derived and
regenerable, the same argument parse_map_titles.py makes for its CLUT.

Output (assets/scenarios/results/):
    sheet_<V>.png          256x128 RGBA — the font sheet under the LETTER palette
                           (CLUT 0x3F9A / pal2). V = 0 normal, 1 game-complete.
    digits.png             256x128 RGBA — the same sheet under the DIGIT palette
                           (CLUT 0x3F98 / pal0), which the gil reel and `Gil` use.
    banner_<NN>.png        256x72 RGBA — page NN's victory-condition banner
                           (sheet rows 128-199) under the letter palette.
    results.json           the glyph metric / string / colour / banner tables and
                           the per-page objective text.

Usage (from `godot-learning/tools/` — `uv run` resolves the environment from the
CURRENT directory, and pillow is pinned in `tools/pyproject.toml`, so running this as
`uv run python tools/parse_bonus.py` one level up dies on `ModuleNotFoundError: PIL`):
    uv run python parse_bonus.py
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from PIL import Image

from _repo_paths import event_dir, assets_dir

# --- BONUS.BIN layout (§14) --------------------------------------------------
PAGE_SIZE = 0x6800           # 13 sectors; page n starts at disc sector 5824 + 13n
PAGE_COUNT = 36              # 0xEA000 / 0x6800 exactly
SHEET_W, SHEET_H = 256, 200  # the whole page image, 128 bytes per row @ 4bpp
RESULTS_H = 128              # rows 0..127 -> VRAM tpage 6 (the results font sheet)
BANNER_ROW0, BANNER_H = 128, 72   # rows 128..199 -> that battle's banner
CLUT_DIGITS_OFF = 0x6400     # pal0 -> CLUT 0x3F98, the digit / `Gil` palette
CLUT_LETTERS_OFF = 0x6440    # pal2 -> CLUT 0x3F9A, the big-font palette
# `0x801C3AB0` streams a page with LoadImage(RECT(384,0,64,256)) + RECT(384,254,64,2);
# 384 is tpage 6 and (254<<6)|(384>>4) / |(416>>4) are exactly those two CLUT ids.
DISC_LBA_BASE, DISC_LBA_STRIDE = 5824, 13

# --- REQUIRE.OUT: the overlay's own tables (§4/§4B/§5/§13) -------------------
# The overlay's DMA load address. parse_map_titles.py reads EVENT/ATTACK.OUT at the
# same base; both are EVENT overlays sharing that region at different times.
OVERLAY_BASE = 0x801BF000
# 12-byte metric records `(u, v, w, h, dx, dy)`, all s16. dx/dy are signed offsets
# from screen centre (128, 120), so a glyph's top-left lands at (128+dx, 120+dy).
METRICS_VA = 0x801D0EE8
# A cumulative *glyph-record* index, NOT a table of pointers: string n occupies
# records `tab[n] .. tab[n+1]-1` (`0x801C9FF8`-`0x801CA00C`).
STRING_INDEX_VA = 0x801D153C
STRING_COUNT = 11
# 20-byte colour records, one per glyph record, `flag` first then four RGB corners.
# `flag` 1 = gouraud (POLY_GT4), 0 = flat (POLY_FT4). The values are the SETTLED
# colours at L = 128 = 1.0; the fade scales them at build time (`0x801C8B94`).
GLYPH_COLORS_VA = 0x801D1548
# The victory-condition banner screen `0x801C8F80`'s own tables.
BANNER_METRICS_VA = 0x801D0DF4      # six 12-byte records, same layout
BANNER_TPAGE_VA = 0x801D0E54        # 4 bytes/record; byte +2 carries the abr bits
BANNER_INDEX_VA = 0x801D0E6C        # (base, count) — reads (0, 6) on every page
BANNER_COLORS_VA = 0x801D0E70       # 20-byte colour records, flag first
BANNER_RECORDS = 6
# The dim colour `{76}` re-reads into every diamond and into its settled quad.
DIM_RGB_VA = 0x801D0078

# The eleven messages, in string-table order (§4B, decoded from the records' own
# (u, v) cells by battle_results_captures/strings.py).
STRING_NAMES = [
    "READY!",
    "CONGRATULATIONS!",
    "BONUS MONEY",
    "gil row",                      # 5 digit cells + `,` + `Gil` — the reel's layout
    "WAR TROPHIES",
    "WARNING",
    "PARTING SHOT!!",
    "This Battle Is Complete!",     # a pre-composed 128x32 blit, not a font run
    "He Has Left Your Company!",
    "She Has Left Your Company!",
    "JOIN UP!",
]

# Which string each screen body spawns (§4B "Who picks which"). Keyed by the {78}
# mode the dispatcher routes to that body; mode 6 picks 8 or 9 on `unit[+6] & 0x40`.
STRING_FOR_MODE = {0: [0], 2: [1, 7], 3: [2, 3], 4: [4], 5: [5], 6: [6, 8]}

# Page -> objective, read off the rendered banners (bonus_bin_map.py). Page 1 is
# also the only page whose results sheet differs; page 28 is an orphan (33 carries
# the same objective and is the one the scripts use) and 35 is blank.
OBJECTIVES = [
    "Defeat all enemies!", "Defeat Elidibs!", "Save Algus!", "Defeat Algus!",
    "Defeat Miluda!", "Defeat Wiegraf !", "Save Chocobo!", "Save Princess Ovelia!",
    "Save Mustadio!", "Save Agrias!", "Defeat Queklain!", "Save Olan!",
    "Save Cloud!", "Defeat Zalmo!", "Defeat Izlude!", "Defeat Wiegraf !",
    "Save Rafa!", "Protect Rafa!", "Defeat Rofel!", "Defeat Kletian!",
    "Defeat Balk!", "Defeat Meliadoul!", "Defeat Vormav!", "Defeat Altima!",
    "Defeat Adramelk!", "Open water gate a Bethla Garrison!", "Defeat Elmdor!",
    "Defeat Hashmalum!", "Save Reis!", "Defeat Velius!", "Defeat Zalera!",
    "Defeat Dycedarg's elder brother!", "Defeat Zalbag!", "Save Reis!",
    "Defeat Worker7!", "(blank)",
]


def _rgb555(v: int) -> tuple[int, int, int]:
    """PSX 16bpp RGB555 → 8-bit RGB (bit15 = STP/mask, ignored for colour)."""
    return ((v & 31) << 3, ((v >> 5) & 31) << 3, ((v >> 10) & 31) << 3)


def _palette(page: bytes, off: int) -> list[tuple[int, int, int]]:
    return [_rgb555(struct.unpack_from("<H", page, off + 2 * i)[0]) for i in range(16)]


def decode_sheet(page: bytes, pal: list, row0: int, rows: int) -> Image.Image:
    """`rows` rows of a page's 4bpp sheet, low nibble = left pixel.

    Index 0 is the transparent index (it is painted magenta in the investigation's
    atlas render for exactly that reason), so it comes out alpha 0 — the dimmed
    battlefield shows straight through the gaps in every glyph. Every other index is
    opaque here; the PER-PRIMITIVE blend (abr 0/1/2) is the renderer's job.

    ⚠️ The CLUT entries' bit 15 (STP) is NOT carried into alpha, and that is
    deliberate. On real hardware STP gates semi-transparency per texel, and the two
    palettes disagree about it (every entry of the digit palette has it set; one
    entry of the letter palette does). But the investigation's own reference
    renderer -- battle_results_captures/banner_anim.py, which produced the banner
    filmstrip this port is checked against -- blends every non-zero index by the
    primitive's abr, and no savestate in BATTLE_RESULTS_SCREEN.md is inside a banner
    screen to settle it. Encoding an STP rule here would be an inference the RE does
    not make; when a mode->8 capture exists, that is the artifact that decides it.

    If it ever is decided, the carrier is already written down: ADR-0096 rules that a
    texture's alpha channel carries STP, 128 for STP=1 and 255 for STP=0. That ADR is
    scoped to EFFECT textures and their artist round-trip, which is also why index 0
    rides as opaque black there and as alpha 0 here — alpha 0 is what
    parse_map_titles.py and parse_show_graphics.py already emit for the transparent
    index, and the scenario assets have no round-trip to be lossless for.
    """
    img = Image.new("RGBA", (SHEET_W, rows))
    pm = img.load()
    bpr = SHEET_W // 2
    for y in range(rows):
        base = (row0 + y) * bpr
        for x in range(SHEET_W):
            byte = page[base + (x >> 1)]
            nib = (byte & 0xF) if (x & 1) == 0 else (byte >> 4)
            r, g, b = pal[nib]
            pm[x, y] = (r, g, b, 0 if nib == 0 else 255)
    return img


class Overlay:
    """EVENT/REQUIRE.OUT addressed by virtual address."""

    def __init__(self, data: bytes) -> None:
        self.d = data

    def off(self, va: int) -> int:
        o = va - OVERLAY_BASE
        if not 0 <= o < len(self.d):
            raise SystemExit(f"VA 0x{va:08X} outside REQUIRE.OUT (base 0x{OVERLAY_BASE:08X})")
        return o

    def metric(self, va: int, i: int) -> list[int]:
        """One 12-byte `(u, v, w, h, dx, dy)` record."""
        return list(struct.unpack_from("<6h", self.d, self.off(va) + 12 * i))

    def color(self, va: int, i: int) -> dict:
        """One 20-byte colour record: `flag` then four RGB corners (TL, TR, BL, BR)."""
        b = self.off(va) + 20 * i
        flag = struct.unpack_from("<I", self.d, b)[0]
        corners = [list(self.d[b + 4 + 4 * k: b + 7 + 4 * k]) for k in range(4)]
        return {"gouraud": bool(flag), "corners": corners}


def read_tables(ov: Overlay) -> dict:
    """Every table the screens draw from, straight out of the overlay image."""
    index = list(ov.d[ov.off(STRING_INDEX_VA): ov.off(STRING_INDEX_VA) + STRING_COUNT + 1])
    if index[0] != 0 or any(b <= a for a, b in zip(index, index[1:])):
        raise SystemExit(f"string index at 0x{STRING_INDEX_VA:08X} is not cumulative: {index}")
    n_glyphs = index[-1]

    strings = []
    for n in range(STRING_COUNT):
        strings.append({
            "name": STRING_NAMES[n],
            "first": index[n],
            "count": index[n + 1] - index[n],
        })

    glyphs = [ov.metric(METRICS_VA, i) for i in range(n_glyphs)]
    glyph_colors = [ov.color(GLYPH_COLORS_VA, i) for i in range(n_glyphs)]

    base, count = ov.d[ov.off(BANNER_INDEX_VA)], ov.d[ov.off(BANNER_INDEX_VA) + 1]
    if (base, count) != (0, BANNER_RECORDS):
        raise SystemExit(f"banner index reads ({base}, {count}), expected (0, {BANNER_RECORDS})")
    banner = []
    for i in range(BANNER_RECORDS):
        # `tpage = (tbl[i][2] & 0x60) | 6` (`0x801C932C`), so the abr bits land
        # straight on the tpage's blend field: 1 = bg + fg, 2 = bg - fg.
        tp = (ov.d[ov.off(BANNER_TPAGE_VA) + 4 * i + 2] & 0x60) | 6
        if tp & 0xF != 6:
            raise SystemExit(f"banner record {i} is not 4bpp tpage 6 (got 0x{tp:X})")
        rec = {"metric": ov.metric(BANNER_METRICS_VA, i), "abr": (tp >> 5) & 3}
        rec.update(ov.color(BANNER_COLORS_VA, i))
        banner.append(rec)

    return {
        "strings": strings,
        "glyphs": glyphs,
        "glyph_colors": glyph_colors,
        "banner": banner,
        "dim_rgb": list(ov.d[ov.off(DIM_RGB_VA): ov.off(DIM_RGB_VA) + 3]),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Decode the {78} results-screen assets")
    ap.add_argument("--fft-extract", help="FFT extract root override")
    ap.add_argument("--out", help="output dir (default assets/scenarios/results)")
    args = ap.parse_args()

    ev = event_dir(args.fft_extract)
    out = Path(args.out) if args.out else assets_dir("scenarios/results")
    out.mkdir(parents=True, exist_ok=True)

    data = (ev / "BONUS.BIN").read_bytes()
    if len(data) != PAGE_SIZE * PAGE_COUNT:
        raise SystemExit(
            f"BONUS.BIN is {len(data)} B, expected {PAGE_SIZE * PAGE_COUNT} "
            f"({PAGE_COUNT} pages of 0x{PAGE_SIZE:X})")
    pages = [data[i * PAGE_SIZE:(i + 1) * PAGE_SIZE] for i in range(PAGE_COUNT)]

    # The palette block is byte-identical on every page (§14) — assert it rather
    # than emit 36 copies of the same two CLUTs.
    pal_block = pages[0][CLUT_DIGITS_OFF:CLUT_LETTERS_OFF + 32]
    for i, p in enumerate(pages):
        if p[CLUT_DIGITS_OFF:CLUT_LETTERS_OFF + 32] != pal_block:
            raise SystemExit(f"page {i}'s CLUTs differ from page 0's — §14 says they cannot")
    pal_letters = _palette(pages[0], CLUT_LETTERS_OFF)
    pal_digits = _palette(pages[0], CLUT_DIGITS_OFF)

    # Rows 0-127 have only TWO variants across the 36 pages; emit each once and
    # record which variant a page uses.
    variants: list[bytes] = []
    page_variant: list[int] = []
    for p in pages:
        key = p[:RESULTS_H * (SHEET_W // 2)]
        if key not in variants:
            variants.append(key)
        page_variant.append(variants.index(key))
    if len(variants) != 2:
        raise SystemExit(f"{len(variants)} results-sheet variants, expected 2 (§14)")

    for v, _ in enumerate(variants):
        page = pages[page_variant.index(v)]
        decode_sheet(page, pal_letters, 0, RESULTS_H).save(out / f"sheet_{v}.png")
    # The digit palette is only ever used below row 80 (the reel cells, the comma
    # and `Gil`), and rows 0-79 are identical on all 36 pages — so one image covers
    # every page under CLUT 0x3F98.
    decode_sheet(pages[0], pal_digits, 0, RESULTS_H).save(out / "digits.png")

    banner_files = []
    for i, p in enumerate(pages):
        fn = f"banner_{i:02d}.png"
        decode_sheet(p, pal_letters, BANNER_ROW0, BANNER_H).save(out / fn)
        banner_files.append(fn)

    ov = Overlay((ev / "REQUIRE.OUT").read_bytes())
    tables = read_tables(ov)

    manifest = {
        "source": "EVENT/BONUS.BIN (sheets) + EVENT/REQUIRE.OUT (tables)",
        "overlay_base": f"0x{OVERLAY_BASE:08X}",
        "disc": {
            "lba_base": DISC_LBA_BASE, "lba_stride": DISC_LBA_STRIDE,
            "note": "0x801C3AB0 streams page n from sector 5824 + 13n — BONUS.BIN's own LBA",
        },
        "sheet": {"w": SHEET_W, "h": RESULTS_H},
        "banner_strip": {"w": SHEET_W, "h": BANNER_H, "row0": BANNER_ROW0},
        # dx/dy in every metric record are offsets from here (§4.1).
        "screen_center": [128, 120],
        "clut": {
            "letters": {"id": "0x3F9A", "rgb": [list(c) for c in pal_letters]},
            "digits": {"id": "0x3F98", "rgb": [list(c) for c in pal_digits]},
        },
        "sheets": [f"sheet_{v}.png" for v in range(len(variants))],
        "digits_sheet": "digits.png",
        "string_for_mode": {str(k): v for k, v in STRING_FOR_MODE.items()},
        "pages": [
            {"objective": OBJECTIVES[i], "variant": page_variant[i], "banner": banner_files[i]}
            for i in range(PAGE_COUNT)
        ],
    }
    manifest.update(tables)
    (out / "results.json").write_text(json.dumps(manifest, indent=2))
    print(f"Wrote {len(variants)} sheets + digits + {len(banner_files)} banners "
          f"+ results.json ({len(tables['glyphs'])} glyph records, "
          f"{len(tables['strings'])} strings) to {out}")


if __name__ == "__main__":
    main()
