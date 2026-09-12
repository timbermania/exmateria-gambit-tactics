# The sequence thumbnail is the real render, minus world position and camera

## Status

accepted

## Context

The film strip (#247) and the sequence player draw every frame through one shared
painter, `SequenceSpritePainter.paint`, whose vertex colour is the literal constant
`Color(1, 1, 1, alpha)` and whose draw is flat-opaque over a dark grey cell. The
sprite's UV, its quad vertices and its animation offset are all honoured; nothing
else the renderer does is.

The question that opened this — *"in the emitters there are effects which are curves
based on particle age. Do you think we can/should fit these in this same panel? This
way we could see how a particle REALLY renders from start to finish"* — was first read
as a request for a new age-axis surface in the focus panel, competing for the ~268px
inspector row that ADR-0102 already fought over twice. It is not. The author's own
framing settled it: **"It's literally like the real particle in the real effect — just
in place over a backdrop."** The strip does not need a new axis. It needs to stop
drawing a lie on the axis it already has.

Everything below was measured against the extracted corpus (401-402 effects under
`assets/effects/`), not reasoned about.

### The age axis is already the strip's own axis

`ParticleAnimator.bake` expands each FRAME opcode into `maxi(1, duration >> 1)`
per-game-frame entries; `tick` sets `anim_frame = anim_time`, `anim_time` starts at 0
on spawn and increments by exactly 1 per physics step. **There is no loop phase to
fix and no lifetime to assume**: age indexes the baked array directly. Lifetime
decides only where the strip *ends*, and it alone is variable (an `_interpolate_range`
read at spawn, `ActiveEmitter.gd:148`).

So the author's construction — take the resolved colour over the whole life, cut it at
opcode boundaries, give each cell its piece — is exact. The corpus then decides what
the pieces look like:

| piece length | cells | share | median intra-piece colour travel | ≥8/255 |
|---|---|---|---|---|
| **1 game frame** | 25,862 | **83.6%** | 0.0/255 | 0.0% |
| 2-3 | 4,667 | 15.1% | 6.0 | 42.7% |
| 4-7 | 213 | 0.7% | 30.0 | 77.0% |
| 8-15 | 88 | 0.3% | 76.0 | 92.0% |
| 16+ | 98 | 0.3% | 150.0 | 92.9% |

(30,928 FRAME opcodes across 2,616 colour-enabled emitters. `duration=2 → 1 frame` is
75.5% of all opcodes by itself; terminal `duration=0` is another 8.1%.)

**Five cells in six are a single curve sample**, because `duration=2` dominates the
corpus — the strip's row resolution already *equals* the age axis's resolution. The
ramp therefore lives between cells, not inside them:

```
intra-piece movement:  median  0.0/255   p90   4.0    ≥8/255 in  7.5% of cells
inter-piece movement:  median  9.0/255   p90  37.0    ≥8/255 in 57.6% of steps
```

### The colour belongs to an emitter; the strip is of a sequence

A strip target is `animation(index, group)`, where `group` is the frameset-group lens
(an emitter's `anim_param`) and **not** an emitter index — deliberately, per ADR-0073
decs. 1 and 8 (a `ref` is a self-contained address). Several emitters can play one sequence at one group.
Drilled from an emitter, the ancestor is on `_nav`; browsed, `_set_root` clears the
trail. Over 2,191 distinct browsable targets:

| | count | share |
|---|---|---|
| no colour-enabled emitter at all | 329 | 15.0% |
| exactly ONE applicable emitter | 1,348 | **61.5%** |
| two or more applicable | 514 | 23.5% |
| …whose curves genuinely **disagree** | 348 | **15.9%** |

When they disagree they disagree hard: worst per-age channel delta **median 144/255**,
p90 255, and 60% of disagreeing cohorts exceed 128/255. An unlabelled "first
applicable" would show a confidently wrong colour on one browsed target in six.

### Colour cannot ship without blend

Across 23,027 corpus frames:

```
ADD       18,930   82.2%          SUB          689   3.0%
ADD_25     2,594   11.3%          BLEND_50     408   1.8%
                                  (opaque)     406   1.8%
```

**93.5% of frames are additive.** And the colour curves are how these effects fade
out — of 2,616 colour-enabled emitters, **35.9% drive their resolved colour to ≤8/255**
somewhere in the life (48.6% reach ≤32/255; median darkest point 36/255). Additive at
`src → 0` is the particle *vanishing*. Drawn flat-opaque, the same moment is a **black
silhouette on grey** — a clearly visible shape at the instant the real particle is gone.

Tinting without blending would therefore make the strip **less** truthful for more than
a third of colour-enabled emitters than the untinted white it draws today. The two are
one feature.

## Decision

**1. The thumbnail is the real render, minus world position and camera.** The
invariant, in the author's words. Blend mode, colour modulate, animation offset, UV
and quad are the actual thing; only placement in the world and the camera looking at
it are dropped. Anything the renderer does that the painter cannot reproduce is a
defect against this decision, not a feature request. `SequenceSpritePainter` is shared,
so the film strip and the viewport player satisfy it together or not at all.

**2. The over-life ribbon is cut at opcode boundaries and each cell owns its piece.**
Cell *k* covers ages `[a_k, a_k + n_k)` with `n_k = maxi(1, duration >> 1)`, and draws
`colour(a_k + (t mod n_k))`. **No static-versus-animated branch**: `n_k == 1` (83.6% of
cells) makes the loop a still by arithmetic, and `n_k == 16` gives the ramp. One
expression covers both. `SET_OFFSET` / `ADD_OFFSET` / `LOOP` append nothing to the
baked array (`ParticleAnimator.gd:40-73`), own zero ages, and get no piece — consistent
with ADR-0102 dec. 4 already drawing them as title-only.

> **Amended 2026-08-20 — EVERY ROW OWNS A PIECE NOW** (ADR-0102 dec. 9, the fencepost
> amendment). "Own zero ages and get no piece" was true of the model this ADR was written
> against, where a cell was one opcode's state. It is false of the model that replaced it,
> where a cell is a POSITION on the animation's clock: every position has a colour.
>
> This paragraph was also the standing description of a HOLE, and said so two paragraphs
> above in different words — the strip having "MORE ROWS THAN AGES" meant the first and
> last thumbnail of every corpus strip were untinted BY CONSTRUCTION, because `SET_OFFSET`
> and `LOOP` both carry `ticks == 0`. It was supporting evidence for the amendment rather
> than an objection to it, and it is now closed: **4,805 spare end cells across the corpus
> gained a real age and a real colour.**
>
> **The cut itself is unchanged.** A cell's piece is now read from `cut_start`/`cut_ticks`,
> which the trace hands over directly, and for a `FRAME` those are still `tick_start` and
> its baked dwell — so a long hold ramps through exactly the ages it did before, and dec. 3
> still governs when. A row owning no dwell gets `cut_ticks == 1`, so it arrives here as a
> STILL rather than as a case: dec. 2's "one expression and no branch" survives the
> amendment, which is most of why it was written that way. The new invariant that pins the
> two together is `cut_start + cut_ticks - 1 == pos_tick` — a cell's position is the last
> tick of its window.

A **uniform** loop was the first proposal and was rejected on the table above: it would
freeze 83.6% of the strip, flicker 15.1% between two or three indistinguishable values,
and genuinely animate 399 cells out of 30,928. A **static-only** tint was also rejected,
but only because dec. 2 makes the loop free — the 1.3% of cells with 4+ frame holds are
precisely the ones a single swatch cannot describe, and there they carry a median of
30-150/255 of travel.

**3. `t` advances only while the sequence player is stopped.** The strip already
carries a sweeping white playhead mark plus a yellow parked mark. Thirty-six cells on
private, unsynchronised phases would compete with the one motion the author is actually
tracking, and while the player runs the playhead is showing the real thing anyway.

**4. Colour provenance is a ladder that always names the rung it fired on** — the
`_pair_anchor` pattern (`EffectStudioPage.gd:2936`), which walks `_nav` backwards for
an ancestor and states its `source` when it falls through:

| rung | condition | strip shows |
|---|---|---|
| `origin` | an emitter is on `_nav` | that emitter's curves, named |
| `only` | browsed, exactly one applicable emitter | its curves, named |
| `first` | browsed, several applicable | the first, named, **plus the count of others** |
| `none` | no colour-enabled emitter | no tint — white, exactly as today |

"First applicable" is right, and it is only honest **labelled**: 15.9% of browsed
targets are genuinely ambiguous with a median disagreement of 144/255. Silently
picking was rejected; so was refusing to tint on ambiguity, which would blank the
feature on 23.5% of targets to protect against a case the label already handles.

**5. The rung is stated in the focus block's existing TITLE, not in a row.** Three
surfaces share a ~268px inspector row and every UX complaint of the preceding session
was that constraint surfacing somewhere new (ADR-0102 dec. 2, twice amended). A title
suffix costs 0px. There is **no off switch** and no emitter picker: 61.5% of targets
are unambiguous, so a picker earns a row only on the remainder, and that is a question
for after real use.

**5-CORRECTED (2026-08-20): the colour rung rides the header's TOOLTIP, not the title.**
Decision 5 put it on the title with the argument that *"a title suffix costs 0px in the
~268px inspector row three surfaces already share — which is the whole reason the rung is
not a row."* **That argument was about HEIGHT, and the cost was WIDTH.** A section header is
a `Button`, so its text sets its minimum width, which propagates through the inspector's
declared content width to the whole right column and squeezes the value tables sharing the
row. Measured on E019 at a 2272px body: `"▾  Frameset 5 — shown by opcode 6 · colour from
emitter 2 (drilled from)"` bids **565px** where `"▾  Frameset 5"` bids **109px** — the
suffix alone was asking for 456px of a 675px inspector, 84% of the row, for one line of
prose. Reported by the author as *"this text is breaking tables and is annoying please
remove it."* The rung is unchanged and still not a row; it is one hover away instead of
zero, and the colour column's slot tooltip already states it in full. Guarded in
`EffectStudioUnifiedAnimationTest` — a title carrying "opcode" or "colour from", or running
past 16 characters, now fails.

**6. The tint samples `colour(a_k + 1)` — the render's pairing, not the ribbon's.**
Traced end to end: spawn leaves `age = 0, anim_time = 0`; spawn requests are processed
at `ParticleSubsystem.gd:189` and `_physics_step()` at `:199`, so the step increments
age to 1 *before* `tick` reads `frames[0]`. **The renderer pairs baked frame *k* with
colour sample *k+1*.** `ColourRibbon.frame_colors` samples at `f` with no offset, so the
shipping ribbon is already one sample off from the render — `sample_rgb`'s docstring
promises the preview "can never drift from the render path", which is true of the
function and false of the index handed to it. The invariant is guarded at the wrong
level.

Matching the ribbon instead was rejected: this feature exists to show what the game
shows, so agreeing with the studio and disagreeing with the game fails it on its own
terms. Correcting the ribbon to match was **filed, not done** — it silently shifts a
surface already in daily use on the strength of one trace, and `_physics_step`'s
docstring cites this ordering as "PSX-accurate order from `update_all_particles`", so
the ROM should be read before anything moves. The two surfaces will visibly disagree by
one cell until then. That disagreement is the point: it is the reminder.

**6-CORRECTED (2026-08-20): the ROM pairs frame k with sample k. The RIBBON was right;
the +1 is gone.** Decision 6 filed its correction against the ribbon *pending a read of the
ROM it claimed to mirror*, on the strength of one Godot trace and `_physics_step`'s docstring
citing "PSX-accurate order from `update_all_particles`". The read was done, and it says the
opposite — at the instruction level, in the very function that docstring names:

| address | instruction | what it settles |
|---|---|---|
| `0x801A2FE0` | `jalr v0` → `update_particle_render_state` | the particle is DRAWN here |
| `0x801A301C` | `lhu v0,0x50(s0)` / `addiu v0,v0,0x1` / `sh v0,0x50(s0)` | …and the colour phase is incremented AFTER, not before |
| `0x801A3020` | `ori v1,zero,0xa0` → `sh zero,0x50(s0)` | the phase wraps at **160**, the curve's own sample count |
| `0x801A5F90` | `sll v0,v1,2; addu v0,v0,v1; sll v0,v0,5` = `idx * 0xa0` | `0x50` IS the colour sample index (`curve*160 + base + phase`) |
| `0x801A5EA4` | gated on `*(u16)(p+0x4e) & 0x40` | …and that gate is `color_curve_enable` itself — `emitter_flags_lo` bit 6 |
| spawn loop | `*(u16)(particle + 0x50) = 0` per allocation | so the phase starts at 0, and the first drawn frame is sample **0** |

**A particle draws its first baked frame with colour sample 0.** The PSX pairs frame *k*
with sample *k*, no offset — which is exactly what `ColourRibbon.frame_colors` was already
doing. `sample_rgb`'s docstring promising the preview "can never drift from the render path"
was true of the function AND of the index the ribbon handed it; dec. 6 read the drift and
blamed the wrong end.

The `+1` is removed from `SequenceCellColour.cell_color`. The thumbnail and the ribbon agree
now, and both agree with the ROM. **This also closes something dec. 6 could not see: under
the `+1`, the trailing `LOOP` row sampled `total` — one tick PAST the end of the animation's
own clock.** The spare end slot the fencepost amendment had just given a real age was
reaching off the end of it, and only a curve long enough to have a value there hid it.

**What dec. 6 got right, and what it cost.** The Godot trace was accurate: spawn requests
are processed before `_physics_step`, so `p.age` is 1 when `frames[0]` is drawn, and
`EffectParticleRenderer._compute_color_modulate` samples that age. **That is the drift, and
it is still there** — the live Godot player remains one sample ahead of both studio surfaces.
Correcting it is a spawn-vs-step ordering change in shared runtime code with gameplay-visible
output, which is a different piece of work from this one and is filed, not done. Dec. 6's
instinct to file rather than shift a surface in daily use was right; only its direction was
wrong, and what made the direction wrong was reasoning from a docstring's claim of
PSX-accuracy instead of from the PSX.

**7. Blend is real `CanvasItemMaterial` blending, with quads grouped by mode.** A
cell's quads are partitioned by blend mode and each group drawn into its own layer.
**95.3% of cells need exactly one layer** — of 17,530 corpus framesets only 827 (4.72%)
mix modes at all, and every common mix is a pair (`ADD`+`ADD_25` 364, `ADD`+`BLEND_50`
322, `ADD`+`SUB` 95). Godot's blend mode is per-CanvasItem, not per-draw-call, and this
is what makes that affordable.

An earlier proposal exploited `dst + src` with `dst = 0` being the identity — draw
opaquely on a **black** cell background and additive comes out exact, for one changed
constant. It was rejected on the author's challenge: it only fakes the additive family.
`SUB` (`dst − src`) over black is nothing, so 689 frames would become invisible, and
under real blending the fade-to-nothing property holds over *any* backdrop, so black
bought nothing it needed.

**8. The cell backdrop is an ADR-0068 tunable, defaulting to today's dark grey.** No
single backdrop serves both families — black gives `ADD` its true colour unclipped and
makes `SUB` invisible; mid-grey reveals `SUB` and clips bright `ADD` toward white. The
backdrop is a *viewing condition*, not a property of the data, exactly as an image
editor's alpha backdrop is. A **static-var home** on `SequenceThumbnail` (the production
owner) fed by `Tune.bind`, with the debug panel as a pure view (ADR-0068 R1–R8),
costs the inspector row **zero pixels**, and the default keeps the strip looking as it
does today.

## Consequences

- **The viewport player is tinted and blended by the same change, for free.** The
  shared painter is what makes dec. 1 enforceable, and it means the player inherits
  dec. 4's provenance question with dec. 4's answer.
- **The strip's look changes for effects that fade out.** Cells at the dark end of a
  curve go from a black sprite silhouette to nothing at all. That is the correction,
  not a regression — but it means an author editing UVs on a faded frame may need
  dec. 8's tunable to see what they are dragging.
- ~~**The ribbon and the strip will disagree by one cell** until dec. 6's filed work
  lands.~~ **Closed 2026-08-20 by dec. 6-CORRECTED** — the ROM says the ribbon was right, so
  the strip moved to meet it rather than the other way round. The two studio surfaces agree.
  What remains open is the Godot RUNTIME's own one-sample lead, which is a spawn-vs-step
  ordering change in shared code and is filed separately.
- **`SUB` frames (3.0%) are only as visible as the backdrop allows.** On the default
  dark grey they have ~41/255 of headroom, which is faint. The frame's own `Blend mode`
  row (`FramesetProjector.gd:141`) remains the authority.
- **The assertable red for provenance needs no scene.** Open a sequence by BROWSING and
  assert no tint (or the `first`/`only` rung named); open the same sequence by DRILLING
  from an emitter span and assert the `origin` rung names that emitter. The ladder is a
  pure function of `_nav` plus the effect data.
- **Rejected, and worth not re-proposing: a new age-axis strip in the focus panel.**
  It was the opening recommendation. `CONTEXT.md`'s *Curve clock domain* already records
  that particle-age is intrinsically per-particle, so a per-life strip is an honest but
  *different* artifact from the playhead view the panel gives — and the measurements
  above show the film strip already **is** the per-age axis at 1:1 for 83.6% of cells.
  A fourth surface in a 268px row would have bought a second copy of an axis that was
  already there.
