"""Seed-red tests for the resource-path register (ADR-0164 dec. 4 criterion 4, built by
ADR-0205, widened to a per-addon mapping by ADR-0217 dec. 4).

An arm that has never been seen to FIRE is indistinguishable from an arm that cannot
fire. This family has paid for that repeatedly — `check_addon_portability.py` shipped
green across an entire extraction because it stopped looking; `check_lattice_ports` and
`check_lattice_doors` each had a `test_a_LISTED_row_prints_above_the_verdict` go vacuous
the day its burn-down emptied; and `test_check_addon_install.py` asserted the literal
`"Not a pass"` — a heading the register prints ONLY WHILE IT CARRIES DEBT — so paying the
last row turned the whole suite red at pre-flight. That was the SIXTH guard in this repo
to expire on success.

So every seed below CONSTRUCTS the site, and where the arm is about a listed row, the row
too. **Not one test reads a row off the shipped `SCENE_BURN_DOWN`.** ✅ THAT DESIGN HAS NOW
BEEN PAID OFF: the register opened at 138 rows, ADR-0207 deleted **121** of them in one
pass — 115 for the composer mount, 6 for the camera — and all 16 tests here still passed,
unchanged, against a burn-down under an eighth of its opening size. They must still fire on
the day it reaches zero.

🔴 EVERY SEED IS PARAMETRIZED OVER `cls.SUBJECTS` AND GRADED ON THAT SUBJECT'S SECTION.
The guard's subject used to be one hardcoded string, so a test could seed Battlefield's
prefix, read the whole report, and pass no matter which addon actually fired. With two
subjects that is a live hazard, not a hypothetical: the rig's folder does not exist yet, so
a rig arm that silently never fires would look exactly like a rig arm that works. `_section`
slices ONE addon's block out of the report and every per-addon assertion runs against that
slice, so a seed that only ever fires on Battlefield fails its rig twin. The classes at the
bottom of this file are generated, one per (behaviour × addon) — read `_PARAMETRIZED`.

⚠️ THESE SEEDS WRITE INTO THE REAL TREE, so a `check_lattice_scene.py` run happening
CONCURRENTLY will see them and read one site too many. Inside the suite it is harmless:
`tests/run_all_tests.sh` runs the pre-flight guards serially. Do not read a register count
taken while the suite is running. `SeedFile` also removes any directory it had to CREATE —
without that, `test_the_addons_OWN_files_are_not_scanned` leaves an `addons/<subject>/`
behind with no `plugin.cfg` in it, and the next addon guard in the same pre-flight reds on
a directory this test invented.

Run from tools/:
    uv run python -m unittest test_check_lattice_scene
"""

from __future__ import annotations

import atexit
import contextlib
import io
import os
import re
import signal
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))
os.chdir(PROJECT_DIR)

import check_lattice_scene as cls

SEED_OWNER = ("#0 — a constructed row", "seeded by the test, never read off the tree")
ADDONS = sorted(cls.SUBJECTS)

TARGET = "_seed/Target.gd"
OTHER = "_seed/Other.tscn"


def rel_for(addon: str, suffix: str = "") -> str:
    """A seed path that is unique PER SUBJECT. Two subjects seeding the same path would
    collide on `SeedFile`'s leak assertion and, worse, one subject's seed would sit in the
    other's corpus — the corpus excludes only its own addon, so a shared seed file is
    scanned by both and the isolation this file is about would be fiction."""
    return "src/_scene_seed_%s%s.tscn" % (addon, suffix)


HOST_PATH = "res://src/_scene_seed_host.gd"

# The SECOND spelling of a host reach (ADR-0222 Amendment 2, #871). A bare `ClassName`
# resolves through Godot's global class registry and reaches the file that declares it,
# with no path in the caller — which is why `tests/MapDitherSnapTest.gd` held two
# battlefield shader paths, reached host territory, and still read `oracle_blockers() ==
# []` for two days while the guard was RED on trunk over exactly those two rows.
HOST_CLASS = "_SceneSeedHostClass"
HOST_CLASS_REL = "src/_scene_seed_host_class.gd"
HOST_CLASS_BODY = "class_name %s\nextends Node\n" % HOST_CLASS


def addon_class_rel(addon: str) -> str:
    """The same declaration INSIDE the addon. Not a blocker, and the difference is the
    whole point of condition 2: a test naming a class the addon declares moves into the
    addon WITH it, so that reach is no argument for permanence."""
    return "%s_seed_class.gd" % cls.addon_dir(addon)


def oracle_rel_for(addon: str, suffix: str = "") -> str:
    """A seed under `tests/`, because arm 3's condition 1 is that an oracle IS a test.

    A `.gd` and never a `.tscn`: `run_tests_parallel` keys every test on a
    `tests/<stem>.tscn`, so a seeded scene here would be COLLECTED AND RUN by the next
    suite in the same tree. `SeedFile` removes it either way, but a seed that can only
    leak harmlessly is cheaper than one that reds a different runner when a suite is
    reaped mid-flight."""
    return "tests/_scene_seed_%s%s.gd" % (addon, suffix)


def oracle_body(addon: str, target: str, host: bool = True,
                klass: str | None = None, in_comment: bool = False) -> str:
    """A test-shaped seed: it names the addon path (so it is a SITE) and, when `host`,
    a host path (so arm 3's condition 2 holds). `host=False` is the constructed form of
    an oracle whose permanence ARGUMENT has expired.

    `klass` adds the OTHER spelling of a host reach — a bare `ClassName`. `in_comment`
    puts that same name in prose instead of in code, which must NOT count: a class name
    is a bare word and this repo's files name classes in their docstrings constantly, so
    a blocker that fired on prose would admit rows on an argument nothing checks."""
    lines = ["extends Node", ""]
    if host:
        lines.append('const Host = preload("%s")' % HOST_PATH)
    if klass:
        lines.append("## prose that merely names %s" % klass if in_comment
                     else "var probe := %s.new()" % klass)
    lines.append('const Seam := "%s%s"' % (cls.prefix(addon), target))
    return "\n".join(lines) + "\n"


def _nest(base: dict, addon: str, rows: dict) -> dict:
    """`base` with `rows` installed for `addon` and every OTHER subject left shipped.

    Both registers are keyed by addon now, and `main()` refuses a register whose keys do
    not match `SUBJECTS` — so a test cannot hand it a flat dict, and a test that swapped
    only its own subject's rows would drop the other subject's entirely."""
    out = {a: dict(base[a]) for a in cls.SUBJECTS}
    out[addon] = rows
    return out


def shipped(base: dict, addon: str) -> dict:
    return dict(base[addon])


def all_live_sites_declared(addon: str) -> dict:
    """Every site the REAL tree holds for `addon`, declared as a mount — the CONSTRUCTED
    empty-register state.

    `report()` scores `sites - mounts`, so this is the only way to drive a subject's
    scored set to zero without editing the tree. It used to be reachable for the rig by
    simply shipping an empty burn-down, because the addon folder did not exist and the
    scan found nothing; #744 landed the move and eight real sites, and that shortcut died
    with it. Constructing the state keeps the arm alive in BOTH directions — it does not
    expire when a burn-down empties and it does not expire when one fills."""
    return {k: SEED_OWNER for k in cls.scan(addon)}


def _run(burn_down=None, mounts=None, oracles=None):
    buf = io.StringIO()
    ob, om, oo = cls.SCENE_BURN_DOWN, cls.DECLARED_MOUNTS, cls.SCENE_ORACLES
    if burn_down is not None:
        cls.SCENE_BURN_DOWN = burn_down
    if mounts is not None:
        cls.DECLARED_MOUNTS = mounts
    if oracles is not None:
        cls.SCENE_ORACLES = oracles
    try:
        with contextlib.redirect_stdout(buf):
            rc = cls.main()
    finally:
        cls.SCENE_BURN_DOWN, cls.DECLARED_MOUNTS, cls.SCENE_ORACLES = ob, om, oo
        os.chdir(PROJECT_DIR)
    return rc, buf.getvalue()


