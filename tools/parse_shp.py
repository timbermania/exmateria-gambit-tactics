#!/usr/bin/env python3
"""
SHP Binary Parser

Parses FFT SHP (shape) files and outputs JSON matching the existing format.

This implementation matches TacticsG's Shp.gd parsing logic, which uses the SAME
parsing logic for all sprite types (TYPE1, WEP, EFF). The only differences are:
1. Section offsets (pointer table location, frame data start)
2. Section sizes (WEP/EFF has larger pointer table)

The frame data format is IDENTICAL for all sprite types.

Frame Structure (SAME for all sprite types):
- Byte 0:
  - Bits 0-2: num_subframes - 1 (so num_subframes = 1-8)
  - Bits 3-7: rotation_index (lookup into ROTATIONS_DEGREES, 0-31)
- Byte 1:
  - Bit 0: transparency_flag
  - Bits 1-4: byte2_3 (unknown)
  - Bits 5-6: transparency_type
  - Bit 7: byte2_4 (unknown)
- Bytes 2+: Subframe data (4 bytes per subframe × num_subframes)

Subframe/Tile Structure (4 bytes each):
- Byte 0: shift_x (signed int8) - X offset for positioning
- Byte 1: shift_y (signed int8) - Y offset for positioning
- Bytes 2-3: Packed flags (little-endian uint16):
  - Bits 0-4: load_location_x tile index (× 8 for pixels)
  - Bits 5-9: load_location_y tile index (× 8 for pixels)
  - Bits 10-13: rect_size_index (lookup into size table)
  - Bit 14: flip_x
  - Bit 15: flip_y

Reference: TacticsG Shp.gd, ffhacktics.com/wiki/Sprite_Y_Rotation_Table

Usage:
    python tools/parse_shp.py --input TYPE1.SHP --output type1_shp.json
    python tools/parse_shp.py --all  # Parse all SHP files
"""

import argparse
import json
import struct
from pathlib import Path
from typing import Optional

# Default paths — resolve to project-assets/fft-extract via shared helper.
from _repo_paths import battle_dir as _battle_dir, battle_bin as _battle_bin
DEFAULT_SHP_DIR = _battle_dir()
DEFAULT_OUTPUT_DIR = Path(__file__).parent.parent / "assets/sprites/animations"

# Rotation lookup table - computed from original formula: hex_value * 0x5A / 0x400
# Reference: https://ffhacktics.com/wiki/Sprite_Y_Rotation_Table
# Hex values: 0x0000, 0x00b6, 0x0106, 0x012d, 0x0130, 0x0133, 0x0155, 0x01e9,
#             0x0200, 0x0272, 0x02ab, 0x031d, 0x0400, 0x0555, 0x0556, 0x058e,
#             0x05b0, 0x05c7, 0x0600, 0x0639, 0x0672, 0x06ab, 0x06cd, 0x06e3,
#             0x071d, 0x0755
ROTATIONS_DEGREES = [
    0x0000 * 90 / 1024,  # 0: 0.0
    0x00b6 * 90 / 1024,  # 1: 15.996...
    0x0106 * 90 / 1024,  # 2: 23.027...
    0x012d * 90 / 1024,  # 3: 26.455...
    0x0130 * 90 / 1024,  # 4: 26.71875
    0x0133 * 90 / 1024,  # 5: 26.982...
    0x0155 * 90 / 1024,  # 6: 29.970...
    0x01e9 * 90 / 1024,  # 7: 42.978...
    0x0200 * 90 / 1024,  # 8: 45.0
    0x0272 * 90 / 1024,  # 9: 55.01953...
    0x02ab * 90 / 1024,  # 10: 60.029296875
    0x031d * 90 / 1024,  # 11: 70.048...
    0x0400 * 90 / 1024,  # 12: 90.0
    0x0555 * 90 / 1024,  # 13: 119.970...
    0x0556 * 90 / 1024,  # 14: 120.058...
    0x058e * 90 / 1024,  # 15: 124.980...
    0x05b0 * 90 / 1024,  # 16: 127.96875
    0x05c7 * 90 / 1024,  # 17: 129.990...
    0x0600 * 90 / 1024,  # 18: 135.0
    0x0639 * 90 / 1024,  # 19: 140.009...
    0x0672 * 90 / 1024,  # 20: 145.01953...
    0x06ab * 90 / 1024,  # 21: 150.029296875
    0x06cd * 90 / 1024,  # 22: 153.017...
    0x06e3 * 90 / 1024,  # 23: 154.951...
    0x071d * 90 / 1024,  # 24: 160.048...
    0x0755 * 90 / 1024,  # 25: 164.970...
]

