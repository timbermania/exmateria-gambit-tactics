"""Tests for the #417 guard — including the arms that prove it FIRES.

A guard that has only ever been run against a tree it already passes has
demonstrated nothing. Two kinds of firing arm below:

  - **synthetic**, one per rule, so each rule is shown to be the thing that fires
    rather than "the guard complains about something";
  - **real**, driven against THIS repository's actual `tests/` tree with one
    entry taken back out of the array — which is the exact shape of the defect
    #417 exists for: 300 marker-emitting scenes fell out of a hand-maintained
    list and nothing said so for two months.

The paired non-firing arm matters as much: without it, `assertEqual(code, 1)`
would pass for a guard that fails on everything.
"""
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUARD = ROOT / "tools" / "check_test_list_coverage.py"

MARKER_GD = 'func _ready():\n\tprint("[PASS] x: it works")\n'
RIG_GD = 'func _ready():\n\tprint("[NOT_A_TEST] a capture rig — it renders, it asserts nothing")\n'
BARE_RIG_GD = 'func _ready():\n\tprint("[NOT_A_TEST]")\n'


def run_guard(root: pathlib.Path):
    r = subprocess.run([sys.executable, str(GUARD), "--root", str(root)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


class Tree:
    """A minimal project root the guard can read: array, scenes, skip file."""

    def __init__(self, d: pathlib.Path):
        self.root = d
        (d / "tests").mkdir(parents=True, exist_ok=True)
        self.listed = []
        self.skips = []

    def scene(self, stem: str, body: str = MARKER_GD, script: bool = True):
        t = self.root / "tests"
        if script:
            (t / f"{stem}.gd").write_text(body)
            (t / f"{stem}.tscn").write_text(
                f'[gd_scene]\n[ext_resource type="Script" path="res://tests/{stem}.gd" id="1"]\n')
        else:
            (t / f"{stem}.tscn").write_text("[gd_scene]\n")
        return self

    def list_it(self, *stems):
        self.listed.extend(stems)
        return self

    def skip(self, stem, klass, reason):
        self.skips.append(f"{stem}\t{klass}\t{reason}")
        return self

    def write(self):
        entries = "\n".join(f'    "{s}"' for s in self.listed)
        (self.root / "tests" / "run_all_tests.sh").write_text(
            f"#!/bin/bash\nTESTS=(\n{entries}\n)\n")
        if self.skips:
            (self.root / "tests" / "skip_tests.tsv").write_text(
                "# stem\tclass\treason\n" + "\n".join(self.skips) + "\n")
        return run_guard(self.root)


class TheGuardPassesOnTheTree(unittest.TestCase):

    def test_this_repository_is_clean(self):
        code, out = run_guard(ROOT)
        self.assertEqual(code, 0, out)


class TheGuardFiresOnTheRealTree(unittest.TestCase):
    """The #417 defect itself, reproduced against the real files."""

    def test_dropping_one_real_test_out_of_the_array_is_caught(self):
        src = (ROOT / "tests" / "run_all_tests.sh").read_text()
        victim = "TuneOwnerSelfRegistrationTest"
        self.assertIn(f'"{victim}"', src, "fixture drifted — pick another listed test")
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            (d / "tests").mkdir()
            (d / "tests" / "run_all_tests.sh").write_text(
                src.replace(f'    "{victim}"\n', "", 1))
            for name in ("skip_tests.tsv",):
                p = ROOT / "tests" / name
                if p.is_file():
                    (d / "tests" / name).write_text(p.read_text())
            # Symlink the scene tree so the guard reads the REAL 744 scenes.
            for p in (ROOT / "tests").rglob("*"):
                if p.name in ("run_all_tests.sh", "skip_tests.tsv"):
                    continue
                q = d / "tests" / p.relative_to(ROOT / "tests")
                q.parent.mkdir(parents=True, exist_ok=True)
                if p.is_dir():
                    q.mkdir(exist_ok=True)
                elif not q.exists():
                    q.symlink_to(p)
            code, out = run_guard(d)
        self.assertEqual(code, 1, out)
        self.assertIn(victim, out)
        self.assertIn("[R1]", out)


class TheGuardFires(unittest.TestCase):
    """One arm per rule, each paired with the state that must stay green."""

    def _tree(self, d):
        return Tree(pathlib.Path(d))

    def test_r1_an_unlisted_marker_emitting_scene_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = self._tree(d).scene("OrphanTest").write()
        self.assertEqual(code, 1, out)
        self.assertIn("[R1] OrphanTest", out)

    def test_r1_listing_it_clears_it(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = self._tree(d).scene("OrphanTest").list_it("OrphanTest").write()
        self.assertEqual(code, 0, out)

    def test_r1_a_skip_row_clears_it(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d).scene("OrphanTest")
                         .skip("OrphanTest", "red", "fails one assertion, see #999")
                         .write())
        self.assertEqual(code, 0, out)

    def test_r1_a_not_a_test_declaration_clears_it(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = self._tree(d).scene("Shot", RIG_GD).write()
        self.assertEqual(code, 0, out)

    def test_r1_a_not_a_test_declaration_without_a_why_does_not(self):
        # The same requirement tests/lib/verdict.sh makes: a declaration with no
        # reason is a silence with a label on it.
        with tempfile.TemporaryDirectory() as d:
            code, out = self._tree(d).scene("Shot", BARE_RIG_GD).write()
        self.assertEqual(code, 1, out)
        self.assertIn("[R1] Shot", out)

    def test_r1_a_scriptless_scene_is_caught(self):
        # `tests/tools/*.tscn` mount their scripts from `tools/`, so there is no
        # `tests/*.gd` to declare in and the skip file is the only home.
        with tempfile.TemporaryDirectory() as d:
            code, out = self._tree(d).scene("bare_capture", script=False).write()
        self.assertEqual(code, 1, out)
        self.assertIn("[R1] bare_capture", out)

    def test_r2_an_unknown_class_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d).scene("OrphanTest")
                         .skip("OrphanTest", "later", "we will get to it eventually")
                         .write())
        self.assertEqual(code, 1, out)
        self.assertIn("[R2] OrphanTest", out)

    def test_r2_a_reason_too_short_to_be_one_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d).scene("OrphanTest")
                         .skip("OrphanTest", "red", "broken").write())
        self.assertEqual(code, 1, out)
        self.assertIn("[R2] OrphanTest", out)

    def test_r3_a_skip_row_for_a_scene_that_is_gone_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d).scene("RealTest").list_it("RealTest")
                         .skip("DeletedTest", "red", "it used to fail, see #999")
                         .write())
        self.assertEqual(code, 1, out)
        self.assertIn("[R3] DeletedTest", out)

    def test_r4_listed_and_skipped_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d).scene("BothTest").list_it("BothTest")
                         .skip("BothTest", "red", "fails one assertion, see #999")
                         .write())
        self.assertEqual(code, 1, out)
        self.assertIn("[R4] BothTest", out)

    def test_r5_a_duplicate_array_entry_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d).scene("DupTest")
                         .list_it("DupTest", "DupTest").write())
        self.assertEqual(code, 1, out)
        self.assertIn("[R5] DupTest", out)

    def test_r5_an_array_entry_with_no_scene_is_caught(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d).scene("RealTest")
                         .list_it("RealTest", "GhostTest").write())
        self.assertEqual(code, 1, out)
        self.assertIn("[R5] GhostTest", out)

    def test_a_clean_tree_of_all_three_states_is_green(self):
        # The paired arm for every case above at once: without it, "code == 1"
        # would be satisfied by a guard that fails unconditionally.
        with tempfile.TemporaryDirectory() as d:
            code, out = (self._tree(d)
                         .scene("RunsTest").list_it("RunsTest")
                         .scene("Shot", RIG_GD)
                         .scene("RedTest").skip("RedTest", "red", "fails one assertion, see #999")
                         .write())
        self.assertEqual(code, 0, out)


if __name__ == "__main__":
    unittest.main()