def _section(out: str, addon: str) -> str:
    """ONE subject's block. Grading a per-addon arm on the whole report is the bug this
    widening could have shipped: with two subjects, `assertNotIn("CRITERION 4 IS 0")` is
    false tree-wide the moment the OTHER addon is clean, and `assertIn(...)` passes when
    the wrong addon printed it."""
    head = "SUBJECT %s " % addon
    i = out.find(head)
    assert i != -1, "no section for %s in:\n%s" % (addon, out)
    j = out.find("\n" + "=" * 78, i)
    return out[i:] if j == -1 else out[i:j]


# ---------------------------------------------------------------------------
# A REAPED RUN LEAVES ITS SEED IN THE TREE, AND THE LEFTOVER IS NOT INERT
# ---------------------------------------------------------------------------
# `SeedFile` writes into the real repo and removes it in `__exit__` — which never runs if
# the process is killed mid-`with`. The leftover then keeps doing the job it was seeded to
# do: `tests/_scene_seed_<addon>.gd` names a path into the addon, so `check_lattice_scene`
# scores it as an UNLISTED production reach and exits 1, and the pre-flight stops at its
# first red guard. That is how one 4-line fixture blocked an entire worktree's suite —
# `check_lattice_scene` red, 39 of the 82 tests here red (14 on the leak assert below),
# and nothing in either report saying "a fixture leaked, delete it".
#
# Two defences, because neither covers the other's case:
#
#   1. The handlers below unlink whatever is live when the process is ASKED to die. That
#      is Ctrl+C and the SIGTERM a `timeout`/harness kill sends — every ordinary reaping.
#      SIGKILL cannot be caught, so it can still leak.
#   2. `setUpModule` sweeps whatever leaked anyway — and SAYS SO. A silent sweep would
#      hide the SIGKILL that produced it, and this file's whole subject is arms that stop
#      firing without telling anyone.
_LIVE_SEEDS: set[Path] = set()

# Every seed name this module writes, as globs under PROJECT_DIR. `_scene_seed` and
# `_seed_class` are this fixture's own spellings and nothing else in the repo uses them,
# so the sweep cannot reach a real file. The `*` tails catch the `.uid` companions Godot
# mints when a later run imports a leaked `.gd` — `__exit__` never knew about those.
_SEED_GLOBS = (
    "src/_scene_seed_*",
    "tests/_scene_seed_*",
    ".godot/_scene_seed_*",
    "addons/*/_scene_seed*",
    "addons/*/_seed_class.gd*",
)


def _unlink_live_seeds() -> None:
    for path in list(_LIVE_SEEDS):
        with contextlib.suppress(OSError):
            path.unlink(missing_ok=True)
    _LIVE_SEEDS.clear()


def _unlink_then_die(signum, _frame):
    """Clean up, then die of the ORIGINAL signal — never `sys.exit`. A killed process must
    still look killed to whoever killed it, or a harness reads a reaped run as a clean one."""
    _unlink_live_seeds()
    signal.signal(signum, signal.SIG_DFL)
    os.kill(os.getpid(), signum)


atexit.register(_unlink_live_seeds)
for _sig in (signal.SIGINT, signal.SIGTERM):
    # Only the main thread may install a handler, and a platform may not have the signal.
    with contextlib.suppress(ValueError, OSError, AttributeError):
        signal.signal(_sig, _unlink_then_die)


def setUpModule() -> None:
    """Sweep seeds a previous run leaked, before the first `SeedFile` trips over one.

    Reported, never silent: the sweep names each path it removed. Reaching this code means
    defence 1 did not run — a SIGKILL, or a crash hard enough to skip `atexit` — and that
    is worth a line in the log rather than a tree that quietly heals itself.
    """
    swept = []
    for pattern in _SEED_GLOBS:
        for path in sorted(PROJECT_DIR.glob(pattern)):
            with contextlib.suppress(OSError):
                path.unlink()
                swept.append(path.relative_to(PROJECT_DIR).as_posix())
    if swept:
        print("[test_check_lattice_scene] swept %d leaked seed file(s) from a previous "
              "run: %s" % (len(swept), ", ".join(swept)))


class SeedFile:
    """A path reach written into the REAL tree, at a REAL scan root. A scratch package
    would prove the code path, which is not the claim: the claim is that the register,
    over THIS repo, scores the seeded line as a reach into the addon. Removed in
    `__exit__` whether or not the body raised — along with any directory it had to
    create, so a seed under an addon root that does not exist yet leaves nothing."""

    def __init__(self, rel: str, body: str):
        self.path = PROJECT_DIR / rel
        self.body = body
        self.made: list[Path] = []

    def __enter__(self):
        # `setUpModule` has already swept anything a PREVIOUS run leaked, so surviving this
        # far means a live collision — two seeds in one run claiming one path — which is a
        # different bug and still worth failing on.
        assert not self.path.exists(), f"a previous run leaked {self.path}"
        d = self.path.parent
        while not d.exists():
            self.made.append(d)
            d = d.parent
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(self.body, encoding="utf-8")
        _LIVE_SEEDS.add(self.path)
        return self.path

    def __exit__(self, *exc):
        _LIVE_SEEDS.discard(self.path)
        self.path.unlink(missing_ok=True)
        for d in self.made:                       # innermost first
            with contextlib.suppress(OSError):
                d.rmdir()
        return False


def body_for(addon: str, *targets: str) -> str:
    lines = ['[gd_scene format=3]', '']
    for i, t in enumerate(targets, 1):
        lines.append('[ext_resource type="Script" path="%s%s" id="%d_seed"]'
                     % (cls.prefix(addon), t, i))
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Per-subject behaviours. Each base below is instantiated ONCE PER SUBJECT at the
# bottom of the file; `self.ADDON` is the subject under test and every assertion
# reads `_section(out, self.ADDON)`.
# ---------------------------------------------------------------------------

class BothDirectionsFailBase:
    """A ratchet has TWO arms. Grade on the REPORTED LINE, never on `rc` — and with two
    subjects, `rc` is the OR across them, so it cannot say WHICH one fired."""

    def _fired(self, out, kind):
        sec = _section(out, self.ADDON)
        self.assertRegex(sec, r"❌ %s arm 1 — \d+ %s" % (re.escape(self.ADDON), kind))
        return sec

    def test_an_UNLISTED_site_is_RED(self):
        rel = rel_for(self.ADDON)
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run(burn_down=_nest(cls.SCENE_BURN_DOWN, self.ADDON,
                                           shipped(cls.SCENE_BURN_DOWN, self.ADDON)))
        sec = self._fired(out, "UNLISTED site")
        self.assertIn(rel, sec)
        self.assertIn(TARGET, sec)
        self.assertEqual(rc, 1, out)

    def test_a_STALE_row_is_RED(self):
        absent = rel_for(self.ADDON, "_absent")
        rows = shipped(cls.SCENE_BURN_DOWN, self.ADDON)
        rows[(absent, TARGET)] = SEED_OWNER
        rc, out = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON, rows))
        sec = self._fired(out, "STALE row")
        self.assertIn(absent, sec)
        self.assertEqual(rc, 1, out)

    def test_a_row_whose_FILE_SURVIVES_but_whose_reach_is_gone_is_STALE(self):
        """The shape a CLOSED row actually has. `test_a_STALE_row_is_RED` names a file
        that does not exist; closing a row keeps the file and removes the PATH — which is
        what the MapComposer collapse does to 115 rows, leaving every consumer in place
        and pointing at a host-owned indirection instead. A scanner that asked "does this
        file exist?" would keep the row alive forever."""
        rel = rel_for(self.ADDON)
        body = ('[gd_scene format=3]\n\n'
                '[ext_resource type="Script" path="res://src/Kept.gd" id="1_kept"]\n')
        rows = shipped(cls.SCENE_BURN_DOWN, self.ADDON)
        rows[(rel, TARGET)] = SEED_OWNER
        with SeedFile(rel, body):
            rc, out = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON, rows))
        sec = self._fired(out, "STALE row")
        self.assertIn(rel, sec)
        self.assertEqual(rc, 1, out)

    def test_the_OTHER_subjects_stay_GREEN_while_this_one_reds(self):
        """🔴 THE WIDENING'S OWN FAILURE MODE. One shared scanner, two subjects: a seed
        that leaked across the mapping would red every subject at once and the register
        would stop being able to say which addon owes what. Asserted on the sections, not
        on `rc`, because `rc` is the OR and is 1 either way."""
        rel = rel_for(self.ADDON)
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run()
        self.assertEqual(rc, 1, out)
        for other in ADDONS:
            if other == self.ADDON:
                continue
            sec = _section(out, other)
            self.assertNotIn("UNLISTED site(s)", sec)
            self.assertNotIn(rel, sec)
            self.assertIn("✅ %s" % other, sec)


