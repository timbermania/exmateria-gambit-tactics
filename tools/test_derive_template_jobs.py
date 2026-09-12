#!/usr/bin/env python3
"""Guard for the catalogue special_name -> job derivation (template_jobs.json).

The "show all templates" catalogue (ADR-0081) minted every unique Form with a
placeholder Squire job, so Ramza/Agrias/Orlandu et al. all read "Squire" in the
nameplate + ability menu. This tool derives each unique Form's REAL job from the
ENTD (dominant job byte per special_name) into a sibling derived bridge --
kept OUT of the assets-only template.json per ADR-0072 dec.2.

Two layers:
  * pure-logic tests over a synthetic ENTD fixture -- dominant-job selection and
    the 0xFE/0xFF sentinel skip;
  * a real-data invariant -- every residue special_name gets a valid-hex job, and
    the discriminating non-Squire uniques resolve to their canonical special job
    (skips if the authored inputs are absent).

Run:  uv run python -m unittest test_derive_template_jobs
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest import mock

import derive_template_jobs as dtj

TOOLS = Path(__file__).resolve().parent
GODOT = TOOLS.parent
SCEN = GODOT / "assets" / "scenarios"
RESIDUE = SCEN / "template_residue.json"
ENTD = SCEN / "entd.json"
JOBS = GODOT / "addons" / "exmateria_almanac" / "jobs" / "jobs.json"  # ADR-0251 dec. 2


def _entd(*slot_lists) -> dict:
    """Wrap raw slot lists as an entd.json-shaped doc."""
    return {"records": [{"slots": slots} for slots in slot_lists]}


def _slot(sn: int, job: int) -> dict:
    return {"special_name": sn, "job": job, "unit_id": sn}


class DominantJobTest(unittest.TestCase):
    def test_picks_highest_count(self) -> None:
        self.assertEqual(dtj.dominant_job({0x0D: 2, 0x11: 9}), 0x0D if 2 > 9 else 0x11)
        self.assertEqual(dtj.dominant_job({0x34: 6, 0x05: 1}), 0x34)

    def test_skips_randomise_and_empty_sentinels(self) -> None:
        # 0xFE (randomise) / 0xFF (empty) never win, even when most frequent.
        self.assertEqual(dtj.dominant_job({0x34: 1, 0xFE: 8, 0xFF: 4}), 0x34)

    def test_none_when_only_sentinels(self) -> None:
        self.assertIsNone(dtj.dominant_job({0xFE: 3, 0xFF: 2}))

    def test_none_when_empty(self) -> None:
        self.assertIsNone(dtj.dominant_job({}))


class JobDistributionTest(unittest.TestCase):
    def test_tallies_job_bytes_per_special_name(self) -> None:
        entd = _entd([_slot(52, 0x34), _slot(52, 0x34), _slot(13, 0x0D)],
                     [_slot(52, 0x34)])
        dist = dtj.job_distribution(entd)
        self.assertEqual(dict(dist[52]), {0x34: 3})
        self.assertEqual(dict(dist[13]), {0x0D: 1})


class DeriveJobsTest(unittest.TestCase):
    """Drive derive_jobs over a synthetic corpus by patching the loaders."""

    def _run(self, residue, entd):
        reads = {dtj.RESIDUE_PATH: {"residue": residue}, dtj.ENTD_PATH: entd}

        def fake_read(self):
            return json.dumps(reads[self])

        with mock.patch.object(Path, "read_text", fake_read):
            return dtj.derive_jobs()

    def test_dominant_job_per_residue_special_name(self) -> None:
        jobs = self._run(
            residue={"52": "agrias_52", "13": "orlandu_13"},
            entd=_entd([_slot(52, 0x34), _slot(52, 0x34), _slot(13, 0x0D)]))
        self.assertEqual(jobs, {52: "34", 13: "0d"})

    def test_only_residue_special_names_are_emitted(self) -> None:
        # A non-residue special_name in the ENTD is ignored.
        jobs = self._run(
            residue={"52": "agrias_52"},
            entd=_entd([_slot(52, 0x34), _slot(200, 0x11)]))
        self.assertEqual(jobs, {52: "34"})

    def test_all_sentinel_special_name_is_dropped(self) -> None:
        # A residue special_name whose every ENTD slot is a sentinel gets no job.
        jobs = self._run(
            residue={"52": "agrias_52", "99": "ghost_99"},
            entd=_entd([_slot(52, 0x34), _slot(99, 0xFE), _slot(99, 0xFF)]))
        self.assertEqual(jobs, {52: "34"})


class ShippedJobsInvariantTest(unittest.TestCase):
    """The real authored/derived data."""

    def setUp(self) -> None:
        for p in (RESIDUE, ENTD, JOBS):
            if not p.exists():
                raise unittest.SkipTest(f"authored input missing: {p}")
        self.residue = json.loads(RESIDUE.read_text())["residue"]
        self.jobs = dtj.derive_jobs()

    def test_every_residue_form_gets_a_valid_hex_job(self) -> None:
        # All 59 uniques resolve to a real job (the whole point -- no unmapped Form
        # falling back to the Squire placeholder).
        residue_sns = {int(sn) for sn in self.residue}
        self.assertEqual(set(self.jobs), residue_sns,
                         "every residue Form has a derived job")
        for sn, jhex in self.jobs.items():
            self.assertEqual(len(jhex), 2, f"job for {sn} is 2-hex ({jhex})")
            int(jhex, 16)  # raises if not valid hex

    def test_discriminating_uniques_map_to_their_special_job(self) -> None:
        # NON-Squire uniques -- the cases a regression to the placeholder would break.
        self.assertEqual(self.jobs[52], "34", "Agrias 52 -> Holy Knight (0x34)")
        self.assertEqual(self.jobs[13], "0d", "Orlandu 13 -> Holy Swordsman (0x0d)")

    def test_multi_form_character_separates_per_form(self) -> None:
        # Reis: human Form 15 (Dragoner 0x0f) vs dragon Form 72 (Holy Dragon 0x48).
        self.assertEqual(self.jobs[15], "0f", "Reis Form 15 -> Dragoner (0x0f)")
        self.assertEqual(self.jobs[72], "48", "Reis Form 72 -> Holy Dragon (0x48)")

    def test_written_file_matches_the_derivation(self) -> None:
        # The shipped template_jobs.json is the derivation's output (drift guard).
        if not dtj.JOBS_PATH.exists():
            self.skipTest("template_jobs.json not generated yet")
        shipped = {int(k): v for k, v in
                   json.loads(dtj.JOBS_PATH.read_text())["jobs"].items()}
        self.assertEqual(shipped, self.jobs,
                         "template_jobs.json is stale -- re-run derive_template_jobs.py --write")


if __name__ == "__main__":
    unittest.main()
