# Effect Studio (authoring tool)

The in-game **development** tool for viewing, scrubbing, and (eventually)
authoring an [effect cast](15-effect-orchestration.md). It is **not** a debug panel
— it is a full-width **page** in the F3 dashboard's separate OS window
([ADR-0035](../adr/0035-debug-ui-is-a-separate-os-window.md)) with its own
control suite, because it is a workspace you *work in*, not an observability
readout you glance at. Sharing that window is a hosting choice
([ADR-0069](../adr/0069-effect-studio-is-a-standalone-development-window-not-a-debug-panel.md)
dec. 4), not a reclassification: the tool is development, not debugging. This
cluster names the tool's parts so they don't collide with the runtime
[effect-orchestration](15-effect-orchestration.md) vocabulary (which owns
"effect timeline", "subsystem", "phase block", "channel", "keyframe").

**Effect Studio**:
The tool surface itself (`EffectStudioPage`). Owns effect selection, the
[transport](16-effect-studio-authoring-tool.md), the [score](16-effect-studio-authoring-tool.md), and the
[keyframe inspector](16-effect-studio-authoring-tool.md). It is a **page in the F3
dashboard window**, built and injected by the effect scene that hosts it
(`EffectViewerScene._setup_studio_page()` → `DebugOverlay.set_studio_page()`), and
it reaches that host only through `studio_*` verbs. The boot target you enter is
therefore the effect scene, `res://assets/scenes/EffectViewer.tscn`, which raises
its own tool surface — not a tool scene that raises a stage. It **drives**, but
does not contain, the 3D preview:
the effect renders in the primary window's stage, and the Studio sends
transport/seek commands to the one live `EffectInstance` there (the audio-editor
split — timeline here, output there). Selecting an effect loads a
**parked document**: the score is drawn and a preview instance is spawned
parked at frame 0, playing nothing until the user plays or scrubs. The score
**persists** whenever an effect is selected — it is not born on Play and killed
on Stop (the defect that motivated the tool). Supersedes the old
`EffectViewer` bottom strip + the `EffectViewerPanel` F3 debug panel, which it
absorbs.
_Avoid_: calling it a "debug panel" — it is a development page and not a masonry
panel, however much window it shares with them; embedding its own 3D
`SubViewport` — the preview is
the primary window's stage, driven remotely; conflating **Effect Studio** (the
tool) with **effect timeline** (the runtime orchestrator it visualizes).

**Score**:
The Studio's central view — the laid-out visual of an effect cast's authored
schedule. It is a **pure projection** of parsed `effect_data` (keyframes), not
of a running sim, so it exists without playback (`EffectScoreModel` builds it;
the model is the testable core, the view is thin glue — the
`TuneDashboardModel`/`TuneDashboardPanel` split). One shared horizontal **frame
axis** (absolute effect frames, `0…max`) carries a single [playhead](16-effect-studio-authoring-tool.md);
lanes are grouped into vertical **phase sections** (PHASE 1 / FOR-EACH /
PHASE 2) because the phases sit at different frame offsets on that one axis
(phase-2 overlapping for-each is shown as overlapping X-bands). A top **ruler**
labels each phase's span in plain words — there are **no** `p1▸fe`/`fe▸p2`
boundary-arrow markers (they were redundant with the phase regions themselves).
_Avoid_: "track" for a score row — that word is retired
([effect orchestration](15-effect-orchestration.md)); the runtime word for the data
is [channel](15-effect-orchestration.md), and the score row that visualizes it is a
**lane**; per-phase local axes — the score has one absolute axis and one
playhead, matching the single runtime clock.

**Script pattern** (Studio mode + swap, [ADR-0094](../adr/0094-effect-script-pattern-swap-is-a-structure-preserving-variable-length-section-rewrite.md)):
The authoring surface for an effect's [script pattern](15-effect-orchestration.md) —
`3-phase` or `1-phase` — shown as a **mode** on the Effect ⚙
([effect settings](16-effect-studio-authoring-tool.md)) surface and, for recognized effects,
**swappable**. A swap is **structure-preserving**: it keeps the effect's real
script **prologue** verbatim (the texture page carried in `set_texture_page`
flags, plus every `load_callback` registration) and regenerates only the
control-flow body — adding/removing the `clear_timeline_a` marker and the
for-each child. It is offered **only** when the script exactly matches a
canonical template *and* the file is DATA-format (the round-trip is then
provably lossless and reversible); Custom, CODE-format, and non-canonical
scripts show the mode **read-only**. The swap rewrites **only** the script
section — phase-1/phase-2 [timeline](15-effect-orchestration.md) data is left
**dormant** (kept in the file, no longer ticked), so the score hides those
phase sections while `1-phase` and restores them on swap-back.
_Avoid_: calling it a "template stamp" — the reference Lua editor stamps a
fixed template and thereby zeroes the texture page and drops callbacks; ours
preserves them (a **structure-preserving swap**, not a stamp); saying a swap
"deletes" phase-1/phase-2 data — it is **dormant**, not deleted; treating the
swap as a fixed-size byte patch like the other [effect settings](16-effect-studio-authoring-tool.md)
tenants — it **resizes** the script section and shifts every downstream section
(ADR-0094).

**Prologue** (effect script):
The leading run of an effect [script](15-effect-orchestration.md) that carries its
**per-effect** payload rather than control flow: `set_texture_page` (the
texture page is packed in its flags byte, never zero), then **0–4**
`load_callback` instructions, then a `clear_timeline_a` marker on `1-phase`
scripts only, then `init_physics_params`. A [script-pattern](16-effect-studio-authoring-tool.md)
swap preserves the prologue verbatim; everything after it is the **canonical
body**, a per-pattern fixed opcode shape whose only per-effect variation is the
branch offsets (which shift with callback count).
_Avoid_: assuming the prologue is fixed-shape across patterns — `1-phase` has
`clear_timeline_a`, `3-phase` does not; treating `load_callback` count as
constant (0–4, per effect).

**Lane** (effect-studio):
One horizontal row of the [score](16-effect-studio-authoring-tool.md) — the visual of a single
[channel](15-effect-orchestration.md) within one [phase block](15-effect-orchestration.md).
Each lane carries [lane events](16-effect-studio-authoring-tool.md) of one archetype: particle lanes
carry [spans](16-effect-studio-authoring-tool.md), screen/palette/camera lanes carry
[tweens](16-effect-studio-authoring-tool.md) (drawn in their tint), sound lanes carry
[triggers](16-effect-studio-authoring-tool.md). Full-word gutter labels (e.g. "Channel 0", "Screen",
"Map tint", "Caster", "Target"), not the retired 2-char `p1`/`fe`/`scr`
abbreviations.
_Avoid_: "track"; treating a lane's vertical position as a Z-order key (channel
index is a lane identifier, not a sort key — [channel](15-effect-orchestration.md)).

**Lane event**:
The general term for one authored entry on a [lane](16-effect-studio-authoring-tool.md) — a thing
that happens at a position on the timeline. Three archetypes, distinguished by
*what happens* (not merely *when*): a **span**, a **tween**, or a **trigger**
(below). A lane is a time-ordered sequence of lane events. On disk they are all
called "keyframes", but that word implies interpolation between two independent
anchor points, which FFT does **not** do — prefer **lane event**.
_Avoid_: "keyframe" as the umbrella (misleading — see Tween); "span" as the
umbrella (span is one archetype, not the genus).

**Span** (lane event):
The **particle** archetype: a window during which an
[emitter](15-effect-orchestration.md) runs (spawns), from this keyframe's time to the
next keyframe's time. Its duration is **implicit** — the gap to the next
keyframe. An emitter of id 0 is a **null span** (a real gap: nothing spawns).
The emitter it names is a shared, reusable configuration — one emitter fills
many spans across channels and phases.
_Avoid_: using "span" for color or sound entries (they are tweens/triggers);
treating the span as owning the emitter's parameters (it only *references* an
[emitter](15-effect-orchestration.md)). A span is also called an **emitter event**
when the emphasis is on *when* it fires (see Emitter-event editing).

**Emitter-event editing** (particle-timeline verbs, [ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md) particle_timeline amendment):
Editing *when* an emitter runs and *which* emitter a [span](16-effect-studio-authoring-tool.md)
fires — as opposed to the emitter's [parameters](16-effect-studio-authoring-tool.md). The author
manipulates **spans**; every verb lowers to a keyframe op on the channel's
fixed **25-slot** table. Storage is a [boundary](16-effect-studio-authoring-tool.md): each span's
edges are stored `time`s (cumulative-absolute within the phase), and one edge
is shared by two windows. The governing law: **an edit only ever consumes or
creates [null-span](16-effect-studio-authoring-tool.md) (gap) space — it never changes another
*drawn* span's extent.** Gaps are the currency; drawn bursts are walls.
- **Resize** — drag a span's right edge. **Grow** consumes the adjacent gap and
  stops at a drawn wall (to grow past flush, insert a null span first);
  **shrink** always works and auto-opens a null span in the vacated space, so
  the neighbour is never disturbed. A gap consumed to zero width is reclaimed.
- **Move** — slide a whole span through the gaps around it; both edges shift by
  the same delta, walls on both sides, no drawn span disturbed.
- **Add / Split / Delete** — **Add** inserts a span (**born disabled** — a real
  null span you then enable and aim), landing in **[gap](16-effect-studio-authoring-tool.md) (empty)
  space**: it is reached by right-clicking an empty stretch of a particle lane
  ("Add span here") and opens a new dimmed span from the cursor to the next wall.
  Right-clicking a **drawn burst** instead offers **Split span here** — honestly
  named, because it cuts the burst at the cursor (the one verb that *does* change
  a drawn span's extent, kept for the "insert a null span to grow past a flush
  wall" workflow) — plus **Delete** (the next span closes up over it, so
  downstream stays pinned and the slot is reclaimed). A full channel refuses Add.
  (Add and Split lower to the *same* keyframe `insert_event`, born-disabled at
  the cursor; only the entry point + label differ — a gap-click can't perturb a
  drawn burst because a gap *is* the covering window it splits.)
- **Enabled / Emitter** — a span's **Enabled** checkbox mutes it to a null span
  while a session sidecar remembers the emitter, so a disabled span stays drawn
  **dimmed and selectable**; the **Emitter** picker retargets which emitter
  fires (editable even while disabled). Unlike the [screen/palette Disabled](16-effect-studio-authoring-tool.md)
  state, this **cannot persist**: the ROM's `emitter_id` conflates value and
  enable (`0` = off, `N` = fire emitter `N−1`) with no spare bit, so a
  saved-disabled span reloads as an ordinary gap.
- The first span's start is the **phase origin** (`kf[0]`), pinned at 0 and
  never editable.
