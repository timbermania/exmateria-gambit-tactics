"""Terrain data models."""

from dataclasses import dataclass, field
from enum import Enum
from typing import List, Tuple


class TerrainSlopeType(Enum):
    """Terrain slope type enum - names match C# for JSON serialization."""
    Flat = 0
    InclineNorth = 133
    InclineEast = 82
    InclineSouth = 37
    InclineWest = 88
    ConvexNortheast = 65
    ConvexSoutheast = 17
    ConvexSouthwest = 20
    ConvexNorthwest = 68
    ConcaveNortheast = 150
    ConcaveSoutheast = 102
    ConcaveSouthwest = 105
    ConcaveNorthwest = 153


class TerrainSurfaceType(Enum):
    """Terrain surface type enum - names match C# for JSON serialization."""
    NaturalSurface = 0
    SandArea = 1
    Stalactite = 2
    Grassland = 3
    Thicket = 4
    Snow = 5
    RockyCliff = 6
    Gravel = 7
    Wasteland = 8
    Swamp = 9
    Marsh = 10
    PoisonedMarsh = 11
    LavaRocks = 12
    Ice = 13
    Waterway = 14
    River = 15
    Lake = 16
    Sea = 17
    Lava = 18
    Road = 19
    WoodenFloor = 20
    StoneFloor = 21
    Roof = 22
    StoneWall = 23
    Sky = 24
    Darkness = 25
    Salt = 26
    Book = 27
    Obstacle = 28
    Rug = 29
    Tree = 30
    Box = 31
    Brick = 32
    Chimney = 33
    MudWall = 34
    Bridge = 35
    WaterPlant = 36
    Stairs = 37
    Furniture = 38
    Ivy = 39
    Deck = 40
    Machine = 41
    IronPlate = 42
    Moss = 43
    Tombstone = 44
    Waterfall = 45
    Coffin = 46
    FftbgPool = 47
    UnusedX30 = 48
    UnusedX31 = 49
    UnusedX32 = 50
    UnusedX33 = 51
    UnusedX34 = 52
    UnusedX35 = 53
    UnusedX36 = 54
    UnusedX37 = 55
    UnusedX38 = 56
    UnusedX39 = 57
    UnusedX3A = 58
    UnusedX3B = 59
    UnusedX3C = 60
    UnusedX3D = 61
    UnusedX3E = 62
    CrossSection = 63


# Slope type ID to enum mapping
SLOPE_TYPE_MAP = {
    0: TerrainSlopeType.Flat,
    133: TerrainSlopeType.InclineNorth,
    82: TerrainSlopeType.InclineEast,
    37: TerrainSlopeType.InclineSouth,
    88: TerrainSlopeType.InclineWest,
    65: TerrainSlopeType.ConvexNortheast,
    17: TerrainSlopeType.ConvexSoutheast,
    20: TerrainSlopeType.ConvexSouthwest,
    68: TerrainSlopeType.ConvexNorthwest,
    150: TerrainSlopeType.ConcaveNortheast,
    102: TerrainSlopeType.ConcaveSoutheast,
    105: TerrainSlopeType.ConcaveSouthwest,
    153: TerrainSlopeType.ConcaveNorthwest,
}


# Vertices to lift for each slope type
VERT0_LIFT_TYPES = {
    TerrainSlopeType.InclineSouth,
    TerrainSlopeType.InclineWest,
    TerrainSlopeType.ConvexSouthwest,
    TerrainSlopeType.ConcaveSoutheast,
    TerrainSlopeType.ConcaveSouthwest,
    TerrainSlopeType.ConcaveNorthwest,
}

VERT1_LIFT_TYPES = {
    TerrainSlopeType.InclineNorth,
    TerrainSlopeType.InclineWest,
    TerrainSlopeType.ConvexNorthwest,
    TerrainSlopeType.ConcaveNortheast,
    TerrainSlopeType.ConcaveSouthwest,
    TerrainSlopeType.ConcaveNorthwest,
}

VERT2_LIFT_TYPES = {
    TerrainSlopeType.InclineNorth,
    TerrainSlopeType.InclineEast,
    TerrainSlopeType.ConvexNortheast,
    TerrainSlopeType.ConcaveNortheast,
    TerrainSlopeType.ConcaveSoutheast,
    TerrainSlopeType.ConcaveNorthwest,
}

VERT3_LIFT_TYPES = {
    TerrainSlopeType.InclineEast,
    TerrainSlopeType.InclineSouth,
    TerrainSlopeType.ConvexSoutheast,
    TerrainSlopeType.ConcaveNortheast,
    TerrainSlopeType.ConcaveSoutheast,
    TerrainSlopeType.ConcaveSouthwest,
}


@dataclass
class TerrainTile:
    """Terrain tile data structure."""
    index_x: int = 0
    index_z: int = 0
    level: int = 0

    # Core properties
    surface_type: TerrainSurfaceType = TerrainSurfaceType.NaturalSurface
    height: int = 0
    depth: int = 0
    slope_height: int = 0
    slope_type: TerrainSlopeType = TerrainSlopeType.Flat

    # Flags
    impassable: bool = False
    unselectable: bool = False
    pass_through_only: bool = False
    thickness: int = 0
    shading: int = 0

    # Rotation flags
    rotates_northwest_top: bool = False
    rotates_southwest_top: bool = False
    rotates_southeast_top: bool = False
    rotates_northeast_top: bool = False
    rotates_northwest_bottom: bool = False
    rotates_southwest_bottom: bool = False
    rotates_southeast_bottom: bool = False
    rotates_northeast_bottom: bool = False

    # Unknown values
    unknown_0a: bool = False
    unknown_0b: bool = False
    unknown_1: int = 0
    unknown_5a: bool = False
    unknown_5b: bool = False
    unknown_5c: bool = False
    unknown_6b: bool = False
    unknown_6c: bool = False
    unknown_6d: bool = False

    def calculate_vertices(self) -> List[Tuple[float, float, float]]:
        """Calculate the 4 vertices of this terrain tile.

        Returns:
            List of 4 (x, y, z) tuples in FFT coordinates.
        """
        base_y = (self.height + self.depth) * 12 + 1

        vertices = [
            (-self.index_x * 28, base_y, self.index_z * 28),
            (-self.index_x * 28, base_y, self.index_z * 28 + 28),
            (-self.index_x * 28 - 28, base_y, self.index_z * 28 + 28),
            (-self.index_x * 28 - 28, base_y, self.index_z * 28),
        ]

        # Apply slope lift
        lift_amount = 12 + (self.slope_height - 1) * 12

        if self.slope_type in VERT0_LIFT_TYPES:
            vertices[0] = (vertices[0][0], vertices[0][1] + lift_amount, vertices[0][2])
        if self.slope_type in VERT1_LIFT_TYPES:
            vertices[1] = (vertices[1][0], vertices[1][1] + lift_amount, vertices[1][2])
        if self.slope_type in VERT2_LIFT_TYPES:
            vertices[2] = (vertices[2][0], vertices[2][1] + lift_amount, vertices[2][2])
        if self.slope_type in VERT3_LIFT_TYPES:
            vertices[3] = (vertices[3][0], vertices[3][1] + lift_amount, vertices[3][2])

        return vertices


@dataclass
class Terrain:
    """Terrain data structure."""
    size_x: int = 0
    size_z: int = 0
    level_0_tiles: List[List[TerrainTile]] = field(default_factory=list)
    level_1_tiles: List[List[TerrainTile]] = field(default_factory=list)
