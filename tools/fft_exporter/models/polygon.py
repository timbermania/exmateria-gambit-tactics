"""Polygon and Vertex data models."""

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import List, Optional, Tuple


class PolygonType(Enum):
    """Polygon type enum matching C# PolygonType."""
    TEXTURED_TRIANGLE = auto()
    TEXTURED_QUAD = auto()
    UNTEXTURED_TRIANGLE = auto()
    UNTEXTURED_QUAD = auto()


class MeshType(Enum):
    """Mesh type enum matching C# MeshType."""
    PRIMARY_MESH = auto()
    ANIMATED_MESH_1 = auto()
    ANIMATED_MESH_2 = auto()
    ANIMATED_MESH_3 = auto()
    ANIMATED_MESH_4 = auto()
    ANIMATED_MESH_5 = auto()
    ANIMATED_MESH_6 = auto()
    ANIMATED_MESH_7 = auto()
    ANIMATED_MESH_8 = auto()


@dataclass
class Vertex:
    """Vertex data structure."""
    # Position in FFT units (raw from file, already sign-adjusted)
    x: float
    y: float
    z: float

    # Normal stored as spherical coordinates (radians)
    uses_normal: bool = False
    normal_elevation: float = 0.0
    normal_azimuth: float = 0.0

    @property
    def position(self) -> Tuple[float, float, float]:
        """Return position as tuple."""
        return (self.x, self.y, self.z)


@dataclass
class Polygon:
    """Polygon data structure."""
    polygon_type: PolygonType
    mesh_type: MeshType
    vertices: List[Vertex] = field(default_factory=list)

    # UV coordinates (pixel coords, 0-255 range)
    uv_coordinates: Optional[List[Tuple[int, int]]] = None

    # Texture properties
    palette_id: int = 0
    texture_page: int = 0

    # Terrain binding
    terrain_x: int = 0
    terrain_z: int = 0
    terrain_level: int = 0

    # Unknown texture values (preserved for round-trip)
    unknown_texture_value_3: int = 120
    unknown_texture_value_6a: int = 0
    texture_source: int = 3
    unknown_texture_value_7: int = 0

    # Unknown untextured values
    unknown_untextured_value_a: int = 0
    unknown_untextured_value_b: int = 0
    unknown_untextured_value_c: int = 0
    unknown_untextured_value_d: int = 0

    # Per-polygon visible-angles bitfield (mesh-resource section at header +0xB0).
    # 16-bit raw value. Bits 2-13 (mask 0x3FFC) gate visibility against the
    # active camera angle via the PSX renderer's two-condition test
    # (see DEPTH_MODE_RENDER_ORDER_GUIDE.md Stage 4). 0 = always visible.
    visible_angles_bits: int = 0

    @property
    def is_textured(self) -> bool:
        """Check if polygon is textured."""
        return self.polygon_type in (PolygonType.TEXTURED_TRIANGLE, PolygonType.TEXTURED_QUAD)

    @property
    def is_quad(self) -> bool:
        """Check if polygon is a quad."""
        return self.polygon_type in (PolygonType.TEXTURED_QUAD, PolygonType.UNTEXTURED_QUAD)

    @property
    def vertex_count(self) -> int:
        """Return number of vertices (3 for triangle, 4 for quad)."""
        return 4 if self.is_quad else 3
