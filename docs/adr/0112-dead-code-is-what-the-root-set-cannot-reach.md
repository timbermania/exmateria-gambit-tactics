# Dead code is what the declared root set cannot reach

Deadness is not proven per-file up front. A **root set** is declared — the
scenes the refactor commits to keeping — and everything unreachable from it is
dead by construction. The vault ballast supplies the check the closure cannot:
what was dropped by accident rather than by choice.

Status: accepted (2026-08-19); the Context denominator re-dated by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
(2026-08-20).

> **Root set ratified and amended by [ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
> (2026-08-21).** Dec. 1's candidacy test counts `.gd` loads as well as `.tscn`
> embeds — as written it does not fail its own example, `Unit.tscn`, which no
> `.tscn` embeds. Dec. 3's **`CombatUI` is struck** (an `[ext_resource]` child
> of `PlayerCamera.tscn`, itself embedded in eight scenes) and so is its
> trailing *"plus the instanced components"*, which contradicts dec. 1. Dec. 4
> extends to `tools/`. The root set is **eleven** named scenes. The Consequences
> figures *124 / 16 / 65* are a **2026-07-12 date splice, not a lost method** —
> they reproduce exactly at `f8f3041b3` and read **371 / 30 / 128** today. The
> Context's **13** does not reproduce under any tested method at its own date
> and should not be re-stated.

> **Dec. 3 ratified by [ADR-0143](0143-the-root-set-is-ratified-and-the-formation-cluster-is-its-one-exception.md)
> (2026-08-21).** The two root sets are **game** (8) and **authoring** (3), both
> declared and both enumerated by ADR-0135 dec. 5. There is no *asset* root set
> and none is owed: assets are reached **through** the scene closure, so the
> missing arm [ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md)
> dec. 8 records is a gap in the closure — prologue pass 4 — not a second
> declaration. Dec. 1's disqualifying relation is **composition**; the whole
> census is [`docs/ROOT_SET.tsv`](../ROOT_SET.tsv), 31 rows, 11 `root` /
> 15 `declined` / 5 `component`.

## Context

Goal #3 asks that only code known to be in use is carried forward. There is no
static oracle for that here. Of 321 `src/` files, **only 13 are referenced by
nothing else** — and all 13 are entry points (`OpeningMenu`, `ProjectileTester`,
`SequenceViewer`, `TrapViewerScene`, `UICompileTest`…), not corpses.

Everything else is referenced by *something*, and that is the trap: 601 test
files and 44 tools do much of the referencing.

> **Amended by [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (2026-08-20).** `321` is a **2026-07-12** count;
> `src/` holds **470** `.gd` files. `601 test files` in this same paragraph is
> current, the same splice ADR-0110's Context carries. The `13` itself is not
> re-stated here — it was produced by a reference method this ADR does not
> record, and re-deriving it is pass 5's work, not a docs correction. `44 tools`
> now reads **73** `.gd` (plus 242 `.py`). A test for a superseded feature
keeps that feature reachable. Under the working definition of used — "for the
game itself, tests, or parsers" — tests become a laundering channel in which
cruft holds cruft up and both appear load-bearing.

The decisive measurement is the scene census. Of **624 `.tscn`: 584 are in
`tests/`, 29 in `assets/`, 9 in `tools/`, 2 in `src/`.** The shippable game is
those 29, main scene `assets/scenes/GPUArena.tscn`. The real root set is about
a dozen scenes — small enough to enumerate by hand.

## Decision

**1. A *candidate root* is a scene that runs on its own** — nothing instances
it. `Unit.tscn`, `PlayerCamera.tscn` and `TileCursor.tscn` fail this: they are
reachable *from* roots, never roots.

**2. The *root set* is the candidates deliberately kept.** Running on its own
makes a scene eligible; being wanted makes it a root. The seven test scenes
sitting in `assets/scenes/` (`AttackSfxTest`, `CombatUITest`, `FEDSTest`,
`SfxBankTest`, `SfxStressTest`, `SMDTest`, `FireCastRepro`) are candidates
declined — declining is what kills them.

**3. There are two root sets.** The ~12 game scenes (`GPUArena`,
`NavigatorMain`, `OpeningScene`, `Formation`, `AllTemplatesFormation`,
`DetailScreen`, `FormationDetailTransition`, `ScenarioPlayer`, `CombatUI`, plus
the instanced components), **and the authoring tools** — `EffectViewer` above
all. Goal #10 makes authoring a product of this effort, not scaffolding; the
Effect Studio is also the highest-churn code in the package.

**4. Test scenes are not roots.** They are evidence *about* roots. This removes
584 of 624 scenes from the propping-up business at a stroke.

**5. Tests inherit liveness from the closure.** A test survives iff the code it
preloads is reachable from a root set — mechanical, and it cannot launder,
since a test whose entire preload set is dead dies with it. Of 601 test files,
**386 preload a `src/` script directly and only 27 load a `.tscn`**, so
extraction breaks *paths*, not semantics. The 90 vault-cited tests are named
oracles and take priority: the vault already says which invariant each defends.
Per extraction, a system's tests migrate to bind that addon's public interface.

**6. Choosing the root set is a scope decision, not a measurement.** Nobody can
compute it. Declaring all 584 test scenes roots leaves nothing dead; declaring
only `GPUArena` a root kills most of the codebase. Same graph, same code.

## Considered alternatives

- **Runtime tracing.** Rejected: coverage equals how thoroughly the game was
  played; rare paths — error handling, a unique boss ability, a status
  interaction — read as dead. Deleting on that evidence is how features vanish
  silently.
- **Test coverage as the oracle.** Rejected: the laundering problem at full
  strength. Only 90 of 601 test files are vouched for by anything external.
- **Vault-cited code only.** Rejected: `gpu` (6,540 lines, 2 citations), `debug`
  (8,569 / 2), `strategy` (1,243 / 0) — this deletes our own engineering because
  nobody wrote a ROM note about it.

## Consequences

- **Omission is invisible to this mechanism.** Anything overlooked is dead *by
  definition*; the conclusion is self-fulfilling. This is precisely what the
  ballast is for: a note whose `R:` was a real code path at baseline and reads
  `R: none` afterwards means something the ROM does was dropped. No code-internal
  analysis can produce that finding. See
  [ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md).
- **Three registers, never merged.** *Residue* is built-but-unclaimed (cruft);
  a *gap* is researched-but-unbuilt (the 251 `R: none` lines); a *known drop* is
  behaviour deliberately not reproduced — a PSX compromise divorced under goal
  #8, or ROM behaviour we choose to leave — recorded with its reason and the ADR
  that authorised it. The known-drops register is not optional bookkeeping: the
  ballast diff re-reports the same intentional drops at every measurement without
  it, and the signal drowns within about three extractions.
- `src/` has 124 `preload("literal")` and 16 `load("literal")` but **65
  non-literal `load()`** calls, so a static closure under-approximates. With a
  dozen roots this is walkable by hand rather than tooled around.
- Failure is recoverable in the safe direction: being wrong leaves a file
  lingering, not a feature missing.
