"""Mesh parsing from mesh resource data."""

import math
from typing import Dict, List, Tuple

from ..models.polygon import MeshType, Polygon, PolygonType, Vertex
from ..utils.binary import read_int16_le, read_int32_le, read_uint16_le


# Mesh pointer offsets in resource header
PRIMARY_MESH_POINTER = 64
# Animated-mesh (System B) geometry pointers: mesh 1..8 at 0x90, 0x94, ...,
# 0xAC. Each chunk is stored exactly like the primary mesh, so parse_mesh
# selects its count/geometry pointer from the mesh_type rather than always
# reading the primary 0x40 pointer.
ANIMATED_MESH_POINTER_BASE = 0x90
# Per-polygon "Polygon Render Properties" bitfield — the FFT engine's
# pre-computed lit/cull table (Hyper-FFT wiki "Polygon Render Properties").
# Fixed 4096-byte chunk laid out as FIVE consecutive blocks. The leading
# 896-byte block is unknown/header — visibility data does NOT start at
# byte 0. Per-type slot bases inside the chunk:
#   0x000..0x380 (896  bytes): unknown header
#   0x380..0x780 (1024 bytes): 512 textured triangles  × 2 bytes
#   0x780..0xD80 (1536 bytes): 768 textured quads      × 2 bytes
#   0xD80..0xE00 (128  bytes):  64 untextured triangles× 2 bytes
#   0xE00..0x1000(512  bytes): 256 untextured quads    × 2 bytes
# Each polygon's 2-byte value: bit 0 = unlit, bits 2..13 = "hide from
# this camera angle" (mask 0x3FFC, set means CULL), bits 1/14/15 = unknown.
VISIBLE_ANGLES_POINTER = 0xB0
VIS_HEADER_BYTES = 896
VIS_TEXTURED_TRI_BASE = VIS_HEADER_BYTES                       # 0x380
VIS_TEXTURED_QUAD_BASE = VIS_TEXTURED_TRI_BASE + 512 * 2       # 0x780
VIS_UNTEXTURED_TRI_BASE = VIS_TEXTURED_QUAD_BASE + 768 * 2     # 0xD80
VIS_UNTEXTURED_QUAD_BASE = VIS_UNTEXTURED_TRI_BASE + 64 * 2    # 0xE00

# The camera-angle cull mask (bits 2..13) is TWO fields the PSX Stage-4 test
# indexes separately (fft_visible_angles.gdshaderinc):
#   bits 2..9  = 8 "fine" buckets, one per 45° sector  (shift1 = (angle-1)>>9 &7)
#   bits 10..13 = 4 "cardinal" buckets, one per 90° quadrant (shift2 = angle>>10 &3)
# The table is emitted RAW: it is indexed by the *live PSX camera angle* at
# runtime, not by geometry orientation, so the ADR-0052 180°-about-X parse
# rotation does NOT remap it (see exporters/geometry.py; issue #135 reverted).
VIS_CULL_MASK = 0x3FFC


def vector_to_sphere(x: float, y: float, z: float) -> Tuple[float, float]:
    """Convert Cartesian vector to spherical coordinates (elevation, azimuth in degrees).

    Matches C# Utilities.VectorToSphere exactly.
    """
    radius = math.sqrt(x * x + y * y + z * z)

    if radius == 0:
        return (0.0, 0.0)

    elevation = math.acos(-y / radius)
    azimuth = math.atan2(x, z)

    elevation_angle = math.degrees(elevation) - 90
    azimuth_angle = -math.degrees(azimuth) + 90

    if azimuth_angle <= 0:
        azimuth_angle += 360

    return (elevation_angle, azimuth_angle)


def mesh_pointer_offset(mesh_type: MeshType) -> int:
    """Return the header offset holding the geometry pointer for ``mesh_type``.

    Primary mesh lives at 0x40; animated meshes 1..8 (System B) at
    0x90 + (n-1)*4.
    """
    if mesh_type == MeshType.PRIMARY_MESH:
        return PRIMARY_MESH_POINTER
    n = mesh_type.value - MeshType.ANIMATED_MESH_1.value  # 0-based mesh index
    return ANIMATED_MESH_POINTER_BASE + n * 4


