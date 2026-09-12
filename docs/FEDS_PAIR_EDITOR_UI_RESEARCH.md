# Research — UI model for a small delta-timed opcode + note stream (FEDS pair editor redesign)

**Date:** 2026-08-11
**Author:** deep-research workflow (`wf_b73371e4-3b4`) + internal code map, synthesized by hand
**Feeds:** the ADR-0085 re-litigation (the "track-lane strip, not a piano-roll" +
"loops draw folded" decision the user now disputes) and the `FedsPairStrip.gd`
view-layer rebuild.
**Status:** research only — no code changed. Next step is `grill-with-docs`/`codebase-design`
to settle the surface + amend ADR-0085, then `tdd` to rebuild the view.

---

## The question

What is the best UI model for viewing/editing a **small, delta-timed opcode + note
stream** at FEDS scale?

- 2 parallel tracks, **2–10 events per track**.
- Each track = a couple of "setup" opcodes (tempo / instrument / pan / portamento
  config) wrapping **1–2 notes**.
- **Foldable REPEAT/CODA loops** that can be shown FOLDED (one pass + ×N badge) or
  UNROLLED ("wound / unwound").

The current surface — a ~60px micro-strip (`FedsPairStrip.gd`) crammed into an
`EffectKeyframeInspector` grid cell — is rejected by the user as *"useless … way too
crammed … I don't even think this is 'unwound'."* The stated benchmark is the DAW
plugin's **note-lane + opcode-lane + loop-roller (wind/unwind)** model
(`fft-plugin/.../fft_smd_loop_roller.h`), and the main-section
`EffectScoreTimeline` look ("big and expressive … like the channels in the main
section").

---

## Method & confidence tiering (READ THIS)

The workflow decomposed into 5 angles, fetched 21 sources (17 primary/official), and
extracted 88 falsifiable claims, of which 25 went to a 3-vote adversarial verify. The
verification and synthesis passes were **partially killed by a server-side rate-limit**
(`Server is temporarily limiting requests · not your usage limit`). Consequence:

- **6 claims reached a full 3-0 confirmation** → **Tier A (Confirmed)**.
- **19 claims scored `0-0 (3 abstain)`** — the verifiers never cast a vote because
  every call errored out. These are **NOT refuted**; they are unadjudicated. Because
  they all come from **primary/official documentation** (Reason, Cakewalk, OpenMPT,
  Renoise, Logic, Cubase, Bitwig, LilyPond, Microsoft), I retain them as
  **Tier B (Sourced, unverified)** and flag them as such at each use.

Do not read the workflow's `refuted[]` bucket as "false" — it's "abstained." The
distinction matters for how much weight the ADR amendment can put on each claim.

---

## The internal code map (what we're comparing against)

Three existing surfaces, mapped from source (`Explore` agent, file:line cited):

| Dimension | **A — DAW plugin (benchmark)** | **B — `EffectScoreTimeline` (the "good" look)** | **C — `FedsPairStrip` (rejected)** |
|---|---|---|---|
| Row/lane height | 128px monolithic track row (`FFTTrackLaneView.h:182 kTrackRowHeight`); 5-row opcode overflow band (`:183 kOverviewOpcodeRows`) | 24px lane + 2px gap (`EffectScoreTimeline.gd:74-75 LANE_H/LANE_GAP`); 20px collapsible section header (`:73`) | 16px note + 12px chip + 6px gap = **34px per track** (`FedsPairStrip.gd:17-20`) |
| Gutter | 124px labels + S/M (`:179 kHeaderWidth`) | 124px labels + S/M, right-justified (`:64 GUTTER_W`, `:79-80`) | **none** — folded into panel margin |
| Ruler | 42px dedicated (`:181 kRulerHeight`) | floating, detached (`EffectFramesBar`) | 14px minimal (`:16 RULER_H`) |
| Notes vs opcodes | notes as bars + opcodes as chips **inside the same 128px lane**, 5-row overflow band for stacking | one concern per lane (no opcode concept) | notes top row / opcodes bottom row **within a 34px block** |
| **Loops** | **UNROLLED** at presentation: each REPEAT/CODA instance draws as separate depth-cued events; every event carries `loop_depth`/`loop_instance_id`/`loop_root_id` (`fft_smd_inspector.h:28-29,51-52,56`); compiler folds, runtime unrolls (`fft_smd_loop_roller.h:47-49`) | N/A (scored product, no sequencer loops) | **FOLDED**: one bracket + ×N badge (`FedsPairModel.gd:138-145`, `FedsPairStrip.gd:151-157`) — loop internals opaque |
| Selection | track-click or per-command select | span → inspect, empty lane → seek (explicit hit-test guard, `:738-878`) | **read-only**; edit via inspector rows below |
| Width budget | fixed, screen-wide | fills panel | **~120px min forced into a reflowing GridContainer cell** (`EffectKeyframeInspector.gd:325-333`) → ~60–120px net/track; auto-width opcode labels **overdraw at tick 0** (`FedsPairStrip.gd:148-149`) |

**The diagnosis in one line:** C fails on two axes the benchmark A gets right — it
**folds loops** (hiding structure the user wants to see "unwound") and it **starves
opcodes of vertical space** (34px, no overflow band), then compounds both by living
inside a reflowing inspector cell that can't guarantee width. A is unrolled + tall +
screen-wide; B is the thin-lane + ruler + S/M-gutter idiom the user points at as "big
and expressive."

---

## Findings by framing

### 1. DAW piano-roll + separate automation/command lanes

The single most consistent pattern across professional DAWs: **notes and non-note
events never share a lane.** Non-note data (automation, controllers, program changes)
gets **its own lane, one lane per event type**, stacked below the note grid.

- **[Tier A]** Reason splits editing into a **Note Edit Lane** and separate
  **Controller/Parameter Automation Lanes** — automation is not drawn on the note
  grid. [reasonstudios · 3-0]
- **[Tier A]** Reason draws notes as **horizontal boxes** in a piano-roll, with a
  **full-range keyboard on the left as the reference axis** (box edges = note-on /
  note-off). [reasonstudios · 3-0]
- **[Tier A]** Cakewalk's multi-track Piano Roll splits the Controller pane into
  **multiple lanes — exactly one lane per unique event type** — keeping non-note events
  off the note grid. [cakewalk · 3-0]
- **[Tier A]** **Each MIDI data lane displays only a single event type**, which
  *"prevents overlapping parameters (velocity, modulation, pitch bend, CC) from
  cluttering one another."* [cakewalk · 3-0] — this is the direct, named cure for
  C's tick-0 opcode overdraw.
- **[Tier A]** Those controller/automation lanes sit **at the bottom of the Piano Roll
  view**, drawn **simultaneously with** the notes above. [cakewalk · 3-0]

**Takeaway for FEDS:** "one lane per concern, notes get bars + a pitch axis, every
opcode *kind* gets its own thin lane below" is the industry-default answer to
heterogeneous events on a timeline. It maps cleanly onto the `EffectScoreTimeline`
lane idiom (B) rather than C's two-rows-in-34px cram.

### 2. Tracker / pattern-grid editors

The tracker model is a **column-per-channel, row-per-tick grid** with **structurally
separate note vs effect columns**, and it keeps commands compact by encoding them as
**fixed-width alphanumeric cells**, not widgets.

- **[Tier A]** OpenMPT encodes each effect command as **one effect-letter + a hex
  parameter** (e.g. `G05`) — a compact fixed-width cell, *not* an expanded visual
  widget. [openmpt · 3-0]
- **[Tier B]** Renoise's Pattern Editor is a **column-per-track, row-per-line** grid;
  within one track, **Note Columns and Effect Columns are structurally separate
  regions**. [renoise · abstained]
- **[Tier B]** FamiTracker subdivides each channel into **Note / Instrument / Volume /
  Effect** sub-columns, effects in `Yxx` format (Y = effect, xx = hex) in their **own
  column beside the note**; extra effect columns expand **on demand** via header arrows.
  [famitracker · abstained]
- **[Tier B]** Renoise's Pattern **Matrix** marks repeated content with a **small
  corner badge** ("Show Identical Repeated Slots") rather than re-rendering it — a
  direct analogue to a folded-loop ×N badge. [renoise · abstained]

**Takeaway for FEDS:** the tracker world validates two things — (a) a **short typed
token** ("G05", "Yxx") is a legitimate, dense way to render an opcode, and (b) **note
and command live in adjacent dedicated columns, never overlaid**. At FEDS scale (2–10
events) a full tracker grid is overkill, but the *token* idea beats C's variable-width
label-that-overdraws.

### 3. MIDI / event-list editors

Every major DAW ships a **typed event list** as the fallback for heterogeneous streams
— proof that when data is sparse/mixed, a scannable list beats a spatial timeline.

- **[Tier B]** Logic's Event List shows **all MIDI event types in one scannable list**
  (note, CC, pitch bend, program change, aftertouch, poly-AT, SysEx, meta) and offers
  an **explicit filter-by-event-type** control. [apple · abstained]
- **[Tier B]** Cubase's Event List is a **chronologically-ordered typed list** with a
  **non-editable Type column** that lets notes and non-note events coexist scannably,
  distinguished by type. [steinberg · abstained]

**Takeaway for FEDS:** because a FEDS track is *tiny* (2–10 events), the event-list
idiom is genuinely competitive with a lane view — and the two are not mutually
exclusive. The strongest pattern is a **hybrid**: a lane view for temporal/loop
structure, backed by a **typed, scannable list** (or the existing F1 inspector rows)
for select→edit. A **Type column / typed chip** is the shared primitive that makes an
opcode legible in either.

### 4. Loop fold / unroll ("wind / unwind") — the core of the dispute

Three independent domains — a DAW, a music engraver, and a code editor — **converge on
the same three-part pattern**, which is the answer to the user's "it's not even
unwound" complaint:

1. **A folded form that carries an explicit count/badge**, and
2. **A first-class, reversible operation that unrolls it**, and
3. **Hover/peek reveals folded contents without committing to unroll.**

- **[Tier B]** **Bitwig**: the **Repeats** operator *folds* repeated events into a
  **single source event with adjustable params** (one event represents N); **"Slice At
  Repeats"** is the **explicit unroll** (fold → N separate events, repeats disabled);
  **"Expand"** prints a chosen number of cycles as permanent individual events.
  [bitwig · abstained] — this is *exactly* the plugin's loop-roller model, from a
  shipping DAW: fold ⇄ unroll as named, reversible verbs.
- **[Tier B]** **LilyPond**: `\repeat volta` = **folded** notation (repeat brackets +
  implied count); `\repeat unfold` = **written-out unrolled**; **`\unfoldRepeats`** is
  an **explicit reversible transform** between the two. [lilypond · abstained] —
  folded and unrolled are formally two views of one stream, with a named conversion.
- **[Tier B]** **Visual Studio outlining**: a region **collapses behind an inline caret
  glyph**; **clicking the same glyph re-expands** it (one reversible in-place
  affordance); **hovering the collapsed region shows its contents as a tooltip** — so
  the folded badge is **never opaque**. [microsoft · abstained]

**Takeaway for FEDS — this is the crux of the ADR re-litigation.** The user is right
that "folded, full stop" is the wrong default. The cross-domain consensus is **not**
"always unroll" and **not** "always fold" — it's **fold-with-a-badge + an explicit,
reversible unroll toggle + hover-to-peek**. ADR-0085 chose fold-only and omitted the
toggle; that omission is the defect. The plugin's `fft_smd_loop_roller` and Bitwig's
Repeats/Slice-At-Repeats are the same design; honor it with a **per-loop wind/unwind
control**, defaulting folded, expandable in place, with hover peek.

### 5. Rendering heterogeneous typed events legibly at small counts

- **[Tier A]** The Cakewalk rule — **one lane per event type** — is itself the primary
  anti-overdraw technique: never stack two event types in the same vertical band.
  [cakewalk · 3-0]
- **[Tier A]** OpenMPT's **fixed-width typed token** (`G05`) shows a compact,
  non-overlapping opcode label is achievable — the opposite of C's auto-width
  `draw_string` that collides at tick 0. [openmpt · 3-0]
- **[Tier B]** Visual Studio's **hover-tooltip-on-collapsed-region** generalizes to
  *any* dense marker: render a **short chip**, reveal the **full opcode name +
  params on hover**. [microsoft · abstained] — this is the honest fix for "PBesttamanto_Init"
  soup: chip shows a glyph/short code, tooltip shows the full name.
- **[Tier B, secondary]** Progressive-disclosure guidance (NN/g) backs the same
  staging: show the few, defer the rest to an expand/hover. [nngroup]

**Is a lane even right for so few events?** The pros say: **use both.** DAWs ship a
spatial view *and* an event list for exactly this reason. For FEDS, a **lane view for
loop/temporal structure + a typed list (or the F1 inspector) for editing** is the
defensible hybrid — with a **typed chip** as the shared legibility primitive.

---

## Synthesis — what wins for FEDS scale

Ranked, highest-confidence first:

1. **One lane per concern; never overlay two event types** *(Tier A, Cakewalk +
   Reason).* Notes get a bar lane with a pitch tell; **each opcode kind gets its own
   thin labeled lane** below. This is the named cure for C's tick-0 overdraw and is the
   `EffectScoreTimeline` idiom the user already blessed.

2. **Fold-with-badge + explicit reversible unroll + hover-peek** *(Tier B, but
   three-domain convergence: Bitwig + LilyPond + Visual Studio).* Loops default folded
   (×N badge), each carries a **wind/unwind toggle** that unrolls **in place**, and
   **hover reveals folded contents** without committing. Directly answers "it's not even
   unwound" and re-opens ADR-0085's fold-only choice. The unrolled projection already
   exists — `SoundGhostProjector.pair_pips` (bounded MAX_PIPS 96 / 30s) — so the
   editor can reuse it rather than re-derive.

3. **Typed chip as the opcode primitive, full detail on hover** *(Tier A token +
   Tier B hover).* Short fixed-width glyph/code in the lane; full opcode name + params
   in a tooltip and in the inspector on select. Kills the auto-width overdraw.

4. **Promote out of the inspector cell into a tall lane panel with a real ruler +
   S/M gutter** *(internal map + Tier A layout norms).* The ~60px micro-strip is the
   root cause; it lives in a **reflowing GridContainer** that can't guarantee width.
   `EffectScoreTimeline` (24px lanes, 124px gutter, detached ruler, collapsible
   sections) is the proven in-repo template.

5. **Keep the event-list / inspector as the select→edit backbone; the lane is the
   navigator** *(Tier B, Logic/Cubase).* At 2–10 events a typed list is legitimately
   competitive; use the lane for temporal/loop structure and the F1 inspector kit for
   editing — preserving ADR-0085's "select → edit through the inspector" seam while
   fixing the *view*.

### What this means for ADR-0085

The amendment's **"loops draw folded"** and **"full piano-roll rejected (dead verbs at
FEDS scale)"** are the two disputed clauses. Research verdict:

