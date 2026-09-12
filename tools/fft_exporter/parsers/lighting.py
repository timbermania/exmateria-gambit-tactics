"""Lighting parsing from mesh resource data."""

import math
from typing import Optional

from ..models.lighting import DirectionalLight, Lighting
from ..utils.binary import read_int16_le, read_int32_le


# Lighting pointer offset in mesh resource header
LIGHTING_POINTER = 100


def vector_to_sphere(x: float, y: float, z: float) -> tuple[float, float]:
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


def parse_lighting(data: bytes) -> Optional[Lighting]:
    """Parse lighting data from mesh resource.

    Args:
        data: Raw mesh resource data

    Returns:
        Lighting object or None if no lighting data
    """
    # Read lighting pointer
    pointer = read_int32_le(data, LIGHTING_POINTER)

    if pointer == 0:
        return None

    offset = pointer
    lighting = Lighting()

    # Parse directional lights
    # Light colors are stored as 3x3 matrix (R1,R2,R3,G1,G2,G3,B1,B2,B3)
    # Each as int16, divided by 8. NOTE: this is a light GAIN coefficient fed to
    # the GTE light-colour matrix, NOT a displayable 0-255 colour — the /8 value
    # routinely EXCEEDS 255 (e.g. MAP062 key light = (604,528,476), a warm ~2.4x
    # overbright key). PSX clamps only the FINAL per-vertex pixel (after ambient
    # add + texture multiply), so we must preserve the full gain here and let the
    # shader's end-stage clamp saturate. Clamping to 255 here (as GaneshaDx's
    # display path does) drops the overbright + warmth and makes lit faces too
    # dark/cool. Floor at 0 only.
    lights = [DirectionalLight(), DirectionalLight(), DirectionalLight()]

    # Red components
    for i in range(3):
        r = int(read_int16_le(data, offset + i * 2) / 8)
        lights[i].color_r = max(0, r)

    # Green components (offset +6)
    for i in range(3):
        g = int(read_int16_le(data, offset + 6 + i * 2) / 8)
        lights[i].color_g = max(0, g)

    # Blue components (offset +12)
    for i in range(3):
        b = int(read_int16_le(data, offset + 12 + i * 2) / 8)
        lights[i].color_b = max(0, b)

    # Light directions (offset +18, 6 bytes each, 3 lights)
    # Direction is stored as int16 x,y,z divided by 4096, normalized
    for i in range(3):
        dir_offset = offset + 18 + i * 6
        x = -read_int16_le(data, dir_offset) / 4096.0
        y = -read_int16_le(data, dir_offset + 2) / 4096.0
        z = read_int16_le(data, dir_offset + 4) / 4096.0

        # Normalize
        length = math.sqrt(x * x + y * y + z * z)
        if length > 0:
            x /= length
            y /= length
            z /= length

        elevation, azimuth = vector_to_sphere(x, y, z)
        lights[i].direction_elevation = elevation
        lights[i].direction_azimuth = azimuth

    lighting.directional_lights = lights
    offset += 36

    # Ambient light (3 bytes)
    lighting.ambient_r = data[offset]
    lighting.ambient_g = data[offset + 1]
    lighting.ambient_b = data[offset + 2]
    offset += 3

    # Background gradient (6 bytes)
    lighting.gradient_top_r = data[offset]
    lighting.gradient_top_g = data[offset + 1]
    lighting.gradient_top_b = data[offset + 2]
    lighting.gradient_bottom_r = data[offset + 3]
    lighting.gradient_bottom_g = data[offset + 4]
    lighting.gradient_bottom_b = data[offset + 5]

    return lighting


def lighting_to_dict(lighting: Optional[Lighting]) -> dict:
    """Serialize a ``Lighting`` (or ``None``) to the manifest lighting shape.

    Single source of the ``{ambient, directional_lights, gradient{top,bottom}}``
    JSON shape read by the runtime (``MapLightingConfig`` + ``ScreenEffectOverlay``).
    When ``lighting`` is ``None`` (a row with no lighting chunk) it falls back to
    the same engine-default sky the single-state manifest has always used.
    """
    data = {
        "ambient": {
            "r": lighting.ambient_r if lighting else 0,
            "g": lighting.ambient_g if lighting else 0,
            "b": lighting.ambient_b if lighting else 0,
        },
        "directional_lights": [],
        "gradient": {
            "top": {
                "r": lighting.gradient_top_r if lighting else 26,
                "g": lighting.gradient_top_g if lighting else 38,
                "b": lighting.gradient_top_b if lighting else 77,
            },
            "bottom": {
                "r": lighting.gradient_bottom_r if lighting else 77,
                "g": lighting.gradient_bottom_g if lighting else 128,
                "b": lighting.gradient_bottom_b if lighting else 179,
            },
        },
    }
    if lighting and lighting.directional_lights:
        for light in lighting.directional_lights:
            data["directional_lights"].append({
                "color": {
                    "r": light.color_r,
                    "g": light.color_g,
                    "b": light.color_b,
                },
                "elevation": round(light.direction_elevation, 2),
                "azimuth": round(light.direction_azimuth, 2),
            })
    return data
