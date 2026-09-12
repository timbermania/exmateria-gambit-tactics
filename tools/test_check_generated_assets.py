"""Seed-red tests for `check_generated_assets.violations` — the ADR-0001 ratchet.

A ratchet that only fails on a NEW violation is half a ratchet: it stays green
while somebody quietly deletes the row that was holding the line. So each of the
three ways to break the manifest gets its own seed, and each seed is paired with
the clean case it must NOT fire on — a guard that fails on everything discriminates
nothing.

The three failures, and why each is a real way to lose the invariant:

  1. A tracked artifact with NO row. This is the one that matters day to day: a
     new ROM-derived JSON gets committed and the manifest never hears about it.
  2. A manifest row whose ignore rule is GONE. Deleting a row silently un-ignores
     the artifact, and the next bootstrap re-commits Square Enix data. The row and
     the `.gitignore` block are generated from the same table precisely so this
     is detectable.
  3. A row that lies about itself: an `iso-*` row naming a generator that does not
     exist, or naming one at all when its provenance says a person wrote it.

`IgnoreBlockLocation` below is a different axis: not what the guard decides, but
whether it can READ its inputs at all, and whether the set it reads is the set
git actually honours.

Run from tools/:
    uv run python -m unittest test_check_generated_assets
"""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

import check_generated_assets as guard
from check_generated_assets import Row, read_ignored, violations

# A manifest that is correct in every respect — every seed below is this, with
# exactly one thing broken, so a failing assertion names the break and not the
# fixture.
CLEAN = [
    Row("assets/scenarios/entd.json", "iso-data", "parse_entd.py"),
    Row("assets/effects/trap/particle_header.json", "iso-code", "parse_trap_effect.py"),
    Row("assets/audio/captured_entity_state.json", "runtime-capture", "-"),
    Row("assets/scenarios/game_states.json", "hand-authored", "-"),
]
TRACKED = {
    "assets/audio/captured_entity_state.json",
    "assets/scenarios/game_states.json",
}
IGNORED = {
    "assets/scenarios/entd.json",
    "assets/effects/trap/particle_header.json",
}
TOOLS = {"parse_entd.py", "parse_trap_effect.py"}


def _run(rows=None, tracked=None, ignored=None, tools=None):
    return violations(
        rows if rows is not None else CLEAN,
        tracked if tracked is not None else TRACKED,
        ignored if ignored is not None else IGNORED,
        tools if tools is not None else TOOLS,
    )


class CleanManifest(unittest.TestCase):
    def test_a_correct_manifest_has_no_violations(self):
        self.assertEqual(_run(), [])

    def test_a_generated_artifact_absent_from_DISK_is_still_clean(self):
        """Absence from the working tree is not absence from git.

        The guard judges `git ls-files`, never `Path.exists()`. A worktree that has
        not run bootstrap has none of these files on disk, and that is the normal
        state of a fresh clone — reading it as a violation would make the guard red
        for everyone who has not extracted an ISO yet.
        """
        self.assertEqual(_run(), [])  # no path in CLEAN exists on disk


class NewViolation(unittest.TestCase):
    def test_a_tracked_artifact_with_no_row_fails(self):
        found = _run(tracked=TRACKED | {"assets/abilities/brand_new.json"})
        self.assertTrue(any("brand_new.json" in v for v in found), found)

    def test_a_row_that_is_BOTH_generated_and_tracked_fails(self):
        found = _run(tracked=TRACKED | {"assets/scenarios/entd.json"})
        self.assertTrue(any("entd.json" in v for v in found), found)


class RemovedEntry(unittest.TestCase):
    def test_a_generated_row_with_no_ignore_rule_fails(self):
        """Deleting the ignore rule is how the invariant is lost quietly."""
        found = _run(ignored=IGNORED - {"assets/scenarios/entd.json"})
        self.assertTrue(any("entd.json" in v for v in found), found)

    def test_an_ignore_rule_with_no_row_fails(self):
        found = _run(ignored=IGNORED | {"assets/abilities/orphan.json"})
        self.assertTrue(any("orphan.json" in v for v in found), found)


class LyingRow(unittest.TestCase):
    def test_a_generated_row_naming_a_missing_generator_fails(self):
        found = _run(tools=TOOLS - {"parse_entd.py"})
        self.assertTrue(any("parse_entd.py" in v for v in found), found)

    def test_a_committed_row_claiming_a_generator_fails(self):
        rows = [r for r in CLEAN if r.provenance != "hand-authored"]
        rows.append(Row("assets/scenarios/game_states.json", "hand-authored", "parse_entd.py"))
        found = violations(rows, TRACKED, IGNORED, TOOLS)
        self.assertTrue(any("game_states.json" in v for v in found), found)

    def test_an_unknown_provenance_fails(self):
        rows = CLEAN[1:] + [Row("assets/scenarios/entd.json", "probably-rom", "parse_entd.py")]
        found = violations(rows, TRACKED, IGNORED, TOOLS)
        self.assertTrue(any("probably-rom" in v for v in found), found)

    def test_a_committed_row_that_is_NOT_tracked_fails(self):
        """A hand-authored artifact nobody committed cannot be rebuilt by anything."""
        found = _run(tracked=TRACKED - {"assets/scenarios/game_states.json"})
        self.assertTrue(any("game_states.json" in v for v in found), found)