class TheVerdictIsPerSubjectBase:

    def test_a_LISTED_row_prints_above_the_verdict(self):
        """CONSTRUCTS both halves. `"Not a pass"` prints only while the register carries
        debt; asserting it against LIVE debt is the exact control that expired six times
        in this repo. This one still fires when the subject's burn-down is empty — which
        it is for `exmateria_battlefield`, and was for the rig until #744 seeded eight
        rows. It reads `shipped()` and ADDS to it, so it is indifferent either way."""
        rel = rel_for(self.ADDON)
        rows = shipped(cls.SCENE_BURN_DOWN, self.ADDON)
        rows[(rel, TARGET)] = SEED_OWNER
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON, rows))
        sec = _section(out, self.ADDON)
        self.assertIn("RESOURCE-PATH REGISTER", sec)
        self.assertIn("Not a pass", sec)
        self.assertIn("criterion 4 unmet", sec)
        self.assertIn(SEED_OWNER[0], sec)
        self.assertNotIn("UNLISTED site(s)", sec)
        self.assertEqual(rc, 0, out)

    def test_the_two_GREEN_verdicts_are_not_the_same_sentence(self):
        """A register carrying named debt and a register carrying none are both rc 0, and
        saying so with one sentence is how a burn-down gets read as a pass while it still
        holds rows. Seeded BOTH ways over the same tree, because both subjects ship an
        empty list and asserting only the live state would test one half.

        Each verdict carries its subject's NAME, and that is load-bearing: with two
        subjects the report contains both sentences at once, so `assertNotIn` tree-wide
        would be false for a reason that has nothing to do with this addon.

        🔴 BOTH HALVES DECLARE THE TREE'S LIVE SITES AS MOUNTS (#744). This used to pass
        an empty burn-down and nothing else, which reached the zero verdict only because
        neither subject had real scored sites — Battlefield's three are all mounts already
        and the rig's folder did not exist. #744 gave the rig eight, so an empty burn-down
        now produces eight UNLISTED rows and rc 1, and the empty half would have been
        asserting the FAILURE path while still reading green. `all_live_sites_declared`
        constructs the zero state instead."""
        covered = all_live_sites_declared(self.ADDON)
        rc_empty, out_empty = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON, {}),
                                   _nest(cls.DECLARED_MOUNTS, self.ADDON, covered))
        sec = _section(out_empty, self.ADDON)
        self.assertIn("✅ %s CRITERION 4 IS 0" % self.ADDON, sec)
        self.assertNotIn("resource-path register OK", sec)
        self.assertIn("ADR-0202 dec. 1", out_empty)   # axis B is still owed, every report
        self.assertEqual(rc_empty, 0, out_empty)

        rel = rel_for(self.ADDON)
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc_debt, out_debt = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON,
                                           {(rel, TARGET): SEED_OWNER}),
                                     _nest(cls.DECLARED_MOUNTS, self.ADDON, covered))
        sec = _section(out_debt, self.ADDON)
        self.assertIn("✅ %s resource-path register OK" % self.ADDON, sec)
        self.assertIn("NOT a pass on criterion 4", sec)
        self.assertNotIn("CRITERION 4 IS 0", sec)
        self.assertEqual(rc_debt, 0, out_debt)

    def test_the_THIRD_verdict_is_its_OWN_sentence_too(self):
        """🔴 ADR-0222 dec. 3. The split created a THIRD way of being green — criterion 4
        at 0 over a NON-EMPTY oracle channel — and it is not the same claim as either of
        the two above. "No production file reaches in" is a real pass; "no file in the
        tree names an addon path" is a bigger one, and printing dec.-4's sentence for both
        is how the split would read as a win it did not buy.

        THIS WAS WRITTEN AS THE STATE THE RIG REACHES THE DAY `assets/materials/unit.tres`
        DRAINS, so the sentence would be seen firing before that pass rather than first
        appearing in its report. It reached the state on 2026-09-03 and the row did not
        drain — it was measured unpayable and declared a mount (ADR-0222 dec. 4) —
        which is exactly why the arm was worth writing on a CONSTRUCTED state: it proved
        the sentence over a seeded exemption, and an exemption is what actually arrived.
        Constructed: an empty burn-down, every live site declared, and one seeded oracle
        row over a seeded test."""
        covered = all_live_sites_declared(self.ADDON)
        rel = oracle_rel_for(self.ADDON)
        with SeedFile(rel, oracle_body(self.ADDON, TARGET)):
            rc, out = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON, {}),
                           _nest(cls.DECLARED_MOUNTS, self.ADDON, covered),
                           _nest(cls.SCENE_ORACLES, self.ADDON, {(rel, TARGET): SEED_OWNER}))
        sec = _section(out, self.ADDON)
        self.assertIn("✅ %s CRITERION 4 IS 0 — no PRODUCTION file" % self.ADDON, sec)
        self.assertIn("1 oracle site(s) remain and are REPORTED, not paid", sec)
        # \U0001f534 AND THE EXEMPTION IS NAMED IN THE SAME BREATH. This construction drives
        # the scored set to 0 by DECLARING every live site, so a verdict that stopped there
        # would be claiming "no production file names a path into the addon" over a tree in
        # which several do. The clause is what makes the third sentence honest.
        self.assertIn("site(s) are DECLARED MOUNTS (arm 2), subtracted before this", sec)
        # and it must NOT be either of the other two sentences
        self.assertNotIn("resource-path register OK", sec)
        self.assertNotIn("the burn-down is EMPTY rather than merely all-named", sec)
        self.assertEqual(rc, 0, out)

    def test_the_subject_is_NAMED_in_its_own_header(self):
        rc, out = _run()
        sec = _section(out, self.ADDON)
        self.assertIn(cls.prefix(self.ADDON), sec)
        self.assertIn("except `%s`" % cls.addon_dir(self.ADDON), sec)
        self.assertIn(cls.SUBJECTS[self.ADDON][:40], sec)
        self.assertEqual(rc, 0, out)


class TheDeclaredMountIsReportedNotScoredBase:

    def test_a_DECLARED_mount_is_not_a_site(self):
        rel = rel_for(self.ADDON)
        mounts = shipped(cls.DECLARED_MOUNTS, self.ADDON)
        mounts[(rel, TARGET)] = SEED_OWNER
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run(None, _nest(cls.DECLARED_MOUNTS, self.ADDON, mounts))
        sec = _section(out, self.ADDON)
        self.assertIn("live  %s" % rel, sec)
        self.assertNotIn("UNLISTED site(s)", sec)
        self.assertEqual(rc, 0, out)

    def test_a_DEAD_mount_is_REPORTED_and_scores_nothing(self):
        """ADR-0205 dec. 3: enforcing this direction would make DELETING a mount red the
        guard, which is backwards. So a mount pointing at a file that names nothing must
        PRINT and must not change `rc`.

        This pair — DEAD here, `live` above, over the same constructed mount — is what
        makes the rig's SEEDED row a witness (ADR-0205 dec. 7): it reads DEAD! at rc 0
        before #744 and flips to `live` after, and neither reading is asserted off the
        shipped register, so #744 landing does not expire either test."""
        rel = rel_for(self.ADDON, "_absent_mount")
        mounts = shipped(cls.DECLARED_MOUNTS, self.ADDON)
        mounts[(rel, TARGET)] = SEED_OWNER
        rc, out = _run(None, _nest(cls.DECLARED_MOUNTS, self.ADDON, mounts))
        sec = _section(out, self.ADDON)
        self.assertIn("DEAD! %s" % rel, sec)
        self.assertIn("Dead mount", sec)
        self.assertEqual(rc, 0, out)


