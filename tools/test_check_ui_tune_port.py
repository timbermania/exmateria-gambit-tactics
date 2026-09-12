"""Seed-red tests for `check_ui_tune_port.py` -- both directions, plus vacuity.

An arm that has never been seen to FIRE is indistinguishable from an arm that
cannot fire, so every arm below is asserted in the direction that matters:

  1. a real bare `Tune.` in member CODE            -> MUST red, and MUST name the line
  2. `Tune.` in a `#` comment or a "..." literal   -> must NOT red
  3. `Tune.` inside a `\"\"\"...\"\"\"` doc block       -> must NOT red   <-- THE SUBTLE ONE
  4. an EMPTY subject                              -> MUST red

ARM 3 IS WHY THIS FILE EXISTS. A `\"\"\"...\"\"\"` block is a STRING LITERAL that GDScript
never executes, so `Tune.` inside one is prose and is not a reach. A blanker that
strips comments and strings ONE LINE AT A TIME cannot see it: the offending line
holds no quote and no `#`, and its opening delimiter is ten lines up. Such a
blanker reds a CLEAN tree -- a false POSITIVE, which is how this family of defect
presents (ADR-0306 §4 records three of them; one published `GambitOptions` off a
sentence in exactly such a block). These files are heavily documented and `Tune`
appears in their prose throughout, so this is not a hypothetical.

ARM 4 IS THE MOVE ARM. This guard's subject is UI's membership, and the whole
point of #1268 is that the membership is about to MOVE under `addons/`. A guard
whose subject empties does not fail -- it stops looking, and silence reads as
clean. `check_ui_tune_port` treats an empty subject as a FAILURE that says so.
"""
import importlib.util
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUARD = ROOT / "tools/check_ui_tune_port.py"
# a member with no bare `Tune.` left, small enough to read in a diff
SUBJECT = ROOT / "src/ui3/changejob/ChangeJobScreen.gd"


def run_guard():
    r = subprocess.run([sys.executable, str(GUARD)], capture_output=True, text=True, cwd=ROOT)
    return r.returncode, r.stdout + r.stderr


class SeededBreak:
    """Append text to a member file and restore it byte-identically."""

    def __init__(self, path, text):
        self.path, self.text = path, text

    def __enter__(self):
        self.original = self.path.read_bytes()
        self.path.write_bytes(self.original + self.text.encode())
        return self

    def __exit__(self, *exc):
        self.path.write_bytes(self.original)
        assert self.path.read_bytes() == self.original, "restore was not byte-identical"
        return False


class CheckUITunePort(unittest.TestCase):

    def test_clean_tree_is_green_and_is_not_green_by_silence(self):
        rc, out = run_guard()
        self.assertEqual(rc, 0, out)
        self.assertIn("OK", out)
        # a guard that read nothing would also print no count
        self.assertRegex(out, r"\b\d{2,}\s+UI members",
                         "the guard must say how many members it READ")

    def test_a_bare_tune_reach_in_code_reds_and_is_named(self):
        seed = '\n\nfunc _seeded_break() -> void:\n\tTune.bind("seed.slug", 1.0)\n'
        with SeededBreak(SUBJECT, seed):
            rc, out = run_guard()
        self.assertEqual(rc, 1, "a bare `Tune.` in code MUST red:\n" + out)
        self.assertIn("ChangeJobScreen.gd", out)
        self.assertIn("Tune.bind", out, "the guard must NAME the offending line")

    def test_tune_in_a_comment_or_a_string_literal_does_not_red(self):
        seed = ('\n\n# Tune.bind("prose.slug", 1.0) -- how this used to be written\n'
                'const _SEED_DOC := "Tune.get_value is the old spelling"\n')
        with SeededBreak(SUBJECT, seed):
            rc, out = run_guard()
        self.assertEqual(rc, 0, "prose is not a reach:\n" + out)

    def test_tune_inside_a_triple_quoted_block_does_not_red(self):
        # THE ARM A LINE-BASED BLANKER GETS WRONG. No line below carries both the
        # delimiter and the name, so only a STATEFUL blanker stays quiet here.
        seed = ('\n\nfunc _seeded_doc() -> void:\n\t"""\n'
                '\tThe old call was Tune.get_value(SLUG) and it asserted a prior bind.\n'
                '\tTune.bind is the registration half.\n'
                '\t"""\n\tpass\n')
        with SeededBreak(SUBJECT, seed):
            rc, out = run_guard()
        self.assertEqual(rc, 0,
                         "a `Tune.` inside a triple-quoted block is PROSE and must not "
                         "red -- a line-by-line blanker fails exactly here:\n" + out)

    def test_an_empty_subject_is_a_failure_not_a_pass(self):
        spec = importlib.util.spec_from_file_location("guard", GUARD)
        guard = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(guard)

        class EmptyCensus:
            @staticmethod
            def members():
                return [], 0

            code_lines = staticmethod(lambda *a, **k: [])

        real, argv = guard._census, sys.argv
        guard._census = lambda: EmptyCensus()
        sys.argv = ["check_ui_tune_port.py"]   # unittest's own argv would hit argparse
        try:
            import contextlib
            import io
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = guard.main()
        finally:
            guard._census, sys.argv = real, argv
        self.assertEqual(rc, 1, "an empty subject must FAIL, not pass by silence")
        self.assertIn("EMPTY", buf.getvalue())
        self.assertIn("DELETED", buf.getvalue(),
                      "the failure must say what to do at the move")


if __name__ == "__main__":
    unittest.main()
