"""Calibration tests for `arm7_membership.py` — it must agree with the guard it mirrors.

A fresh instrument that agrees with nothing is a fresh instrument's opinion, and this
one exists to produce numbers an ADR rules on. Two calibrations, and the first was
VACUOUS on its obvious form:

  1. AGAINST THE REAL GUARD, row for row. `check_addon_portability.py` arm 7 filters
     `outbound_reaches()` on `kind == "class_name"` and `not _ADDON_RES_RE.match(dst_path)`.
     Run that way, every addon in the package reads ZERO — goal #5 is enforcing and
     `ARM7_BURN_DOWN` is empty — so `0 == 0` passes whether this file works or returns
     an empty dict. `test_matches_guard_with_filter_off` is the LIVENESS half: with the
     addon-root filter off the sets are non-empty (35 / 19 / 1 lines) and the comparison
     has something to fail on. Both halves are asserted.

  2. AGAINST ADR-0241 dec. 2's four published memberships — 4/45, 9/85, 8/79, 13/119 —
     which are the predicate applied BY HAND to memberships that do not exist. If this
     file and that hand-application disagree, one of them is wrong and the ADR that
     rejected `Character Catalogue` for extraction #5 rests on the number.

Both are pinned to the tree, so a classifier or `strip_noncode` change that moves them
fails here rather than silently re-pricing a future selection. If a legitimate change
moves a number, the fix is to re-take it AND say so in the ADR that owns it.

Run from tools/:
    uv run python -m unittest test_arm7_membership
"""

from __future__ import annotations

import collections
import os
import pathlib
import unittest

_HERE = pathlib.Path(__file__).resolve().parent
os.chdir(_HERE.parent)

import arm7_membership as am  # noqa: E402


def _members(addon: str):
    ns = am._load()
    return sorted(p.as_posix() for p in pathlib.Path(addon).rglob("*")
                  if p.is_file() and p.suffix in ns["SOURCE_SUFFIXES"])


def _guard_rows(addon: str, system: str, apply_filter: bool):
    """Arm 7's own reading, transcribed from check_addon_portability.py:1120."""
    rows = collections.defaultdict(list)
    for r in am._load()["outbound_reaches"](addon, system):
        if r.kind != "class_name":
            continue
        if apply_filter and am._ADDON_RE.match(r.dst_path):
            continue
        rows[r.target].extend((r.rel, ln) for ln in r.lines)
    return {k: sorted(v) for k, v in rows.items()}


def _ours(addon: str, apply_filter: bool):
    if apply_filter:
        return {k: sorted(v["lines"]) for k, v in am.arm7(_members(addon)).items()}
    # the same predicate with the addon-root filter lifted, for the liveness half
    members = set(_members(addon))
    ns = am._load()
    t, strip = ns["_tables"](), ns["strip_noncode"]
    hits = collections.defaultdict(list)
    for rel in sorted(members):
        q = pathlib.Path(rel)
        if q.suffix not in ns["SOURCE_SUFFIXES"] or q.suffix in ns["SHADER_SUFFIXES"]:
            continue
        for i, ln in enumerate(strip(q.read_text(errors="ignore")), 1):
            for cn in set(am._WORD.findall(ln)):
                tgt = t["cname"].get(cn)
                if tgt is not None and tgt != rel and tgt not in members:
                    hits[cn].append((rel, i))
    return {k: sorted(v) for k, v in hits.items()}


ADDONS = [("addons/exmateria_battlefield", "Battlefield", 2, 35),
          ("addons/exmateria_sprite_rig", "Sprite Rig", 2, 19),
          ("addons/exmateria_render", "Render", 1, 1)]


class GuardAgreement(unittest.TestCase):
    def test_matches_guard_with_filter_on(self):
        """Arm 7 as the guard actually reads it. Every addon is zero, so this alone
        proves nothing — it is here because the guard's real reading is what ships."""
        for addon, system, _, _ in ADDONS:
            with self.subTest(addon=addon):
                self.assertEqual(_guard_rows(addon, system, True), _ours(addon, True))

    def test_matches_guard_with_filter_off(self):
        """THE LIVENESS HALF. Non-empty on both sides, matched by name AND line number."""
        for addon, system, names, lines in ADDONS:
            with self.subTest(addon=addon):
                real = _guard_rows(addon, system, False)
                self.assertEqual(len(real), names, "the fixture itself moved")
                self.assertEqual(sum(len(v) for v in real.values()), lines,
                                 "the fixture itself moved")
                self.assertEqual(real, _ours(addon, False))

    def test_extracted_addons_are_arm7_clean(self):
        """`ARM7_BURN_DOWN` is empty by design, so this is the tree's own claim."""
        for addon, _, _, _ in ADDONS:
            with self.subTest(addon=addon):
                self.assertEqual(am.arm7(_members(addon)), {})


