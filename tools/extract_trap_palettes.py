#!/usr/bin/env python3
"""
Extract TRAP1 texture from WEP.SPR with different palette rows.

TRAP1 is 4bpp indexed with 16 possible sub-palettes (rows 0-15).
This script generates TGA files for each palette so we can visually
determine which palette produces the correct dust/smoke effect.

Usage:
    uv run python tools/extract_trap_palettes.py

Output:
    assets/sprites/textures/TRAP1_pal00.tga through TRAP1_pal15.tga
"""

import struct
from pathlib import Path

from _repo_paths import battle_dir as _battle_dir, assets_dir as _assets_dir


# TRAP1 location in WEP.SPR
TRAP1_OFFSET = 0x10400
TRAP1_WIDTH = 256
TRAP1_HEIGHT = 144
OUTPUT_HEIGHT = 488  # Padded to match shader expectations

# Paths resolve from the repo via _repo_paths (host-agnostic).
WEP_SPR_PATH = _battle_dir() / "WEP.SPR"
OUTPUT_DIR = _assets_dir("sprites/textures")


def bgr555_to_rgba(color16: int) -> tuple:
    """Convert BGR555 to RGBA. STP=1 means semi-transparent (alpha=128)."""
    r = (color16 & 0x1F) * 8
    g = ((color16 >> 5) & 0x1F) * 8
    b = ((color16 >> 10) & 0x1F) * 8
    stp = (color16 >> 15) & 1

    a = 128 if stp else 255
    if r == 0 and g == 0 and b == 0:
        a = 0

    return (r, g, b, a)


def read_palette(data: bytes, offset: int, num_colors: int = 256) -> list:
    """Read BGR555 palette."""
    palette = []
    for i in range(num_colors):
        color16 = struct.unpack_from('<H', data, offset + i * 2)[0]
        palette.append(bgr555_to_rgba(color16))
    return palette


def decode_4bpp_with_palette_row(pixel_bytes: bytes, palette: list, row: int) -> list:
    """
    Decode 4bpp pixels using a specific palette row.

    Args:
        pixel_bytes: Raw 4bpp data
        palette: Full 256-color palette
        row: Palette row 0-15 (each row is 16 colors)
    """
    offset = row * 16
    pixels = []
    for byte in pixel_bytes:
        idx1 = (byte & 0x0F) + offset
        idx2 = ((byte >> 4) & 0x0F) + offset
        pixels.append(palette[idx1])
        pixels.append(palette[idx2])
    return pixels


def write_tga(path: str, width: int, height: int, pixels: list) -> None:
    """Write 32-bit RGBA TGA."""
    with open(path, 'wb') as f:
        f.write(bytes([0, 0, 2, 0, 0, 0, 0, 0]))
        f.write(struct.pack('<H', 0))  # X origin
        f.write(struct.pack('<H', 0))  # Y origin
        f.write(struct.pack('<H', width))
        f.write(struct.pack('<H', height))
        f.write(bytes([32, 0x28]))

        for r, g, b, a in pixels:
            f.write(bytes([b, g, r, a]))


def main():
    print(f"Reading WEP.SPR from: {WEP_SPR_PATH}")

    with open(WEP_SPR_PATH, 'rb') as f:
        data = f.read()

    # TRAP1's palette is at the start of its section
    palette = read_palette(data, TRAP1_OFFSET, num_colors=256)

    # Pixel data is after palette (512 bytes)
    pixel_start = TRAP1_OFFSET + 512
    pixel_bytes = (TRAP1_WIDTH * TRAP1_HEIGHT) // 2
    pixel_data = data[pixel_start:pixel_start + pixel_bytes]

    # Print palette row colors for debugging
    print("\nPalette row preview (first 4 colors of each row):")
    for row in range(16):
        colors = []
        for c in range(4):
            idx = row * 16 + c
            r, g, b, a = palette[idx]
            colors.append(f"({r:3},{g:3},{b:3})")
        print(f"  Row {row:2}: {' '.join(colors)}")

    # Generate TGA for each palette row
    print(f"\nExtracting TRAP1 with all 16 palette rows to: {OUTPUT_DIR}")

    for row in range(16):
        pixels = decode_4bpp_with_palette_row(pixel_data, palette, row)

        # Pad to standard height
        if TRAP1_HEIGHT < OUTPUT_HEIGHT:
            padding = TRAP1_WIDTH * (OUTPUT_HEIGHT - TRAP1_HEIGHT)
            pixels.extend([(0, 0, 0, 0)] * padding)

        output_path = OUTPUT_DIR / f"TRAP1_pal{row:02d}.tga"
        write_tga(str(output_path), TRAP1_WIDTH, OUTPUT_HEIGHT, pixels)
        print(f"  Created: {output_path.name}")

    print("\nDone! Compare the TGA files visually to find the correct dust/smoke palette.")
    print("Expected: brownish/tan dust colors, NOT blue/bubble colors")


if __name__ == '__main__':
    main()
