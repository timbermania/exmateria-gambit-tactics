"""Tests for the key-location ownership guard (ADR-0088 Amendment 2 §2).

A key location `<ns>.loc.<name>` must be DEFINED in exactly one owner class — the class
its namespace names — so a position is always colocated with its owner and the
namespace→owner mapping the deferred Amendment 3 §7 "add a location" injection needs is
unambiguous. The guard is a static source scan: a definition is a source fact (the slug
STRING LITERAL lives only in the owner's const/bind block; consumers reference that
const, never re-literal the slug), so grouping literals by namespace must yield exactly
one owner file per namespace.
"""
import pathlib
import tempfile
import unittest

import check_location_ownership as guard


def _write(root, rel, text):
    p = pathlib.Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    return p


class ScanTest(unittest.TestCase):
    def test_single_owner_is_clean(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "src/foo/FooWindow.gd", (
                'const LOC_A := "foo.loc.a"\n'
                'const LOC_B := "foo.loc.b"\n'
            ))
            self.assertEqual(guard.check(f"{d}/src"), [])
            owners = guard.resolve(f"{d}/src")
            self.assertEqual(set(owners.keys()), {"foo"})
            self.assertTrue(owners["foo"].endswith("FooWindow.gd"))

    def test_namespace_split_across_two_classes_fails(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "src/a/AWin.gd", 'const L := "foo.loc.a"\n')
            _write(d, "src/b/BWin.gd", 'const L := "foo.loc.b"\n')
            violations = guard.check(f"{d}/src")
            self.assertEqual(len(violations), 1)
            self.assertIn("foo", violations[0])
            self.assertIn("AWin", violations[0])
            self.assertIn("BWin", violations[0])

    def test_consumer_const_reference_is_not_an_owner(self):
        # A consumer that answers at(LOC_A) references the const, not the literal, so it
        # must NOT be counted as an owner (that is the whole colocation convention).
        with tempfile.TemporaryDirectory() as d:
            _write(d, "src/foo/FooWindow.gd", 'const LOC_A := "foo.loc.a"\n')
            _write(d, "src/foo/Consumer.gd", 'func _r(): UI3Element.at(FooWindow.LOC_A)\n')
            self.assertEqual(guard.check(f"{d}/src"), [])
            self.assertTrue(guard.resolve(f"{d}/src")["foo"].endswith("FooWindow.gd"))

    def test_prose_and_marker_mentions_do_not_match(self):
        # Doc comments (`startmenu.loc.*`, `<ns>.loc.`) and the ".loc." marker string are
        # not full quoted slugs and must not be picked up as definitions.
        with tempfile.TemporaryDirectory() as d:
            _write(d, "src/foo/Notes.gd", (
                '# the foo.loc.* homes are picked by policy\n'
                'var marker := ".loc."\n'
                'if s.contains(".loc."): pass\n'
            ))
            self.assertEqual(guard.check(f"{d}/src"), [])
            self.assertEqual(guard.resolve(f"{d}/src"), {})

    def test_quoted_example_slug_in_a_comment_is_not_an_owner(self):
        # A doc-comment example like `## "foo.loc.a" -> "a"` is not a definition; only the
        # real const literal counts, so a helper file that merely documents the format
        # must not register as a second owner.
        with tempfile.TemporaryDirectory() as d:
            _write(d, "src/foo/FooWindow.gd", 'const LOC_A := "foo.loc.a"\n')
            _write(d, "src/debug/Helper.gd", '## Example: "foo.loc.a" -> "a" (the tail)\n')
            self.assertEqual(guard.check(f"{d}/src"), [])
            self.assertTrue(guard.resolve(f"{d}/src")["foo"].endswith("FooWindow.gd"))

    def test_empty_tree_is_clean_not_crash(self):
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, "src").mkdir()
            self.assertEqual(guard.check(f"{d}/src"), [])
            self.assertEqual(guard.resolve(f"{d}/src"), {})


class RealTreeTest(unittest.TestCase):
    def test_startmenu_locations_are_owned_by_startactionmenu(self):
        # The live invariant the user asked to "make sure is always there": the only key
        # locations today (startmenu.loc.*) resolve to exactly StartActionMenu.
        src = pathlib.Path(__file__).resolve().parents[1] / "src"
        self.assertEqual(guard.check(str(src)), [])
        owners = guard.resolve(str(src))
        self.assertIn("startmenu", owners)
        self.assertTrue(owners["startmenu"].endswith("StartActionMenu.gd"))


if __name__ == "__main__":
    unittest.main()
