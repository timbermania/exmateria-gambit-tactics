# A Studio lane event projects through a per-archetype projector that separates what the event owns from the entity it references

> **Amended by [ADR-0073](0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md):**
> the per-archetype dispatch here is now one level *inside* a generic inspection-target
> seam. The inspector renders an `InspectionTarget = {kind, ref}` (span / emitter / …); a
> `span` target still routes to the archetype projectors described below, but an `emitter`
> target renders a bare emitter view, and the "reference" a span navigates across is now a
> first-class, followable **link**.

**Status:** proposed (design settled in a grilling session). Build to follow via
TDD, particle projector first (behavior-preserving) then the screen Blend/Gradient
split (the visible fix).
**Relates to:** [ADR-0069](0069-effect-studio-is-a-standalone-development-window-not-a-debug-panel.md)
(the Studio is a development window) and [ADR-0070](0070-effect-replay-is-deterministic-within-an-instance-via-a-per-instance-seeded-rng.md)
(deterministic scrub). This ADR fixes how a selected [lane event](../context/16-effect-studio-authoring-tool.md)
is turned into what the lane draws and what the inspector shows.

## Context

The Studio's `EffectScoreModel` dispatched **by lane kind**: `_span_label()`
switched on kind for the lane label, `inspector_rows()` switched on kind for the
detail rows, and the inspector had a hardcoded fork between particle spans (a rich
grouped emitter view) and "everything else" (a flat row list). Adding any
parameter deepened the special-casing at each of those call sites.

Two facts the lane-kind dispatch obscured, and which this ADR builds on:

1. **A particle span does not own its parameters — it *references* a shared
   [Emitter](../context/16-effect-studio-authoring-tool.md).** The event owns exactly `{emitter_id,
   action_flags}` (`TimelineData.Keyframe`). The rich fields (position, spread,
   velocity, curves, child emitters) live on the emitter, resolved by
   `emitter_index = emitter_id - 1`, and **one emitter fills many spans** across
   channels and phases. Clicking a span to see those fields is a *navigation
   across a reference*, not an inspection of the event.

2. **A screen tween owns its parameters inline, and a tag on the event selects
   which of them are live.** `ScreenData.Keyframe` carries color, duration, and a
   `ctrl` bit that discriminates the two [Blend / Gradient](../context/16-effect-studio-authoring-tool.md)
   tween kinds — Blend uses `{rgb, blend_mode}`, Gradient uses `{top, bottom}`.
   Same storage, disjoint live field-sets.

The visible symptoms were: Blend and Gradient tweens were indistinguishable in the
lane (both labeled "scr", same fill), Gradient tweens were **not drawn at all**
(`EffectScoreModel` filtered the screen lane to TINT-only, violating the
fully-tiled-lane law), and the code still used the retired `{ FADE, TINT }`
nomenclature the glossary had already replaced with Blend / Gradient.

## Decision

A lane event is projected through a **per-archetype projector**, and the two
levels above are kept as **two separate seams**.

### Decision 1 — Two seams — an event-view and a distinct referenced-entity view

**Two seams.** An **event-view** (what the lane event owns) and a distinct
**referenced-entity view** (the shared `Emitter`, reachable *through* a span but
not owned by it). The inspector for a span is the **concatenation** of the two,
as an ordered list of sections:

```
inspect(lane_event) -> [ Section ]        Section = { title, fields, note? }

  span    -> [ event_section {emitter_id, action_flags} ]
             + emitter_sections (the 4 groups, each note: "shared by N events")
  tween   -> [ one kind-keyed section ]     (Blend | Gradient | palette | camera)
  trigger -> [ one section ]                (sound)
```

The `Section` is the only uniform container; the `Field` atoms inside it stay
**archetype-appropriate** (emitter param-shape with from/to/curve, tween
start→end+duration, plain constants) — no false uniformity is imposed across
archetypes.

### Decision 2 — Discrimination lives in the model, not the view

**Discrimination lives in the model, not the view.** A projector hands the Studio
an already-typed, **live-fields-only** projection: a Blend tween projects
`{rgb, blend_mode, duration}`, a Gradient tween `{top, bottom, duration}`.
Fields a kind does not use are **absent**, not present-and-greyed. The view is a
dumb renderer of the sections it is given.

### Decision 3 — One projector per archetype, owning both outputs

**One projector per archetype, owning both outputs.** `EmitterProjector`,
`ScreenTweenProjector`, `CameraTweenProjector`, `SoundTriggerProjector` each own
`summarize(event) -> {label, color}` (the lane) **and** `sections(event) ->
[Section]` (the inspector). A thin dispatcher in `EffectScoreModel` routes by
archetype + kind. Parse classes (`ScreenData`, `TimelineData`, …) stay pure — they
do not learn about labels, hues, or sections. Because a single projector owns both
the lane label/color and the inspector detail, the timeline's Blend-vs-Gradient
distinction and the inspector's come from **one source of truth**.