_Avoid_: an edit that silently grows or shrinks a *drawn* neighbour (only gaps
flex); a bare "Add" that lands on a drawn burst (it silently cut the burst — that
gesture is now the honestly-named **Split**, offered only on the burst's own menu);
a gap right-click that shows nothing (empty particle-lane space must offer "Add
span here" — a plain [seek](16-effect-studio-authoring-tool.md) hit swallowing it is the bug this
fixes); promising a persistent "disabled-but-remembers-emitter" state (it is
session-only by ROM constraint); treating the origin as movable; addressing a
span by a coalescing "ordinal" (particle channels are flat and 1:1 with
storage — a raw keyframe index is the stable address, unlike [camera](16-effect-studio-authoring-tool.md)).

**Emitter parameters** (shared emitter contents, [ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)):
The fields of one [emitter](15-effect-orchestration.md) — what its particles look
like and how they move. Authored **at the reference**: the span inspector's
emitter sections (and the emitter browser — the same inspection target) edit
the shared object in place under a shared-ness cue ("Emitter N — shared, fired
by K events"); there is no separate emitter editor screen, and editing an
emitter changes **every** span that fires it. Most parameters vary along two
axes, made explicit and uniform: **Randomness** — each particle rolls a value
between *min* and *max* when it spawns; **Evolution** — the min–max range
itself slides from its *At start* value to its *At end* value over the
emitter's active window, shaped by that parameter's assigned curve (curve
*assignment* is authored; curve *contents* are shared and edited elsewhere).
Presented as one labeled group per parameter with **At start / At end** rows ×
min/max cells — the editing cells never collapse when min == max (collapsing
hides the randomness axis). Groups render as **collapsible folds** in a single
column: a collapsed group's header carries a read-only start→end summary (which
*may* collapse min == max — the law binds the editing cells) plus a mini
sparkline when a curve is assigned; inert groups (all zero, no curve) dim.
Sparklines are **trimmed to the emitter's used window and normalized** to it
(ADR-0089 curve-UX amendment, reversing the earlier "full 160, tail dimmed"):
they draw only samples `0..N` X-stretched to full width, Y re-fit to that
window — the firing span's own window in the span inspector, the widest firing
in the emitter browser. A wrapping (≥160-frame) or animation-driven (lifetime
−1) window has no defined active length, so it falls back to the **whole curve,
un-normalized, fully bright** — **except** the **over-life** colour + homing
curves, whose lifetime−1 window resolves to the emitter's **animation baked
display length** (`EffectData.get_animation_display_length` — one anim per
emitter; `Σ maxi(1, duration>>1)`, the actual Life=-1 particle lifespan,
mirroring [ParticleAnimator](16-effect-studio-authoring-tool.md) baking), since those curves clock by
particle age and the particle lives exactly as long as its animation plays.
Display names are semantic ("Gravity scale", not `weight`;
the ADR-0089 table is the naming source of truth); the raw RE name + byte
offset live in the tooltip; values author in human units (tiles / degrees /
frames / × multipliers) only where the runtime conversion is proven, else they
stay honest raw ints.
_Avoid_: a modal/separate emitter editor (edits happen where the fields are
shown); four flat number cells for a min/max × start/end quad (the two axes
are the presentation); renaming a field without keeping its raw name reachable
in the tooltip; speculative unit conversions; treating callback params as
inert (they feed the effect's native callback — editable raw, honestly
labeled).

**Directional field** vs **Extent field** (authoring chirality):
Splits the pos-scale emitter fields by whether their **Y sign is visible on
screen**. A **directional field** — Position start/end, Target-offset start/end,
Acceleration, Drag — names a place or a force, so `+Y` vs `−Y` is up vs down: its
authoring cell reads **game-up** (`−raw/28` tiles, committing `raw = −typed·28`),
showing the exact Godot value the sim caches (author-sees == author-uses). An
**extent field** — Spread — is a **symmetric scatter magnitude** (`_apply_spread`
samples `randf(−s, s)`; `_rotate_y` never touches Y), so its Y sign is **provably
inert**: it stays shown **unflipped**, as a magnitude. This is the chirality
(ADR-0057) half of the [game-unit boundary](24-units-convention-magnitude-vs-chirality.md)
applied at the authoring cell — the units amendment did magnitude only, leaving
the "author dials +Y, particle goes down" contention (ADR-0089 amendment
2026-08-13). Storage stays raw PSX `−Y = up`; only the directional **cell** flips.
_Avoid_: deleting the runtime/parser `−Y` negation to "fix" the backwards feeling
(that conversion is honest and test-locked — the gap is the editor, not the sim);
flipping spread's cell (shows a nonsensical negative extent); treating this as an
ADR-0052 half-rotation bug (effect coords are their own subsystem — see
[Placement](23-spatial-convention-placement-orientation-render.md)).

**Tween** (lane event):
The **screen / palette / camera** archetype: a value glides linearly (start→end)
toward a target over an **explicit** duration (snapping if the duration is 0).
Not a classic keyframe — each tween is self-contained, carrying its *own* start,
end, and duration; there are no two-anchor pairs to interpolate between. A
palette tween whose enable control is off is a genuine **null tween** (a true
hold — nothing happens); a *screen* tween has **no stored enable bit** — its
authoring **Disabled** state is the **identity no-op Blend** (see Blend/Gradient
and the fully-tiled-lane law).
_Avoid_: "ramp"/"fade"/"keyframe"; assuming "disabled = nothing" on the screen
lane; reading the old TINT/FADE ctrl bit as an enable (it is the Kind).

**Blend / Gradient** (screen tween kinds):
The screen tween's enable control selects one of two behaviors — these names
retire the misleading on-disk `TINT`/`FADE` labels:
- **Blend** (was "TINT"): recolors the whole backdrop by pushing it through one
  of 11 color-math **blend modes** with a single shared RGB param; the top→bottom
  gradient shape is preserved (a uniform recolor). The param is a **signed** byte
  applied **doubled** (`start << 1`, ScreenSubsystem.gd:94-99) — a *bidirectional
  additive* delta (positive brightens, negative darkens), so ±128 is not a colour
  chart. It **authors as a WYSIWYG target-colour picker** (`editor:"target_color"`):
  the author picks the colour the backdrop **top** should BECOME at the parked
  frame, and `BlendTargetSolver` back-solves the signed param by brute-forcing all
  256 candidate bytes per channel through the **real** forward blend fold
  (`ScreenSubsystem.fold_top`, the exact path the preview uses — no drift). A target
  the mode/range/clamp can't reach snaps to the **nearest** achievable colour, shown
  in a read-only "actual" swatch beside the picker (the honest feedback; the live
  preview is the other). The on-disk byte stays 0-255 (the solver lowers its chosen
  bytes through the same `EffectEditSession` choke point). The old bipolar
  per-component spinbox editor (`editor:"signed_rgb"`) is retired — an author picks
  the *result*, never ±128.
- **Gradient** (was "FADE"): sets the backdrop's two stops to **explicit,
  independent** top and bottom colors — literally "pick the sky's top and bottom
  color." Unlike Blend these stops are **unsigned absolute sets**, so a Gradient
  editor (deferred) is a real colour picker — the two screen kinds need *different*
  colour editors.
Both glide to their target over the tween's duration; they differ only in how the
*target* is computed — a procedural transform vs an absolute set.
The screen tween's inspector rows are **harmonized with the palette lane** (ADR-0087
amendment): beside the Blend picker sits a signed **Tint Δ** row showing the **stored
byte** (the label tells the engine's ×2 application — *"applied ×2"*), the Blend
**mode is editable** (the same 11 `ColorModeLabels` choices as palette), and an
**Enabled** control exists despite the missing bit: **Disable swaps the keyframe's
bytes to the identity no-op Blend** (mode 0, Δ 0 — the insert-seed convention),
stashing the prior bytes in a session-only authoring sidecar so re-enable restores
them losslessly; disabling a Gradient presents/rewrites as a Blend no-op. "Disabled"
is a **derived** state (identity-no-op bytes, or a stash present) — a cold no-op
after reload has nothing to restore, so enabling it means *author a tint*. The live
bytes always equal what plays and what saves.
_Avoid_: "FADE" (it neither fades nor no-ops — it is the Gradient set) and "TINT"
(Blend is a blend-mode op, not a palette-style tint); a Δ row showing the doubled
value (the row is raw storage truth); a preview-only mute that lets the studio fold
diverge from the saved bytes.

**Palette tint** (palette tween contents, [ADR-0087](../adr/0087-palette-tint-is-a-signed-blend-delta-authored-as-a-result-pick-against-a-reference.md)):
The palette lane's colour value is a **signed Δ through one of the 11 shared
[colour modes](27-color-modes.md)** — the *same family as the screen [Blend](16-effect-studio-authoring-tool.md)*,
NOT an absolute colour. The engine sign-extends each r/g/b byte (`ColorRecipe._sb`) and
*adds* it, per channel, to the colour-so-far or the committed base; real data stores
negatives (`[-31,-31,-31]`). So it **authors as a result-picker against a fixed
mid-grey reference** (reusing the screen `BlendTargetSolver` against the *palette* fold,
`param_max=31`) — the author picks the colour a mid-grey should BECOME, the solver
back-solves the Δ, unreachable → nearest in an "actual" swatch. The 11 modes carry
**human labels shared with screen** (one `ColorModeLabels`): *Add*, *Dim ½ + Add*,
*Desaturate (strong|subtle)*, their idempotent *over base* variants, *Reset to base*
(8), *Reset* (10). The two **restore** modes (8/10) carry **no colour** — the tint cell
is absent for them (a mode-shaped [Variant](16-effect-studio-authoring-tool.md) field set). The `enabled`
control (ctrl bit-7) is a **scalar** in-place toggle producing a [null tween](16-effect-studio-authoring-tool.md)
that HOLDS the prior tint — never a structural add/remove; it is **presented** as an Enabled
(Disabled/Enabled) choice, and a disabled tween still draws on its lane as a **dashed null span**
(fully-tiled) so it stays selectable to re-enable. Beside the result-picker sits a precise
**signed-Δ (R/G/B) row** with a **"No tint"** reset: it shows/types the raw delta as signed
bytes so **Δ = (0, 0, 0)** reads as the unambiguous **no-op** the mid-grey picker can't surface
(a true "no change" only in additive mode 0 — *over base* (4/9), Δ 0 still resets the colour
to base, masking any tint layered below; see [Spacer](16-effect-studio-authoring-tool.md)). Together these give
full byte coverage of
the palette keyframe (time_value via [boundary drag](16-effect-studio-authoring-tool.md) or the typed **Duration**
row — the same edit; rgb via picker + Δ row, ctrl enabled + mode).
_Avoid_: modeling the palette rgb as an unsigned `raw/255` colour (the #266 mislabel and
the "seek-color renders wrong" bug); reusing the screen Gradient's `gradient_color`
absolute picker on the palette lane; calling enable/disable a structural edit.

**Spacer** (lane-event role; ADR-0087 decs. 17-28 for colour,
[ADR-0086](../adr/0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md)'s
`MAP`-delta amendment for camera):
A [lane event](16-effect-studio-authoring-tool.md) on a **fully-tiled** lane that **owns its span
and changes nothing** — so it is the lane's **empty space**: it occupies time
purely to position its neighbours, and it renders as **nothing** — no fill, no
border, no label, no hatch. The *treatment* is one rule; **how a spacer is
DECIDED is per-lane**, because the two lanes fail differently:

- **Colour** (palette + screen) — the **disable-equivalence fold**: the
  channel's *authored* stream with the event vs. without it, timing kept, must
  yield the **same colour transform, for every base colour, at every frame**
  (never "same colour on the currently-previewed map"). Colour ops **compose**,
  so the verdict needs the whole stream — `SpacerVerdicts`, the studio's most
  expensive computation.
- **Camera** (angle / position / zoom sub-channel lanes) — **source `MAP` with
  a zero value**, tested on `zoom.x` alone. `MAP` is `current + keyframe`, so
  zero holds the pose. It is decidable **locally, with no fold**, because
  `CameraSubsystem` only searches for a keyframe on an **idle** channel — a
  camera event can never preempt a running tween, so there is no stream context.
  The verdict is per **span**, not per stored keyframe: a coalesced keyframe
  shares one command word but keeps separate per-sub-channel values, so it can
  be a spacer on one mask bit and a real move on another.

Zero alone is **not** the camera tell — every E317 for-each keyframe stores
`[0,0,0]`, and the `CASTER` pan, `TARGET` framing and `SLOT_COPY` return are all
real moves. The **source mode** does the work; under an absolute mode a stored
zero is the *opposite* of inert (zoom `DIRECT` 0 = zoom **to** zero).

A spacer is **not selectable and not editable** on either lane; the
pre-fifth-amendment "wake it into a real event by clicking it" verb is **gone**.
The only thing you can do in a spacer's region is **right-click → Add** —
exactly how you fill an emitter-lane [gap](16-effect-studio-authoring-tool.md). You never *convert*
a spacer; you *build over* it. On **colour** that Add is "Add event here",
seeding a fresh **1-frame [disabled](16-effect-studio-authoring-tool.md) stub** at the clicked frame
with spacer on either side, which you resize + enable + colour into a live
event; on **camera** it is "Add waypoint here", the same insert a drawn span
offers — see the camera paragraph below for how its seed differs.

Two things a spacer is **not**. (1) A **deliberately-disabled** event (you
cleared its Enable bit) is *not* empty space — it stays drawn (its colour,
dimmed, under a **diagonal hatch** that now means exactly *"you turned this
off"*), keeps its solid-Blend / dashed-Gradient *kind* border, and stays
**selectable** so you can re-enable it: **"muted, not gone,"** mirroring a
disabled [emitter](16-effect-studio-authoring-tool.md). The hatch thus flips meaning — it no longer
marks auto-detected inertness (that's invisible now); it appears **only where a
human chose "off".** (2) The verdict is **live**: an upstream edit can wake a
*contextual* spacer (a Δ-0 over nothing, a restore with nothing to restore, a
Gradient re-setting what an earlier *equal* Gradient set), at which point it
stops being empty space and **reappears** as an ordinary event — the score
recomputes on every colour edit, so empty-vs-drawn is never stale. Still
**not** spacers: the half-dims (modes 1/5 at Δ 0 — `(current|base) >> 1` is a
real darken; an *idempotent repeat* of the already-settled base-source op is
disable-equivalent and does vanish), a Δ-0 fade-out returning from a tint
(same bytes as a lead-in, opposite role), the luma modes at Δ 0, and a
*leading* Gradient (an absolute set differs from a map-dependent passthrough
*as a transform*). The **currently-selected** event always draws, even if its
bytes would otherwise make it a spacer — so a just-added or
just-enabled-not-yet-coloured stub never blinks out mid-edit. Verdicts fold the
authored stream — Solo/Mute is a listening tool and never turns a tween into
empty space.
A **hold run** is what colour spacers usually come in: because the colour verdict
is a **fold over the whole stream** rather than a local byte test, inert events
arrive in **consecutive runs**, not alternating with real ones the way camera's
locally-decidable `MAP`+0 holds do. A run's *interior* boundaries are the
**blind** ones of [Boundary drag](16-effect-studio-authoring-tool.md) — empty space on
both sides. The 1-frame floor bounds a **keyframe**, not a run: a run of `k`
holds may shrink to `k` frames and then **vanish entirely**, letting a span butt
against the previous drawn event and **returning its keyframes to the
[slot budget](16-effect-studio-authoring-tool.md)**.
On **camera** lanes the same treatment lands with three differences. There is
no **Enable** bit and no Solo/Mute, so the "muted, not gone" carve-out has no
camera analogue and the hide predicate is *"spacer unless **explicitly**
disabled"*. The **boundary grip** survives on a hidden span — and lands exactly
on the next drawn event's visible left edge, so resizing a hold reads as
dragging that event's start, which is also who the drag **selects** (the hold
writes the boundary but never speaks for it, and never reveals — see [Boundary
drag](16-effect-studio-authoring-tool.md)); between two holds the boundary is blind and does not
grip at all. And **Add** seeds differently: `insert_event`
deliberately inherits the covering span's command word (a no-op until you drag
the waypoint), so an event added inside a hold **is itself a spacer** — drawn
while selected, gone on deselect unless you give it a real Source or a non-zero
value. The verdict is **live** on camera too: give a hold a real value, or
change its Source away from `MAP`, and it **reappears** as an ordinary event
that same moment. A camera `MAP`+0 is the ROM's **hold primitive**, not an encoding
accident (28.7% of all camera spans), so what a camera lane hides is the shot's
*pacing*; the read-only [Compiled lane](16-effect-studio-authoring-tool.md) hides
nothing and is where those holds stay legible.

_Avoid_: making a spacer selectable or editable *in place* (the "ghosted but
grabbable" model — you now build over it, never convert it); reusing the
**dashed** border as the disabled cue (dashed means Gradient kind); hiding a
**deliberately-disabled** event (you'd strand the knob that re-enables it);
seeding the Add with an *enabled* identity tween (it would instantly re-hide —
the born-disabled stub is what stays visible); preview-relative verdicts
(equality sampled only at the current map's base); calling the mode-5 Δ-0
half-dim a no-op (it is the darkening on real effects); routing camera through
the colour **fold** (it is locally decidable, and a third fold would worsen a
score build already over budget); treating a camera **zero value** as the
predicate without its source mode; a **per-keyframe** camera verdict (it is per
sub-channel span); confusing this with the two unrelated senses of *inert* —
the `(inert)` **value-row suffix** (zoom under `OFFSET`/`CURSOR`, a label the
runtime never applies, #281) and the `Hide inert` **inspector view toggle**
(ADR-0089, over field *relevance* states); hiding a camera span the runtime
skips for being **one frame wide** (that is an authoring accident worth seeing,
not a configured no-op).

**Trigger** (lane event):
The **sound** archetype: fires a one-shot at an instant; the SFX then plays on
its **own clock** (the SPU), not bound by timeline frames. Its duration field
only gates when the *next* trigger fires (often a large "never again" sentinel),
and a sound id of 0 is a **null trigger** (fires nothing). A trigger marks
**playback start, not the audible hit** — the salient moment can land later, per
the sound's internal design (see [Anchor](16-effect-studio-authoring-tool.md)). **Cross-subsystem
alignment happens here**: because one [effect timeline](15-effect-orchestration.md)
pumps every subsystem off a shared playhead, a boom + flash + camera-shake are
"contemporaneous" by sitting at the same frame on the shared ruler — you align at
the trigger, you *design* the sound elsewhere ([FEDS content editor](16-effect-studio-authoring-tool.md)).
**In the studio the instant is the primary object**: you select and drag the
**marker** (overlap resolves by *nearest fire marker* to the click, not first-in-order),
and `duration_frames` surfaces on the marker as the **`gap`** label — the space to the
next event. Position is *derived* from the gap chain, never stored: `fire[N] =
phase_offset + Σ duration_frames[0..N−1]` (skip keyframes consume gap too); dragging a
marker is a **local two-gap trade** (`dur[N−1]+=K, dur[N]−=K`), first trigger pinned.
_Avoid_: drawing a trigger as a duration bar the way spans and tweens are drawn —
it has no meaningful on-timeline length (an optional [ghost bar](16-effect-studio-authoring-tool.md)
may *project* the resolved sound's real length, but read-only); making the ghost bar
the **select target** or the dominant visual (you select the *instant*, not the bar —
letting the ghost's width own the hit-rect is the ADR-0085 drift that swallows a
near neighbour's marker).

**FEDS content editor** (effect-studio):
The surface for authoring **what a sound is** (its notes, instrument, real length,
loops) — TIER-3 [FEDS](14-audio.md), the *same opcode VM as SMD music*. It is an
**inspection-first surface** (a good place to *see* what's happening; authoring is
the F1 inspector's job) that **projects onto the shared effect-frame axis** — the
same `TimelineAxis` the [score](16-effect-studio-authoring-tool.md) and [ghost bar](16-effect-studio-authoring-tool.md) use,
so a sound's events line up with the flash/shake/palette lanes below (2026-08-11
amendment). It draws that alignment as a **per-frame orientation grid** — the same
frames the [score](16-effect-studio-authoring-tool.md) grids, at the same x, so a chip sits over its own
column below (2026-08-12 amendment); the grid, not the tick marks, is the panel's
vertical reference. Its **own tick/tempo clock survives as the ruler's tell** ("tick ·
seconds") and as the **numeric edit unit** — but it no longer places events on a
self-contained tick ruler, because that could not align with the timeline. This is
**projection, not composition**: no edit happens on the axis (every value edit stays
numeric in the F1 inspector), so the "two unsynchronized clocks" hazard the original
own-axis rule guarded against never fires — the panel is a wider, always-visible
member of the [ghost bar](16-effect-studio-authoring-tool.md)/[ghost pips](16-effect-studio-authoring-tool.md) projection
family. It mirrors the music DAW plugin's model at honest scale: a **tall page-level
lane panel** (the `EffectScoreTimeline` idiom — real ruler + label gutter +
collapsible sections), **one note lane per [track](14-audio.md) plus one lane per opcode
*kind* present** in the pair (never two event kinds in one band). Tick→frame is
**tempo-integrated** (`fire + seconds_at(tick) × 30`, the same per-track integrator
the [ghost pips](16-effect-studio-authoring-tool.md) use, so panel and pips cannot disagree); the pair's
tick-0 anchors to a **representative firing trigger** (drilled-from → selected →
first-firing → orphan-at-0-with-a-tell). A **folded loop collapses drawing, not
time** — it still spans its full N-pass frame width (the envelope of its pips), so
alignment is exact folded or unwound; unwinding just fills that span with the
unrolled copies. Coincident opcode chips keep their **true x** and **wrap to rows**
within the kind-lane (never push-right, which would falsify the tick). Notes draw as labeled duration bars (key + velocity as text, not a vertical
pitch axis); opcodes as **typed chips** (short code in-lane, full opcode name on
hover). Loops **fold by default** (`REPEAT 0x98 … CODA 0x99` → bracket + ×N badge)
but each carries a **per-loop wind/unwind toggle** that unrolls it in place, plus
hover-peek — folded is the *default*, never the only view. NOT a piano-roll in the
sense that matters (no overlaying event types, no drag-to-pitch structural verbs);
the panel is the **navigator**, select → edit through the F1 inspector kit. Its
scope is **bounded
parameter editing**: change the events that exist (opcode params, note
velocity/key/duration — durations snap to the delta-time table's storable
values, with the honest tell — and paired on/off toggles), never restructure the
stream (insert/delete/move and loop surgery are the deferred compile path). What
it shows comes from the **runtime decoder** — the same decode the sequencer
plays, so seeing is playing. Reached by *following the reference* from a
[trigger](16-effect-studio-authoring-tool.md) through its [SoundContainer](14-audio.md)
([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)
link model), never nested as a channel-owned subchannel — a FEDS pair is shared,
effect-global, referenced by many triggers, so the editor leads with provenance
("used by container C → N triggers") and badges byte regions shared by
flow-through stub tracks (a tell, not a block). See
[ADR-0085](../adr/0085-effect-sfx-authoring-is-three-projected-surfaces-not-one-flattened-ruler.md).
_Avoid_: *composing* (drag-authoring) FEDS notes on the effect-frame ruler — the
banned thing is placing/editing an event by its frame, where the tempo map lies;
*projecting* the panel onto that ruler (read-only alignment, edits stay numeric in
the F1 inspector) is the 2026-08-11 model, not the hazard; reading "own tick/tempo
axis" as a self-contained placement ruler (it survives as the tell + edit unit, but
placement is the shared frame axis); a linear tick→frame share (disagrees with the
tempo-integrated pips under an inline `TEMPO`); drawing a folded loop compressed so
its chips miss their own unrolled pips (folded reserves full time — see amendment);
treating the FEDS pair as owned by the channel that fired it; treating
`feds.json` as a decode source of truth (it is a human-readable byproduct — the
runtime decode of `feds.bin` is what plays); reading "editor" as structural
editing (that is the deferred compile path, not this surface); reading "folded"
as fold-only (loops carry a reversible per-loop wind/unwind toggle + hover-peek —
the first build's fold-with-no-unroll was rejected); hosting the surface in the
reflowing inspector grid cell (the width-unstable trap the rejected micro-strip
fell into — it is a page-level panel).

**Empirical usage range** (effect-studio):
The **honest substitute for a physical unit** on a FEDS opcode param that has none.
Where a param carries a real unit (ADSR ms, tempo BPM) or a named enum (instrument),
that grounds the number; where it does not — the pitch/portamento family, raw
scalars, un-named selectors — a bare byte answers neither *"what does 2 mean?"* nor
*"is 2 a lot?"*. The range answers the second by **scanning what shipped FFT effects
actually do** with that byte: a generated, drift-guarded `feds_param_stats.json`
gives per `(opcode, param_index)` a **signed-aware min/max/median/mode/n** across
every effect FEDS blob. The [keyframe inspector](16-effect-studio-authoring-tool.md) cell surfaces it as
an inline dim hint ("typical −8…+8 · median 0 · n=47") + a fuller tooltip, plus an
**out-of-corpus tell** (the [quantize](16-effect-studio-authoring-tool.md)-tell pattern) that fires when
the current or typed value falls outside the observed range — *"no shipped effect
uses a value this high."* It does not merely show a spread; it **warns when the
author leaves the envelope of real data**. The one generated table is the **shared
source for stats AND signedness** (the Python producer and the GDScript descriptor
read the same file, so they can't disagree); the hand-authored **signed-param list**
is the generator's single input. A **physical** unit (semitones/cents) ships only if
pinned by static analysis + oracle validation — otherwise the param ships label +
range. See [ADR-0085](../adr/0085-effect-sfx-authoring-is-three-projected-surfaces-not-one-flattened-ruler.md)
(2026-08-12 amendment).
The range is also bucketed by **active instrument** (the last `0xAC` earlier in the
_same_ track — per-`TrackState` runtime state, never crossing the pair's two voices):
the cell shows the global line **and**, when an instrument is active, an
**instrument-conditional** line marked as the sharper answer ("with Timpani (64):
2…40 · median 8 · n=47"). This second line is a **correlation** — *what shipped
effects using that instrument did with the byte* — **not** a claim the instrument
changes the byte's _meaning_ (no such interpretation is RE-validated). The line is
always shown at n≥1 but its wording is **n-adaptive** (n=1 → "seen once at 8", so a
single sample is never dressed as a range); when the instrument is active but the
corpus has _zero_ samples for it, an explicit "none with Timpani (64)" line marks
the unprecedented-for-this-instrument case. The out-of-corpus tell distinguishes the
two envelopes: leaving _global_ fires the loud "outside corpus" tell; leaving only
the _instrument_ envelope (fired only when its bucket has **n≥8**) fires a milder
"unusual for Timpani" tell — honest that the value is precedented in general.
_Avoid_: fabricating a unit (ms/cents) to fill the gap — the range is the honest
form when RE can't pin a real one; computing the stats live from open effects (no
global corpus, per-session cost, a duplicated signed list); showing the range where
an enum or real unit already grounds the value (redundant noise); reading a signed
param's stats in raw 0–255 space (they are signed-space, matching the cell's
sign-extended display); framing the per-instrument range as **causal** (the byte's
meaning changing per instrument) rather than correlational — not RE-validated;
dressing a **tiny** instrument bucket as a range or letting it drive the amber tell
(n<8 is too flimsy — show the line, gate the tell); reusing the loud "outside corpus"
tell for an instrument-only miss (the value IS precedented elsewhere).

**Ghost bar** (effect-studio):
The **read-only projection** of a resolved sound's *real length* (and its
[anchor](16-effect-studio-authoring-tool.md)) onto the effect-frame ruler, drawn behind a
[trigger](16-effect-studio-authoring-tool.md). It is the visual bridge between the two clocks —
computed `tick → second → frame` through the tempo map — so an author can *see* a
sound's body/hit against the visual climax and nudge the trigger to line them up.
It is **not editable on that axis** (you edit length in the
[FEDS content editor](16-effect-studio-authoring-tool.md)) and is **never a click target** — it is drawn
*behind* the [trigger](16-effect-studio-authoring-tool.md) marker, which always wins z-order. Rendering:
**always-on and faint** (same colour + alpha, so overlapping washes composite
order-independently and a doubled-up region simply reads denser), each with a hairline
top edge so every extent stays traceable under a neighbour; the **selected** trigger's
ghost brightens and draws in front. Paint passes: faint fills → selected fill →
hairlines → markers.
_Avoid_: making the ghost bar editable or clickable; letting its width drive the
trigger's select hit-rect; treating it as the trigger's `duration_frames` (that is the
**`gap`** to the next event, unrelated to real length).

**Ghost pips** (effect-studio):
The [ghost bar](16-effect-studio-authoring-tool.md)'s interior detail: read-only tick marks projecting
the resolved pair's **note onsets** (loops **unrolled** — a ×14 loop marches 14
pips) onto the effect-frame ruler, so an author sees where a sound *articulates*
against the palette/screen/particle lanes at those frames — not just its extent
(the energy swell shows where the sound *is*; pips show where it *hits*). Scoped,
not always-on: drawn on the **selected** trigger's ghost, and on every ghost
resolving to the pair currently open in the [FEDS content
editor](16-effect-studio-authoring-tool.md); selecting a note there emphasizes its pip(s) — the
linkage is **one-way** (editor → timeline). Inherits the ghost bar's honesty
policy: fire-0 resolution for multi-fire container [Modes](14-audio.md),
frame-resolution intent ("≈this frame"), and **never a click target**.
_Avoid_: making pips clickable or editable (the timeline shows *where*, the FEDS
editor is *what*); drawing pips folded (playback spools loops — the projection
must unroll); rendering pips on every ghost all the time (the faint-wash rule —
unscoped pips are noise).

**Anchor** (a.k.a. **sync point**) (effect-studio):
The point *within* a sound that should land on a chosen effect frame — its audible
**hit**, as opposed to its playback start. An author drags the sound so its anchor
snaps to the climax; the tool back-computes the fire frame
(`fire_frame = hit_frame − anchor_offset`) and stores a plain early
[trigger](16-effect-studio-authoring-tool.md). An **authoring-tool convenience with no ROM
counterpart** — the bytes stay byte-faithful. One scalar crossing the surface
seam: defined in the [FEDS content editor](16-effect-studio-authoring-tool.md), consumed by the
trigger scheduler.
_Avoid_: conflating the anchor with the trigger frame (the trigger is *start*, the
anchor is *hit*); expecting the ROM to honour it (it fires and starts at tick 0).

**Chain inspection** (effect-studio):
The [ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)
nav stack **seeded with a whole [Effect-cast SFX chain](14-audio.md) in one gesture and
rendered as co-resident sections**, instead of walked one drill at a time. Clicking a
sound [trigger](16-effect-studio-authoring-tool.md) opens its event, its [SoundContainer](14-audio.md) and its
[FEDS](14-audio.md) pair together: three projectors, three addresses, one page. It is a
**navigation** shape, not a model one — the three tiers stay three surfaces
([ADR-0085](../adr/0085-effect-sfx-authoring-is-three-projected-surfaces-not-one-flattened-ruler.md)),
each keeps its own projector and its own write channel, and no edit moves onto a shared
axis. Where the container can fire more than one pair (15.3% of events), the last entry
seeds to the **first fire** — the pair the [ghost bar](16-effect-studio-authoring-tool.md) already draws —
and a dropdown labelled by **fire ordinal** flips it. A one-entry stack is a chain
inspection of length one, which is just an ordinary inspection — and so is a
[terminator](16-effect-studio-authoring-tool.md) end-cap, which fires nothing and therefore has no chain even
when its padding `sound_id` resolves to a live container (112 end-caps across 52 effects
carry one that does).
_Avoid_: calling it a "page" or an "all-in-one page" (it is a stack rendering, and the
studio has exactly one inspector surface); calling it "flattening" (nothing is flattened
— co-resident is not one ruler); saying it *replaces* the drill-down (a `link` to
something already on screen becomes a scroll-to anchor, and everything not seeded as a
chain still drills exactly as before).

**Fully-tiled lane** (law):
Every [lane](16-effect-studio-authoring-tool.md) is contiguous with no gaps: each
[lane event](16-effect-studio-authoring-tool.md) occupies its `[start, start+duration)` back-to-back.
"Nothing happening" is therefore always an **explicit null event**, never an
absence — a null span (emitter 0), a null palette tween (enable off), or a null
trigger (sound 0). **Exception**: the **screen** lane has no true null — a
"disabled" screen entry is an active [Gradient](16-effect-studio-authoring-tool.md) tween, not a hold.
_Avoid_: modeling a gap as empty space *between* events; assuming a disabled
screen entry is a hold (only palette disables are holds).

**Emitter field / Particle field**:
An [emitter](15-effect-orchestration.md)'s parameters split by **what they
characterize** — the primary way the inspector groups them:
- **Emitter fields** describe the *emission*: where/how-wide/how-many/how-often
  — position, spread (spawn-point variance), particle count, spawn interval.
- **Particle fields** describe each *spawned particle*: velocity, physics
  (weight/drag/acceleration/inertia), lifetime, homing, and color. Most are
  **stamped at birth** by the emitter (they ramp over the burst — see param
  shape); two — **color** and **homing blend** — animate over the particle's
  *own* life.
The tell for authoring: "when I say *velocity*, is it the emitter's or the
particle's?" → the **particle's** — the emitter merely stamps it at spawn. This
"characterizes" axis is **orthogonal** to *when a field is sampled*: velocity is
sampled at spawn (on the emitter's timeline) yet is a particle trait. Sprite/anim,
anchor modes, child-emitter refs, and flags are neither — they are emitter
**config constants**.
_Avoid_: grouping params by sampling clock (emitter-age vs particle-age) — that
is derived, not authored; assuming "sampled at spawn" ⟹ "characterizes the
emitter" (the mistake velocity exposes).

**Param shape (from / to / curve)** and **range**:
The structured authoring atom for one scalar emitter param — replacing the four
flat on-disk floats (`…_min_start`, `…_max_start`, `…_min_end`, `…_max_end`). A
param is `{ from: range, to: range, curve }`:
- a **range** is a `[min, max]` pair; each spawned particle draws a *random*
  value within it (the stochastic spread across the cloud).
- **from** / **to** are the two endpoint ranges; the value glides from `from`
  toward `to`.
- the **curve** (0–1) *is* the driver of that glide — **not** a shape layered on
  a linear ramp. **No curve ⇒ the param is pinned to `from`; `to` is inert.**
  This is the per-param `curve_indices` nibble from the ROM emitter struct.
The curve is a **facet of the field**: the [curve painter](16-effect-studio-authoring-tool.md) opens
from a specific param, never from a keyframe (the "getting ahead of ourselves"
seam this model fixes). Birth-stamped [particle/emitter fields](16-effect-studio-authoring-tool.md)
read the curve *once at spawn* (the glide plays over the emitter's burst); the two
life fields (color, homing blend) carry only a curve (no from/to), read each frame
over the particle's life.
_Avoid_: exposing `min_start/max_start/min_end/max_end` as four sibling floats;
calling the `[min,max]` a "spread" (taken by the spatial `spread_*` field) or a
"jitter"; treating `to` as always meaningful (it is inert without a curve).

**Field relevance (Live / Inactive / Dead)** and **gate**:
The salience verdict the inspector attaches to every [emitter/particle
field](16-effect-studio-authoring-tool.md) — "is this field *actually doing anything* right now?"
There are exactly three states, and they demand opposite UI treatment:
- **Live** — read by the sim *and* carrying a value that changes the output.
  Rendered normally.
- **Inactive** — read every frame, but its current value is the group's
  **neutral value** so its term *drops out of the simulation entirely* (adds
  nothing / multiplies to nothing). The field is fully wired — an author edits
  it to *wake* it. Neutral is **not always zero** — it is 0 for the additive
  terms (launch direction, direction scatter, acceleration, drag, outward
  speed, gravity scale). **Inertia has no such neutral** (build 2026-08-11): the
  ADR guessed 4096 (the ×1.0 divisor), but the real integrator makes 4096 the
  identity *only* when the particle-header `inertia_threshold` is 0 — at the
  default 512 it decays velocity ×0.875. Since neutrality depends on a header
  field the oracle can't see, inertia is **never merely Inactive** — but it *is*
  **Dead** when the particle's velocity is provably 0 for all time (velocity
  amendment 2): inertia only *decays an existing velocity*, so when no source
  creates one — spawn speed 0 (radial 0 / Skip mode), acceleration 0, **drag 0**
  (drag is a constant *force*, `accel += drag`, a velocity SOURCE not a consumer,
  so a non-zero drag revives inertia), gravity/weight 0, and homing 0 — the
  inertia divisor can never move output. Sim-guarded both ways. Inactive fields
  are shown **collapsed and marked**, never hidden — hiding a wake-able knob is
  the trap.
- **Dead** — editing it **provably cannot change the output** given its
  siblings' current values, so editing it does nothing. Two mechanisms, one
  verdict: the field is either **never read** (behind a guard — e.g. target
  offset when homing is 0) **or read then annihilated** (computed but multiplied
  to nothing — e.g. a launch **direction** multiplied by an **outward speed** of
  0). The author-facing meaning is identical; the [sim guard](16-effect-studio-authoring-tool.md)
  tests exactly this ("set the gate, assert the field cannot move output"), so
  both mechanisms are one Dead state. Hidden behind a per-section reveal.
A **gate** is the field whose value flips another field between Dead and Live:
`homing_strength == 0` deads *target offset* + *homing blend*; a group's
`curve == none` deads that group's **end axis** (proven: `interpolate_*`
returns `start` when `curve == null`); `color enable` off deads *color R/G/B*;
a disabled *child mode* deads its child-emitter index. **A gate is never
hidden** — it is the switch the author throws to bring the block to life, and
it carries its own marker pointing the *other* way (hover = "what I'm
suppressing"). Two asymmetries worth stating: **Position** is never Inactive
(offset 0 = *spawn at the anchor*, a real place, not "nothing"); **particle
count 0** is not a mild Inactive but the louder "this emitter emits nothing."
The "shown collapsed, never hidden" (Inactive) and "a gate is never hidden"
rules above describe the **default view**. A session-local **"Hide inert"**
mode (ADR-0089 amendment, the `Hide inert` toolbar toggle) deliberately
overrides both: with it on, the emitter inspector renders a field **iff its
state is Live**, so Inactive fields, Dead fields, *and* suppressing gates at
their neutral (`homing_strength`/outward speed 0) all vanish, along with the
Dead reveal, the formula view, and any section left with no live rows. It is
opt-in, default off, never saved to the effect; the only way back to a hidden
knob is to toggle it off. It composes with the verdict-flip reproject — a field
edited to Live reappears, one deadened vanishes.
_Avoid_: conflating Inactive with Dead (they invert whether you hide the
field); treating "all zero" as the universal neutral (inertia's is 4096);
hiding a gate or an Inactive field (you strand the knob that wakes the block);
calling a field Dead off a value eyeball rather than a proven read-gate;
asserting inertia's neutral is 4096 (refuted — its identity is header-dependent).

**Annihilator** and the **formula view**:
For a Dead field killed by the **read-then-annihilated** mechanism, the honest
"why" is the **active formula with the killing factor marked**. The
**annihilator** is a *zero factor in a product* that forces the whole term to
zero — e.g. in `velocity = direction × speed`, an outward **speed** of 0
annihilates the **direction** factor, so *launch direction* and *direction
scatter* are Dead. The velocity family reads as three mode-selected formulas
(**Outward/Unit-oriented** `direction × speed`; **Inward** `(toward center) ×
speed` — direction absent; **Skip** `velocity = 0` — constant). The formula
view marks **all applicable** culprits (a *set*, not one), under one rule:
mark a **zero factor** as annihilating a field only when that field is a **live
factor in the active formula**; when the field is instead **omitted by the
mode** (direction under Inward/Skip), mark the **mode switch** as the culprit,
not the zero sibling. Shown only **under the Dead reveal** (never in the resting
view). _Avoid_: marking a zero/neutral sibling as annihilating a field the mode
already dropped from the formula (it isn't a factor — the mode is the culprit);
calling a *mode flag* an "annihilator" (it omits, it doesn't multiply to zero).

**Field Dependency Inventory**:
The bounded, per-field table derived by reading the sim formulas one field at a
time — the **source of truth** the [relevance](16-effect-studio-authoring-tool.md) oracle is
generated from (not a throwaway doc). One row per [emitter/particle
field](16-effect-studio-authoring-tool.md) + config flag, columns: *consumed-by* (`file:line`
formula), *neutral value* (drives Inactive), *gated-by* (upstream switch +
condition ⇒ this is Dead), *gates* (what this field deads at its neutral), and
the *why-string* the UI shows on hover (`"target offset unused — homing
strength is 0"`). The *gated-by* / *gates* columns are the edges of a directed
**annihilation graph**; the why-string is one edge read aloud. Each Dead edge
is backed by a guard that sets the gate in the **real sim** and asserts the
gated field cannot affect output — the [static-rooted, dynamically-validated]
rule, so the oracle can never drift from the engine.
_Avoid_: asserting an edge from a formula skim without the sim guard; letting
the oracle encode gates the inventory hasn't proven (it supersedes ADR-0089's
ad-hoc "dim all-zero groups" heuristic, which conflates Dead/Inactive and
misses inertia = 4096).

**Playhead / scrub**:
The playhead is the single frame cursor swept across the [score](16-effect-studio-authoring-tool.md)
by the [transport](16-effect-studio-authoring-tool.md). **Scrub** = dragging it (or clicking the
ruler) to seek the preview to an arbitrary frame — the audio-editor gesture the
tool is built around. Seeking is **frame-exact and deterministic**: seek-to-N
pumps the clock exactly N fixed frames, and replay reproduces the identical
particle cloud because each `EffectInstance` carries a **per-instance seeded
RNG** re-seeded on `reset()` (see ADR — gameplay still varies cast-to-cast; only
in-instance replay is pinned). Forward scrub pumps forward from the current
frame; backward scrub `reset()`s and re-pumps from 0.
Two playheads can be on screen at once, on two clocks. Bare **"playhead"** always
means this one, the score's. The **sequence playhead** is the [sequence
player](16-effect-studio-authoring-tool.md)'s own cursor over one sequence's opcodes, running on that
panel's independent clock at its own rate — a different cursor over a different
axis, and it is never scrubbed (there is nothing between opcodes to land on). They
are one concept on two clocks, so the code keeps one vocabulary for both:
`SequenceCanvas.playhead_op()` and `SequenceThumbnail.PLAYHEAD` are the sequence
one, spelled plainly, and the qualifier lives in the prose
([ADR-0100](../adr/0100-the-inspector-row-has-one-right-column-bounded-by-declared-content-width.md)).
_Avoid_: seeking via wall-clock `tick(delta)` — the accumulator's one-frame
time-mod lag makes that drift; expecting a global-`randf()` sim to replay
identically (the seeded-RNG change is what makes scrubbing stable); saying bare
"playhead" for the sequence one, or renaming either to disambiguate — the two are
qualified in prose, not in code.

**Curve clock domain**:
Which frame counter a curve is read on — the fact that resolves "at what frame
are we at which part of the curve?" ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
span-anchored-marker amendment). Three domains, and a curve belongs to exactly
one: **emitter-elapsed** — the [Emitter](16-effect-studio-authoring-tool.md) + Particle · born-with
curves, read at `ActiveEmitter.elapsed_frames` *at spawn* (position, spread,
particle count, spawn interval, velocity, weight, drag, acceleration, inertia,
lifetime, homing strength, target offset); **particle-age** — the Particle ·
over-life curves, read at `particle.age` (colour R/G/B, homing blend);
**callback-frame** — callback curves, read at the callback's own counter. Only
the **emitter-elapsed** domain has a single-valued playhead map (one firing, one
`elapsed`, one point); particle-age is intrinsically *per-particle* (many
particles alive at one playhead, each at a different age) — which is why it needs
its own marker, not this one. The surface that already carries this domain is the
[film strip](16-effect-studio-authoring-tool.md): because `duration=2` is three quarters of the corpus,
one opcode row **is** one game frame **is** one curve sample for 83.6% of cells
(the [ribbon cut](16-effect-studio-authoring-tool.md)), so a new age-axis surface would be a second copy
of an axis already on screen.
_Avoid_: assuming all of an emitter's curves share a clock (colour is the odd one
out); calling the over-life colour bar's frame ruler a playhead map (it is
[per-life](16-effect-studio-authoring-tool.md), not tied to the global playhead).

**Curve playhead marker** ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md) span-anchored-marker amendment):
The read-only cursor drawn on an **emitter-elapsed** ([curve clock
domain](16-effect-studio-authoring-tool.md)) curve to show where the [playhead](16-effect-studio-authoring-tool.md) is on
that curve *right now*. Position is pure geometry — `elapsed = playhead −
span.start`, curve index `= elapsed % 160` — and sits **exactly** where
`EffectCurve.sample_by_frame` reads, so it never lies about the sim's sample site.
Drawn on both the [curve painter](16-effect-studio-authoring-tool.md) (primary, with a two-ended
`elapsed N · fF` tag bridging emitter-elapsed ↔ absolute frame, plus a `×N` lap
tag when the firing wraps past 160) and the inspector [curve
sparklines](16-effect-studio-authoring-tool.md) (bare line, no text). Requires a **[span](16-effect-studio-authoring-tool.md)
target** (a concrete firing start); a browsed/drilled emitter shows a hint, no
marker. **Out of the firing** (playhead before start / after end) it clamps to the
nearest edge, dims, and says *before / after firing*. Tracks **continuously**
during Play, so it sweeps over a looped [region](16-effect-studio-authoring-tool.md). It reads the
value being assigned to particles **spawned this frame** — not the state of
on-screen particles (those were born earlier, at earlier curve points).
_Avoid_: drawing it on over-life (particle-age) curves — those clock by
[age](16-effect-studio-authoring-tool.md) and get their own marker; a live-particle read to place it
(emitter-elapsed needs only playhead + start, no cast); click-to-seek (read-only
for now — the painter canvas stays paint-only).

**Transport**:
The Studio's playback controls, audio-editor semantics: **Play** resumes from
the current playhead (not always 0), **Pause** halts in place, **Stop** returns
the playhead to 0 and halts; plus [Loop mode](16-effect-studio-authoring-tool.md), frame-step (±1
frame), and a speed multiplier (0.25/0.5/1/2×). The **ruler is the seek surface**
(click/drag = seek); clicking a **span** in the lane area instead **selects** it
for the [keyframe inspector](16-effect-studio-authoring-tool.md), so "seek here" and "inspect this"
never fight over one click. During Play the transport is **page-driven** (the
page computes the next frame each 30 Hz × speed tick and `studio_seek`s it,
per [ADR-0090](../adr/0090-effect-studio-region-loop-is-a-session-span-driven-by-a-page-side-bounce-transport.md))
— it no longer mirrors the host instance's free-running clock.

**Loop mode**:
The [transport](16-effect-studio-authoring-tool.md)'s loop state — **Off**, **Forward**, or
**Ping-pong** — cycled from one control (replacing the old on/off Loop toggle).
**Forward** wraps `end → start`; **Ping-pong** reflects at both ends
(`… end-1, end, end-1 …` / `… start+1, start, start+1 …`, each endpoint shown
once per pass — _reflect, not repeat_). What it loops is the [loop
region](16-effect-studio-authoring-tool.md) when one is set, else the whole score (`0 .. stop
frame`). Direction resets to forward on each Play. Persists across effect loads
as page state (like [Ripple](16-effect-studio-authoring-tool.md) / Hide-inert).
_Avoid_: a separate "region loop" control distinct from whole-score loop (there
is one loop concept; the region only changes _what_ is looped); repeating an
endpoint frame on turnaround (that's a visible 1-frame stutter).

**Loop region**:
A session-scoped, inclusive `[start, end]` span of frames that bounds automatic
[transport](16-effect-studio-authoring-tool.md) playback — drawn on the [frames bar](16-effect-studio-authoring-tool.md)
by **Alt+left-drag** (plain drag still scrubs), adjusted by its edge handles /
body, cleared to fall back to whole-score looping. Shaded on the ruler and as a
full-height band across the lanes. **Ephemeral**: never written to `E###.BIN`,
and cleared on effect load (frames are effect-specific). A one-click **"Loop
life"** sets it to `[0, animation display length]` — the particle's real
lifespan. Only bounds the automatic transport; scrubbing/stepping stays free
anywhere for single-frame inspection.
_Avoid_: a loop marker persisted into the effect file; constraining the playhead
to the region while scrubbing.

**Keyframe inspector**:
A panel docked on the right of the Studio showing the current
[inspection target](16-effect-studio-authoring-tool.md) ([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)
generalized it from "the selected span" to a `{kind, ref}` target). For a **particle span**
target it navigates keyframe(span) → the referenced [emitter](15-effect-orchestration.md) → the
[emitter view](16-effect-studio-authoring-tool.md), with a **span header** (Kind/Phase/Frames/Authored) above;
the Event section's "Emitter" row is a [link](16-effect-studio-authoring-tool.md) into that emitter. For an
**emitter** target (reached via a link, an [incoming edge](16-effect-studio-authoring-tool.md), or the
[emitter browser](16-effect-studio-authoring-tool.md)) it shows the bare emitter view — the four groups + an
emitter header with [provenance](16-effect-studio-authoring-tool.md), and **no** Event/Phase/Frames (those are
keyframe-owned). For a non-particle span (screen/palette/camera/sound
[tween](16-effect-studio-authoring-tool.md)/[trigger](16-effect-studio-authoring-tool.md)) it keeps the flat typed label/value rows.
The ancestor trail is **not** in this panel: it moved out to the [path bar](16-effect-studio-authoring-tool.md),
where it can be told apart from the target's own label/value rows. **Read-only**
for now (`EffectScoreModel` + the per-kind projectors are the pure projection; the panel is
thin glue), built so edit widgets can replace the value cells when authoring lands.
_Avoid_: a transient hover tooltip as the primary surface — the inspector is a
persistent panel you can study and (later) edit; jumping keyframe → a flat list of
curves (the "getting ahead of ourselves" seam — the curve hangs off a
[param row](16-effect-studio-authoring-tool.md), never the keyframe).

**Emitter view**:
An [emitter](15-effect-orchestration.md)'s params laid out as four collapsible accordion
sections in the [emitter/particle field](16-effect-studio-authoring-tool.md) order — **Emitter** (emission),
**Particle · born-with**, **Particle · over-life**, **Config** (constants) — each holding
[param rows](16-effect-studio-authoring-tool.md). It is the shared grouped projection reached BOTH *through* a
particle [span](16-effect-studio-authoring-tool.md) (under its Event section) AND directly as the bare
**emitter** [inspection target](16-effect-studio-authoring-tool.md) (with a [provenance](16-effect-studio-authoring-tool.md) header
instead of an Event section). Its Config child-on-death / mid-life rows are
[links](16-effect-studio-authoring-tool.md) to those child emitters' views. **In THIS view** sections default
expanded — the per-kind default is the projector's to declare (a section may carry
`collapsed: true`, which the [sequence player](16-effect-studio-authoring-tool.md)'s opcode sections do, and so
does the trailing **Advanced (raw)** group in both the emitter and camera-tween views: dead
bits and opaque callback bytes are the last thing the ~268px row should spend its opening
height on), and the inspector's default when none is declared is expanded. Section collapse
state is per-session view state keyed by a projector-supplied `fold_id`, not persisted to
disk — so a `collapsed` hint WITHOUT a `fold_id` re-shuts the section on every rebuild and
the author re-opens it forever; the two are declared together or neither works.
`EffectScoreModel.emitter_view` is the testable projection (ordered groups of rows); the
panel just lays it out.
_Avoid_: tabs (they hide the cross-group relationships authoring reasons over) or a
flat header list (the born-with/over-life distinction gets lost); surfacing the
opaque **`callback_params`** bag — it is un-modeled (per-callback meaning) and
intentionally OMITTED until the callbacks are decoded (door #2), not shown raw and
not faked as params.

**Param row**:
One row in the [emitter view](16-effect-studio-authoring-tool.md): `name │ from → to │ curve` for a
scalar/vector emitter param, rendered in the param's natural **shape** — `vec3`
`(x, y, z)`, a `range` `min – max` (the stochastic spread each particle draws in),
a `vec3_range` `lo(…) hi(…)`, an `int`, a `curve_only` over-life trait (color /
homing blend — no from/to), or a `const` (a [Config](16-effect-studio-authoring-tool.md) value, no
from/to/curve). The curve is a [curve sparkline](16-effect-studio-authoring-tool.md). Params flow into
1–3 responsive columns so a wide dock lays them side-by-side.
_Avoid_: exposing the four on-disk floats (`min_start/max_start/min_end/max_end`) as
sibling cells — collapse them into one `{from, to}` row (the
[param shape](16-effect-studio-authoring-tool.md) atom).

**Curve sparkline**:
The per-[param-row](16-effect-studio-authoring-tool.md) curve affordance — a tiny inline drawing of the
param's own [curve](16-effect-studio-authoring-tool.md) (normalized polyline of the ROM samples, same
data the [curve painter](16-effect-studio-authoring-tool.md) binds) that is itself the click target:
pressing it opens the painter scoped to THAT param's curve index. The curve is a
*facet of the param*, so the affordance lives on the row, never as a separate
"edit curve" button or off the keyframe. A [pinned/disabled](16-effect-studio-authoring-tool.md) param
draws a greyed flat line. It is **trimmed and normalized to the used window**
(only samples `0..N`, X-stretched, Y re-fit) — a wrapping (≥160) or
animation-driven (lifetime −1) window falls back to the whole curve, un-trimmed
(ADR-0089 curve-UX amendment). Distinct from the **[curve painter](16-effect-studio-authoring-tool.md)**,
which keeps ALL 160 frames (you edit the whole curve) but **veils the inactive
tail past N + marks the boundary** — same `used_n`, opposite presentation
(sparkline trims what the painter dims).
_Avoid_: a button labelled "curve N" (reads as a bolted-on action, the indirection
this replaces); drawing a sparkline for a param with no curve (it has no shape).

**Curve use site** ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
curve-ownership amendment, 2026-08-20):
The thing a [curve](16-effect-studio-authoring-tool.md) belongs to — an `(emitter, slot)` pair, where slot is
a param name or one of colour `r`/`g`/`b`. Every curve reference in the game resolves
through one of these two dicts on an emitter, the callbacks included, so there is no such
thing as an effect-global curve reference (the pacing curves are not in the table at all).
A use site **owns** its curve privately: editing it moves nothing else. Median 22 use
sites per effect, max 67.
_Avoid_: "curve index" as a way of naming a curve in authoring vocabulary (indices are an
[export](16-effect-studio-authoring-tool.md) concern); treating two use sites that happen to draw the same
[shape](16-effect-studio-authoring-tool.md) as the same curve.

**Curve explode** ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
curve-ownership amendment, 2026-08-20):
What load does to the ROM's shared 15-slot curve table: hands every
[use site](16-effect-studio-authoring-tool.md) its **own private copy** at its own new index, repointing the
emitter field. After it, no two use sites share an index, so privacy is structural rather
than a rule any write path could forget. The array grows (15 → ~22 median) but the read
path does not change — a use site still resolves by index, so every `get_curve()` caller
is untouched. Each copy keeps its **provenance** (the slot it came from) so an unedited
effect [compiles](16-effect-studio-authoring-tool.md) back to its original indices. Curves nothing references
are **residue**: not use sites, carried aside, restored to their original slots on export
(6.5 per effect on average; 28% of them are distinct real shapes, not padding).
A reference that does NOT resolve becomes an explicit -1: the corpus has exactly 60, all in
`E509`/`E510` (7 emitters apiece pointing into a `curves.json` with zero entries). They read
as "no curve" before the explode because `get_curve` range-checks, and a longer exploded
array would otherwise have let a stale index start resolving to another use site's curve.
_Avoid_: calling this a fork or copy-on-write — it is unconditional and happens at load,
which is the whole point; treating residue as authorable; reading `curve_indices_raw` as the
live assignment (post-explode it is ROM provenance, and `em.curves` is the authoring truth).

**Curve shape** ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
curve-ownership amendment, 2026-08-20):
A *distinct* 160-sample sequence, as opposed to a [use site](16-effect-studio-authoring-tool.md)'s curve
(which is an instance of one). After [explode](16-effect-studio-authoring-tool.md) an effect holds median 22
curves carrying median 8 distinct shapes, max 15. Shapes are what the
[picker](16-effect-studio-authoring-tool.md) shows and what the [compiler](16-effect-studio-authoring-tool.md) emits, so the
distinct-shape count is the effect's PSX budget: **shapes in use / 15**. An untouched
effect is ≤15 by construction; authoring is what can overrun it.
The gauge is `CurveShapeSet` — one dedup, by the quantized 0-255 bytes the compiler will
actually write, feeding both the picker's tiles and the "Shapes N/15" read-out in the curve
painter's header. Residue is NOT counted: it occupies ROM slots, so byte-exact headroom is
tighter than `15 − distinct-in-use`, but spending a residue slot costs byte-exactness rather
than correctness and the call is the [compiler](16-effect-studio-authoring-tool.md)'s.
_Avoid_: counting curves when you mean shapes (22 vs 8 — the first is never the budget);
reading the gauge as a hard authoring limit (it is a watch, not a wall — the refusal is at
export, which is only fair BECAUSE the watch exists).