class WhatCountsAsASiteBase:

    def test_a_site_is_a_PAIR_not_a_line(self):
        """Three lines naming one target is ONE site with three line numbers. Counting
        lines would make a formatting change move the register."""
        rel = rel_for(self.ADDON)
        rows = shipped(cls.SCENE_BURN_DOWN, self.ADDON)
        rows[(rel, TARGET)] = SEED_OWNER
        with SeedFile(rel, body_for(self.ADDON, TARGET, TARGET, TARGET)):
            rc, out = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON, rows))
            sites = cls.scan(self.ADDON)
        seeded = {k: v for k, v in sites.items() if k[0] == rel}
        self.assertEqual(list(seeded), [(rel, TARGET)], seeded)
        self.assertEqual(seeded[(rel, TARGET)]["lines"], [3, 4, 5], seeded)
        self.assertNotIn("UNLISTED site(s)", _section(out, self.ADDON))
        self.assertEqual(rc, 0, out)

    def test_two_targets_in_one_file_are_TWO_sites(self):
        rel = rel_for(self.ADDON)
        rows = shipped(cls.SCENE_BURN_DOWN, self.ADDON)
        rows[(rel, TARGET)] = SEED_OWNER
        with SeedFile(rel, body_for(self.ADDON, TARGET, OTHER)):
            rc, out = _run(_nest(cls.SCENE_BURN_DOWN, self.ADDON, rows))
        sec = _section(out, self.ADDON)
        self.assertIn("UNLISTED site(s)", sec)
        self.assertIn(OTHER, sec)
        self.assertEqual(rc, 1, out)

    def test_a_preload_in_a_gd_file_is_a_site(self):
        """ADR-0205 dec. 4 — the `.gd` path shape folds into this register. It is the
        blind spot `check_lattice_publish` names in its own docstring: `preload(...)`
        names the FILE, not the `class_name`, so criterion 1 cannot see it."""
        rel = "src/_scene_seed_%s.gd" % self.ADDON
        body = 'extends Node\n\nconst Seeded = preload("%s%s")\n' % (cls.prefix(self.ADDON), TARGET)
        with SeedFile(rel, body):
            rc, out = _run()
        sec = _section(out, self.ADDON)
        self.assertIn("UNLISTED site(s)", sec)
        self.assertIn(rel, sec)
        self.assertIn("preload()", sec)
        self.assertEqual(rc, 1, out)

    def test_tests_ENFORCE_here_unlike_criterion_1(self):
        """ADR-0205 dec. 6. ADR-0196 dec. 3 made `tests/` a REPORTING arm on criterion 1
        because `classify()` returns `None` for every test file. That reason does not
        transfer to a path, and `tests/` held 122 of the 139 sites — a reporting-only
        arm would have left 88% unscored."""
        rel = "tests/_scene_seed_%s.tscn" % self.ADDON
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run()
        sec = _section(out, self.ADDON)
        self.assertIn("UNLISTED site(s)", sec)
        self.assertIn(rel, sec)
        self.assertEqual(rc, 1, out)


class WhatIsNotASiteBase:

    def test_the_addons_OWN_files_are_not_scanned(self):
        """The exclusion FOLLOWS the subject — it is not a hardcoded string any more.
        For a subject whose folder does not exist yet this also proves the seed round
        trip leaves no directory behind (`SeedFile` removes what it created), because the
        next addon guard in the same pre-flight would red on an `addons/<x>/` with no
        `plugin.cfg` in it."""
        root = PROJECT_DIR / cls.addon_dir(self.ADDON)
        existed = root.exists()
        rel = cls.addon_dir(self.ADDON) + "_scene_seed.tscn"
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run()
        self.assertNotIn("_scene_seed.tscn", _section(out, self.ADDON))
        self.assertEqual(rc, 0, out)
        self.assertEqual(root.exists(), existed)

    def test_dot_godot_is_pruned(self):
        """The import cache is generated and mirrors real references; scanning it
        double-counts. A `lstrip("./")` — which strips CHARACTERS, not a prefix —
        silently readmitted 32 cache hits during this register's own measurement."""
        rel = ".godot/_scene_seed_%s.tscn" % self.ADDON
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run()
        self.assertNotIn("_scene_seed", _section(out, self.ADDON))
        self.assertEqual(rc, 0, out)

    def test_a_sibling_addon_is_PROBED_not_walked(self):
        """🔴 WRITTEN ASSERTING THE OPPOSITE, and the failure was the finding.
        `addons/exmateria_sound/` is a SYMLINK into `exmateria-sound/`, and
        `Path.rglob` does not recurse into one (`recurse_symlinks=False`, Python 3.13),
        so ~20 trees sit outside the walk. Following them was rejected — `assets/maps`
        is absent from a bare worktree, so the ENFORCED count would differ between two
        checkouts of the same commit. `symlink_probe()` reports instead, so the gap
        cannot go non-empty silently. It measures 0 across every tree today; this test
        makes the seeded file show up in the probe's ⚠️ line, not in arm 1."""
        rel = "addons/exmateria_sound/_scene_seed_%s.tscn" % self.ADDON
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run()
            probe = dict(cls.symlink_probe(self.ADDON))
        self.assertNotIn("UNLISTED site(s)", _section(out, self.ADDON))
        self.assertEqual(rc, 0, out)
        self.assertEqual(probe["addons/exmateria_sound"], 1)

    def test_the_symlink_probe_reports_zero_on_a_clean_tree(self):
        rc, out = _run()
        sec = _section(out, self.ADDON)
        self.assertIn("symlink probe", sec)
        self.assertIn("Files naming the prefix inside them: 0.", sec)
        self.assertNotIn("NOT on the burn-down", sec)
        self.assertEqual(rc, 0, out)

    def test_a_SIBLING_subjects_prefix_is_not_this_subjects_site(self):
        """One scanner, two prefixes. A file naming the OTHER subject's addon path is
        that subject's reach and must not appear in this one's arm 1 — the corpus
        excludes only the subject, so the file IS scanned here and simply does not
        match."""
        for other in ADDONS:
            if other == self.ADDON:
                continue
            rel = "src/_scene_seed_cross_%s.tscn" % other
            with SeedFile(rel, body_for(other, TARGET)):
                rc, out = _run()
            self.assertNotIn(rel, _section(out, self.ADDON))
            self.assertIn(rel, _section(out, other))
            self.assertEqual(rc, 1, out)


