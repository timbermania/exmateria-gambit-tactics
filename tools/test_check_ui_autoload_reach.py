#!/usr/bin/env python3
"""Direction tests for the arm-2a ratchet.

A ratchet has three ways to rot and a one-arm test catches one of them: it must red
on a NEW reach, on a GROWN count, AND on an entry whose debt was paid but whose
BASELINE line was left behind. The third is the one that silently re-admits a reach —
pay `EventBus` down to 0, leave `"EventBus": (4, ...)` in the table, and a later commit
can re-introduce four reaches under a green suite. That is not hypothetical: #1274 paid
`EventBus` off and this arm fired on the real tree before the entry was dropped.

Every arm asserts the guard NAMES what it caught. A red that does not say which
identifier moved sends the next reader to all six.
"""
import importlib.util
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SUBJECT = ROOT / "src/ui3/changejob/ChangeJobScreen.gd"


def load():
    """Fresh module per arm — BASELINE is module state and arms mutate it."""
    spec = importlib.util.spec_from_file_location(
        "cuar_%d" % load.n, ROOT / "tools" / "check_ui_autoload_reach.py")
    load.n += 1
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


load.n = 0


def run(mod):
    import io
    import contextlib
    buf = io.StringIO()
    argv = sys.argv
    sys.argv = ["check_ui_autoload_reach.py"]
    try:
        with contextlib.redirect_stdout(buf):
            rc = mod.main()
    finally:
        sys.argv = argv
    return rc, buf.getvalue()


class SeededBreak:
    """Edit a tracked file, guarantee a byte-identical restore."""

    def __init__(self, path, seed):
        self.path, self.seed = path, seed

    def __enter__(self):
        self.orig = self.path.read_bytes()
        self.path.write_text(self.path.read_text() + self.seed)
        return self

    def __exit__(self, *exc):
        self.path.write_bytes(self.orig)
        assert self.path.read_bytes() == self.orig, "restore was not byte-identical"
        return False


def _an_owed_identifier(mod):
    """One (name, (count, why)) still owed, taken from the module's own BASELINE.

    An empty BASELINE is not a reason to skip: it means arm 2a is MET, and the
    guard and these tests are due for deletion in the move commit (#1270). Say so
    rather than passing quietly.
    """
    assert mod.BASELINE, (
        "BASELINE is empty -- every autoload reach is paid and arm 2a is met. "
        "DELETE check_ui_autoload_reach.py, this file, and their run_all_tests.sh "
        "block in the move commit (#1270); do not leave a ratchet with no subject."
    )
    name = sorted(mod.BASELINE)[0]
    return name, mod.BASELINE[name]


class TestRatchet(unittest.TestCase):

    def test_clean_tree_is_green_and_not_green_by_silence(self):
        rc, out = run(load())
        self.assertEqual(rc, 0, out)
        # A pass that reported no number would also "pass"; demand the counts.
        # NEITHER LITERAL: the member count rots whenever the system gains or
        # loses a file (#1271 added `UIDebug.gd`, 121 -> 122) and the reach total
        # rots on every payment, so both would make this arm red for the RIGHT
        # change. Their correctness is the NEW/GREW/PAID-DOWN arms' job; this arm
        # only refuses a pass that said nothing.
        self.assertRegex(out, r"\d+ UI members")
        self.assertRegex(out, r"\d+ autoload reach\(es\) owed across \d+ identifier")

    def test_a_new_autoload_reach_reds_and_is_named(self):
        # `Focus` is a real host autoload that NO member reaches today.
        mod = load()
        with SeededBreak(SUBJECT, "\nfunc _seeded() -> void:\n\tFocus.grab()\n"):
            rc, out = run(mod)
        self.assertEqual(rc, 1, out)
        self.assertIn("NEW autoload reach", out)
        self.assertIn("Focus", out)
        self.assertIn("ChangeJobScreen.gd", out)

    def test_a_grown_count_reds_and_is_named(self):
        mod = load()
        # 🔴 THE SEED IS READ OUT OF BASELINE, NOT SPELLED HERE. This arm needs an
        # identifier that is STILL owed; a hardcoded one silently becomes a NEW-arm
        # test the moment that debt is paid, and then this arm tests nothing while
        # staying green-adjacent. It has already happened twice: the seed was
        # `EventBus` until #1274 paid it, then `DebugConfig` until #1271 paid it.
        # Reading BASELINE cannot rot while BASELINE has an entry, and when it has
        # none the guard itself is due for deletion -- which the assert below says.
        name, (count, _why) = _an_owed_identifier(mod)
        with SeededBreak(SUBJECT, "\nfunc _seeded() -> void:\n\t%s.probe()\n" % name):
            rc, out = run(mod)
        self.assertEqual(rc, 1, out)
        self.assertIn("GREW", out)
        self.assertIn(name, out)
        self.assertIn("is %d, BASELINE allows %d" % (count + 1, count), out)

    def test_a_paid_down_entry_left_in_the_baseline_reds(self):
        # THE arm a one-armed ratchet misses: the debt is gone, the line remains.
        mod = load()
        # Same rule as the GREW arm: the subject comes OUT of BASELINE.
        name, (count, why) = _an_owed_identifier(mod)
        mod.BASELINE[name] = (count + 99, why)
        rc, out = run(mod)
        self.assertEqual(rc, 1, out)
        self.assertIn("PAID DOWN but still listed", out)
        self.assertIn(name, out)
        self.assertIn("Lower it to %d" % count, out)

    def test_an_autoload_named_in_a_comment_or_string_does_not_red(self):
        mod = load()
        seed = ('\n# Focus is named here in PROSE and must not count.\n'
                'const _SEEDED := "Focus.grab() in a string literal"\n')
        with SeededBreak(SUBJECT, seed):
            rc, out = run(mod)
        self.assertEqual(rc, 0, out)

    def test_an_empty_subject_is_a_failure_not_a_pass(self):
        mod = load()
        mod.members = lambda: ([], 0)
        census = mod._census()
        orig = census.members
        try:
            mod._census = lambda: type("M", (), {
                "members": staticmethod(lambda: ([], 0)),
                "code_lines": staticmethod(census.code_lines)})()
            rc, out = run(mod)
        finally:
            census.members = orig
        self.assertEqual(rc, 1, out)
        self.assertIn("subject is EMPTY", out)
        self.assertIn("DELETE this guard", out)

    def test_no_declared_autoloads_is_a_failure_not_a_pass(self):
        mod = load()
        mod.autoload_names = lambda _t: []
        rc, out = run(mod)
        self.assertEqual(rc, 1, out)
        self.assertIn("no autoloads", out)


if __name__ == "__main__":
    unittest.main()