- **"folded" is under-specified, not wrong.** Fold is the right *default*; the defect
  is the **missing reversible unroll toggle + hover-peek**. Amend to
  *"loops draw folded by default, with a per-loop wind/unwind toggle (Bitwig
  Slice-At-Repeats / LilyPond `\unfoldRepeats` / VS outlining precedent) and
  hover-peek."*
- **"reject the full piano-roll" survives, but for the wrong-stated reason.** The pros
  don't reject piano-roll verticality because events are few — they reject **overlaying
  event types**. Re-cast the rejection as *"no drag-to-pitch structural verbs at v1"*
  while **adopting** the piano-roll's actual win: **per-concern lanes + a real ruler +
  a tall, breathing layout**, promoted out of the inspector cell.

Net: the user's instinct matches the evidence. Amend ADR-0085 — don't silently
contradict it — then rebuild the view (`tdd`) against the tall-lane + wind/unwind +
typed-chip spec, reusing `SoundGhostProjector.pair_pips` for the unrolled projection
and keeping the MODEL/EDIT/save layers untouched.

---

## Sources

**Tier A — confirmed (3-0 adversarial):**

- Reason 13 — Note & Automation Editing (note lane vs controller lanes; piano-roll
  boxes + keyboard axis). https://docs.reasonstudios.com/reason13/note-and-automation-editing