**Identity curve** ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
curve-ownership amendment, 2026-08-20):
The all-zero curve, `constant(0)` — what a [use site](16-effect-studio-authoring-tool.md) with no curve gets
when one is added, so that adding a curve changes **nothing** until it is painted. Exact,
not approximate: no curve makes the sim hold the **start** values, and an all-zero curve
lerps to `min_start` at every frame, bit-identically. 71.9% of the ROM's unreferenced
curve slots are already all-zero — FFT's dead padding *is* the identity.
`CurveGenerators.constant(0)` mints it, and it is the ONE way a use site gains a curve —
`CurveExplode.mint_identity` — so "adding a curve changes nothing until it is painted" holds
whether the caller then paints or not.
_Avoid_: describing "no curve" as a linear start→end ramp (this ADR's line 40 and the
picker's `none` glyph both did until 2026-08-20; the sim does no such ramp — it holds the
start values); confusing it with picking `none`, which CLEARS a use site's address and is
not the same as giving it a flat curve (colour reads the two differently — a null colour
curve is not black).

**Curve compile (PSX pack)** ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
curve-ownership amendment, 2026-08-20):
The export step that turns N private curves back into the ROM's shared, indexed, ≤15
table — dedup by value, restore indices by [provenance](16-effect-studio-authoring-tool.md), re-pack the
nibbles. **Sharing exists only here**: it is an output format, never an authoring model,
so it is also the only place that has to be tested for it. More than 15 distinct
[shapes](16-effect-studio-authoring-tool.md) is a **compile error** that names the overrun for the author to
resolve, never a silent merge — a merged colour curve is a visual regression a numeric
tell cannot convey. Headroom is genuinely tight: 29 effects (7.3%) have zero spare slots
and 78 (19.5%) have ≤2, against up to 3 shapes spent per colour emitter authored.
Provenance is `EffectCurve.index` (the ROM slot a private curve was copied from, -1 for a
minted one) plus `raw_data.curve_indices_raw`, the untouched ROM nibbles. Nothing reads
either yet — a cost carried deliberately, since only the compiler exercises them.
_Avoid_: enforcing the 15-slot or `0..15` nibble limit anywhere upstream of this step
(authoring is unbounded by design — the param nibble, the colour nibble and the 2-bit homing
pair all had such a cap and all lost it); "consolidate" as a synonym for merging *unlike*
shapes; overwriting `curve_indices_raw` from the authoring side (it is the provenance this
step reads).

