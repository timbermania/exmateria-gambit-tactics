# Time-Scale pacing lives on the timeline as a slowness band, freehand-painted from a pop-up

Status: accepted (design settled via `/grill-with-docs` 2026-08-13;
[timbermania/fft-monorepo#270](https://github.com/timbermania/fft-monorepo/issues/270)
`/tdd` build pending)

## Context

Making Time Scale editable (#270, part of the #262 editability push) means authoring its two
**pacing curves** — `outer_phases` ("Phase 1 pacing") and `for_each` ("For-each pacing"), each
600 integers on disk (see the *Pacing curve* term in `CONTEXT.md`). A raw 600-row grid is
unusable, so the UX is the whole cost of the ticket; the byte writer is cheap (re-pack 600
ints → 300 nibbles per curve).

Two questions had to be settled: **where the curve is seen**, and **how it is edited**.

An earlier pass in the same grill put the curves as rows on the **Effect Settings** inspector
surface (alongside #271 Timeline durations and #272 Flags), each a sparkline that opened a
pop-up painter. The user rejected that placement: a pacing curve isolated in a side panel is not
useful — the whole point is to **line time-slow up against the rest of the effect** (other spans,
sound firings, the visual climax). It has to be read *against the timeline*, on the same frame
axis. The reference model given was the sound triggers' **energy "ghost band"** (ADR-0085):
a translucent swell drawn on the timeline whose height tracks an envelope.

## Decision

### Decision 1 — placement: an on-timeline band, not a settings panel

**Placement — an on-timeline band, not a settings panel.** The pacing curves project as a single
**global full-width "Time scale" lane** pinned at the **bottom** of the timeline, built by a new
`EffectScoreModel` lane builder (realigning with #270's original `EffectScoreModel.gd`
instruction). It is *global* because one lane carries **both** curves and they span different
phases, so it cannot nest under any single phase section (unlike every normal lane). Within the
row, two filled bands tile the frame axis — Phase 1 pacing over `[0, phase1_duration)`, For-each
pacing over the for-each region — drawn by a `_draw_pacing_bands()` that mirrors the sound
`_draw_ghost_energy()` (`EffectScoreTimeline.gd`). The shared playhead line already crosses every
lane, so "where are we in the pacing" is free. No solo/mute (it is a visualization, not an audio
channel).

### Decision 2 — band height is slowness above normal

**Band height = slowness above normal**, not raw value: `(value − 2)` clamped to `0..8`,
normalized to the lane height (`EffectScoreModel.pacing_norm`). Because value `2` (normal speed)
is ~94% of all samples in the corpus, a raw-value fill would paint a constant band down the whole
timeline; the slowness mapping lets the band **swell only where time slows**, which is exactly the
"spot the slow-mo against the climax" read the user wanted. A curve whose enable bit is off is
still drawn, but **greyed** (you see the authored shape without it acting).

### Decision 3 — revision: outline + fill, so the band shows something everywhere

**Revision — outline + fill, so the band shows *something* everywhere.** The first cut drew *only*
the slowness fill (a swell from the baseline). At value `2` the fill has zero height, so the ~94%
normal-speed stretches drew nothing at all — the band collapsed to invisible slivers and read as
disconnected humps that "snapped in and out" while scrolling. The fix keeps the same height map but
draws the curve's stepped top edge as an **always-present outline** (`pacing_top_points` →
`draw_polyline`) *under* the swell fill: through normal-speed stretches the outline lies flat on
the baseline (present, legible), and where time slows it rises into the filled hump. The fill is
drawn as **one rect per raised sample column** (`pacing_fill_rects` → `draw_rect`), not a single
closed polygon — a lone fill polygon self-touches at the gutter when the band is scrolled partly
off-screen (off-screen points clamp to `GUTTER_W`) and fails to triangulate, silently dropping the
whole fill while the outline stayed (a scroll-dependent flicker). Per-column rects clip cleanly.
The height map and byte semantics are unchanged — this is purely a render decision.

### Decision 4 — editing: freehand paint from a pop-up, live

**Editing — freehand paint from a pop-up, live.** Clicking a band opens the existing centered
**pop-up painter panel** (`EffectStudioPage._painter_panel`), extended with an **enable/disable
checkbox** for that curve's bit (pattern1 for Phase 1, pattern2 for For-each). Inside it the
curve is authored by **freehand-painting a dense integer grid**, reusing `EffectCurvePainter` —
**not** the sparse-keyframe path the colour editor uses. Edits are **live**: painting mutates the
shared `EffectCurve`, so the on-timeline band re-renders immediately, and toggling the enable
greys/ungreys the band in place. The painter carries its own playhead marker. Specifics:

- **Y-axis `0–10`**, floor 0, a marked baseline at **2** ("normal speed"), `3–9` the slow ramp
  (deeper = slower, factor `2/value`), and `10`/`0` hinted as "hold previous". Not `0–9` (would
  clamp the 15 real `10` samples in the corpus → breaks byte-exact round-trip) and not `0–15`
  (11–15 never occur and are pure "hold" clutter). Empirically the whole corpus uses only 2–10.
- **X-scope defaults to the *played window*** — the frames the phase actually samples (Phase-1
  duration / for-each length). All 600 samples are preserved on disk and written verbatim; the
  window grows if the phase is lengthened; the full 600 stays revealable.
- **Undo** is per committed stroke (mouse-up), snapshotting that curve's full 600-int array.
  Curve edits are `invalidates_sim=true`: they re-fold and recompute the end marker, because
  pacing feeds `tl.setup(...)` → `EffectEndModel` (same wrinkle #271's timeline-header edit
  handled).

## Why not keyframes (the non-obvious rejection)

A reader who just saw the colour editor will ask why time-scale diverges. Two reasons: (1) the
data is **stepped integers**, not a smooth curve — a real `outer_phases` reads
`…3,4,5,5,7,7,8,8,9,9,10,10,10,10,10,9,9,8…`; Douglas–Peucker fitting a stairstep needs a
control point at nearly every step to stay byte-faithful, so keyframes fight this data. (2) The
painter is a **zero-lift reuse** (already generic), whereas keyframes would need a ~200–300-line
extraction of a non-colour keyframe session out of the mux/demux-specific `ColourKeyframeFit`.
Freehand painting a `0–10` integer grid is both the better data fit and the cheaper build.

## Consequences

- The Effect Settings surface gains **no** Time-Scale section; the earlier `_time_scale_section`
  plan is dropped. The two enable bits leave Effect Flags for the band's pop-up editor (see the
  ADR-0092 amendment), so those bits are surfaced **only** on the timeline path.
- `EffectScoreModel` grows a first **global (non-phase) lane** — a small structural addition
  (the loop band is the precedent for full-width overlay drawing on the timeline).
- The band is a **derived view** of the same `EffectCurve` the painter mutates; no second source
  of truth, and live redraw is just re-reading the curve on `curve_changed`.
- **Studio playback honours the curve.** The game slows via `EffectInstance._process`'s accumulator
  (`+= delta * _time_scale_factor`), but the Studio preview instance is **parked** — the page owns
  the clock (ADR-0090) and seeks it frame-by-frame, so that accumulator never runs. The page
  therefore applies the same factor to its own transport accumulator
  (`_transport_accum += delta * TRANSPORT_HZ * _speed() * pacing_factor_now`), where
  `EffectScoreModel.pacing_factor_at` reproduces `EffectTimeline._update_time_scale`
  (`2/value`, gated by the pattern enables). A slow frame accrues fewer steps and dwells longer, so
  painting a slowdown visibly slows preview playback — matching the game. Without this the transport
  advanced one frame per tick regardless of the authored pacing.

## Amendment 1 — paint the curve *on the band*, not in a pop-up

Status: accepted (design settled via `/grill-with-docs` 2026-08-13; supersedes the "Editing —
freehand paint from a pop-up" decision above and its Y-axis sub-point; `/tdd` build pending).

Once the band shipped, authoring through the centered pop-up proved clunky for the reason the whole
placement decision was meant to fix: **you can't imagine the curve against the timeline contents
while editing it in a disconnected modal**, and the pop-up's `0–10` axis wasted ~70% of its canvas
(every real sample lives in `2–10`, clustered at the top), leaving little room to be precise. The
band already lays out on the shared frame axis over the *played window*, so the fix is to make the
band itself the editor.

**Editing surface — a focus-expand accordion on the bottom lane.** Left-clicking a band **expands
the "Time scale" lane row** from its compact 34px to a paintable height (~140px); **Esc or a
click-away collapses it** back. The first click only *arms/expands* — it does not paint. Because
this is the bottom-most lane, the row grows **downward** into empty space and nothing above it
moves. The lane is not permanently tall (that would waste vertical space on a lane that is flat at
baseline ~94% of the time and fights the compact slowness map) — it is tall **only while in use**.

**Scope — one band at a time.** The two curves (`outer_phases` / `for_each`) sit on the same lane
over disjoint frame ranges. The **clicked band is focused and editable**; the other **dims to
read-only** (still drawn, for context). Clicking the other band re-focuses to it (the lane stays
expanded). This reuses the existing per-band select (`hit_test` → `{kind:"select",
span_id:"time_scale#<field>"}`) and prevents a horizontal sweep that crosses the phase-1→for-each
boundary from silently painting the wrong curve.

**Gesture — bare left-drag paints; modified gestures still navigate.** The pacing lane already
excludes seek/scrub, so a bare drag *there* is unambiguously "paint" (no "seek vs inspect" fight).
It reuses `EffectCurvePainter`'s stroke math (`stroke_segment`, preview-live, **commit on
mouse-up**) bound to the focused band's rect + the shared axis, and lands through the same
`_commit_pacing_edit(field, ints)` choke (undo, `invalidates_sim`). **Shift/middle-drag pan** and
**Ctrl+wheel zoom** pass through unchanged, so the timeline still scrolls/zooms while a band is
focused.

**Y-axis — the slowness scale, `2` (floor) → `10` (top)**, revising the pop-up's `0–10` linear
axis. The paint canvas uses the **same `(value−2)/8` map the band draws**, so painting is **WYSIWYG
with the collapsed render** (no surprise remap) and the whole expanded height covers the meaningful
`2–10` range — which is exactly the "only 30% is used" complaint the `0–10` axis caused. Value `10`
("hold at max slow") is the top, `2` (normal) the floor; `3–9` the ramp. You **cannot** paint `0`
or `1` — but those **never occur in the corpus** and mean "hold"/"real speed", already covered by
`10`/`2`. Byte-exactness is unaffected: a stroke only rewrites the columns it paints, so untouched
samples keep their exact disk value, and the two real `10`s are still reachable. This honours the
original constraint (preserve `10`, no `0–9` clamp, no `0–15` clutter) while fitting the band.

**Precision aids.** The expanded canvas draws **horizontal gridlines at each integer `2…10` with
value labels** (reusing the painter's `_draw_y_gridlines`, on the slowness scale) plus a **live
value readout** that follows the cursor while hovering/painting. Integer snap is inherent
(`pixel_to_cell` rounds), so there is no sub-integer fuzz.

**Chrome — gutter, not modal.** The lane gains a proper **"Time scale"** gutter name like every
other lane. The two per-curve **Enabled** toggles (Phase 1 / For-each, `effect_flags` bits 5/6)
move to the **gutter's Solo/Mute button slot** (this lane has no Solo/Mute) — one toggle per band —
so enable/disable no longer needs the pop-up. The expanded band stays a pure paint canvas.

**Consequence — the pop-up route for pacing is removed.** `_open_pacing_painter`, the shared
painter panel's pacing branch, and the pop-up's pacing enable checkbox are deleted. The shared
painter panel remains for **emitter/colour curves only** (unchanged). One editor for pacing, no
"which one do I use?" split.

## Amendment 2 (2026-08-28) — the Decision is built to the letter; Amendment 1 is unbuilt in every clause, and it is the *only* half of this ADR whose Status tells the truth

*Audit pass, 2026-08-28 (ADR consolidation). The four Decision paragraphs above were unnumbered;
they now carry `### Decision 1`–`4` headings so `ADR-0093 dec. N` citations resolve, and the
bare `## Amendment` became `## Amendment 1` (nothing in the corpus cited it, by date or
otherwise). No prose was changed or removed. Graded against the tree.*

### What is current, per rule

| Rule | Where it is written | Holds? | What the tree says |
| --- | --- | --- | --- |
| Global full-width "Time scale" lane, bottom-pinned, built by an `EffectScoreModel` lane builder | dec. 1 | **built** | `EffectScoreModel._pacing_lane` (`:277`) returns `"global": true`; `EffectScoreTimeline._layout_pacing_lane` is the **last** call in the layout pass (`:766`, with `_content_h = y` immediately after), so it is bottom-pinned by construction. `_draw_pacing_bands` (`:1877`) mirrors the sound ghost band as designed. |
| No solo/mute on the lane | dec. 1 | **holds** | No solo/mute hit anywhere in the pacing code path. |
| Band height = `(value−2)` clamped `0..8`, normalized; disabled curve drawn but **greyed** | dec. 2 | **built and guarded** | `EffectScoreModel.pacing_norm` (`:337`), pinned by `EffectScoreModelTest._test_pacing_norm_height_map`. `_draw_pacing_bands` picks `COL_PACING_FILL_OFF`/`COL_PACING_LINE_OFF` off each band's `enabled`. |
| Always-present stepped outline under a **per-column-rect** fill | dec. 3 | **built and guarded** | `pacing_top_points` (`:1899`) + `pacing_fill_rects` (`:1924`), with `EffectScoreTimelineTest` arms at `:1602`, `:1642` and `:1656` (the all-normal case returns **0** rects while the outline still runs flat — exactly the failure dec. 3 describes). |
| Pop-up painter, `EffectCurvePainter`, Y-axis `0–10` with baseline 2, X-scope = played window, per-stroke full-array undo, `invalidates_sim` | dec. 4 | **built, every sub-point** | `_open_pacing_painter` (`:6272`) binds the painter at `PACING_VMAX = 10` and titles it "freehand paint (0–10, baseline 2)"; `_pacing_window(field)` supplies the played-window `used_n`; `TimeScaleChannel.apply_raw` `duplicate()`s the pre-edit array as `before_raw`, so one committed stroke is one undo of the whole 600 ints; `_commit_pacing_edit` re-folds and re-derives the end marker. |
| Studio playback honours the curve via the page's own transport accumulator | Consequences | **built and guarded** | `EffectStudioPage.gd:3960` — `_transport_accum += delta * TRANSPORT_HZ * _speed() * _pacing_factor_now()`; `_pacing_factor_now` (`:4157`) delegates to `EffectScoreModel.pacing_factor_at` (`:347`), pinned by `EffectScoreModelTest._test_pacing_factor_at`. |
| The two enable bits are surfaced **only** on the timeline path | Consequences | **FALSE** | See below. |
| Accordion-expand the lane to paint on the band; enables move to the gutter; the pop-up route is **deleted** | Amendment 1 | **unbuilt, and Amendment 1's own Status says so** | See below. |

### The head Status is stale; Amendment 1's Status is the accurate one

The document opens with "#270 `/tdd` build **pending**". Every decision above is in the tree and
guarded, including a full end-to-end acceptance test (`EffectStudioTimeScaleAcceptanceTest`,
four numbered arms through the real page). That is the fifth consecutive audited ADR (0040,
0069, 0071, 0092, 0093) whose head Status advertises shipped work as pending.

Amendment 1's own Status — "supersedes the 'Editing — freehand paint from a pop-up' decision
above and its Y-axis sub-point; `/tdd` build pending" — is, unusually for this corpus,
**exactly right**: none of its five clauses is built.

- **Accordion / focus-expand**: no lane-expand state, no ~140px paint height, no Esc-collapse.
  Nothing in `EffectScoreTimeline` grows a lane row.
- **One band focused, the other dimmed read-only**: not present; the two bands grey purely on
  their enable bit.
- **Bare left-drag paints on the band**: the lane's click still routes to the pop-up —
  `_on_span_selected` (`:4243`) sends every `time_scale#<field>` id straight to
  `_open_pacing_painter` and returns.
- **Y-axis revised to `2 → 10`**: the painter is still bound `0..PACING_VMAX` with the
  literal title "freehand paint (**0–10**, baseline 2)".
- **Enables move to the gutter's Solo/Mute slot**: `_pacing_enable_check` is built at `:1008`
  and added to the painter panel's `head` (`:1012`), i.e. inside the pop-up the amendment
  deletes.

One clause is already true for an unrelated reason: the amendment says the lane "**gains** a
proper 'Time scale' gutter name like every other lane" — `_draw_pacing_bands` has been drawing
that label at `:1885` since the original build.

**The consequence clause is the one that reads as a claim about the tree and is false today.**
"`_open_pacing_painter`, the shared painter panel's pacing branch, and the pop-up's pacing
enable checkbox are deleted" is written in the present tense; all three exist. A reader who
trusts it will grep for a deleted function and find it routed from the only click path the
band has. Landing Amendment 1 also costs the acceptance test: arms 2–4 of
`EffectStudioTimeScaleAcceptanceTest` are written *through* the pop-up ("Clicking the Phase-1
band … opens the pop-up painter … it does NOT set a span inspection root"), so the amendment
cannot land without rewriting a currently-green end-to-end guard.

### "Surfaced only on the timeline path" is false in the shipped tree

Consequences bullet 1 says the two enable bits leave Effect Flags for the band's pop-up editor
"(see the ADR-0092 amendment), so those bits are surfaced **only** on the timeline path."
Measured in the 2026-08-28 audit of ADR-0092: `EffectSettingsProjector._flags_section()` still
declares masks `0x20` and `0x40` on the Effect Settings surface, and
`tests/EffectSettingsProjectorTest.gd:183`–`:196` **asserts** all four bits are there. So bits
5/6 are surfaced on **two** controls — the Effect Settings bitflags group and this ADR's pop-up
checkbox — and on neither of the two surfaces Amendment 1 predicts (the gutter). Both controls
address `{channel: "effect_flags", field: "flags_byte"}`, so this is still one writer and one
undo; what is duplicated is the control, not the truth. The open question of which surface
should lose the bits is recorded against ADR-0092, where the contradicted amendment lives; it
is restated here because this document repeats the false half in its own voice.

### What could not be checked here

The corpus statistics dec. 2 and dec. 4 rest on — "~94% of all samples are value 2", "the 15
real `10` samples", "the whole corpus uses only 2–10" — are claims about
`assets/effects/E###/time_scale.json`. That tree is gitignored ROM-derived content and is
unpopulated in this checkout, so the figures are **unverified, not refuted**. The design
consequences that depend on them (the slowness map, the `0–10` axis choice over `0–9`/`0–15`)
are internally consistent with the code that shipped.

### Recorded question — does Amendment 1 still bind?

Two readings, and the tree supports both:

- **Reading A — Amendment 1 is the design of record and #270's remaining work.** It is dated
  and accepted, it names its supersession precisely, and its rationale (a disconnected modal
  defeats the placement decision the ADR exists to make) is the same argument the Decision
  itself uses. Landing it means deleting `_open_pacing_painter` and rewriting three arms of a
  green acceptance test.
- **Reading B — the pop-up is what shipped and the amendment should be withdrawn or
  rescheduled explicitly.** The pop-up route has been live, guarded end-to-end, and unrevised
  since the amendment was written; nothing in the tree moved toward the accordion. On this
  reading the amendment's present-tense "are deleted" prose is the defect and should be
  restated as a proposal.

Not guessed here: this is a product call about the pacing editor's surface, and it is the same
control-home question ADR-0092 is holding.

### On mechanizing this ADR

Decisions 1–3 and the transport consequence are already covered (`EffectScoreModelTest`,
`EffectScoreTimelineTest`, `EffectStudioTimeScaleAcceptanceTest`). The arm that is **absent and
writable today** is a doc-vs-tree one, not a behaviour one: assert that a symbol an ADR
declares "deleted" is in fact absent from `src/`. Seeded against this ADR it would report
`_open_pacing_painter` at `EffectStudioPage.gd:6272` and fail, which is the correct answer while
Amendment 1 is unbuilt — so it can only be written after the question above is settled, or
written to read Amendment 1's Status ("build pending") as an explicit exemption.