- Cakewalk — Editing MIDI (controller pane split one-lane-per-event-type; single type
  per lane; lanes at bottom of piano roll).
  https://legacy.cakewalk.com/Documentation?product=Cakewalk&language=3&help=EditingMIDI.21.html
- OpenMPT — Effect Reference (compact effect-letter + hex token).
  https://wiki.openmpt.org/Manual:_Effect_Reference

**Tier B — sourced but unverified (primary docs; verify abstained under rate-limit):**

- Bitwig — Operator Functions (Repeats fold; Slice At Repeats unroll; Expand).
  https://www.bitwig.com/userguide/latest/operator_functions/
- LilyPond — Long Repeats (`\repeat volta` folded; `\repeat unfold`; `\unfoldRepeats`).
  https://lilypond.org/doc/v2.23/Documentation/notation/long-repeats
- Microsoft — Visual Studio Outlining (collapse glyph; click to expand; hover tooltip).
  https://learn.microsoft.com/en-us/visualstudio/ide/outlining
- Renoise — Pattern Editor & Pattern Matrix (column-per-track; note vs effect columns;
  repeated-slot badge). https://tutorials.renoise.com/wiki/Pattern_Editor ·
  https://tutorials.renoise.com/wiki/Pattern_Matrix
- FamiTracker — Pattern editor (Note/Instrument/Volume/Effect sub-columns; `Yxx`;
  expandable effect columns). http://famitracker.com/wiki/index.php?title=Pattern_editor
