"""Seed-red tests for the addon-globals register (ADR-0212 dec. 6).

An arm that has never been seen to FIRE is indistinguishable from an arm that
cannot fire, and this family has paid for that repeatedly — `check_addon_
portability.py` shipped green across an entire extraction because it stopped
looking, and two sibling registers had a listed-row test go vacuous the day
their burn-down emptied.

So every seed below CONSTRUCTS the condition, and none of them reads a name off
the shipped list. The ones that grade a burn-down patch it with FABRICATED
names, because an arm graded against the shipped set expires the day the
migration finishes — which is the whole point of the migration.

🔴 THE ARMS RUN OVER FOUR ADDONS NOW, SO THE SEEDS DO TOO. ADR-0212 dec. 6
widened `ADDON`/`FACADE` back into the `FACADES` dict the guard's own ancestor
carries. A seed that only ever fires on `exmateria_battlefield` cannot tell a
looping arm from one that still reads a single hardcoded folder — which is
exactly the narrowing dec. 6 is undoing — so every creep and ratchet seed is
parametrized over `cag.FACADES` and asserts the ADDON's name in the output.

🔴 THE INERT ROT BRANCH IS THE ONE TO WATCH. Before a façade exists, `arm_rot`
reports `ok` and scores nothing. That branch is correct for the three addons
still owing names and becomes a lie the moment a burn-down empties, so
`TheRotArm.test_an_absent_facade_with_an_empty_burn_down_FAILS` pins the
transition rather than the state.

⚠️ THESE SEEDS WRITE INTO THE REAL TREE, so a concurrent hand-run of the guard
will see them. Inside the suite it is harmless — `tests/run_all_tests.sh` runs
the pre-flight guards serially.

Run from tools/:
    uv run python -m unittest test_check_addon_globals
"""

from __future__ import annotations

import contextlib
import io
import os
import re
import subprocess
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))
os.chdir(PROJECT_DIR)

import check_addon_globals as cag

# The addon whose façade is BUILT. The rot and citation arms need a real façade
# file to rewrite, and on this tree exactly one addon has one — the other three
# are the migration ADR-0212 dec. 10 stages across three PRs. Named once so the
# day a second façade lands the reader can see what this constant was standing
# in for, rather than finding `exmateria_battlefield` spelled through the file.
SUBJECT = "exmateria_battlefield"
SUBJECT_FACADE = cag.FACADES[SUBJECT]
SUBJECT_DIR = PROJECT_DIR / "addons" / SUBJECT
SUBJECT_FACADE_FILE = cag.facade_file(SUBJECT)

# The anti-vacuity floor, PER ADDON (ADR-0212 dec. 6). This control was a flat
# `len(cag.gd_files(ADDON_DIR)) > 40` while the guard read one addon. Copied
# unchanged across the widening it asserts something FALSE —
# `addons/exmateria_render/` holds TWO `.gd` files — and dropped, the creep arm
# could pass over a scan that found nothing. So each floor is derived from the
# addon it guards, with the live count on 2026-08-30 stated beside it.
MIN_GD_FILES: dict[str, int] = {
    "exmateria_almanac": 28,       # 34 live on 2026-09-06: the façade + 32 members + plugin.gd
    "exmateria_battlefield": 40,   # 45 live
    "exmateria_catalogue": 11,     # 13 live on 2026-09-08, the day #1025 pass 3 moved
                                   # extraction #6 in: the façade + 10 members +
                                   # plugin.gd + install/CatalogueContent.gd
    "exmateria_platform": 8,       # 9 live after #1220 brought the PSX trio home: the
                                   # façade + 6 published (TunePort, DisplayPort,
                                   # CameraCalibration, PsxNum, PsxMagnitude, PsxChirality,
                                   # JsonAsset — 7 rows, PSXDisplay is NOT one) + PSXDisplay
                                   # + plugin.gd
    "exmateria_render": 3,         # 3 live: the façade + FoldSurface.gd + plugin.gd — the WHOLE addon
    "exmateria_schema": 9,         # 11 live: the façade + 6 published + plugin.gd + 3 tests
    "exmateria_sprite_rig": 25,    # 30 live on 2026-09-01, after #744 moved the rig in
    "exmateria_effects": 48,       # 54 live on 2026-09-12, the day #1225 moved extraction
                                   # #7 in: the façade + 52 members (the other 12 members
                                   # are shaders) + plugin.gd
}


def _run(burn_down=None):
    """Run `main()`, optionally over a SEEDED burn-down."""
    buf = io.StringIO()
    saved = cag.BURN_DOWN
    if burn_down is not None:
        cag.BURN_DOWN = burn_down
    try:
        with contextlib.redirect_stdout(buf):
            rc = cag.main()
    finally:
        cag.BURN_DOWN = saved
        os.chdir(PROJECT_DIR)
    return rc, buf.getvalue()


