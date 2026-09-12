"""Direction tests for #1163 — the register guard's two kinds of staleness.

`docs/adr/INDEX.md` and `AUDIT.md` are generated, committed, and asserted at the
suite pre-flight, and `run_tests_parallel.py` exits at the first red guard. So
until #1163 one stale cell in a 270-row table stopped all 763 scenes — and the
trigger was invisible: `code`/`test`/`doc`/`tool`/`guard` and `cited_by` are
MEASURED from a walk, so **putting the string `ADR-0072` in a comment in a shell
script made a committed register stale.** `1d2426dc9` did exactly that and neither
author had any reason to look at `docs/adr/`.

The fix splits the verdict by PROVENANCE, and a split is only worth anything if it
is tested in BOTH directions — a classifier that calls everything "measured" would
pass a seed-only suite and would have deleted the arm the guard exists for. So each
pair below is a seed AND its control:

  measured cell moves   -> advisory, exit 0      | non-measured cell moves -> FAILS
  count goes UP         -> advisory              | count goes DOWN         -> advisory
  registers identical   -> nothing at all        | a row added             -> FAILS
  masked set is exactly {code,test,doc,tool,guard} / {cited_by}, asserted BY COLUMN
      NAME, so adding a column to either generator forces somebody to decide which
      side it is on rather than inheriting a default.

And the property that made the old arm worse than useless on its failure path:
🔴 THE GUARD MUST NOT WRITE. It used to run each generator as a subprocess and
compare the file before against the file after, leaving `AUDIT.md` MODIFIED in the
working tree whenever it aborted — three times per pre-flight, since the guard
block repeats. `TheGuardIsReadOnly` is that, measured on bytes AND mtime, because a
rewrite with identical bytes is still a write and still races a concurrent reader in
the same worktree.

Read-only also buys IDEMPOTENCE, which the old arm did not have and whose absence is
already written down: it rewrote the registers when it found them stale and THEN
reported red, so re-running it on the same tree came back green with no edit in
between. A red you cannot reproduce is a red nobody trusts. There is no separate test
for it — it follows from the guard not writing.

Run from tools/:
    uv run python -m unittest test_check_adr_classification
"""

from __future__ import annotations

import functools
import os
import pathlib
import subprocess
import sys
import unittest

_HERE = pathlib.Path(__file__).resolve().parent
os.chdir(_HERE.parent)
sys.path.insert(0, str(_HERE))

import gen_adr_audit  # noqa: E402
import gen_adr_index  # noqa: E402

# The guard runs top-to-bottom, so exec only the prefix that defines the two pure
# functions — the idiom test_check_adr_anchors.py already uses.
_SRC = (_HERE / "check_adr_classification.py").read_text(encoding="utf-8")
_NS: dict = {"__file__": str(_HERE / "check_adr_classification.py")}
exec(_SRC.split("\nfail = []\n")[0], _NS)
classify_drift = _NS["classify_drift"]
drift_report = _NS["drift_report"]

MASK = gen_adr_audit.MASK


@functools.lru_cache(maxsize=None)
def render(which: str, measured: bool) -> str:
    """One render per (generator, mode) for the whole module.

    `gen_adr_audit.render()` walks six roots; six uncached calls across four test
    classes cost more than everything else here put together, and this file runs in
    the suite pre-flight where that is somebody's wall clock. The renders are pure —
    `TheGuardIsReadOnly` is the proof — so caching them cannot hide a defect.
    """
    return {"index": gen_adr_index, "audit": gen_adr_audit}[which].render(measured=measured)