class IgnoreBlockLocation(unittest.TestCase):
    """The block lives in the PACKAGE's `.gitignore`, and git agrees with us.

    It used to live in the monorepo ROOT `.gitignore`, prefixed `godot-learning/`,
    and the guard read `PACKAGE.parent / ".gitignore"` — a path that escapes the
    standalone `exmateria-gambit-tactics` clone the package ships as, where the
    package IS the repo root. Measured before the move: a traceback with no
    `.gitignore` above the clone, 56 false violations with an unrelated one.

    One unprefixed copy in the package is correct in both repos, because git reads
    a `.gitignore` relative to its own directory. These arms hold that in place.
    """

    def test_the_block_is_in_the_PACKAGE_gitignore(self):
        self.assertEqual(guard.GITIGNORE, guard.PACKAGE / ".gitignore")
        self.assertIsNotNone(read_ignored(), f"no managed block in {guard.GITIGNORE}")

    def test_every_disc_derived_row_is_covered(self):
        """Direction test against the LIVE repo, not a fixture.

        Asserted against the manifest rather than a hardcoded path — artifacts
        move (`entd_positions.json` went to the almanac addon), and a guard test
        that rots on a rename teaches nothing about the guard.
        """
        ignored = read_ignored()
        disc = [r.path for r in guard.read_manifest() if r.provenance in guard.GENERATED]
        self.assertTrue(disc, "the manifest names no disc derivations at all")
        self.assertEqual(set(disc) - ignored, set())

    def test_the_rules_carry_NO_monorepo_prefix(self):
        """A `godot-learning/`-prefixed rule matches nothing in the standalone repo."""
        self.assertEqual(
            [p for p in read_ignored() if p.startswith(f"{guard.PACKAGE.name}/")], [])

    def test_GIT_ignores_exactly_what_the_guard_thinks_it_does(self):
        """The strongest arm: our parse of the block, checked against git itself.

        Everything else here reads the file the same way the guard does, so all of
        it would agree with a guard that was wrong in the same direction. This one
        asks `git check-ignore` — the only authority on what is actually ignored —
        and so it also catches the move landing rules git does not honour.
        """
        paths = sorted(read_ignored())
        r = subprocess.run(
            ["git", "check-ignore", "--no-index", "-v", "--", *paths],
            cwd=guard.PACKAGE, capture_output=True, text=True,
        )
        honoured = {line.split("\t", 1)[1] for line in r.stdout.splitlines() if "\t" in line}
        self.assertEqual(set(paths) - honoured, set(),
                         "the managed block names paths git does not ignore")
        # `check-ignore` names its source relative to the REPO root, which is the
        # monorepo root here and the package itself in the standalone clone — so
        # the assertion resolves it rather than matching a spelling.
        repo = Path(subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=guard.PACKAGE, capture_output=True, text=True, check=True,
        ).stdout.strip()).resolve()
        sources = {(repo / line.split(":", 1)[0]).resolve()
                   for line in r.stdout.splitlines() if ":" in line}
        self.assertEqual(sources, {guard.GITIGNORE.resolve()},
                         "a rule came from a .gitignore other than the package's — "
                         "it will be missing in the standalone repo")


class BlockParsing(unittest.TestCase):
    """How the block is read, on fixtures — the arms the live repo cannot seed."""

    @staticmethod
    def _gitignore(body: str) -> Path:
        d = Path(tempfile.mkdtemp())
        f = d / ".gitignore"
        f.write_text(body, encoding="utf-8")
        return f

    def test_a_gitignore_with_no_block_is_None_not_an_empty_set(self):
        """One named failure, not one violation per disc-derived row.

        An empty set re-derives the missing block as 56 identical "absent from
        the managed block" lines, none of which names the cause.
        """
        self.assertIsNone(read_ignored(self._gitignore("*.log\n")))

    def test_a_block_with_no_END_marker_is_None(self):
        self.assertIsNone(read_ignored(self._gitignore(
            f"{guard.BEGIN}\nassets/scenarios/entd.json\n")))

    def test_a_missing_gitignore_is_None_and_does_not_raise(self):
        self.assertIsNone(read_ignored(Path(tempfile.mkdtemp()) / "nope.gitignore"))

    def test_the_marker_lines_trailing_clause_is_not_read_as_a_path(self):
        """`BEGIN` is matched as a line PREFIX, so the block must be sliced by LINE.

        The marker reads `# BEGIN generated-assets (rendered from …tsv)`. Slicing
        the file with `str.split(BEGIN)` leaves `(rendered from …tsv)` as the
        block's first line. That was invisible while every rule carried a
        `godot-learning/` prefix to filter on; with package-relative rules it
        parses as a phantom path and the guard reports it as an ignore rule with
        no manifest row.
        """
        self.assertEqual(
            read_ignored(self._gitignore(
                f"{guard.BEGIN} (rendered from tools/data/generated_assets.tsv)\n"
                f"# a comment, not a path\n"
                f"assets/scenarios/entd.json\n"
                f"{guard.END}\n")),
            {"assets/scenarios/entd.json"},
        )

    def test_rules_outside_the_markers_are_not_read(self):
        self.assertEqual(
            read_ignored(self._gitignore(
                f"assets/before.json\n{guard.BEGIN}\nassets/inside.json\n"
                f"{guard.END}\nassets/after.json\n")),
            {"assets/inside.json"},
        )


if __name__ == "__main__":
    unittest.main()
