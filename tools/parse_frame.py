#!/usr/bin/env python3
"""
FFT FRAME.BIN Parser

Extracts the dialog frame texture from Final Fantasy Tactics FRAME.BIN.

FRAME.BIN Format:
- Dimensions: 256 x 288 pixels
- Color depth: 4 bits per pixel (indexed color, 16 colors)
- Pixel data: 36,864 bytes (4bpp) at offset 0x0000
- Palettes: 704 bytes (22 palettes x 16 colors x 2 bytes) at offset 0x9000

The beveled dialog frame is the FRAME.BIN sprite (40, 0, 32, 32) — a 32x32 tile,
9-sliced with uniform 8px margins and a 16x16 tiled center (battle.bin
FUN_8014c18c/FUN_8014c758; see dialogue_box_geometry_and_fidelity_decode.md
Part 4). This script emits the WHOLE 256x288 image as frame.tga, so the crop
lives in the consumer (UIFrame.source_region = Vector4(40, 0, 32, 32),
margins = 8/8/8/8) — set per-instance by DialogueBox. The old (2,2)-(31,28)
crop was the flat menu-tile interior, NOT the dialog frame.

The boxed-portrait dialog's speaker triangle is TWO stacked 16x16 cells at
FRAME-atlas X=0x58 (88): (88,0) = arrow UP (box below the unit, triangle on
the box's TOP edge) and (88,16) = arrow DOWN (box above the unit, triangle on
the BOTTOM edge). Source: research/working_documents/scenario_1_captures/
boxed_dialog_decode.md (dynamic round 1 — live blit src rects captured).

Usage:
    uv run python tools/parse_frame.py [fft-extract-path]

Output:
    assets/ui/frame.tga                 - 256x288 RGBA texture (9-slice frame)
    assets/ui/dialog_triangle_up.tga    - 16x16 arrow-UP cell   (box below unit)
    assets/ui/dialog_triangle_down.tga  - 16x16 arrow-DOWN cell (box above unit)
    assets/ui/dialog_triangle.json      - cell offsets / metadata
"""

import argparse
import json
import struct
import sys
from pathlib import Path


# Constants
WIDTH = 256
HEIGHT = 288
PIXEL_OFFSET = 0x0000
PIXEL_SIZE = (WIDTH * HEIGHT) // 2  # 36,864 bytes at 4bpp
PALETTE_OFFSET = 0x9000  # Palettes are at end of file
PALETTE_COLORS = 16  # 4bpp = 16 colors per palette
PALETTE_SIZE = PALETTE_COLORS * 2  # 32 bytes per palette

# Speaker-triangle cells (boxed-portrait dialog). Two stacked 16x16 cells at
# atlas X=0x58. See module docstring / boxed_dialog_decode.md.
TRIANGLE_X = 0x58  # 88
TRIANGLE_SIZE = 16
TRIANGLE_UP_Y = 0    # arrow UP   — box BELOW unit, triangle on box TOP edge
TRIANGLE_DOWN_Y = 16  # arrow DOWN — box ABOVE unit, triangle on box BOTTOM edge


def bgr555_to_rgba(color16: int) -> tuple:
    """
    Convert BGR555 color to RGBA tuple.

    BGR555: bits 0-4 = R, bits 5-9 = G, bits 10-14 = B, bit 15 = STP
    """
    r = (color16 & 0x1F) * 8            # bits 0-4, multiply by 8 (0-248)
    g = ((color16 >> 5) & 0x1F) * 8     # bits 5-9
    b = ((color16 >> 10) & 0x1F) * 8    # bits 10-14
    stp = (color16 >> 15) & 1           # bit 15 (semi-transparency)

    # STP=1 means semi-transparent (alpha=128), STP=0 means opaque (alpha=255)
    a = 128 if stp else 255

    # Black pixels are fully transparent
    if r == 0 and g == 0 and b == 0:
        a = 0

    return (r, g, b, a)


def read_palette(data: bytes, offset: int, num_colors: int = 16) -> list:
    """Read BGR555 palette from data."""
    palette = []
    for i in range(num_colors):
        color16 = struct.unpack_from('<H', data, offset + i * 2)[0]
        palette.append(bgr555_to_rgba(color16))
    return palette


def decode_4bpp_bytes(pixel_bytes: bytes, palette: list) -> list:
    """
    Decode 4bpp pixel bytes to RGBA tuples.
    Each byte contains 2 pixels: low nibble = pixel 1, high nibble = pixel 2.
    """
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
        # TGA Header (18 bytes)
        f.write(bytes([
            0,              # ID length
            0,              # Color map type
            2,              # Image type (uncompressed true-color)
            0, 0, 0, 0, 0,  # Color map spec (5 bytes)
        ]))
        f.write(struct.pack('<H', 0))       # X origin
        f.write(struct.pack('<H', 0))       # Y origin
        f.write(struct.pack('<H', width))   # Width
        f.write(struct.pack('<H', height))  # Height
        f.write(bytes([
            32,     # Bits per pixel
            0x28    # Descriptor (top-left origin, 8 alpha bits)
        ]))

        # Pixel data in BGRA order (TGA format)
        for r, g, b, a in pixels:
            f.write(bytes([b, g, r, a]))


def crop_region(pixels: list, src_w: int, x: int, y: int, w: int, h: int) -> list:
    """Crop a w×h rectangle out of a flat top-left-origin RGBA pixel list."""
    out = []
    for row in range(y, y + h):
        base = row * src_w
        out.extend(pixels[base + x:base + x + w])
    return out


