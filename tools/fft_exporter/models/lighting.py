"""Lighting data models."""

from dataclasses import dataclass, field
from typing import List, Tuple


@dataclass
class DirectionalLight:
    """Directional light data."""
    color_r: int = 0
    color_g: int = 0
    color_b: int = 0
    direction_elevation: float = 0.0
    direction_azimuth: float = 0.0


@dataclass
class Lighting:
    """Lighting data structure."""
    ambient_r: int = 0
    ambient_g: int = 0
    ambient_b: int = 0
    directional_lights: List[DirectionalLight] = field(default_factory=list)
    # Background gradient (6 bytes after ambient)
    gradient_top_r: int = 0
    gradient_top_g: int = 0
    gradient_top_b: int = 0
    gradient_bottom_r: int = 0
    gradient_bottom_g: int = 0
    gradient_bottom_b: int = 0
