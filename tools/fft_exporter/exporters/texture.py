"""Texture and palette export functionality."""

import json
from pathlib import Path
from typing import List

from ..models.palette import Palette
from ..parsers.texture import (
    TEXTURE_WIDTH,
    TEXTURE_HEIGHT,
    extract_indexed_pixels,
    indexed_to_grayscale,
)
from .tga import write_grayscale_tga


def export_indexed_texture(raw_texture_data: bytes, output_path: Path) -> None:
    """Export indexed texture as grayscale TGA.

    Pixel values 0-15 are scaled to 0-255 for visibility (multiply by 17).

    Args:
        raw_texture_data: Raw texture resource data
        output_path: Path for output TGA file
    """
    # Extract indexed pixels
    indexed_pixels = extract_indexed_pixels(raw_texture_data)

    # Convert to grayscale
    grayscale_data = indexed_to_grayscale(indexed_pixels)

    # Write as grayscale TGA
    write_grayscale_tga(output_path, TEXTURE_WIDTH, TEXTURE_HEIGHT, grayscale_data)


def export_palettes_json(
    palettes: List[Palette],
    animation_frames: List[Palette],
    output_path: Path,
) -> None:
    """Export palettes and animation frames as JSON.

    Args:
        palettes: List of 16 palettes
        animation_frames: List of animation frame palettes
        output_path: Path for output JSON file
    """
    data = {
        "palettes": [
            palette.to_dict(i) for i, palette in enumerate(palettes)
        ],
        "animation_frames": [
            frame.to_dict(i) for i, frame in enumerate(animation_frames)
        ] if animation_frames else [],
    }

    with open(output_path, 'w') as f:
        json.dump(data, f, indent=2)


def export_textures(
    texture_resource_data: bytes,
    palettes: List[Palette],
    animation_frames: List[Palette],
    output_dir: Path,
    verbose: bool = False,
) -> None:
    """Export texture and palette data.

    Creates:
    - texture_indexed.tga: Grayscale indexed texture
    - palettes.json: Palette colors and animation frames

    Args:
        texture_resource_data: Raw texture resource data
        palettes: List of 16 palettes from mesh resource
        animation_frames: List of animation frame palettes
        output_dir: Output directory
        verbose: Enable verbose output
    """
    if verbose:
        print("Exporting textures and palettes...")
        print(f"  Texture size: {TEXTURE_WIDTH}x{TEXTURE_HEIGHT}")
        print(f"  Palettes: {len(palettes)}")
        if animation_frames:
            print(f"  Animation Frames: {len(animation_frames)}")

    # Export indexed texture as TGA
    texture_path = output_dir / "texture_indexed.tga"
    export_indexed_texture(texture_resource_data, texture_path)

    if verbose:
        print(f"  Wrote: texture_indexed.tga")

    # Export palettes JSON
    palettes_path = output_dir / "palettes.json"
    export_palettes_json(palettes, animation_frames, palettes_path)

    if verbose:
        print(f"  Wrote: palettes.json")
