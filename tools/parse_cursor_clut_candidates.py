#!/usr/bin/env python3
"""Emit ALL plausible CLUTs on tpage 0x1F so the cursor preview scene can cycle
through them visually. Two sources are bundled together:

  1. ASSET CLUTs — the 22 palettes baked into the LBA-0xE68 asset itself, at
     asset+0x9000 (16 CLUTs uploaded to VRAM rect (960,496,16,16)) and
     asset+0x9200 (6 CLUTs uploaded to (976,506,16,6)). These are what
     FUN_80045154 DMAs to VRAM at battle init — the "initial" tpage CLUTs.
  2. BATTLE.BIN CLUTs — the 9 non-zero palettes at file offset 0x2DAE4..0x2DC23
     (RAM 0x80094AE4..0x80094BE4). These look like the "real" runtime palettes
     (recognizable blue/red/gold barber-poles); the game probably overwrites the
     asset's initial CLUTs with these at some later point in battle setup.

Outputs (regenerable bulk, gitignored alongside the rest of the RANGETILE files):

  RANGETILE.cursor_clut_candidates.palette.tga    16x31 RGBA
  RANGETILE.cursor_clut_candidates.json            cell labels (CLUT word, source)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _repo_paths  # noqa: E402
from fft_exporter.exporters.tga import write_rgba_tga  # noqa: E402

TEXTURE_LBA = 0xE68
ASSET_SECTORS = 19
SECTOR_SIZE = 2352
USER_DATA_OFFSET = 0x18
USER_DATA_SIZE = 2048
ASSET_R1_OFFSET = 0x9000     # 16 CLUTs * 32 bytes
ASSET_R2_OFFSET = 0x9200     # 6 CLUTs * 32 bytes
BB_RUNTIME_PAL_BASE = 0x2DAE4
BB_RUNTIME_PAL_COUNT = 9      # non-zero entries; rows 9..15 are all zero in BATTLE.BIN
PAL_BYTES = 32


def iso_path(cli_value: str | None) -> Path:
    if cli_value:
        return Path(cli_value)
    env = os.environ.get("FFT_ISO")
    if env:
        return Path(env)
    return _repo_paths.repo_root() / "project-assets" / "Final Fantasy Tactics.bin"


def read_lba(bin_path: Path, lba: int, nsectors: int) -> bytes:
    out = bytearray()
    with bin_path.open("rb") as f:
        for i in range(nsectors):
            f.seek((lba + i) * SECTOR_SIZE + USER_DATA_OFFSET)
            chunk = f.read(USER_DATA_SIZE)
            if len(chunk) != USER_DATA_SIZE:
                raise IOError(f"short read at LBA {lba + i:#x}")
            out += chunk
    return bytes(out)


def bgr555_to_rgba(lo: int, hi: int, transparent: bool) -> tuple[int, int, int, int]:
    v = lo | (hi << 8)
    r5, g5, b5 = v & 0x1F, (v >> 5) & 0x1F, (v >> 10) & 0x1F
    expand = lambda c: (c << 3) | (c >> 2)
    return expand(r5), expand(g5), expand(b5), 0 if transparent else 255


def palette_pixels(buf: bytes) -> list[tuple[int, int, int, int]]:
    return [bgr555_to_rgba(buf[i*2], buf[i*2+1], i == 0) for i in range(16)]


def clut_word(x_field: int, y: int) -> int:
    return x_field | (y << 6)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--iso")
    ap.add_argument("--fft-extract")
    ap.add_argument("--out")
    args = ap.parse_args()

    bin_path = iso_path(args.iso)
    battle_bin = _repo_paths.battle_bin(args.fft_extract)
    out_dir = Path(args.out) if args.out else _repo_paths.assets_dir("sprites/textures")
    out_dir.mkdir(parents=True, exist_ok=True)

    if not bin_path.exists():
        print(f"ERROR: ISO not found: {bin_path}", file=sys.stderr); return 1
    if not battle_bin.exists():
        print(f"ERROR: BATTLE.BIN not found: {battle_bin}", file=sys.stderr); return 1

    asset = read_lba(bin_path, TEXTURE_LBA, ASSET_SECTORS)
    bb = battle_bin.read_bytes()

    rows: list[dict] = []
    rgba_pixels: list[tuple[int, int, int, int]] = []

    # Asset region 1 (16 CLUTs at VRAM (960, 496..511), x_field=60)
    for n in range(16):
        off = ASSET_R1_OFFSET + n * PAL_BYTES
        pal = palette_pixels(asset[off:off + PAL_BYTES])
        rgba_pixels.extend(pal)
        rows.append({
            "row": len(rows),
            "source": "asset_r1",
            "slot": n,
            "clut_word": clut_word(60, 496 + n),
            "vram_xy": [960, 496 + n],
            "name": "",
        })

    # Asset region 2 (6 CLUTs at VRAM (976, 506..511), x_field=61)
    for n in range(6):
        off = ASSET_R2_OFFSET + n * PAL_BYTES
        pal = palette_pixels(asset[off:off + PAL_BYTES])
        rgba_pixels.extend(pal)
        rows.append({
            "row": len(rows),
            "source": "asset_r2",
            "slot": n,
            "clut_word": clut_word(61, 506 + n),
            "vram_xy": [976, 506 + n],
            "name": "",
        })

    # BATTLE.BIN runtime palettes (9 non-zero entries at 0x2DAE4 + N*0x20)
    bb_names = {0: "blue", 1: "red", 3: "yellow_a", 8: "yellow_b"}
    for n in range(BB_RUNTIME_PAL_COUNT):
        off = BB_RUNTIME_PAL_BASE + n * PAL_BYTES
        pal = palette_pixels(bb[off:off + PAL_BYTES])
        rgba_pixels.extend(pal)
        rows.append({
            "row": len(rows),
            "source": "battle_bin",
            "slot": n,
            "clut_word": clut_word(60, 496 + n),
            "vram_xy": [960, 496 + n],
            "name": bb_names.get(n, ""),
        })

    pal_out = out_dir / "RANGETILE.cursor_clut_candidates.palette.tga"
    write_rgba_tga(pal_out, 16, len(rows), rgba_pixels)

    manifest = {
        "palette": pal_out.name,
        "rows": rows,
        "cursor_uv": {"x": 66, "y": 128, "w": 13, "h": 24,
                      "note": "visually derived from RANGETILE.tga texels; NOT yet "
                              "cross-checked against disassembly prim-build site."},
    }
    json_out = out_dir / "RANGETILE.cursor_clut_candidates.json"
    json_out.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"wrote {pal_out}  (16x{len(rows)} RGBA)")
    print(f"wrote {json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
