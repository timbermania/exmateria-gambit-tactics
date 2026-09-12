"""Seed-red tests for every arm of the goal-#5 portability net -- 1, 2, 2b, 3, 4, 4b, 5, 6, 7.

ADR-0169 dec. 5 specifies both arms; ADR-0171 dec. 5 widens arm 4's subject. An arm
that has never been seen to FIRE is indistinguishable from an arm that cannot fire, and
this guard's own history is the argument: it shipped green across an entire extraction
because it stopped looking (see `check_addon_portability.py`, "WHY THIS GUARD WAS GREEN
WHILE BOTH WERE TRUE"). So every arm below is asserted in both directions — a seed that
must be reported, and a control that must not.

The two subtle ones, both of which were live defects during the build:

  1. ARM 4's CPU SIDE SURVIVES STRIPPING. The pushed global's name is a STRING LITERAL,
     and arm 2's `strip_noncode` blanks string literals. Built on it, arm 4 read
     `PSXDisplay.gd`'s five pushes as `&""` and reported nothing —
     `test_push_survives_comment_stripping` is that regression.
  2. NEITHER ARM MAY MATCH ITS OWN DOCUMENTATION. `effect_fold_add.gdshader` says
     "global uniform" in a `//` comment, `ot_depth.gdshaderinc:11` spells a
     `#include` in one, and `PSXDisplay.gd:54-55` discusses
     `global_shader_parameter_set` in a `##` doc comment. All three are prose and a raw
     grep reports all three.

The clean-tree arms share ONE walk: `walk_addons`'s output is a fact about the
tree, `report_walk` applies the burn-downs, and `_clean_walk()` below caches the
fact per tree state — 13 arms used to re-walk the ~19.5 s whole tree each
(docs/PREFLIGHT-TIMING.tsv, 2026-09-07: this step was 253 s, 73.5% of the
pre-flight). The seeded arms still walk fresh: the cache key IS the tree, so a
seed invalidates it, and a wrong hit would red the test — not make the guard
green, which still walks on every plain run. `test_the_real_walk_is_green_and_is
_not_green_by_silence` still drives the shipped script end to end in a SUBPROCESS,
because a helper that fires while nothing routes it to the exit code is still a
green guard — that arm keeps the `__main__` wiring alive for the rest.

Run from tools/:
    uv run python -m unittest test_check_addon_portability
"""

from __future__ import annotations

import contextlib
import os
import re
import subprocess
import sys
import tempfile
import unittest
import hashlib
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent

## The PERMITTED cross-addon `class_name` census: every line on which a portable addon
## names the kernel or the platform port, which is exactly what ADR-0139 dec. 9 + dec. 12
## allow it to name. It is a LIVE COUNT of the tree, so it moves whenever anybody adds a
## legitimate `TunePort.` / `DisplayPort.` / `ExMateriaSchema.` line — +2 most recently for
## `camera.handoff_ease_seconds`' `bind` and `on_update` (#1168), then +18 for #1180's
## kernel lift. RE-READ FROM THE GUARD'S OWN REPORT after rebasing #1180 onto a main that
## had moved 78 commits: 426, not the 424 the branch measured pre-rebase. Two legitimate
## lines landed in between; keeping the branch's number would have been a fabrication.
##
## 🔴 IT IS THE ONLY LITERAL. This used to be five of them — 406 three times, 438 and 442 —
## plus two arithmetic restatements, and every one of them redded on any legitimate line
## anywhere in the walk. That is a treadmill, not a guard: the thing the mutation arms
## actually prove is the DELTA (32 lines cross over, 36 stop being debt), and a delta does
## not care what the base is. So the base is named once here and the arms are deltas off
## `_permitted()`, which reads the number back out of the report. Bump this when the census
## legitimately moves; if an arm below reds, the DELTA broke and that is a real finding.
##
## 🔴 426 -> 504 AT #1225, THE LARGEST SINGLE MOVE THIS CONSTANT HAS SEEN, AND THE DEBT
## SIDE MOVED WITH IT FOR THE FIRST TIME SINCE #1180 — 13 -> 23. Extraction #7 put
## `addons/exmateria_effects` in the walk (64 members, 14,498 lines), and 78 of its lines
## name the kernel or the port — `ExMateriaSchema.Fold` / `.ColorStack` / `.DepthMode`,
## `ExMateriaPlatform.PsxMagnitude` / `.CameraCalibration` / `.PsxChirality` — which is
## what ADR-0139 dec. 9/12 permit, so they arrive FREE. The ten that are debt are
## ADR-0288 dec. 8's table minus one row: `MapIlluminationDDA` 4, `FoldSurface` 3,
## `Lattice` 2 — dec. 8's `ExMateriaSound.FedsBank` line was re-spelled as a PATH to that
## package's façade in the same pass, because #1241's arm 8 is unconditional and the
## `deps=` route raises on a package that declares no `engine=`. An addon joining the walk is the one event
## that moves this census by a large number legitimately, and it has now happened six
## times.
##
## 🔴 504 -> 513 AT #1218, AND THIS ONE IS THE CENSUS DOING ITS JOB RATHER THAN A
## MOVE. #1218 wrote `addons/exmateria_effects/install/EffectsDebug.gd` to take 61
## `DebugConfig` reads out of that addon, and the seam it reads them through is
## `ExMateriaPlatform.TunePort` — one alias `const` plus four `bind`s and four
## `get_value`s. Nine lines, every one exactly what ADR-0139 dec. 12 permits, so they
## arrive FREE and the debt side does not move: arm 1 went 67 -> 6 in the same commit.
## A severance that pays a system reach by naming the PORT is supposed to read as
## +permitted / -debt, and this is the first time both halves moved in one ticket.
##
## 🔴 513 -> 509 AT #1224, AND A DROP IN THIS CENSUS IS THE RARE DIRECTION. #1224
## deleted `addons/exmateria_effects/overlay/MapTintOverlay.gd`, folding it into
## `TintedSurfaces` as the reserved `SURFACE_MAP` token, and its four
## `ExMateriaSchema.ColorStack` lines went with it — the alias `const` plus three use
## sites. The surviving file already named the same kernel type, so the merge removed
## four PERMITTED lines and added none. Worth stating because every prior move of this
## constant was upward: an addon joining the walk, or a severance routed through the
## port. This is the first time the number fell because two files became one.
##
## \U0001f534 509 -> 508 AT #658's COMMIT, AND IT FELL FOR A BUG FIX. `EffectsDebug`'s four
## readers each named `TunePort.get_value` on its own line; they now delegate to one
## `_read()` helper that guards the pull-read with `TunePort.is_registered` and re-`bind`s.
## Four PERMITTED lines became three, net -1. The helper exists because #1218 shipped a
## static-only tunable owner WITHOUT the lazy re-declaration `DebugConfig._dbg_get` always
## had, and `Tune.reset()` clears the registry — 19 tunable tests went THREW on
## `debug.particle_debug_enabled` and only the first full-suite run of the sequence saw it.
##
## \U0001f534 508 -> 517 AT #1249, AND THE +9 IS THE COST OF ROUTE 2 RATHER THAN NEW DEBT.
## Moving seven host tests INTO `addons/exmateria_effects/tests/` (ADR-0194) puts them
## under this walk, so the `ExMateriaSchema` / `ExMateriaEffects` names they already used
## become cross-addon `class_name` lines. Every one is the kernel or the addon's own
## facade, which ADR-0139 dec. 9/12 permit, so they arrive FREE — and criterion 4 fell
## 61 -> 52 for them. A register that scores the addon root will always read a move INTO
## the root as growth; the question is whether the growth is permitted, and here it is.
## 🟢 THE DEBT SIDE FELL 22 -> 18 AT #1192 (2026-09-12), the rarer half of this
## pair to move. The four lines were `PaletteSubsystem` naming
## `ExMateriaBattlefield.MapIlluminationDDA` for the Holy/E015 additive map flood.
## ADR-0288 dec. 8 predicted this exact drop from this exact deletion, and it took a RUN
## to authorise it — 2 probe hits in the unit test as a positive control, 0 across eight
## battle scenes — because ADR-0208 dec. 5 had refused the counter argument alone. The
## free side is untouched: debt LEFT, it was not re-spelt as permitted.
PERMITTED = 517

## The guard prints the census in exactly one shape; the arms read it back rather than
## re-asserting a literal, so "did it move by 32" is a subtraction and not two constants.
_CENSUS_RE = re.compile(r"cross-addon class_name — (\d+) line\(s\)")


def _permitted(out: str) -> int:
    m = _CENSUS_RE.search(out)
    assert m is not None, "the guard stopped printing the census line:\n%s" % out[:2000]
    return int(m.group(1))

sys.path.insert(0, str(TOOLS_DIR))

# CHDIR BEFORE THE IMPORT, and it is not optional. Importing the guard loads
# `score_goals`, which `exec`s `classify_blueprint.py`, which WALKS RELATIVE PATHS —
# from `tools/` it walks nothing and dies dividing by zero. `main()` does this same
# chdir for the same reason; a test that skips it never reaches the first assertion.
os.chdir(PROJECT_DIR)

import check_addon_portability as cap


# --- ONE WALK, MANY ARMS -----------------------------------------------------
# This file's pre-flight cost (docs/PREFLIGHT-TIMING.tsv, 2026-09-07) was 13 of
# its 69 arms each re-running the ~19.5 s whole-tree walk on a tree that does
# not change between them. The walk's output is a fact about the tree; the
# burn-downs are claims about the walk. `cap.walk_addons()` / `cap.report_walk()`
# is that split, and the cache below is what makes the arms share the walk.
#
# ⚠️ THE CACHE IS KEYED ON THE TREE, NOT ON THE ARM. Any arm that SEEDS the tree
# (`test_an_unlisted_reach_is_still_RED` writes a file under an addon root) gets
# a FRESH walk, because the seed moves the signature below. The cache lives here,
# in the test, and not in the guard: a wrong hit REDs this test and cannot make
# the guard green — the guard still walks the whole tree on every plain run.
_WALK_CACHE: dict[str, dict] = {}


def _tree_signature() -> str:
    """Everything `walk_addons` reads, stat'd: every file under every walk root
    and extracted root, the host `project.godot` (arm 2 reads its autoload
    block), and the tool modules that decide the walk (root membership, the
    classifier). A content change moves an mtime, so the signature moves. The
    error direction is re-walking, which is what a stale walk would do anyway.
    """
    h = hashlib.sha256()
    roots = list(cap._sg._walk_roots.addon_roots())
    for row in cap._sg._walk_roots.extracted_roots():
        roots.append(row.path)
    for r in roots:
        for q in sorted(r.rglob("*")):
            if q.is_file():
                st = q.stat()
                h.update(("%s|%d|%d\n" % (q, st.st_size, st.st_mtime_ns)).encode())
    for p in (PROJECT_DIR / "project.godot", TOOLS_DIR / "_walk_roots.py",
              TOOLS_DIR / "score_goals.py", TOOLS_DIR / "classify_blueprint.py"):
        st = p.stat()
        h.update(("%s|%d|%d\n" % (p, st.st_size, st.st_mtime_ns)).encode())
    return h.hexdigest()


def _clean_walk() -> dict:
    """The full-walk result for the tree as it is NOW, shared across the arms."""
    sig = _tree_signature()
    w = _WALK_CACHE.get(sig)
    if w is None:
        roots, gone = cap.full_roots()
        w = cap.walk_addons(roots, None, gone)
        _WALK_CACHE[sig] = w
    return w


def _redeclare_dep_row(w: dict, rel: str, deps=None, subject_engine=None,
                       closure_engine=None) -> dict:
    """The shared walk with ONE subject's arm-8 `dep_rows` entry re-declared (#1241).

    `report_walk`'s split, used the way `Arm1BurnDownTests` uses the burn-downs: the
    walk's output is a fact about the tree and the declaration is a claim about it, so
    a seeded declaration re-scores the SAME walk instead of buying a second ~19.5 s one.
    The row is DERIVED from the real row rather than written out, so a change to
    `walk_addons`' row shape breaks the callers loudly instead of leaving them scoring
    a shape the guard no longer produces.
    """
    out = dict(w)
    rows, seen = [], False
    for row in w["dep_rows"]:
        if row[0] == rel:
            seen = True
            r = list(row)
            if subject_engine is not None:
                r[1] = subject_engine
            if closure_engine is not None:
                r[2] = closure_engine
            if deps is not None:
                r[3] = deps
                # The measured map carries a 0 for a declared dep nothing reaches,
                # which is how `walk_addons` builds it.
                r[5] = {"addons/" + d: 0 for d in deps} | {
                    h: n for h, n in r[5].items() if n}
            row = tuple(r)
        rows.append(row)
    assert seen, "no arm-8 dep row for %s to re-declare" % rel
    out["dep_rows"] = rows
    return out


def _clean_report() -> tuple:
    """`main()`'s full-walk `(rc, stdout)`, on the shared walk, unseeded lists."""
    import contextlib, io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = cap.report_walk(_clean_walk())
    return rc, buf.getvalue()


def _a_host_class_name() -> tuple[str, str]:
    """`(name, rel)` for a `class_name` the real tree declares OUTSIDE every addon root.

    Resolved at run time on purpose. This test hard-coded `JsonAsset` at
    `src/data/JsonAsset.gd` until #809 moved that file into
    `addons/exmateria_platform/` — which turned the SEED into the CONTROL below: the
    arm correctly went green and the test failed for the one reason a seed-red test
    must never fail, which is the tree moving under it rather than the arm breaking.
    Derived, it cannot rot the same way. This is `refactor-loop.md`'s extraction-#1
    lesson — *ask, per guard, whether the thing that used to watch a moved file still
    does* — asked of a test instead of a guard.
    """
    for q in sorted((PROJECT_DIR / "src").rglob("*.gd")):
        m = re.search(r"^class_name\s+([A-Za-z0-9_]+)", q.read_text(errors="ignore"), re.M)
        if not m:
            continue
        rel = q.relative_to(PROJECT_DIR).as_posix()
        # \U0001f534 NOT ONE OF THE ELEVEN. A `class_name` whose file classifies into a
        # system is arm 1's row as well as arm 7's, and a seed that fires two arms
        # cannot say which one it tested. `JsonAsset` was `infrastructure`, which is
        # why the hardcoded seed only ever printed arm 7's line; the first host
        # `class_name` under `src/` alphabetically is `CatalogueReplay`, which is
        # `Character Catalogue`'s and fires both. Arm 1's own test for that set is
        # `_system_of(...) is None`, and this is the same question asked of a file.
        if cap._sg.classify(rel) in cap._sg.SYSTEMS:
            continue
        return m.group(1), rel
    raise AssertionError("the host declares no system-free `class_name` under src/ — "
                         "arm 7 has no subject that arm 1 would leave alone")


def _pkg(root: Path, globals_block: str = "") -> Path:
    """A scratch PACKAGE — its own `project.godot` plus one addon root under it.

    Its own project is what makes arms 3 and 4 ENFORCING rather than reporting:
    `package_project` returns non-None, which is the same switch that makes
    `exmateria-sound/` red and the in-walk addons debt.
    """
    (root / "project.godot").write_text("[shader_globals]\n\n" + globals_block, encoding="utf-8")
    addon = root / "addons" / "seedaddon"
    addon.mkdir(parents=True)
    return addon


_wr = cap._sg._walk_roots


