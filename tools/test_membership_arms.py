"""Calibration tests for `membership_arms.py` — the five arms `arm7_membership.py` cannot see.

`arm7_membership.py` earned its numbers by being calibrated three ways before anyone
quoted it (ADR-0243 dec. 11). This file owes the same debt for arms 1, 3, 4, 4b and 5,
and the obvious calibration is VACUOUS in the same way its predecessor's was: goal #5 is
enforcing, so every real addon reads arm-1 zero and arm-5-not-free zero, and `0 == 0`
passes whether the code works or returns `{}`.

So every agreement test below is paired with a LIVENESS witness on a set the guard
reports NON-EMPTY:

  * arm 5 — `sibling_class_reaches` on `exmateria_sprite_rig` and `exmateria_battlefield`
    is 337 lines tree-wide and never zero. Compared row for row INCLUDING line numbers.
  * arm 6 — `res_path_reaches` on the sound package is the three `ARM6_BURN_DOWN` rows.
    Two of them are a BARE quoted literal, a shape `all_shapes` does not scan at all, so
    the test asserts the direction that holds and proves each exception by predicate
    rather than excusing it by name. `test_the_catalogue_has_no_row_outside_that_universe`
    is the control that says the gap does not touch the membership this pass rules on.
  * arms 4 / 4b / 5 — these ARE the guard's own functions, handed a `_FileSet` rather
    than a directory, so what is under test is that seam: the equality is only meaningful
    because a flat file list can deliver a different set than `root.rglob("*")`. Read with
    the own-names filter OFF as well, for `arm7_membership`'s calibration-1 reason — with
    it on the platform owns all but `psx_gamma`, which is goal #5 working.
  * arm 1 — has no non-empty subject inside an addon (that IS goal #5), so its liveness
    witness is the HOST membership this instrument was built for: the Character Catalogue
    reaches `ExMateriaSpriteRig`, which books to the `Sprite Rig` system, on one line.
    A stub returning `{}` fails it.

`TwoSpellingsOfOneAutoload` is the seed-red set. It pins the finding that motivated the
`2_declared_bare` row: `autoload_reaches` requires the dot, so `catalog = CharacterCatalog`
is a standalone-parse break no arm of the guard can see. Both arms are held — that the
dotted predicate finds the dotted line, and that it does NOT find the bare one — because a
scan that counted both would report the same total for the wrong reason. 🔴 ITS SUBJECT
CHANGED IN PASS 3. It was seeded on `CharacterCatalog`, whose two reach sites pass 3 then
PAID — both now go through `get_node_or_null(^"CharacterCatalog")`, so re-pinning it there
would assert `[] == []` and pass for a broken predicate. It is re-based on `PerfMonitor`
under `src/debug/`, which is live at 5 dotted and 4 bare. A control that depends on the
defect expires when the defect is paid; the seed has to move, not be deleted.

`TestsAreNotOutsideTheFacade` pins ADR-0211 dec. 5 against the classifier's walk roots:
`tests/` is not one, so a façade counted from `src/` alone publishes SEVEN names where TEN
are reached. Re-taken at the pass-3 address, where the reading itself had to move: after
the shed there is no `class_name` in the membership, so `ma.inbound()` — the pre-move
instrument — is structurally blind to this addon and the reach lives in the ADR-0211
dec. 4 alias lines instead. See `_alias_sites`.

Run from tools/:
    uv run python -m unittest test_membership_arms
"""

from __future__ import annotations

import os
import re
import pathlib
import unittest

_HERE = pathlib.Path(__file__).resolve().parent
os.chdir(_HERE.parent)

import membership_arms as ma  # noqa: E402
import check_addon_portability as cap  # noqa: E402


def _members(addon: str):
    ns = ma.A._load()
    return sorted(p.as_posix() for p in pathlib.Path(addon).rglob("*")
                  if p.is_file() and p.suffix in ns["SOURCE_SUFFIXES"])


