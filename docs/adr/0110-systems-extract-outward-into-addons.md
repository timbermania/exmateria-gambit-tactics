# Systems extract outward into addons; the host shrinks to the FFT content pack

`godot-learning` is refactored **outward, one system at a time, into
self-contained Godot addons** — never in place, and never by porting into a
fresh project. The package keeps running throughout; as systems leave, what
remains converges on the FFT **content pack** plus its authoring tools.

Status: accepted (2026-08-19); the Context census re-dated and the
progress-bar Consequence re-scoped by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20).

## Context

The target is a game-agnostic tactics-RPG engine with FFT as one content set:
portable systems (goal #5), assets rethought as a superset rather than a ROM
transcription (#6), no PSX/FFT jargon in engine vocabulary (#7), and eventual
support for authoring content (#10).

The package is 321 `.gd` files and ~100k lines under `src/`, across 17
top-level directories, with 24 autoloads and 624 `.tscn`.

> **Amended by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20).** The `.gd` figure is a
> **2026-07-12 census** (`f8f3041b3`: 321 files, 100,701 lines), published here
> five weeks later. Measured at this ADR's own commit: **470 files, 141,831
> lines** — +46%, of which `src/effects/` is +26,258. The `624 .tscn` in the
> **same sentence** *is* current — 269 on 2026-07-12, first reaching 624 on
> 2026-08-14 — so the sentence splices two censuses. `24 autoloads` matches
> neither date (23 on 2026-07-12, **26** at this commit). Only `17 top-level
> directories` is invariant. A measured figure now states the commit or date it
> was taken on.

The precedent already exists in this repo. `exmateria-sound/addons/exmateria_sound/`
references **zero** of `godot-learning`'s 24 autoloads — and it is the *hardest*
subsystem, carrying a native GDExtension. The addon model is not speculative
here; it has been done once, for the worst case.

## Decision

**1. Extraction, not transformation or reconstruction.** Systems are lifted out
of the host into addons. The host remains bootable and playable at every commit.

**2. One system extraction is one unit of work** — one branch, many small
commits, closed by a code review before merge. This is the unit that can be
handed to a single agent in its own worktree without colliding with another,
which is the parallelism the effort is aiming for. Per-commit review is too fine
to catch architectural drift; per-session is arbitrary, since a system may take
several.

**3. Scope is `godot-learning` only.** `exmateria-sound` is already an addon and
already passes the portability test — it is the model being copied, not a thing
needing repair. `fft-plugin` and `fft-sound-driver` are C++ consumers on their
own release cycle.

**4. The boundary test is portability**: could this ship to another tactics RPG
with its interface intact? `exmateria_sound` is the calibrated *yes*.

## Considered alternatives

- **In-place transformation.** Rejected: never yields the greenfield slate goal
  #1 asks for — every decision is negotiated against what is already there — and
  the ambient autoloads are hardest to dislodge from inside.
- **A new project that code is ported into.** Rejected: two live codebases, and
  nothing playable until enough has crossed. The "only port what is used"
  framing points here, but [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)
  obtains the same result without the outage.

## Consequences

- The end state of goals #5 and #6 is reached incrementally rather than by a
  big bang, and is observable the whole way: the host's size is the progress bar.

  > **Amended by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20).** The host's size is an
  > **inventory count**, tracked under [ADR-0114](0114-refactor-progress-is-two-per-cluster-numbers.md)
  > dec. 7; `project()` supplies the progress bar. As written this promoted a
  > count to the metric, and one number cannot tell an extraction from a
  > deletion — which is why extracted lines are now reported beside host lines.
- Extraction order is set by the domain model, not by convenience. The five
  vault clusters that map cleanly to systems — `Ability Execution`, `Unit`,
  `Unit Deployment`, `Formation Screen`, `SFX` — go first, as cheap validation
  of the model rather than its first hard test.

  > **Withdrawn 2026-08-21 by [ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md).**
  > The five are five of the **fifteen topic clusters** in `vault/AI Research
  > Index.md` — the vault's table of contents — and
  > [ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md), added in
  > **this same commit**, rejects vault clusters as boundaries. There was also no
  > roster to *"map cleanly to"* yet:
  > [ADR-0117](0117-the-blueprints-ten-systems.md) is a day later. Only `SFX` is a
  > system; the other four are three parts of `Battle` and one span of `UI` over
  > `Character Catalogue`, so under dec. 2 this schedules **41,406 lines, 29% of
  > the package**. Extraction order is now chosen by **measured isolation**, and
  > **#1 is `Render`**. The list survives as `BLUEPRINT.md`'s *calibration set*,
  > which is sound and untouched.
