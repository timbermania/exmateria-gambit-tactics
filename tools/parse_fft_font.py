#!/usr/bin/env python3
"""
Parse FFT bitmap font from BATTLE.BIN

Font format:
- 2200 characters total
- Each character: 35 bytes, 2bpp, 10x14 pixels
- Graphics offset: 0x000E7614
- Width table offset: 0x000FF0FC

Colors (2bpp) — by inspection of decoded 'G'/'o'/'e' glyphs:
- 0x0 = transparent (background)
- 0x1 = main stroke (the bulk of the letter body)
- 0x2 = highlight (top edges of strokes; sparse)
- 0x3 = AA / soft edge (right edges; trails along the main stroke)

So for white dialog text the palette should put the brightest colour at
slot 1, a mid-tone at slot 2 (highlight), and a darker tone at slot 3
(shadow/AA edge).

Output:
- TGA texture atlas with all characters
- JSON metadata with character widths and UV coordinates
"""

import argparse
import json
import struct
import zlib
from pathlib import Path

# Constants from FFT data
GRAPHICS_OFFSET = 0x000E7614
WIDTHS_OFFSET = 0x000FF0FC
CHAR_COUNT = 2200
CHAR_WIDTH = 10
CHAR_HEIGHT = 14
BYTES_PER_CHAR = 35  # 10 * 14 * 2 / 8 = 35 bytes at 2bpp

# FRAME.BIN palette table: 22 × 16 colors × 2 bytes starting at 0x9000.
FRAME_PALETTE_BASE = 0x9000
FRAME_PALETTE_STRIDE = 32  # 16 colors × 2 bytes per palette

# Palette 15 offset in FRAME.BIN — 0x9000 + (15 * 32) = 0x91E0. Kept for
# backwards compat with the `--frame-bin` flag (legacy default).
FRAME_PALETTE_15_OFFSET = FRAME_PALETTE_BASE + 15 * FRAME_PALETTE_STRIDE

# FRAME palette 0 is the boxed-dialog font CLUT (file offset 0x9000).
FRAME_PALETTE_0_OFFSET = FRAME_PALETTE_BASE + 0 * FRAME_PALETTE_STRIDE

# The 16-color dialog font CLUT — FRAME.BIN palette 0 (file offset 0x9000).
# CONFIRMED DYNAMICALLY (2026-06-27): the unit dialogue box renders FRAME pal 0
# (dark body + RED speaker), NOT pal 2 (off-white). All 22 FRAME palettes are
# uploaded resident into VRAM stacked at X=960 rows 496-511; pal 0 sits at row
# 496 (clut id 0x7c3c) and pal 2 at row 498 (0x7cbc). The box glyph primitives
# carry pal 0's clut, not 0x7cbc — the old static "0x7cbc" read picked the wrong
# (off-white) row. Ground-truth match: body slot1 (49,41,32) ≈ (50,41,34)
# dist 2.2; speaker slot9 (106,41,16) ≈ (106,41,18) dist 2.0. See
# handoff_dialog_box_palette_RESOLVED.md.
#
# The font rasterizer FUN_8014bd88 computes
# `final_4bpp_index = glyph_pixel(1..3) + {Color NN}`, so:
#   {Color 00} (body)    → slots 1,2,3
#   {Color 08} (speaker) → slots 9,10,11
# NOTE: pal 0's body ramp is brightness-INVERTED vs the old pal 2 — slot 1 is
# the DARK stroke core (49,41,32) and slot 3 is the LIGHT AA edge (131,123,106)
# that blends into the tan box. The pixel-level→slot mapping (px1→slot1/9,
# px2→slot2/10, px3→slot3/11) is unchanged. RGB is RGB-555→888 (v*255//31).
DIALOG_CLUT = [
    (0, 0, 0, 0),            # 0  transparent
    (49, 41, 32, 255),       # 1  body stroke (px1)  — dark core
    (82, 82, 65, 255),       # 2  body highlight (px2)
    (131, 123, 106, 255),    # 3  body AA/edge (px3)  — light, blends to box
    (156, 148, 123, 255),    # 4
    (98, 90, 74, 255),       # 5
    (115, 106, 90, 255),     # 6
    (139, 131, 115, 255),    # 7
    (164, 156, 131, 255),    # 8
    (106, 41, 16, 255),      # 9  speaker stroke (px1) — RED core
    (123, 74, 57, 255),      # 10 speaker highlight (px2)
    (139, 123, 106, 255),    # 11 speaker AA (px3)
    (172, 164, 139, 255),    # 12
    (32, 24, 16, 255),       # 13
    (115, 106, 82, 255),     # 14
    (213, 205, 172, 255),    # 15
]

