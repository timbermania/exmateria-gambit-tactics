#!/usr/bin/env python3
"""
Extract a sub-doodad from an existing doodad by specifying tile coordinates.

Usage:
    python tools/extract_doodad.py --source MAP022 --coords "5,12 6,12" --output bridge_2tile
"""

import json
import shutil
from pathlib import Path
from typing import List, Tuple, Set
import argparse


def load_json(path: Path) -> dict:
    """Load and parse JSON file."""
    with open(path, 'r') as f:
        return json.load(f)


def save_json(data: dict, path: Path):
    """Save data as formatted JSON."""
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)


def parse_coords(coord_string: str) -> List[Tuple[int, int]]:
    """
    Parse space-separated coordinate string into list of (x, z) tuples.

    Example: "5,12 6,12" -> [(5, 12), (6, 12)]
    """
    coords = []
    for coord_pair in coord_string.split():
        x, z = coord_pair.split(',')
        coords.append((int(x), int(z)))
    return coords


def calculate_bounds(coords: List[Tuple[int, int]]) -> Tuple[int, int, int, int]:
    """Calculate bounding box: (min_x, max_x, min_z, max_z)."""
    xs = [x for x, z in coords]
    zs = [z for x, z in coords]
    return min(xs), max(xs), min(zs), max(zs)


def extract_terrain(terrain_data: dict, coords: List[Tuple[int, int]], tile_offset_x: int, tile_offset_z: int, geom_offset_x: float, geom_offset_z: float) -> dict:
    """
    Extract terrain tiles at specified coordinates and transform to start at (0,0).

    Returns a sparse grid - bounding box may have None entries for unspecified tiles.
    """
    coord_set = set(coords)
    min_x, max_x, min_z, max_z = calculate_bounds(coords)

    # Calculate output grid size
    width = max_x - min_x + 1
    height = max_z - min_z + 1

    # Create sparse grid
    output_grid = []
    for out_z in range(height):
        row = []
        for out_x in range(width):
            # Calculate source coordinates (use tile offsets)
            src_x = out_x - tile_offset_x
            src_z = out_z - tile_offset_z

            if (src_x, src_z) in coord_set:
                # Extract and transform this tile
                src_tile = terrain_data["terrain"]["level_0"][src_z][src_x]

                # Deep copy and transform
                tile = json.loads(json.dumps(src_tile))  # Deep copy
                tile["x"] = out_x
                tile["z"] = out_z

                # Transform vertex positions (use geometry offsets)
                for vertex in tile["vertices"]:
                    vertex["x"] += geom_offset_x
                    vertex["z"] += geom_offset_z

                row.append(tile)
            else:
                # Empty tile in sparse grid
                row.append(None)
        output_grid.append(row)

    return {
        "terrain": {
            "level_0": output_grid
        }
    }