def parse_mesh(
    data: bytes,
    mesh_type: MeshType = MeshType.PRIMARY_MESH,
) -> Dict[PolygonType, List[Polygon]]:
    """Parse mesh data from mesh resource.

    Args:
        data: Raw mesh resource data
        mesh_type: Type of mesh being parsed. Selects which header pointer the
            geometry is read from (primary 0x40, or animated-mesh 0x90+).

    Returns:
        Dictionary mapping PolygonType to list of Polygons
    """
    # Read mesh pointer (primary 0x40, or the animated-mesh slot for System B)
    pointer = read_int32_le(data, mesh_pointer_offset(mesh_type))

    if pointer == 0:
        return {
            PolygonType.TEXTURED_TRIANGLE: [],
            PolygonType.TEXTURED_QUAD: [],
            PolygonType.UNTEXTURED_TRIANGLE: [],
            PolygonType.UNTEXTURED_QUAD: [],
        }

    # Initialize polygon collections
    polygons: Dict[PolygonType, List[Polygon]] = {
        PolygonType.TEXTURED_TRIANGLE: [],
        PolygonType.TEXTURED_QUAD: [],
        PolygonType.UNTEXTURED_TRIANGLE: [],
        PolygonType.UNTEXTURED_QUAD: [],
    }

    # Read polygon counts (4 x uint16 at mesh pointer)
    offset = pointer
    textured_triangle_count = read_uint16_le(data, offset)
    textured_quad_count = read_uint16_le(data, offset + 2)
    untextured_triangle_count = read_uint16_le(data, offset + 4)
    untextured_quad_count = read_uint16_le(data, offset + 6)

    # Create empty polygons
    for _ in range(textured_triangle_count):
        polygons[PolygonType.TEXTURED_TRIANGLE].append(Polygon(
            polygon_type=PolygonType.TEXTURED_TRIANGLE,
            mesh_type=mesh_type,
        ))

    for _ in range(textured_quad_count):
        polygons[PolygonType.TEXTURED_QUAD].append(Polygon(
            polygon_type=PolygonType.TEXTURED_QUAD,
            mesh_type=mesh_type,
        ))

    for _ in range(untextured_triangle_count):
        polygons[PolygonType.UNTEXTURED_TRIANGLE].append(Polygon(
            polygon_type=PolygonType.UNTEXTURED_TRIANGLE,
            mesh_type=mesh_type,
        ))

    for _ in range(untextured_quad_count):
        polygons[PolygonType.UNTEXTURED_QUAD].append(Polygon(
            polygon_type=PolygonType.UNTEXTURED_QUAD,
            mesh_type=mesh_type,
        ))

    # Skip polygon counts (8 bytes)
    offset = pointer + 8

    # Parse position data
    offset = _parse_position_data(data, offset, polygons[PolygonType.TEXTURED_TRIANGLE], 3)
    offset = _parse_position_data(data, offset, polygons[PolygonType.TEXTURED_QUAD], 4)
    offset = _parse_position_data(data, offset, polygons[PolygonType.UNTEXTURED_TRIANGLE], 3)
    offset = _parse_position_data(data, offset, polygons[PolygonType.UNTEXTURED_QUAD], 4)

    # Parse normal data (textured only)
    offset = _parse_normal_data(data, offset, polygons[PolygonType.TEXTURED_TRIANGLE], 3)
    offset = _parse_normal_data(data, offset, polygons[PolygonType.TEXTURED_QUAD], 4)

    # Parse texture data (textured only)
    offset = _parse_texture_data(data, offset, polygons[PolygonType.TEXTURED_TRIANGLE], 3)
    offset = _parse_texture_data(data, offset, polygons[PolygonType.TEXTURED_QUAD], 4)

    # Parse untextured polygon data
    offset = _parse_untextured_data(data, offset, polygons[PolygonType.UNTEXTURED_TRIANGLE])
    offset = _parse_untextured_data(data, offset, polygons[PolygonType.UNTEXTURED_QUAD])

    # Parse terrain binding (textured only)
    offset = _parse_terrain_binding(data, offset, polygons[PolygonType.TEXTURED_TRIANGLE])
    offset = _parse_terrain_binding(data, offset, polygons[PolygonType.TEXTURED_QUAD])

    # Parse per-polygon visible-angles bitfield (header +0xB0). This 4096-byte
    # section is sized to the PRIMARY mesh's polygon caps, so it only applies to
    # the primary mesh; animated meshes leave visible_angles_bits at 0.
    if mesh_type == MeshType.PRIMARY_MESH:
        _parse_visible_angles(data, polygons)

    return polygons