# The baked RGBA atlas uses the OFF-WHITE general ramp = FRAME palette 2 body
# (slots 0-3). This is the shared atlas for ALL text: general UI / menus and
# the chapel-prayer overlay (DialogueOverlay) render it DIRECTLY (atlas pixels
# tinted white). The boxed DialogueBox is the EXCEPTION — it does NOT render the
# atlas directly; both its {Color 00} body run AND its {Color 08} speaker run
# are recolored at runtime to DIALOG_CLUT (FRAME pal 0, dark+red) via the
# shader's 3-level nearest-match CUSTOM remap. So the atlas stays off-white
# (don't bake the box palette into it, or every menu would go dark). The
# shader's reference-match colors (ui_font_char.gdshader) MUST equal the three
# off-white slots 1-3 below.
ATLAS_PALETTE = [
    (0, 0, 0, 0),            # 0  transparent
    (238, 238, 230, 255),    # 1  stroke (px1)  — off-white, FRAME pal 2 slot 1
    (156, 156, 148, 255),    # 2  highlight (px2)
    (82, 82, 74, 255),       # 3  AA/shadow (px3)
]
DEFAULT_PALETTE = ATLAS_PALETTE


def read_frame_palette_15(frame_bin_path: Path) -> list:
    """Read palette 15 from FRAME.BIN at offset 0x91E0.

    FFT uses 16-bit colors: 0BBBBBGGGGGRRRRR (5 bits per channel, MSB unused)
    Palette 15 contains the 4 colors used for the 2bpp font.
    """
    with open(frame_bin_path, 'rb') as f:
        f.seek(FRAME_PALETTE_15_OFFSET)
        data = f.read(8)  # Only need first 4 colors (2 bytes each)

    palette = []
    for i in range(4):
        color16 = struct.unpack_from('<H', data, i * 2)[0]
        # Extract 5-bit channels and scale to 8-bit
        r = (color16 & 0x1F) * 8
        g = ((color16 >> 5) & 0x1F) * 8
        b = ((color16 >> 10) & 0x1F) * 8
        # Index 0 is transparent, others are opaque
        a = 0 if (i == 0 or (r == 0 and g == 0 and b == 0)) else 255
        palette.append((r, g, b, a))

    return palette


def read_frame_palette(frame_bin_path: Path, idx: int = 0) -> list:
    """Read a full 16-color FRAME.BIN palette as RGBA tuples.

    FRAME.BIN holds 22 palettes of 16 RGB-555 colors at 0x9000 (32 B each).
    Palette 0 is the boxed-dialog CLUT (dark body slots 1-3 + red speaker
    slots 9-11) — see handoff_dialog_box_palette_RESOLVED.md. RGB-555→888 uses
    v*255//31 (matches the hardcoded DIALOG_CLUT fallback exactly).
    """
    off = FRAME_PALETTE_BASE + idx * FRAME_PALETTE_STRIDE
    with open(frame_bin_path, 'rb') as f:
        f.seek(off)
        data = f.read(FRAME_PALETTE_STRIDE)

    palette = []
    for i in range(16):
        c = struct.unpack_from('<H', data, i * 2)[0]
        r = (c & 0x1F) * 255 // 31
        g = ((c >> 5) & 0x1F) * 255 // 31
        b = ((c >> 10) & 0x1F) * 255 // 31
        a = 0 if i == 0 else 255
        palette.append((r, g, b, a))
    return palette

# FFT Character Encoding Map (font index → character).
#
# The font index is the byte value that selects a glyph from BATTLE.BIN's
# 2200-glyph table. The byte-sequence encoding (what an FFT text byte
# stream encodes to which font index) follows the BuildVersion3Charmap port
# in `extract_psx_charmap.py`:
#
#   - font_index 0..0xCF       → 1-byte key = font_index
#   - font_index 0xD0..2199    → 2-byte key = 0xD100 + 0x100*bucket + offset
#                                where bucket = (font_index - 0xD0) // 0xD0
#                                and   offset = (font_index - 0xD0) % 0xD0
#
# `psx_charmap.json` (extracted from FFTPatcher's PSXMap) is keyed on those
# byte-sequence keys and maps each to its DECODED character (e.g. 0xDA74 →
# `,`, the full-width comma). We invert that ordering here so the bake can
# emit per-font-index records carrying BOTH the decoded char (when single
# printable) AND the raw byte-sequence hex (for renderers that key glyph
# lookups on the original byte stream).
_PSX_CHARMAP_PATH = Path(__file__).parent / "data" / "psx_charmap.json"


