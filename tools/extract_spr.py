#!/usr/bin/env python3
"""
FFT SPR Sprite Extractor

Extracts sprite textures from Final Fantasy Tactics SPR files to TGA.
Follows the same pattern as extract_effect_texture.lua for correct PSX semantics.

SPR Format:
- 256x488 pixels, 4 bits per pixel (indexed color)
- Palette: 256 colors x 2 bytes (BGR555) = 512 bytes at offset 0
- Top section: 256x256 pixels uncompressed (0x0200)
- Portrait rows: 256x32 pixels uncompressed (0x8200)
- Compressed section: 256x200 pixels LZ77-variant (0x9200)

Usage:
    python extract_spr.py <input.spr> <output.tga> [--no-decompress]
"""

import argparse
import struct
import sys
from pathlib import Path


# Constants
WIDTH = 256
HEIGHT = 488
PALETTE_OFFSET = 0x0000
PALETTE_SIZE = 512  # 256 colors * 2 bytes
TOP_SECTION_OFFSET = 0x0200
TOP_SECTION_HEIGHT = 256
PORTRAIT_OFFSET = 0x8200
PORTRAIT_HEIGHT = 32
COMPRESSED_OFFSET = 0x9200
COMPRESSED_HEIGHT = 200

# Files that don't use compression
UNCOMPRESSED_FILES = {
    'WEP', 'EFF', 'OTHER',
    '10M', '10W', '20M', '20W', '40M', '40W', '60M', '60W',
    'CYOMON1', 'CYOMON2', 'CYOMON3', 'CYOMON4',
    'DAMI', 'FURAIA'
}

# WEP.SPR contains multiple concatenated sub-sprites, each with its own palette
# Structure from ShishiSpriteEditor AllSprites.cs:
#   WEP1/WEP2 share offset 0x0000 (256x256)
#   EFF1/EFF2 share offset 0x8200 (256x256)
#   TRAP1 at offset 0x10400 (256x144)
# All outputs are padded to 256x488 to match unit sprite sheet dimensions
WEP_SPRITES = {
    'WEP1': {'offset': 0x0000, 'width': 256, 'height': 256},
    'EFF1': {'offset': 0x8200, 'width': 256, 'height': 256},
    'TRAP1': {'offset': 0x10400, 'width': 256, 'height': 144},
}
# Standard output height for shader compatibility
WEP_OUTPUT_HEIGHT = 488


