"""Tests for tools/fft_exporter/exporters/coordinates.py.

Verifies the parser-time PSX → Godot coordinate conversion. The Z axis flip
(part of the 180° rotation around X required by ADR-0052) lives here, so the
test pins it: PSX file values at near-Z corner of the map map to world Z =
size_z * 28 / 50; values at far-Z corner map to world Z = 0.

Run from tools/:
    uv run python -m unittest test_coordinates
"""

from __future__ import annotations

import math
import unittest

from fft_exporter.exporters.coordinates import convert_normal, convert_position


class ConvertPositionTest(unittest.TestCase):

    def test_z_zero_maps_to_far_corner_of_map(self) -> None:
        """PSX z=0 (near corner of the PSX frame) is the far corner in our
        coord system after the 180° rotation around X. For a 10-tile-deep
        map (size_z_psx_units = 10*28 = 280) it must land at world Z = 5.6."""
        x_out, y_out, z_out = convert_position(0, 0, 0, size_z_psx_units=280)
        self.assertAlmostEqual(z_out, 5.6, places=6)

    def test_z_at_size_z_psx_units_maps_to_origin(self) -> None:
        """PSX vertex at the far-Z corner of the map maps to world Z = 0."""
        _, _, z_out = convert_position(0, 0, 280, size_z_psx_units=280)
        self.assertAlmostEqual(z_out, 0.0, places=6)

    def test_x_axis_conversion_unchanged(self) -> None:
        """ADR-0052 keeps the X axis untouched; convert_position still does
        the existing X-negation independent of the new Z-flip."""
        x_out, _, _ = convert_position(50, 0, 0, size_z_psx_units=280)
        self.assertAlmostEqual(x_out, -1.0, places=6)

    def test_y_axis_conversion_unchanged(self) -> None:
        """ADR-0052 keeps the Y conversion untouched (existing pipeline
        negates Y at mesh parse time; convert_position itself doesn't)."""
        _, y_out, _ = convert_position(0, 50, 0, size_z_psx_units=280)
        self.assertAlmostEqual(y_out, 1.0, places=6)


class ConvertNormalTest(unittest.TestCase):
    """The parser-time 180° rotation around X (ADR-0052) negates the Z
    component of vertex normals (X unchanged, Y handled by upstream parse-time
    negation). These tests pin the spherical → cartesian sign convention."""

    def test_z_axis_normal_negates(self) -> None:
        """convert_normal(elevation=0, azimuth=90) is the +Z PSX unit normal.
        After the Z flip it must come out as -Z."""
        nx, ny, nz = convert_normal(0, 90)
        self.assertAlmostEqual(nx, 0.0, places=6)
        self.assertAlmostEqual(ny, 0.0, places=6)
        self.assertAlmostEqual(nz, -1.0, places=6)

    def test_x_axis_normal_unchanged(self) -> None:
        """convert_normal(elevation=0, azimuth=180) is the +X PSX unit normal
        in the existing convention (X-negation matches convert_position).
        The Z flip leaves it intact."""
        nx, ny, nz = convert_normal(0, 180)
        self.assertAlmostEqual(nx, 1.0, places=6)
        self.assertAlmostEqual(ny, 0.0, places=6)
        self.assertAlmostEqual(nz, 0.0, places=6)

    def test_y_axis_normal_unchanged(self) -> None:
        """Elevation 90° puts the unit normal on +Y; the Z flip leaves it
        alone."""
        nx, ny, nz = convert_normal(90, 0)
        self.assertAlmostEqual(nx, 0.0, places=6)
        self.assertAlmostEqual(ny, 1.0, places=6)
        self.assertAlmostEqual(nz, 0.0, places=6)


if __name__ == "__main__":
    unittest.main()
