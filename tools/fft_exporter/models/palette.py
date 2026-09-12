"""Palette data models."""

from dataclasses import dataclass, field
from typing import List


@dataclass
class PaletteColor:
    """A single color in a palette (5-bit per channel internally)."""
    red: int  # 0-31 (5-bit)
    green: int  # 0-31 (5-bit)
    blue: int  # 0-31 (5-bit)
    is_transparent: bool

    def to_rgba(self) -> tuple[int, int, int, int]:
        """Convert to 8-bit RGBA tuple.

        Uses the formula: output = round(input * 255 / 31)
        """
        ratio = 255.0 / 31.0
        r = round(self.red * ratio)
        g = round(self.green * ratio)
        b = round(self.blue * ratio)

        # Transparent black -> alpha 0, otherwise alpha 255
        if self.is_transparent and r == 0 and g == 0 and b == 0:
            a = 0
        else:
            a = 255

        return (r, g, b, a)


@dataclass
class Palette:
    """A 16-color palette."""
    colors: List[PaletteColor] = field(default_factory=list)

    def to_dict(self, palette_id: int) -> dict:
        """Convert to dictionary for JSON export."""
        return {
            "id": palette_id,
            "colors": [
                {"r": c[0], "g": c[1], "b": c[2], "a": c[3]}
                for c in (color.to_rgba() for color in self.colors)
            ]
        }
