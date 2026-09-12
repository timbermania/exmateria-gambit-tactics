# Refactor progress is two per-cluster numbers, never one score

Progress is measured per ballast cluster as **scatter** and **crossing
discipline**, reported as a vector and never collapsed into a single figure.
Clusters with thin ballast report *no signal* rather than a flattering zero, and
the metric never gates a commit.

Status: accepted (2026-08-19); the denominator changed from ballast cluster to
blueprint system by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20). Depends on
[ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md).

## Context

The refactor spans months, so it needs a longitudinal signal that does not
depend on the refactorer's own shifting architectural opinion. The target
property has two clauses: code should be **deeply connected where it is supposed
to be**, and **interfaced where it has to be**. Those are two measurements.

Vault coverage is severely uneven — `scenarios` 148 citations, `effects` 89,
`gpu` 2, `strategy` 0. Any global sum is dominated by the two most heavily
reverse-engineered subsystems, which would amount to measuring the scenario VM
and calling it the codebase.

## Decision

**1. Two numbers per cluster, kept apart.**

- **Scatter** — how many distinct modules hold code cited by this cluster's
  notes. Falls as a system consolidates into its addon. This is *deeply
  connected where we are supposed to be*.
- **Crossing discipline** — of the code this cluster shares with other clusters,
  the fraction sitting on a **declared addon interface** rather than reaching
  into internals. This is *interfaced where we have to be*; the addon model
  supplies the denominator, since a public surface is a declarable thing.

Kept apart, a bad reading says *which* problem exists. Collapsed, it says only
that something got worse.

> **Amended by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20).** The *keeping apart* holds and is
> extended; the **denominator changes from ballast cluster to blueprint
> system**. A cluster with thin ballast reports no signal — `gpu` carries 2
> citations for 6,907 lines, `strategy` 0 — and dec. 2 below concedes the hole
> grows as the project succeeds. Per system, every line lands in exactly one
> bucket by construction, so coverage is total and does not decay. The two
> counts become **lines** and **uninterfaced reaches**, and they are never
> divided: a ratio falls whenever a system merely grows internally. dec. 2's
> *unobserved* rule survives for ballast-derived readings, not for the progress
> bar.

**2. Per-cluster vector, never a scalar.** A cluster with no notes is not
well-modularised — it is **unobserved**, and must report as such.

**3. Never a commit gate.** The moment it becomes a gate it becomes a thing to
satisfy rather than a thing to learn from. Read directionally, over months.

**4. The instrument must not change mid-series.** All code↔vault markers are
backfilled **before** the baseline is taken. A baseline computed from the vault's
`R:` paths and later measurements computed from code-side markers would show a
step change at every extraction that is an artifact of swapping instruments, not
a signal — and months of series would be unreadable. After the backfill the `R:`
lines are only ever the seed. (The alternative — measuring both ways at baseline
and calibrating the offset — works, is much cheaper, and is easier to get subtly
wrong.)

**5. The reading is global and against the baseline.** It is computed over
*every* cluster at each merge, not only the system just extracted — the failure
this metric exists to catch is local improvements that sum to a worse whole, and
a per-system reading is blind to exactly that. And it compares against the
**baseline**, never the previous commit: the noise-cancellation argument above
holds over a long interval and not over a single merge. A last-merge→HEAD figure
may be reported alongside to attribute one extraction; the baseline→HEAD trend is
the one to trust.

**6. Predict before building.** `project()` is a program and a proposed boundary
is only a different grouping over the same graph, so a candidate seam is scored
before any code is written. Measuring solely at merge means the metric reports
but cannot steer.

**7. Inventory is tracked alongside, not folded in.** Gaps (`R: none` delta),
residue, autoload fan-in and ADR conformance are counts, not quality. Mixing
inventory into a quality score makes both unreadable.

## Considered alternatives

- **A single composite score.** Rejected: hides which property moved, and a
  single number invites optimising the number — a real risk on a self-driven
  refactor, not a theoretical one.
- **Crossings only.** Rejected: it is the original framing ("which connection
  exists that shouldn't?") and the cheapest thing that could work, but blind to
  a cluster that is internally scattered while happening not to cross — which
  describes most of a half-finished extraction.
- **A full dashboard.** Rejected as *the metric*: every input exists, but
  dashboards decay into wallpaper. The extra series live as counts instead.

## Consequences

- `R:` lines are model-written prose, so the graph is noisy. That noise largely
  cancels in a **difference** — stable noise subtracts out — which is why this
  works as a trend and would not work as a point-in-time score.
- The measurement is only valid against a **pinned** ballast SHA, and
  the projection therefore takes two refs (`docs/adr/0002`). An unpinned
  vault conflates code improvement with research rewriting.
