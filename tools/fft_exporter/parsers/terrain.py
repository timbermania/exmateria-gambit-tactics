"""Terrain parsing from mesh resource data."""

from typing import Optional

from ..models.terrain import (
    Terrain,
    TerrainTile,
    TerrainSlopeType,
    TerrainSurfaceType,
    SLOPE_TYPE_MAP,
)
from ..utils.binary import read_int32_le


# Terrain pointer offset in mesh resource header
TERRAIN_POINTER = 104


def parse_terrain(data: bytes) -> Optional[Terrain]:
    """Parse terrain data from mesh resource.

    Args:
        data: Raw mesh resource data

    Returns:
        Terrain object or None if no terrain data
    """
    # Read terrain pointer
    pointer = read_int32_le(data, TERRAIN_POINTER)

    if pointer == 0:
        return None

    # Read terrain dimensions
    width = data[pointer]
    length = data[pointer + 1]

    terrain = Terrain(size_x=width, size_z=length)
    offset = pointer + 2

    # Parse Level 0 and Level 1 tiles
    for level in range(2):
        level_tiles = []

        for index_z in range(length):
            row = []

            for index_x in range(width):
                tile = _parse_tile(data, offset, index_x, index_z, level)
                row.append(tile)
                offset += 8

            level_tiles.append(row)

        # Skip to next level (each level is 2048 bytes)
        # Level data is width * length * 8 bytes, padded to 2048
        offset += 2048 - width * length * 8

        if level == 0:
            terrain.level_0_tiles = level_tiles
        else:
            terrain.level_1_tiles = level_tiles

    return terrain


def _parse_tile(
    data: bytes,
    offset: int,
    index_x: int,
    index_z: int,
    level: int,
) -> TerrainTile:
    """Parse a single terrain tile (8 bytes).

    Tile format:
    - Byte 0: bits 0-1 = unknown_0a/0b, bits 2-7 = surface type
    - Byte 1: unknown_1
    - Byte 2: height
    - Byte 3: bits 0-2 = depth, bits 3-7 = slope height
    - Byte 4: slope type ID
    - Byte 5: bits 0-2 = unknown_5a/5b/5c, bits 3-7 = thickness
    - Byte 6: pass_through_only, unknown_6b/c/d, shading, impassable, unselectable
    - Byte 7: rotation flags
    """
    byte0 = data[offset]
    byte1 = data[offset + 1]
    byte2 = data[offset + 2]
    byte3 = data[offset + 3]
    byte4 = data[offset + 4]
    byte5 = data[offset + 5]
    byte6 = data[offset + 6]
    byte7 = data[offset + 7]

    # Byte 0: unknown flags and surface type
    unknown_0a = bool((byte0 >> 7) & 1)
    unknown_0b = bool((byte0 >> 6) & 1)
    surface_type_id = byte0 & 0x3F  # Lower 6 bits

    # TOTAL, so no default: the enum names all 64 values `byte0 & 0x3F` can take,
    # which is what ADR-0004 requires of a named form ("allowed when it is total and
    # exactly reversible").  The prior `except ValueError -> NaturalSurface` was not a
    # safety net, it was a silent flatten: 0x3F CrossSection is IMPASSABLE (0xFF) in
    # every movetype at 0x8005EA50, and defaulting it to NaturalSurface made 367 tiles
    # across 28 arrangements walkable that the ROM treats as wall.  If this ever raises,
    # the enum has LOST a member and the guard (tools/check_rom_terrain_tables.py) is
    # the thing to look at -- raising is correct.
    surface_type = TerrainSurfaceType(surface_type_id)

    # Byte 1: unknown
    unknown_1 = byte1

    # Byte 2: height
    height = byte2

    # Byte 3: depth and slope height
    depth = (byte3 >> 5) & 0x07  # Upper 3 bits
    slope_height = byte3 & 0x1F  # Lower 5 bits

    # Byte 4: slope type
    slope_type = SLOPE_TYPE_MAP.get(byte4, TerrainSlopeType.Flat)

    # Byte 5: unknown flags and thickness
    unknown_5a = bool((byte5 >> 7) & 1)
    unknown_5b = bool((byte5 >> 6) & 1)
    unknown_5c = bool((byte5 >> 5) & 1)
    thickness = byte5 & 0x1F  # Lower 5 bits

    # Byte 6: flags
    pass_through_only = bool((byte6 >> 7) & 1)
    unknown_6b = bool((byte6 >> 6) & 1)
    unknown_6c = bool((byte6 >> 5) & 1)
    unknown_6d = bool((byte6 >> 4) & 1)
    shading = (byte6 >> 2) & 0x03  # Bits 2-3
    impassable = bool((byte6 >> 1) & 1)
    unselectable = bool(byte6 & 1)

    # Byte 7: rotation flags
    rotates_northwest_top = bool((byte7 >> 7) & 1)
    rotates_southwest_top = bool((byte7 >> 6) & 1)
    rotates_southeast_top = bool((byte7 >> 5) & 1)
    rotates_northeast_top = bool((byte7 >> 4) & 1)
    rotates_northwest_bottom = bool((byte7 >> 3) & 1)
    rotates_southwest_bottom = bool((byte7 >> 2) & 1)
    rotates_southeast_bottom = bool((byte7 >> 1) & 1)
    rotates_northeast_bottom = bool(byte7 & 1)

    return TerrainTile(
        index_x=index_x,
        index_z=index_z,
        level=level,
        surface_type=surface_type,
        height=height,
        depth=depth,
        slope_height=slope_height,
        slope_type=slope_type,
        impassable=impassable,
        unselectable=unselectable,
        pass_through_only=pass_through_only,
        thickness=thickness,
        shading=shading,
        rotates_northwest_top=rotates_northwest_top,
        rotates_southwest_top=rotates_southwest_top,
        rotates_southeast_top=rotates_southeast_top,
        rotates_northeast_top=rotates_northeast_top,
        rotates_northwest_bottom=rotates_northwest_bottom,
        rotates_southwest_bottom=rotates_southwest_bottom,
        rotates_southeast_bottom=rotates_southeast_bottom,
        rotates_northeast_bottom=rotates_northeast_bottom,
        unknown_0a=unknown_0a,
        unknown_0b=unknown_0b,
        unknown_1=unknown_1,
        unknown_5a=unknown_5a,
        unknown_5b=unknown_5b,
        unknown_5c=unknown_5c,
        unknown_6b=unknown_6b,
        unknown_6c=unknown_6c,
        unknown_6d=unknown_6d,
    )