def extract_geometry(geometry_data: dict, coords: List[Tuple[int, int]], geom_offset_x: float, geom_offset_z: float) -> dict:
    """
    Extract geometry triangles for specified tiles and transform coordinates.

    - Filters triangles by TriangleMetadata.tile_coords (for floor/slopes)
    - Also includes walls (tile_coords=[-1,-1]) if vertices are within bounds
    - Extracts only used vertices
    - Renumbers indices
    - Transforms vertex positions and tile_coords
    """
    coord_set = set(coords)

    # Scan primitives to find triangles belonging to our tiles
    source_vertices = geometry_data["Meshes"]["PrimaryMesh"]["Vertices"]
    source_primitives = geometry_data["Meshes"]["PrimaryMesh"]["Primitives"]

    # First pass: find floor tiles and calculate bounds from their vertices
    floor_vertex_coords = []
    for prim in source_primitives:
        indices = prim["Indices"]
        metadata = prim["TriangleMetadata"]
        for tri_idx in range(len(metadata)):
            tri_meta = metadata[tri_idx]
            tile_x, tile_z = tri_meta["tile_coords"]
            if (tile_x, tile_z) in coord_set:
                # This is a floor tile - collect vertex coordinates
                base_idx = tri_idx * 3
                for vi in [indices[base_idx], indices[base_idx + 1], indices[base_idx + 2]]:
                    v = source_vertices[vi]["Position"]
                    floor_vertex_coords.append((v[0], v[2]))  # X, Z only

    # Calculate bounds from actual floor geometry
    if floor_vertex_coords:
        x_vals = [x for x, z in floor_vertex_coords]
        z_vals = [z for x, z in floor_vertex_coords]
        bounds_min_x, bounds_max_x = min(x_vals), max(x_vals)
        bounds_min_z, bounds_max_z = min(z_vals), max(z_vals)
    else:
        # Fallback: no floor geometry found
        bounds_min_x = bounds_max_x = bounds_min_z = bounds_max_z = 0

    output_primitives = []
    used_vertex_indices = set()

    for prim in source_primitives:
        # Check which triangles belong to our tiles
        included_triangles = []
        included_metadata = []

        indices = prim["Indices"]
        metadata = prim["TriangleMetadata"]

        for tri_idx in range(len(metadata)):
            tri_meta = metadata[tri_idx]
            tile_x, tile_z = tri_meta["tile_coords"]

            include_triangle = False

            # Check 1: Exact tile_coords match (floor/slope geometry)
            if (tile_x, tile_z) in coord_set:
                include_triangle = True
            # Check 2: Wall geometry (tile_coords = [-1,-1]) within bounds
            elif tile_x == -1 and tile_z == -1:
                # Check if all vertices are within bounds
                base_idx = tri_idx * 3
                v0 = source_vertices[indices[base_idx]]["Position"]
                v1 = source_vertices[indices[base_idx + 1]]["Position"]
                v2 = source_vertices[indices[base_idx + 2]]["Position"]

                # All vertices must be within bounds
                all_in_bounds = all(
                    bounds_min_x <= v[0] <= bounds_max_x and bounds_min_z <= v[2] <= bounds_max_z
                    for v in [v0, v1, v2]
                )

                if all_in_bounds:
                    include_triangle = True

            if include_triangle:
                # Include this triangle
                included_triangles.append(tri_idx)
                included_metadata.append(tri_meta)

                # Mark vertices as used
                base_idx = tri_idx * 3
                used_vertex_indices.add(indices[base_idx])
                used_vertex_indices.add(indices[base_idx + 1])
                used_vertex_indices.add(indices[base_idx + 2])

        # If this primitive has any included triangles, create output primitive
        if included_triangles:
            output_prim = {
                "PaletteId": prim["PaletteId"],
                "Indices": [],
                "TriangleMetadata": []
            }

            # Collect indices for included triangles
            for tri_idx in included_triangles:
                base_idx = tri_idx * 3
                output_prim["Indices"].extend([
                    indices[base_idx],
                    indices[base_idx + 1],
                    indices[base_idx + 2]
                ])

            # Transform metadata tile_coords (keep as integers for tile space)
            for tri_meta in included_metadata:
                transformed_meta = {
                    "surface_type": tri_meta["surface_type"],
                    "tile_coords": [
                        tri_meta["tile_coords"][0] + int(round(geom_offset_x)),
                        tri_meta["tile_coords"][1] + int(round(geom_offset_z))
                    ]
                }
                output_prim["TriangleMetadata"].append(transformed_meta)

            output_primitives.append(output_prim)

    # Extract and renumber vertices
    old_to_new = {}
    new_vertices = []

    for old_idx in sorted(used_vertex_indices):
        old_to_new[old_idx] = len(new_vertices)

        # Transform vertex position, preserve other fields (UV, Normal, etc.)
        old_vert = source_vertices[old_idx]
        old_pos = old_vert["Position"]
        new_vert = {
            "Position": [
                old_pos[0] + geom_offset_x,  # x
                old_pos[1],                   # y (unchanged)
                old_pos[2] + geom_offset_z    # z
            ]
        }

        # Copy other vertex attributes (UV, Normal, etc.)
        for key, value in old_vert.items():
            if key != "Position":
                new_vert[key] = value

        new_vertices.append(new_vert)

    # Update indices in output primitives
    for prim in output_primitives:
        prim["Indices"] = [old_to_new[idx] for idx in prim["Indices"]]

    return {
        "Meshes": {
            "PrimaryMesh": {
                "Vertices": new_vertices,
                "Primitives": output_primitives
            }
        }
    }


