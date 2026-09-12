"""Decode the {7D} ShowGraphic image files → PNG textures + a manifest.

ShowGraphic(xGR) draws a full-screen graphic that fades in/out. The 1-byte ID
selects a file loaded from the EVENT/WORLD data. All four classes are decoded
here, deterministically from the ISO extract (no live VRAM capture needed):

    ID         File(s)                  Format
    0x01-0x04  EVENT/CHAPTER1-4.BIN     256x16  4bpp, grayscale CLUT @ 0x1FE0
    0x07       EVENT/GAMEOVER.BIN       256x256 8bpp indexed (grayscale approx)
    0x08-0x0C  EVENT/END1-5.BIN         256x256 16bpp RGB555
    0x10-0x91  WORLD/WLDBK.BIN entry k  256x240 16bpp RGB555, stride 0x1E000

Formats decoded + visually verified 2026-07-02; full RE in
research/working_documents/scenario_1_captures/show_graphic_op7d_decode.md.

Why WLDBK defeats Shishi: it's a headerless raw-framebuffer container (131 back-
to-back 16bpp frames), not a TIM/sprite format.

Output:
    assets/scenarios/graphics/<name>.png     one PNG per graphic
    assets/scenarios/graphics/show_graphics.json   ShowGraphic ID -> metadata

Usage:
    uv run python tools/parse_show_graphics.py            # all incl. 131 WLDBK
    uv run python tools/parse_show_graphics.py --no-wldbk # skip the 131 backgrounds
"""

from __future__ import annotations

import argparse
import json
import struct
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from _repo_paths import event_dir, fft_extract_root, assets_dir

# --- ETC.OUT: the {7D} ShowGraphic render worker ----------------------------
# EVENT/ETC.OUT is loaded over a shared overlay slot at VA 0x801BF000 while a
# ShowGraphic card is up, so file_offset = VA - ETC_BASE. It carries the master
# per-graphic descriptor table that maps a row -> {format, sector, size, upload
# RECT, screen template}. Recipe + provenance: show_graphic_op7d_decode.md
# Part III.1 (every offset byte-verified against the disc).
ETC_BASE = 0x801BF000
DESC_TABLE_OFF = 0x18A8   # file offset of the descriptor table
DESC_STRIDE = 0x20        # bytes per row
DESC_ROWS = 13            # live rows (0..12)

# --- fmt-0 (CHAPTER) render constants ---------------------------------------
# Sourced from ETC.OUT's anim loop (0x801C017C) + builder (0x801BF3E0) and a
# BATTLE global (III.4/III.5). The grow-limit is per-graphic (parsed from the
# template); the rest are shared fmt-0 constants. Emitted into the manifest so
# the controller regenerates timing from files, never from a savestate.
CHAPTER_GROW_STEP = 1     # _DAT_80165f88 (static-init 1) -> 1 px/frame
CHAPTER_HOLD_FRAMES = 80  # 0x50 frames held at full brightness
CHAPTER_FADE_FRAMES = 128 # 0x80 frames, grey 128 -> 0
CHAPTER_GREY = 128        # 0x80 interior vertex grey (the fade level)
CHAPTER_EDGE = 32         # 0x20 px soft-edge kernel of the reveal front
CHAPTER_SHADOW_OFFSET = (1, 1)  # subtractive drop-shadow, right-anchored ~(+1,+1)

CHAPTER_W, CHAPTER_H = 256, 16
CHAPTER_PIX = (0x000, 0x800)     # 4bpp pixel region
CHAPTER_CLUT = 0x1FE0            # 16-entry RGB555 CLUT (last 32 bytes)

# PSX framebuffer the on-screen placement is expressed against (the card's
# screen `top` is a row in this 256x240 frame).
PSX_FB_W, PSX_FB_H = 256, 240

END_W, END_H = 256, 256
GAMEOVER_W, GAMEOVER_H = 256, 256

WLDBK_W, WLDBK_H = 256, 240
WLDBK_STRIDE = WLDBK_W * WLDBK_H * 2   # 0x1E000
WLDBK_COUNT = 131


@dataclass
class Descriptor:
    """One row of ETC.OUT's per-graphic table (file 0x18A8, stride 0x20).

    Field layout (show_graphic_op7d_decode.md III.1, byte-verified):
        +0x00 rect_va    -> VRAM upload RECT (deref within ETC.OUT)
        +0x04 tmpl_va    -> screen quad template
        +0x10 format     0=CHAPTER, 1=END-still, 2=movie
        +0x14 fname_va   -> ASCII dev path
        +0x18 sector     disc LBA
        +0x1C size       bytes to read
    """

    row: int
    format: int
    sector: int
    size: int
    rect_va: int
    tmpl_va: int
    fname_va: int


