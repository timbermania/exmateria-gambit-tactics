# Extraction #7 is the `Effects` runtime, and the studio that is seventy percent of the bucket is a root set that stays

The selection instrument reports `Effects` at **191 files / 58,124 lines, arm 7 = 3 names
/ 21 lines** — the cheapest seam of any large unextracted system, and the reading that
put it forward as extraction #7. Both halves of that number are somebody else's.

**Eighteen of the twenty-one arm-7 lines are a debug panel's.** They sit in
`src/debug/EffectViewerPanel.gd`, `src/debug/TrapViewerPanel.gd` and
`src/debug/FireCastReproPanel.gd`, naming `TuneField` (15) and `BaseDebugPanel` (3) —
the host's own debug window reaching its own base class and its own field widget, booked
to `Effects` because `classify()` books a file to the system it *consumes*
([ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
dec. 3). This is
[ADR-0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md)'s
artefact firing a second time, on a system it was not derived from, with no amendment
needed.

**And 69.9% of the bucket is an authoring tool.** `src/effects/studio/` is **116 files /
40,623 lines** of the 58,124 —
[ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md) dec. 3 declares
the Effect Studio the *second root set*, `docs/agents/refactor-loop.md` → *Extraction
order* schedules it **last**, and `EffectStudioPage.gd` alone (7,946 lines) is touched by
**186 of the 495 commits** `src/effects/` has taken in 60 days. A membership that swallows
it is not an extraction of `Effects`; it is a rewrite of the thing still being designed.

Take those two away and what is left is the system the blueprint describes: **69 files /
16,505 lines**, whose entire outbound debt into an unextracted system is **three lines** —
`caster: Unit, target: Unit` in `EffectManager`'s three `spawn_*` signatures, at **0.018%**
of its size. `Sprite Rig` was selected for #4 on six lines at 0.112%, and `Battlefield`
for #3 on ten at 0.121%. This is the best reading the method has taken.

> ⚠️ **Corrected the same day by
> [ADR-0287](0287-the-backwards-edge-is-one-misfiled-file-and-the-arm-that-fails-is-the-one-no-selection-ever-ran.md),
> pass 2.** Two decisions moved and the rest stand. **Dec. 2's membership is 67 files /
> 14,441 lines, not 69** — the directory rule as written produces 70, and three files leave
> for three different reasons (`CompositorAutopilot.gd` is `assembler`, ADR-0135 dec. 9a;
> `EffectScoreModel.gd` is a studio file; `PSXDitherCurves.gd` is dead). **Dec. 6's
> backwards edge is 25 lines, not 5**, and the remedy is a file move rather than an
> inversion — arm 7 sees 5 `class_name` lines and cannot see the 20 `preload()` lines beside
> them. Pass 2 also found the thing no selection pass has ever run: **arm 4b FAILS**, it
> does not report debt. Read ADR-0287 before acting on dec. 2 or dec. 6.

Status: accepted (2026-09-11). This is
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md)'s **pass 1** for extraction
#7, run in parallel with extraction #6 (`Character Catalogue`,
[#1025](https://github.com/timbermania/fft-monorepo/issues/1025)). Reads
[ADR-0110](0110-systems-extract-outward-into-addons.md) for the unit of work,
[ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) for the three
selection readings, [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)
dec. 3 for the two root sets,
[ADR-0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md)
for what a member is,
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 6 for the autoload precedent, and
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
for why every number here is re-taken rather than carried. **Supersedes nothing.**
Re-prices one sentence of `docs/context/37-the-blueprint.md` (dec. 4) and one of
`docs/agents/refactor-loop.md` (dec. 5). Tickets: files the extraction #7 selection, and
hands pass 2 the four items in *Soft spots*.

## Context

### Everything here is re-measured on `feat/extraction-7-effects` @ `2b55e3f81`, 0 commits behind `origin/main`

The handoff that opened this session carried a selection table it correctly marked as
unreproduced, and named
[#1059](https://github.com/timbermania/fft-monorepo/issues/1059) as a blocker that had to
land before #7's numbers could be trusted. **#1059's phases 1 and 2 are already merged**
(PR [#1088](https://github.com/timbermania/fft-monorepo/pull/1088),
PR [#1095](https://github.com/timbermania/fft-monorepo/pull/1095) — `tier=` is declared in
all nine `plugin.cfg` files and `_walk_roots.declared_tier` raises where it is absent);
the ticket is open only for its phase 3, which is a **move** (#1060) and not a guard
change. The selection numbers below are therefore taken on the post-#1059 tree, and they
reproduce the handoff's table row for row — arm 7 is keyed on the reach's *subject*, so
the tier fix could not have moved it either way.

### The instrument, and the two things it cannot represent

`tools/selection_sweep.py` over `tools/arm7_membership.py`, calibrated three ways
(ADR-0243 dec. 11). Everything in the corpus-wide table is its unmodified output.

Two blind spots surfaced while decomposing the membership, and both are the *same* defect
in `all_shapes`' `inside_prefixes` argument, which is a **prefix** test:

1. **`src/debug/` swallowed every Debug-autoload reach.** As classified, `Effects` reads
   **arm 2 = 9**. Drop the six panels — which changes nothing about the code — and it
   reads **63**, because `src/debug/` stops being an `inside` prefix and 54 `DebugConfig.`
   lines appear. The 9 was never a fact about `Effects`; it was a fact about the panels
   being in the membership.
2. **`src/effects/` cannot be spelled without `src/effects/studio/`.** No prefix
   expresses *"this directory but not that subdirectory"*, so every runtime→studio and
   studio→runtime edge is invisible to `all_shapes` at this membership. `arm7()` sees
   them, because it tests set membership rather than a prefix — which is why dec. 6's
   backwards edge shows up in one instrument and not the other.

Neither is fixed here. A pass 1 that repairs its own instrument mid-reading cannot say
whether the reading moved (ADR-0148); both are handed to pass 2 as S1.

### The bucket, decomposed

| directory | files | lines | share |
|---|---:|---:|---:|
| `src/effects/studio/` | 116 | 40,623 | 69.9% |
| `src/effects/` | 45 | 12,575 | 21.6% |
| `src/effects/callbacks/` | 12 | 3,467 | 6.0% |
| `src/debug/` (6 panels) | 6 | 996 | 1.7% |
| `assets/shaders/` (`effect_*`, `trap_*`) | 12 | 463 | 0.8% |
| **total, as classified** | **191** | **58,124** | |

### Four candidate memberships, same tree, one instrument

| membership | files | lines | arm 7 | ratio |
|---|---:|---:|---|---:|
| **A.** as classified | 191 | 58,124 | 3 names / 21 lines | 0.036% |
| **B.** ADR-0257 rule, panels out | 185 | 57,128 | 1 name / 3 lines | 0.005% |
| **C.** runtime only, studio outside | **69** | **16,505** | 3 names / 8 lines | 0.048% |
| **D.** studio only | 116 | 40,623 | 2 names / 8 lines | 0.020% |

**B reads best and B is the trap.** Its 0.005% is three lines over a denominator that is
70% authoring tool: the ratio improves because the system got bigger, not because the
seam got cleaner — ADR-0131's standing warning, arriving as a selection argument rather
than as drift. C is the honest reading and it is the one dec. 2 selects.

### C's eight lines, named

```
Unit                     3   src/units/Unit.gd        [Battle]   src/effects/EffectManager.gd:48,132,258
EmitterFieldRelevance    3   src/effects/studio/…     [Effects]  src/effects/EffectScoreModel.gd
EmitterChannel           2   src/effects/studio/…     [Effects]  src/effects/EffectScoreModel.gd
```

Three into an unextracted system, five **backwards into the editor** (dec. 6). All eight
live in two files.

The three `Unit` lines are all three of `EffectManager`'s entry points:

```gdscript
func spawn_spell_effect(caster: Unit, target: Unit, ability_id: int, effect_id: int)
func spawn_cinematic_effect(caster: Unit, target: Unit, ability_id: int, …
func spawn_item_effect(target: Unit, effect_dir_num: int)
```

`docs/context/37-the-blueprint.md` already names both the invariant they break and the
repair, under **Role binding**: *"The map from an effect script's roles — caster, target,
cell — to anchors that answer position and orientation and nothing else. It is what keeps
`Effects` ignorant of what a combatant is."* Its `Effects` entry says the system *"depends
on nothing"*; these three lines are the whole of the falsification.

### What C reaches that arm 7 does not count

| shape | target | lines | files |
|---|---|---:|---:|
| autoload | `DebugConfig` | 61 | 19 of 69 |
| class_name | `Unit` | 3 | 1 |
| const path | `assets/sprites/textures/TRAP1{,.palette}.tga` | 2 | 1 |

`Debug` is a non-counting sink for the outbound reading (ADR-0141), and
[ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 2 /
[ADR-0187](0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md)
are the precedent that answers it. It is still 61 lines and 19 files, which is larger than
everything else this system owes put together, so dec. 7 names it rather than letting the
sink absorb it silently.

### The inbound surface, and where four fifths of it lives

Measured over **2,545 files** — the whole tree, not `classify()`'s file set, because
`classify()` does not see `tests/` and
[ADR-0157](0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md)
→ *Soft spots* S3 is the standing lesson that four fifths of a reference count lives there.

| shape | total | production | `tests/` + `tools/` |
|---|---:|---:|---:|
| `class_name` | 656 over 27 names | 42 over 9 | 614 |
| `res://` path | 508 over 40 targets | 40 over 15 | 468 |
| autoload | 43 over 4 names | 8 over 3 | 35 |
| **total** | **1,207** | **90** | **1,117 (92.5%)** |

The production 90 decomposes by consumer as `assembler` 20, `Battle` 13, `Cutscene` 10,
the studio 40, the six panels 6. **Strip the studio and the panels — both host-side by
dec. 3 and dec. 4 — and the seam between `Effects` and the other ten systems is 44 lines**,
concentrated in `PSXCameraConvert` (16), `PsxUnits` (5), `CameraCalib` (4) and three
autoloads (8).

The 1,117 is the cost that is not in any matrix, and it is **4× `Battlefield`'s 284**
(ADR-0157's correction, the largest previously recorded). Pass 5 prices it; pass 1 records
it so that nobody discovers it in rebase.

### The churn, split

| window | commits touching `src/effects/` | of which studio | of which runtime |
|---|---:|---:|---:|
| 60 days | 495 | 370 | 209 |
| 14 days | — | 8 | 19 |

(The two columns overlap; a commit can touch both.) `EffectStudioPage.gd` — one file,
7,946 lines, 430 KB — carries 186 of the 60-day commits. **The churn is the studio's, and
in the last fortnight it has cooled to 8 while the runtime took 19 ordinary commits.**

The growth measurement says it harder, and it is a like-for-like comparison because both
ends are `classify_blueprint.py`'s own accounting.
[ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md) dec. 5
published the split on **2026-08-20**:

| half | 2026-08-20 (ADR-0134 dec. 5) | 2026-09-11 (this pass) | change |
|---|---:|---:|---:|
| `src/effects/studio/` | 21,986 | 40,623 | **+18,637 / +84.8%** |
| everything else in the bucket | 16,176 | 17,501 | +1,325 / +8.2% |
| `Effects` total | 38,162 | 58,124 | +19,962 / +52.3% |

**In three weeks the studio nearly doubled and the runtime moved 8%.** The system the
blueprint describes — *"the effect timeline player … its particle simulation, and the
channel vocabulary every consumer implements"* — is not the thing that is churning. That
separability is the finding that makes dec. 2's membership buildable at all, and it is
also the reason dec. 4 refuses to move the studio: a directory growing at 6,000 lines a
month is the definition of *"code whose shape is still being designed."*

### Parallel safety against extraction #6, re-derived

- `CharacterCatalog` / `ExMateriaCatalogue` appear on **zero** lines of the 69-file
  membership (and zero across all 191).
- PR [#1181](https://github.com/timbermania/fft-monorepo/pull/1181) touches 25 files:
  `addons/exmateria_{almanac,catalogue,schema}/`, four `docs/adr/` files, one test, and
  **`tools/classify_blueprint.py`**. The last is not a collision but it *is* a shared
  dependency — every number in this ADR is downstream of that classifier, so dec. 1's
  re-take obligation binds after #1181 merges, not only after #6 does.
- The four shared registers (`docs/GOALS.tsv`, `docs/RESIDUE.tsv`, `docs/BASELINE.tsv`,
  `docs/adr/CLASSIFICATION.tsv`) are append-only from both tracks; ADR-0131 already rules
  every published number re-taken at pass 9.

### `Debug` was the cheaper seam and is still #8

`Debug` reads **1 name / 2 lines** — cheaper than anything here — and
[ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md) rules it a pure sink that
may extract at any point in the order. It is declined for #7 on collision, re-derived:
**four `src/debug/` files name the catalogue** (`ProgressionDebugPanel.gd`,
`RosterUniverseDebugPanel.gd`, `StoryTimelineDebugPanel.gd`,
`BattleBindingDebugPanel.gd`), two live worktrees are editing `src/debug/` for extraction
#6 (`feat/debug-panel-catalogue`, `feat/panel-catalogue-at-the-seam`), and #1025's open
item 4 — the catalogue's four booked panels — is unresolved. It is the natural **#8**.

## Decision

**1. Extraction #7 is `Effects`, and its selection numbers are re-taken on this tree, not
carried.** Every figure in this ADR was measured at `2b55e3f81` after #1059's phases 1–2
had landed. The handoff's table reproduces exactly; it is cited nowhere as authority.

**2. The membership is the RUNTIME: 69 files / 16,505 lines.** Three roots, and they are a
directory rule plus an extension rule, which is what makes the pass-6 manifest
machine-checkable:

- `src/effects/*.gd` — 45 files / 12,575 lines (the directory, excluding `studio/`)
- `src/effects/callbacks/*.gd` — 12 files / 3,467 lines
- `assets/shaders/{effect_*,trap_charge_line}.{gdshader,gdshaderinc}` — 12 files / 463 lines

**3. The six `src/debug/` panels are not members.** `EffectViewerPanel.gd`,
`TrapViewerPanel.gd`, `FireCastReproPanel.gd`, `EffectTimelineView.gd`,
`EffectTimelineModel.gd` and `ColorTimelineModel.gd` are the host's debug window
(ADR-0035), and their 18 arm-7 lines are the window's debt, not `Effects`'. **This is
ADR-0257's rule applied to a system it was not derived from, and it needed no amendment to
fit** — which is the control arm that ADR-0257 could not run on itself. It stands as a
general rule, not a `Character Catalogue` special case.

**4. `src/effects/studio/` is not in this extraction, and ADR-0134 dec. 4 is upheld
rather than narrowed.** That decision is emphatic — *"they are **one system**, and an
"Effect Authoring" system is ruled out by the same clause that ruled out headless
`Battle`"* — and this ADR does not touch it. `src/effects/studio/` stays classified
`Effects`. What dec. 3 establishes is that **classification and membership are different
questions**: a file can belong to a system and still not move in that system's extraction,
which is exactly what the six panels do and exactly what ADR-0134 dec. 4 never addressed,
because it was answering *which of the eleven* rather than *what moves*.

Two guards on that reading, because the failure mode here is severe:

- **The studio is NOT re-parked in `assembler`.** ADR-0134 dec. 2 rules a directory in the
  assembler list a defect — *"assembler is the one category that never becomes a system, so
  anything parked there is permanently exempt from extraction"* — and its dec. 3 removed
  the `("src/effects/studio/", "assembler")` entry for that reason. Nothing here restores
  it. The studio stays a `Effects`-classified directory in the host, extractable later, on
  its own schedule.
- **The partial extraction is precedented, not invented.** `Audio` is the shape: *"OUT 3,
  21 inbound over 4 names, because 12 host-side files stayed behind."* This is that at six
  times the scale, and dec. 10 states the metric consequence up front rather than
  explaining it at pass 9.

The blueprint's sentence *"the 21,986 lines of `src/effects/studio/` are `Effects`"* is
therefore upheld in substance and stale in fact: it reads **40,623** today. The studio's
assembler remains `EffectViewerScene.gd` (1,553 lines, `src/scenes/`, ADR-0134 dec. 3,
which published 1,321); `EffectStudioPage.gd` (7,946 lines) is inside the studio directory
and is the most-churned file in the package.

**5. `docs/agents/refactor-loop.md` → *Extraction order* is upheld and made precise.**
*"Effect Studio last"* and *"when `effects` extracts, the studio's reaching into its
internals breaks — which is the correct outcome … but it should be scheduled rather than
discovered"* are the same instruction read two ways. This ADR schedules it: the runtime
extracts at #7, the studio stays in the host, and the studio's **39 code lines** into the
runtime (8 `class_name`, 31 `preload`) plus **32 `res://` paths** become an ordinary
inbound edge across an addon boundary, priced at pass 3 and paid at pass 6.

**6. `src/effects/EffectScoreModel.gd`'s five lines into `src/effects/studio/` are a
backwards edge, and inverting them is pass 3's first item.** `EmitterFieldRelevance` (3)
and `EmitterChannel` (2) are editor types named by the runtime. This is the one finding
that **blocks** the move rather than pricing it: an addon cannot name a class that stays
in the host. It is invisible to `all_shapes` for the reason in *Context*, and it was found
only because `arm7()` tests set membership.

**7. `DebugConfig` on 61 lines across 19 of 69 files is named, not absorbed.** `Debug` is a
non-counting sink for the selection reading and this ADR does not count it; it is
nonetheless the single largest thing the runtime reaches, and ADR-0175 dec. 2 / ADR-0187's
port is the shape that answers it. Pass 2 measures whether the 61 are a port's two
signatures or 61 independent decisions.

**8. The inbound seam to design is 44 lines over ~12 addresses**, once the studio and the
panels are set aside — `PSXCameraConvert` 16, `PsxUnits` 5, `CameraCalib` 4, `TrapEffect`
and three trap classes 5, `EffectManager` 1, `ScreenData` 1, plus 8 autoload reaches to
`MapTintOverlay` / `ScreenEffectOverlay` / `UnitTintOverlay`. The four autoloads ship by
ADR-0262 dec. 6 — script with the addon, `[autoload]` line stays the host's — which is now
precedent five.

**9. ADR numbers `0286`–`0295` in the `godot-learning/` corpus are reserved for extraction
#7** and are announced in the selection ticket so the ~50 other live branches route around
them. Both scans were run before this file was written and agree: high-water `0285`, next
free `0286` ([#1031](https://github.com/timbermania/fft-monorepo/issues/1031) is the open,
unowned ticket for the fact that nothing allocates these across branches).

**10. Pass 9 will not read *"`Effects` is gone"*, and that is stated now rather than
explained then.** The studio's 116 files / 40,623 lines stay booked `Effects` in the host,
so `classify_blueprint.py` will report the system at roughly 70% of its present size after
a successful extraction. This is the `Audio` shape — *"OUT 3, 21 inbound over 4 names,
because 12 host-side files stayed behind"* — at six times the scale. The pass-9 claim is
about the **runtime's** two numbers, and the goal-scoring must say so on its face.

**11. The pass-6 move is gated and the gate is written here, not discovered in rebase.**
It does not start without either (a) the Effect Studio work quiescing — the 14-day runtime
/ studio split of 19 / 8 is the instrument for that — or (b) an agreed flag-day window
against [#262](https://github.com/timbermania/fft-monorepo/issues/262). Pass 5's plan
restates this or is incomplete.

## Considered alternatives

**Take the bucket as classified (A: 191 files).** It is what the instrument reports and
what the handoff proposed. Rejected: 69.9% of it is an authoring tool that ADR-0112 dec. 3
declares a separate root set and the extraction order schedules last, and 1.7% is a debug
window ADR-0257 already ruled out. Moving it would rewrite `EffectStudioPage.gd`'s
directory under 186 commits of live work.

**Take B (185 files — panels out, studio in).** It publishes the best arm-7 ratio in the
history of the method, **0.005%**. Rejected precisely because of that: three absolute lines
over a 57,128-line denominator is a *smaller fraction* than three over 16,505, and nothing
about the seam changed between them. Selecting on it would be ADR-0131's drift used as an
argument.

**Take C but keep the six panels (75 files).** Rejected: it re-imports the 18 arm-7 lines
that are the host debug window's, and it would make this pass the first to *decline*
ADR-0257's rule six weeks after adopting it, on no new evidence.

**Select `Debug` as #7 instead.** Cheapest seam in the corpus (1 name / 2 lines) and
ADR-0140 permits it at any point. Rejected on measured collision with extraction #6 — four
`src/debug/` files name the catalogue, two live worktrees are editing the directory, and
#1025's item 4 is open. It is #8.

**Defer `Effects` until the studio quiesces.** Rejected: it treats 495 commits as one
number. 370 of them are the studio's and 209 the runtime's, the last fortnight reads 8 and
19, and dec. 2's membership is exactly the half that is not churning. Deferring the runtime
on the studio's churn is the mistake the extraction order warns about, inverted.

**Split the studio out of `Effects` in the blueprint as well.** Tempting — it would make
the pass-9 number read cleanly (dec. 10) — and rejected twice over. It is **already
decided against**: ADR-0134 dec. 4 rules an *"Effect Authoring"* system out by ADR-0115
dec. 3's asymmetry test (*nobody uses the effect editor without `Effects`; the game uses
`Effects` with no editor at all*), and overturning a ratified classification is not
something a selection pass gets to do in passing. It is also dangerous in the one
direction ADR-0134 dec. 2 names: the nearest available home for a rejected directory is
`assembler`, and anything parked there is *permanently* exempt from extraction. Recorded
as S4, because the question is now asked by the measurement (84.8% growth in three weeks)
rather than by anyone's preference.

## Consequences

- Extraction #7 is scoped at **69 files / 16,505 lines**, the second-smallest membership
  since `Audio`, against a classified bucket of 58,124.
- **Two published numbers move without any code changing**: the blueprint's `21,986` for
  `src/effects/studio/` is now `40,623`, and `Effects`' arm 2 is 9 or 63 depending only on
  whether the panels are in the membership. ADR-0131 dec. 5's obligation now has a second
  worked example that is not about line counts.
- ADR-0257's rule has a control arm. It was derived from `Character Catalogue`, where it
  re-ordered the queue; it predicts `Effects`' arm-7 composition on a different system,
  unamended, and 18 of 21 lines fall exactly where it says they will.
- Pass 2 inherits a **five-line blocker** (dec. 6) that must invert before any `git mv`,
  and a **1,117-reference** test-and-tool surface (dec. 8's table) that no symbol matrix
  would have shown it.
- `tools/arm7_membership.py`'s `all_shapes(inside_prefixes=…)` is known to be unable to
  express a membership that excludes a subdirectory of an included one. Every future
  selection over a system with a nested authoring tool inherits the blind spot until it is
  fixed.
- The selection ticket announces the `0286`–`0295` reservation; sessions on the other ~50
  live branches take `0296` and up.

## Soft spots

**S1 — the instrument was not repaired and the reading was taken anyway.** Both blind
spots in *Context* are real and both were worked around by hand (set-membership `arm7()`
for the studio boundary, a second run with the panels dropped for the `DebugConfig`
count). A hand-applied predicate is what ADR-0241 S1 named as its own weakest point and
what ADR-0243 dec. 11 built `arm7_membership.py` to end. Pass 2 should fix
`inside_prefixes` — most likely as an explicit exclusion list rather than a prefix — and
**re-take the C row**, because the numbers in this ADR would then be reproducible by a
single command rather than by three.

**S2 — the 44-line inbound seam counts lines, not calls.** `PSXCameraConvert` at 16 lines
across `Battle`, `Cutscene` and `assembler` may be one conversion used sixteen times or
sixteen independent uses; ADR-0141 dec. 2 has no term separating a name that is *called*
from one that is merely *named*, and ADR-0213 dec. 4 recorded that gap without closing it.
Pass 3 designs against the call graph, not this table.

**S3 — the 61 `DebugConfig` lines are unexamined.** They were counted and bucketed and
nothing was read. If they are 61 independent `if DebugConfig.foo_enabled:` guards rather
than a port's two signatures, ADR-0187's precedent does not transfer and dec. 7's deferral
becomes a real design problem rather than a bookkeeping one.

**S4 — the studio stays booked `Effects` and nobody has decided whether it should be.**
Dec. 4 upholds the classification and dec. 10 states the consequence, but the underlying
question — *is a 40,623-line authoring tool a member of the system it authors, or its own
thing?* — is asked here and answered nowhere. It will resurface at pass 9 as a metric that
does not move, and again whenever the Effect Studio is finally scheduled.

**S5 — the 14-day churn split is one fortnight.** 19 runtime / 8 studio is the evidence
for dec. 11's gate being satisfiable, and it is a single sample of a series that read
209 / 370 over 60 days. One quiet fortnight is not quiescence. Pass 5 should re-take it
rather than cite this one.