# A miniature AUDIT.md: the header the classifier reads column names from, one data
# row, and a prose line. `WANT` is the fresh render, `MASKED` the same render with
# the measured cells blanked — line-aligned by construction, which is the whole
# reason the rule can live in the generator instead of a regex here.
HEAD = "| ADR | bucket | lines | amd | dec | code | test | doc | tool | guard | arms | body | verdict |"
ROW = "| [0072](0072-a-template.md) | `content` | 221 | 1 | 6 | 19 | 11 | 12 | 12 | — | · | · | unaudited |"
ROW_MASKED = (f"| [0072](0072-a-template.md) | `content` | 221 | 1 | 6 | {MASK} | {MASK} "
              f"| {MASK} | {MASK} | {MASK} | · | · | unaudited |")
PROSE = "102 of 272 ADRs are named by a `tools/check_*.py`."
PROSE_MASKED = f"{MASK} of 272 ADRs are named by a `tools/check_*.py`."

WANT = "\n".join([HEAD, ROW, PROSE]) + "\n"
MASKED = "\n".join([HEAD, ROW_MASKED, PROSE_MASKED]) + "\n"


def _classify(have: str):
    return classify_drift("AUDIT.md", have, WANT, MASKED, MASK)


class MeasuredDriftIsNotTheAuthorsFault(unittest.TestCase):
    """A count moved because some unrelated file gained or lost an `ADR-NNNN`."""

    def test_a_tool_count_that_went_up_is_measured_not_structural(self):
        # The literal #1163 trigger: bootstrap_assets.sh gained `ADR-0072 dec.3`.
        have = WANT.replace("| 12 | — |", "| 13 | — |")
        self.assertNotEqual(have, WANT)                       # the seed really landed
        structural, measured = _classify(have)
        self.assertEqual(structural, [])
        self.assertEqual(len(measured), 1)
        self.assertIn("ADR-0072", measured[0])
        self.assertIn("tool 13→12", measured[0])              # committed→fresh

    def test_a_tool_count_that_went_DOWN_is_also_measured(self):
        # "A fix that only tolerates additions is half a fix" — #1163. Deleting the
        # comment must be as harmless as adding it, or the treadmill just runs the
        # other way.
        have = WANT.replace("| 12 | — |", "| 11 | — |")
        structural, measured = _classify(have)
        self.assertEqual(structural, [])
        self.assertEqual(len(measured), 1)
        self.assertIn("tool 11→12", measured[0])

    def test_the_guard_column_is_measured_too(self):
        # `guard` is a walk of tools/check_*.py, so writing a new guard that names
        # ADR-0072 moves this cell in a diff that touches no ADR.
        have = WANT.replace("| — | · |", "| battle_materials | · |")
        structural, measured = _classify(have)
        self.assertEqual(structural, [])
        self.assertEqual(len(measured), 1)

    def test_the_measured_number_in_the_prose_summary_is_measured(self):
        have = WANT.replace("102 of 272", "103 of 272")
        structural, measured = _classify(have)
        self.assertEqual(structural, [])
        self.assertEqual(len(measured), 1)
        self.assertIn("the summary line", measured[0])


class StructuralDriftStillFails(unittest.TestCase):
    """The arm the guard exists for: somebody edited a TSV and forgot the generator."""

    def test_a_moved_verdict_is_structural(self):
        have = WANT.replace("| unaudited |", "| complete |")
        structural, measured = _classify(have)
        self.assertEqual(measured, [])
        self.assertEqual(len(structural), 1)
        self.assertIn("verdict", structural[0])
        self.assertIn("NOT a measured column", structural[0])

    def test_the_adrs_own_line_count_is_structural(self):
        # `lines`/`amd`/`dec` are measured from the ADR's own body — an author who
        # moves one is standing in docs/adr/ already, so they keep the old contract.
        have = WANT.replace("| 221 | 1 | 6 |", "| 222 | 1 | 6 |")
        structural, measured = _classify(have)
        self.assertEqual(measured, [])
        self.assertEqual(len(structural), 1)
        self.assertIn("lines", structural[0])

    def test_a_masked_and_an_unmasked_cell_on_one_line_is_structural(self):
        # The hard cell wins. A row that drifted both ways is the author's to fix.
        have = WANT.replace("| 12 | — | · | · | unaudited |", "| 13 | — | · | · | complete |")
        structural, measured = _classify(have)
        self.assertEqual(measured, [])
        self.assertEqual(len(structural), 1)

    def test_an_added_row_is_structural(self):
        have = WANT.replace(PROSE, ROW + "\n" + PROSE)
        structural, measured = _classify(have)
        self.assertEqual(measured, [])
        self.assertEqual(len(structural), 1)
        self.assertIn("a row was added or removed", structural[0])

    def test_a_changed_prose_line_with_no_mask_is_structural(self):
        have = WANT.replace("named by a `tools/check_*.py`.", "named by a guard.")
        structural, measured = _classify(have)
        self.assertEqual(measured, [])
        self.assertEqual(len(structural), 1)

    def test_a_register_that_does_not_exist_is_structural(self):
        structural, measured = classify_drift("AUDIT.md", None, WANT, MASKED, MASK)
        self.assertEqual(measured, [])
        self.assertIn("MISSING", structural[0])