class TheOracleChannelIsReportedAndEnforcedBase:
    """ADR-0222 dec. 1. Criterion 4 split into a SCORED production channel and a REPORTED
    oracle channel, because six of the rig's seven rows could not be paid by any move and
    a burn-down that cannot reach 0 stops being read.

    🔴 A REPORTED CHANNEL IS WHERE DEBT GOES TO HIDE, so every arm below seeds the escape
    ROUTE and asserts the guard refuses it. Three of them are the three admission
    conditions; the fourth is the reason a split number is allowed to exist at all
    (the halves stay addable). Every seed CONSTRUCTS both the site and the row — not one
    reads a row off the shipped `SCENE_ORACLES`, so these still fire on the day the rig's
    six are gone."""

    def _oracles(self, rows):
        return _nest(cls.SCENE_ORACLES, self.ADDON, rows)

    def test_an_oracle_site_is_LIFTED_out_of_criterion_4_and_REPORTED(self):
        """The whole point, in one arm: the same seeded site reads as criterion-4 debt
        when it is NOT an oracle row and as arm-3 report when it is. Asserted as a PAIR
        so a guard that simply stopped scanning would fail the first half."""
        rel = oracle_rel_for(self.ADDON)
        with SeedFile(rel, oracle_body(self.ADDON, TARGET)):
            rc_debt, out_debt = _run(burn_down=_nest(
                cls.SCENE_BURN_DOWN, self.ADDON,
                {**shipped(cls.SCENE_BURN_DOWN, self.ADDON), (rel, TARGET): SEED_OWNER}))
            rc_or, out_or = _run(oracles=self._oracles(
                {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}))
        n_debt = int(re.search(r"target 0: (\d+) site", _section(out_debt, self.ADDON)).group(1))
        n_or = int(re.search(r"target 0: (\d+) site", _section(out_or, self.ADDON)).group(1))
        self.assertEqual(n_or, n_debt - 1,
                         "the oracle row must leave arm 1's count, not just print twice")
        sec = _section(out_or, self.ADDON)
        self.assertIn("arm 3 — ORACLES", sec)
        self.assertIn(rel, sec.split("arm 3 — ORACLES")[1])
        self.assertEqual((rc_debt, rc_or), (0, 0), out_or)

    def test_a_STALE_oracle_row_is_RED(self):
        """Condition 3. An oracle that stops naming the seam has stopped measuring it,
        and a row left behind would keep excusing a site nobody checks."""
        absent = oracle_rel_for(self.ADDON, "_absent")
        rows = {**shipped(cls.SCENE_ORACLES, self.ADDON), (absent, TARGET): SEED_OWNER}
        rc, out = _run(oracles=self._oracles(rows))
        sec = _section(out, self.ADDON)
        self.assertRegex(sec, r"❌ %s arm 3 — \d+ STALE oracle row" % re.escape(self.ADDON))
        self.assertIn(absent, sec)
        self.assertEqual(rc, 1, out)

    def test_an_oracle_row_NOT_under_tests_is_RED(self):
        """🔴 THE SPLIT'S OWN FAILURE MODE. Condition 1 is what stops criterion 4 being
        drained to 0 by RECLASSIFICATION — parking a production reach in the channel that
        scores nothing. The seed is a `src/` file, which is exactly the shape
        `assets/materials/unit.tres` has."""
        rel = rel_for(self.ADDON)                      # `src/…`, deliberately not `tests/`
        with SeedFile(rel, body_for(self.ADDON, TARGET)):
            rc, out = _run(oracles=self._oracles(
                {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}))
        sec = _section(out, self.ADDON)
        self.assertRegex(sec, r"❌ %s arm 3 — \d+ oracle row\(s\) NOT under"
                         % re.escape(self.ADDON))
        self.assertIn(rel, sec)
        self.assertEqual(rc, 1, out)

    def test_a_row_whose_ARGUMENT_EXPIRES_is_RED(self):
        """Condition 2, and the reason this channel is a MEASUREMENT rather than an
        assertion. A row is permanent because ADR-0194 cannot take the test into the
        addon, and the machine-checkable form of that is: the file still names a HOST
        path. The seed names the seam and no host path — an oracle that COULD move now,
        so its permanence argument is gone and the row has to be re-argued or paid."""
        rel = oracle_rel_for(self.ADDON)
        with SeedFile(rel, oracle_body(self.ADDON, TARGET, host=False)):
            rc, out = _run(oracles=self._oracles(
                {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}))
        sec = _section(out, self.ADDON)
        self.assertRegex(sec, r"❌ %s arm 3 — \d+ oracle row\(s\) whose ARGUMENT EXPIRED"
                         % re.escape(self.ADDON))
        self.assertIn(rel, sec)
        self.assertEqual(rc, 1, out)
        self.assertEqual(cls.oracle_blockers(rel), [])

    def test_the_SAME_seed_with_a_host_path_is_GREEN(self):
        """The control for the arm above — without it, `ARGUMENT EXPIRED` could be firing
        on the seeding rather than on the missing host path. Same row, same site, same
        register; the ONLY difference is the `preload` of a host script."""
        rel = oracle_rel_for(self.ADDON)
        with SeedFile(rel, oracle_body(self.ADDON, TARGET, host=True)):
            rc, out = _run(oracles=self._oracles(
                {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}))
            self.assertEqual(cls.oracle_blockers(rel), [HOST_PATH])
        self.assertNotIn("ARGUMENT EXPIRED", _section(out, self.ADDON))
        self.assertEqual(rc, 0, out)

    def test_a_host_CLASS_reach_and_NO_host_path_is_GREEN(self):
        """🔴 #871's EXACT SHAPE, and the arm the guard did not have on the day it cost a
        red trunk. A test that reaches host territory only through a bare `ClassName` is
        as unmovable as one holding `res://src/…` — Godot resolves the name through the
        global class registry and the declaring file is in `src/`. Before ADR-0222
        Amendment 2 this seed read `ARGUMENT EXPIRED`, so the two rows the tree was
        already red on could not be admitted to the channel they belong to."""
        rel = oracle_rel_for(self.ADDON)
        with SeedFile(HOST_CLASS_REL, HOST_CLASS_BODY), \
             SeedFile(rel, oracle_body(self.ADDON, TARGET, host=False, klass=HOST_CLASS)):
            rc, out = _run(oracles=self._oracles(
                {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}))
            self.assertEqual(cls.oracle_blockers(rel),
                             ["%s (%s)" % (HOST_CLASS, HOST_CLASS_REL)])
        sec = _section(out, self.ADDON)
        self.assertNotIn("ARGUMENT EXPIRED", sec)
        self.assertIn(rel, sec.split("arm 3 — ORACLES")[1])
        self.assertEqual(rc, 0, out)

    def test_the_host_class_named_only_in_PROSE_is_RED(self):
        """The control for the arm above, and the reason the class half strips comments
        while the path half does not. Same seed, same declaration, same register — the
        ONLY difference is that the name sits in a `##` line instead of in code. A
        blocker that fired on prose would let any row buy permanence with a sentence."""
        rel = oracle_rel_for(self.ADDON)
        with SeedFile(HOST_CLASS_REL, HOST_CLASS_BODY), \
             SeedFile(rel, oracle_body(self.ADDON, TARGET, host=False, klass=HOST_CLASS,
                                       in_comment=True)):
            rc, out = _run(oracles=self._oracles(
                {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}))
            self.assertEqual(cls.oracle_blockers(rel), [])
        self.assertRegex(_section(out, self.ADDON),
                         r"❌ %s arm 3 — \d+ oracle row\(s\) whose ARGUMENT EXPIRED"
                         % re.escape(self.ADDON))
        self.assertEqual(rc, 1, out)

    def test_a_class_the_ADDON_declares_is_NOT_a_blocker(self):
        """HOST is `_HOST_PATH`'s exclusion in the other spelling, and this is the half a
        widening gets wrong. A class declared INSIDE the addon travels with the addon, so
        a test reaching it can move — that reach is no argument for permanence, and
        counting it would let any addon-internal name buy a permanent row."""
        rel = oracle_rel_for(self.ADDON)
        klass = "_SceneSeedAddonClass"
        with SeedFile(addon_class_rel(self.ADDON),
                      "class_name %s\nextends Node\n" % klass), \
             SeedFile(rel, oracle_body(self.ADDON, TARGET, host=False, klass=klass)):
            rc, out = _run(oracles=self._oracles(
                {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}))
            self.assertEqual(cls.oracle_blockers(rel), [])
        self.assertRegex(_section(out, self.ADDON),
                         r"❌ %s arm 3 — \d+ oracle row\(s\) whose ARGUMENT EXPIRED"
                         % re.escape(self.ADDON))
        self.assertEqual(rc, 1, out)

    def test_a_key_in_BOTH_REGISTERS_RAISES(self):
        """Splitting one number into two is only honest while the halves stay addable. A
        key in both channels is counted twice — and a reader who adds `1 + 6` to recover
        the 7 would get a number that was never true of the tree."""
        rel = oracle_rel_for(self.ADDON)
        rows = {**shipped(cls.SCENE_ORACLES, self.ADDON), (rel, TARGET): SEED_OWNER}
        burn = {**shipped(cls.SCENE_BURN_DOWN, self.ADDON), (rel, TARGET): SEED_OWNER}
        with self.assertRaises(SystemExit) as e:
            _run(burn_down=_nest(cls.SCENE_BURN_DOWN, self.ADDON, burn),
                 oracles=self._oracles(rows))
        self.assertIn("BOTH SCENE_BURN_DOWN and SCENE_ORACLES", str(e.exception))
        self.assertIn(rel, str(e.exception))


# ---------------------------------------------------------------------------
# Tree-wide arms — one subject apiece would say nothing.
# ---------------------------------------------------------------------------

