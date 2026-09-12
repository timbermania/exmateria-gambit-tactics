# `Debug` is a system, and a system logs itself

`Debug` is the **panel host** — the window, the masonry, the field factory, the
override layer and the walk that discovers what loaded systems declare. It is a
system: genre-neutral, a package you would install rather than write, and after
the correction below it reaches **nothing** — a pure sink, so it may extract at
any point in the order.

The 88-edge headline that opened the question was never `Debug`'s interface.
**Thirty of `Debug`'s forty-five files are per-system panels the classifier
misfiled**, and of what remains, `DebugConfig` is three unrelated things wearing
one name — **73% of it a verbosity gate, not a tunable**. There is no
inter-system logging concept to preserve and none is introduced: **a system
declares and prints its own diagnostics**, and its panel reads that flag as a
view. `GameLogger` is deleted rather than promoted.

Status: accepted (2026-08-21). Amends
[ADR-0113](0113-tunables-invert-at-the-addon-boundary.md)'s target;
corrects [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
dec. 2's shared-surface table and `CONTEXT.md`'s system count; extends
[ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md)
and [ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 2. Follows
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) dec. 11's
precedent of booking files in the classifier by decision. Resolves
[#337](https://github.com/timbermania/fft-monorepo/issues/337) on blueprint map
[#305](https://github.com/timbermania/fft-monorepo/issues/305).

## Context

`Debug` was the largest shared surface in the package by a wide margin — 88
edges from the other ten systems against the shared kernel's 45 — and no ADR
said what happens to it. ADR-0139 dec. 4(b) ruled it out of the *kernel* on
principle (`DebugConfig` is an autoload, so a port by ADR-0118 dec. 2), which
answers *"is it kernel?"* and leaves *"then what is it?"* open at the top of the
list.

All figures below: trunk `bc51724ba`, `classify_blueprint.py` at `8c19a4d3f`,
measured 2026-08-21. Census definition, stated once and used throughout —
**edges whose source is one of the eleven blueprint systems and whose target
bucket is the surface, excluding the surface as its own source.** ADR-0139 dec.
2 states the same definition for the same reason: this ranking flips on its
definition, and a ranking without one is not a fact.

## Decision

**1. The classifier cannot execute its own stated rule, and `Debug` is 15 files,
not 45.** `classify_blueprint.py` comments its intent exactly —
*"debug/: the harness itself vs per-system panels, matched on filename"* — and
then defeats it. `DEBUG_HOST` contains the string `"DebugPanel"`, matched as a
**substring**, so it swallows all 33 `*DebugPanel.gd` files before `DEBUG_OWNER`
is consulted. The result: **19 of `DEBUG_OWNER`'s 30 entries can never fire**,
eight of them shadowing a real file (`SpuAudioDebugPanel` → `Audio`,
`ProgressionDebugPanel` → `Character Catalogue`, `TilesDebugPanel` →
`Battlefield`, and five more).

That the entry is a mistake rather than a policy is decidable, not a matter of
taste: **11 of `DEBUG_HOST`'s 14 entries name an exact file** in `src/debug/`.
`DebugPanel`, `DebugWindow` and `DebugRoot` name none. It is a list of
filenames with three stale members, one of which happens to be a prefix of
thirty-three others.

Corrected — `"DebugPanel"`, `"DebugWindow"` and `"DebugRoot"` dropped, and
`DEBUG_OWNER` given entries for the eleven panels no fragment reached, each
assigned to the system its own outbound edges land in:

| | before | after |
|---|---|---|
| `Debug` | 45 files / 6,911 lines / **4.9%** | **15 / 2,884 / 2.0%** |
| `Cutscene` | 35 / 14,193 | 44 / 15,982 |
| `Battlefield` | 28 / 6,888 | 33 / 7,276 |
| `Battle` | 71 / 16,788 | 75 / 17,171 |
| `UI` | 54 / 18,932 | 59 / 19,372 |
| `Character Catalogue` | 10 / 1,402 | 14 / 2,046 |
| `Audio`, `Campaign`, `Render` | — | +1 file each |
| **cross-system edges** | **316** | **367** |
| in a system | 112,787 (79.5%) | 112,787 (79.5%) |
| UNCLASSIFIED | 0 | 0 |

Thirty files and 4,027 lines change owner; the total and the in-a-system figure
do not move, because the panels move *between* systems, not out of them. **Every
`Debug` figure this map has published is superseded by this line**, and the
`+51` on the edge count is a *reveal*, not an increase: a panel's reaches were
invisible while the panel sat in the bucket it reached out of.

The fix lands before the baseline (pass 6, gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299)), which is what
makes it safe. Pass 2 exists to stop an instrument change being baked into the
series; a correction made *before the first reading* is the opposite of that
failure.

**2. `Debug` is a system, and `CONTEXT.md` already said so — including the half
the ticket needed.** The vocabulary entry reads, unamended, since #306:

> **Debug**: The panel host — full-screen panels in their own window, field
> widgets, the override layer, and the walk that discovers what loaded systems
> declare. […] Genre-neutral and still a system: you would install it, not write
> it. _Avoid_: debug panel (that is one, and **per-system panels ship with their
> system**), DebugConfig (**the ambient autoload this replaces**).

Both halves of the ticket's owed-item 1 and half of owed-item 2 were already
written down. This is the **eighth** ticket on this map whose answer was latent
in prior prose. The lesson has now earned a stronger form: *before measuring a
surface, read what the vocabulary already claims about it* — the measurement's
job is then to confirm or refute a stated claim rather than to discover one, and
it is far harder to mis-scope.

`Debug`'s claim to systemhood is the same one `Render` and `UI` hold —
genre-orthogonal but substantial and installable. Genre-orthogonality is not
disqualifying; ADR-0115's test is whether it is a bundle that ships.

**Correction it forces, and it is older than this ticket:** the heading above
that list reads *"The ten systems"* and lists **eleven**.
[ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
already caught the count — *"the count is eleven systems, not ten"* — and fixed
it where it found it. Two headings survived it:
[ADR-0117](0117-the-blueprints-ten-systems.md) says *"eleven"* in its first line
and *"The ten systems"* over its own table, and `CONTEXT.md` repeats the same
disagreement. Same shape as the schema-count bug ADR-0139 dec. 14 found: a count
held constant while the list beneath it changed. Both headings are fixed here.
`0117`'s **filename** is left alone — renaming an ADR file breaks every citation
to it, and five other ADRs plus `BLUEPRINT.md` cite this one.

**3. The 88 was measured from the wrong side; the real surface is 160, the
ranking inverts, and the outbound is zero.** Re-measured after dec. 1, from the
corrected bucket:

| member | edges | from | what it is |
|---|---|---|---|
| `TuneField` | **58** | 9 | field-widget factory — the published interface |
| `DebugConfig` | **57** | 7 | the autoload `Debug` replaces |
| `BaseDebugPanel` | **37** | 9 | panel base class — the published interface |
| `GameLogger` | 4 | 3 | a second, unused logger |
| `DebugOverlay` | 4 | 3 | the mount point (`register_panel`) |
| **total** | **160** | | |

`DebugConfig` falls from 63% of the surface to **36%**, and the *published
interface* (`TuneField` + `BaseDebugPanel` = 95) becomes the majority. The
88-edge table was not mis-counted — it was counted from a bucket that contained
the panels doing most of the reaching.

This is ADR-0139's *"re-measure from the new bucket's side"* lesson recurring
at larger scale, and it now has a general statement: **a bucket hides every edge
that crosses inside it.** A surface's measured reach is a floor whose slack is
exactly the mis-filed membership.

**And `Debug`'s outbound falls 34 → 0.** All 34 outbound edges — into nine
systems — came from `*DebugPanel.gd` files. Once they go home, nothing in
`Debug` names anything in `src/`. `Debug` passes ADR-0139 dec. 4(a)'s sink veto
outright, which is what settles the ticket's serialisation fear: **`Debug`
depends on no system, so extraction order stays free** (ADR-0118 dec. 5 holds,
and did not need defending). It fails dec. 4(b)'s autoload veto and is not
kernel — correctly, since it is a system.

**4. `DebugConfig` is three unrelated things, and only 12% of it is a tunable.**
324 references across 46 members:

| family | members | refs | share |
|---|---|---|---|
| **verbosity gates** — `if DebugConfig.x_debug_enabled: print(…)` | 15 | **235** | **73%** |
| **launch control** — scenario, seed, autostart, skip-phase, quit, time scale | 14 | 50 | 15% |
| **tunables + overlay toggles** | 17 | 39 | 12% |

171 of the gate uses are literally `if <gate>:` immediately followed by a
`print`/log; the remainder gate a small compute-then-print block. This is the
**third** instance on this map of one slot muxing several unrelated things —
after #307's six effect storage slots and ADR-0139 dec. 14's schema list. The
pattern is now reliable enough to use as a prior: *a name reached from many
systems is more often a mux than an interface.*

**This amends ADR-0113's target.** ADR-0113 calls `DebugConfig` a tunables
registry and its inversion *"the single highest-leverage change in the package
for portability… because the answer is applied 69 times."* The direction is
right and the target is 12% of what was measured. The other 88% is two different
problems with two different homes, below.

**5. A system logs itself; there is no inter-system logging.** The 235 verbosity
gates do not become a shared logger. Each becomes a `static var` in the system
that prints through it, exactly as ADR-0068 already requires of a tunable's
production owner, with the system's own debug panel reading it as a view.

> ⚠️ **Amended 2026-08-26 by [ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
> dec. 3, built ([#563](https://github.com/timbermania/fft-monorepo/issues/563)).
> DELETE-FIRST PRECEDES THE `static var` HOME, because this decision presumes the
> print is worth keeping and mostly it is not.** Measured over `Battlefield`'s
> whole share — 31 gates, 36 print lines: **25 guard ASCII banners and per-call
> traces** (`print("\n=== REBUILDING DYNAMIC GEOMETRY MESH ===\n")`,
> `print("DoodadLibrary: Loading '%s' from cache")`), **5 are genuine warnings**
> about malformed data with a fallback taken, and **1 is worth keeping**. Nothing
> in `tests/` or `tools/` asserts any of the ten distinct message prefixes.
>
> The amended rule: **ask first whether the output is worth keeping.** The
> `static var` home is right for a gate that survives that question. What does not
> survive is deleted, and a genuine warning becomes an un-gated `push_warning()` —
> an engine built-in with no autoload, no flag and no host, already this codebase's
> dominant idiom at **511 uses in `src/`**, wearing the same `[ClassName] message`
> convention the gated line already had.
>
> **Two consequences for this decision's own numbers.** Deletion has no residue, so
> it does not reproduce #500's finding that *"swapping one host autoload name for
> another is a re-label"* — `Tune` stayed at 59 across the whole sweep. And this
> decision's SPLIT requirement for a shared gate is contingent, not absolute:
> `map_debug_enabled` had to split because it was shared 25 `Battlefield` / 9
> `Battle` / 1 `Debug`, and deleting `Battlefield`'s 25 left nothing to split.
> The Considered Alternatives below list five rejected options and **deletion is
> not among them**; that omission is what this amendment repairs.

This is decidable rather than aspirational because the flags are almost already
per-system: **12 of the 15 gates are used by one system only** —
`particle_debug_enabled` 26 refs all `Effects`, `land_skirt_debug_enabled` 10
all `Battlefield`, `chapel_trace_enabled` 8 all `Cutscene`. The three shared
gates are the defect, not a shared concept: `iteration_debug_enabled` alone is
**107 refs across six systems** (Battle 53, Effects 24, Sprite Rig 10,
Battlefield 6, UI 6, Cutscene 1) — one name doing generic verbose-logging duty
for six unrelated subsystems. It splits into six flags and nothing is lost,
because nothing ever read it as a single concept.

**`GameLogger` is deleted, not promoted.** It is a 113-line logger with a
**closed `Category` enum of four** (`ANIMATION`, `EFFECT`, `CAMERA`, `MAP`),
reached by 4 edges from 3 systems, and it already re-derives its levels from two
`DebugConfig` gates. Promoting it would hand every addon a host dependency and a
list it cannot extend — which is precisely the alternative ADR-0113 rejected as
*"portable to any other game quietly means port my debug harness too."* A
shared logger is that rejection with a nicer API.

**6. Launch control belongs to the assembler.** The 50 references that select a
scenario, set a combat seed, autostart, skip the strategy phase, scale time or
quit are not any system's state and not `Debug`'s. They are the root scene's
**startup arguments** — the assembler's own inputs by ADR-0134's definition of a
composition that wires once and leaves. They move to the assembler, and no
system reads them.

This is the family neither ADR-0113 nor this map had a home for, and it is
sizeable enough (14 members) that leaving it inside a *debug* autoload would
have quietly kept a launch mechanism inside an extractable package.

**7. `TuneField.add` is `Tune.bind` plus a widget, and splitting it is what
inverts the arrow.** `TuneField.add()` calls `Tune.bind()` directly
(`TuneField.gd:78`, and again at 105 and 190). So a system calling
`TuneField.add(parent, "Speed", "unit.speed", 1.0)` performs **two unrelated
acts in one call**: it publishes the *tunable declarations* schema through
`platform`'s port, and it mints a Godot `Control` from `Debug`.

**121 of the 139 calls (87%) go through `add`/`add_dropdown`**; only 15 use the
lower-level `build_control`. Split the factory and those 58 edges become
`Tune.bind` edges on a port ADR-0139 dec. 12 already blessed, while the widget
half stays in `Debug` and is called by the host during its discovery walk. That
*is* ADR-0113's inversion for the tunable half — and it is a split of one
function, not a rewrite.

ADR-0139 dec. 12 already observed that *"`TuneField` builds Godot `Control`s,
which is `Debug`'s presentation."* What it did not observe is that the same call
also performs the registration, which is why the schema it declared memberless
nonetheless shows 58 edges into `Debug`.

**8. `BaseDebugPanel` does not invert, and the honest answer is composition.**
The tempting generalisation — *the addon declares, the host renders* — is true
of fields and **false of views**. Measured across the 39 files that
`extends BaseDebugPanel`: **zero are pure declarations.** They total 5,934
lines, 176 `TuneField` calls against **210 raw widget `.new()`** calls, and the
large ones are bespoke instruments (`ScenarioVMDebugPanel` 676 lines,
`UnitAnimationViewerPanel` 431, `ProgressionDebugPanel` 422). No declarative
schema renders those, and pretending otherwise would have been the expensive
mistake in this ticket.

So a system's panel is **a `Control` the system ships**, satisfying `Debug`'s
registration signature rather than inheriting its base class. The mounting half
of this is already built and already inverted: `DebugOverlay.register_panel(
panel, category)` has 20+ call sites in root scenes, and **the harness names no
panel anywhere**. Only `extends BaseDebugPanel` — 37 edges — points the wrong
way, and it is the same dependency ADR-0113 rejected in the abstract.

`check_debug_panel_tunables.py` (`ENFORCE = True`) already states the contract
this decision formalises: *"A debug panel is a VIEW onto tunable state."*

**9. `platform` is a different question, and it is one port wide.** Owed-item 3,
answered by measurement rather than by analogy:

- **`Tune`** — 41 edges from 10 systems. Already a port (ADR-0139 dec. 12), and
  it *grows* under dec. 7 as `TuneField`'s registration half collapses into it.
  Nothing to decide; `platform` is not a second addon.
- **`PsxNum`** — 8 edges, and **seven of them are `src/scenarios/`**. It is
  `Cutscene`'s event-script operand codec, misfiled. Its own docstring says so:
  *"PSX numeric conventions of the FFT event-script interpreter."*

`PsxNum`'s single outside reacher, `src/effects/PsxUnits.gd`, re-exports two of
its constants (`TURN_12BIT`, `UNITS_PER_TILE`) while its own docstring claims to
be *"the ONE home for PSX continuous-magnitude ↔ game-unit conversions."* **Two
modules each declaring themselves the single home for PSX numeric conventions,
one aliasing the other.** Recorded as fog on #305, not settled here — it is a
content-convention question, not a `Debug` question.

**10. The guards are not `Debug`'s, and there are 21 of them, not ~40.** All 21
`tools/check_*.py` root at `PROJECT_DIR` and walk the tree **by path**. A
guard's reach is a path, not an interface, so none survives a system leaving
unchanged — but that makes them a *packaging* problem for whichever system moves,
not a shared surface. ADR-0139 dec. 7 already set the precedent by moving the
two kernel guards with the kernel: **a guard that checks one system's invariant
travels with that system; a cross-cutting guard stays with the host.** `Debug`
is not the home for "everything that inspects a system from outside" — that
description fits the *loop's own instrument*, which ADR-0133 owns.

## Considered alternatives

- **`Debug` is host machinery that never extracts, so the blueprint has ten
  systems.** Rejected on dec. 2's evidence: the vocabulary already calls it
  installable, and after dec. 1 it is a coherent 2,884-line package with zero
  outbound edges — a better extraction candidate than several accepted systems.
  Its shared-surface size was an artifact of holding thirty files that were not
  its.

- **Promote `GameLogger` into the real logging interface.** Rejected in dec. 5.
  It is the alternative ADR-0113 already rejected, and its closed four-value
  `Category` enum is the reductio: an addon cannot add a category without
  editing the host.

- **Declare `Debug` a required platform service every host must provide.**
  Rejected by ADR-0113 verbatim, and this ADR adds the number: it would make 95
  interface edges permanent rather than retiring them.

- **Leave the classifier alone and record the correction in prose.** Rejected:
  `touch_matrix.py` `exec`s the classifier as ground truth, so the wrong bucket
  keeps generating wrong numbers in every future ticket, and dec. 3's 88 → 160
  correction would be unreproducible from the instrument.

- **Rewrite the 39 panels as declarative schemas so everything inverts
  uniformly.** Rejected on dec. 8's measurement — 210 raw widget calls against
  176 `TuneField` calls, zero pure-declaration panels. The uniform answer is
  available only by spending 5,934 lines to buy back 37 edges.

## Consequences

- **Every `Debug` figure published by this map before 2026-08-21 is superseded.**
  `Debug` 4.9% → 2.0%; cross-system edges 316 → 367. Any future citation must
  name the classifier revision alongside the commit.

- **`DebugConfig` is retired in three directions, not one** — 235 refs to
  per-system `static var`s, 50 to the assembler, 39 through `Tune`. ADR-0113's
  *"applied 69 times"* becomes three separate migrations, and only the smallest
  is the one ADR-0113 described.

- **The work is a per-system pass, not a programme.** Each system retires its own
  gates and un-inherits its own panels during its own extraction. Nothing here is
  gated on #299 beyond the baseline itself.

- **Two closed lists survive this ADR and are not fixed by it.**
  `DebugOverlay.Category` is a closed enum of **22** and `GameLogger.Category` of
  **4**. Deleting `GameLogger` removes one; the panel-category enum remains, so
  an extracted addon still cannot add a debug page without editing the host.
  Same defect class as #315's hardcoded effect lanes. Recorded as fog on #305.

- **Soft spot, stated plainly:** dec. 8 leaves `Debug` with a published base
  class it wants systems to stop inheriting, and no replacement signature is
  specified here. The registration call is `register_panel(panel: Control,
  category: int)` today, which a plain `Control` already satisfies — so the
  interface exists and the inheritance is convenience, not necessity. But
  *convenience across 39 files* is how the 5,934 lines got written, and nothing
  in this ADR stops the 40th panel from extending the base class again. A guard
  would, and this ADR does not write one.

- **Second soft spot:** dec. 1's eleven added `DEBUG_OWNER` entries are
  filename-fragment rules, the same brittle mechanism whose failure this ADR
  opens with. They are correct today and checked against each panel's measured
  outbound reach, but the mechanism is unchanged and will mis-file the next
  oddly-named panel. Booking by explicit path, as ADR-0129 dec. 11 does, would
  be sturdier and was not done here only because thirty entries is a worse
  document than eleven fragments.

  > **This soft spot came true, twice over, and is now mechanized
  > ([ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)
  > dec. 3, 2026-08-21).** `DetailScreenDebugPanel.gd` is the *"next oddly-named
  > panel"* — 158 lines, no fragment, `None`. And the shadow returned at a
  > smaller scale: `"Map"` precedes `"Ui"`/`"UI"`, so the UI3 owner-map tool
  > (468 lines) was booked `Battlefield`, and `"Cinematic"` sent a combat probe
  > (323) to `Cutscene`. Worse, once a guard was written for dec. 1's closing
  > instruction — *"Keep every entry here matching an actual file, or the shadow
  > returns"* — it found that **14 of the 41 fragments could never fire**: eleven
  > match no file, three are wholly shadowed. Pass 4 puts an exact-stem table in
  > FRONT of the fragments (exact before substring, as `RULES` already does) and
  > `check_blueprint_walk.py` now fails on a dead or shadowed entry. The
  > prediction was right about the mechanism and right about the remedy; what it
  > underestimated is how fast a table of intent rots when nothing reads it back.
