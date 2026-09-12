"""Seed-red tests for the duck-typed-door register (ADR-0164 dec. 4 crit. 2 / ADR-0192).

Every seed below CONSTRUCTS the site it asserts on. None of them leans on a site
today's debt happens to provide, and that is not style — the 27 sites this guard
reports are the exact population the port is about to delete. A control written
against the defect EXPIRES ON SUCCESS and the expiry is indistinguishable from a
regression (`test_an_unlisted_reach_is_still_RED`, `rows.size() == 46`, both at #642).
When arm 1 reaches 0 these tests do not change.

🔴 SEED EVERY CLAUSE OF THE ARM. Arm 1 is "a receiver NOT provably `Lattice`, calling a
port method". A seed that writes the call but leaves the receiver typed `Lattice` lands
in the clean bucket and returns 0, and the failure reads like a broken guard rather than
a mis-seeded test. Each seed below states which clause it varies.

Run from tools/:
    uv run python -m unittest test_check_lattice_ports
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

# CHDIR BEFORE THE IMPORT: the guard slices `strip_noncode` out of `tools/touch_matrix.py`
# relative to the project dir.
os.chdir(PROJECT_DIR)

import check_lattice_ports as clp


def _run(burn_down=None, argv=None):
    buf = io.StringIO()
    original_bd, original_argv = clp.PORT_BURN_DOWN, sys.argv
    if burn_down is not None:
        clp.PORT_BURN_DOWN = burn_down
    if argv is not None:
        sys.argv = ["check_lattice_ports.py"] + argv
    try:
        with contextlib.redirect_stdout(buf):
            rc = clp.main()
    finally:
        clp.PORT_BURN_DOWN, sys.argv = original_bd, original_argv
        os.chdir(PROJECT_DIR)
    return rc, buf.getvalue()


def _unlisted(out: str) -> str:
    """Only the text of the UNLISTED sections.

    🔴 A SEED TEST MUST READ THE ARM IT SEEDED, NOT THE WHOLE REPORT. `_run()`'s output
    also carries the burn-down rows and the STALE section, and both contain the same
    labels a seed writes — `test_an_unlisted_MOCK_PRODUCER_is_RED` was measured passing
    under a mutation that turned the producer scan OFF, because deleting the scan turned
    seven shipped rows stale and the stale block printed `func get_tile()` for it. rc was
    1 for the wrong reason and the assertion matched the wrong section. That is this
    codebase's "a source assertion can match its own comment", one guard over."""
    out_lines, keep, buf = out.splitlines(), False, []
    for ln in out_lines:
        if ln.startswith(("ARM ", "STALE ", "Duck-typed", "subject:", "arm ")):
            keep = "NOT ON PORT_BURN_DOWN" in ln
        if keep:
            buf.append(ln)
    return "\n".join(buf)


class Seed:
    """A `.gd` file written into the REAL tree and removed in `__exit__`.

    A scratch package would prove the code path, which is not the claim: the claim is
    that THIS guard, over THIS repo, with THIS receiver-type inference, reports the site.
    """

    def __init__(self, body: str, root: str = "src", name: str = "_PortSeed.gd"):
        self.path = PROJECT_DIR / root / name
        self.body = body

    def __enter__(self):
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        self.path.write_text(self.body, encoding="utf-8")
        return self.path

    def __exit__(self, *exc):
        self.path.unlink(missing_ok=True)
        return False