def extract_triangle(pixels: list, ui_dir: Path) -> None:
    """Emit the two speaker-triangle cells + offset metadata from the decoded
    FRAME.BIN image. `pixels` is the full WIDTH×HEIGHT RGBA list."""
    ui_dir.mkdir(parents=True, exist_ok=True)

    up = crop_region(pixels, WIDTH, TRIANGLE_X, TRIANGLE_UP_Y,
                     TRIANGLE_SIZE, TRIANGLE_SIZE)
    down = crop_region(pixels, WIDTH, TRIANGLE_X, TRIANGLE_DOWN_Y,
                       TRIANGLE_SIZE, TRIANGLE_SIZE)

    up_path = ui_dir / 'dialog_triangle_up.tga'
    down_path = ui_dir / 'dialog_triangle_down.tga'
    write_tga(str(up_path), TRIANGLE_SIZE, TRIANGLE_SIZE, up)
    write_tga(str(down_path), TRIANGLE_SIZE, TRIANGLE_SIZE, down)

    meta = {
        "_comment": (
            "Speaker triangle for the boxed-portrait DialogueBox. Cells are "
            "16x16, extracted from FRAME.BIN atlas X=0x58. 'up' points up and "
            "rides the box TOP edge (box below the unit); 'down' points down "
            "and rides the BOTTOM edge (box above the unit). Horizontal-mirror "
            "either cell for left/right facing. See boxed_dialog_decode.md."
        ),
        "cell_size": TRIANGLE_SIZE,
        "up": {"texture": up_path.name,
               "atlas": [TRIANGLE_X, TRIANGLE_UP_Y, TRIANGLE_SIZE, TRIANGLE_SIZE]},
        "down": {"texture": down_path.name,
                 "atlas": [TRIANGLE_X, TRIANGLE_DOWN_Y, TRIANGLE_SIZE, TRIANGLE_SIZE]},
    }
    meta_path = ui_dir / 'dialog_triangle.json'
    with open(meta_path, 'w') as f:
        json.dump(meta, f, indent=2)

    print(f"  Saved: {up_path} (16x16, arrow UP — box below unit)")
    print(f"  Saved: {down_path} (16x16, arrow DOWN — box above unit)")
    print(f"  Saved: {meta_path}")


def extract_frame(input_path: str, output_path: str) -> None:
    """Extract FRAME.BIN to TGA (frame 9-slice + speaker-triangle cells)."""
    with open(input_path, 'rb') as f:
        data = f.read()

    print(f"Extracting: {Path(input_path).name}")
    print(f"  File size: {len(data)} bytes")

    # Read first palette (16 colors at offset 0x9000)
    palette = read_palette(data, PALETTE_OFFSET, PALETTE_COLORS)
    print(f"  Palette at 0x{PALETTE_OFFSET:04X}: {PALETTE_COLORS} colors")

    # Print first few palette colors for debugging
    print(f"  Palette colors: ", end="")
    for i, (r, g, b, a) in enumerate(palette[:4]):
        print(f"[{i}]=({r},{g},{b},{a}) ", end="")
    print("...")

    # Read pixel data from start of file
    pixel_data = data[PIXEL_OFFSET:PIXEL_OFFSET + PIXEL_SIZE]
    print(f"  Pixel data: {len(pixel_data)} bytes")

    # Decode pixels
    pixels = decode_4bpp_bytes(pixel_data, palette)

    # Verify pixel count
    expected_pixels = WIDTH * HEIGHT
    if len(pixels) < expected_pixels:
        print(f"  Warning: Only {len(pixels)} pixels, expected {expected_pixels}")
        pixels.extend([(0, 0, 0, 0)] * (expected_pixels - len(pixels)))
    elif len(pixels) > expected_pixels:
        pixels = pixels[:expected_pixels]

    # Ensure output directory exists
    output_dir = Path(output_path).parent
    output_dir.mkdir(parents=True, exist_ok=True)

    # Write TGA
    write_tga(output_path, WIDTH, HEIGHT, pixels)
    print(f"  Saved: {output_path} ({WIDTH}x{HEIGHT})")

    # Also emit the speaker-triangle cells from the same decoded image.
    extract_triangle(pixels, Path(output_path).parent)
    print()
    print("Dialog frame region: (40,0,32,32) — 9-slice, uniform 8px margins, tiled center")
    print("Consumer crop: UIFrame.source_region = Vector4(40, 0, 32, 32), margins = 8/8/8/8")


def main():
    parser = argparse.ArgumentParser(
        description='Extract FFT FRAME.BIN to TGA',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    from _repo_paths import fft_extract_root as _fft_extract_root
    _default_fft = _fft_extract_root()
    parser.add_argument(
        'fft_path',
        nargs='?',
        default=str(_default_fft),
        help=f'Path to FFT extract directory (default: {_default_fft})'
    )

    args = parser.parse_args()

    # Construct input path
    input_path = Path(args.fft_path) / 'EVENT' / 'FRAME.BIN'
    if not input_path.exists():
        print(f"Error: FRAME.BIN not found at {input_path}")
        sys.exit(1)

    # Output path
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    output_path = project_root / 'assets' / 'ui' / 'frame.tga'

    extract_frame(str(input_path), str(output_path))


if __name__ == '__main__':
    main()