def _bd(**overrides) -> dict[str, set[str]]:
    """The shipped burn-down with one addon's set replaced, DEEP-COPIED.

    The guard's burn-down is a dict of sets now. A seed that reached in and
    mutated one of those sets would leak into every test after it — and the
    leak would be invisible, because the restore in `_run` puts back the same
    object it took out."""
    out = {addon: set(names) for addon, names in cag.BURN_DOWN.items()}
    out.update({addon: set(names) for addon, names in overrides.items()})
    return out


class SeedFile:
    """A file written into the REAL tree, at the REAL scan root.

    A scratch package would prove the code path, which is not the claim: the
    claim is that the register, over THESE addons, scores the seeded line."""

    def __init__(self, path: Path, body: str):
        self.path = path
        self.body = body

    def __enter__(self):
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        self.path.write_text(self.body, encoding="utf-8")
        return self.path

    def __exit__(self, *exc):
        self.path.unlink(missing_ok=True)
        return False


class SeedReplace:
    """Seed a file that ALREADY EXISTS, restoring the real one afterwards.

    `SeedFile` refuses to clobber, which is right for a file the tree does not
    have. The façade IS in the tree now, so every rot seed that rewrites it
    needs this instead — and it must restore on the failure path too, or one
    red test deletes the addon's public surface for every test after it."""

    def __init__(self, path: Path, body: str):
        self.path = path
        self.body = body
        self.stash = path.with_suffix(path.suffix + ".seedstash")

    def __enter__(self):
        assert self.path.exists(), f"{self.path} is missing; use SeedFile"
        assert not self.stash.exists(), f"a previous run leaked {self.stash}"
        self.path.rename(self.stash)
        self.path.write_text(self.body, encoding="utf-8")
        return self.path

    def __exit__(self, *exc):
        self.path.unlink(missing_ok=True)
        self.stash.rename(self.path)
        return False


class TheShippedTree(unittest.TestCase):
    def test_the_shipped_register_is_clean(self):
        rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("FAIL:", out)

    def test_every_burn_down_is_EXACTLY_its_addons_live_class_name_set(self):
        """Anti-vacuity. If the two drift, every seed below still passes while
        the register has stopped describing the addon."""
        for addon, facade in cag.FACADES.items():
            with self.subTest(addon=addon):
                live = set(cag.declared_class_names(PROJECT_DIR / "addons" / addon))
                self.assertEqual(
                    live - {facade}, cag.BURN_DOWN[addon],
                    f"{addon}: BURN_DOWN and the live `class_name` set disagree",
                )

    def test_every_facade_has_a_burn_down_and_a_floor(self):
        """The guard reads `BURN_DOWN.get(addon, set())`, so an addon added to
        `FACADES` without an entry would silently be scored as owing nothing —
        a fifth addon could join the register already exempt from its own
        ratchet's second arm."""
        self.assertEqual(sorted(cag.FACADES), sorted(cag.BURN_DOWN))
        self.assertEqual(sorted(cag.FACADES), sorted(MIN_GD_FILES))

    def test_FACADES_is_EVERY_addon_this_package_owns(self):
        """🔴 THE ONE CONTROL THAT DOES NOT READ THE GUARD'S OWN CONSTANT.

        Every parametrized seed below loops `cag.FACADES`, so narrowing that dict
        back to one addon shrinks the SEEDS' population too and the whole file
        keeps passing — measured, not reasoned: with `FACADES` cut to
        `exmateria_battlefield` the 28 tests reported a single failure, and it was
        this class's key-equality check firing only because the other two dicts had
        not been narrowed alongside it. A register that describes its own constant
        cannot report that the constant stopped describing the tree.

        So the population is derived from the TREE: every directory under
        `addons/` that this package actually owns and that holds GDScript. The
        two it does not own are `exmateria_sound` and `exmateria_spu`, which live
        in `exmateria-sound/` and stay ruled by the repo-root
        `docs/adr/0003-an-installed-addon-owns-five-global-names.md` and that
        package's own `tools/check_globals.py` (ADR-0212 dec. 11).

        🔴 OWNERSHIP IS WHAT GIT TRACKS, NOT HOW THE DIRECTORY GOT THERE (#731).
        This predicate used to read `not d.is_symlink()`, on the reasoning that
        the symlink is what makes dec. 11's package boundary machine-readable.
        It is not — it makes the INSTALL METHOD machine-readable, and this repo
        supports two. `tools/link_worktree_godot_assets.sh` symlinks;
        `tools/sync_exmateria_sound.sh` does `rsync -aL`, which lands a real
        directory. Measured on ONE ref, this branch's `FACADES` against two live
        checkouts:

            symlink install  -> owned = 4 names, equals FACADES
            rsync install    -> owned = 6 names, `exmateria_sound` and
                                `exmateria_spu` leak in and the assert FAILS

        So this test failed on every rsync-installed checkout — including the
        canonical `~/Repos/fft-monorepo` — and because it runs in the suite
        PREFLIGHT, its failure ABORTED the whole run and masked ~38 guards
        behind it. A guard whose verdict depends on a gitignored install detail
        is measuring the box, not the tree.

        `git ls-files addons/` does not have that failure mode: it answers about
        the REF, identically in both install forms (verified on both checkouts
        above), and it stays independent of `cag.FACADES`, which is the
        anti-vacuity property this control exists for.

        Residual, stated rather than elided: an addon added but not yet committed
        reads as unowned until its first commit. That is a window measured in
        minutes and it closes before any guard result is worth anything."""
        tracked = subprocess.run(
            ["git", "-C", str(PROJECT_DIR), "ls-files", "addons/"],
            capture_output=True, text=True, check=True).stdout.splitlines()
        owned = {
            name
            for name in {p.split("/")[1] for p in tracked if p.count("/") >= 2}
            if cag.gd_files(PROJECT_DIR / "addons" / name)
        }
        self.assertEqual(owned, set(cag.FACADES))
        self.assertNotIn("exmateria_sound", owned)
        self.assertNotIn("exmateria_spu", owned)

    def test_the_scan_finds_files_at_all_IN_EVERY_ADDON(self):
        for addon, floor in MIN_GD_FILES.items():
            with self.subTest(addon=addon):
                n = len(cag.gd_files(PROJECT_DIR / "addons" / addon))
                self.assertGreaterEqual(n, floor)


