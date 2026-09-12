#!/usr/bin/env python3
"""
Preprocess doodad geometry to link triangles with terrain surface types.

This script ports the correlation algorithm from MapGeometryBuilder.gd
(_correlate_triangle_to_terrain) to run at build time instead of runtime.

Reads:
  - doodad/terrain.json (tile data with vertices and surface types)
  - doodad/geometry.json (mesh primitives with vertex indices)

Writes:
  - doodad/geometry_linked.json (geometry with TriangleMetadata arrays)

Usage:
  python tools/preprocess_doodad.py assets/maps/MAP022/
"""

import json
import sys
from pathlib import Path
from typing import Tuple, List, Dict, Any


# Constants (MUST match MapGeometryBuilder.gd exactly)
TILE_SCALE = 1.0 / 0.56  # ≈ 1.786 - converts FFT's 0.56 tiles to 1.0 world units
VERTEX_MATCH_TOLERANCE_XZ = 0.1  # Horizontal precision
VERTEX_MATCH_TOLERANCE_Y = 0.5   # Vertical tolerance for slopes


class Vector3:
    """Simple 3D vector for position calculations."""

    def __init__(self, x: float, y: float, z: float):
        self.x = x
        self.y = y
        self.z = z

    def __repr__(self):
        return f"Vector3({self.x:.3f}, {self.y:.3f}, {self.z:.3f})"


