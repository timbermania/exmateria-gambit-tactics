"""Manifest export functionality.

Exports map manifest with metadata, lighting, and file references.
"""

import json
from pathlib import Path
from typing import Dict, List

from ..models.lighting import Lighting
from ..parsers.lighting import lighting_to_dict
from ..models.animation import UvAnimation, PaletteAnimation
from ..models.polygon import PolygonType, Polygon
from ..models.palette import Palette


def export_manifest(
    map_name: str,
    arrangement: str,
    time: str,
    weather: str,
    lighting: Lighting,
    uv_animations: List[UvAnimation],
    palette_animations: List[PaletteAnimation],
    polygons: Dict[PolygonType, List[Polygon]],
    palettes: List[Palette],
    output_dir: Path,
    verbose: bool = False,
    texture_animation_slots: List[dict] = None,
    mesh_animation_manifest: dict = None,
    states: List[dict] = None,
) -> None:
    """Export map manifest to JSON.

    Args:
        map_name: Name of the map
        arrangement: Map arrangement state (Primary/Alternate)
        time: Map time (Day/Night)
        weather: Map weather (None/Snow/etc)
        lighting: Lighting data
        uv_animations: UV animation data
        palette_animations: Palette animation data
        polygons: Polygon collection
        palettes: Palette collection
        output_dir: Output directory
        verbose: Enable verbose output
    """
    if verbose:
        print("Exporting manifest...")

    # Count polygons
    total_polygons = sum(len(p) for p in polygons.values())

    # Build lighting data (shared shape — see parsers/lighting.lighting_to_dict).
    lighting_data = lighting_to_dict(lighting)

    # Build animations data. `texture_animations` is the index-stable, all-32-slot
    # view used by event-script {55} Use Field Object (Field Object ID == slot
    # index). The filtered uv_animations/palette_animations lists below are kept
    # for the existing per-map palette-animation render path.
    animations_data = {
        "uv_animations": [],
        "palette_animations": [],
        "texture_animations": texture_animation_slots or [],
    }

    # System B (moving geometry). Present only for maps with a 0x8C chunk; a
    # convenience pointer to mesh_animation.json + anim_meshes/* (the actual
    # data lives in those files). See exporters/mesh_animation.py.
    if mesh_animation_manifest:
        animations_data["mesh_animation"] = mesh_animation_manifest

    for anim in uv_animations:
        animations_data["uv_animations"].append({
            "canvas_x": anim.canvas_x,
            "canvas_y": anim.canvas_y,
            "canvas_texture_page": anim.canvas_texture_page,
            "size_width": anim.size_width,
            "size_height": anim.size_height,
            "first_frame_x": anim.first_frame_x,
            "first_frame_y": anim.first_frame_y,
            "first_frame_texture_page": anim.first_frame_texture_page,
            "frame_count": anim.frame_count,
            "frame_duration": anim.frame_duration,
            "animation_mode": anim.animation_mode.name.replace('_', ''),  # ForwardLooping style
        })

    for anim in palette_animations:
        animations_data["palette_animations"].append({
            "overridden_palette_id": anim.overridden_palette_id,
            "animation_start_index": anim.animation_start_index,
            "frame_count": anim.frame_count,
            "frame_duration": anim.frame_duration,
            "animation_mode": anim.animation_mode.name.replace('_', ''),  # ForwardLooping style
        })

    # Build manifest
    manifest = {
        "map_name": map_name,
        "version": "1.0",
        "state": {
            "arrangement": arrangement,
            "time": time,
            "weather": weather,
        },
        "files": {
            "geometry_gltf": "geometry.gltf",
            "geometry_bin": "geometry.bin",
            "geometry_json": "geometry.json",
            "texture_indexed": "texture_indexed.tga",  # We use TGA
            "palettes": "palettes.json",
            "terrain_json": "terrain.json",
            "terrain_gltf": "terrain.gltf",
        },
        "lighting": lighting_data,
        "animations": animations_data,
        "stats": {
            "polygon_count": total_polygons,
            "palette_count": len(palettes),
            "texture_size": "256x1024",
        },
    }

    # System C — index of every GNS mesh state (arrangement/time/weather +
    # resource type + the directory holding its geometry). Present only on the
    # root manifest of a map that ships ≥1 alternate baked geometry (#131).
    if states is not None:
        manifest["states"] = states

    # Write manifest
    manifest_path = output_dir / "manifest.json"
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    if verbose:
        print(f"  Wrote: manifest.json")