class TheClassifierCanAlsoSayNothing(unittest.TestCase):
    """Positive control — without this, a classifier that returns ([], []) always
    would pass every structural test above by accident."""

    def test_an_identical_register_yields_neither_finding(self):
        self.assertEqual(_classify(WANT), ([], []))


class TheGeneratorsDeclareTheProvenance(unittest.TestCase):
    """Asserted against the LIVE generators, BY COLUMN NAME. A new column in either
    one lands in neither set and fails here, which is the point: provenance is a
    decision somebody makes, not a default something inherits."""

    @classmethod
    def setUpClass(cls):
        cls.audit = (render("audit", True), render("audit", False))
        cls.index = (render("index", True), render("index", False))

    def _masked_columns(self, real: str, masked: str) -> set:
        header, out = [], set()
        for w, m in zip(real.splitlines(), masked.splitlines()):
            if w.startswith("| ADR |"):
                header = [c.strip() for c in w.split("|")]
                continue
            if not header or not w.startswith("| ["):
                continue
            for j, cell in enumerate(m.split("|")):
                if MASK in cell:
                    out.add(header[j])
        return out

    def test_the_audit_masks_exactly_the_five_outside_docs_adr(self):
        self.assertEqual(self._masked_columns(*self.audit),
                         {"code", "test", "doc", "tool", "guard"})

    def test_the_audit_does_NOT_mask_the_columns_read_from_the_tsvs(self):
        masked = self._masked_columns(*self.audit)
        for col in ("lines", "amd", "dec", "arms", "body", "verdict", "bucket"):
            self.assertNotIn(col, masked)

    def test_the_index_masks_exactly_cited_by(self):
        self.assertEqual(self._masked_columns(*self.index), {"cited_by"})

    def test_both_renders_are_line_aligned(self):
        # classify_drift asserts this; if it ever stopped holding the guard would
        # compare cell j of one table against cell j of another.
        for real, masked in (self.audit, self.index):
            self.assertEqual(len(real.splitlines()), len(masked.splitlines()))

    def test_the_masked_render_is_not_vacuously_equal(self):
        for real, masked in (self.audit, self.index):
            self.assertNotEqual(real, masked)
            self.assertIn(MASK, masked)
            self.assertNotIn(MASK, real)