class TierDeclarationTests(unittest.TestCase):
    """The addon TIER — declared in `plugin.cfg`, read by arms 1, 2b, 4b and 5 (#1059).

    All four arms used to spell their question `system_of[addon] is None`, over a
    value derived from the modal `classify()` bucket of the addon's own files. That
    is a proxy for tier membership and the guard's own comment said so; `classify()`
    books a file to the system that CONSUMES it (ADR-0243 dec. 3), so a package of
    tables inherits the names of its readers. It agreed with the intent for exactly
    as long as the only non-system addons were the two FREE ones.

    Two directions, and the second is the one a count would miss:

      1. `exmateria_almanac` votes `Battle` and is not Battle's — seven of the
         eleven reach it and its top two consumers are 3.4% apart.
      2. Both EXTRACTED roots vote `None` for every source file they hold, because
         they are outside `classify_blueprint`'s walk. `None` is the FREE set. The
         only thing between that and a free verdict is `_walk_roots.EXTRACTED`
         naming two paths by hand — the vote has never answered this question for a
         package it was not told about.

    🔴 THE VERDICT DID NOT MOVE, AND THAT IS THE CLAIM. Declaring what was inferred
    re-prices nothing: the shipped report is byte-identical across this change
    (354 free rows, 55 debt rows, rc=0). What moves is that the answer is now a
    declaration a reader can check, and `rules` — the fourth tier — is stated to be
    OUTSIDE the free set rather than accidentally inside one of the other three.
    Pricing it is #1059 phase 2 and `test_freeing_the_rules_tier_is_worth_...`
    below says what it is worth.
    """

    ALMANAC = PROJECT_DIR / "addons" / "exmateria_almanac"
    SEED = ALMANAC / "_tier_arm1_seed.gd"

    def _cfg(self, root: Path, body: str) -> Path:
        addon = root / "addons" / "seedaddon"
        addon.mkdir(parents=True)
        (addon / "plugin.cfg").write_text(body, encoding="utf-8")
        return addon

    def _report(self, walk=None):
        import contextlib, io
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = cap.report_walk(_clean_walk() if walk is None else walk)
        finally:
            os.chdir(PROJECT_DIR)
        return rc, buf.getvalue()

    def _vote(self, addon: Path):
        """The derivation the declaration replaces, run here so the two can be diffed.

        Deliberately a COPY of the four lines `_system_of` used to be rather than a
        call into the guard: the guard no longer performs it for a non-system tier,
        so a test that asked the guard would be asking the answer it is testing.
        """
        import collections
        buckets = collections.Counter(
            cap._sg.classify(cap._sg._rel(q))
            for q in addon.rglob("*")
            if q.is_file() and q.suffix in cap._sg.SOURCE_SUFFIXES)
        return next((b for b, _ in buckets.most_common() if b in cap._sg.SYSTEMS), None)

    # --- the reader, in both directions -------------------------------------

    def test_each_of_the_four_tiers_is_read_back(self):
        for tier in _wr.TIERS:
            with self.subTest(tier=tier):
                with tempfile.TemporaryDirectory() as d:
                    addon = self._cfg(Path(d), '[plugin]\nname="x"\ntier="%s"\n' % tier)
                    self.assertEqual(_wr.declared_tier(addon), tier)

    def test_a_plugin_cfg_with_no_tier_RAISES(self):
        """The whole point of the declaration. A default would be one of the four
        answers chosen silently, and three of the four move an enforcing verdict."""
        with tempfile.TemporaryDirectory() as d:
            addon = self._cfg(Path(d), '[plugin]\nname="x"\nengine="stock"\n')
            with self.assertRaises(ValueError) as e:
                _wr.declared_tier(addon)
            self.assertIn("declares no `tier=`", str(e.exception))

    def test_a_tier_outside_the_four_RAISES(self):
        with tempfile.TemporaryDirectory() as d:
            addon = self._cfg(Path(d), '[plugin]\nname="x"\ntier="feature"\n')
            with self.assertRaises(ValueError) as e:
                _wr.declared_tier(addon)
            self.assertIn("not one of", str(e.exception))

    def test_a_root_with_no_plugin_cfg_RAISES(self):
        """`check_lattice_scene`'s own regression, one directory up: a leftover addon
        root with no `plugin.cfg` in it must fail loudly rather than score as a
        default."""
        with tempfile.TemporaryDirectory() as d:
            addon = Path(d) / "addons" / "seedaddon"
            addon.mkdir(parents=True)
            with self.assertRaises(FileNotFoundError):
                _wr.declared_tier(addon)

    def test_a_COMMENTED_tier_is_not_a_declaration(self):
        """This file's standing rule — no arm may match its own documentation — asked
        of the reader. `plugin.cfg`'s comment char is `;`, and every tier in this
        repo ships under six to forty lines of `;` prose that NAME the four tiers."""
        for body in ('[plugin]\n; tier="port"\n',
                     '[plugin]\n;tier="port"\n',
                     '[plugin]\n; one of `kernel port system rules`\n'):
            with self.subTest(body=body):
                with tempfile.TemporaryDirectory() as d:
                    addon = self._cfg(Path(d), body)
                    with self.assertRaises(ValueError):
                        _wr.declared_tier(addon)

    # --- the real tree ------------------------------------------------------

    def test_every_root_the_guards_walk_declares_a_tier(self):
        """Coverage, over the JOIN of the two root populations rather than over one.

        `addon_roots()` and `EXTRACTED` are declared in different files and only one
        of them ever had an answer to this question. Asking `tiers()` for the union
        is what makes an addon added to either list fail here rather than be scored
        by a default that no longer exists."""
        t = _wr.tiers()
        expected = ({r.resolve() for r in _wr.addon_roots()}
                    | {e.path.resolve() for e in _wr.extracted_roots()})
        self.assertEqual(set(t), expected)
        # LIVENESS, three legs. An empty map, a map of one, or a map whose values
        # are all the same string would pass every agreement arm below while saying
        # nothing — the shape `test_the_platform_port_may_declare` was vacuous in.
        self.assertGreaterEqual(len(t), 7, "the walk holds fewer roots than this "
                                           "repo has addons — the subject moved")
        self.assertTrue(set(t.values()) <= set(_wr.TIERS), t)
        self.assertGreaterEqual(len(set(t.values())), 3,
                                "every root declares the SAME tier, so no arm below "
                                "is distinguishing anything: %r" % t)

    def test_the_free_set_is_the_kernel_and_the_port_and_nothing_else(self):
        """Arm 5's free set, read off the declarations. The count is not the claim —
        the MEMBERSHIP is, because the failure this guards against is a third package
        joining the free set without anyone deciding that it should."""
        t = _wr.tiers()
        self.assertEqual(_wr.PORTABLE_TIERS, frozenset({"kernel", "port"}))
        self.assertEqual(sorted(p.name for p, v in t.items() if v in _wr.PORTABLE_TIERS),
                         ["exmateria_platform", "exmateria_schema"])
        self.assertEqual(t[(PROJECT_DIR / "addons" / "exmateria_schema").resolve()], "kernel")
        self.assertEqual(t[(PROJECT_DIR / "addons" / "exmateria_platform").resolve()], "port")

    def test_the_vote_and_the_declaration_diverge_for_the_ALMANAC_and_agree_elsewhere(self):
        """The measurement #1059 is built on, taken here so it cannot rot silently.

        The vote is not merely absent for the almanac — it is CONFIDENT AND WRONG,
        which is why the fix is a declaration rather than a tie-break. Asserted in
        both directions: it still says `Battle` (so the divergence is live, not a
        classifier that has stopped answering), and it still agrees with the declared
        tier for every other in-walk root (so ONE addon needed a decision, not nine).
        """
        self.assertEqual(self._vote(self.ALMANAC), "Battle",
                         "the vote no longer says Battle — either `classify` moved or "
                         "the almanac's population did, and #1059's argument is stated "
                         "against a tree that no longer exists")
        self.assertEqual(_wr.declared_tier(self.ALMANAC), "rules")
        for root in _wr.addon_roots():
            if root.resolve() == self.ALMANAC.resolve():
                continue
            with self.subTest(addon=root.name):
                self.assertEqual(self._vote(root) is not None,
                                 _wr.declared_tier(root) == "system",
                                 "%s: the vote and the declaration disagree, and only "
                                 "the almanac is supposed to" % root.name)

    def test_the_almanac_has_no_system_NAME_and_is_still_arm_1s_SUBJECT(self):
        """🔴 THE REGRESSION THIS CHANGE COULD HAVE SHIPPED, seeded.

        `system_of[exmateria_almanac]` was `Battle` and is now `None`, because
        `rules` is not one of the eleven. Arm 1's gate used to read `if system is
        None: continue` — left as it was, this change would have taken a whole addon
        OUT of arm 1's subject, and an arm going quiet over a package reads exactly
        like a package with nothing to report. That is this guard's own founding
        defect (`check_addon_portability.py`, "WHY THIS GUARD WAS GREEN WHILE BOTH
        WERE TRUE"), and only the two FREE tiers are outside arm 1's subject.

        So: assert the name is gone, and seed a real cross-system reach into the real
        addon and require arm 1 to still report it. `Unit` is a host `class_name`
        under `src/units/` that `classify` books to `Battle`.
        """
        self.assertNotEqual(_wr.declared_tier(self.ALMANAC), "system",
                            "the almanac declares a system tier, so it HAS a name and "
                            "this arm is no longer testing the case it was written for")
        self.assertFalse(self.SEED.exists(), "a previous run leaked its seed file")
        self.SEED.write_text("extends Node\n\n\nfunc f(u: Unit) -> void:\n\tprint(u)\n",
                             encoding="utf-8")
        try:
            rc, out = self._report()
        finally:
            self.SEED.unlink()
        self.assertIn("PORTABILITY: ", out)
        self.assertIn("_tier_arm1_seed.gd", out)
        self.assertIn("Battle.Unit", out.split("PORTABILITY: ", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_the_seed_is_what_reddens_arm_1_and_not_the_tree(self):
        """The other half of the seed. Named to sort AFTER it, so a leaked file fails
        here rather than making the seed's red look structural."""
        self.assertFalse(self.SEED.exists(), "the seed test leaked its file")
        rc, out = self._report()
        self.assertNotIn("PORTABILITY: ", out)
        self.assertEqual(rc, 0, out)

    def test_freeing_the_rules_tier_leaves_exactly_the_EFFECTS_rows(self):
        """What `rules` being outside the free set COSTS, measured rather than argued.

        The pricing arm. Today the almanac is not free, so `exmateria_catalogue`
        naming its symbols is arm 5 DEBT — 53 lines, accepted by ADR-0262 dec. 5.
        Widening `PORTABLE_TIERS` to hold `rules` moves them into the free block.
        This is #1059 phase 2's whole decision expressed as a diff, and a future
        change that silently frees the tier fails here instead of arriving as a
        smaller number nobody looked at.

        🔴 THE PRICE AND THE REMAINDER BOTH MOVED AT #1071 (ADR-0272), AND THE
        REMAINDER MOVED TO ZERO. This arm was written against 55 debt lines leaving
        2 — the `exmateria_sprite_rig` row, named here as #1071's. #1071 paid that
        row by deleting the key it produced, and its two lines WERE arm 1's row: the
        alias and the call it fed. So the price is 53, every remaining row is the
        almanac's, and freeing the tier does not SHRINK the block — the block stops
        existing, heading and all. That is a stronger phase-2 result than the one
        this test was written to price, and the assertion says so directly rather
        than checking a smaller count: `assertNotIn` on the heading cannot pass for
        a block that merely got quieter.

        ADR-0262 dec. 5, its table at `:126` and ADR-0267's soft-spot note all still
        read 55. They are accepted ADRs and are not edited; the correction lives in
        ADR-0272's consequences and the number to quote is 53.

        🔴 RE-PRICED AGAIN AT #1059 PHASE 2 (ADR-0273), AND THE BASELINE IS NOW
        406 / 36 RATHER THAN 354 / 53. Phase 2 did NOT take the wholesale branch
        this arm prices — it split free-ness by declared MEMBER KIND, so the 17
        `table` lines (`JobDatabase`, `SpriteDatabase`) moved into the free block
        and the 36 that remained were the two `state` members. This arm therefore
        keeps its whole job: it prices the alternative ADR-0271 REJECTED and
        ADR-0273 rejected again, and a future change that quietly adds `rules` to
        `PORTABLE_TIERS` still fails here rather than arriving as a smaller number.
        The two readings of the same debt block are unchanged in shape: the heading
        stops existing, and the free block rises by exactly the debt count.

        ⚠ THE FREE SIDE WENT 371 -> 373 AT #1120 AND THE DEBT SIDE DID NOT MOVE.
        ADR-0273 measured 371; `ShopAvailabilityDatabase` landed afterwards and its
        own two `ExMateriaPlatform.JsonAsset` lines (`:27,46`) are the whole delta —
        A/B'd by removing the file, which reads 371, and restoring it, which reads
        373, with 36 debt in both arms. A port reach is what ADR-0139 dec. 9/12
        permits and every sibling `*Database` in that addon already has one, so this
        is the free block doing its job, not a debt increase wearing a free heading.

        ⚠ AND 373 -> 408 AT #1159, ALSO WITH THE DEBT SIDE UNMOVED. `UnitRole` left
        the almanac for the kernel (ADR-0280 dec. 3), so `Gambit.gd`,
        `TargetSelector.gd` and `JobDatabase.gd` name a SIBLING's `class_name` where
        they used to name a path inside their own root — three rows, thirty-five
        LINES, since this arm counts lines and `TargetSelector.gd` alone names it
        eleven times. Reaches INTO the kernel are exactly what ADR-0202 dec. 2 rules
        free, so the free side rising is the extraction working; the number that
        would say otherwise is the 36 beside it.

        ⚠ AND 408 -> 406 AT #1160, DEBT SIDE STILL UNMOVED. ADR-0280 dec. 4 moved
        the gambit's English out of the almanac to `src/ui3/GambitProse.gd`, and
        `Gambit.gd:179,180` went with it — two lines that named
        `ExMateriaSchema.UnitRole` inside the prose helpers. A/B'd on the block
        itself: `check_addon_portability.py`'s free listing on `main` and on this
        branch differ in exactly one row, `Gambit.gd:26,179,180` becoming
        `Gambit.gd:26`, and in nothing else. The lines did not stop existing —
        `src/` is not walked, so a reach that leaves an addon for the game leaves
        this census entirely. That is the free side FALLING for the same reason it
        rose at #1159: fewer addon lines, not fewer dependencies.

        ⚠ AND 408 -> 426 AT #1180, AND THIS IS THE FIRST TIME THE DEBT SIDE HAS
        MOVED SINCE ADR-0273 — 36 -> 13. ADR-0294 dec. 2 lifted `EquipSlot`,
        `BaseStatType` and `Zodiac` out of `UnitProgression` into the shared kernel
        as ADR-0118 dec. 1's TWELFTH row, and 23 of the catalogue's 36 lines named
        one of those three rather than a progression record.

        🔴 THE FREE SIDE ROSE BY 18 WHERE THE DEBT SIDE FELL BY 23, AND THE TWO
        NUMBERS ARE NOT SUPPOSED TO MATCH. Three separate effects, all of them the
        instrument working:
          · an ALIAS COLLAPSES LINES. This arm counts lines that NAME a foreign
            symbol. Sixteen `UnitProgression.EquipSlot.*` lines in
            `Character.gd` became sixteen bare `EquipSlot.*` lines plus ONE alias
            line naming `ExMateriaSchema.EquipSlot` — so 16 debt lines leave and 1
            free line arrives. Nothing was dropped; the spelling stopped repeating
            the package.
          · `UnitBirthdays.gd` LEFT THE CENSUS' ALMANAC SIDE ENTIRELY. Its only
            non-alias line was the `zodiac_from_birthday` call, so its alias went
            with it — 2 debt lines out, 2 free lines in against a different home.
          · `EquipCandidates.gd` IS A GENUINELY NEW PRINT of 5 lines. It used to
            `preload` `items/EquipSlot.gd` from inside its OWN root, which is in
            neither block; the same read now crosses into the kernel. A new free
            row that was in no block before is arm 5 becoming able to SEE an
            install-time dependency it previously could not, which is what the free
            block is for.

        The row asserted before and after is now `UnitProgression`, not
        `JobDatabase`: `JobDatabase` is free on BOTH sides after phase 2, so it can
        no longer witness that the rows moved rather than being dropped.

        ⚠ AND 426 -> 504 AT #1225, WITH THE DEBT SIDE 13 -> 23 — THE FIRST TIME BOTH
        SIDES HAVE MOVED IN ONE COMMIT, AND THE FIRST TIME THIS ARM'S RESULT HAS
        CHANGED SHAPE. Extraction #7 put `addons/exmateria_effects` in the walk. 78 of
        its lines name the kernel or the port and arrive FREE; ten are debt and none of
        them is the `rules` tier — `ExMateriaBattlefield.MapIlluminationDDA` 4,
        `ExMateriaRender.FoldSurface` 3, `ExMateriaBattlefield.Lattice` 2,
        `ExMateriaSound.FedsBank` 1, which is ADR-0288 dec. 8's table row for row.
        \U0001f7e2 THE `MapIlluminationDDA` 4 ARE GONE SINCE #1192 and the arm now asserts
        their ABSENCE; ADR-0288 dec. 8 predicted that deletion in the same table it
        predicted the rows. So
        widening `PORTABLE_TIERS` no longer takes the heading away: it moves the
        almanac's 13 and leaves the effects' 10, and THIS TEST WAS RENAMED rather than
        re-pinned, because `…_to_ZERO` asserting 10 would be a name that lies. The two
        readings that matter are unchanged — the free block rises by exactly the debt
        that moved, and every row that leaves is named.

        The patched walk is FRESH rather than `_clean_walk()`'s: the free set is
        read inside `walk_addons`, so scoring a cached walk would test nothing.
        """
        rc, out = self._report()
        self.assertEqual(rc, 0, out)
        self.assertIn("cross-addon class_name DEBT — 18 line(s)", out)
        self.assertIn("cross-addon class_name — %d line(s)" % PERMITTED, out)
        self.assertIn("ExMateriaAlmanac.UnitProgression -> declared in addons/exmateria_almanac",
                      out)

        original = _wr.PORTABLE_TIERS
        _wr.PORTABLE_TIERS = frozenset(original | {"rules"})
        try:
            roots, gone = cap.full_roots()
            widened = cap.walk_addons(roots, None, gone)
        finally:
            _wr.PORTABLE_TIERS = original
            os.chdir(PROJECT_DIR)
        rc2, out2 = self._report(widened)
        self.assertEqual(rc2, 0, out2)
        # The block SHRINKS to exactly extraction #7's rows. It used to stop existing,
        # and the assertion was `assertNotIn` on the heading for that reason; since
        # #1225 there IS a second population behind the almanac's, so the arm names it
        # instead — a `assertNotIn` here would now be asserting that `Effects` has no
        # sibling debt, which is false and is somebody else's ticket (#1192/#1193).
        # 9 -> 5 at #1192: freeing the rules tier now leaves only Lattice x2 +
        # FoldSurface x3. The four MapIlluminationDDA lines that used to be here are the
        # deletion, not a re-spelling — arm 5 Effects->Battlefield reads 2, was 6.
        self.assertIn("cross-addon class_name DEBT — 5 line(s)", out2)
        self.assertNotIn("ExMateriaAlmanac.UnitProgression -> declared in addons/exmateria_almanac",
                         out2.partition("cross-addon class_name DEBT")[2])
        for row in ("ExMateriaRender.FoldSurface", "ExMateriaBattlefield.Lattice"):
            self.assertIn(row, out2.partition("cross-addon class_name DEBT")[2])
        # \U0001f7e2 AND THE ROW THAT LEFT IS ASSERTED GONE, not merely dropped from the list
        # above. `ExMateriaBattlefield.MapIlluminationDDA` was the third Effects row until
        # #1192 deleted the machinery that named it; asserting its ABSENCE is what stops
        # this arm from silently passing if the deletion were reverted without the register
        # following. Removing the name from a `for` tuple would have tested nothing.
        self.assertNotIn("ExMateriaBattlefield.MapIlluminationDDA", out2)
        # And the control for the control: the rows did not vanish, they MOVED into
        # the free block, whose count goes up by exactly the debt count. Two
        # readings of the same 13 that would not agree if the rows had been dropped.
        self.assertEqual(_permitted(out2) - _permitted(out), 13,
                         "widening PORTABLE_TIERS must move all 13 debt lines into the "
                         "free block and no others")
        self.assertIn("ExMateriaAlmanac.UnitProgression -> declared in addons/exmateria_almanac",
                      out2)
        # 🔴 AND THE PART THAT MAKES THIS AN ALTERNATIVE RATHER THAN A SMALLER
        # NUMBER: the TOTAL is the same either way — the delta asserted just above is
        # the whole difference. The wholesale branch and the member-kind branch agree
        # on every row's existence and disagree only on which block it is printed in,
        # so the whole decision is what the guard stays able to SAY — 13 lines of
        # per-playthrough state naming a `rules` package — and never a count of
        # dependencies discovered or lost.


class UnitProgressionVocabularyTests(unittest.TestCase):
    """#1180 / ADR-0294 — the twelfth schema row, and the one way it can rot silently.

    ADR-0294 dec. 2 moved `EquipSlot`, `BaseStatType` and `Zodiac` out of
    `progression/UnitProgression.gd` into the shared kernel, and dec. 3 had the member
    RE-EXPORT all three so no call site was respelled. That re-export is load-bearing
    for ~33 `src/` lines and every `tests/` site, and **nothing in the tree was looking
    at it** — which is this class.

    🔴 ARM 5's DEBT COUNT IS BLIND TO THE RE-EXPORT BREAKING, AND THE FREE COUNT MOVES
    THE WRONG WAY. Seeded live on `e75a05a26` by replacing dec. 3's two alias lines with
    `enum BaseStatType { MALE, FEMALE, MONSTER }` — a divergent inline copy that every
    `UnitProgression.BaseStatType.*` site would silently bind to — and running
    `check_addon_portability.py`:

        baseline   424 free / 13 debt, rc 0
        seeded     422 free / 13 debt, rc 0

    The DEBT side, which is the number ADR-0294 quotes and four arms above pin, does not
    move at all. Arm 5 counts lines that name a sibling `class_name`, and a defect that
    *stops* naming one is invisible to it by construction — that is arm 5 answering the
    question it was built for, not an arm-5 defect.

    ⚠ THE FOUR CENSUS ARMS DO RED ON THAT SEED, AND THAT IS NOT THE SAME AS SEEING IT.
    Measured rather than assumed: the seed reds five tests, four of them the free-side
    literal (`'cross-addon class_name — 424 line(s)' not found in …`) against a ~9 KB
    report, naming no subject and pointing at no file. They red because 424 is PINNED,
    so they would red identically for eighteen unrelated lines moving — and the movement
    they report is DOWNWARD, which a reader re-pinning a census scores as the extraction
    working. The fifth is `test_UnitProgression_resolves_all_three_to_the_KERNEL` below,
    which fails `(name='BaseStatType')` and says which binding broke. A literal pin that
    reds for any reason is not an instrument for this one.

    The ordinal seed is the clean case: `MALE = 0` collided onto `FEMALE`'s `1` reds
    EXACTLY ONE test of the 108 in this file, and it is the one below.

    🔴 AND THE ORDINALS ARE STORED DATA, WHICH NOTHING ELSE GUARDS AT ALL.
    `@export var base_stat_type: BaseStatType` and `@export var zodiac: int` write these
    enums' INTEGERS into every saved `UnitProgression` on disk, so a re-order re-reads
    every unit already saved as a different sex or a different sign. Seeded on the same
    commit by colliding `MALE = 0` onto `FEMALE`'s `1`: **424 / 13, rc 0, every census
    arm still green** — arm 5 sees
    nothing, and GDScript sees nothing either, because duplicate enum values are legal.
    The Godot suite does not catch it either: it constructs fresh objects, and a fresh
    object round-trips whatever ordinal it was built with.

    `EquipSlot.Slot` is deliberately NOT pinned, and the asymmetry is asserted rather
    than left to chance. `var equipment` is a plain `var`, and `Character.gd` serialises
    it to `weapon_id` / `shield_id` / `helm_id` / `body_id` / `accessory_id` — by NAME.
    No `EquipSlot` ordinal reaches disk, so spelling them out would claim a constraint
    that does not exist.

    Every seed below is applied to the source TEXT, never to the shipped file. This runs
    in a tree shared with ~28 other worktrees and a crashing test that had edited
    `UnitProgression.gd` in place would break all of them — the same reason
    `MemberKindTests` patches the READER rather than the FILE.
    """

    ALMANAC = PROJECT_DIR / "addons" / "exmateria_almanac"
    SCHEMA = PROJECT_DIR / "addons" / "exmateria_schema"
    UNIT_PROGRESSION = ALMANAC / "progression" / "UnitProgression.gd"
    VOCAB = SCHEMA / "unit_vocabulary"

    # (name as `UnitProgression` spells it, kernel file, the enum inside it)
    MEMBERS = (
        ("EquipSlot", "EquipSlot", "Slot"),
        ("BaseStatType", "BaseStatType", "Type"),
        ("Zodiac", "Zodiac", "Sign"),
    )

    # ADR-0294 soft spot 1. The subject is DERIVED — an enum is pinned iff an `@export`
    # field is typed with it — so the list cannot drift away from its own reason.
    PINNED = {
        "BaseStatType": {"MALE": 0, "FEMALE": 1, "MONSTER": 2},
        "Zodiac": {"ARIES": 0, "TAURUS": 1, "GEMINI": 2, "CANCER": 3, "LEO": 4,
                   "VIRGO": 5, "LIBRA": 6, "SCORPIO": 7, "SAGITTARIUS": 8,
                   "CAPRICORN": 9, "AQUARIUS": 10, "PISCES": 11, "SERPENTARIUS": 12},
    }

    # --- the readers, kept pure so a seed is a string and never a file ------

    @staticmethod
    def _resolve(text: str) -> dict:
        """name -> ("kernel", member, enum) | ("inline",), read from source alone.

        Dec. 3's idiom is two-step, because each kernel member is a FILE holding an
        ENUM: `const EquipSlotVocab = ExMateriaSchema.EquipSlot` then
        `const EquipSlot = EquipSlotVocab.Slot`. Both hops are required — a name bound
        to the file rather than to the enum inside it does not compile at the use site.
        """
        vocab, out = {}, {}
        for raw in text.splitlines():
            line = raw.strip()
            m = re.match(r"const (\w+) = ExMateriaSchema\.(\w+)$", line)
            if m:
                vocab[m.group(1)] = m.group(2)
                continue
            m = re.match(r"const (\w+) = (\w+)\.(\w+)$", line)
            if m and m.group(2) in vocab:
                out[m.group(1)] = ("kernel", vocab[m.group(2)], m.group(3))
                continue
            m = re.match(r"enum (\w+)\b", line)
            if m:
                out[m.group(1)] = ("inline",)
        return out

    @staticmethod
    def _ordinals(text: str, enum_name: str):
        """member -> int | None for one enum body. None means the value is IMPLICIT."""
        m = re.search(r"^enum %s\s*\{(.*?)\}" % re.escape(enum_name), text,
                      re.S | re.M)
        if m is None:
            return None
        out = {}
        for entry in m.group(1).split(","):
            entry = re.sub(r"#.*", "", entry).strip()
            if not entry:
                continue
            k, _, v = entry.partition("=")
            out[k.strip()] = int(v.strip()) if v.strip() else None
        return out

    def _source(self, path: Path) -> str:
        return path.read_text(encoding="utf-8")

    # --- the re-export, in both directions ----------------------------------

    def test_UnitProgression_resolves_all_three_to_the_KERNEL(self):
        """Dec. 3, on the shipped file. The alias is the whole reason `src/` was not
        touched, so it is asserted where the rot would land rather than at a use site."""
        got = self._resolve(self._source(self.UNIT_PROGRESSION))
        for name, member, enum in self.MEMBERS:
            with self.subTest(name=name):
                self.assertEqual(got.get(name), ("kernel", member, enum))

    def test_a_re_inlined_enum_is_REPORTED(self):
        """The seed, and the defect it stands for is not hypothetical: an inline copy
        beside a live kernel member is exactly the state ADR-0294 dec. 2 moved OUT of,
        and re-creating it binds every use site to the copy with no error anywhere."""
        seeded = self._source(self.UNIT_PROGRESSION).replace(
            "const BaseStatTypeVocab = ExMateriaSchema.BaseStatType\n"
            "const BaseStatType = BaseStatTypeVocab.Type",
            "enum BaseStatType { MALE, FEMALE, MONSTER }")
        self.assertIn("enum BaseStatType", seeded, "the seed did not apply")
        got = self._resolve(seeded)
        self.assertEqual(got.get("BaseStatType"), ("inline",))
        # The CONTROL for the seed: the other two are untouched, so a red here is the
        # one member that was seeded and never the reader having stopped reading.
        self.assertEqual(got.get("EquipSlot"), ("kernel", "EquipSlot", "Slot"))
        self.assertEqual(got.get("Zodiac"), ("kernel", "Zodiac", "Sign"))

    def test_a_HALF_alias_that_stops_at_the_file_is_REPORTED(self):
        """The subtler seed. `const Zodiac = ExMateriaSchema.Zodiac` looks finished and
        binds the FILE, not the enum, so `Zodiac.ARIES` fails at every use site rather
        than here. One hop is not the idiom; two is."""
        seeded = self._source(self.UNIT_PROGRESSION).replace(
            "const ZodiacVocab = ExMateriaSchema.Zodiac\n"
            "const Zodiac = ZodiacVocab.Sign",
            "const Zodiac = ExMateriaSchema.Zodiac")
        self.assertNotIn("ZodiacVocab", seeded, "the seed did not apply")
        self.assertIsNone(self._resolve(seeded).get("Zodiac"))

    def test_the_kernel_files_declare_the_enums_the_alias_names(self):
        """The other end of the same edge. The alias could be right and the kernel file
        renamed, and the two halves are read from different files on purpose."""
        for _, member, enum in self.MEMBERS:
            with self.subTest(member=member):
                path = self.VOCAB / ("%s.gd" % member)
                self.assertTrue(path.is_file(), "%s is not in the kernel" % member)
                self.assertIsNotNone(
                    self._ordinals(self._source(path), enum),
                    "%s.gd declares no `enum %s`" % (member, enum))

    # --- the stored ordinals, in both directions ----------------------------

    def test_every_EXPORTED_ordinal_is_spelled_out_and_pinned(self):
        """ADR-0294 soft spot 1. These integers are on disk in saved Resources, so the
        pin is a data-format pin and not a style rule."""
        for member, expected in self.PINNED.items():
            with self.subTest(member=member):
                enum = dict(self.MEMBERS and
                            [(m, e) for _, m, e in self.MEMBERS])[member]
                got = self._ordinals(self._source(self.VOCAB / ("%s.gd" % member)), enum)
                self.assertEqual(got, expected)

    def test_the_subject_is_DERIVED_from_which_fields_are_exported(self):
        """A hand-kept list of pinned enums would rot the day a fourth is added. The
        list is checked against its own reason instead: `UnitProgression` `@export`s a
        field typed with `BaseStatType` and one initialised from `Zodiac`, and it
        `@export`s nothing typed with `EquipSlot`."""
        src = self._source(self.UNIT_PROGRESSION)
        exported = set()
        for name, _, _ in self.MEMBERS:
            if re.search(r"^@export var \w+\s*:[^=\n]*\b%s\b" % name, src, re.M) or \
               re.search(r"^@export var \w+[^=\n]*=\s*%s\." % name, src, re.M):
                exported.add(name)
        self.assertEqual(exported, set(self.PINNED))

    def test_a_collided_ordinal_is_REPORTED(self):
        """The seed. Duplicate enum values are LEGAL GDScript, so this is the only
        instrument in the tree that fires on it — measured: arm 5 reads 424 / 13 rc 0
        with the collision in place, unchanged from baseline."""
        seeded = self._source(self.VOCAB / "BaseStatType.gd").replace(
            "MALE = 0,", "MALE = 1,")
        got = self._ordinals(seeded, "Type")
        self.assertEqual(got, {"MALE": 1, "FEMALE": 1, "MONSTER": 2})
        self.assertNotEqual(got, self.PINNED["BaseStatType"])

    def test_a_dropped_ordinal_is_REPORTED(self):
        """The other seed. An implicit value is not wrong TODAY — it happens to equal
        the explicit one — and it is reported anyway, because what is being pinned is
        that the number was WRITTEN DOWN, not that it currently matches."""
        seeded = self._source(self.VOCAB / "Zodiac.gd").replace(
            "SERPENTARIUS = 12,", "SERPENTARIUS,")
        got = self._ordinals(seeded, "Sign")
        self.assertIsNone(got["SERPENTARIUS"])
        self.assertNotEqual(got, self.PINNED["Zodiac"])

    def test_EquipSlot_is_NOT_pinned_and_that_is_the_control(self):
        """The asymmetry, asserted rather than left to chance. No `EquipSlot` ordinal
        reaches disk — `var equipment` is a plain `var` and `Character.gd` serialises it
        by NAME to `weapon_id` / `shield_id` / `helm_id` / `body_id` / `accessory_id`.
        Pinning it would claim a constraint that does not exist, and this test is what
        makes the two pins above a finding rather than a habit."""
        got = self._ordinals(self._source(self.VOCAB / "EquipSlot.gd"), "Slot")
        self.assertEqual(set(got), {"RIGHT_HAND", "LEFT_HAND", "HEAD", "BODY",
                                    "ACCESSORY"})
        self.assertEqual(set(got.values()), {None})
        self.assertNotIn("EquipSlot", self.PINNED)

    # --- the live instrument, so the blindness above is a real zero ---------

    def test_arm_5_DOES_see_the_three_members_which_is_why_its_zero_is_readable(self):
        """The positive control for the two blindness measurements in the docstring.
        A census that never named these members would give the same 13 for the wrong
        reason. It names all three, on the FREE side, which is ADR-0202 dec. 2 putting
        the kernel in the install target."""
        rc, out = self._report()
        self.assertEqual(rc, 0, out)
        free, _, debt = out.partition("cross-addon class_name DEBT")
        for _, member, _ in self.MEMBERS:
            with self.subTest(member=member):
                self.assertIn("ExMateriaSchema.%s -> declared in addons/exmateria_schema"
                              % member, free)
                self.assertNotIn("ExMateriaSchema.%s" % member, debt)

    def _report(self):
        import contextlib, io
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = cap.report_walk(_clean_walk())
        finally:
            os.chdir(PROJECT_DIR)
        return rc, buf.getvalue()


class MemberKindTests(unittest.TestCase):
    """#1059 phase 2 — arm 5's free set inside the `rules` tier, per MEMBER.

    `TierDeclarationTests` above holds the PACKAGE question and this class holds the
    one level in. The two are separate for the reason ADR-0273 dec. 2 gives: a tier
    is a fact about a package and a kind is a fact about a member, and the guard that
    conflated them is the one #1059 exists to unpick.

    Every raise arm below is built on a TEMPORARY facade rather than on the shipped
    one. The shipped facade is edited by exactly one arm — `_patched()` — which
    replaces the READER rather than the FILE, so a crashing test cannot leave
    `addons/exmateria_almanac/exmateria_almanac.gd` broken for the other 28
    worktrees on this box.
    """

    ALMANAC = PROJECT_DIR / "addons" / "exmateria_almanac"

    def _facade(self, d, body: str) -> Path:
        """A folder-named facade under a scratch addon root, ADR-0212 dec. 1's shape."""
        addon = Path(d) / "addons" / "seedrules"
        addon.mkdir(parents=True)
        (addon / "seedrules.gd").write_text(body, encoding="utf-8")
        return addon

    def _report(self, walk):
        import contextlib, io
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = cap.report_walk(walk)
        finally:
            os.chdir(PROJECT_DIR)
        return rc, buf.getvalue()

    @contextlib.contextmanager
    def _patched(self, mutate):
        """Score the REAL tree with one member's declared kind changed.

        The mutation arm. Every assertion in this class about the census and the debt
        block is a reading of
        a green guard, and a green guard reads the same for a live scan and a dead
        one — so the register is proved by moving one word and requiring the number
        to move by the amount that word is worth. The patch is on the READER, so
        nothing on disk changes and a failure mid-`with` restores it anyway.
        """
        original = _wr.declared_member_kinds

        def patched(root):
            kinds = dict(original(root))
            mutate(root, kinds)
            return kinds

        _wr.declared_member_kinds = patched
        try:
            roots, gone = cap.full_roots()
            yield cap.walk_addons(roots, None, gone)
        finally:
            _wr.declared_member_kinds = original
            os.chdir(PROJECT_DIR)

    # --- the vocabulary and the free set ------------------------------------

    def test_the_vocabulary_is_three_words_and_only_table_is_free(self):
        """The MEMBERSHIP is the claim, not the count. The failure this guards against
        is `rule` or `state` joining the free set without anyone deciding that it
        should — which is `PORTABLE_TIERS`' own failure mode one level in."""
        self.assertEqual(_wr.MEMBER_KINDS, ("table", "rule", "state"))
        self.assertEqual(_wr.MEMBER_FREE_KINDS, frozenset({"table"}))
        self.assertTrue(_wr.MEMBER_FREE_KINDS < set(_wr.MEMBER_KINDS),
                        "a free kind that is not in the vocabulary frees nothing, and "
                        "a free set equal to the vocabulary frees the whole package — "
                        "which is the wholesale branch ADR-0271 rejected")

    # --- the reader, in both directions -------------------------------------

    def test_each_of_the_three_kinds_is_read_back(self):
        for kind in _wr.MEMBER_KINDS:
            with self.subTest(kind=kind):
                with tempfile.TemporaryDirectory() as d:
                    addon = self._facade(
                        d, 'class_name SeedRules\n\nconst MEMBER_KINDS := {\n'
                           '\t"Alpha": "%s",\n}\n' % kind)
                    self.assertEqual(_wr.declared_member_kinds(addon), {"Alpha": kind})

    def test_a_root_with_no_FOLDER_NAMED_facade_RAISES(self):
        """ADR-0212 dec. 1 makes the facade's address derivable, so a `rules` package
        without one cannot be scored per member — and must say so rather than score
        every member as whatever an empty map defaults to."""
        with tempfile.TemporaryDirectory() as d:
            addon = Path(d) / "addons" / "seedrules"
            addon.mkdir(parents=True)
            (addon / "something_else.gd").write_text("class_name X\n", encoding="utf-8")
            with self.assertRaises(FileNotFoundError):
                _wr.declared_member_kinds(addon)

    def test_a_facade_with_no_MEMBER_KINDS_RAISES(self):
        with tempfile.TemporaryDirectory() as d:
            addon = self._facade(
                d, 'class_name SeedRules\n\nconst Alpha = preload("res://a.gd")\n')
            with self.assertRaises(ValueError):
                _wr.declared_member_kinds(addon)

    def test_an_UNKNOWN_kind_word_RAISES(self):
        """`declared_tier`'s rule for its reason: a word outside the vocabulary is not
        a fourth answer to be inferred around, it is a declaration nothing can score."""
        with tempfile.TemporaryDirectory() as d:
            addon = self._facade(
                d, 'class_name SeedRules\n\nconst MEMBER_KINDS := {\n'
                   '\t"Alpha": "bank",\n}\n')
            with self.assertRaises(ValueError):
                _wr.declared_member_kinds(addon)

    def test_an_EMPTY_map_RAISES(self):
        """An empty map frees nothing, so it reads exactly like a package whose members
        are all `rule` — a verdict wearing an absence. The reconciliation arm would
        also catch this one on the real tree; both are held, because the reader is used
        on roots the walk has never seen."""
        with tempfile.TemporaryDirectory() as d:
            addon = self._facade(
                d, 'class_name SeedRules\n\nconst MEMBER_KINDS := {\n}\n')
            with self.assertRaises(ValueError):
                _wr.declared_member_kinds(addon)

    def test_a_DUPLICATE_member_RAISES(self):
        """GDScript keeps the LAST value; a reader that kept the first would disagree
        with the file it is reading, silently and only for the duplicated name."""
        with tempfile.TemporaryDirectory() as d:
            addon = self._facade(
                d, 'class_name SeedRules\n\nconst MEMBER_KINDS := {\n'
                   '\t"Alpha": "table",\n\t"Alpha": "rule",\n}\n')
            with self.assertRaises(ValueError):
                _wr.declared_member_kinds(addon)

    def test_an_UNPARSEABLE_line_inside_the_map_RAISES(self):
        """Deliberately strict, for `_TIER_RE`'s reason. A reader looser than the file
        it reads lets a declaration land that nothing else can see — and the failure
        direction of a SKIPPED line is a member silently absent from the map."""
        for line in ('\t"Alpha": "table"\n',            # no trailing comma
                     '\t"Alpha" : table,\n',            # unquoted value
                     '\t"Alpha": "table", "Beta": "rule",\n'):   # two on one line
            with self.subTest(line=line):
                with tempfile.TemporaryDirectory() as d:
                    addon = self._facade(
                        d, 'class_name SeedRules\n\nconst MEMBER_KINDS := {\n'
                           + line + '}\n')
                    with self.assertRaises(ValueError):
                        _wr.declared_member_kinds(addon)

    def test_a_COMMENTED_kind_is_not_a_declaration(self):
        """This file's standing rule — no arm may match its own documentation. The
        almanac's own MEMBER_KINDS ships under forty lines of `#` prose that name all
        three words and quote example rows."""
        with tempfile.TemporaryDirectory() as d:
            addon = self._facade(
                d, 'class_name SeedRules\n\n# const MEMBER_KINDS := {\n'
                   '# \t"Alpha": "table",\n# }\n')
            with self.assertRaises(ValueError):
                _wr.declared_member_kinds(addon)

    # --- the real tree ------------------------------------------------------

    def test_the_almanac_declares_a_kind_for_every_member_it_publishes(self):
        """Both directions over the real facade, which is the guard's own arm restated
        where a reader can see it fail. A map naming six of thirty-two parses fine.

        THIRTY-THREE AT ADR-0278; THIRTY-TWO SINCE #1159, AND THE REGISTER MOVES IN
        BOTH DIRECTIONS. `AbilityFamily` was the thirty-third published member;
        `UnitRole` then LEFT for the shared kernel as ADR-0118 dec. 1's eleventh
        schema row (ADR-0280 dec. 3), which is the first time a member has been
        removed since the extraction. This number is the LIVE register; ADR-0251's
        thirty-two is the EXTRACTION's and does not move — the two reading the same
        digit today is a COINCIDENCE and not a reconciliation."""
        kinds = _wr.declared_member_kinds(self.ALMANAC)
        roots, _ = cap.full_roots()
        published = cap.published_members(roots)["ExMateriaAlmanac"]
        self.assertEqual(set(kinds), published)
        self.assertEqual(len(kinds), 32)

    def test_the_split_is_eighteen_tables_eleven_rules_three_state(self):
        """The measurement ADR-0273 rules on, pinned so it cannot drift silently.

        LIVENESS IS THE POINT OF THE THIRD NUMBER. All-`table` would free the package
        by another route and read as a clean zero; all-`rule` would print everything
        and read as a guard that had stopped distinguishing. And the three `state`
        members are not a rounding error — they are ADR-0271 soft spot S4's finding
        with a count on it, and they were 36 of the 53 lines phase 2 inherited.

        🔴 THEY ARE 13 OF THOSE LINES SINCE #1180, AND THE MEMBERSHIP DEFECT IS
        UNCHANGED. ADR-0294 dec. 1 read the 36 line by line and found 23 of them
        naming an ENUM declared inside `UnitProgression` rather than the member —
        `EquipSlot` 16, `BaseStatType` 4, `Zodiac` 2, plus one alias whose only use
        was the third. Those 23 were a vocabulary in the wrong package and dec. 2
        moved them to the shared kernel. The 13 that remain are the three members
        being HELD and CONSTRUCTED, which is the defect S4 actually named, so this
        docstring's argument is not weakened by the number falling — it is what is
        left after the part that was never an instance of it was subtracted.

        🔴 EIGHTEEN, NOT SEVENTEEN, SINCE #1120 — AND THE BUMP IS A DERIVATION, NOT AN
        INCREMENT. `ShopAvailabilityDatabase` is the first member ruled after ADR-0273
        landed. The obvious argument for `table` — every `*Database` is one — is the
        by-NAME proxy that ADR's considered alternatives RULE OUT, and that section
        measures it under-counting this very map by eight. Derived from dec. 1 instead: the member owns a bank
        (`items/shop_availability.json`, from `rec[10]`, the 16-bit shop-slot mask and
        `rec[2]`) and seven of its ten queries pluck a stored field, where
        `EquipCandidates` and `StatusEncoder` own no payload at all. The close call is
        `is_stocked`, which reproduces a NAMED ROM gate (`FUN_8012502C`) — so dec. 5's
        tie-break was CHECKED rather than assumed: no sibling addon and no `src/` file
        names this member, and the guard was run both ways to 373 free / 36 debt each
        time. That zero is not blind; the dec. 7 control ran beside it and moved the
        same register to 405 / 4. (Those two are the register AS IT READ AT #1120 and
        are left alone — the free side is 426 today for a reason that has nothing to
        do with this derivation, and re-stamping a past A/B with a later total would
        make it unreproducible.)

        🔴 TWELVE, NOT ELEVEN, SINCE ADR-0278 — AND THIS ONE IS THE TIE-BREAK'S FIRST
        REAL USE. `AbilityFamily` answers what an ability is FOR (`damage` / `healing` /
        `buff` / `debuff`), which is a bank of rulings and therefore arguable as a
        `table`. It is `rule` on dec. 1's own test rather than on the tie-break alone:
        delete its computation and NOTHING is left, where deleting
        `ShopAvailabilityDatabase`'s leaves a ROM table still answering the member's
        headline question. Nothing in the ROM stores a family — five routes derive one.
        ADR-0273 dec. 5 points the same way and costs nothing here: no sibling addon
        names the member, so arm 5 reads 36 debt lines under EITHER word, run both ways.

        🔴 AND ELEVEN AGAIN SINCE #1159 — BUT NOT ADR-0273'S ELEVEN. `UnitRole` left
        the register rather than being re-ruled: it holds an enum, an enum->string
        table, the enum's members and a two-line predicate, and NO derivation, so
        neither of dec. 1's two words names it and dec. 5's tie-break has nothing to
        break. It is ADR-0118 dec. 1's ELEVENTH schema row now (ADR-0280 dec. 3), in
        `addons/exmateria_schema/unit_vocabulary/`. THIS IS THE ONE CASE THE
        TIE-BREAK CANNOT DECIDE, and the register losing a row is the answer rather
        than a third word. Read the two elevens as different SETS: ADR-0273's held
        `UnitRole` and not `AbilityFamily`; this one is the other way round.

        ADR-0273 is not amended by any of the three moves. It rules on the per-member
        VOCABULARY and REPORTS 17/11/3 as a consequence of the tree it was measured
        on; 18 satisfies that ruling exactly when the eighteenth member is a `table`
        under dec. 1, 12 satisfies it when the twelfth `rule` COMPUTES, and 11 again
        satisfies it when a member that was never either one leaves the package it was
        declared in. ADR-0251's thirty-two/thirty-one are a
        DIFFERENT register — the EXTRACTION's count, frozen by the addon README on
        purpose — and are deliberately left alone.
        """
        import collections
        got = collections.Counter(_wr.declared_member_kinds(self.ALMANAC).values())
        self.assertEqual(dict(got), {"table": 18, "rule": 11, "state": 3})
        kinds = _wr.declared_member_kinds(self.ALMANAC)
        self.assertEqual(sorted(k for k, v in kinds.items() if v == "state"),
                         ["AbilityLoadout", "GambitList", "UnitProgression"],
                         "the three `state` members are #1059 phase 3's subject and "
                         "ADR-0271 S4's; phase 3 is REJECTED (ADR-0300) and they stay, "
                         "so if this list moved, something moved them without a ruling")

    def test_the_debt_that_survives_is_exactly_the_state_members(self):
        """The claim, end to end, and the one number that is not a re-statement.

        Phase 2 takes arm 5 from 354 free / 53 debt to 371 / 36; the free side read
        373 after #1120 added `ShopAvailabilityDatabase`'s own two port lines, 406
        after #1159/#1160, 408 after #1168, and 426 since #1180.

        🔴 AND THE DEBT SIDE READS 13, WHICH IS THE FIRST TIME IT HAS MOVED SINCE
        ADR-0273 SET IT. Every earlier paragraph in this class says the debt is
        untouched, and that was the whole point of them — the free side is an
        install-dependency count and only the debt side is a verdict. #1180 is the
        one change that is about the verdict: ADR-0294 dec. 2 admitted `EquipSlot`,
        `BaseStatType` and `Zodiac` to the shared kernel as ADR-0118 dec. 1's
        TWELFTH row, and 23 of the 36 lines named one of those three. ADR-0280
        dec. 6 rules the 36 the accepted price *"not a countdown"* and dec. 9(ii)
        says in the same breath that it does not rule a future pass may not pay
        them; this is that pass, and what it paid was the vocabulary and nothing
        else. Thirteen remain and they are what the catalogue actually owes:
        `Character.gd` holding and constructing a `UnitProgression` and a
        `GambitList`, and `AllTemplatesSeeder` constructing one.

        🔴 THE +35 IS NOT A REGRESSION AND IT IS NOT THIS ARM'S SUBJECT. #1159 moved
        `UnitRole` into the kernel, so the three almanac files naming it reach a
        SIBLING addon where they used to name a file inside their own root — and
        every one of those is a reach INTO the kernel, which ADR-0202 dec. 2 rules
        free and ADR-0139 dec. 9 PRINTS rather than forbids. Read the free number as
        an install-time dependency count, never as a score: it went up because a
        member became MORE shared, which is the outcome the extraction is for. The
        number that would mean a regression is the debt, and it did not move.

        What makes that a
        DECISION rather than a discount is which rows survived: every remaining line
        names a member declared `state`, and not one names a `table` or a `rule`.
        `rule` reading zero here is not a hole — no sibling addon names a `rule`
        member today; the 83% of shared behaviour ADR-0271 dec. 5 measured is `src/`'s
        and arm 5 does not scan the host. Said out loud so the zero is not read as
        coverage.
        """
        roots, gone = cap.full_roots()
        w = cap.walk_addons(roots, None, gone)
        kinds = _wr.declared_member_kinds(self.ALMANAC)
        debt = [(f, name, lines) for _rel, f, name, home, lines in w["sib_debt"]
                if "exmateria_almanac" in str(home)]
        self.assertTrue(debt, "liveness: arm 5 must still report almanac rows")
        self.assertEqual(sum(len(l) for _f, _n, l in debt), 13)
        self.assertEqual({kinds[n.split(".", 1)[1]] for _f, n, _l in debt}, {"state"})

        free = [(name, lines) for _rel, _f, name, home, lines in w["sib_free"]
                if "exmateria_almanac" in str(home)]
        self.assertTrue(free, "liveness: freeing these lines and then not PRINTING them "
                              "would read identically to dropping them — arm 5's free "
                              "block exists so the surviving dependency is counted")
        # 21, and it was 17 until #1225. Extraction #7's `addons/exmateria_effects` names
        # `ExMateriaAlmanac.AbilityDatabase` on four lines (`cast/EffectManager.gd:24` plus
        # its three use sites), which is a `table` read — ADR-0115 dec. 4's content shadow,
        # the same shape as the catalogue's `JobDatabase` rows — so it arrives FREE by the
        # member-kind split this test is about. A SECOND addon landing in the free half of
        # that split is the split generalising, which is why the number moved and the two
        # assertions under it did not.
        self.assertEqual(sum(len(l) for _n, l in free), 21)
        self.assertEqual({kinds[n.split(".", 1)[1]] for n, _l in free}, {"table"})

        rc, out = self._report(w)
        self.assertEqual(rc, 0, out)
        self.assertIn("cross-addon class_name — %d line(s)" % PERMITTED, out)
        self.assertIn("cross-addon class_name DEBT — 18 line(s)", out)

    # --- the mutation arms --------------------------------------------------

    def test_declaring_UnitProgression_a_table_moves_the_debt_by_exactly_9(self):
        """🔴 THE MUTATION PROOF. Everything above reads a GREEN guard, and a green
        guard reads the same whether the register is consulted or ignored.

        `UnitProgression` is 9 of the 13 surviving lines and ADR-0241 dec. 1 already
        ruled it the Character Catalogue's BY OWNERSHIP, so calling it a `table` is
        the exact wrong answer this register exists to be able to state. The reds must
        land where predicted — 13 -> 4 and PERMITTED -> PERMITTED+9 — and not
        merely somewhere.

        ⚠ THIS CONTROL WAS 32 AND IS NOW 9, AND THE ARM IT CONTROLS GOT STRONGER
        RATHER THAN WEAKER. Before #1180 the mutation moved 32 lines, but 23 of
        those were `UnitProgression.EquipSlot.*` / `.BaseStatType.*` /
        `.zodiac_from_birthday` — lines that named the member only because the
        vocabulary was NESTED in it, so most of the control's swing came from
        spelling rather than from ownership. The 9 that remain are every line that
        holds or constructs a progression record and nothing else, which is exactly
        the claim `state` makes. A smaller number measuring only the thing under
        test beats a larger one measuring two.

        🔴 14, NOT 0, AND THE RESIDUE IS THE POSITIVE CONTROL. `GambitList` is
        `state` too and this mutation does not touch it, so a run that took the
        block to zero would mean the patch had reached further than the member it
        names. Since #1225 the residue also holds extraction #7's nine
        `addons/exmateria_effects` lines, which this mutation cannot reach at all —
        four almanac lines plus nine effects lines is the 13.
        """
        def to_table(root, kinds):
            if root.name == "exmateria_almanac":
                kinds["UnitProgression"] = "table"

        with self._patched(to_table) as w:
            rc, out = self._report(w)
        self.assertEqual(rc, 0, out)
        self.assertIn("cross-addon class_name DEBT — 9 line(s)", out)  # 13 -> 9 with the base at #1192's 18 (was 22): the mutation frees the same 9
        self.assertEqual(_permitted(out) - PERMITTED, 9,
                         "calling UnitProgression a table must free exactly its 9 lines")
        # 22 - 9, not 13 - 9: extraction #7 (#1225) added NINE `addons/exmateria_effects`
        # rows to the same block, and this mutation cannot reach them — they name
        # `Battlefield` and `Render`, not the `rules` tier. The RESIDUE arm below is what
        # that strengthens: the block must keep `GambitList` AND the effects rows.
        # (It was ten until the same pass re-spelled `ExMateriaSound.FedsBank` as a path to
        # that package's façade — #1241's arm 8 is unconditional and the `deps=` route
        # raises, because the sound package declares no `engine=`.)
        self.assertEqual(22 - 9, 13)

    def test_declaring_UnitProgression_a_RULE_moves_NOTHING(self):
        """The other half, and it is what says the split is on FREE-NESS rather than
        on the word. `rule` and `state` are different claims about a member and the
        SAME verdict for arm 5, so swapping one for the other must move no number —
        if it did, some arm would be reading the vocabulary instead of the free set.
        """
        def to_rule(root, kinds):
            if root.name == "exmateria_almanac":
                kinds["UnitProgression"] = "rule"

        with self._patched(to_rule) as w:
            rc, out = self._report(w)
        self.assertEqual(rc, 0, out)
        self.assertIn("cross-addon class_name DEBT — 18 line(s)", out)
        self.assertIn("cross-addon class_name — %d line(s)" % PERMITTED, out)

    def test_a_member_missing_from_the_register_RAISES_THE_WHOLE_GUARD(self):
        """Not a KeyError deep in the scan, and above all not a silent `table`.

        The reader cannot see the published list and `published_members` cannot see
        the kinds, so neither one alone notices a map that names thirty of thirty-two.
        The reconciliation is the join, it runs before the first row is scored, and
        its message has to be the fix — #424's rule that an exclusion expressed as a
        filter cannot tell a triaged name from one that merely matches.
        """
        def drop(root, kinds):
            if root.name == "exmateria_almanac":
                del kinds["JobDatabase"]

        with self.assertRaises(ValueError) as cm:
            with self._patched(drop):
                pass
        self.assertIn("JobDatabase", str(cm.exception))
        self.assertIn("MEMBER_KINDS", str(cm.exception))

    def test_a_register_row_naming_an_UNPUBLISHED_member_RAISES(self):
        """The other direction, which is the one a ratchet usually forgets. A row for
        a member that no longer exists rots into a permanent exemption, and the day it
        matters is the day someone re-publishes that name."""
        def add(root, kinds):
            if root.name == "exmateria_almanac":
                kinds["BaseStatsDatabase"] = "table"

        with self.assertRaises(ValueError) as cm:
            with self._patched(add):
                pass
        self.assertIn("BaseStatsDatabase", str(cm.exception))

    def test_the_UNRESOLVED_FACADE_is_not_free(self):
        """`sibling_class_reaches` refuses to guess: a member the facade does not
        publish resolves to the bare `ExMateriaAlmanac`. That row names an INTERNAL,
        which is a strictly worse dependency than naming a published table — so it
        must take the printed branch, and a `.get(member, "table")` anywhere in
        `member_free` would silently free it."""
        roots, gone = cap.full_roots()
        w = cap.walk_addons(roots, None, gone)
        bare = [r for r in w["sib_free"] if r[2] == "ExMateriaAlmanac"]
        self.assertEqual(bare, [], "a bare facade reach was scored FREE")


class Arm3HostIncludeTests(unittest.TestCase):
    """Arm 3 — a `#include` under an addon root that reaches outside every addon root."""

    def test_host_include_is_reported(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (root / "assets").mkdir()
            (root / "assets" / "shared.gdshaderinc").write_text("// host\n", encoding="utf-8")
            (addon / "seed.gdshader").write_text(
                '#include "res://assets/shared.gdshaderinc"\n', encoding="utf-8")
            rows = cap.include_reaches(addon, root)
            self.assertEqual(len(rows), 1, "an include leaving every addon root must be reported")
            self.assertIn("outside every addon root", rows[0][3])

    def test_res_scheme_is_not_a_comment(self):
        """`res://` CONTAINS `//`. A stripper that calls that a line comment blanks every
        include in the tree and arm 3 reports a clean zero — which it did."""
        kept = cap.strip_shader_comments('#include "res://addons/k/a.gdshaderinc"\n')[0]
        self.assertIn("res://addons/k/a.gdshaderinc", kept)

    def test_include_into_another_addon_is_clean(self):
        """The precedent and the correct shape: `exmateria_render` -> `exmateria_schema`."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            other = root / "addons" / "kernel"
            other.mkdir()
            (other / "shared.gdshaderinc").write_text("// kernel\n", encoding="utf-8")
            (addon / "seed.gdshader").write_text(
                '#include "res://addons/kernel/shared.gdshaderinc"\n', encoding="utf-8")
            self.assertEqual(cap.include_reaches(addon, root), [])

    def test_commented_host_include_is_not_reported(self):
        """A `//` usage example is prose. `ot_depth.gdshaderinc:11` is exactly this."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gdshader").write_text(
                "// usage:\n"
                '//   #include "res://assets/shared.gdshaderinc"\n'
                "/* and\n"
                '   #include "res://assets/blocked.gdshaderinc" */\n', encoding="utf-8")
            self.assertEqual(cap.include_reaches(addon, root), [])

    def test_dangling_include_into_an_addon_is_reported(self):
        """ADR-0146 dec. 8: a seam guard checks the file EXISTS, not just the basename."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gdshader").write_text(
                '#include "res://addons/kernel/gone.gdshaderinc"\n', encoding="utf-8")
            rows = cap.include_reaches(addon, root)
            self.assertEqual(len(rows), 1)
            self.assertIn("does not exist", rows[0][3])

    def test_relative_include_escaping_the_addon_is_reported(self):
        """ADR-0169 dec. 5 writes the arm as `#include "res://…"`. Matching only that
        literal prefix leaves the same escape spelled relatively invisible."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (root / "assets").mkdir()
            (root / "assets" / "shared.gdshaderinc").write_text("// host\n", encoding="utf-8")
            (addon / "seed.gdshader").write_text(
                '#include "../../assets/shared.gdshaderinc"\n', encoding="utf-8")
            rows = cap.include_reaches(addon, root)
            self.assertEqual(len(rows), 1, "a relative escape is the same defect")
            self.assertIn("outside every addon root", rows[0][3])


class Arm4ShaderGlobalTests(unittest.TestCase):
    """Arm 4 — a `[shader_globals]` name bound from an addon root, on EITHER side."""

    def test_declaration_side_is_reported(self):
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gdshaderinc").write_text(
                "global uniform float psx_gamma;\n", encoding="utf-8")
            rows = cap.shader_global_reaches(addon, set())
            self.assertEqual([(r[1], r[2]) for r in rows], [("psx_gamma", "declares")])

    def test_push_side_is_reported(self):
        """ADR-0171 dec. 5. `PSXDisplay` declares no `global uniform` and never will —
        it is the CPU half. A declaration-only arm reads it as clean."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                'func _apply(v: float) -> void:\n'
                '\tRenderingServer.global_shader_parameter_set(&"psx_gamma", v)\n',
                encoding="utf-8")
            rows = cap.shader_global_reaches(addon, set())
            self.assertEqual([(r[1], r[2]) for r in rows], [("psx_gamma", "pushes")])

    def test_push_survives_comment_stripping(self):
        """THE REGRESSION. Arm 2's `strip_noncode` blanks string literals, so arm 4 built
        on it turned `&"psx_gamma"` into `&""` and reported nothing. The name arm 4 needs
        is the token arm 2 must destroy."""
        text = 'func _apply(v: float) -> void:\n\tRenderingServer.global_shader_parameter_set(&"psx_gamma", v)\n'
        self.assertIn("psx_gamma", cap.strip_gdscript_comments(text)[1],
                      "the pushed name is a string literal and must survive stripping")

    def test_name_the_package_declares_is_clean(self):
        """A package that ships its own `[shader_globals]` entry owns the name."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gdshaderinc").write_text(
                "global uniform float psx_owned;\n", encoding="utf-8")
            self.assertEqual(cap.shader_global_reaches(addon, {"psx_owned"}), [])

    def test_commented_global_uniform_is_not_reported(self):
        """`effect_fold_add.gdshader` carries the words "global uniform" in a `//`
        comment explaining that psx_brightness is OFF the fold contract."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gdshader").write_text(
                "// no global uniform float psx_gamma; here — it is off the contract\n"
                "/* global uniform float pixel_aspect; */\n", encoding="utf-8")
            self.assertEqual(cap.shader_global_reaches(addon, set()), [])

    def test_documented_push_is_not_reported(self):
        """`PSXDisplay.gd:54-55` discusses the API in a `##` doc comment thirty lines
        above the first real call."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                '## We do NOT call global_shader_parameter_set(&"psx_gamma", v) here.\n'
                '# global_shader_parameter_get(&"pixel_aspect")\n', encoding="utf-8")
            self.assertEqual(cap.shader_global_reaches(addon, set()), [])

    def test_hash_inside_a_string_starts_no_comment(self):
        """The two rules interact, which is why the stripper scans rather than regexes."""
        kept = cap.strip_gdscript_comments('var s = "a # b"\n')[0]
        self.assertIn("# b", kept)


