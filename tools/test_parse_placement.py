"""Unit tests for tools/parse_placement.py.

Covers the two scenario-sourced strategy-phase placement tables:
  - the deployment-zone table (ATTACK.OUT 0xBBD4) -> player START tiles
  - ENTD enemy positions (BATTLE/ENTD{1..4}.ENT) -> enemy START tiles

Pure-function tests run on synthetic bytes; a final group validates the real
decode against the retail ROM (Gariland deployment idx 256 -> 8 tiles, maxsq 5).

Uses stdlib unittest so there's no pytest dep on the tools venv.

Run from tools/:
    uv run python -m unittest test_parse_placement
"""

from __future__ import annotations

import struct
import unittest

import parse_placement as p
import _repo_paths as rp


def _deploy_record(bitmap: int, cx: int, cy: int, facing: int,
                   max_squad: int, map_id: int, dep_id: int) -> bytes:
    """Build a synthetic 12-byte deployment-zone record. `facing` is the raw
    0x07 byte (high nibble unit_facing, low nibble zone_facing)."""
    rec = bytearray(12)
    struct.pack_into("<I", rec, 0, bitmap)
    rec[4] = cx
    rec[5] = cy
    rec[7] = facing
    rec[8] = max_squad
    rec[9] = map_id
    struct.pack_into("<H", rec, 10, dep_id)
    return bytes(rec)


def _entd_unit(sprite: int, pos_x: int, pos_y: int,
               is_player: bool, upper: bool = False, direction: int = 0,
               team: int = 1) -> bytes:
    """Build a synthetic 40-byte ENTD unit record (only the fields we read)."""
    rec = bytearray(40)
    rec[0] = sprite
    flags2 = (team << 4) & 0x30
    if is_player:
        flags2 |= 0x08
    rec[0x18] = flags2
    rec[0x19] = pos_x
    rec[0x1a] = pos_y
    flags3 = direction & 0x03
    if upper:
        flags3 |= 0x80
    rec[0x1b] = flags3
    return bytes(rec)


class RotateQuarter(unittest.TestCase):
    """Quarter-turn rotation must match Godot's Vector2.rotated(k*PI/2).round()."""

    def test_identity(self):
        self.assertEqual(p.rotate_quarter(1, -2, 0), (1, -2))

    def test_90(self):
        # Godot rotated(PI/2) on integer coords: (x, y) -> (-y, x)
        self.assertEqual(p.rotate_quarter(1, -2, 1), (2, 1))

    def test_180(self):
        self.assertEqual(p.rotate_quarter(1, -2, 2), (-1, 2))

    def test_270(self):
        # rotated(3PI/2): (x, y) -> (y, -x)
        self.assertEqual(p.rotate_quarter(1, -2, 3), (-2, -1))


class DeploymentBitmapDecode(unittest.TestCase):

    def test_single_bit_uses_shift_not_square(self):
        # bit 0 set. Correct (1<<idx) => idx 0 present => base (-2,-2).
        # The upstream bug (idx**2) would mark idx 1 instead (base (-1,-2)).
        rec = _deploy_record(0x1, cx=0, cy=0, facing=0, max_squad=1,
                             map_id=7, dep_id=0)
        zone = p.decode_deployment_zone(rec, 0)
        self.assertEqual(zone.tiles, [(-2, -2)])

    def test_center_bit(self):
        rec = _deploy_record(1 << 12, cx=10, cy=10, facing=0, max_squad=1,
                             map_id=7, dep_id=0)
        zone = p.decode_deployment_zone(rec, 0)
        self.assertEqual(zone.tiles, [(10, 10)])

    def test_full_5x5_is_25_tiles(self):
        rec = _deploy_record(0x01ffffff, cx=10, cy=10, facing=0, max_squad=5,
                             map_id=7, dep_id=0)
        zone = p.decode_deployment_zone(rec, 0)
        self.assertEqual(len(zone.tiles), 25)

    def test_rotation_applied_with_center(self):
        # bit 7 -> base (0, -1); zone_facing 1 -> (-y, x) = (1, 0); + center.
        rec = _deploy_record(1 << 7, cx=5, cy=5, facing=0x01, max_squad=1,
                             map_id=7, dep_id=0)
        zone = p.decode_deployment_zone(rec, 0)
        self.assertEqual(zone.zone_facing, 1)
        self.assertEqual(zone.tiles, [(6, 5)])

    def test_facing_nibbles(self):
        rec = _deploy_record(0x1, cx=0, cy=0, facing=0x23, max_squad=1,
                             map_id=7, dep_id=0)
        zone = p.decode_deployment_zone(rec, 0)
        self.assertEqual(zone.zone_facing, 3)
        self.assertEqual(zone.unit_facing, 2)