class AgainstTheLiveRegister(unittest.TestCase):
    """Same two directions, but on the real 272-row render rather than a fixture —
    a fixture can agree with a classifier that disagrees with the generator."""

    @classmethod
    def setUpClass(cls):
        cls.want = render("audit", True)
        cls.masked = render("audit", False)

    def _row(self, text):
        return next(l for l in text.splitlines() if l.startswith("| [0001]"))

    def test_bumping_a_live_tool_count_is_measured_only(self):
        row = self._row(self.want)
        cells = row.split("|")
        header = next(l for l in self.want.splitlines() if l.startswith("| ADR |")).split("|")
        j = [i for i, c in enumerate(header) if c.strip() == "tool"][0]
        cells[j] = " 99 "
        have = self.want.replace(row, "|".join(cells))
        structural, measured = classify_drift("AUDIT.md", have, self.want, self.masked, MASK)
        self.assertEqual(structural, [])
        self.assertEqual(len(measured), 1)
        self.assertIn("ADR-0001", measured[0])

    def test_changing_a_live_verdict_is_structural(self):
        row = self._row(self.want)
        cells = row.split("|")
        cells[-2] = " superseded "
        have = self.want.replace(row, "|".join(cells))
        structural, measured = classify_drift("AUDIT.md", have, self.want, self.masked, MASK)
        self.assertEqual(measured, [])
        self.assertEqual(len(structural), 1)

    def test_the_committed_register_is_structurally_current(self):
        # The genuine arm, run for real. Measured drift is allowed here and is
        # reported by the guard; a structural finding means somebody edited a TSV
        # and did not re-run the generator, and that IS this branch's problem.
        for name, mod in (("INDEX.md", gen_adr_index), ("AUDIT.md", gen_adr_audit)):
            have = pathlib.Path("docs/adr", name).read_text(encoding="utf-8")
            key = "index" if name == "INDEX.md" else "audit"
            structural, _ = classify_drift(name, have, render(key, True),
                                           render(key, False), mod.MASK)
            self.assertEqual(structural, [], f"{name} is structurally stale")


class TheRoutingIsTestable(unittest.TestCase):
    def test_advisory_by_default(self):
        fatal, advisory = drift_report(["AUDIT.md:123 ADR-0072  tool 12→13"], strict=False)
        self.assertEqual(fatal, [])
        self.assertTrue(any("MEASURED DRIFT" in l for l in advisory))

    def test_fatal_under_strict(self):
        fatal, advisory = drift_report(["AUDIT.md:123 ADR-0072  tool 12→13"], strict=True)
        self.assertEqual(advisory, [])
        self.assertTrue(any("MEASURED DRIFT" in l for l in fatal))

    def test_no_drift_says_nothing_either_way(self):
        self.assertEqual(drift_report([], strict=False), ([], []))
        self.assertEqual(drift_report([], strict=True), ([], []))


class TheGuardIsReadOnly(unittest.TestCase):
    """🔴 The half of #1163 that has no count in it. The old arm WAS the generator:
    it ran both as subprocesses and compared before-file to after-file, so every
    pre-flight rewrote two tracked files and a FAILING one left them modified."""

    REGISTERS = ("docs/adr/INDEX.md", "docs/adr/AUDIT.md")

    def _stamp(self):
        return {f: (pathlib.Path(f).read_bytes(), pathlib.Path(f).stat().st_mtime_ns)
                for f in self.REGISTERS}

    def test_render_does_not_write(self):
        # Uncached on purpose — this is the one place that must see the real call.
        before = self._stamp()
        gen_adr_index.render()
        gen_adr_index.render(measured=False)
        gen_adr_audit.render()
        gen_adr_audit.render(measured=False)
        self.assertEqual(self._stamp(), before)

    def test_running_the_whole_guard_does_not_write(self):
        before = self._stamp()
        subprocess.run([sys.executable, "tools/check_adr_classification.py"],
                       capture_output=True, text=True)
        self.assertEqual(self._stamp(), before)

    def test_the_stamp_can_see_a_write(self):
        # Positive control for the two above — an instrument that cannot see a write
        # reports "did not write" for a guard that did.
        before = self._stamp()
        p = pathlib.Path(self.REGISTERS[0])
        body = p.read_bytes()
        try:
            p.write_bytes(body + b"\n")
            self.assertNotEqual(self._stamp(), before)
        finally:
            p.write_bytes(body)


if __name__ == "__main__":
    unittest.main()
