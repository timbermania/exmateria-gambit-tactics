#!/usr/bin/env python3
"""Bake per-SPR "populated body rows" into a manifest for the palette resolver.

A body SPR ships 16 sub-palette rows of 16 BGR555 colors. Only some of rows
0-7 carry real color; the rest are the all-transparent/black (or the EVTCHR
``(0,104,0)`` green) sentinel the extractor pads with. The event-script CLUT
resolver (``SpritePaletteResolver.resolve_body_palette_row``) needs to know
which of rows 0-7 a sprite actually authored so it can CLAMP an out-of-range
ENTD ``palette`` byte to row 0 — see
``research/working_documents/EVTCHR_CLUT_RESOLUTION.md`` §3.1.

Generics (e.g. 0x60/0x62/0x64) author rows {0,1,2,3,4}; the ENTD byte
(Blue=0/Red=2) lands inside that set and passes through. Named unique units
(Delita 0x05, Ramza 0x01, Ovelia 0x0C) author only row 0 among the body rows,
so an ENTD byte of 2 (a stale team-color selector) points at an all-black row
and must clamp to 0.

This reads the already-baked ``NN.palette.tga`` files (which are themselves
deterministic ISO derivations from ``extract_spr.py`` — per
``feedback_assets_from_iso``, this is a tool output, not a hand-authored value),
so it needs no re-run of the full SPR extraction and no live PSX read.

Output: ``addons/exmateria_sprite_rig/resources/populated_rows.json`` mapping ``"NN"`` (uppercase hex
sprite id, matching ``sprite_files.json``) -> sorted list of populated rows in
0-7. Only BODY rows 0-7 are emitted; rows 8-15 (portrait region) are not
selectable via the ``body_palette_row`` uniform and are irrelevant to the
body-color clamp.

Run: ``uv run python tools/bake_populated_rows.py``
Check (CI): ``uv run python tools/bake_populated_rows.py --check``
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

TEXTURES_DIR = Path(__file__).resolve().parent.parent / "assets" / "sprites" / "textures"
OUTPUT_PATH = Path(__file__).resolve().parent.parent / "addons" / "exmateria_sprite_rig" / "resources" / "populated_rows.json"

# The EVTCHR/extractor "unused" sentinel color (RGB). A row made entirely of
# this (or of transparent/black) carries no real palette.
SENTINEL_RGB = (0, 104, 0)


def _read_palette_rgba(path: Path) -> list[tuple[int, int, int, int]]:
    """Read a 16x16 RGBA palette TGA into a flat list of 256 (r,g,b,a) tuples.

    Matches the little-endian, uncompressed, top-left-origin 32bpp BGRA layout
    written by ``extract_spr.py:write_tga``.
    """
    data = path.read_bytes()
    id_len = data[0]
    off = 18 + id_len
    px: list[tuple[int, int, int, int]] = []
    for i in range(256):
        b, g, r, a = data[off + i * 4 : off + i * 4 + 4]
        px.append((r, g, b, a))
    return px


def _is_populated(color: tuple[int, int, int, int]) -> bool:
    """A color counts as real if it is neither black/transparent nor sentinel."""
    r, g, b, _a = color
    if r == 0 and g == 0 and b == 0:
        return False
    if (r, g, b) == SENTINEL_RGB:
        return False
    return True


def populated_body_rows(palette: list[tuple[int, int, int, int]]) -> list[int]:
    """Return which of body rows 0-7 carry at least one real color."""
    rows: list[int] = []
    for row in range(8):
        row_px = palette[row * 16 : (row + 1) * 16]
        if any(_is_populated(c) for c in row_px):
            rows.append(row)
    return rows


def build() -> dict[str, list[int]]:
    result: dict[str, list[int]] = {}
    for tga in sorted(TEXTURES_DIR.glob("*.palette.tga")):
        stem = tga.name[: -len(".palette.tga")]
        # Only the two-hex sprite-id BODY palettes (01..FF). Skip named
        # companions like WEP1/EFF1/TRAP1/RANGETILE.
        if len(stem) != 2:
            continue
        try:
            int(stem, 16)
        except ValueError:
            continue
        result[stem.upper()] = populated_body_rows(_read_palette_rgba(tga))
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="verify the committed manifest matches the SPR palettes; exit 1 if stale")
    args = ap.parse_args()

    data = build()
    # An unpopulated worktree has no `*.palette.tga` yet (they are gitignored,
    # linked or generated), and `build()` then returns {} — which `--check`
    # reports as "stale" and a plain run WRITES, wiping a tracked manifest of
    # 154 sprites. The abort message tells you to run this tool, so following it
    # in an unlinked tree destroys the file. Refuse instead; "no inputs" is not
    # "no populated rows".
    if not data:
        print(f"ERROR: no *.palette.tga body palettes under {TEXTURES_DIR}")
        print("       This tree has no sprite textures linked, so there is nothing")
        print("       to bake from — NOT an empty result. Populate first:")
        print("         bash tools/link_worktree_godot_assets.sh")
        print("       (or run the SPR extraction), then re-run this tool.")
        return 1
    payload = {
        "_comment": "Generated by tools/bake_populated_rows.py — populated BODY palette rows "
                    "(0-7) per SPR id. Do not hand-edit; re-run the tool.",
        "sprites": data,
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"

    if args.check:
        if not OUTPUT_PATH.exists():
            print(f"ABORT: {OUTPUT_PATH} missing — run: uv run python tools/bake_populated_rows.py")
            return 1
        current = OUTPUT_PATH.read_text()
        if current != text:
            print(f"ABORT: {OUTPUT_PATH} is stale — run: uv run python tools/bake_populated_rows.py")
            return 1
        print(f"OK: {OUTPUT_PATH.name} up to date ({len(data)} sprites)")
        return 0

    OUTPUT_PATH.write_text(text)
    print(f"Wrote {OUTPUT_PATH} ({len(data)} sprites)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
