"""Geometry export functionality.

Exports FFT polygon geometry to GLTF and JSON formats.
"""

import json
import struct
from pathlib import Path
from typing import Any, Dict, List, Tuple
from collections import defaultdict

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
    VEC2,
    VEC3,
    TRIANGLES,
)
import base64

from ..models.polygon import MeshType, Polygon, PolygonType
from .coordinates import convert_position, convert_normal, convert_uv


def export_geometry(
    polygons: Dict[PolygonType, List[Polygon]],
    output_dir: Path,
    size_z_psx_units: int,
    verbose: bool = False,
) -> None:
    """Export geometry to GLTF and JSON files.

    Creates:
    - geometry.gltf: GLTF file with embedded binary data
    - geometry.bin: Binary buffer (separate file)
    - geometry.json: JSON mesh data for procedural building

    Args:
        polygons: Dictionary mapping PolygonType to list of Polygons
        output_dir: Output directory
        size_z_psx_units: PSX-unit depth of the map (size_z_tiles * 28),
            passed through to convert_position for the parser-time Z flip
            (ADR-0052).
        verbose: Enable verbose output
    """
    if verbose:
        print("Exporting geometry...")

    # Export JSON first (simpler, for verification)
    json_path = output_dir / "geometry.json"
    _export_geometry_json(polygons, json_path, size_z_psx_units, verbose)

    if verbose:
        print(f"  Wrote: geometry.json")

    # Export GLTF
    gltf_path = output_dir / "geometry.gltf"
    bin_path = output_dir / "geometry.bin"
    _export_geometry_gltf(polygons, gltf_path, bin_path, size_z_psx_units, verbose)

    if verbose:
        print(f"  Wrote: geometry.gltf")
        print(f"  Wrote: geometry.bin")


def _export_geometry_json(
    polygons: Dict[PolygonType, List[Polygon]],
    output_path: Path,
    size_z_psx_units: int,
    verbose: bool = False,
) -> None:
    """Export geometry as JSON for procedural mesh building."""
    # Collect all polygons
    all_polygons: List[Polygon] = []
    for poly_type in [
        PolygonType.TEXTURED_TRIANGLE,
        PolygonType.TEXTURED_QUAD,
        PolygonType.UNTEXTURED_TRIANGLE,
        PolygonType.UNTEXTURED_QUAD,
    ]:
        all_polygons.extend(polygons[poly_type])

    # Group by palette (textured) or untextured
    textured_by_palette: Dict[int, List[Polygon]] = defaultdict(list)
    untextured: List[Polygon] = []

    for polygon in all_polygons:
        if polygon.is_textured:
            textured_by_palette[polygon.palette_id].append(polygon)
        else:
            untextured.append(polygon)

    # Build JSON structure
    mesh_data = {
        "Vertices": [],
        "Primitives": [],
    }

    vertices = mesh_data["Vertices"]

    # Process each palette group (sorted by palette ID)
    for palette_id in sorted(textured_by_palette.keys()):
        palette_polys = textured_by_palette[palette_id]

        primitive = {
            "Name": f"Palette{palette_id}",
            "PaletteId": palette_id,
            "Indices": [],
            "FaceCentroids": [],
            "VisibleAngles": [],
            "PolygonCount": len(palette_polys),
        }

        for polygon in palette_polys:
            _add_polygon_to_json(polygon, size_z_psx_units, vertices, primitive["Indices"], primitive["FaceCentroids"], primitive["VisibleAngles"])

        mesh_data["Primitives"].append(primitive)

        if verbose:
            print(f"    Palette {palette_id}: {len(palette_polys)} polygons")

    # Process untextured polygons
    if untextured:
        primitive = {
            "Name": "Untextured",
            "PaletteId": None,
            "Indices": [],
            "FaceCentroids": [],
            "VisibleAngles": [],
            "PolygonCount": len(untextured),
        }

        for polygon in untextured:
            _add_polygon_to_json(polygon, size_z_psx_units, vertices, primitive["Indices"], primitive["FaceCentroids"], primitive["VisibleAngles"])

        mesh_data["Primitives"].append(primitive)

        if verbose:
            print(f"    Untextured: {len(untextured)} polygons")

    # Wrap in Meshes structure (matching C# output).
    json_data = {
        "Meshes": {
            "PrimaryMesh": mesh_data,
        }
    }

    with open(output_path, 'w') as f:
        json.dump(json_data, f, indent=2)


