#!/usr/bin/env python3
"""Arms for `export_standalone.py` — register step 10.

    cd tools && uv run python -m unittest test_export_standalone

TWO KINDS OF ARM, and the split is the point. The `LiveRepo` class asserts the
real worktree is clean, which is what a pre-flight wants but can only ever show
the guard returning nothing. The `Invariant*` classes drive `violations()` with
fixtures so each rule is seen to FIRE — a guard whose failing direction has never
been reached is a guard nobody has watched work
(`test_check_generated_assets.py::IgnoreBlockLocation` is the shape).

Mutation-verified: each `Invariant*` class is the arm that reds when its own rule
is deleted from `violations()`, and no other class moves. Counts in step 10's
commit message.
"""

from __future__ import annotations

import contextlib
import io
import pathlib
import re
import unittest

import export_standalone as ex


ROOT = [("LICENSE", "LICENSE")]
MIN = ["project.godot", ".gitignore", "SETUP_FROM_SCRATCH.md"]


class LiveRepo(unittest.TestCase):
    """Against this worktree — the arms the pre-flight runs."""

    def test_this_worktree_exports_clean(self):
        self.assertEqual(ex.check(), [])

    def test_the_register_is_excluded_and_really_is_tracked(self):
        """Both halves: the rule fires, AND it is not a rule about nothing."""
        rel = "docs/EXTRACTION-GAMBIT-REGISTER.tsv"
        self.assertIn(rel, ex.tracked_package_files())
        self.assertIsNotNone(ex.excluded(rel))
        self.assertNotIn(rel, ex.manifest())

    def test_every_required_path_is_in_the_manifest(self):
        got = set(ex.manifest())
        for p in ex.REQUIRED:
            self.assertIn(p, got, f"{p} is REQUIRED but would not export")

    def test_the_prefix_is_stripped_so_the_package_root_is_the_repo_root(self):
        for p in ex.manifest():
            self.assertFalse(p.startswith("godot-learning/"),
                             f"{p} kept the monorepo prefix — dead in the standalone repo")
        self.assertIn("project.godot", ex.manifest())

    def test_no_exclusion_has_rotted(self):
        self.assertEqual(ex.stale_excludes(), [])

    def test_the_hud_captures_are_excluded_as_SQUARE_DATA(self):
        """DECIDED 2026-09-12: "hud captures are square data so i can't really
        include them." This arm previously asserted the OPPOSITE — that they stayed
        unlisted — so that the decision could not be made quietly; it fired when the
        rule was added, which is what it was for. It now pins the decided state.
        """
        caps = [p for p in ex.tracked_package_files()
                if p.startswith("tools/hud_digit_captures/") and p.endswith(".bin.gz")]
        self.assertEqual(len(caps), 5, "the capture set changed; re-read step 9")
        exported = set(ex.manifest())
        for c in caps:
            why = ex.excluded(c)
            self.assertIsNotNone(why, f"{c} is Square Enix VRAM and must not export")
            self.assertIn("Square Enix", why,
                          "the reason must say WHY, so nobody re-adds it as an oversight")
            self.assertNotIn(c, exported)

    def test_excluding_the_captures_costs_SKIPS_not_REDS(self):
        """The whole basis for excluding them: `_scratch_reader` already treats an
        absent capture as a skip. If that ever became a hard failure, a clone would
        have 4 red tests out of the box and this decision would need revisiting.
        """
        import importlib
        pf = importlib.import_module("test_parse_frame_font")
        with self.assertRaises(unittest.SkipTest):
            pf._scratch_reader("scratchpad_sstate_does_not_exist.bin.gz")

    def test_the_dead_particle_dump_is_excluded_and_really_is_dead(self):
        """Excluded by inference from the same principle, not by instruction — so
        the arm also pins the fact that made it safe: nothing reads it."""
        rel = "example_particle_data_ref_fft.txt"
        self.assertIn(rel, ex.tracked_package_files())
        self.assertIsNotNone(ex.excluded(rel))
        self.assertNotIn(rel, ex.manifest())


#: The 2026-09-12 "no square assets" sweep, as data: (glob prefix, expected file
#: count, what makes it Square's). The COUNT is load-bearing — it is what makes a
#: 63rd fixture appearing upstream a loud failure here instead of a silent export.
_SQUARE_DATA_GROUPS = (
    ("addons/exmateria_battlefield/tests/fixtures/rom_walk/", 14, "MAP009 tile array"),
    ("addons/exmateria_battlefield/tests/fixtures/rom_event_route/", 27,
     "MAP009/012/057 tile arrays"),
    ("tests/fixtures/rom_event_route/", 1, "the host's copy of the same"),
    ("assets/doodads/bridge_2tile/", 8, "MAP022 mesh, texture and palettes"),
    ("tools/goldens/reference_scenes/", 5, "byte-exact {19} operands + terrain grids"),
    ("tests/goldens/world_map_prims_ss", 2, "verbatim PSX GPU packets"),
)


