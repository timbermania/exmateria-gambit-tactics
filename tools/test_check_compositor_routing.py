"""Seeded-defect tests for the compositor-routing scoreboard (check_compositor_routing.py).

WHY THIS FILE EXISTS. The guard carries **three shrink-only ratchets across two axes**
and, until this file, nobody had ever watched one fail. Its axis-1 arms *were* proven —
by a scratch harness that mutated the real shader tree and restored it with
`git checkout -- .` between cases — but a scratch script nothing re-runs is not
verification: a later edit could silently break every arm with nothing going red. That
is the "a guard nobody has watched fail" problem moved up one level, which is the
problem the guard itself was written to fix.

So each arm is seeded here against a handful of files in a tmpdir, via
`check(scan_dirs=..., allowlist=..., clamp_allowlist=..., display_space_allowlist=...)`.
The working tree is never touched.

THREE RULES CARRIED OVER FROM THE HARNESS, each learned the expensive way:

  1. **Assert on the SPECIFIC message, never on a non-zero exit.** The guard has seven
     failure channels; a seed that trips a *different* one proves nothing. The harness's
     S7 originally "passed" for exactly that reason — the anchor was a prefix of a line
     belonging to another allowlist, so the ghost name landed on the wrong list.
     `assert_channels` here goes further than the harness did: it names the channels
     that must be SILENT as well as the one that must fire.
  2. **Keep the negative controls.** A suite of only-failing seeds cannot tell you the
     guard is not simply failing on any edit. `test_clean_corpus_*` and the four
     `test_positive_*` cases are that control.
  3. **Do not leave a legitimate answer in place beside the seeded defect.** The
     off-fork-fallback seeds below remove the twin's `compositor_layer` (or the twin
     itself) rather than only editing the marker — otherwise a *different* rule
     legitimately matches and the guard passes while the arm goes untested.

VERIFIED, and the verification is the point of the file: 15 defects were seeded into
`check_compositor_routing.py` itself -- each arm silenced or inverted in turn -- and all
15 were killed by the cases below. The nine original seeds were also re-run against the
refactored guard on the REAL shader corpus and still behave as specified. Note the trap
there, because it cost a false green: that harness restores with `git checkout -- .`,
which reverts the GUARD too, so re-running it after editing the guard silently re-tests
the pre-edit code and reports 9/9 no matter what you changed.

Run from tools/:
    uv run python -m unittest test_check_compositor_routing
"""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import check_compositor_routing as ccr


# --- the seven failure channels, by their report headline -------------------------------
# Keyed so a test can say which one must fire AND which must stay silent. The headlines
# are matched in full: "DISPLAY_SPACE_ALLOWLIST entries the scan can never REACH" is a
# substring of nothing else here only because it is spelled out to the colon.
CHANNELS = {
    "exempt-kind":
        "`compositor-exempt:` marker(s) whose claim is not a KIND the guard can accept:",
    "clamp-stale":
        "Stale CLAMP_ARGUMENT_ALLOWLIST entries in check_compositor_routing.py:",
    "ds-unanswered":
        "In-scene blend_add/blend_sub with an UNANSWERED display-space question:",
    "ds-stale":
        "Stale DISPLAY_SPACE_ALLOWLIST entries in check_compositor_routing.py:",
    "ds-unreachable":
        "DISPLAY_SPACE_ALLOWLIST entries the scan can never REACH:",
    "leak":
        "Un-routed additive/subtractive shader(s) not in the allowlist:",
    "allowlist-stale":
        "Stale ALLOWLIST entries in check_compositor_routing.py:",
}
CLEAN = "OK: compositor-routing scoreboard clean"


def shader(blend: str | None = "blend_add", *, fold: bool = False, canvas: bool = False,
           exempt: str | None = None, ds: str | None = None, tail: str = "") -> str:
    """One synthetic shader. Only the lines this guard's regexes read are real."""
    modes = ["unshaded"]
    if blend:
        modes.append(blend)
    if fold:
        modes.append("compositor_layer")
    lines = [f"shader_type {'canvas_item' if canvas else 'spatial'};",
             f"render_mode {', '.join(modes)};"]
    if exempt is not None:
        lines.append(f"// compositor-exempt: {exempt}")
    if ds is not None:
        lines.append(f"// display-space: {ds}")
    lines.append(tail)
    lines.append("void fragment() { }")
    return "\n".join(lines) + "\n"