def _add_polygon_to_json(
    polygon: Polygon,
    size_z_psx_units: int,
    vertices: List[Dict],
    indices: List[int],
    face_centroids: List[List[float]],
    visible_angles: List[int],
) -> None:
    """Add a polygon to JSON vertex, index, and face centroid lists."""
    start_index = len(vertices)
    vertex_count = 4 if polygon.is_quad else 3

    # Add vertices
    positions = []
    for i in range(vertex_count):
        v = polygon.vertices[i]
        pos = convert_position(v.x, v.y, v.z, size_z_psx_units)
        normal = convert_normal(v.normal_elevation, v.normal_azimuth)

        if polygon.is_textured and polygon.uv_coordinates:
            uv = convert_uv(
                polygon.uv_coordinates[i][0],
                polygon.uv_coordinates[i][1],
                polygon.texture_page
            )
        else:
            uv = (0.0, 0.0)

        positions.append(pos)
        vertices.append({
            "Position": list(pos),
            "Normal": list(normal),
            "UV": list(uv),
        })

    # Compute face centroid (GTE AVSZ4 for quads, AVSZ3 for triangles)
    # For quads: average of all 4 original vertices (both triangles share this)
    # For triangles: average of 3 vertices
    centroid = [
        sum(p[i] for p in positions) / len(positions)
        for i in range(3)
    ]

    # Triangle indices. ADR-0052 Z-flip flips the winding direction of both
    # quad triangles relative to the pre-fix pipeline, so both need to be
    # reversed (not just tri1 as the prior code did). FFT N-shape quad
    # vertex order is v0=NW, v1=NE, v2=SW, v3=SE with diagonal v1-v2:
    # tri1 was (v0,v2,v1) → now (v0,v1,v2); tri2 was (v1,v2,v3) → now (v1,v3,v2).
    #
    # The per-polygon visible-angles cull table (mesh +0xB0) is emitted RAW — it
    # is NOT remapped for the ADR-0052 180°-about-X flip. That table is indexed
    # by the *live PSX camera angle*, not by geometry orientation: at runtime we
    # feed the shader the true PSX camera angle (PlayerCamera → psx_camera_angle),
    # so the ROM-authored bits apply as-is regardless of how the geometry was
    # rotated for display. (Issue #135 briefly remapped it here on the theory that
    # the flip negated the view azimuth; that double-counted the flip and
    # over-culled ~13% of the map in the parked quadrant — e.g. chapel/MAP062
    # rendered black holes at camera angle 0xC10. Reverted: the cull decision is a
    # Render-time angle-vs-table test, and both sides already live in PSX-angle
    # space.)
    vis_bits = polygon.visible_angles_bits
    indices.extend([start_index + 0, start_index + 1, start_index + 2])
    face_centroids.append(centroid)
    visible_angles.append(vis_bits)
    if polygon.is_quad:
        indices.extend([start_index + 1, start_index + 3, start_index + 2])
        face_centroids.append(centroid)
        visible_angles.append(vis_bits)


