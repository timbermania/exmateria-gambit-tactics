"""TGA file writing utilities - no external dependencies.

Based on the Lua implementation in tactics_debug/lua_scripts/effect_editor/utils/bmp.lua
"""

import struct
from pathlib import Path
from typing import List, Tuple


def write_u16_le(value: int) -> bytes:
    """Write a 16-bit little-endian value."""
    return struct.pack('<H', value)


def write_grayscale_tga(path: Path, width: int, height: int, pixels: bytes) -> None:
    """Write an 8-bit grayscale TGA file.

    Args:
        path: Output file path
        width: Image width in pixels
        height: Image height in pixels
        pixels: Grayscale pixel data (1 byte per pixel, top-to-bottom row order)
    """
    parts = []

    # TGA Header (18 bytes)
    parts.append(bytes([0]))         # ID length (0 = no ID)
    parts.append(bytes([0]))         # Color map type (0 = no color map)
    parts.append(bytes([3]))         # Image type (3 = uncompressed grayscale)
    parts.append(bytes(5))           # Color map specification (unused, 5 zero bytes)
    parts.append(write_u16_le(0))    # X origin
    parts.append(write_u16_le(0))    # Y origin
    parts.append(write_u16_le(width))   # Width
    parts.append(write_u16_le(height))  # Height
    parts.append(bytes([8]))         # Bits per pixel (8 = grayscale)
    parts.append(bytes([0x20]))      # Image descriptor (0x20 = top-left origin)

    # Pixel data (already in top-to-bottom order)
    parts.append(pixels)

    # Write to file
    with open(path, 'wb') as f:
        for part in parts:
            f.write(part)


def write_rgba_tga(path: Path, width: int, height: int, pixels: List[Tuple[int, int, int, int]]) -> None:
    """Write a 32-bit RGBA TGA file.

    Args:
        path: Output file path
        width: Image width in pixels
        height: Image height in pixels
        pixels: List of (r, g, b, a) tuples, top-to-bottom row order
    """
    parts = []

    # TGA Header (18 bytes)
    parts.append(bytes([0]))         # ID length
    parts.append(bytes([0]))         # Color map type (0 = no color map)
    parts.append(bytes([2]))         # Image type (2 = uncompressed true-color)
    parts.append(bytes(5))           # Color map specification (unused)
    parts.append(write_u16_le(0))    # X origin
    parts.append(write_u16_le(0))    # Y origin
    parts.append(write_u16_le(width))   # Width
    parts.append(write_u16_le(height))  # Height
    parts.append(bytes([32]))        # Bits per pixel (32 = RGBA)
    parts.append(bytes([0x28]))      # Image descriptor (0x20 = top-left origin, 0x08 = 8 alpha bits)

    # Pixel data (BGRA order for TGA)
    pixel_data = bytearray()
    for r, g, b, a in pixels:
        pixel_data.extend([b, g, r, a])  # BGRA order
    parts.append(bytes(pixel_data))

    # Write to file
    with open(path, 'wb') as f:
        for part in parts:
            f.write(part)