class ChiralityFix(unittest.TestCase):
    """ADR-0052/0057: a deployment tile is a Placement quantity, so it gets the
    180°-about-X depth flip (`y -> size_z-1-y`) at parse time — same rule the
    ENTD enemy positions already get. Without it the player's owned units deploy
    mirrored (opposite the zone), while the pre-flipped enemies land right."""

    def _zone(self, tiles, center_y=5, facing=0x23):
        return p.DeploymentZone(
            deployment_idx=0, center_x=3, center_y=center_y,
            zone_facing=facing & 0x0F, unit_facing=(facing & 0xF0) >> 4,
            max_squad_size=1, map_id=7, tiles=list(tiles),
        )

    def test_tile_y_renumbers_to_our_coord(self):
        z = self._zone([(3, 13), (6, 11)])
        p.apply_chirality_fix_to_zone(z, size_z_tiles=15)
        # y -> 15 - 1 - y = 14 - y; x untouched.
        self.assertEqual(z.tiles, [(3, 1), (6, 3)])

    def test_center_y_flipped_x_kept(self):
        z = self._zone([(3, 13)], center_y=12)
        p.apply_chirality_fix_to_zone(z, size_z_tiles=15)
        self.assertEqual(z.center_y, 2)
        self.assertEqual(z.center_x, 3)

    def test_facing_untouched(self):
        # Facing is an Orientation pose, consumed raw — never chirality-flipped.
        z = self._zone([(3, 13)], facing=0x23)
        p.apply_chirality_fix_to_zone(z, size_z_tiles=15)
        self.assertEqual(z.zone_facing, 3)
        self.assertEqual(z.unit_facing, 2)


class EntdDecode(unittest.TestCase):

    def test_enemy_filter_excludes_player_and_empty(self):
        rec = bytearray(640)
        # slot 0: enemy at (4, 5)
        rec[0:40] = _entd_unit(0x80, 4, 5, is_player=False)
        # slot 1: player-controlled (excluded)
        rec[40:80] = _entd_unit(0x80, 9, 9, is_player=True)
        # slot 2: enemy at (6, 7), upper level, facing east
        rec[80:120] = _entd_unit(0x82, 6, 7, is_player=False, upper=True,
                                 direction=1)
        # slots 3..15 left empty (sprite 0) -> skipped
        record = p.decode_entd_record(bytes(rec), 17)
        self.assertEqual(record.entd_idx, 17)
        self.assertEqual(len(record.enemies), 2)
        e0, e1 = record.enemies
        self.assertEqual((e0.x, e0.y, e0.upper_level), (4, 5, 0))
        self.assertEqual((e1.x, e1.y, e1.upper_level, e1.facing), (6, 7, 1, 1))

    def test_entd_index_resolution(self):
        # flat 0..511 index -> (file 1..4, record-in-file)
        self.assertEqual(p.entd_file_and_record(0), (1, 0))
        self.assertEqual(p.entd_file_and_record(127), (1, 127))
        self.assertEqual(p.entd_file_and_record(128), (2, 0))
        self.assertEqual(p.entd_file_and_record(511), (4, 127))


class RomValidation(unittest.TestCase):
    """Validate the real decode against the retail extract (skips if absent)."""

    @classmethod
    def setUpClass(cls):
        cls.attack_out = rp.attack_out()
        if not cls.attack_out.exists():
            raise unittest.SkipTest(f"extract missing: {cls.attack_out}")

    def test_gariland_deployment_idx_256(self):
        data = self.attack_out.read_bytes()
        off = p.DEPLOY_OFFSET + 256 * p.DEPLOY_STRIDE
        zone = p.decode_deployment_zone(data[off:off + p.DEPLOY_STRIDE], 256)
        self.assertEqual(zone.max_squad_size, 5)
        self.assertEqual(zone.map_id, 22)
        self.assertEqual(len(zone.tiles), 8)
        self.assertEqual(
            set(zone.tiles),
            {(3, 13), (3, 12), (4, 12), (5, 12),
             (6, 12), (6, 11), (7, 12), (7, 11)},
        )

    def test_gariland_deployment_idx_256_chirality_flipped(self):
        # Gariland is MAP022, size_z = 15 -> y maps to 14 - y. This is what the
        # navigator/strategy phase consume so the owned units land on the SAME
        # side as the zone (opposite the red thieves).
        data = self.attack_out.read_bytes()
        off = p.DEPLOY_OFFSET + 256 * p.DEPLOY_STRIDE
        zone = p.decode_deployment_zone(data[off:off + p.DEPLOY_STRIDE], 256)
        p.apply_chirality_fix_to_zone(zone, size_z_tiles=15)
        self.assertEqual(
            set(zone.tiles),
            {(3, 1), (3, 2), (4, 2), (5, 2),
             (6, 2), (6, 3), (7, 2), (7, 3)},
        )