def bgr555_to_rgba(color16: int) -> tuple:
    """
    Convert BGR555 color to RGBA tuple.
    Matches extract_effect_texture.lua exactly.

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


def read_palette(data: bytes, offset: int = 0, num_colors: int = 256) -> list:
    """Read BGR555 palette from SPR data."""
    palette = []
    for i in range(num_colors):
        color16 = struct.unpack_from('<H', data, offset + i * 2)[0]
        palette.append(bgr555_to_rgba(color16))
    return palette


def decode_4bpp_bytes_indices(pixel_bytes: bytes) -> list:
	"""
	Decode 4bpp pixel bytes to a flat list of palette INDICES (0-15).
	Each byte contains 2 pixels: low nibble = pixel 1, high nibble = pixel 2.

	Sibling of decode_4bpp_bytes (which applies a palette and returns RGBA).
	Used by extract_spr_indexed for the paletted body-sprite path (ADR-0022):
	the SPR's indices are written verbatim; the palette is emitted separately;
	the runtime shader does the index->RGBA lookup.
	"""
	indices = []
	for byte in pixel_bytes:
		indices.append(byte & 0x0F)         # Low nibble first
		indices.append((byte >> 4) & 0x0F)  # High nibble second
	return indices


def decode_4bpp_bytes(pixel_bytes: bytes, palette: list, palette_offset: int = 0) -> list:
    """
    Decode 4bpp pixel bytes to RGBA tuples.
    Each byte contains 2 pixels: low nibble = pixel 1, high nibble = pixel 2.

    Args:
        pixel_bytes: Raw 4bpp pixel data
        palette: Full palette (256 colors)
        palette_offset: Offset into palette for 4bpp lookups (row * 16).
                        Each 4bpp index (0-15) becomes index + palette_offset.
    """
    pixels = []
    for byte in pixel_bytes:
        # Low nibble first, high nibble second
        idx1 = (byte & 0x0F) + palette_offset
        idx2 = ((byte >> 4) & 0x0F) + palette_offset
        pixels.append(palette[idx1])
        pixels.append(palette[idx2])
    return pixels


# Portrait region within the portrait rows (256x32)
PORTRAIT_REGION_X = 80
PORTRAIT_REGION_WIDTH = 48


def decode_portrait_rows(pixel_bytes: bytes, palette: list, row_width: int,
                         portrait_palette_offset: int) -> list:
    """
    Decode portrait rows with selective palette application.

    The portrait rows (256x32) contain more than just the portrait.
    Only the portrait region (X:80-127) should use the portrait palette.
    Everything else uses the default palette (offset 0).

    Args:
        pixel_bytes: Raw 4bpp pixel data for portrait rows
        palette: Full palette (256 colors)
        row_width: Width of each row in pixels (256)
        portrait_palette_offset: Palette offset for portrait region (row * 16)
    """
    pixels = []
    pixel_x = 0

    for byte in pixel_bytes:
        # Low nibble first, high nibble second
        for nibble_idx in range(2):
            if nibble_idx == 0:
                color_idx = byte & 0x0F
            else:
                color_idx = (byte >> 4) & 0x0F

            # Check if this pixel is within the portrait region
            if PORTRAIT_REGION_X <= pixel_x < PORTRAIT_REGION_X + PORTRAIT_REGION_WIDTH:
                # Use portrait palette
                final_idx = color_idx + portrait_palette_offset
            else:
                # Use default palette (offset 0)
                final_idx = color_idx

            pixels.append(palette[final_idx])

            # Advance X position, wrap at row width
            pixel_x += 1
            if pixel_x >= row_width:
                pixel_x = 0

    return pixels


def decompress_section(compressed_data: bytes, target_byte_count: int) -> bytes:
    """
    Decompress LZ77-variant compressed sprite data.
    Returns decompressed BYTES (not nibbles).

    Compression operates on nibbles:
    - Non-zero nibble: literal value
    - 0x0 N (N=1-6): N zeros
    - 0x0 0x0 N: N zeros (extended)
    - 0x0 0x7 LO HI: (LO + HI*16) zeros
    - 0x0 0x8 LO MID HI: 24-bit zero count
    """
    # Step 1: Extract nibbles from input bytes (high nibble first, low nibble second)
    # This matches TacticsEngineG spr.gd lines 188-191
    input_nibbles = []
    for byte in compressed_data:
        input_nibbles.append((byte >> 4) & 0x0F)  # High nibble first
        input_nibbles.append(byte & 0x0F)          # Low nibble second

    # Step 2: Decompress nibble stream
    # Target is number of NIBBLES (2 per pixel for 4bpp, but we want output bytes)
    target_nibble_count = target_byte_count * 2
    decompressed_nibbles = []
    i = 0

    while i < len(input_nibbles) and len(decompressed_nibbles) < target_nibble_count:
        nibble = input_nibbles[i]

        if nibble != 0:
            # Literal nibble value
            decompressed_nibbles.append(nibble)
            i += 1
        else:
            # Zero run encoding
            if i + 1 >= len(input_nibbles):
                break

            next_nibble = input_nibbles[i + 1]

            if next_nibble == 0:
                # Extended format: 0x0 0x0 N
                if i + 2 >= len(input_nibbles):
                    break
                num_zeros = input_nibbles[i + 2]
                decompressed_nibbles.extend([0] * num_zeros)
                i += 3
            elif next_nibble == 7:
                # 16-bit count: 0x0 0x7 LO HI
                if i + 3 >= len(input_nibbles):
                    break
                lo = input_nibbles[i + 2]
                hi = input_nibbles[i + 3]
                num_zeros = lo + (hi << 4)
                decompressed_nibbles.extend([0] * num_zeros)
                i += 4
            elif next_nibble == 8:
                # 24-bit count: 0x0 0x8 LO MID HI
                if i + 4 >= len(input_nibbles):
                    break
                lo = input_nibbles[i + 2]
                mid = input_nibbles[i + 3]
                hi = input_nibbles[i + 4]
                num_zeros = lo + (mid << 4) + (hi << 8)
                decompressed_nibbles.extend([0] * num_zeros)
                i += 5
            else:
                # Simple count: 0x0 N (N = 1-6)
                num_zeros = next_nibble
                decompressed_nibbles.extend([0] * num_zeros)
                i += 2

    # Pad to target size if needed
    while len(decompressed_nibbles) < target_nibble_count:
        decompressed_nibbles.append(0)

    # Truncate if overshot
    decompressed_nibbles = decompressed_nibbles[:target_nibble_count]

    # Step 3: Recombine nibbles back into bytes
    # This matches TacticsEngineG spr.gd lines 232-234
    # decompressed_bytes[n] = decompressed_nibbles[n*2] << 4 | decompressed_nibbles[n*2+1]
    decompressed_bytes = bytearray(target_byte_count)
    for idx in range(target_byte_count):
        high_nibble = decompressed_nibbles[idx * 2]
        low_nibble = decompressed_nibbles[idx * 2 + 1]
        decompressed_bytes[idx] = (high_nibble << 4) | low_nibble

    return bytes(decompressed_bytes)


def should_decompress(filename: str) -> bool:
    """Determine if file uses compression based on filename.

    Most SPR files ARE compressed. Only specific files in UNCOMPRESSED_FILES
    are stored uncompressed.
    """
    basename = Path(filename).stem.upper()

    for pattern in UNCOMPRESSED_FILES:
        if pattern in basename:
            return False

    # Default: most files are compressed
    return True


def write_tga(path: str, width: int, height: int, pixels: list) -> None:
    """
    Write 32-bit RGBA TGA file.
    Matches extract_effect_texture.lua exactly.
    """
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


def extract_wep_spr(input_path: str, output_dir: str) -> None:
    """Extract all sub-sprites from WEP.SPR to TGA files.

    Every sub-sprite (WEP1, EFF1, TRAP1) emits BOTH:
      - `{name}.tga` — indexed-grayscale (R=G=B=index*17, A=255), 256x488 padded
        so the shader can do runtime palette swap (matches the ADR-0022 BODY
        pattern). Default 0-row palette gives the same colors the old RGBA
        bake produced.
      - `{name}.palette.tga` — 16x16 RGBA palette table; y = palette row,
        x = index within row. The shader picks a row at runtime via the
        corresponding palette_row uniform (wep1_palette_row / eff1_palette_row
        / TrapEffect's per-particle palette_row).
    """
    with open(input_path, 'rb') as f:
        data = f.read()

    print(f"Extracting WEP.SPR sub-sprites:")
    print(f"  File size: {len(data)} bytes")

    for name, config in WEP_SPRITES.items():
        offset = config['offset']
        width = config['width']
        height = config['height']

        # Each sub-sprite has its own palette at the start (512 bytes = 256 colors)
        palette = read_palette(data, offset, num_colors=256)

        # Pixel data follows palette (4bpp)
        pixel_start = offset + 512  # 0x200 after sub-sprite start
        pixel_bytes = (width * height) // 2  # 4bpp = 2 pixels per byte
        pixel_data = data[pixel_start:pixel_start + pixel_bytes]

        output_height = WEP_OUTPUT_HEIGHT
        output_path = Path(output_dir) / f"{name}.tga"

        # WEP1 / EFF1 / TRAP1: indexed grayscale + palette companion.
        indices = decode_4bpp_bytes_indices(pixel_data)
        # Pad to the standard output height with index 0 (which is typically
        # transparent in the palette; if it isn't, the alpha bake of palette[0]
        # determines whether the padding is visible — same behaviour as before).
        expected = width * output_height
        if len(indices) < expected:
            indices.extend([0] * (expected - len(indices)))
        indexed_pixels = [(idx * 17, idx * 17, idx * 17, 255) for idx in indices]
        write_tga(str(output_path), width, output_height, indexed_pixels)
        print(f"  Saved indexed:  {output_path} ({width}x{output_height})")

        palette_path = Path(output_dir) / f"{name}.palette.tga"
        palette_pixels = []
        for row in range(16):
            for col in range(16):
                pidx = row * 16 + col
                palette_pixels.append(palette[pidx] if pidx < len(palette) else (0, 0, 0, 255))
        write_tga(str(palette_path), 16, 16, palette_pixels)
        print(f"  Saved palette:  {palette_path} (16x16)")


def extract_spr_indexed(input_path: str, indexed_path: str, palette_path: str,
                        force_no_decompress: bool = False) -> None:
	"""Extract a BODY-sprite SPR file to two outputs:
	  - indexed_path: 256x488 grayscale TGA where each pixel value = palette
	    index 0-15 scaled to 0-255 by multiplying by 17 (the same convention
	    `tools/fft_exporter/exporters/texture.py` uses for the map). Shader
	    decodes as `int(pixel.r * 15.0)` to recover the original index.
	  - palette_path: 16x16 RGBA TGA holding the SPR's full 256-color palette.
	    Layout: col = palette index 0-15 within a row; row = palette row 0-15.
	    Shader samples by `vec2(index/15.0, row/15.0)` (with filter_nearest).

	Per ADR-0022: replaces the pre-baked RGBA output for BODY sprites. WEP /
	OTHER sprites still use extract_spr (RGBA-baked) because their per-layer
	palette concerns are per-equipped-weapon / per-keyframe, not per-unit.

	The portrait region (X:80-127) is NOT pre-applied with a different palette
	row here. The runtime portrait shader (per ADR-0022) consumes the same
	indexed TGA and applies portrait_palette_row at sample time. Default row 8
	preserves the historical humanoid extraction convention.
	"""
	filename = Path(input_path).name.upper()

	with open(input_path, 'rb') as f:
		data = f.read()

	use_compression = should_decompress(filename) and not force_no_decompress
	num_colors = 512 if 'OTHER' in filename.upper() else 256

	print(f"Extracting (indexed): {filename}")
	print(f"  File size: {len(data)} bytes")
	print(f"  Palette colors: {num_colors}")
	print(f"  Compression: {'yes' if use_compression else 'no'}")

	# Read the full palette (all 16 rows × 16 colors). The runtime shader
	# picks one row via the body_palette_row uniform.
	palette = read_palette(data, PALETTE_OFFSET, num_colors)

	# Calculate byte counts (4bpp = 2 pixels per byte)
	top_bytes = (WIDTH * TOP_SECTION_HEIGHT) // 2       # 32768 bytes
	portrait_bytes = (WIDTH * PORTRAIT_HEIGHT) // 2     # 4096 bytes
	compressed_bytes = (WIDTH * COMPRESSED_HEIGHT) // 2 # 25600 bytes

	all_indices: list = []

	if use_compression:
		top_data = data[TOP_SECTION_OFFSET:TOP_SECTION_OFFSET + top_bytes]
		all_indices.extend(decode_4bpp_bytes_indices(top_data))

		compressed_data = data[COMPRESSED_OFFSET:]
		decompressed_data = decompress_section(compressed_data, compressed_bytes)
		all_indices.extend(decode_4bpp_bytes_indices(decompressed_data))

		portrait_data = data[PORTRAIT_OFFSET:PORTRAIT_OFFSET + portrait_bytes]
		all_indices.extend(decode_4bpp_bytes_indices(portrait_data))
	else:
		total_bytes = (WIDTH * HEIGHT) // 2
		pixel_data = data[TOP_SECTION_OFFSET:TOP_SECTION_OFFSET + total_bytes]
		all_indices = decode_4bpp_bytes_indices(pixel_data)

	expected_pixels = WIDTH * HEIGHT
	if len(all_indices) < expected_pixels:
		print(f"  Warning: Only {len(all_indices)} pixels, expected {expected_pixels}")
		all_indices.extend([0] * (expected_pixels - len(all_indices)))
	elif len(all_indices) > expected_pixels:
		all_indices = all_indices[:expected_pixels]

	# Indexed TGA: grayscale RGBA, R=G=B=index*17, A=255. The map exporter
	# uses the same *17 convention; matches `indexed_color.gdshader`'s
	# `indexed.r * 15.0` decode.
	indexed_pixels = [(idx * 17, idx * 17, idx * 17, 255) for idx in all_indices]
	write_tga(indexed_path, WIDTH, HEIGHT, indexed_pixels)
	print(f"  Saved indexed:  {indexed_path} ({WIDTH}x{HEIGHT})")

	# Palette TGA: 16x16 RGBA. Layout: y = palette_row, x = index_within_row.
	# OTHER sprites have 512 colors but the FFT runtime addresses them with
	# the same 16-row model — extra colors live past row 15 and aren't
	# selectable via the body_palette_row uniform. We emit the first 256.
	palette_pixels = []
	for row in range(16):
		for col in range(16):
			pidx = row * 16 + col
			if pidx < len(palette):
				palette_pixels.append(palette[pidx])
			else:
				palette_pixels.append((0, 0, 0, 255))
	write_tga(palette_path, 16, 16, palette_pixels)
	print(f"  Saved palette:  {palette_path} (16x16)")


def extract_spr(input_path: str, output_path: str, force_no_decompress: bool = False,
                portrait_palette: int = 0) -> None:
    """Extract SPR file to TGA.

    Args:
        input_path: Path to input SPR file
        output_path: Path to output TGA file
        force_no_decompress: Skip decompression even if file normally uses it
        portrait_palette: Palette row (0-15) for portrait region. Default 0.
                          FFT portraits often use rows 8-15.
    """
    filename = Path(input_path).name.upper()

    # Special handling for WEP.SPR - extract to multiple files
    if filename == 'WEP.SPR':
        output_dir = Path(output_path).parent
        extract_wep_spr(input_path, str(output_dir))
        return

    with open(input_path, 'rb') as f:
        data = f.read()

    use_compression = should_decompress(filename) and not force_no_decompress

    # OTHER.SPR uses 512 colors
    num_colors = 512 if 'OTHER' in filename.upper() else 256

    print(f"Extracting: {filename}")
    print(f"  File size: {len(data)} bytes")
    print(f"  Palette colors: {num_colors}")
    print(f"  Compression: {'yes' if use_compression else 'no'}")
    if portrait_palette != 0:
        print(f"  Portrait palette row: {portrait_palette}")

    # Read palette
    palette = read_palette(data, PALETTE_OFFSET, num_colors)

    # Calculate byte counts (4bpp = 2 pixels per byte)
    top_bytes = (WIDTH * TOP_SECTION_HEIGHT) // 2      # 32768 bytes
    portrait_bytes = (WIDTH * PORTRAIT_HEIGHT) // 2    # 4096 bytes
    compressed_bytes = (WIDTH * COMPRESSED_HEIGHT) // 2  # 25600 bytes

    all_pixels = []

    # Portrait uses a different palette row (each row is 16 colors)
    portrait_palette_offset = portrait_palette * 16

    if use_compression:
        # Read top section (uncompressed)
        top_data = data[TOP_SECTION_OFFSET:TOP_SECTION_OFFSET + top_bytes]
        all_pixels.extend(decode_4bpp_bytes(top_data, palette))

        # Read and decompress middle section
        compressed_data = data[COMPRESSED_OFFSET:]
        decompressed_data = decompress_section(compressed_data, compressed_bytes)
        all_pixels.extend(decode_4bpp_bytes(decompressed_data, palette))

        # Read portrait rows (uncompressed) - portrait region uses different palette
        portrait_data = data[PORTRAIT_OFFSET:PORTRAIT_OFFSET + portrait_bytes]
        all_pixels.extend(decode_portrait_rows(portrait_data, palette, WIDTH, portrait_palette_offset))
    else:
        # For uncompressed files, read all pixel data sequentially
        total_bytes = (WIDTH * HEIGHT) // 2
        pixel_data = data[TOP_SECTION_OFFSET:TOP_SECTION_OFFSET + total_bytes]
        all_pixels = decode_4bpp_bytes(pixel_data, palette)

    # Verify pixel count
    expected_pixels = WIDTH * HEIGHT
    if len(all_pixels) < expected_pixels:
        print(f"  Warning: Only {len(all_pixels)} pixels, expected {expected_pixels}")
        # Pad with transparent black
        all_pixels.extend([(0, 0, 0, 0)] * (expected_pixels - len(all_pixels)))
    elif len(all_pixels) > expected_pixels:
        all_pixels = all_pixels[:expected_pixels]

    # Write TGA
    write_tga(output_path, WIDTH, HEIGHT, all_pixels)
    print(f"  Saved: {output_path} ({WIDTH}x{HEIGHT})")


def main():
    parser = argparse.ArgumentParser(
        description='Extract FFT SPR sprite files to TGA',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('input', help='Input SPR file')
    parser.add_argument('output', help='Output TGA file')
    parser.add_argument('--no-decompress', action='store_true',
                        help='Skip decompression (for testing)')
    parser.add_argument('--portrait-palette', type=int, default=8, metavar='ROW',
                        help='Palette row (0-15) for portrait region. Default 8 (FFT portrait palette).')

    args = parser.parse_args()

    if not Path(args.input).exists():
        print(f"Error: Input file not found: {args.input}")
        sys.exit(1)

    extract_spr(args.input, args.output, args.no_decompress, args.portrait_palette)


if __name__ == '__main__':
    main()