class ShaderGlobalNamesTests(unittest.TestCase):
    def test_reads_only_the_shader_globals_block(self):
        with tempfile.TemporaryDirectory() as d:
            q = Path(d) / "project.godot"
            q.write_text('[autoload]\n\nTune="*res://src/Tune.gd"\n\n'
                         '[shader_globals]\n\npixel_aspect={"type":"float"}\n\n'
                         '[rendering]\n\nfoo=1\n', encoding="utf-8")
            self.assertEqual(cap.shader_global_names(q), {"pixel_aspect"})

    def test_none_project_owns_nothing(self):
        """An in-walk addon has no project of its own, so every name it binds is the
        host's — which is what makes it debt rather than clean."""
        self.assertEqual(cap.shader_global_names(None), set())


class Arm4bDeclarationOwnerTests(unittest.TestCase):
    """Arm 4b — only a NON-SYSTEM addon may DECLARE a `global uniform` (ADR-0190).

    Distinct from arm 4, which asks whether the HOST declares a name the addon
    BINDS and cannot answer in-walk. This asks which addon the DECLARATION sits in,
    which is a fact about the tree, so it enforces.
    """

    def _seed(self, root, body):
        addon = _pkg(root)
        (addon / "seed.gdshader").write_text(body, encoding="utf-8")
        return addon

    def _run(self, addon, system):
        return subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
             "--root", str(addon), "--system", system],
            capture_output=True, text=True)

    def test_a_system_declaring_one_is_RED(self):
        with tempfile.TemporaryDirectory() as d:
            addon = self._seed(Path(d), "global uniform int seed_probe;\n")
            r = self._run(addon, "Render")
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("GLOBAL UNIFORM DECLARED BY A SYSTEM", r.stdout)
            self.assertIn("declares seed_probe", r.stdout)

    def test_the_report_survives_having_findings(self):
        # 🔴 THE ARM'S FIRST DRAFT CRASHED HERE, and its hand-seed passed anyway:
        # the report called an `_fmt` helper that does not exist, so a run WITH
        # findings raised NameError, printed the header, and exited 1 — which reads
        # exactly like the arm firing. rc=1 is not the verdict; the LINE is.
        with tempfile.TemporaryDirectory() as d:
            addon = self._seed(Path(d), "global uniform int a;\nglobal uniform float b;\n")
            r = self._run(addon, "Render")
            self.assertNotIn("Traceback", r.stderr)
            self.assertIn("declares a", r.stdout)
            self.assertIn("declares b", r.stdout)
            self.assertIn("2 line(s)", r.stdout)

    def test_the_platform_port_may_declare(self):
        # 🔴 THE FIRST DRAFT OF THIS ARM WAS VACUOUS and a seed is what said so.
        # It expressed "not a system" as `--system ''`, which the guard REJECTS
        # before any arm runs ("--system  is not one of the eleven"), so the
        # assertion passed against an error message and survived a seed that made
        # arm 4b fire for every subject.
        #
        # The free set is only exercisable on the REAL walk, where
        # `addons/exmateria_platform/` is in it and declares three global uniforms
        # (ADR-0190 dec. 2). So the subject is the tree.
        _rc, out = _clean_report()
        self.assertNotIn("GLOBAL UNIFORM DECLARED BY A SYSTEM", out,
                         "the platform port is in the free set and must not be reported")
        # And the arm is not silent for want of anything to look at. TWO legs, because
        # the helper alone is not enough: calling `own_global_uniform_declarations`
        # directly BYPASSES the walk, so if `exmateria_platform` ever dropped out of
        # WALK_ROOTS both the assertNotIn above and a bare helper call would still pass
        # — the arm would be silent because it never looked, and this test would say
        # "free set works". So assert MEMBERSHIP first, then content.
        port = PROJECT_DIR / "addons" / "exmateria_platform"
        roots = list(cap._sg._walk_roots.addon_roots())
        self.assertIn(port, roots,
                      "the platform port is not in the walk — arm 4b never looks at it, "
                      "so 'not reported' is silence, not a free-set verdict")
        decls = cap.own_global_uniform_declarations(port)
        self.assertTrue(decls, "the platform port declares no global uniform — this "
                               "arm would pass for the wrong reason")

    def test_a_comment_is_not_a_declaration(self):
        # Both comment syntaxes, because `strip_shader_comments` handles them on
        # different code paths and a guard that only ever met `//` has been wrong
        # about `/* */` in this family before.
        for body in ("// global uniform int seed_probe;\n",
                     "/* global uniform int seed_probe; */\n",
                     "/*\nglobal uniform int seed_probe;\n*/\n"):
            with self.subTest(body=body):
                with tempfile.TemporaryDirectory() as d:
                    addon = self._seed(Path(d), body)
                    r = self._run(addon, "Render")
                    self.assertNotIn("GLOBAL UNIFORM DECLARED BY A SYSTEM", r.stdout)