class TheAxisIsNamed(unittest.TestCase):

    def test_the_output_says_axis_A_and_names_axis_B_as_a_different_number(self):
        """ADR-0202 dec. 1 forbids reporting either axis as the other, and ADR-0205's
        whole correction is that this population was being called the INSTALL term."""
        rc, out = _run()
        self.assertIn("AXIS A", out)
        self.assertIn("check_addon_install", out)
        self.assertIn("NOT the install term", out)
        self.assertEqual(rc, 0, out)

    def test_the_summary_reports_EVERY_subject_separately(self):
        """One addon at 0 and another carrying debt are two readings, not an average."""
        rc, out = _run()
        tail = out[out.rindex("criterion 4 per addon"):]
        for addon in ADDONS:
            self.assertRegex(tail, r"%s \d+" % re.escape(addon))
        self.assertEqual(rc, 0, out)

    def test_the_summary_prints_the_SIZE_of_each_register_not_its_rc(self):
        """\U0001f534 THIS ARM USED TO ASSERT THE DEFECT. It demanded `<addon> 0` for every
        subject, which the old summary satisfied by rendering `report()`'s rc — 0 for a
        fully-NAMED register of any size. So it passed all through #745 while the sprite
        rig's register held ELEVEN rows and the line read `exmateria_sprite_rig 0`, and
        its own docstring above ("another carrying debt") described a state it forbade.

        Criterion 4 is the SIZE and its target is 0 (ADR-0205 dec. 3); rc is the HYGIENE
        question, whether a row is unlisted or stale. The summary must carry the size, so
        the number a reader quotes out of the last line is the criterion itself."""
        rc, out = _run()
        tail = out[out.rindex("criterion 4 per addon"):]
        for addon in ADDONS:
            n = len(cls.SCENE_BURN_DOWN[addon])
            self.assertIn("%s %d" % (addon, n), tail)
        # and a green rc must not be readable as "criterion 4 met" on its own
        self.assertIn("NOT the criterion being met", tail)
        self.assertEqual(rc, 0, out)

    def test_the_summary_prints_BOTH_channels_and_NEVER_sums_them(self):
        """🔴 ADR-0222 dec. 3, and the arm that makes the split honest rather than a way
        to buy a number. The rig read 7 before the split and 1 after with NOT ONE LINE OF
        THE TREE MOVED, so the summary has to carry the oracle term — otherwise the
        sentence a reader quotes says a drop happened that never did (ADR-0205 dec. 7).

        Asserted as `n (+m oracle, k mount)` per addon AND as the SUM being absent, because
        a line that printed `7` would satisfy any test that only looked for both digits."""
        rc, out = _run()
        tail = out[out.rindex("criterion 4 per addon"):]
        for addon in ADDONS:
            n, m = len(cls.SCENE_BURN_DOWN[addon]), len(cls.SCENE_ORACLES[addon])
            k = len(cls.DECLARED_MOUNTS[addon])
            self.assertIn("%s %d (+%d oracle, %d mount)" % (addon, n, m, k), tail)
        self.assertIn("NEVER added", tail)
        self.assertIn("ADR-0205 dec. 7", tail)
        self.assertEqual(rc, 0, out)

    def test_the_summary_prints_the_MOUNT_term_so_an_EXEMPTION_cannot_read_as_a_DRAIN(self):
        """🔴 ADR-0222 dec. 6, and the same medicine dec. 3 gave the oracle term.

        A mount is subtracted from the scored set before either channel is consulted, so
        the FIRST number — criterion 4 itself — can reach 0 because a row was EXEMPTED
        rather than because a reach was removed. The rig's did: its last production row
        could not be drained and became its second mount, with not one line of the tree
        moving. Without this term the sentence a reader quotes out of the last line is
        identical to the one they would quote if the reach had actually gone.

        Driven on a CONSTRUCTED exemption, not on the shipped registers, so it keeps
        saying this after the shipped mounts change: every live site declared, an empty
        burn-down, and the resulting `0` must still be printed beside a non-zero mount
        count. The control is the same run's OTHER subject, whose own term is its own."""
        addon = ADDONS[-1]
        covered = all_live_sites_declared(addon)
        rc, out = _run(_nest(cls.SCENE_BURN_DOWN, addon, {}),
                       _nest(cls.DECLARED_MOUNTS, addon, covered),
                       _nest(cls.SCENE_ORACLES, addon, {}))
        tail = out[out.rindex("criterion 4 per addon"):]
        self.assertIn("%s 0 (+0 oracle, %d mount)" % (addon, len(covered)), tail)
        self.assertGreater(len(covered), 0, "the constructed state exempts nothing")
        self.assertIn("subtracted before either channel", tail)
        self.assertIn("NOT that", tail)
        # the verdict block says it too, one level down from the summary
        self.assertIn("site(s) are DECLARED MOUNTS (arm 2), subtracted before this",
                      _section(out, addon))
        self.assertEqual(rc, 0, out)


class TheRegistersCoverTheMapping(unittest.TestCase):
    """Widening a hardcoded subject into a mapping introduces a way to be silently wrong
    that the old shape could not have: a subject with no row in a register. `main()`
    RAISES on that rather than reporting it, because a missing row is a `KeyError` at the
    first use and an extra row is a register nobody grades."""

    def test_every_subject_has_a_row_in_BOTH_registers(self):
        for reg in (cls.DECLARED_MOUNTS, cls.SCENE_BURN_DOWN, cls.SCENE_ORACLES):
            self.assertEqual(sorted(reg), ADDONS)

    def test_a_MISSING_row_raises(self):
        rows = {a: dict(cls.SCENE_BURN_DOWN[a]) for a in ADDONS[1:]}
        with self.assertRaises(SystemExit) as e:
            _run(rows)
        self.assertIn(ADDONS[0], str(e.exception))

    def test_an_EXTRA_row_raises(self):
        rows = {a: dict(cls.SCENE_BURN_DOWN[a]) for a in ADDONS}
        rows["exmateria_not_a_subject"] = {}
        with self.assertRaises(SystemExit) as e:
            _run(rows)
        self.assertIn("exmateria_not_a_subject", str(e.exception))