class SquareDataSweep(unittest.TestCase):
    """The user's 2026-09-12 ruling — "making sure no square assets are included" —
    pinned per group, against the LIVE repo.

    WHY THE COUNTS ARE ASSERTED and not just the exclusion: an `EXCLUDE` glob keeps
    matching whatever lands under its directory, so the rule alone cannot tell you
    the population is the one that was audited. `stale_excludes()` catches a rule
    that stops matching ANYTHING; nothing catches a group that grew. These counts
    are what make that a failure someone has to read.
    """

    def test_every_audited_group_is_excluded_with_a_reason_that_says_why(self):
        exported = set(ex.manifest())
        tracked = ex.tracked_package_files()
        for prefix, expected_n, what in _SQUARE_DATA_GROUPS:
            with self.subTest(group=prefix):
                members = [p for p in tracked if p.startswith(prefix)]
                self.assertEqual(
                    len(members), expected_n,
                    f"{prefix} holds {len(members)} tracked files, audited at "
                    f"{expected_n} — re-read register step 9 before changing this")
                for m in members:
                    why = ex.excluded(m)
                    self.assertIsNotNone(why, f"{m} is Square Enix data ({what})")
                    self.assertIn(
                        "Square Enix", why,
                        "the reason must say WHY, so nobody re-adds it as an oversight")
                    self.assertNotIn(m, exported)

    def test_the_SYNTHETIC_fuzz_corpus_still_EXPORTS(self):
        """The other half of the ruling, and the arm that keeps the sweep honest.

        `rom_walk_fuzz/` is 48 files of SEEDED-RANDOM terrain whose expectations come
        from our own port — no disc byte in it — so it ships, and shipping it is what
        leaves `RomWalkStepperCrossCheckTest` its full oracle while
        `RomWalkStepperTest` loses one. Without this arm the cheapest way to pass the
        arm above is to exclude the whole `fixtures/` tree, which would cost a real
        test its oracle for nothing.
        """
        fuzz = [p for p in ex.tracked_package_files()
                if p.startswith("addons/exmateria_battlefield/tests/fixtures/rom_walk_fuzz/")]
        self.assertEqual(len(fuzz), 48)
        exported = set(ex.manifest())
        for f in fuzz:
            self.assertIsNone(ex.excluded(f))
            self.assertIn(f, exported)

    def test_a_DIGEST_of_absent_content_still_exports(self):
        """The line the sweep drew, pinned by its nearest miss. `map_buffer_golden.json`
        is 37 KB about FFT maps and holds no map byte — only sha256 and sizes — so it
        ships. A sweep that excluded it would be excluding the word "map", not Square's
        data.
        """
        rel = "tests/data/map_buffer_golden.json"
        self.assertIn(rel, ex.tracked_package_files())
        self.assertIsNone(ex.excluded(rel))
        self.assertIn(rel, ex.manifest())

    def test_the_preflight_golden_guard_SKIPS_rather_than_aborting_a_clone(self):
        """The cost check, and the reason it is this module that carries it.

        `tools/test_reference_goldens.py` asserted `path.exists()` and runs in the
        SUITE PRE-FLIGHT, which exits at its first red — so excluding the goldens
        would have taken a clone's entire suite down before the first test booted.
        It now skips.

        EXERCISED, NOT INSPECTED. `unittest.skipIf(False, ...)` returns the class
        untouched, so in THIS worktree — where the goldens are present — there is no
        `__unittest_skip__` to look at and an arm reading one passes vacuously. So the
        arm drives `_absent_goldens()` against a patched `golden_path` instead: that
        is the function whose emptiness gates both classes, and a clone is exactly the
        case where it comes back non-empty.
        """
        import importlib
        from pathlib import Path
        rg = importlib.import_module("test_reference_goldens")
        self.assertEqual(rg._ABSENT, [],
                         "this worktree HAS the goldens; _ABSENT must be empty here")

        real = rg.g.golden_path
        try:
            rg.g.golden_path = lambda role, sid: Path("/nonexistent/%s_%d.json" % (role, sid))
            absent = rg._absent_goldens()
        finally:
            rg.g.golden_path = real
        self.assertEqual(len(absent), len(rg.g.ROSTER),
                         "every roster golden must read as absent when none exist")
        self.assertTrue(all(a.count("/") == 1 for a in absent), absent)

        # And the gate is actually wired to it, in both classes.
        src = (ex.PACKAGE / "tools/test_reference_goldens.py").read_text()
        self.assertEqual(src.count("@unittest.skipIf(_ABSENT, _SKIP_WHY)"), 2,
                         "both golden-reading classes must carry the absent-golden skip")

    def test_each_gdscript_consumer_declares_a_SKIP_for_its_absent_fixture(self):
        """Four GDScript tests read an excluded group, and GDScript has no SkipTest.

        Measured, not assumed: each of the four FAILED on an absent fixture before
        this change — `[FAIL] fixtures missing`, a `push_error`, a `_true(not
        fx.is_empty())`, and (the worst) a golden diff reading an absent oracle as a
        wrong answer. Each now prints `[SKIP]`. This arm is a source assertion, which
        is weak on its own — `test_export_skips_are_reachable` in the register's
        evidence is the run that actually exercised them inside a built export.
        """
        pkg = ex.PACKAGE
        for rel, needle in (
            # ⚠️ THE NEEDLE MUST BE UNIQUE TO THE SKIP PATH. The obvious one here —
            # `_completed["_test_every_capture_matches_the_wire"] = true` — occurs
            # TWICE in that file: once in the skip block and once where the arm
            # completes normally. Asserting it would have survived deleting the skip
            # entirely, which is a green that means nothing. Each needle below is
            # mutation-checked to occur exactly once.
            ("addons/exmateria_battlefield/tests/RomWalkStepperTest.gd",
             "[SKIP] wire captures absent"),
            ("addons/exmateria_battlefield/tests/EventPathfinderTest.gd",
             "func _fixtures_present() -> bool:"),
            ("tests/ScenarioPathMotionTest.gd", "[SKIP] wired path"),
            ("tests/ReferenceRenderDirectionTest.gd",
             "[SKIP] ReferenceRenderDirectionTest"),
            ("tests/WorldMapPrimitivesTest.gd", "[SKIP] packet diff"),
        ):
            with self.subTest(test=rel):
                body = (pkg / rel).read_text()
                self.assertEqual(
                    body.count(needle), 1,
                    f"{rel}: the needle {needle!r} must occur EXACTLY once — a needle "
                    f"that also appears outside the skip path survives deleting it")
                self.assertIn(needle, body,
                              f"{rel} lost its absent-fixture skip path")