class Arm4cDeclarerProvidesTests(unittest.TestCase):
    """Arm 4c — the addon that DECLARES a `global uniform` PROVIDES it (ADR-0220 dec. 1).

    Arm 4b's other half. 4b rules who may declare; this rules that the declarer ships the
    `[shader_globals]` entry in its OWN `plugin.gd`. The pair is what makes "only the port
    declares" imply "only the port provides".

    🔴 THE SEED CANNOT BE A `plugin.gd` IN THE SCRATCH TREE, and that is a property of the
    subject rather than a shortcut. `provided_anywhere()` reads `<real project>/addons/*/
    plugin.gd` — it is deliberately tree-wide (see its docstring) — so nothing written under
    a `tempfile` directory is ever a provider. That makes the two RED branches seedable in
    scratch and the GREEN branch answerable only on the real walk, which is exactly how
    `test_the_platform_port_may_declare` handles arm 4b's free set.
    """

    def _seed(self, root, body):
        addon = _pkg(root)
        (addon / "seed.gdshaderinc").write_text(body, encoding="utf-8")
        return addon

    def _run(self, addon):
        # `--system` is required by the CLI; `Render` keeps the subject OUT of the free
        # set, which costs nothing here — arm 4c has no free set. A name that is nobody's
        # is arm 4b's finding as well, so these seeds use a name arm 4b cannot reach only
        # where the distinction matters (see `test_wrong_addon_...` below).
        return subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
             "--root", str(addon), "--system", "Render"],
            capture_output=True, text=True)

    def test_a_declaration_nothing_provides_is_RED(self):
        with tempfile.TemporaryDirectory() as d:
            addon = self._seed(Path(d), "global uniform float seed_unprovided;\n")
            r = self._run(addon)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertNotIn("Traceback", r.stderr)
            self.assertIn("DECLARED BUT NOT PROVIDED BY ITS DECLARER", r.stdout)
            self.assertIn("[unprovided ]", r.stdout)
            self.assertIn("declares seed_unprovided", r.stdout)

    def test_a_provide_in_ANOTHER_addon_does_not_satisfy_it(self):
        # 🔴 THE ARM'S ENTIRE REASON FOR EXISTING. `pixel_aspect` was provided for an entire
        # extraction — by `exmateria_battlefield`, off a declaration in
        # `exmateria_platform` — and a "provided by anything" predicate reads that green.
        # It is not green: the sprite rig's install target holds the port and not the
        # battlefield, so one declaration was arm-3 green for one subject and red for the
        # other (ADR-0202 dec. 6, Class C). This seed re-declares a name the REAL tree
        # already provides somewhere and asserts the arm still fires.
        provided = cap._install_register_provides()
        self.assertTrue(provided, "the install register provided nothing — this test "
                                  "would pass on an empty dict for the wrong reason")
        name = sorted(k[len("shader_globals/"):] for k in provided
                      if k.startswith("shader_globals/"))[0]
        with tempfile.TemporaryDirectory() as d:
            addon = self._seed(Path(d), "global uniform float %s;\n" % name)
            r = self._run(addon)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("[wrong addon]", r.stdout)
            self.assertIn("declares %s" % name, r.stdout)
            self.assertIn("provided by addons/", r.stdout)

    def test_a_comment_is_not_a_declaration(self):
        for body in ("// global uniform float seed_unprovided;\n",
                     "/* global uniform float seed_unprovided; */\n"):
            with self.subTest(body=body):
                with tempfile.TemporaryDirectory() as d:
                    addon = self._seed(Path(d), body)
                    r = self._run(addon)
                    self.assertNotIn("DECLARED BUT NOT PROVIDED BY ITS DECLARER", r.stdout)

    def test_the_real_walk_is_green_and_is_not_green_by_silence(self):
        # The control, and it needs THREE legs for `test_the_platform_port_may_declare`'s
        # reason: "not reported" is silence unless the subject is in the walk AND actually
        # declares something AND the provide map is non-empty. Any one of the three failing
        # would make an arm that never looked read as an arm that looked and approved.
        # THE ARM THAT KEEPS THE SUBPROCESS ALIVE. Every other clean-tree arm in
        # this file scores the SHARED in-process walk; this one still launches
        # the shipped script, because the split's proof is only as good as the
        # entry point: `if __name__ == "__main__"` + exit-code propagation + the
        # no-argv defaults are properties of the script AS SHIPPED, and an
        # in-process `report_walk` call cannot falsify them.
        r = subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py")],
            capture_output=True, text=True)
        self.assertNotIn("DECLARED BUT NOT PROVIDED BY ITS DECLARER", r.stdout,
                         "every `global uniform` under addons/ must be provided by the "
                         "addon that declares it (ADR-0220 dec. 1)")
        port = PROJECT_DIR / "addons" / "exmateria_platform"
        self.assertIn(port, list(cap._sg._walk_roots.addon_roots()),
                      "the port is not in the walk — arm 4c never looks at it")
        decls = cap.own_global_uniform_declarations(port)
        self.assertTrue(decls, "the port declares no global uniform — arm 4c would pass "
                               "for the wrong reason")
        provided = cap._install_register_provides()
        for _f, name, _lines in decls:
            self.assertEqual(provided.get("shader_globals/" + name),
                             "addons/exmateria_platform/plugin.gd",
                             "`%s` is declared by the port and provided elsewhere" % name)


