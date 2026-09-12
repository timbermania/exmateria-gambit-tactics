# Learn job picker shows the full job catalogue, not the unit's unlocked jobs

**This is a testing scaffold, not the shipping behavior.** The real game gates
the Learn picker to the generic jobs a unit has actually unlocked
(`UnitProgression.get_unlocked_jobs()`). We temporarily point the picker at
the full job catalogue to exercise its 11-row scroll/render pipeline and its
four number columns against real depth.

**Status:** accepted, and provisional on purpose — the scaffold above is the
current behaviour, and the gated path it replaces is retained untouched.

The job-domain sibling of
[ADR-0197](0197-ability-picker-shows-a-full-catalog-not-the-learned-set.md).

The formation "Learn" picker sourced its rows from the seeded unit's own
progression, which yields ~13 generic jobs against an 11-row window — barely
more than one screen, and never any special or monster job. We instead source
a **unit-independent catalogue**, `JobCandidates.build_catalog()`, that lists
**every** job in `jobs.json` carrying at least one JP-costed learnable ability
and honors **no** progression gate: 80 of 160 jobs — 56 special, 19 generic,
5 monster. Rows are `{hex-string id, name}` name-sorted with the **job index**
as the tie-break.

Dropping the other 80 jobs is **data hygiene, not a gate**: a job with an empty
learn list renders a dead row that can never commit.

## The row key is the job index, and the name column collides on purpose

Nineteen display names are shared by more than one job index. Six jobs are
named **"Squire"** — `01`, `02`, `03`, `04`, `07`, `4a` — with genuinely
different learn lists: `03` carries **Ultima** at 9999 JP, the generic `4a`
does not. The chapter/character-specific Squires are separate job indices, so
a faithful catalogue lists "Squire" six times.

Those six rows are shown with **identical, unsuffixed names**. Considered and
rejected: appending the hex id (to colliding names, or to all rows). The JOB
column runs x29..x119 (~90 px) and the longest job names already fill it
(`Holy Swordsman`, 14 chars), so a suffix would overflow into the Lv. column.
The four number columns already distinguish the rows in practice — the seeded
generic Squire reads `Lv3 / 430 / 120 / 430` against five zero rows.

This is why the sort tie-break and the row key are the **index**, not the
name. Nothing needed re-keying to reach Ultima: the hex job index was always
the key and maps 1:1 onto `skill_set_id`. The only thing hiding the
character-specific jobs was `get_unlocked_jobs()` enumerating generics.

## Deliberately not ROM-faithful

A unit can normally only learn from jobs it has unlocked, yet this picker
offers special (story) and monster jobs. It is a stress test of the scroll
pipeline — 80 rows through an 11-row window.

**The JP gate is retained.** Unlike ADR-0197's unvalidated commits, picking a
job still resolves its first unlearned learnable and charges its JP cost,
buzzing on insufficient JP. The catalogue only widens what is *listed*, so
committing Ultima onto an arbitrary unit still costs 9999 JP.

The gated path is retained, untouched, as `UnitProgression.get_unlocked_jobs()`
(still consumed by `ProgressionTester` and under test in
`ProgressionTesterTest`). Only one wiring seam in
`FormationDetailTransition._open_job_picker()` switched to the catalogue, so
restoring the real gated picker is a one-line revert.

`is_job_unlocked` / `get_locked_jobs` also enumerate generics only — check
them if anything else starts consuming the catalogue.

Guards: `tests/JobCandidatesTest.gd` (pure — counts, the collision tie-break,
`03` carries Ultima and `4a` does not, hygiene) and the reconciled
`tests/FormationLearnPickerTest.gd`, which now asserts the catalogue is a
strict **superset** of the gated set and drives the real `ui_down` path to a
job **by id** rather than by row index.