class PlatformSupportIsWhatTheBinariesSay(unittest.TestCase):
    """Register step 14 / decision 7: the clone is Linux x86_64 only, and the doc must
    keep saying so.

    THE SHAPE OF THE RISK is a doc that rots quietly in the SAFE direction's opposite.
    `exmateria_spu.gdextension` declares twelve library slots and the repository ships
    one binary, so eleven platforms resolve to a path that is not there. The addon's
    own README says a tree without the compiled library means "nothing will load" —
    there is no GDScript mixer behind it — so this is a project that does not open,
    not muted audio. Whoever later cross-compiles one of the eleven will drop a file
    in `bin/` and have no reason to open `SETUP_FROM_SCRATCH.md`; these arms are what
    turns that into a failure someone reads.
    """

    #: `res://addons/exmateria_spu/` in a declared slot is `vendor/exmateria_spu/` in
    #: the tree — `sync_exmateria_sound.sh` is what maps one onto the other.
    GDEXT = "vendor/exmateria_spu/exmateria_spu.gdextension"
    RES_PREFIX = "res://addons/exmateria_spu/"
    VENDOR_PREFIX = "vendor/exmateria_spu/"

    def _declared(self) -> dict:
        """slot -> tree-relative path of the library it names."""
        body = (ex.PACKAGE / self.GDEXT).read_text()
        libs = body.split("[libraries]", 1)[1]
        out = {}
        for line in libs.splitlines():
            if "=" not in line or line.strip().startswith(";"):
                continue
            slot, path = (x.strip().strip('"') for x in line.split("=", 1))
            self.assertTrue(path.startswith(self.RES_PREFIX), path)
            out[slot] = self.VENDOR_PREFIX + path[len(self.RES_PREFIX):]
        return out

    def test_three_of_the_declared_slots_have_a_committed_binary(self):
        """Was one slot until the `SPU Windows build` workflow existed. The two
        Windows DLLs are CI output committed on purpose — no maintainer has a Windows
        machine, so CI is their only producer and a `PREBUILT` entry sourced from a
        local build could never restore them.
        """
        declared = self._declared()
        self.assertEqual(len(declared), 12,
                         "the slot list changed; re-read register step 14")
        tracked = set(ex.tracked_package_files())
        have = sorted(slot for slot, path in declared.items() if path in tracked)
        self.assertEqual(
            have, ["linux.debug.x86_64",
                   "windows.debug.x86_64",
                   "windows.release.x86_64"],
            "the shipped-platform set changed. That is good news, and it makes "
            "SETUP_FROM_SCRATCH.md's 'Platform support' table and the README's WRONG "
            "— update the tables and this arm together")

    def test_every_shipped_slot_really_resolves_to_a_real_library(self):
        """A tracked path is not a loadable library. Every slot we claim ships must
        point at a file that is present, non-trivial, and the right binary format for
        its platform — a broken symlink into another worktree is tracked all the same,
        and that is the failure this repository's own asset-hub rule exists to prevent.

        The Windows arms check the format ONLY. `MZ` proves a PE image and nothing
        about whether Godot can load it; the DLLs are unverified at runtime and the
        docs say so. A guard that implied otherwise would be the more dangerous lie.
        """
        for slot, magic, why in (
            ("linux.debug.x86_64", b"\x7fELF", "not an ELF shared object"),
            ("windows.debug.x86_64", b"MZ", "not a PE image"),
            ("windows.release.x86_64", b"MZ", "not a PE image"),
        ):
            lib = ex.PACKAGE / self._declared()[slot]
            self.assertTrue(lib.exists(), f"{lib} is declared, tracked and NOT THERE")
            self.assertGreater(lib.stat().st_size, 500_000,
                               f"{slot}: suspiciously small for the SPU")
            with lib.open("rb") as f:
                self.assertEqual(f.read(len(magic)), magic, f"{slot}: {why}")

    def test_the_setup_doc_states_the_platform_limit_and_why(self):
        """Pinned as whole claims, not bare words: the section heading, the fact that
        a release build fails on Linux too (the slot most easily mistaken for covered),
        and the reason a reader cannot fix it locally — the C++ source is not here."""
        doc = (ex.PACKAGE / "SETUP_FROM_SCRATCH.md").read_text()
        for claim in (
            "#### Platform support — Linux x86_64, plus an unverified Windows build",
            "an **exported release build fails on Linux**",
            # ⚠️ ONE LINE ONLY. The first draft of this needle was "**no C++ source
            # and no `SConstruct`**", which the doc wraps between "C++" and "source"
            # — a claim can be present and still not match a needle that spans the
            # wrap, and the arm reds for a reason that has nothing to do with the doc.
            "source and no `SConstruct`**",
        ):
            self.assertIn(claim, doc, f"SETUP_FROM_SCRATCH.md lost: {claim!r}")
            self.assertEqual(doc.count(claim), 1,
                             f"{claim!r} must occur exactly once — a needle that also "
                             f"appears elsewhere survives deleting the claim")

    def test_the_portability_claim_is_scoped_to_the_PARSERS(self):
        """The claim that stood here was "the same parsers work identically on Linux,
        WSL, macOS, and Git Bash on Windows" — true of the Python, and read by a
        newcomer as the game running on all four. Same defect class as steps 2 and 18:
        the shipped doc wrong about the repo it ships in.
        """
        doc = (ex.PACKAGE / "SETUP_FROM_SCRATCH.md").read_text()
        self.assertIn("**That is a claim about the parsers, not about the game.**", doc)
        self.assertNotIn("This means the same parsers work identically", doc,
                         "the unscoped portability claim came back")