class EndToEndExitCodeTests(unittest.TestCase):
    """A helper that fires while nothing routes it to the exit code is still a green
    guard, so these drive the tool itself and assert on the process."""

    def _run(self, addon: Path):
        return subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
             "--root", str(addon), "--system", "Render"],
            capture_output=True, text=True)

    def test_seeded_package_exits_red(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (root / "assets").mkdir()
            (root / "assets" / "shared.gdshaderinc").write_text("// host\n", encoding="utf-8")
            (addon / "seed.gdshader").write_text(
                '#include "res://assets/shared.gdshaderinc"\n'
                "global uniform float psx_gamma;\n", encoding="utf-8")
            (addon / "seed.gd").write_text(
                'func _apply(v: float) -> void:\n'
                '\tRenderingServer.global_shader_parameter_set(&"pixel_aspect", v)\n',
                encoding="utf-8")
            r = self._run(addon)
            self.assertEqual(r.returncode, 1, "a seeded package must exit RED\n" + r.stdout)
            self.assertIn("HOST INCLUDE", r.stdout)
            self.assertIn("SHADER GLOBALS", r.stdout)
            self.assertIn("declares psx_gamma", r.stdout)
            self.assertIn("pushes pixel_aspect", r.stdout)

    def test_clean_package_exits_green(self):
        """The control. Without it, a tool that exits 1 unconditionally passes the test
        above — an inert seed reads exactly like a working arm."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gdshader").write_text(
                "void fragment() { ALBEDO = vec3(1.0); }\n", encoding="utf-8")
            r = self._run(addon)
            self.assertEqual(r.returncode, 0, "an unseeded package must exit GREEN\n" + r.stdout)



class Arm5SiblingClassNameTests(unittest.TestCase):
    """Arm 5 — a `class_name` one addon root declares and ANOTHER names.

    The arm exists because ADR-0175 dec. 2 re-points 61 host-autoload reaches onto a
    `class_name` port. That fixes arm 2 by construction — `host_auto` is read from the
    host `project.godot` and a `class_name` is never in it — so without arm 5 the trade
    is a measured break swapped for an unmeasured one. Arm 2's own docstring already
    named this gap: *"a `class_name` a consumer happens to define would be another."*

    The dependency is REAL, and it was measured before the arm was written rather than
    reasoned about: a consumer naming a sibling's `class_name` parses clean with the
    sibling present and reports `Parse Error: Identifier "TunePort" not declared in the
    current scope` with the sibling's directory removed — both arms run with the class
    cache warmed by `--import`, because a cold cache reports the same error for every
    `class_name` in the tree and would have made the seed unfalsifiable.
    """

    def _two_addons(self, root: Path):
        """Two sibling addon roots under one scratch package."""
        consumer = _pkg(root)
        provider = root / "addons" / "provider"
        provider.mkdir()
        return consumer, provider

    def test_sibling_class_name_is_reported(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._two_addons(root)
            (provider / "Lattice.gd").write_text(
                "class_name Lattice\nextends RefCounted\n", encoding="utf-8")
            (consumer / "seed.gd").write_text(
                "extends Node\nfunc f() -> void:\n\tvar g = Lattice.new()\n", encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            self.assertEqual(set(homes), {"Lattice"})
            rows = cap.sibling_class_reaches(consumer, homes)
            self.assertEqual(len(rows), 1, "naming a sibling addon's class_name must be reported")
            self.assertEqual(rows[0][1], "Lattice")
            self.assertEqual(rows[0][3], [3])

    def test_declaring_file_is_not_its_own_reach(self):
        """`Lattice.gd` contains the token `Lattice`. Scoring the declaring root against
        its own names reports every addon as reaching itself, which is a guard that is
        red always and therefore says nothing."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._two_addons(root)
            (provider / "Lattice.gd").write_text(
                "class_name Lattice\nextends RefCounted\nstatic func make() -> Lattice:\n"
                "\treturn Lattice.new()\n", encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            self.assertEqual(cap.sibling_class_reaches(provider, homes), [])

    def test_prose_naming_the_class_is_not_a_reach(self):
        """This repo documents heavily and `## returns a Lattice` is not a dependency.
        The same defect arm 4 shipped: built on a stripper that did not run, or on one
        that ran the wrong way."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._two_addons(root)
            (provider / "Lattice.gd").write_text(
                "class_name Lattice\nextends RefCounted\n", encoding="utf-8")
            (consumer / "seed.gd").write_text(
                "extends Node\n## Returns a Lattice, eventually.\n"
                '# Lattice.new() is what this WOULD call.\n'
                'const NOTE := "Lattice is the kernel type"\n', encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            self.assertEqual(cap.sibling_class_reaches(consumer, homes), [])

    def test_substring_of_a_longer_identifier_is_not_a_reach(self):
        """`Fold` is a real kernel name and `FoldSurface` is a real consumer class. A
        bare-substring match books the second as a reach into the first."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._two_addons(root)
            (provider / "Fold.gd").write_text("class_name Fold\nextends RefCounted\n", encoding="utf-8")
            (consumer / "seed.gd").write_text(
                "extends Node\nfunc f() -> void:\n\tvar s = FoldSurface.new()\n"
                "\tvar t = thing.Fold\n", encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            self.assertEqual(cap.sibling_class_reaches(consumer, homes), [])

    def test_kernel_and_port_are_free_and_a_system_is_not(self):
        """The whole rule, on the real tree: `exmateria_render` names the kernel, and the
        kernel is free. It is reported as a dependency and it is not a failure —
        `system_of[home] is None` is arm 1's own test for the free set, so
        `addons/exmateria_platform/` qualifies the day it exists without this file
        learning its name.

        🔴 THE NAME IT REACHES BY CHANGED TWICE, AND THE ROW IS STILL THE SAME ROW. It
        read `FoldSurface.gd:263,270,292,301  Fold` until ADR-0212 dec. 1 collapsed
        `exmateria_schema`'s six globals onto one façade, at which point arm 5 — which
        reads the SPELLING — saw only the bare `ExMateriaSchema` the alias resolves
        through, and per-NAME resolution became per-FOLDER resolution. #722 restores the
        name by reading the alias, and lands past where it started: the row names
        `ExMateriaSchema.Fold`, the symbol the addon PUBLISHES, where the original named
        only the local spelling. One dependency throughout; three reports of it."""
        rc, out = _clean_report()
        # NOT a total. This assertion used to read `— 4 line(s)` and was already
        # red at trunk `c246812cd`: #594 added `exmateria_spu` to EXTRACTED and the
        # free set became 55 without anything failing that said so. A count over a
        # set that grows every time an addon joins the subject is a test of the
        # subject list, not of the rule — so assert the RULE, on the row the
        # docstring is about.
        self.assertIn("cross-addon class_name — ", out)
        # No line numbers. They churned twice in one day for reasons that were not this
        # rule — once when the alias landed, once when the name it aliases changed — and
        # a test that reds on an edit ABOVE the row it is about is testing the file's
        # line count. Assert the row: this consumer, that provider, by name.
        self.assertRegex(out,
                         r"addons/exmateria_render/fold_bracket/FoldSurface\.gd:[\d,]+"
                         r"  ExMateriaSchema\.Fold -> declared in addons/exmateria_schema")
        self.assertNotIn("CROSS-ADDON class_name:", out)
        self.assertEqual(rc, 0, out)

    def test_two_addons_in_ONE_package_are_free(self):
        """The false positive this arm shipped with, and the reason the free set has two
        grounds instead of one.

        `exmateria_sound` names `Spu` -- declared in `exmateria_spu` -- on **51 lines**, and
        both resolve to `exmateria-sound/project.godot`. Arm 5 called that 51 red the moment
        `exmateria_spu` entered the subject list, which is wrong: the two ship as ONE package,
        so co-presence is guaranteed by construction. That is the vendoring the repo-root
        ADR-0003 dec. 4 leans on -- *"D2's vendoring guarantees the SPU addon is present
        whenever Sound is, so the re-export never dangles."*
        """
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._two_addons(root)
            self.assertEqual(cap.package_project(consumer), cap.package_project(provider),
                             "both addons must resolve to the same project.godot")
            self.assertIsNotNone(cap.package_project(consumer))

    def test_host_owned_addons_do_NOT_share_a_package(self):
        """`own is not None` is load-bearing. Two addons owned by the HOST both resolve to
        None, and `None == None` would excuse exactly the reach this arm exists to catch --
        `exmateria_render` naming a future `exmateria_battlefield`'s class_name."""
        for name in ("exmateria_schema", "exmateria_render"):
            q = cap.PROJECT_DIR / "addons" / name
            if not q.is_dir():
                self.skipTest(f"{name} not present in this worktree")
            self.assertIsNone(cap.package_project(q),
                              f"{name} lives in the HOST project and ships with no package of its own")
        # NOT a directory scan: `addons/exmateria_sound` is a SYMLINK into the sound
        # package, created per-worktree by tools/link_worktree_godot_assets.sh, and it
        # resolves to exmateria-sound/project.godot -- correctly. Scanning `addons/*`
        # makes this test's population depend on whether the worktree has been linked,
        # which is how the first version of it failed.

    def test_a_system_sibling_is_debt_in_walk_and_red_in_a_package(self):
        """Arm 2's strictness rule verbatim, and the reason it is not one rule: an addon
        with no project.godot of its own has nothing to fail a parse against."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._two_addons(root)
            (provider / "Combat.gd").write_text("class_name Combat\nextends RefCounted\n", encoding="utf-8")
            (consumer / "seed.gd").write_text(
                "extends Node\nfunc f() -> void:\n\tvar c = Combat.new()\n", encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            self.assertEqual(len(cap.sibling_class_reaches(consumer, homes)), 1)
            self.assertIsNotNone(cap.package_project(consumer),
                                 "the scratch package has its own project.godot, so this arm is RED")

class Arm1BurnDownTests(unittest.TestCase):
    """Arm 1's named debt list, in BOTH directions (ADR-0184 dec. 4).

    A burn-down is the one construct in this family that can turn a guard into
    wallpaper, so the arm that matters is not "a listed reach is excused" — it is
    "an entry that stopped being true FAILS". These score the SHARED clean-tree
    walk (`_clean_walk()`) against a patched list rather than seeding a scratch
    package, because the subject is the REAL tree's reaches: a scratch package
    proves the code path, not that the rows shipped in
    `check_addon_portability.py` still describe this repo.
    """

    def _main(self, burn_down, walk=None):
        import contextlib, io
        buf = io.StringIO()
        original = cap.ARM1_BURN_DOWN
        cap.ARM1_BURN_DOWN = burn_down
        try:
            with contextlib.redirect_stdout(buf):
                rc = cap.report_walk(_clean_walk() if walk is None else walk)
        finally:
            cap.ARM1_BURN_DOWN = original
            os.chdir(PROJECT_DIR)
        return rc, buf.getvalue()

    def test_the_shipped_list_is_live_and_the_tree_is_green(self):
        rc, out = self._main(cap.ARM1_BURN_DOWN)
        self.assertNotIn("STALE ARM1_BURN_DOWN", out)
        self.assertEqual(rc, 0, out)

    def test_an_entry_naming_no_reach_is_STALE_and_red(self):
        """The arm that keeps the list honest. A row whose debt was paid — or whose
        file was deleted — must fail exactly as an unlisted reach does."""
        seeded = dict(cap.ARM1_BURN_DOWN)
        seeded[("addons/exmateria_battlefield/lattice/MapConstants.gd", "NoSuchSymbol")] = (
            "#0", "a row that names no reach")
        rc, out = self._main(seeded)
        self.assertIn("STALE ARM1_BURN_DOWN", out)
        self.assertIn("NoSuchSymbol", out)
        self.assertEqual(rc, 1, out)

    def test_the_green_sentence_is_qualified_EXACTLY_WHEN_arm_1_has_a_row(self):
        """SCOPED TO ARM 1's CAVEAT, and the scoping is the claim. Arm 7 ships five rows
        and prints the same sentence about ARM7_BURN_DOWN, legitimately (ADR-0223 dec.
        6). A bare `assertNotIn("NOT part of that sentence")` reads arm 7's line and
        fails, which is this test asserting that no OTHER arm may ever carry a
        burn-down — a claim it was never written to make.

        🔴 THIS TEST'S PREMISE HAS NOW EXPIRED THREE TIMES, IN BOTH DIRECTIONS, AND
        THAT IS WHY IT IS SHAPED THE WAY IT IS. The third is #1225: extraction #7 put
        `addons/exmateria_effects` in the walk with 23 live rows, so the list is not
        empty, the shipped list alone exercises the POSITIVE direction, and an empty
        list over this tree is red rather than green. Neither direction reads the
        list's size. Written the day `ARM1_BURN_DOWN` went EMPTY,
        it asserted the OK line had SHED its caveat. #1025 pass 3 put one row back
        (`templates/CharacterTemplateResolver.gd` → `ExMateriaSpriteRig`, owner #1071)
        and it was re-pinned to `len(...) == 1`. #1071 then PAID that row (ADR-0272) and
        the list is empty again — so a pin on the list's SIZE has now been wrong on both
        sides of the same assertion.

        WHAT SURVIVES IS THE IF AND ONLY IF: the caveat appears exactly when the list
        has a LIVE row. Neither direction is taken from the shipped list any more,
        because on a clean tree the shipped list cannot exercise the positive one — a
        row with no reach is STALE, not carried, so the caveat stays absent and the run
        reds for an unrelated reason. The positive direction SEEDS the reach back (the
        `_arm1_seed.gd` idiom below) and lists it; the negative direction runs the same
        clean walk with an empty list. A guard that printed the sentence
        unconditionally — or never — fails one of them."""
        self.assertTrue(cap.ARM1_BURN_DOWN,
                        "not empty since #1225 — if this emptied, re-read the arms below")

        # NEGATIVE DIRECTION. Empty list over the SAME tree: no caveat, because there is
        # no listed row to caveat — and rc is now 1 rather than 0, because the reaches
        # the shipped list names are then UNLISTED. That is the third expiry of this
        # arm's premise (#1225): a tree with no arm-1 reach at all no longer exists to
        # score, so the negative direction holds the if-and-only-if — caveat iff a LISTED
        # LIVE row — and says out loud that it is not also a claim about `rc`.
        rc0, out0 = self._main({})
        self.assertEqual(rc0, 1, out0)
        self.assertIn("PORTABILITY: ", out0)
        self.assertNotIn("PORTABILITY BURN-DOWN", out0)
        self.assertNotIn("on ARM1_BURN_DOWN above and are NOT part of that sentence", out0)

        # POSITIVE DIRECTION. Put a real arm-1 reach back into a real addon and LIST
        # it. This is the reach #1071 severed, spelled the way the resolver spelled it,
        # so the row this asserts on is the row the repo actually carried.
        seed = (PROJECT_DIR / "addons" / "exmateria_catalogue" / "templates"
                / "_arm1_caveat_seed.gd")
        self.assertFalse(seed.exists(), "a previous run leaked its seed file")
        seed.write_text(
            "extends Node\n\n"
            "const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver\n",
            encoding="utf-8")
        rel = str(seed.relative_to(PROJECT_DIR))
        # \U0001f534 AND IT HAS TO SEED THE `deps=` HALF TOO, SINCE #1241. The row this
        # recreates is #1025 pass 3's, and at #1025 the catalogue's `plugin.cfg` DECLARED
        # `exmateria_sprite_rig` — #1239 dropped the declaration only after #1071 severed
        # the reach. Arm 8 reads the pair, so seeding the reach alone builds a state this
        # repo has never been in (a reach nobody declared) and reds arm 8 for a reason
        # this test is not about. Seeding both halves restores the tree as it was.
        try:
            # AND IT SEEDS THE SHIPPED LIST BENEATH ITS OWN ROW, SINCE #1225. `ARM1_BURN_DOWN`
            # is no longer empty — extraction #7 put 23 live rows in it — so passing this
            # test's single row ALONE would unlist those 23 and red the run for a reason
            # this test is not about, the mirror image of the `deps=` half below.
            seeded = dict(cap.ARM1_BURN_DOWN)
            seeded[(rel, "ExMateriaSpriteRig")] = ("#1071", "the reach this test seeds")
            rc1, out1 = self._main(
                seeded,
                walk=_redeclare_dep_row(
                    _clean_walk(), "addons/exmateria_catalogue",
                    deps=["exmateria_almanac", "exmateria_platform", "exmateria_schema",
                          "exmateria_sprite_rig"]))
        finally:
            seed.unlink()
        self.assertEqual(rc1, 0, out1)
        self.assertIn("addon portability OK", out1)
        self.assertIn("PORTABILITY BURN-DOWN", out1)
        self.assertIn("on ARM1_BURN_DOWN above and are NOT part of that sentence", out1)
        self.assertIn("_arm1_caveat_seed.gd", out1)

    def test_the_caveat_seed_is_gone_and_the_tree_is_green(self):
        """The other half of the seed above: without the file, the shipped (empty) list
        is green over the same walk. Run after it so a leaked seed fails HERE rather
        than silently making the positive direction look structural."""
        seed = (PROJECT_DIR / "addons" / "exmateria_catalogue" / "templates"
                / "_arm1_caveat_seed.gd")
        self.assertFalse(seed.exists(), "the caveat test leaked its file")
        rc, out = self._main(cap.ARM1_BURN_DOWN)
        self.assertNotIn("_arm1_caveat_seed.gd", out)
        self.assertEqual(rc, 0, out)

    def test_an_unlisted_reach_is_still_RED(self):
        """The control for the control. Without it, a burn-down that swallowed
        everything would pass both tests above.

        🔴 THIS TEST USED TO BE VACUOUS THE DAY IT MATTERED, AND THAT IS THE FINDING.
        It read `{k: v for k, v in ARM1_BURN_DOWN.items() if k[1] != "Unit"}` — it
        unlisted the shipped `Tile.gd -> Battle.Unit` row and asserted the reach came
        back. That works only while the debt is UNPAID. #642 severed the reach, the
        thinned dict became identical to the full one, and the control went green
        while asserting nothing — the exact shape ADR-0184 dec. 4 wrote the list to
        avoid, arriving through the test rather than the list. A control that depends
        on the defect it controls for expires on success.

        So it seeds a real reach into the real addon instead. A scratch package (the
        `_pkg` helper above) would prove the code path, which is not the claim: the
        claim is that arm 1, over THIS repo's walk with THIS repo's classifier, still
        reports a `Battlefield` file naming a `Battle` `class_name`. The seed file
        lives for the duration of one `main()` call and is removed in `finally`.
        """
        seed = PROJECT_DIR / "addons" / "exmateria_battlefield" / "lattice" / "_arm1_seed.gd"
        self.assertFalse(seed.exists(), "a previous run leaked its seed file")
        seed.write_text("extends Node\n\n\nfunc f(u: Unit) -> void:\n\tprint(u)\n",
                        encoding="utf-8")
        try:
            rc, out = self._main(cap.ARM1_BURN_DOWN)
        finally:
            seed.unlink()
        self.assertIn("PORTABILITY: ", out)
        self.assertIn("Battle.Unit", out.split("PORTABILITY: ", 1)[1])
        self.assertIn("_arm1_seed.gd", out)
        self.assertEqual(rc, 1, out)

    def test_the_seed_is_what_reddens_it_and_not_the_tree(self):
        """The other half of the seed: without the file, the same call is GREEN. Run
        after the seed test so a leaked file fails here rather than silently making
        the seed test's red look structural."""
        seed = PROJECT_DIR / "addons" / "exmateria_battlefield" / "lattice" / "_arm1_seed.gd"
        self.assertFalse(seed.exists(), "the seed test leaked its file")
        rc, out = self._main(cap.ARM1_BURN_DOWN)
        self.assertNotIn("PORTABILITY: ", out)
        self.assertEqual(rc, 0, out)



class Arm5FacadeAliasTests(unittest.TestCase):
    """Arm 5 through a FAÇADE — the row must name the published SYMBOL, not the folder.

    #722. ADR-0212 collapsed six `exmateria_schema` globals and three
    `exmateria_platform` ones onto one branded `class_name` each, and every consumer
    aliases them back — `const Fold = ExMateriaSchema.Fold`. Arm 5 reads the SPELLING,
    so 21 rows naming `Fold`, `DepthMode`, `TerrainCell`, `ColorStack`, `ColorRecipe`,
    `DisplayPort` … collapsed to ~20 rows naming two folders. Per-NAME resolution became
    per-FOLDER resolution, and the guard that already resolved a bare type to its
    declaring addon was left with the one line that names less.

    🔴 THE FIX IS NOT "RESTORE THE OLD ROW". A façade member is reachable as
    `ExMateriaSchema.Fold`, which is what the addon PUBLISHES; the pre-façade `Fold` was
    only ever the local spelling. Resolving through the alias therefore lands STRICTLY
    BETTER than the pre-merge report, and the assertions below are written on that
    reading: the row names `<Facade>.<Member>`.
    """

    def _facade_pair(self, root: Path):
        """A provider publishing one member behind a façade, and a consumer addon."""
        consumer = _pkg(root)
        provider = root / "addons" / "provider"
        (provider / "compositing_key").mkdir(parents=True)
        (provider / "compositing_key" / "Fold.gd").write_text(
            "extends RefCounted\nstatic func owns() -> bool:\n\treturn false\n", encoding="utf-8")
        (provider / "provider_facade.gd").write_text(
            "class_name ProviderFacade\nextends RefCounted\n"
            'const Fold = preload("res://addons/provider/compositing_key/Fold.gd")\n',
            encoding="utf-8")
        return consumer, provider

    def test_an_alias_resolves_to_the_published_symbol(self):
        """The red arm. `const Fold = ProviderFacade.Fold` then a bare `Fold.owns()`:
        ONE row, named for the member, carrying BOTH lines — the alias declaration and
        the use site the alias exists to keep spelled the way it was."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._facade_pair(root)
            (consumer / "seed.gd").write_text(
                "extends Node\n"
                "const Fold = ProviderFacade.Fold\n"
                "func f() -> bool:\n"
                "\treturn Fold.owns()\n", encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            rows = cap.sibling_class_reaches(consumer, homes)
            self.assertEqual(len(rows), 1, rows)
            self.assertEqual(rows[0][1], "ProviderFacade.Fold",
                             "the row must name the PUBLISHED symbol, not the façade alone")
            self.assertEqual(rows[0][3], [2, 4],
                             "both the alias and the bare use it licenses are reach lines")

    def test_a_bare_facade_use_invents_no_member(self):
        """The control, and the both-arms half that keeps the resolution honest. A file
        that names the façade and no member of it reaches the FAÇADE — the row must say
        so rather than guess a symbol the file never wrote."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._facade_pair(root)
            (consumer / "seed.gd").write_text(
                "extends Node\nfunc f() -> RefCounted:\n\treturn ProviderFacade.new()\n",
                encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            rows = cap.sibling_class_reaches(consumer, homes)
            self.assertEqual([(r[1], r[3]) for r in rows], [("ProviderFacade", [3])])

    def test_a_member_the_facade_does_not_publish_is_not_resolved(self):
        """`ProviderFacade.Internal` is not on the published list, so there is no symbol
        to name. Reporting `ProviderFacade.Internal` would assert a surface the provider
        does not have; the reach is real and it is a reach on the FAÇADE."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._facade_pair(root)
            (consumer / "seed.gd").write_text(
                "extends Node\nfunc f() -> void:\n\tProviderFacade.Internal.go()\n",
                encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider])
            rows = cap.sibling_class_reaches(consumer, homes)
            self.assertEqual([(r[1], r[3]) for r in rows], [("ProviderFacade", [3])])

    def test_a_local_alias_beats_a_siblings_class_name_of_the_same_spelling(self):
        """GDScript resolves a file-local `const` before an engine-global `class_name`,
        and after ADR-0212 the two spellings COLLIDE by construction: the alias is named
        after the member precisely so the use sites did not move. Scoring the bare name
        against a same-named sibling would book one dependency as two, on the addon the
        file does not depend on."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            consumer, provider = self._facade_pair(root)
            other = root / "addons" / "impostor"
            other.mkdir()
            (other / "Fold.gd").write_text("class_name Fold\nextends RefCounted\n", encoding="utf-8")
            (consumer / "seed.gd").write_text(
                "extends Node\n"
                "const Fold = ProviderFacade.Fold\n"
                "func f() -> bool:\n"
                "\treturn Fold.owns()\n", encoding="utf-8")
            homes = cap.class_name_homes([consumer, provider, other])
            rows = cap.sibling_class_reaches(consumer, homes)
            self.assertEqual([(r[1], r[2].name) for r in rows],
                             [("ProviderFacade.Fold", "provider")])


class Arm2bAutoloadRouteTests(unittest.TestCase):
    """Arm 2b — a host autoload named as a STRING to `get_node`, not as a bare `Name.`.

    #648, and it is arm 2's subject in a third spelling. Arm 2 scores a bare `Name.`
    and says so in its own docstring — *"a bare `Name.` and not a bare `Name`"* — so
    this route is invisible to it:

        var ap := get_node_or_null("CompositorAutopilot")
        ap.owns_compositing()

    The autoload is named as a string and the call is duck-typed on an untyped `Node`,
    so nothing in the file ever writes `CompositorAutopilot.` and arm 2 reports clean.
    `addons/exmateria_battlefield/cursor/TileCursor.gd` did exactly this against a
    `src/effects/` autoload and the guard was green over it the whole time (ADR-0191).

    🔴 IT IS A SEPARATE ARM BECAUSE THE FREE SET IS DIFFERENT, WHICH IS 4b's PRECEDENT.
    Arm 2 checks every subject including the kernel. This one cannot: reaching a
    singleton by node path is what the platform PORT is built out of — ADR-0175 dec. 2
    converts 61 host-autoload reaches into exactly this spelling on purpose, so that an
    `[autoload]` line only the consuming game can write becomes an addon-presence
    dependency instead. `TunePort.gd:77` naming `Tune` is that design working, not a
    defect. So the free set is arm 5's: the kernel and the port.

    And a second exemption the measurement forced: an addon that reaches ITS OWN
    singleton this way — `exmateria_sound` naming `ExMateriaAudioEngine`,
    `exmateria_platform` naming `PSXDisplay` — ships the script the autoload points at.
    The consumer still has to register it, and `plugin.gd` can (ADR-0203 dec. 1). The
    defect this arm is armed against is naming a script the addon does NOT ship.
    """

    def _host(self, root: Path):
        """Autoload names as a host `project.godot` declares them: `{name: res-path}`."""
        return {"CompositorAutopilot": "src/effects/CompositorAutopilot.gd",
                "SeedSingleton": "addons/seedaddon/runtime/seed_singleton.gd"}

    def test_a_host_autoload_named_as_a_string_is_reported(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gd").write_text(
                "extends Node\n"
                "func f() -> void:\n"
                '\tvar ap = get_node_or_null("CompositorAutopilot")\n'
                "\tap.owns_compositing()\n", encoding="utf-8")
            rows = cap.autoload_route_reaches(addon, self._host(root))
            self.assertEqual([(r[1], r[3]) for r in rows], [("CompositorAutopilot", [3])])

    def test_the_root_prefixed_and_stringname_spellings_are_the_same_reach(self):
        """`/root/Name`, `^"Name"` and `has_node` are the same dependency wearing three
        spellings. ADR-0191 recorded that `TileCursor` used the longest of them —
        `Engine.get_main_loop().root.get_node_or_null("…")` — and a rule that reads only
        the shortest reports zero on the file that motivated it."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'func a(): return get_node("/root/CompositorAutopilot")\n'
                'func b(): return has_node(^"CompositorAutopilot")\n'
                'func c(): return Engine.get_main_loop().root.get_node_or_null("CompositorAutopilot")\n'
                'func d(): return find_child("CompositorAutopilot")\n', encoding="utf-8")
            rows = cap.autoload_route_reaches(addon, self._host(root))
            self.assertEqual([(r[1], r[3]) for r in rows],
                             [("CompositorAutopilot", [2, 3, 4, 5])])

    def test_the_addons_OWN_singleton_is_not_a_foreign_reach(self):
        """The control. `SeedSingleton` points at a script THIS addon ships, so the
        consumer's install step is one the addon can satisfy itself. That is
        `exmateria_sound` naming `ExMateriaAudioEngine` and `exmateria_platform` naming
        `PSXDisplay` — three of the four routes on the real tree."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'func f(): return get_node_or_null("SeedSingleton")\n', encoding="utf-8")
            self.assertEqual(cap.autoload_route_reaches(addon, self._host(root)), [])

    def test_a_node_that_is_no_autoload_is_not_a_reach(self):
        """The other control, and the reason this cannot be "match the 26 names". A
        `get_node("Camera3D")` is an ordinary scene lookup; the arm's universe is the
        host's `[autoload]` block and nothing wider."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'func f(): return get_node_or_null("Camera3D")\n'
                'func g(): return get_node("FocusPoint/Camera")\n', encoding="utf-8")
            self.assertEqual(cap.autoload_route_reaches(addon, self._host(root)), [])

    def test_the_route_in_a_comment_is_not_a_reach(self):
        """NEITHER ARM MAY MATCH ITS OWN DOCUMENTATION, and this arm is the one most
        exposed to it: the guard's OWN remedy text spells `get_node_or_null(^"Name")`,
        and any addon that copies that advice into a `##` doc comment would be scored
        red for quoting the fix."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gd").write_text(
                "extends Node\n"
                '## Reach it with get_node_or_null("CompositorAutopilot") instead.\n'
                '# var ap = get_node_or_null("CompositorAutopilot")\n', encoding="utf-8")
            self.assertEqual(cap.autoload_route_reaches(addon, self._host(root)), [])

    def test_a_seeded_route_reaches_the_EXIT_CODE(self):
        """A helper that fires while nothing routes it to the exit code is still a green
        guard — this file's oldest lesson. `--root` forces a SYSTEM verdict, which is
        what takes the seed out of the free set, and `host_auto` is read from the real
        `project.godot` either way, so `CompositorAutopilot` is a live host name here."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'func f(): return get_node_or_null("CompositorAutopilot")\n', encoding="utf-8")
            r = subprocess.run(
                [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
                 "--root", str(addon), "--system", "Render"],
                capture_output=True, text=True)
            self.assertNotIn("Traceback", r.stderr)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("AUTOLOAD ROUTE:", r.stdout)
            self.assertIn('"CompositorAutopilot" -> src/effects/CompositorAutopilot.gd', r.stdout)

    def test_the_kernel_and_the_port_are_free_and_the_real_tree_is_green(self):
        """End to end on the real tree, which is where the free set lives — the helper
        above knows nothing about systems. Four routes exist today: `PSXDisplay` and
        two `exmateria_sound` singletons are each the addon's own, and `TunePort.gd`
        naming `Tune` is the platform port doing the job ADR-0175 dec. 2 built it for.
        Zero violations, so this arm ships ENFORCING rather than as debt.

        THREE LEGS, and arm 4b's `test_the_platform_port_may_declare` is why. "Not
        reported" is silence unless the arm looked: if `exmateria_platform` ever left
        the walk, or if it stopped naming `Tune` by node path, the assertion below would
        still pass and would say "free set works" about an arm with nothing to score.
        So assert MEMBERSHIP, then CONTENT, then the verdict."""
        port = PROJECT_DIR / "addons" / "exmateria_platform"
        self.assertIn(port, list(cap._sg._walk_roots.addon_roots()),
                      "the platform port is not in the walk — arm 2b never looks at it, "
                      "so 'not reported' is silence, not a free-set verdict")
        host = cap.autoload_names(PROJECT_DIR / "project.godot")
        routes = cap.autoload_route_reaches(port, host)
        self.assertTrue([r for r in routes if r[1] == "Tune"],
                        "the port no longer soft-binds `Tune` by node path — this test "
                        "would pass for the wrong reason")
        # And the KERNEL half of the free set, measured rather than assumed. #648 asks
        # only for "excluding the addon's own"; scoring on arm 5's free set is WIDER
        # than that, so what the extra width actually excuses is a number and not an
        # opinion. It is zero — the kernel routes to no host singleton at all, so the
        # kernel's exemption is vacuous today and the whole free set is carrying the
        # port's one row. If this ever fails, the width started doing work and #648's
        # narrower rule is the one to argue against.
        kernel = PROJECT_DIR / "addons" / "exmateria_schema"
        self.assertIn(kernel, list(cap._sg._walk_roots.addon_roots()))
        self.assertEqual(cap.autoload_route_reaches(kernel, host), [],
                         "the kernel now uses a node-path route the free set silently "
                         "excuses — decide it, do not inherit it")
        rc, out = _clean_report()
        self.assertNotIn("AUTOLOAD ROUTE:", out)
        self.assertEqual(rc, 0, out)

    def test_the_spelled_arm_count_equals_the_enumerated_arms(self):
        """The count has now been wrong THREE times -- FOUR in this docstring while the
        file held five, FIVE in the preflight banner while it held six, and SEVEN here
        over an eight-label list. Spelling it out did not fix it, because the word and
        the list are two places that a human keeps in step. This recounts the list, so
        the word cannot drift again. `2b` and `4b` COUNT: each has its own subject, its
        own strictness verdict and its own test class."""
        WORDS = {4: "FOUR", 5: "FIVE", 6: "SIX", 7: "SEVEN", 8: "EIGHT",
                 9: "NINE", 10: "TEN", 11: "ELEVEN", 12: "TWELVE"}
        doc = cap.__doc__
        # The CANONICAL list only: the block from `  1.` to the first column-0 line.
        # A bare findall over the whole docstring counts ten, because the docstring
        # re-enumerates `3.` and `4.` further down under "WHY ARMS 3 AND 4 EXIST" —
        # a deep-dive on two of the arms, not two more arms. Structural rather than
        # keyed on that heading's wording, which is prose and will move.
        lines = doc.splitlines()
        first = next(i for i, l in enumerate(lines) if re.match(r"^  1\. [A-Z]", l))
        arms = []
        for l in lines[first:]:
            if l.strip() and not l.startswith("  "):
                break
            m = re.match(r"^  (\d+b?)\. [A-Z]", l)
            if m:
                arms.append(m.group(1))
        self.assertGreater(len(arms), 1, doc)
        self.assertEqual(len(arms), len(set(arms)), "an arm label is enumerated twice")
        spelled = WORDS[len(arms)]
        self.assertIn("along %s arms" % spelled, doc,
                      "the docstring enumerates %d arms (%s) and spells a different "
                      "number" % (len(arms), ", ".join(arms)))
        # The preflight banner names the arms too and has been the stale copy once
        # already. `assertIn(spelled, banner)` is NOT enough: the file is ~1700 lines
        # and the word occurs in the section header, so the `echo` 30 lines below can
        # read "seven" while the assertion still passes on the header. Measured — that
        # is exactly what it did. So collect EVERY spelled count in the section and
        # require them all to agree.
        banner = (PROJECT_DIR / "tests" / "run_all_tests.sh").read_text(encoding="utf-8")
        head = banner.index("Pre-flight: goal #5's addon net")
        section = banner[head:banner.index("lost their seeded red arms", head)]
        spoken = re.findall(r"\b(%s)\b\s+arms" % "|".join(WORDS.values()),
                            section, re.I)
        self.assertTrue(spoken, section)
        self.assertEqual({w.upper() for w in spoken}, {spelled},
                         "the preflight banner spells the arm count %s while the tool "
                         "enumerates %d" % (sorted(set(spoken)), len(arms)))

    def test_arm_2s_remedy_does_not_recommend_what_this_arm_forbids(self):
        """The contradiction this arm creates, held closed. Arm 2's remedy text tells a
        failing addon to *"reach the singleton by NODE PATH instead"* — which was whole
        advice while the node path was invisible, and is half of it now. A guard that
        advises the thing it fails is worse than either arm alone, so the text has to
        name the two grounds on which the route is still open."""
        text = (TOOLS_DIR / "check_addon_portability.py").read_text(encoding="utf-8")
        # SLICED to the remedy's own print block. Whole-file, this assertion passes on
        # the `# --- arm 2b:` comment in `main()` and on the module docstring's arm
        # list — it would stay green with the ⚠️ paragraph deleted, which is the one
        # thing it exists to forbid (NEITHER ARM MAY MATCH ITS OWN DOCUMENTATION).
        head = text.index("Reach the singleton by NODE PATH instead")
        remedy = text[head:text.index("\n    if path_bad:", head)]
        self.assertIn("arm 2b", remedy.lower(),
                      "the remedy must name the arm that narrows it, in the text a "
                      "failing addon actually reads")
        self.assertIn("ADR-0175 dec. 2", remedy,
                      "and must send a SYSTEM to a port rather than to the node path")


class Arm6ResPathTests(unittest.TestCase):
    """Arm 6 — a quoted `res://` path in an addon whose target is outside every addon root.

    #658. Goal #5's sentence is *"reach no system"*, and until this arm that was true
    only of TYPE-shaped reaches; a PATH-shaped one had never been in the universe. The
    seed the ticket ships is one line in the kernel:

        const _SEED = preload("res://src/data/JobDatabase.gd")

    and all four arms report OK. `tests/stranger/exmateria_schema/run.sh` catches it —
    staged into a project with no `src/`, the file does not compile — but only one addon
    has a rig and the static guard runs on all six.

    🔴 THE TICKET'S EXPLANATION OF WHY IS STALE, AND MEASURING IT MOVED THE ARM. Its table
    says arm 1 *"names a type, not a path"*; `score_goals.outbound_reaches` has since
    grown `preload` and `const path` shapes, and a `preload` of a **Battle**-booked file
    from `exmateria_battlefield` is red today. Two things are actually open, and the
    ticket's seed happens to sit on both:

      1. ARM 1 DOES NOT RUN ON THE KERNEL OR THE PORT AT ALL — `main()` reads
         `if system is None: continue`, correctly, because they are not systems. So the
         two addons every other addon depends on can `preload` any host file with no
         report. The ticket's seed is in the kernel.
      2. THE ELEVEN SYSTEMS ARE NOT THE WHOLE HOST. `src/data/JobDatabase.gd` classifies
         `content`, not `Battle`, so even from a system addon that exact seed is
         invisible — and an addon that cannot find `res://assets/…` is just as broken as
         one that cannot find `src/`.

    This arm answers both, and it answers them the way arm 3 does rather than the way arm
    1 does: the target resolves under an addon root or it does not, which needs no
    classifier verdict and no standalone project. So it ENFORCES.
    """

    def test_a_host_path_is_reported(self):
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'const _SEED = preload("res://src/data/JobDatabase.gd")\n', encoding="utf-8")
            rows = cap.res_path_reaches(addon)
            self.assertEqual([(r[1], r[2]) for r in rows],
                             [(2, "res://src/data/JobDatabase.gd")])

    def test_a_path_into_another_addon_is_clean(self):
        """The addon ships, and so does the addon it names. That dependency is arm 5's
        and arm 3's subject; it is not an address that leaves the shipped set."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'const A = preload("res://addons/kernel/Fold.gd")\n'
                'const B = preload("res://addons/seedaddon/lattice/Tile.gd")\n', encoding="utf-8")
            self.assertEqual(cap.res_path_reaches(addon), [])

    def test_prose_about_a_path_is_not_a_path(self):
        """🔴 THE WHOLE ARM TURNS ON THIS, and the measurement says so: all 11 rows
        #658 lists for `exmateria_battlefield` are GONE — ADR-0202/ADR-0204 moved the
        addon onto a host-injected content root — and every surviving `res://assets/`
        in that addon is a `##` note, a `#` note or a `;` line in a `.tres` saying so.
        An arm without a stripper reports 21 false rows on the addon that already paid."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                '## ⚠️ Was `const P := "res://assets/maps/"`. Now host-injected.\n'
                '# const P := "res://assets/doodads/"\n', encoding="utf-8")
            (addon / "seed.tres").write_text(
                "[gd_resource type=\"Material\"]\n"
                "; `[ext_resource]` links into res://assets/sprites/ — ADR-0202 Class B\n",
                encoding="utf-8")
            self.assertEqual(cap.res_path_reaches(addon), [])

    def test_a_scene_referrer_counts(self):
        """`camera/PlayerCamera.tscn:5` naming `res://assets/scenes/CombatUI.tscn` is the
        row #658 singles out as worth a look on its own — a scene reference out of the
        addon into the host's UI. A `.gd`-only arm cannot see it."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.tscn").write_text(
                '[gd_scene load_steps=2 format=3]\n'
                '[ext_resource type="PackedScene" path="res://assets/scenes/CombatUI.tscn" id="1"]\n',
                encoding="utf-8")
            rows = cap.res_path_reaches(addon)
            self.assertEqual([(r[1], r[2]) for r in rows],
                             [(2, "res://assets/scenes/CombatUI.tscn")])

    def test_a_non_source_target_is_in_the_universe(self):
        """The deliberate divergence from `check_res_paths.LITERAL`, which this arm
        otherwise borrows. That pattern is scoped to hand-written SOURCE suffixes because
        its question is "does every source path still resolve"; this arm's question is
        "can the addon be installed elsewhere", and a `.tga`, a `.json` and a bare
        directory are exactly as unshippable as a `.gd`. Of the eleven rows #658
        measured, four were `.tga`/`.json` and two were bare directories — the narrow
        pattern drops six of eleven."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'const T := "res://assets/sprites/textures/RANGETILE.tga"\n'
                'const J := "res://assets/sprites/tile_knife.json"\n'
                'const M := "res://assets/maps/"\n', encoding="utf-8")
            self.assertEqual([r[2] for r in cap.res_path_reaches(addon)],
                             ["res://assets/sprites/textures/RANGETILE.tga",
                              "res://assets/sprites/tile_knife.json",
                              "res://assets/maps/"])

    def test_a_shader_include_is_arm_3s_row_and_not_this_arms(self):
        """One defect, one report. `#include "res://assets/shared.gdshaderinc"` is arm
        3's exact subject and arm 3 resolves it against the shipping project and checks
        the file exists — strictly more than this arm can say. Scanning shaders here
        prints the same line twice under two headers."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            addon = _pkg(root)
            (addon / "seed.gdshader").write_text(
                '#include "res://assets/shared.gdshaderinc"\n', encoding="utf-8")
            self.assertEqual(cap.res_path_reaches(addon), [])
            self.assertEqual(len(cap.include_reaches(addon, root)), 1,
                             "arm 3 must be the one that reports it")

    def test_the_shipped_burn_down_is_live_and_the_tree_is_green(self):
        """Both directions, arm 1's rule verbatim (ADR-0184 dec. 4, #424): a named list
        and never a pattern. Every entry must still name a real reach, and the tree must
        be green with them accounted for."""
        rc, out = _clean_report()
        self.assertNotIn("STALE ARM6_BURN_DOWN", out)
        self.assertNotIn("RES:// PATH:", out)
        self.assertEqual(rc, 0, out)
        # \U0001f534 DISCRIMINATE, do not hardcode the debt heading. Arm 7's twin of this
        # test opened `assertTrue(cap.ARM7_BURN_DOWN)` and asserted the heading
        # unconditionally; #809 emptied that register and the test went red on the arm
        # reaching its target. This register still carries three rows (Audio's #726) so
        # it has not expired yet — which is exactly when to fix the shape, rather than
        # after the eighth guard in this repo fails the same way.
        if cap.ARM6_BURN_DOWN:
            self.assertIn("RES:// PATH BURN-DOWN", out)
        else:
            self.assertNotIn("RES:// PATH BURN-DOWN", out)
        # And the GREEN SENTENCE carries this arm. The module docstring calls that
        # sentence "the one-line version of the same list", and it shipped without an
        # arm-6 clause — a green that claims less than it checked reads as an arm that
        # is not there. Same shape as `test_the_green_sentence_carries_arm_1`.
        self.assertIn("quote no `res://` path", out)
        self.assertIn("beyond the\nburn-downs above", out,
                      "the clause must say what it does NOT claim: rows are "
                      "excused, so an unqualified 'no res:// path' would be false")

    def test_an_entry_naming_no_path_reach_is_STALE_and_red(self):
        """The burn-down's SECOND direction, which the shipped-list control above cannot
        measure. `assertNotIn("STALE ARM6_BURN_DOWN")` on a green tree passes whether the
        stale branch works or is unreachable, so it is a clean bill nothing measured;
        arm 1 has carried a seeded stale row since ADR-0184 dec. 4 and arm 6 must too.
        Driven in-process against the REAL tree for arm 1's reason: a scratch package
        proves the code path, not that the shipped rows still describe this repo."""
        import contextlib, io
        buf = io.StringIO()
        original = cap.ARM6_BURN_DOWN
        seeded = dict(original)
        seeded[("addons/exmateria_render/fold_bracket/FoldSurface.gd",
                "res://no/such/path.tres")] = ("#0", "a row that names no path reach")
        cap.ARM6_BURN_DOWN = seeded
        try:
            with contextlib.redirect_stdout(buf):
                rc = cap.report_walk(_clean_walk())
        finally:
            cap.ARM6_BURN_DOWN = original
            os.chdir(PROJECT_DIR)
        out = buf.getvalue()
        self.assertIn("STALE ARM6_BURN_DOWN", out)
        self.assertIn("res://no/such/path.tres", out)
        self.assertEqual(rc, 1, out)

    def test_an_unlisted_path_is_RED_and_reaches_the_exit_code(self):
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'const _SEED = preload("res://src/data/JobDatabase.gd")\n', encoding="utf-8")
            r = subprocess.run(
                [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
                 "--root", str(addon), "--system", "Render"],
                capture_output=True, text=True)
            self.assertNotIn("Traceback", r.stderr)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            self.assertIn("RES:// PATH:", r.stdout)
            self.assertIn("res://src/data/JobDatabase.gd", r.stdout)

    def test_the_KERNEL_is_in_this_arms_subject(self):
        """The half of #658 arm 1 structurally cannot cover. `main()` reads
        `if system is None: continue` before arm 1, correctly — the kernel is not one of
        the eleven — so the kernel may `preload` any host file with no report. This arm
        sits BEFORE that `continue`, and the ticket's own seed is a kernel file."""
        kernel = PROJECT_DIR / "addons" / "exmateria_schema"
        if not kernel.is_dir():
            self.skipTest("exmateria_schema not present in this worktree")
        self.assertNotIn(cap._sg.classify(cap._sg._rel(kernel / "colour_model" / "ColorStack.gd")),
                         cap._sg.SYSTEMS,
                         "read as: the kernel books to no system, which is exactly why "
                         "`main()` skips it before arm 1")
        seed = kernel / "colour_model" / "_arm6_probe.gd"
        # addCleanup and not try/finally: an assertion error must still take the seed out
        # of a REAL addon root. It declares no `class_name` and Godot is not running, so
        # nothing caches it, but a probe that can survive a failed run is a tree edit.
        self.addCleanup(lambda: seed.exists() and seed.unlink())
        seed.write_text('extends RefCounted\n'
                        'const _SEED = preload("res://src/data/JobDatabase.gd")\n',
                        encoding="utf-8")
        rows = cap.res_path_reaches(kernel)
        self.assertIn("res://src/data/JobDatabase.gd", [r[2] for r in rows])

class Arm7HostClassNameTests(unittest.TestCase):
    """Arm 7 — a `class_name` under an addon root DECLARED OUTSIDE every addon root.

    Arm 5's rule one level out, exactly as arm 5 is arm 1's rule one level down. Arm 5
    builds `homes` from the addon roots alone, so a type declared in `src/` is in no map
    any arm here reads: five lines in `exmateria_sprite_rig` named one and every arm
    reported OK while goal #5 printed `met`.

    EVERY TEST BELOW CARRIES ITS CONTROL, and for arm 7 the control is the whole point:
    the seed and the control differ ONLY in where the named type is declared. Without it
    the arm could be measuring "a scratch addon names an unknown symbol" and pass.
    """

    def _run(self, addon: Path):
        return subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
             "--root", str(addon), "--system", "Render"],
            capture_output=True, text=True)

    def test_a_host_class_name_is_RED_and_reaches_the_exit_code(self):
        """A `class_name` the host declares under `src/` is under no addon root. A helper
        that fires while nothing routes it to the exit code is still a green guard, so
        this drives `main()` rather than a helper."""
        name, rel = _a_host_class_name()
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                "func f() -> Variant:\n"
                f"\treturn {name}\n",
                encoding="utf-8")
            r = self._run(addon)
            self.assertNotIn("Traceback", r.stderr)
            self.assertIn("HOST class_name:", r.stdout)
            self.assertIn(f"{name} -> declared in {rel}", r.stdout)
            self.assertEqual(r.returncode, 1, r.stdout)

    def test_a_class_name_under_an_addon_root_is_the_CONTROL_and_is_green(self):
        """THE SAME SEED, one word different. `ExMateriaSchema` is declared at
        `addons/exmateria_schema/exmateria_schema.gd`, which IS under an addon root, and
        naming the kernel is what a portable addon is allowed to do (ADR-0139 dec. 9).
        If this went red too, the arm would be measuring the seeding rather than the
        boundary."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                "func f() -> Variant:\n"
                "\treturn ExMateriaSchema.SpriteLayer\n", encoding="utf-8")
            r = self._run(addon)
            self.assertNotIn("Traceback", r.stderr)
            self.assertNotIn("HOST class_name", r.stdout)
            self.assertEqual(r.returncode, 0, r.stdout)

    def test_a_host_autoload_is_arm_2s_row_and_not_this_arms(self):
        """One defect, one report — `_ARM6_REFERRERS`' rule, which subtracts the four
        shader suffixes because arm 3 owns them. `Tune` is a HOST autoload and arm 2
        is the arm that owns the shape; `src/core/Tune.gd` declares no `class_name`, so
        the two arms cannot even collide on the same row. The seed is deliberately
        SYNTHETIC and no longer cites a shipped line: `SpriteLayerManager.gd:121,811`
        was that citation until #847 routed both lines through `TunePort`, and a test
        that quotes the tree as its evidence goes stale the day the tree is fixed."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                "func f() -> void:\n"
                "\tprint(Tune.get_num(\"x\"))\n", encoding="utf-8")
            r = self._run(addon)
            self.assertNotIn("HOST class_name", r.stdout)
            self.assertIn("STANDALONE PARSE", r.stdout,
                          "arm 2 must be the one that reports it")

    def test_a_host_preload_is_arm_6s_row_and_not_this_arms(self):
        """The other half of the same rule, on the PATH axis. `preload` is one of
        `outbound_reaches`' six kinds and arm 6 owns it — with the right stripper, which
        matters: `outbound_reaches` matches `preload`/`load` against the RAW line, so it
        reports `trace_writer.gd:82`'s `load("res://...")` out of a `#` comment. Arm 6
        strips comments and does not."""
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                'const _SEED = preload("res://src/data/JobDatabase.gd")\n',
                encoding="utf-8")
            r = self._run(addon)
            self.assertNotIn("HOST class_name", r.stdout)
            self.assertIn("RES:// PATH:", r.stdout,
                          "arm 6 must be the one that reports it")

    def test_a_NAMED_row_lands_in_the_burn_down_and_not_in_the_red_list(self):
        """The seed CONSTRUCTS BOTH the site and the register row, so it cannot expire
        the day the shipped rows are paid — a seed that borrows a live row is a test of
        the tree, not of the arm, and this repo has watched that expire six times.

        Driven in-process because the row has to be added to `ARM7_BURN_DOWN` before
        `main()` reads it, and a subprocess cannot be reached into.

        The ROW is constructed and the SITE is constructed, but the SYMBOL still has to
        be one the real tree declares outside every addon root — arm 7 indexes the repo,
        not the scratch package. It read `JsonAsset` until #809 moved that file under
        `addons/exmateria_platform/`, at which point the seed silently became the CONTROL
        (a `class_name` under an addon root is exactly what this arm must NOT report) and
        the test failed with the arm working correctly. Derived, it cannot pick a symbol
        that has moved.
        """
        import contextlib, io
        name, _rel = _a_host_class_name()
        with tempfile.TemporaryDirectory() as d:
            addon = _pkg(Path(d))
            (addon / "seed.gd").write_text(
                "extends Node\n"
                "func f() -> Variant:\n"
                f"\treturn {name}\n",
                encoding="utf-8")
            key = (cap._sg._rel(addon / "seed.gd"), name)
            original, argv = cap.ARM7_BURN_DOWN, sys.argv
            cap.ARM7_BURN_DOWN = dict(original)
            cap.ARM7_BURN_DOWN[key] = ("#0", "a constructed row, not a borrowed one")
            sys.argv = ["check_addon_portability.py", "--root", str(addon),
                        "--system", "Render"]
            buf = io.StringIO()
            try:
                with contextlib.redirect_stdout(buf):
                    rc = cap.main()
            finally:
                cap.ARM7_BURN_DOWN, sys.argv = original, argv
                os.chdir(PROJECT_DIR)
            out = buf.getvalue()
            self.assertIn("HOST class_name BURN-DOWN", out)
            self.assertIn("a constructed row, not a borrowed one", out)
            self.assertNotIn("HOST class_name:", out)
            self.assertEqual(rc, 0, out)

    def test_the_shipped_burn_down_is_live_and_the_tree_is_green(self):
        """Both directions, arm 1's rule verbatim (ADR-0184 dec. 4, #424): a named list
        and never a pattern. Every entry must still name a real reach, and the tree must
        be green with them accounted for.

        \U0001f534 This used to open `assertTrue(cap.ARM7_BURN_DOWN)` and then hardcode the
        debt heading — a control that EXPIRES ON SUCCESS. #809 paid the last five rows
        and the register emptied, so the arm stopped printing its heading and this test
        went red on the addon getting BETTER, aborting the whole suite at pre-flight.
        `test_check_addon_install.py` records that as the sixth guard in this repo to
        fail that way; this is the seventh, and it is written the other way round now:
        discriminate on `ARM7_BURN_DOWN` and assert the heading the register ENTAILS.
        rc 0 means nothing unlisted and nothing stale, so on a green tree the burned set
        IS the list — a non-empty list must print the heading and the trailer, an empty
        one must print neither. Both directions are asserted, so a register that went
        quiet while still carrying rows (or the reverse) reds here rather than reading
        as a pass. The debt branch is not left to a list that may be empty: the seeded
        `test_a_NAMED_row_lands_in_the_burn_down_and_not_in_the_red_list` above
        constructs it."""
        rc, out = _clean_report()
        self.assertNotIn("STALE ARM7_BURN_DOWN", out)
        self.assertNotIn("HOST class_name:", out)
        self.assertEqual(rc, 0, out)
        if cap.ARM7_BURN_DOWN:
            self.assertIn("HOST class_name BURN-DOWN", out)
            self.assertIn("line(s) are on ARM7_BURN_DOWN above", out)
        else:
            self.assertNotIn("HOST class_name BURN-DOWN", out)
            self.assertNotIn("on ARM7_BURN_DOWN above", out,
                             "an empty register must not claim rows are excused")
        # And the GREEN SENTENCE carries this arm. A green that claims less than it
        # checked reads as an arm that is not there — `test_the_green_sentence_carries
        # _arm_1`'s shape, and arm 6 shipped without its clause once already.
        self.assertIn("name no `class_name` declared outside every addon root",
                      out)
        self.assertIn("beyond the\nburn-downs above", out,
                      "the clause must say what it does NOT claim: arm 1 and arm 6 "
                      "still carry rows, so an unqualified sentence would be false")

    def test_an_entry_naming_no_class_name_reach_is_STALE_and_red(self):
        """The burn-down's SECOND direction, which the shipped-list control above cannot
        measure: `assertNotIn("STALE ARM7_BURN_DOWN")` on a green tree passes whether the
        stale branch works or is unreachable. Driven in-process against the REAL tree for
        arm 1's reason — a scratch package proves the code path, not that the shipped
        rows still describe this repo."""
        import contextlib, io
        buf = io.StringIO()
        original = cap.ARM7_BURN_DOWN
        seeded = dict(original)
        seeded[("addons/exmateria_render/fold_bracket/FoldSurface.gd",
                "NoSuchClassName")] = ("#0", "a row that names no class_name reach")
        cap.ARM7_BURN_DOWN = seeded
        try:
            with contextlib.redirect_stdout(buf):
                rc = cap.report_walk(_clean_walk())
        finally:
            cap.ARM7_BURN_DOWN = original
            os.chdir(PROJECT_DIR)
        out = buf.getvalue()
        self.assertIn("STALE ARM7_BURN_DOWN", out)
        self.assertIn("NoSuchClassName", out)
        self.assertEqual(rc, 1, out)

    def test_a_shipped_row_outside_a_NARROWED_root_is_out_of_scope_not_stale(self):
        """`--root` NARROWS the subject, so a row naming a file in another package has
        not had its debt paid — it has not been looked at. The list is a claim about the
        WALK and only the walk can falsify it. This is not hypothetical: the same trap
        turned `test_clean_package_exits_green` red the first time arm 1 ran."""
        r = subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
             "--root", "addons/exmateria_render", "--system", "Render"],
            cwd=PROJECT_DIR, capture_output=True, text=True)
        self.assertNotIn("STALE ARM7_BURN_DOWN", r.stdout)
        self.assertNotIn("HOST class_name", r.stdout)
        self.assertEqual(r.returncode, 0, r.stdout)


