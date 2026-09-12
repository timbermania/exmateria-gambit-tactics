"""Data models for FFT map resources."""

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional


class ResourceType(Enum):
    """Type of resource in a GNS file."""
    INITIAL_MESH_DATA = auto()
    OVERRIDE_MESH_DATA = auto()
    ALTERNATE_STATE_MESH_DATA = auto()
    TEXTURE = auto()
    PADDED = auto()
    UNKNOWN_EXTRA_DATA_A = auto()
    UNKNOWN_EXTRA_DATA_B = auto()
    UNKNOWN_TWIN = auto()
    UNKNOWN_TRAILING_DATA = auto()
    BAD_FORMAT = auto()


class MapWeather(Enum):
    """Weather condition for a map state.

    Names follow the authoritative GNS field-C decode (bits 6-4):
    0 None, 1 NoneAlt, 2 Light, 3 Normal, 4 Heavy. This is OFFSET from the
    scenario weather enum (parse_scenarios.py has no NoneAlt slot) — selection
    is by RAW int, never by label (see MapStateSelector.gd / ADR-0056).
    """
    NONE = 0
    NONE_ALT = 1
    LIGHT = 2
    NORMAL = 3
    HEAVY = 4


class MapTime(Enum):
    """Time of day for a map state."""
    DAY = 0
    NIGHT = 1


class MapArrangementState(Enum):
    """Arrangement state (primary or secondary variant)."""
    PRIMARY = 0
    SECONDARY = 1


class MeshType(Enum):
    """Type of mesh in the polygon collection."""
    PRIMARY_MESH = 0
    ANIMATED_MESH_1 = 1
    ANIMATED_MESH_2 = 2
    ANIMATED_MESH_3 = 3
    ANIMATED_MESH_4 = 4
    ANIMATED_MESH_5 = 5
    ANIMATED_MESH_6 = 6
    ANIMATED_MESH_7 = 7
    ANIMATED_MESH_8 = 8


class PolygonType(Enum):
    """Type of polygon."""
    TEXTURED_TRIANGLE = 0
    TEXTURED_QUAD = 1
    UNTEXTURED_TRIANGLE = 2
    UNTEXTURED_QUAD = 3


@dataclass
class MapResource:
    """A single resource entry from a GNS file."""
    resource_type: ResourceType
    arrangement: MapArrangementState
    time: MapTime
    weather: MapWeather
    file_sector: int
    raw_data: bytes = field(repr=False)
    x_file: int = -1
    resource_data: Optional[bytes] = field(default=None, repr=False)

    @property
    def is_mesh(self) -> bool:
        """Returns True if this resource contains mesh data."""
        return self.resource_type in (
            ResourceType.INITIAL_MESH_DATA,
            ResourceType.OVERRIDE_MESH_DATA,
            ResourceType.ALTERNATE_STATE_MESH_DATA,
        )

    @property
    def is_texture(self) -> bool:
        """Returns True if this resource contains texture data."""
        return self.resource_type == ResourceType.TEXTURE
