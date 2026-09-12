"""Tests for the #463 guard — including the arm that proves it FIRES.

A guard that only ever runs against a clean tree has demonstrated nothing: it is
green whether it works or not. So the direction test below is not a synthetic
sample, it is `ScenarioWalkToAnimTest.gd` AS IT ACTUALLY WAS — the real file with
its `[PASS]` marker taken back out, which is byte-for-byte the state that scored
`NO_VERDICT` in the two oldest archived full runs (2026-08-22 08:14 and 10:55)
and was fixed by hand in `2538dd4cc`.
"""
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
GUARD = ROOT / "tools" / "check_test_verdict_channel.py"


def run_guard(root: pathlib.Path):
    r = subprocess.run([sys.executable, str(GUARD), "--root", str(root)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


class TheGuardPassesOnTheTree(unittest.TestCase):

    def test_the_real_tests_directory_is_clean(self):
        code, out = run_guard(ROOT / "tests")
        self.assertEqual(code, 0, out)


class TheGuardFires(unittest.TestCase):
    """The other arm. Each case is a state the tree has actually been in."""

    def _scan(self, name: str, body: str):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / name
            p.write_text(body)
            return run_guard(pathlib.Path(d))

    def test_the_real_pre_fix_scenario_walk_to_anim_is_caught(self):
        # The regression, restored: strip the marker the fix added and the guard
        # must name the file the archived runs scored NO_VERDICT.
        src = (ROOT / "tests" / "ScenarioWalkToAnimTest.gd").read_text()
        stripped = "\n".join(l for l in src.splitlines()
                             if "[PASS]" not in l and "[FAIL]" not in l)
        code, out = self._scan("ScenarioWalkToAnimTest.gd", stripped)
        self.assertEqual(code, 1, out)
        self.assertIn("prints an assertion summary", out)
        self.assertIn("16 passed" if "16 passed" in stripped else "passed", out)

    def test_the_fixed_file_is_not_caught(self):
        # The paired arm, so the case above is a test of the RULE and not of the
        # guard's ability to complain about any file at all.
        src = (ROOT / "tests" / "ScenarioWalkToAnimTest.gd").read_text()
        code, out = self._scan("ScenarioWalkToAnimTest.gd", src)
        self.assertEqual(code, 0, out)

    def test_a_summary_with_no_verdict_channel_is_caught(self):
        code, out = self._scan("XTest.gd",
                               'func _f():\n\tprint("=== X: %d passed, %d failed ===" % [1, 0])\n')
        self.assertEqual(code, 1, out)

    def test_the_result_form_is_caught_too(self):
        # The other dialect ScenarioWalkToAnimTest spoke.
        code, out = self._scan("XTest.gd", 'func _f():\n\tprint("RESULT: PASS")\n')
        self.assertEqual(code, 1, out)

    def test_a_rig_that_asserts_is_caught(self):
        # Rule 2: `[NOT_A_TEST]` is read only when no marker exists, so a scene
        # that declares it AND counts assertions would launder a red into
        # "asserts nothing by design".
        code, out = self._scan("XTest.gd",
                               'func _f():\n\tprint("[NOT_A_TEST] a rig")\n'
                               '\tprint("=== X: %d passed, %d failed ===" % [1, 1])\n')
        self.assertEqual(code, 1, out)
        self.assertIn("a rig does not assert", out)

    def test_not_a_test_alone_does_not_satisfy_rule_one(self):
        # The declaration is not a verdict channel. A scene printing counts must
        # print a marker, not a rig declaration.
        code, out = self._scan("XTest.gd",
                               'func _f():\n\tprint("=== X: %d passed, %d failed ===" % [1, 0])\n'
                               '\tprint("[NOT_A_TEST] a rig")\n')
        self.assertEqual(code, 1, out)
        self.assertIn("NO [PASS]/[FAIL]/[VERDICT]", out)

    def test_a_verdict_declaration_satisfies_it(self):
        code, out = self._scan("XTest.gd",
                               'func _f():\n\tprint("=== X: %d passed, %d failed ===" % [1, 0])\n'
                               '\tprint("[VERDICT] PASS")\n')
        self.assertEqual(code, 0, out)

    def test_a_rig_with_no_summary_is_fine(self):
        code, out = self._scan("XRig.gd", 'func _f():\n\tprint("[NOT_A_TEST] a probe")\n')
        self.assertEqual(code, 0, out)

    def test_a_comment_is_not_a_marker(self):
        # A `##` docstring quoting `[PASS]` must not satisfy the rule — that is
        # how a guard goes quietly vacuous.
        code, out = self._scan("XTest.gd",
                               '## prints [PASS] when it works\n'
                               'func _f():\n\tprint("=== X: %d passed, %d failed ===" % [1, 0])\n')
        self.assertEqual(code, 1, out)

    def test_a_commented_out_summary_does_not_trip_it(self):
        code, out = self._scan("XRig.gd",
                               'func _f():\n\t# print("=== X: %d passed, %d failed ===")\n\tpass\n')
        self.assertEqual(code, 0, out)


class ItIsWiredAsAPreflight(unittest.TestCase):
    """A guard nobody runs is a guard that does not exist."""

    def test_the_suite_runs_it_before_booting_godot(self):
        text = (ROOT / "tests" / "run_all_tests.sh").read_text()
        self.assertIn("tools/check_test_verdict_channel.py", text)


if __name__ == "__main__":
    unittest.main()