class DepsAndEngineReaderTests(unittest.TestCase):
    """`_walk_roots.declared_engine/declared_deps/dep_closure/closure_engine` (#1241).

    These readers are the SECOND reading of a file `tests/stranger/shared/rig.sh`
    already reads with `sed`, and until #1241 the rig was the only reader of either
    key in the repo. Two readings of one file is what this repo diffs rather than
    trusts (ADR-0147/0148), so the diff is `test_the_python_reader_and_the_rigs_sed
    _agree` below and not a comment claiming they match.
    """

    def _cfg(self, d: Path, body: str) -> Path:
        root = d / "addons" / "seedaddon"
        root.mkdir(parents=True)
        (root / "plugin.cfg").write_text("[plugin]\n\nname=\"Seed\"\n" + body,
                                         encoding="utf-8")
        return root

    def test_each_engine_word_is_read_back(self):
        for word in _wr.ENGINES:
            with tempfile.TemporaryDirectory() as d, self.subTest(word):
                root = self._cfg(Path(d), 'engine="%s"\n' % word)
                self.assertEqual(_wr.declared_engine(root), word)

    def test_a_plugin_cfg_with_no_engine_RAISES(self):
        """`rig.sh` exits 2 rather than defaulting, *"because a default is how the
        declaration stops being read"*. A Python reader that answered `stock` here would
        answer a question the rig refuses to answer."""
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'tier="system"\n')
            with self.assertRaises(ValueError) as e:
                _wr.declared_engine(root)
            self.assertIn("declares no `engine=`", str(e.exception))

    def test_an_engine_outside_the_two_RAISES(self):
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'engine="mobile"\n')
            with self.assertRaises(ValueError):
                _wr.declared_engine(root)

    def test_a_COMMENTED_engine_is_not_a_declaration(self):
        """`plugin.cfg` carries its reasoning inline as `;` comments, and every shipped
        one DISCUSSES the other engine word at length — `exmateria_almanac`'s block says
        `fork` five times. A reader that matched mid-line would read the prose."""
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), '; engine="fork" -- rejected, see ADR-0194\n'
                                      'engine="stock"\n')
            self.assertEqual(_wr.declared_engine(root), "stock")

    def test_an_ABSENT_deps_key_is_no_deps_and_does_NOT_raise(self):
        """The one place this pair is deliberately asymmetric, and the asymmetry is
        `rig.sh`'s own: *"an addon with no line has no deps; an addon that names one that
        is not there cannot run"*. An absent `engine=` leaves the rig with no binary and
        is unanswerable; an absent `deps=` has one correct answer, and four of the nine
        roots in this tree give it."""
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'engine="stock"\n')
            self.assertEqual(_wr.declared_deps(root), [])
            self.assertEqual(_wr.dep_closure(root), [])

    def test_an_EMPTY_deps_value_is_also_no_deps(self):
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'engine="stock"\ndeps=""\n')
            self.assertEqual(_wr.declared_deps(root), [])

    def test_a_dep_with_no_directory_RAISES(self):
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'engine="stock"\ndeps="exmateria_nosuchthing"\n')
            with self.assertRaises(ValueError) as e:
                _wr.declared_deps(root)
            self.assertIn("exmateria_nosuchthing", str(e.exception))

    def test_a_COMMENTED_deps_is_not_a_declaration(self):
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'engine="stock"\n'
                                      '; deps="exmateria_sprite_rig" -- dropped at #1239\n'
                                      'deps="exmateria_schema"\n')
            self.assertEqual(_wr.declared_deps(root), ["exmateria_schema"])

    def test_the_closure_is_TRANSITIVE_and_is_the_rigs_ORDER(self):
        """`exmateria_catalogue` is the corpus's only non-leaf case and it is the one the
        rig's own note is written about: `exmateria_almanac` declares deps of its own, so
        the closure is wider than the line. The ORDER is part of the answer — the rig
        prints this list in its banner, and a reader diffing the banner against the
        guard's report needs the same STRING, not the same set."""
        root = PROJECT_DIR / "addons" / "exmateria_catalogue"
        self.assertEqual(_wr.declared_deps(root),
                         ["exmateria_almanac", "exmateria_platform", "exmateria_schema"])
        self.assertEqual(_wr.dep_closure(root),
                         ["exmateria_almanac", "exmateria_platform", "exmateria_schema"])
        # The transitivity is REAL and not an accident of this line already naming
        # everything: the almanac's own deps are a subset, so drop them from the
        # subject's line and the closure must put them back.
        self.assertEqual(_wr.declared_deps(PROJECT_DIR / "addons" / "exmateria_almanac"),
                         ["exmateria_platform", "exmateria_schema"])

    def test_a_deps_of_deps_is_pulled_in_and_deduped_once(self):
        """The transitivity arm with a subject that CANNOT pass by naming everything
        itself. `exmateria_catalogue` declares its whole closure already, so the arm
        above cannot tell a transitive walk from a one-level read."""
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'engine="stock"\ndeps="exmateria_catalogue"\n')
            self.assertEqual(
                _wr.dep_closure(root),
                ["exmateria_catalogue", "exmateria_almanac", "exmateria_platform",
                 "exmateria_schema"])

    def test_the_closure_engine_is_FORK_when_ANY_member_is(self):
        """The coupling #1241 is about: the subject declares `stock` truthfully and the
        rig boots the fork, because the binary has to parse everything it STAGES."""
        cat = PROJECT_DIR / "addons" / "exmateria_catalogue"
        self.assertEqual(_wr.declared_engine(cat), "stock")
        self.assertEqual(_wr.declared_engine(PROJECT_DIR / "addons" / "exmateria_schema"),
                         "fork")
        self.assertEqual(_wr.closure_engine(cat), "fork")

    def test_a_stock_only_closure_leaves_the_engine_alone(self):
        """The control. Without it, `closure_engine` could return `fork` unconditionally
        and the arm above would still pass."""
        with tempfile.TemporaryDirectory() as d:
            root = self._cfg(Path(d), 'engine="stock"\ndeps="exmateria_platform"\n')
            self.assertEqual(_wr.declared_engine(PROJECT_DIR / "addons" / "exmateria_platform"),
                             "stock")
            self.assertEqual(_wr.closure_engine(root), "stock")

    def test_the_python_reader_and_the_rigs_sed_agree(self):
        """THE TWO-READINGS DIFF, run rather than asserted in a comment.

        `rig.sh` reads `engine=` and `deps=` with `sed`, this module reads them with
        `re`, and a reader that accepted a LOOSER spelling than the rig does would let a
        declaration land that the rig cannot see — a guard green on a key its only other
        consumer ignores. So the `sed` scripts are lifted OUT of `rig.sh` and run on
        every `plugin.cfg` in the tree: if the rig's spelling changes, this test compares
        against the new one rather than against a copy that has drifted.
        """
        rig = (PROJECT_DIR / "tests" / "stranger" / "shared" / "rig.sh").read_text(
            encoding="utf-8")
        cfgs = sorted((PROJECT_DIR / "addons").glob("*/plugin.cfg")) + sorted(
            (PROJECT_DIR.parent / "exmateria-sound" / "addons").glob("*/plugin.cfg"))
        self.assertGreaterEqual(len(cfgs), 9, "the population collapsed; a zero-row "
                                              "diff agrees with anything")
        for key in ("engine", "deps"):
            scripts = set(re.findall(r"sed -n '(s/\^%s=[^']*)'" % key, rig))
            self.assertEqual(len(scripts), 1,
                             "rig.sh runs %d distinct `sed` scripts for `%s=`: %s"
                             % (len(scripts), key, sorted(scripts)))
            script = scripts.pop()
            for cfg in cfgs:
                with self.subTest(key=key, cfg=cfg.parent.name):
                    sed = subprocess.run(["sed", "-n", script, str(cfg)],
                                         capture_output=True, text=True, check=True)
                    # `head -1`, which is what rig.sh pipes into.
                    first = sed.stdout.splitlines()[:1]
                    if key == "engine":
                        try:
                            mine = [_wr.declared_engine(cfg.parent)]
                        except ValueError:
                            mine = []      # no key: the rig reads "" and exits 2
                        self.assertEqual(first, mine)
                    else:
                        self.assertEqual((first[0].split() if first else []),
                                         _wr.declared_deps(cfg.parent))


