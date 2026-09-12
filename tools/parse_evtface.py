"""Decode EVENT/EVTFACE.BIN event-dialogue portraits -> PNG textures + manifest.

The {50} Portrait Row opcode selects an EVTFACE.BIN *row-block* (a group of 8
portraits); the following {10} DisplayMessage / {51} ChangeDialog supply a
*column* (its Portrait byte, 1-based; col = byte - 1). Together they address one
EVTFACE cell = the message-box face. Distinct from the WORLD.BIN WLDFACE
world-map path and the in-battle unit-SPR path.

EVTFACE.BIN (65536 B) is an 8x8 grid of 32x48 4bpp portraits with an inline
16-colour BGR555 CLUT per portrait. Offsets (byte-verified vs the file AND live
VRAM, PORTRAIT_ROW_OPCODE_50_EVTFACE.md sec 4.1/6.3):

    pixel_offset   =        row*8192 + col*768     # 768 B contiguous 32x48 4bpp
    palette_offset = 6144 + row*8192 + col*32      # 32 B, 16x BGR555 little-endian

Each 8192-B row-block = pixels 0x000..0x17FF (8x768) + CLUTs 0x1800..0x18FF
(8x32) + pad to 0x2000 -- exactly the {50} VRAM upload unit.

Full RE + provenance:
    research/working_documents/PORTRAIT_ROW_OPCODE_50_EVTFACE.md

Output:
    assets/scenarios/faces/face_r<R>_c<C>.png   one PNG per portrait (64)
    assets/scenarios/faces/evtface.json         (row,col) -> metadata manifest

Usage:
    uv run python tools/parse_evtface.py
"""

from __future__ import annotations

import struct

from PIL import Image

ROWS = 8
COLS = 8
ROW_BLOCK = 8192           # 0x2000 bytes per row-block
PORTRAIT_BYTES = 768       # 0x300 bytes per 32x48 4bpp portrait
CLUT_BASE = 6144           # 0x1800 within a row-block
CLUT_BYTES = 32            # 16 x BGR555

FACE_W, FACE_H = 32, 48    # each portrait, 4bpp


def pixel_offset(row: int, col: int) -> int:
    """Byte offset of portrait (row, col)'s 768-B 4bpp pixel block in EVTFACE.BIN."""
    return row * ROW_BLOCK + col * PORTRAIT_BYTES


def palette_offset(row: int, col: int) -> int:
    """Byte offset of portrait (row, col)'s 32-B inline 16-colour CLUT."""
    return CLUT_BASE + row * ROW_BLOCK + col * CLUT_BYTES


def read_clut(data: bytes, row: int, col: int) -> list[int]:
    """The 16 raw BGR555 CLUT words (little-endian u16) for portrait (row, col)."""
    return list(struct.unpack_from("<16H", data, palette_offset(row, col)))


def _rgb555(v: int) -> tuple[int, int, int]:
    """PSX 16bpp BGR555 -> 8-bit RGB (bit15 = STP/mask, ignored for colour)."""
    return ((v & 31) << 3, ((v >> 5) & 31) << 3, ((v >> 10) & 31) << 3)


def decode_portrait(data: bytes, row: int, col: int) -> Image.Image:
    """Decode portrait (row, col) into a 32x48 RGBA image.

    4bpp, low-nibble = left pixel, inline 16-colour CLUT at palette_offset. Index
    0 is emitted transparent (the portrait's background) so the box composites
    only the face; every other index takes its CLUT colour opaque.
    """
    pal = [_rgb555(v) for v in read_clut(data, row, col)]
    pix = pixel_offset(row, col)
    img = Image.new("RGBA", (FACE_W, FACE_H))
    pm = img.load()
    bpr = FACE_W // 2
    for y in range(FACE_H):
        for x in range(FACE_W):
            byte = data[pix + y * bpr + (x >> 1)]
            nib = (byte & 0xF) if (x & 1) == 0 else (byte >> 4)
            r, g, b = pal[nib]
            pm[x, y] = (r, g, b, 0 if nib == 0 else 255)
    return img


def face_filename(row: int, col: int) -> str:
    """Stable PNG name for portrait (row, col) -- the Godot face-texture path stem."""
    return "face_r%d_c%d.png" % (row, col)


def main(argv: list[str] | None = None) -> None:
    import argparse
    import json
    from pathlib import Path

    from _repo_paths import event_dir, assets_dir

    ap = argparse.ArgumentParser(description="Decode EVTFACE.BIN event portraits")
    ap.add_argument("--fft-extract", help="FFT extract root override")
    ap.add_argument("--out", help="output dir (default assets/scenarios/faces)")
    args = ap.parse_args(argv)

    data = (event_dir(args.fft_extract) / "EVTFACE.BIN").read_bytes()
    if len(data) < ROWS * ROW_BLOCK:
        raise SystemExit("EVTFACE.BIN too small: %d B (expected %d)"
                         % (len(data), ROWS * ROW_BLOCK))

    out = Path(args.out) if args.out else assets_dir("scenarios/faces")
    out.mkdir(parents=True, exist_ok=True)

    faces: dict[str, dict] = {}
    for row in range(ROWS):
        for col in range(COLS):
            fn = face_filename(row, col)
            decode_portrait(data, row, col).save(out / fn)
            faces["%d_%d" % (row, col)] = {
                "file": fn, "row": row, "col": col, "w": FACE_W, "h": FACE_H,
            }

    manifest = {
        "source": "EVENT/EVTFACE.BIN (8x8 grid, 32x48 4bpp, inline BGR555 CLUT)",
        "grid": {"rows": ROWS, "cols": COLS},
        "faces": faces,
    }
    (out / "evtface.json").write_text(json.dumps(manifest, indent=2))
    print("Wrote %d EVTFACE portraits + evtface.json to %s" % (len(faces), out))


if __name__ == "__main__":
    main()