# The ADR-0257 dec. 2 membership at the address #1025 pass 3 gave it. TEN files,
# ENUMERATED rather than globbed: the addon root also holds the façade, `plugin.gd`
# and `install/CatalogueContent.gd`, none of which is a member — they are what the
# move BUILT, and a glob would fold them into every number below and make the
# before/after comparison meaningless. Pre-move these paths were
# `src/characters/*.gd` + `src/debug/RosterDebugView.gd` +
# `src/scenarios/AllTemplatesSeeder.gd`, and ADR-0262 dec. 2's readings were taken
# there; every number in `CataloguePinnedToTheTree` says which of the two trees it
# came from.
CATALOGUE = sorted([
    "addons/exmateria_catalogue/identity/Character.gd",
    "addons/exmateria_catalogue/identity/SlugBinding.gd",
    "addons/exmateria_catalogue/identity/UnitBirthdays.gd",
    "addons/exmateria_catalogue/identity/UnitNames.gd",
    "addons/exmateria_catalogue/inspection/RosterDebugView.gd",
    "addons/exmateria_catalogue/registry/CharacterCatalog.gd",
    "addons/exmateria_catalogue/seeding/AllTemplatesSeeder.gd",
    "addons/exmateria_catalogue/seeding/CatalogueReplay.gd",
    "addons/exmateria_catalogue/templates/CharacterTemplateResolver.gd",
    "addons/exmateria_catalogue/templates/ResidueManifest.gd",
])
INSIDE = ("addons/exmateria_catalogue/",)


class Arm5AgreesWithTheGuard(unittest.TestCase):
    """`arm5_resolved` hands the guard its OWN arm 5, so it must reproduce it exactly.

    The one difference is deliberate and is filtered here rather than papered over: a
    `_FileSet` is not any `class_name`'s home, so a membership drawn FROM an addon sees
    that addon's own façade as foreign. Real memberships live in `src/` and declare no
    façade, so the case cannot arise where the instrument is used; it arises only in this
    test, which is why the test says so instead of the tool guessing.
    """

    def _root(self, name: str):
        roots, _ = cap.full_roots()
        for r in roots:
            if r.name == name:
                return r
        self.skipTest("%s is not a walk root in this worktree" % name)

    def _compare(self, name: str):
        root = self._root(name)
        roots, _ = cap.full_roots()
        homes = cap.class_name_homes(roots)
        published = cap.published_members(roots)
        guard = {(rel, sym, tuple(lines))
                 for rel, sym, _h, lines in
                 cap.sibling_class_reaches(root, homes, published)}
        mine = {(rel, sym, tuple(lines))
                for rel, sym, h, lines in ma.arm5_resolved(_members("addons/" + name))
                if pathlib.Path(h).resolve() != root.resolve()}
        self.assertTrue(guard, "liveness: the guard must report rows here")
        self.assertEqual(guard, mine)

    def test_sprite_rig_matches_and_is_not_empty(self):
        self._compare("exmateria_sprite_rig")

    def test_battlefield_matches_and_is_not_empty(self):
        self._compare("exmateria_battlefield")

    def test_the_shape_scan_is_a_floor_not_the_answer(self):
        """The alias route (ADR-0211 dec. 4) is invisible to a `class_name` token scan."""
        shape = sum(len(v) for v in ma.arms(CATALOGUE, INSIDE)["5"].values())
        resolved = sum(len(lines) for _r, _n, _h, lines in ma.arm5_resolved(CATALOGUE))
        self.assertEqual(shape, 11)
        self.assertEqual(resolved, 59)
        self.assertGreater(resolved, shape * 4)


