# The display-space fold is `Render`'s, and a producer keeps its own shader

`Render` publishes **three** things — a shader library, a membership interface,
and an order encoding — and a producer that takes all three writes its own
shader. What crosses is a carrier, a material and an order key. `src/effects/`
holds **969 lines** that belong to four other owners.

Status: accepted (2026-08-20).

## Context

`tools/classify_blueprint.py` booked all 2,088 lines of rendering machinery
inside `src/effects/` to `Effects` by its directory rule, and
[#316](https://github.com/timbermania/fft-monorepo/issues/316) was filed to
settle who actually owns it. The ticket framed a contradiction: either the
renderer is `Render`'s and `particle` publishes on the compositing key, or it is
`Effects`' and [ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 1
names a crossing that does not occur.

**The dichotomy was false.** BLUEPRINT §10 already lists *"the fold |
pre-transparent compositing"* and *"the depth model | ordering-table / `CUSTOM0`
depth"* as `Render` Parts. The open question was never *who owns the fold* — it
was **where the line falls inside the 2,088**, and the audit moved it twice from
the position the ticket proposed.

Two facts the ticket did not have reframed the whole answer.

**The fold has producers in five systems, not four.** The ticket named
`Effects`, `Battlefield` and `Sprite Rig`. `UI` is the fifth and was missed
entirely — `UIUnitNameplate`, `UIVitalsBand`, `DamageNumber3D`, `DetailScene` and
`FormationScene` all call `Fold.add`. That is ADR-0118 dec. 4's *"`anchor space`
is what keeps `UI` free of the camera"* already instantiated in code.

**There are two submission paths, with different contracts and opposite
directions.**

| | direct | batch |
|---|---|---|
| call | `Fold.add(carrier, material, order_z, rank)` | `UnifiedPrimStager` → `OTDepthPrimOrder.order()` → `EffectMultiMeshPool.upload_unified()` |
| size | 33 lines | 724 lines |
| producers | `Battlefield`, `Sprite Rig`, `UI`, `Effects` (callbacks) | `EffectParticleRenderer` + `TrapEffect` — both `Effects` |
| direction | producer names `Render` — a publish | **`Render` names `Effects`** |

The ticket's proposed split assigned `UnifiedPrimStager` and `OTDepthPrimOrder`
to `Render` on the strength of a **stale docstring**: `UnifiedPrimStager`'s class
header says the tile / cursor / crystal producers *"become new callers"*, while
its own `publish()` header records the later truth — *"the light producers that
varied them (crystal / tile_overlay / cursor) **left the pool** to become direct
fold nodes with their own monomorphic materials."* Verified: those three files
mention `UnifiedPrimStager` only in comments. Zero calls.

## Decision

**1. `Render` owns the fold, and it is 504 lines, not 880.** `Fold.gd` (33),
`FoldSurface.gd` (263) and `EngineFoldCompositor.gd` (208) — the machinery every
producer system touches. `DepthMode.gd` is already `Render`'s and already lives
in `src/core/`.

> **Amended by [ADR-0200](0200-the-batch-payload-is-deleted-not-designed.md)
> (2026-08-21):** **296, not 504.** `EngineFoldCompositor.gd`'s 208 lines were the
> measure of how much `Effects` work had drifted across the boundary, not of how
> much renderer there is — its `Render` residue is the two-line
> `FoldSurface.new()` / `setup(cam)` install, so the file leaves `Render`
> entirely. `Render` projects **9 files / 1,755 → 8 / ~1,552** (−11.6%). Pass 6
> gates the code move; the classifier is unchanged and the booking follows the
> code.

**2. The batch path is `Effects`' own preparation.** `UnifiedPrimStager` (107),
`OTDepthPrimOrder` (269) and `EffectMultiMeshPool` (348) are `Effects`'.
`Render`'s ownership of the depth model is discharged by `DepthMode` being a
**published encoding**; `OTDepthPrimOrder` *applies* that rule, and applying a
published rule is not owning it. That is dec. 1 working as designed — the schema
is public, the consumer sorts by it. `EffectMultiMeshPool` settles itself: a slot
**is** an effect (`WARMUP_TOTAL_SLOTS = 64  # Concurrent effects pre-warmed`,
`set_effect_texture` on borrow), and its `RM_OPAQUE` MultiMesh is `Effects`
drawing its own particles in-scene, which never touches the fold at all.

**3. The batch edge points the wrong way and flips.** Today
`EngineFoldCompositor` does `get_node_or_null("EffectMultiMeshPool")` and then
`_pool.call("get_active_effect_buckets")` every frame — a hardcoded autoload name
**plus** a duck-typed method call, so `Render` polls `Effects`. This is the
[ADR-0127](0127-effects-publishes-and-requires-two-ports.md) defect in a file
that ADR did not look at, and doubly invisible: the classifier cannot see it
because it is the same directory, `tools/touch_matrix.py` cannot see it because
it is `.call("…")`. **`Effects` publishes its batch; the assembler wires the
sink; `Render` never says the word "effect."** The direct path is the worked
example — the fix makes the two paths structurally identical.

> **Amended by [ADR-0200](0200-the-batch-payload-is-deleted-not-designed.md)
> (2026-08-21):** the **diagnosis holds and the prescription was one step too
> far.** The last sentence is the one that survived: the two paths do not become
> *structurally identical*, they become **the same path**. There is no batch and
> nothing to publish — `Effects` builds its own carriers and joins through
> `Fold.add` like the other ten producers, so no assembler wires anything. A
> publish is for peers who must not know each other; `Render` is a **leaf** that
> names `Effects` zero times, and making `Effects` the only fold producer needing
> an assembler would be a bespoke mechanism for one caller. Generalising the test
> is [#333](https://github.com/timbermania/fft-monorepo/issues/333). **Answered by
> [ADR-0138](0138-a-publish-does-not-imply-an-assembler.md) (2026-08-21): the
> conclusion holds, the word `Leaf` does not.** `Fold.add` is a **publish with a
> direct binding** — the consumer set is closed, so an assembler buys nothing.
> `Render`'s runtime has **0** inbound edges; the 43 that look like calls on it
> land on shared encodings `Render` itself depends on. Dec. 4's *"`Render`
> publishes three things"* had already said it.
>
> Also measured there: this poll is worth **0** of `touch_matrix.py`'s 358 edges
> — invisible on all four shapes — so *"doubly invisible"* understates it. The
> replacement is a visible `class_name` reach, i.e. the count **rises** as the
> boundary improves.

**4. `Render` publishes three things, and a producer keeps its own shader.**

| | what | where |
|---|---|---|
| a **shader library** | the generic includes, taken across systems | `ot_depth` (16 includers), `par` (10), `screen_blend` (4), `color_stack` (2), `dither` (1) |
| a **membership interface** | declare `compositor_layer`, wear `FOLD_LAYER` | `Fold.add` |
| an **order encoding** | `(order_z, rank)` → `render_layer_order` | `DepthMode`, CPU **and** GPU halves |

This is [ADR-0074](0074-display-space-fold-is-a-material-contract-not-a-module.md)'s
*"a material contract, not a module"* stated precisely enough to build against,
and it is why `Fold.add` can be 33 lines: the rest of the contract is compiled
into the producer's shader. The depth model crosses in **two** halves —
`DepthMode.gd` computes `render_layer_order` on the CPU; `ot_depth.gdshaderinc`
writes reversed-Z `ot_depth` on the GPU. One encoding, two publication surfaces.

> **Amended by [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
> dec. 7 (2026-08-21): the library splits 2/3, and the last sentence above is
> why.** *"One encoding, two publication surfaces"* is exactly the property that
> makes `ot_depth` and `color_stack` **shared-kernel members rather than library
> entries** — they are the GPU halves of `DepthMode` and `ColorStack`, and they
> move into `addons/exmateria_schema/` with them. `par`, `dither` and
> `screen_blend` stay here and stay `Render`'s: no CPU counterpart, nothing
> agreeing across them, shared implementation rather than a crossing.
>
> The includer counts above are also restated with the convention they used, so
> the next reading is comparable. `.gdshader` entry points, `tests/` excluded —
> the convention here: `ot_depth` **16**, `par` **11**, `screen_blend` **4**,
> `color_stack` **3**, `dither` **1**. Every `#include` site, `.gdshaderinc`
> intermediates and `tests/` included: **21 / 16 / 4 / 5 / 3**. `par` and
> `color_stack` each read one above the figures recorded here.

**5. `anchor space` is not a key field — it is a library entry.** It is
`psx_par.gdshaderinc`, taken by ten producer shaders. Same for colour mode on the
direct path, where the opaque token dec. 4 requires **is the material**: `Render`
receives an opaque `Material` instead of an opaque `int` and interprets neither.
Picking your blend is not picking your place; place is order, and order is
surrendered on both paths. **This amends ADR-0118 dec. 4.**

**6. `layer` is currently degenerate, deliberately.** There is exactly one
`FOLD_LAYER` — *"one resource → one partition, the engine's one-partition fast
path."* The key names a field with one value. Recorded as a known simplification,
not a layer stack that exists.

**7. `Fold.add` is the sole sanctioned way to join the fold.** A producer never
names `FOLD_LAYER`; it hands over a carrier, a material and an order key, and
`Fold.add` defaults the layer because there is only one. `EngineFoldCompositor`
self-stamps `render_layer` at lines 201-202 — `Render` bypassing its own
interface — and closes onto `Fold.add`. `FoldSurface:200`
(`render_layers = [FOLD_LAYER]`) is *not* a bypass: that is the consumer-side
declaration.

**8. The fold-capability read is a third port.** `owns_compositing()` is reached
from **8 call sites across 4 systems** (`EffectCallback`, `TileCursor`,
`DamageNumber3D`, `DetailScene`, `StartActionMenu`, `FormationScene`,
`UIUnitNameplate`, `EffectViewerScene`), every one by hardcoded autoload name,
and every caller **branches on the answer**. By ADR-0118 dec. 3's test — *does
the caller need an answer?* — that is a port. It is a **build capability**,
static after startup, so each consumer declares it and the assembler answers it
once. **This adds a row to ADR-0127's port table**, which said `Effects` requires
exactly two.

**9. `CompositorAutopilot` is split, not assigned.** The capability probe,
`owns_compositing()` and the `native_blend` compare toggle are `Render`'s — they
are facts and policy about the renderer, and `Render` should answer *can I fold?*
itself.

> **Amended by [ADR-0200](0200-the-batch-payload-is-deleted-not-designed.md)
> (2026-08-21):** `native_blend` is `Render`'s **and it is partial**. It reaches
> exactly **one** consumer — `EngineFoldCompositor`, the file ADR-0137 dissolves
> — and **zero** of the ten direct `Fold.add` producers consult it, so flipping
> the toggle puts pooled particles and trap into native blend while callbacks,
> crystal, tile cursor, tile overlay, nameplates, vitals band, damage numbers and
> formation prims keep folding. It becomes a **second read on the
> `owns_compositing()` port** (dec. 8) so every producer answers it. The
> fold/native shader pair must stay a pair: they differ *only* in
> `compositor_layer` in `render_mode`, a compile-time flag. Camera-watching and re-attachment across scene changes are the
**assembler's** (ADR-0127). Measured, that residue is `_process` (6 lines) +
`_attach` (15) = **21 lines**, which is ADR-0118 dec. 6's *"twenty-line adapter"*
almost to the line — so the two assemblers **duplicate it rather than share a
library**. The platform tier is explicitly *"not a place for code"* and shared
`infrastructure` is for generic subdomains, so neither is its home. Should the
residue ever outgrow twenty lines, the shape that fits is `Render`'s addon
shipping an *optional attacher* the assembler chooses to call.

**10. The generic includes drop their `psx_` prefix, and gain no replacement.**
Inside `Render` everything is PSX, so the prefix says nothing (§10: *"it is about
looking like a PlayStation … the shaders and the depth model **are** the
deliverable"*). The tier marker is the **extraction path** — tier 1 becomes
`res://addons/render/shaders/ot_depth.gdshaderinc` while tier 2 stays in
`assets/shaders/` — and no prefix can say that as well as the path does.
Inventing one now is the preparatory-marker version of ADR-0121's preparatory
move. Only `par` wants a longer name (`pixel_aspect`). **The rename happens when
`Render` extracts, not here** — includes are absolute `res://` paths, so it edits
ten-plus files.

**11. The classifier books by file wherever a directory holds two systems.** The
mechanism already existed — `RULES` is ordered and exact paths beat directory
prefixes, which is how `src/core/` is already split. Eight entries added; done
**now**, before pass 6 takes the baseline, because #305's Notes warn that
measuring first *"would bake an instrument change into the series."*

## Consequences

**969 lines move, and every predicted figure landed exactly.**

| bucket | before | after |
|---|---|---|
| `Render` | 6 files / 1,251 | **9 / 1,755** (+40%) |
| `Effects` | 68 / 17,145 | **61 / 16,176** (−5.7%) |

**Amended by [ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
(2026-08-20):** `16,176` was correct and still reproduces exactly — but it counted
`Effects` *without* `src/effects/studio/`, which the classifier then booked as
`assembler`. ADR-0134 dec. 4 moves those 21,986 lines into `Effects`, which now
reads **146 files / 38,162 lines**. The `Render` figures are unaffected.
| `Battlefield` | 26 / 6,585 | 28 / 6,888 |
| `Sprite Rig` | 21 / 3,760 | 23 / 3,928 |
| `Battle` | 72 / 16,881 | 71 / 16,788 |
| `assembler` | 100 / 28,805 | 101 / 28,892 |

Total unchanged at 470 / 141,831; 0 unclassified.

**`Render` is still 1.2%, and that is the finding.** The classifier walks
`src/**/*.gd` only, so `Render`'s 48 shaders — what §10 calls its deliverable —
are invisible to ADR-0110's progress bar. **`Render` will read as the smallest
system in the repo right up until the moment it extracts.** This sharpens #305's
standing *"the metric counts the wrong lines"* rather than resolving it.

**BLUEPRINT's own extraction map is falsified.** *Where the code goes* draws
`render/ ← assets/shaders/ moves in; it is the deliverable` and `assets/ ←
content shadows stay; shaders leave with Render`. But tier 2 belongs to other
systems — `effect_particle_stp` is `Effects`', `unit_sprite_body` is
`Sprite Rig`'s, `tile_overlay` / `tile_cursor` / `cursor_fold` are
`Battlefield`'s — and leaves with **them**. **`assets/shaders/` splits by system
exactly as `src/effects/` does**: the same disease, a second directory, and one
the classifier cannot currently see at all.

**Two Accepted ADRs are amended, not superseded** — dec. 5 narrows ADR-0118
dec. 4's key, and dec. 8 adds a row to ADR-0127's port table. Both were
*under*-specified rather than wrong.

**ADR-0121 is not in tension.** Deciding who owns a file is not moving it, and
dec. 10 explicitly declines the preparatory rename.

**Not decided here.** The batch submission schema of dec. 3 is eight fields
including raw `RID`s and a `PackedByteArray` duplicating a GPU buffer; designing
it is its own ticket. The engine-side gap behind dec. 7 — the fork's
`get_configuration_warnings()` warns only when `render_layer.is_valid()`, so a
`compositor_layer` material with a **null** layer draws normally and silently,
the exact case a guard would want — is a change to an upstream Godot PR in
another repo, and is out of this map's scope. `Unit.gd`'s own `Battle` /
`Sprite Rig` question stays open in #305's fog; dec. 11 settles only
`CrystalSprite3D.gd`.
