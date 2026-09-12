#!/usr/bin/env python3
"""
Split map manifest into doodad-level and scene-level concerns.

Reads manifest.json from a map directory and splits it into:
1. Doodad-level manifest: Visual properties (palette/UV animations)
2. Scene-level manifest: Environmental properties (lighting, state)

Usage:
  python tools/split_manifest.py assets/maps/MAP022/
"""

import json
import sys
from pathlib import Path


def split_manifest(map_path: Path) -> None:
    """
    Split manifest.json into doodad and scene manifests.

    Args:
        map_path: Path to map directory (e.g., assets/maps/MAP022/)
    """
    print(f"\n=== SPLITTING MANIFEST: {map_path} ===\n")

    manifest_file = map_path / "manifest.json"

    if not manifest_file.exists():
        print(f"ERROR: manifest.json not found at {manifest_file}")
        sys.exit(1)

    # Load original manifest
    print(f"Loading {manifest_file}...")
    with open(manifest_file, 'r') as f:
        original = json.load(f)

    # Create doodad-level manifest (visual properties intrinsic to doodad)
    doodad_manifest = {}

    # Palette animations are intrinsic to doodad visuals
    if "animations" in original:
        doodad_manifest["animations"] = {}

        if "palette_animations" in original["animations"]:
            doodad_manifest["animations"]["palette_animations"] = original["animations"]["palette_animations"]

        if "uv_animations" in original["animations"]:
            doodad_manifest["animations"]["uv_animations"] = original["animations"]["uv_animations"]

        # Index-stable all-32-slot table; slot index == event-script Field Object ID.
        if "texture_animations" in original["animations"]:
            doodad_manifest["animations"]["texture_animations"] = original["animations"]["texture_animations"]

        # System B moving-geometry pointer (present only for animated maps).
        if "mesh_animation" in original["animations"]:
            doodad_manifest["animations"]["mesh_animation"] = original["animations"]["mesh_animation"]

    # Create scene-level manifest (environmental properties extrinsic to doodad)
    scene_manifest = {}

    # System C "map states" index (ADR-0056): every arrangement/time/weather row
    # with its own environment (sky/ambient/lights) + palette. This is an
    # environmental, scene-level concern — MapComposer reads scene_manifest.json
    # to select the weather/night sky at load — so it belongs here, NOT in the
    # doodad manifest (#131 originally put it in doodad before states[] carried
    # env; same drop-on-split gotcha mesh_animation hit in #130).
    if "states" in original:
        scene_manifest["states"] = original["states"]

    # Scene metadata
    if "map_name" in original:
        scene_manifest["map_name"] = original["map_name"]

    if "version" in original:
        scene_manifest["version"] = original["version"]

    if "state" in original:
        scene_manifest["state"] = original["state"]

    # Lighting is extrinsic scene property
    if "lighting" in original:
        scene_manifest["lighting"] = original["lighting"]

    # Write doodad manifest
    doodad_output = map_path / "manifest_doodad.json"
    print(f"Writing {doodad_output}...")
    with open(doodad_output, 'w') as f:
        json.dump(doodad_manifest, f, indent=2)

    # Write scene manifest
    scene_output = map_path / "scene_manifest.json"
    print(f"Writing {scene_output}...")
    with open(scene_output, 'w') as f:
        json.dump(scene_manifest, f, indent=2)

    # Print summary
    print(f"\n=== SPLIT COMPLETE ===\n")
    print(f"Doodad manifest: {doodad_output}")
    print(f"  - Contains: animations (palette_animations, uv_animations)")
    print(f"\nScene manifest: {scene_output}")
    print(f"  - Contains: map_name, version, state, lighting")
    print()


def main():
    """CLI entry point."""
    if len(sys.argv) != 2:
        print("Usage: python tools/split_manifest.py <map_path>")
        print()
        print("Example:")
        print("  python tools/split_manifest.py assets/maps/MAP022/")
        sys.exit(1)

    map_path = Path(sys.argv[1])

    if not map_path.exists():
        print(f"ERROR: Map path does not exist: {map_path}")
        sys.exit(1)

    if not map_path.is_dir():
        print(f"ERROR: Map path is not a directory: {map_path}")
        sys.exit(1)

    split_manifest(map_path)


if __name__ == "__main__":
    main()