def load_json(filepath: Path) -> Dict[str, Any]:
    """Load and parse JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)


def save_json(filepath: Path, data: Dict[str, Any]) -> None:
    """Save data to JSON file with pretty formatting."""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)


def correlate_triangle_to_terrain(
    v0_idx: int,
    v1_idx: int,
    v2_idx: int,
    all_vertices: List[Dict],
    terrain_level_0: List[List[Dict]]
) -> Tuple[str, List[int]]:
    """
    Match a triangle's vertices to terrain tile vertices.

    Ported from MapGeometryBuilder._correlate_triangle_to_terrain() (lines 274-349).

    Args:
        v0_idx, v1_idx, v2_idx: Vertex indices into shared geometry vertex array
        all_vertices: Shared vertex array from geometry.json
        terrain_level_0: 2D array [z][x] of tile dictionaries from terrain.json

    Returns:
        Tuple of (surface_type: str, tile_coords: [x, z])
        Returns ("Wall", [-1, -1]) if no match found
    """
    epsilon_xz = VERTEX_MATCH_TOLERANCE_XZ
    epsilon_y = VERTEX_MATCH_TOLERANCE_Y

    # Get triangle vertices and convert to world space with TILE_SCALE
    tri_verts = []
    for v_idx in [v0_idx, v1_idx, v2_idx]:
        vertex = all_vertices[v_idx]
        # Apply TILE_SCALE to match terrain data coordinates
        tri_verts.append(Vector3(
            vertex["Position"][0] * TILE_SCALE,
            vertex["Position"][1] * TILE_SCALE,
            vertex["Position"][2] * TILE_SCALE
        ))

    # Check each terrain tile (terrain_level_0 is 2D array: [z][x])
    for z in range(len(terrain_level_0)):
        row = terrain_level_0[z]
        if not isinstance(row, list):
            continue

        for x in range(len(row)):
            tile = row[x]
            if not isinstance(tile, dict):
                continue

            # Note: terrain data uses lowercase keys
            if "vertices" not in tile:
                continue

            # Get tile vertices (4 vertices for quad)
            tile_verts = []
            for v in tile["vertices"]:
                # Terrain vertices need TILE_SCALE applied to match geometry coordinates
                tile_verts.append(Vector3(
                    v["x"] * TILE_SCALE,
                    v["y"] * TILE_SCALE,
                    v["z"] * TILE_SCALE
                ))

            # Track which tile vertices have been matched (prevent duplicates)
            matched_tile_indices = []

            # For each triangle vertex, find which tile vertex it matches (if any)
            for tri_v in tri_verts:
                for tile_idx in range(len(tile_verts)):
                    # Skip if this tile vertex was already matched
                    if tile_idx in matched_tile_indices:
                        continue

                    tile_v = tile_verts[tile_idx]

                    # Check with separate tolerances for XZ and Y
                    dx = abs(tri_v.x - tile_v.x)
                    dy = abs(tri_v.y - tile_v.y)
                    dz = abs(tri_v.z - tile_v.z)

                    if dx < epsilon_xz and dy < epsilon_y and dz < epsilon_xz:
                        matched_tile_indices.append(tile_idx)
                        break  # Found match for this triangle vertex

            # If all 3 triangle vertices matched 3 UNIQUE tile vertices
            if len(matched_tile_indices) == 3:
                surface_type = tile.get("surface_type", "Unknown")
                # Get actual grid coordinates from tile data (don't trust loop indices)
                tile_x = tile.get("x", x)
                tile_z = tile.get("z", z)
                return (surface_type, [tile_x, tile_z])

    # No match = wall, border, or prop
    return ("Wall", [-1, -1])


def preprocess_doodad(doodad_path: Path) -> None:
    """
    Pre-correlate geometry triangles to terrain tiles.

    Reads terrain.json and geometry.json, writes geometry_linked.json
    with TriangleMetadata arrays added to each primitive.

    Args:
        doodad_path: Path to doodad directory (e.g., assets/maps/MAP022/)
    """
    print(f"\n=== PREPROCESSING DOODAD: {doodad_path} ===\n")

    # Load input files
    terrain_file = doodad_path / "terrain.json"
    geometry_file = doodad_path / "geometry.json"
    output_file = doodad_path / "geometry_linked.json"

    if not terrain_file.exists():
        print(f"ERROR: terrain.json not found at {terrain_file}")
        sys.exit(1)

    if not geometry_file.exists():
        print(f"ERROR: geometry.json not found at {geometry_file}")
        sys.exit(1)

    print(f"Loading {terrain_file}...")
    terrain_dict = load_json(terrain_file)
    terrain_level_0 = terrain_dict["terrain"]["level_0"]  # 2D array [z][x]

    print(f"Loading {geometry_file}...")
    geometry = load_json(geometry_file)

    # Statistics
    total_triangles = 0
    surface_type_counts = {}

    # Process each primitive
    primitives = geometry["Meshes"]["PrimaryMesh"]["Primitives"]
    all_vertices = geometry["Meshes"]["PrimaryMesh"]["Vertices"]

    print(f"\nProcessing {len(primitives)} primitives...")

    for prim_idx, primitive in enumerate(primitives):
        indices = primitive["Indices"]
        triangle_metadata = []

        # Process each triangle in this primitive
        for tri_start in range(0, len(indices), 3):
            v0_idx = indices[tri_start]
            v1_idx = indices[tri_start + 1]
            v2_idx = indices[tri_start + 2]

            # Run correlation (ported from MapGeometryBuilder)
            surface_type, tile_coords = correlate_triangle_to_terrain(
                v0_idx, v1_idx, v2_idx,
                all_vertices,
                terrain_level_0
            )

            triangle_metadata.append({
                "surface_type": surface_type,
                "tile_coords": tile_coords
            })

            total_triangles += 1
            surface_type_counts[surface_type] = surface_type_counts.get(surface_type, 0) + 1

        # Add metadata array to primitive
        primitive["TriangleMetadata"] = triangle_metadata

        # Progress indicator every 50 primitives
        if (prim_idx + 1) % 50 == 0:
            print(f"  Processed {prim_idx + 1}/{len(primitives)} primitives...")

    # Write linked geometry
    print(f"\nWriting {output_file}...")
    save_json(output_file, geometry)

    # Print statistics
    print(f"\n=== PREPROCESSING COMPLETE ===\n")
    print(f"Total triangles: {total_triangles}")
    print(f"Output: {output_file}")
    print(f"\nSurface type distribution:")
    for surface_type in sorted(surface_type_counts.keys()):
        count = surface_type_counts[surface_type]
        percentage = (count / total_triangles) * 100
        print(f"  {surface_type:20s}: {count:4d} ({percentage:5.1f}%)")
    print()


def main():
    """CLI entry point."""
    if len(sys.argv) != 2:
        print("Usage: python tools/preprocess_doodad.py <doodad_path>")
        print()
        print("Example:")
        print("  python tools/preprocess_doodad.py assets/maps/MAP022/")
        sys.exit(1)

    doodad_path = Path(sys.argv[1])

    if not doodad_path.exists():
        print(f"ERROR: Doodad path does not exist: {doodad_path}")
        sys.exit(1)

    if not doodad_path.is_dir():
        print(f"ERROR: Doodad path is not a directory: {doodad_path}")
        sys.exit(1)

    preprocess_doodad(doodad_path)


if __name__ == "__main__":
    main()