def _parse_visible_angles(
    data: bytes,
    polygons: Dict[PolygonType, List[Polygon]],
) -> None:
    """Read the 4096-byte visible-angles section pointed at by header +0xB0
    and stamp `visible_angles_bits` on each polygon.

    Layout is per-type slotted to FFT's max-polygon caps (see constants
    above), not packed by actual count — index polygon N at base + N*2.
    """
    if len(data) < VISIBLE_ANGLES_POINTER + 4:
        return
    vis_off = read_int32_le(data, VISIBLE_ANGLES_POINTER)
    if vis_off <= 0 or vis_off + 0x1000 > len(data):
        return

    layout = [
        (PolygonType.TEXTURED_TRIANGLE, VIS_TEXTURED_TRI_BASE),
        (PolygonType.TEXTURED_QUAD, VIS_TEXTURED_QUAD_BASE),
        (PolygonType.UNTEXTURED_TRIANGLE, VIS_UNTEXTURED_TRI_BASE),
        (PolygonType.UNTEXTURED_QUAD, VIS_UNTEXTURED_QUAD_BASE),
    ]
    for ptype, base in layout:
        for i, polygon in enumerate(polygons[ptype]):
            polygon.visible_angles_bits = read_uint16_le(data, vis_off + base + i * 2)


def _parse_position_data(
    data: bytes,
    offset: int,
    polygon_list: List[Polygon],
    vertex_count: int,
) -> int:
    """Parse position data for a list of polygons.

    Returns the new offset after parsing.
    """
    for polygon in polygon_list:
        polygon.vertices = []
        for _ in range(vertex_count):
            # Read raw position (int16 each). The X/Y negation is a Placement
            # coordinate transform (PSX→Godot axes), not a file-format quirk —
            # it is the linear (axis-sign) half of the map's Placement mapping;
            # the depth mirror half (ADR-0052 size_z−1−z) is applied downstream
            # in coordinates.convert_position. See CONTEXT.md → Placement, ADR-0057.
            x = -read_int16_le(data, offset)
            y = -read_int16_le(data, offset + 2)
            z = read_int16_le(data, offset + 4)

            polygon.vertices.append(Vertex(x=x, y=y, z=z))
            offset += 6

    return offset


def _parse_normal_data(
    data: bytes,
    offset: int,
    polygon_list: List[Polygon],
    vertex_count: int,
) -> int:
    """Parse normal data for a list of polygons.

    Normals are stored as int16 fixed-point (/4096), converted to spherical.
    Returns the new offset after parsing.
    """
    for polygon in polygon_list:
        for i in range(vertex_count):
            # Read raw normal (int16 each, /4096 to get float). A normal is a
            # RELATIVE Placement (a direction, not a position), so it gets the
            # LINEAR part of the transform only — the X/Y axis-sign flip, no
            # size_z mirror (the affine corollary, ADR-0057). This is the same
            # axis negation the vertices get above.
            nx = -read_int16_le(data, offset) / 4096.0
            ny = -read_int16_le(data, offset + 2) / 4096.0
            nz = read_int16_le(data, offset + 4) / 4096.0

            # Convert to spherical coordinates
            elevation, azimuth = vector_to_sphere(nx, ny, nz)

            polygon.vertices[i].uses_normal = True
            polygon.vertices[i].normal_elevation = elevation
            polygon.vertices[i].normal_azimuth = azimuth

            offset += 6

    return offset