class Adr0241Memberships(unittest.TestCase):
    """ADR-0241 dec. 2's table, RE-PINNED because extraction #5 discharged it.

    🔴 THIS CALIBRATION WAS A CLAIM ABOUT A TREE THAT NO LONGER EXISTS, AND THE
    THING THAT CHANGED IT IS THE THING IT WAS TAKEN TO JUSTIFY. dec. 2's table
    read A 4/45, B 9/85, C 8/79, D 13/119 and its argument was the DELTA: adding
    `UnitProgression` to Character Catalogue's membership roughly DOUBLES the
    debt, so ownership could be the catalogue's and the address still not be.
    ADR-0243 dec. 6 predicted the whole question would dissolve once the
    databases travelled, and ADR-0251 built that.

    Measured on this tree, all four fall and TWO OF THE FOUR DELTAS ARE NOW ZERO:

        A  the ten members + AllTemplatesSeeder        45  ->   0
        B  A + UnitProgression                         85  ->   0
        C  classify()'s bucket                         79  ->  32
        D  C + UnitProgression                        119  ->  32

    🔴 RE-TAKEN AGAIN AT THE #1025 PASS-3 ADDRESS, AND THE ADDRESS IS THE ONLY
    THING THAT MOVED. A and B named `src/characters/` + `src/scenarios/
    AllTemplatesSeeder.gd`; those ten files are now `addons/exmateria_catalogue/`
    and the fixture below is ENUMERATED at the new address rather than globbed off
    a directory, because a glob over a directory that no longer exists returns `[]`
    and a membership of nothing scores 0 for the wrong reason. All four counts are
    unchanged, which is the claim: 0 and 32 were properties of what these files
    REACH, and a move relocates a file without re-booking it (#744). C's INPUT did
    move -- `classify()`'s bucket is sixteen rows now, not fourteen; see
    `test_membership_c`.

    `UnitProgression.gd` is inside `addons/exmateria_almanac/` now, so arm 7's
    own predicate (the declaring file matches `^addons/[^/]+/`) filters it, and
    ADDING IT TO A MEMBERSHIP COSTS NOTHING. B == A and D == C is not a bug in
    this test; it is the extraction's payoff, stated as an equality.

    🔴 A == 0 IS A LIVE INPUT TO A SELECTION, NOT A CURIOSITY. ADR-0241 dec. 5
    rejected Character Catalogue as extraction #5 on '45 lines over 4 names at
    best-case membership'; that membership now reaches NOTHING outside an addon
    root. Whoever selects #7 should re-read dec. 5 against this row rather than
    against the number it quotes.

    The historical values are kept above rather than deleted, because the ADRs
    that quote them are still the record of why #5 was the tier."""

    # The ADR-0257 dec. 2 membership at its pass-3 address. Enumerated, not globbed:
    # `addons/exmateria_catalogue/` also holds the façade, `plugin.gd` and
    # `install/CatalogueContent.gd`, none of which is a member.
    CHARS = sorted([
        "addons/exmateria_catalogue/identity/Character.gd",
        "addons/exmateria_catalogue/identity/SlugBinding.gd",
        "addons/exmateria_catalogue/identity/UnitBirthdays.gd",
        "addons/exmateria_catalogue/identity/UnitNames.gd",
        "addons/exmateria_catalogue/inspection/RosterDebugView.gd",
        "addons/exmateria_catalogue/registry/CharacterCatalog.gd",
        "addons/exmateria_catalogue/seeding/CatalogueReplay.gd",
        "addons/exmateria_catalogue/templates/CharacterTemplateResolver.gd",
        "addons/exmateria_catalogue/templates/ResidueManifest.gd",
    ])
    SEEDER = ["addons/exmateria_catalogue/seeding/AllTemplatesSeeder.gd"]
    PROG = ["addons/exmateria_almanac/progression/UnitProgression.gd"]

    def setUp(self):
        for rel in self.CHARS + self.SEEDER + self.PROG:
            self.assertTrue(pathlib.Path(rel).is_file(),
                            "%s moved -- the fixture is stale, not the count" % rel)

    def _count(self, members):
        h = am.arm7(sorted(set(members)))
        return len(h), sum(len(v["lines"]) for v in h.values())

    def test_membership_a(self):
        """ADR-0241 dec. 2 read 4 names / 45 lines here."""
        self.assertEqual(self._count(self.CHARS + self.SEEDER), (0, 0))

    def test_membership_b(self):
        """dec. 2 read 9 / 85. The DELTA against A was its argument; it is now 0."""
        self.assertEqual(self._count(self.CHARS + self.SEEDER + self.PROG), (0, 0))
        self.assertEqual(self._count(self.CHARS + self.SEEDER + self.PROG),
                         self._count(self.CHARS + self.SEEDER),
                         "UnitProgression is in an addon; adding it costs nothing")

    def test_membership_c(self):
        """dec. 2 read 8 / 79. ADR-0251 dec. 10's table says 79 -> 32 and this is
        that row, taken by a different route: the six-system reading books these
        files by `sysof` and this one asks arm7 directly."""
        classified = sorted(r for r, s in am._load()["_tables"]()["sysof"].items()
                            if s == "Character Catalogue")
        self.assertEqual(len(classified), 15,
                         "dec. 2 read fourteen; pass 3 added the façade and the install "
                         "port, which are addon files but not ADR-0257 dec. 2 members "
                         "(`plugin.gd` books to `infrastructure`, so it is not here); "
                         "#1070 then deleted `RosterViewDebugPanel.gd`, 16 -> 15")
        self.assertEqual(self._count(classified), (3, 19),
                         "the lines were always the `src/debug/` panels', never the "
                         "members' -- #1070 retired one of the four, so 4/32 -> 3/19. "
                         "The two files the bucket gained at pass 3 still reach nothing "
                         "outside an addon root, which is what this arm is for")

    def test_membership_d(self):
        """dec. 2 read 13 / 119, and the +34 over C was the doubling it argued
        from. It is now zero."""
        classified = sorted(r for r, s in am._load()["_tables"]()["sysof"].items()
                            if s == "Character Catalogue")
        self.assertEqual(self._count(classified + self.PROG), (3, 19))
        self.assertEqual(self._count(classified + self.PROG), self._count(classified))