class Arm6AgreesWithTheGuard(unittest.TestCase):
    """Every row the guard reports must be here. The converse does not hold, on purpose.

    `arm7_membership.all_shapes` matches `preload`/`const` on the RAW line, so a `res://`
    path inside a comment scores — `exmateria_sound/runtime/effect_sound/trace_writer.gd:82`
    is one. That is the inherited scanner's behaviour and this instrument does not
    second-guess it; the direction that matters for a pre-move audit is that nothing the
    guard would report is MISSING, and an over-report is visible in the printed rows.
    """

    def test_sound_package_preload_and_const_rows_are_all_present(self):
        addon = pathlib.Path("../exmateria-sound/addons/exmateria_sound")
        if not addon.is_dir():
            self.skipTest("sound package not linked in this worktree")
        guard = {(rel, ln, target) for rel, ln, target in cap.res_path_reaches(addon)}
        self.assertTrue(guard, "liveness: the guard must report rows here")
        a = ma.arms(_members(str(addon)))
        mine = {(rel, ln, "res://" + target)
                for (_k, target, _d, _b), v in a["6"].items() for rel, ln in v}
        # Every row the guard reports that `all_shapes` CAN see must be here, and every
        # row it cannot must fail the predicate rather than be excused by name.
        for rel, ln, target in sorted(guard - mine):
            raw = pathlib.Path(rel).read_text(errors="ignore").splitlines()[ln - 1]
            self.assertNotRegex(raw, r'(?:preload|load)\("res://')
            self.assertNotRegex(raw, r'^\s*const\s+\w+\s*:?=\s*"res://')

    def test_the_catalogue_has_no_row_outside_that_universe(self):
        """So its arm-6 seven is exact rather than a floor. The control for the above."""
        import re as _re
        bare = []
        for rel in CATALOGUE:
            for i, raw in enumerate(
                    pathlib.Path(rel).read_text(errors="ignore").splitlines(), 1):
                if "res://" not in raw or raw.lstrip().startswith("#"):
                    continue
                if _re.search(r'(?:preload|load)\("res://', raw):
                    continue
                if _re.match(r'^\s*const\s+\w+\s*:?=\s*"res://', raw):
                    continue
                bare.append((rel, i, raw.strip()))
        self.assertEqual(bare, [])


class Arm4AgreesWithTheGuard(unittest.TestCase):
    """Arms 4/4b ARE the guard's functions, so what is under test is the `_FileSet` seam.

    The equality below would be a tautology if `_FileSet` were the addon directory. It is
    not: it is a flat list built by the caller, and the thing that can go wrong is that it
    delivers a DIFFERENT set of files than `root.rglob("*")` — a suffix dropped, a nested
    directory missed, a symlink not followed. That is what these assert, on a subject
    where the guard's answer is non-empty in both readings.
    """

    def _root(self):
        roots, _ = cap.full_roots()
        for r in roots:
            if r.name == "exmateria_platform":
                return r
        self.skipTest("exmateria_platform is not a walk root in this worktree")

    def test_the_file_set_delivers_the_same_pushes_with_the_filter_off(self):
        root = self._root()
        guard = cap.shader_global_reaches(root, set())
        self.assertTrue(guard, "liveness: the filter is off, the set must be non-empty")
        mine = cap.shader_global_reaches(ma._FileSet(_members("addons/exmateria_platform")),
                                         set())
        self.assertEqual(sorted(guard), sorted(mine))

    def test_the_membership_owns_all_but_psx_gamma(self):
        """The filter ON is the real question and its answer is not zero here."""
        a = ma.arms(_members("addons/exmateria_platform"))
        self.assertEqual({name for _rel, name, _side, _lines in a["4"]}, {"psx_gamma"})

    def test_arm_4b_sees_the_declarations_the_guard_sees(self):
        root = self._root()
        guard = cap.own_global_uniform_declarations(root)
        self.assertTrue(guard, "liveness: the platform declares global uniforms")
        a = ma.arms(_members("addons/exmateria_platform"))
        self.assertEqual(sorted(guard), sorted(a["4b"]))

    def test_the_catalogue_declares_and_binds_nothing(self):
        a = ma.arms(CATALOGUE, INSIDE)
        self.assertEqual(a["4"], [])
        self.assertEqual(a["4b"], [])