## Considered options

- **Keep dispatching by lane kind** (the status quo) — rejected: it is the
  shallow shape the refactor exists to remove; every new parameter re-touches
  `_span_label()`, `inspector_rows()`, and the inspector fork.
- **Projection methods on the parse data classes** (`ScreenData.Keyframe.sections()`)
  — rejected: maximal locality but couples pure parse types to display concerns
  (a keyframe should not know inspector sections or hues).
- **One central `EffectEventView` that switches on archetype/kind** — rejected: it
  just relocates the god-switch; shallow.
- **Weld the emitter to its span in one `detail()`** (today's conflation) —
  rejected: it is exactly what made particle a special case, and it hides that
  emitter edits fan out across every span that shares the id.

## Consequences

- The Blend/Gradient bug dies as a **byproduct**: `summarize()` returns a real
  label/color for Gradient tweens, so the TINT-only filter goes away and the
  fully-tiled screen lane is honored. The `{ FADE, TINT }` enum is retired to
  match the glossary; the lane distinguishes the kinds by label ("Blend"/"Grad")
  plus a border style, with fill still = the color the tween produces.
- The inspector honestly shows the two levels: a span's own fields first, then the
  shared emitter marked **"shared by N events"** — the signal that editing there
  fans out (a live warning once authoring exists; today the Studio is read-only).
- **Time-slow fits without reopening this seam.** It is a *fourth archetype* — a
  **curve lane** (a continuous per-frame pacing curve, not discrete events) — with
  its own `TimeScaleProjector` (`sections()` shows the pacing data, `summarize()`
  renders a curve). The only extra machinery it needs is a lane **render-mode**
  flag (discrete-events vs curve), orthogonal to the projector model.
- Each projector is unit-tested in isolation through its two methods, matching the
  Score model's existing "testable core, thin view" split.

## Amendment 1 (2026-08-28) — the god-switch is gone and the seam generalized past its own design, but "owning both outputs" is a real property for exactly one archetype

*Audited against the tree at `docs/adr-consolidation`. The three bold Decision
paragraphs were given `### Decision N` headings in the same pass — prose
untouched — so `ADR-0071 dec. N` citations resolve.*

Status still reads "proposed … build to follow via TDD". It is built, and
built past this design: `InspectorProjectorRegistry` knows **11** target kinds
and `src/effects/studio/` holds **16** projector files where this ADR names
four. Four later ADRs cite it (0073, 0075, 0086, 0087) and 15 source files do.

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | Two seams — an event-view, and a distinct referenced-entity view; a span's inspector is the **concatenation** | **holds, and generalized** | `SpanProjector` and `EmitterTargetProjector` are separate registered kinds; `InspectionTarget = {kind, ref}` is a real type (ADR-0073's banner above is accurate). `EmitterProjector.gd:56-59` emits the `"shared by %d event%s"` note citing this ADR, and `EffectKeyframeInspector.gd:549` renders it. The fan-out signal went further than the ADR asked: `EffectScoreModel.gd:1541` records making the emitter header a **clickable reverse-navigation row**, fixing a misleading "shared by 0 events". |
| 2 | Discrimination in the model; live-fields-only, absent not greyed | **holds exactly** | `ScreenTweenProjector.sections()` returns `[{"title": "Blend", "fields": …}]` on one branch (`:46`) and `[{"title": "Gradient", "fields": …}]` on the other (`:55`) — disjoint sets, nothing greyed. `summarize()` (`:65-68`) returns `{"label": "Blend", … "border": "solid"}` vs `{"label": "Grad", … "border": "dashed"}`, exactly the Consequence's "label plus a border style, with fill still = the colour the tween produces". |
| 3 | One projector per archetype owning **both** `summarize()` and `sections()`, so lane and inspector share one source of truth | **half** — see below | The half that landed is the important one: `_span_label()` is **gone** from `EffectScoreModel`, so the god-switch this ADR existed to remove is deleted. But `summarize()` is defined on **3 of 16** projectors and called on **1**. |

### The `summarize()` half of dec. 3, measured

`sections()` is everywhere — 18 definitions across the projector set.
`summarize()` exists on three files only:

| Projector | `summarize()` | Callers (src **and** tests) |
| --- | --- | --- |
| `ScreenTweenProjector` | `:65` | `EffectScoreModel.gd:512` (the lane build) + `tests/ScreenTweenProjectorTest.gd:68-69` |
| `CameraTweenProjector` | `:135` | **none** |
| `PaletteTweenProjector` | `:64` | **none** |
| `EmitterProjector` | — | (never written) |
| `SoundTriggerProjector` | — | (never written) |

