# The batch payload is deleted, not designed — `Effects` builds its own carriers

There is no batch submission schema, because there should be no batch
submission. `Effects` hands `Render` exactly what the other ten fold producers
hand it — **a carrier, a material and an order key**, through `Fold.add` — and
the ten-field bucket dictionary, the run descriptors and the render-thread
storage buffer behind them are deleted. The payload [#318](https://github.com/timbermania/fft-monorepo/issues/318)
asked us to design is the shape of a boundary drawn in the wrong place.

Status: accepted (2026-08-21). Completes
[ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md) dec. 3,
which flipped the batch edge and deliberately did not design the payload;
discharges its dec. 7 (*"`EngineFoldCompositor` … closes onto `Fold.add`"*);
revises its dec. 1 line count and its dec. 9 treatment of `native_blend`.
Resolves [#318](https://github.com/timbermania/fft-monorepo/issues/318) on
blueprint map [#305](https://github.com/timbermania/fft-monorepo/issues/305).

All figures measured on trunk `003042ab9`, **2026-08-21**.

## Context

ADR-0129 dec. 3 found `Render` polling `Effects` — `EngineFoldCompositor` doing
`get_node_or_null("EffectMultiMeshPool")` and then
`_pool.call("get_active_effect_buckets")` every frame — and ruled that the edge
flips: *"`Effects` publishes its batch; the assembler wires the sink; `Render`
never says the word 'effect.'"* It named the payload as the open question and
left it. #318 inherited that, pre-loaded with an eight-field inventory copied
from `get_active_effect_buckets`' own docstring.

**Three of the ticket's premises were wrong, and correcting them is most of the
answer.**

**1. The payload is ten fields and five run fields, not eight and three.** The
producer emits `palette_tex_2d` and `palette_rows` on top of the eight; each run
descriptor is `{mode, base, count, stride, depth}`, not `{mode, base, count}`.
Both the ticket and the docstring it quotes are stale — `stride` and `depth`
were added by the slice-C packing bump and `OTDepthPrimOrder` writes them at
`:228` and `:235`.

**2. The dead half of every duplication is the GPU half, which is the opposite
of what the ticket's framing implies.** The ticket noted the raw-RD/GLSL fold
was retired in #228 Phase 3 and asked which of each pair had died. Measured
repo-wide, **`unified_buf`, `effect_tex` (the RD RID) and `palette_tex` (the RD
RID) have zero readers**, and so does top-level `count`. The only live consumer,
`EngineFoldCompositor._process`, reads `unified_bytes`, `effect_tex_2d`,
`palette_tex_2d`, `use_palette`, `palette_rows` and `runs`. Behind the three
dead fields sits real machinery: a 26-line render-thread storage-buffer
create/grow/update (`_rt_upload_unified`), the `_unified_buf`/`_unified_cap`
slot fields, and two `RenderingServer.texture_get_rd_texture` calls per bucket
per frame — one in the pool, one in `TrapEffect`, both feeding fields nobody
reads.

**3. `set_palette_texture` has one caller, not two.** Its docstring names
*"paletted producers (TileCursorCompositor, TrapEffect)"*; `TileCursorCompositor`
left the pool to become a direct `Fold.add` producer and no longer calls it.
`TrapEffect.gd:304` is the sole caller — the ticket's own guess at Q4 was right
and the code's comment was wrong. Third stale docstring in the same file.

**What the ticket could not see: `Render` holds three pieces of `Effects`
knowledge in order to consume this payload.** `EngineFoldCompositor._process`
decodes the 24-float ADR-0040 record layout by hand, knows that `record[20]` is
a per-prim `level_scale` that is `0.25` for mode 3, and multiplies every
carrier's `COLOR.rgb` by `POOL_GOURAUD_GAIN = 2.2` — a constant whose own
comment states its purpose: *"The effect POOL decodes its colour curve to `/255`
(EffectData: byte/255)."* It exists solely to undo `EffectData.gd:90`. That is
`Effects`' unit convention living in `Render` as a tuned scalar.

## Decision

**1. There is no batch payload. `Effects` builds its own carriers and joins the
fold through `Fold.add`.** Nothing effect-shaped crosses. The per-run
`MultiMeshInstance3D`, its material, its `effect_texture`/`palette_texture`
uniforms and the two colour bakes are all `Effects`' work, done on `Effects`'
side, and what reaches `Render` is `Fold.add(carrier, material, order_z, rank)`
— the identical call `EffectCallback`, `CrystalSpriteCompositor`,
`TileCursorCompositor`, `TileOverlayCompositor`, `UIUnitNameplate`,
`UIVitalsBand`, `DamageNumber3D` and `FormationScene` already make.

This answers #318's question 1 by refusing it. A payload is what you design when
two systems must exchange data; here the second system was only ever a factory
for a carrier the first system already knows how to build.

**2. `Effects` already builds MultiMesh carriers, so this is not new
capability.** `EffectMultiMeshPool` constructs a `MultiMeshInstance3D` per slot
for its `RM_OPAQUE` in-scene draw, with the same `use_colors` +
`use_custom_data` layout the fold carriers need (`:97-113`). The pool is one
function away from producing the fold carriers itself. `Render` builds a second
set from a byte blob **only because the payload arrived as bytes**.

**3. The duplications do not survive, and the survivor stops crossing anyway.**
Delete `unified_buf`, `effect_tex` (RID), `palette_tex` (RID) and top-level
`count`, with `_rt_upload_unified`, `_unified_buf`, `_unified_cap`,
`_UNIFIED_HEADROOM_BYTES`, the `palette_tex: RID` parameters on
`EffectMultiMeshPool.upload_unified` and `UnifiedPrimStager.publish`, and
`TrapEffect`'s `pal_rd` computation. The CPU/`Texture2D` half survives — but
under dec. 1 it stops being a crossing and becomes a shader-uniform set on
`Effects`' own material. **#318's question 2 has a stronger answer than "cut the
dead half": cut the dead half, and the live half stops crossing.**

**4. The 24-float record is itself a fossil, and the transcode goes with it.**
The stride-24 packing exists because the retired GLSL fold read an SSBO of
24-float records; `EngineFoldCompositor` immediately repacks it to Godot's
20-float `MultiMesh` layout, drops `[21..23]` as pad and bakes `[20]` into
`COLOR.rgb`. Once `Effects` owns the carrier, `OTDepthPrimOrder` can order
straight into per-run 20-float buffers and the repack loop disappears rather
than moving. Recorded as the shape, not scheduled here — the packing bump is
`Effects`' extraction pass.

**5. Buffer lifetime is not a question once nothing but a `Node` crosses.**
#318's question 3 asked who owns a buffer `Render` reads through an `RID`
allocated by an autoload it found by name. Under dec. 1 there is no buffer and
no `RID`: `Effects` owns the `MultiMesh`, parents the `MultiMeshInstance3D`, and
frees it on its own rebuild — exactly as `EffectCallback` owns `_mesh_instance`
today. **`Fold.add` mutates three properties and retains nothing**, which is why
it can be 33 lines and why lifetime never had to cross.

**6. The palette is a producer detail, and the mechanism says so, not the
census.** #318's question 4 asked whether `use_palette` + `palette_tex` +
`palette_rows` are schema or producer detail. Once the producer owns its
material, an indexed sheet is a `use_palette`/`palette_texture`/`palette_rows`
uniform triple that `Effects` sets on its own shader. `Render` never learns that
some sheets are indexed. The one-caller census (dec., context 3) agrees, but the
mechanism is the argument: this is ADR-0129 dec. 5's *"`Render` receives an
opaque `Material` … and interprets neither"*, applied to the batch path.

**7. There is one schema, and the batch path was never a second form of it — it
was the same interface with the carrier factory on the wrong side.** #318's
question 5 asked whether to reconcile the two paths or deliberately keep two.
Reconcile: they collapse to one. ADR-0129 dec. 7 already said
`EngineFoldCompositor` *"self-stamps `render_layer` at lines 201-202 — `Render`
bypassing its own interface — and closes onto `Fold.add`"*; this ADR is that
sentence carried to its conclusion. The bypass at `:200-202` is three lines that
duplicate `Fold.add`'s body verbatim.

**8. `Effects` calling `Render` is a dependency on a leaf, and that is the more
modular shape — not ADR-0129 dec. 3's publish.** Dec. 3 designed a *publish*:
`Effects` emits, the assembler wires the sink, neither names the other. Dec. 1
here instead gives `Effects` a hard static edge into `Render`. That is fewer
degrees of freedom on paper, and it is still right, because **`Render` is a
leaf**: `Fold.gd`, `FoldSurface.gd` and `DepthMode.gd` name `Effects` **zero
times** today, and ten producers across four systems already depend on `Render`
exactly this way. A one-way dependency on a stable leaf is the shape to want.
The publish shape is for *peers* who must not know each other — adopting it here
would make `Effects` the only fold producer needing an assembler to wire it: a
bespoke mechanism for one caller beside a shared interface for the other ten.
**Dec. 3's diagnosis was right and its prescription was one step too far.**

> **Amended by [ADR-0138](0138-a-publish-does-not-imply-an-assembler.md)
> (2026-08-21):** the **action holds and the reason is replaced.** `Fold.add` is
> the right shape, but not because `Render` is a leaf — that names a property of
> the *housing system* to license a property of the *thing named*. Measured on
> trunk `1a435a142`: of `Render`'s **55 inbound edges, 0 reach its runtime**
> (`FoldSurface` + `EngineFoldCompositor`, 471 lines, named by nobody); 43 land
> on `Fold`/`DepthMode`/`ColorStack`/`ColorRecipe`, which `Render`'s own runtime
> depends on *too*. Both sides depend on an encoding and neither invokes the
> other — that is a **publish**, and a publish never required an assembler. The
> binding test is whether the consumer set must stay open. **`Leaf` is retired**;
> those four files leave `Render` for ADR-0121 dec. 5's shared kernel
> (`Render` 1,755 → **869** lines).

**9. Four things cross, three of them declared ports and one a path.**

| what crosses | interface | precedent |
|---|---|---|
| the carrier | `Fold.add(carrier, material, order_z, rank)` | ADR-0129 dec. 4 — 10 call sites, 4 systems |
| *may I fold?* | `owns_compositing()` | ADR-0129 dec. 8 — 8 call sites, 4 systems |
| the order key | `DepthMode` | dec. 2: *applying a published rule is not owning it* |
| the shading | `ot_depth` / `par` includes | the shader library, dec. 4 |

The fourth is the honest soft spot: `effect_fold_add.gdshader` reaches
`psx_ot_depth.gdshaderinc` and `psx_par.gdshaderinc` through
`effect_particle_stp.gdshaderinc` as a **`res://` path string**. Nothing checks
it, `touch_matrix.py` cannot see it, and ADR-0129 dec. 10 defers the rename to
extraction. Three of four crossings are declared; the fourth is aspirational and
is now recorded as such rather than assumed.

**10. `native_blend` is a capability read, not a private field, and it is
partial today.** ADR-0129 dec. 9 books the compare toggle as `Render`'s. It
cannot survive dec. 1 as a field on a file that ceases to exist, and it should
not: measured, **`native_blend` reaches exactly one consumer** —
`EngineFoldCompositor` itself. **Zero of the ten direct `Fold.add` producers
consult it**, so flipping the Effect Studio's *"Render-layer: NATIVE"* toggle
puts pooled particles and trap into native blend while callbacks, crystal, tile
cursor, tile overlay, nameplates, vitals band, damage numbers and formation
prims keep folding. The comparison is silently partial, which makes it a
misleading instrument for the one question it exists to answer. It becomes a
**second read on the `owns_compositing()` port** — the shape already proven
across 8 call sites and 4 systems — so every producer answers it and every
producer picks its fold-or-native material accordingly. The fold/native shader
pair must stay a pair: they differ *only* in `compositor_layer` in
`render_mode`, which is a compile-time flag, so membership genuinely cannot be
toggled on one material.

**11. The fold shaders are `Effects`', and `Render` holding them by path is the
leak dec. 4 predicted.** All six — `effect_fold_{add,sub,mix}` and
`effect_native_{add,sub,mix}` — `#include`
`effect_particle_stp.gdshaderinc`, the particle STP-window contract. They are
producer shaders under ADR-0129 dec. 4's *"a producer keeps its own shader"*,
and `EngineFoldCompositor` names all six by `res://` path. That reference goes
with the file.

**12. Making the crossing declared makes it countable, so the reach count goes
UP while the boundary gets cleaner.** `touch_matrix.py` reads **358** edges
today, of which `Render → Effects` is **2** — and both are
`src/debug/ColorTimelineModel.gd`, nothing to do with the fold.
`EngineFoldCompositor`'s poll contributes **zero**: the autoload rule needs
`EffectMultiMeshPool.` with a dot, the `/root/` rule needs a `/root/` prefix,
and `strip_noncode` erases the string literal, so
`Engine.get_main_loop().root.get_node_or_null("EffectMultiMeshPool")` plus
`.call("get_active_effect_buckets")` is invisible on all four shapes. **The
largest payload `Effects` hands `Render` — ten fields wide — is worth 0 of the
358.** After the collapse the same relationship reads as `Fold` and `FoldSurface`
`class_name` references from `Effects`, i.e. **+1 to +2**. This is
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 6's floor, and the second instance after
[ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)'s
33-verb facade: **a number that rises when a boundary improves is behaving
correctly, and the baseline series must not be read as monotone.**

**13. No classifier edit, and no code moves now.** `EngineFoldCompositor.gd`
books as `Render` correctly *for the code as it stands* — it is a file that
polls `Effects` on `Render`'s behalf. The booking follows the code when the code
moves, and pass 6 gates that (#305, gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299)). ADR-0129 dec. 11
edited the classifier because that was a **booking** fix with no code change;
this is a code move, so the instrument stays still. The projected delta is
recorded in Consequences and is **not** in today's baseline.

## Consequences

**`Render` loses 203 of its 1,755 lines, and #316's arithmetic is revised.**
ADR-0129 dec. 1 booked `Render` at 504 lines of fold machinery — `Fold.gd` (33),
`FoldSurface.gd` (263), `EngineFoldCompositor.gd` (208). Under dec. 1 here,
`Render`'s residue in that third file is the two-line
`FoldSurface.new()` / `_fold_surface.setup(cam)` install, which is
`FoldSurface`'s own concern or the assembler's (ADR-0129 dec. 9 already books
camera-watching and re-attachment as the assembler's). The file leaves `Render`
entirely.

| bucket | today (2026-08-21) | projected |
|---|---|---|
| `Render` | 9 files / **1,755** | 8 / **~1,552** (−11.6%) |
| `Effects` | 146 / **38,168** | 146 / **~38,371** (+0.5%) |
| fold machinery (dec. 1) | 504 | **296** |

**The baseline moved, and this ADR moved it — third session running.** Both
instruments were re-run on `003042ab9` before and after. Reaches are unchanged
at **358**, but the three docstring corrections below add **6 lines** to
`Effects`: **470 / 141,831 → 470 / 141,837**, `Effects` **38,162 → 38,168**.
No classifier edit, so the movement is pure content — and it is the same lesson
[ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
recorded (*"the baseline moved before pass 6 read it — again"*) arriving from a
new direction: **fixing prose is enough to move a line-count baseline.** Pass 6
should take its reading from a stated commit, not from a figure quoted in an
ADR.

**`Render` was 1.2% of the projection and becomes ~1.1%.** ADR-0129's
Consequences already called `Render`'s size the finding; this makes it smaller
still, and for the right reason — the fold contract is genuinely tiny, and
`EngineFoldCompositor`'s 208 lines were the measure of how much `Effects` work
had drifted across the boundary, not of how much renderer there is.

**Three stale docstrings are corrected in place**, since all three misled this
ticket: `get_active_effect_buckets`' six-field inventory (it emits ten),
`OTDepthPrimOrder`'s run descriptor as `{mode, base, count}` (it writes five
fields), and `set_palette_texture`'s two named callers (it has one).

**What is now unowned:** the *"is the fold on?"* question has two reads with
different reach — `owns_compositing()` (8 sites, 4 systems) and `native_blend`
(1 site) — and dec. 10 merges the second into the first. Which system's
extraction pass performs that merge is not decided here; `Render` extracts
before `Effects`, and the toggle is `Render`'s by ADR-0129 dec. 9, so the
natural owner is `Render`'s pass. Recorded as fog on #305.