def _parse_texture_data(
    data: bytes,
    offset: int,
    polygon_list: List[Polygon],
    vertex_count: int,
) -> int:
    """Parse texture UV and palette data for textured polygons.

    Triangle: 10 bytes
    Quad: 12 bytes

    Layout:
    - byte 0: vertex A U
    - byte 1: vertex A V
    - byte 2: palette number
    - byte 3: unknown_texture_value_3
    - byte 4: vertex B U
    - byte 5: vertex B V
    - byte 6: texture page (lower 2 bits)
    - byte 7: unknown_texture_value_7
    - byte 8: vertex C U
    - byte 9: vertex C V
    - byte 10: vertex D U (quad only)
    - byte 11: vertex D V (quad only)
    """
    for polygon in polygon_list:
        # UV coordinates
        uv_a = (data[offset], data[offset + 1])
        uv_b = (data[offset + 4], data[offset + 5])
        uv_c = (data[offset + 8], data[offset + 9])

        # Palette ID (mod 16)
        palette_id = data[offset + 2]
        while palette_id > 15:
            palette_id -= 16
        polygon.palette_id = palette_id

        # Unknown values
        polygon.unknown_texture_value_3 = data[offset + 3]
        polygon.unknown_texture_value_7 = data[offset + 7]

        # Texture page and other bits from byte 6
        texture_byte = data[offset + 6]
        polygon.texture_page = texture_byte & 0x03  # Lower 2 bits
        polygon.texture_source = (texture_byte >> 2) & 0x03  # Bits 2-3
        polygon.unknown_texture_value_6a = (texture_byte >> 4) & 0x0F  # Upper 4 bits

        polygon.uv_coordinates = [uv_a, uv_b, uv_c]
        offset += 10

        if vertex_count == 4:
            uv_d = (data[offset], data[offset + 1])
            polygon.uv_coordinates.append(uv_d)
            offset += 2

    return offset


def _parse_untextured_data(
    data: bytes,
    offset: int,
    polygon_list: List[Polygon],
) -> int:
    """Parse unknown data for untextured polygons (4 bytes each)."""
    for polygon in polygon_list:
        polygon.unknown_untextured_value_a = data[offset]
        polygon.unknown_untextured_value_b = data[offset + 1]
        polygon.unknown_untextured_value_c = data[offset + 2]
        polygon.unknown_untextured_value_d = data[offset + 3]
        offset += 4

    return offset


def _parse_terrain_binding(
    data: bytes,
    offset: int,
    polygon_list: List[Polygon],
) -> int:
    """Parse terrain binding for textured polygons (2 bytes each).

    Byte 0: bits 0-6 = terrain Z, bit 7 = terrain level
    Byte 1: terrain X
    """
    for polygon in polygon_list:
        byte0 = data[offset]
        byte1 = data[offset + 1]

        polygon.terrain_z = byte0 >> 1  # Upper 7 bits
        polygon.terrain_level = byte0 & 0x01  # Lower 1 bit
        polygon.terrain_x = byte1

        offset += 2

    return offset


def get_polygon_counts(polygons: Dict[PolygonType, List[Polygon]]) -> Dict[str, int]:
    """Get polygon counts by type."""
    return {
        "textured_triangles": len(polygons[PolygonType.TEXTURED_TRIANGLE]),
        "textured_quads": len(polygons[PolygonType.TEXTURED_QUAD]),
        "untextured_triangles": len(polygons[PolygonType.UNTEXTURED_TRIANGLE]),
        "untextured_quads": len(polygons[PolygonType.UNTEXTURED_QUAD]),
        "total": sum(len(p) for p in polygons.values()),
    }
