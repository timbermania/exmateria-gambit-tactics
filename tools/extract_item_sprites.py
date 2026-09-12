#!/usr/bin/env python3
"""
FFT Item Icon Extractor

Extracts item icons from EVENT/ITEM.BIN to TGA.

ITEM.BIN Format (33,280 bytes):
- 0x0000-0x7FFF: 32,768 bytes of 4bpp pixel data (65,536 pixels)
- 0x8000-0x81FF: 512 bytes of palette data (16 palettes × 16 colors × 2 bytes BGR555)

Dimensions: 256x256 (or possibly 128x512)
Icons: 16x16 pixels each, arranged in grid

Usage:
    uv run python tools/extract_item_sprites.py /path/to/fft-extract/EVENT/ITEM.BIN

Output:
    assets/items/item_icons.tga
"""

import argparse
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _repo_paths import assets_dir as _assets_dir, event_dir as _event_dir  # noqa: E402

# The picker/status renderer samples item icons through the SAME index->CLUT shader as every other
# RANGETILE sprite (formation_text_opaque: `idx = tex.r * 15`), so we ALSO emit an indexed-as-grayscale
# sheet (index i -> red i*17, index 0 = transparent key) + the 16 ITEM.BIN palettes as JSON. §15.26 (b):
# the picker icon is ITEM.BIN via the `graphic` byte, CLUT 0x3fa8 (proven by the green CLUT-swap).
INDEX_SCALE = 17          # i*17 spans 0..255 for i in 0..15 (matches RANGETILE.json index_scale)
PICKER_ICON_CLUT = 0x3fa8


# Constants for ITEM.BIN format
PIXEL_DATA_SIZE = 0x8000  # 32,768 bytes
PALETTE_OFFSET = 0x8000   # Palette starts after pixel data
PALETTE_SIZE = 512        # 16 palettes × 16 colors × 2 bytes
COLORS_PER_PALETTE = 16
NUM_PALETTES = 16

# Texture dimensions
WIDTH = 256
HEIGHT = 256  # 65,536 pixels / 256 = 256


def bgr555_to_rgba(color16: int) -> tuple:
    """Convert BGR555 color to RGBA tuple."""
    r = (color16 & 0x1F) * 8
    g = ((color16 >> 5) & 0x1F) * 8
    b = ((color16 >> 10) & 0x1F) * 8
    stp = (color16 >> 15) & 1
    a = 128 if stp else 255
    if r == 0 and g == 0 and b == 0:
        a = 0
    return (r, g, b, a)


def read_palettes(data: bytes) -> list:
    """Read all 16 palettes from ITEM.BIN."""
    palettes = []
    for pal_idx in range(NUM_PALETTES):
        palette = []
        pal_offset = PALETTE_OFFSET + pal_idx * COLORS_PER_PALETTE * 2
        for color_idx in range(COLORS_PER_PALETTE):
            color16 = struct.unpack_from('<H', data, pal_offset + color_idx * 2)[0]
            palette.append(bgr555_to_rgba(color16))
        palettes.append(palette)
    return palettes


def decode_4bpp_row(pixel_bytes: bytes, palette: list) -> list:
    """Decode 4bpp pixel bytes to RGBA tuples."""
    pixels = []
    for byte in pixel_bytes:
        # Low nibble first, high nibble second
        idx1 = byte & 0x0F
        idx2 = (byte >> 4) & 0x0F
        pixels.append(palette[idx1])
        pixels.append(palette[idx2])
    return pixels


def write_tga(path: str, width: int, height: int, pixels: list) -> None:
    """Write 32-bit RGBA TGA file."""
    with open(path, 'wb') as f:
        f.write(bytes([0, 0, 2, 0, 0, 0, 0, 0]))
        f.write(struct.pack('<H', 0))
        f.write(struct.pack('<H', 0))
        f.write(struct.pack('<H', width))
        f.write(struct.pack('<H', height))
        f.write(bytes([32, 0x28]))
        for r, g, b, a in pixels:
            f.write(bytes([b, g, r, a]))


def read_indices(data: bytes) -> list:
    """Decode the 4bpp pixel plane to raw palette INDICES (0-15), row-major (WIDTH*HEIGHT)."""
    indices = []
    bytes_per_row = WIDTH // 2
    for row in range(HEIGHT):
        row_bytes = data[row * bytes_per_row:(row + 1) * bytes_per_row]
        for byte in row_bytes:
            indices.append(byte & 0x0F)         # low nibble first
            indices.append((byte >> 4) & 0x0F)  # high nibble second
    return indices


def write_index_tga(path: str, indices: list) -> None:
    """Write the indexed-as-grayscale sheet: red = index*17 (index 0 = transparent key). RGB carry the
    scaled index; alpha stays 255 (the shader keys transparency on `idx == 0`, not alpha)."""
    pixels = []
    for i in indices:
        v = i * INDEX_SCALE
        pixels.append((v, v, v, 255))
    write_tga(path, WIDTH, HEIGHT, pixels)


