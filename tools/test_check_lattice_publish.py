"""Seed-red tests for the published-symbol register (ADR-0164 dec. 4 criterion 1,
amended and built by ADR-0196).

An arm that has never been seen to FIRE is indistinguishable from an arm that cannot
fire, and this family has now paid for that three times: `check_addon_portability.py`
shipped green across an entire extraction because it stopped looking, and BOTH
`check_lattice_ports` and `check_lattice_doors` had a `test_a_LISTED_row_prints_above_
the_verdict` go vacuous the day its burn-down emptied. So every seed below CONSTRUCTS
the site — and, where the arm is about a listed row, the row too. None of them reads a
row off the shipped list.

⚠️ THESE SEEDS WRITE INTO THE REAL TREE, so a `check_lattice_publish.py` run happening
CONCURRENTLY will see them and read one site too many — observed twice during this build,
both times a hand-run of the guard beside a running suite, and both times it looked exactly
like a real unlisted namer. Inside the suite it is harmless: `tests/run_all_tests.sh` runs
the pre-flight guards serially, and the one nested re-entry (`test_run_tests_parallel` runs
the whole pre-flight again as a subprocess) starts long after the outer lattice block has
finished. Do not read a register count taken while the suite is running.

Run from tools/:
    uv run python -m unittest test_check_lattice_publish
"""

from __future__ import annotations

import contextlib
import io
import os
import re
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

# CHDIR BEFORE THE IMPORT: the guard resolves `tools/touch_matrix.py` relative to the
# project dir to slice `strip_noncode` out of it.
os.chdir(PROJECT_DIR)

import check_lattice_publish as clp


def _run(burn_down=None, undeclared=None, declared=None):
    """Run `main()`, optionally over SEEDED literals.

    All three are patched the same way and for the same reason: an arm graded against
    the SHIPPED list is a control that expires the day the list empties, which this
    family has had to repair three times."""
    buf = io.StringIO()
    saved = (clp.PUBLISH_BURN_DOWN, clp.UNDECLARED_BURN_DOWN, clp.DECLARED_PUBLISHED)
    if burn_down is not None:
        clp.PUBLISH_BURN_DOWN = burn_down
    if undeclared is not None:
        clp.UNDECLARED_BURN_DOWN = undeclared
    if declared is not None:
        clp.DECLARED_PUBLISHED = declared
    try:
        with contextlib.redirect_stdout(buf):
            rc = clp.main()
    finally:
        (clp.PUBLISH_BURN_DOWN, clp.UNDECLARED_BURN_DOWN,
         clp.DECLARED_PUBLISHED) = saved
        os.chdir(PROJECT_DIR)
    return rc, buf.getvalue()


# An addon `class_name` that is NOT one of the forbidden six and that nothing outside the
# addon names today. Seeding it fires arm 3 and NOTHING ELSE, which is what makes the
# direction tests below say only what they claim. Pinned by
# `test_the_arm_3_probe_is_still_an_isolating_probe` — the day the probe gains a host namer
# or a `DECLARED_PUBLISHED` entry, every seed below goes vacuous silently.
# 🔴 THE PROBE IS SEEDED, NOT SHIPPED — ADR-0211 dec. 7. It was `Doodad`, one of the
# addon's thirty `class_name`s. The façade deleted twenty-nine of them, so there is no
# longer ANY addon `class_name` that is undeclared — arm 3's population is structurally
# empty and no shipped name can play the probe. That is the arm's success condition, not
# its death: a probe that must be CONSTRUCTED still direction-tests, and this file is the
# direction test dec. 7 makes arm 3's survival conditional on. Every seed below now writes
# the addon-side `class_name` as well as the host-side namer, so the pair asserts exactly
# what arm 3 claims — a host may not compile against a name the addon never published.
ARM3_PROBE = "_PublishProbe"
ARM3_PROBE_REL = "addons/exmateria_battlefield/_publish_probe.gd"
ARM3_PROBE_BODY = "class_name %s\nextends Node\n" % ARM3_PROBE


class SeedFile:
    """A namer written into the REAL tree, at a REAL scan root.

    A scratch package would prove the code path, which is not the claim: the claim is
    that the register, over THIS repo with THIS stripper, scores the seeded line as a
    type reference to an addon `class_name`. Removed in `__exit__` whether or not the
    body raised."""

    def __init__(self, rel: str, body: str):
        self.path = PROJECT_DIR / rel
        self.body = body

    def __enter__(self):
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        self.path.write_text(self.body, encoding="utf-8")
        return self.path

    def __exit__(self, *exc):
        self.path.unlink(missing_ok=True)
        return False


def seeded_addon_class():
    """The addon-side half of every arm-3 seed: a `class_name` inside the addon that
    `DECLARED_PUBLISHED` does not name. Since ADR-0211 the shipped tree has none, so
    the seed constructs one rather than borrowing a name that could be published,
    forbidden or reached out from under it."""
    return SeedFile(ARM3_PROBE_REL, ARM3_PROBE_BODY)


