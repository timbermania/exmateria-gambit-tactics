#!/usr/bin/env python3
"""Derive each unique catalogue Form's JOB from the ENTD (template_jobs.json).

The "show all templates" catalogue (ADR-0081) mints one owned Character per unique
Form but had no job data, so `AllTemplatesSeeder` seeded a placeholder Squire --
Ramza/Agrias/Orlandu et al. all showed "Squire" in the nameplate and the ability
menu. The job a Form should show IS in the ENTD: every deployment slot carries a
`job` byte, and for a story unit that byte is the character's special job (Agrias
-> Holy Knight, Orlandu -> Holy Swordsman). We take the DOMINANT (most-frequent,
non-sentinel) job across every ENTD slot carrying a residue Form's `special_name`
-- the same distribution machinery `derive_template_residue.py` uses for the body
sprite, keyed on `job` instead of `sprite_set`.

This is a SIBLING derived bridge (`special_name -> job`), kept OUT of the
assets-only `template.json` per ADR-0072 dec.2 ("a template is assets only; no
stats -- a unique's ROM data seeds the Character, not its template"). It mirrors
`template_residue.json` (special_name -> folder) and `template_assets.json`
(special_name -> body sprite): durable, git-tracked, parsed-into-assets, so the
seeder reads a baked map rather than computing over the ENTD at runtime.

The per-Form granularity resolves multi-Form characters for free: Reis Form 15 is
a Dragoner (0x0f), Form 72 is a Holy Dragon (0x48) -- distinct special_names,
distinct rows, distinct jobs. `0xFE` (randomise) / `0xFF` (empty) slots are
skipped when tallying.

Run:
    uv run python tools/derive_template_jobs.py            # report only
    uv run python tools/derive_template_jobs.py --write    # (re)write template_jobs.json
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict

from _repo_paths import almanac_dir, assets_dir, catalogue_dir

RESIDUE_PATH = catalogue_dir("templates/template_residue.json")   # ADR-0251 dec. 2, #1025 pass 3
ENTD_PATH = assets_dir("scenarios/entd.json")
JOBS_PATH = catalogue_dir("seeding/template_jobs.json")          # ADR-0251 dec. 2, #1025 pass 3
JOBDB_PATH = almanac_dir("jobs/jobs.json")                     # ADR-0251 dec. 2

# ENTD sentinel job bytes (ENTD_FORMAT.md): 0xFE = "randomise / use story value",
# 0xFF = "empty slot". Neither is a real job -- skip when tallying.
RANDOMISE = 0xFE
EMPTY = 0xFF


def _entd_slots(entd: dict) -> list:
    recs = entd["records"]
    return list(recs.values() if isinstance(recs, dict) else recs)


def job_distribution(entd: dict) -> dict:
    """{special_name -> {job -> count}} over every ENTD slot."""
    dist: dict = defaultdict(lambda: defaultdict(int))
    for rec in _entd_slots(entd):
        for slot in rec.get("slots", []):
            sn = slot.get("special_name")
            jb = slot.get("job")
            if sn is not None and jb is not None:
                dist[sn][jb] += 1
    return dist


def dominant_job(dist_for_sn: dict) -> int | None:
    """The most-used non-sentinel job byte for one special_name, or None.

    Ties break on the higher job value (deterministic), matching the residue
    tool's `sorted(..., reverse=True)[0]` convention."""
    ranked = sorted(((n, jb) for jb, n in dist_for_sn.items()
                     if jb not in (RANDOMISE, EMPTY)), reverse=True)
    if not ranked:
        return None
    _n, jb = ranked[0]
    return jb


def derive_jobs() -> dict:
    """{special_name (int) -> job "%02x"} for every residue Form with an ENTD job.

    A residue Form whose ENTD slots are all sentinels (or that never appears) is
    omitted -- the seeder falls back to its own default for a missing key."""
    residue = json.loads(RESIDUE_PATH.read_text())["residue"]
    entd = json.loads(ENTD_PATH.read_text())
    dist = job_distribution(entd)

    out: dict = {}
    for sn_str in residue:
        sn = int(sn_str)
        jb = dominant_job(dist.get(sn, {}))
        if jb is not None:
            out[sn] = "%02x" % jb
    return dict(sorted(out.items()))


def _write(jobs: dict) -> int:
    """Write template_jobs.json (special_name string -> job hex). Idempotent."""
    doc = {
        "_note": ("special_name -> dominant ENTD job (2-hex jobs.json key) for each "
                  "unique catalogue Form. Derived by tools/derive_template_jobs.py; a "
                  "sibling of template_residue.json/template_assets.json kept OUT of "
                  "the assets-only template.json (ADR-0072 dec.2). Consumed by "
                  "AllTemplatesSeeder so the nameplate + ability menu show the real job."),
        "jobs": {str(sn): jhex for sn, jhex in sorted(jobs.items())},
    }
    JOBS_PATH.write_text(json.dumps(doc, indent=1) + "\n")
    return len(doc["jobs"])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true",
                    help="(re)write addons/exmateria_catalogue/seeding/template_jobs.json")
    args = ap.parse_args()

    jobs = derive_jobs()
    jobdb = json.loads(JOBDB_PATH.read_text()).get("jobs", {}) if JOBDB_PATH.exists() else {}
    residue = json.loads(RESIDUE_PATH.read_text())["residue"]

    print(f"{'sn':>4} {'token':<16} {'job':>4} jobname")
    for sn, jhex in jobs.items():
        name = jobdb.get(jhex, {}).get("name", "?")
        print(f"{sn:>4} {residue.get(str(sn), '?'):<16} 0x{jhex} {name}")
    missing = sorted(int(sn) for sn in residue if int(sn) not in jobs)
    print(f"\n{len(jobs)}/{len(residue)} residue Forms mapped"
          + (f"; unmapped (all-sentinel): {missing}" if missing else " (all mapped)"))

    if args.write:
        n = _write(jobs)
        print(f"wrote {JOBS_PATH} ({n} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