class Arm1TheReceiverIsNotProvablyLattice(unittest.TestCase):
    """Arm 1, ADR-0192 dec. 2: clean IFF the receiver is annotated `Lattice`."""

    def test_a_bare_untyped_receiver_is_RED(self):
        """The `var _map` shape — CinematicFacingResolver.gd:64."""
        body = ("extends Node\n\n"
                "var _seed_map\n\n\n"
                "func f() -> void:\n"
                "\tvar t = _seed_map.get_tile(0, 0)\n"
                "\tprint(t)\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn("_PortSeed.gd", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_a_TYPED_receiver_that_is_not_Lattice_is_still_RED(self):
        """🔴 THE INVERSION, and the reason arm 1 is an allowlist (ADR-0192 dec. 2).

        ADR-0170 dec. 5 phrased arm 1 as "the receiver carries no type", and that
        sentence is false on FIVE of its own fifteen sites: `map_composer: Node` x2,
        `map: Node3D` x2 and one `:=` inference all carry a type and are all the defect.
        A denylist phrased against ABSENCE of an annotation is satisfied by writing a
        different wrong type. This seed writes the wrong type on purpose."""
        body = ("extends Node\n\n\n"
                "func f(seed_map: Node3D) -> void:\n"
                "\tvar t = seed_map.get_tile(0, 0)\n"
                "\tprint(t)\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn("_PortSeed.gd", _unlisted(out))
        self.assertIn("`Node3D`, not `Lattice`", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_a_receiver_annotated_Lattice_is_CLEAN(self):
        """The other side of the same clause, and the control for every seed above: the
        ONLY thing that changes is the receiver's annotation. Without this the red seeds
        prove the guard reports the FILE, not the receiver."""
        body = ("extends Node\n\n"
                "var _seed_map: Lattice\n\n\n"
                "func f() -> void:\n"
                "\tvar t = _seed_map.terrain_at(0, 0)\n"
                "\tprint(t)\n")
        with Seed(body):
            rc, out = _run()
        self.assertNotIn("_PortSeed.gd", out)
        self.assertEqual(rc, 0, out)

    def test_an_inferred_receiver_is_RED(self):
        """`var map := _get_map()` — ScenarioUnitAlignmentDebugPanel.gd:131, the fifth of
        dec. 5's five. GDScript infers a type here; this guard does not, and treats an
        un-annotated declaration as not provably `Lattice`. That is the conservative
        direction and it is the one dec. 2 asks for."""
        body = ("extends Node\n\n\n"
                "func _get_seed_map() -> Node:\n"
                "\treturn null\n\n\n"
                "func f() -> void:\n"
                "\tvar seed_map := _get_seed_map()\n"
                "\tvar t = seed_map.get_tile(0, 0)\n"
                "\tprint(t)\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn("_PortSeed.gd", _unlisted(out))
        self.assertIn("unannotated", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_a_chained_receiver_that_never_binds_a_handle_is_RED(self):
        """`_vm.map_composer.get_tile(...)` — ScenarioCameraDirector x3, ScenarioVM x2.
        There is no annotation site to inspect at all, so a denylist over annotations
        cannot see these five; the allowlist can, because "provably `Lattice`" is false
        for an expression that binds nothing."""
        body = ("extends Node\n\n"
                "var _seed_vm\n\n\n"
                "func f() -> void:\n"
                "\tvar t = _seed_vm.map_composer.get_tile(0, 0)\n"
                "\tprint(t)\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn("_seed_vm.map_composer.get_tile()", _unlisted(out))
        self.assertIn("chained", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_the_has_method_PROBE_form_is_a_site(self):
        """`map.has_method("get_all_tiles")` — ScenarioUnitAlignmentDebugPanel.gd:132 and
        ScenarioWeather.gd:300. The member name lives INSIDE a string literal, and
        `strip_noncode` blanks string literals; a scan that stripped first would score the
        probe form at zero."""
        body = ("extends Node\n\n"
                "var _seed_map\n\n\n"
                "func f() -> void:\n"
                "\tif _seed_map.has_method(\"get_all_tiles\"):\n"
                "\t\tprint(1)\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn('_seed_map.has_method("get_all_tiles")', _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_a_FUTURE_port_name_is_scanned_from_day_one(self):
        """ADR-0192 dec. 1: the scan keys on BOTH name sets. `Lattice` does not exist yet,
        so a guard that knew only `terrain_at` / `all_cells` would be green today and
        prove nothing — and one that knew only `get_tile` / `get_all_tiles` would go
        green the moment the port landed, while every consumer stayed duck-typed."""
        body = ("extends Node\n\n"
                "var _seed_map\n\n\n"
                "func f() -> void:\n"
                "\tvar c = _seed_map.all_cells()\n"
                "\tvar w = _seed_map.world_position_at(0, 0)\n"
                "\tprint(c, w)\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn("_seed_map.all_cells()", _unlisted(out))
        self.assertIn("_seed_map.world_position_at()", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_a_wrapped_declaration_still_types_the_receiver(self):
        """`CombatLoop.gd:313` and `:331` declare a `TerrainIndex` parameter across two
        lines. A per-line declaration scan reads a wrapped header as NO declaration and
        files a correctly-typed receiver as `undeclared` — the receiver-side twin of the
        fourteen wrapped headers `check_lattice_doors.py` found on the door side. Here
        the wrapped annotation is `Lattice`, so the site must be CLEAN; if the join
        broke, it would redden and this test would say so."""
        body = ("extends Node\n\n\n"
                "func f(\n"
                "\t\tseed_map: Lattice,\n"
                "\t\tflag: bool = false) -> void:\n"
                "\tif flag:\n"
                "\t\tprint(seed_map.all_cells())\n")
        with Seed(body):
            rc, out = _run()
        self.assertNotIn("_PortSeed.gd", out)
        self.assertEqual(rc, 0, out)

    def test_a_method_name_inside_a_STRING_is_not_a_site(self):
        """`ScenarioUnitAlignmentDebugPanel.gd:133` is a `push_warning` whose text
        contains `ProceduralMap.get_all_tiles()`. It is the whole difference between the
        raw grep's 28 and ADR-0192's 27, and a guard that counted it would report a
        population nobody can burn down."""
        body = ("extends Node\n\n\n"
                "func f() -> void:\n"
                "\tpush_warning(\"[Seed] no ProceduralMap.get_all_tiles(); skipped\")\n"
                "\t# and _seed_map.get_tile(0, 0) in a comment is not a site either\n")
        with Seed(body):
            rc, out = _run()
        self.assertNotIn("_PortSeed.gd", out)
        self.assertEqual(rc, 0, out)


class Arm1TheHandleFetch(unittest.TestCase):
    """Arm 1's third spelling, ADR-0192 dec. 3: clean IFF the result lands typed."""

    def test_a_fetch_that_lands_UNTYPED_is_RED(self):
        """`terrain_index = map.terrain_index` — GPUArena.gd:117, ProgressionTester.gd:70.
        No arm before this register saw these, and all twelve `TerrainIndex`-typed CALL
        sites got their handle at one of them: a pass that re-points 27 calls and leaves
        the three fetches has changed no structure at all."""
        body = ("extends Node\n\n"
                "var _seed_map\n"
                "var _seed_handle\n\n\n"
                "func f() -> void:\n"
                "\t_seed_handle = _seed_map.terrain_index\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn("_seed_map.terrain_index", _unlisted(out))
        self.assertIn("lands in", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_a_fetch_landing_in_a_Lattice_slot_is_CLEAN(self):
        """The permitted shape, and it is permitted rather than merely tolerated: six
        assembler scene roots hold the map as `@onready var map: Node3D = $ProceduralMap`,
        a NodePath fetch that infers `Node`, so the consumer can NEVER type the map handle
        and `map.lattice` is duck-typed permanently and by design. One untyped step, at
        the seam; everything after it typed."""
        body = ("extends Node\n\n"
                "@onready var _seed_map: Node3D = $Nothing\n\n\n"
                "func f() -> void:\n"
                "\tvar lattice: Lattice = _seed_map.lattice\n"
                "\tprint(lattice)\n")
        with Seed(body):
            rc, out = _run()
        self.assertNotIn("_PortSeed.gd", out)
        self.assertEqual(rc, 0, out)

    def test_a_fetch_landing_in_a_TerrainIndex_slot_is_RED(self):
        """`var terrain: TerrainIndex = _map.terrain_index` — NavigatorMain.gd:1275. The
        result IS annotated; the annotation is the wrong type. Without this clause dec.
        3's rule would be "lands in anything annotated", which the port cannot satisfy
        any better than today's code does."""
        body = ("extends Node\n\n"
                "var _seed_map\n\n\n"
                "func f() -> void:\n"
                "\tvar terrain: TerrainIndex = _seed_map.terrain_index\n"
                "\tprint(terrain)\n")
        with Seed(body):
            rc, out = _run()
        self.assertIn("_PortSeed.gd", _unlisted(out))
        self.assertIn("lands in `var terrain: TerrainIndex`, not `Lattice`", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_STORING_a_handle_is_not_a_fetch(self):
        """`combat_loop.terrain_index = terrain` — NavigatorMain.gd:1283, GPUArena.gd:199.
        Two of the five raw `.terrain_index` lines in `src/` are WRITES, and counting them
        would put arm 1's fetch population at 5 where ADR-0192 measured 3. This is the
        control that keeps that number honest."""
        body = ("extends Node\n\n"
                "var _seed_sink\n\n\n"
                "func f(handle) -> void:\n"
                "\t_seed_sink.terrain_index = handle\n")
        with Seed(body):
            rc, out = _run()
        self.assertNotIn("_PortSeed.gd", out)
        self.assertEqual(rc, 0, out)


class Arm2IsEnforcing(unittest.TestCase):
    """ADR-0192 dec. 7, ruled by amendment 1: a named burn-down, not reporting."""

    def test_an_unlisted_tests_consumer_is_RED(self):
        """ADR-0170 dec. 5 left arm 2 reporting-only *because `classify()` returns `None`
        for every test file and a threshold there would be guesswork*, while naming the
        risk it could not fix: *arm 1 reaching zero while 20 cases sit in `tests/` reads
        as coverage*. A named list is not a threshold — it needs no `classify()` at all —
        so the objection does not reach it and the risk is answered."""
        body = ("extends Node\n\n"
                "var _seed_map\n\n\n"
                "func f() -> void:\n"
                "\tprint(_seed_map.get_all_tiles())\n")
        with Seed(body, root="tests"):
            rc, out = _run()
        self.assertIn("ARM 2", _unlisted(out))
        self.assertIn("tests/_PortSeed.gd", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_an_unlisted_MOCK_PRODUCER_is_RED(self):
        """The other end of the duck-typing. ADR-0170 dec. 3 keeps the seam precisely so
        a test can fake a map, and dec. 6 predicts >=4 of the 7 producers are DELETED
        rather than ported — which this arm reports as a stale row, i.e. as the win."""
        body = ("extends Node\n\n\n"
                "class SeedFakeMap:\n"
                "\tfunc get_tile(x: int, z: int) -> Node3D:\n"
                "\t\treturn null\n")
        with Seed(body, root="tests"):
            rc, out = _run()
        block = _unlisted(out)
        self.assertIn("tests/_PortSeed.gd", block)
        self.assertIn("func get_tile()", block)
        self.assertIn("producer", block)
        self.assertEqual(rc, 1, out)

    def test_an_override_INSIDE_extends_Lattice_is_NOT_a_producer(self):
        """The producer arm's other direction, and the one it got wrong.

        GDScript has no interfaces, so ADR-0170 dec. 5's ⚠️ names two sanctioned mock
        routes — `extends Lattice` and override, or a real `Lattice` seeded with
        fabricated `TerrainCell`s — and requires that BOTH pass, because a rule phrased
        against subclassing forbids the cheaper one. The producer scan was blind to
        `extends`: it read every `func terrain_at` as a duck-typed mock map, so the
        repair scored as the defect and the count went UP on the pass that fixed all
        seven producers.

        The seed is the sanctioned form, with an UNSANCTIONED sibling in the same file so
        this cannot pass by the scan simply being off — the bare class must still be
        reported while the subclass is not."""
        body = ("extends Node\n\n\n"
                "class SeedPorted extends Lattice:\n"
                "\tfunc terrain_at(_x: int, _z: int) -> TerrainCell:\n"
                "\t\treturn null\n"
                "\n"
                "\tfunc all_cells() -> Array[TerrainCell]:\n"
                "\t\treturn []\n"
                "\n"
                "\n"
                "class SeedDuckMap:\n"
                "\tfunc get_all_tiles() -> Array:\n"
                "\t\treturn []\n")
        with Seed(body, root="tests"):
            rc, out = _run()
        block = _unlisted(out)
        self.assertIn("func get_all_tiles()", block)      # the bare class IS reported
        self.assertNotIn("func terrain_at()", block)      # the subclass is NOT
        self.assertNotIn("func all_cells()", block)
        self.assertEqual(rc, 1, out)


class Arm3IsInsideTheAddon(unittest.TestCase):
    """The region arms 1 and 2 exclude, and the one that paid for the omission.

    `PlayerCamera.gd` reached its map exactly the way every host file did —
    `procedural_map.get_all_tiles()` behind a `has_method` probe — and when ADR-0170
    dec. 1 deleted that forwarder off `MapComposer` the probe did not error: it started
    answering "no tiles" forever, centring the battle camera on the world origin. Found
    by grep, because no register scanned inside the addon."""

    ADDON = "addons/exmateria_battlefield"

    def test_a_LEGACY_call_on_an_untyped_receiver_INSIDE_the_addon_is_RED(self):
        body = ("extends Node\n\n\n"
                "var procedural_map: Node3D\n\n\n"
                "func recentre() -> void:\n"
                "\tif procedural_map == null or not procedural_map.has_method(\"get_all_tiles\"):\n"
                "\t\treturn\n"
                "\tvar tiles = procedural_map.get_all_tiles()\n"
                "\tprint(tiles.size())\n")
        with Seed(body, root=self.ADDON):
            rc, out = _run()
        block = _unlisted(out)
        self.assertIn("_PortSeed.gd", block)
        self.assertIn("procedural_map.get_all_tiles()", block)
        self.assertEqual(rc, 1, out)

    def test_a_LEGACY_call_on_the_STORE_alias_is_CLEAN(self):
        """The other direction, and the one that makes the arm survivable: the port and
        the builders reach the store on purpose, and they name it by `preload` because it
        has no `class_name` (ADR-0192 dec. 4). A rule that could not tell those apart
        would have to be switched off."""
        body = ("extends RefCounted\n\n"
                "const SeedStore := preload(\"res://addons/exmateria_battlefield/lattice/TerrainIndex.gd\")\n\n"
                "var _store: SeedStore = null\n\n\n"
                "func at(x: int, z: int) -> Tile:\n"
                "\treturn _store.get_tile(x, z)\n")
        with Seed(body, root=self.ADDON):
            rc, out = _run()
        self.assertNotIn("_PortSeed.gd", out)
        self.assertEqual(rc, 0, out)

    def test_a_FUTURE_call_on_a_non_Lattice_receiver_INSIDE_the_addon_is_RED(self):
        """Inside the addon a consumer of the PORT is still a consumer of the port, so
        the future half keeps arm 1's allowlist rule rather than the store rule."""
        body = ("extends Node\n\n\n"
                "var some_map\n\n\n"
                "func height_at(x: int, z: int) -> int:\n"
                "\tvar c = some_map.terrain_at(x, z)\n"
                "\treturn c.height if c else 0\n")
        with Seed(body, root=self.ADDON):
            rc, out = _run()
        block = _unlisted(out)
        self.assertIn("_PortSeed.gd", block)
        self.assertIn("some_map.terrain_at()", block)
        self.assertEqual(rc, 1, out)

    def test_the_STORE_ITSELF_is_not_scanned(self):
        """`TerrainIndex.gd` declares `func get_tile` and reaches `_tiles`; it is the
        definition, not a reach. Excluding it by path is why arm 3 needs no producer
        scan at all."""
        rc, out = _run()
        self.assertNotIn("lattice/TerrainIndex.gd", out)
        self.assertEqual(rc, 0, out)


class TheShippedRegister(unittest.TestCase):

    def test_the_shipped_rows_are_live_and_none_is_stale(self):
        rc, out = _run()
        self.assertNotIn("NOT ON PORT_BURN_DOWN", out)
        self.assertNotIn("STALE PORT_BURN_DOWN", out)
        self.assertEqual(rc, 0, out)

    def test_a_LISTED_row_prints_above_the_verdict(self):
        """A listed row must PRINT, under a heading that says it is not a pass — the
        property that makes a burn-down a burn-down and not an exemption (ADR-0184
        dec. 4).

        🔴 SEEDED, NOT READ OFF THE SHIPPED LIST. This assertion used to iterate
        `PORT_BURN_DOWN` and demand each label appear; when the port emptied the list it
        became a loop over nothing wrapped around an `assertIn("Not a pass")` that could
        only fail — a control that DEPENDS on the debt it controls for, expiring on
        success, which is the failure this whole file's docstring is about. It now writes
        the site AND the row, so it says the same thing at any burn-down size, zero
        included."""
        body = ("extends Node\n\n\n"
                "func reach(m) -> void:\n"
                "\tvar t = m.get_tile(0, 0)\n"
                "\tprint(t)\n")
        listed = dict(clp.PORT_BURN_DOWN)
        listed[("src/_PortSeed.gd", "m.get_tile()")] = (
            "#0", "a seeded row, so the printing property has something to print", "arm 1")
        with Seed(body):
            rc, out = _run(listed)
        self.assertIn("Not a pass", out)
        self.assertIn("m.get_tile()", out)
        self.assertIn("a seeded row", out)
        # ...and it printed as a LISTED row, not as the unlisted failure.
        self.assertNotIn("_PortSeed.gd", _unlisted(out))
        self.assertEqual(rc, 0, out)

    def test_a_stale_row_is_RED(self):
        """The other direction. ⚠️ A stale row is what SUCCESS looks like here — the port
        deletes this whole population — so the arm must fire loudly and say so, rather
        than let a row outlive its debt."""
        seeded = dict(clp.PORT_BURN_DOWN)
        seeded[("src/units/Unit.gd", "map.no_such_member()")] = (
            "#0", "a row that names no site", "arm 1")
        rc, out = _run(seeded)
        self.assertIn("STALE PORT_BURN_DOWN", out)
        self.assertIn("no_such_member", out)
        self.assertNotIn("no_such_member", _unlisted(out))
        self.assertEqual(rc, 1, out)

    def test_the_seed_is_what_reddens_it_and_not_the_tree(self):
        """The control for every seed above: without the file the same call is green, and
        no seed leaked into `src/` or `tests/`."""
        for root in ("src", "tests"):
            self.assertFalse((PROJECT_DIR / root / "_PortSeed.gd").exists(),
                             "a seed test leaked its %s file" % root)
        rc, out = _run()
        self.assertNotIn("NOT ON PORT_BURN_DOWN", out)
        self.assertEqual(rc, 0, out)

    def test_the_arm1_split_reproduces_the_hand_count(self):
        """🔴 ADR-0192's whole argument for building this guard FIRST, stated as a number.

        ADR-0170 dec. 5 hand-counted 15 untyped receivers in `src/`; ADR-0192 dec. 2
        re-measured and split 27 = 15 + 12. Those are the only independent evidence that
        the receiver-type inference is right, and the port DELETES them. Asserting the
        numbers directly would expire on success, so this test asserts the SHAPE — the
        split is printed, and its parts sum — while `PORT_BURN_DOWN` carries the frozen
        hand count and the stale arm defends it."""
        rc, out = _run()
        line = [l for l in out.splitlines() if l.startswith("arm 1 (")][0]
        import re as _re
        n = [int(x) for x in _re.findall(r"\d+", line)]
        total, calls, untyped, typed, fetches, producers, _files = n[1:8]
        self.assertEqual(untyped + typed, calls)
        self.assertEqual(calls + fetches + producers, total)
        self.assertEqual(rc, 0, out)




if __name__ == "__main__":
    unittest.main()