class BothDirectionsFail(unittest.TestCase):

    def test_an_unlisted_namer_is_RED(self):
        body = "extends Node\n\n\nvar _seeded: CursorController = null\n"
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertIn("PUBLISHED SYMBOL:", out)
        self.assertIn("_publish_seed.gd", out)
        self.assertEqual(rc, 1, out)


    def test_a_stale_row_is_RED(self):
        seeded = dict(clp.PUBLISH_BURN_DOWN)
        seeded[("src/_publish_seed.gd", "MapComposer")] = (
            "#0", "a row that names no type reference")
        rc, out = _run(seeded)
        self.assertIn("STALE PUBLISH_BURN_DOWN", out)
        self.assertIn("MapComposer", out)
        self.assertEqual(rc, 1, out)

    def test_a_row_whose_LAST_site_went_away_is_STALE(self):
        """The shape a CLOSED row actually has. `test_a_stale_row_is_RED` names a file
        that does not exist; closing a row keeps the file and removes the TYPE — which
        is exactly what commit 2 does to `Tile`'s ten sites, leaving the files in place
        and full of `CellMarking.Kind`. A scanner that asked \"does this file exist?\"
        would keep the row alive forever."""
        body = ("extends Node\n\n\nvar _seeded: CursorController = null\n"
                "var _kept := CellMarking.Kind.NONE\n")
        seeded = dict(clp.PUBLISH_BURN_DOWN)
        seeded[("src/_publish_seed.gd", "CursorController")] = ("#0", "the seeded row")
        seeded[("src/_publish_seed.gd", "Tile")] = ("#0", "a row whose type reference is gone")
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run(seeded)
        self.assertIn("STALE PUBLISH_BURN_DOWN", out)
        self.assertIn("`Tile`", out.split("STALE PUBLISH_BURN_DOWN", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_the_seed_is_what_reddens_it_and_not_the_tree(self):
        """The control for the seeds above: the seed did not leak."""
        self.assertFalse((PROJECT_DIR / "src" / "_publish_seed.gd").exists(),
                         "a seed test leaked its src file")
        self.assertFalse((PROJECT_DIR / "tests" / "_PublishSeed.gd").exists(),
                         "a seed test leaked its tests file")
        self.assertFalse((PROJECT_DIR / "tools" / "_publish_seed.gd").exists(),
                         "a seed test leaked its tools file")


class TheShippedRegister(unittest.TestCase):

    def test_the_shipped_rows_are_live_and_none_is_stale(self):
        rc, out = _run()
        self.assertNotIn("STALE PUBLISH_BURN_DOWN", out)
        self.assertNotIn("PUBLISHED SYMBOL:", out)
        self.assertEqual(rc, 0, out)

    def test_a_LISTED_row_prints_above_the_verdict(self):
        """A listed row must PRINT, under a heading that says it is not a pass.

        🔴 SEEDED, NOT READ OFF THE SHIPPED LIST. A control that depends on the debt it
        controls for expires on success, and this family has produced three of them —
        `check_lattice_ports` and `check_lattice_doors` both had to repair this exact
        test. It constructs the SITE and the ROW, so it says the same thing when the
        register reaches zero."""
        body = "extends Node\n\n\nvar _seeded: CursorController = null\n"
        listed = dict(clp.PUBLISH_BURN_DOWN)
        listed[("src/_publish_seed.gd", "CursorController")] = (
            "#0", "a seeded row, so the printing property has something to print")
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run(listed)
        self.assertIn("PUBLISHED-SYMBOL REGISTER", out)
        self.assertIn("Not a pass", out)
        self.assertIn("a seeded row", out)
        self.assertNotIn("PUBLISHED SYMBOL:", out)
        self.assertEqual(rc, 0, out)


class ArmTwoReports(unittest.TestCase):

    def test_a_tests_namer_REPORTS_and_does_not_fail(self):
        """ADR-0196 dec. 3, on ADR-0170 dec. 5's precedent: `classify()` returns `None`
        for every test file, so a threshold there is guesswork. The site must PRINT —
        arm 1 at zero while `tests/` holds dozens of `Array[Tile]` reads as coverage,
        and that is the failure dec. 3 names."""
        body = "extends Node\n\n\nvar _seeded: CursorController = null\n"
        with SeedFile("tests/_PublishSeed.gd", body):
            rc, out = _run()
        self.assertIn("ARM 2", out)
        self.assertIn("_PublishSeed.gd", out)
        self.assertEqual(rc, 0, out)


class ScannerRegressions(unittest.TestCase):

    def test_a_node_path_is_not_a_type_reference(self):
        """ADR-0196 dec. 2, and the cheapest falsifier this register has. All eight of
        `PlayerCamera`'s code lines in `src/` are `$PlayerCamera`; if the scan scores
        them, the rule is not implemented."""
        body = ('extends Node\n\n\n@onready var _a: Node = $PlayerCamera\n'
                '@onready var _b: Node = get_node_or_null("PlayerCamera")\n'
                '@onready var _c: Node = %PlayerCamera\n'
                'var _d := $PlayerCamera/FocusPoint/Camera\n')
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertNotIn("_publish_seed.gd", out)
        self.assertEqual(rc, 0, out)

    def test_an_annotation_SHARING_its_line_with_a_node_path_still_counts_once(self):
        """🔴 THE DEFECT THE HAND COUNT ACTUALLY HAD. ADR-0196's reading (a) put
        `TileCursor` at 9; the tree holds 12. The three it missed are
        `EffectViewerScene.gd:27`, `FireCastReproScene.gd:45` and `GPUArena.gd:41`, each
        `@onready var tile_cursor: TileCursor = $TileCursor` or the
        `get_node_or_null(\"TileCursor\")` spelling — a real type ANNOTATION sharing its
        line with a node path. Dec. 2 excludes the node-path OCCURRENCE; excluding the
        LINE drops a compiled symbol reference, which is criterion 1's entire subject.

        Once, not twice: the node path on the same line must not double it."""
        body = ('extends Node\n\n\n'
                '@onready var _a: TileCursor = $TileCursor\n'
                '@onready var _b: TileCursor = get_node_or_null("TileCursor")\n')
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertIn("`TileCursor` x2", out)
        self.assertEqual(rc, 1, out)

    def test_a_trailing_comment_and_a_docstring_body_are_not_type_references(self):
        """The `strip_noncode` family this repo has been bitten by before. Five lines in
        the shipped tree are exactly these shapes — `BaseDebugPanel.gd:30` and
        `GPUCombatPacker.gd:54` carry `Tile` in a TRAILING comment, and `Unit.gd:1677-80`
        carry it in a `\"\"\"` docstring body. A stripper that drops only lines whose FIRST
        non-whitespace is `#` keeps all five and reads `Tile` as 15."""
        body = ('extends Node\n\n\n'
                'var _x := 1  # Tile-cursor blend, see CursorController\n'
                '# MapComposer is named here in a whole-line comment\n'
                'func f() -> void:\n'
                '\t"""A docstring body naming Tile and TerrainIndex."""\n'
                '\tvar _s := "PlayerCamera"\n')
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertNotIn("_publish_seed.gd", out)
        self.assertEqual(rc, 0, out)

    def test_a_namer_under_tools_is_ENFORCED_too(self):
        """🔴 THE ROOT NEITHER SIBLING SCANS. `check_lattice_doors` and
        `check_lattice_ports` both stop at `src`/`tests`/`assets`/`addons`; `tools/`
        holds 94 `.gd` capture and debug scenes, which are host code. It reads 0 there
        today — which is what makes an unscanned root dangerous rather than harmless,
        because 0 is also what a scan that never looks reports."""
        body = "extends Node\n\n\nvar _seeded: TileCursor = null\n"
        with SeedFile("tools/_publish_seed.gd", body):
            rc, out = _run()
        self.assertIn("PUBLISHED SYMBOL:", out)
        self.assertIn("tools/_publish_seed.gd", out)
        self.assertEqual(rc, 1, out)

    def test_a_hash_INSIDE_a_string_literal_does_not_eat_the_code_after_it(self):
        """🔴 A LIVE UNDER-COUNT, found by auditing this guard's own blind-spot list.

        `strip_noncode` strips comments BEFORE it blanks string literals, so a `#` that
        is not a comment at all truncates the line. `src/debug/CursorDebugPanel.gd:85` —
        `print("# outline blend mode …: %s" % TileCursor.SEMI_MODE_LABELS[bm])` — is a
        real static read of `TileCursor` that the first scanner dropped, and it took
        `TileCursor` from 13 to 12.

        Both halves are seeded, because the fix has to be exact: the reference AFTER the
        closing quote counts, and the name INSIDE the literal still does not."""
        body = ('extends Node\n\n\nfunc f(x: int) -> void:\n'
                '\tprint("# a label: %s" % TileCursor.SEMI_MODE_LABELS[x])\n'
                '\tprint("# paste into CursorController.gd defaults:")\n')
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertIn("`TileCursor` x1", out)
        self.assertNotIn("CursorController", out.split("_publish_seed.gd")[1][:40])
        self.assertEqual(rc, 1, out)

    def test_a_longer_name_is_not_its_prefix(self):
        """The control that proves the scan turns on the SYMBOL. `TileCursor`,
        `TileCursorCompositor` and `TileHighlights` all start with `Tile`, and only the
        first is forbidden.

        🔴 THE SECOND NAME CHANGED WHEN ARM 3 LANDED, and the reason is worth the line.
        This test used `TileCursorBob`, which is an addon `class_name` that
        `DECLARED_PUBLISHED` does not name — so under arm 3 the seed is a REAL defect and
        `rc == 0` became false. The claim being made here is about the word boundary, not
        about publication, so the seed moved to two names that are both DECLARED and still
        both share a forbidden prefix (`Tile` and `TileCursor`). Relaxing the `rc` instead
        would have turned the arm-3 signal off inside a test named for something else."""
        body = ("extends Node\n\n\nvar _a: TileHighlights = null\n"
                "var _b: TileCursorCompositor = null\n")
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertNotIn("_publish_seed.gd", out)
        self.assertEqual(rc, 0, out)


class ArmThreeBothDirectionsFail(unittest.TestCase):
    """ADR-0208 dec. 2's second half, built by #713.

    Dec. 2 rules that a criterion-4 path row is paid by deleting the dependency, by
    host-owned indirection, or by naming a name the addon PUBLISHES — never by
    re-spelling an unpublished one. Arm 3 is that second half. Every seed here
    CONSTRUCTS the namer, and the two that need a listed row construct the row too."""

    def test_the_arm_3_probe_is_still_an_isolating_probe(self):
        """🔴 THE CONTROL FOR EVERY SEED BELOW. They all claim to fire arm 3 ALONE. That
        is only true while the probe is an addon `class_name` that is neither forbidden
        nor declared nor already named from outside — and any of those can change without
        touching this file, leaving the seeds passing for the wrong reason.

        🔴 IT NOW ASSERTS BOTH HALVES, because since ADR-0211 the probe is CONSTRUCTED.
        Absent the seed the name must not exist at all (a leak from a crashed run would
        make every seed below pass without seeding anything); with the seed it must be a
        live addon `class_name`. The old form asserted only the second half against a
        shipped name, and the day the façade landed it failed — correctly, and that
        failure is what dec. 7's direction test was asking for.

        🔴 THE REFRESH IS LOAD-BEARING AND THIS TEST FOUND OUT THE HARD WAY. `corpus()`
        caches, and `main()` refreshes it ON ENTRY — so after any seeded `_run` the cache
        holds the tree INCLUDING a seed file that has since been deleted. Read without
        the refresh, `named_set()` reported the probe as already having a host namer and
        this control failed against a tree that does not exist. Every other reader in
        this file goes through `main()`; this one does not."""
        clp.corpus(refresh=True)
        self.assertNotIn(ARM3_PROBE, clp.addon_class_names(),
                         "the probe LEAKED into the tree — a previous run did not clean "
                         "up, and every seed below would pass without seeding")
        with seeded_addon_class():
            clp.corpus(refresh=True)
            self.assertIn(ARM3_PROBE, clp.addon_class_names(),
                          "seeding the addon file did not make the probe a `class_name`")
            self.assertNotIn(ARM3_PROBE, clp.FORBIDDEN,
                             "the probe became forbidden; a seed would fire arm 1 too")
            self.assertNotIn(ARM3_PROBE, clp.DECLARED_PUBLISHED,
                             "the probe was published; a seed can no longer fire arm 3")
            self.assertNotIn(ARM3_PROBE, clp.named_set(),
                             "the probe gained a host namer; the seeds no longer isolate it")
        clp.corpus(refresh=True)

    def test_an_UNLISTED_undeclared_namer_is_RED(self):
        """The direction #713 exists for: a host writes a bare name the addon never
        published, and before this arm all five registers stayed green."""
        body = "extends Node\n\n\nvar _seeded: %s = null\n" % ARM3_PROBE
        with seeded_addon_class(), SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertIn("UNDECLARED NAME:", out)
        self.assertIn(ARM3_PROBE, out.split("UNDECLARED NAME:", 1)[1])
        self.assertIn("_publish_seed.gd", out.split("UNDECLARED NAME:", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_a_namer_under_tests_is_ENFORCED_by_arm_3(self):
        """🔴 THE ROOT ARMS 1 AND 2 SPLIT OFF, AND ARM 3 DELIBERATELY DOES NOT. Arm 1
        stops at `tests/` and arm 2 scores nothing there, so before this arm a `tests/`
        file was a place the rule could be satisfied by writing the reach where nothing
        enforcing looks. Criterion 4 has rows in `tests/` today — a path row there paid
        by re-spelling it as a bare name is exactly dec. 2's forbidden move."""
        body = "extends Node\n\n\nvar _seeded: %s = null\n" % ARM3_PROBE
        with seeded_addon_class(), SeedFile("tests/_PublishSeed.gd", body):
            rc, out = _run()
        self.assertIn("UNDECLARED NAME:", out)
        self.assertIn("_PublishSeed.gd", out.split("UNDECLARED NAME:", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_a_LISTED_row_prints_above_the_verdict_and_passes(self):
        """Seeded, not read off the shipped list — the failure this family has repaired
        three times. It says the same thing when `UNDECLARED_BURN_DOWN` reaches zero."""
        body = "extends Node\n\n\nvar _seeded: %s = null\n" % ARM3_PROBE
        listed = dict(clp.UNDECLARED_BURN_DOWN)
        listed[ARM3_PROBE] = ("#0", "a seeded row, so the printing property has something")
        with seeded_addon_class(), SeedFile("src/_publish_seed.gd", body):
            rc, out = _run(undeclared=listed)
        self.assertIn("UNDECLARED-NAME REGISTER", out)
        self.assertIn("Not a pass", out.split("UNDECLARED-NAME REGISTER", 1)[1])
        self.assertIn("a seeded row", out)
        self.assertIn("_publish_seed.gd", out)          # the row must be FINDABLE
        self.assertNotIn("UNDECLARED NAME:", out)
        self.assertEqual(rc, 0, out)

    def test_a_row_whose_LAST_NAMER_went_away_is_STALE(self):
        """Closure route one: the host reach is deleted. No seed file at all."""
        listed = dict(clp.UNDECLARED_BURN_DOWN)
        listed[ARM3_PROBE] = ("#0", "a row that names nothing")
        with seeded_addon_class():
            rc, out = _run(undeclared=listed)
        self.assertIn("STALE UNDECLARED_BURN_DOWN", out)
        self.assertIn(ARM3_PROBE, out.split("STALE UNDECLARED_BURN_DOWN", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_a_row_whose_NAME_GOT_DECLARED_is_STALE(self):
        """🔴 CLOSURE ROUTE TWO, AND THE ONE THAT IS ALSO A HOLE. A row drains when the
        name joins `DECLARED_PUBLISHED` — the namer is untouched and the reach is still
        there, it is simply now a reach the addon invited. That is a legitimate payment
        under dec. 2 and it is gated one level up by ADR-0208 dec. 6 (state the host use
        above the entry; never in the commit that closes the row). Pinned here because a
        scanner that only recognised route one would keep the row alive forever and
        teach the next reader that publishing is not a closure."""
        body = "extends Node\n\n\nvar _seeded: %s = null\n" % ARM3_PROBE
        listed = dict(clp.UNDECLARED_BURN_DOWN)
        listed[ARM3_PROBE] = ("#0", "a row whose name has since been published")
        with seeded_addon_class(), SeedFile("src/_publish_seed.gd", body):
            rc, out = _run(undeclared=listed,
                           declared=clp.DECLARED_PUBLISHED + (ARM3_PROBE,))
        self.assertIn("STALE UNDECLARED_BURN_DOWN", out)
        self.assertIn(ARM3_PROBE, out.split("STALE UNDECLARED_BURN_DOWN", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_a_DECLARED_name_named_from_outside_is_NOT_an_arm_3_row(self):
        """The negative control. Arm 3 must turn on PUBLICATION, not on the reach — or
        it would red every legitimate use of the addon's own published surface, which is
        ADR-0196 dec. 4's stated backwardness one direction over."""
        self.assertIn("ExMateriaBattlefield", clp.DECLARED_PUBLISHED)
        body = "extends Node\n\n\nvar _a: ExMateriaBattlefield = null\n"
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertNotIn("UNDECLARED NAME:", out)
        self.assertEqual(rc, 0, out)

    def test_a_node_path_to_an_undeclared_name_is_not_a_reach(self):
        """Arm 3 inherits `_type_ref`, so ADR-0196 dec. 2 holds here too: `$Doodad` is a
        scene-tree coupling. It is criterion 4's subject and `check_lattice_scene.py`
        scores it. Folding it in would make one number answer two questions."""
        body = ('extends Node\n\n\n@onready var _a: Node = $%s\n'
                '@onready var _b: Node = get_node_or_null("%s")\n' % (ARM3_PROBE, ARM3_PROBE))
        with seeded_addon_class(), SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertNotIn("UNDECLARED NAME:", out)
        self.assertEqual(rc, 0, out)


class TheDeclaredSet(unittest.TestCase):

    def test_the_declared_set_report_is_a_SUPERSET_check_and_never_fails(self):
        """ADR-0196 dec. 4's reported half. A declared-but-unnamed name is not a defect
        — enforcing that direction would make DELETING a host call site red the guard,
        which is backwards. The report must print both directions and change no rc."""
        body = "extends Node\n\n\nvar _a: ExMateriaBattlefield = null\n"
        with SeedFile("src/_publish_seed.gd", body):
            rc, out = _run()
        self.assertIn("DECLARED PUBLISHED SET", out)
        self.assertNotIn("_publish_seed.gd", out.split("DECLARED PUBLISHED SET")[0])
        self.assertEqual(rc, 0, out)

    def test_every_arm_3_row_is_a_real_addon_class_name(self):
        """The same rot `test_every_declared_name_is_a_real_addon_class_name` catches,
        one list over. A burn-down row naming something the addon no longer declares can
        never go stale by being fixed — it is stale the moment it is written, and the
        STALE arm would report it as a success."""
        self.assertEqual(
            sorted(set(clp.UNDECLARED_BURN_DOWN) - clp.addon_class_names()), [])

    def test_every_declared_name_is_a_real_addon_class_name(self):
        """A declared set that names something the addon does not declare is a literal
        nobody rereads — the README's count has already been stale twice (ADR-0196
        dec. 4). The guard's own literal must not repeat that."""
        self.assertEqual(sorted(set(clp.DECLARED_PUBLISHED) - clp.addon_class_names()),
                         [])

    def test_every_declared_name_states_a_host_use(self):
        """ADR-0208 dec. 6, the gate on the list itself. A published name is a legitimate
        payment for a criterion-4 path row (dec. 2), so ADDING to this tuple can drain a
        burn-down row — the same hole one level up. The prose half of the gate (state the
        host use; never in the commit that closes the row) is a discipline no scanner can
        read. The half that IS mechanizable is presence: every entry carries a comment
        immediately above it. A silent addition then cannot look like the others.

        This is deliberately STRUCTURAL and not semantic. It cannot tell a true host use
        from a false one; it can only tell that somebody was made to write a sentence.
        `TileCursorCompositor`'s entry says it has NO host namer today — that is a stated
        use and passes, which is the point: the arm requires an answer, not a yes."""
        src = (Path(clp.__file__).read_text().split("DECLARED_PUBLISHED = (")[1]
               .split("\n)")[0].splitlines())
        undocumented, prev_is_comment = [], False
        for line in src:
            stripped = line.strip()
            if stripped.startswith('"'):
                if not prev_is_comment:
                    undocumented.append(stripped.strip('",'))
            if stripped:
                prev_is_comment = stripped.startswith("#")
        self.assertEqual(undocumented, [],
                         "declared with no stated host use above the entry (ADR-0208 dec. 6)")
        # The arm is worthless if it cannot COUNT — a block that parsed to nothing would
        # also report zero undocumented. Pin that it saw every name.
        seen = [l.strip().strip('",') for l in src if l.strip().startswith('"')]
        self.assertEqual(sorted(seen), sorted(clp.DECLARED_PUBLISHED))

class TheCitedHostFiles(unittest.TestCase):
    """ADR-0210 dec. 1 — the half of ADR-0208 dec. 6 its own docstring called
    unmechanizable, mechanized as far as it actually goes.

    `test_every_declared_name_states_a_host_use` requires that somebody wrote a
    sentence. It cannot read the sentence, and `Lattice`'s entry is the proof: it named
    ONE debug panel while the GPU pipeline, the scenario VM, strategy placement and
    `Unit` compiled against the name across 22 `src/` files and 50 references. Twenty
    times understated, and every arm green.

    A sentence cannot be graded. A CITATION can — it is a claim about the tree, and it
    rots the two ways a claim about the tree always rots: the file moves, or the last
    call site is deleted. Both arms below are green on this tree, so each is a ratchet
    that can only ever go red on rot.

    🔴 THIS DOES MAKE DELETING THE LAST HOST CALL SITE RED THE ARM, which is the
    direction ADR-0196 dec. 4 called backwards for the declared-set REPORT. It is not
    the same direction. Dec. 4's inversion was that deleting a coupling would make the
    name itself a defect; here the name stays declared and the remedy is to re-read the
    comment — exactly what `TileCursorCompositor` did when ADR-0200 took its last host
    namer away, and its `⚠️ NO HOST NAMER TODAY` entry passes both arms today because
    the prose still names the symbol. The arm demands a current sentence, not a
    restored call."""

    # 🔴 THE PREDICATES LIVE HERE AND BOTH THE LIVE ARM AND ITS SEED CALL THEM. A seed
    # that merely re-states the condition it seeded ("the file is absent") proves the
    # TREE, never the arm — this repo has shipped that shape and watched a broken guard
    # pass with the seed green beside it. Each seed below runs the same function the
    # live arm runs and asserts it returns the row.

    @staticmethod
    def _moved(cites):
        """Rot one: the cited file is gone."""
        return [(n, f) for n, f in cites if not (PROJECT_DIR / f).is_file()]

    @staticmethod
    def _silent(cites):
        """Rot two: the file is there and no longer names the symbol."""
        out = []
        for name, f in cites:
            q = PROJECT_DIR / f
            if q.is_file() and not re.search(rf"\b{re.escape(name)}\b",
                                             q.read_text(errors="ignore")):
                out.append((name, f))
        return out

    @staticmethod
    def _flatten(citations):
        return [(n, f) for n, fs in citations.items() for f in fs]

    def _cites(self):
        cited = self._flatten(clp.declared_citations())
        # An arm that parsed nothing reports zero failures. Pin that it SAW the list.
        # An arm that parsed nothing reports zero failures, so pin that it SAW the
        # list. The floor is the LIST'S OWN LENGTH, not a magic number: ADR-0208 dec. 6
        # requires every entry to state a host use, so every declared name must yield at
        # least one citation. The old floor of 10 was tied to an eleven-name list and
        # went red — not vacuous, just wrong — when ADR-0211 collapsed it to one.
        self.assertGreaterEqual(
            len(cited), len(clp.DECLARED_PUBLISHED),
            "the citation parse collapsed — %d name(s) declared, %d citation(s)"
            % (len(clp.DECLARED_PUBLISHED), len(cited)))
        return cited

    def test_every_cited_host_file_exists(self):
        self.assertEqual(self._moved(self._cites()), [],
                         "a declared name cites a host file that has MOVED or been "
                         "deleted (ADR-0210 dec. 1)")

    def test_every_cited_host_file_names_its_symbol(self):
        self.assertEqual(self._silent(self._cites()), [],
                         "a declared name cites a host file that no longer names it — "
                         "re-read the comment (ADR-0210 dec. 1)")

    def test_a_MOVED_host_file_reds_the_exists_arm(self):
        """Seed, not a shipped row (this file's header). Construct the entry."""
        seeded = clp.declared_citations(
            'DECLARED_PUBLISHED = (\n'
            '    # Host use: `src/gone/NoSuchPanel.gd` holds one.\n'
            '    "Seeded",\n)\n')
        self.assertEqual(seeded, {"Seeded": ["src/gone/NoSuchPanel.gd"]})
        # Drive the ARM, not the tree.
        self.assertEqual(self._moved(self._flatten(seeded)),
                         [("Seeded", "src/gone/NoSuchPanel.gd")])
        # ...and the OTHER arm must stay quiet: an absent file is one rot, not both.
        self.assertEqual(self._silent(self._flatten(seeded)), [])

    def test_a_citation_whose_file_no_longer_NAMES_the_symbol_reds(self):
        """The second rot: the file is still there and the coupling is gone. Seeded
        against a real host file that genuinely does not name the seeded symbol."""
        seeded = clp.declared_citations(
            'DECLARED_PUBLISHED = (\n'
            '    # Host use: `src/gpu/CombatHost.gd` holds one.\n'
            '    "ZzzNotASymbolAnywhere",\n)\n')
        self.assertEqual(seeded["ZzzNotASymbolAnywhere"], ["src/gpu/CombatHost.gd"])
        self.assertEqual(self._silent(self._flatten(seeded)),
                         [("ZzzNotASymbolAnywhere", "src/gpu/CombatHost.gd")])
        # The exists arm must NOT fire — the file is present. Two rots, two arms.
        self.assertEqual(self._moved(self._flatten(seeded)), [])

    def test_a_class_or_method_citation_is_NOT_scored(self):
        """The stated blind spot, pinned so it cannot be widened by accident. Path-shaped
        prose naming a method is house style (the illumination entry's, before ADR-0211
        folded it onto the façade) and scoring
        it would red a correct comment."""
        seeded = clp.declared_citations(
            'DECLARED_PUBLISHED = (\n'
            '    # Host use: `src/effects/PaletteSubsystem.build_illumination()` returns one.\n'
            '    "Seeded",\n)\n')
        self.assertEqual(seeded, {"Seeded": []})
        self.assertEqual(self._moved(self._flatten(seeded)), [])


class TheSlicedStripperIsCompiledOnce(unittest.TestCase):
    r"""`touch_matrix.strip_noncode` compiles its two patterns ON THE `def` LINE.

    THE COST IT REMOVES. This guard calls the stripper once per `.gd` file and the
    uncompiled `re.sub(r'…', …)` form went through `re._compile` twice per LINE —
    1,268,120 lookups in one run, 79% of it by `tottime`. Compiling on the `def` line
    took this module from 10.5 s to 7.0 s. That is worth 3x its face value: the
    pre-flight block runs THREE times per invocation, once directly and twice more
    inside `test_run_tests_parallel.SequentialArmIsGated`, which re-runs the whole
    script as a subprocess.

    🔴 WHY NOT MODULE-LEVEL CONSTANTS, WHICH IS THE OBVIOUS FIX. Five modules do not
    import this function — they lift it by SOURCE SLICE (`^def strip_noncode\(` …
    `(?=^\S)`) and exec the slice in a namespace holding only `re`, because importing
    `touch_matrix` runs its whole cross-system walk and cost `check_lattice_doors` 73 s
    of its 85 s. A module-level `_COMMENT = re.compile(...)` is NOT part of that slice,
    so every one of the five would NameError on its first call. Arm 1 is that
    direction, and it is the reason this class exists rather than a comment.
    """

    SLICE_RE = r'^def strip_noncode\(.*?(?=^\S)'
    # Comments, a docstring, a literal, and a `#` INSIDE a literal — the last is the
    # hazard `check_lattice_publish._code_lines` exists to work around, so identity
    # has to be asserted over text that contains it.
    FIXTURE = (
        'extends Node  # a trailing comment\n'
        '"""\n'
        'a docstring naming TileCursor\n'
        '"""\n'
        'const P := "res://assets/thing.tres"\n'
        'print("# not a comment") ; var keep := 1\n'
        '## a doc comment\n'
        'var plain := 2\n')

    def _slice(self):
        src = (PROJECT_DIR / "tools" / "touch_matrix.py").read_text()
        fn = re.search(self.SLICE_RE, src, re.S | re.M)
        self.assertIsNotNone(fn, "touch_matrix.py no longer defines strip_noncode")
        return fn.group(0)

    def test_the_slice_execs_in_a_namespace_holding_only_re(self):
        """Arm 1 — the direction a module-level constant breaks.

        This is exactly what all five consumers do. If the patterns are hoisted out of
        the signature the exec still SUCCEEDS and the failure lands on the first call,
        which is why this arm calls it rather than only exec'ing it."""
        ns = {"re": re}
        exec(self._slice(), ns)
        self.assertEqual(ns["strip_noncode"]("var x := 1  # gone"), ["var x := 1  "])

    def test_it_is_byte_identical_to_the_uncompiled_form(self):
        """Arm 2 — the patterns did not change while being compiled.

        The reference is the pre-change body, spelled out here rather than sliced, so
        an edit to BOTH forms cannot make this arm agree with itself."""
        def reference(txt):
            out, indoc = [], False
            for ln in txt.splitlines():
                s = ln
                if '"""' in s:
                    n = s.count('"""')
                    if not indoc:
                        s = s.split('"""')[0]
                        if n == 1:
                            indoc = True
                    else:
                        if n >= 1:
                            indoc = False
                            s = s.split('"""')[-1]
                        else:
                            s = ""
                elif indoc:
                    s = ""
                s = re.sub(r'#.*$', '', s)
                s = re.sub(r'"[^"]*"', '""', s)
                out.append(s)
            return out

        ns = {"re": re}
        exec(self._slice(), ns)
        self.assertEqual(ns["strip_noncode"](self.FIXTURE), reference(self.FIXTURE))
        # …and the fixture is not vacuous: the reference must actually STRIP something.
        self.assertNotEqual(reference(self.FIXTURE), self.FIXTURE.splitlines())

    def test_no_pattern_is_compiled_per_LINE(self):
        """Arm 3 — the anti-regression arm, and the only one that fires on a revert.

        Arms 1 and 2 both stay GREEN against `re.sub(r'…', …)`: it slices fine and it
        is the reference. So neither can see the defect this change removes. Counting
        the module-level `re.sub` calls can — the compiled form makes ZERO of them, and
        the uncompiled form makes two per line."""
        ns = {"re": re}
        exec(self._slice(), ns)
        text = "var x := 1  # c\n" * 200
        calls = []
        real_sub = re.sub
        re.sub = lambda *a, **k: (calls.append(1), real_sub(*a, **k))[1]
        try:
            got = ns["strip_noncode"](text)
        finally:
            re.sub = real_sub
        self.assertEqual(len(got), 200, "the stripper stopped preserving the line count")
        self.assertEqual(calls, [],
                         "strip_noncode is calling the module-level re.sub again — %d "
                         "times over 200 lines. The patterns must stay compiled on the "
                         "`def` line." % len(calls))
        # The counter is real: the same 200 lines through the uncompiled form trips it.
        control = []
        re.sub = lambda *a, **k: (control.append(1), real_sub(*a, **k))[1]
        try:
            for ln in text.splitlines():
                re.sub(r'#.*$', '', ln)
        finally:
            re.sub = real_sub
        self.assertEqual(len(control), 200, "the call counter cannot see re.sub at all")


class TheCLevelRejectIsNotABlindSpot(unittest.TestCase):
    r"""The `any(n in text ...)` gate `named_types` and `named_sites` reject files with.

    THE COST IT REMOVES. `_code_lines` was called 2,118 times per `main()` over a
    1,492-file corpus — once per file in `scan()` (gated), once per `src/` file, and
    once per file for the whole-corpus walk (both ungated). Only 154 files contain a
    forbidden name and only 64 contain an addon `class_name` at all, so the register was
    stripping ~1,900 files a run to prove they said nothing. The gate took `main()` from
    0.346 s to 0.113 s and this module from 7.20 s to 2.44 s, x3 in the pre-flight.

    🔴 A REJECT IS A BLIND SPOT THE DAY ITS PREMISE STOPS HOLDING, and the premise lives
    in a FILE THIS ONE DOES NOT OWN. It is that stripping cannot INVENT a name: every
    transform in `touch_matrix.strip_noncode` yields a prefix, a suffix or an empty
    line, and the literal blank is `"[^"]*" -> ""`, which KEEPS BOTH QUOTES. Change that
    one substitution to delete the run instead and `Ti"x"le` becomes `Tile` — a name the
    raw text never held, in a file the gate has already thrown away. Every seed in this
    module writes the name it seeds, so all twenty of them stay GREEN through that
    change. This class is the only arm that would not.
    """

    # `Ti"x"le` is the whole point: a deleting stripper forges `Tile` out of it, a
    # blanking one cannot. The rest are the other three shapes a name can hide in.
    HAZARDS = ('var a: Ti"x"le = null\n'
               'print("# not a comment") ; var b: PlayerCamera = null\n'
               '"""\n'
               'a docstring naming MapComposer\n'
               '"""\n'
               'var c := 1  # CursorController in a comment\n')

    def _names(self):
        return sorted(set(clp.FORBIDDEN) | clp.addon_class_names())

    def test_stripping_never_introduces_a_name(self):
        """Arm 1 — the premise, and the arm that fires on the substitution above."""
        stripped = " ".join(clp._code_lines(self.HAZARDS))
        forged = [n for n in self._names()
                  if n in stripped and n not in self.HAZARDS]
        self.assertEqual(forged, [], "stripping INVENTED %s — the raw text does not "
                                     "contain it, so the C-level reject in "
                                     "`named_types` / `named_sites` would throw the "
                                     "file away before the scan could see it. The gate "
                                     "is now a blind spot; see `_code_lines`." % forged)

        # The control: the arm CAN see a forged name. A stripper that deletes the
        # literal instead of blanking it is the one-character change described above.
        def deleting(txt):
            return [re.sub(r'"[^"]*"', '', re.sub(r'#.*$', '', ln))
                    for ln in txt.splitlines()]
        self.assertNotIn("Tile", self.HAZARDS, "the fixture stopped being a hazard")
        self.assertIn("Tile", " ".join(deleting(self.HAZARDS)),
                      "the control cannot forge a name, so arm 1 proves nothing")

    def test_the_reject_drops_the_blind_and_never_a_real_namer(self):
        """Arm 2 — the gate is in the live path, it FIRES, and a real site survives it.

        Both halves matter and neither implies the other. A gate that rejected nothing
        would pass the second assertion while removing no cost; a gate that rejected
        everything would pass the first while disarming all three arms."""
        body = "extends Node\n\n\nvar _seeded: %s = null\n" % ARM3_PROBE
        seen, real = [], clp._code_lines
        clp._code_lines = lambda t: (seen.append(t), real(t))[1]
        try:
            with seeded_addon_class(), SeedFile("src/_publish_reject_seed.gd", body):
                rc, out = _run()
        finally:
            clp._code_lines = real

        self.assertEqual(rc, 1, out)
        self.assertIn("_publish_reject_seed.gd",
                      out.split("UNDECLARED NAME:", 1)[1])
        self.assertIn(body, seen,
                      "the reject threw the seeded namer away BEFORE stripping it — it "
                      "was still reported, so only this counter can see the miss")
        # …and it is rejecting: the corpus is stripped far fewer times than it is walked.
        self.assertLess(len(seen), len(clp.corpus()),
                        "the reject let every file through (%d strips over %d files) — "
                        "it costs what it used to and arm 1 guards nothing"
                        % (len(seen), len(clp.corpus())))


if __name__ == "__main__":
    unittest.main()