def write_index_import(tga_path: Path) -> None:
    """Mirror RANGETILE.tga's import params (lossless, no mipmaps, linear sample) so the index->CLUT
    math (`tex.r * 15`) is byte-exact. Godot regenerates the .ctex on import; only params matter here."""
    imp = tga_path.with_suffix(tga_path.suffix + ".import")
    src = f"res://assets/items/{tga_path.name}"
    imp.write_text(
        "[remap]\n\n"
        'importer="texture"\n'
        'type="CompressedTexture2D"\n\n'
        "[deps]\n\n"
        f'source_file="{src}"\n\n'
        "[params]\n\n"
        "compress/mode=0\n"
        "mipmaps/generate=false\n"
        "process/hdr_as_srgb=false\n"
        "detect_3d/compress_to=0\n")


def write_palette_json(path: str, palettes: list) -> None:
    """Emit the 16 ITEM.BIN palettes (each 16 RGBA) + the picker CLUT id + cell size, so the Godot
    side builds a 16x1 CLUT texture for the type-selected palette (default 0 = the weapon bank)."""
    Path(path).write_text(json.dumps({
        "index_texture": "item_icons_index.tga",
        "flat_texture": "item_icons.tga",
        "cell": 16,
        "size": [WIDTH, HEIGHT],
        "picker_clut": PICKER_ICON_CLUT,
        "palettes": palettes,   # list[16] of list[16] of [r,g,b,a]
    }, indent=2))


def extract_indexed(input_path: str, out_dir: Path) -> None:
    """Emit the indexed sheet + import + palette JSON alongside the flat sheet (§15.26 b renderer feed)."""
    data = Path(input_path).read_bytes()
    indices = read_indices(data)
    palettes = read_palettes(data)
    idx_tga = out_dir / "item_icons_index.tga"
    write_index_tga(str(idx_tga), indices)
    write_index_import(idx_tga)
    write_palette_json(str(out_dir / "item_icons.json"), palettes)
    print(f"  Saved: {idx_tga} (+ .import) and item_icons.json ({len(palettes)} palettes)")


def extract_item_icons(input_path: str, output_path: str, palette_idx: int = 0) -> None:
    """Extract ITEM.BIN to TGA."""
    with open(input_path, 'rb') as f:
        data = f.read()

    print(f"Extracting: {Path(input_path).name}")
    print(f"  File size: {len(data)} bytes")

    if len(data) < PALETTE_OFFSET + PALETTE_SIZE:
        print(f"  ERROR: File too small, expected at least {PALETTE_OFFSET + PALETTE_SIZE} bytes")
        return

    # Read palettes (at end of file)
    palettes = read_palettes(data)
    print(f"  Palettes: {len(palettes)}")

    # Select palette
    if palette_idx < 0 or palette_idx >= len(palettes):
        palette_idx = 0
    palette = palettes[palette_idx]
    print(f"  Using palette: {palette_idx}")

    # Decode pixels (at start of file)
    all_pixels = []
    bytes_per_row = WIDTH // 2  # 4bpp = 2 pixels per byte

    for row in range(HEIGHT):
        row_offset = row * bytes_per_row
        row_bytes = data[row_offset:row_offset + bytes_per_row]
        row_pixels = decode_4bpp_row(row_bytes, palette)
        all_pixels.extend(row_pixels)

    print(f"  Dimensions: {WIDTH}x{HEIGHT}")
    print(f"  Total pixels: {len(all_pixels)}")

    # Write TGA
    write_tga(output_path, WIDTH, HEIGHT, all_pixels)
    print(f"  Saved: {output_path}")


def extract_all_palettes(input_path: str, output_dir: str) -> None:
    """Extract ITEM.BIN with all palettes for inspection."""
    with open(input_path, 'rb') as f:
        data = f.read()

    palettes = read_palettes(data)
    bytes_per_row = WIDTH // 2

    for pal_idx, palette in enumerate(palettes):
        all_pixels = []
        for row in range(HEIGHT):
            row_offset = row * bytes_per_row
            row_bytes = data[row_offset:row_offset + bytes_per_row]
            row_pixels = decode_4bpp_row(row_bytes, palette)
            all_pixels.extend(row_pixels)

        output_path = Path(output_dir) / f"item_icons_pal{pal_idx}.tga"
        write_tga(str(output_path), WIDTH, HEIGHT, all_pixels)
        print(f"  Extracted palette {pal_idx}: {output_path}")


def main():
    parser = argparse.ArgumentParser(description='Extract FFT item icons from ITEM.BIN')
    parser.add_argument('input', nargs='?', default=str(_event_dir() / 'ITEM.BIN'),
                        help='Path to EVENT/ITEM.BIN (default: the resolved extract)')
    parser.add_argument('-o', '--output',
                        default=str(_assets_dir('items') / 'item_icons.tga'),
                        help='Output TGA path')
    parser.add_argument('-p', '--palette', type=int, default=0,
                        help='Palette index (0-15)')
    parser.add_argument('--all-palettes', action='store_true',
                        help='Extract with all palettes')

    args = parser.parse_args()

    if not Path(args.input).exists():
        print(f"Error: Input file not found: {args.input}")
        sys.exit(1)

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)

    if args.all_palettes:
        extract_all_palettes(args.input, str(Path(args.output).parent))
    else:
        extract_item_icons(args.input, str(args.output), args.palette)
        # Always emit the indexed sheet + palette JSON the Godot index->CLUT renderer consumes.
        extract_indexed(args.input, Path(args.output).parent)


if __name__ == '__main__':
    main()
