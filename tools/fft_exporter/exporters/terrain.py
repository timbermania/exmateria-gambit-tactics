"""Terrain export functionality.

Exports terrain grid to JSON and GLTF formats.
"""

import json
import math
import struct
from pathlib import Path
from typing import Any, Dict, List, Tuple

from pygltflib import (
    GLTF2,
    Accessor,
    Asset,
    Attributes,
    Buffer,
    BufferView,
    Mesh,
    Node,
    Primitive,
    Scene,
    FLOAT,
    UNSIGNED_INT,
    SCALAR,
    VEC3,
    VEC4,
    TRIANGLES,
)

from ..models.terrain import Terrain, TerrainTile
from .coordinates import convert_position

# PSX uses 28 position-units per tile (FFT mesh convention). Multiply
# tile-count by this to get the PSX-units extent passed to convert_position.
PSX_UNITS_PER_TILE = 28


def renumber_tile_z(z_psx: int, size_z_tiles: int) -> int:
    """Map a PSX-side tile Z index to our-coord Z (ADR-0052).

    Part of the 180° rotation around X applied at parse time: a tile at
    PSX-z=0 (near corner of the PSX scene) lands at our-coord z = size_z - 1
    (far row of the Godot scene).
    """
    return size_z_tiles - 1 - z_psx


def export_terrain(
    terrain: Terrain,
    output_dir: Path,
    verbose: bool = False,
) -> None:
    """Export terrain to JSON and GLTF files.

    Creates:
    - terrain.json: Terrain grid data with tile properties
    - terrain.gltf + terrain.bin: Debug visualization mesh

    Args:
        terrain: Terrain data
        output_dir: Output directory
        verbose: Enable verbose output
    """
    if verbose:
        print("Exporting terrain...")
        print(f"  Dimensions: {terrain.size_x}x{terrain.size_z}")

    # Export JSON
    json_path = output_dir / "terrain.json"
    _export_terrain_json(terrain, json_path, verbose)

    if verbose:
        print(f"  Wrote: terrain.json")

    # Export GLTF
    gltf_path = output_dir / "terrain.gltf"
    bin_path = output_dir / "terrain.bin"
    _export_terrain_gltf(terrain, gltf_path, bin_path, verbose)

    if verbose:
        print(f"  Wrote: terrain.gltf")
        print(f"  Wrote: terrain.bin")


def _export_terrain_json(
    terrain: Terrain,
    output_path: Path,
    verbose: bool = False,
) -> None:
    """Export terrain as JSON for gameplay/collision."""
    size_z_psx_units = terrain.size_z * PSX_UNITS_PER_TILE
    terrain_data = {
        "terrain": {
            "size_x": terrain.size_x,
            "size_z": terrain.size_z,
            "level_0": _export_tile_level(terrain.level_0_tiles, size_z_psx_units),
            "level_1": _export_tile_level(terrain.level_1_tiles, size_z_psx_units),
        }
    }

    with open(output_path, 'w') as f:
        json.dump(terrain_data, f, indent=2)


def _export_tile_level(
    tiles: List[List[TerrainTile]],
    size_z_psx_units: int,
) -> List[List[Dict]]:
    """Export a single terrain level."""
    rows = []

    size_z_tiles = size_z_psx_units // PSX_UNITS_PER_TILE

    # Reverse row order so JSON row 0 is our-coord z=0 — pairs with the
    # per-tile `z` renumber below so `level_0[z]` still indexes by our-coord z.
    for row in reversed(tiles):
        tile_data_list = []

        for tile in row:
            # Calculate vertices
            raw_vertices = tile.calculate_vertices()

            # Convert to export coordinates
            converted = [
                convert_position(v[0], v[1], v[2], size_z_psx_units)
                for v in raw_vertices
            ]

            # Calculate normal from first 3 vertices
            normal = _calculate_normal(converted[0], converted[1], converted[2])

            tile_data = {
                "x": tile.index_x,
                "z": renumber_tile_z(tile.index_z, size_z_tiles),
                "height": tile.height,
                "depth": tile.depth,
                "slope_height": tile.slope_height,
                "slope_type": tile.slope_type.name,
                "surface_type": tile.surface_type.name,
                "normal": {
                    "x": round(normal[0], 2),
                    "y": round(normal[1], 2),
                    "z": round(normal[2], 2),
                },
                "vertices": [
                    {"x": round(v[0], 2), "y": round(v[1], 2), "z": round(v[2], 2)}
                    for v in converted
                ],
                "impassable": tile.impassable,
                "unselectable": tile.unselectable,
                "pass_through_only": tile.pass_through_only,
                "thickness": tile.thickness,
                "shading": tile.shading,
            }

            tile_data_list.append(tile_data)

        rows.append(tile_data_list)

    return rows


def _calculate_normal(
    v0: Tuple[float, float, float],
    v1: Tuple[float, float, float],
    v2: Tuple[float, float, float],
) -> Tuple[float, float, float]:
    """Calculate normal from 3 vertices using cross product."""
    # Edge vectors
    edge1 = (v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2])
    edge2 = (v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2])

    # Cross product
    nx = edge1[1] * edge2[2] - edge1[2] * edge2[1]
    ny = edge1[2] * edge2[0] - edge1[0] * edge2[2]
    nz = edge1[0] * edge2[1] - edge1[1] * edge2[0]

    # Normalize
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length > 0:
        nx /= length
        ny /= length
        nz /= length

    return (nx, ny, nz)