Two of the four projectors this ADR names by hand — `EmitterProjector` and
`SoundTriggerProjector` — own only `sections()`. So "because a single projector
owns both the lane label/color and the inspector detail, the timeline's
Blend-vs-Gradient distinction and the inspector's come from one source of truth"
is a true and load-bearing statement about the **screen** archetype, which is
the one that had the visible bug, and an unrealized one elsewhere.

What replaced it is not the rejected option. The surviving kind-switch,
`EffectScoreModel._kind_label()` (`:1281`), is used at exactly two call sites
(`:1155`, `:1161`) to fill an inspector row *value* — "Kind: Particle" — not to
label a span. The per-lane labels at `:397` / `:540` / `:649` / `:774` / `:958`
are **lane** headers ("Particle 3", "Sound 1"), not per-event. Outside screen,
no archetype ever grew a per-event lane label to be a source of truth about.

### Recorded question — delete the two dead `summarize()`s, or wire them?

Not resolved here, because the two readings prescribe opposite edits:

- **Dead because unneeded.** Camera and palette lanes draw colour spans with no
  per-event label; nothing in the Studio asks those projectors for a summary and
  nothing ever did. On this reading the two methods are speculative generality
  left from following the ADR's shape literally, and should be deleted — dec. 3
  is then "satisfied where it applies".
- **Dead because unfinished.** The ADR's argument is that lane presentation and
  inspector detail must not drift, and camera/palette lanes *do* present
  something (fill colour, at `:760` / `:774` / `:649`) that is currently computed
  in `EffectScoreModel` rather than by the projector. On this reading the methods
  are the right destination and the wiring is the missing work — dec. 3 is
  half-built and the drift risk is live.

Deciding needs a look at whether the camera/palette lane fills in
`EffectScoreModel` duplicate logic the projectors already hold, which is a
reading of ADR-0086 and ADR-0087's territory, not this one's.

### The `{FADE, TINT}` retirement landed with a deliberate exception

The Consequence says the enum "is retired to match the glossary". The *enum* is:
`ScreenData.ScreenMode` is `BLEND` / `GRADIENT`. But the strings `"TINT"` and
`"FADE"` survive on purpose as the **on-disk labels** — `ScreenData.parse_mode()`
maps `"TINT" → BLEND` and `mode_label()` maps `BLEND → "TINT"` (`:24-31`),
documented as "On-disk labels stay TINT/FADE" so a written `screen.json` matches
the parser's output. `EffectScreenSaver.gd:74` writes `"mode": "FADE"`
accordingly. The nomenclature retirement is real at the type level and correctly
*not* applied to the wire format, which the ADR did not distinguish.

The E173 hand-back also refined the lane-tiling fix beyond what this ADR
describes: `EffectScoreModel.gd:500-506` draws only the played window
`0..max_keyframe-2`, "so the trailing keyframes — mostly bit-7-clear (Gradient) —
don't surface as phantom Gradient tweens (ADR-0071; the E173 'bound 2 too wide'
hand-back)". Drawing Gradient tweens at all was this ADR's fix; not drawing the
padding ones was the correction to it.

### Two forecasts, one wrong mechanism and one expired premise

- **The fourth archetype.** The ADR predicts time-slow arrives as a
  `TimeScaleProjector` plus "a lane **render-mode** flag (discrete-events vs
  curve)". `TimeScaleProjector` has **zero hits**; a lane render-mode flag has
  **zero hits**. Time-slow landed as `TimeScaleChannel` + `EffectTimeScaleSaver`
  and its lane is built by `EffectScoreModel._pacing_band()` (`:311`) into a
  band, not a projector-rendered curve. The forecast that the projector model
  would absorb it without reopening the seam is *true* — the seam was never
  reopened — but neither named mechanism is what did it.
- **"Today the Studio is read-only."** No longer true, which retires the premise
  under "a live warning once authoring exists": `EffectViewerScene` exposes 41
  `studio_*` verbs, most of them authoring, and `src/effects/studio/` holds 15
  `*Saver.gd` files. Whether the "shared by N events" note became the live
  fan-out warning the Consequence promised is a question for ADR-0075's audit,
  which owns the first interactive control.

### On mechanizing this ADR

Dec. 2 is already guarded end to end — `tests/ScreenTweenProjectorTest.gd` calls
both `summarize()` branches and the disjoint `sections()` sets. Dec. 1's fan-out
note is covered by `tests/EffectKeyframeInspectorTest.gd`.

Dec. 3 is the mechanizable gap, and the arm is cheap: assert that every file
matching `src/effects/studio/*Projector.gd` which defines `summarize()` has a
caller. That is the arm that would have surfaced the two dead methods above
instead of leaving them to an audit. The stronger arm — "every archetype's lane
presentation is computed by its projector" — cannot be written until the
recorded question is answered, because it presumes the second reading.

Verdict recorded as **half-landed**: dec. 1 and dec. 2 are built and generalized,
dec. 3's god-switch removal landed while its one-source-of-truth property reaches
one archetype of four.