class TheCreepArm(unittest.TestCase):
    """Parametrized over every façade in the dict. A seed that only ever fired
    on one addon could not tell a looping arm from the hardcoded single-addon
    one ADR-0212 dec. 6 widened."""

    def test_a_NEW_class_name_outside_the_burn_down_FAILS_in_EVERY_addon(self):
        for addon in sorted(cag.FACADES):
            with self.subTest(addon=addon):
                probe = f"_SeedCreepProbe_{addon}"
                seed = PROJECT_DIR / "addons" / addon / "_seed_creep.gd"
                with SeedFile(seed, f"class_name {probe}\nextends Node\n"):
                    rc, out = _run()
                self.assertEqual(rc, 1, out)
                self.assertIn(probe, out)
                self.assertIn(f"{addon}: 1 global `class_name`", out)

    def test_the_ONE_LINE_extends_form_is_caught(self):
        """`class_name Foo extends Node` registers the same global as the bare
        form. The root guard's older pattern anchored on end-of-line and scored
        this spelling clean, so the set it compared was smaller than the real
        one."""
        seed = SUBJECT_DIR / "_seed_oneline.gd"
        with SeedFile(seed, "class_name _SeedOneLineProbe extends Node\n"):
            rc, out = _run()
        self.assertEqual(rc, 1, out)
        self.assertIn("_SeedOneLineProbe", out)

    def test_a_class_name_in_a_COMMENT_is_not_scored(self):
        seed = SUBJECT_DIR / "_seed_comment.gd"
        with SeedFile(seed, "extends Node\n# class_name _SeedCommentProbe\n"):
            rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("_SeedCommentProbe", out)

    def test_it_passes_once_the_seed_is_gone(self):
        """The other direction. Without it, a permanently-red arm would pass
        every test above."""
        rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertNotIn("_SeedCreepProbe", out)


class TheRatchetSecondArm(unittest.TestCase):
    """A BURN_DOWN entry that no longer violates must FAIL, or the list rots
    into a permanent exemption. Parametrized for the same reason the creep
    seeds are: one addon's list going stale must be caught in EVERY list."""

    def test_a_STALE_burn_down_entry_FAILS_in_EVERY_addon(self):
        for addon in sorted(cag.FACADES):
            with self.subTest(addon=addon):
                stale = f"_SeedNeverDeclaredAnywhere_{addon}"
                rc, out = _run(_bd(**{addon: cag.BURN_DOWN[addon] | {stale}}))
                self.assertEqual(rc, 1, out)
                self.assertIn(stale, out)
                self.assertIn(f"{addon}: 1 BURN_DOWN entr(ies) name no "
                              "`class_name` any more", out)

    def test_the_shipped_burn_downs_have_no_stale_entry(self):
        rc, out = _run()
        self.assertEqual(rc, 0, out)
        for addon in cag.FACADES:
            self.assertIn(f"{addon}: every BURN_DOWN entry still names a live", out)