class ProvenanceOfTheThreeUnclassified(unittest.TestCase):
    """Register step 15: three artifacts root ADR-0001's table had mis-sorted, and the
    disposition each one earned. Pinned because all three are the kind of fact that
    reverts by someone re-adding a file "so the clone works".
    """

    ALMANAC = "addons/exmateria_almanac/"

    def _manifest_row(self, path: str) -> tuple:
        rows = {}
        for line in (ex.PACKAGE / "tools/data/generated_assets.tsv").read_text().splitlines():
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                rows[parts[0].strip()] = (parts[1].strip(), parts[2].strip())
        self.assertIn(path, rows, f"{path} has no manifest row")
        return rows[path]

    def test_sprite_types_is_ISO_DATA_with_its_generator_and_does_not_ship(self):
        """MEASURED, which is what moved it: a fresh `parse_sprite_types.py` read of
        BATTLE.BIN `0x2D748` is byte-identical to the copy that had been committed for
        the whole life of the repo — `diff` over 1,433 lines reported nothing but
        "\\ No newline at end of file".

        It read as hand-authored for one reason: the parser defaulted to STDOUT and
        nothing wired it to the path the game loads, so a derivation nobody could
        re-derive in place looked authored no matter what `docs/context/18-sprite-layers.md`
        said about `0x2D748`.
        """
        rel = self.ALMANAC + "sprites/sprite_types.json"
        self.assertEqual(self._manifest_row(rel), ("iso-data", "parse_sprite_types.py"))
        self.assertNotIn(rel, ex.tracked_package_files(),
                         "iso-data must not be tracked (ADR-0001)")
        self.assertNotIn(rel, ex.manifest(),
                         "untracking it is what keeps 28 KB of ROM table out of the "
                         "published repo — see register step 9")
        # The generator has a canonical destination, which is the half that was missing.
        src = (ex.PACKAGE / "tools/parse_sprite_types.py").read_text()
        self.assertIn("DEFAULT_OUTPUT_PATH", src)
        self.assertIn("sprite_types.json", src)
        # And the bootstrap actually calls it, or a clone has no such file at all.
        boot = (ex.PACKAGE / "tools/bootstrap_assets.sh").read_text()
        self.assertIn("parse_sprite_types.py", boot,
                      "gitignored with no bootstrap line is a clone that cannot open")

    def test_base_stats_stays_COMMITTED_and_says_why_in_its_own_metadata(self):
        """The opposite disposition, on purpose. The values are the disc's, but no
        generator exists and a bounded six-encoding search of SCUS_942.21 and
        BATTLE.BIN found no table — so nothing can rebuild it and ADR-0001's COMMITTED
        classes are exactly for that. ADR-0001 also requires such a file to say so in
        its own `_comment`; this arm is what makes that non-optional.
        """
        import json
        rel = self.ALMANAC + "progression/base_stats.json"
        self.assertEqual(self._manifest_row(rel), ("hand-authored", "-"))
        self.assertIn(rel, ex.tracked_package_files())
        self.assertIn(rel, ex.manifest(), "15 constants are not an asset; it ships")
        md = json.loads((ex.PACKAGE / rel).read_text())["metadata"]
        self.assertIn("provenance", md,
                      "ADR-0001: a committed artifact declares its provenance in itself")
        self.assertIn("There is no parser", md["source"])
        # The claims, not the prose. This arm fired when the note was reworded under
        # #1307 to record a SECOND bounded search — which is the arm working, so the
        # needles now name what must remain true rather than a sentence's shape.
        for claim in ("no generator exists",
                      "nothing can rebuild this file",
                      "a bounded negative is not an absence"):
            self.assertIn(claim, md["provenance"],
                          f"base_stats' provenance note no longer states: {claim!r}")

    def test_job_levels_is_FFTPATCHER_which_ADR_0001_itself_says(self):
        """The one of the three that was already right, and the arm exists so a future
        sweep does not "fix" it. Root ADR-0001's provenance table names
        `job_levels.json` as its FFTPatcher example by name.

        Worth knowing and NOT a reclassification: the same eight JP thresholds are
        independently readable from the reader's own SCUS_942.21 —
        `extract_fft_data.py:parse_job_levels` does exactly that at
        `JOB_LEVELS_OFFSET` for `jobs.json`. Being derivable from the disc does not
        change where THIS file came from, which is what provenance records.
        """
        rel = self.ALMANAC + "jobs/job_levels.json"
        self.assertEqual(self._manifest_row(rel), ("fftpatcher", "-"))
        self.assertIn(rel, ex.manifest())
        adr = (ex.REPO / "docs/adr/0001-iso-derived-assets-reproducible.md").read_text()
        self.assertIn("job_levels.json", adr,
                      "ADR-0001's table is the authority for this row")