def _export_terrain_gltf(
    terrain: Terrain,
    gltf_path: Path,
    bin_path: Path,
    verbose: bool = False,
) -> None:
    """Export terrain as GLTF mesh for debugging/visualization."""
    all_positions: List[float] = []
    all_normals: List[float] = []
    all_colors: List[float] = []
    all_indices: List[int] = []

    vertex_offset = 0
    size_z_psx_units = terrain.size_z * PSX_UNITS_PER_TILE

    # Process Level 0
    for row in terrain.level_0_tiles:
        for tile in row:
            vertex_offset = _add_tile_to_buffers(
                tile, vertex_offset, size_z_psx_units,
                all_positions, all_normals, all_colors, all_indices
            )

    # Process Level 1
    for row in terrain.level_1_tiles:
        for tile in row:
            vertex_offset = _add_tile_to_buffers(
                tile, vertex_offset, size_z_psx_units,
                all_positions, all_normals, all_colors, all_indices
            )

    total_vertices = vertex_offset

    # Build binary buffer
    buffer_data = bytearray()

    # Positions (vec3 float)
    positions_offset = len(buffer_data)
    for p in all_positions:
        buffer_data.extend(struct.pack('<f', p))
    positions_length = len(buffer_data) - positions_offset

    # Normals (vec3 float)
    normals_offset = len(buffer_data)
    for n in all_normals:
        buffer_data.extend(struct.pack('<f', n))
    normals_length = len(buffer_data) - normals_offset

    # Colors (vec4 float)
    colors_offset = len(buffer_data)
    for c in all_colors:
        buffer_data.extend(struct.pack('<f', c))
    colors_length = len(buffer_data) - colors_offset

    # Indices
    indices_offset = len(buffer_data)
    for idx in all_indices:
        buffer_data.extend(struct.pack('<I', idx))
    indices_length = len(buffer_data) - indices_offset

    # Write binary file
    with open(bin_path, 'wb') as f:
        f.write(buffer_data)

    # Build GLTF
    gltf = GLTF2(
        asset=Asset(version="2.0", generator="FFT Map Exporter"),
        buffers=[Buffer(byteLength=len(buffer_data), uri="terrain.bin")],
        bufferViews=[
            BufferView(buffer=0, byteOffset=positions_offset, byteLength=positions_length, target=34962),
            BufferView(buffer=0, byteOffset=normals_offset, byteLength=normals_length, target=34962),
            BufferView(buffer=0, byteOffset=colors_offset, byteLength=colors_length, target=34962),
            BufferView(buffer=0, byteOffset=indices_offset, byteLength=indices_length, target=34963),
        ],
        accessors=[
            Accessor(
                bufferView=0, componentType=FLOAT, count=total_vertices, type=VEC3,
                max=[max(all_positions[i::3]) for i in range(3)] if all_positions else [0, 0, 0],
                min=[min(all_positions[i::3]) for i in range(3)] if all_positions else [0, 0, 0],
            ),
            Accessor(bufferView=1, componentType=FLOAT, count=total_vertices, type=VEC3),
            Accessor(bufferView=2, componentType=FLOAT, count=total_vertices, type=VEC4),
            Accessor(bufferView=3, componentType=UNSIGNED_INT, count=len(all_indices), type=SCALAR),
        ],
        meshes=[Mesh(
            name="Terrain",
            primitives=[Primitive(
                attributes=Attributes(POSITION=0, NORMAL=1, COLOR_0=2),
                indices=3,
                mode=TRIANGLES,
            )]
        )],
        nodes=[Node(mesh=0, name="Terrain")],
        scenes=[Scene(nodes=[0])],
        scene=0,
    )

    gltf.save(str(gltf_path))


def _add_tile_to_buffers(
    tile: TerrainTile,
    vertex_offset: int,
    size_z_psx_units: int,
    positions: List[float],
    normals: List[float],
    colors: List[float],
    indices: List[int],
) -> int:
    """Add a terrain tile to the vertex and index buffers."""
    raw_vertices = tile.calculate_vertices()
    converted = [
        convert_position(v[0], v[1], v[2], size_z_psx_units)
        for v in raw_vertices
    ]

    # Get height-based color
    color = _get_height_color(tile.height + tile.depth)

    # Add 4 vertices
    for v in converted:
        positions.extend(v)
        normals.extend([0.0, 1.0, 0.0])  # Up normal
        colors.extend(color)

    # Add two triangles (counterclockwise)
    indices.extend([
        vertex_offset + 0, vertex_offset + 1, vertex_offset + 2,
        vertex_offset + 0, vertex_offset + 2, vertex_offset + 3,
    ])

    return vertex_offset + 4


def _get_height_color(height: int) -> Tuple[float, float, float, float]:
    """Get color based on tile height for visual debugging."""
    # Gradient from blue (low) to green (medium) to red (high)
    normalized = max(0.0, min(1.0, height / 10.0))

    if normalized < 0.5:
        # Blue to green
        t = normalized * 2.0
        return (0.0, t, 1.0 - t, 1.0)
    else:
        # Green to red
        t = (normalized - 0.5) * 2.0
        return (t, 1.0 - t, 0.0, 1.0)
