"""Seed-red tests for `check_adr_anchors.anchors_of` — what an ADR OFFERS.

The guard's own report is a count of citations that resolve, and a bug that makes an
ADR offer LESS shows up there as *silence*: an offer that is not made is not a failure
until somebody outside `docs/adr/` writes the citation. `docs/adr/` is excluded from the
citation scan, so an ADR quoted only by other ADRs can lose its whole Decision section
and the guard stays green.

That is not hypothetical — it is how these tests came to exist. ADR-0241 quotes GDScript
in a fenced block, GDScript docstrings begin `## `, and the section matcher read one as a
Markdown heading and turned `in_decision` off. The ADR offered **decision 1 and nothing
else**, and `dec. 2`-`dec. 9` were uncitable from any `.py` or `.gd` in the package.
ADR-0243 dec. 13 records it.

So these assert the OFFER directly rather than the exit code, in both directions: a
fence must not end a section (the seed), and a real `##` heading must still end one (the
control, so the fix is not "ignore section state").

Run from tools/:
    uv run python -m unittest test_check_adr_anchors
"""

from __future__ import annotations

import os
import pathlib
import re
import tempfile
import unittest

_HERE = pathlib.Path(__file__).resolve().parent
os.chdir(_HERE.parent)

_SRC = (_HERE / "check_adr_anchors.py").read_text()
_NS: dict = {}
exec(_SRC.split("adr_dir = pathlib.Path")[0], _NS)
anchors_of = _NS["anchors_of"]


def _offers(body: str):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(body)
        path = pathlib.Path(fh.name)
    try:
        return anchors_of(path)
    finally:
        path.unlink()


GDSCRIPT_IN_A_FENCE = """\
## Decision

**1. The first one.**

```
## A Character = identity, the catalog record above the battle roster.
## It also holds refs to the durable functional objects.
```

**2. The second one.**

**3. The third one.**
"""

REAL_HEADING_ENDS_IT = """\
## Decision

**1. The first one.**

## Considered alternatives

**2. Not a decision at all.**
"""

TILDE_FENCE = """\
## Decision

**1. The first one.**

~~~
## Not a heading.
```
## Still not a heading — a backtick run does not close a tilde fence.
~~~

**2. The second one.**
"""


class FenceDoesNotEndTheDecisionSection(unittest.TestCase):
    def test_quoted_gdscript_docstring_is_not_a_heading(self):
        """THE SEED. Before the fix this returned {'1'}."""
        _, dec, _ = _offers(GDSCRIPT_IN_A_FENCE)
        self.assertEqual(dec, {"1", "2", "3"})

    def test_tilde_fence_is_not_closed_by_backticks(self):
        _, dec, _ = _offers(TILDE_FENCE)
        self.assertEqual(dec, {"1", "2"})

    def test_numbers_inside_a_fence_are_not_sections(self):
        """`12.6  12.6  9.6` is a table row, not `§ 12`. ADR-0137 is the live case."""
        _, _, sec = _offers("## Decision\n\n**1. One.**\n\n```\n12.6  12.6  9.6\n```\n")
        self.assertNotIn("12", sec)
        self.assertIn("1", sec)


class SectionStateStillWorks(unittest.TestCase):
    def test_a_real_heading_still_ends_the_decision_section(self):
        """THE CONTROL. The fix must not be 'stop tracking sections'."""
        _, dec, sec = _offers(REAL_HEADING_ENDS_IT)
        self.assertEqual(dec, {"1"})
        self.assertIn("2", sec, "it is still a numbered item, just not a decision")


class TheLiveCorpus(unittest.TestCase):
    def test_adr_0241_offers_all_nine_decisions(self):
        """The ADR that surfaced the defect, asserted against the real file."""
        p = next(pathlib.Path("docs/adr").glob("0241-*.md"))
        _, dec, _ = anchors_of(p)
        self.assertEqual(dec, {str(i) for i in range(1, 10)})

    def test_adr_0137_no_longer_offers_the_fenced_table_row(self):
        """THE OTHER HALF of the blast radius, and the only thing the fix takes away.

        ADR-0137 used to offer `12` in its any-numbered set. It was never a section:
        it is `12.6  12.6  9.6` — a row of camera sizes in a fenced table, matched by
        `NUM` because the row begins with a number and a dot. Nothing outside
        `docs/adr/` addresses that anchor, so removing it costs no citation.

        Asserted as an absence deliberately: a wrong anchor that resolves is exactly
        the failure this guard exists to prevent, one ADR up.
        """
        p = next(pathlib.Path("docs/adr").glob("0137-*.md"))
        _, _, sec = anchors_of(p)
        self.assertNotIn("12", sec)


if __name__ == "__main__":
    unittest.main()