# The seed `Arm1HasALiveSubject` stands on. It is a FILE ON DISK under the catalogue
# root, not a fixture string, because arm 1's whole subject is "a file under an addon
# root" and a synthetic path would test the dictionary rather than the walk.
_ARM1_SEED = pathlib.Path("addons/exmateria_catalogue/templates/_arm1_liveness_seed.gd")
_ARM1_SEED_TEXT = ("""extends RefCounted
# Written and deleted by `Arm1HasALiveSubject` (test_membership_arms.py). If you are
# reading this in a committed tree, a test run died between its write and its cleanup:
# DELETE IT. `check_addon_portability.py` reds on it, which is the point.
const SpritePaletteResolver = ExMateriaSpriteRig.SpritePaletteResolver
""")


class Arm1HasALiveSubject(unittest.TestCase):
    """Arm 1 reads zero on every addon — that IS goal #5 — so the subject is SEEDED.

    🔴 ITS SUBJECT CHANGED AT #1071, for `TwoSpellingsOfOneAutoload`'s reason and by
    the same rule: a control that depends on the defect expires when the defect is
    paid, and the seed has to move rather than be deleted. The witness used to be the
    Character Catalogue reaching `ExMateriaSpriteRig` on one line — `ARM1_BURN_DOWN`'s
    last row. #1071 paid it (ADR-0272), so `ma.arms(CATALOGUE, INSIDE)["1"]` is now
    `{}` and every assertion written against it would read `{} == {}` and pass for a
    stub returning nothing.

    Unlike that one, this seed could NOT move to another live subject: there is no
    longer any file under any addon root that reaches one of the eleven systems, which
    is goal #5 fully met and is a state the tree is meant to stay in. So the liveness
    witness is written, measured and removed inside the test, and BOTH directions are
    held — the real membership must read zero, and the same walk over the same
    membership plus one seeded line must read one.
    """

    def _seeded(self):
        _ARM1_SEED.write_text(_ARM1_SEED_TEXT)
        self.addCleanup(_ARM1_SEED.unlink, missing_ok=True)
        return ma.arms(CATALOGUE + [_ARM1_SEED.as_posix()], INSIDE)

    def test_the_real_membership_reaches_no_system(self):
        """The paid direction. On its own this passes for a stub; see the next test."""
        self.assertEqual(ma.arms(CATALOGUE, INSIDE)["1"], {})

    def test_a_seeded_reach_is_seen_and_books_to_its_system(self):
        a = self._seeded()
        rows = {(target, dst_bucket)
                for (_k, target, _dst, dst_bucket) in a["1"]}
        self.assertEqual(rows, {("ExMateriaSpriteRig", "Sprite Rig")})
        self.assertEqual(sum(len(v) for v in a["1"].values()), 1)
        sites = [rel for v in a["1"].values() for rel, _line in v]
        self.assertEqual(sites, [_ARM1_SEED.as_posix()])

    def test_arm_1_is_not_arm_7(self):
        """Arm 7 reads zero on the SEEDED membership too. If arm 1 mirrored arm 7's
        addon-root filter, the seeded line would be invisible to it as well."""
        a = self._seeded()
        self.assertEqual(a["7"], {})
        self.assertTrue(a["1"], "arm 1 must see what arm 7's addon-root filter drops")

    def test_every_arm_1_row_books_to_one_of_the_eleven(self):
        ns = ma.A._load()
        a = self._seeded()
        self.assertTrue(a["1"], "liveness: an empty walk books nothing and proves nothing")
        for (_k, _t, _d, bucket) in a["1"]:
            self.assertIn(bucket, ns["SYSTEMS"])

    def test_the_seed_is_gone_and_the_guard_is_green(self):
        """The leak arm. A seed left behind reds `check_addon_portability` for everyone,
        so this says the file is absent AND that its absence is what green means."""
        self.assertFalse(_ARM1_SEED.exists(), "%s leaked" % _ARM1_SEED)
        self.assertEqual(ma.arms(CATALOGUE, INSIDE)["1"], {})


# The live subject for `TwoSpellingsOfOneAutoload` below, chosen mechanically rather
# than by taste: of the eleven autoloads declared inside their own directory, this is
# the one whose directory reaches it BOTH ways (5 dotted, 4 bare, 2026-09-08). Every
# other candidate reads bare-zero and would make half the class vacuous.
_TWO_SPELLING_AUTOLOAD = "PerfMonitor"
_TWO_SPELLING_DIR = "src/debug/"