**Curve assignment picker**:
The left cell of the [curve](16-effect-studio-authoring-tool.md) row — a **thumbnail picker** whose face
shows the current [shape](16-effect-studio-authoring-tool.md) as a mini [sparkline](16-effect-studio-authoring-tool.md) and whose
grid shows candidate shapes. Since the [curve-ownership amendment](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
(2026-08-20) its verb is **copy, not reference**: a pick writes that shape into this
[use site](16-effect-studio-authoring-tool.md)'s own curve and nothing links afterward. It is fed the
**distinct shape set**, never the post-[explode](16-effect-studio-authoring-tool.md) array — median 8 tiles,
not median 22 — which makes its tile count the live PSX budget gauge (see
[curve compile](16-effect-studio-authoring-tool.md)). Candidate shapes are **generated**, not browsed from a
library: 16 parametric generators (`linear`, `ease_in`/`out`, `s_curve`,
`exponential_in`/`out`, `sine_wave`, `triangle_wave`, `sawtooth`, `pulse`, `constant`,
plus `invert`, `reverse`, `scale`, `shift`, `copy`). Thumbnails draw the **whole curve,
un-trimmed** — browsing compares shapes, and the used window belongs to the param
(identical for every candidate), so trimming there misleads.
A pick lowers the shape's SAMPLES on the `curve_assign` channel, addressed by use site
(`emitter_index` / `slot` / `kind`) — never an index, because there is none to name. A pick
onto a site with no curve mints the [identity](16-effect-studio-authoring-tool.md) first; picking `none` clears
the ADDRESS and leaves the array alone (removing an entry would renumber every index above
it). `none`'s glyph is the identity curve, dim — flat at zero is literally what no curve
does.
_Avoid_: describing a pick as "assigning curve N" (there is no shared N to assign — that
is a [compile](16-effect-studio-authoring-tool.md) concern); trimming/normalizing picker thumbnails (a
row-sparkline rule, not a browse rule); a global shape library (2443 corpus shapes with
only 421 reused across effects — a browsing problem, not an authoring one); deleting a
curve entry to "clean up" after a `none` pick.

**Curve contents**:
The 160 samples a [curve painter](16-effect-studio-authoring-tool.md) edits. **Private to its
[use site](16-effect-studio-authoring-tool.md)** since the [curve-ownership amendment](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
(2026-08-20): an edit moves that one param on that one emitter and nothing else. It
previously mutated a *shared* curve, which restyled every referring param — the common
case, not the tail (70.8% of ROM curve slots have more than one referrer; `E009` curve 0
has 30), and the reason the model changed. The edit routes through the edit-session choke
point (undoable) and is saved to `curves.json`; the **pacing** curves already worked this
way and were the model's working proof. Distinct from a [pick](16-effect-studio-authoring-tool.md), which
replaces the whole [shape](16-effect-studio-authoring-tool.md); the painter reshapes the one you have.
The painter PREVIEWS into a local grid and reports the finished stroke on mouse-up
(`curve_changed(values)`); it does not write the bound curve. It used to, back when the edit
was ephemeral — but the choke point has to see the pre-edit samples to snapshot them, which
it cannot if the painter has already overwritten them, so undo would have restored the value
it had just written. `CurveChannel` writes; one stroke is one undo.
_Avoid_: "shared curve contents" (the sharing is a [compile](16-effect-studio-authoring-tool.md) output, not
a thing you edit); a global curve-table editor — the honest home for a shared N-referrer
surface, dissolved along with the sharing it existed to make visible; writing an
EffectCurve's samples anywhere but the channel (a write that bypasses the choke point is a
lost undo, not a shortcut).

**Colour ribbon** (VERTICAL since 2026-08-20 — ADR-0089's vertical-column amendment;
**WRAPPING** into up to `EffectStudioPage.life_columns` = 3 columns since the same day, dec. 6):
**it wraps into COLUMNS and the ribbon wraps WITH it** — each column of thumbnails carries its
own ribbon strip, which is the sentence that dissolved the old "a column beside a ribbon
cannot wrap" rule. Rows split *as many columns as it takes to avoid scrolling, up to three,
then BALANCED* (22 rows = two of 11, not 12 + 10). Corpus rows are median 9 / p90 22 / p99 35
/ **max 75**, so three columns cover the 99th percentile and **the tail still scrolls** — the
author was shown that and chose it over the uncapped form, which never scrolls but moves the
inspector's right edge on every click. The extra width is therefore bid CONSTANTLY, whatever
the emitter shows. The slot's declared minimum stays ONE column (raising it puts the panel's
floor over the inspector); the rest is a `_relayout` bid under the leftover clamp, and three
columns cost **198px, not 3×70** — one scrollbar for the whole scroller, and one scroll offset
so the columns cannot drift.
**COLOUR ON/OFF** lives in the player's transport row (`⏮ op / op ⏭ / 1.00× / Colour: on|off`,
dec. 7) — `emitter_flags_lo` bit 6, relocated out of the inspector's flag section. Not in the
picker panel: that panel only exists while an age is selected, so a toggle there could turn
colour off and never back on. Turning it ON where the emitter's r/g/b resolve to nothing
(**14 corpus emitters, all in E509/E510** whose `curves.json` is empty) **MINTS three flat
curves at the identity**, so the toggle means the same thing on all 605 off-emitters and
nothing on screen changes until authored.
**SELECTING AN AGE IS NOT KEYING IT** (dec. 5, same day): a click selects any life frame,
keyframe or not, and mints **nothing** — the second step is the picker's **⬥ Set keyframe**
button, and *nothing keys implicitly* (a colour pick on an interpolated age authors nothing,
which the author chose with that cost stated). Two orthogonal marks: an **outline** = selected,
a **bar** = is a real keyframe.
The resolved-colour bar in the [sequence player](16-effect-studio-authoring-tool.md)'s column, running **DOWN the
side of the [film strip](16-effect-studio-authoring-tool.md)** (`ColourLifeColumn`): **one row per thumbnail,
equal height; one column per life frame inside it.** So a thumbnail holding 3 frames shows 3
columns and a 1-frame cell shows one — 81.8% of corpus rows are a single column, which is
why "one colour per frameset" nearly holds and where it breaks. Row *i* IS thumbnail *i*,
both laid out from ONE projection (`SequenceLifeMap.life_rows`), so **the misalignment the
author reported is unrepresentable rather than explained**. The axis is therefore **not
linear in time** — two rows are the same height whether the picture held 1 frame or 128, so
it is *not a clock*. It samples the colour the curves
actually **produce** at each particle-age frame (`Color(r,g,b)` from the same three
`sample_by_frame` reads the renderer uses in `_compute_color_modulate`, via one
shared pure resolve) and draws it as a horizontal strip. **The ribbon pairs frame *k* with
sample *k*, and the ROM says that is right** — `update_all_particles` draws at `0x801A2FE0`
and only THEN increments the colour phase at `0x801A301C` (`0x50`, wrapped at `0xa0` = 160,
zeroed on spawn), so a particle's first baked frame is drawn with sample **0**. The film
strip's `+1` was removed on 2026-08-20 to match, and the two studio surfaces now agree with
each other and with the game
([ADR-0103](../adr/0103-the-sequence-thumbnail-is-the-real-render-minus-position-and-camera.md)
dec. 6-CORRECTED, which reverses dec. 6's direction: the ribbon was never the wrong one).
**The Godot RUNTIME is still one sample ahead** — the sim increments `age` before
`ParticleAnimator.tick` reads its frame, so `_compute_color_modulate` samples *k+1*. That is
a spawn-vs-step ordering change in shared runtime code and is **filed, not fixed**.
**It moved out of the inspector on 2026-08-20** (ADR-0089's colour-move amendment): it, the
keyframe track and the picker are the player column's now, which took 477px (78%) off the
"Particle · over-life" section. Its window is the **particle's LIFE** (`EmitterLifeWindow`),
not the animation's display length the player's old read-only bar used — the honest bound on
what the renderer reads, and different for **1204 of 2622** colour-enabled corpus emitters
(698 by more than 8 frames). The [film strip](16-effect-studio-authoring-tool.md) beside it therefore no longer
shares its ruler; it **projects** onto it (`SequenceLifeMap`).
The old horizontal `ColourRibbon` survives **headless**: it still owns the sprite mux, the
global `Fit W` trim and the resolved `colors()` array — the shared resolve the renderer
paints with — but it no longer draws, and every call site re-parks it because `set_curves`
sets its own visibility. `ColourKeyframeTrack.band_width`'s **fixed 260px** rule (2026-08-19)
does **not** apply to the vertical column: that was an argument about a *linear* axis
(`width / n` a pure function of the life window, so two emitters compare) and it dissolves
with the axis. The column is `ColourLifeColumn.band_width`, 22px, narrow because every pixel
comes off the player's square. Its own frame ruler carries the
frame numbers. A
**frame ruler** under the
bands (tick marks + frame numbers, the studio frames-bar step ladder) reads "at frame
N the particle is this colour", ending with the total lived frame count. **Opaque RGB only** —
particle transparency is a *separate* per-frame flag (`semi_trans_on`) the colour
curves don't drive, so it stays out of the ribbon. **Hidden entirely when the
emitter's colour is disabled** (`color_curve_enabled` false → the curves colour
nothing, so [field-relevance](16-effect-studio-authoring-tool.md) says draw nothing). It answers "what
colour is the particle at each point in its life?" — the clarity the three abstract
per-channel wiggles don't give, and the read-side companion to a future
colour-keyframe authoring layer.
_Avoid_: calling it a "gradient" (that is the screen-backdrop two-stop
[colour mode](27-color-modes.md), a different concept); drawing it for a disabled or
absent colour-curve set (implies colour output that isn't happening); folding the
`semi_trans_on` alpha into it (conflates colour authoring with the blend flag and
can't reproduce additive blending anyway).

**Muxed colour**:
The colour an effect particle actually **renders** — `sprite_texel ⊙ colour_curve`
(per-channel multiply; `addons/exmateria_effects/render/effect_particle_opaque.gdshader:27`), as
opposed to the raw curve values `cr/cg/cb` the storage holds. The
[colour ribbon](16-effect-studio-authoring-tool.md) shows the muxed colour. The distinction is what
colour authoring is about: the curve inputs span the full `[0,1]³` cube, but the
muxed *output* is squashed into the [reachable box](16-effect-studio-authoring-tool.md) — so "0–255 in
every channel = every colour on screen" is an illusion.
Authoring itself happens in **curve** space, not muxed space
([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
decision 4, amended 2026-08-21): the picker's RGB *is* the curve triple. It used to
be the muxed target — pick the colour you want to see, and the tool inverted — which
put the whole authoring range inside the box: **97.5% of 3,213 corpus colour emitters
had no channel whose byte slider could hold 255**. The muxed colour is now what the
picker *reports* (a "renders as" swatch) rather than what it takes.
_Avoid_: using "muxed colour" for the raw curve triple (that is the *input*, and the
thing the picker now edits); conflating it with the [colour mode](27-color-modes.md) blend
of a screen tween; describing the picker as editing in muxed space (it did until
2026-08-21).

**Reachable box**:
The set of [muxed colours](16-effect-studio-authoring-tool.md) an emitter can produce, given the
multiply: `[0,S.r]×[0,S.g]×[0,S.b]` where `S` is the emitter's **representative
sprite texel** (the peak-luma visible texel, `EmitterSpriteColor.representative()`,
the same one the [colour ribbon](16-effect-studio-authoring-tool.md) uses). A multiply can only
*attenuate*, never add a channel the sprite lacks, so a green texel `(0,1,0)` makes
red and blue a **dead channel** (box side of length 0). Since 2026-08-21 the box
**bounds the render and is reported, never imposed on a pick**: the picker authors the
curve, all of `[0,1]³` is selectable, and the panel shows `S ⊙ curve` beside the grid
plus the dead channels by name. It used to clamp every pick into the box and lock a
dead channel's slider at 0 — a silent rewrite of the author's value, and the reason
*"I am not able to reach every [0,0,0] to [255,255,255]"* was literally true of the
control. The box is **convex** — which is why colour keyframes interpolate by **linear
RGB lerp only**.
_Avoid_: treating the box as fixed per effect (it is per-emitter, set by that
emitter's sprite); calling a colour outside it "author error" — it is *unreachable*,
and the honest answer is a different sprite/animation (deferred), not a clamp the
author can't see; re-introducing a clamp or a disabled slider as the way to express
it (a bound the author cannot see is the fault, not the cure).

**Inverse mux**:
The map from a picked [muxed colour](16-effect-studio-authoring-tool.md) `T` back to the curve values
that produce it: `curve = T ⊘ S` per channel (`S` = the representative texel). It is
exact and unique inside the [reachable box](16-effect-studio-authoring-tool.md) (`S.k = 0` ⇒ that channel
is locked to 0). It is **no longer in the authoring path**: colour keyframes hold the
curve triple directly and compile down without it (ADR-0089 decision 4, amended
2026-08-21). It remains the definition of the [reachable box](16-effect-studio-authoring-tool.md) and the
answer to "what curve would render this colour", which is what the box report is about.
_Avoid_: describing keyframe compile-down as going through the inverse mux (it did
until 2026-08-21; the round trip through `S ⊘ S` was the identity anyway).

**Colour keyframe**:
A joint colour-at-a-frame authoring point — one **curve** colour at frame F that sets
`cr/cg/cb` at F **together** (no independent per-channel keyframe times). It held the
[muxed colour](16-effect-studio-authoring-tool.md) until 2026-08-21; the value stored is the curve triple
now, so a keyframe and the sample it compiles to are the same number. Keyframes are the authoring layer; the dense 160-sample [curves](16-effect-studio-authoring-tool.md)
stay the compiled artifact (fed to the same `sample_rgb` the renderer and
[colour ribbon](16-effect-studio-authoring-tool.md) read). First colour-edit **forks** the emitter's
shared curves into 3 per-emitter curves (copy-on-write — colour curves are a shared
table, and many emitters **alias** all three channels onto one curve, which can only
ride the brightness ray `k·S`; the fork un-aliases and unlocks the box). Entering
keyframe mode on an existing ROM curve **imports** keyframes fitted to its 160
samples (no visual jump; exact for piecewise-linear). The read-side companion is the
[colour ribbon](16-effect-studio-authoring-tool.md).
_Avoid_: per-channel independent keyframe times (colour is authored jointly);
persisting keyframes as a new ROM artifact (they compile down to the curves, which
stay the source of truth on disk — and because they are re-derived from those curves
at every `begin()`, changing what a keyframe *holds* needs no migration); assuming the
fork is bounded by the
16-slot nibble cap (that is a [BIN-pack](16-effect-studio-authoring-tool.md) concern only — the game
curves array is unbounded).

**Pinned / disabled row**:
A [param row](16-effect-studio-authoring-tool.md) whose curve nibble is `-1` (`curves[name] < 0`): with
no [curve](16-effect-studio-authoring-tool.md) the param is **pinned to `from`** and its `to` is inert
(the [param shape](16-effect-studio-authoring-tool.md) law). The row greys its `to`, its `→`, and its
[sparkline](16-effect-studio-authoring-tool.md) IN PLACE — the curve-presence bit toggles an
enabled/**disabled** visual state, it does **not** hide the fields. Disabling a
curve never cascade-clears the `to` value it was driving.
_Avoid_: hiding the `to`/curve when there is no curve (causes layout jitter and
reads as "this field doesn't exist" rather than "inert right now"); clearing the
`to` value on disable.

**Inspection target** ([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)):
The unit the [keyframe inspector](16-effect-studio-authoring-tool.md) renders — `{kind, ref}`, where `kind`
selects a projector and `ref` is an **opaque, kind-specific** payload only that projector
reads (`span → {span_id}`, `emitter → {index}`, future `frame → {frameset_id, index}`). The
inspector is no longer "a span viewer"; a [span](16-effect-studio-authoring-tool.md) is just the timeline's
**drill-in handle** — one *kind* of inspectable object, not a privileged one. The generic
target is what lets the same inspector show an emitter reached with no span at all (a
child-ref, a browsed orphan) and, later, a frame/curve/animation.
_Avoid_: a single scalar `id` (breaks the moment a kind needs a composite identity — a
frame is `frameset + index`); the registry reading inside `ref` (only the kind's projector
may).

**Sequence** (the settled name; storage `animation`):
The opcode stream a particle plays to pick which [frameset](15-effect-orchestration.md) shows for
how long. It answers to **four** names across the stack and they are all the same object:
`EffectData.animations[i]` and an inspection `ref`'s `animation_index` (storage), the
emitter's `anim_index` byte (the reference), **"Animation set"** (the emitter Config row's
author-facing label), and **"sequence"** everywhere in the studio's own surfaces (the
`animation` target kind's title/breadcrumb, the browser, the Lua editor's sequences tab).
Storage keeps `animation` because that is what the file section is called; **prose and UI
say "sequence"**.
_Avoid_: "anim id" (ambiguous with a unit's `anim_id`, an unrelated SEQ/SHP concept — see
[sprite animation](19-animation-playback.md)); coining a fifth name in a new row label.

**Sequence player**:
The right-hand column of the [inspector](16-effect-studio-authoring-tool.md) row while an `animation`
[inspection target](16-effect-studio-authoring-tool.md) is open: the [sequence](15-effect-orchestration.md) assembled
and moving, drawn through the shared bounds box every one of its opcode thumbnails also
draws through. It owns the decode. It is **opcode-granular in every direction** — its
transport steps by opcode, a thumbnail click parks it on one, and the **sequence
playhead** ([playhead](16-effect-studio-authoring-tool.md)) addresses one — because `SequenceTimeline.trace` is
one cell per opcode and the picture is constant for that cell's whole dwell, so there is
nothing finer to land on and no scrubber. A click parks at the cell's **`pos_tick`** — the END
of its dwell — not at its `tick_start` (2026-08-20); for the 83.6% of cells that dwell one tick
those are the same number, and over the corpus 4,236 rows actually move.
It runs on **its own clock at its own rate** (0.1–4.00x, page-session state, default 1.00x =
true game speed), deliberately not the [transport](16-effect-studio-authoring-tool.md)'s: a sequence is a
reusable asset played by whichever particle references it, not a position on the effect
timeline, so parking the score must not park the animation being authored. It shares ONE
column slot with the [frameset viewport](16-effect-studio-authoring-tool.md), chosen by target kind
([ADR-0100](../adr/0100-the-inspector-row-has-one-right-column-bounded-by-declared-content-width.md)).
**Its size is a CONSTANT** — `EffectStudioPage._CANVAS_SIDE` (260) square, plus the panel's
own measured chrome — and the inspector row is FLOORED at it rather than deriving it
(`inspector_row_height`). Two derivations were tried and both had a term that moves: off the
inspector's `content_height()` the box resized on every click AND every fold (a container
minimum skips invisible children, so opening a section grew it); off the row's whole budget
it resized with the WINDOW, and on a tall one it grew to half the row and starved the
[focus panel](16-effect-studio-authoring-tool.md) beside it out of existence (ADR-0100 dec. 2 amendment).
_Avoid_: a tick-level scrubber (eight ticks of a FRAME are eight ticks of the same picture);
sharing the page transport's speed field; calling its cursor bare "playhead"; a full-width
band under the inspector (that was the shape before ADR-0100, and the height came out of the
timeline); sizing the box off ANY term that moves — `content_height()` (resizes per click and per
fold) or the row's whole budget (resizes per window, and eats the focus column's width on a
tall one).

**Film strip** (BESIDE the player since 2026-08-20, [ADR-0100](../adr/0100-the-inspector-row-has-one-right-column-bounded-by-declared-content-width.md)
dec. 1, 2026-08-19; ADR-0089's vertical-column amendment):
One [sequence thumbnail](16-effect-studio-authoring-tool.md) per **LIFE ROW** — the particle's life, not the
opcode list — in a single vertical column to the right of the square canvas, with the
[colour ribbon](16-effect-studio-authoring-tool.md) running beside it. A zero-dwell cell (LOOP, SET_OFFSET)
holds no age and gets **no row**; a looped cell gets one row **per pass** (105 emitters,
4.0%, whose later passes were previously unauthorable); a parked `duration = 0` terminal
frame is **one row of many columns** (726 emitters, 27.8%). It is SHORTER than the
by-opcode strip it replaces — median 9 rows against 12 trace cells, max 75 against 98 — and
bounded by `life_n`, since every row consumes at least one life frame. Colour off falls back
to one row per trace cell. It is a **ROW OF TIME
POSITIONS** ([ADR-0102](../adr/0102-the-animation-screen-composes-the-frameset-it-shows-rather-than-linking-to-it.md)
dec. 9, 2026-08-20): the first cell is the animation at t=0, the last is the animation at its
end, and an interior cell is the END of that opcode's duration. That is a **fencepost** fix —
N stretches of time have N+1 boundaries, and the strip used to expose only the interior ones,
so neither the start nor the end could be parked on. Both spare slots already existed in the
data (all 2,428 corpus animations open with a `SET_OFFSET`, and 2,377 close with a `LOOP`).
Fed from the canvas's
already-computed trace, bounds and display texture, so a cell here and an opcode row in the
inspector cannot disagree. Since 2026-08-20 it is also the **second entry point for colour**
(ADR-0089's colour-move amendment): **right-click** a cell to author a keyframe at the life
frame it lands on (`SequenceLifeMap`, which projects the same trace). Left-click still parks,
deliberately — an author parks constantly while browsing. The projection is a **partial
function**: 324 of 2622 colour-enabled corpus emitters (12.4%) die mid-animation, so their
tail opcodes never play; those cells are **dimmed** and say why rather than silently doing
nothing — and since the vertical column those dimmed cells follow the life rows at the
**bottom** rather than sitting in opcode order. `life_frames` resolves a looped opcode to its
**first** occurrence; `life_rows` gives every pass its own row, which is the projection the
column is built from. It **NO LONGER WRAPS** — it was an `HFlowContainer` of `strip_rows`
(default 2) rows while it was a wide, short band under the player, and a column beside a
ribbon cannot wrap at all: a second column of thumbnails would have no ribbon next to it. A click
**parks** (never navigates); the parked cell's row is scrolled into view on every bind and
selection change. On an `emitter` or `span` [column subject](16-effect-studio-authoring-tool.md) it is the only
opcode picker on the screen — the inspector there renders physics, not opcodes.
_Avoid_: reading a cell as "the state after this opcode runs" (that was the model until
2026-08-20, and the reversal is recorded rather than quiet — the PURPOSE changed, from a state
readout to a clock position, which is why "inventing a sprite in cell 0 would make it lie" no
longer holds); treating the first or last cell as a special case in code (`pos_tick` is one
expression that lands both, and the 51 animations with no trailing `LOOP` besides); confusing
`pos_tick` with `tick_start`/`ticks`, which are still the DWELL and still reconcile to
`ParticleAnimator`'s bake; confusing it with the pre-`de36a115d` full-width band (that
was the only view of the
sequence and took the whole row); letting it or its scrollbar hide when it fits (the panel's
chrome is MEASURED, so anything that disappears re-sizes the canvas square); fitting the row
count to the sequence (same chrome swing, one browse later); forgetting it costs the player
74px of height at two rows, and 36 more per row after that.

**Sequence thumbnail** ([ADR-0103](../adr/0103-the-sequence-thumbnail-is-the-real-render-minus-position-and-camera.md)):
One TIME POSITION's picture in the [film strip](16-effect-studio-authoring-tool.md), and — the invariant that
decides every question about it — **the real render minus world position and camera**.
Blend mode,
[over-life](16-effect-studio-authoring-tool.md) colour, animation offset, UV and quad are the actual thing the
game draws; only placement in the world and the camera looking at it are dropped. It shares
`SequenceSpritePainter` with the [sequence player](16-effect-studio-authoring-tool.md), so the two satisfy the
invariant together or not at all, and anything the particle renderer does that the painter
cannot reproduce is a **defect against this term**, not a feature request.
Its **backdrop is a viewing condition, not data** — a [static-var home](34-debug-tuning.md)
tunable (ADR-0068 R1–R8), because no one backdrop serves both blend families (black gives additive its true
colour and hides subtractive; grey reveals subtractive and clips bright additive).
Its row's TITLE names the **OPCODE** and its picture is a **time position** — two different
facts on purpose (author, 2026-08-20), so the first row reads `0: SET_OFFSET x=0 y=0` beside
a picture of the animation's first frame and the **tooltip names the tick** it parks at. A row
IS an opcode: it selects one, edits one, and folds under `seq:anim:op`.
_Avoid_: treating the tint and the blend as separable features (colour drives these effects
to zero, and un-blended that reads as a black silhouette at the instant the particle
vanishes); calling a thumbnail a "preview" as though approximation were licensed; multiplying
in the [representative sprite colour](16-effect-studio-authoring-tool.md) (the ribbon needs it because it has no
sprite — a thumbnail has the real texels and would square them).

**Ribbon cut**:
The [over-life](16-effect-studio-authoring-tool.md) colour of one particle life, divided at opcode boundaries so
each [sequence thumbnail](16-effect-studio-authoring-tool.md) owns the ages its own opcode occupies —
`[a_k, a_k + n_k)` where `n_k` is that opcode's baked display length. The cell draws its
piece on a loop, which is **one expression and no branch**: `n_k == 1` makes the loop a
still by arithmetic. That is the common case, not the fallback — `duration=2` is three
quarters of every opcode in the corpus, so **the film strip already is the particle-age axis
at 1:1** for 83.6% of cells and the colour ramp lives *between* cells (median 9/255 per step)
rather than inside them (median 0.0). **Every row owns a piece** — a row that occupies no time
(offset opcodes, and the `LOOP`) stands for the boundary it sits on and gets `cut_ticks == 1`,
a still by the same arithmetic. Until 2026-08-20 those rows got no piece at all, which meant
the first and last thumbnail of every corpus strip were untinted BY CONSTRUCTION; closing that
was the supporting evidence for the [film strip](16-effect-studio-authoring-tool.md)'s fencepost amendment, and
4,805 spare end cells across the corpus gained a real colour with it. The window is pinned to
the position by `cut_start + cut_ticks - 1 == pos_tick`.
_Avoid_: proposing a separate age-axis surface for a strip that already is one; animating
every cell (399 of 30,928 cells have a hold long enough to show anything); letting the loops
run while the [sequence player](16-effect-studio-authoring-tool.md) does, where they compete with the one
[playhead](16-effect-studio-authoring-tool.md) the author is tracking.

**Colour dead zone** ([ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
colour-keyframe amendment, 2026-08-19):
The particle ages **past `life_n`** — the emitter's max authored lifetime, or its animation's
display length when lifetime is the −1 sentinel. **`EmitterLifeWindow` is the one derivation**
of it (2026-08-20); it was inline in `EffectScoreModel` while the inspector was the only
surface with an over-life axis, and a second copy would now decide the same emitter's axis
twice — invisibly, since both candidate windows are plausible integers. `life_n` is the UPPER bound of what the
particle renderer ever reads, so colour-curve samples beyond it are inert.
**Only the START pair defines it** (`lifetime_min_start` / `lifetime_max_start`) unless the
emitter carries a **lifetime curve** — 9 of 3227 corpus emitters do. `interpolate_range`
opens `if curve == null: return _srange(min_start, max_start)`, and the ROM's
`emitter_control_routine` (`0x801A634C`) branches the same way on the packed curve nibble, so
`lifetime_*_end` is inert data for 99.7% of emitters. The rule read all four until
2026-08-20 and drew up to **32 frames of phantom life on 309 colour emitters** (median 6);
`tools/census_life_window.gd` is the instrument, and ADR-0089's same-day correction block
argues it. They still carry
**keyframes**: the import is a Douglas-Peucker fit over all 160 curve samples and DP always
keeps the terminal point, so *every* colour emitter in the corpus has one at frame 159, and
some are almost all dead zone (E241 emitter 2: a 2-frame window, 23 of 24 keyframes beyond
it). The [keyframe track](16-effect-studio-authoring-tool.md) therefore takes the [colour ribbon](16-effect-studio-authoring-tool.md)'s
window as its domain — dead-zone handles are neither drawn nor hit — and states the count in
prose instead. Median live window across 2621 colour emitters is **16** frames (p90 32, p95 40).
**The fit's BUDGET is split at the boundary** (2026-08-21): `MAX_KEYFRAMES` is 24 *per region*,
not 24 shared. One global budget was spent wherever the curve deviates most, and for a ROM
curve that is very often the dead zone — `_douglas_peucker` also pops its segment stack from
the back, descending RIGHT-first, so it exhausts the tail before returning to the head. The
live window STARVED: 291 of the 605 colour-off emitters (**48.1%**) showed one keyframe or
none inside the life, which is the whole of what an author sees, and the worst-case residual
*inside* the life — the only error that renders — was **0.774**. Now 58 (9.6%), and those are
genuinely flat across their life. Both regions are still fitted and share the boundary sample,
so this is not the truncation the _Avoid_ below rules out: live residual matches a truncating
fit exactly (max 0.133, p90 0.0019) and the dead zone matches the old fit exactly (max 0.9725),
for a median 10 keyframes against 9. `tools/census_colour_fit_window.gd` is the instrument and
`tools/census_colour_enable_keyframes.gd` measures what the author actually sees.
_Avoid_: mapping a dead-zone frame through `x_of_frame` (it does not clamp and the track does
not clip, so the handle paints outside the control — the 2026-08-19 report); widening the
window to include them (every emitter has one at 159, so that is "no trim"); re-fitting the
import to the live window (it compiles the dead samples flat, rewriting bytes to fix a
drawing bug — split the BUDGET instead, which fits both regions and drops nothing);
concluding from that _Avoid_ that the dead zone may keep starving the live window — it is an
objection to truncating the fit, not to bounding what each region may spend; reading `lifetime_*_end` without first checking for a lifetime curve; and
asserting `ribbon.colors().size() == life_n` — the ribbon floors a trimmed window at **2**
bands and 154 colour emitters have a 1-frame life.

**Colour provenance**:
Which [emitter](16-effect-studio-authoring-tool.md)'s colour curves a [sequence thumbnail](16-effect-studio-authoring-tool.md) is
tinted by, and the named rung the answer came from — `origin` (drilled, the emitter is on the
nav trail), `only` (browsed, one applicable emitter), `first` (browsed, several — the first,
**plus the count of others**), `none` (no colour-enabled emitter, so no tint). A strip's
target is a [sequence](15-effect-orchestration.md) seen through a [lens](16-effect-studio-authoring-tool.md), never an
emitter, so the tint is *conditional on how you arrived*. Naming the rung is what makes
"first applicable" honest rather than a lie: 15.9% of browsable targets have two or more
applicable emitters whose curves genuinely disagree, by a median of 144/255. Modelled on the
[pair anchor](16-effect-studio-authoring-tool.md)'s ladder, which states its `source` the same way.
_Avoid_: picking an emitter silently; refusing to tint whenever the cohort is ambiguous
(that blanks the feature on 23.5% of targets to guard a case the label already covers);
recovering the emitter from the target's `ref` — the group is a lens, not an emitter index.

**Stacked block**: the ADR-0102 frameset block, sitting UNDER the
[sequence player](16-effect-studio-authoring-tool.md) inside the player's own column rather than as a middle
column of its own (ADR-0100 dec. 1, 2026-08-19). Its height is the column's slack once the
player's constant box is paid (`focus_stack_height`) — so the player never shrinks to make
room, and a row too short to hold both drops the block until the window grows. It follows the
[column subject](16-effect-studio-authoring-tool.md), not the open target, so it appears on `emitter` and `span`
screens too.
The column is sized for whichever occupant wants MORE width — the player's 276 or the block's
declared 710 — clamped so the inspector never drops below what it declares. The player's box
stays a constant square inside the surplus.
_Avoid_: feeding it the target's `ref` (on an emitter that `index` is an emitter index, and
the block would name and EDIT a frameset from an unrelated sequence); shrinking the player to
fit it, or letting the canvas expand to the column (both make the box a function of the open
target); expecting it on a ~268px row — the box fills the row there and no chrome saving
changes that.

**Column subject** ([ADR-0100](../adr/0100-the-inspector-row-has-one-right-column-bounded-by-declared-content-width.md)
dec. 1, amended):
The sequence the inspector row's right-hand column is **bound to**, and the one thing that
decides whether the [sequence player](16-effect-studio-authoring-tool.md) opens at all. Three [inspection
targets](16-effect-studio-authoring-tool.md) name a sequence, by two routes: an `animation` target carries the
index and the [lens](16-effect-studio-authoring-tool.md) in its own `ref` (and wins there, because the lens is
part of its identity); an `emitter` — or the particle `span` that fires one — names them
*through* the emitter's `anim_index`/`anim_param`. So the emitter screen shows **the
particle this emitter spawns, playing, tinted by its own curves** ([colour
provenance](16-effect-studio-authoring-tool.md) rung `origin` by construction) instead of 512px of empty row.
The address is **resolved once and stored**, never re-read from the open target: an emitter
`ref`'s `index` is not an animation index, and `animations[emitter_index]` decodes a real
sequence and draws real sprites — a wrong picture indistinguishable from a right one.
_Avoid_: keying anything on `_nav.back()`'s `ref` now that two of the three kinds put an
emitter index there; treating the column's emptiness as a height problem (the pane is tall
because 2257px of content sits in a 268px row — a different, unrelated, un-taken decision);
growing a [film strip](16-effect-studio-authoring-tool.md) on the emitter screen (its rows are the emitter's own
physics, which is what the author is there to edit).

**Frameset group** / **lens** (`anim_param`):
The emitter byte that selects which **group** of framesets its sequence's FRAME opcodes
index into. A FRAME opcode stores a frameset index **relative to the group**, so the
absolute index is `opcode.frameset + EffectData.frameset_group_offset(anim_param)` — meaning
**the same opcode shows a different sprite depending on which emitter plays it**. The group
therefore is not a place you navigate to (there is no group target kind) but a **lens** the
sequence is read through, and it rides an `animation` [inspection
target](16-effect-studio-authoring-tool.md)'s `ref` as part of its identity
([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)
amendment 2026-08-18). Rare in practice — of 2201 (effect, sequence) pairs across all 481
effects, exactly **2** are played at more than one group (E241 anim 0, E408 anim 4), and
383 of 401 effects have a single group — but silently *wrong* when ignored, since the naive
resolution lands on a real frameset, the wrong one.
_Avoid_: reading the group back off the nav stack (makes a link's destination depend on how
you arrived); a fifth copy of the offset arithmetic — `EffectData.frameset_group_offset` is
the one derivation, and it already has four former callers routed through it.

**Follow** (an `edit` row's drill-in):
A `link` riding an **editable** field rather than replacing it: `edit` fields may carry
`follow: {label, target, disabled?}`, which the inspector renders as a flat link button
beside the editor in the same grid cell. The reference fields the drill-down chain needs
(an emitter's Animation set, a FRAME opcode's Frameset) are
[ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
tier-1 authoring cells, so navigation had to be **additive**. The button registers on the
same `_link_buttons` seam and fires the same navigate callback as a `shape: "link"` row — it
*is* a [link](16-effect-studio-authoring-tool.md), differing only in that it shares a cell.
A FRAME opcode's Frameset follow resolves through
`SequenceProjector.absolute_frameset`, which the [unified animation
screen](16-effect-studio-authoring-tool.md) shares — one derivation, so the block cannot edit a different
frameset from the one the button beside it opens.
_Avoid_: regressing an edit row to a link to make it followable; a `disabled` follow that
still renders a pressable button (a dangling `u8` reference shows no button and the row wears
the [relevance](16-effect-studio-authoring-tool.md) `dead` marker instead).

**Path bar** ([ADR-0102](../adr/0102-the-animation-screen-composes-the-frameset-it-shows-rather-than-linking-to-it.md)):
The full-width strip above the [keyframe inspector](16-effect-studio-authoring-tool.md) and the right-hand
canvas column, rendering the whole nav stack as `E019 › emitter 0 › ▸ frame 0/0`. It is the
nav stack's **presentation**, not a second model of it — the stack, its drill/truncate rules
and its 17-assertion guard are unchanged. The trail used to be header rows inside the
inspector's 6-column grid, where it was indistinguishable from the target's own label/value
pairs and it **wrapped**. Three things it shows that those rows did not: the **current**
target, marked `▸` and inert (a trail stopping at the parent does not read as "where am I"
once there is no title under it); the **effect** as a dim, non-navigable root (there is no
effect target kind); and `‹`, the visible half of [step back](16-effect-studio-authoring-tool.md). Constant
chrome — up at depth 1 and in the [deselected](16-effect-studio-authoring-tool.md) state, because chrome that
appears and vanishes re-flows the inspector, the column, the frames bar and the channel
scroll on the most common gesture there is. Past depth 4 the middle folds into a `…` menu
that still reaches every elided crumb.
_Avoid_: a hard `BAR_H` as the reserved row (a Container cannot shrink below its combined
minimum — the bar measures 35 against a 26 floor at the dev theme, so `bar_height()` is what
`_relayout` reserves); a browser-style **forward** stack (a second model of "where am I",
which is the confusion the bar exists to remove — the dimmed *ghost tail* of a truncated
path is the cheaper answer if the round trip ever proves real).

**Step back** (`‹` / **Alt+Left**):
Walk **one** level up the nav stack — the same thing clicking the second-to-last
[path bar](16-effect-studio-authoring-tool.md) crumb does. Inert at the root: stepping off it would mean
deselecting, and that stays [Esc](16-effect-studio-authoring-tool.md)'s. Recognized by a pure static
`_is_back_shortcut`, beside `_is_undo_shortcut` / `_is_escape`, so it is guarded without a
scene.
_Avoid_: overloading Esc with it (Esc means "let go of everything" — two-stage: drop the
focused field, then deselect — which is a different gesture from walking up one level of the
same inspection, and folding them together makes one key with a hidden mode).

**Unified animation screen** ([ADR-0102](../adr/0102-the-animation-screen-composes-the-frameset-it-shows-rather-than-linking-to-it.md)):
The **focus panel** — a column of its own between the film strip and the sequence player,
holding the [frameset](16-effect-studio-authoring-tool.md) the **selected opcode** shows plus one fold per member
frame, the first of them OPEN — so `opcode → frameset → frame` is authorable on one screen
instead of three. **Composed, not projected**: it calls `FramesetProjector.sections()` and
grafts the rows, which is safe because a frame row's `field_ref` is absolute
(`{channel:"frameset", frameset_index, frame_index, field}`) and `apply_edit` routes on the
channel alone, never on the open target. It follows `SequenceCanvas.selection_changed` with a
`show_target` on its OWN inspector, never a full render — a click on the film strip already
[parks](16-effect-studio-authoring-tool.md) rather than navigating, and a render would take the folds, the
scroll and (for an edit) the ScrubField being dragged. The **UV rows are read-only** here:
a rect is a shared [sheet region](16-effect-studio-authoring-tool.md) and the scope control that states a move's
blast radius cannot be on screen beside the player, so the block states the fan-out and
links to the frame's own screen.
The frames LEAD the block and the frameset's own rows follow: the inspector row is
~268px against 2000+px of content, so leading with Sheet/Export/Import spent the whole
visible height on chrome and the screen arrived showing a header.
**It is a COLUMN because a section moved the strip.** As the first section of the strip's own
list its height was the strip's, and a two-member frameset is one fold taller than a
one-member one — every thumbnail below it slid **39px** per click (E019 sequence 0). In its
own container: **0.0px**. Its width is the row's SLACK
(`EffectStudioPage.focus_column_width`), claimed only after the strip's declared
`content_width()` and the player's chrome floor, because a Container cannot shrink below its
minimum and width taken from either overflows onto this column instead; under 120px of slack
the column is dropped, which is why `_focus_wanted` ("the target has a block") is a different
question from `_focus_panel.visible` ("there is room for it"). Its inspector runs with
`show_own_chrome = false`, `allow_horizontal_scroll = true` and `NAME_COL_WIDTH_TIGHT`
(the house 240 puts every value off the right edge of a narrow column), and the column is
capped at what the block DECLARES so a wide window does not stretch a name/value grid across
a third of the screen — the surplus goes back to the strip.
**The strip pays for the block's width, so the strip is kept narrow**: the same tight name
column (its longest name is "Depth mode"), and no prose in a value cell — "N ticks" not
"N ticks before the terminator", "none" not "none — restarts the sequence from the
beginning", with the sentences moved to tooltips. Those three cuts took the sequence view's
declared `content_width()` from **677 to 432**, every pixel of which the focus column gets.
_Avoid_: a fold per opcode (measured 1867 ms against the block's 400-428 and a 343 ms
baseline; the cost is ~4 ms per fold **header**, before a row exists); a fourth projector
restating a frame's fields; a block back in the strip's section list (whatever it is called —
`EffectStudioSequenceViewportTest` counts non-opcode sections rather than naming it); a panel
that VANISHES on a spriteless opcode (it would hand its width back and re-flow the strip — the
movement the column exists to stop; a spriteless opcode gets a TITLE and no rows instead);
**every** frame fold shut (13,854 corpus framesets hold ONE frame — all-shut means
the block shows no frame at all); a `[📌 pin]` (withdrawn on first use — an `action` row costs
a label column and a full row at the top of the block, for a case that never came up).

**Deselected (empty inspection)**:
The legal state where the [keyframe inspector](16-effect-studio-authoring-tool.md) renders **no**
[inspection target](16-effect-studio-authoring-tool.md) at all — the nav stack is empty, the inspector shows its
placeholder (its content collapses to zero height, so the timeline lanes reclaim the space),
and no [span](16-effect-studio-authoring-tool.md) is highlighted. The [path bar](16-effect-studio-authoring-tool.md) stays up,
showing the effect id alone — it is constant chrome, so nothing below it re-flows. Reached by
pressing **Esc**, the sole deselect gesture ([step back](16-effect-studio-authoring-tool.md) is a different
gesture and never reaches this state) (a second click on the selected span does **not** toggle it off; clicking empty
timeline space seeks the playhead, it does not deselect). Esc backs out exactly one step: if
an inspector value cell holds focus, the first Esc drops that focus (cancels the field) and
the *next* Esc deselects. It is not an error state — `_render_current` early-returns on an
empty nav, so the deselect path clears the inspector **explicitly** rather than through a
render.
_Avoid_: calling it a *null inspection target* (there is no `{kind, ref}` — it is the
**absence** of one, distinct from an unbuilt-kind [projector](16-effect-studio-authoring-tool.md) **seam** that
has a target but renders nothing); reaching it by clicking empty timeline space (that seeks).

**Projector registry** ([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)):
The `kind → projector` map (`InspectorProjectorRegistry`) the model dispatches an
[inspection target](16-effect-studio-authoring-tool.md) through — each projector owning `header()` and
`sections()`. Generalizes [ADR-0071](../adr/0071-a-studio-lane-event-projects-through-a-per-archetype-projector-that-separates-owned-from-referenced.md)'s
per-archetype span dispatch one level up (a `span` target's projector still routes to the
archetype projectors below it). Unbuilt kinds are declared **seams** (recognized, projector
`null` → inert): adding one is a registration, not an inspector change.
_Avoid_: a god-`match` on kind in the model or view (the shape the registry exists to
remove); erroring on an unbuilt kind (a seam renders nothing, it does not crash).

**Link field** ([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)):
A first-class field / header shape — `{name, shape:"link", label, target}` — that renders a
clickable cell following its reference to another [inspection target](16-effect-studio-authoring-tool.md). It
promotes ADR-0071's "a span *references* an emitter" from a concept to a followable handle:
the Config child-on-death / mid-life rows and the span Event's "Emitter" row are links, so
the dead-end `"Child on death: 5"` integer becomes a jump into that emitter's bare view.
_Avoid_: rendering a reference as inert text (the defect this fixes); a `link` breaking the
`const` 2-column layout (it shares it — name │ button).

**Incoming edge / provenance** ([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)):
The **inverse** of a [link](16-effect-studio-authoring-tool.md) — the set of edges that spawn/reference an
emitter, enumerated as clickable reverse-nav rows in the bare-emitter header: keyframe refs
(→ a span target), on-death / mid-life parents (→ an emitter target, by inverting the
child adjacency). Fixes the misleading "shared by N events" (which counted only keyframes,
so a child-only emitter read "shared by 0"). **Callback edges are not statically derivable**
— `spawn_child_from_callback` takes its index from callback logic at runtime and there is no
static callback→emitter field — so an emitter with no static edge shows a flagged, NON-link
note ("may spawn via callback at runtime"), never a fabricated link.
_Avoid_: counting only keyframe references as "shared by N"; inventing a reverse link for a
callback edge that isn't statically knowable.

**Spawn graph** ([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)):
The real shape of `EffectData.emitters[]` — emitters reached by edges of several kinds, of
which a keyframe is only one (also on-death, mid-life, callback). The
[emitter browser](16-effect-studio-authoring-tool.md) (an all-emitters list in the Studio) is the exhaustive
entry point that guarantees **reachability**: every emitter is inspectable regardless of how
(or whether) it is spawned — orphan and callback-only emitters included.
_Avoid_: treating the timeline as the only way into the emitters (it reaches only the
keyframe edge); calling a runtime child *particle* the unreachable thing — the unreachable
object is the child **emitter config**.

**Child-spawn suppression** ([ADR-0075](../adr/0075-the-studio-inspectors-first-interactive-control-is-per-edge-child-spawn-suppression.md)):
The [keyframe inspector](16-effect-studio-authoring-tool.md)'s first **interactive** control — a checkbox on each of
the [emitter view](16-effect-studio-authoring-tool.md)'s two Config child rows ("Child on death" / "Child mid-life")
that turns off *that parent's spawn of that child*. It is **per-edge**, keyed by
**(parent emitter index, edge kind)** — NOT the global-by-index render hide (`disabled_emitters`,
the F3 panel's mechanism), which is a separate, orthogonal thing. Because it changes the
**simulation** (the child and its descendants never spawn), the frozen preview is re-derived by a
deterministic **re-seek** ([reset + re-pump](16-effect-studio-authoring-tool.md), ADR-0070 seeded RNG), NOT an
in-place re-filter — and skipping the spawn's RNG draws **ripples** into other emitters' clouds
(a counterfactual "what if P never spawned this?", accepted, not a hold-all-else-fixed hide). The
checkbox appears **only on a live edge** (`child_index ≥ 0` AND the authored
`is_child_death/midlife_enabled()` flag on), defaults **checked**, and is **off-only** (it never
enables an authored-off edge). Ephemeral: in-memory, cleared on effect change, keyed by emitter.
_Avoid_: conflating it with the render-filter hide (different key, different mechanism, no
re-seek); expecting it to hold other emitters fixed (it ripples); showing the checkbox on a
"none" or authored-off row (nothing spawns to suppress); calling it a *particle* toggle — it
suppresses the [spawn graph](16-effect-studio-authoring-tool.md) **edge**.

#### Authoring model (write side)

The write-side extension of the [Effect Studio](16-effect-studio-authoring-tool.md) cluster — the
ubiquitous language for *editing* an effect, not just projecting it. It reuses
the read-side vocabulary above ([lane event](16-effect-studio-authoring-tool.md),
[span/tween/trigger](16-effect-studio-authoring-tool.md), [Blend/Gradient](16-effect-studio-authoring-tool.md),
[emitter view](16-effect-studio-authoring-tool.md), [link](16-effect-studio-authoring-tool.md)) and adds only what
mutation needs. The spine, decided in
[#248](https://github.com/timbermania/fft-monorepo/issues/248): **"edit a lane
event; its contents dispatch per channel archetype"** — the write-side mirror of
the read-side [projector registry](16-effect-studio-authoring-tool.md). All five channels are the
**same shape** — an ordered list of lane events + a [live window](16-effect-studio-authoring-tool.md)
— with **no structural special cases**. Camera *looks* like an exception (its bytes
pack several sub-channels into one masked keyframe) but is not: the author edits
independent [sub-channel lanes](16-effect-studio-authoring-tool.md) of ordinary lane events, and
`channel_mask` is a [lowering](16-effect-studio-authoring-tool.md) artifact the author never sees
([ADR-0086](../adr/0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md);
see [sub-channel lane](16-effect-studio-authoring-tool.md) below).

**Lane-event-atomic authoring**:
The unit the author creates / edits / deletes is the [lane
event](16-effect-studio-authoring-tool.md) itself (a [span](16-effect-studio-authoring-tool.md), [tween](16-effect-studio-authoring-tool.md),
or [trigger](16-effect-studio-authoring-tool.md)) — the thing actually stored in the channel's
slot array — **not** a higher-level derived-interval object. The timeline
*renders* each lane event as its filled tile (the [fully-tiled
lane](16-effect-studio-authoring-tool.md) law), and clicking that tile **selects the lane event**;
there is no separate "span object" you drag independently of the event it draws.
One edit = one slot write, isomorphic to the bytes.
_Avoid_: resurrecting **"keyframe"** as the authoring unit (the read side retired
it as misleading — [lane event](16-effect-studio-authoring-tool.md) is the genus); modeling a
draggable "span" distinct from the [span](16-effect-studio-authoring-tool.md) lane event it renders
(the two are the same object — editing the event redraws the tile).

**Channel archetype** (the deep module):
The single per-channel module owning **everything about how one channel works** —
its read [projection](16-effect-studio-authoring-tool.md), its lane-event **contents schema**, its
[variants](16-effect-studio-authoring-tool.md), its [lowering](16-effect-studio-authoring-tool.md) to bytes, and its
[Faithful constraint bundle](16-effect-studio-authoring-tool.md). There are **five** channel
archetypes (particle, screen, palette, camera, sound) — distinct from the
**three** [lane-event archetypes](16-effect-studio-authoring-tool.md) (span/tween/trigger, which
classify *how a lane event is drawn*). Screen, palette, and camera all *draw* as
[tweens](16-effect-studio-authoring-tool.md) yet are three separate channel archetypes because their
**contents** differ (screen backdrop Blend/Gradient vs unit-target palette tint vs
angle/position/zoom). Adding a channel type = adding one module; the read
[projector](16-effect-studio-authoring-tool.md) and the write editor are two views onto it (not two
registries that must agree).
_Avoid_: a per-channel module split across a read file and a write file that must
be kept in sync (the drift the single deep module exists to prevent); conflating
the 3 drawing archetypes with the 5 contents archetypes.

**Authoring time (absolute intervals)** / **Lowering**:
The author manipulates every lane event on **one absolute frame axis** (the
[score](16-effect-studio-authoring-tool.md)'s axis) — an absolute `[start, end)` — regardless of how
the bytes encode time. The per-channel **lowering** step (owned by the encoder,
the E###.BIN writer) translates that back to each channel's native encoding:
[span](16-effect-studio-authoring-tool.md) → implicit gap-to-next cumulative point, [tween] →
explicit `duration` (`×8` units for screen/palette/sound), camera → absolute
`end_frame`, [trigger] → the next-fire gate. Because authoring is absolute,
**moving a lane event is always local** — the ripple that "resizing a duration"
would cause on the length-encoded channels is the encoder's problem, never a
surprise the author feels.
_Avoid_: exposing three different time models to the author (cumulative /
duration / endpoint — that heterogeneity is a [lowering](16-effect-studio-authoring-tool.md) detail);
hiding native granularity (it is surfaced as a [Faithful](16-effect-studio-authoring-tool.md)
constraint, below).

**Variant** (keyframe-variant capability):
A lane event's editable **contents schema may be discriminated by a `mode` field
the event itself owns** — selecting the mode reshapes the rest of the field set.
This generalizes the established [Blend/Gradient](16-effect-studio-authoring-tool.md) pair (the screen
tween's two variants) into a spine capability every [channel
archetype](16-effect-studio-authoring-tool.md) may use: the archetype **declares** its variants and
each variant's field set; the generic editor renders "a mode selector that
reshapes the fields below it" uniformly. A variant reshapes *which fields you
edit*; the event still occupies its one tile in its one lane. Camera's
`channel_mask` is **not** a variant (nor any authored field) — it is a
[lowering](16-effect-studio-authoring-tool.md) artifact, born when the compiler packs coincident
[sub-channel](16-effect-studio-authoring-tool.md) events into one keyframe, never a control the author
touches. The **colour value** inside a
variant's fields (flat RGB vs the [ADR-0067](../adr/0067-color-modes-are-one-model.md)
recipe-layer stack) is **deferred to
[#252](https://github.com/timbermania/fft-monorepo/issues/252)** — the spine only
guarantees a slot exists for it.
_Avoid_: enumerating any archetype's modes in the spine (the archetype declares
them); a universal "sub-type" concept at the channel level (only the schema is
discriminated, and only where an archetype opts in).

**Sub-channel lane** / **Coalescing lowering** (camera, [ADR-0086](../adr/0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md)):
Camera has a **two-model** split — the sharpest instance of
[authoring-time vs lowering](16-effect-studio-authoring-tool.md). Its **authoring model** is three
**independent sub-channel lanes** — angle, position, zoom — each an ordinary
[fully-tiled lane](16-effect-studio-authoring-tool.md) of [lane events](16-effect-studio-authoring-tool.md) the author edits
in place. Camera is thus [lane-event-atomic](16-effect-studio-authoring-tool.md) like the other four; one
event = one tile. Its **storage model** packs these into a flat keyframe array where
one keyframe carries a `channel_mask` bitfield + one shared command word (source /
interp / end / param / flags) that drives *every* sub-channel the mask selects. That
packing is a **lowering** artifact, **never authored** — `channel_mask` is emitted by
the encoder, not set by a person. The sub-channel lanes are also the runtime's own
grain: `CameraSubsystem` searches each of angle/position/zoom *separately*
(`_find_active_keyframe`, once per `CHANNEL_ANGLE/POSITION/ZOOM`), so the authoring
lanes map 1:1 onto the engine.
- **Lowering is a coalescing compiler.** After authoring, it folds sub-channel events
  that **coincide and agree** (same frame + source + interp + param + flags) into one
  masked keyframe, and **splits** them when they disagree. Parsing does the inverse
  (one masked keyframe → one event per set bit).
- **Faithful is semantic, not byte-exact.** Editing camera **recompiles the whole
  camera section** and patches that entire region in (no surgical per-field byte diff —
  the "bigger piece"). Faithful still validates [capacity](16-effect-studio-authoring-tool.md) and
  quantization on the compiled keyframes; it does **not** promise byte-identical
  round-trip (irregular ROM packings need not survive untouched). Byte-exact partial
  patching was **rejected** here — it would force provenance tracking for no
  author-visible gain.
- **The orphan cannot exist.** There is no membership to clear and no `channel_mask==0`
  to author — a hold on a sub-channel is just *no event there*. This dissolves (does not
  manage) the "unchecking Channels hides the event" bug; no keyframe-level inspection
  target is needed.
_Avoid_: exposing `channel_mask` as an editable field / [variant](16-effect-studio-authoring-tool.md) /
membership checkbox (the original bug — a content gesture that changed which lanes an
event lived in); byte-exact partial patching of camera (a camera edit rewrites the whole
section); collapsing the three sub-channel lanes into one (they are both the authoring
grain and the runtime's search structure).

**Compiled lane** / **Storage view** (camera, [ADR-0086](../adr/0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md)):
A strictly **read-only** observability lane (`kind:"camera_compiled"`, one per phase
with a camera table) that shows the [storage model](16-effect-studio-authoring-tool.md)
*directly* — **one span per packed keyframe**, appended after that phase's three
sub-channel lanes. It exists because [coalescing lowering](16-effect-studio-authoring-tool.md)
is otherwise invisible: an author edits sub-channel events but never *sees* the masked
keyframes those fold into, so a split feels like the tool "doing something behind the
scenes." The compiled lane makes that concrete — edit a sub-channel Source so two
sub-channels disagree and the coalesced keyframe **splits into two**. The lane is a
**faithful mirror of the packed store**: it shows exactly the keyframes the store holds,
so it splits the moment an edit recompiles the store, and shows a merge whenever the store
re-coalesces. It shows one item per **real** keyframe (`channel_mask != 0` — the same
"is-this-real" test [`CameraLowering.parse`](16-effect-studio-authoring-tool.md) uses;
the mask==0 empty SoA slots the table pads with drop out).
- **Keyframes are POINT MARKERS, not intervals.** Each is a small diamond drawn AT its
  `end_frame` — a keyframe is "a target reached at frame N," and the storage stores no
  duration. Drawing intervals would *lie* whenever tracks interleave: a position move over
  `[0,40)` would render `[30,40)` merely because an angle keyframe was packed before it in
  the flat array (the compiled lane can't recover each keyframe's per-track start, only its
  end). The real per-sub-channel windows live on the angle/position/zoom lanes; the storage
  view asserts only the honest fact — a keyframe lands here. So there is **no Length row**
  in its inspector.
- **Coincident split siblings both show, and both stay clickable.** A split produces two
  keyframes at the **same** `end_frame` (angle@10 + position@10). As points they land on the
  same frame, so the view **fans them** apart by a few px around the true frame x — each
  keeps its own hit box (`MARKER_FAN` in `EffectScoreTimeline`) so you can select either.
  All compiled markers share one slate hue, so a small mask tag (a/p/z), not colour, tells
  the sub-channels apart.

Its inspector (`CameraCompiledProjector`) emits only `const` rows — Index, End frame,
Channels (mask → sub-channel names), Source, Interp, Param, Flags, Command word (raw hex) —
so the packed truth is legible but **editing it is impossible by construction** (no editable
field / `field_ref` is ever emitted; the orphan bug the lowering dissolved stays dead).
Being display-only, it carries no [Solo/Mute](16-effect-studio-authoring-tool.md) (like the sub-channel camera
lanes). A related read-only companion on the *editable* side: the sub-channel Event
inspector shows a `const` **Length** (`authored_end − authored_start`, a real interval on
that track) — `end_frame` stays the single editable length knob so there is no second,
conflicting way to say the same thing.
_Avoid_: making any compiled-lane surface editable (inverting authoring to the packed
level was **rejected** — it would resurrect the `channel_mask` orphan; a new ADR is
required to revisit); a Length that edits (it derives from the extent, not vice-versa).

**Boundary drag** (camera edge-resize, [ADR-0086](../adr/0086-camera-authoring-is-sub-channel-lanes-lowered-to-masked-keyframes.md)):
Direct-manipulation resize of a camera [tween](16-effect-studio-authoring-tool.md) by dragging the shared
boundary between it and its lane-neighbour on the [score](16-effect-studio-authoring-tool.md) timeline — the
second UI affordance for the edit the `end_frame` int cell already does (the
[Length](16-effect-studio-authoring-tool.md) row stays read-only). Because a camera span's start
is **derived** from the previous event's `end_frame` (the [fully-tiled
lane](16-effect-studio-authoring-tool.md) law), the gesture is a **single `end_frame` edit** — the neighbour's
start moves *for free*, a stay-local boundary trade with everything downstream pinned.
Deliberately **not** the sound [fire-drag](16-effect-studio-authoring-tool.md) gap-trade: no `SoundGapMath`,
no compound edit — camera stores endpoints, sound stores next-fire gates, so the arithmetic
differs even though the [seam](16-effect-studio-authoring-tool.md) (report-don't-mutate → host applies →
reproject) is shared. **One grip per span, right edge only** (a "left edge" is always the
neighbour's right edge or the pinned frame-0 origin); the **first** span's left edge is
un-draggable, the **last** span's grip resizes the lane tail (and re-derives the end marker).
A grip therefore carries **two** span identities and they are allowed to differ (ADR-0086
decs. 22-23): its **write owner** — whose `end_frame` /
`time_value` the drag stores, never re-attributed — and its **select identity**, who the drag
selects, inspects and draws a handle for. They coincide on a drawn span and come apart at a
hidden [Spacer](16-effect-studio-authoring-tool.md): a hold's grip is the *next drawn span's* visible left edge, so
that neighbour is what gets selected (the hold never reveals, and its derived Length ticks with
the drag); a hold whose successor is **also** a hold is a **blind** boundary, and a hold at the
lane **tail** has no successor at all — both grip **with no identity**, so the drag moves no
selection and the hold still never reveals. Three cases, no special case. One pure decision,
`EffectScoreTimeline.edge_grip_identity` (a String; `""` = leave the selection alone).
_Superseded 2026-08-19 (ADR-0086 dec. 23, built): blind boundaries
briefly registered **no grip**, which cost 0.9% of camera boundaries but 12-18% of colour ones
— and unlike camera, a colour hold has no [compiled lane](16-effect-studio-authoring-tool.md) to fall
back to, so ~1945 colour keyframes became unreachable rather than merely un-grabbable._ Because grips draw for the hovered edge plus every
edge whose *identity* is the selection, a selected span shows **both** its handles wherever a
hold precedes it — the author's "left resize handle", with no second grip existing.
Clamped strictly between neighbours (min 1 frame) — a drag never deletes or makes a
zero-width span (deletion is the separate [delete verb](16-effect-studio-authoring-tool.md)). Strictly
**per-sub-channel-lane**: dragging angle never moves a coincident position/zoom sibling —
the [coalescing lowering](16-effect-studio-authoring-tool.md) re-splits/merges on save.
One drag = **one undo** (a drag-scoped same-field coalesce in `EffectEditSession`), applied
**at most once per rendered frame** (the same expensive-op drain the scrub-seek uses).
The **palette** lane shares this gesture and seam ([ADR-0087](../adr/0087-palette-tint-is-a-signed-blend-delta-authored-as-a-result-pick-against-a-reference.md)):
because palette adopts the same [absolute-interval authoring + lowering](16-effect-studio-authoring-tool.md)
split, a boundary drag is still ONE absolute-boundary edit (downstream pinned), and the
palette lowering re-derives the length-encoded `time_value`s (`× 8`) — so palette drags
**snap to 8-frame steps** and re-time the DDA ramp (length and ramp are the same on-disk
field). The trade **freezes the far edge**: the two traded lengths sum to their original total
*exactly*, so a boundary position whose halves are not both storable is **not offered** and the
handle visibly skips it (ADR-0087 dec. 30 / [ADR-0101](../adr/0101-a-colour-span-moves-at-frame-granularity-by-spending-keyframe-slots.md),
built 2026-08-19 — the pre-fix code re-snapped the neighbour's share silently and
its far edge drifted ±1 frame in ~13% of drag positions). Colour trades are therefore strictly **8-grained**;
sub-8 positioning belongs to [Move](16-effect-studio-authoring-tool.md), not to the trade. It is still **not** the sound gap-trade — only the lowering *target* differs from
camera (`time_value` vs `end_frame`). On the colour lanes the typed **Duration** row is the
**second affordance for the same edit** (a `duration` pseudo-field delegating to the boundary
trade; typed values quantize to the snap grid and the cell shows the snapped number), and both
affordances obey the [Ripple](16-effect-studio-authoring-tool.md) toggle.
_Avoid_: modelling it as a two-neighbour compound edit; reusing the sound gap math (for
camera OR palette — both author absolutely); letting an over-drag collapse a span into a delete;
giving the typed Duration different semantics from the drag; **selecting a grip's write owner**
(that reveals a hidden hold mid-drag — the reported "left-handle resize creates a spacer");
suppressing a hold's grip outright (it is the only way to drag that boundary).

**Move** (span body-drag; [ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md)
`particle_timeline`, generalized to colour + camera by
[ADR-0101](../adr/0101-a-colour-span-moves-at-frame-granularity-by-spending-keyframe-slots.md)
decision 3, 2026-08-19):
Repositioning a [lane event](16-effect-studio-authoring-tool.md) by dragging its **body**, as distinct from
[Boundary drag](16-effect-studio-authoring-tool.md), which resizes it by an edge. The span keeps its
**width**; one clamped delta shifts **both** its boundaries; the two immediate neighbours absorb
the shift, and everything outside them stays **pinned at its absolute frame**. Both neighbours
must therefore be [spacers](16-effect-studio-authoring-tool.md) — a span **wedged** between two drawn events is
**refused**, and a first span never slides **left** — there is nothing before the phase origin
to give up. It does slide **right**, where the kind can manufacture the empty space in front of
it: on **camera** always (a `MAP`+0 event is a hold by the *local* predicate, invisible by
construction), on **colour** never for span 0 (its only candidate padding is an idempotent
repeat of the keyframe at the insertion point, and before the first span there is none). On
**colour**
that rule is read at its word rather than mirrored from particle, because a colour lane is
**fully tiled** and only **1.9%** of its drawn spans have a [hold run](16-effect-studio-authoring-tool.md) on both
sides: **one** hold is enough, and the side that must GROW is grown from a **manufactured**
hold — an idempotent repeat of the keyframe at the insertion point, whose invisibility is
**asked of the real fold** once per gesture (it holds for ~92% of palette keyframes and the
verbs refuse that direction for the rest). Census: **17%** of shipped drawn colour spans move,
against 2% under the strict reading. The right-edge
grip is hit-tested first, so the body-drag is body-only; a press without motion is still just a
select. One drag = **one undo**, and it **re-plans from a pristine snapshot** each motion
rather than mutating in place, so the gesture is idempotent — replaying an earlier cursor
position lands exactly where going there directly lands. The COLOUR edge drag now shares that
bracket; camera's does not need it (its boundary arithmetic is absolute, and its spacer test is
local rather than a fold).
_Avoid_: reading it as a resize (width is the invariant); expecting downstream to slide (that is
Ripple, a different choice); assuming one granularity across kinds — camera moves at **1 frame**
for free, colour only by paying the [slot budget](16-effect-studio-authoring-tool.md).

**Slot budget** (colour storage capacity; [ADR-0101](../adr/0101-a-colour-span-moves-at-frame-granularity-by-spending-keyframe-slots.md)):
A colour track is a **fixed 33-slot** on-disk structure, and the runtime plays only
`max_keyframe − 1` of them — so a channel's spare capacity is `33 − max_keyframe`, a real and
exhaustible quantity. It becomes a **currency** because a colour span's length is `1` or a
multiple of `8` and nothing between: any offset that is not a multiple of 8 can only be
expressed by **spending 1-frame spacer keyframes**, since every sum of multiples of 8 is itself
a multiple of 8. The cost is forced, not chosen — a slide-in-place [Move](16-effect-studio-authoring-tool.md) of a
non-multiple-of-8 delta costs **exactly 8 slots**, whatever the delta. Where the channel cannot
pay, the gesture **degrades to 8-frame granularity** rather than refusing, and the *tell is the
handle's own motion* (frame-by-frame tracking vs. visible eight-frame snapping) rather than any
added chrome. Measured: **90 of 4812** shipped palette+screen channels (1.9%) have fewer than 8
free slots; 28 have exactly one. Collapsing a [hold run](16-effect-studio-authoring-tool.md) **recovers** its slots.
The verbs enforce the ceiling **up front** — `insert_event` used to append past 33 with no check
at all and let the saver discover it, which turned a full channel into a failure deferred to the
one moment it costs most.
_Avoid_: treating the 33 slots as headroom (real data sits on the ceiling); reading the budget
off `keyframes.size()` (loaded data always carries all **33** slots — the used count is
`max_keyframe`); padding with **disabled** keyframes (those are "muted, not gone" and *draw*, hatched — padding must be
**copies of the adjacent hold**, which inherit its inert verdict and stay invisible).

**Drag preview** (deferred refold, [ADR-0089](../adr/0089-emitter-parameters-author-as-semantic-two-axis-groups-edited-at-the-reference.md) particle_timeline amendment):
The per-motion cost model of a live edge- or body-drag. During the drag only the
**sim-free [score](16-effect-studio-authoring-tool.md) geometry** reprojects each rendered frame
(`reproject_score` → `rebuild_layout` — pure layout off `effect_data`, so the
dragged rect follows the cursor); the **sim refold is deferred to drag-release**
(`edge_drag_ended` / `span_body_drag_ended`). For [read-live](16-effect-studio-authoring-tool.md) lanes
(screen / palette / sound, `invalidates_sim = false`) there is no refold anyway, so
this is a no-op; it matters for the **sim-invalidating** lanes — **particle** and
**camera** (`invalidates_sim = true`) — whose refold is a full **rescrub** (reset +
deterministic replay from frame 0, `EffectTimeline.rescrub`). The old path ran that
rescrub **once per rendered frame** of the drag, which stalls when particles are
dense (unlike a cheap fold). So the particle **cloud** holds its drag-start state
until release, then snaps to the committed result: **one refold per drag, not per
frame**. This *sharpens* the [Boundary drag](16-effect-studio-authoring-tool.md) "at most
once per rendered frame" rule — the geometry still reprojects per frame; only the
expensive sim replay moves to release.
_Avoid_: refolding per motion on a sim lane (the lag this fixed); "fixing" the
frozen-cloud-during-drag as a bug (it is the deferral, correct on release);
deferring the *geometry* too (the rect must track the cursor live); assuming
read-live lanes need any of this (they never refold).

**Ripple** (resize mode, ADR-0087 decs. 10, 15-16):
An explicit, author-chosen resize mode — a visible **toolbar toggle** (off by default,
session-local, never saved into the effect) under which a resize (edge drag **or** typed
value alike) **skips the stay-local trade**: the edit behaves like the tail-extend path and
every downstream keyframe **in that lane** shifts by the delta. Covers **every lane with a
resize affordance** (ADR-0087 decs. 15-16): the length-encoded colour lanes
(storage-native, one duration field, scalar undo), the **camera** sub-channel lanes
(endpoint-encoded — the lane's downstream `end_frame`s shift, coalesced keyframes split out
lane-locally, undo is the structural stash, overflow is clamped/refused never saturated), and
the **sound** trigger lanes (the typed Gap is ripple *by nature*, toggle or no; the fire-drag
under ripple edits only the prior gap so later fires shift). **Lane-local by
contract** — other subsystems stay parked, so cross-lane alignment (boom+flash+shake) is the
author's responsibility while the toggle is on; a cross-lane ripple is a separate, deferred
design. Distinct from the **forbidden implicit ripple** (a `time_value` edit silently moving
the tail as a storage side-effect, the semantic ADR-0087 rejected as a default): ripple here
is deliberate, visible, and one undo.
_Avoid_: rippling by default (stay-local trade is the off-state and the default); shifting
other lanes; persisting the toggle into the file; calling the storage side-effect "ripple
mode"; "fixing" the sound Gap to obey the toggle (it is natively ripple — the gap IS the
offset to the next trigger); using the word for the
spatial propagation of a [sheet region](16-effect-studio-authoring-tool.md) edit across the frames
that share it (different axis, different lifetime, ADR-0099).

**Entity pool** / **Reference** (write side of the [link](16-effect-studio-authoring-tool.md)):
The authoring model is **two-layered**: *(1)* channels of lane events (the
timeline) **plus** *(2)* a **pool of shared entities** that lane events point at —
[emitter](15-effect-orchestration.md), and the future frameset / frame / curve /
animation / callback ([ADR-0073](../adr/0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)
kinds). A lane event's per-archetype contents may hold a **reference** into that
pool — the write-side counterpart of the read-side [link](16-effect-studio-authoring-tool.md),
preserving [ADR-0071](../adr/0071-a-studio-lane-event-projects-through-a-per-archetype-projector-that-separates-owned-from-referenced.md)'s
owned-vs-referenced split. **Repointing** a reference (which emitter a
[span](16-effect-studio-authoring-tool.md) spawns) is part of lane-event authoring; **editing the
entity itself** is a *distinct authoring target* with its own per-kind editor —
**seams** for now, mirroring the read side's null [projectors](16-effect-studio-authoring-tool.md) and
the "frame/frameset editor" fog on the map.
_Avoid_: flattening a reference to an opaque integer field (loses the shared-entity
affordance and forces a re-model when the entity editors graduate); building an
entity editor under this spine ticket (it stays fog).

**Live window** / **Capacity**:
A channel's lane events run up to a **watermark** (the on-disk `max_keyframe`) —
the count that is *live*; slots beyond it are ignored stale bytes. **Create** =
append/insert a lane event and advance the watermark; **delete** = remove and
retract it. Whether the watermark is **bounded** is set by the [conformance
profile](16-effect-studio-authoring-tool.md): **unbounded** in Free, **capped** at the channel's
native array size (≤25 particle, ≤33 screen/palette, ≤17–21 camera, ≤9–17 sound)
in Faithful.
_Avoid_: modeling the slots past the watermark as meaningful; treating capacity as
an absolute law (it is a [Faithful](16-effect-studio-authoring-tool.md)-only constraint).

**Conformance profile (Free / Faithful)**:
The axis that makes the map's destination — "free authoring **subsumes** faithful
ROM re-authoring" — concrete. The authoring model is **unbounded by default
(Free)**; **Faithful** is a profile the author switches on to guarantee the effect
is patchable back into `E###.BIN`. It is an **extensible** concept (two members
defined now, room for more). Faithful enforces the **whole constraint bundle**,
not just one limit: per-channel [capacity](16-effect-studio-authoring-tool.md) **and** quantization
(screen/palette/sound durations snap to 8-frame steps) **and** the fixed byte
[encodings](16-effect-studio-authoring-tool.md) — all three must be satisfiable or the effect cannot
be lowered to BIN. Free ignores the bundle and targets the Godot-native resource.
The [channel archetype](16-effect-studio-authoring-tool.md) module owns each channel's bundle; the
encoder validates against it before repack. This feeds the persistence-target
decision ([#254](https://github.com/timbermania/fft-monorepo/issues/254):
Faithful ↔ `E###.BIN`, Free ↔ native resource — decided there, not here).
_Avoid_: treating Faithful as "capacity only" (a 20-of-25 particle timeline with a
non-`×8` frame is still un-encodable — patchability needs the full bundle);
hard-coding exactly two profiles as a closed enum (the concept is extensible).

**Texel class**:
Which of three kinds a texel on an effect's [sheet](16-effect-studio-authoring-tool.md)
is, partitioned by its palette word: **transparent** (`0x0000` — the PSX skips it;
72.1% of corpus texels), **opaque** (STP=0 with a real colour), and **STP**
(STP=1 — the blend-mode flag of [ADR-0096](../adr/0096-a-texture-alpha-channel-carries-the-stp-bit-not-opacity.md),
27.9%). A *class*, not a layer or a plane: the partition is a property each texel
already has, not a stacking order and not a separate body of pixel data. The
opaque class is near-empty in the ROM (254 texels across 4 effects) and kept
anyway — this is an authoring surface, so the corpus is its input, not a bound on
its output.
_Avoid_: "layer" (taken by [sprite layers](18-sprite-layers.md) — a unit's four
ROM-defined layers); "plane" (taken by the *indexed pixel plane*, the per-texel
index data that lives only in the BIN); reading the alpha byte as opacity (it
carries STP); calling the transparent class "background" (it is a palette value,
and art can contain it).

**Sheet**:
The single texture every [frame](16-effect-studio-authoring-tool.md) of an effect UVs
into — `assets/effects/E###/texture.tga`, one per effect. The word exists to keep
"the whole image the frames address" distinct from "the image data" generally.
_Avoid_: "the texture" when the point is that frames share one (the sharing is
what makes UV rects meaningful).

**Pixel ladder**:
The rule that an effect [sheet](16-effect-studio-authoring-tool.md) is only ever drawn
at a whole-number scale — `1×, 2×, 3×…` when magnified, `1/2, 1/3…` when shrunk,
with fit snapping *down* to the nearest rung. Trades ~9% of the largest possible
view for a grid where one texel is always the same number of screen pixels, which
is what makes a per-texel readout trustworthy ([ADR-0098](../adr/0098-the-frameset-viewport-is-a-pixel-exact-texel-class-view-of-the-sheet.md)).
_Avoid_: "fit" / "zoom to fit" as if it were free (exact fit is the rejected
alternative); interpolating between rungs.

**Frame coverage**:
The region of a [sheet](16-effect-studio-authoring-tool.md) that some frame's UV rect
actually addresses — 48.1% corpus-wide, and as low as 27.3% (E317). Its
complement is sheet area no frame ever draws: dead in the ROM, and therefore the
space an author can paint into freely.
_Avoid_: assuming a sheet is fully used; conflating coverage (which texels are
*referenced*) with [texel class](16-effect-studio-authoring-tool.md) (what each texel
*is*) — a covered texel can be transparent and an uncovered one can be art.

**Texture tab** ([ADR-0130](../adr/0130-the-texture-has-two-surfaces-a-page-and-a-tab-on-the-inspector-row.md),
2026-08-20):
The inspector row's LEFT column has two tabs, `[Texture] [Values]`, on every target kind.
`Values` is the inspector; `Texture` is the sheet's picture — the [frameset
canvas](16-effect-studio-authoring-tool.md) taking the whole slot, with the sheet's metadata, the Export/Import
round trip and the [region scope](16-effect-studio-authoring-tool.md) control riding ON it as a bottom-right
overlay. It is the SHALLOW of the texture's two surfaces; the [texture page](16-effect-studio-authoring-tool.md)
is the deep one.

The tab exists because the studio had **four** texture surfaces and **none of them drew the
sheet**: the only renderer was gated to the `frame` target kind alone, so the texture page
could not show the texture by construction. A tab rather than the collapsible BAND first
proposed, because a band takes height from a budget that is 268px total at the dev body —
where the sequence player already wants 348 and is clipped — while a tab costs the row no
height at all. Measured on a 128×256 sheet: the band shows 52% of it, the tab 94%, and the
player does not move. The strip's height is MEASURED (`_tab_strip_h()`), never the
`_TAB_STRIP_H` constant: a Container cannot shrink below its minimum, so the constant is a
floor its buttons' own padding exceeds — reserving the constant overlapped the inspector by
5px. Same trap as `PathBar.bar_height()`.

**The picture takes the WHOLE slot; the facts are an overlay on it** (ADR-0130 dec. 11,
amended 2026-08-21). There is no width split any more and no `set_slot_width` — the tab's
combined minimum is chrome alone, measured **1px**, because `FramesetCanvas` extends
`Control` and NOT Container, so an anchored child contributes nothing to an ancestor's
minimum. The overlay declares `OVERLAY_W` (248), caps itself at 60% of the port's height,
scrolls its own body, keeps Export/Import at the TOP so a clamp takes a fact and never a
button, and is `MOUSE_FILTER_PASS` so hover/zoom/pan reach the picture through it.

**The history matters more than the rule, because this surface has frozen an incidental
layout into a constraint twice.** The old shape was a SPLIT: `CANVAS_W` (560) beside a
declared 300px facts column, which put the panel's combined minimum at 864 against
leftovers of 727/776/812 — a Container cannot shrink below its minimum, so the panel
overflowed RIGHT and the sequence player, drawn later and therefore on top, sliced the
facts off mid-word. That reasoning is sound and its failure is now UNREACHABLE rather than
managed. What the split could not see is that at the dev body the slot is **1564px**: the
canvas was capped at 560 while the facts scroll carried `SIZE_EXPAND_FILL`, so a thousand
pixels went to a column whose text is 250px wide — *"a giant column with a bunch of dead
space on it"*. `CANVAS_W`'s own justification (a wide port strands the metadata 1100px from
the sheet) dissolved the same way: on the port, the facts are adjacent at every width by
construction.
_Avoid_: reading a Control's `.size` to learn what it was offered; giving this panel a
`custom_minimum_size` on either axis (the height floor was the same bug in 2026-08-20's
first round — see ADR-0130 finding 4); putting the overlay's body in a
`SCROLL_MODE_DISABLED` ScrollContainer (that folds the content's minimum WIDTH into the
overlay's, and one un-wrapped Label built by another file blew 248 out to 315); styling the
overlay with per-node theme overrides rather than a propagating `Theme` (they miss every
control built elsewhere).

**The tab opens the sheet at `max(1, fit)`, and the frame screen does not** ([ADR-0098]
dec. 2, amended per surface 2026-08-20). `FramesetCanvas.open_at_fit` is the flag; the rung
is DERIVED from the live port every draw, never snapshotted, because this port's height
changes with the open target. The floor is ADR-0098's flat-100% ruling surviving rather than
being overturned: `fit_scale` snaps DOWN, so a 256-tall sheet in a 263-tall row fits at 0.96
and a bare fit would halve it to save nine pixels. Measured on E019: a `frame` target's port
is 701 tall and opens at **2×** (was 128×256 adrift in a 560×701 canvas); a `frameset`
target's is 263 and stays at **1×**. Since dec. 11 gave the port the whole slot the tall
emitter row opens at **6×** — the fit is height-bound, so widening the port only helped
where the row was already tall.
_Avoid_: applying the flat 100% ruling to a new surface without re-measuring its port — it
was ruled against ONE port (the frame screen's 297×270), where fitting halves the view and
shrinks a 23×23 UV box below its own 8px handles.

**Frame screen** ([ADR-0130](../adr/0130-the-texture-has-two-surfaces-a-page-and-a-tab-on-the-inspector-row.md)
dec. 10, 2026-08-20):
**The sheet on the left, the animation on the right.** A `frame` target draws the sheet in
the [texture tab](16-effect-studio-authoring-tool.md) only; the inspector row's right column plays the sequence
that shows this frameset. It used to draw the sheet in BOTH columns, both interactive —
two places to drag one box.

Which sequence: measured over 17,423 framesets, **76.4% are named by exactly one animation**,
10.8% by none, 12.8% by several. One → bind it; several → bind the lowest and name it in the
panel title; **none → claim nothing**, and the width returns to the inspector ([ADR-0100]).
Inventing an address for an orphan frameset would decode a real sequence and draw real
sprites with nothing on screen saying it is the wrong one. The [group lens](16-effect-studio-authoring-tool.md)
is not applied — a frame target has no emitter to read one from.

A `texture` target still draws the sheet in both, on purpose: there is no sequence for it to
play, and the page having a picture is the complaint ADR-0130 opened on.

**Sheet region outline** ([ADR-0130](../adr/0130-the-texture-has-two-surfaces-a-page-and-a-tab-on-the-inspector-row.md)
dec. 4b, 2026-08-20; **live since dec. 12, 2026-08-21**):
The [texture tab](16-effect-studio-authoring-tool.md) outlines **every distinct region the frameset in context
samples**. Deduped by block — members of one region have the identical block ([sheet
region](16-effect-studio-authoring-tool.md)), so E019's typical 2-frame double-draw on one rect draws ONE
outline, not two stacked, and the readout's region count comes from the same array that is
drawn.

When there is **no single frame in context** — an `emitter`, `animation` or `span` target,
or a `frameset` — every one of those outlines is a **live box**: full-strength yellow, four
corner handles, its own anchor colouring, independently draggable (ADR-0130 dec. 12). That
is the *all-in-one* surface's editing model, and the dedup above is exactly what "perfectly
overlapping frames move together" means — frames whose blocks are equal are one box and one
drag, while partially overlapping or nested rects stay separate boxes ([ADR-0099](../adr/0099-a-uv-rect-is-a-shared-sheet-region-and-the-region-is-the-unit-of-edit.md)
dec. 2's "not overlapping, not containing, not near").

_Avoid_: calling a live box "the frameset's UV rect" — a frameset has as many as it has
distinct regions (up to 9 in the corpus, though 90.5% of framesets have exactly one), and
the singular is what dec. 4 rightly refused to mint.

**Pinned region** (ADR-0130 dec. 12f, 2026-08-21): a **click** on a live box — a press and
release with no motion between them — *pins* the scope to it. While pinned the pointer stops
speaking: hover re-binds nothing, only the pinned box takes a press, and the others fall back
to read-only outlines with no handles. Released by a press on bare sheet or by `Escape`, and
dropped by any re-bind.

It exists because dec. 12d's follow-the-pointer makes every control that *reads* the scope
unreachable — the facts overlay is in the port's corner, so the hand travelling to a button
or a rail tile crosses the sheet, and 118 corpus region pairs overlap inside one frameset, so
the panel is re-bound before the hand arrives.

_Avoid_: calling it "selection". Nothing is selected — the region was already the unit of
edit; the pin only decides **which** region the panel is about and freezes that answer.

**Frameset rail** ([ADR-0099](../adr/0099-a-uv-rect-is-a-shared-sheet-region-and-the-region-is-the-unit-of-edit.md)
dec. 5a, 2026-08-21): the row of tick-able **thumbnails along the bottom of the texture
viewfinder**, one per frameset the resolved region reaches, painted through the same
`SequenceSpritePainter` the sequence strip and the player use. It is the `Pick` mode of the
[scope toggle](16-effect-studio-authoring-tool.md), and it is a picture because the thing it
selects has no other address: 91.5% of multi-member regions reach outside the frameset on
screen, so the set an author must consent to is normally sprites they cannot see.

In **thumbnail order** — the framesets the sequence on screen reaches first, in that order,
then the ones it never plays. That tail is the point, not a leftover: on E317 a region spans
framesets 15/17/18/19/20/21 while the emitter's sequence plays only 15, 16 and 22.

**It shows for EVERY region**, including one living in a single frameset (2026-08-21). It
used to collapse a row of one to nothing — *"a row of one is not a choice"*, true about
**ticking** and wrong about the rail — which hid it on **3636 of 6632** corpus regions
(54.8%), so its presence read as arbitrary. **3361** of those (50.7% of all regions) have a
single member, and the member list is gated on `_members.size() > 1`, so the author saw
*neither*: nothing at all named the sprite the edit would rewrite. Two consequences ride
with it. The list is **not** suppressed on a one-tile row — that row enumerates none of the
choice, and 275 regions (4.1%) have several members inside one frameset, 68 of them
disagreeing about a facet; a 13-tile row for 15 members still suppresses it, as always. And
`toggle_frameset` **refuses the whole gesture, mode switch included**, on a one-frameset
region: *"a tile tick IS choosing to pick"* and *"the last tick cannot be removed"* are the
same click there, so its entire effect had been to move the control into `Pick` with nothing
in it to pick.

**Each tile is fit to its OWN bounds**, which is the one place the rail must not copy the
[sequence strip](16-effect-studio-authoring-tool.md) (2026-08-21). The strip shares one `SequenceTimeline.bounds`
box across its row so that two framesets differing only in where the sprite sits cannot draw
as the same picture — a rule about one animation over **time**. The rail's row is one
**region**'s framesets, every member of which is the same sheet rect *by definition*, so
there is no such case to protect against; what differs is the frame **quad**, a transform
(dec. 3 amended), and the same texels routinely appear at wildly different scales. Under a
shared box the small ones vanished: E317 frameset 15's region is 33x33 beside five sprites
**5px tall**, drawn at 15% of the tile's height — *"why don't I see the thumbnails on the
texture anymore for what is selected for multi select?"* Corpus-wide (2920 rows / 15692
tiles, `tools/census_rail_tile_legibility.gd`) **19.2%** of tiles drew under a quarter of the
shared box and **26.4%** of rows had at least one; fit to their own, **2.8%** still draw under
2px. That residual is extreme **aspect ratio** — 244x4 beams that no choice of box can rescue
in a square tile — so this is an improvement and not a cure. What it costs: a tile no longer
shows that its member is drawn squashed. The label and the scope control's varying facets
still say so; the picture does not.

**Scope toggle** (ADR-0099 dec. 5a): *Effect wide* (default) / *Frameset wide* / *Pick*, each
carrying its own **count** ("Effect 15", "Frameset 2"), keyed on the **frameset** and never on
the frame. **Persists** across re-binds (ADR-0099 dec. 5e) — thumbnail changes, hover, pin,
and the author's own commit all keep it; only *Pick* degrades to *Frameset wide*, and only
when the region's **membership** changes. A region that merely **moved** is the same region.

_Avoid_: calling a narrowed scope a **filter**. It is a **SPLIT** (dec. 5b) — a region is
recomputed from the frames' own `uv_*` bytes on every read, so leaving members out gives the
moved frames a new rect and leaves the rest behind as their own region. The label says so.

**Age width** (ADR-0089, 2026-08-21): a colour column's band is `min_col_w` (5px) x its
**widest row**, floored at `band_width` (22) and capped at `band_max` (150). 22 is not a
judgement about ribbons — it is `sequence_life_slot_w(3)` minus the scrollbar, the gaps and
the 34px thumbnail, i.e. what **three** pairs can afford; one pair affords 150. A row is wide
exactly when there are few rows (`rows x ticks ~= life_n`), which is exactly when the strip
leaves pairs unused, so the width is already declared and already idle.

_Avoid_: growing the **slot**. Its declared minimum is one pair on purpose — a per-emitter bid
moves the inspector's right edge, and `_canvas_floor_w` would shrink the player's square per
target. The band grows inside the slot's live width, never past it.

**Grab target** vs **handle**: the corner handle is drawn 8px (`HANDLE_SIZE`) and grabbed at
14px (`HANDLE_GRAB`), reaching its full half **outward** and at most a **third of the box's own
side inward**, so the four corners can never eat the body drag on a small box. They used to be
one number tested as a *circle*, which stranded 26.8% of the pixels the author could see — the
diagonal-outward ones a hand aims at.

_Avoid_: growing the drawn square instead. The handle does not scale with zoom and the box
does; at the opening 100% a 23×23 UV box is 23px and its handles already nearly meet.

**Grab priority** (ADR-0130 dec. 12a): with N live boxes, a **corner beats a body across
regions**, then a **smaller block beats a larger** one. 118 corpus region pairs overlap
within one frameset and 48 share a top-left origin, so the handles genuinely stack; without
the first rule a nested rect's resize moves its neighbour, without the second the nested
rect is unreachable. The box under the pointer is drawn brighter, so which one *would* take
the press is readable before it is pressed.

**Anchor set** (ADR-0130 dec. 12b): on a live box the cyan [anchor
corner](16-effect-studio-authoring-tool.md) is drawn for **every corner some member winds from**,
not for one chosen member — 419 of 19,518 corpus regions have members that disagree. Agreeing
members give exactly one cyan corner, as on a `frame` target; disagreeing members give two,
which says so. Anchors draw in a second pass so a stacked corner never loses its cyan to a
neighbour's plain handle (dec. 12c).

Which frameset is "in context" is the target's on a `frame`/`frameset` target, and **the
sequence player's shown opcode** on an `emitter`/`animation`/`span` target — read from the
canvas's own trace via `shown_op()`, which already owns the playing-vs-parked rule. So
scrubbing the player walks the outlines around the sheet. Coverage dimming alone could not
answer this: dimming is a property of texels, and "which rect samples what" is a question
about rectangles.

**Texture surface count** ([ADR-0130](../adr/0130-the-texture-has-two-surfaces-a-page-and-a-tab-on-the-inspector-row.md)):
TWO places to view/export/import a texture — the [texture page](16-effect-studio-authoring-tool.md) and the
[texture tab](16-effect-studio-authoring-tool.md) — and everything else is a DOOR to one of them, never a third
place to do the work. The `Sheet → texture` link survives because it is the only thing that
MINTS the `texture` target (registering a kind does not make it reachable); the duplicate
Export/Import pair does not, and it rendered on TWO target kinds, not the one the audit
counted.

**Sheet region**:
The texel block on a [sheet](16-effect-studio-authoring-tool.md) that a UV rect
addresses, **shared by every [frame](16-effect-studio-authoring-tool.md) whose rect is
exactly it** — E019 has 184 frames and 14 regions, one of them used by 30 frames
across 15 framesets. Identity is *derived* from the frame's bytes with the flip
folded out (a negative `uv.width` means the stored `x` is the block's last
column), never stored, so membership is always current and nothing persists. A
region owns the rect and nothing else: palette, bpp, blend, and the vertices —
hence **scale and rotation** — stay per-frame, which is why one region can be
drawn at ten different sizes ([ADR-0099](../adr/0099-a-uv-rect-is-a-shared-sheet-region-and-the-region-is-the-unit-of-edit.md)).
_Avoid_: grouping by *overlap* or containment (E173 holds five nested beam
lengths that share an origin and are five regions); calling a region edit a
[Ripple](16-effect-studio-authoring-tool.md) (that word is the time-axis resize mode, and this is
neither sticky nor lane-shaped); a stored region id or a "detached frame" flag
(both would have to be session-local, and would silently reattach on reload).

**Anchor corner**:
Which corner of its [sheet region](16-effect-studio-authoring-tool.md) a frame's
stored `uv.x`/`uv.y` actually names — top-left for 20,292 frames, but
**top-right, bottom-left or bottom-right for the 2,628 that carry a flip** in the
sign of their width/height. Drawn in its own colour on the viewport, because the
box on screen is identical for every member of a region and only the anchor
differs.
_Avoid_: assuming `uv.x` is the left edge (it is the *right* edge whenever the
width is negative); treating the anchor as region state (it is a per-frame
property of how that frame encodes the same block).

**UV sign flag**:
The per-frame, per-**axis** bit (`E###.BIN` byte1 bits 4/5) that decides whether
a frame's `uv.width`/`uv.height` byte is read unsigned (`0…255`) or as two's
complement (`−128…127`). `parse_frame` applies it on read, the writer preserves
it verbatim and never authors it, and **`frames.json` does not carry it** — so
the studio can only *infer* it from the value the extractor produced: negative
proves it set, above 127 proves it clear, and `0…127` proves nothing, leaving the
intersection as the only honest bound (`FramesetCanvas.encodable_uv_range`).
Outside a frame's real range the writer's `& 0xFF` silently **aliases** rather
than failing: E027 stores a region at width −128, and growing it to −136 writes
byte 120, which the still-set flag reads back as +120 — losing the value and the
flip at once ([ADR-0099](../adr/0099-a-uv-rect-is-a-shared-sheet-region-and-the-region-is-the-unit-of-edit.md)
dec. 4a).
_Avoid_: reading "is negative" as "is flag-set" (16 corpus frames are flag-set
with a *positive* width); a flat `−128…127` bound (it mis-flags the 219 frames
whose dimension legitimately exceeds 127, E022's height 176 among them);
assuming a block one member of a [sheet region](16-effect-studio-authoring-tool.md)
can store is storable by all of them — the bound is per-member, which is why it
is checked before release rather than discovered as corruption after a write.