def _export_geometry_gltf(
    polygons: Dict[PolygonType, List[Polygon]],
    gltf_path: Path,
    bin_path: Path,
    size_z_psx_units: int,
    verbose: bool = False,
) -> None:
    """Export geometry as GLTF 2.0 with separate binary buffer."""
    # Collect all polygons
    all_polygons: List[Polygon] = []
    for poly_type in [
        PolygonType.TEXTURED_TRIANGLE,
        PolygonType.TEXTURED_QUAD,
        PolygonType.UNTEXTURED_TRIANGLE,
        PolygonType.UNTEXTURED_QUAD,
    ]:
        all_polygons.extend(polygons[poly_type])

    # Group by palette
    textured_by_palette: Dict[int, List[Polygon]] = defaultdict(list)
    untextured: List[Polygon] = []

    for polygon in all_polygons:
        if polygon.is_textured:
            textured_by_palette[polygon.palette_id].append(polygon)
        else:
            untextured.append(polygon)

    # Build all vertex and index data
    all_positions: List[float] = []
    all_normals: List[float] = []
    all_uvs: List[float] = []

    # Primitives info: (name, start_index, index_count)
    primitives_info: List[Tuple[str, int, int, List[int]]] = []

    # Process each palette group
    current_vertex_offset = 0

    for palette_id in sorted(textured_by_palette.keys()):
        palette_polys = textured_by_palette[palette_id]
        indices: List[int] = []

        for polygon in palette_polys:
            vertex_count = 4 if polygon.is_quad else 3
            start_idx = current_vertex_offset

            for i in range(vertex_count):
                v = polygon.vertices[i]
                pos = convert_position(v.x, v.y, v.z, size_z_psx_units)
                normal = convert_normal(v.normal_elevation, v.normal_azimuth)
                uv = convert_uv(
                    polygon.uv_coordinates[i][0],
                    polygon.uv_coordinates[i][1],
                    polygon.texture_page
                ) if polygon.uv_coordinates else (0.0, 0.0)

                all_positions.extend(pos)
                all_normals.extend(normal)
                all_uvs.extend(uv)
                current_vertex_offset += 1

            # ADR-0052 Z-flip reverses winding for both quad triangles.
            # Diagonal v1-v2 preserved; both tris wound CCW post-flip.
            indices.extend([start_idx, start_idx + 1, start_idx + 2])
            if polygon.is_quad:
                indices.extend([start_idx + 1, start_idx + 3, start_idx + 2])

        primitives_info.append((f"Palette{palette_id}", palette_id, len(indices), indices))

    # Process untextured
    if untextured:
        indices = []
        for polygon in untextured:
            vertex_count = 4 if polygon.is_quad else 3
            start_idx = current_vertex_offset

            for i in range(vertex_count):
                v = polygon.vertices[i]
                pos = convert_position(v.x, v.y, v.z, size_z_psx_units)
                normal = convert_normal(v.normal_elevation, v.normal_azimuth)
                uv = (0.0, 0.0)

                all_positions.extend(pos)
                all_normals.extend(normal)
                all_uvs.extend(uv)
                current_vertex_offset += 1

            # ADR-0052 Z-flip reverses winding for both quad triangles.
            # Diagonal v1-v2 preserved; both tris wound CCW post-flip.
            indices.extend([start_idx, start_idx + 1, start_idx + 2])
            if polygon.is_quad:
                indices.extend([start_idx + 1, start_idx + 3, start_idx + 2])

        primitives_info.append(("Untextured", None, len(indices), indices))

    total_vertices = current_vertex_offset

    # Build binary buffer
    # Layout: positions, normals, UVs, then indices for each primitive
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

    # UVs (vec2 float)
    uvs_offset = len(buffer_data)
    for u in all_uvs:
        buffer_data.extend(struct.pack('<f', u))
    uvs_length = len(buffer_data) - uvs_offset

    # Indices for each primitive
    indices_info: List[Tuple[int, int]] = []  # (offset, length)
    for name, palette_id, count, indices in primitives_info:
        offset = len(buffer_data)
        for idx in indices:
            buffer_data.extend(struct.pack('<I', idx))
        length = len(buffer_data) - offset
        indices_info.append((offset, length))

    # Write binary file
    with open(bin_path, 'wb') as f:
        f.write(buffer_data)

    # Build GLTF structure
    gltf = GLTF2(
        asset=Asset(version="2.0", generator="FFT Map Exporter"),
        buffers=[Buffer(byteLength=len(buffer_data), uri="geometry.bin")],
        bufferViews=[],
        accessors=[],
        meshes=[],
        nodes=[],
        scenes=[Scene(nodes=[0])],
        scene=0,
    )

    # Buffer views
    # 0: positions
    gltf.bufferViews.append(BufferView(
        buffer=0,
        byteOffset=positions_offset,
        byteLength=positions_length,
        target=34962,  # ARRAY_BUFFER
    ))
    # 1: normals
    gltf.bufferViews.append(BufferView(
        buffer=0,
        byteOffset=normals_offset,
        byteLength=normals_length,
        target=34962,
    ))
    # 2: UVs
    gltf.bufferViews.append(BufferView(
        buffer=0,
        byteOffset=uvs_offset,
        byteLength=uvs_length,
        target=34962,
    ))
    # Index buffer views (one per primitive)
    for i, (offset, length) in enumerate(indices_info):
        gltf.bufferViews.append(BufferView(
            buffer=0,
            byteOffset=offset,
            byteLength=length,
            target=34963,  # ELEMENT_ARRAY_BUFFER
        ))

    # Accessors
    # 0: positions
    gltf.accessors.append(Accessor(
        bufferView=0,
        componentType=FLOAT,
        count=total_vertices,
        type=VEC3,
        max=[max(all_positions[i::3]) for i in range(3)],
        min=[min(all_positions[i::3]) for i in range(3)],
    ))
    # 1: normals
    gltf.accessors.append(Accessor(
        bufferView=1,
        componentType=FLOAT,
        count=total_vertices,
        type=VEC3,
    ))
    # 2: UVs
    gltf.accessors.append(Accessor(
        bufferView=2,
        componentType=FLOAT,
        count=total_vertices,
        type=VEC2,
    ))
    # Index accessors (one per primitive)
    for i, (name, palette_id, count, indices) in enumerate(primitives_info):
        gltf.accessors.append(Accessor(
            bufferView=3 + i,
            componentType=UNSIGNED_INT,
            count=count,
            type=SCALAR,
        ))

    # Mesh with primitives
    mesh_primitives = []
    for i, (name, palette_id, count, indices) in enumerate(primitives_info):
        mesh_primitives.append(Primitive(
            attributes=Attributes(
                POSITION=0,
                NORMAL=1,
                TEXCOORD_0=2,
            ),
            indices=3 + i,
            mode=TRIANGLES,
        ))

    gltf.meshes.append(Mesh(
        name="PrimaryMesh",
        primitives=mesh_primitives,
    ))

    # Node
    gltf.nodes.append(Node(mesh=0, name="PrimaryMesh"))

    # Save GLTF
    gltf.save(str(gltf_path))