class TheRotArm(unittest.TestCase):
    """Every seed here runs over the SHIPPED burn-down, so the creep arm stays
    green and the rot arm is the only thing that can move the verdict. An
    earlier draft emptied the burn-down instead, which fired creep as well —
    the assertions passed for a reason that had nothing to do with rot.

    The seeds rewrite `SUBJECT`'s façade because it is the only one BUILT on
    this tree. The three unbuilt addons are covered by the two INERT-branch
    tests at the bottom, which are the arm's other state."""

    def _facade(self, consts: str) -> str:
        """🔴 EVERY SEEDED CONSTANT GETS A HOST-USE COMMENT, and that is not cosmetic.
        The citation arm (ADR-0208 dec. 6) fails a published name that states no host
        use, so without this every seed below would fire TWO arms and the ones asserting
        rc 1 would pass for a reason unrelated to rot — the exact defect this class's
        docstring was written about, one arm later. The comment cites no path, so the
        rot-of-citation and sibling arms stay quiet too; `TheCitationArm` seeds those."""
        body = "".join(
            ("## Host use: seeded — this probe isolates the ROT arm.\n" + ln + "\n")
            if ln.startswith("const ") else (ln + "\n")
            for ln in consts.splitlines()
        )
        return f"class_name {SUBJECT_FACADE}\nextends RefCounted\n\n{body}"

    def test_a_facade_constant_naming_a_MISSING_file_FAILS(self):
        body = self._facade(
            'const Gone = preload("res://addons/'
            f'{SUBJECT}/lattice/_no_such_file.gd")\n'
        )
        with SeedReplace(SUBJECT_FACADE_FILE, body):
            rc, out = _run()
        self.assertEqual(rc, 1, out)
        self.assertIn("which does not exist", out)
        self.assertIn("Gone", out)

    def test_a_facade_constant_pointing_OUTSIDE_addons_FAILS(self):
        body = self._facade('const Stray = preload("res://src/gpu/CombatHost.gd")\n')
        with SeedReplace(SUBJECT_FACADE_FILE, body):
            rc, out = _run()
        self.assertEqual(rc, 1, out)
        self.assertIn("points outside addons/", out)

    def test_a_facade_publishing_NOTHING_FAILS(self):
        with SeedReplace(SUBJECT_FACADE_FILE, self._facade("# no constants\n")):
            rc, out = _run()
        self.assertEqual(rc, 1, out)
        self.assertIn("publishes nothing", out)

    def test_a_facade_in_the_WRONG_FILE_FAILS(self):
        """The façade lives in the file named after its addon so a stranger can
        find it — ADR-0212 dec. 1's location half, which is what makes the
        invariant stronger than a count of one."""
        stray = SUBJECT_DIR / "lattice" / "_seed_stray_facade.gd"
        with SeedFile(stray, self._facade(
            f'const Lattice = preload("res://addons/{SUBJECT}/lattice/Lattice.gd")\n'
        )):
            rc, out = _run()
        self.assertEqual(rc, 1, out)
        self.assertIn("the façade lives in the file named after", out)

    def test_a_RESOLVING_facade_constant_passes(self):
        """The other direction — without it every assertion above would hold on
        an arm that simply always fails."""
        body = self._facade(
            f'const Lattice = preload("res://addons/{SUBJECT}/lattice/Lattice.gd")\n'
        )
        with SeedReplace(SUBJECT_FACADE_FILE, body):
            rc, out = _run()
        self.assertEqual(rc, 0, out)
        self.assertIn("façade constant(s) all resolve", out)

    def test_an_absent_facade_with_an_empty_burn_down_FAILS(self):
        """🔴 The arm that makes the surface's disappearance loud. `arm_rot`
        reports `THIS ARM IS INERT` while names are owed — correct for the three
        addons mid-migration, and a lie once a burn-down empties. With the
        burn-down empty (which is `SUBJECT`'s shipped state), an absent façade
        means the whole public surface is gone and must fail.

        The façade EXISTS on this tree, so the seed moves it aside rather than
        asserting it away. An earlier draft asserted `not FACADE_FILE.exists()`,
        which was true only until dec. 2 landed and would have started passing
        vacuously the moment the migration it guards was built."""
        stash = SUBJECT_FACADE_FILE.with_suffix(".gd.seedstash")
        SUBJECT_FACADE_FILE.rename(stash)
        try:
            rc, out = _run()
            self.assertEqual(rc, 1, out)
            self.assertIn("the burn-down is empty", out)
            self.assertIn("nothing downstream can name anything", out)
        finally:
            stash.rename(SUBJECT_FACADE_FILE)

    def test_the_INERT_branch_still_reports_while_names_are_owed(self):
        """The other direction of the same branch, driven by a SEEDED burn-down
        so it cannot expire now that `SUBJECT`'s shipped one is empty."""
        stash = SUBJECT_FACADE_FILE.with_suffix(".gd.seedstash")
        SUBJECT_FACADE_FILE.rename(stash)
        try:
            rc, out = _run(_bd(**{SUBJECT: {"_SeedOwedName"}}))
            self.assertIn("THIS ARM IS INERT", out)
        finally:
            stash.rename(SUBJECT_FACADE_FILE)

    def test_an_OWING_addon_reports_one_of_the_arm_TWO_states_IN_EVERY_ADDON(self):
        """The widened arm's two states, on a SEEDED owed name, per addon. An addon
        that still owes names is in exactly one of two states, and the arm must SAY
        which — a rot arm that returned early on a missing file would be
        indistinguishable from one that had scored the addon and found nothing wrong.

        🔴 THIS ASSERTED ONLY THE UNBUILT STATE FIRST, AND IT HAS NOW EXPIRED TWICE.
        It read *"three addons owe names and have no façade file"* and asserted
        `not facade_file(addon).is_file()` for every owing addon; #744 landed the
        sprite rig's façade WHILE it still owed 23 names — which is the whole shape
        of a burn-down, land the surface first and drain after — and the old
        assertion called that a failure. Both states were then asserted, but still
        over the addons owing on the SHIPPED tree, with an anti-vacuity floor that
        said so: *"no addon owes a name any more — this arm now tests nothing."*
        #746 drained the last burn-down to 0 and that floor fired. It was right to:
        the population this arm read is the one the migration exists to empty, so
        reading it at all was the defect. The owed name is FABRICATED now, exactly
        as this file's header says every burn-down seed must be, and the arm can
        never go quiet again.
        """
        for addon in sorted(cag.FACADES):
            owed = f"_SeedOwedLive_{addon}"
            seed = PROJECT_DIR / "addons" / addon / "_seed_owed.gd"
            burn_down = _bd(**{addon: {owed}})
            with self.subTest(addon=addon):
                # The seeded `class_name` is LIVE, so the stale half of arm 2 stays
                # quiet and what is under test is which of the two states arm_rot
                # reports — not whether the entry names anything.
                with SeedFile(seed, f"class_name {owed}\nextends Node\n"):
                    # BUILT and still owing: the enforcing state. The rot arm scores it.
                    rc, out = _run(burn_down)
                    self.assertEqual(rc, 0, out)
                    self.assertIn(f"{addon}: every BURN_DOWN entry still names a live", out)
                    self.assertNotIn(f"{addon}: façade `{cag.FACADES[addon]}` not declared", out)

                    # UNBUILT and owing: the inert state, which must SAY it is inert.
                    stash = cag.facade_file(addon).with_suffix(".gd.seedstash")
                    cag.facade_file(addon).rename(stash)
                    try:
                        rc, out = _run(burn_down)
                        self.assertEqual(rc, 0, out)
                        self.assertIn(f"{addon}: façade `{cag.FACADES[addon]}` not declared yet", out)
                        self.assertIn("THIS ARM IS INERT", out)
                    finally:
                        stash.rename(cag.facade_file(addon))