# Size lookup table (index 0-15). ROM-derived from BATTLE.BIN's
# `shp_subframe_sizes` table at 0x2d6c8 — 16 entries × 8 bytes, two uint32 LE
# (width, height) per entry, both pre-divided by 8 in ROM (so we ×8 to get
# pixels). Authority: TacticsEngineG `battle_bin_data.gd` `shp_subframe_sizes_start`.
#
# Was hand-typed from ShishiSpriteEditor Tile.cs; index 12 was wrong (hand
# said 48×16, ROM says 40×16). Wrong index-12 sizes caused the spear's
# WEP1 thrust tiles (SHP frames 263-265) to oversample 8 px of width into
# neighbouring weapons in WEP1.tga, rendering as artifacts behind the unit
# during a thrust. Fixed by parsing the ROM table directly (issue #40).
def _load_sizes_from_rom() -> list:
    import struct as _s
    data = _battle_bin().read_bytes()
    TABLE = 0x2d6c8
    return [(_s.unpack_from('<I', data, TABLE + i * 8)[0] * 8,
             _s.unpack_from('<I', data, TABLE + i * 8 + 4)[0] * 8)
            for i in range(16)]

SIZES = _load_sizes_from_rom()


def parse_tile(data: bytes, y_offset: int, rotation: float) -> dict:
    """Parse a single 4-byte tile/subframe.

    Args:
        data: 4 bytes of tile data
        y_offset: Y offset for second half of sprite sheet (0 or 256)
        rotation: Rotation value in degrees (from lookup table)

    Returns: Tile dict matching existing JSON format
    """
    # Signed bytes for location offsets
    x = struct.unpack('b', bytes([data[0]]))[0]
    y = struct.unpack('b', bytes([data[1]]))[0]

    # Flags (little-endian ushort)
    flags = data[2] + data[3] * 256

    reverse_x = bool(flags & 0x4000)
    reverse_y = bool(flags & 0x8000)
    size_index = (flags >> 10) & 0x0F
    tile_x = (flags & 0x1F) * 8
    tile_y = ((flags >> 5) & 0x1F) * 8 + y_offset

    width, height = SIZES[size_index] if size_index < len(SIZES) else (8, 8)

    return {
        "rectangle_x": tile_x,
        "rectangle_y": tile_y,
        "rectangle_width": width,
        "rectangle_height": height,
        "location_x": x,
        "location_y": y,
        "rotation": rotation,
        "revert": reverse_x,
        "invert": reverse_y
    }


def parse_frame(data: bytes, y_offset: int) -> list:
    """Parse a single frame containing multiple tiles/subframes.

    This uses UNIFIED logic for all sprite types (TYPE1, WEP, EFF, etc.)
    matching TacticsG's Shp.gd implementation.

    Args:
        data: Frame data starting at frame offset
        y_offset: Y offset for second half of sprite sheet

    Returns: List of tile dicts (reversed order like ShishiSpriteEditor)
    """
    if len(data) < 2:
        return []

    # Byte 0: bits 0-2 = num_subframes - 1 (1-8 tiles), bits 3-7 = rotation_index.
    # Matches the file-header docstring and TacticsG's Shp.gd line 228
    # (`1 + (byte & 0b111)`). Was wrongly masked as `& 0x03` historically,
    # dropping bit 2 — any frame with byte0 >= 0x04 had ≥4 subframes
    # silently truncated. Surfaced as the Book "reading" flicker on issue
    # #39: TYPE1.SHP frame 129 has byte0=0x04 (5 subframes — body + book
    # + arms), parser emitted only 1 (the book hand), so alternating with
    # frame 128 looked like the body vanishing every 8 ticks.
    byte0 = data[0]
    num_subframes = 1 + (byte0 & 0x07)
    rotation_index = (byte0 >> 3) & 0x1F

    # Look up rotation from table
    if rotation_index < len(ROTATIONS_DEGREES):
        rotation = ROTATIONS_DEGREES[rotation_index]
    else:
        rotation = 0.0

    tiles = []
    for i in range(num_subframes):
        tile_start = 2 + i * 4
        tile_end = tile_start + 4
        if tile_end > len(data):
            break
        tile_data = data[tile_start:tile_end]
        tile = parse_tile(tile_data, y_offset, rotation)
        tiles.append(tile)

    # Reverse order (like ShishiSpriteEditor Frame.cs line 72)
    tiles.reverse()
    return tiles