class UnitFacingLift(unittest.TestCase):
    """The deployment facing byte's TWO nibbles -> a 12-bit world facing angle.

    The engine adds them (ATTACK.OUT overlay 0x801C5588: `R = zone_facing +
    unit_facing - 1`, masked to 2 bits) and each of the four unrolled placement
    loops ORs a hard-coded facing of `(-R) & 3` into the deploy record — so the
    lift is `((1 - unit_facing - zone_facing) & 3) << 10`.
    """

    def test_rotates_with_both_nibbles(self):
        # zone_facing=3 is the family the old unit_facing-alone table was
        # calibrated on, so it is unchanged: {0:W 1:S 2:E 3:N} on the render
        # wheel (0x000=East, 0x400=South, 0x800=West, 0xC00=North).
        self.assertEqual(p.start_facing_12bit(0, 3), 0x800)  # West
        self.assertEqual(p.start_facing_12bit(1, 3), 0x400)  # South
        self.assertEqual(p.start_facing_12bit(2, 3), 0x000)  # East
        self.assertEqual(p.start_facing_12bit(3, 3), 0xC00)  # North
        # ... and every other zone_facing is a quarter turn off it.
        self.assertEqual(p.start_facing_12bit(2, 2), 0x400)
        self.assertEqual(p.start_facing_12bit(2, 1), 0x800)
        self.assertEqual(p.start_facing_12bit(2, 0), 0xC00)

    def test_rom_variant_facing_table(self):
        """All 16 (unit_facing, zone_facing) pairs, as LITERAL angles.

        Written out rather than recomputed from `(-((zf + uf - 1) & 3)) & 3`,
        which is the implementation restated: such an arm catches typos and
        nothing else. These 16 come from the ROM — R = zone_facing +
        unit_facing - 1 (0x801C5588), and the four unrolled placement loops OR
        a hard-coded facing of R=0->0 (`andi 0xe0` @0x801C5654), R=1->3 (`ori
        3` @0x801C5734), R=2->2 (`ori 2` @0x801C5818), R=3->1 (`ori 1`
        @0x801C58F8), each then lifted `code << 10`.
        """
        expected = {
            #  (uf, zf): angle          R = (zf + uf - 1) & 3
            (0, 0): 0x400,   # R=3
            (1, 0): 0x000,   # R=0
            (2, 0): 0xC00,   # R=1
            (3, 0): 0x800,   # R=2
            (0, 1): 0x000,   # R=0
            (1, 1): 0xC00,   # R=1
            (2, 1): 0x800,   # R=2
            (3, 1): 0x400,   # R=3
            (0, 2): 0xC00,   # R=1
            (1, 2): 0x800,   # R=2  <- Mandalia, zone 257
            (2, 2): 0x400,   # R=3
            (3, 2): 0x000,   # R=0  <- Fort Zeakden, zone 266
            (0, 3): 0x800,   # R=2
            (1, 3): 0x400,   # R=3
            (2, 3): 0x000,   # R=0  <- Gariland, zone 256
            (3, 3): 0xC00,   # R=1
        }
        for (uf, zf), angle in expected.items():
            self.assertEqual(
                p.start_facing_12bit(uf, zf), angle,
                f"unit_facing={uf} zone_facing={zf}",
            )

    def test_masks_to_low_two_bits(self):
        self.assertEqual(p.start_facing_12bit(0x12, 3), p.start_facing_12bit(2, 3))
        self.assertEqual(p.start_facing_12bit(2, 0x13), p.start_facing_12bit(2, 3))

    def test_gariland_faces_east_toward_thieves(self):
        # Zone 256 (Gariland): zone_facing=3, unit_facing=2 -> East (0x000). The
        # owned units deploy on the near half (grid_z 1-3) and must face +Z=East
        # to meet the red thieves on the far half (grid_z 9-13, facing back West
        # at 0x800).
        self.assertEqual(p.start_facing_12bit(2, 3), 0x000)

    def test_mandalia_faces_west_toward_the_corps(self):
        # Zone 257 (Mandalia Plains): zone_facing=2, unit_facing=1 -> West
        # (0x800). The squad deploys at grid_z 10-11 and the Corps knights sit at
        # grid_z 0-5, so it must face -Z. The unit_facing-alone table lifted this
        # to 0x400 (-X) and the squad stood side-on to the battle.
        self.assertEqual(p.start_facing_12bit(1, 2), 0x800)


if __name__ == "__main__":
    unittest.main()
