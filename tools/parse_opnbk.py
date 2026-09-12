#!/usr/bin/env python3
"""
FFT OPNBK.BIN Parser

Extracts the opening-menu background images from Final Fantasy Tactics
OPEN/OPNBK.BIN.

Layout (from Shishi PSXImages.xml — Section "OPNBK.BIN", 825,344 bytes):

    Name      Offset       Length    Dimensions    Format
    OPNBK1    0x00000      153,600   320 x 240     Raw 16-bit (5/5/5/1)
    OPNBK2    0x25800      122,880   256 x 240     Raw 16-bit
    OPNBK3..6 0x43800+     75,600 ea 210 x 180     Raw 16-bit
    OPNBK7    0x8D800      245,760   512 x 240     Raw 16-bit

Each pixel is two little-endian bytes:
    byte0 = GGGRRRRR    -> R = bits 0..4
    byte1 = ABBBBBGG    -> G = top 3 bits of byte0 + low 2 bits of byte1
                         B = bits 2..6 of byte1, A = bit 7 of byte1

OPNBK1 is the main-menu background and is the only image extracted by
default. Pass --all to write every entry.

Usage:
    uv run python tools/parse_opnbk.py
    uv run python tools/parse_opnbk.py --all
"""

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image


ENTRIES = [
    # (name, offset, width, height)
    ("OPNBK1", 0x00000, 320, 240),
    ("OPNBK2", 0x25800, 256, 240),
    ("OPNBK3", 0x43800, 210, 180),
    ("OPNBK4", 0x56280, 210, 180),
    ("OPNBK5", 0x68D00, 210, 180),
    ("OPNBK6", 0x7B780, 210, 180),
    ("OPNBK7", 0x8D800, 512, 240),
]


def decode_pixel(b0: int, b1: int) -> tuple:
    """Decode one PSX 16bpp (5/5/5/1) little-endian pixel to RGBA.

    The STP bit (bit 15) only matters for PSX hardware blending modes
    (semi-transparency between draw calls). For a static fullscreen bg
    rendered as a quad we always want it opaque, so STP is ignored here.
    OPNBK1 in particular has STP=1 on its top/bottom letterbox rows AND
    on parts of the title glyphs; honouring it would knock those out to
    the background colour.
    """
    r = (b0 & 0x1F) << 3
    g = ((b1 & 0x03) << 6) | ((b0 & 0xE0) >> 2)
    b = (b1 & 0x7C) << 1
    return (r, g, b, 255)


def decode_raw16(data: bytes, offset: int, width: int, height: int) -> Image.Image:
    img = Image.new("RGBA", (width, height))
    px = img.load()
    for y in range(height):
        row_off = offset + y * width * 2
        for x in range(width):
            b0 = data[row_off + x * 2]
            b1 = data[row_off + x * 2 + 1]
            px[x, y] = decode_pixel(b0, b1)
    return img


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    repo_root = Path(__file__).resolve().parents[2]  # godot-learning/tools/.. /..
    parser.add_argument(
        "--input",
        default=str(repo_root / "project-assets/fft-extract/OPEN/OPNBK.BIN"),
        help="Path to OPNBK.BIN (default: monorepo project-assets)",
    )
    parser.add_argument(
        "--out-dir",
        default=str(repo_root / "godot-learning/assets/ui"),
        help="Output directory for PNG files (default: godot-learning/assets/ui)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Extract every entry (default: OPNBK1 only)",
    )
    args = parser.parse_args()

    src = Path(args.input)
    if not src.is_file():
        print(f"error: {src} not found", file=sys.stderr)
        return 1

    data = src.read_bytes()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    entries = ENTRIES if args.all else ENTRIES[:1]
    for name, off, w, h in entries:
        img = decode_raw16(data, off, w, h)
        out_path = out_dir / f"{name.lower()}.png"
        img.save(out_path)
        print(f"wrote {out_path}  ({w}x{h})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