class SHPParser:
    """Parser for FFT SHP shape files."""

    def parse_file(self, filepath: Path, sprite_name: str = "") -> dict:
        """Parse a SHP file and return JSON-compatible dict.

        Args:
            filepath: Path to SHP file
            sprite_name: Sprite type name (e.g., "TYPE1", "WEP1")

        Returns: Dict keyed by frame index (as string), each containing
                 a list of tile dicts.
        """
        with open(filepath, 'rb') as f:
            data = f.read()

        is_wep = sprite_name.upper() in ("WEP1", "WEP2", "WEP3", "EFF1", "EFF2")

        # Section sizes differ by sprite type (from TacticsG Shp.gd)
        if is_wep:
            section1_length = 0x44  # 68 bytes
            section2_length = 0x800  # 2048 bytes
        else:
            section1_length = 8
            section2_length = 0x400  # 1024 bytes

        # Minimum file size check
        min_size = section1_length + section2_length
        if len(data) < min_size:
            raise ValueError(f"SHP file too small: {filepath}")

        if is_wep:
            return self._parse_wep(data, sprite_name, section1_length, section2_length)
        else:
            return self._parse_standard(data, sprite_name, section1_length, section2_length)

    def _parse_standard(self, data: bytes, sprite_name: str,
                        section1_length: int, section2_length: int) -> dict:
        """Parse standard sprite types (TYPE1, TYPE2, MON, CYOKO, etc.)."""
        # Jump offset (first 4 bytes) - for extended sprite sheets
        jump = struct.unpack_from('<I', data, 0)[0]

        # secondHalf indicator (bytes 4-5)
        second_half = data[4] + data[5] * 256

        # Pointer table starts at section1_length (offset 8 for standard)
        pointer_table_start = section1_length

        # Read frame pointer table
        offsets = [0]  # Always include offset 0
        i = 0
        while True:
            ptr_start = pointer_table_start + 4 + i * 4  # +4 to skip first entry
            if ptr_start + 4 > section1_length + section2_length:
                break
            ptr = struct.unpack_from('<I', data, ptr_start)[0]
            if ptr == 0:
                break
            offsets.append(ptr)
            i += 1

        result = {}
        # Frame data starts at section1_length + section2_length + 2
        frame_data_start = section1_length + section2_length + 2  # 0x40A for standard

        # Parse first half frames
        for frame_idx, offset in enumerate(offsets):
            y_offset = 256 if frame_idx >= second_half else 0
            frame_start = frame_data_start + offset

            if frame_start >= len(data):
                continue

            tiles = parse_frame(data[frame_start:], y_offset)
            if tiles:
                # Add frame metadata to each tile
                for tile_no, tile in enumerate(tiles):
                    tile["pointer_index_no_hex"] = f"0x{frame_idx:02X}"
                    tile["pointer_index_no"] = frame_idx
                    tile["tile_no"] = tile_no

                result[str(frame_idx)] = tiles

        # Parse second half if jump offset indicates extended sprite
        if jump > 8:
            offsets2 = [0]
            i = 0
            while True:
                ptr_start = jump + i * 4 + 4
                if ptr_start + 4 > len(data):
                    break
                ptr = struct.unpack_from('<I', data, ptr_start)[0]
                if ptr == 0:
                    break
                offsets2.append(ptr)
                i += 1

            frame_data_start2 = jump + 0x402
            base_frame_idx = len(result)

            for i, offset in enumerate(offsets2):
                frame_idx = base_frame_idx + i
                y_offset = 256 if i >= second_half else 0
                frame_start = frame_data_start2 + offset

                if frame_start >= len(data):
                    continue

                tiles = parse_frame(data[frame_start:], y_offset)
                if tiles:
                    for tile_no, tile in enumerate(tiles):
                        tile["pointer_index_no_hex"] = f"0x{frame_idx:02X}"
                        tile["pointer_index_no"] = frame_idx
                        tile["tile_no"] = tile_no

                    result[str(frame_idx)] = tiles

        return result

    def _parse_wep(self, data: bytes, sprite_name: str,
                   section1_length: int, section2_length: int) -> dict:
        """Parse WEP/EFF sprite types."""
        # Pointer table: from section1_length to ptr_end (fixed range like old script)
        # Old script: ptr_start = 0x44, ptr_end = 0x6DB for WEP1
        # This gives (0x6DB - 0x44) / 4 + 1 = 422 pointers
        pointer_table_start = section1_length  # 0x44
        pointer_table_end = 0x6DB  # Fixed end like old parse_wep1_shp.py

        # Read frame pointer table (don't break on ptr == 0, it's valid!)
        offsets = []
        ptr_addr = pointer_table_start
        while ptr_addr + 4 <= pointer_table_end + 1:
            ptr = struct.unpack_from('<I', data, ptr_addr)[0]
            offsets.append(ptr)
            ptr_addr += 4

        result = {}
        # Frame data starts at section1_length + section2_length + 2
        frame_data_start = section1_length + section2_length + 2  # 0x846 for WEP/EFF

        for frame_idx, offset in enumerate(offsets):
            frame_start = frame_data_start + offset

            if frame_start >= len(data):
                continue

            # Use unified parse_frame - no is_wep flag needed
            tiles = parse_frame(data[frame_start:], 0)
            if tiles:
                for tile_no, tile in enumerate(tiles):
                    tile["pointer_index_no_hex"] = f"0x{frame_idx:02X}"
                    tile["pointer_index_no"] = frame_idx
                    tile["tile_no"] = tile_no

                result[str(frame_idx)] = tiles

        return result