class TwoSpellingsOfOneAutoload(unittest.TestCase):
    """`autoload_reaches` needs the dot; the bare identifier breaks the parse anyway.

    🔴 THE CATALOGUE IS NO LONGER THIS CLASS'S SUBJECT, AND THAT IS THE POINT OF
    `CatalogueAutoloadExposureIsPaid` below. ADR-0262 dec. 6 priced the catalogue's
    exposure at TWO lines — `src/characters/Character.gd:209` spelled
    `CharacterCatalog.` and `src/scenarios/AllTemplatesSeeder.gd:184` spelled bare —
    and #1025 pass 3 PAID both by moving them to the node-path spelling. Re-pinning
    this class on the catalogue would therefore assert `[] == []` on both arms, which
    is exactly the vacuous shape this file's own docstring exists to refuse. The
    finding is about the INSTRUMENT, not about the catalogue, so it keeps its claim
    and moves to a subject where the guard's answer is non-empty in both readings.
    """

    def setUp(self):
        members = sorted(p.as_posix()
                         for p in pathlib.Path(_TWO_SPELLING_DIR).glob("*.gd"))
        self.a = ma.arms(members, (_TWO_SPELLING_DIR,))
        self.hits = self.a["2_declared"][_TWO_SPELLING_AUTOLOAD]
        self.bares = self.a["2_declared_bare"][_TWO_SPELLING_AUTOLOAD]

    def test_the_membership_declares_the_autoload(self):
        self.assertIn(_TWO_SPELLING_AUTOLOAD, self.a["2_declared"])

    def test_the_dotted_spelling_is_arm_2s_own_predicate(self):
        """Liveness: non-empty, and every row really does carry the dot."""
        self.assertTrue(self.hits, "liveness: the dotted reading must be non-empty")
        ns = ma.A._load()
        strip = ns["strip_noncode"]
        for rel, i in self.hits:
            line = strip(pathlib.Path(rel).read_text(errors="ignore"))[i - 1]
            self.assertRegex(line, r"(?<![.\w])" + _TWO_SPELLING_AUTOLOAD + r"\s*\.")

    def test_the_bare_spelling_is_found_and_is_a_different_line(self):
        self.assertTrue(self.bares, "liveness: the bare reading must be non-empty")
        for row in self.bares:
            self.assertNotIn(row, self.hits)

    def test_no_arm_of_the_guard_sees_the_bare_line(self):
        """The claim the ADR rests on: arm 2 needs a dot, arm 2b needs a string."""
        ns = ma.A._load()
        strip = ns["strip_noncode"]
        for rel, i in self.bares:
            line = strip(pathlib.Path(rel).read_text(errors="ignore"))[i - 1]
            self.assertIn(_TWO_SPELLING_AUTOLOAD, line)
            self.assertNotIn(_TWO_SPELLING_AUTOLOAD + ".", line)
            self.assertNotIn("/root/", line)

    def test_the_two_spellings_are_not_summed(self):
        self.assertEqual(set(self.hits) & set(self.bares), set())

    def test_a_foreign_autoload_is_a_different_row(self):
        """Arm 2 proper is zero on the CATALOGUE, and that is a different statement."""
        self.assertEqual(
            sum(len(v) for v in ma.arms(CATALOGUE, INSIDE)["2"].values()), 0)