def _byte_sequence_for_font_index(i: int) -> str:
    """Inverse of BuildVersion3Charmap: font index → 2-hex-digit byte string
    (for single-byte) or 4-hex-digit (for multi-byte 0xD1XX..0xDAXX)."""
    if i < 0xD0:
        return f"{i:02X}"
    j = i - 0xD0
    bucket = j // 0xD0
    offset = j % 0xD0
    key = 0xD100 + 0x100 * bucket + offset
    return f"{key:04X}"


def _load_fft_char_map() -> tuple[dict[int, str], dict[int, str]]:
    """Return (font_index → printable_char, font_index → byte_seq_hex).

    Only `font_index → printable_char` entries with a SINGLE-glyph mapping
    are returned (control codes like `{Newline}`, multi-char macros like
    `{Ramza}`, and `<HH>`-style fallbacks are skipped). The byte-sequence
    map is exhaustive — every font index 0..2199 gets one.
    """
    raw = json.loads(_PSX_CHARMAP_PATH.read_text(encoding="utf-8"))
    raw_int = {int(k): v for k, v in raw.items()}
    by_char: dict[int, str] = {}
    by_bytes: dict[int, str] = {}
    for font_idx in range(CHAR_COUNT):
        seq = _byte_sequence_for_font_index(font_idx)
        by_bytes[font_idx] = seq
        key = int(seq, 16)
        value = raw_int.get(key)
        if not isinstance(value, str):
            continue
        if value.startswith("{"):
            continue  # macro/control like {Newline}, {Color XX}
        if len(value) != 1:
            continue  # multi-char fallback string
        by_char[font_idx] = value
    return by_char, by_bytes


FFT_CHAR_MAP, FFT_BYTES_MAP = _load_fft_char_map()

# Build reverse map (character -> index) for encoding. Only single-byte
# slots — multi-byte slots with the same character would clobber the
# half-width entry, which the encoder path doesn't want.
CHAR_TO_FFT = {char: idx for idx, char in FFT_CHAR_MAP.items() if idx < 0x100}


# Renderer char -> atlas-index map (baked into font_meta.json's char_to_index).
# Unlike the encoder map, this MUST cover glyphs that only exist in a multi-byte
# slot (idx >= 0x100) — e.g. the dialogue comma ',' lives ONLY at font index
# 2196 (byte-seq 0xDA74). Without it the renderer falls back to '?' (G1 bug,
# dialogue_box_geometry_and_fidelity_decode.md). Start from the single-byte map
# (so existing half-width ASCII wins) and add multi-byte glyphs only for chars
# not already present — never clobbering a half-width entry.
def _build_render_char_map() -> dict[str, int]:
    render = dict(CHAR_TO_FFT)
    for font_idx, char in FFT_CHAR_MAP.items():
        if font_idx < 0x100:
            continue
        render.setdefault(char, font_idx)
    return render


CHAR_TO_INDEX_RENDER = _build_render_char_map()


def decode_2bpp_char(data: bytes) -> list[list[int]]:
    """Decode a 2bpp character graphic to a 2D pixel array.

    FFT stores 4 pixels per byte, MSB first (bits 7-6 = pixel 0, bits 5-4 = pixel 1, etc.)
    Each byte contains 4 pixels at 2 bits each.
    """
    pixels = [[0] * CHAR_WIDTH for _ in range(CHAR_HEIGHT)]

    bit_index = 0
    for y in range(CHAR_HEIGHT):
        for x in range(CHAR_WIDTH):
            byte_idx = bit_index // 8
            bit_in_byte = bit_index % 8

            if byte_idx < len(data):
                byte_val = data[byte_idx]
                # MSB first: bits 7-6 = pixel 0, bits 5-4 = pixel 1, etc.
                # So for bit_in_byte 0,2,4,6 we shift by 6,4,2,0
                shift = 6 - bit_in_byte
                pixel_val = (byte_val >> shift) & 0x03
                pixels[y][x] = pixel_val

            bit_index += 2

    return pixels


def create_tga(width: int, height: int, pixels: list[tuple[int, int, int, int]], output_path: Path):
    """Create a 32-bit RGBA TGA file."""
    with open(output_path, 'wb') as f:
        # TGA header (18 bytes)
        f.write(bytes([
            0,          # ID length
            0,          # Color map type (none)
            2,          # Image type (uncompressed true-color)
            0, 0, 0, 0, 0,  # Color map specification (unused)
            0, 0,       # X origin
            0, 0,       # Y origin
            width & 0xFF, (width >> 8) & 0xFF,   # Width
            height & 0xFF, (height >> 8) & 0xFF, # Height
            32,         # Bits per pixel
            0x28,       # Image descriptor (top-left origin, 8 alpha bits)
        ]))

        # Write pixels (BGRA order for TGA)
        for pixel in pixels:
            r, g, b, a = pixel
            f.write(bytes([b, g, r, a]))