class VendorIsTheStandaloneAudioSource(unittest.TestCase):
    """Register step 18: §1.3 told the reader a sibling `exmateria-sound/` checkout
    "MUST exist" — true in the monorepo, impossible in the repo this package ships as.
    Same defect class as step 2 (the doc wrong about its own repo), and the clone was
    never broken: `pick_src()` already falls back to `vendor/`.
    """

    def test_pick_src_falls_back_to_vendor_so_a_clone_needs_no_sibling(self):
        """The fact that made the doc wrong rather than the clone broken. Asserted on
        the SCRIPT, because this is the behaviour §1.3 now promises."""
        sync = (ex.PACKAGE / "tools/sync_exmateria_sound.sh").read_text()
        self.assertIn('else printf \'%s\' "$GODOT_DIR/vendor/$2"', sync,
                      "pick_src lost its vendor/ fallback — §1.3's promise is now false")
        for addon in ("exmateria_sound", "exmateria_spu"):
            self.assertIn(f"pick_src exmateria-sound/addons/{addon} {addon}", sync)

    def test_both_audio_addons_ship_under_vendor(self):
        """A fallback to a directory the export does not carry would be worse than no
        fallback: the clone would fail at bootstrap with a path that looks deliberate."""
        exported = ex.manifest()
        for addon in ("exmateria_sound", "exmateria_spu"):
            n = len([p for p in exported if p.startswith(f"vendor/{addon}/")])
            self.assertGreater(n, 20, f"vendor/{addon}/ ships only {n} files")
        self.assertIn("vendor/exmateria_spu/exmateria_spu.gdextension", exported)

    def test_the_gdignore_mask_exists_and_ships(self):
        """NOTHING GUARDED THIS BEFORE — grep for 'gdignore' across tools/ and tests/
        returned zero hits, and handoff 6 §6 had flagged exactly that.

        It matters because of what its absence looks like: `vendor/exmateria_sound/`
        carries the same `class_name` declarations as the synced copy under `addons/`,
        so an unmasked `vendor/` makes Godot see every class TWICE. That surfaces as
        duplicate-class errors in files nobody edited, which reads as a broken sync
        rather than a missing one-line file.
        """
        rel = "vendor/.gdignore"
        self.assertIn(rel, ex.tracked_package_files(), f"{rel} is not tracked")
        self.assertIn(rel, ex.manifest(), f"{rel} must reach the clone")
        self.assertTrue((ex.PACKAGE / rel).exists())

    def test_section_1_3_no_longer_demands_a_sibling_checkout(self):
        """The claim replaced, and the replacement, pinned as whole lines."""
        doc = (ex.PACKAGE / "SETUP_FROM_SCRATCH.md").read_text()
        self.assertNotIn("Make sure the sibling `exmateria-sound/` checkout", doc,
                         "the impossible-in-a-clone instruction came back")
        for claim in (
            "**There is no sibling `exmateria-sound/` in a standalone clone, and nothing is",
            "`vendor/.gdignore` stops the scan at that directory",
        ):
            self.assertIn(claim, doc, f"§1.3 lost: {claim!r}")
            self.assertEqual(doc.count(claim), 1, f"{claim!r} must occur exactly once")

    def test_the_1_3_tree_diagram_does_not_nest_the_sibling_inside_itself(self):
        """The pre-existing cosmetic half of the row: the old diagram printed
        `exmateria-sound/addons/exmateria_spu/` as a line INSIDE the
        `exmateria-sound/` subtree, repeating the prefix at an indent that made the SPU
        look like a child of the sound addon rather than its sibling.
        """
        doc = (ex.PACKAGE / "SETUP_FROM_SCRATCH.md").read_text()
        self.assertNotIn("    exmateria-sound/addons/exmateria_spu/", doc,
                         "the mis-indented repeated path is back in the tree diagram")


