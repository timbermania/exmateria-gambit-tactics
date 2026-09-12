# The research vault is refactor ballast, not the architecture blueprint

The Obsidian research vault provides the **fixed external reference** against
which refactor drift is measured. It does **not** supply the target module
boundaries. Its note↔note graph is the ballast; its `R:` code citations are the
measurement; the blueprint comes from a separate, game-agnostic domain model.

Status: accepted (2026-08-19); dec. 7's adoption figure corrected by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
(2026-08-20);
dec. 1, dec. 5 and dec. 7 amended by [#310](https://github.com/timbermania/fft-monorepo/issues/310) (2026-08-21).

## Context

A refactor spanning many months cannot use its own architectural opinion as its
reference — that opinion drifts, and drift is the failure being guarded against.
Something external and unmoving is required.

The vault is the obvious candidate: 148 notes, 12 domain indexes beneath one
root index (`AI Research Index`), and 732 mandatory `R:` sub-bullets projecting
research points onto code (`vault/AGENTS.md`).

> **Corrected 2026-08-21 ([#310](https://github.com/timbermania/fft-monorepo/issues/310)).** Re-measured at `main` `dafcb81b3`:
> **230 notes**, **15** domain indexes beneath the root index, and **1,717** `R:`
> sub-bullets — every figure roughly double the one above, four days later. **516**
> of those `R:` lines read `none` (`godot-learning/CONTEXT.md` → **Gap** said 251).
> `vault/AGENTS.md` itself still specifies only **7** domain indexes and is stale on
> `main`; it is not corrected here, because nothing is ever written to `vault/`
> (dec. 6).

The trap is promoting it from *yardstick* to *blueprint*. **The knowledge is
filed ROM-shaped.** `Effect System` is one cohesive cluster because `E###.BIN`
is one file format — but inside it are a particle renderer, an audio trigger
bus, camera shake, screen flashes and palette tinting: at least four systems,
clustered only because they arrive through one parser. `Event VM` is the same
failure: `ScenarioVM.gd` cites 32 notes and touches everything because the ROM's
opcode set touches everything, not because the code failed to modularise. Its
60 opcode handlers are 925 of its 4,383 lines; the other 79% is accreted
machinery no cluster predicted.

Adopting those clusters as target boundaries would import precisely the
decomposition and vocabulary that goals #2, #6 and #7 exist to remove.

## Decision

**1. Ballast is the note↔note wikilink graph plus index membership.** These are
claims about the domain, containing no reference to code, so refactoring cannot
perturb them. **Pinned to a SHA per measurement** — the vault is a living
document, and an unpinned yardstick conflates *the code got better* with *the
research got rewritten*.

> **Amended by [#310](https://github.com/timbermania/fft-monorepo/issues/310) (2026-08-21). One reading, so one pin — there is no
> re-pin cadence, and nobody owns one.** The refactor is driven by the **blueprint**:
> `classify_blueprint.py` assigns `src/` files to one of the eleven systems and
> `touch_matrix.py` counts the crossings between them — both built and running today.
> At trunk `fe9ad574a` (classifier `34848f14f`), after the Effect Studio branches
> landed: **533 files / 177,748 lines**, in a system **148,102 (83.3%)**, **400**
> cross-system edges. *(This ADR was written against `b935f0fa9` — 470 files /
> 141,837 lines / 367 edges — before those ~36k lines arrived; the figures move, the
> argument does not.)* **⚠ `UNCLASSIFIED` regressed from 0 to 1**:
> `src/debug/DetailScreenDebugPanel.gd` (158 lines) matches no fragment in the
> `src/debug/` filename list, which is precisely the maintenance treadmill
> [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md) dec. 1 named — and
> `classify(...)` returns `None` **silently**. Left unfixed on purpose: it is a pass-4
> instrument change and ADR-0131 requires those to land together. The ballast is read **once, at the end**, as a qualitative
> assessment rather than a series. dec. 5 is what makes that free: `project()` is a
> function over two preserved git histories, so the end-state assessment computes its
> own baseline reading retroactively. With a single reading there is no series for a
> living vault to perturb, so *"per measurement"* selects **one** SHA, chosen when the
> assessment is taken. The re-pin **owner**, **trigger** and **discontinuity rule**
> this decision implied are vacated — there is nothing between now and then to own.
>
> Deferring is safe because the ballast is **monotone**. Over its 28 commits
> (2026-08-17 → 2026-08-21) it went **74 → 230 notes** and **310 → 1,395 edges**,
> tripling in five days, via **1,114 edge additions against 29 deletions** — and **no
> note has ever been deleted**. Nothing the end-state assessment will want has been
> lost in the meantime. What the same churn *does* cost is this ADR's own Context
> figures; see the correction there.
>
> The trade accepted: **no mid-refactor signal.** A behaviour dropped at extraction #3
> surfaces after #15, not at #3.

**2. Measurement is the `R:` edge set** — the only part that moves, and it moves
because the code moved.

**3. The ballast answers directional questions only.** *Is the code implementing
this body of knowledge more scattered than it was?* needs no correct answer,
which is what makes it non-circular. *Should these be one module or two?* is
positional and requires knowing the target — the ballast cannot supply it.

**4. The blueprint is a fresh game-agnostic tactics-RPG domain model**, built
without reference to FFT or to the current code, recorded as ADRs. This is the
only candidate that is neither tautological (code-derived) nor ROM-shaped
(vault-derived). The three-way split: **domain model = blueprint · vault =
ballast · code = subject.**

**5. The projection is a function, not an artifact.** `project(commit) → graph`.
A baseline is `project(baseline_sha)`; the current state is `project(HEAD)`.
Materialising a baseline by hand makes it unrecomputable the moment the metric
changes; as a function it is re-derivable over any past commit with any future
metric, and yields a curve rather than a single before-and-after. Either
snapshot renders into an Obsidian-openable folder on demand.

> **Amended by [#310](https://github.com/timbermania/fft-monorepo/issues/310) (2026-08-21). The signature takes two refs —
> `project(code_sha, vault_sha)`.** No single commit holds both halves: `vault/` and
> `vault-sync/` exist only on `main`, the code only on the trunk. The one-argument
> form written here cannot express *which ballast* a reading used, which is precisely
> what dec. 1 requires it to record.
> [`docs/adr/0002`](../../../docs/adr/0002-import-godot-game-is-trunk-main-is-the-vault-line.md)
> and [`docs/agents/refactor-loop.md`](../../../docs/agents/refactor-loop.md) already
> write the two-argument form; `godot-learning/CONTEXT.md` → **Projection** carried
> the one-argument form and is corrected to match.

**6. Nothing is ever written to `vault/`.** The pipeline (`vault-sync/`) is its
only writer.

**7. Code cites its vault note in a comment**, mirroring the ADR citation
convention already at 95% adoption (306 of 321 `src/` files, 1,732 citations,
88 of 93 ADRs).

> **Amended by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20).** **65.1%, not 95%.** `306` is the
> *current* count (re-measured: 306 of **470** `src/` files carry an `ADR-NNNN`
> citation); `321` is the 2026-07-12 denominator ADR-0110 also quotes. At that
> July tree the numerator was **149** of 321. A current numerator on a five-week
> -old denominator. Pass 2's backfill is ~50% larger than this sized it: **164**
> files lack a citation, not 15. A comment travels with the code through any rename, move or
rewrite, so this anchor survives goal #7's jargon purge — which path- and
symbol-based `R:` citations cannot. The existing 504 `R:` path citations seed
the backfill once; afterwards the vault never needs to know where code lives.

> **Amended by [#310](https://github.com/timbermania/fft-monorepo/issues/310) (2026-08-21). This backfill moves out of the prologue
> and into each extraction's first step.** It is the one part of the instrument that
> **cannot** be deferred, because it is the only part that must exist *before* the code
> it names is rewritten — and
> [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md) makes each addon an
> **analog**, authored fresh, so no after-the-fact crosswalk or rename detection can
> reconstruct the mapping (both are already rejected above).
>
> > **Amended by [ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md)
> > (2026-08-22): ADR-0112 does not say this**, and the anchoring conclusion survives on a
> > different reason. Extraction #1's anchors travelled *because* the files were renamed —
> > git carried the comments — so the stated rationale did not operate. The anchor is still
> > worth doing, and the reason is dec. 7's own: a `res://` path citation rots and a comment
> > does not. The extraction that genuinely rewrites is the one this paragraph describes.
>
> The `R:` path seed is rotting without any help from the refactor. Of **320** distinct
> code paths the vault's `R:` lines cite, **81 are dead at trunk** — a further 12 are a
> counting artifact, `.gdshader` files cited with a `.gd` extension. **70 of the 81 are
> the single `smd-player/` → `exmateria-sound/` package rename**, which predates the
> refactor: one rename cost **26%** of the seed, and the plan is ten to fifteen more.
>
> So the backfill is **not** a 470-file prologue pass. Its scope is the **124
> live-cited `src/` files** (plus 92 in `tests/` and 11 in `tools/`), anchored per
> extraction while those files are already open. Adoption today is **0 of 470** — the
> 3 `# Note:` hits in `src/` are ordinary prose and the 15 `[[` hits are nested array
> literals.

## Considered alternatives

- **Vault clusters as target module boundaries.** Rejected: bakes the ROM's
  storage organisation into an engine intended to be game-agnostic.
- **Emergent clusters from note↔code co-citation.** Rejected as ballast: its
  edges run *through code files*, so the partition moves when the code moves —
  the same tautology, better disguised.
- **Git rename detection as the anchor.** Rejected: the refactor writes analogs,
  not moves; git sees delete-plus-add whenever similarity drops, failing exactly
  on the rewrites that matter most.
  > **Amended by [ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md):
  > the premise is wrong and the rejection still holds.** ADR-0110 dec. 1 lifts rather than
  > rewrites, so git rename detection *did* work at extraction #1 (94–100%). It is still
  > rejected, on the second clause alone: it fails on the rewrites, and an anchor that works
  > only while nothing is rewritten is not an anchor.
- **A hand-maintained crosswalk per extraction.** Rejected: requires sustained
  discipline over months, and a rotted crosswalk fails *silently* — the metric
  keeps producing numbers, merely wrong ones.

## Consequences

- **Coverage is severely uneven and that is not noise.** Citations per `src/`
  dir: `scenarios` 148, `effects` 89, `ui3` 32 — but `gpu` 2 (6,540 lines),
  `debug` 2 (8,569), `scenes` 4, `strategy` 0. Roughly 30k of ~100k lines sit in
  directories with ≤4 citations. *(Those per-directory line counts are the
  same 2026-07-12 census — today `gpu` is 6,907 and `debug` 9,265. The
  proportions hold; the absolute figures do not. [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md).)* The split is *decoded from the ROM* versus
  *engineered by us*.
- **The blind spot grows as the project succeeds.** Every line written for the
  superset (#6) or for authoring (#10) has no note to attach to. The ballast is
  a good instrument for the porting half of this work and a progressively worse
  one for the building half.
- Because `R:` lines are model-written prose, small movements are noise. Read
  per-cluster, directionally, over months.