def parse_all_shp_files(shp_dir: Path, output_dir: Path):
    """Parse all SHP files in directory.

    Note: Some sprite types share SHP files (per ShishiSpriteEditor):
    - RUKA uses MON.SHP
    - TYPE3 and TYPE4 use TYPE1.SHP (standard humanoid shape)
    """
    shp_files = [
        ("TYPE1.SHP", "type1_shp.json", "TYPE1"),
        ("TYPE2.SHP", "type2_shp.json", "TYPE2"),
        ("TYPE1.SHP", "type3_shp.json", "TYPE1"),  # TYPE3 uses TYPE1 shape
        ("TYPE1.SHP", "type4_shp.json", "TYPE1"),  # TYPE4 uses TYPE1 shape
        ("MON.SHP", "mon_shp.json", "MON"),
        ("MON.SHP", "ruka_shp.json", "MON"),      # RUKA uses MON shape
        ("CYOKO.SHP", "cyoko_shp.json", "CYOKO"),
        ("ARUTE.SHP", "arute_shp.json", "ARUTE"),
        ("KANZEN.SHP", "kanzen_shp.json", "KANZEN"),
        ("OTHER.SHP", "other_shp.json", "OTHER"),
        ("WEP1.SHP", "wep1_shp.json", "WEP1"),
        ("WEP2.SHP", "wep2_shp.json", "WEP2"),
        ("EFF1.SHP", "eff1_shp.json", "EFF1"),
        ("EFF2.SHP", "eff2_shp.json", "EFF2"),
    ]

    parser = SHPParser()

    for input_name, output_name, sprite_name in shp_files:
        input_path = shp_dir / input_name
        output_path = output_dir / output_name

        if not input_path.exists():
            print(f"  Skipping {input_name} (not found)")
            continue

        print(f"Parsing {input_name}...")
        try:
            result = parser.parse_file(input_path, sprite_name)

            with open(output_path, 'w') as f:
                json.dump(result, f, indent=4)

            print(f"  -> {output_name} ({len(result)} frames)")
        except Exception as e:
            print(f"  Error: {e}")


def main():
    parser = argparse.ArgumentParser(description="Parse FFT SHP shape files")
    parser.add_argument("--input", type=Path, help="Input SHP file")
    parser.add_argument("--output", type=Path, help="Output JSON file")
    parser.add_argument("--name", type=str, default="", help="Sprite name (TYPE1, WEP1, etc.)")
    parser.add_argument("--all", action="store_true", help="Parse all SHP files")
    parser.add_argument("--shp-dir", type=Path, default=DEFAULT_SHP_DIR,
                       help=f"SHP files directory (default: {DEFAULT_SHP_DIR})")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR,
                       help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})")
    args = parser.parse_args()

    if args.all:
        parse_all_shp_files(args.shp_dir, args.output_dir)
    elif args.input and args.output:
        shp_parser = SHPParser()
        result = shp_parser.parse_file(args.input, args.name)

        with open(args.output, 'w') as f:
            json.dump(result, f, indent=4)

        print(f"Wrote {args.output} ({len(result)} frames)")
    else:
        parser.print_help()
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