class WhatTheEndToEndProofFound(unittest.TestCase):
    """Register step 13: a clone of the published repo, bootstrapped from a real ISO
    extract, reached `[GPU Arena] GPU simulator ready` and held 60-62 fps with audio.
    It also surfaced these two, which no static check had — both arms exist so the run
    does not have to be repeated to keep them fixed.
    """

    def test_the_monorepo_only_gdextension_does_not_ship(self):
        """Exactly three ERROR lines on every launch of a clone, all one cause:
        `sync_exmateria_sound.sh` copies `vendor/exmateria_sound/` wholesale, so it
        carried a `.gdextension` pointing at `libfftsmd.*.so` — a library never built
        here and never shipped. Godot then failed it three ways: can't open the dynamic
        library, GDExtension library not found, error loading extension.

        The file's own FIRST LINE says it should not be here: "MONOREPO-ONLY — excluded
        from the published tree by publish/manifests/exmateria-sound.manifest". This
        export had no equivalent of that manifest until now.
        """
        exported = set(ex.manifest())
        tracked = ex.tracked_package_files()
        smd = [p for p in tracked if p.startswith("vendor/exmateria_sound/fft_smd.gdextension")]
        self.assertEqual(len(smd), 2, f"expected the .gdextension and its .uid, got {smd}")
        for f in smd:
            self.assertIsNotNone(ex.excluded(f), f"{f} is monorepo-only and must not ship")
            self.assertNotIn(f, exported)
        # The SPU's own extension MUST still ship — it is the one with a real library,
        # and excluding it would be a clone that cannot open at all.
        self.assertIn("vendor/exmateria_spu/exmateria_spu.gdextension", exported)

    def test_bootstraps_closing_note_is_printed_not_executed(self):
        """An unquoted heredoc COMMAND-SUBSTITUTES the backticks in its own prose.

        The audio note read "Build it with `cd exmateria-sound && scons` then re-run
        sync." inside `cat <<EOF`, so every bootstrap run — in BOTH checkouts, since cwd
        there is `$GODOT_DIR/tools` where no such directory exists in either — actually
        executed it, printed `cd: exmateria-sound: No such file or directory` to stderr,
        and substituted the empty result back, telling the reader to "Build it with
        then re-run sync." The script still exited 0, which is why it survived.

        Asserted structurally, not by looking for the old string: any heredoc that both
        interpolates and contains a backtick is the same bug again.
        """
        src = (ex.PACKAGE / "tools/bootstrap_assets.sh").read_text()
        lines = src.splitlines()
        delim, quoted, start = None, None, None
        offenders = []
        for i, line in enumerate(lines, 1):
            if delim is None:
                m = re.search(r"<<(-?)('?)([A-Za-z_]+)\2\s*$", line)
                if m:
                    quoted, delim, start = bool(m.group(2)), m.group(3), i
                continue
            if line.strip() == delim:
                delim = None
                continue
            if not quoted and "`" in line:
                offenders.append(f"line {i} (heredoc opened at {start}): {line.strip()[:60]}")
        self.assertEqual(
            offenders, [],
            "a backtick inside an UNQUOTED heredoc is executed, not printed — "
            "quote the delimiter (<<'EOF') or escape the backticks:\n  "
            + "\n  ".join(offenders))


class TheReadmeIsTheFrontDoor(unittest.TestCase):
    """Register step 11. Written AFTER step 13's clone-and-launch on purpose: a
    quick-start describing a flow nobody had run is a doc that might be wrong, so every
    number in it is one the real run produced.
    """

    def test_the_readme_ships_and_is_required(self):
        self.assertIn("README.md", ex.REQUIRED,
                      "a missing README must be a loud export failure, not a surprise "
                      "on the GitHub page")
        self.assertIn("README.md", ex.manifest())
        self.assertIn("README.md", ex.tracked_package_files())

    def test_it_states_the_three_things_that_surprise_every_reader(self):
        """All three were learned the expensive way and all three belong above the fold:
        the extract landing OUTSIDE the clone (step 12), the shipped library slots
        (step 14), and the ENGINE — a fork with no package or download.

        ⚠️ The engine needle used to pin "Stock Godot fails silently, not loudly ...
        every folded effect vanishes", which #721 / ADR-0191 dec. 14 REFUTED in both
        directions: before it the kernel did not compile on stock (loud, not silent),
        and after it each producer draws an in-scene twin (present, not vanished). A
        guard can pin a sentence that is confidently wrong, so these needles pin the
        MEASURED section's heading instead of its conclusions.

        They pin HEADINGS for a second reason. The next needle to rot was the fork
        URL's blockquote — pinned as `> **<...>** — branch `master``, and broken by
        reflowing that same URL into prose in the very commit that added the release
        links. The claim was never the punctuation. Both ways of getting an engine
        are now pinned as their headings, which is what a reader actually needs to
        find, and the bare URL is left unpinned because it legitimately appears
        several times.

        The engine claims are pinned here rather than in a test of their own because a
        test is a process (charter clause 13) and these share this one's setup.
        """
        r = (ex.PACKAGE / "README.md").read_text()
        for claim in (
            "**`project-assets/` lands BESIDE the clone, not inside it.**",
            "## Platform support — Linux x86_64, and an unverified Windows build",
            "an **exported release build fails on Linux**",
            "### Which Godot — this needs a fork, and stock will not do",
            "## Building the fork",
            "### Download it",
            "### Build it yourself",
            "Keep `dev_build=no`",
        ):
            self.assertIn(claim, r, f"README lost: {claim!r}")
            self.assertEqual(r.count(claim), 1, f"{claim!r} must occur exactly once")

    def test_it_does_not_promise_a_build_the_repo_cannot_do(self):
        """The trap step 14 found, in the doc most likely to repeat it: this repo ships
        no C++ source, so any 'just build it' instruction for the missing platforms is
        false. Asserted as an absence, which is the direction that rots."""
        r = (ex.PACKAGE / "README.md").read_text()
        self.assertIn("The C++ source is not in this repository", r)
        self.assertNotIn("cd exmateria-sound && scons", r)

    def test_the_quickstart_command_matches_what_bootstrap_accepts(self):
        """A copy-pasteable command that does not work is worse than no command. Pinned
        against the script's own interface rather than against prose."""
        r = (ex.PACKAGE / "README.md").read_text()
        boot = (ex.PACKAGE / "tools/bootstrap_assets.sh").read_text()
        self.assertIn("bash tools/bootstrap_assets.sh", r)
        self.assertIn("FFT_ISO=", r)
        self.assertIn('FFT_ISO_PATH="${FFT_ISO:-', boot,
                      "the README documents $FFT_ISO; bootstrap must still read it")
        self.assertIn("godot --path . res://assets/scenes/GPUArena.tscn", r)