def parse_descriptor_table(data: bytes) -> list[Descriptor]:
    """Decode ETC.OUT's 13-row ShowGraphic descriptor table.

    `data` is the raw EVENT/ETC.OUT bytes. Returns one Descriptor per row in
    table order (row = the value ETC.OUT indexes with = graphic_operand - 1).
    A short/unexpected file returns [] rather than raising, so a bad ETC.OUT
    degrades to "no render params" instead of aborting the whole asset parse.
    """
    if len(data) < DESC_TABLE_OFF + DESC_ROWS * DESC_STRIDE:
        return []
    rows: list[Descriptor] = []
    for r in range(DESC_ROWS):
        off = DESC_TABLE_OFF + r * DESC_STRIDE
        rect_va, tmpl_va = struct.unpack_from("<II", data, off + 0x00)
        fmt = struct.unpack_from("<I", data, off + 0x10)[0]
        fname_va = struct.unpack_from("<I", data, off + 0x14)[0]
        sector, size = struct.unpack_from("<II", data, off + 0x18)
        rows.append(Descriptor(
            row=r, format=fmt, sector=sector, size=size,
            rect_va=rect_va, tmpl_va=tmpl_va, fname_va=fname_va,
        ))
    return rows


def row_for_operand(operand: int) -> int | None:
    """Map a {7D} graphic operand to its ETC.OUT descriptor row (row = op - 1).

    Returns None for operands outside the battle table: operand 0 (no card) and
    operands >= 0x10 (WLDBK world-map backgrounds, driven by WORLD.BIN, not this
    table -- III.2).
    """
    if operand < 1 or operand >= 0x10:
        return None
    row = operand - 1
    return row if row < DESC_ROWS else None


# The reveal front grows to the card content width, stored as an s16 at
# template +0x1C (III.4); the fade-in wipe sweeps 0 -> this many texels.
TEMPLATE_GROW_LIMIT_OFF = 0x1C


def template_grow_limit(data: bytes, tmpl_va: int) -> int:
    """Read the reveal grow-limit (content width, px) from a screen template.

    `tmpl_va` is the descriptor's template pointer; file_offset = VA - ETC_BASE.
    """
    off = (tmpl_va - ETC_BASE) + TEMPLATE_GROW_LIMIT_OFF
    return struct.unpack_from("<h", data, off)[0]


# The card is NOT centred. ETC.OUT's builder (FUN_801bf3e0) sets every vertex
# Y = template_record(+0x0A) + 0x80 (128 = GPU screen-centre offset). So the
# card's on-screen top row = min(record Y-base) + 128. Records are 0xC bytes;
# the card's quads all carry the grow-limit as their width field (+0x04).
TEMPLATE_STRIDE = 0xC
TEMPLATE_XBASE_OFF = 0x08
TEMPLATE_YBASE_OFF = 0x0A
TEMPLATE_WIDTH_OFF = 0x04
SCREEN_Y_OFFSET = 0x80    # +128, added by the builder to every vertex Y


def template_screen_top(data: bytes, tmpl_va: int) -> int | None:
    """The card's on-screen top row (px, in a 240-tall framebuffer), or None.

    Scans the card's quad records (those carrying the grow-limit as their width
    field) and returns min(Y-base) of the un-shifted pass + the builder's +128
    draw offset. The template holds additive/subtractive pairs offset ~1px; we
    take the records at the max X-base (the pass not shifted toward lower X) so
    the value is stable against the shadow. For the chapter template this yields
    -50 + 128 = 78 -- the PSX-confirmed card top (upper third, not screen centre).

    Returns None if the template pointer is out of range or no card quad is found
    (a null/movie row, or an unexpected layout) so the caller can fall back to a
    safe default rather than emitting a bogus top=0 that jams the card off-screen.
    """
    base = tmpl_va - ETC_BASE
    if base < 0 or base + TEMPLATE_STRIDE > len(data):
        return None
    grow = template_grow_limit(data, tmpl_va)
    recs: list[tuple[int, int]] = []   # (x_base, y_base) per card quad
    for i in range(16):  # safety bound; the card uses a handful of quads
        rec = base + i * TEMPLATE_STRIDE
        if rec + TEMPLATE_STRIDE > len(data):
            break
        width = struct.unpack_from("<h", data, rec + TEMPLATE_WIDTH_OFF)[0]
        if width != grow:
            break
        x = struct.unpack_from("<h", data, rec + TEMPLATE_XBASE_OFF)[0]
        y = struct.unpack_from("<h", data, rec + TEMPLATE_YBASE_OFF)[0]
        recs.append((x, y))
    if not recs:
        return None
    top_x = max(x for x, _ in recs)
    return min(y for x, y in recs if x == top_x) + SCREEN_Y_OFFSET