def run_guard(files: dict[str, str], *, allowlist=(), clamp=(), ds_allow=(),
              scan_dirs=None):
    """(rc, report) for one synthetic corpus. Never touches the working tree."""
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        for name, text in files.items():
            (root / name).write_text(text, encoding="utf-8")
        buf = io.StringIO()
        rc = ccr.check([root] if scan_dirs is None else scan_dirs,
                       allowlist=allowlist, clamp_allowlist=clamp,
                       display_space_allowlist=ds_allow, out=buf)
        return rc, buf.getvalue()


class _GuardCase(unittest.TestCase):
    def assert_channels(self, report: str, *expected: str):
        """Exactly `expected` fired. Naming the SILENT channels is the point: a seed
        that trips a neighbouring channel would otherwise read as a pass."""
        for key, headline in CHANNELS.items():
            if key in expected:
                self.assertIn(headline, report, f"channel {key!r} should have fired")
            else:
                self.assertNotIn(headline, report, f"channel {key!r} fired unexpectedly")

    def assert_clean(self, rc: int, report: str):
        self.assertEqual(rc, 0, report)
        self.assertIn(CLEAN, report)
        self.assert_channels(report)


# =========================================================================================
# NEGATIVE CONTROLS — the guard must not simply fail on any corpus.
# =========================================================================================
class CleanCorpusTests(_GuardCase):
    def test_clean_corpus_is_green(self):
        """Routed prim + a verified off-fork pair + an inventoried mix = nothing to report."""
        rc, out = run_guard({
            "routed.gdshader": shader("blend_add", fold=True),
            "pair.gdshader": shader("blend_sub", exempt="off-fork-fallback — the Mobile path"),
            "pair_fold.gdshader": shader("blend_sub", fold=True),
            "alpha.gdshader": shader("blend_mix"),
        })
        self.assert_clean(rc, out)

    def test_positive_explicit_twin_arg_is_accepted(self):
        """The N1 control: an implicit claim rewritten as an explicit, TRUE one. The
        twin is named outright, and the display-space axis is answered the same way."""
        rc, out = run_guard({
            "box.gdshader": shader("blend_add",
                                   exempt="off-fork-fallback box_v2_fold.gdshader — fallback",
                                   ds="folds-on-fork box_v2_fold.gdshader"),
            "box_v2_fold.gdshader": shader("blend_add", fold=True),
        })
        self.assert_clean(rc, out)

    def test_positive_no_arg_leans_on_the_fold_sibling(self):
        """The no-arg form: the guard finds `<stem>_fold` itself, on BOTH axes."""
        rc, out = run_guard({
            "glow.gdshader": shader("blend_add", exempt="off-fork-fallback — OFF-FORK only"),
            "glow_fold.gdshader": shader("blend_add", fold=True),
        })
        self.assert_clean(rc, out)

    def test_positive_prose_after_a_no_arg_kind_is_not_read_as_a_twin(self):
        """The N2 control. Without the `.gdshader` suffix test in `_twin_of`, the regex
        would read the first word of the prose as a filename and the no-arg form could
        never be written at all."""
        rc, out = run_guard({
            "glow.gdshader": shader(
                "blend_add", exempt="off-fork-fallback definitely_not_a_filename OFF-FORK"),
            "glow_fold.gdshader": shader("blend_add", fold=True),
        })
        self.assert_clean(rc, out)

    def test_positive_allowlisted_clamp_argument_is_accepted(self):
        """`pre-clamped-single-layer` is un-checkable, so it is admitted only from the
        allowlist — and from there it must be admitted, or the list would be a no-op."""
        rc, out = run_guard(
            {"tint.gdshader": shader("blend_add", exempt="pre-clamped-single-layer — §D")},
            clamp={"tint.gdshader"}, ds_allow={"tint.gdshader"})
        self.assert_clean(rc, out)