- Apple — Logic Pro Event List (unified typed list; filter-by-type).
  https://support.apple.com/guide/logicpro/event-list-interface-lgcp31f1a05a/mac
- Steinberg — Cubase List Editor / Event List (chronological typed list; Type column).
  https://archive.steinberg.help/cubase_pro/v11/en/cubase_nuendo/topics/midi_editors/midi_editors_list_editor_event_list_r.html

**Supporting (secondary):**

- Nielsen Norman Group — Progressive Disclosure. https://www.nngroup.com/articles/progressive-disclosure/
- OpenMPT — Patterns; MusicRadar — tracker tips; setproduct — data-table UI design.

**Internal code map (this repo / sibling package):** `fft-plugin/src/juce/FFTTrackLaneView.h`,
`fft-plugin/include/fft_plugin/fft_smd_inspector.h`, `fft_smd_loop_roller.h`;
`godot-learning/src/effects/studio/EffectScoreTimeline.gd`, `FedsPairStrip.gd`,
`FedsPairModel.gd`, `EffectKeyframeInspector.gd`.

---

## Method footnote

Deep-research workflow `wf_b73371e4-3b4`: 5 angles → 21 sources → 88 claims → 25
adversarially verified (need 2/3 refutes to kill). Confirmed 6; the remaining 19
**abstained** (verify + synthesize passes hit a transient server-side rate-limit),
retained here as Tier B because all are primary/official docs. Re-running the verify
pass later (when un-throttled) would upgrade most Tier-B claims to Tier A; none were
contradicted by any source.