def deref_rect(data: bytes, rect_va: int) -> tuple[int, int, int, int] | None:
    """Read the 4x s16 upload RECT (x, y, w, h) a descriptor points at.

    `rect_va` is a VA in ETC.OUT's load image; file_offset = VA - ETC_BASE.
    A null pointer (movie rows) returns None.
    """
    if rect_va == 0:
        return None
    off = rect_va - ETC_BASE
    x, y, w, h = struct.unpack_from("<4h", data, off)
    return (x, y, w, h)


def _rgb555(v: int) -> tuple[int, int, int]:
    """PSX 16bpp RGB555 -> 8-bit RGB (bit15 = STP/mask, ignored for color)."""
    return ((v & 31) << 3, ((v >> 5) & 31) << 3, ((v >> 10) & 31) << 3)


def chapter_render_params(data: bytes, row: Descriptor) -> dict:
    """The ISO-sourced fmt-0 render block the manifest carries per graphic id.

    `data` is ETC.OUT bytes; `row` its descriptor. Emits {format, animation,
    passes}: the reveal grows `grow_step` px/frame to the template `grow_limit`,
    holds `hold_frames`, then the whole card's grey ramps 128->0 over
    `fade_frames`; drawn as an additive text pass + a subtractive drop-shadow
    (III.4). All values trace to ETC.OUT / the graphic file -- none captured.
    """
    params: dict = {
        "format": row.format,
        "animation": {
            "grow_limit": template_grow_limit(data, row.tmpl_va),
            "grow_step": CHAPTER_GROW_STEP,
            "hold_frames": CHAPTER_HOLD_FRAMES,
            "fade_frames": CHAPTER_FADE_FRAMES,
            "grey": CHAPTER_GREY,
            "edge": CHAPTER_EDGE,
        },
        "passes": {
            "additive": True,
            "subtractive": True,
            "shadow_offset": list(CHAPTER_SHADOW_OFFSET),
        },
    }
    # On-screen placement (PSX 240-tall framebuffer). The card is NOT centred:
    # its top row = template Y + 128 (builder FUN_801bf3e0). Omitted when the
    # template can't be read, so the controller falls back to a safe centre
    # rather than a bogus top=0 that would jam the card off the top edge.
    top = template_screen_top(data, row.tmpl_va)
    if top is not None:
        params["screen"] = {"top": top, "height": CHAPTER_H, "ref_h": PSX_FB_H}
    return params


def parse_chapter_clut(data: bytes) -> list[int]:
    """The chapter card's embedded 16-entry RGB555 CLUT (raw u16 words @0x1FE0).

    idx0 = 0x0000 (transparent background), idx15 = 0xFFFF (white text peak).
    Returned as raw PSX words so a caller can byte-match the disc.
    """
    return list(struct.unpack_from("<16H", data, CHAPTER_CLUT))


def decode_chapter(data: bytes) -> Image.Image:
    """256x16 4bpp strip, low-nibble = left pixel, grayscale CLUT @ 0x1FE0.

    Index 0 (black background) is emitted transparent so the fade compositing
    only touches the visible text/rule; the card shows centered on a black
    screen anyway.
    """
    pal = [_rgb555(v) for v in parse_chapter_clut(data)]
    px = data[CHAPTER_PIX[0]:CHAPTER_PIX[1]]
    img = Image.new("RGBA", (CHAPTER_W, CHAPTER_H))
    pm = img.load()
    bpr = CHAPTER_W // 2
    for y in range(CHAPTER_H):
        for x in range(CHAPTER_W):
            byte = px[y * bpr + (x >> 1)]
            nib = (byte & 0xF) if (x & 1) == 0 else (byte >> 4)
            r, g, b = pal[nib]
            pm[x, y] = (r, g, b, 0 if nib == 0 else 255)
    return img


