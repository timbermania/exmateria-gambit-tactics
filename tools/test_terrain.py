"""Tests for tools/fft_exporter/exporters/terrain.py.

Pins the parser-time tile-Z renumber: after the 180° rotation around X
(ADR-0052), tile records in terrain.json are written in our-coord row-major
order, with each tile's `z` index reading from the our-coord side.

Run from tools/:
    uv run python -m unittest test_terrain
"""

from __future__ import annotations

import unittest

from fft_exporter.exporters.terrain import renumber_tile_z


class RenumberTileZTest(unittest.TestCase):

    def test_psx_z_zero_becomes_far_row(self) -> None:
        """PSX z=0 (near corner) maps to our-coord z = size_z - 1 (far row)."""
        self.assertEqual(renumber_tile_z(0, 10), 9)

    def test_psx_z_max_becomes_origin(self) -> None:
        """PSX z=size_z-1 (far corner) maps to our-coord z=0 (near row)."""
        self.assertEqual(renumber_tile_z(9, 10), 0)

    def test_middle_index_mirrors(self) -> None:
        """A middle index reflects across the map center."""
        self.assertEqual(renumber_tile_z(4, 10), 5)

    def test_idempotent_round_trip(self) -> None:
        """Renumbering twice should land back on the input — the operation
        is its own inverse (size_z - 1 - (size_z - 1 - z) == z)."""
        for z_in in range(10):
            self.assertEqual(renumber_tile_z(renumber_tile_z(z_in, 10), 10), z_in)


if __name__ == "__main__":
    unittest.main()
