"""Coordinate conversion utilities.

Converts FFT coordinate system to Godot-compatible coordinates.
"""

import math
from typing import Tuple


SCALE_FACTOR = 50.0


def convert_position(
    x: float, y: float, z: float, size_z_psx_units: float,
) -> Tuple[float, float, float]:
    """Convert FFT position to export position.

    Scales down by 50, negates X, flips Z about the map's far-Z edge.
    The Z flip is part of the 180° rotation around X applied at parse time
    to PSX-derived coordinates (ADR-0052): two reflections (Y + Z) compose
    to a rotation, so chirality is preserved.

    Args:
        x, y, z: FFT position coordinates (z is along the map's depth axis)
        size_z_psx_units: PSX-units-deep of the map, used as the Z-flip
            origin. Equal to `map_length_tiles * 28` (PSX uses 28 position
            units per tile).
    """
    return (
        -x / SCALE_FACTOR,
        y / SCALE_FACTOR,
        (size_z_psx_units - z) / SCALE_FACTOR,
    )


def convert_normal(elevation: float, azimuth: float) -> Tuple[float, float, float]:
    """Convert spherical normal (elevation/azimuth) to Cartesian vector.

    FFT stores normals as spherical coordinates in degrees.

    X is negated and Z is negated to match convert_position(), keeping
    normals in the same coord system as positions after the parser-time
    180° rotation around X (ADR-0052).

    Args:
        elevation: Elevation angle in degrees (from VectorToSphere)
        azimuth: Azimuth angle in degrees (from VectorToSphere)

    Returns:
        Tuple of (x, y, z) normalized normal vector
    """
    elev_rad = math.radians(elevation)
    azim_rad = math.radians(azimuth)

    return (
        -math.cos(elev_rad) * math.cos(azim_rad),
        math.sin(elev_rad),
        -math.cos(elev_rad) * math.sin(azim_rad),
    )


def convert_uv(u: int, v: int, texture_page: int) -> Tuple[float, float]:
    """Convert FFT UV coordinates to normalized [0,1] range.

    FFT uses 256x1024 texture with 4 pages (256x256 each).

    Args:
        u: U coordinate (0-255 pixel)
        v: V coordinate (0-255 pixel within page)
        texture_page: Texture page index (0-3)

    Returns:
        Tuple of (u, v) in [0,1] normalized range
    """
    return (
        u / 256.0,
        (v + texture_page * 256) / 1024.0,
    )