# =========================================================================================
# AXIS 1 — the exemption is a KINDED claim, and the checkable kind is CHECKED.
# =========================================================================================
class ExemptionKindTests(_GuardCase):
    def test_free_prose_marker_is_rejected(self):
        """The regression that started all of this: the glove cursor's shadow carried
        `compositor-exempt: the glove sits ON TOP of ...` — prose that satisfied the old
        `EXEMPT in text` test, was never validated, and was simply FALSE (folding it took
        max |err| vs the ROM's `bg - CLUT` from 104 to 4)."""
        rc, out = run_guard({
            "glove.gdshader": shader(
                "blend_sub",
                exempt="the glove sits ON TOP of already-composited opaque chrome",
                ds="reviewed for this test"),
        })
        self.assertEqual(rc, 1)
        self.assert_channels(out, "exempt-kind")
        self.assertIn("glove.gdshader: `compositor-exempt: the` — unknown kind", out)

    def test_marker_outside_a_line_comment_is_malformed(self):
        """`EXEMPT in text` is still what selects a file for this arm, so a marker the
        KIND regex cannot parse must report as malformed rather than pass silently."""
        rc, out = run_guard({
            "glove.gdshader": shader("blend_sub", ds="reviewed for this test",
                                     tail="/* compositor-exempt: off-fork-fallback */"),
        })
        self.assertEqual(rc, 1)
        self.assert_channels(out, "exempt-kind")
        self.assertIn("marker is malformed", out)

    def test_off_fork_twin_that_does_not_exist_is_rejected(self):
        """The claim's whole value is that it can be falsified by looking for the twin."""
        rc, out = run_guard({
            "cb.gdshader": shader("blend_add",
                                  exempt="off-fork-fallback no_such_fold.gdshader — fallback",
                                  ds="reviewed for this test"),
        })
        self.assertEqual(rc, 1)
        self.assert_channels(out, "exempt-kind")
        self.assertIn("`compositor-exempt: off-fork-fallback no_such_fold.gdshader` — that "
                      "file does not exist in the scan or does not declare compositor_layer",
                      out)

    def test_off_fork_twin_that_exists_but_does_not_fold_is_rejected(self):
        """Naming a REAL shader is not enough — it has to actually fold. `mix.gdshader`
        is in the scan and is not a folding prim."""
        rc, out = run_guard({
            "cb.gdshader": shader("blend_add",
                                  exempt="off-fork-fallback mix.gdshader — fallback",
                                  ds="reviewed for this test"),
            "mix.gdshader": shader("blend_mix"),
        })
        self.assertEqual(rc, 1)
        self.assert_channels(out, "exempt-kind")
        self.assertIn("off-fork-fallback mix.gdshader` — that file does not exist in the "
                      "scan or does not declare compositor_layer", out)

    def test_no_arg_off_fork_without_a_folding_sibling_is_rejected(self):
        """Two shapes, one message. Leaving a real folding twin in place is how a seed
        silently passes, so the sibling here is present-but-not-folding in the first run
        and absent in the second."""
        for label, files in (
            ("sibling stopped folding", {
                "fs.gdshader": shader("blend_sub", exempt="off-fork-fallback — OFF-FORK",
                                      ds="reviewed for this test"),
                "fs_fold.gdshader": shader("blend_mix"),
            }),
            ("no sibling at all", {
                "fs.gdshader": shader("blend_sub", exempt="off-fork-fallback — OFF-FORK",
                                      ds="reviewed for this test"),
            }),
        ):
            with self.subTest(label):
                rc, out = run_guard(files)
                self.assertEqual(rc, 1)
                self.assert_channels(out, "exempt-kind")
                self.assertIn("fs.gdshader: `compositor-exempt: off-fork-fallback` names no "
                              "twin", out)

    def test_unallowlisted_clamp_argument_is_rejected(self):
        """Being unable to check a claim is a reason to bound WHO may make it, not a
        reason to wave it through. A new shader cannot talk its way in."""
        rc, out = run_guard(
            {"cyl.gdshader": shader("blend_add", exempt="pre-clamped-single-layer — §C2",
                                    ds="reviewed for this test")},
            clamp=())
        self.assertEqual(rc, 1)
        self.assert_channels(out, "exempt-kind")
        self.assertIn("cyl.gdshader: claims `pre-clamped-single-layer`, which the scan "
                      "cannot verify, but is not on CLAMP_ARGUMENT_ALLOWLIST", out)

    def test_clamp_allowlist_ratchets_when_an_entry_is_routed(self):
        """The other arm of the ratchet: fold the prim and the entry must GO."""
        rc, out = run_guard(
            {"unit_additive.gdshader": shader("blend_add", fold=True)},
            clamp={"unit_additive.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "clamp-stale")
        self.assertIn("unit_additive.gdshader: no longer a `compositor-exempt:`-marked "
                      "in-scene add/sub", out)


# =========================================================================================
# AXIS 2 — the display-space (LINEAR vs DISPLAY) question, answered CHECKABLY.
# =========================================================================================
class DisplaySpaceTests(_GuardCase):
    def test_unanswered_in_scene_add_sub_is_flagged(self):
        """On the burn-down allowlist for axis 1, so only the colour-space axis speaks."""
        rc, out = run_guard({"blob.gdshader": shader("blend_sub")},
                            allowlist={"blob.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "ds-unanswered")
        self.assertIn("blob.gdshader: no display-space answer", out)

    def test_folds_on_fork_without_a_twin_is_flagged(self):
        rc, out = run_guard({"blob.gdshader": shader("blend_sub", ds="folds-on-fork")},
                            allowlist={"blob.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "ds-unanswered")
        self.assertIn("`display-space: folds-on-fork` names no twin", out)

    def test_folds_on_fork_naming_a_non_folding_twin_is_flagged(self):
        rc, out = run_guard(
            {"blob.gdshader": shader("blend_sub", ds="folds-on-fork ghost_fold.gdshader")},
            allowlist={"blob.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "ds-unanswered")
        self.assertIn("`display-space: folds-on-fork ghost_fold.gdshader` — that file does "
                      "not exist or does not declare compositor_layer", out)

    def test_any_other_display_space_reason_is_accepted_as_reviewed(self):
        """Kind (d): an explicit, reviewed decision. Unlike axis 1's prose, writing one
        is itself the reviewed act — the burn-down list is what it is measured against."""
        rc, out = run_guard(
            {"blob.gdshader": shader("blend_sub", ds="cpu-folded — measured, no gamma term")},
            allowlist={"blob.gdshader"})
        self.assert_clean(rc, out)

    def test_display_space_allowlist_ratchets_when_the_question_is_answered(self):
        """Fold the prim and the burn-down entry must go — the list only shrinks."""
        rc, out = run_guard({
            "blob.gdshader": shader("blend_sub"),
            "blob_fold.gdshader": shader("blend_sub", fold=True),
        }, allowlist={"blob.gdshader"}, ds_allow={"blob.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "ds-stale")
        self.assertIn("blob.gdshader: now answered — off-fork fallback of blob_fold.gdshader",
                      out)


class UnreachableBurnDownEntryTests(_GuardCase):
    """An entry the scan never iterates can never go STALE either, so it sits on the
    burn-down forever inflating the un-reviewed count with a prim nothing measures.
    `screen_in_mode2.gdshader` was one of these for real — `shader_type canvas_item`,
    which the scan skips by design."""

    def test_entry_the_scan_never_sees(self):
        for label, files in (
            ("file absent from the corpus", {"other.gdshader": shader("blend_mix")}),
            ("file present but canvas_item", {
                "ghost.gdshader": shader("blend_add", canvas=True),
                "other.gdshader": shader("blend_mix"),
            }),
        ):
            with self.subTest(label):
                rc, out = run_guard(files, ds_allow={"ghost.gdshader"})
                self.assertEqual(rc, 1)
                self.assert_channels(out, "ds-unreachable")
                self.assertIn("ghost.gdshader: the scan never sees this file", out)

    def test_entry_that_now_folds(self):
        rc, out = run_guard({"blob.gdshader": shader("blend_sub", fold=True)},
                            ds_allow={"blob.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "ds-unreachable")
        self.assertIn("blob.gdshader: now declares compositor_layer — it folds", out)

    def test_entry_that_no_longer_blends_add_or_sub(self):
        rc, out = run_guard({"blob.gdshader": shader("blend_mix")},
                            ds_allow={"blob.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "ds-unreachable")
        self.assertIn("blob.gdshader: no longer declares blend_add/blend_sub", out)


# =========================================================================================
# The original burn-down ratchet (ALLOWLIST) — both directions.
# =========================================================================================
class BurnDownAllowlistTests(_GuardCase):
    def test_new_unrouted_add_sub_leaks(self):
        """No silent regressions: a brand-new in-scene add/sub fails. Axis 2 is answered
        so the leak channel is the only one that speaks."""
        rc, out = run_guard(
            {"newprim.gdshader": shader("blend_add", ds="reviewed for this test")})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "leak")
        self.assertIn("newprim.gdshader: declares blend_add/blend_sub in-scene", out)

    def test_allowlist_entry_that_has_since_been_routed_is_stale(self):
        rc, out = run_guard({"blob.gdshader": shader("blend_sub", fold=True)},
                            allowlist={"blob.gdshader"})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "allowlist-stale")
        self.assertIn("blob.gdshader: no longer an un-routed in-scene add/sub", out)


# =========================================================================================
# What the scan does and does not reach.
# =========================================================================================
class ScanScopeTests(_GuardCase):
    def test_canvas_item_add_is_not_in_the_3d_domain(self):
        """2D UI is not in the compositor's Pass-C domain — skipped, not leaked."""
        rc, out = run_guard({"ui_add.gdshader": shader("blend_add", canvas=True)})
        self.assert_clean(rc, out)
        self.assertNotIn("ui_add.gdshader", out)

    def test_mix_is_inventoried_but_not_enforced(self):
        """Alpha blend does not accumulate-saturate, so it is located, not failed."""
        rc, out = run_guard({"alpha.gdshader": shader("blend_mix")})
        self.assert_clean(rc, out)
        self.assertIn("alpha.gdshader: mix (inventory", out)

    def test_gdshaderinc_is_scanned(self):
        rc, out = run_guard(
            {"frag.gdshaderinc": shader("blend_add", ds="reviewed for this test")})
        self.assertEqual(rc, 1)
        self.assert_channels(out, "leak")
        self.assertIn("frag.gdshaderinc", out)

    def test_blend_add_in_a_comment_is_not_a_blend(self):
        """`_ADD_SUB` is line-anchored to `render_mode` precisely so unit.gdshader's
        "opaque here, blend_add there" note is never matched."""
        rc, out = run_guard(
            {"opaque.gdshader": shader(None, tail="// opaque here, blend_add there")})
        self.assert_clean(rc, out)
        self.assertNotIn("opaque.gdshader", out)

    def test_subdirectories_are_scanned(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "nested" / "deeper").mkdir(parents=True)
            (root / "nested" / "deeper" / "buried.gdshader").write_text(
                shader("blend_add", ds="reviewed for this test"), encoding="utf-8")
            buf = io.StringIO()
            rc = ccr.check([root], allowlist=(), clamp_allowlist=(),
                           display_space_allowlist=(), out=buf)
        self.assertEqual(rc, 1)
        self.assertIn("buried.gdshader", buf.getvalue())

    def test_missing_scan_dir_is_a_hard_failure(self):
        """A scan root that is not there must be LOUD: a guard that goes green because
        it stopped looking is this repo's most-repeated defect (ADR-0148)."""
        buf = io.StringIO()
        rc = ccr.check([Path("/nonexistent/scan/root")], out=buf)
        self.assertEqual(rc, 1)
        self.assertIn("ERROR: scan dir not found", buf.getvalue())


class DefaultsTests(_GuardCase):
    """`check()` with no lists must read the module constants — otherwise the tests above
    would be exercising a guard the pre-flight does not run."""

    def test_omitted_lists_fall_back_to_the_module_constants(self):
        rc, out = run_guard({"unrelated.gdshader": shader("blend_mix")},
                            allowlist=ccr.ALLOWLIST, clamp=ccr.CLAMP_ARGUMENT_ALLOWLIST,
                            ds_allow=ccr.DISPLAY_SPACE_ALLOWLIST)
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "unrelated.gdshader").write_text(shader("blend_mix"), encoding="utf-8")
            buf = io.StringIO()
            rc_default = ccr.check([root], out=buf)
        self.assertEqual(rc, rc_default)
        self.assertEqual(out, buf.getvalue())
        # ...and that shared verdict is a real one: every constant entry is unreachable
        # against an empty corpus, which is what proves the lists were actually consulted.
        self.assertEqual(rc, 1)
        self.assert_channels(out, "ds-unreachable", "clamp-stale", "allowlist-stale")
        for name in ccr.DISPLAY_SPACE_ALLOWLIST:
            self.assertIn(name, out)


if __name__ == "__main__":
    unittest.main()