class CatalogueAutoloadExposureIsPaid(unittest.TestCase):
    """ADR-0262 dec. 6's two lines, after #1025 pass 3 chose the node-path spelling.

    The zero below is only readable BECAUSE `TwoSpellingsOfOneAutoload` above proves
    the same two predicates non-empty on a live subject in the same run. Read alone it
    is indistinguishable from an instrument that stopped looking.
    """

    def setUp(self):
        self.a = ma.arms(CATALOGUE, INSIDE)

    def test_the_membership_still_declares_the_autoload(self):
        """It MOVED with the addon (dec. 6); it did not stop being the membership's."""
        self.assertEqual(sorted(self.a["2_declared"]), ["CharacterCatalog"])

    def test_both_spellings_are_now_zero(self):
        self.assertEqual(self.a["2_declared"]["CharacterCatalog"], [])
        self.assertEqual(self.a["2_declared_bare"]["CharacterCatalog"], [])

    def test_the_two_sites_reach_the_live_node_by_path_instead(self):
        """What paid them. Both spell `get_node_or_null(^"CharacterCatalog")`.

        `exmateria_platform`'s `DisplayPort.gd:104` and `exmateria_sound`'s
        `spu_audio_debug_panel.gd:71` are the corpus precedent, and both files record
        that the bare identifier does not parse in a project without the `[autoload]`.
        """
        for rel in ("addons/exmateria_catalogue/registry/CharacterCatalog.gd",
                    "addons/exmateria_catalogue/identity/Character.gd"):
            body = pathlib.Path(rel).read_text(errors="ignore")
            self.assertIn('get_node_or_null(^"CharacterCatalog")', body,
                          "%s must reach the live node by path" % rel)

    def test_arm_2b_still_reads_zero_because_the_path_is_the_addons_own(self):
        """Arm 2b HAS an own-singleton exemption, decided on the `res://` path in the
        `[autoload]` line — which `plugin.gd` writes and `project.godot` carries."""
        self.assertEqual(sum(len(v) for v in self.a["2b"].values()), 0)


_ALIAS = re.compile(r"^const\s+\w+\s*(?::=|=)\s*ExMateriaCatalogue\.(\w+)\s*$", re.M)
_PUBLISHED = re.compile(r"^const\s+(\w+)\s*=\s*preload\(", re.M)
_FACADE = "addons/exmateria_catalogue/exmateria_catalogue.gd"


def _published() -> set:
    return set(_PUBLISHED.findall(pathlib.Path(_FACADE).read_text(errors="ignore")))


def _alias_sites() -> dict:
    """`{published name: [host rel path, ...]}` over the ADR-0211 dec. 4 alias lines.

    This REPLACES `ma.inbound()` as the reading of the façade's reach. After the pass-3
    shed there is no `class_name` left in the membership, so `inbound()` — which resolves
    identifiers against the engine-global table — returns exactly `{"CharacterCatalog"}`,
    the autoload name, for every possible caller. It is not broken; it has become
    structurally unable to see this addon, which is what ADR-0212 dec. 1 does to every
    extracted system. The alias line is where the reach moved to.
    """
    out = {}
    for root in ("src", "tests"):
        for q in sorted(pathlib.Path(root).rglob("*.gd")):
            for name in _ALIAS.findall(q.read_text(errors="ignore")):
                out.setdefault(name, []).append(q.as_posix())
    return out