class Arm8DeclaredDepsTests(unittest.TestCase):
    """Arm 8 — `deps=` against the reach arm 5 MEASURES, both directions (#1241).

    These score the SHARED clean-tree walk with `dep_rows` re-declared, on
    `Arm1BurnDownTests`' rule: the walk's output is a fact about the tree and the
    registers are claims about the walk, so a seed that only re-declares the rows
    re-scores the SAME walk. The rows are DERIVED from the real ones rather than
    written by hand, so a change to `walk_addons`' row shape breaks these loudly
    instead of leaving them scoring a shape the guard no longer produces.

    ONE arm here seeds the real `plugin.cfg` and drives the shipped script in a
    SUBPROCESS (`test_the_1239_declaration_re_added_to_the_real_plugin_cfg_is_NAMED`).
    Without it every arm below would prove `report_walk`'s half and none of them
    would prove that `walk_addons` still derives a row from the file on disk.
    """

    def _main(self, w, deps_list=None, engine_reg=None):
        import contextlib, io
        buf = io.StringIO()
        od, oe = cap.ARM8_DEPS_NOT_BY_CLASS_NAME, cap.ARM8_CLOSURE_ENGINE
        if deps_list is not None:
            cap.ARM8_DEPS_NOT_BY_CLASS_NAME = deps_list
        if engine_reg is not None:
            cap.ARM8_CLOSURE_ENGINE = engine_reg
        try:
            with contextlib.redirect_stdout(buf):
                rc = cap.report_walk(w)
        finally:
            cap.ARM8_DEPS_NOT_BY_CLASS_NAME, cap.ARM8_CLOSURE_ENGINE = od, oe
            os.chdir(PROJECT_DIR)
        return rc, buf.getvalue()

    # --- the shipped state ------------------------------------------------
    def test_the_shipped_registers_are_live_and_the_tree_is_green(self):
        rc, out = self._main(_clean_walk())
        self.assertNotIn("STALE ARM8_DEPS_NOT_BY_CLASS_NAME", out)
        self.assertNotIn("STALE ARM8_CLOSURE_ENGINE", out)
        self.assertNotIn("UNDECLARED DEPENDENCY", out)
        self.assertNotIn("DECLARED DEPENDENCY NOTHING REACHES", out)
        self.assertNotIn("CLOSURE ENGINE NOT REGISTERED", out)
        self.assertEqual(rc, 0, out)

    def test_the_census_is_PRINTED_and_covers_every_shared_rig_subject(self):
        """The arm is only half a guard if the pair is not on the page: #1241 asks for
        the closure's engine printed BESIDE the subject's own, *"so the pair is a printed
        number that a diff can move, rather than something a reader has to re-derive"*."""
        rc, out = self._main(_clean_walk())
        subjects = {r.root for r in cap._sg._walk_roots.rigs() if r.in_suite}
        # EIGHT since #1225: extraction #7's rig is the last in-walk addon to get one, and
        # `rigs()` is what forced it — the register raises for a root with no row and has no
        # "declared as having none" shape, whatever its message says.
        self.assertEqual(len(subjects), 8, "the shared-rig population moved")
        self.assertIn("declared dependencies (`deps=`) — %d subject(s)" % len(subjects), out)
        for root in subjects:
            self.assertIn("  %s  engine " % cap._sg._rel(root), out)
        self.assertEqual(rc, 0, out)

    def test_the_declared_deps_and_the_measured_reach_are_EXACT_on_every_subject(self):
        """The baseline the ratchet is installed at, stated as a number rather than left
        implicit: exact over every `deps=` key in the corpus, which is why
        `ARM8_DEPS_NOT_BY_CLASS_NAME` ships EMPTY. A ratchet installed anywhere else
        carries a burn-down from its first day.

        🔴 SIX SINCE #1225, AND THE SIXTH IS THE ONE THAT TESTED THE ARM. Extraction #7's
        addon declares five deps and reached a SIXTH package — `exmateria_sound` — by its
        global `class_name`. Arm 8 caught it on the merge, unconditionally and correctly,
        and the fix was not to declare it: `deps=` is what the rig STAGES, and
        `_walk_roots.declared_engine` RAISES on that package because it declares no
        `engine=`. The reach is a PATH to the same façade now, so the pair is exact again
        and the empty register stays honest."""
        carry = [r for r in _clean_walk()["dep_rows"] if r[3]]
        self.assertEqual(len(carry), 6, "the population of addons carrying a `deps=` key "
                                        "moved; re-screen before trusting the empty list")
        for rel, _se, _ce, deps, _closure, meas in carry:
            with self.subTest(rel):
                self.assertEqual(sorted("addons/" + d for d in deps),
                                 sorted(h for h, n in meas.items() if n))

    # --- arm 8, completeness, both directions -----------------------------
    def test_an_undeclared_sibling_reach_is_RED(self):
        """The unconditional direction. `exmateria_render` names five `ExMateriaSchema`
        lines; un-declare the dep and the arm must say so."""
        w = _redeclare_dep_row(
            _clean_walk(), "addons/exmateria_render", deps=[])
        rc, out = self._main(w)
        self.assertIn("UNDECLARED DEPENDENCY", out)
        self.assertIn("addons/exmateria_render  reaches addons/exmateria_schema on 5 "
                      "line(s), undeclared", out)
        self.assertEqual(rc, 1, out)

    def test_a_declared_dep_nothing_reaches_is_RED(self):
        """#1239's defect exactly, and the direction that survived 474 commits because
        nothing in `tools/` read the key."""
        w = _redeclare_dep_row(
            _clean_walk(),
            "addons/exmateria_catalogue",
            deps=["exmateria_almanac", "exmateria_platform", "exmateria_schema",
                  "exmateria_sprite_rig"])
        rc, out = self._main(w)
        self.assertIn("DECLARED DEPENDENCY NOTHING REACHES", out)
        self.assertIn("addons/exmateria_catalogue  declares exmateria_sprite_rig", out)
        self.assertEqual(rc, 1, out)

    def test_a_NAMED_row_is_PERMITTED_and_is_not_in_the_red_list(self):
        """The other side of #424's rule: the list is TRIAGE, so a dep that is real and
        invisible to arm 5 must be nameable without a pattern."""
        w = _redeclare_dep_row(
            _clean_walk(),
            "addons/exmateria_catalogue",
            deps=["exmateria_almanac", "exmateria_platform", "exmateria_schema",
                  "exmateria_sprite_rig"])
        rc, out = self._main(w, deps_list={
            ("addons/exmateria_catalogue", "exmateria_sprite_rig"):
                ("#0", "a seeded row standing in for a res:// or scene dependency")})
        self.assertIn("declared dependencies ARM 5 CANNOT SEE", out)
        self.assertNotIn("DECLARED DEPENDENCY NOTHING REACHES", out)
        self.assertEqual(rc, 0, out)

    def test_a_CLEAN_dep_left_in_the_list_is_STALE_and_red(self):
        """The arm that keeps the exception list from rotting, and the reason this file
        can ship an EMPTY one without the stale arm going vacuous: `exmateria_almanac` IS
        reached on 30 lines, so a row excusing it excuses nothing and must fail."""
        rc, out = self._main(_clean_walk(), deps_list={
            ("addons/exmateria_catalogue", "exmateria_almanac"):
                ("#0", "a row naming a dep arm 5 does measure")})
        self.assertIn("STALE ARM8_DEPS_NOT_BY_CLASS_NAME", out)
        self.assertIn("exmateria_almanac", out.split(
            "STALE ARM8_DEPS_NOT_BY_CLASS_NAME", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_a_row_naming_an_addon_that_is_no_longer_a_subject_is_STALE(self):
        rc, out = self._main(_clean_walk(), deps_list={
            ("addons/exmateria_gone", "exmateria_schema"): ("#0", "a row with no subject")})
        self.assertIn("STALE ARM8_DEPS_NOT_BY_CLASS_NAME", out)
        self.assertEqual(rc, 1, out)

    # --- arm 8b, the closure's engine, three directions -------------------
    def test_the_shipped_register_records_what_the_TREE_measures(self):
        """A register of names would pass on a row whose pair had inverted; these are
        rows of FACTS, so each is re-measured from `plugin.cfg` here."""
        self.assertTrue(cap.ARM8_CLOSURE_ENGINE, "an empty register makes every arm "
                                                 "below vacuous")
        for rel, (se, ce, owner, why) in cap.ARM8_CLOSURE_ENGINE.items():
            with self.subTest(rel):
                root = PROJECT_DIR / rel
                self.assertEqual(_wr.declared_engine(root), se)
                self.assertEqual(_wr.closure_engine(root), ce)
                self.assertNotEqual(se, ce, "a row whose pair AGREES registers no "
                                            "divergence and is stale by construction")
                self.assertTrue(owner and why)

    def test_a_NEW_divergence_nobody_registered_is_RED(self):
        """The direction that fires when a `stock` subject gains a `fork` dependency —
        or when a subject's own `engine=` is edited away from its closure's."""
        w = _redeclare_dep_row(
            _clean_walk(), "addons/exmateria_sprite_rig", subject_engine="stock")
        rc, out = self._main(w)
        self.assertIn("CLOSURE ENGINE NOT REGISTERED", out)
        self.assertIn('addons/exmateria_sprite_rig  declares engine="stock", closure '
                      'needs "fork"', out)
        self.assertIn("[UNREGISTERED]", out)
        self.assertEqual(rc, 1, out)

    def test_a_divergence_that_WENT_AWAY_is_STALE_and_red(self):
        """#1239's own near-miss in guard form, and the loud direction: a row leaving
        this register means the BOOTED BINARY MOVED. Dropping `exmateria_sprite_rig`
        (`fork`) from the catalogue would have flipped that rig to a stock binary, and
        did not only because #1180 had already added `exmateria_schema` (also `fork`)."""
        w = _redeclare_dep_row(
            _clean_walk(), "addons/exmateria_catalogue", closure_engine="stock")
        rc, out = self._main(w)
        self.assertIn("STALE ARM8_CLOSURE_ENGINE", out)
        self.assertIn("addons/exmateria_catalogue", out.split(
            "STALE ARM8_CLOSURE_ENGINE", 1)[1])
        self.assertEqual(rc, 1, out)

    def test_a_row_recording_the_WRONG_pair_is_red(self):
        """The third direction, and it is what makes the register's CONTENT load-bearing
        rather than just its keys."""
        w = _redeclare_dep_row(
            _clean_walk(), "addons/exmateria_catalogue",
                             subject_engine="fork", closure_engine="stock")
        rc, out = self._main(w)
        self.assertIn("ARM8_CLOSURE_ENGINE ROW DISAGREES WITH THE TREE", out)
        self.assertIn("registered stock -> fork, measured fork -> stock", out)
        self.assertEqual(rc, 1, out)

    # --- the derivation, end to end -------------------------------------
    def test_the_1239_declaration_re_added_to_the_real_plugin_cfg_is_NAMED(self):
        """THE ONE ARM THAT PROVES THE WALK AND NOT JUST THE REPORT. Every arm above
        re-declares `dep_rows` in memory, which scores `report_walk`'s half; this writes
        #1239's actual defect back into `addons/exmateria_catalogue/plugin.cfg` and
        drives the SHIPPED script in a subprocess, so the `plugin.cfg` read, the closure
        walk, the arm-5 join and the exit code are all in the subject.

        The file is restored byte-for-byte AND mtime-for-mtime in `finally`: `_tree_
        signature` above hashes `st_mtime_ns`, so restoring the bytes alone would spend
        a second ~19.5 s whole-tree walk on the next arm that asks for one.
        """
        cfg = PROJECT_DIR / "addons" / "exmateria_catalogue" / "plugin.cfg"
        original = cfg.read_bytes()
        st = cfg.stat()
        self.assertIn(b'\ndeps="exmateria_almanac exmateria_platform exmateria_schema"\n',
                      original, "the catalogue's `deps=` line moved; re-point the seed")
        try:
            cfg.write_bytes(original.replace(
                b'\ndeps="exmateria_almanac exmateria_platform exmateria_schema"\n',
                b'\ndeps="exmateria_almanac exmateria_platform exmateria_schema '
                b'exmateria_sprite_rig"\n'))
            r = subprocess.run(
                [sys.executable, str(TOOLS_DIR / "check_addon_portability.py")],
                cwd=PROJECT_DIR, capture_output=True, text=True)
        finally:
            cfg.write_bytes(original)
            os.utime(cfg, ns=(st.st_atime_ns, st.st_mtime_ns))
        self.assertEqual(cfg.read_bytes(), original)
        self.assertIn("DECLARED DEPENDENCY NOTHING REACHES", r.stdout)
        self.assertIn("addons/exmateria_catalogue  declares exmateria_sprite_rig",
                      r.stdout)
        self.assertEqual(r.returncode, 1, r.stdout)

    def test_the_seed_is_what_reddens_it_and_not_the_tree(self):
        """The control for the arm above — the same subprocess, unseeded, is GREEN. It
        also catches a leaked seed, which would otherwise make that arm's red look
        structural."""
        r = subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py")],
            cwd=PROJECT_DIR, capture_output=True, text=True)
        self.assertNotIn("DECLARED DEPENDENCY NOTHING REACHES", r.stdout)
        self.assertNotIn("UNDECLARED DEPENDENCY", r.stdout)
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_a_NARROWED_root_scores_no_dep_row_at_all(self):
        """`--root` NARROWS the walk to one package, so `homes` holds only that package's
        `class_name`s and arm 5 measures ZERO sibling reaches BY CONSTRUCTION — every
        declared dep would read as unreached. This is a claim about the WALK and only the
        walk can falsify it, which is arm 1's rule with a sharper reason."""
        r = subprocess.run(
            [sys.executable, str(TOOLS_DIR / "check_addon_portability.py"),
             "--root", "addons/exmateria_render", "--system", "Render"],
            cwd=PROJECT_DIR, capture_output=True, text=True)
        self.assertNotIn("declared dependencies (`deps=`)", r.stdout)
        self.assertNotIn("DECLARED DEPENDENCY NOTHING REACHES", r.stdout)
        self.assertNotIn("STALE ARM8_CLOSURE_ENGINE", r.stdout)
        self.assertEqual(r.returncode, 0, r.stdout)



if __name__ == "__main__":
    unittest.main()
