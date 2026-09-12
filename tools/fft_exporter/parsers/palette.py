"""Palette parsing from mesh resource data."""

from typing import List, Tuple

from ..models.palette import Palette, PaletteColor
from ..utils.binary import read_int32_le, read_uint16_le


# Offset of texture palette pointer in mesh resource header
TEXTURE_PALETTE_POINTER_OFFSET = 68

# Number of palettes and colors
NUM_PALETTES = 16
NUM_COLORS_PER_PALETTE = 16


def parse_color(word: int) -> PaletteColor:
    """Parse a 16-bit color value into a PaletteColor.

    Format: 1-bit transparency, 5-bit blue, 5-bit green, 5-bit red
    Bit 15: Transparency (0 = transparent, 1 = opaque)
    Bits 14-10: Blue
    Bits 9-5: Green
    Bits 4-0: Red

    Args:
        word: 16-bit color value

    Returns:
        PaletteColor with parsed values
    """
    is_transparent = ((word >> 15) & 1) == 0
    blue = (word >> 10) & 0x1F
    green = (word >> 5) & 0x1F
    red = word & 0x1F

    return PaletteColor(
        red=red,
        green=green,
        blue=blue,
        is_transparent=is_transparent,
    )


def parse_palettes(data: bytes) -> Tuple[List[Palette], bool]:
    """Parse palettes from mesh resource data.

    Args:
        data: Raw mesh resource data

    Returns:
        Tuple of (list of 16 palettes, has_palettes flag)
    """
    # Read pointer to palette data
    palette_pointer = read_int32_le(data, TEXTURE_PALETTE_POINTER_OFFSET)

    if palette_pointer == 0:
        return [], False

    palettes: List[Palette] = []
    offset = palette_pointer

    for _ in range(NUM_PALETTES):
        palette = Palette()

        for _ in range(NUM_COLORS_PER_PALETTE):
            word = read_uint16_le(data, offset)
            color = parse_color(word)
            palette.colors.append(color)
            offset += 2

        palettes.append(palette)

    return palettes, True


def parse_palette_animation_frames(data: bytes) -> List[Palette]:
    """Parse palette animation frames from mesh resource data.

    The animation frames are stored at the palette animation pointer.
    Each frame is a full 16-color palette.

    Args:
        data: Raw mesh resource data

    Returns:
        List of animation frame palettes (typically 16 frames)
    """
    # Palette animation pointer at offset 112
    PALETTE_ANIMATION_POINTER_OFFSET = 112
    pointer = read_int32_le(data, PALETTE_ANIMATION_POINTER_OFFSET)

    if pointer == 0:
        return []

    # Read 16 animation frames directly from the pointer
    NUM_ANIMATION_FRAMES = 16

    offset = pointer
    frames: List[Palette] = []

    for _ in range(NUM_ANIMATION_FRAMES):
        palette = Palette()

        for _ in range(NUM_COLORS_PER_PALETTE):
            if offset + 2 > len(data):
                break
            word = read_uint16_le(data, offset)
            color = parse_color(word)
            palette.colors.append(color)
            offset += 2

        if len(palette.colors) == NUM_COLORS_PER_PALETTE:
            frames.append(palette)

    return frames