class TestsAreNotOutsideTheFacade(unittest.TestCase):
    """ADR-0211 dec. 5 against `classify_blueprint.WALK_ROOTS`, which excludes `tests/`.

    Re-taken at the pass-3 address. The pre-move form read the façade surface off
    `ma.inbound(CATALOGUE)`; see `_alias_sites` for why that reading is now vacuously
    `{"CharacterCatalog"}` and what replaced it. The FINDING is unchanged and the
    numbers moved by one in each column: nine names reached / seven from `src/` became
    TEN reached / SEVEN from `src/`, because `CharacterCatalog` joined the published
    surface (two host files preload a fresh one) and it is preloaded only from `tests/`.
    """

    def setUp(self):
        self.sites = _alias_sites()

    def test_every_published_name_is_reached_and_the_set_is_the_ten(self):
        """The liveness witness the rest of the class rests on: a stub `_alias_sites`
        returning `{}` fails here before it can make the two counts below agree at 0."""
        pub = _published()
        self.assertEqual(len(pub), 10)
        self.assertEqual(set(self.sites), pub)
        self.assertEqual(sum(len(v) for v in self.sites.values()), 71)

    def test_three_names_are_reached_only_from_tests(self):
        for name in ("CharacterCatalog", "UnitBirthdays", "UnitNames"):
            hits = self.sites.get(name, [])
            self.assertTrue(hits, "%s must be reached from somewhere" % name)
            self.assertTrue(all(rel.startswith("tests/") for rel in hits),
                            "%s is expected to be test-only" % name)
        # Direction control: a name that IS reached from `src/`, so the predicate above
        # is not passing because `startswith` matches everything.
        self.assertTrue(any(rel.startswith("src/") for rel in self.sites["Character"]))

    def test_a_src_only_reading_publishes_three_fewer_names(self):
        src_only = {k for k, v in self.sites.items()
                    if any(rel.startswith("src/") for rel in v)}
        everywhere = {k for k, v in self.sites.items() if v}
        self.assertEqual(len(everywhere), 10)
        self.assertEqual(len(src_only), 7)
        self.assertEqual(len(everywhere) - len(src_only), 3)

    def test_the_autoload_is_published_but_is_not_how_the_host_reaches_it(self):
        """`CharacterCatalog` is on the façade for the two files that mint a FRESH one.
        Every other host site reaches the live node, and it is not a `class_name`."""
        ns = ma.A._load()
        t = ns["_tables"]()
        self.assertIn("CharacterCatalog", _published())
        self.assertEqual(len(self.sites["CharacterCatalog"]), 2)
        self.assertNotIn("CharacterCatalog", t["cname"])