class TheWideningDidNotMoveBattlefield(unittest.TestCase):
    """ADR-0217 dec. 4 widened the subject; Battlefield's reading is ASSERTED unchanged,
    not assumed. The numbers pinned here are the ones the guard printed on `origin/main`
    immediately before the widening."""

    A = "exmateria_battlefield"

    def test_battlefields_arm_1_still_reads_zero_over_three_declared_files(self):
        """🔴 THE `file(s)` TERM MOVED 3 -> 4 -> 5 AND CRITERION 4 DID NOT MOVE AT ALL,
        which is the distinction ADR-0205 dec. 7 exists to keep visible. `file(s)` counts
        every file holding a SITE — mounts, oracles and production together — so admitting
        `MapDitherSnapTest`'s two rows to arm 3 (#871, ADR-0222 Amendment 2) raised it by
        one while arm 1's own number stayed 0, and `ShadowFoldOrderTest`'s single row
        (#1075) raised it by one again on the same terms. Both halves are asserted here so
        a future reader cannot mistake either for the other: the day arm 1 leaves 0, this
        fails on the number that IS criterion 4, not on the file count beside it."""
        rc, out = _run()
        sec = _section(out, self.A)
        self.assertIn("arm 1 — PRODUCTION, ENFORCING, target 0: 0 site(s) over 5 "
                      "file(s), 3 declared.", sec)
        self.assertIn("3 oracle site(s) are reported by arm 3", sec)
        self.assertIn("✅ %s CRITERION 4 IS 0" % self.A, sec)
        self.assertEqual(rc, 0, out)

    def test_battlefields_three_mounts_are_all_LIVE_and_unchanged(self):
        rows = cls.DECLARED_MOUNTS[self.A]
        self.assertEqual(sorted(rows), [
            ("assets/scenes/CombatCamera.tscn", "camera/PlayerCamera.tscn"),
            ("assets/scenes/CombatCursor.tscn", "cursor/TileCursor.tscn"),
            ("assets/scenes/ProceduralMap.tscn", "assembly/MapComposer.gd"),
        ])
        rc, out = _run()
        sec = _section(out, self.A)
        for rel, target in rows:
            self.assertIn("live  %s → %s" % (rel, target), sec)
        self.assertNotIn("DEAD!", sec)
        self.assertEqual(rc, 0, out)

    def test_the_corpus_excludes_ONLY_the_subject(self):
        """Tree-independent, deliberately: hardcoding `2325 file(s)` would red on any
        commit that adds a `.gd`, and a bare worktree scores a different absolute number
        for the same commit (the symlink probe's whole reason). What must hold is the
        RELATIONSHIP — the exclusion FOLLOWS the subject and drops nothing else.

        🔴 WRITTEN BACKWARDS THE FIRST TIME and the failure was the finding: the rig's
        corpus is 71 files LARGER than Battlefield's, not smaller. Each subject excludes
        its own addon and no other, so the rig — whose folder does not exist yet —
        scans Battlefield's 71 files and Battlefield does not. A sibling addon naming a
        path into this one is a REAL reach; hiding every addon from every scan would put
        it in a hole instead of on a burn-down."""
        for x in ADDONS:
            fx = {p.relative_to(cls.ROOT).as_posix() for p in cls.corpus(x)}
            self.assertFalse({r for r in fx if r.startswith(cls.addon_dir(x))},
                             "%s scans its own addon" % x)
            for y in ADDONS:
                if x == y:
                    continue
                fy = {p.relative_to(cls.ROOT).as_posix() for p in cls.corpus(y)}
                self.assertTrue(all(r.startswith(cls.addon_dir(y)) for r in fx - fy),
                                "%s drops files that are not %s's" % (y, y))

    def test_ONE_walk_serves_every_subject(self):
        """The widening made the walk linear in the number of subjects until `entries()`
        was threaded through; a pre-flight guard paying that twice for a report nobody
        reads twice is a regression with no reader. Asserted as an IDENTITY — a shared
        listing gives each subject exactly the corpus its own walk would."""
        listing = cls.entries()
        for addon in ADDONS:
            self.assertEqual(cls.corpus(addon, listing), cls.corpus(addon))
        counts = cls.symlink_counts(listing)
        for addon in ADDONS:
            self.assertEqual(cls.symlink_probe(addon, counts), cls.symlink_probe(addon))

    def test_entries_is_the_pruned_rglob(self):
        """`entries()` prunes `SKIP_DIRS` AT THE WALK instead of walking in and dropping
        the results afterwards. That is a claim about what is MISSING from a listing, and
        the failure it invites is the one this file exists to catch: a prune that takes
        too much leaves every consumer scoring a smaller tree and reporting the same
        clean number, because a guard that stopped LOOKING and a guard that found nothing
        print identically.

        So the equality is asserted against a LIVE `rglob` — the pre-prune walk, run here
        and not remembered — rather than against a stored count. `.godot/` alone is ~69%
        of the raw listing, so an off-by-one in the prune predicate is not a rounding
        error, it is most of the tree.

        Order is asserted too, not just membership: `report()` prints rows in listing
        order and the burn-down registers are diffed as text.

        ALL parts, not `parts[:-1]`. The consumers spell their own filter over the
        DIRECTORY parts, which keeps the pruned directory's OWN entry (`.godot` itself)
        and then drops it a step later on `is_file()`. The walk cannot hand back an entry
        it never descended into, so it omits that one path too — a difference of exactly
        one non-file entry, which is why the guard's report is byte-identical across the
        change. Pinning it here means a future reader meets the discrepancy as a stated
        contract rather than as a mystery in a diff."""
        got = cls.entries()
        raw = sorted(cls.ROOT.rglob("*"))
        want = [q for q in raw
                if not any(part in cls.SKIP_DIRS
                           for part in q.relative_to(cls.ROOT).parts)]
        self.assertEqual(got, want,
                         "entries() is no longer the SKIP_DIRS-pruned rglob — it dropped "
                         "%d paths the raw walk keeps and invented %d it does not"
                         % (len(set(want) - set(got)), len(set(got) - set(want))))
        self.assertLess(len(got), len(raw),
                        "the prune removed NOTHING (%d == %d) — either SKIP_DIRS stopped "
                        "matching or the walk stopped pruning; both make this arm's "
                        "equality vacuous" % (len(got), len(raw)))


class TheRigsRowIsSeeded(unittest.TestCase):
    """ADR-0217 dec. 3/4. The rig's registers are seeded BEFORE the move, so P9's
    prediction — this addon's criterion 4 opens at exactly one site and that site is the
    mount, never a burn-down row — has something to be measured against.

    None of this asserts DEAD-ness. `#744` landing the move flips the row to `live` and
    must not turn a test red: the DEAD→live pair is proved on CONSTRUCTED mounts in
    `TheDeclaredMountIsReportedNotScored`, which is the seventh time in this repo a
    control has been written so success cannot expire it."""

    A = "exmateria_sprite_rig"

    def test_P9s_FALSIFICATION_SURVIVES_the_BURN_DOWN_EMPTYING(self):
        """🔴 THIS ARM ASSERTED `SCENE_BURN_DOWN[rig]` WAS NON-EMPTY, and that was the
        right assertion for exactly two days. P9 predicted the rig's criterion 4 would open
        at ONE site — the `Unit.tscn` mount — and never a burn-down row. #744 landed and it
        opened at EIGHT rows beside the mount, so the register held the finding and the old
        docstring said flipping it back to `assertEqual(..., {})` would delete it.

        The burn-down is empty again now, and NOT because P9 came true. Six rows went to
        `SCENE_ORACLES` (ADR-0222 dec. 1) and the seventh became a SECOND DECLARED MOUNT
        once the drain ADR-0222 P1 predicted was measured and refused (ADR-0222 dec. 4):
        a shader-less `ShaderMaterial` drops all 39 authored `shader_parameter/` values at
        parse time. Re-pointing this arm at "the burn-down is non-empty" would now delete
        the finding the way flipping it to `{}` would have then, because the finding never
        was a property of that one dict.

        So it asserts the finding itself, ACROSS all three registers: seven rows exist that
        P9 said would not, wherever they currently live. The TOTAL is pinned even though
        the per-register split is not, because the hazard this whole file watches for is a
        row leaving one register without arriving in another (ADR-0205 dec. 7)."""
        # `Unit.tscn` is the one site P9 DID predict; everything else is its falsification.
        p9 = ("assets/scenes/Unit.tscn", "UnitRig.tscn")
        mounts = cls.DECLARED_MOUNTS[self.A]
        self.assertIn(p9, mounts)
        found = {**cls.SCENE_ORACLES[self.A], **cls.SCENE_BURN_DOWN[self.A],
                 **{k: v for k, v in mounts.items() if k != p9}}
        self.assertEqual(len(found), 7, sorted(found))
        for (rel, target), (owner, why) in found.items():
            self.assertTrue(rel and target, (rel, target))
            self.assertRegex(owner, r"#744|ADR-0222", (rel, target, owner))
            self.assertGreater(len(why), 60, (rel, target, why))

    def test_the_SPLIT_and_the_EXEMPTION_left_ZERO_production_rows_and_SIX_oracles(self):
        """🔴 ADR-0222's own before/after, pinned so the number cannot move by accident.

        The rig's criterion 4 read SEVEN and could not reach 0: six rows were host tests
        naming the seam to measure it, and neither test can move into the addon because
        both reach `src/` (ADR-0194). The split booked them in the channel that scores
        nothing and left criterion 4 at the ONE production reach —
        `assets/materials/unit.tres`, which ADR-0222 P1 predicted would DRAIN.

        ⚠️ IT DID NOT DRAIN. It was MEASURED and refused (Amendment 1), and it is a
        declared mount now — so criterion 4 reads 0 without one line of the tree moving,
        for the second time in three days. That is why this arm asserts the mount rather
        than just the empty burn-down: `burn == {}` alone is satisfied by the row silently
        disappearing, which is the exact failure ADR-0205 dec. 7 names.

        The 6 is pinned because it must NOT move without a decision — an oracle row
        arriving silently is the escape route this whole channel is watched for."""
        burn = cls.SCENE_BURN_DOWN[self.A]
        oracles = cls.SCENE_ORACLES[self.A]
        self.assertEqual(burn, {}, sorted(burn))
        self.assertIn(("assets/materials/unit.tres", "render/unit.gdshader"),
                      cls.DECLARED_MOUNTS[self.A])
        self.assertEqual(len(oracles), 6, sorted(oracles))
        self.assertTrue(all(r.startswith("tests/") for r, _ in oracles), sorted(oracles))
        self.assertEqual(len(set(burn) & set(oracles)), 0)

    def test_every_oracle_row_is_STILL_BLOCKED_from_moving_into_the_addon(self):
        """The permanence claim, MEASURED against the tree rather than read off the row's
        prose. ADR-0194 takes a test into the addon when it can run without the game;
        naming a host path is what says it cannot. If this ever goes empty the row is not
        permanent any more and arm 3 reds — this asserts the same fact one level up, so
        the failure names the ROW rather than arriving as a report line."""
        for rel, target in cls.SCENE_ORACLES[self.A]:
            self.assertTrue(cls.oracle_blockers(rel), (rel, target))

    def test_every_oracle_row_has_a_dated_owner_and_a_reason(self):
        """Same shape the burn-down's rows are held to. A channel that scores nothing is
        exactly where an undated, unreasoned row would survive longest."""
        for (rel, target), (owner, why) in cls.SCENE_ORACLES[self.A].items():
            self.assertIn("#744", owner)
            self.assertIn("ARGUED PERMANENT", owner)
            self.assertGreater(len(why), 60, (rel, target, why))

    def test_every_oracle_row_names_a_file_that_EXISTS(self):
        for rel, _ in cls.SCENE_ORACLES[self.A]:
            self.assertTrue((PROJECT_DIR / rel).is_file(), rel)

    def test_every_burn_down_row_names_a_file_that_EXISTS(self):
        """The sibling of `test_the_host_scene_the_mount_names_EXISTS`. A row whose file
        is gone goes STALE and reds arm 1 loudly, so this is not the same check — it
        catches the typo BEFORE the register runs, where the message names the key."""
        for rel, _ in cls.SCENE_BURN_DOWN[self.A]:
            self.assertTrue((PROJECT_DIR / rel).is_file(), rel)

    def test_TWO_declared_mounts_each_with_an_owner_and_a_reason(self):
        """The second one is the exemption, and it is held to the SAME bar as the first:
        an owner naming the decision and a reason long enough to be one. A mount is the
        only escape hatch from arm 1, so an undocumented one is how a reach stops being
        counted without anybody agreeing to it."""
        rows = cls.DECLARED_MOUNTS[self.A]
        self.assertEqual(sorted(rows), [
            ("assets/materials/unit.tres", "render/unit.gdshader"),
            ("assets/scenes/Unit.tscn", "UnitRig.tscn"),
        ])
        for (rel, target), (owner, why) in rows.items():
            self.assertTrue(target)
            self.assertRegex(owner, r"ADR-02(17|22)", (rel, owner))
            self.assertGreater(len(why), 80, why)

    def test_the_EXEMPTIONS_reason_carries_the_MEASUREMENT_not_an_argument(self):
        """🔴 THE ONLY THING SEPARATING THIS MOUNT FROM PARKING A ROW WHERE IT STOPS
        BEING COUNTED is that the drain was measured and refused rather than argued away.
        `tools/probe_unitres_shader_drain.gd` authored a shader-less copy and read it back:
        39 of 39 `shader_parameter/` values null before the injection AND after it, because
        `ShaderMaterial::_set` is guarded by `shader.is_valid()`. So the row's note has to
        carry the numbers and the mechanism — an exemption whose reason is a paraphrase is
        indistinguishable from a filter with extra words (#424)."""
        _, why = cls.DECLARED_MOUNTS[self.A][
            ("assets/materials/unit.tres", "render/unit.gdshader")]
        for token in ("39", "shader.is_valid()", "probe_unitres_shader_drain",
                      "EXEMPTION", "ADR-0205 dec. 7"):
            self.assertIn(token, why, token)

    def test_the_host_scene_the_mount_names_EXISTS(self):
        """A mount may be dead; the FILE it is declared on may not be missing. That is
        the difference between "the reach has not landed yet" and a typo."""
        for rel, _ in cls.DECLARED_MOUNTS[self.A]:
            self.assertTrue((PROJECT_DIR / rel).is_file(), rel)