def decode_rgb555(data: bytes, w: int, h: int, off: int = 0) -> Image.Image:
    """Raw 16bpp RGB555 framebuffer (END*, WLDBK). Opaque; fade is runtime."""
    img = Image.new("RGBA", (w, h))
    pm = img.load()
    u = struct.unpack_from("<%dH" % (w * h), data, off)
    for i, v in enumerate(u):
        r, g, b = _rgb555(v)
        pm[i % w, i // w] = (r, g, b, 255)
    return img


def decode_gameover(data: bytes) -> Image.Image:
    """256x256 8bpp indexed. Exact CLUT unknown (external) -> grayscale approx.

    GAP: capture the real palette from live VRAM later. Rare defeat graphic.
    """
    img = Image.new("RGBA", (GAMEOVER_W, GAMEOVER_H))
    pm = img.load()
    for i in range(GAMEOVER_W * GAMEOVER_H):
        v = data[i]
        pm[i % GAMEOVER_W, i // GAMEOVER_W] = (v, v, v, 255)
    return img


def main() -> None:
    ap = argparse.ArgumentParser(description="Decode {7D} ShowGraphic textures")
    ap.add_argument("--fft-extract", help="FFT extract root override")
    ap.add_argument("--no-wldbk", action="store_true",
                    help="skip the 131 WLDBK world backgrounds")
    ap.add_argument("--out", help="output dir (default assets/scenarios/graphics)")
    args = ap.parse_args()

    ev = event_dir(args.fft_extract)
    wldbk_path = fft_extract_root(args.fft_extract) / "WORLD" / "WLDBK.BIN"
    out = Path(args.out) if args.out else assets_dir("scenarios/graphics")
    out.mkdir(parents=True, exist_ok=True)

    # ETC.OUT's descriptor table drives the fmt-0 render params (idempotent,
    # ISO-sourced) so the manifest regenerates the whole effect from files.
    etc_data = (ev / "ETC.OUT").read_bytes()
    descriptors = parse_descriptor_table(etc_data)

    manifest: dict[str, dict] = {}

    def emit(gid: int, name: str, img: Image.Image, fullscreen: bool,
             extra: dict | None = None) -> None:
        fn = f"{name}.png"
        img.save(out / fn)
        entry = {
            "file": fn, "w": img.width, "h": img.height,
            "fullscreen": fullscreen,
        }
        if extra:
            entry.update(extra)
        manifest[f"0x{gid:02X}"] = entry
        print(f"  0x{gid:02X} -> {fn} ({img.width}x{img.height})")

    # CHAPTER1-4  (0x01-0x04): merge the ISO-sourced fmt-0 render params so the
    # controller drives the reveal/hold/fade + dual-pass straight from the file.
    # If ETC.OUT was unreadable, chapters still emit (decoded from the .BIN) — the
    # controller falls back to its fmt-0 defaults.
    if not descriptors:
        print("  WARNING: ETC.OUT table unreadable — chapters emit without "
              "ISO animation params (controller uses fmt-0 defaults)")
    for n in range(1, 5):
        data = (ev / f"CHAPTER{n}.BIN").read_bytes()
        row_idx = row_for_operand(n)
        extra = None
        if descriptors and row_idx is not None and row_idx < len(descriptors):
            extra = chapter_render_params(etc_data, descriptors[row_idx])
        emit(n, f"chapter_{n}", decode_chapter(data), fullscreen=False, extra=extra)

    # GAMEOVER (0x07)
    emit(0x07, "gameover", decode_gameover((ev / "GAMEOVER.BIN").read_bytes()),
         fullscreen=True)

    # END1-5 (0x08-0x0C)
    for n in range(1, 6):
        data = (ev / f"END{n}.BIN").read_bytes()
        emit(0x07 + n, f"end_{n}", decode_rgb555(data, END_W, END_H),
             fullscreen=True)

    # WLDBK backgrounds (0x10-0x91 -> entry ID-0x10)
    if not args.no_wldbk:
        wl = wldbk_path.read_bytes()
        for gid in range(0x10, 0x92):
            entry = gid - 0x10
            if entry >= WLDBK_COUNT:
                break
            img = decode_rgb555(wl, WLDBK_W, WLDBK_H, entry * WLDBK_STRIDE)
            emit(gid, f"wldbk_{entry:03d}", img, fullscreen=True)

    (out / "show_graphics.json").write_text(json.dumps(manifest, indent=2))
    print(f"\nWrote {len(manifest)} graphics + show_graphics.json to {out}")


if __name__ == "__main__":
    main()
