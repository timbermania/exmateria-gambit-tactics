"""Texture parsing from texture resource data."""

from typing import List


# Texture dimensions
TEXTURE_WIDTH = 256
TEXTURE_HEIGHT = 1024


def extract_indexed_pixels(raw_data: bytes) -> List[int]:
    """Extract indexed pixel data from raw texture data.

    Each byte contains 2 pixels (4 bits each).
    Lower nibble = first pixel, upper nibble = second pixel.

    Args:
        raw_data: Raw texture resource data (131072 bytes for 256x1024)

    Returns:
        List of pixel indices (0-15), length = 256 * 1024 = 262144
    """
    pixels: List[int] = []

    for byte in raw_data:
        # Lower nibble = first pixel
        pixel_a = byte & 0x0F
        # Upper nibble = second pixel
        pixel_b = (byte >> 4) & 0x0F
        pixels.append(pixel_a)
        pixels.append(pixel_b)

    return pixels


def indexed_to_grayscale(indexed_pixels: List[int]) -> bytes:
    """Convert indexed pixels to grayscale bytes.

    Scales 0-15 index values to 0-255 grayscale (multiply by 17).

    Args:
        indexed_pixels: List of pixel indices (0-15)

    Returns:
        Grayscale pixel data as bytes
    """
    return bytes(pixel * 17 for pixel in indexed_pixels)
