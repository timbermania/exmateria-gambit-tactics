# Effect SFX authoring is three projected surfaces, not one flattened ruler

**Status:** accepted (design; grilling/domain-modeling session 2026-08-08). Relates to
[ADR-0073](0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)
(inspection is a generic target reached through followable references) and
[ADR-0014](0014-effecttimeline-owns-time-modulation-tracks-self-deliver.md) (one effect
timeline pumps every subsystem off a shared clock). No code lands from this ADR by itself;
it fixes the *shape* the Effect Studio's sound authoring will take.

## Context

Effect SFX (#268) shipped a sound lane that lets an author edit two integers per event —
`sound_id` and `duration_frames` — and draws each event as a **bar whose width is
`duration_frames`** (`EffectScoreModel.gd:444–478`). That is misleading and feels useless
to author with, because it contradicts what a sound event actually *is*:

- A sound event is a **Trigger**: it fires a one-shot at an instant; the SFX then plays on
  the **SPU's own clock, not bound by timeline frames** (CONTEXT.md *Trigger*). It has no
  meaningful on-timeline length. `duration_frames` is the **gap to the next trigger**, not
  the sound's length. The runtime (`effect_sound_controller.gd:319–377`) fires and forgets —
  it never learns the real audio duration.
- "Making a sound" (its notes, instrument, real length, loops) does not live on the timeline
  at all. It lives one or two tiers below, in the **FEDS opcode stream** — the *same opcode
  VM as SMD music*. The chain a trigger walks is
  `Trigger → SoundContainer[sound_id−2] → (mode+counter) → FEDS pair → Trackset → Sequencer`
  (CONTEXT.md *Effect-cast SFX chain*).
- The SoundContainers (4 per effect, at `effect_flags_ptr+8`) and the FEDS bank are
  **effect-global, shared, referenced** resources — not owned by any channel. Many triggers,
  across channels and phases, point at the same container and the same FEDS pair.

The tempting UI — "expand the sound channel into subchannels that nest the container and the
FEDS streams, all drawn on the effect timeline at full granularity" — re-parents shared data
under one channel (implying ownership that does not exist) and flattens two unsynchronized
clocks onto one ruler.

## Decision

**Effect SFX authoring is three distinct surfaces, one per tier, joined by a shared-seconds
projection — never one flattened editing ruler.**

1. **Trigger scheduler (TIER-1, the effect timeline).** Sound triggers are **instant
   markers** on the *shared* effect timeline and playhead, alongside particle/screen/camera
   events. **This is where cross-subsystem alignment happens** (the "boom + flash + camera
   shake at the climax" case): all four subsystems already share one clock and one playhead
   (ADR-0014), so contemporaneity is just "same frame on the shared ruler." A trigger marks
   *playback start*, not the audible hit. It is drawn as an instant, optionally with a
   **read-only ghost bar** — the resolved sound's real length, projected onto the frame axis.

2. **Sound-selection logic (TIER-2, the SoundContainer).** The 4 effect-global containers
   (`mode` + `id_a/id_b/id_c` + stateful counter). Reached by **following the reference**
   (the ADR-0073 link/projector model already used for particle→emitter), **not** nested as
   channel-owned subchannels. Because it is shared, editing one container changes **every**
   trigger that references it — the UI must say so ("used by N triggers").

3. **FEDS content editor (TIER-3, the sound itself).** The reusable sound, edited on its
   **own tick/tempo axis** — the music DAW plugin's model ported (`fft_smd_inspector.h`,
   `fft_smd_loop_roller.h`): **note lanes vs. opcode lanes**, delta-timed, loops kept folded
   (`REPEAT 0x98 … CODA 0x99`) and spooled at playback. This is "make a sound." Read-only
   first (FEDS is deeply stateful bytecode); authoring later.

**Clock reconciliation.** Both rulers project onto one common domain — **real seconds**
(effect-frames via the frame rate; FEDS ticks via a tempo map that may be *variable*
[`TEMPO 0xA0`, `TEMPO_SLIDE 0xA2`] and must be *integrated*, not scaled). That shared domain
*legitimizes the projection* (ghost bar, anchor) but does **not** justify a shared editing
axis: commensurable ≠ phase-locked (the pumps run independently and drift under frame
hitching), so alignment is **frame-resolution intent**, honest to FFT's fire-and-forget.

**The seam between surfaces is three scalars**, crossing a clean boundary — not a merged
ruler: the **frame rate** and the **tempo map** (for length/position projection), and an
optional **anchor offset** (aligns the audible *hit* rather than the onset). The anchor is an
authoring-tool convenience with **no ROM counterpart** — on disk the trigger is still a plain
early fire (`fire_frame = hit_frame − anchor_offset`), so it stays byte-faithful. The anchor
concept is designed in now; onset + ghost-bar ships first, anchor as a fast-follow.

## Considered options

- **Flatten all three tiers onto the effect timeline as nested subchannels** (the "expand the
  channel" idea). Rejected: it visually re-parents shared/global resources under one channel
  (the "I edited it here, why did it change over there?" trap), forces two unsynchronized
  clocks onto one ruler, and cannot place a FEDS stream for `PARITY`/`TRIPLE_CYCLE` containers
  (the counter yields a *different* pair per fire — no single stream to draw under the event).
- **Keep sound out of the Studio entirely** (schedule pre-existing sounds only). Rejected: it
  leaves "make a sound" homeless, which was the whole complaint.

## Consequences

- The ghost bar stops being polish and becomes **load-bearing** (it is how an author sees a
  sound's real extent/hit against the visual climax) and grows an **anchor marker**.
- The FEDS content editor is a genuinely new, large surface — but it is a near-port of the
  existing music DAW plugin's opcode/note-lane model, not new research.
- Retire the misnomer **"channel config"** for a SoundContainer (it is not config *of* a
  timeline channel; it is shared sound-selection logic keyed by `sound_id`).

## Amendment (2026-08-10): every event is accessible via a timeline handle

The trigger scheduler surface hid two-thirds of its own data. `EffectScoreModel._sound_spans`
projected a handle **only** for audible events (`sound_id >= 2`), so a silent event (a `0/1`
skip) — which still consumes gap and shifts every later fire — was invisible, "gap to 0"
couldn't butt against the next audible fire, and "time to first sound" had no handle. There is
no "rest": sounds overlap and never cut each other off, so a no-sound event is just *an event
that emits no new sound*, and it deserves the same handle as any other.

**Decision.** The score's sound projection is **one honest source, not an audible/silent
fork.** Over the live window `[0, max_keyframe)` every event projects exactly one uniform,
selectable handle (carrying `role: "event"`); each lane with `max_keyframe >= 1` also projects
exactly one **terminator** end-cap (`role: "terminator"`) at index `max_keyframe`, at its true
frame, so the last event's Gap points at something visible. `max_keyframe == 0` and padding
slots (index `> max_keyframe`) project nothing.

- **The tail is the SOLE tell of sound.** Ghost bar + energy swell attach iff the event is
  audible — which falls out for free, because the ghost/energy maps only key `sound_id >= 2`
  (`SoundGhostProjector`). A silent event's handle simply carries no tail. No separate
  `fires` flag exists; it would only duplicate `sound_id >= 2` and risk drifting from it.
- **`role` is the one discriminator.** The terminator forks behaviour — no fire-grab
  (fire-drag is gated on `role == "event"`, **not** `keyframe_index > 0`; the terminator's
  index *is* > 0), no tail (built with none, even if its slot's `sound_id` looks audible — the
  runtime never fires index `max_keyframe`), a distinct inert end-cap glyph, and an inert
  "end of track" inspector (no editable Gap/Sound id — that byte is the last event's Gap; a
  second editor would be two-handles-one-byte). A real event always wins a select-rect overlap
  against a terminator.
- **Fire-grab is gated by POSITION, not by firing.** Index `>= 1` is draggable; index 0 is
  pinned (its fire == the phase offset). Dragging a *silent* interior event is an honest
  audible no-op (stay-local pins every later fire).
- **The terminator does not drive framing.** It is excluded from the content extent
  (`max_frame`, phase-band `end`) so a long silent tail (E317's 544-frame gap) doesn't crush
  every beat into ~10% of the width; it stays reachable by pan/zoom. Pure default-zoom
  cosmetics over an already-honest model.

**Invariant (mechanized).** Over the live window `[0, max_keyframe)`, every sound EVENT
projects exactly one selectable handle, and each lane with `max_keyframe >= 1` emits exactly
one terminator end-cap at index `max_keyframe`; `max_keyframe == 0` and padding slots project
nothing. Guarded by `EffectSoundEventHandleBijectionTest` (counts + frames over real E317).

**Deferred:** event **Add/Delete** verbs (mirror the camera `insert_event`/`delete_event` +
`EffectEditSession` hybrid-snapshot-undo pattern). Promote/demote via `sound_id` already
toggles an existing slot's audibility without touching array structure.

## Amendment (2026-08-11): TIER-3 un-deferred as bounded parameter editing

Grilling/domain-modeling session. TIER-1 and TIER-2 are built; this fixes the shape of
the TIER-3 build (the `sound_def` deferred entry in `editability_manifest.json`,
E###.BIN bytes 0x04638–0x04780). The 2024-08-08 decision said "read-only first"; the
#268 lesson is that read-only sound surfaces feel useless. This amendment replaces that
staging with a middle scope the byte encoding itself draws.

**Scope: bounded parameter editing.** v1 edits the events that exist and never
restructures the stream. Three rings, all same-size byte patches:

1. **All parameterized opcodes** as int/enum inspector cells (Instrument, Octave,
   Dynamics, the ADSR family, Fermata, Rest, noise clocks, pitch-bend family, LFO
   params, Repeat count …).
2. **Note velocity / key / duration** — velocity is its own byte; key and duration
   share the data byte (`key*19 + delta_idx`), so durations **snap to the 18-value
   delta-time table** (or edit freely 0–255 where the note already uses the
   explicit-duration byte form), with the nearest-storable honest tell (the palette
   split-fix precedent).
3. **Paired toggles as enums** (ReverbOn↔Off, SlurOn↔Off, FMod, Noise enable/disable)
   — same-shape opcode substitutions, structurally free.

Excluded (structural — the deferred **compile path**): insert/delete/move events,
EndBar/Coda placement, and changing a duration between table-form and explicit-byte
form (a ±1-byte size change hiding inside a "parameter"). The edit model is shaped like
the DAW plugin's authoring document (`fft_smd_authoring_model.h`: authored spans +
opcodes → compile → bytes) so structural verbs later add the compiler, not a redesign.
The compile path is *not* taken in v1 because re-emitting bytes must reproduce the
ROM's exact encoding choices (delta-table vs. explicit-byte is a degree of freedom) —
patch-in-place sidesteps that; a corpus round-trip guard is the gate for building it.

**Read model: the runtime decoder is the one decoder.** The editor decodes `feds.bin`
through `FedsBank`/`SMDOpcodes.decode_track` — the code path the sequencer plays —
with **byte offsets annotated per event** (a small decode extension) so the writer
knows where each edited param lives. This decision is forced by a discovery: the
Python extractor's `_FEDS_OPCODE_INFO` (`tools/parse_effect.py`) was stale — opcodes
RE'd long ago in `smd_opcodes.gd` (0xB4 `Noise_EnableAndClock`, 0xAD `Byte76_Adjust`,
0xA9 `FormulaSelector`, the 0xF0-family LFO machinery …) fell back to "Unknown_XX,
0 params", so every `feds.json` track containing a param-taking unknown **desyncs at
that byte** and decodes as garbage (proof: E004 track 2, a noise-sweep whoosh whose
JSON reads as chromatic notes). It also mislabels opcodes it does know (0xC4 "Release"
is `ADSR_SustainRate`; real Release is 0xC5). Playback was never affected — the
sequencer plays `feds.bin` with its own correct table. Therefore:

- **Slice 0 (prerequisite):** sync the extractor table to `smd_opcodes.gd`
  (names + param counts + the `_EXTRA_OPCODES` size-table entries), add a
  cross-language **drift guard** (a Python unittest that parses `smd_opcodes.gd` and
  asserts table agreement), regenerate every `E###/feds.json`.
- `feds.json` is demoted to a human-readable byproduct — never an editor input.
- With the correct table, exactly **one** unknown opcode survives the whole corpus:
  `0xBF` (2 occurrences). It renders as a read-only raw row ("unknown opcode —
  preserved verbatim"; the camera Param/Flags precedent). Ghidra follow-up, not a
  blocker.

**Surface: a track-lane strip, not a piano-roll.** *(The view-layer specifics in this
paragraph — the inspector-hosted micro-strip and the unqualified "loops draw folded" —
are **superseded by the 2026-08-11 amendment "FEDS pair surface: a tall lane panel with
per-loop wind/unwind" at the end of this file**, which the user rejected the first build
against. The MODEL / EDIT / SAVE and shared-tick-axis decisions here stand.)* A FEDS
track is typically 2–10
events — one or two notes wrapped in setup opcodes — so the DAW's piano-roll verticality
would ship with all its verbs dead (drag-to-pitch/move need structural editing). The
pair's 2 tracks stack on a shared tick ruler carrying a **tick→seconds tell**
(integrated tempo map, 120 BPM fallback); notes draw as duration bars (pitch/velocity
labeled), opcodes as chips in each track's opcode lane; loops draw **folded** (REPEAT
bracket + ×N badge). Select → edit through the F1 inspector kit, the studio's native
idiom. The DAW's presentation structs (`FFTSmdLaneNoteBlock`/`LaneCommandBlock`,
`fft_smd_inspector.h`) port ~1:1 as the projector's view model.

**Ghost pips (the cross-surface projection).** `SoundGhostProjector` additionally
projects the resolved pair's note onsets into ghost bars as read-only pips, loops
**unrolled** in the projection even though the editor keeps them folded. Scoped: the
selected trigger's ghost + every ghost resolving to the pair open in TIER-3 — so an
open pair lights up across the timeline next to the palette/screen/particle lanes.
One-way selection emphasis (editor → timeline); pips are never click targets. Inherits
the ghost's fire-0 resolution policy and frame-resolution honesty.

**Write path + saves.** Edits flow through `EffectEditSession.apply_edit` via a new
`SoundDefChannel` encoder writing bytes at their annotated offsets; a new
`invalidates_feds` result flag drives the page's ghost-cache eviction +
`SoundRenderQueue` re-render (the container-edit fan-out pattern). The Python writer
(`sound_def` in the registry) degenerates to a **section splice**, guarded by a
corpus-wide round-trip identity test. This build also **bridges this branch's three
unbridged save seams in one pass** — sound triggers, containers, sound_def — through
`patch_all` into the unified `studio_save` (the `EffectCameraSaver` template); palette
and screen stay on the authoring branch per the agreed merge order.

**Honesty.** The pair editor leads with provenance ("used by container C → N
triggers") and badges byte regions shared via flow-through (80 of 2,018 corpus tracks
are stub tracks without EndBar flowing into a neighbour — all 2–6 bytes): a tell,
never a block. Audition is a manual button on the `on_action` seam (the container
precedent) — auto-replay-on-edit rejected (spinbox drags machine-gun retriggers into
the known SPU voice-pool wobble); a debounced replay toggle is a possible additive
follow-on.

**Non-goal:** the TIER-1 leftover (empty sound channel can't be seeded via the gap
menu) stays out of scope unless it falls out free.

**Considered and rejected:** full piano-roll port in v1 (dead verbs at FEDS scale)
*(re-cast by the 2026-08-11 surface amendment below: what's rejected is **overlaying
event types** and **drag-to-pitch structural verbs**, not lane verticality per se — the
amendment adopts the piano-roll's real win, per-concern lanes + a real ruler)*;
compile-path re-emit in v1 (encoding-choice fidelity unproven — gate on the round-trip
guard); regenerated `feds.json` as the editor's read model (two decoders that must
agree forever — the exact failure mode just found); read-only-first staging (the #268
"felt useless" lesson).

## Amendment (2026-08-11): FEDS pair surface — a tall lane panel with per-loop wind/unwind

Grilling/domain-modeling session, informed by a `/deep-research` pass
(`docs/FEDS_PAIR_EDITOR_UI_RESEARCH.md`; workflow `wf_b73371e4-3b4`, 21 sources /
88 claims — 6 Tier-A confirmed, 19 Tier-B primary-doc-sourced). The user rejected the
first TIER-3 build's `FedsPairStrip` surface as *"useless … way too crammed … I don't
even think this is 'unwound'."* This amendment supersedes the **view-layer** clauses of
the 2026-08-11 TIER-3 amendment (the inspector-hosted micro-strip; the unqualified
"loops draw folded"). The **MODEL / EDIT / SAVE** layers — `FedsPairModel`,
`FedsPairProjector`, `SoundDefChannel`, `invalidates_feds`, the sound save bridge — are
**accepted and untouched**; this is a **VIEW-only** rebuild.

**Root cause.** The strip failed on two axes the DAW benchmark
(`fft-plugin/.../fft_smd_loop_roller.h`) gets right, then compounded both by living in a
reflowing `EffectKeyframeInspector` `GridContainer` cell that cannot guarantee width
(the same reflow that pushed content off-window in `291bcf638`): it **folded loops with
no way to see them unrolled**, and it **starved opcodes of vertical space** (34px, no
overflow band), so auto-width opcode labels overdrew at tick 0.

**The rebuilt surface.**

1. **A page-level lane panel, not an inspector cell.** Promote the view out of the
   reflowing grid into its own tall panel on the `EffectScoreTimeline` idiom (24px
   lanes, ~124px label gutter, a real detached ruler carrying the tick→seconds tell,
   collapsible sections). This is the root-cause fix and the "big and expressive like
   the main-section channels" look the user pointed at. The F1 inspector remains the
   edit surface (below); the panel is the **navigator + structure view**.

2. **Data-driven, one-lane-per-concern taxonomy.** One **note lane per track** plus one
   **opcode lane per opcode *kind* that actually occurs** in the pair (a tempo+instrument
   pair draws two opcode lanes, not a fixed grid of empty ones). This is Cakewalk's
   *"exactly one lane per unique event type … prevents overlapping parameters from
   cluttering"* [Tier A] — the named cure for the tick-0 overdraw — scaled to FEDS's
   2–10 events so no near-empty lanes are drawn.

3. **Loops fold by default, with a first-class per-loop wind/unwind toggle + hover-peek.**
   This is the correction to "loops draw folded, full stop." Each loop draws folded
   (REPEAT bracket + ×N badge) but carries an obvious, reversible **wind/unwind** control
   that unrolls it **in place** (the ×14 marches into 14 note bars), and **hovering the
   folded badge peeks its contents** without committing. Fold-default + reversible unroll
   + hover-peek is the three-domain convergence — Bitwig *Slice At Repeats* / LilyPond
   `\unfoldRepeats` / Visual-Studio outlining [Tier B, all primary docs]. Unrolling is
   **per-loop independent** (one loop wound, its sibling folded); a pair-wide "unwind all"
   is allowed as header sugar. The unrolled projection **reuses
   `SoundGhostProjector.pair_pips`** (bounded MAX_PIPS 96 / 30s) — the editor does not
   re-derive it.

4. **Typed chip as the opcode primitive; full detail on hover.** An opcode renders as a
   short fixed-width glyph/code in its lane (OpenMPT's `G05`-style token [Tier A]), with
   the **full opcode name + params in a hover tooltip** and in the inspector on select
   (VS hover-tooltip precedent [Tier B]). This replaces the auto-width `draw_string` that
   collided at tick 0.

5. **Note bars tell pitch by label, not by vertical position.** A note is a horizontal
   duration bar at a fixed lane y with its key + velocity labeled (width = duration). No
   vertical pitch ladder — a pitch axis buys nothing at 1–2 notes and would re-introduce
   the verticality this ADR rejects. What's rejected about the piano-roll is **overlaying
   event types** and **drag-to-pitch structural verbs**, *not* per-concern lanes + a real
   ruler — those are adopted.

6. **Lane navigates, F1 inspector edits.** Clicking a note bar / opcode chip selects it
   and routes to the existing F1 inspector rows (the studio-native editor kit) for the
   value edit — no new event-list widget. This preserves the accepted select→edit seam
   and keeps the rebuild VIEW-only; a typed, scannable event-list (Logic/Cubase idiom
   [Tier B]) is a **possible additive follow-on, not v1**. Reuse the `EffectScoreTimeline`
   hit-test guard and **do not grow the `_nav` back-stack on same-pair re-selection**.

7. **No per-lane solo/mute.** Unlike `EffectScoreTimeline`, a FEDS concern-lane is not an
   audio channel that can be soloed, and per-track audition muting is EDIT/engine surface
   outside this VIEW-only scope, so the gutter carries the lane **label only**. Auditioning
   stays the single manual button on the `on_action` seam.

The honesty furniture from the TIER-3 amendment is retained: the panel leads with
**provenance** ("used by container C → N triggers") and badges **flow-through stub-track**
byte regions as a tell, not a block.

**Considered and rejected (this amendment):** keeping the strip inside a widened inspector
cell (still lives with the reflowing grid column that caused `291bcf638`); a fixed
full-taxonomy lane grid (tallest, mostly-empty at FEDS scale — the FamiTracker
expand-on-demand idiom exists to avoid it); ~~unrolled-by-default (a large loop floods the
lane on open; fold-default + visible toggle answers "not even unwound" without the noise)~~
**— REVERSED 2026-08-19d, see that amendment: the flood is bounded by MAX_UNROLL_COPIES,
and the user wants the pair to open showing what it actually does**;
a vertical pitch axis (dead at 1–2 notes; edges into the rejected verticality); a new typed
event-list as a co-equal v1 edit surface (blows the VIEW-only scope; the F1 inspector
already is a typed field-list).

---

## Amendment (2026-08-11) — the lane panel PROJECTS onto the shared frame axis (inspection, not its own tick ruler)

The 2026-08-11 lane-panel amendment above stood the surface up on a **self-contained
tick axis** (`ppt = usable / total_ticks`), faithful to this ADR's original guard —
*the FEDS editor lives on its own tick/tempo axis, NOT the effect-frame ruler.* On review
the user reframed the panel's role: it is *"a good place to look at what's happening — but
maybe not the best for authoring"* — an **inspection surface** first. As an inspection
surface it must **line up with the effect timeline below it** (where the boom/flash/shake
land), which the self-contained axis cannot do. This amendment retargets the panel's axis;
the taxonomy, typed chips, fold/wind, provenance, and the *"lane navigates, F1 inspector
edits"* seam are all **retained**.

**This does not flatten the FEDS clock onto the frame ruler in the sense this ADR
rejected.** The rejected thing was *composing* (authoring) FEDS notes on the frame ruler —
placing an event by dragging it to a frame, where the tempo map would lie. Here **no edit
happens on the axis**: every value edit stays numeric in the F1 inspector (the retained
select→edit seam). The panel merely *projects* onto the frame axis — exactly what the
sanctioned **ghost bar / ghost pips** already do — so it is a wider, always-visible member
of the same projection family, not a new authoring ruler. The tick/tempo axis **survives**
as the ruler's label (the "tick · seconds" tell) and as the numeric edit unit.

**The retarget.**

1. **Adopt the timeline's shared `TimelineAxis` OBJECT** (the pattern `FramesBar` already
   uses via `bind_timeline`). One `(base_x, pixels_per_frame, scroll_x)` for the whole
   band, so panel and timeline **cannot drift**, and zoom/pan/playhead are unified for free
   — zooming the panel zooms the timeline, by design (the panel is an *extension* of the
   timeline, not an independent viewport). The panel never caches the three params
   (`load_score` resets them); it re-reads the object each layout.

2. **Anchor the pair's tick-0 to a representative trigger's fire frame.** A pair is shared
   by many triggers, so the panel picks one anchor: the trigger **drilled from** (`_nav`
   origin span) → else the **selected** resolving trigger (live re-anchor on selection) →
   else the **first firing** trigger resolving to the pair (reuse `_compute_pips`
   scoping) → else an **orphan** pair anchors at frame 0 with a visible tell. This is the
   same *first-fire representative* honesty the ghost pips already use for multi-fire
   containers.

3. **Tick → frame is tempo-integrated, one number shared with the pips.**
   `frame = fire + round(seconds_at(tick) × EFFECT_FPS)`, where `seconds_at` is the SAME
   per-track tempo integrator the ghost pips use (`FedsPairModel` carries per-event
   `seconds` so panel chips and pips are driven off one value and cannot disagree under an
   inline `TEMPO`). In the common no-tempo pair this equals the old linear share; it only
   diverges — correctly — when a `TEMPO` opcode is present. The linear share survives only
   as the ruler's seconds *label*.

4. **Folded collapses DRAWING, not TIME (always exact).** Because the pips are already
   unrolled on the shared axis, a folded loop must still span its **full N-pass frame
   width** (the envelope of its pips) so the panel and the pips agree; folding only hides
   the repeated *bodies* (bracket + ×N badge + hover-peek, optional faint pass-onset
   ticks), and unwinding *fills* that same span with ghost-copy chips landing on the pips.
   `_expand_track` therefore always applies the full `(count-1)×body_len` downstream shift
   regardless of fold state; the fold flag gates only whether the copies are drawn. The
   existing `truncated` / 30 s-cap logic still bounds a runaway loop. (This **supersedes**
   the prior amendment's *"a folded view only aligns approximately"* framing — it is exact,
   just visually collapsed.)

5. **Coincident chips wrap to rows at their TRUE x** (replacing the `next_free_x`
   push-right, which falsified a chip's tick): each chip keeps its axis-derived x; chips
   whose fixed-width rects would overlap drop into the lowest free row (greedy first-fit in
   tick/byte order), and the kind-lane grows by `rows × (CHIP_H+gap)`. Unbounded rows
   (FEDS scale self-limits); note bars stay single-row until real data shows overlap.

6. **Playhead is draw-only at v1.** The panel is in frame space, so it draws the main
   playhead at `axis.frame_to_x(get_playhead())` and redraws on `playhead_changed`. Panel
   ruler clicks do **not** seek at v1 (VIEW-only scope); routing them through
   `seek_requested` is a cheap follow-on.

**Considered and rejected (this amendment):** keeping the self-contained tick axis and
aligning only weakly (a projected playhead marker over an unaligned chip grid — fails the
"line up with the timeline below" ask); an **own axis mirrored** on `axis_changed` (buys
independent panel zoom at the cost of drift risk and wiring — but the panel is an extension
of the timeline, so independent zoom is a non-goal); **compressed-folded / approximate**
alignment (the pips are already unrolled, so folded chips would not sit over their own pips
— F2's time-reserved fold keeps them consistent); a linear tick→frame share (disagrees with
the tempo-integrated pips under an inline `TEMPO`); showing a second **frame** ruler on the
panel (pure duplication of the frames bar directly below — the panel's ruler earns its keep
only by showing the FEDS-native tick·seconds).

## Amendment (2026-08-12) — a per-frame orientation grid, timeline-aligned

The frame-axis retarget above shipped (feat `e8abcc000`), but the panel kept drawing only
its **five tick-quarter marks** as its sole vertical reference. In practice that left a wide
empty field where chips float with almost nothing to peg them to a time position — *"the
'sound' timeline part has no vertical bars. it's difficult to be oriented."* The retarget
made the fix trivial and coherent: the panel is now in frame space, so it can show the
**same per-frame grid the score draws directly below it**.

1. **Vertical bars = a per-frame grid on the shared axis, not more tick marks.** Reuse the
   score's `_ruler_step(axis)` spacing and draw at `axis.frame_to_x(f)` for
   `f = 0, step, 2·step…`. The lines fall at round frames and therefore **coincide
   pixel-for-pixel** with `EffectScoreTimeline._draw_grid` below (same axis, same
   `GUTTER_W`, same base_x) — a chip in the panel sits above the same column in the score.
   This is the whole point of sharing the axis, now made visible. (Rejected: denser
   *tick-quarter* subdivisions — rhythmic but panel-local, they would **not** coincide with
   the score's frame grid, so they buy no cross-lane orientation.)

2. **The tick ruler stays the musical tell; its full-height lines retire.** The
   `tick · seconds` labels remain in the ruler band (with short *in-band* marks only) — that
   FEDS-native mapping is why the panel's ruler earns its keep (see the prior amendment's
   last rejection). But the frame grid is now the **sole full-height line system**, so the
   old full-height tick-quarter lines go away rather than compete with it.

3. **The panel grid is a touch stronger than the score's** (`COL_GRID` ≈ `0.12` α vs the
   score's `0.05`) — a plain const mirroring `EffectScoreTimeline.COL_GRID`, not a tunable.
   Position parity is about *x*, not α, so a more legible panel grid still aligns perfectly.
   The score's own `0.05` grid arguably reads as too faint as well, but that is a separate
   surface and out of scope here.

4. **Lines run continuously top-to-bottom, crossing the section-header rows.** Orientation
   means tracking one column unbroken from the ruler down to the last lane, so the grid
   draws **above** the lane/section backgrounds and **below** the note bars / chips /
   brackets / playhead (which stay crisp on top). It clips to `x ≥ GUTTER_W` (never over the
   label gutter) and spans from below the ruler band to `content_h`.

**Mechanics (follow, not fresh choices):** the grid is computed in the **pure `layout()`**
as `lay["grid"]` (mirroring `lay["ruler"]`) so it is guard-testable off the pixels, and it
re-projects for free on zoom/pan because the panel already redraws on `axis_changed`. The
build is a `/tdd` follow-on whose RED guard asserts a grid line at `axis.frame_to_x(f)` for
each stepped frame within the panel width, and none at `x < GUTTER_W`.

## Amendment (2026-08-12) — opcode-param honesty: author labels, signed display, and an empirical usage range

The TIER-3 F1 inspector shipped, but it only *curates* ~15 opcodes; every other
opcode param falls to a bare raw byte with a generic `"%s p%d"` fallback label and
no sense of scale — *"there are still some really confusing inputs."* Two examples
pin it: `PitchBendRel → 2` (*"what does this mean semantically? is 2 a lot?"*) and
`Portamento_Init p2 → 23` (*"is this milliseconds? we need more units."*). The
diagnosis is mostly a **content** gap in `FedsParamSemantics.descriptor()` — but it
exposed three **structural** gaps and one conceptual one, and the conceptual one is
the load-bearing decision here: **when a param has no honest physical unit, the
anti-technobabble answer is not a fabricated unit — it is what real effects actually
do with that byte.**

1. **Author labels, confident-else-honest-generic — kill every `p2`/`p3`.** Each
   uncurated param gets a real semantic label where the RE (`smd_opcodes.gd`
   comments + `research/`) supports one ("Glide target", "Glide rate", "LFO
   depth"); where it does not, an honest **descriptive generic** that names *what
   the byte touches* ("LFO sub-slot param 2", "(unmapped raw byte)") — never the
   opaque `p2`, and never a confident-sounding label we cannot back. Best-guess
   semantics across the whole LFO family are **rejected** (technobabble-in-reverse
   — false precision is worse than an honest generic; the [empirical usage
   range](#) below carries the scale a name can't).

2. **A signed byte is a CELL-LOCAL display transform, not a channel concern.**
   Several params are stored signed (`sb` in the opcode comments: `PitchBendRel`,
   `Detune`, `AddPitchBend`, `Dynamics_Add`, `Byte76_Adjust`). The decoder hands
   the projector **raw unsigned bytes** (`decode_track` → `params.append(data[pos])`),
   and `SoundDefChannel.apply_raw`'s `"byte"` kind **rejects** anything outside
   0–255 — so a small negative bend reads as `254`, a lie. `_int_cell`
   **sign-extends the seed** (254 → −2) and **masks the fanned value** (−2 → 254),
   composing with the author-unit affine (sign-extend happens *before* the scale).
   The byte writer's 0–255 contract is **unchanged** — signedness is purely an
   authoring-display transform, exactly as [CameraUnits](#) keeps the writer seeing
   only raw. **Correction to the frame-axis handoff's premise:** two's-complement is
   *piecewise*, not the linear `bias` affine — there is no constant `bias` mapping
   both `127→+127` and `128→−128`, so this is real modular code, not a reuse of the
   screen signed-byte lesson. Rejected: a channel-level `"sbyte"` kind — it changes
   the write contract and adds a field_ref kind for a display-only concern.

3. **A genuine 16-bit param is one editor, via an atomic word write.**
   `0xD3 PitchBend_Add_16bit`'s two bytes are one signed 16-bit value
   (`high<<8 | low`) — showing them as two byte cells is the *purest* case of the
   byte-thinking the user objects to. It becomes a single `s16` cell backed by a new
   `"word"`/`"s16"` field_ref kind on `SoundDefChannel` that writes both bytes in one
   `apply_raw` call: **one field_ref, one undo entry, one honest number.** This is
   the *one* justified new channel kind — the storage genuinely *is* two bytes wide
   (distinct from #2, which is display-only). Rejected: two labeled byte cells (still
   asks the author to think in bytes).

4. **Empirical usage range — the honest substitute for a physical unit.** Where a
   param has no fully-explaining unit or enum, ground it in **what shipped FFT
   effects actually do**: a generated, drift-guarded `feds_param_stats.json` giving
   per `(opcode, param_index)` a **signed-aware min/max/median/mode/n** scanned
   across every effect FEDS blob. The cell surfaces it as an **inline dim hint**
   ("typical −8…+8 · median 0 · n=47") + a fuller **tooltip**, plus an
   **out-of-corpus tell** (reusing the [quantize](#)-tell pattern) that fires when
   the current/typed value falls outside the observed range — *"no shipped effect
   uses a value this high."* This is the sharpest possible answer to "is 2 a lot?":
   it does not merely show a range, it warns when the author leaves the envelope of
   real data — and it is honest (real data, never an invented unit). A **physical**
   unit (semitones/cents for the pitch/bend/portamento family) ships **only** if
   pinned by static analysis + oracle validation (per
   `re-conclusions-static-rooted-dynamic-validated`); otherwise the family ships
   label + range, which already answers the scale question. `Portamento_Init`'s
   `rate` is provably a **per-tick pitch delta, NOT milliseconds** — and no honest
   ms is derivable (total glide time needs runtime starting pitch), so it ships as a
   labeled rate + its corpus range. Rejected: a fabricated ms/cents unit for a rate;
   showing the corpus range where an enum/real unit already grounds the value
   (redundant noise).

**Mechanics (follow, not fresh choices).** The stats generator sits on the existing
FEDS-drift substrate (`test_feds_opcode_drift`), and the **single generated table is
the shared source for stats AND signedness** — the Python producer and the GDScript
descriptor read the same file, so they cannot disagree; the **hand-authored
signed-param list** (from the `smd_opcodes` RE) is the one input the generator
consumes. Live in-editor computation is **rejected**: it sees only the open
effect(s) (no global corpus), pays a per-session cost, and forces a duplicate signed
list into GDScript. The build is a docs-first `/tdd` follow-on: stats generator +
table → `s8` display path / 16-bit word write → descriptor content + range UI →
[chip-hover](#) parity (`param_summary` speaks the same labels/units as the cells,
range detail staying in the inspector) → headful verify on E004/E317. The pitch-unit
research pass gates **only** the semitone/cent unit; labels, empirical range, signed
display, and the 16-bit editor ship regardless.

## Amendment (2026-08-12) — click lands on the code, opcode-honesty verdicts, and per-track energy

Three authorship complaints about the shipped FEDS pair editor, settled together
because they collapse into **one coherent surface**: the pair panel becomes an
*honest, land-deep* view where the opcode chips, their verdicts, and a per-track
energy band all ride the same frame axis. The RE behind complaint 2 is
static-rooted (cited below) and dynamically validated by complaint 3's energy
render — the two were suspected to be one surface, and they are.

### 1. Clicking a sound event lands on the code, not an empty overview

Today a trigger click is a 4-click **step-in drill** (`_set_root` span →
`SoundTriggerProjector` "→ container N" → `SoundContainerProjector` "→ Sound bank
entry N" → a pair that opens with `_selected = {}`, `FedsPairLanePanel.gd:108`),
landing on an overview the author must click *again* to leave — *"I just want to
skip straight to the first sound's FEDS-code stream… start there and step back as
needed, as opposed to step in."* Invert it: **seed the nav stack deep**
(`[span → container → pair]`) **and auto-select the pair's first event** so the
inspector/panel open **on the code**. The container and trigger stay as
**breadcrumb crumbs** — the `_navigate_to` truncate-to-ancestor primitive
(`EffectStudioPage.gd:1009`) already makes them one click to *step back*, so
nothing is hidden; the author just starts at the bottom. "First event" is
**track A's first event, period** — fully predictable, **no stub fallthrough**
(landing on a silent-stub track A is acceptable; the author reads down or steps to
B). Fallback: a genuinely empty track A shows the overview. Rejected: **collapsing
the intermediate levels** (dropping container/trigger from the back-stack — loses
the parent inspection surfaces for no gain now that they're crumbs); **auto-select
"first *audible* event"** (skips silent stubs/pre-arm, but the author preferred a
predictable "always track A" over a cleverer landing that varies per effect);
**falling through to track B when A is a stub** (the same predictability call).

### 2. An opcode-honesty surface — because the RE answers "why is this here?"

*"Lots of opcodes are effectively no-ops… sometimes even a silent track DOES
something… why are they there — cruft? why is it a PAIR — left/right ear?"* The RE
sweep (static, cited; validated dynamically by §3 + the headful pass):

- **A "pair" is two *layered SPU voices*, not L/R ears.** The header is pair-major
  (`pair_count_plus1 = channels/2 + 1`); `play_feds_pair`
  (`effect_sound/play_sound.gd:406-570`) `allocate_pair`s **two consecutive slots**
  → **two distinct SPU voices** (`pool.voice_for_slot(slot_idx)`), binds `slot_a↔ch_a`
  and `slot_b↔ch_b`, and runs both streams concurrently. **Pan is a separate
  per-voice opcode** (`0xE8`), so the two tracks are two simultaneous *sounds*
  layered, not stereo channels.
- **No opcode reaches across to the sibling track's voice.** Each opcode writes its
  **own** channel/slot state; a silent-driver track has all voice-writes **gated**
  (`dispatcher.gd` `voice_writes := not channel.is_silent_driver`). `Tempo 0xA0` —
  the one entity-global op — is **not even implemented on the effect path** (music
  only). So the naïve "a silent track stomps the other track's state" reading is
  **refuted**.
- **But "a silent track DOES something" is nonetheless TRUE — via stub-flow, not
  cross-voice.** A track without `EndBar (0x90)` has no boundary, so its bytes
  **flow into the next track's stream** (`feds_bank.gd::get_track_bytes_from`). A
  "silent stub" isn't a separate inert voice — it's the *preamble* of the track it
  flows into.
- **The no-ops are a deliberate "pre-arm" idiom, not cruft.** Real example, Cure_4
  track A: `AC 0E` (silent instrument) → `C2 34` ADSR → `D4 60 0F` portamento →
  **Note** → `AC 83` (switch to an audible instrument) → audible Notes. The silent
  instrument + param opcodes **stage ADSR/pitch/LFO state** the first audible note
  inherits. Load-bearing.

So the deliverable is the arc's honest-editor pattern (cf. the emitter
Live/Inactive/Dead relevance oracle): a per-opcode **verdict** with a fixed
vocabulary — **Live** (its effect is heard), **Pre-arm** (staged before the first
note; not heard *then* but load-bearing for an upcoming note), **Inert** (never
observed: a true NOP `0x82`/`0x9B`, or a voice-write on a stub track that never
sounds), **Structural** (flow/timing — `EndBar`/`Loop`/`Repeat`/`Rest`) — plus a
**track-level** label, **Sounding** vs **Silent stub → flows into B**. Verdicts are
computed by a **position + opcode-kind classifier** (v1: NOP→Inert, flow→Structural,
voice-write before first note→Pre-arm, at/after first note→Live; stub detected by a
missing `EndBar`) — **no value-tracking**, honest about its limits, with §3's energy
band as the empirical check that promotes an inferred verdict to a confirmed one.
Verdicts render **on the pair-panel chips** (verdict = tint/glyph) **+ the track
header** (the Sounding/Stub label); the *reason* ("pre-arms the voice for the note
at tick X") rides the **existing chip-hover label**, aligned directly above the
energy band that corroborates it. Rejected: a **full voice-state simulator** for v1
(would also catch redundant re-sets / overwritten-before-read, but needs a "which
instrument ids are genuinely silent" corpus we don't have — deferred, the energy
band covers the empirical gap); verdicts **in the F1 inspector** (one event at a
time — loses the at-a-glance map the author asked for); treating **pre-arm as
cruft** (the RE shows it is intent).

### 3. Per-track energy, inline under each lane — and it grounds §2

*"A bigger energy diagram up with the FEDS pairs — maybe one for each part of the
pair?"* Energy today is one array **per resolved sound_id, both tracks mixed**
(`SoundGhostProjector.render_pair`), drawn only as a ~20px swell in the timeline
ghost. Give each track its **own** energy band **inline under its lane, on the
shared frame axis**, so the swell sits **directly beneath the opcodes that cause
it** — which is exactly why it *doubles as §2's ground truth*: a flat band means
those opcodes really are inert here; a swell means they're live. Per-track energy
needs an **isolated render** (⚠️ *not* an L/R split — L/R is pan, the two tracks are
two voices): a `single_track` flag on `play_feds_pair` that **empties the sibling
track's events** before binding, so only the target voice sounds (reverb tail then
reflects that track alone — correct for intrinsic energy). Both bands use **shared
normalization** — scaled by the **pair's** peak, not each track's own — so a silent
stub reads **flat** and the carrying track reads **tall**, answering "which track is
making the sound?" at a glance. Cost: two isolated renders per pair (A-alone,
B-alone) through the already chunked+cached `SoundRenderQueue`. Rejected:
**splitting the stereo L/R output** (the explorer's suggestion — wrong, that's pan);
**one combined tall strip only** (doesn't answer per-part); **per-track independent
normalization** (each band fills its own height, hiding that A is far quieter
than B).

**Mechanics (follow, not fresh choices):** §1 is a nav-seed + auto-select change on
`EffectStudioPage` (no new primitive — `_navigate_to` already truncates to an
ancestor). §2's verdicts compute in a **pure** classifier (guard-testable off the
decoded stream, like `FedsParamSemantics`) and paint through the panel's existing
chip/track-header draw + chip-hover label. §3 reuses the `SoundGhostProjector` /
`SoundRenderQueue` render+RMS path behind the `single_track` flag and the shared-peak
normalize. The build is a `/tdd` follow-on on the existing `FedsPairEditorTest` +
headful `FedsPairEditorAcceptanceTest` (E004 ×14 / E317) pattern; the headful pass on
**E001 (CURE) / E004 / E317** is the dynamic close (`re-conclusions-static-rooted-dynamic-validated`)
— the energy bands must corroborate the Pre-arm/Inert/Stub verdicts on real effects.

## Amendment (2026-08-12) — the empirical usage range, conditioned on the active instrument

The just-shipped [empirical usage range](#amendment-2026-08-12--opcode-param-honesty-author-labels-signed-display-and-an-empirical-usage-range)
reports **one global `min/max/median/mode/n` per `(opcode, param_index)`** across the
whole corpus. But — *"many of these fields are conditional on what instrument is being
used"* — a pitch/bend/portamento byte's typical usage differs sharply by **active
instrument** (`0xAC`), so a single global range can mislead: it answers "is 2 a lot?"
with the average over *all* wavesets when the author is composing under *one*. Add a
**second, instrument-conditional** range and show both.

**The framing is the load-bearing decision, and it is deliberately narrow: the
per-instrument range is a _correlation_, not a claim about meaning.** The second line
means *"what shipped effects that were using this instrument did with this byte"* — a
conditional empirical observation — **NOT** that the SPU *interprets* the byte
instrument-dependently. We have not RE-validated an instrument-dependent interpretation
for these opcodes on the oracle, and `re-conclusions-static-rooted-dynamic-validated`
forbids asserting causation we haven't proven. (A real instrument-dependent
interpretation — e.g. the pitch table's per-waveset base note making a bend's audible
effect genuinely relative — *may* exist; if it is ever statically rooted + oracle-validated,
a causal note can be added then. Until then the wording stays correlational.) This keeps
the feature squarely inside the amendment's anti-technobabble ethos: honest data, never
an invented relationship.

**Active instrument = a runtime fact, not a choice.** Instrument state is **per-track
channel state** (`sequencer.gd` `channel.instrument_idx = idx`; each `TrackState` owns
its own), so the active instrument is **the last `0xAC` at an index `<` the event's, in
the _same_ track** — it never crosses the pair's two layered voices. The projector reads
this straight off the decoded `track.commands`; there is no cross-track scope to decide.

1. **A param's range is bucketed both ways; the cell can show two lines.** Alongside the
   global entry, the generated table carries a per-instrument bucket, and the cell
   surfaces global (the baseline) plus, when an instrument is active, an
   instrument-conditional line marked as the sharper answer
   (`typical (all): 0…255 · median 211 · n=3123` / `with Timpani (64): 2…40 · median 8 · n=47`).
   The instrument line is **always shown when the bucket has ≥1 sample** — the author
   asked to *see* the conditional data — but its **wording is n-adaptive** so a single
   sample is never dressed up as a range: `n=1 → "seen once at 8"`, `n≥2 → "A…B · median
   M · n=N"`. The count `n` is itself the confidence caveat, shown inline.

2. **The three cell states are explicit and distinct.** (1) *No `0xAC` precedes* → the
   global line only (no per-instrument line, no note — there is nothing to condition on).
   (2) *Instrument active but the corpus has **zero** samples of this param under it* —
   real and common for the sparse opcodes (`0xD6 Detune`'s entire corpus is one
   instrument, so nearly every other active instrument has zero Detune samples) → a
   distinct informational line **`none with Timpani (64)`**, the honest counterpart to
   the n≥1 case (*"you are in unprecedented territory for this instrument"*), with the
   tell falling back to global. (3) *Instrument active, n≥1* → the two-line form above.
   States 1 and 2 must not look identical — "no instrument set" and "this instrument
   never used this way" are different facts.

3. **The out-of-corpus tell is gated, and it distinguishes _which_ envelope was left.**
   The amber tell now has two envelopes to choose between, and they mean different things:
   - **Outside the _global_ envelope** → the full **"outside corpus"** tell (unchanged):
     *no shipped effect anywhere uses a value this extreme.*
   - **Inside global but outside the _instrument_ envelope** → a **distinct, milder** tell:
     *`unusual for Timpani · Timpani uses 2…40`* — honest that the value **is** precedented
     in general, just atypical for this instrument. Reusing the loud "outside corpus"
     styling here would be a lie (it implies *no* effect uses the value when effects do).
   - The instrument envelope may drive its tell **only when its bucket has `n ≥ 8`** —
     below that it is too flimsy to sound an alarm (a single-sample bucket `[8]` would
     flag every value but 8), so the tell reverts to the global envelope. `T = 8`
     comfortably clears the `n=1…3` noise tail while the dense flagship opcodes
     (Portamento `n≈490` per instrument, AddPitchBend) clear it easily.
   - **Precedence:** outside-global (the stronger, more universal signal) wins over an
     instrument-only miss.

4. **The generated table stays the single source: emit-for-all, show-selectively.** The
   generator adds `by_instrument: {"<id>": {min,max,median,mode,n}}` to **every** stats
   entry (reusing `_summarize`), exactly as the **global** stats already emit for all
   ~60 control-param keys and let the UI's `_attach_range` gate show them only where no
   unit/enum grounds the value. This is ~+150 KB (parsed once per session via
   `FileAccess` — trivial), of which the unit/enum opcodes' buckets are never read — the
   price of **not** introducing a second "which opcodes show a range" list in the
   generator, which is precisely the py/gd drift trap the parent amendment fought (stale
   `feds.json`). One source of truth beats a lean file with a divergence risk. The
   drift guard gains **one hand-enumerated low-n `(opcode, param, instrument)` oracle
   triple** (the per-instrument analogue of the existing `0xD3 n=15` global oracle).

Rejected: a **causal** framing ("the instrument changes the byte's meaning") — not
RE-validated, would violate static-rooted/dynamic-validated; **suppressing** small-n
instrument buckets from display (the author asked to see the conditional data — hide only
the *tell*, never the line); reusing the **loud** "outside corpus" tell for an
instrument-only miss (overstates it); letting a **tiny bucket drive the tell** (`n<8`
noise); a **cross-track** instrument scope (the runtime is strictly per-track); a **lean
range-only** table (a second drift-prone list); putting the per-instrument detail in the
**chip-hover** `param_summary` (it stays global — the range detail lives in the inspector,
per the parent amendment's rule).

**Mechanics (follow, not fresh choices):** the generator's `_collect`/`_iter_events`
already iterate track-scoped, so tracking a `current_instrument` (reset to `None` at each
track start, set on `0xAC`) and emitting the second bucket is local. `FedsParamStats.of`
gains an instrument-conditional lookup; `FedsParamSemantics.usage_range` grows an optional
`instrument_id`; `FedsPairProjector` resolves the active instrument by scanning the
decoded track back from the selected `event_index` and attaches both ranges to the cell;
`EffectKeyframeInspector._int_cell`'s `refresh_range` closure renders the second line and
applies the gated/distinct tell. `storage_type` is instrument-independent — untouched.
The build is a `/tdd` follow-on on `FedsPairEditorTest` + headful `FedsPairEditorAcceptanceTest`
+ the python drift guards; the headful close picks an event whose active instrument has a
sharply different conditional range and reads both lines + the tell by eye (the complaint
is inspector *text*).

## Amendment (2026-08-12) — the opcode verdict tells the truth about silence: a two-axis static classifier + a hatch

The shipped verdict (amendment above, §2) is **position-only** — NOP→Inert,
flow→Structural, voice-write-before-first-note→Pre-arm, else→Live, notes always Live.
On **E001 (CURE) track A** it tags **19 events Live** while the track is **silent**: its
active instrument is `#1 "Empty/Silent"`, every note plays that empty sample, and the
isolated energy render peaks at **0.0117** (≈ floor). A verdict that says "Live" over a
provably-silent track **lies**. The prior amendment's escape hatch — "the energy band
promotes an inferred verdict to a confirmed one" — was never a *classification* input; it
was decoration. This amendment makes the classifier **honest by theory**: it reads the
stream, tracks per-voice state, and **proves** silence rather than guessing from position.

The fix is a **two-axis, per-event verdict**, and — the load-bearing constraint — it stays
**static**: every input is knowable from the decoded opcode stream. **No render is in the
decision.**

1. **Axis a — is the active instrument audible?** Muteness is a property of the **running
   `0xAC`** (set-instrument) at each event, **not** the track. The corpus forces this:
   **44.3 %** of tracks (894 / 2018) fire `0xAC` **two or more times** — mid-stream
   instrument switching (the Cure pre-arm idiom `AC 0E … Note … AC 83 … Note`) is nearly
   half the corpus, so a per-track instrument would mislabel every note under whichever
   `0xAC` it didn't pick. The classifier carries a **running instrument** per voice (reset
   at track start, updated on each `0xAC`).

2. **Axis b — is the opcode per-voice or global?** A confirmed **global** opcode matters
   even to a muted voice, so it is **never** hatched. The confirmed set is the **noise
   clock**: `0xB4 Noise_EnableAndClock` (writes `SPUCNT[8-13]`, the single shared SPU
   noise-frequency register) and `0xB5 Noise_ClockAdd` (re-asserts it). These render
   **`Live-by-proxy`** — "makes no sound *here*, colours another voice." **Default for
   unconfirmed opcodes is per-voice** (hatchable when muted); completing the per-opcode
   scope tag is a **deferred RE follow-on** (table at `smd_opcodes.gd::OPCODE_INFO`,
   handlers at `runtime/shared/opcodes/*.gd`). The allowlist is the **sole** guard here —
   the per-track energy band (prior §3) renders each track *in isolation*, so a
   *cross-track* global effect is invisible to it; the band **cannot** backstop a
   global-scope mistake. Keep the allowlist small and confirmed.

3. **The new verdict — `Muted` — is two-level, and only notes carry it.** A **note**
   produces sound directly; a voice-write only *stages* state a later note (possibly under
   a different, audible instrument) may inherit. So muteness downgrades **notes**, never
   voice-writes:
   - **Track-level:** a track where **no `0xAC` ever resolves to an audible instrument** is
     **wholly `Muted`** — every event hatched (the deterministic E001 fix). *Exception:* a
     `Live-by-proxy` global opcode inside it stays un-hatched.
   - **Event-level** inside a sounding track: a **note** whose running instrument is a
     **trusted-empty** instrument is `Muted`. Voice-writes keep their `Pre-arm`/`Live`
     verdict — they may feed a later audible note.

4. **The silent set is two tiers — hatch only what we can *prove*.** The `· Silence`
   instruments split by provenance (Lesson 3): ~62 **Empty·Silence** (trusted zero output)
   vs **9 Inaudible / Nearly-Inaudible Clip** (faint but **nonzero**). A note under a
   **trusted Empty** is `Muted` → **hard hatch**. A note under a **gray-zone Clip** is
   **not** provably silent → **not hatched**; it gets a softer **"faint"** tell (`≈`). We
   never assert a silence we can't prove — and a one-note render can lie both ways (Lesson
   3), which is the other reason not to lean on it.

5. **Noise mode voids the empty-instrument premise — and it, too, is static.** `0xB4`/`0xB6`
   **arm noise on the voice**, rerouting it off its sample onto the noise generator; `0xB7`
   clears it. A note on a **noise-armed** voice is **audible even under an empty
   instrument**. So the classifier carries a second per-voice fact — **noise-armed?** — and
   the `Muted` note predicate is **instrument-empty AND NOT-noise-armed**. Two facts per
   voice (running instrument, noise-armed) are the entire "theory"; nothing else is needed
   to be correct about silence.

6. **Static-authoritative; the band is corroboration, not a vote.** The hatch is decided
   *entirely* by 1–5 off the stream. The per-track energy band stays purely a
   **corroborating picture** under the panel — it lets the author eyeball that the theory
   holds and would surface a *bug* in our model (a hatched event the band shows sounding),
   but it **never** hides or forces a hatch. One **display-honesty** fix rides along: the
   shared-normalize (prior §3) dressed E001 track A's noise-floor up to **0.25**, so a
   genuinely-silent track *looked* like a swell. Add an absolute **"silent in isolation"**
   marker keyed to the **raw, un-normalized** render (E001 track A raw peak 0.0117) so the
   picture stops lying — but this is **display only**, never wired back into the verdict.

7. **The hatch UX.** A proven-`Muted` chip/note bar keeps its hue and gets **45° diagonal
   hatch lines** over it (the recognisable "struck out / does nothing" read), distinct from
   the existing plain-dim **Inert** tint. A gray-zone **faint** note is **not** hatched — a
   **dotted, dimmed** outline plus a small `≈`. (No spacer hatch exists on this branch —
   that pattern lives on `feature/effect-studio-authoring`; here a new `_draw_hatch` =
   clipped repeated `draw_line`, alongside the existing `_stroke_dashed` / terminator
   dim-ink idioms in `EffectScoreTimeline` / `FedsPairLanePanel`.)

Rejected: **per-track muteness** (the 44.3 % mid-stream-switch corpus refutes it);
downgrading **voice-writes** by muteness (they stage state for later audible notes); folding
`Muted` into **`Inert`** (conflates a true NOP with a note on a silent instrument —
different honesty stories, and `Inert` is not hatched today); a single **all-`· Silence`**
tier (over-claims silence on the 9 faint clips — the opposite lie); the **band as a veto**
on the hatch (considered and dropped — noise mode, the one case a veto would catch, is
*statically* knowable, and a render both wobbles ±1–2 frames and can itself lie via
shared-normalize); a **third "uncertain" verdict** for unknown-scope opcodes (the per-voice
default + small allowlist is enough; the extra visual state isn't earned); a **causal**
reading of noise mode ("silence depends on the render") — it depends on the *stream*.

**Mechanics (follow, not fresh choices):** `FedsOpcodeVerdicts.gd` (pure) gains the two
per-voice state walks (running `0xAC`, noise-armed) and the `Muted` / `Live-by-proxy`
branches; `FedsPairModel.gd` threads the per-event active instrument the classifier needs;
`FedsInstrumentNames.gd` grows the trusted-empty vs gray-zone-clip split (category parse on
`· Silence` + flavour); `FedsPairLanePanel.gd` adds `_draw_hatch` + the faint marker and
paints them through the existing verdict-tint path; the absolute "silent in isolation"
marker is a display-only addition to `SoundGhostProjector.gd`'s band (raw peak alongside the
shared-normalized envelope). The build is a `/tdd` follow-on on `FedsPairEditorTest` +
headful `FedsPairEditorAcceptanceTest` on **E001 (CURE anchor) / E004 / E317** — the dynamic
close (`re-conclusions-static-rooted-dynamic-validated`): the bands must corroborate the
`Muted` / `Live-by-proxy` verdicts, and E001 track A must read wholly hatched.

## Amendment (2026-08-12) — active corroboration: the no-op prune A/B

§6 above kept the per-track energy band as **corroboration, not a vote** — but corroboration
you never actually *run* is decoration. The author's ask: "I would like to be confident that
these do nothing. A debug button that skips the muted opcodes and A/Bs the energy." This
amendment adds the **active** counterpart to the passive band: **prune every opcode the
verdict system calls a no-op, re-render the pair, and prove the audible output didn't change.**
It is the purest form of `re-conclusions-static-rooted-dynamic-validated` — the static
classifier stays the source of truth; this experiment *tests* it, never *feeds* it.

Decisions (each the settled branch of a `/grill-with-docs`):

1. **Measured on the MIXED pair, never isolated voices.** The per-track band (§3) renders
   each voice alone and is structurally **blind to cross-voice coupling** — a pruned opcode
   that perturbs a **shared SPU register** (reverb bus, noise clock) shows nothing in
   isolation. Rendering the real mix is the only way to catch a global effect. On E001 this
   makes the *wholly-muted* case meaningful, not tautological: baseline = carrier track B
   (raw peak 0.0465) **+** track A's floor; pruned = track B **+** idle — a **loud-vs-loud
   diff with a tiny expected Δ**, testing whether the "silent" track A perturbs the mix.

2. **Per-track skip, mixed measurement, per-track attribution.** One button press → **3
   mixed renders**: baseline, track-A-pruned, track-B-pruned. Each track's Δ (read off the
   full mix) is attributable to *that* track's no-ops. Rejected: per-voice-isolation A/B (§1);
   one pair-wide prune (loses attribution).

3. **Prune set = every no-op verdict = `Muted` ∪ `Inert`, verdict-driven** (not
   note-hardcoded — a note is one *muted opcode*). `Muted` notes consume ticks → substitute
   an **equal-`delta_time` rest** (re-emit `relative_key = 13`; the explicit-duration rest
   form covers every delta, and because the whole track byte stream is rebuilt, width changes
   are free). `Inert` zero-tick opcodes → **deleted**. **Hard exclusions regardless of
   verdict:** the **instrument opcode (`0xAC`)** — it sets the *running instrument* a later
   audible note inherits, and the `Muted` predicate itself depends on it; and **structural/
   flow** (`0x98` Repeat / `0x99` Coda / `0x90` EndBar / Rest / Hold). **`Pre-arm` stays** —
   it is *not* a no-op (it stages state for an audible note); pruning an `Inert` opcode that
   was really a mislabelled pre-arm is exactly a bug this experiment catches. Everything
   un-pruned is **byte-identical in both renders → cancels**, so Δ isolates precisely the
   no-ops. Loops are honored **for free** by editing the **byte stream**: a pruned note
   inside a loop becomes a rest once and the loop replays that rest every iteration (editing
   a flattened event list would silently drop iterations — the reason we "expose" structure
   by staying at the byte level).

4. **A-priori metric, three tiers off the existing constants — never fitted to confirm.**
   Because the render is **deterministic** and every un-pruned byte is identical, a genuinely
   no-op prune should leave the sample stream **bit-identical → Δ = 0 exactly** *unless* a
   "trusted-empty" instrument isn't truly all-zero. Compare **raw, un-normalized** envelopes
   (normalize would hide amplitude — §3's shared-normalize dressed 0.0117 up to 0.25), both
   rendered **untrimmed to a common length**; report **max per-frame |Δ|** and **peak Δ** as
   a number, always. Color by the **audibility constants already committed** in
   `SoundGhostProjector` — chosen *before* seeing any result: Δ `< SILENCE_RMS` (0.004) →
   **inert ✓**; `< ABSOLUTE_QUIET` (0.035) → **faint ≈** (reuses the existing gray-zone tier,
   not a new state); `≥ 0.035` → **changed ✗** (classifier over-claimed — a real bug).
   E001 track A's 0.0117 floor is expected to land **amber "faint"**, an *honest* read
   ("these no-ops leak a sub-audible floor"), not a fitted pass.

5. **Manual one-shot button on the F3 studio page; proof-only.** ADR-0051 forbids env-var
   gating — the control is a button on the pair panel (`EffectStudioPage`, ADR-0069),
   mirroring the existing capture-mode dance (`_playing` guard, `capture_mode = true`,
   `panic()` isolation, restore). Result is a **per-track tell under each energy band**
   (`no-op A/B: inert ✓ Δ0.003` / `faint ≈` / `changed ✗`); cached per pair, invalidated on
   edit. Rejected: auto-run on selection / persistent toggle (3 offline renders per keystroke,
   and it would creep toward feeding the live view). The pruned bank is a **transient,
   in-memory `FedsBank`, never saved**; the Δ **never flows back into the verdict or hatch**
   (same display/QA-only rule as §6's band and the "silent in isolation" marker).

Deferred (earned, not in this build): **prune-for-real** (write the smaller byte stream back
to `E###.BIN` with a byte-exact saver + undo — a real editor mutation, not a falsification
tool); and the **`Live-by-proxy` allowlist check** — deliberately skip `0xB4`/`0xB5` and
confirm a *different* track **changes** (inverted pass semantics: green = *changed*), the only
empirical test of the allowlist, kept a sibling experiment so its opposite pass condition
never collides with the prune's.

**Mechanics (follow, not fresh choices):** a new pure `FedsNoOpPrune.gd` (track view +
`FedsOpcodeVerdicts.verdicts()` → modified byte stream); `SoundGhostProjector.gd` gains
`energy_diff(a, b)` (max|Δ|/peak on a common untrimmed length) and
`render_pair_pruning_noops(…)` (build the transient bank, mixed render); `EffectStudioPage.gd`
adds the button + per-track tell + cache/invalidation. Build is a `/tdd` follow-on on
`FedsPairEditorTest` (Slice 1 pure transform: only no-ops changed, total ticks identical,
instrument/structural/pre-arm untouched, loop-interior note rests every iteration; Slice 2
projector with `_MockEnergyEngine`) + headful `FedsPairEditorAcceptanceTest` on **E001**
(wholly-muted; asserts the **deterministic Δ actually measured**, not a hoped-for verdict)
and a **partially-muted** track picked from **E004 / E317** (the sharp "the live swell
survives, the no-ops don't" test).

## Amendment (2026-08-13) — the instrument chip tells whether the sample sustains

A held FEDS note (E001/CURE track B is one long `AC 67` note, duration 144) can *sound
like many notes* because the **sample** loops a tail for the whole hold — a property of
the ADPCM **block-loop flags**, one tier below the note opcode, invisible in the score.
The instrument (`0xAC`) chip named the waveset sample but said nothing about this. So
clicking it now leads with a **humanized loop verdict**.

1. **A generated, committed metadata table — not a live waveset read.** A new
   `tools/generate_feds_instrument_meta.py` parses `WAVESET.WD` once (mirroring
   `waveset_parser._decode_adpcm`'s block-flag walk — the code path the game plays) into
   `assets/feds_instrument_meta.json`, **keyed by raw `0xAC` id** (applying the runtime's
   `id → waveset[id+1]` rule internally): `{sample_size, has_loop_repeat,
   has_explicit_loop_start, loop_offset_bytes, is_null}`. This mirrors the
   `FedsInstrumentNames` / `feds_param_stats.json` pattern: **ROM-free-testable** (synthetic
   `dwds` blob + a pinned oracle — id 67 = 2288 B/loop-repeat, id 1 = silent), with a full
   live re-parse drift guard that **skips when the ROM is absent**. Rejected: a live
   `WavesetParser` read (untestable without ROM, needs a loaded bank).

2. **A humanized verdict, honest about the heuristic loop point.** `FedsInstrumentMeta.gd`
   (no `class_name`, ADR-0004) turns the raw facts into a plain line: **"Sustains — loops
   its tail (last N of M bytes)"** when an explicit `LOOP_START` block marks the point;
   **"Sustains — loops … (loop point is a heuristic)"** when only `LOOP_REPEAT` is set (the
   FFT default `end − 0x1010`, labeled as the heuristic it is, per
   `re-conclusions-static-rooted-dynamic-validated`); **"One-shot — plays once, then
   stops"** otherwise. `describe(id)` leads with the name, then sample size, then the verdict
   — or the **silent tell** for a `·Silence` instrument (reusing the trusted-empty /
   gray-zone-clip split). `loop_summary_of(meta)` is a **pure** function of the raw facts,
   guard-covered on every branch.

3. **Shown on the chip, via a generic enum-cell detail seam.** The `0xAC` descriptor
   (`FedsParamSemantics`) carries a `value_detail: Callable(id) → String`; `_enum_cell`
   renders it as a **dim Label under the dropdown**, seeded to the current id and **refreshed
   on selection** (the `_int_cell` range-hint idiom; absent → the bare OptionButton,
   unchanged). Test seam: `enum_detail_hints()`.

**Dynamic close (`re-conclusions-static-rooted-dynamic-validated`).** The committed table
matches a live `WavesetParser` dump of `WAVESET.WD` (id 67 → waveset[68], 2288 B,
`has_loop_repeat`), and `FedsInstrumentMetaTest` decodes **real E001** to confirm it
carries the `AC 67` event whose chip now reads **"Sustains."** Guards: `test_feds_instrument_meta_drift`
(8, Python) + `FedsInstrumentMetaTest` (24, GDScript); `FedsPairEditorTest` green (604, no
enum-cell regression). Deferred: a physical loop-length in ms (needs the pitch/tempo
runtime); surfacing the same verdict on the timeline ghost bar.

## Amendment (2026-08-13) — the note chip is an audition console (hear the sustain)

The prior amendment let the `0xAC` chip *say* "Sustains — loops its tail." This one lets an
author *hear* it. The phenomenon is **note-level**: E001/CURE track B is one long note
(dur 144) that rings like many because the sample loops its tail — you cannot demonstrate a
sustain without a real duration to play, and only the **note** event carries one. So the
audition surface is the **note chip**, not the instrument chip. Text *tells*; audio
*demonstrates* — the verdict line stays, unchanged, on the `0xAC` chip. (Settled in a
`grilling` session; the user reframed the design mid-grill with the transient-dropdown ask.)

1. **The note chip becomes an audition console** — a small stack of controls built on the
   existing inspector seams (the `action`-button shape, an `enum` OptionButton, and the dim
   `value_detail` detail label — no new cell machinery), rendered top-to-bottom:
   - **`Audition as: [ instrument ▾ ]`** — a **transient** instrument-override dropdown,
     defaulting to the note's *running instrument* (the last in-track `0xAC`, resolved by the
     existing `FedsParamSemantics.usage_range(..., instrument_id)` path). It is
     **audition-only and NEVER written to `E###.BIN`** (same display/QA-only rule the loop
     verdict and the no-op A/B band follow). Its whole reason to exist: demoing "what would
     this same note sound like as instrument X?" without editing — and re-picking the sample
     via the `0xAC` chip each time is unwieldy. It drives **both** buttons below.
   - **`▶ Hear this note held`** — sounds the note at its **real pitch** for its **real
     duration** (E001: 144 ticks stepped on the SFX tick clock), then `key_off` → ADSR
     release fade. A **`■ Stop`** cuts it early. This is "this note, as written," faithful.
   - **`▶ Tail only`** — sounds **just the looping tail** (starts at the loop point, skips
     the attack — the pure ring), and **rings until Stop**. **Gated on Sustains:** disabled
     for a One-shot instrument (there is no tail to isolate).

2. **Live, not offline — guarded on stopped transport.** Audition pokes the SPU directly via
   `Spu.key_on` (hear-held) and `Spu.key_on_with_addresses(start = loop point)` (tail-only) —
   the primitives already exist (`addons/exmateria_sound/runtime/spu.gd`), give instant
   response and natural hold/release, and need **no native/C++ work**. The ADR's SPU
   voice-pool-wobble / transport-collision worry is dodged structurally: both buttons are
   **disabled while the effect is playing** (you audition from a parked transport, which is
   the state you're in while inspecting a chip). Rejected: an offline single-note
   `render_pair` (matches the pair-panel auditions but needs a new Godot render path and turns
   "rings until Stop" into a fixed clip — machinery bought for no benefit here).

3. **Honest about the loop point.** The loop point is exact when the sample carries an
   explicit `LOOP_START` block; when only `LOOP_REPEAT` is set, FFT (and therefore we)
   fall back to `end − 0x1010`. In that case the tail button reads **"▶ Tail only (defaulted
   loop point)"** with a dim hint ("uses the game's fallback point"), so a *defaulted* start
   is never mistaken for a *marked* one — the same `re-conclusions-static-rooted-dynamic-validated`
   honesty the verdict line already keeps. Word chosen: **"defaulted,"** not "approx."

4. **Silent instruments say so.** When the auditioned instrument — real or dropdown-overridden
   — is a `·Silence` / empty slot (e.g. id 1), both buttons go **disabled** with a dim reason
   "Silent — nothing to hear (empty slot)," so an inaudible press never reads as broken.

5. **Nothing feeds back into state.** No audition mutates the score, the verdict, or any
   projector output; the override dropdown is transient session UI. Audition is a
   *demonstration* of the static classifier, never an input to it.

**Dropped** (superseded by this design): the separately-planned instrument-chip "▶ Preview
sample" blip — the note console plays any dropdown-picked instrument against a *real* note,
which is strictly a better demo than a fixed-pitch blip. **Deferred (earned, not built):**
physical loop length in ms (needs the pitch/tempo runtime, as before).

Build is a `/tdd` follow-on: a pure hold/tail parameter builder (real pitch/duration; loop
point from `FedsInstrumentMeta.of(id)` explicit-else-heuristic; Sustains/silent gating) with
GDScript guards on every branch (One-shot disables tail, silent disables both, defaulted-loop
label), plus a headful acceptance on **E001** (the `AC 67` note audibly rings; tail-only
isolates the loop) driven through the console seam.

## Amendment (2026-08-13) — prune-for-real: the real delete (un-defer the compile path)

The proof-only "▶ Audition (no-ops pruned)" button (§ the 2026-08-12 no-op A/B amendment)
plays a *transient* pruned bank and never saves. Its own "Deferred (earned, not in this
build)" paragraph named the next step: **prune-for-real** — write the smaller byte stream
back to `E###.BIN` with a byte-exact saver + undo, "a real editor mutation, not a
falsification tool." This amendment un-defers it. User decisions settle the two open scopes:
**full prune set** (`Muted` ∪ `Inert`, exactly what `FedsNoOpPrune.prune_track` already does)
and **open pair only** (the two tracks `pair_idx*2 + {0,1}`, not the whole bank).

**The structural rewrite already exists — reuse, don't rebuild.** Deleting opcodes *shrinks*
a track, so it cannot ride `SoundDefChannel.apply_raw` (same-size byte patches, the "bounded
parameter editing" ring). But the size-changing splice is already written and already used
by the proof-only path: `SoundGhostProjector.build_pruned_bank(bank, pair_idx, [0,1])` →
`_rebuild_bank_with_track` prunes each track and re-splices, recomputing the section length
(`0x04`), `data_offset` (`0x0C`), and **every downstream track offset** (`0x18 + i*2`) by the
byte delta, then re-`parse()`s a fresh `FedsBank`. The two tracks compose because it re-splices
between them. That pruned bank IS the exact bytes a real delete must persist. Likewise the
*persistence* path is not new: `EffectSoundSaver.save` already writes the whole FEDS blob
(any size) to `feds.bin` and shells to `write_effect_sound_sections.py` → `patch_all`, a
section **splice** (not a re-emit) that carries our exact bytes — the same structural writer
the camera/screen savers use. So prune-for-real is a **commit seam + undo**, not a new saver.

1. **Commit seam through the one choke point.** `EffectEditSession.prune_feds_noops(pair_idx)`
   snapshots the live `EffectData.feds_bank`, builds the pruned bank, and **swaps the whole
   object** (`_data.feds_bank = pruned`). If the build returns null or the bytes are identical
   (no prunable no-ops in this pair) it is a **no-op — no swap, no undo entry** (the button
   does nothing rather than pushing an empty edit). Host wrapper `studio_prune_feds_noops`
   mirrors `studio_insert_event`/`studio_delete_event` (re-bind the session to the current
   instance, refold on success). Returns `{invalidates_feds, pair_idx, before_bytes,
   after_bytes}`.

2. **Undo = the snapshot verb, already the precedent.** A whole-object swap is snapshot-based
   undo exactly like the camera insert/delete verbs: the pre-edit `FedsBank` is stashed and
   restored wholesale (`undo()` gains a `"feds"` channel branch → `_data.feds_bank = snapshot`).
   The verbs never mutate the old bank in place, so the stash is byte-exact. LIFO ordering keeps
   it consistent with any earlier same-size `sound_def` scalar edits: the prune sits on top, so
   undo restores the old bank *before* an older scalar replay dispatches against it. A whole-pair
   delete is **one compound = one undo entry** (both tracks pruned in the single build).

3. **Re-derive + persist reuse the `invalidates_feds` path.** The page handler
   `_commit_prune_noops` re-points `_sound_env["feds_bank"]` at the swapped bank, then runs the
   SAME re-derive block a `sound_def` byte patch takes: `_compute_pair_views()`, evict the pair's
   energy + no-op-A/B caches, fan-out-invalidate the ghosts of every `sound_id` resolving into
   the pair, `_rebuild_score()` + `_render_current()`. Persistence is **not** auto-save — it flows
   through the existing `studio_save` seam like every other edit, so undo is meaningful (undo
   before Save never touched disk; the pruned blob reaches `E###.BIN` only on an explicit save).

4. **The gate the compile path was deferred behind: a corpus round-trip identity guard.** The
   reason this was deferred is that re-emitted bytes must reproduce the ROM's exact encoding.
   Because `build_pruned_bank` operates at the **byte level** (slice + splice, arithmetic offset
   fixup) and never re-emits from a parsed event model, byte-exactness of the *unpruned* regions
   is guaranteed by construction — but that claim must be **mechanically proven across the whole
   corpus**, not asserted. `FedsPrunePersistenceTest` (GDScript, corpus-wide over every
   `assets/effects/E###/feds.bin`): for each pair assert (a) **splice identity** — replacing a
   track with *itself* through the fixup reproduces the original blob byte-for-byte; (b) **offset
   self-consistency** — the pruned bank's track offsets stay in-bounds and its `parse()` round-
   trips (`parse(pruned.raw).raw == pruned.raw`); (c) **tick preservation** — each pruned track's
   total `delta_time` equals the original (a delete may not shift the clock). No SPU render in the
   guard (the audible-Δ=0 claim is the proof-only A/B's job, already tested on E001/E004/E317).

**Build (`/tdd`), reusing the existing modules:** Slice A pure — `prune_feds_noops` + the
`"feds"` undo branch + `studio_prune_feds_noops`, guarded in `FedsPairEditorTest` (swap makes
`feds_bank` the pruned blob; undo restores exact bytes; a no-no-op pair is a no-op with no undo
entry). Slice B page — the `{"kind":"prune_noops_commit"}` sibling action beside the proof-only
audition (destructive label + tooltip) and `_commit_prune_noops`. Slice C — the corpus
`FedsPrunePersistenceTest` gate. Headful `FedsPairEditorAcceptanceTest` on **E001** (delete →
the pair re-derives smaller → undo restores). `FedsInstrumentMetaTest`/`FedsNoteAuditionTest`
stay green.

## Amendment (2026-08-14) — a stub lane renders its flow-through span, not its two lonely bytes

The [per-track energy](#3-per-track-energy-inline-under-each-lane--and-it-grounds-2) and the
audio render both read a track through the **flow-through** reader (`feds_bank.gd`
`get_track_events_from` / `play_pair(..., single_track)`): a track with no `0x90` **EndBar** is
a **stub** whose voice walks *past* its own bytes into the following bytecode until the first
EndBar — FFT's SPU driver is a linear byte-walker with no per-track boundary. But the **lane /
pip / verdict** surfaces read the **bounded** track (`FedsPairModel._track_view` →
`get_track_bytes`, `SoundGhostProjector.pair_pips` → `get_track_events`). So a stub lane draws
its ~2 own bytes and *looks silent* directly above a **loud energy swell** — the picture
contradicts the audio. **Canonical case E317 pair 0:** track A = `D2 02` (a lone
`PitchBendRel +2`, no EndBar), track B = `AC 0A 94 03 D4 0E 17 60 0B D4 90 D7 81 90 90`
(instr #10, octave, portamento, a **C3**, Fermata, EndBar). Voice A alone renders **raw_peak
0.317 / 106 frames** — it has no note of its own, so that energy is voice A *flowing into track
B's C3* and sounding it **detuned +2** against voice B's clean C3 (a detuned-unison / chorus).
The `D2` is **load-bearing**, not a no-op; the display just never showed why.

**Decision — a derived, read-only flow-through span field; the authored track stays bounded
(option C, not A/B).** Reject **(A) making `_track_view` wholesale flow-through** — the verdict
engine would then classify track B's opcodes *as if authored on track A*, and prune-for-real
(which edits the bounded bytes but reads those verdicts) would misalign; it also destroys the
authored-vs-borrowed distinction. Reject **(B) re-decoding the span inside the lane `Control`**
— untestable as pure value logic, and `pair_pips` (a separate path) would stay bounded and keep
disagreeing. Instead: the authored track keeps its **bounded** events (verdict/prune/`_track_view`
byte-unchanged, **zero regression**), and the view gains a **derived `flow_through` field**
produced by **one pure span builder**:

1. **Decode one continuous stream from the stub's byte offset to the first *decoded* EndBar**
   (`get_track_events_from` semantics — never a byte-scan for `0x90`; in E317 track B a `90`
   byte is a `D4` portamento *param*, the real EndBar is a later decoded `90` **opcode**). A
   single tick accumulator runs through the stub's own time-advancing events straight into the
   flowed bytes, so any **leading-tick offset** (0 for E317's instant `D2`, nonzero for a stub
   that `Rest`s first) and the **running state** (the borrowed note carries B's instrument #10
   + octave *and* A's `+2` detune, because A's `D2` then B's `AC`/`94` accumulate in decode
   order) both fall out **for free** — this is *why* the continuous-decode shape is the right
   one.
2. **Tag every event own-vs-borrowed** by whether its absolute byte offset has crossed into a
   **later track's** region. The span is the **full event stream — notes *and* commands** (the
   voice executes every opcode it walks through: it borrows B's `Ins10`/`Oct3`/`Por` *and* the
   note), all `flowed` events tagged.
3. **Populate the field only when `stub == true`.** A track with an EndBar terminates itself,
   borrows nothing → empty field, no behavior change. Non-stub lanes/pips/verdict/prune stay
   byte-for-byte identical.

The **shared model** the [energy §3](#3-per-track-energy-inline-under-each-lane--and-it-grounds-2)
asked for is this one builder: the lane **and** `pair_pips` both consume it, so **lane / pip /
energy / audio finally agree**. (Pip onsets dedup by frame, so a borrowed onset usually merges
with the neighbour's own — a *distinct* pip appears only when detune / a leading `Rest` shifts
it off that frame. Correct either way.)

**Display — both voices visible, borrowed styled apart (Q3 = "keep them visible").** The borrowed
notes/chips draw on track A's own lanes in a **borrowed style** (the panel's existing dimmed
ghost idiom + a distinct hue + a **flow-start marker** at the own→borrowed byte boundary), time-
aligned beneath track B so the **detuned double-sound reads at a glance**, plus a **source tell**
on the section header (*"stub → flows into Track B; borrows its notes, `PitchBendRel +2`
detunes"*). Not collapsed into one lane (hides the two concurrent voices), not an unstyled dup
(reads as a bug). The stub's `D2` **stays `Pre-arm`** in the verdict — now honestly so: it
pre-arms the pitch register the *flowed* note reads. Playhead / pair length are **untouched**:
the rendered ghost length is already flow-through-correct, and within-pair flow stops at the
neighbour's EndBar so the drawn time axis (`max(end_seconds)`, driven by track B) does not
stretch — only *content* is added.

**Empirical scope (corpus probe, 401 effects / 2018 tracks).** **80 stub tracks (4.0%)** —
**70 track A, 10 track B**. **100% flow within their own pair; 0% cross a pair boundary into a
different sound.** So the **track-A-stub → track-B inline** case (E317) *is* the whole real
feature; the 10 track-B stubs occur only in a **last pair**, flowing into trailing bytes (a
non-last B stub would necessarily cross into the next pair — none do). **Cross-pair chaining is
therefore a pure safety rail:** the builder still chains honestly across all boundaries (audio
truth), but the per-pair panel renders borrowed notes inline only while they live in *this*
pair and shows a cheap **"flows beyond this pair →" terminal tell** instead of injecting another
sound's authored notes — never exercised by real data, kept correct and minimal.

**Faithfulness (`re-conclusions-static-rooted-dynamic-validated`).** Static-rooted (the byte-
walker, no per-track boundary, only a decoded `0x90` terminates) **and** dynamic-validated: the
flow-through mechanism is already confirmed against a **PCSX per-voice WAV for the analogous
`cure_4` stub** (`VOICE_18_KON_NEVER_FIRES.md`), and the **port** is confirmed on E317 (voice A
audible, raw_peak 0.317). We build on that; the **E317 pair 0 voice-A PCSX capture** is a
**pre-push confirmation**, not a hard gate — if it came back silent the premise would flip and
we would stop.

**Build (`/tdd`), reusing existing modules.** Slice A pure — a `FedsPairModel` flow-through-span
builder + the derived `flow_through` field (stub-only), guarded on **E317 pair 0** and the
`cure_4` fixture (continuous-decode-to-first-decoded-EndBar, own/flowed byte-offset tagging,
leading-offset, the `90`-as-param trap). Slice B — `pair_pips` sources a stub's onsets from the
span. Slice C — `FedsPairLanePanel` draws borrowed notes/chips in the borrowed style + flow-start
marker + source tell (and the cross-pair terminal tell). `FedsPairEditorTest` (incl. the existing
stub-tell guard) + `FedsPrunePersistenceTest` + the prune/verdict guards stay green. Headful
`FedsPairEditorAcceptanceTest` on **E317** is the dynamic close: the stub lane now shows the
borrowed C3 (+ borrowed opcodes) matching the energy band and what you hear.

---

## Amendment (2026-08-18) — the borrowed span is a **NoEnd phantom that folds**, and a null slot is not a stub

The [2026-08-14 amendment](#amendment-2026-08-14--a-stub-lane-renders-its-flow-through-span-not-its-two-lonely-bytes)
shipped its model half (`81d86a7e7`) and left a *Display* paragraph. Building it surfaced two
things: the display idea it named was the wrong shape, and its **empirical scope paragraph was
wrong about the data**. Both are corrected here. The model half stands unchanged.

### 1. Correction — the 10 "track B stubs" are NULL SLOTS, not music

The 2026-08-14 corpus paragraph read *"80 stub tracks — 70 track A, 10 track B … the 10 track-B
stubs occur only in a last pair, flowing into trailing bytes."* Re-run with the real decoder
(`tools/feds_stub_audit.gd`, 401 effects with feds / 1009 pairs — never a byte-scan for `0x90`):

```
stub tracks on EVEN index (track A, flows into its own partner): 70
stub tracks on ODD  index (track B):                             10
flows crossing into the next pair (crosses_pair):                 0
flows with no EndBar anywhere:                                    0
```

**All 10 odd-index "stubs" have `track_offsets[i] == 0`.** The magic + header + offset table
occupy the blob's first bytes, so offset 0 can never address bytecode: it is the table's *"no
track here"* sentinel, and the pair simply has **one voice**. They are E097/E185/E332/E336/E376/
E382 pair 1, E343 pair 2, E248/E249 pair 3, and **E089 pair 5 — whose null slot sits MID-table**
(`t11` between `t10@0x179` and `t12@0x18D`), so the old "only in a last pair" reading was wrong
twice over.

Deciding stub-ness by *"the bounded decode has no EndBar"* therefore misread them as **stubs that
flow**, and the reader walked the **feds header as opcodes** — 11 phantom notes and 7 pips where
1 was real, in the guard's fixture. A **null slot** is now a first-class term: never a stub, no
`flow_through`, skipped by `pair_pips` and `build_pruned_bank` (`c097bb210`).

With null slots excluded the corpus says, and guards now assert:

- **A stub is always track A of its pair**, flowing into its own partner.
- **A pair never has two real stubs.**
- **No flow ever leaves its pair** — `crosses_pair` and the no-EndBar-anywhere case are *empty*.
  The 2026-08-14 "flows beyond this pair →" terminal tell is **withdrawn**: it would render a
  case that does not exist, and the safety rail is the null-slot predicate instead.
- `flow_through_span`'s `track_offsets[i+1]` boundary rule **never** disagrees with
  `FedsBank.track_size`'s nearest-larger-offset rule for a real stub (0 cases), so the offset
  table's unordered-ness — real, and exactly the 10 null-slot effects — costs us nothing.

### 2. Supersedes the *Display* paragraph — a phantom that folds, not a marker plus permanent content

**Rejected (the 2026-08-14 text):** borrowed notes drawn *always*, plus a separate flow-start
marker. Two new visual concepts, permanently taller lanes, and a marker whose only job is to say
where a thing you can already see begins.

**Decided:** the missing EndBar becomes a **`NoEnd` phantom** — a **derived span with no byte
behind it** — that **folds exactly like a loop**. The panel already has one fold idiom (a
bracket + a `×N ▸` badge that unrolls the body in place); this is its second instance, so there
is no new gesture, no new verb and no new hit-test route: the phantom is `loop_index = -1`, and
`toggle_loop` / the badge / `_loop_key` all take it unchanged.

- **Collapsed, the bracket already spans the real borrowed envelope.** The span *sounds* — pips,
  energy and audio all include it as of `81d86a7e7` — so hiding its *duration* would make the
  panel the one surface disagreeing with what you hear. This is the loop bracket's existing law
  (*"unwinding can never MOVE the axis"*) applied to the other kind of borrowing: **folding hides
  content, never time.** Folded by default.
- **A dedicated `flow` lane** (the old `loops` lane, renamed) hosts both loop brackets and the
  phantom, under one rule: **`structure` = authored bytes; `flow` = derived spans.** A loop
  bracket was always derived; the phantom has no byte at all. Putting a byte-that-does-not-exist
  on the lane whose job is *"what did the composer write?"* would undo what §2's verdict work is
  for.
- **`flowed` is a SECOND, INDEPENDENT axis from `ghost`**, not a reuse of it. Dim means *"a
  copy"*; the violet means *"not this track's bytes"*. They compose — a dimmed violet item is a
  copy of borrowed bytes, which is what a loop inside a borrowed span produces, and one flag
  could not say that. Borrowed items take a violet **outline** rather than a fill swap, so the
  §2 verdict hue still reads underneath: **ownership on the edge, honesty inside.**
- **A borrowed item selects its OWNER's event.** You edit a byte **where it lives**, never where
  it is heard — the law the panel already applies to an unrolled loop copy, extended across
  tracks. Identity travels by **blob-absolute offset**, not by ordinal: a flow-through walk's
  `event_index` counts from the stub's start and means nothing to the owner, so the model stamps
  `owner_track` / `owner_event_index` on every flowed event. Clicking the borrowed C3 jumps the
  highlight to track B's real note and opens **its** rows. An unresolvable owner is inert.
- **The header's unwind-all includes phantoms** — it means *"show me everything this pair
  actually does"*, and the borrowed span is now precisely the part the bytes do not show.
- **A stub with nothing following it draws no phantom.** Borrowing nothing is the honest answer,
  not a missing feature.
- **The source tell stays, always visible** (`FedsPairProjector.gd:11`'s standing promise, kept):
  E317 pair 0 renders *"Track A · 2 bytes · Stub → flows into the next track · borrows Track B's
  notes; `PitchBendRel +2` detunes"*, and the phantom's hover says *"no EndBar — this voice runs
  on into Track B and sounds 6 borrowed notes … (a derived span — no byte encodes it)"*.
- **`FedsOpcodeVerdicts.STUB` drops the word "silent"** (`"Silent stub → …"` → `"Stub → …"`). A
  stub sounds. That word was the lie this branch set out to remove.

**Untouched, as before:** playhead, pair length, the drawn axis. The stub's drawn extent stays
bounded by its own bytes — the amendment adds *content*, never axis length.

**Verified.** E317 pair 0, folded: track A carries `opcode` + `flow` lanes and one `→B ▸`
bracket. Unfolded: `notes` + `structure` join, the badge flips to `→B ▾`, and **1 borrowed note +
6 borrowed chips** appear with owners `1/0 1/1 1/2 1/4 1/5 1/6` — while the stub's own `PBd2`
stays `flowed=false`. `FedsPairEditorTest` 673 passed, `FedsPairEditorAcceptanceTest` 54 passed,
the rest of the FEDS family green.

**Trap re-recorded:** `FedsPairEditorTest` needs `--quit-after 400`. At the documented `4` the
awaited page tests cut the run off **before the summary**, printing *nothing at all* — no
`[PASS]`, no `[FAIL]`, exit 0. Grep for the summary line itself, not for failures.

---

## Amendment (2026-08-18b) — structural authoring: the panel composes, and the writer learns to make room

Decided in a grilling session; **nothing here is built yet**. It supersedes three standing
decisions (decision 6's "the panel NAVIGATES", the encoding-shaped lane taxonomy, and the
same-size-only write path) and records the facts that forced each one, so the build does not
re-derive them.

**The goal is narrow: structural editing of pairs that already exist** — adding and removing
events in a sound the ROM already contains. Not discoverability polish (per-byte editing already
works and lands live on the shared bank), and **not composing new pairs from scratch**: every
corpus pair is addressed by a container's fire table, so inventing a pair means inventing its
provenance, and none of that machinery is exercised by this work.

### 1. The blocker is persistence, not the gesture — and it is already broken

`tools/effect_writer_registry.py::serialize_sound_def` refuses any length change:

> *"sound_def: blob is %d bytes but the section is %d — same-size patches only (a resize is the
> deferred compile path)"*

and there is nowhere to hide. Spare room inside each FEDS section, measured over all 401
effects with feds:

```
slack 0 bytes : 92 effects      max 3, median 1
slack 1 bytes : 112
slack 2 bytes : 96
slack 3 bytes : 101
```

That is 4-byte alignment padding. **One added opcode overflows a quarter of the corpus.**

Consequence, true today with no new feature added: **prune-for-real cannot be saved.**
`EffectSoundSaver` hands `feds_bank.raw` straight to that writer, and a prune shrinks the blob,
so the save raises rather than writing. Fixing relocation repairs something already shipped
before it enables anything new — which is why it goes first.

**Decision: teach the writer to relocate** — splice the resized section, shift the tail, patch
every header pointer after `sound_def_ptr` (for FEDS that is `texture_ptr` alone). The mechanism
already exists one section over: `tools/write_effect_script.py` does "splice + tail-shift +
header fix-up" with a `_DOWNSTREAM_PTR_OFFSETS` list. Build the sound_def path first against its
own corpus gate, then extract the shared helper once there are two real callers — the second is
already named, not speculative: `SequenceChannel` (#275) defers insert/delete/reorder of
animation opcodes for precisely this reason.

**Rejected — moving the FEDS blob to the end of the file** and repointing `sound_def_ptr`. It
touches one pointer instead of shifting anything, but it breaks an invariant we rely on
ourselves: `FedsBank._load_from_effect_bin` derives the section as `[sound_def_ptr, texture_ptr)`
— FEDS is bounded *by being immediately before the texture*. Tail-shifting preserves that;
relocating to the tail would need a Ghidra session to prove the game does not rely on the same
adjacency. Tail-shift needs no RE lookup at all.

**CODE-format effects are not a special case.** 107 of 401 effects carry a MIPS prologue, but
the structure after the embedded header is identical — which is why the whole pipeline already
plays them — and `parse_effect.parse_header(data, base_offset)` already resolves their pointers
to absolute file offsets. The relocation writes back in the header's frame; that is the whole
difference.

**Corpus gate**, mirroring `FedsPrunePersistenceTest`'s three claims one level up at the file:
δ=0 reproduces the original `E###.BIN` byte-for-byte across all 401 effects and both formats;
at δ≠0 every header pointer after `sound_def_ptr` still addresses the same *content* (compare
bytes, not numbers); and the rewritten file re-parses to the same effect.

### 2. The panel composes (supersedes decision 6)

Decision 6 read *"the panel NAVIGATES; the F1 inspector EDITS."* It becomes: **the panel
navigates and composes; the inspector owns parameter editing.**

Add and delete land as a **right-click context menu on the lane panel**, routed through the path
every other channel already uses — `EffectScoreTimeline`'s `lane_context_requested` →
`EffectStudioPage._run_lane_verb` → `EffectEditSession.insert_event/delete_event` → the channel.
`FedsPairLanePanel` is the only lane surface in the studio with no context signal at all.

**Rejected — inspector-only verbs** (the `prune_noops_commit` action-row precedent, which does
already exist for FEDS at pair scope). *"Add an opcode **here**"* is irreducibly positional: in a
stream where an `Instrument` byte's whole meaning is where it sits relative to the notes after
it, an insert with no position is barely a verb, and "insert after the selected event" makes the
author select a proxy for the place they actually mean. **Rejected — splitting the verbs**
(insert on the panel, delete in the inspector): one conceptual pair of verbs, two places to look.

### 3. First slice: zero-tick opcodes only

**Only note-form events (note/tie/rest) and `0x80 Rest` / `0x81 Fermata` advance the tick**
(`FedsPairModel._project_events`). Every other opcode is zero-tick. So there is a large, exactly
enumerable set of edits that **cannot move the clock**, and the first slice is precisely that
set: insert and delete of zero-tick opcodes. The hardest question — what "delete" means for
something that consumes time — never arises, and stays parked (§7).

`EndBar` is offered **only at the phantom's boundary**. Inserted anywhere else it makes the rest
of the track unreachable; at the boundary it is the natural verb the NoEnd phantom has been
advertising since the 2026-08-18 amendment — one byte, no earlier offset moves, and the
borrowing visibly stops. `Tempo` is zero-tick but shifts the wall-clock of everything after it;
that is honest and the panel already draws seconds from the tempo map, so it is a tell, not a
restriction.

### 4. An insert is anchored to an event, not to a time

**A tick is not a position in this stream.** Zero-tick opcodes stack: E317 pair 0 has *four*
events at tick 0 (`PBd2`, then borrowed `Ins10`, `Oct3`, `Por14`), drawn at the same x. "Insert
at tick 0" cannot say which of four boundaries is meant, and they behave differently — an
`Instrument` after the note does not affect that note.

So the address is a **byte boundary**, expressed as *"add after this event"*. A right-click in
empty lane space may still work, but the menu must **name what it resolved to** ("Add opcode
after `Oct3` @ tick 0") rather than silently picking one of four.

**This is the answer to "are opcodes attached to a note?" — they are not.** An opcode is
*positioned after* something, never *owned by* it; voice state applies from where it sits until
changed. The single exception in the language is `0x81 Fermata`, which reaches back and extends
`last_note`. Consequently, **delete a note and the opcodes around it neither move nor vanish** —
they simply now follow whatever preceded it. Their *effect* may change (a `PitchBendRel` now
colours a different next note), and a trailing `Fermata` re-binds to and lengthens a different
note; but nothing is orphaned, because nothing belonged to the note.

### 5. Lanes group by whether an event consumes time

Today the taxonomy follows **encoding form**, not behaviour, and it splits one concept across
two lanes: there are two ways to write a rest, and note-form rest lands on "Rests" while
`0x80 Rest` lands on "Opcodes" beside things that take no time at all. `0x81 Fermata` — 144
ticks in E317 — sits next to `Octave`, looking identical.

**Decision: group by "does this advance the clock?"** The time group takes notes, ties, both
forms of rest, and Fermata; the Opcodes lane becomes **voice settings only**. Then the lane
answers the question the structural work actually needs — *"does deleting this move everything
after it?"* — and it draws exactly the slice-1 boundary. This changes `_opcode_kind`, which the
verdict system and the prune share, so it is a model change, not a repaint.

### 6. Every event shows its position in the stream

The panel already stacks same-tick events top-to-bottom in stream order — but only *within* one
lane, so two simultaneous events on different lanes carry no ordering cue at all. Drawing each
event's ordinal on its note bar / chip makes the whole pair read as **one ordered list** across
lanes, which is what "pick where it goes in the list" requires. Gappy numbers are informative: a
`0, 1, 2, … 4, 5, 6` run on the Opcodes lane says a note sits at 3.

A borrowed or ghost copy shows its **owner's** number, not a fresh one — a borrowed `Ins10` is
track B's item 0 heard on A's voice, and clicking it already routes there, so any other number
would contradict the click. On a stub's lane the run reads out of order and gappy ("one of mine,
then someone else's list"); the violet borrowed outline already separates the two runs.

Chips are 34 px at font size 9 and will need ~44 px (= `BADGE_W`) for a two-digit prefix.

### 7. The insert menu is the corpus

**57 distinct opcodes** occur across the 2008 real tracks, with a clear head and a long tail
(`Detune` twice, `Noise_EnableNoArm` once):

```
0xAC Instrument       1819 tracks     0xE0 Dynamics             1281
0x94 Octave           1817            0xD4 Portamento_Init      1264
0x90 EndBar           1938            0xE2 Expression_VolBurst  1037
0xBA ReverbOn         1631            0xC2 ADSR_Attack          1013
0xC4 ADSR_SustainRate 1331
```

The menu offers **those 57, ordered by track coverage**, minus the time-carrying pair and the
flow opcodes (`EndBar` only at the phantom). A new opcode starts at the **corpus mode** for its
parameter — the value FFT itself most often writes — so an inserted `Instrument` is a real
instrument and an inserted `ADSR_Attack` does something. Same source, no hand-authored canon to
rot. **Rejected:** the full decoder table (offers opcodes no FFT sound contains — a way to end
up debugging the decoder instead of the sound) and a hand-curated short list.

### 8. Selection is recomputed, never left stale

A resize shifts every later `event_index`, and the panel holds its selection as
`{track, event_index}` — so doing nothing makes the selection silently point at a *different*
event. It lands on the **new opcode** after an insert (its parameter rows open immediately, so
"add an `Instrument`" and "set it to 42" are one motion) and on the **anchor event** after a
delete. This is what `_run_lane_verb` already does for every other channel.

### Already answered by the code — not decisions

- **Structural undo**: `EffectEditSession.prune_feds_noops` snapshots the whole `FedsBank` and
  pushes `{"snapshot": before, "channel": "feds"}`. Insert/delete reuse it verbatim.
- **The in-memory splice**: `SoundGhostProjector._rebuild_bank_with_track`, corpus-gated by
  `FedsPrunePersistenceTest`.
- **Cache choreography after a resize**: `EffectStudioPage._commit_prune_noops` is the template
  — re-point the cached env at the swapped bank, re-derive pair views, evict the pair's energy
  and no-op A/B, evict ghost + energy for every sound id resolving into the pair.

### Parked

- **Delete semantics for time-carrying events** — silence-in-place vs ripple. Slice 1 avoids it.
  The codebase's standing rule is *preserve the clock*: the prune substitutes a `Muted` note with
  an equal-`delta_time` Rest, and `FedsPrunePersistenceTest` asserts tick totals are unchanged by
  a delete. Whenever this is taken up, ADR-0095's boundary grips and ADR-0087's consume law are
  where the ripple vocabulary should come from rather than being invented fresh.
  **CLOSED by the 2026-08-18c amendment: delete means putting a rest there.** Time is fully
  tiled, so there is no hole to close and no ripple to choose — and the ripple question turns
  out to belong to the *length* verb, not this one.
- **The band's height** — an unfolded phantom wants ~420 px of a contention band with no user
  sizing control. Explicitly deferred by the user; it belongs to a different feature.
- **`crosses_pair`** is now dead data (0 corpus occurrences, its terminal tell withdrawn).
  Delete the field or keep it as a guarded assertion.
- **`write_effect_script.py`'s CODE refusal reason is false.** It reads *"CODE-format effect
  (script is MIPS executable, not editable)"*, but a CODE file's script section decodes to
  ordinary effect bytecode — E317 `[0x3C48,0x3C78)` and E004 `[0x3820,0x386C)` both start
  `set_texture_page, load_callback, …`, exactly like DATA-format E001. Whatever that gate really
  protects, the stated reason is not it. Left alone here rather than guessed at; a wrong
  justification in a user-facing refusal is how a misconception gets re-learned, and it cost a
  detour in this very session.

### Build note (step 1, 2026-08-18) — two things the plan did not settle

**The section is padded to a 4-byte multiple.** All 401 FEDS sections start, end and
size 4-aligned; the 0-3 slack bytes measured above ARE that padding. A prune leaves the
blob at an arbitrary length (E001: 228 → 214), so the writer pads up rather than
misaligning `texture_ptr`. δ=0 is unaffected, since an unedited section is already aligned.

**The header base comes from `frames_ptr`, not from a scan.** The stored pointers are
relative to the header, and `parse_header` hands the writers absolutes, so the relocation
needs the base back: `frames_ptr - 0x28` names it exactly (the header's own first field is
always 0x28 — checked against all 401 extracted headers) with no re-detection, and
`find_header_offset` is not consulted because it can disagree with the extractor's
BATTLE.BIN-sourced offset. That derived base is then **checked against the file**: the
stored `sound_def_ptr` / `texture_ptr` must resolve to the very section being moved, or the
resize is refused rather than writing a pointer into the middle of another section.

**Resizing sections splice last.** `patch_all` runs every serializer over one shared
buffer with offsets from one header, and those are only valid while the geometry holds —
so `RESIZING_SECTIONS` sorts `sound_def` to the end of the loop.

### Build note (step 3, 2026-08-18) — a bug the addressing surfaced

**A borrowed event's `owner_track` was a GLOBAL bank index in a pair-LOCAL world.**
`FedsPairModel._stamp_owners` resolves an owner by walking every track in the bank, so it
stamps `pair_idx*2 + t`; every coordinate in the panel — lane rows, the selection, and now
a verb's address — is 0/1. `_select_route` handed the global index straight through, so
clicking a borrowed item in any pair but the first looked for a lane that does not exist
(E004 pair 2 stamps owner 5, E026 pair 4 stamps 9). Harmless-looking as a dead selection;
fatal once the same index addresses a byte write. The layout now maps it once, at the one
place where the model's vocabulary meets the panel's.

**The corpus menu is a submenu.** 51 entries is too long to sit inline beside Delete, and
§2's whole point is that the two verbs read as one short list in one place. The top level
is the two named verbs; the corpus hangs off the Add row, each row carrying its track
coverage so the ordering says out loud what it is.

### Order of work

1. Writer relocation + its corpus gate (repairs prune-for-real's unsaveable state).
2. Lane regroup by time + ordinal labels — read-only, small, and what makes §4's "pick a slot"
   legible before any verb exists.
3. `SoundDefChannel.insert_event` / `delete_event`, the panel context menu, and selection landing.

## Amendment (2026-08-18c) — deleting time means resting it: the time lane is spans

Decided in a grilling session; **nothing here is built yet**. It closes the first
**Parked** bullet of the 2026-08-18b amendment — *"delete semantics for time-carrying
events — silence-in-place vs ripple"* — and supersedes that amendment's §5 on which
events the time group contains.

The answer is one sentence: **delete means putting a rest there.** What took a session
was establishing that the question was mis-shaped, and that the answer is already
built twice — once in FFT's own data, once in this repo's DAW.

### 1. Five time-carrying forms are three, and one of the three is ours

The 18b amendment names five forms that advance the tick. Measured over every real
track — 2008 in FEDS, plus all 100 `MUSIC_*.SMD` decoded with the canonical Python
parser:

```
                        FEDS (2008 tracks)   SMD music (100 songs)
note (relative_key 0-11)      6234                 61447
0x81 Fermata                  2763                  4257
0x80 Rest                      779                 87014
tie (relative_key 12)            0                     0
note-form rest (rel_key 13)      0                     0
```

**FFT never writes a tie or a note-form rest, in music or in effects.** Those two rows
are our decoder's reading of `relative_key` (`smd_opcodes.gd:99`), not a form the game
authored. The only thing in this repo that produces one is `FedsNoOpPrune`, which
substitutes a Muted note with `REST_DATA_BYTE = 247` — inventing a form with zero
precedent when the form FFT writes 87,793 times was available.

**Decision: `0x80 Rest` is the rest.** It is the corpus's rest; it expresses every
duration in 2 bytes (`80 pp`, param 0-255) where the note form covers only the 18
values in `SMD.DELTA_TIME_TABLE` before needing a third byte; and it carries no dead
velocity byte for the inspector to show someone. After a note the two forms are
behaviourally identical in our runtime (`advance_track.gd:141-144` — `0x80` in the
post-note scan is a bare `accumulated +=`), so this is a choice of notation, and the
corpus decides it.

**`FedsNoOpPrune` is retrofitted to emit `0x80`**, so the studio has exactly one rest.
`FedsPrunePersistenceTest`'s three claims are unaffected (tick totals still preserved);
its byte expectations move. Effects already pruned and saved keep a note-form rest we
will then only ever read — which the decoder handles and the time lane draws as a rest
like any other.

**Tie is out of scope, stated rather than designed.** It is not offered by the insert
menu, and `delete_event` refuses it with a reason that says so: no FFT sound contains
one, so designing semantics for it means inventing data to test them.

### 2. There are two kinds of time — sounding and silent — and both opcodes add it

The grilling nearly ran aground on the claim that a Fermata "doesn't add duration".
It does. Both time opcodes add exactly `param` ticks to the clock. They differ in
**whose** ticks they are:

```
E317 track 1:   Note C(16) · Portamento_Init(144,215) · Fermata 144 · EndBar
  tick 0-15     C sounding
  tick 16       Fermata → +144 ticks, C still sounding
  tick 160      EndBar                        track length 160

same track with 0x80 Rest 144 instead:
  tick 0-15     C sounding
  tick 16       Rest → +144 ticks, silence
  tick 160      EndBar                        track length 160  ← identical clock
```

`advance_track.gd`'s post-note scan is where this lives: `0x81` does
`accumulated += dur` **and** `note_sustain += dur`; `0x80` does only the first. So
`0x81` is more of the note that is already playing, and `0x80` is silence — same
length either way.

**The rule the lane draws by:** a Fermata's ticks are **sounding** time if a note is
sounding and **silent** time otherwise (19 corpus Fermatas precede any note; the
runtime's pre-note path treats them as a bare wait). The lane therefore reads no
opcode names at all — it asks one question per tick, *is a note sounding?*, which is
the same question the sequencer answers, so the picture cannot drift from the sound.

### 3. Time is fully tiled, so there is nothing to ripple

Every tick in a track is owned by exactly one **span**, and a span is a note or a rest.
There is no empty space in the stream. That is not a rule we are adopting; it is what
the bytes are.

Applied to ADR-0095 §3, this is the **camera** case, not the colour/particle case —
*"camera is fully tiled with no invisible tiles, so its behaviour is unchanged."* The
consume law's currency is invisible tiles, and this lane has none. So the ripple
vocabulary transfers by saying **there is nothing to consume**, which is what the 18b
amendment asked for: taken from ADR-0095 rather than invented.

**Decision: delete never moves the clock** — not because *preserve the clock* is
doctrine inherited from the prune, but because a delete leaves no hole to close.

### 4. The unit is the span, and a delete substitutes byte-for-byte

The obvious lowering — re-spell the span canonically, largest table value then 255-tick
Fermata chunks, the way `fft_smd_authoring_model.cpp::build_note_events_for_duration`
composes one from scratch — is **wrong for editing**, and the corpus says so loudly:

```
spans containing a fermata:            1619
  with zero-tick opcodes INSIDE them:  1600     (98.8%)
  bare note+fermata:                     19
  split across multiple fermatas:       629
```

**The note/fermata split is how FFT schedules voice changes during a sustained note.**
E317's `Note C(16) · Portamento_Init · Fermata 144` is one 160-tick C whose portamento
fires 16 ticks in; the split point *is* the opcode's timing. Re-spelling would move the
interior opcode of 1600 of 1619 spans.

**Decision: delete replaces each of the span's time-carrying bytes with a `0x80 Rest`
of identical tick count, in place.** (The middle row of the table below read `vv F7 tt`
until the 2026-08-19 amendment §5 — `F7` is key 13, the note-form *rest*; an explicit
note's second byte is `key*19`.)

```
vv dd      →  80 pp     (pp = the DELTA_TIME_TABLE duration, ≤192)   same size
vv kk tt   →  80 tt     (explicit-duration note, kk = key*19)       one byte smaller
81 pp      →  80 pp     (every fermata segment of the span)          same size, one byte changed
```

Everything follows from that:

- **Interior opcodes keep their exact firing tick**, because segments are substituted
  segment-for-segment.
- **The event count does not change**, so `event_index` is stable and §6's ordinals,
  `FedsOpcodeVerdicts`' per-event keying, `_stamp_owners`' borrowed-event identity and
  §8's selection remap all sit still. A delete is not a resize in the addressing sense.
- **The byte size does not change** for 5878 of 6234 notes and for *every* fermata.
  Only the 356 explicit-duration notes shrink by one byte. Delete essentially never
  relocates; step 1's writer relocation is there for insert.
- **18b §4's trailing-Fermata re-bind disappears.** `NoteA … NoteB Ferm` deleted at
  NoteB gives `NoteA … Rest Rest`; the post-note scan walks both `0x80`s with
  `accumulated +=` only, so NoteA does **not** grow. That second-order effect is true
  of a *byte* delete and untrue of a *span* delete — an argument for the span being the
  unit that is independent of anything the DAW does.
- **Loops need no special case.** Same tick count per iteration, so a rest inside
  `Repeat…Coda` replays exactly as the note did — the prune's "for free" property,
  unchanged. Worth checking, since 2842 of 9776 time-carrying events (29%) sit inside a
  loop body.

### 5. One time lane, three fills (supersedes 18b §5's list)

18b §5's rule — *group by "does this advance the clock?"* — stands. Its **list** does
not: it put ties and note-form rests on a "Holds"/"Rests" lane beside `0x80`, and left
`0x81` as its own chip while `_project_events` was *simultaneously* folding the same
ticks into `last_note["fermata_extension_ticks"]`. E317's 160-tick C draws today as a
16-tick bar on Notes plus an unrelated-looking chip on Holds — the exact complaint §5
raised about Fermata sitting next to `Octave`, moved one lane over rather than fixed.

**Decision: `notes`, `hold` and `rest` collapse into one time lane, drawn as one bar
per span with three fills** — the arrangement `fft-plugin` already ships
(`FFTTrackLaneView.cpp:1201-1223`):

```
blue   RGB(114,178,255)   the note's own delta_time
amber  RGB(255,196,92)    fermata_extension_ticks, butted against it
grey   RGB(110,116,128)   a rest span
```

```
today                              proposed
Notes    [C]                       Time     [C ────────────────]   blue then amber
Holds        [Ferm 144]            Opcodes  [Por14]  [Por144]
Rests    (empty)
Opcodes  [Por14] [Por144]
```

`opcode`, `tempo`, `structure` and `flow` are untouched. §6's ordinals number **spans**
on this lane; a fermata segment gets no ordinal of its own.

**Rejected — drawing rests as empty lane** (the "piano roll" reading, by analogy with
ADR-0087 decs. 23-28 *"a spacer is empty space, not a hatched block"*). That
analogy does not hold: a colour spacer is an event that does nothing, whereas a rest is
authored silence that FFT writes 87,793 times and that the author will want to click,
inspect and turn back into a note. The DAW draws it grey, and the DAW is the benchmark.

### 6. The verb is Delete, and a rest has no Delete row

The verb keeps its name and its plumbing — `EffectEditSession.delete_event` through
`_run_lane_verb`, like every other channel. Under this rule delete and "make it a rest"
are the same act, so **deleting a rest is a literal no-op and the context menu does not
offer it**: a grey bar's menu has no Delete row. The only way to remove silence is to
make it not silence.

**Rejected — merging a deleted span into an adjacent rest.** It is the one place a
consume could sneak back in, and it would collapse the segment boundaries that interior
opcodes ride on (§4).

The DAW corroborates the whole shape: `handle_time_lane_note_delete` calls
`replace_note_with_rest_by_authored_index`, which rewrites the span with `total_ticks`
unchanged and `relative_key = 13` — delete is *literally* "replace note with rest"
there, and the tiling invariant is enforced in one place by
`normalize_authored_spans_for_edit`.

### 7. The clock-moving verb is length, not delete — and its rule is already written

Delete cannot change a track's tick total. Neither can inserting a note into a rest
(it splits one). The **only** verb that could is editing a span's length, so
*"silence-in-place vs ripple"* was parked on the wrong verb. Its rule transfers from
ADR-0095 with nothing invented, now that rests are the lane's grey tiles:

| ADR-0095 | here |
|---|---|
| invisible tiles are consumed, cascading to the far edge of the run | a note grows by eating the run of rests after it |
| visible tiles are walls | the next **note** clamps — never deleted |
| *"empty space isn't data; consuming it is a re-timing"* | rests are that space |
| ripple = the session-local toolbar toggle (ADR-0087 2nd amendment) | unchanged; skips the trade |

The DAW independently lands on the same law: `set_fermata_extension_by_authored_index`
refuses with *"Note resize exceeds covered span"* rather than shifting a tail, and
`insert_time_into_authored_spans` is a **separate, explicitly-named verb** for the case
where you do want everything after to move.

**Decision: the rule is recorded here; the encoding is parked** (below). That closes
the 18b bullet rather than moving it — what stays open shrinks from "what does delete
mean" to one encoding detail on a verb that does not exist yet.

### Build notes (written before the build)

- **Every path that writes bytes must re-derive the opcode verdicts.** ADR-0087's sixth
  amendment states this as an invariant and this is a new such path: delete a note span
  and the voice writes inside it become writes with nothing sounding, which is exactly
  what the verdict system calls `Muted`. The studio then greys them without anyone
  designing a feature for it — but only if the verdicts are re-derived, and it is a
  silent wrong answer if they are not.
- **The span fold layers over the event list, it does not replace it.** `_project_events`
  gains spans; `FedsOpcodeVerdicts`, `_stamp_owners` and the panel's addressing keep
  keying off decode-order `event_index`. The panel still draws every byte — honesty is
  not traded away — but the time lane's **verbs** address spans.
- **`_advances_the_clock` stays as the gate**, and stops being a refusal: it becomes the
  predicate that routes a delete to the span substitution instead of to the byte splice.

### Built (2026-08-19) — three things the design did not settle

Built across `ffb0290fe..HEAD`, in the amendment's own order. Everything above held;
these are the answers the code had to supply.

1. **A Fermata after a rest is silent time, and the corpus never asks.** The fold's
   rule needs one more clause than §2 spells out: `0x80` *closes* the open note span,
   so a Fermata following one has no note to be more of and becomes a rest span of its
   own. Measured over all 2008 FEDS tracks: **zero** occurrences. It is a guard, not a
   path. (The 24 Fermatas that sound with nothing playing all sit before any note.)

2. **The fold does NOT stop at a flow opcode**, because 404 spans would break if it
   did: 191 have a `Coda` between the note and its Fermata, 186 a `Repeat`, 8 a loop
   marker. Under a loop the reading is genuinely ambiguous (which pass is the Fermata
   more of?), but the substitution preserves ticks *per pass* regardless, so the clock
   is right in every reading — and the fold matches what `_project_events` has always
   done. Linear decode order, no loop awareness, no new claim.

3. **The `0x80` retrofit changed an audible measurement, and the old number was the
   artifact.** The E001 no-op A/B guard asserted "faint ≈ 0.0245, a sub-audible floor
   from the empty-instrument note-ons". Track A's raw peak in isolation is **0.0117**,
   so removing it cannot move the mix by 0.0245 — the old figure was measuring the old
   *substitute*. A note-form rest goes down `advance_track`'s NOTE path (inline
   `accumulated +=`); `0x80` dispatches through `_process_opcode` and **returns**, the
   FFT-faithful pre-Note Rest exit at PC `0x8001588C` the tempo-drift work put there.
   Substituting every note of a wholly-Muted track with the invented form deleted every
   one of those exits and re-batched the track's cadences. On the capture SPU:

   ```
   Δ(baseline, note-form rest)  0.2562        isolated raw peak  A 0.0117  B 0.0465
   Δ(baseline, 0x80 rest)       0.0295
   Δ(note-form, 0x80)           0.2456
   ```

   With the corpus's rest the answer is the one the static classifier predicts: track A
   is silent in isolation, so pruning it reads **inert**. §1 is corroborated harder than
   it claimed — `0x80` is not only the better notation, it is the form the runtime
   dispatches faithfully.

Also settled in passing: `FedsPrunePersistenceTest`'s tick guard counted only
`NoteEvent.delta_time`, so it was blind the moment the substitute became an opcode — it
now counts the whole clock. And the delete refuses a span **segment** addressed instead
of its head, alongside §6's rest and the tie: a Fermata inside a note is not a span.

### Parked

- **Which segment absorbs a length delta**, and **what happens to an interior opcode when
  a shrink crosses its split point.** This is the whole of what remains from the 18b
  bullet. It wants a prototype against real spans before it is designed.
- The 18b amendment's other parked items are untouched by this one.

## Amendment (2026-08-19) — the un-rest: delete's inverse, and what a rest cannot keep

Built the same day it was decided; nothing here was parked. 18c §6 ended on *"the only
way to remove silence is to make it not silence"* and then did not build that verb, so
the delete that shipped the day before had **no inverse but Ctrl+Z**. This is that verb.

### 1. The corpus chooses the note, so there is nothing to design

An un-rest has to write a velocity and a key that the rest does not carry. Measured over
every FEDS track:

```
notes                        6234
distinct velocities             1     (96 — every note, no exceptions)
key C (relative_key 0)       3143     50.4%, the most common by 6×
```

**There is no velocity to choose.** FFT's effect notes have exactly one, so the un-rest
writes 96 and the inspector's velocity row is the place to disagree. The key defaults to
**C** on the same evidence, and unlike the velocity it is a one-click bounded edit
(`note_key`) immediately afterwards — a starting point, not a verdict.

### 2. One span in, one span out

```
80 pp   →  vv dd      (pp is one of DELTA_TIME_TABLE's 18 values — 713 of 779)  same size
80 pp   →  vv 00 pp   (the other 66 — the explicit-duration form)         one byte larger
```

The smallest form that says the length **exactly**; the tick count is the one thing the
verb must not round. Symmetric with the delete, which grows nothing and shrinks the 465
explicit-duration notes by one byte.

**A rest span is always ONE segment**, which is why one note replaces it and the event
count, the ordinals, the verdict keying and the selection all sit still exactly as they
do for a delete. That falls out of `fold_spans`: silence closes the open note, so nothing
ever extends a rest. (A `0x81` after a `0x80` is therefore a rest span of its own — 18c's
`### Built` §1 guard, zero corpus occurrences.)

Refused, never silently reshaped: a **note** span (already sounding — the no-op in this
direction), a span **segment** addressed instead of its head, a span headed by a **tie**
(undesigned in both directions), and a **zero-tick** span (no length to sound; deleting
the corpus's one 0-tick Fermata is the only way to make one).

### 3. What the pair cannot round-trip, said out loud

Delete → un-rest is **byte-identical** for the corpus's own note — velocity 96, key C, a
duration the table can spell. It is not for any other key: the rest held the ticks and
never the key, so a deleted `B2` comes back a `C`. That loss happens at the **delete**,
not at the un-rest, and it is why undo still exists. E482 pair 0's 218-tick C survives the
round trip byte-for-byte in the e2e probe; E001's `C#4` and E026's `B2` come back as Cs.

**Rejected — un-resting a rest that follows a note into a `0x81 Fermata`**, handing its
ticks back to the note before it. That is the parked length verb (18c §7) wearing this
verb's name. The un-rest writes a note, as `replace_rest_with_note_by_authored_index`
does in the DAW.

**Rejected — carrying the deleted note's key in the rest** (a sidecar, or the note-form
rest's key field). The rest is the corpus's `0x80`, which has no key field; inventing a
place to hide one would re-open exactly what 18c §1 closed.

### 4. The surface: every span has exactly one time verb

A note span's menu offers **Delete**; a rest span's offers **Sound `Rst48` — C, 48 ticks**.
Neither offers both, and the row names what it will write, the way the Add row names its
anchor (18b §2). `EffectEditSession.unrest_event` → `SoundDefChannel.unrest_event` is the
third structural verb through the same choke point, so snapshot undo, the FEDS re-derive
and the verdict refresh are the delete's contract verbatim.

### 5. Two corrections to what is written above

- **18c §4's substitution table mis-spells the explicit-duration note as `vv F7 tt`.**
  `F7` is `13*19 + 0` — key 13, i.e. the **note-form rest**, the form §1 established FFT
  never writes. An explicit-duration NOTE is `vv kk tt` with `kk = key*19` (key 0-11);
  the corpus's 465 of them carry keys 0-11, 335 of those C. The delete's behaviour is
  unaffected (it reads the decoded event's size, never that byte), but the un-rest had to
  write the byte, so the error surfaced. Corrected in `SoundDefChannel`'s docstring too.
- **`probe_feds_structural_e2e`'s save round-trip fails on CODE-format effects**, not on
  E317 specifically: E482 is `is_code_format` too (`header_offset` 2000) and fails
  identically at `16949844a`, before this build. Use a non-CODE effect — **E001** or
  **E026** — for that probe's round-trip claim.

### 6. The length verb was reachable through a costume — closed

18c §7 named the length verb, transferred its rule from ADR-0095 and **parked its
encoding**. The inspector was shipping it anyway: "Note duration" was a bounded enum over
the 18 delta-table values (and, for the explicit-byte form, a *free 0-255 int*). Same-size,
so it read as a parameter — but not same-**time**: changing it re-timed the span and slid
every later event, with no ripple rule and no tell. It was the only verb in the studio that
could move a track's clock, and the only one nobody had designed.

**The row is now a TELL**, for both forms: it still shows `16 ticks · 0.167 s (+144 held —
the span is 160)`, and the tooltip names where the verb went. `note_delta_idx` is refused
at the encoder too, because a `field_ref` can be built by any tool. Nothing about editing
what *sounds* is lost — delete (rest it), un-rest and the note-key edit all hold the clock
still.

**And the measurement says §7's rule is not ready to be built.** Its currency is the run of
rests after a note:

```
note spans                       6234
  followed by a NOTE             3983     no rest to eat — growth clamps immediately
  at the end of the track        1900
  followed by a REST              351     5.6%, median run 18 ticks
multi-segment (a fermata inside) 1619     the parked "which segment absorbs it" case
```

Implementing §7 literally today would give the author a verb that refuses 94% of grows.
That is not an argument against the rule — it is the evidence that effects are not music
here (the corpus writes 779 rests against 87,014 in the songs), and that the length verb
wants the prototype 18c asked for before an encoding is chosen. **Parked deliberately, not
by omission**, and now unreachable while it is parked.

### Parked (unchanged)

18c's two parked items are untouched: which segment absorbs a length delta, and what
happens to an interior opcode when a shrink crosses its split point. Inserting a note
INTO a rest (splitting it) is still unbuilt, and still wants the byte-boundary-vs-tick
addressing question answered first — an insert changes the event count, so 18c §4's
"the ordinals sit still" does not carry over to it.

## Amendment (2026-08-19b) — the sound lane drags: a rest's tick count is the editable number

The un-rest closed delete's inverse and left one hole: **no verb puts new time into a
track**. The queued item was "insert a note into a rest, splitting it," parked on the
byte-boundary-vs-tick addressing question. That question dissolves, and answering it
turned out to open a bigger and more coherent item — the one the author asked for the
moment the split was described: *"you mean I won't be able to drag notes to move them?"*

No. The FEDS pair lane has **no drag at all** today: `_gui_input` handles select,
context menu, ctrl+wheel zoom and middle/shift-drag pan. Every structural edit is a
context-menu row. This amendment designs the lane's drag, of which the split is one
gesture of three.

### 1. The addressing collision does not exist inside a rest

18b §4 anchors an insert to a byte boundary because zero-tick opcodes stack — E317
pair 0 has four events at tick 0, so "insert at tick 0" cannot say which of four
boundaries is meant. That cannot arise inside a rest. `fold_spans` gives a `0x80` no
way to be extended (`sounding` is false, so silence always opens a new span), which
makes a **rest span exactly one two-byte event with no interior**. There is nothing to
disambiguate, and the address is the hybrid the DAW already uses: the span head's byte
offset, plus a tick offset within it — span identity for the anchor, ticks for the
position, exactly as `replace_rest_with_note_by_authored_index` takes
`(authored_span_index, start_offset_ticks, duration_ticks)`.

### 2. Two of the three gestures touch no note at all

The DAW's primitive is *paint a note over a tick range* (`rewrite_authored_spans`:
clip, insert, normalize). That is not this lane's primitive, because on this lane a
move is not a paint — it is arithmetic on the rests **around** the note:

| gesture | what it writes | note bytes touched |
|---|---|---|
| **move** (body drag) | leading rest `a+k`, trailing rest `b−k` | **none** |
| **resize** (edge drag) | one flanking rest `b∓Δ` | the duration byte |
| **paint** (drag inside a rest) | one rest → rest · **note** · rest | creates one |

A move rewrites two `0x80 pp` params, both same-size: it **never relocates a byte and
needs no encoder**, making it the cheapest verb of the three rather than the middle
one. Where there is no rest on the side being moved into, the rest is **inserted**;
where one reaches zero it is **spliced out** — insert-or-grow on one side, shrink-or-
delete on the other.

So the lane's editable number is **a rest's tick count**, which is ADR-0095's *"a
boundary is one stored number"* landing here with nothing invented.

**Rejected — mirroring `rewrite_authored_spans`' paint signature.** This repo has
mirrored the DAW's *model* twice and been right both times, but the model is the span
tiling, the single enforcement point, and ripple as a separately-named verb — not the
signature, which exists because the DAW has a piano roll to drag on. Painting would
express a move as "clip whatever I overlap," i.e. as authorised destruction of a
neighbour, which §3 forbids.

### 3. The law: a drag may re-time silence; it may never move an authored event's firing tick

ADR-0095's *"a drag consumes empty space but never authored work"* transferred. 18c §7
already carried over its table for the length verb; this generalizes it to the gesture
and adds a third wall the colour lanes do not have:

- **A rest is the currency.** Consumable, cascading to the far edge of a run of
  consecutive rests.
- **A note is a wall.** Clamped against, never shortened by someone else's drag, never
  deleted.
- **A zero-tick opcode is a wall too.** Rewriting a rest's `pp` ahead of an `Instrument`
  changes *when that instrument changes* — a silent re-timing of authored work that the
  author never touched. This is why reach cascades only through a run of rests with **no
  opcode between them**, and why "the run" must be measured that way everywhere.

One place this lane is strictly better off than ADR-0095's: a rest consumed to zero is
**spliced out**, so adjacency IS expressible. The colour lanes' "1-frame spacer you can
never remove" (`ColorLowering` cannot encode zero) has no analogue here.

**The clock never moves.** All three gestures preserve the track's tick total — a move
by construction, a resize because its flanking rest absorbs the delta, a paint because
`a + d + (N−a−d) = N`. Putting *new* time into a track remains an unbuilt, separately
named verb, as `insert_time_into_authored_spans` is in the DAW.

### 4. The corpus is packed wall to wall, and that is the staging argument

```
note spans                                    6234
  rest on neither side                        5932    95.2%
  rest on the right only                       216
  rest on the left only                         53
  rest on both sides                            33
  movable at all (>=1 adjacent rest)           302     4.8%
  single-segment with a rest to its right      183     (resizable)
rest spans                                     803    801 of >=2 ticks (paintable)
rest runs, contiguous with no opcode between   1x610 · 2x77 · 3x13
multi-segment note spans                      1619    1279 carry an interior opcode
```

FFT packs notes end to end, so under §3's law **move and resize are no-ops on 95% of
the pristine corpus** — there is no currency to spend. That is not an argument against
them; it is the measurement that says which gesture carries the session.

**Delete is the rest factory.** The verb that shipped 2026-08-18c turns any note span
into rest span(s), so the paint's reach is not the 803 rests that exist but every span
of >=2 ticks — **6901 of 7037**, two clicks away. And {delete, un-rest, paint} is
*complete* for retiling a track's clock: `rest(N)` → paint → `rest(a)·note(N−a)` →
un-rest the head → `note(a)·note(N−a)`, each key then a one-click bounded edit. Any
tiling, any granularity, without a drag existing at all.

This corrects the framing the previous session left behind, which counted 779 `0x80`s
in the pristine corpus and asked whether a verb with so few places to act was worth
building. It measured the corpus at rest, not the corpus under editing.

### 5. The drag reads its tick from the bar, not from the axis

`_place_span_bars` projects **seconds** through the shared axis (`_sec_x`), and
seconds come from a tempo map. Inverting x → seconds → ticks would need that map. It
does not have to: a span is drawn as ONE linear rect from its start to its end, so
interpolating within the grabbed bar —

```
tick_offset = round((x - rect.position.x) / rect.size.x * span_total_ticks)
```

— is by construction consistent with the picture the author is pointing at. **What you
see is what you get**, and no second projection can disagree with the first.

It is also exact, not merely consistent: **the FEDS corpus contains zero `0xA0 Tempo`
and zero `0xA2 TempoSlide` opcodes** across all 1998 byte-owning tracks. Ticks and
seconds are one constant per track, so the linear read has no error term to bound.
(Music is a different matter; this claim is scoped to FEDS.)

**Rejected — locating a span by pixel x across an edit.** The axis re-anchors after a
structural verb, so a pre-edit rectangle addresses a different span afterwards. The
pixel is read **once, at grab time**, and converted immediately to `(event_index, tick
offset)`; every later stage of the drag and the verb itself speak ticks.

### 6. The surface: grips on the ends, body in the middle, and the menu keeps its rows

ADR-0095's split 9 px band, transferred: centred on the boundary, grabbing left of the
line roots on the left tile, right of the line on the right tile, and **either grab
writes the same number** — the rest's `pp`. Grips belong only to spans that have
currency adjacent; a note walled on both sides draws none, which is honest (95% of the
corpus) rather than a phantom handle over a drag that cannot move.

Three gestures on the bar:

- **inside a rest bar** — drag out a range → paint a note there
- **a note bar's interior** — drag → move it through silence, clamping at walls
- **a note bar's end grip** — drag → resize, eating the rest beside it, clamping at walls

The context menu keeps every row it has. `Delete` and the un-rest's `Sound Rst48 — C, 48
ticks` are not replaced by the drag: they are the precise, zoom-independent way to say
"all of it," and 18c §6's *"every span has exactly one time verb"* still describes the
menu. The drag is the imprecise, direct-manipulation path to the same verbs.

**One drag is one undo**, restoring the consumed rests byte-exact — the same coalesce
ADR-0095 §4 relies on (`EffectEditSession` captures a channel snapshot before dispatch
and the drag keeps the FIRST stash).

### 7. Order of work

Staged, and the stages are independently shippable. A pure planner comes first in each,
mirroring `BoundaryDragPlan`'s shape — spans in, new tiling out, no `EffectData`, no
scene — so the law is guardable without a paint.

1. **Paint into a rest**, as a verb + a menu row. `SoundDefChannel` gains the split;
   the note encoder is lifted from `unrest_event`, not re-derived. This is the stage
   that unblocks authoring, and it needs no drag.
2. **`SoundDragPlan`** — the pure planner: `(spans, grabbed span, desired ticks)` →
   the new tiling, with §3's walls and the clean-run cascade. Guarded alone.
3. **The gesture** on `FedsPairLanePanel`: grips, body drag, the tick read of §5, and
   the drag coalesce. Wires stage 2 to stage 1's verb.
4. **Move**, then **resize**. Move first: it writes two same-size params and relocates
   nothing.

### Built (2026-08-19b, stage 1) — four things the design did not settle

Stage 1 of §7's order — the paint verb and its pre-drag surface — built across
`d1b7b43a9..18f496775`. Everything above held; these are the answers the code supplied.

1. **The un-rest and the paint are one gate.** They differ only in WHERE inside the
   silence the note lands, so `_grab_rest_span` is now both verbs' preamble and their
   refusals are provably the same set — a segment addressed instead of its head, a span
   that already sounds, a tie head. The paint adds three of its own (offset before the
   start, zero duration, a placement past the last tick) and `_encode_note` is shared, so
   `paint(0, N)` cannot disagree with the un-rest about a byte. That is now a test, not a
   claim.

2. **No deadzone at the span head, deliberately.** A grab one pixel in genuinely is one
   tick in, and the first instinct was to snap it to zero. Wrong: the un-rest row sits on
   every grey bar whatever the grab, so *"all of it"* never depends on pixel-perfect aim —
   which leaves a one-tick grab as the real, distinct edit it is. The paint row is
   suppressed only at exactly zero, where it would duplicate the un-rest.

3. **Zero tempo opcodes in the corpus** — `0xA0 Tempo` and `0xA2 TempoSlide` both occur
   **0** times across all 1998 byte-owning FEDS tracks. §5's linear read off the bar was
   argued as *consistent* with the picture; this makes it **exact**, with no error term.
   (Scoped to FEDS. Music is a different matter.)

4. **`studio_undo` on the host only refolds.** FEDS bytes are sound, not the folded
   framebuffer, so undoing a structural sound_def edit through the host method alone
   leaves the pair panel drawing the pre-undo tiling. `EffectStudioPage._undo` already
   re-points the cached env and re-derives the pair views — the prune's path, which every
   FEDS structural undo needs. Not a product bug; the e2e probe was calling the wrong one
   of the two, which is worth knowing before the drag adds a third caller.

The pre-drag surface is the menu row, and it takes only ONE number: the grab gives the
offset, and the duration is always the remainder. That is not a compromise waiting for
the drag — with delete it already composes to any tiling (paint to the end, delete the
note to rest it, paint the second rest), so stage 1 ships the complete authoring surface
and stages 3-4 make it direct rather than possible.

### Built (2026-08-19b, stages 2-4) — the drag, and five things the design did not settle

§7's remaining three stages built across `f0d…` (see `git log`). The staging held, with one
order change and no design change: **stage 4's verb was built before stage 3's gesture**,
because the surface needs something to call and stage 2 had already settled the interface
the ADR left open. The order §7 gives buys nothing once the planner exists.

Everything above held. These are the answers the code supplied.

1. **The deposit side needs the same wall check as the consume side, and §3 did not say
   so.** §3 argues the third wall from the spend direction — *rewriting a rest's `pp` ahead
   of an `Instrument` changes when that instrument changes* — and the run-cascade honours it.
   But the ticks a drag spends have to go somewhere, and growing the nearest rest on the
   OTHER side is the identical bug facing the other way: `rest(a) Instrument note(d)` grown
   on the left would push the Instrument to `a+k`. So a deposit grows the rest already
   **touching** the note, and where the thing touching it is an opcode or the track edge it
   writes a NEW rest **byte-adjacent to the note**, ahead of that opcode. `Instrument
   note(16)` moved right becomes `Instrument rest(k) note(16)`. That is a test, and it is
   the one rule the pure planner could not enforce alone — it is about a byte position, not
   about ticks.

2. **The grip band's width does not transfer; its centring does.** ADR-0095 §1 rejected
   insetting the band with a specific argument — a 1-frame stub is a couple of pixels wide
   and insetting would kill click-to-select. That argument is about ONE gesture per tile.
   A bar on this lane hosts **two** (the body moves, the edge resizes) and a rest bar hosts
   the paint, so a full 9 px band on a 6 px bar swallows the body drag whole. The band is
   therefore **capped at a quarter of the narrower of the two bars it straddles**, and below
   1.5 px of half it is not drawn at all: that bar has no room for two gestures, and the
   menu row is the zoom-independent way to say the same thing (18c §6). Centred-on-the-
   boundary transfers unchanged — the rest's first pixels resize the note to its left and
   its last pixels move the next note's start, both writing that rest's `pp`.

3. **A drag clamped flat must still SWAP.** The pristine re-plan restores the pre-drag bytes
   before every re-dispatch, so a motion that plans to zero has just *undone* the previous
   motion — returning `{}` (the natural "nothing to do") leaves the pair views drawing the
   stale tiling. `drag_event` therefore swaps the track even when the plan writes nothing.
   This is the same class of trap as the fourth 19b stage-1 finding: FEDS bytes are sound,
   so nothing re-derives unless the verb says it did.

4. **`_structural_verb` needed the bracket half of ADR-0095 §4, which only `apply_edit` had.**
   The scalar choke point already restored the bracket's first snapshot before each
   re-dispatch; the structural path pushed a fresh snapshot per call, so a drag would have
   been N undos deep and every motion compounded on the last one's splices. Both halves now
   live in `_structural_verb`, and `_ref_key` carries `track_idx` + `at` so a FEDS bracket
   is keyed to the span it grabbed.

5. **A left grip on a multi-segment span is provably safe, and stays refused.** Growing a
   span leftward moves only its START, and the HEAD segment is the forced absorber — an
   interior opcode's absolute firing tick is unchanged (`rest(a) note(16) Port Ferm(144)` →
   `rest(a-Δ) note(16+Δ) Port Ferm(144)`, and the Portamento still fires at `a+16`). So §8's
   park — *which segment absorbs a length delta* — genuinely does not bite on that edge.
   The resize refuses it anyway, on both edges, because one rule per verb is worth more than
   the 1619 extra spans, and because the claim above is arithmetic that has not been heard.
   Recorded here so the next session does not re-derive it.

**Move and resize are no-ops on 95% of the pristine corpus, and the surface says so** rather
than drawing a handle over it: a note walled on both sides owns no grip, and a press on its
body arms **nothing** — it stays a plain selection. A live drag writing zero every motion
would read as a broken handle; nothing at all reads as a wall. The paint is still the
gesture that carries the session, exactly as §4 predicted.

The e2e probe reports the drag as a **tiling**, per §5's own rule about counts:

```
grips on the lane: 5r
armed a move on `C2 · v96` (24 ticks; currency 0 left / 75 right)
tiling: note24 rest75 → rest75 note24   (asked +400 ticks, the law wrote +75)
tiling: → rest8 note24 rest67   (same grab, +8 ticks — re-planned, not compounded)
tiling: → note24 rest75   (dragged back; pristine again: true)
one drag, one undo: rest75 note24 → note24 rest75 (pristine: true)
```

The middle line is the one prose cannot establish: +8 from the same grab reading
`rest8 note24 rest67` is proof the motion was planned against the pre-drag 0/75 rather than
compounded on the clamped 75/0.

**Still unbuilt on this lane:** creating a bank / track / pair, and §8's list below, which
this build leaves exactly as it found it.

### 8. Parked, and why

- **Which segment absorbs a length delta** on a multi-segment span (18c). Unchanged.
  **1619 of 6234** note spans are multi-segment and **1279 of those carry an interior
  opcode**, so guessing would re-time authored work on a fifth of the corpus. Resize
  therefore **refuses multi-segment spans** — explicitly, not by omission — which still
  leaves 4615 single-segment notes resizable.
- **What happens to an interior opcode when a shrink crosses its split point** (18c).
  Unchanged, and now unreachable: §3 makes such an opcode a wall, so a shrink clamps
  before it rather than crossing it.
- **Putting new time into a track** — appending past the end, or growing the clock.
  ~~Every verb on this lane holds the clock still; this would be the first that does not,
  and 1900 of 1966 tracks end on a note, so there is not even a trailing rest to paint
  into.~~ **BUILT 2026-08-19c as the OUTRO** — see that amendment, which also corrects the
  measurement quoted here (19 tracks DO end on a nonzero trailing rest; none end on a
  zero-tick one).
- **Move on a span with an interior opcode.** A move translates the whole span, so an
  opcode *inside* it travels with the note. That is probably right — it is the note's
  own articulation — but it is a claim about firing ticks that §3's law does not
  license, so move refuses it until it is measured against audio.

## Amendment (2026-08-19c) — the outro: where new time comes from, and the costume that was already writing it

19b §8 named *"putting new time into a track"* and left it unbuilt, on the grounds that
every verb on this lane holds the clock still and *"1900 of 1966 tracks end on a note, so
there is not even a trailing rest to paint into"*. That was the last ceiling on
from-scratch authorship. This builds the verb — and finds that a control shipped one
amendment earlier had been doing it anyway, unlawfully.

### 1. Two corrections to the corpus this session ran on

Measured over all 401 banks with `parse_effect.parse_feds_blob`, skipping `offset == 0`:

```
byte-owning tracks                          2008
  own ZERO bytes                              10
  terminated (a decoded 0x90 EndBar)        1928
  STUBS (no EndBar — they borrow forward)     70
tracks ending on a NONZERO trailing rest      19    11 terminated + 8 stubs
tracks ending on a `80 00` zero-tick rest      0
last event before a terminated track's outro:
  Fermata 813 · note 618 · zero-tick Coda 482 · other zero-tick opcode 15
```

- **The stub count is 70, not 80.** The extra ten are byte-owning tracks that decode to
  no events at all — a third thing, neither stub nor null slot.
- **Trailing silence exists.** `E015` t2 ends `81 18 | 80 24 | 90` (36 ticks), `E481` t3
  ends `60 dd | 80 4b | 90` (75), `E259` t0 ends `99 | 80 78 | 90` (120). The claim that
  every rest-terminated track ends on a *zero-tick* rest is false; there are **zero** `80
  00` tails anywhere. The reach conclusion is unchanged — 11 of 1928 is not a hatch — but
  the paint has always reached those 11, and the one used as this session's e2e case
  (E026 p1) is among them.

### 2. The outro is a number at the end of a track, not an event

**The outro** is the run of `0x80` rests between a track's last authored event and its
`0x90 EndBar`. Writing there re-times nothing: the new bytes go in front of the
terminator and *after* every zero-tick opcode the track ends on, so no authored event's
firing tick moves — which matters because 482 tracks end on a `Coda` and 15 more on
another zero-tick opcode. The run therefore **stops at the first non-rest**, exactly as
the drag's cascade does (19b §3's third wall): `note Coda rest(120) EndBar` has a
120-tick outro; `note rest(8) Coda EndBar` has none.

The verb takes an **absolute** count, not a delta. One number means trim is set-to-zero,
a repeat is a no-op, and the surface's "+48" is arithmetic the surface does. It is the
only verb on this lane that moves `end_tick`.

**Nothing outside the track cares.** A pair's two voices are separate bytecode streams on
separate clocks; lengthening one moves neither the other's ticks nor any other track's.
What does move is the pair band's axis, which is `max(end_tick)` over the two — that is a
re-derive, and the structural result already carries it.

### 3. A stub is refused, and the refusal has a path

A stub has no terminator, so its own stream stops at a byte edge and everything after it
is **borrowed** from the next track (`feds_bank.gd:144` — FFT's walker has no per-track
boundary concept; the `0x90` is what terminates a track). Silence written at that edge
pushes another track's authored work later **in ticks** — §3's law broken from the one
direction §3 never faced, the same shape of mistake as 19b's first build finding.

Refused, and the refusal names its own fix: `insert_event` already offers `EndBar` **only**
at the phantom boundary (`FedsOpcodeCatalog.can_insert`). Say where the track ends, and
then it has an end to lengthen. 70 tracks.

### 4. The surface is the track's END, because there is no bar to point at

The five shipped verbs are span verbs: you point at a bar. The outro has no bar until it
exists, so it hangs off the one thing every terminated track draws — its terminator. A
right-click on the EndBar chip, or anywhere in the empty lane past it (which resolves to
the same anchor), offers **Extend**, hanging the corpus's own 18 `DELTA_TIME_TABLE`
lengths off a submenu the way the Add row hangs the opcode corpus, and **Trim**, which
appears only when there is silence and says the number it removes.

**Rejected — a grip at the track's end.** Nothing is drawn past the last bar to grab, and
the lane's axis is `max(end_tick)` over the pair, so dragging the longer track's end would
rescale the ruler under the cursor while the cursor chases it. The menu is zoom-independent
and exact — 18c §6's argument, unchanged.

### 5. The length verb's costume was still being worn — by the rests

§6 of the 2026-08-19 amendment closed `note_delta_idx`: a same-SIZE write that is not
same-TIME reads as a bounded parameter and is not one. **The same costume was still on the
other two forms that carry time.** `FedsParamSemantics` labels `0x80` "Rest (ticks)" and
`0x81` "Hold extra (ticks)", and `FedsPairProjector._param_fields` renders every
parameterized opcode's params as int cells — so the F1 inspector could retype a mid-track
rest's tick count, sliding every later event in that voice while the pair's other voice
stayed where it was. No law, no tell, no test, one amendment after the identical hole was
closed.

Both rows are **tells** now, and each names where its lawful verbs live rather than going
dead. The write is refused at the encoder too (`_is_time_carrying_param` asks the decoder
which byte it is), because a field_ref can be built by any tool — the same defence in depth
`note_delta_idx` got. The guard is exact: the velocity byte one position away still writes.

What is lost is real and deliberate: **mid-track insert-time** — making a gap longer and
sliding the rest of the voice — is now unreachable. See §7.

### 6. Built (2026-08-19c) — what the code supplied

1. **The one-function rule paid immediately.** `FedsPairModel.outro_of` is called by the
   lane's tell and by the verb's write, so the number drawn and the number written cannot
   disagree — and the surface's Trim row can name the count it is about to remove without
   a second scan that could drift from the first.
2. **Two silent fall-throughs, found by the first e2e run.** `EffectViewerScene.
   _studio_structural_verb` and `EffectEditSession._dispatch_structural`'s `sound_def` arm
   both ended in a bare `_: delete`, so the new verb ran a DELETE at an address built for
   something else and the probe printed "nothing changed" instead of an error. A verb added
   at the page without a case in both matches is silently a delete. Both name every verb now.
3. **The probe needed a new tell, exactly as 19b predicted.** Every verb before this held
   `end_tick` still by construction, so the tiling string said everything; `_clock` prints
   the tiling with the total and the outro beside it. On E026 p1:

   ```
   extend +48:       note24 rest75        [end_tick 99,  outro 75]
                   → note24 rest123       [end_tick 147, outro 123]
   painted into it:  note24 note24 rest99 [end_tick 147, outro 99]
   trim → 0:         note24 note24        [end_tick 48,  outro 0]
   the saved BIN re-parses to the edited track: true
   ```

   The middle line is the reach argument: the new silence is an **ordinary rest span**, so
   the paint that shipped in 19b sounds a note where FFT's track had no time at all. The
   last is the other direction — a track *shorter* than FFT wrote it, which nothing on this
   lane could do before.
4. **A defect this probe has had for longer, recorded rather than hidden:** its mid-run
   PNGs are wrong under a tiling WM. `page.get_window().size = 1500x1000` does not take, so
   the captured viewport is 626x1390 while the pair panel's global rect is 943 wide — the
   crop clips and what gets saved is the timeline above the pair band. Every numeric tell is
   computed from the real layout's span bars and is unaffected.

**Where authorship stands now.** `{delete, un-rest, paint, drag}` retiles a track's existing
clock into any pattern at any granularity; the outro makes that clock **any length at all**,
in both directions. What no verb can still do is create a bank, a track or a pair — and 999
of 1009 corpus pairs already have both voices owning bytes, so "author a new sound" in
practice means "retile an existing pair", which is now fully expressible.

### 7. Parked, and why

- 19b §8's four parks are untouched: which segment absorbs a length delta, an interior
  opcode under a crossing shrink, move on a span with an interior opcode, and the
  provably-safe-but-unheard left grip on a multi-segment span.
- **Mid-track insert-time** — the DAW's `insert_time_into_authored_spans`. §5 closed the
  unlawful path to it; the lawful one is unbuilt. It is a different verb from the outro,
  and the reason it is harder is not the encoding (it is the same byte write) but the
  **two voices**: a pair is two streams FFT wrote to line up, and inserting time into one
  slides it against the other. That is a claim about what a pair should sound like, which
  is a thing to hear, not to derive. Named here so it is not mistaken for part of the outro.
- **The CODE-format save gap** — `FedsBank.load_from_file` cannot re-parse a CODE-format
  `E###.BIN`, so the e2e round-trip claim reads `false` on E317/E482 whatever the edit was.
  Persistence, not reach; unowned and worth an issue.

## Amendment (2026-08-19d) — a pair opens unrolled: decision 3's fold-default, reversed

Decision 3 chose **fold-by-default** for loops and listed *unrolled-by-default* under
"considered and rejected", on one ground: *"a large loop floods the lane on open;
fold-default + visible toggle answers 'not even unwound' without the noise."* The
2026-08-18 NoEnd phantom inherited the same default ("a borrowed span folds like a loop").

**Reversed, on the user's call, after living with it.** A pair now opens with every `Rep`
bracket unrolled in place and every stub's `Flow` phantom revealed.

The flood the rejection feared is already bounded and was when it was written: unrolling
draws at most `MAX_UNROLL_COPIES` (= `SoundGhostProjector.MAX_PIPS`, 96) event copies
panel-wide and never past the 30 s render ceiling, so the worst case on open is the same
worst case the unwind-all chip already produced in one click. The corpus says how often it
bites: **867 of 1998 byte-owning tracks carry a `Repeat`**, at 1–2 per track for 699 of
them, and the play counts cluster at 2–10 (max 192, which the budget truncates with its
existing tell). 70 tracks are stubs with a `Flow` phantom.

What is NOT reversed:

- **Both fold verbs stay reversible and per-loop independent.** The badge now folds an open
  loop on the first click instead of unrolling a folded one; the unwind-all chip still
  toggles the pair either way.
- **The pure `layout(view, width, state)` is unchanged** — it draws whatever fold state it
  is handed, and an empty state still means folded. The reversal is the PANEL's open state,
  which is where a default belongs; `_unwound_keys` is the one function the open and the
  unwind-all chip both call, so they cannot drift apart.
- **A same-pair re-derive after an edit still preserves the author's fold**, exactly as it
  preserves selection. Only opening a *different* pair re-unrolls.

**Known consequence, carried over rather than solved:** an unfolded phantom wants ~420 px of
band (the Parked "band's height" item). Opening a stub pair is therefore tall by default now.
That item is unchanged and still belongs to a different feature.

## Amendment (2026-08-19e) — the three verbs the author could not find

**Status:** Accepted. **Date:** 2026-08-19.

The author, working the finished pair lane, asked three questions:

> How do I change the note length, and how do I re-order opcodes? How do I add a note?
> Right clicking on the note band didn't seem to bring up an add note opcode — or anything.

Read against the code, the three split cleanly, and the split is the finding:

- **Note length** already has two lawful verbs — the end grip (19b) and delete → paint. The
  gap is that neither is *named* anywhere the author looks.
- **Add a note** cannot have a verb, ever: a note is a velocity byte below `0x80`, not an
  opcode, and 18c established that time is fully tiled, so a note can only be **taken** from
  a neighbour. It is a composition, and again the surface never named it.
- **Re-order** is the one that genuinely did not exist. It was delete + insert — and the Add
  menu re-inserts *corpus-mode* params, so a re-order silently reset the value the composer
  had typed.

And "…or anything" was not a broken menu. `resolve_context` returned a bare `{}` — no menu,
no message — for three real places on the panel that own no bytes: the label gutter, any
point in no lane rect, and a null slot. A right-click that resolves to nothing was **silent**,
which is the same failure §4 named for a silent pick among four stacked events, facing the
other way.

### 1. A refusal names the place it landed on

Each of the three silent returns now carries `refused: "<the place>"`, and the page turns it
into exactly one **disabled** row. The popup opens, so the gesture is answered; the row
carries no verb and no `track_idx`, so there is nothing on it that could be run. Same law as
"Add opcode after `Oct3` @ tick 0": *name what the click resolved to* — including when what
it resolved to is not a byte boundary.

### 2. Cut and paste — the re-order, and the params that survive it

**Cut is the delete that remembers the bytes it removed. Paste is the insert that writes
them back.** Both lower to verbs that already existed (`delete`, `insert`), so neither
dispatch seam grows a case; the clipboard is the page's, held across popups and across the
pair's two tracks, and is not persisted — it is a gesture's memory, not a document's.

Paste is offered on **both sides** of the anchor. That is not redundancy: 18b §4's whole
point is that zero-tick opcodes stack, so "before `Oct3`" (Oct3's own first byte) and "after
`Oct3`" (the boundary past it) are two different addresses at the same tick, and neither is
derivable from the other on the surface. Before every event there is no anchor to be either
side of, so the one row reads "at the start of this track".

Cut is offered **only where `can_insert` will take the same bytes back**. That excludes the
flow opcodes, `EndBar` included: a cut with no lawful paste is a trap, not a verb. It is
never offered on a span — a note is a velocity byte, and a span's time verbs are delete and
the paint.

Proven end to end on a real corpus track (`E026` pair 1, probe stage 3e):
`AC 86 AC 72 94 02 …` → `AC 72 AC 86 94 02 …` — the `Instrument(114)` moved ahead of
`Instrument(134)` **with its own param byte**, where the Add menu would have written the
corpus mode. Saved, re-parsed, byte-identical.

*Rejected: carrying the deleted event's params silently into the next insert.* It is smaller
and it is worse — the row would appear from nowhere and nothing would say it was tied to the
delete. *Rejected: a single "Move `X` after `Y`" verb with an anchor submenu.* Exact, but the
submenu is as long as the track's event list, and it cannot express "before".

### 3. The compositions, said out loud

Two verbs now name their consequence instead of leaving it to this document:

- **Delete on a span** reads `Delete `C · v96` — leaves 24 ticks of silence to sound`. That
  silence is the currency the paint spends, so the row is the first half of a composition the
  author can see through. A zero-tick opcode leaves nothing and keeps its bare row.
- **The corpus submenu** — where an author goes looking for "add a note", and therefore the
  one place the refusal can be explained at the moment of the wrong guess — opens with three
  disabled lines ahead of the 51 opcodes:

  > A note is not an opcode — there is no row that adds one.
  >   Inside the track:  Delete a span, then sound the rest it leaves.
  >   Past the end:  Extend the track, then sound the new silence.

### 4. Not re-opened

**Note duration as a typed field** stays refused (2026-08-19 §6), and **a "Set length…" row**
stays parked (18c §7). Neither question changed; only the discoverability of the verbs that
already answer it did. The 19b measurement stands on re-check: **302 of 6234** corpus notes
have byte-adjacent currency, **183** single-segment with a rest to the right, **1619**
multi-segment. Counting a run of rests *through* an intervening opcode gives 906 and 268 —
and would be wrong, because `SoundDragPlan.currency` treats a bare zero-tick opcode as a
**wall** (§3): re-timing silence in front of one changes when it fires.

## Amendment (2026-08-19f) — a fermata span owns two boundaries, and only one was reachable

**Status:** Accepted. **Date:** 2026-08-20.

Asked immediately after 19e shipped:

> The fermata opcode isn't displayed. What if I wanted to put an opcode after the fermata —
> or is this a strange thing to do?

It is not strange. **1534 of the corpus's 1619 multi-segment spans are followed immediately
by a zero-tick opcode** — 805 `EndBar`, 162 `Dynamics`, 107 `Instrument`, 45 `Coda`. It is
the ordinary place to write. It was simply **unreachable**.

### What the surface was doing

The fermata not being displayed as a chip is correct and stays: 18c §5 routes `0x81` to
`kind == "time"`, and the time lane draws time as **spans**, so the fermata is the amber tail
of the note bar. That fixed the complaint 18b created (E317's 160-tick C drawn as a 16-tick
bar plus an unrelated-looking Fermata chip beside `Octave`).

But it left the fermata with **no click target**, and `resolve_context` maps every hit on a
span bar — amber tail included — to the span **head**. So the bar's only address was
`ev.offset + ev.size`: the boundary after the head *note byte*, which is **inside** the
picture being pointed at. Measured on a fixture of `AC 05 | 60 0C | 81 30 | AC 07 | 90`:

```
Note C4  start_tick 0   span_note_ticks 12   span_total_ticks 60
Fermata  tick 12                    ← the interior boundary is here
next opcode  tick 60                ← the span-end boundary is here
row offered: "Add opcode after `C4` @ tick 0"   → writes at byte +4, fires at tick 12
```

The row was wrong twice: it read as "after this bar" while landing in the middle of it, and
the tick it named was the anchor's, not the tick the new opcode fires at. The boundary at
tick 60 had no row at all.

### The decision

**A multi-segment span offers both of its boundaries, as two named rows.**

- `Add opcode inside \`C4\` — before its Fermata, @ tick 12`
- `Add opcode after \`C4\`'s Fermata @ tick 60`

and the paste splits the same way, giving three addresses on such a span: before it, inside
it, past its fermata. A single-segment span has one boundary and keeps the row it always had.
The span end was always a legal boundary in `SoundDefChannel._track_context` — nothing on the
surface addressed it, which is why this is a naming fix with a one-line address behind it.

*Rejected: resolving by WHERE in the bar the click landed* — blue half → interior, amber half
→ span end. It matches the picture and needs no extra row, but a span can be 6 px wide, and
ADR-0095 §2 already established that a pixel-half is not a reachable target where a
zoom-independent menu row is. The bar keeps one hit region; the menu carries the split.

*Not offered: the boundaries between a span's inner segments.* 629 of 1619 multi-segment
spans have three or more, and 1967 interior opcodes sit deeper than the head-adjacent slot —
but an interior opcode that already exists **is** drawn as a chip on the opcode lane, so its
own two boundaries are reachable by clicking it. What was unreachable was a fermata's
trailing boundary with nothing after it yet, and the span end is that case, 1534 times over.
The bar also merges every fermata into ONE amber region, so offering per-segment rows would
name distinctions the picture cannot show.

## Amendment (2026-08-20) — the top panel's height belongs to the open target, not to the last click

**Status:** Accepted. **Date:** 2026-08-20.

> Clicking around on opcodes resizes the panel above it, which is annoying and distracting.

`_relayout` sized the inspector from `_inspector.content_height()` every time it ran, and on
a window with room the band arithmetic lands `editor_h` **exactly** on that number — so the
top panel's height *was* its content height. Two things then made every click move it:

- `_on_pair_event_selected` calls `_navigate_to(Target.pair(idx))`, which re-enters
  `_render_current()` and rebuilds the inspector from scratch. Clicking a sibling opcode is
  a full teardown and rebuild, and the rebuild passes through smaller intermediate heights.
- `content_changed` and `_pair_panel.minimum_size_changed` are both wired straight to
  `_relayout`, so each of those intermediate heights re-flowed the pair panel, the frames
  bar and every channel lane below.

Measured across `E026` pairs 0–5: content height is **stable within one pair** (every opcode
kind in a pair projects the same 335 px) but moves **327 → 355 px** across pairs and opcode
kinds. The visible motion was therefore mostly the rebuild transient, with a real 28 px step
whenever the root changed.

### The decision

**The top panel's height is a high-water mark per open ROOT target.** Within a root it never
shrinks — so no click, and no intermediate state of a rebuild, can re-flow the band. Opening
a different root starts the mark over, so a tall target cannot leave a permanent gap behind
it. An empty key (nothing open) tracks content exactly, so a cleared inspector still
collapses to nothing.

Verified live on `E026`: clicking every event of pair 0 produces exactly one latched value
(327), pair 3 exactly one (355), and returning to pair 0 gives 327 again rather than
inheriting 355.

*Rejected: quantising the content height to a step.* It shrinks the jump without removing it,
and it does nothing about the rebuild transient, which was the larger part of the motion.

*Not done: suppressing the redundant re-navigation itself.* `_on_pair_event_selected`
re-navigating to a root the page is already on is wasteful, and removing it would cut the
rebuild rather than absorb it — but it changes what a selection means to the inspector, which
is a separate decision from how tall the band is. The layout is now stable either way.

Two pure statics were lifted out of `_relayout` so the rule is guarded without a scene:
`_editor_band` (the inspector/panel contention, unchanged arithmetic — its contended case
computes 148/148 at a 296 px budget, which is what the running page measures) and
`_latched_editor_h` (the mark itself).

## Amendment (2026-08-21, design via `/grill-with-docs`) — the chain inspects as one page: seed the stack, render it whole

**Status: design settled, build pending.** No code lands from this amendment by itself.

### The question, and why the premise it arrived with was wrong

The ask was: *"we made a kind of all-in-one page for emitters — could we do this for sound,
showing the event-level, config-level and feds-level stuff all in one page?"* Sharpened by
the author in the session: **"when I click on a sound event, 99% of the time I want to go
straight to the FEDS data, but I have to click into 2 other things first because of the
hierarchy. The hierarchy is good — we just want to present it so we can view and edit it all
at once."**

The emitter surface is **not** a precedent that transfers, because it is not a precedent at
all in this direction. [ADR-0089](0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)'s
"Edit at the reference" decision says emitter fields become editable where they are already
shown, honest about shared-ness *"instead of inventing a separate editor screen"* — and then,
in its own words, **"Same shape as the SoundContainer precedent."** The emitter surface was
modelled on sound. (It is also not mechanically available here: `SequenceLifeMap`,
`ColourLifeColumn`, `TextureTabPanel` and the tab strip live only on
`feature/effect-studio-authoring`, which already conflicts with this branch in seven files at
the `EffectEditSession.apply_edit` choke point.)

So this is not a request to flatten three tiers into one model. It is a request to stop
*walking* them. **This ADR's title survives intact**: three projected surfaces, still not one
flattened ruler. Co-resident is not flattened — no edit moves onto a shared axis, the two
unsynchronized clocks stay unmerged, and each tier keeps its own projector.

### The fan-out, measured before arguing about it

Across all 402 effect dirs, driving the real mode table in
`addons/exmateria_sound/runtime/effect_sound_resolver.gd` (not re-deriving it). The script is
`tools/measure_sound_fanout.py` — **re-run it rather than re-quoting this table**. The session
that produced it first published figures three points off, because a dead `id` slot
(`id_b == 0` → `pair_idx == -1`, which is no pair at all) was counted as a second pair:

| | |
|---|---|
| effects with ≥1 firing event | 400 / 402 |
| total firing events (`sound_id ≥ 2`, index ≤ `max_keyframe`) | 1,077 |
| containers referenced by exactly **1** event | 810 / 921 = **87.9%** |
| containers emitting exactly **1** distinct pair | 827 / 912 = **90.7%** |
| pairs reached from exactly **1** container | 1,001 / 1,002 |
| events on a fully 1:1:1 chain | 765 / 1,077 = **71.0%** |
| effects where *every* chain is 1:1:1 | 297 / 400 = **74.2%** |
| median effect | 2 events, 2 containers, 2 pairs in bank |

Mode 0 (`Always Sound 1`) accounts for 786 of 912 references. **13 events across 9 effects**
(E005/6/7, E072, E325, E330, E335, E362, E363) point at a container index that does not
exist — `sound_id 13` → container 11 of 4.

The chain is therefore *usually* 1:1:1, and the asymmetry that survives is **not** the one
[ADR-0092](0092-effect-flags-author-on-the-effect-settings-surface-sound-channels-stay-in-their-container-view.md)
named. Its objection was the reverse-link *upward* (a container shared by N events) — that is
12.1% of containers. The awkward direction is *downward*: 85 containers emit 2–3 distinct
pairs, covering **15.3% of events** (165/1,077).

### The decision

1. **Seed the stack; do not collapse it.** Clicking a sound event sets the ADR-0073 nav stack
   to `[span, container, pair]` in one gesture, and the inspector renders **every** stack
   entry's sections in order, each under its own projector header. There is no new target
   kind, no new projector, and no duplicated section code — the three existing projectors are
   the three sections. See ADR-0073 dec. 11 for the generic mechanism and its opt-in rule.

2. **The ambiguous third slot seeds to the first fire.** Where the container emits 2–3 pairs
   (15.3% of events),
   slot 3 seeds with `SoundGhostProjector.resolve_pair_idx()` — a fresh resolver at count 0,
   which is **the same pair the timeline's ghost bar already draws**, so the page agrees with
   what the author was looking at when they clicked. A **dropdown** on the FEDS section flips
   slot 3 to a sibling, replacing that entry rather than appending to the stack.

3. **The dropdown labels by fire ordinal and slot only** — `1st fire · Sound 1 · entry 2` /
   `2nd fire · Sound 2 · entry 5` — built from `SoundContainerModel.fire_sequence()`, which
   already drives a fresh resolver to produce exactly this ordering. **No reachability claim
   is made** (see the runtime note below): the ordinal is true under either reading of the
   counter, so the surface stays correct however that question lands.

4. **Event and Container collapse to one summary line each by default**; the FEDS section and
   the `FedsPairLanePanel` own the vertical budget. This is the decision the ask actually
   turns on — the naive build makes the FEDS view *smaller* than it is today, because
   `_editor_band`'s budget is `h − MIN_CHANNELS_H(180) − BAR_H(30)`, the pair inspector alone
   already measures 327–355 px, and Event (4 cells) + Container (3 pickers + a 5-row mode
   radio + Audition + pair links) push the three sections past the budget, at which point the
   panel takes its `budget × 0.5` floor and squeezes the inspector below what the pair section
   gets on its own. **The collapsed Container line carries `used by N triggers`**, which is
   what keeps ADR-0092's property alive.
   *This one is settled by looking, not by argument* — verify headful at a real window size,
   on `page._editor_latch` state, never on a probe screenshot (a studio probe window never
   reaches the size asked for and sits in the 50/50 clamp where the band is independent of
   content, so a layout bug is invisible there).

5. **An explicit fold toggle resets `_editor_latch`.** The 2026-08-20 amendment made the top
   panel's height a high-water mark per open root, precisely so a rebuild transient could not
   re-flow the band. A deliberate collapse is not a transient: without a reset, expanding then
   collapsing the Container section would leave a permanent gap for that event. The latch must
   distinguish the author's toggle from the rebuild it was built to absorb.

6. **The links become anchors, and the breadcrumb goes.** With the chain on screen, the
   trigger's `Plays → container N` cell and the container's `→ bank entry N` cells navigate to
   something already visible; they degrade to scroll-to anchors. `_breadcrumb_rows` suppresses
   for a chain stack — `Path › Event › Container` is redundant with the sections themselves.

7. **Degenerate chains are short, not special-cased.** A `sound_id` naming a container that
   does not exist seeds a 1-entry stack with an honest tell. A pair opened from anywhere else
   is a 1-entry stack and renders exactly as it does today.

### Why this answers ADR-0092 rather than routing around it

ADR-0092 rejected *flat sound-channel rows on the Effect Settings surface* because that
"would duplicate the container view and lose the reverse-links." Both halves are avoided by
construction: there is still exactly **one** `SoundContainerProjector` — it is the section —
so nothing is duplicated, and it still emits its own `Used by N triggers` header, so nothing
is lost. Its ruling is **answered, not overturned**, and the corpus is kinder to it than
either side assumed: 1,001 of 1,002 pairs are reached from a single container.

### Costs that turned out not to exist

**Three address spaces on one page is free.** `EffectEditSession._dispatch` matches on
`field_ref.channel` and nothing else; every cell already carries its own complete address
(`sound` = phase + channel_index + event_index; `sound_container` = index; `sound_def` = the
global bank track index). The choke point has never consulted the nav stack, so co-locating
three tiers costs no dispatch work.

**The page already reads `_nav` as a chain.** `_pair_anchor()` walks the whole stack backwards
looking for the span the drill started from, to anchor the panel's tick-0. Seeding makes that
walk's assumption *true by construction* instead of true by accident of how the author
arrived.

### Rejected

- **A new composite `sound_chain` target kind** whose projector delegates to the three
  existing ones — rejected: it needs a new ref shape and label, and forces `_update_pair_panel`
  and `_pair_anchor` to unwrap it instead of reading `_nav.back()` / walking the stack. More
  new surface for the same picture.
- **Page-level composition with the stack unchanged** (the page notices the open target belongs
  to a chain and renders its neighbours) — rejected: ambiguous in exactly the direction that
  has fan-out. Open a pair directly and there is no single event above it; picking one is the
  lie ADR-0092 warned about.
- **Render every pair a multi-pair container can emit** (2–3 FEDS sections and 2–3 lane
  panels) — rejected on the vertical budget: `FedsPairLanePanel` is ~2,000 lines of per-pair
  drawing with energy bands at ~350 px each; three would pin the timeline strip at its floor
  and put the whole page in internal scroll.
- **Leave slot 3 empty when ambiguous** — rejected: it re-imposes the click the ask exists to
  remove, on precisely the 15.3% of events whose sound is most interesting.
- **Dimming siblings this cast cannot reach** — rejected: it asserts our runtime's reset
  behaviour is correct, and would be confidently wrong on 40 containers if it is not.

### Out of scope, but found: our runtime may drop real ROM content

Of the 85 multi-pair containers, **40 are referenced by fewer events than they have pairs**
(33 mode 1 `PARITY_A`, 4 mode 4 `TRIPLE_CYCLE`, 2 mode 3, 1 mode 2), and 34 of those 40 are
referenced by exactly one event. Our runtime resets the
per-container counter at every cast (`effect_sound_controller.gd` `start()`, and
`EffectInstance.gd`'s audition path), so a one-event PARITY container fires once at
`count == 0` and always plays `id_a`; `id_b`'s pair is unreachable.

But `research/restore_context/SOUND_SYSTEM_VERIFIED.md` records the ROM counter `0x801B9250`
as touched at exactly two addresses — `lbu` at `0x801a32f4` and `sb` at `0x801a3308`, **both
inside `lookup_sound_effect`**. If that is exhaustive, the ROM never resets it: it is a
free-running global, and a one-event PARITY container alternates **across casts** — cast the
spell twice, hear two different sounds. That would make our reset a fidelity bug affecting 40
containers. *This is quoted from that document's exhaustiveness claim, not re-derived here*,
and it is why decision 3 refuses to state reachability.

### Built (2026-08-21) — and two things the build measured differently

**Status: decisions 1–7 BUILT.** `EffectStudioPage._sections_for_render` composes the
chain, `EffectKeyframeInspector` renders N sections with per-section folds, and
`SoundContainerModel.pair_choices` supplies the fire dropdown. No projector changed. The
guard is `tests/EffectStudioChainInspectionTest.gd` (44 assertions).

**Decision 4 is right; its stated mechanism does not occur.** The decision argued that the
naive build "makes the FEDS view *smaller* than it is today", because the three sections
push past `_editor_band`'s budget "at which point the panel takes its `budget × 0.5` floor
and squeezes the inspector below what the pair section gets on its own". Measured on E026
at real window heights (the band is pure, so this needs no window to reach the size):

| | inspector content | FEDS lane panel at h=1080 | at h=900 |
|---|---|---|---|
| today (1-entry pair) | 362 px | 364 (full want) | 345 (50/50 floor) |
| chain, tiers expanded | 1,195 px | 364 (full want) | 345 (50/50 floor) |
| chain, tiers collapsed (shipped) | 493 px | 364 (full want) | 345 (50/50 floor) |

**The lane panel's height is identical in all three, at every height.** It sits below the
inspector and takes its want-or-floor independently, so the chain never shrinks it. What
actually goes wrong is one layer in: at 1,195 px the *inspector's own* content overflows its
band and the FEDS sections fall into its internal scroll. Looked at headful, the expanded
chain shows the trigger's eight cells and **nothing else** — the Container line, the fire
dropdown and the whole FEDS surface are all below the fold, i.e. the one thing the author
clicked for is the one thing not on screen. So collapse by default, for a different reason
than the one written down: not budget contention with the panel, but the inspector burying
its own deepest tier. The shipped default costs +131 px over today and fits whole at h≥1080.

**"13 events name a container that does not exist" counts end-caps.** The corpus line above
is measured with `i <= max_keyframe`, which includes the TERMINATOR slot; all 13 sit exactly
at `index == max_keyframe`. **No firing event in the corpus names a missing container**, so
decision 7's stated degenerate is not one a click can reach.

The reachable degenerate is the end-cap itself, and it was a live bug predating this build:
**112 end-caps across 52 effects carry padding whose `sound_id` resolves to a live
container**, and `_pair_nav_for_sound_span` never checked the role, so clicking one seeded a
full chain. Rendering that chain puts the terminator's own inert row — "End of track … It is
not a sound" — directly above two sections naming the sound it plays. An end-cap now yields
no chain at all.

**One emergent consequence, deliberately left alone.** Flipping the dropdown to a 2nd-fire
pair makes `_pair_anchor` return `orphan`, because `_span_resolves_to_pair` is first-fire
only — so the panel anchors at frame 0 and says "no firing trigger". That is correct under
decision 3's refusal: anchoring the sibling at the clicked trigger's frame would assert this
cast reaches it, which is exactly the claim the counter question forbids. Do not "fix" it
without settling the ROM counter first.

---

## Amendment (2026-08-21c) — the time lane's note bars stop being one ribbon

Written after the fact: the build (`8e5e9a4ed`) cites "ADR-0085 amendment 2026-08-21c"
in eight places and the amendment was never added here, so every one of those citations
pointed at nothing. The commit message carries the full argument and every corpus
figure; this records the decisions so a reader following a citation lands somewhere.

The complaint: *"there are some cases where the notes are so compressed you can't even
read them. and also you can't see where they start and end."* Four mechanical causes,
all measured against the 401-effect corpus (2,018 tracks, 6,439 authored notes):

1. **`· v96` is dropped.** 6,262 of 6,439 notes (97.3%) carry velocity 96, so printing
   it spent ~5 characters of a bar that is often 40 px wide saying what is almost always
   true. It prints when it is **not** 96 — the informative case (v0, 106 notes, marked
   by nothing else, since the MUTED / FAINT verdicts are instrument-derived and never
   read velocity).
2. **A label never draws wider than its own bar.** The clip was
   `maxf(rect.w - 2.0, 40.0)`, so any bar under 42 px drew its text straight over its
   neighbour. Removing the floor alone would only move the cut inside the bar and still
   cut mid-token — "8 C" reads as the key C, not as a truncation — so the label walks an
   **elision ladder** and drops whole tokens. Pitch goes before the ordinal, because the
   Opcodes lane below numbers this track's events at the same x while the pitch is
   recoverable from nowhere else on the panel.
3. **A hairline per span BOUNDARY, not a border per bar.** Spans tile (CONTEXT.md
   "Span"), so a boundary is one thing two bars share: N spans own N+1 boundaries. Drawn
   as a LINE, because the outline vocabulary is already spoken for (violet = borrowed,
   white = selected) and a third outline would leave those two differing only by hue.
4. **`_sec_x` keeps the fraction of a frame** — the cause no handoff had, and the one the
   other three cannot reach. Rounding both span endpoints to whole effect frames
   collapsed 314 notes (4.9%) to ZERO width, drawn as a 2 px sliver by `maxf(2.0, …)` at
   every zoom, and pinned another 18.5% to one frame — which is 40 px at
   `TimelineAxis.MAX_PPF`, the panel's hard ceiling and the zoom the complaint screenshot
   was already taken at. The `round()` bought a bar's edge landing on its ghost pip's x;
   a pip is frame-quantized by nature and is a read-only coarse tell, while the bar is
   what you click, label and resize, so the bar keeps the truth and the pip keeps the
   frame.

**Decision 5 is not amended by this.** The bars still tell pitch by label at a fixed lane
y; what changed is that the label now fits and the boundaries are visible.

**A note's fill carries its OCTAVE** as a lightness step on the one note hue (a global
ordered ramp; octave 4 is the colour the bar has always had, 24.3% of the corpus). Octave
is ordered data, so it takes a sequential scale rather than ten categorical hues fighting
the blue / amber / grey the lane already speaks, and the label's ink follows the fill's
luminance because near-black was chosen for a single bright blue.

---

## Amendment (2026-08-21d) — the Key roll: an opt-in second reading of the time lane

Path A above made the ribbon legible. It did not make it *sparse*: the reason a dense
track is crowded is that every note in it is drawn on one line, and the only axis
available for spreading them out — zoom — was already at its ceiling when the complaint
was taken. This amendment adds the other axis.

### What decision 5 got right, and what it got wrong

> *"A pitch axis buys nothing at 1–2 notes."*

**Confirmed for the median track, and falsified as "typical."** The median FEDS track
carries **2 notes**, exactly as decision 5 assumed. But **46.0% of the 2,018 tracks carry
more than 2**, and the tail is where the complaint lives: E090 pair 3 track B holds 31
notes across 15 distinct pitches. Decision 5's premise is a statement about the median
that was written as a statement about the corpus.

What decision 5 **rejects** is unchanged and is not being amended: *"overlaying event
types"* and *"drag-to-pitch structural verbs."* The Key roll is designed to satisfy both
rather than to trade against either — see the two decisions below.

### The decision

1. **Opt-in, per pair, defaulting to Lanes.** A `[ Lanes | Roll ]` chip in the pair
   header, a sibling of the unwind-all chip. It resets when the pair changes. A pair still
   *opens* as the lane strip decision 5 specifies; the roll is a second reading you ask
   for, which is what leaves decision 5 in force rather than quietly overwritten.
2. **Only the TIME lane is replaced.** Opcodes / Structure / Flow stay, re-projected onto
   the roll's axis. Two rolls, one per track, stacked.
3. **Y is `relative_key`: 12 fixed rows C..B plus a 13th Rest row.** Accidentals striped
   darker so the rows read as a keyboard. Rows never move and never scroll.
4. **The roll is OCTAVE-AGNOSTIC, and that is the load-bearing decision.** Octave is set
   by the `Octave` / `RaiseOctave` / `LowerOctave` opcodes and read from the Opcodes lane's
   `Oct3` / `Oct5` chips. Putting absolute pitch on Y would encode *an opcode's effect*
   into the note lane's geometry — which is precisely the **"overlaying event types"**
   decision 5 rejects. So the full keyboard is refused here for decision 5's own reason,
   not in spite of it.

   The **measured cost, accepted knowingly:** C is 50.4% of all corpus notes, so
   collapsing the octave decrowds only ~1.5× at the median (the busiest row holds 67% of a
   track's notes, against 38% on a full keyboard) and **25.1% of dense tracks still land on
   one row**. The answers are the bar's octave DIGIT, the octave fill tint and the boundary
   hairlines (all three built by 2026-08-21c above), and the roll's own zoom.
5. **X is the pair's own axis, fitted on open.** Not the shared `TimelineAxis` object the
   editor band uses: "zoom in" was never available there — `MAX_PPF` is 40 px/frame and the
   complaint screenshot was already *at* it. Fit-to-pair takes the median pair's tightest
   note from 40 px to ~108 px, and only the 15.6% of pairs still holding a sub-20 px note
   need to zoom at all. `TimelineAxis` therefore grows a **per-instance zoom band**
   defaulting to the shared constants, so no other consumer's band moves.
6. **A vertical drag rewrites `relative_key`** — one same-size byte patch, through the same
   `note_key` field_ref the inspector's "Note key" dropdown already builds. Because the roll
   is octave-agnostic there is **no octave boundary to cross**, so decision 5's rejection of
   drag-to-pitch *structural* verbs is **satisfied, not amended**: this gesture is a bounded
   parameter edit and cannot restructure the stream.

### The sub-decisions the design never reached, settled at build

* **Bar text.** A wide bar still prints `8 C3`. The ladder then drops velocity, then the
  KEY (the row states it better than ink can), then the ordinal — leaving the **octave
  digit**. That is the inverse of the lanes ladder and for the identical reason: each rung
  drops the token most recoverable elsewhere. The ordinal is recoverable by looking down
  one lane; the octave is only recoverable where an Octave opcode actually fires.
* **Row height: 12 px**, and this is arithmetic rather than taste. The pair band is a
  contended budget (`EffectStudioPage._editor_band`). On a maximised window on a 1440-tall
  display the page body is ~1219 px and the band grants the panel ~654. A two-track roll
  with three opcode rows per track wants **626**. It fits whole, and there is a guard on
  exactly that sum.
* **The energy band, the no-op A/B tell and the joint mix band are LANES-ONLY.** They exist
  to corroborate the opcode-honesty verdicts — "is this opcode really inert" — which is the
  Opcodes lane's question, not the roll's. They also cost 142 px, which is precisely the
  difference between the roll fitting whole and being scrolled inside its own panel. One
  click back to Lanes brings all three back unchanged.
* **The orientation grid becomes a TICK grid.** At round *absolute frames* it exists to
  coincide pixel-for-pixel with the score below; on an axis the roll does not share, it
  would be lines at numbers this view never says.
* **The ruler keeps "tick · seconds."** **Ghost copies** are drawn dim as before and are
  not drag targets (`_authored_bar` already refused them — a ghost is not an address).
  **Borrowed bars** are drawn where the span is HEARD and edited where the bytes LIVE, so a
  key drag on one reads its start key off the OWNER's bar and never off the cursor's row.
  The **fermata amber** still butts against the note's own blue on the same row: the ticks
  are one note's, and a sounding extension does not change the key it sounds at. **Zoom** is
  cursor-anchored over `[MIN_PPF, 4000]`.

### Pitch ascends upward

Row index is **11 − `relative_key`**, not `relative_key`. The handoff phrased the guard the
other way round, but the accidental striping only reads as a keyboard with the high notes at
the top, and the Rest row wants to sit *below* the lowest pitch rather than between two of
them.

### Why the build was cheap, and where it was not

`hit_in` hit-tests span bars **by rect, generically**, so moving a bar's `y` handed the roll
selection routing (the borrowed-bar → owner rule included), tooltips, `context_at` /
`resolve_context`, the boundary grips and `drag_target` with no parallel hit-test written.
The core edit really is one `bar_y`. Three places that had pinned `NOTE_BAR_H` now read the
bar's own height instead — the boundary hairline, the grip band and the label baseline; a
16 px stroke on a 10 px bar would be the lane rule the hairline replaced.

The genuinely new plumbing is the vertical drag, and it needed one thing the design did not
name: a note bar in roll mode hosts **two** verbs — a MOVE in time (a structural byte splice)
and a KEY (a bounded parameter patch) — and running both from one gesture would put two
different kinds of edit inside one undo bracket. The axis is therefore **locked once**, at the
threshold crossing, by whichever way the cursor actually went. A rest refuses (its gesture is
the paint), a grip stays horizontal (a boundary has no key), and a press with no legal axis
disarms rather than becoming a dead drag. The key motion reports an **absolute** key, so
motions never compound and a drag away and back restores the original while the button is
still down.

### Built (2026-08-21d)

`617b61104`. `FedsPairEditorTest` 1398 → 1648 / 0: the row law (`row == 11 − relative_key`,
round-tripping, and the rest row refusing to be a key), exactly 13 tiled rows with five
striped accidentals, Δrows → Δkey clamped at both ends and writing nothing that moves the
clock, the drag's address being *identical* to the dropdown's `field_ref`, the roll ladder,
N+1 hairlines per **row** at the roll bar's height, the band arithmetic above, and the toggle
routing without colliding with the unwind-all chip. Acceptance 53 + the known ghost-copy
failure; ChainInspection 44; SoundDefEdit 43; PrunePersistence 5; TimelineAxis 11;
LoopRegionView 11.

Verified with pixels as well as assertions — E011 p0 (the complaint pair), E090 p3 (the
corpus's densest) and E092 p2 (few pitches, wide leaps: the case the octave-agnostic roll is
weakest on), all shot through a fixed-size `SubViewport` so the tiling WM never gets a vote
(`tools/probe_roll_shot.gd`). A scripted press → motion → release on E011 p0
(`tools/probe_roll_keydrag.gd`) moved note 21 up three rows: data byte 0 → 57, key C → D#,
duration index preserved, label re-read `21 D#5`, nothing else in the pair touched.