# --- arm 3: the citation arm (ADR-0208 dec. 6 + ADR-0210 dec. 1 + ADR-0212 dec. 7) ---

# A real file inside SUBJECT, so a seeded constant resolves and only the arm
# under test can move the verdict.
_REAL = f"res://addons/{SUBJECT}/lattice/Tile.gd"
# A real file inside a DIFFERENT addon that genuinely names `Fold` — the sibling
# citation dec. 7 rules on, and the shape schema's heaviest consumers actually
# have. Read off the tree rather than invented, so a seed cannot pass by citing
# something that only exists in the seed.
_SIBLING_ADDON = "exmateria_schema"
_SIBLING_FILE = f"addons/{_SIBLING_ADDON}/compositing_key/Fold.gd"


def _facade(body: str) -> str:
    """A minimal but VALID façade, so only the arm under test can move the verdict.

    The same discipline the rot seeds run under: a seed that fires three arms proves
    none of them. `class_name` and the file location keep creep and rot quiet."""
    return f"class_name {SUBJECT_FACADE}\nextends RefCounted\n\n" + body


class TheCitationArm(unittest.TestCase):
    """ADR-0210 dec. 1's two rots plus ADR-0212 dec. 7's sibling label, on the channel
    ADR-0211 moved the comments to.

    🔴 THIS ARM EXISTS BECAUSE AN ENFORCED INVARIANT ALMOST MOVED HOUSE UNGUARDED.
    Eleven of these names carried a ratcheted host-use citation on
    `check_lattice_publish.DECLARED_PUBLISHED`. ADR-0211 collapsed that list to one and
    the fourteen per-name comments moved to the façade — where, until this arm, nothing
    read them. The population moved and the instrument did not, which is the failure this
    repo keeps re-finding."""

    def test_the_shipped_facade_states_a_host_use_for_EVERY_name(self):
        rc, out = _run()
        self.assertIn("published name(s) state a host use", out)
        self.assertEqual(rc, 0, out)

    def test_the_parse_is_not_COLLAPSED(self):
        """An arm that parsed nothing reports zero failures. Pin that it SAW the list —
        every published constant must appear, so the two arms agree on one population."""
        cites = cag.facade_citations(SUBJECT)
        consts = cag._PUBLISHED_CONST.findall(SUBJECT_FACADE_FILE.read_text())
        self.assertEqual(sorted(cites), sorted(n for n, _ in consts))
        self.assertGreaterEqual(len(cites), 1, "the citation parse collapsed")

    def test_a_constant_with_NO_COMMENT_fails(self):
        body = 'const Tile = preload("%s")\n' % _REAL
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn("state no host use", out)
        self.assertIn("Tile", out)
        self.assertEqual(rc, 1, out)

    def test_a_citation_to_a_MISSING_file_fails(self):
        body = ("## Host use: `src/zzz_not_a_file_anywhere.gd` holds one.\n"
                'const Tile = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn("MOVED or been deleted", out)
        self.assertIn("src/zzz_not_a_file_anywhere.gd", out)
        self.assertEqual(rc, 1, out)

    def test_a_citation_to_a_file_that_does_NOT_NAME_it_fails(self):
        """Rot two, seeded against a REAL host file that genuinely does not name the
        symbol — the file is present, so the first arm must stay quiet and only the
        second may fire. Two rots, two arms."""
        body = ("## Host use: `src/gpu/CombatHost.gd` holds one.\n"
                'const ZzzNotASymbolAnywhere = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn("no longer names it", out)
        self.assertNotIn("MOVED or been deleted", out)
        self.assertEqual(rc, 1, out)

    def test_an_entry_citing_NOTHING_passes_the_rot_arms(self):
        """The stated blind spot, pinned so it cannot be widened by accident. Prose that
        names a class or a method instead of a path is house style — `TileHighlights`
        names three host controllers and `TileCursorCompositor` says it has no host namer
        at all. Presence still covers them; scoring the prose would red a correct
        comment."""
        body = ("## Host use: the strategy phase owns it — `PlacementPhaseController`.\n"
                'const Tile = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertNotIn("MOVED or been deleted", out)
        self.assertNotIn("no longer names it", out)
        self.assertNotIn("state no host use", out)
        self.assertEqual(rc, 0, out)

    # --- ADR-0212 dec. 7: a sibling citation is valid PROVIDED IT SAYS SO ---

    def test_an_UNLABELLED_sibling_addon_citation_fails(self):
        """The citation resolves and the file still names the symbol, so both rot arms
        stay quiet and only dec. 7's arm may fire. Without the label a reader cannot
        tell an addon consumer from a host one, and the two are staged differently —
        the sibling is only present because `plugin.cfg` `deps=` declares it."""
        body = (f"## Host use: `{_SIBLING_FILE}` holds one.\n"
                'const Fold = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn("a SIBLING ADDON", out)
        self.assertIn(_SIBLING_FILE, out)
        self.assertNotIn("MOVED or been deleted", out)
        self.assertNotIn("no longer names it", out)
        self.assertEqual(rc, 1, out)

    def test_a_LABELLED_sibling_addon_citation_passes(self):
        """The other direction, and the one dec. 7 exists for: without it the rule would
        read as 'no sibling citations', which leaves `Fold`'s most load-bearing use —
        inside `exmateria_battlefield` — uncitable."""
        body = (f"## Host use: ⚠️ **SIBLING NAMER** — `{_SIBLING_FILE}` holds one.\n"
                'const Fold = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertNotIn("a SIBLING ADDON", out)
        self.assertEqual(rc, 0, out)

    def test_an_IN_ADDON_citation_is_NOT_read_as_a_sibling(self):
        """The boundary of dec. 7's rule, pinned so it does not widen into 'every
        `addons/` path is a sibling'. `exmateria_battlefield`'s own files are not a
        sibling of `exmateria_battlefield` — asking for the SIBLING label there would
        red a correct comment, and dec. 7's message would name the wrong relationship.
        It is a different arm that fires, which the next class asserts."""
        body = (f"## Host use: `addons/{SUBJECT}/lattice/Tile.gd` holds one.\n"
                'const Tile = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            _rc, out = _run()
        self.assertNotIn("a SIBLING ADDON", out)

    def test_a_RESTORED_facade_passes(self):
        """The control every seed above depends on: `SeedReplace` must put the real
        façade back, including on the failure path, or a red test here deletes the
        addon's public surface for every test after it.

        ⚠️ THE COUNT IS THE CONTROL and it moves when the surface does — every seeded
        façade above publishes exactly one name, so a stale-but-plausible number here
        would still catch a failed restore, but a number nobody maintains stops saying
        which surface came back. 14 -> 15 when ADR-0218 published `TerrainFixture`;
        15 -> 16 when ADR-0225 published `RomWalkStepper`, the `{28} Walk To` render
        half that sits beside `EventPathfinder`; 16 -> 17 when ADR-0226 published
        `RomTerrain`, which is the map file BOTH of those halves read."""
        rc, out = _run()
        self.assertIn("17 façade constant(s) all resolve", out)
        self.assertEqual(rc, 0, out)


_INADDON_FILE = f"addons/{SUBJECT}/lattice/Tile.gd"
_INADDON_MSG = "a file INSIDE THIS ADDON"
_REPORT = " labelled IN-ADDON citation(s)"


class TheInAddonCitationLabel(unittest.TestCase):
    """ADR-0217 dec. 5, mechanizing ADR-0215 dec. 4 — the third CITE label.

    🔴 THIS ARM REVERSES A TEST THAT USED TO ASSERT THE OPPOSITE.
    `test_a_citation_INSIDE_THE_SAME_addon_needs_no_label` pinned the silent pass as a
    requirement, which was right while dec. 7 was the only rule and wrong the moment
    dec. 4 became mechanized: an in-addon citation is a real consumer, but it is not a
    HOST use, and reading green over it is precisely the failure dec. 4 predicts. The
    old test survives one class up, narrowed to the claim that still holds — an in-addon
    path is not read as a SIBLING.

    Dec. 5 asks for a label and A COUNT, not for a prohibition: an addon is allowed an
    in-addon consumer. So the shape is `unlabelled -> red`, `labelled -> green`, and the
    count is REPORTED either way for pass 9 to read."""

    def test_an_UNLABELLED_in_addon_citation_FAILS(self):
        """The citation resolves and the file still names the symbol, so both rot arms
        stay quiet and only dec. 5's arm may fire — the same one-arm discipline the
        sibling seeds run under."""
        body = (f"## Host use: `{_INADDON_FILE}` holds one.\n"
                'const Tile = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn(_INADDON_MSG, out)
        self.assertIn(_INADDON_FILE, out)
        self.assertNotIn("MOVED or been deleted", out)
        self.assertNotIn("no longer names it", out)
        self.assertNotIn("a SIBLING ADDON", out)
        self.assertEqual(rc, 1, out)

    def test_a_LABELLED_in_addon_citation_passes(self):
        """The other direction, and the one dec. 5 exists for. Without it the rule reads
        as 'no in-addon citations', which would make the rig's own `SequenceViewer` an
        uncitable consumer and push the comment into prose the arm cannot read at all —
        trading a silent pass for a silent pass."""
        body = (f"## Host use: \u26a0\ufe0f **IN-ADDON NAMER** — `{_INADDON_FILE}` holds one.\n"
                'const Tile = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertNotIn(_INADDON_MSG, out)
        self.assertEqual(rc, 0, out)

    def test_the_LABELLED_count_is_REPORTED_and_reads_the_seeded_row(self):
        """The acceptance criterion pass 9 actually reads. A seed that only asserted
        `rc == 0` would pass over a branch that labels correctly and counts NOTHING, so
        this reads the printed number on the tree that has one — 1, not 0."""
        body = (f"## Host use: \u26a0\ufe0f **IN-ADDON NAMER** — `{_INADDON_FILE}` holds one.\n"
                'const Tile = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn(f"{SUBJECT}: 1{_REPORT}", out)
        self.assertEqual(rc, 0, out)

    def test_the_count_is_REPORTED_on_the_FAILING_path_too(self):
        """A number printed only when everything else is green is missing on the one day
        it moved. Seeded with a SECOND constant that fails a different arm, so the run
        is red and the count must still appear."""
        body = (f"## Host use: \u26a0\ufe0f **IN-ADDON NAMER** — `{_INADDON_FILE}` holds one.\n"
                'const Tile = preload("%s")\n' % _REAL
                + "## Host use: `src/zzz_not_a_file_anywhere.gd` holds one.\n"
                'const Tile2 = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertEqual(rc, 1, out)
        self.assertIn("MOVED or been deleted", out)
        self.assertIn(f"{SUBJECT}: 1{_REPORT}", out)

    def test_the_SHIPPED_tree_reports_a_count_for_EVERY_addon(self):
        """`0` is a measurement, not a silence — and a per-addon line, because a single
        total would hide which addon's surface moved. Every shipped façade must print
        its row.

        🔴 THIS USED TO ASSERT THE COUNT WAS 0 FOR EVERY ADDON, and #744 is the day
        that stopped being a property of the tree: the sprite rig's port is called
        only from inside the rig, which is what a correct port looks like (ADR-0217
        dec. 5), so its row reads 5. Pinning the value made the assertion a claim
        about the CORPUS rather than about the arm — a number moving for a legitimate
        reason would red it and the fix would be to edit the expected number, which is
        no assertion at all. What the arm owes is a ROW PER ADDON, so that is what is
        asserted; the non-zero half is asserted separately below so the report cannot
        quietly collapse back to a constant 0."""
        rc, out = _run()
        for addon in sorted(cag.FACADES):
            self.assertRegex(out, rf"{re.escape(addon)}: \d+{re.escape(_REPORT)}")
        self.assertEqual(rc, 0, out)

    def test_the_SHIPPED_tree_carries_at_least_one_NON_ZERO_row(self):
        """The other half. A report that is structurally present but always reads 0 is
        indistinguishable from one that never counts anything, and dec. 5 exists
        because the count CAN be positive — an addon whose published name is asked for
        only by its own consumers. The shipped tree has such a row today; if it ever
        has none, this fails and the label's live example has to be re-found rather
        than assumed."""
        rc, out = _run()
        rows = re.findall(rf"(\w+): (\d+){re.escape(_REPORT)}", out)
        self.assertTrue(rows, out)
        self.assertTrue(any(int(n) > 0 for _, n in rows),
                        "every addon reports 0 labelled in-addon citations — the arm has "
                        "no live example left, so nothing proves it can count. " + out)

    # --- the two labels are NOT interchangeable (dec. 7's behaviour, unchanged) ---

    def test_the_IN_ADDON_label_does_NOT_excuse_a_SIBLING_citation(self):
        """One `_ADDON_CITE` match, two branches. If the arm read either label for
        either relationship the count would be meaningless — a sibling citation would
        book itself as an in-addon one and dec. 7's message would never fire."""
        body = (f"## Host use: \u26a0\ufe0f **IN-ADDON NAMER** — `{_SIBLING_FILE}` holds one.\n"
                'const Fold = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn("a SIBLING ADDON", out)
        self.assertIn(f"{SUBJECT}: 0{_REPORT}", out)
        self.assertEqual(rc, 1, out)

    def test_the_SIBLING_label_does_NOT_excuse_an_IN_ADDON_citation(self):
        """The mirror. `SIBLING NAMER` on an in-addon path says the wrong thing about
        the relationship, so it must not buy the pass — and it must not be counted."""
        body = (f"## Host use: \u26a0\ufe0f **SIBLING NAMER** — `{_INADDON_FILE}` holds one.\n"
                'const Tile = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertIn(_INADDON_MSG, out)
        self.assertIn(f"{SUBJECT}: 0{_REPORT}", out)
        self.assertEqual(rc, 1, out)

    def test_a_LABELLED_SIBLING_citation_still_passes_and_counts_ZERO(self):
        """Dec. 7's own green case, re-asserted from this class: widening `_ADDON_CITE`
        into two branches must not change it, and a sibling must never book itself into
        the in-addon count."""
        body = (f"## Host use: \u26a0\ufe0f **SIBLING NAMER** — `{_SIBLING_FILE}` holds one.\n"
                'const Fold = preload("%s")\n' % _REAL)
        with SeedReplace(SUBJECT_FACADE_FILE, _facade(body)):
            rc, out = _run()
        self.assertNotIn("a SIBLING ADDON", out)
        self.assertNotIn(_INADDON_MSG, out)
        self.assertIn(f"{SUBJECT}: 0{_REPORT}", out)
        self.assertEqual(rc, 0, out)

    def test_the_arm_is_INERT_where_no_facade_file_exists(self):
        """Why this can land before the rig's addon does (#738 before #742): the arm
        returns before any of its branches when the façade file is absent, so a
        `FACADES` row added ahead of the folder would not be reddened BY THIS ARM.
        Asserted on a name the tree does not have, not argued."""
        self.assertFalse(cag.facade_file("exmateria_not_an_addon").is_file())
        buf = io.StringIO()
        saved = list(cag.fails)          # module state, cleared per `main()` and not
        cag.fails.clear()                # per arm — without this the seed inherits
        try:                             # whatever ran before it in this process.
            with contextlib.redirect_stdout(buf):
                cag.arm_citations("exmateria_not_an_addon", "ExMateriaNotAnAddon")
            seeded = list(cag.fails)
        finally:
            cag.fails[:] = saved
        self.assertEqual(buf.getvalue(), "")
        self.assertEqual(seeded, [])


if __name__ == "__main__":
    unittest.main()