def extract_doodad(source_name: str, coords: List[Tuple[int, int]], output_name: str):
    """
    Extract a sub-doodad from source doodad.

    Args:
        source_name: Source doodad name (e.g., "MAP022")
        coords: List of (x, z) tile coordinates to extract
        output_name: Output doodad name (e.g., "bridge_2tile")
    """
    # Paths
    source_dir = Path("assets/doodads") / source_name
    output_dir = Path("assets/doodads") / output_name

    # Validate source
    if not source_dir.exists():
        raise FileNotFoundError(f"Source doodad not found: {source_dir}")

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Extracting {len(coords)} tiles from {source_name}...")
    print(f"Coordinates: {coords}")

    # Load source data first
    print("\nLoading source data...")
    terrain_data = load_json(source_dir / "terrain.json")
    geometry_data = load_json(source_dir / "geometry_linked.json")

    # Calculate offset from actual geometry vertices (not tile indices!)
    coord_set = set(coords)
    source_vertices = geometry_data["Meshes"]["PrimaryMesh"]["Vertices"]
    source_primitives = geometry_data["Meshes"]["PrimaryMesh"]["Primitives"]

    # Find all floor tile vertices
    floor_x_coords = []
    floor_z_coords = []
    for prim in source_primitives:
        indices = prim["Indices"]
        metadata = prim["TriangleMetadata"]
        for tri_idx in range(len(metadata)):
            tri_meta = metadata[tri_idx]
            tile_x, tile_z = tri_meta["tile_coords"]
            if (tile_x, tile_z) in coord_set:
                base_idx = tri_idx * 3
                for vi in [indices[base_idx], indices[base_idx + 1], indices[base_idx + 2]]:
                    v = source_vertices[vi]["Position"]
                    floor_x_coords.append(v[0])
                    floor_z_coords.append(v[2])

    # Calculate offset from geometry (FFT coordinate space)
    geom_min_x = min(floor_x_coords)
    geom_min_z = min(floor_z_coords)
    geom_max_x = max(floor_x_coords)
    geom_max_z = max(floor_z_coords)
    offset_x = -geom_min_x
    offset_z = -geom_min_z

    # Calculate tile offsets for grid mapping
    min_x, max_x, min_z, max_z = calculate_bounds(coords)
    tile_offset_x = -min_x
    tile_offset_z = -min_z

    print(f"Tile bounds: ({min_x}, {min_z}) to ({max_x}, {max_z})")
    print(f"Geometry bounds: ({geom_min_x:.2f}, {geom_min_z:.2f}) to ({geom_max_x:.2f}, {geom_max_z:.2f})")
    print(f"Tile offset: ({tile_offset_x}, {tile_offset_z})")
    print(f"Geometry offset: ({offset_x:.2f}, {offset_z:.2f})")
    print(f"Output size: {max_x - min_x + 1} × {max_z - min_z + 1}")

    # Extract terrain
    print("Extracting terrain...")
    output_terrain = extract_terrain(terrain_data, coords, tile_offset_x, tile_offset_z, offset_x, offset_z)

    # Count non-None tiles
    tile_count = sum(1 for row in output_terrain["terrain"]["level_0"] for tile in row if tile is not None)
    print(f"  Extracted {tile_count} tiles")

    # Extract geometry
    print("Extracting geometry...")
    output_geometry = extract_geometry(geometry_data, coords, offset_x, offset_z)

    vertex_count = len(output_geometry["Meshes"]["PrimaryMesh"]["Vertices"])
    triangle_count = sum(len(p["TriangleMetadata"]) for p in output_geometry["Meshes"]["PrimaryMesh"]["Primitives"])
    print(f"  Extracted {vertex_count} vertices, {triangle_count} triangles")

    # Copy supporting files
    print("Copying supporting files...")
    shutil.copy(source_dir / "palettes.json", output_dir / "palettes.json")
    shutil.copy(source_dir / "texture_indexed.png", output_dir / "texture_indexed.png")
    shutil.copy(source_dir / "manifest.json", output_dir / "manifest.json")

    # Save extracted data
    print("Writing output files...")
    save_json(output_terrain, output_dir / "terrain.json")
    save_json(output_geometry, output_dir / "geometry_linked.json")

    print(f"\n✓ Extraction complete: {output_dir}")
    print("\nNext steps:")
    print(f"  1. Run: python tools/split_manifest.py {output_dir}")
    print(f"  2. Test: Load '{output_name}' via DoodadLibrary")


def main():
    parser = argparse.ArgumentParser(
        description="Extract a sub-doodad from an existing doodad by tile coordinates"
    )
    parser.add_argument(
        "--source",
        required=True,
        help="Source doodad name (e.g., MAP022)"
    )
    parser.add_argument(
        "--coords",
        required=True,
        help="Space-separated tile coordinates (e.g., '5,12 6,12')"
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Output doodad name (e.g., bridge_2tile)"
    )

    args = parser.parse_args()

    coords = parse_coords(args.coords)
    extract_doodad(args.source, coords, args.output)


if __name__ == "__main__":
    main()