def create_png(width: int, height: int, pixels: list[tuple[int, int, int, int]], output_path: Path):
    """Create a 32-bit RGBA PNG file (no external dependencies)."""

    def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
        """Create a PNG chunk with CRC."""
        chunk_len = struct.pack(">I", len(data))
        chunk_crc = struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
        return chunk_len + chunk_type + data + chunk_crc

    # PNG signature
    signature = b'\x89PNG\r\n\x1a\n'

    # IHDR chunk (image header)
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    # 8 = bit depth, 6 = RGBA color type

    # IDAT chunk (image data)
    raw_data = bytearray()
    for y in range(height):
        raw_data.append(0)  # Filter byte (none)
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw_data.extend([r, g, b, a])

    compressed = zlib.compress(bytes(raw_data), 9)

    # IEND chunk (image end)
    with open(output_path, 'wb') as f:
        f.write(signature)
        f.write(png_chunk(b'IHDR', ihdr_data))
        f.write(png_chunk(b'IDAT', compressed))
        f.write(png_chunk(b'IEND', b''))


def debug_char(data: bytes, char_idx: int = 0):
    """Print debug info for a character's raw bytes and decoded pixels."""
    char_start = char_idx * BYTES_PER_CHAR
    char_data = data[char_start:char_start + BYTES_PER_CHAR]

    print(f"\n=== Debug char {char_idx} ===")
    print(f"Raw bytes ({len(char_data)}): {' '.join(f'{b:02X}' for b in char_data[:16])}...")

    pixels = decode_2bpp_char(char_data)
    print("Decoded pixels (. = 0, 1-3 shown as digit):")
    for y, row in enumerate(pixels):
        line = ''.join('.' if p == 0 else str(p) for p in row)
        print(f"  {y:2d}: {line}")


