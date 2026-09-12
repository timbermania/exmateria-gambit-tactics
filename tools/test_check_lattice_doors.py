"""Seed-red tests for the Tile-door register (ADR-0164 dec. 4 criterion 3 / ADR-0166 dec. 4).

An arm that has never been seen to FIRE is indistinguishable from an arm that cannot
fire, and this family's own history is the argument twice over:

  1. `check_addon_portability.py` shipped green across an entire extraction because it
     stopped looking.
  2. THIS guard's sibling control, `test_an_unlisted_reach_is_still_RED`, went vacuous
     the day its debt was paid because it was written against the debt. So none of the
     seeds below thin a list or lean on a row that happens to exist today — each writes
     a real member into the real addon and removes it in `finally`. When the register
     reaches 0 these tests do not change.

TWO SCANNER DEFECTS ARE PINNED HERE AS REGRESSIONS, both live during the build:

  - A WRAPPED `func` HEADER. The first draft scanned per line and asserted the addon had
    none. It has fourteen. `test_a_wrapped_header_is_still_a_door` seeds one.
  - THE SIGNAL LOOKBEHIND. The first draft's signal pattern was
    `(?<![.\\w])name\\s*\\.\\s*connect`, which excludes `tile_cursor.cursor_stepped.connect(...)`
    — the only form that exists. It scored two live doors as named by nobody and filed
    them to the reporting arm. `test_a_signal_connected_through_its_emitter_counts` is
    that regression.

Run from tools/:
    uv run python -m unittest test_check_lattice_doors
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

# CHDIR BEFORE THE IMPORT: the guard resolves `tools/touch_matrix.py` relative to the
# project dir to slice `strip_noncode` out of it.
os.chdir(PROJECT_DIR)

import check_lattice_doors as cld

ADDON = PROJECT_DIR / "addons" / "exmateria_battlefield"


def _run(burn_down=None):
    buf = io.StringIO()
    original = cld.DOOR_BURN_DOWN
    if burn_down is not None:
        cld.DOOR_BURN_DOWN = burn_down
    try:
        with contextlib.redirect_stdout(buf):
            rc = cld.main()
    finally:
        cld.DOOR_BURN_DOWN = original
        os.chdir(PROJECT_DIR)
    return rc, buf.getvalue()


class SeedFile:
    """A door written into the REAL addon, optionally with a caller OUTSIDE it.

    A scratch package would prove the code path, which is not the claim: the claim is
    that the register, over THIS addon with THIS repo's outside-namer scan, reports a
    door that hands a `Tile` out. Both files are removed in `__exit__` whether or not
    the body raised.

    🔴 `caller` IS NOT OPTIONAL DECORATION, AND THE FIRST DRAFT LEARNED IT THE HARD WAY.
    Arm 1 is "a door NAMED OUTSIDE the addon"; a door nobody names is arm 2, which
    REPORTS and returns 0 — that is ADR-0166 dec. 4's own exclusion for
    `DynamicTerrainBuilder.add_terrain`. Seeding only the addon side therefore produced
    a green run and an assertion failure that read like a broken guard. A seed for an
    enforcing arm has to satisfy every clause of that arm, and "named outside" is a
    clause.
    """

    def __init__(self, name: str, body: str, caller: str | None = None):
        self.path = ADDON / "lattice" / name
        self.body = body
        self.caller_path = PROJECT_DIR / "tests" / "_DoorSeedCaller.gd" if caller else None
        self.caller = caller

    def __enter__(self):
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        self.path.write_text(self.body, encoding="utf-8")
        if self.caller_path is not None:
            assert not self.caller_path.exists(), f"a previous run leaked {self.caller_path}"
            self.caller_path.write_text(self.caller, encoding="utf-8")
        return self.path

    def __exit__(self, *exc):
        self.path.unlink(missing_ok=True)
        if self.caller_path is not None:
            self.caller_path.unlink(missing_ok=True)
        return False


class TheShippedRegister(unittest.TestCase):

    def test_the_shipped_rows_are_live_and_none_is_stale(self):
        rc, out = _run()
        self.assertNotIn("STALE DOOR_BURN_DOWN", out)
        self.assertNotIn("TILE DOOR:", out)
        self.assertEqual(rc, 0, out)

    def test_a_LISTED_row_prints_above_the_verdict(self):
        """A listed row must PRINT, under a heading that says it is not a pass — the
        property that makes `check_par_shaders.BURN_DOWN` a burn-down and not an
        exemption (ADR-0184 dec. 4).

        🔴 SEEDED, NOT READ OFF THE SHIPPED LIST, and this file's own docstring was
        wrong about it. The previous version iterated `DOOR_BURN_DOWN` and demanded each
        member appear; the register prints its heading only when it has rows, so at zero
        that test became a loop over nothing wrapped around an `assertIn("Not a pass")`
        that could only FAIL. A control that depends on the debt it controls for expires
        on success — third instance in this family (`check_lattice_ports`
        `test_a_LISTED_row_prints_above_the_verdict` is the second). It now constructs
        the door AND the row, so it says the same thing at any register size, zero
        included."""
        body = ("extends Node\n\n\nfunc seeded_listed_door(x: int) -> Tile:\n"
                "\treturn null\n")
        caller = "extends Node\n\n\nfunc f(m) -> void:\n\tm.seeded_listed_door(0)\n"
        listed = dict(cld.DOOR_BURN_DOWN)
        listed[("addons/exmateria_battlefield/lattice/_door_seed.gd",
                "seeded_listed_door")] = (
            "#0", "a seeded row, so the printing property has something to print")
        with SeedFile("_door_seed.gd", body, caller):
            rc, out = _run(listed)
        self.assertIn("TILE-DOOR REGISTER", out)
        self.assertIn("Not a pass", out)
        self.assertIn("seeded_listed_door", out)
        self.assertIn("a seeded row", out)
        # ...and it printed as a LISTED row, not as the unlisted failure.
        self.assertNotIn("TILE DOOR:", out)
        self.assertEqual(rc, 0, out)


class BothDirectionsFail(unittest.TestCase):

    def test_an_unlisted_door_is_RED(self):
        body = ("extends Node\n\n\nfunc seeded_door(x: int) -> Tile:\n"
                "\treturn null\n")
        caller = "extends Node\n\n\nfunc f(m) -> void:\n\tm.seeded_door(0)\n"
        with SeedFile("_door_seed.gd", body, caller):
            rc, out = _run()
        self.assertIn("TILE DOOR:", out)
        self.assertIn("seeded_door", out)
        self.assertEqual(rc, 1, out)

    def test_a_door_NOBODY_names_reports_instead_of_failing(self):
        """The other side of arm 1's "named outside" clause, and the reason
        `test_an_unlisted_door_is_RED` needs a caller. ADR-0166 dec. 4 excludes
        `DynamicTerrainBuilder.add_terrain` / `remove_terrain_in_bounds` on exactly this
        ground: a door is only a door if something walks through it."""
        body = ("extends Node\n\n\nfunc seeded_door(x: int) -> Tile:\n"
                "\treturn null\n")
        with SeedFile("_door_seed.gd", body):
            rc, out = _run()
        self.assertIn("INTERNAL-BUT-PUBLIC", out)
        self.assertIn("seeded_door", out.split("INTERNAL-BUT-PUBLIC", 1)[1])
        self.assertNotIn("TILE DOOR:", out)
        self.assertEqual(rc, 0, out)

    def test_a_row_whose_door_LOST_its_Tile_is_STALE(self):
        """The shape a CLOSED row actually has, which is not the shape
        `test_a_stale_row_is_RED` seeds. That one deletes the member; closing a door
        keeps the member and narrows it — `active_tile() -> Tile` becomes private, a
        `signal cursor_moved(grid_pos: Vector2i, tile: Tile)` becomes
        `(grid_pos: Vector2i)`. The member still resolves, so a scanner that asked "does
        this name exist?" would keep the row alive and read 5 forever. It asks "is this
        name a DOOR?", so the row goes stale and the guard says so."""
        body = ("extends Node\n\n\nfunc seeded_narrowed_door(x: int) -> Vector2i:\n"
                "\treturn Vector2i.ZERO\n")
        caller = "extends Node\n\n\nfunc f(m) -> void:\n\tm.seeded_narrowed_door(0)\n"
        seeded = dict(cld.DOOR_BURN_DOWN)
        seeded[("addons/exmateria_battlefield/lattice/_door_seed.gd",
                "seeded_narrowed_door")] = ("#0", "a row whose door no longer hands a Tile out")
        with SeedFile("_door_seed.gd", body, caller):
            rc, out = _run(seeded)
        self.assertIn("STALE DOOR_BURN_DOWN", out)
        self.assertIn("seeded_narrowed_door", out)
        self.assertEqual(rc, 1, out)

    def test_a_stale_row_is_RED(self):
        seeded = dict(cld.DOOR_BURN_DOWN)
        seeded[("addons/exmateria_battlefield/lattice/MapConstants.gd", "no_such_door")] = (
            "#0", "a row that names no door")
        rc, out = _run(seeded)
        self.assertIn("STALE DOOR_BURN_DOWN", out)
        self.assertIn("no_such_door", out)
        self.assertEqual(rc, 1, out)

    def test_the_seed_is_what_reddens_it_and_not_the_tree(self):
        """The control for the two above: without the file, the same call is green,
        and the seed did not leak."""
        self.assertFalse((ADDON / "lattice" / "_door_seed.gd").exists(),
                         "a seed test leaked its addon file")
        self.assertFalse((PROJECT_DIR / "tests" / "_DoorSeedCaller.gd").exists(),
                         "a seed test leaked its caller file")
        rc, out = _run()
        self.assertNotIn("TILE DOOR:", out)
        self.assertEqual(rc, 0, out)