class DocstringsDoNotScore(unittest.TestCase):
    def test_addon_comments_naming_tier_classes_are_not_reaches(self):
        """Eight addon files mention `JobDatabase`/`ItemDatabase`/`AbilityDatabase` and
        every occurrence is prose. A raw grep reports them; `strip_noncode` must not."""
        rig = _members("addons/exmateria_sprite_rig")
        named = set(am.arm7(rig)) | {k for k in _ours("addons/exmateria_sprite_rig", False)}
        for prose in ("JobDatabase", "ItemDatabase", "AbilityDatabase", "AbilityView",
                      "WeaponGraphicData", "WeaponZeroFrames", "ReactionType"):
            self.assertNotIn(prose, named,
                             "%s is named only in the rig's docstrings (ADR-0203's "
                             "ContentPort severed the code half)" % prose)


class PanelExclusion(unittest.TestCase):
    """ADR-0257 dec. 1's rule, and the arm that would let it lie.

    The rule DROPS `BaseDebugPanel` subclasses from a membership. A rule that only ever
    subtracts is trivially satisfiable by a detector that returns everything, and a
    detector that returns nothing reads exactly like a clean membership -- so both
    directions are asserted, and the pinned numbers are the ones ADR-0257 rules on.
    """

    CATALOGUE = sorted(p for p, sys_ in am._load()["_tables"]()["sysof"].items()
                       if sys_ == "Character Catalogue")

    def test_the_base_class_is_itself_excluded(self):
        """It is as much host debug-window UI as its children, and leaving it in would
        make the rule's own subject a member."""
        self.assertIn(am._PANEL_ROOT, am.panel_subclasses())

    def test_the_detector_is_not_a_path_prefix_in_disguise(self):
        """If it were `startswith("src/debug/")` this would fail: exactly one subclass
        lives elsewhere, and a prefix rule would keep it while dropping non-panels."""
        outside = sorted(p for p in am.panel_subclasses()
                         if not p.startswith("src/debug/"))
        self.assertEqual(outside, ["src/ui3/testing/CombatUIDebugPanel.gd"])

    def test_a_debug_helper_that_is_not_a_panel_stays(self):
        """`RosterDebugView.gd` is NOT a `BaseDebugPanel` subclass, so the rule keeps it.
        This is the arm that fails if anyone 'simplifies' the walk into a directory test.

        🔴 RE-POINTED IN PASS 3, AND THE OLD FORM WOULD STILL HAVE PASSED. It named
        `src/debug/RosterDebugView.gd`, which no longer exists -- `assertNotIn` on a path
        that is absent from the tree is true for every possible detector, including one
        returning everything. The subject has to be a file that IS there."""
        rel = "addons/exmateria_catalogue/inspection/RosterDebugView.gd"
        self.assertTrue(pathlib.Path(rel).is_file(),
                        "the subject moved -- re-point it, do not let the assertion "
                        "go vacuous")
        self.assertNotIn(rel, am.panel_subclasses())

    def test_the_exclusion_changes_the_catalogues_answer(self):
        """THE LIVENESS HALF. As classified the membership is 3 names / 19 lines; the
        rule takes it to zero. A detector returning nothing passes the zero arm below
        and fails here.

        🔴 RE-TAKEN AT #1070, WHICH DELETED ONE OF THE FOUR PANELS THIS COUNTS.
        4 / 32 -> 3 / 19. The VALUE moved and the PREMISE did not: the arm exists to
        prove the exclusion is not a no-op, and a non-empty count is what proves it.
        The assertion below is therefore paired with a floor, so a future deletion that
        empties the set makes this arm FAIL rather than quietly agree with the zero arm
        it is the control for."""
        hits = am.arm7(self.CATALOGUE)
        self.assertEqual((len(hits), sum(len(h["lines"]) for h in hits.values())), (3, 19))
        self.assertGreater(len(hits), 0,
                           "if the catalogue's panels ever go to zero this arm stops "
                           "being a liveness witness -- delete it or re-point it, do "
                           "not let it pass vacuously alongside the zero arm")

    def test_the_catalogue_opens_at_zero_under_the_rule(self):
        keep = [p for p in self.CATALOGUE if p not in am.panel_subclasses()]
        self.assertEqual(len(keep), 12,
                         "ten ADR-0257 dec. 2 members plus the two pass-3 files that "
                         "book to the system but are not members -- the façade and "
                         "`install/CatalogueContent.gd`")
        self.assertEqual(am.arm7(keep), {})

    def test_dropping_panels_is_not_uniformly_a_reduction(self):
        """ADR-0257 dec. 3. Removing a panel can CONVERT an internal name into an
        outbound one, so the rule is not monotone and must never be sold as a discount.
        `UI` rises 15 -> 18 names while its lines fall 128 -> 61.

        🔴 THIS TEST WAS ALREADY RED ON `main` (#1055) AND PASS 3 MOVED ITS SUBJECT
        AGAIN. It read `17 -> 20`; `main` measures `18 -> 21`, which is the drift #1055
        was filed for -- the file is in no pre-flight, so nobody saw it. On this branch
        the same reading is `15 -> 18`, and the three names it lost are named below.
        Re-pinning the value here does NOT close #1055: that ticket is about the pin
        being unwatched, not about which number it holds."""
        ui = sorted(p for p, sys_ in am._load()["_tables"]()["sysof"].items()
                    if sys_ == "UI" and not am._ADDON_RE.match(p))
        before = am.arm7(ui)
        after = am.arm7([p for p in ui if p not in am.panel_subclasses()])
        self.assertEqual(len(before), 15)
        self.assertEqual(len(after), 18, "names RISE; only the line count falls")
        self.assertLess(sum(len(h["lines"]) for h in after.values()),
                        sum(len(h["lines"]) for h in before.values()))
        # ATTRIBUTION. `main` reads 18 -> 21. The three names pass 3 removed are the
        # three catalogue members UI reached by `class_name`; every UI use site now
        # spells them `const X = ExMateriaCatalogue.X` (ADR-0211 dec. 4), so the
        # declaring file matches `^addons/[^/]+/` and arm 7 filters it. Asserting
        # their ABSENCE is what separates "the extraction worked" from "the walk
        # broke and lost three rows at random".
        for gone in ("CatalogueReplay", "Character", "CharacterTemplateResolver"):
            self.assertNotIn(gone, before)
        self.assertIn("BaseDebugPanel", before)


if __name__ == "__main__":
    unittest.main()
