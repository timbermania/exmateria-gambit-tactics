"""Seed tests for goal #7's comment model (ADR-0228 dec. 5).

`score_goals.jargon_hits` answers goal #7, which is a claim about VOCABULARY.
[ADR-0149](../docs/adr/0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md)'s
rule is that a comment is prose: the GDScript path has always run
`touch_matrix.strip_noncode`, which blanks `#` comments and triple-quoted
docstrings. The shader path stripped `//` and nothing else, so the `/* … */`
header paragraph every `.gdshader` in this tree opens with read as CODE — five
of `Sprite Rig`'s 39 lines at extraction #4's pass 9, two of them sentences
saying the file *renders PSX-era sprite animations*.

Every seed here FABRICATES its subject in a temp directory. A test that read the
shipped count would pin a number the next rename moves, and the arm that matters
is the one that says which text is code — not how much of it there is today. The
one arm that does touch the real tree asserts only that the new branch FIRES on
it, so the repair cannot go inert without a red.

Run from tools/:
    uv run python -m unittest test_score_goals
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))
os.chdir(PROJECT_DIR)

import score_goals as sgl


def _hits(name: str, body: str):
    """`jargon_hits` over a one-file package, fabricated on disk."""
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / name).write_text(body, encoding="utf-8")
        return sgl.jargon_hits(Path(d))


class TheShaderCommentModel(unittest.TestCase):
    """A `/* … */` block is prose; everything outside one is code."""

    HEADER = "/*\n\tUNIT COMPOSITOR\n\n\tRenders PSX-era sprites.\n*/\n"

    def test_a_block_comment_header_scores_NOTHING(self):
        self.assertEqual(_hits("a.gdshader", self.HEADER + "void fragment() {}\n"), [])

    def test_the_SAME_SENTENCE_as_code_still_scores(self):
        # The anti-vacuity control for the arm above: if the term itself had
        # stopped matching, the first test would pass for the wrong reason.
        hits = _hits("a.gdshader", "float psx_gain = 2.0;\n")
        self.assertEqual([(h[1], h[2]) for h in hits], [(1, "psx")])

    def test_code_AFTER_the_block_closes_is_code_and_keeps_its_line_number(self):
        hits = _hits("a.gdshader", self.HEADER + "float psx_gain = 2.0;\n")
        self.assertEqual([(h[1], h[2]) for h in hits], [(6, "psx")])

    def test_an_UNCLOSED_block_swallows_the_rest_of_the_file(self):
        # Not a wish: it is what a shader compiler does, and a scorer that
        # disagreed with the compiler about where code begins would be reporting
        # on a file the GPU never sees.
        self.assertEqual(_hits("a.gdshader", "/*\nfloat psx_gain = 2.0;\n"), [])

    def test_a_TRAILING_block_comment_hides_itself_and_not_the_code(self):
        hits = _hits("a.gdshader", "float gain = 2.0;  /* the psx value */\n")
        self.assertEqual(hits, [])
        hits = _hits("a.gdshader", "float psx_gain = 2.0;  /* retired */\n")
        self.assertEqual([(h[1], h[2]) for h in hits], [(1, "psx")])

    def test_a_res_url_is_NOT_a_line_comment(self):
        # `res://` contains `//`, and the two `//` arms both have to know it —
        # ADR-0175's lesson about `strip_noncode` in a shader, one instrument over.
        #
        # The path is a FIXTURE, not a reference: no such file exists, and the
        # `psx_` token inside it IS the assertion — it sits AFTER the `//`, so a
        # scorer that mistook `res://` for a line comment would report zero here.
        # A rename pass that "corrects" this string to a real path deletes the
        # only thing the test measures. That is not hypothetical: ADR-0129
        # dec. 10's bulk rename did exactly that and the pre-flight caught it.
        hits = _hits("a.gdshader",
                     '#include "res://addons/fixture_only/psx_fixture.gdshaderinc"\n')
        self.assertEqual([(h[1], h[2]) for h in hits], [(1, "psx")])

    def test_a_line_comment_is_still_prose(self):
        self.assertEqual(_hits("a.gdshader", "// the psx value\nfloat gain = 2.0;\n"), [])


class TheGDScriptPathIsUnchanged(unittest.TestCase):
    """GDScript has no block comment, and the repair must not invent one."""

    def test_a_slash_star_in_gdscript_is_not_a_comment(self):
        hits = _hits("a.gd", "var psx_angle := 0  # /* not a comment */\n")
        self.assertEqual([(h[1], h[2]) for h in hits], [(1, "psx")])

    def test_a_hash_comment_is_still_prose(self):
        self.assertEqual(_hits("a.gd", "# the psx value\nvar gain := 2.0\n"), [])

    def test_a_docstring_is_still_prose(self):
        self.assertEqual(_hits("a.gd", 'var gain := 2.0\n"""\nthe psx value\n"""\n'), [])


class TheBranchIsLiveOnTheRealTree(unittest.TestCase):
    """A repair nothing in the tree exercises is a repair that can rot silently."""

    def test_at_least_one_shipped_shader_carries_a_block_comment(self):
        moved = []
        for q in sorted(PROJECT_DIR.glob("addons/*/**/*.gdshader*")):
            lines = q.read_text(errors="replace").splitlines()
            if sgl._blank_block_comments(lines) != lines:
                moved.append(sgl._rel(q))
        self.assertTrue(moved, "no shipped shader under addons/ has a `/* … */` region, "
                               "so `_blank_block_comments` alters nothing and this repair "
                               "has gone inert")


# --------------------------------------------------------------------------
# ADR-0232 — goal #5 is a conjunction, and `_walk_roots.RIGS` is the join.
#
# Every arm below is new with that ADR. The three register arms are RAISES, so
# each is seeded red here rather than asserted by inspection: `rigs()` takes its
# table and its stranger directory as arguments for exactly this.
# --------------------------------------------------------------------------

import pathlib
import unittest.mock

import _walk_roots as wr


class _FakeRig:
    """A `Rig` stand-in for `mechanical(5)`'s branch selection.

    Not `wr.Rig`, deliberately: these arms are about which BRANCH the goal takes
    for a given (reach count, declared debt, in_suite) triple, and building a real
    `Rig` would drag the on-disk register into a test about control flow. The real
    register has its own arms below, and `TheRegisterIsLiveOnTheRealTree` is what
    stops the two drifting.
    """

    def __init__(self, debt, in_suite=True, run_sh=None):
        self.run_sh = run_sh or (sgl.PROJECT_DIR / "tests/stranger/exmateria_sprite_rig/run.sh")
        self._debt, self.in_suite = debt, in_suite

    def known_failure_rows(self):
        return self._debt


def _goal5(reach_lines, rig):
    """`mechanical(5)` over a fabricated reach set and a fabricated rig."""
    addon = sgl.PROJECT_DIR / "addons" / "exmateria_sprite_rig"
    reaches = [sgl.Reach("addons/x/A.gd", "class_name", "Foo", "Battlefield",
                         "addons/exmateria_battlefield/Foo.gd", list(range(reach_lines)))]
    with unittest.mock.patch.object(sgl, "outbound_reaches",
                                    return_value=reaches if reach_lines else []), \
         unittest.mock.patch.object(wr, "rig_for", return_value=rig):
        return sgl.mechanical(5, addon, "Sprite Rig")


class TheGoalFiveConjunction(unittest.TestCase):
    """`met` needs BOTH halves. Either half alone opens the row."""

    def test_zero_reaches_and_a_clean_rig_is_MET(self):
        ok, reading = _goal5(0, _FakeRig([]))
        self.assertIs(ok, True)
        self.assertIn("0 cross-system reach lines", reading)
        self.assertIn("tests/stranger/exmateria_sprite_rig/run.sh", reading)

    def test_zero_reaches_and_a_DECLARED_DEBT_is_OPEN(self):
        # THE ROW THIS ADR EXISTS FOR. Before the conjunction this scored `met`
        # on the reach half while the rig printed UNMET on the same tree.
        ok, reading = _goal5(0, _FakeRig([("res://addons/x/CameraRelativeRenderer.gd", "#848")]))
        self.assertIs(ok, False)
        self.assertIn("CameraRelativeRenderer.gd", reading)
        self.assertIn("#848", reading)

    def test_reaches_and_a_clean_rig_is_OPEN_and_SAYS_it_is_the_budget_half(self):
        ok, reading = _goal5(3, _FakeRig([]))
        self.assertIs(ok, False)
        self.assertIn("3 reach lines", reading)
        self.assertIn("budget half alone", reading)

    def test_both_halves_failing_names_BOTH(self):
        ok, reading = _goal5(3, _FakeRig([("res://addons/x/B.gd", "#999")]))
        self.assertIs(ok, False)
        self.assertIn("3 reach lines", reading)
        self.assertIn("B.gd", reading)

    def test_NO_RIG_is_UNSCORABLE_and_not_a_clean_bill(self):
        # ADR-0229 dec. 8. A 0 on an addon nobody has tried to install is a budget
        # reading; `None` is the charter's sixth state and `main()` maps it to
        # `unscorable`, so `GOALS.tsv` cannot record `met` for it.
        ok, reading = _goal5(0, None)
        self.assertIsNone(ok)
        self.assertIn("NO STRANGER RIG", reading)

    def test_a_rig_the_SUITE_DOES_NOT_RUN_says_so_in_the_reading(self):
        # The anti-vacuity arm for dec. 5: an empty `known_failures.tsv` on a rig
        # nothing invoked is a FILE, not a run, and the reading may not hide it.
        ok, reading = _goal5(0, _FakeRig([], in_suite=False))
        self.assertIs(ok, True)
        self.assertIn("NOT run by the suite", reading)

    def test_the_suite_run_rig_does_NOT_carry_that_clause(self):
        # Control for the arm above: if the clause were unconditional it would
        # pass while saying nothing.
        _, reading = _goal5(0, _FakeRig([], in_suite=True))
        self.assertNotIn("NOT run by the suite", reading)


class TheKnownFailuresParseRule(unittest.TestCase):
    """Mirrored from `stranger_burn_down.gd._rows()`, field count included."""

    def _rows(self, text):
        with tempfile.TemporaryDirectory() as d:
            run_sh = Path(d) / "run.sh"
            run_sh.write_text("", encoding="utf-8")
            (Path(d) / "known_failures.tsv").write_text(text, encoding="utf-8")
            return wr.Rig(Path(d), run_sh, "").known_failure_rows()

    def test_comments_and_blanks_are_skipped(self):
        self.assertEqual(self._rows("# a header\n\n\t\n"), [])

    def test_a_bare_path_gets_the_res_prefix(self):
        rows = self._rows("addons/x/A.gd\t#1\terr\twhy\n")
        self.assertEqual(rows, [("res://addons/x/A.gd", "#1")])

    def test_an_already_prefixed_path_is_left_alone(self):
        rows = self._rows("res://addons/x/A.gd\t#1\terr\twhy\n")
        self.assertEqual(rows, [("res://addons/x/A.gd", "#1")])

    def test_a_THREE_FIELD_row_is_DROPPED_exactly_as_the_gdscript_drops_it(self):
        # Not tidiness. `stranger_burn_down.gd` requires >= 4 fields and drops a
        # short row silently, so a reader that accepted three would report debt
        # the rig never checks and the two would disagree about the same file.
        self.assertEqual(self._rows("addons/x/A.gd\t#1\terr\n"), [])

    def test_an_ABSENT_file_is_no_declared_debt_and_not_an_error(self):
        with tempfile.TemporaryDirectory() as d:
            run_sh = Path(d) / "run.sh"
            run_sh.write_text("", encoding="utf-8")
            r = wr.Rig(Path(d), run_sh, "")
            self.assertIsNone(r.known_failures)
            self.assertEqual(r.known_failure_rows(), [])


class TheRegisterFailsInThreeDirections(unittest.TestCase):
    """Each arm seeded RED. A raise nobody has seen fire is a raise nobody has."""

    REAL = wr.RIGS

    def test_a_DECLARED_RIG_THAT_DOES_NOT_EXIST_raises(self):
        table = self.REAL + (("addons/exmateria_render",
                              "tests/stranger/nope/run.sh", ""),)
        with self.assertRaises(FileNotFoundError) as cm:
            wr.rigs(table=table)
        self.assertIn("tests/stranger/nope/run.sh", str(cm.exception))

    def test_an_ADDON_ROOT_WITH_NO_ROW_raises(self):
        table = tuple(r for r in self.REAL if "sprite_rig" not in r[0])
        with self.assertRaises(AssertionError) as cm:
            wr.rigs(table=table)
        self.assertIn("exmateria_sprite_rig", str(cm.exception))

    def test_a_RIG_ON_DISK_THAT_NO_ROW_NAMES_raises(self):
        # The arrows reversed: this is the arm that would have caught the fifth
        # rig landing while README.md still said "All four".
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "exmateria_sixth").mkdir()
            (Path(d) / "exmateria_sixth" / "run.sh").write_text("", encoding="utf-8")
            with self.assertRaises(AssertionError) as cm:
                wr.rigs(stranger_dir=Path(d))
            self.assertIn("exmateria_sixth", str(cm.exception))

    def test_shared_is_not_a_rig(self):
        # Control: `shared/` holds the arms the rigs share and must not be read as
        # a sixth rig by the arm above.
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "shared").mkdir()
            (Path(d) / "shared" / "run.sh").write_text("", encoding="utf-8")
            wr.rigs(stranger_dir=Path(d))          # does not raise


class TheRegisterIsLiveOnTheRealTree(unittest.TestCase):
    """The seeds above are fabricated; these three assert the branches are live."""

    def test_the_real_register_passes_its_own_three_arms(self):
        self.assertTrue(wr.rigs())

    def test_every_addon_root_has_a_rig(self):
        roots = {r.resolve() for r in wr.addon_roots()}
        roots |= {e.path.resolve() for e in wr.extracted_roots()}
        self.assertEqual(roots - {r.root for r in wr.rigs()}, set())

    def test_at_least_one_declared_rig_lives_OUTSIDE_tests_stranger(self):
        # Anti-vacuity for dec. 4/5: the two-homes branch and the `in_suite`
        # clause both go inert the day every rig is in one directory, and this
        # arm reds if that happens without the ADR being revisited.
        self.assertTrue([r for r in wr.rigs() if not r.in_suite])


if __name__ == "__main__":
    unittest.main()