class CataloguePinnedToTheTree(unittest.TestCase):
    """The nine-arm reading ADR-0262 rules on, RE-TAKEN at the pass-3 address (#1025).

    Every number below is a re-take, not a copy: the membership is the same ten files
    at a new address, so a value that did not move is a claim in its own right.

    RE-TAKEN AGAIN AT #1071 (ADR-0272), which paid `ARM1_BURN_DOWN`'s last row. Four
    of these numbers moved and each one names what moved it; the rest are unchanged
    across both re-takes, which is the stronger half of what this class is for.
    """

    def test_the_membership_is_ten_files_and_1676_lines(self):
        """1,581 before the move. The +95 is the shed, the addon's own prose, and the
        self-preload the stranger rig found: ten `class_name` lines removed, the host-use
        citations ADR-0212 dec. 1 requires written into the members' headers, and the
        fifteen-line block in `identity/Character.gd` that re-declares `Character` as a
        `const` because shedding the engine global took the name away from the nine lines
        inside that same file which name it. That block is a FIX, not prose — the host
        tree cannot see the break it repairs, because a warm `.godot` global-class cache
        still answers `Character` from a deleted `res://src/characters/` path. Only the
        stranger rig (ADR-0194 dec. 3) and a cold cache report it.

        1,673 until #1071. The +3 is net in ONE member: `templates/
        CharacterTemplateResolver.gd` lost the `ExMateriaSpriteRig` alias, its
        ADR-0211 dec. 4 comment and the `body_palette_row` key, and gained the
        paragraph in `resolve()`'s docstring saying it does NOT answer that row
        (ADR-0272 dec. 1). A line count that did not move would mean the severance
        had not touched the file it was about."""
        self.assertEqual(len(CATALOGUE), 10)
        self.assertEqual(
            sum(len(pathlib.Path(m).read_text(errors="ignore").splitlines())
                for m in CATALOGUE), 1676)

    def test_the_nine_arms(self):
        a = ma.arms(CATALOGUE, INSIDE)
        got = {k: sum(len(v) for v in a[k].values()) for k in ("1", "2", "2b", "3", "5", "6")}
        got["4"], got["4b"] = len(a["4"]), len(a["4b"])
        got["7"] = sum(len(h["lines"]) for h in a["7"].values())
        self.assertEqual(got, {"1": 0, "2": 0, "2b": 0, "3": 0, "4": 0, "4b": 0,
                               "5": 11, "6": 0, "7": 0})

    def test_arm_5_splits_eight_almanac_three_platform_one_sprite_rig(self):
        a = ma.arms(CATALOGUE, INSIDE)
        by_root = {}
        for (_k, _t, dst, _b), v in a["5"].items():
            by_root[dst.split("/")[1]] = by_root.get(dst.split("/")[1], 0) + len(v)
        self.assertEqual(by_root, {"exmateria_almanac": 8, "exmateria_platform": 3})

    def test_arm_5_resolved_is_fifty_three_almanac_six_platform_two_sprite_rig(self):
        """The number the destination question turns on. 53 are debt; 6 are free.

        Identical to the pre-move reading, which is ADR-0262 soft spot S1 discharged:
        S1 asked whether the `src/`-address arm-5 shape survived the move, and it does,
        row for row. It is also why #1059 still governs the report card — the 53 debt
        lines are `_system_of`'s tier answer, not an artefact of where the files sat.

        `exmateria_sprite_rig: 2` until #1071, and the two were the SAME two lines
        arm 1 was reporting — the alias and the call it fed. Paying the arm-1 row
        therefore moved this number too, which is why it is re-taken here rather than
        assumed: 55 debt lines became 53, and #1059's report card inherits the
        smaller one.
        """
        by_root = {}
        for _rel, _n, home, lines in ma.arm5_resolved(CATALOGUE):
            k = pathlib.Path(home).name
            by_root[k] = by_root.get(k, 0) + len(lines)
        self.assertEqual(by_root, {"exmateria_almanac": 53, "exmateria_platform": 6})

    def test_arm_6_is_zero_and_each_of_the_seven_lines_is_paid_not_hidden(self):
        """Six paths over seven lines before the move; zero now.

        A zero from this arm is exactly the shape that reads the same for a working
        scan and a broken one, so it is asserted ONLY alongside the two witnesses that
        say the scan still finds things and the payment is real:

          * `Arm6AgreesWithTheGuard` in this file runs `res_path_reaches` over the sound
            package and gets its three `ARM6_BURN_DOWN` rows, so the function is live.
          * The four JSON payloads did not stop being referenced — they TRAVELLED, and
            are asserted present at their addon addresses below (ADR-0251 dec. 2).
          * The remaining three lines named two content trees that could not travel
            (`assets/characters/templates/` is untracked and `git check-ignore`-matched;
            `assets/sprites/textures/` is host art). They are paid by the ADR-0202
            dec. 5 host-injected root, so the assertion that matters is that
            `install/CatalogueContent.gd` carries NO `res://` literal of its own — a
            default of `res://assets/` would leave the literal in an addon file and
            book the fix into the bucket it drains (ADR-0167).
        """
        a = ma.arms(CATALOGUE, INSIDE)
        self.assertEqual(len(a["6"]), 0)
        self.assertEqual(sum(len(v) for v in a["6"].values()), 0)

        travelled = [
            "addons/exmateria_catalogue/identity/unit_names.json",
            "addons/exmateria_catalogue/identity/unit_birthdays.json",
            "addons/exmateria_catalogue/templates/template_residue.json",
            "addons/exmateria_catalogue/seeding/template_jobs.json",
        ]
        for rel in travelled:
            self.assertTrue(pathlib.Path(rel).is_file(), "%s must have travelled" % rel)

        install = pathlib.Path("addons/exmateria_catalogue/install/CatalogueContent.gd")
        self.assertTrue(install.is_file())
        body = [ln for ln in install.read_text(errors="ignore").splitlines()
                if not ln.lstrip().startswith("#")]
        self.assertTrue(body, "the file must have code, not only prose")
        self.assertFalse([ln for ln in body if "res://" in ln],
                         "no `res://` literal may survive in the injection point's CODE")
        # Direction control: the file DOES say `res://` — nine times, in the comment
        # block explaining why the default is empty. An assertion over the whole text
        # would fail on the explanation, and one that passed would mean the file had
        # stopped saying why. The split is the point, not an accommodation.
        self.assertTrue(any("res://" in ln
                            for ln in install.read_text(errors="ignore").splitlines()
                            if ln.lstrip().startswith("#")))


if __name__ == "__main__":
    unittest.main()
