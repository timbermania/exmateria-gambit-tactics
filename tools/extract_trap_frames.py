#!/usr/bin/env python3
"""
FFT TRAP Frame Definition Generator

Generates frame definitions for TRAP sprite animations.
Animation type 7 = physical hit cloud (Throw Stone dust effect).

The frame definitions describe UV regions and vertex positions for each
animation frame in the TRAP1 sprite sheet.

TRAP1 texture layout (144×256):
- 32×32 dust cloud frames arranged in a grid
- Typical hit cloud uses 4-8 frames expanding outward

Usage:
    python extract_trap_frames.py <output_dir>

Example:
    python extract_trap_frames.py assets/effects/trap
"""

import argparse
import json
from pathlib import Path

# TRAP1 texture dimensions
TEXTURE_WIDTH = 144
TEXTURE_HEIGHT = 256

# Physical hit cloud animation (type 7)
# Based on typical FFT hit effect: starts small, expands, fades
# Frame positions in texture (UV coords)
PHYSICAL_HIT_FRAMES = [
    # Frame 0: Initial small puff (center)
    {"uv": {"x": 0, "y": 0, "width": 32, "height": 32}, "scale": 0.5},
    # Frame 1: Expanding
    {"uv": {"x": 32, "y": 0, "width": 32, "height": 32}, "scale": 0.7},
    # Frame 2: Mid-size
    {"uv": {"x": 64, "y": 0, "width": 32, "height": 32}, "scale": 0.9},
    # Frame 3: Full size
    {"uv": {"x": 96, "y": 0, "width": 32, "height": 32}, "scale": 1.0},
    # Frame 4: Starting to dissipate
    {"uv": {"x": 0, "y": 32, "width": 32, "height": 32}, "scale": 1.0},
    # Frame 5: Fading
    {"uv": {"x": 32, "y": 32, "width": 32, "height": 32}, "scale": 0.9},
    # Frame 6: Nearly gone
    {"uv": {"x": 64, "y": 32, "width": 32, "height": 32}, "scale": 0.7},
    # Frame 7: Final fade
    {"uv": {"x": 96, "y": 32, "width": 32, "height": 32}, "scale": 0.5},
]


def generate_frame_vertices(uv_width: float, uv_height: float, scale: float) -> dict:
    """Generate vertex positions for a frame (centered quad)."""
    # Half-sizes for centered quad
    hw = (uv_width / 2) * scale
    hh = (uv_height / 2) * scale

    return {
        "top_left": [-hw, -hh],
        "top_right": [hw, -hh],
        "bottom_left": [-hw, hh],
        "bottom_right": [hw, hh]
    }


def generate_frames_json(animation_type: int = 7) -> dict:
    """Generate complete frames.json for a TRAP animation type."""
    frames = []

    for i, frame_def in enumerate(PHYSICAL_HIT_FRAMES):
        uv = frame_def["uv"]
        scale = frame_def["scale"]

        frame = {
            "frame_index": i,
            "uv": uv,
            "vertices": generate_frame_vertices(uv["width"], uv["height"], scale),
            "blend_mode": "ADD",
            "semi_trans_mode": 1,  # Standard additive
            "semi_trans_on": True,
            "palette_id": 0,
        }
        frames.append(frame)

    return {
        "animation_type": animation_type,
        "name": "physical_hit_cloud",
        "texture_size": {"width": TEXTURE_WIDTH, "height": TEXTURE_HEIGHT},
        "frame_duration": 2,  # Frames per animation step (at 30 FPS = ~15 FPS animation)
        "total_frames": len(frames),
        "frames": frames
    }


def main():
    parser = argparse.ArgumentParser(
        description='Generate TRAP frame definitions',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('output_dir', help='Output directory for frames.json')
    parser.add_argument('--type', type=int, default=7,
                        help='Animation type (7 = physical hit cloud)')

    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate frames data
    frames_data = generate_frames_json(args.type)

    # Write JSON
    output_path = output_dir / "frames.json"
    with open(output_path, 'w') as f:
        json.dump(frames_data, f, indent=2)

    print(f"Generated: {output_path}")
    print(f"  Animation type: {frames_data['animation_type']}")
    print(f"  Name: {frames_data['name']}")
    print(f"  Total frames: {frames_data['total_frames']}")


if __name__ == '__main__':
    main()
