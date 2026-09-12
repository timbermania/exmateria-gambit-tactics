"""Phase-0 reference-scene parser-golden tests (issue #137, ADR-0057).

Two layers:

  RegenMatchesGolden  - regenerate each reference scene's snapshot from the
                        current assets and assert it byte-matches the committed
                        golden. The ROM-derived map layers (terrain / mesh /
                        cull) are gitignored, so when a map asset is absent the
                        scene falls back to comparing only the ROM-independent
                        layers (entd / camera / scalars); mirrors the skip
                        discipline in test_parse_placement.py.

  RosterInvariants    - reads the *committed* goldens (no ROM needed) and locks
                        the reason each scene is in the roster: chapel is
                        orientation-blind (a regression guard, never a facing
                        reference), orbonne carries the {0,2} pair, academy is
                        the only scene exercising facing 1/3 (the values the
                        0<->2 swap leaves untouched), frog's map is
                        non-symmetric, monastery is strong-cull.

This slice *locks current behavior* only (ADR-0057 Phase 0): it introduces no
transform and asserts nothing about correctness, just stability.

Run from tools/:
    uv run python -m unittest test_reference_goldens
"""

from __future__ import annotations

import json
import unittest

import gen_reference_goldens as g


def _load_golden(role: str, sid: int) -> dict:
    return json.loads(g.golden_path(role, sid).read_text())


def _absent_goldens() -> list[str]:
    """Roster goldens this checkout does not have.

    THE STANDALONE REPO DOES NOT SHIP THEM. `tools/goldens/reference_scenes/` holds
    the `{19}` Camera operands byte-exact plus MAP062/004/008's terrain grids, so
    `export_standalone.py` excludes it as Square Enix data (register step 9, the
    user's "no square assets" ruling). They regenerate from the reader's own ISO --
    `uv run python tools/gen_reference_goldens.py` -- so this is a bootstrap step a
    clone has not run yet, never a defect.

    WHY A SKIP AND NOT A FAIL, specifically here: this module is a PRE-FLIGHT guard
    (`tests/run_all_tests.sh:497`) and the pre-flight aborts at its first red, so an
    absent golden would take a clone's ENTIRE suite down before the first test
    booted -- 82 guard blocks and 776 scenes, none of them the thing that is
    missing. Same discipline as `test_parse_placement.py`, and as `_scratch_reader`'s
    `SkipTest` for the excluded HUD captures.
    """
    return ["%s/%d" % (role, sid) for role, sid in g.ROSTER
            if not g.golden_path(role, sid).exists()]


_ABSENT = _absent_goldens()
_SKIP_WHY = ("reference-scene goldens absent (%s) -- excluded from the standalone "
             "repo as Square Enix data; regenerate with "
             "tools/gen_reference_goldens.py" % ", ".join(_ABSENT))


# ROM-independent snapshot layers (regenerable from committed assets alone).
_ROM_FREE_KEYS = ("role", "scenario_id", "scenario_name", "map_id", "map",
                  "entd", "camera")


@unittest.skipIf(_ABSENT, _SKIP_WHY)
class RegenMatchesGolden(unittest.TestCase):
    """The committed golden must equal a fresh regeneration from the assets."""

    @classmethod
    def setUpClass(cls):
        cls.scenarios = g._scenarios()
        cls.records = g._entd_records()

    def test_each_scene_regenerates_identically(self):
        for role, sid in g.ROSTER:
            with self.subTest(role=role, scenario=sid):
                path = g.golden_path(role, sid)
                self.assertTrue(path.exists(),
                                "golden missing; run gen_reference_goldens.py")
                committed = _load_golden(role, sid)
                fresh = g.build_snapshot(role, sid, self.scenarios, self.records)
                has_maps = fresh.get("terrain") is not None \
                    and fresh.get("mesh_bounds") is not None
                if has_maps:
                    # Full exact comparison (the real CI path, map assets present).
                    self.assertEqual(committed, fresh)
                else:
                    # Map assets absent (gitignored) - compare the layers we can
                    # still regenerate; don't fail the suite for a fresh clone.
                    for k in _ROM_FREE_KEYS:
                        self.assertEqual(committed.get(k), fresh.get(k),
                                         "ROM-free layer %r drifted" % k)


@unittest.skipIf(_ABSENT, _SKIP_WHY)
class RosterInvariants(unittest.TestCase):
    """Why each scene earns its roster slot (reads committed goldens; no ROM)."""

    def test_chapel_is_orientation_blind_regression_guard(self):
        # Chapel's active ENTD slots only carry facing {0,3}: it never exercises
        # 1 or 2, so it CANNOT calibrate facing - it is a breadth/regression
        # guard only (ADR-0057; CONTEXT.md -> Orientation direction).
        facings = set(_load_golden("chapel", 1)["entd"]["facings_present"])
        self.assertTrue(facings.issubset({0, 3}), facings)
        self.assertNotIn(1, facings)
        self.assertNotIn(2, facings)

    def test_orbonne_carries_the_0_2_pair(self):
        # The enemies-West / knights-East pair - the 0<->2 swap category error.
        facings = set(_load_golden("orbonne", 4)["entd"]["facings_present"])
        self.assertIn(0, facings)
        self.assertIn(2, facings)

    def test_academy_exercises_facing_1_and_3(self):
        # The ONLY roster scene covering 1 and 3 - the values a 0<->2 swap
        # leaves untouched, so a regression there can only be caught here.
        facings = set(_load_golden("academy", 8)["entd"]["facings_present"])
        self.assertIn(1, facings)
        self.assertIn(3, facings)
        self.assertEqual(facings, {0, 1, 2, 3})

    def test_frog_map_is_non_symmetric(self):
        # size_x != size_z so a depth-flip off-by-one (row shift) cannot hide
        # behind symmetry. Also guards against committing a ROM-less golden
        # (terrain would be null).
        terrain = _load_golden("frog", 269)["terrain"]
        self.assertIsNotNone(terrain, "golden committed without terrain (ROM absent?)")
        self.assertNotEqual(terrain["size_x"], terrain["size_z"])

    def test_monastery_is_strong_cull(self):
        # >80% of polygons carry a visible-angles cull bit: the oracle #135's
        # cull-table remap is later checked against.
        cull = _load_golden("monastery", 232).get("cull")
        self.assertIsNotNone(cull, "golden committed without cull (ROM absent?)")
        self.assertGreater(cull["polygon_count"], 200)
        frac = cull["culled_polygon_count"] / cull["polygon_count"]
        self.assertGreater(frac, 0.8, "cull fraction %.3f" % frac)
        # The orbit oracle must be present and genuinely camera-angle dependent
        # (the culled count varies across buckets), so #135's azimuth-negation
        # remap has a per-bucket before/after to be checked against.
        orbit = cull["orbit"]
        self.assertGreaterEqual(len(orbit), 8)
        culled_by_bucket = {o["culled"] for o in orbit}
        self.assertGreater(len(culled_by_bucket), 1, "cull orbit is angle-invariant")

    def test_chapel_camera_operands_locked(self):
        # The cinematic reference carries the {19} Camera opcodes byte-exact
        # (Phase 2/3 camera consolidation is checked against these).
        cam = _load_golden("chapel", 1)["camera"]
        self.assertIsNotNone(cam)
        self.assertEqual(cam["opcode_0x19_count"], len(cam["opcode_0x19_raw"]))
        self.assertGreater(cam["opcode_0x19_count"], 0)


if __name__ == "__main__":
    unittest.main()