class TheBlindSpotThatCostATrunkRed(unittest.TestCase):
    """#871, pinned. `check_lattice_scene` was rc 1 on `main` for two days over two rows
    in `tests/MapDitherSnapTest.gd`, and the pre-flight is a GATE, so it aborted the full
    suite on every branch cut from trunk — one session spent 390 s and ran zero test
    scenes.

    🔴 THE ROWS COULD NOT BE ADMITTED BY THE GUARD AS IT STOOD. The issue's own reading —
    *"it looks like an oracle, so put it on arm 3"* — was refuted by the instrument:
    `oracle_blockers()` read `[]` for this file, so condition 2 said ADR-0194 could take
    the test into the addon and the new row would have red on arrival under `ARGUMENT
    EXPIRED`. The judgement was right and the PREDICATE was wrong.

    This class asserts the two facts that made it so, against the real tree, so that the
    day either changes the failure names the file rather than arriving as a report line.
    ⚠️ It is deliberately NOT parametrized: it is about one file, and a per-subject twin
    would assert the rig has a row it does not have."""

    A = "exmateria_battlefield"
    REL = "tests/MapDitherSnapTest.gd"

    def test_the_file_holds_NO_host_res_path_at_all(self):
        """The blind spot, stated as a measurement. If this ever goes non-empty the
        widening stops being load-bearing FOR THIS FILE — which is worth knowing, and is
        not the same as the widening being wrong."""
        text = (PROJECT_DIR / self.REL).read_text(encoding="utf-8")
        self.assertEqual([m.group(0) for m in cls._HOST_PATH.finditer(text)], [])

    def test_and_it_is_STILL_BLOCKED_from_moving_into_the_addon(self):
        """By the second spelling alone. `MapRenderDebugPanel` is a host debug panel the
        test INSTANTIATES — arm 8 grades the panel by what it emits — and a stranger rig
        has no host, so ADR-0194 cannot take this test into `exmateria_battlefield`."""
        blockers = cls.oracle_blockers(self.REL)
        self.assertTrue(blockers, "the permanence argument for #871's rows is gone")
        self.assertTrue(all("res://" not in b for b in blockers), blockers)

    def test_both_rows_are_on_arm_3_and_criterion_4_is_still_ZERO(self):
        """The whole point of the split, on the row that motivated Amendment 2: the two
        sites are REPORTED and criterion 4 does not move. Booking them on the burn-down
        instead would have taken Battlefield's criterion 4 off the 0 ADR-0209 closed — for
        a TEST — which is the reclassification-in-reverse ADR-0222 dec. 1 exists to stop."""
        rows = [k for k in cls.SCENE_ORACLES[self.A] if k[0] == self.REL]
        self.assertEqual(len(rows), 2, sorted(cls.SCENE_ORACLES[self.A]))
        self.assertEqual(cls.SCENE_BURN_DOWN[self.A], {})
        rc, out = _run()
        sec = _section(out, self.A)
        self.assertIn("arm 1 — PRODUCTION, ENFORCING, target 0: 0 site(s)", sec)
        self.assertIn("3 oracle site(s) are reported by arm 3", sec)
        self.assertEqual(rc, 0, out)

    def test_both_rows_carry_a_dated_owner_naming_the_ticket_and_a_reason(self):
        """Scoped to THIS file's rows. It used to walk the whole channel and assert
        `#871` on every row, which passed only while #871 was the only admission —
        i.e. it was asserting the channel's SIZE in the shape of a per-row claim, and
        the next true row (#1075's) failed it for being new rather than for being
        wrong. The channel-size claim belongs to the two counted assertions above."""
        rows = {k: v for k, v in cls.SCENE_ORACLES[self.A].items() if k[0] == self.REL}
        self.assertEqual(len(rows), 2, sorted(cls.SCENE_ORACLES[self.A]))
        for (rel, target), (owner, why) in rows.items():
            self.assertIn("#871", owner, (rel, target))
            self.assertIn("ARGUED PERMANENT", owner, (rel, target))
            self.assertGreater(len(why), 60, (rel, target, why))


_PARAMETRIZED = (BothDirectionsFailBase, TheVerdictIsPerSubjectBase,
                 TheDeclaredMountIsReportedNotScoredBase, WhatCountsAsASiteBase,
                 WhatIsNotASiteBase, TheOracleChannelIsReportedAndEnforcedBase)

for _base in _PARAMETRIZED:
    for _addon in ADDONS:
        _name = "%s__%s" % (_base.__name__.removesuffix("Base"), _addon)
        globals()[_name] = type(_name, (_base, unittest.TestCase), {"ADDON": _addon})
del _base, _addon, _name


if __name__ == "__main__":
    unittest.main()
