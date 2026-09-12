# An unattended loop may delete a test, and a named survivor is what makes that safe

The suite is **736 processes**, not 736 functions. Godot boots with 28 autoloads in
each one and the cheapest test in the tree measures **2.31 s** warm, so the count is
the cost. `CLAUDE.md` already carries the measurement that says per-test speed work
cannot fix this — *"Cutting slow tests barely helps (80% of the clock is 66% of the
tests)"* — and the same paragraph names the only lever that pays: **running fewer**.

That makes *delete* and *merge* the two verdicts worth having, and both remove
coverage. This ADR is about the one property that makes an unattended overnight loop
allowed to reach for them.

**A green suite after a deletion proves nothing — deleting a test always keeps the
suite green.** The proof has to run the other way: before a test may be removed, some
*other* test must be shown to go red on the same seeded break. That other test is the
**survivor**, and the pair (`seeded_break`, `survivor`) is what a morning reviewer
reads instead of re-deriving the decision.

Status: accepted (2026-09-07). Establishes
[docs/TEST-CHARTER.md](../TEST-CHARTER.md) and `.claude/skills/test-audit-loop`.
Reads [ADR-0158](0158-the-suite-runs-in-parallel-and-the-lane-is-a-measurement.md)
for the parallel arm and the lane,
[ADR-0160](0160-a-register-taken-from-one-run-reports-a-verdict-and-not-a-flake-set.md)
for why one run cannot report a flake set, and
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) for the
eight tests the array names that do not live under `tests/`. Leaves every decision
any of them made standing.

## Context

### Why the obvious safety rules are not safety rules

Three candidate gates were considered and each fails on the same axis — it cannot
distinguish a deletion that lost coverage from one that did not.

**"Re-run the suite; if it is green the deletion was fine."** A deleted test cannot
fail. The suite is green *by construction*, and greener the more it deletes.

**"Never delete, only speed up."** This is the option the package's own measurement
refutes. 59% of tests finish inside Godot's boot cost; there is no speed left in them
to find. A loop restricted to speed work would run all night against the 41% and move
the wall clock by minutes.

**"Keep a floor — never go below N tests."** A count floor protects a statistic. It
stops the loop at an arbitrary number whether or not the next deletion was justified,
and permits every deletion before that number whether or not *those* were.

### What a seeded break already is here

Clause 10 of the charter asks every test to record the change that reds it. That is
not a new idea in this package; it is a defect it has paid for repeatedly, always
found by hand. [#421](https://github.com/timbermania/fft-monorepo/issues/421)'s guard
could not fail at all — `EditorImportPlugin.new()` returns null outside an editor and
the scene passed regardless. An arm elsewhere asked its subject for the subject's own
flag and passed a seeded defect. A rig that never spelled its subject's path could
not have noticed the subject's absence.

So the loop has to seed a break on every test it audits whatever verdict it reaches.
Given that, the delete gate costs nothing extra: the seed already exists, and the
question becomes *which other test does this same seed red*.

## Decisions

1. **An audit iteration may reach one of seven verdicts**: `KEEP`, `SPEED`,
   `DEMOTE`, `MERGE`, `DELETE`, `FLAKY`, `RED`. They are defined in `CONTEXT.md` →
   *Audit verdict*, and recorded in `docs/TEST-AUDIT-REGISTER.tsv`.

2. **`DELETE` and `MERGE` require a named survivor.** The register row must carry a
   `seeded_break` and a `survivor`, and the survivor must have been *observed* to red
   on that break — not argued to. A `DELETE` row with an empty `survivor` is an
   unfinished audit, and it is the one thing to check in review.

3. **The loop does not fix the game.** A test already failing on trunk is recorded
   `RED` and left alone. An overnight loop that starts debugging the navigator
   produces a morning's worth of commits nobody can review.

4. **One commit per iteration.** A bad call is one `git revert` away, and the PR body
   lists every deletion with its survivor.

5. **The loop works in its own worktree, cut from `origin/main`.** Root `CLAUDE.md`
   pins `fft-monorepo-main` to `main` by policy. Cutting from `origin/main` rather
   than from a working tree also keeps a hub's staged state out of the run — the
   measurement that opened this ADR found `NavigatorWorldMapFormationRenderTest`
   failing in 243 s against a hub whose `config/tune_overrides.json` had
   `navigator.auto_advance_node` staged true, which is the tunable `NavigatorMain.gd`
   documents as advancing past the world map. The test reported *"the world map never
   mounted"*. A loop that inherited that would have audited a false red.

6. **Verification per iteration is the test itself, its seeded break, and
   `scoped_tests.py`** — not the full suite. One full suite runs at the end of the
   night, before the PR, so the PR carries a real verdict. 736 full suites would
   monopolise a box that carries four other sessions.

7. **The loop holds when the box is busy.** Godot processes belonging to other
   worktrees mean another session is measuring something; the loop waits, bounded,
   and logs the skip. This is not politeness — three suites on this box are RAM-gated
   to serial, and a contended run produces verdicts neither session can trust.

## Consequences

The register becomes the reviewable artifact rather than the diff. A morning review
reads `verdict`, `seeded_break` and `survivor` per row and does not re-run anything.

Charter clauses 1 and 10 start at 736 violations each because they are new columns,
not because 736 tests are broken; they burn down at one row per audit. The three real
debts are small — 4 tests never call `.quit()`, 11 sleep a real duration, 20 read a
wall clock outside a `perf` declaration.

**This ADR does not claim the loop will reduce the suite.** Whether 736 contains
enough redundancy to matter is unmeasured; `docs/TEST-AUDIT-REGISTER.tsv`'s `overlap`
column is a candidate list, not a finding. The first night's register is what turns
that into a number.