class TheGodotRequirementIsStated(unittest.TestCase):
    """The published docs claimed "godot >= 4.6" and never mentioned that this project
    needs a build with the `compositor_layer` primitive.

    MEASURED on stock 4.7.1, which is why the wording is this strong: TWO independent
    fork-only dependencies, either fatal alone —
      - `fold_layer.tres` is a `CompositorRenderLayer`: "Can't create sub resource"
      - `is_compositor_layer_supported()` is resolved at PARSE time, so `Fold.gd`'s own
        `has_method()` guard cannot save the file that contains the call
    `Fold.gd` then does not compile and `Fold.owns()` is "Nonexistent function", which
    cascades through every display-space effect. It does NOT degrade.
    """

    def test_no_doc_still_claims_the_old_floor(self):
        for rel in ("README.md", "SETUP_FROM_SCRATCH.md"):
            with self.subTest(doc=rel):
                body = (ex.PACKAGE / rel).read_text()
                self.assertNotIn("≥ 4.6", body,
                                 f"{rel} still advertises a floor that cannot open this project")

    def test_the_README_names_the_requirement_and_why(self):
        r = (ex.PACKAGE / "README.md").read_text()
        for claim in ("### Which Godot — this needs a fork, and stock will not do",
                      "`CompositorRenderLayer`",
                      "**parse** error"):
            self.assertIn(claim, r, f"README lost: {claim!r}")

    def test_both_docs_warn_that_OPENING_it_with_stock_edits_the_repo(self):
        """The trap a reader hits while checking: Godot rewrites `project.godot` on
        open and strips the `4.8` feature, so 'just try it' is a repo edit."""
        for rel in ("README.md", "SETUP_FROM_SCRATCH.md"):
            with self.subTest(doc=rel):
                body = (ex.PACKAGE / rel).read_text()
                self.assertIn("strips the `4.8` feature", body)

    def test_project_godot_still_declares_the_4_8_feature(self):
        """The docs' claim rests on this. If the feature list ever drops 4.8 the
        requirement changed and all of the above needs re-measuring."""
        pg = (ex.PACKAGE / "project.godot").read_text()
        self.assertIn('config/features=PackedStringArray("4.8"', pg)

    def test_the_shipped_CLAUDE_md_does_not_leave_a_local_path_as_the_only_answer(self):
        """CLAUDE.md ships in the clone. It told the reader `godot` on `$PATH` is the
        fork via `/usr/local/bin/godot` — true on the maintainer's box and useless
        anywhere else. Same defect class as steps 2, 14 and 18."""
        c = (ex.PACKAGE / "CLAUDE.md").read_text()
        self.assertIn("/usr/local/bin/godot", c, "the note should still exist")
        self.assertIn("a fact about this machine, not about the repository", c,
                      "the shipped file must say the local path is not the answer")