def parse_font(battle_bin_path: Path, output_dir: Path, debug: bool = False,
                dialog_clut: list = None, atlas_palette: list = None):
    """Parse FFT font and create texture atlas + metadata.

    `atlas_palette` is the 4-color OFF-WHITE ramp (transparent + slots 1-3)
    baked into the shared atlas — used directly by menus and the prayer overlay.
    `dialog_clut` is the full 16-color BOX CLUT (FRAME pal 0, dark+red) written
    to `font_meta.json`; the DialogueBox reads its body ramp (slots 1-3) and
    speaker ramp (slots 9-11) from there and remaps the off-white atlas to them
    at runtime via the shader. The two are intentionally DIFFERENT palettes.
    """
    if dialog_clut is None:
        dialog_clut = DIALOG_CLUT
    if atlas_palette is None:
        atlas_palette = ATLAS_PALETTE
    palette = atlas_palette

    print(f"Reading {battle_bin_path}...")

    with open(battle_bin_path, 'rb') as f:
        # Read character graphics
        f.seek(GRAPHICS_OFFSET)
        graphics_data = f.read(BYTES_PER_CHAR * CHAR_COUNT)

        # Read character widths
        f.seek(WIDTHS_OFFSET)
        widths_data = f.read(CHAR_COUNT)

    print(f"Loaded {len(graphics_data)} bytes of graphics, {len(widths_data)} bytes of widths")

    if debug:
        # Debug first few characters
        for i in [0, 1, 10, 36]:  # '0', '1', 'A', 'a'
            debug_char(graphics_data, i)

    # Calculate atlas dimensions (arrange in grid)
    # Use 64 characters per row for a reasonable texture size
    chars_per_row = 64
    rows = (CHAR_COUNT + chars_per_row - 1) // chars_per_row

    atlas_width = chars_per_row * CHAR_WIDTH
    atlas_height = rows * CHAR_HEIGHT

    print(f"Creating {atlas_width}x{atlas_height} atlas ({chars_per_row} chars/row, {rows} rows)")

    # Initialize atlas with transparent pixels
    atlas_pixels = [(0, 0, 0, 0)] * (atlas_width * atlas_height)

    # Character metadata
    char_metadata = {
        "char_width": CHAR_WIDTH,
        "char_height": CHAR_HEIGHT,
        "atlas_width": atlas_width,
        "atlas_height": atlas_height,
        "chars_per_row": chars_per_row,
        "char_to_index": CHAR_TO_INDEX_RENDER,  # char -> atlas index (incl. multi-byte-only glyphs like ',')
        # ROM-dumped 16-color dialog CLUT (see DIALOG_CLUT). Renderers read the
        # speaker ramp (slots 9-11) and body ramp (slots 1-3) from here so the
        # colors are sourced from the dump, not hardcoded per renderer.
        "dialog_clut": [[r, g, b, a] for (r, g, b, a) in dialog_clut],
        "characters": {}
    }

    # Process each character
    for char_idx in range(CHAR_COUNT):
        # Extract character graphic data
        char_start = char_idx * BYTES_PER_CHAR
        char_data = graphics_data[char_start:char_start + BYTES_PER_CHAR]

        # Get character width
        char_width = widths_data[char_idx] if char_idx < len(widths_data) else CHAR_WIDTH

        # Decode 2bpp to pixels
        char_pixels = decode_2bpp_char(char_data)

        # Calculate position in atlas
        atlas_col = char_idx % chars_per_row
        atlas_row = char_idx // chars_per_row
        atlas_x = atlas_col * CHAR_WIDTH
        atlas_y = atlas_row * CHAR_HEIGHT

        # Copy character to atlas
        for y in range(CHAR_HEIGHT):
            for x in range(CHAR_WIDTH):
                pixel_val = char_pixels[y][x]
                color = palette[pixel_val]

                pixel_idx = (atlas_y + y) * atlas_width + (atlas_x + x)
                atlas_pixels[pixel_idx] = color

        # Store metadata
        char_entry = {
            "width": char_width,
            "atlas_x": atlas_x,
            "atlas_y": atlas_y,
        }
        # Add character representation if known
        if char_idx in FFT_CHAR_MAP:
            char_entry["char"] = FFT_CHAR_MAP[char_idx]
        char_metadata["characters"][str(char_idx)] = char_entry

    # Write atlas TGA
    output_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = output_dir / "font_atlas.tga"
    create_tga(atlas_width, atlas_height, atlas_pixels, atlas_path)
    print(f"Wrote {atlas_path}")

    # Write metadata JSON
    meta_path = output_dir / "font_meta.json"
    with open(meta_path, 'w') as f:
        json.dump(char_metadata, f, indent=2)
    print(f"Wrote {meta_path}")

    # Print sample character info
    print("\nSample characters (0-9, A-Z, a-z, punctuation):")
    for i in range(min(90, CHAR_COUNT)):
        w = widths_data[i] if i < len(widths_data) else 0
        char_repr = FFT_CHAR_MAP.get(i, "?")
        print(f"  {i:3d} (0x{i:02X}) = '{char_repr}' width={w}")


def main():
    parser = argparse.ArgumentParser(description="Parse FFT bitmap font from BATTLE.BIN")
    parser.add_argument("battle_bin", type=Path, help="Path to BATTLE.BIN")
    parser.add_argument("-o", "--output", type=Path, default=Path("assets/fonts"),
                        help="Output directory (default: assets/fonts)")
    parser.add_argument("-d", "--debug", action="store_true",
                        help="Print debug info for sample characters")
    parser.add_argument("--frame-bin", type=Path, default=None,
                        help="Path to FRAME.BIN to extract the dialog CLUT "
                             "(FRAME palette 0 — dark body + red speaker)")
    args = parser.parse_args()

    if not args.battle_bin.exists():
        print(f"Error: {args.battle_bin} not found")
        return 1

    # Atlas = FRAME pal 2 (off-white, shared by menus + prayer overlay).
    # Box CLUT = FRAME pal 0 (dark body + red speaker), written to metadata.
    if args.frame_bin:
        if not args.frame_bin.exists():
            print(f"Error: {args.frame_bin} not found")
            return 1
        print(f"Reading FRAME palettes from {args.frame_bin}...")
        atlas_palette = read_frame_palette(args.frame_bin, 2)[0:4]
        dialog_clut = read_frame_palette(args.frame_bin, 0)
        print(f"  atlas (off-white) slots 1-3: {atlas_palette[1:4]}")
        print(f"  box body slots 1-3:          {dialog_clut[1:4]}")
        print(f"  box speaker slots 9-11:      {dialog_clut[9:12]}")
    else:
        print("No --frame-bin provided, using hardcoded palettes "
              "(atlas=pal2 off-white, box=pal0)")
        atlas_palette = ATLAS_PALETTE
        dialog_clut = DIALOG_CLUT

    parse_font(args.battle_bin, args.output, args.debug, dialog_clut, atlas_palette)
    return 0


if __name__ == "__main__":
    exit(main())