class ScannerRegressions(unittest.TestCase):

    def test_a_wrapped_header_is_still_a_door(self):
        """GDScript wraps long signatures and this addon has fourteen. A per-line scan
        reads a wrapped header as NO door, which is a guard that is green because it
        stopped looking."""
        body = ("extends Node\n\n\nfunc wrapped_door(\n\t\tx: int,\n\t\tz: int) -> Tile:\n"
                "\treturn null\n")
        caller = "extends Node\n\n\nfunc f(m) -> void:\n\tm.wrapped_door(0, 0)\n"
        with SeedFile("_door_seed.gd", body, caller):
            rc, out = _run()
        self.assertIn("wrapped_door", out)
        self.assertIn("TILE DOOR:", out)
        self.assertEqual(rc, 1, out)

    def test_a_signal_connected_through_its_emitter_counts(self):
        """`outside_namers` must match `x.sig.connect(...)`. A `(?<![.\\w])` lookbehind
        on the signal pattern excludes exactly that form — the only one that exists —
        and files a live door to the reporting arm as "named by nobody"."""
        self.assertTrue(cld.outside_namers("cursor_stepped"),
                        "cursor_stepped is connected at src/scenes/BattlefieldWiring.gd")
        self.assertTrue(any("BattlefieldWiring" in h for h in cld.outside_namers("cursor_stepped")))

    def test_a_private_member_is_not_a_door(self):
        """`_get_tile_at` and `_create_tile` both return `Tile` and are excluded by
        ADR-0166 dec. 4 on the leading underscore. A seed with one must stay green."""
        body = "extends Node\n\n\nfunc _private_door() -> Tile:\n\treturn null\n"
        with SeedFile("_door_seed.gd", body):
            rc, out = _run()
        self.assertNotIn("_private_door", out.split("PARAMETER POSITION")[0])
        self.assertEqual(rc, 0, out)

    def test_a_parameter_door_reports_but_does_not_fail(self):
        """Arm 3 is REPORTING: the rule as ADR-0166 dec. 4 writes it covers return and
        signal-payload position only. A parameter must print and must not redden."""
        body = "extends Node\n\n\nfunc takes_a_tile(t: Tile) -> void:\n\tprint(t)\n"
        with SeedFile("_door_seed.gd", body):
            rc, out = _run()
        self.assertIn("PARAMETER POSITION", out)
        self.assertIn("takes_a_tile", out)
        self.assertEqual(rc, 0, out)

    def test_a_non_Tile_return_is_not_a_door(self):
        """The control that proves the seeds above turn on the TYPE and not on the
        file existing. `-> TileCursor` must not match `-> Tile`."""
        body = "extends Node\n\n\nfunc not_a_door() -> TileCursor:\n\treturn null\n"
        with SeedFile("_door_seed.gd", body):
            rc, out = _run()
        self.assertNotIn("not_a_door", out)
        self.assertEqual(rc, 0, out)


if __name__ == "__main__":
    unittest.main()