class InvariantStaleInDest(unittest.TestCase):
    """Rule 1: the export DIRECTORY holds a file the manifest does not name.

    The first version of this rule compared the manifest against the list the
    manifest was built from, so it could not fire; this arm existed and passed
    against a tautology. Scored against the filesystem now, which is the only
    side that can disagree.
    """

    def test_a_file_left_behind_by_an_earlier_export_is_reported(self):
        v = ex.violations(MIN, ROOT, (), [],
                          on_disk=MIN + ["LICENSE", "docs/deleted-upstream.md"])
        stale = [p for p in v if p.startswith("[stale]")]
        self.assertEqual(len(stale), 1, v)
        self.assertIn("docs/deleted-upstream.md", stale[0])

    def test_a_dest_matching_the_manifest_reports_nothing(self):
        v = ex.violations(MIN, ROOT, (), [], on_disk=MIN + ["LICENSE"])
        self.assertEqual([p for p in v if p.startswith("[stale]")], [])

    def test_no_dest_means_the_rule_does_not_run(self):
        """`--check` with no destination cannot know what is on disk, and must not
        invent a verdict about it."""
        v = ex.violations(MIN, ROOT, (), [], on_disk=None)
        self.assertEqual([p for p in v if p.startswith("[stale]")], [])

    def test_build_REMOVES_a_stale_file_rather_than_leaving_it(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            dest = pathlib.Path(d)
            (dest / "docs").mkdir()
            planted = dest / "docs" / "deleted-upstream.md"
            planted.write_text("should not survive an export")
            written, removed = ex.build(dest)
            self.assertFalse(planted.exists(), "build() left a stale file behind")
            self.assertGreaterEqual(removed, 1)
            self.assertEqual(ex.check(dest), [])


class InvariantLeak(unittest.TestCase):
    """Rule 2: an excluded path that reached the export anyway.

    Reachable only because `manifest()` and the leak scan are separate steps. If
    a refactor makes them one expression this arm goes vacuous — it is asserting
    that the guard does not trust its own filter.
    """

    def test_a_leaked_exclusion_is_reported(self):
        # The exclusion matches a ROOT file, which `manifest()` does not filter.
        v = ex.violations(MIN, ROOT, (("LICENSE", "seeded"),), [])
        leaks = [p for p in v if p.startswith("[leaked]")]
        self.assertEqual(len(leaks), 1, v)
        self.assertIn("seeded", leaks[0], "the reason must travel with the violation")

    def test_an_exclusion_that_does_filter_reports_no_leak(self):
        v = ex.violations(MIN + ["docs/gone.md"], ROOT, (("docs/gone.md", "why"),), [])
        self.assertEqual([p for p in v if p.startswith("[leaked]")], [])
        self.assertNotIn("docs/gone.md", ex.manifest(MIN + ["docs/gone.md"], ROOT,
                                                     (("docs/gone.md", "why"),)))


class InvariantStaleExclude(unittest.TestCase):
    """Rule 3: an exclusion matching nothing. A dead rule must not become an
    exemption that outlives the thing it excluded."""

    def test_a_rule_matching_nothing_is_reported(self):
        v = ex.violations(MIN, ROOT, (("docs/never-existed.md", "why"),), [])
        self.assertEqual(len([p for p in v if p.startswith("[stale-exclude]")]), 1, v)

    def test_a_rule_that_matches_is_not_reported(self):
        v = ex.violations(MIN + ["docs/real.md"], ROOT, (("docs/real.md", "why"),), [])
        self.assertEqual([p for p in v if p.startswith("[stale-exclude]")], [])

    def test_a_GLOB_that_matches_is_not_reported(self):
        v = ex.violations(MIN + ["docs/a.tsv"], ROOT, (("docs/*.tsv", "why"),), [])
        self.assertEqual([p for p in v if p.startswith("[stale-exclude]")], [])


class InvariantRequired(unittest.TestCase):
    """Rule 4: a clone that cannot be opened."""

    def test_a_missing_required_path_is_reported(self):
        v = ex.violations(["project.godot"], ROOT, (), MIN)
        missing = [p for p in v if p.startswith("[missing]")]
        self.assertEqual(len(missing), 2, v)          # .gitignore + SETUP_FROM_SCRATCH.md
        self.assertTrue(all("project.godot" not in m for m in missing))

    def test_a_required_path_supplied_BY_A_ROOT_FILE_counts(self):
        """`LICENSE` is REQUIRED and comes from the monorepo root, not the package.
        Scoring only package files would report it missing forever."""
        v = ex.violations([], ROOT, (), ["LICENSE"])
        self.assertEqual([p for p in v if p.startswith("[missing]")], [])

class BuildBeforeCheck(unittest.TestCase):
    """The ORDER of build and verify, which was wrong once and is a deadlock when
    it is wrong: checking a destination for staleness before building it meant a
    dirty destination failed, the build was skipped, and the only way out was to
    drop the `--check` you added for safety."""

    def test_a_dirty_dest_with_check_is_cleaned_and_passes(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            dest = pathlib.Path(d)
            (dest / "docs").mkdir()
            planted = dest / "docs" / "ZZZ-stale.md"
            planted.write_text("left by an earlier export")
            with contextlib.redirect_stdout(io.StringIO()):
                rc = ex.main([str(dest), "--check"])
            self.assertEqual(rc, 0, "a dirty dest must be fixable by re-exporting")
            self.assertFalse(planted.exists())

    def test_a_MANIFEST_problem_still_blocks_the_build(self):
        """The destination rule must not gate the build; the manifest rules must."""
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            dest = pathlib.Path(d) / "out"
            real = ex.violations
            try:
                ex.violations = lambda *a, **k: ["[stale-exclude] 'seeded' matches nothing"]
                with contextlib.redirect_stderr(io.StringIO()):
                    rc = ex.main([str(dest), "--check"])
            finally:
                ex.violations = real
            self.assertEqual(rc, 1)
            self.assertFalse(dest.exists(), "nothing may be written when the manifest is unsound")

class ProjectAssetsLandsBesideTheClone(unittest.TestCase):
    """Register step 12 — the fact `SETUP_FROM_SCRATCH.md` §1.3 now documents.

    Documented because it reads as a bug: in a standalone clone the package root
    IS the repo root, so `<package>/..` is the directory you cloned into and
    `project-assets/` is a SIBLING of the repo, not part of it. That is deliberate
    (no ROM byte ever lands inside the repository) and it is the first thing that
    confuses someone following the goal sentence. These arms live here rather than
    in a new module because this file is already invoked by the pre-flight and is
    already about how a standalone checkout differs.
    """

    def test_the_extract_resolves_OUTSIDE_the_package(self):
        import importlib, os
        from unittest import mock
        rp = importlib.import_module("_repo_paths")
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("FFT_EXTRACT", None)
            got = rp.fft_extract_root()
        pkg = rp.godot_root().resolve()
        self.assertEqual(got, pkg.parent / "project-assets" / "fft-extract")
        self.assertFalse(
            got.resolve().is_relative_to(pkg),
            "the extract resolved INSIDE the package — ROM data would land in the repo, "
            "and SETUP_FROM_SCRATCH.md §1.3 is now wrong")

    def test_FFT_EXTRACT_overrides_it(self):
        """§1.3 tells the reader this is the escape hatch. If it stopped working the
        doc would be sending people down a path that does nothing."""
        import importlib, os
        from unittest import mock
        rp = importlib.import_module("_repo_paths")
        with mock.patch.dict(os.environ, {"FFT_EXTRACT": "/mnt/roms/somewhere"}):
            self.assertEqual(rp.fft_extract_root(), pathlib.Path("/mnt/roms/somewhere"))

    def test_an_explicit_argument_beats_the_environment(self):
        import importlib, os
        from unittest import mock
        rp = importlib.import_module("_repo_paths")
        with mock.patch.dict(os.environ, {"FFT_EXTRACT": "/mnt/roms/somewhere"}):
            self.assertEqual(rp.fft_extract_root("/explicit"), pathlib.Path("/explicit"))



if __name__ == "__main__":
    unittest.main()
