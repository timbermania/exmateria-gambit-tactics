---
status: accepted
---

# The display-space effect fold is a material contract, not a module

## Status

Accepted. Verified 2026-08-28 — decisions 1–9 all built, and all four contract guards
sit at a hard-zero burn-down.

## Context

On the Forward+ 4.8 compositor fork, effect prims blend in **display space** through the
engine's Pass B, so each blend step clamps like PSX hardware. The prototype
`EngineFoldCompositor` fused two unrelated jobs — owning the Pass A/C display scratch
**and** rebuilding a `MultiMesh` carrier from a particle pool every frame — and routed
*every* producer (cursor, crystal, tile-overlay, callbacks, real particles) through that
particle pool. The pool carried a four-axis prim contract (blend / geometry / discard /
PAR) but the materialization step read only `mode`, dropping the other three: the live,
user-confirmed "blue Move / red Attack tiles vanish on Forward+" bug.

The original decision fixed fold routing and shape but said nothing about the fragment
**colour math**, and two folds drifted before that half was written down — the gold box
clipped pale, the cursor and orb halos went overbright. Decisions 6–9 are that half.

## Decision

"Folding" is a **contract, not a code module**.

1. **A foldable carrier is any `GeometryInstance3D` wearing a monomorphic material.** A
   single-quad `MeshInstance3D`, a baked multi-quad `ArrayMesh` or a batched
   `MultiMeshInstance3D`, wearing a `compositor_fold` material whose
   blend/geometry/discard/PAR are baked into its own shader with **no data-driven axis
   branching**, and carrying the ordering key of decision 2. Sixteen fold materials
   exist and every one is monomorphic.

2. **Ordering belongs to the depth system, not the fold.**
   `DepthMode.render_layer_order_for(order_z, rank)` is the single encoding —
   `round(order_z / UNITS_PER_OT_BUCKET) * RANK_STRIDE + rank`, asserting that rank
   cannot spill its bucket — and producers do not re-derive the OT-bucket math inline.
   The key is an **int32 `render_layer_order`** paired with a `render_layer`, not a float
   `sorting_offset`: no float32-ULP cliff and no NaN. *(Both spellings were renamed after
   the decision; `sorting_offset_for` and per-carrier `sorting_offset` are the retired
   ones. ADR-0009 records the rename.)* The clause held further than it claimed — the
   same encoding now serves `Fold.add`, `EngineFoldCompositor`, and, via `rung_z`
   (ADR-0077), four flat UI scenes that used to inline the multiply.

3. **The seam stays thin: material choice, attach and stamp are the producer's.** `Fold`
   is three statics and nothing else — `add(carrier, material, order_z, rank)`, plus
   `owns()` and `shader(folded, fallback)`, which ADR-0191 moved into the kernel after
   the fold-availability predicate had been copied verbatim to fourteen call sites. That
   predicate is not what this ADR refused; the refusal is of a module owning material
   choice, attach or stamp, and it stands. `add` self-gates on `owns()` and decorates
   nothing off-fork, because `render_layer` and `render_layer_order` are fork-only
   properties that **raise** rather than no-op on stock — a producer off-fork draws its
   own in-scene fallback.

4. **The `MultiMesh` batch path is the many-instances option, not universal transport.**
   `EffectMultiMeshPool` is retained only for the two genuine high-count particle
   producers, `EffectParticleRenderer` and `TrapEffect`, which borrow a slot;
   `EngineFoldCompositor` reads the pool each frame as the carrier source. Light
   producers and callbacks build their own carriers and fold directly.

5. **The Pass A/C scratch owner is a separate module, `FoldSurface`** — allocate, seed
   and resolve the display scratch — and it knows nothing about producers. It lives in
   the render addon (`addons/exmateria_render/fold_bracket/`).

6. **The fold is the *blended* (PSX semi-transparent / STP) pass, and only that.** Opaque
   texels and prims are a different pass: they draw in-scene, get tonemapped, and
   legitimately keep their `pow` (sRGB→linear). A single PSX sprite is often split — its
   opaque core draws in-scene while its STP glow/halo/outline folds, as `cursor_fold`
   does by keeping only the STP-window outline via `discard`. So "in the fold" ⇒ blended
   ⇒ display-space, and decisions 7–9 apply; "opaque" ⇒ the other pass, where they do not.

7. **A fold material declares its PSX primitive kind, and the kind selects the colour
   math.** A fold prim has two orthogonal axes: its blend/ABR mode (average / additive /
   subtractive / add-¼, already declared by `render_mode blend_*` + `compositor_fold`)
   and its **PSX primitive kind**. The kind is static per material, so it is a
   header-comment declaration with no runtime cost — `// psx-prim: textured` or
   `// psx-prim: untextured` — enforced by `tools/check_fold_primitive_kind.py`, which
   fails on missing or mismatched. In display space:

   ```
   // psx-prim: textured     ALBEDO = display_texel * (gouraud / 128)   // PSX (texel*color)>>7
   // psx-prim: untextured   ALBEDO = color                             // PSX flat/gouraud: color IS the output
   ```

   Textured prims (sprites, textured/paletted polys) modulate a texel, and the modulate
   **is** `gouraud / 128` — the PSX `>>7` identity, 128 = 1.0. Untextured prims
   (flat/gouraud polys, `TILE`, lines) have no texel: the interpolated vertex colour goes
   straight out, with no `>>7` and no `gouraud/128`. `tile_decal_fold` is the untextured
   case (`ALBEDO = COLOR.rgb`); everything else in the family is textured. The
   declaration is explicit because guessing the kind from "does it call `texture()`" is
   what let the untextured decal hide.

8. **No `pow`, no sRGB→linear, anywhere the fold reaches — including CPU colour
   resolution.** The fold blends into the display-space scratch with no tonemap after it,
   so linearizing is a half colour-space round-trip with no return leg: the gold-box
   class of bug. `pow` belongs only to the in-scene linear path (opaque bodies,
   `effect_particle_opaque`) which the pipeline tonemaps back. A helper resolving a
   folded prim's colour (`TileOverlayColor`, damage-number trends) must not apply
   `pow`/gamma either — it feeds the display-space fold. Enforced by
   `tools/check_no_pow_in_fold.py` for shaders and `tools/check_no_cpu_color_math_in_fold.py`
   for the resolvers, which is the class the shader guards are blind to.

9. **No global brightness multiplier; the display-gouraud gain is baked per-producer.**
   `psx_brightness` (~2.2) was never part of the contract — it was a legacy `÷255→÷128`
   scale conversion for the effect pool's `/127` colour-curve envelope only, and applying
   it to a display-native CLUT or direct-gouraud prim (box, orb, cursor) double-brightened
   it. The global shader param, its `PSXDisplay` plumbing and the `render.psx_brightness`
   tunable (ADR-0068) are deleted; brightness falls out of the data instead. Particles and
   trap take `POOL_GOURAUD_GAIN` baked into the fold `COLOR` at `EngineFoldCompositor`'s
   choke point where every pooled run's colour is finalized (`effect_fold_add/sub/mix`);
   `crystal_fold` and `effect_callback_fold` take a shader-local constant, the callbacks'
   selected by a per-material `uniform bool use_psx_brightness`; the tile decal takes
   neither, being an already-absolute CLUT colour. In-scene (non-fold) twins —
   `formation_box`/`orb`/`box_sub`, `effect_callback_additive` — keep their own
   `PSX_OUTPUT_LEVEL` local — they blend into a linear buffer and are tonemapped back, so they legitimately
   keep the level; they just no longer read a shared global. Enforced by
   `tools/check_no_psx_brightness_in_fold.py`.

## Why

The four-axis "mechanism" was an artifact of forcing heterogeneous producers through one
data-batched pipe. Axis variation is **per-producer and static**: a tile is *always* a
`world_quad` `alpha_key` decal, a crystal *always* a `billboard` `alpha_key` PAR-none
sprite, real batched particles *always* `billboard`/`stp`/`anchor`. Monomorphic materials
fix the tile bug **by construction** and let the particle path *delete* axis handling
rather than port it. Once material is producer-owned and ordering is `DepthMode`'s,
nothing is left in the middle worth a module.

## Verification

Four contract guards, all at hard-zero burn-down, run from the package root:

| guard | covers | reads |
|---|---|---|
| `check_fold_primitive_kind.py` | dec. 7 | 16 folds declare a matching kind (13 textured, 3 untextured) |
| `check_no_pow_in_fold.py` | dec. 8 (shaders) | 16 fold entry shaders scanned, 0 allowlisted |
| `check_no_cpu_color_math_in_fold.py` | dec. 8 (CPU) | 5 resolvers scanned, all raw display-space |
| `check_no_psx_brightness_in_fold.py` | dec. 9 | 16 fold entries, 0 on the endgame burn-down |

`tools/check_compositor_routing.py` scores routing across the whole shader family (16
routed, 19 exempt-marked, 7 mix inventoried, 2 add/sub allowlisted).
`tests/CallbackFoldRoutingTest.gd` locks the callback producer's routing in five arms —
the `Fold.shader` pick forced both ways, `compositor_layer` declared on the fold variant,
`// compositor-exempt:` on the fallback, uniform parity across the runtime `.shader` swap,
and every `CallbackRegistry` entry being an `EffectCallback` subclass. `tests/FoldTest.gd`
section 5 pins `add`'s off-fork no-op; `tests/DepthModeTest.gd` pins decision 2's
encoding.

Decisions 1, 4 and 5 are verified by reading. Unwritten and cheap: an arm asserting that
`sorting_offset` appears on no live fold path — it survives in `DepthMode`, two tests and
`tools/probe_demi_engine_fold.gd`, and only the last of those still **assigns** it, on a
probe rig that predates the int32 key.

## Considered options

- **Data-driven axis-branching übershader** — port the retired GLSL fold's push-constant
  flags into the engine-fold `.gdshader`. Rejected: no batched particle ever needs a
  non-default axis, and it keeps the heavy pool as universal transport, the thing being
  demoted.
- **A deep `Fold` module** owning material choice + attach + stamp (the architecture
  review's Candidate 1). Rejected once material became producer-owned and ordering became
  `DepthMode`'s: the module dissolved into a thin decorator. ADR-0191 dec. 4 re-refuses
  the material-choice third of it on a measurement this ADR did not have — only 6 of the
  16 `compositor_layer` shaders are mechanical enough for a factory, and those six are
  already deduplicated one layer down into two `.gdshaderinc` files, so a GDScript factory
  would collapse nothing still duplicated.

## Consequences

- Fixed the Forward+ tile-vanish bug, which was the precondition for deleting the GLSL
  fold `CombatDisplaySpaceComposite`. That deletion has happened; the name survives only
  as epitaphs in `EngineFoldCompositor` and `CompositorAutopilot`.
- Two new monomorphic shaders were needed and exist: `crystal_fold` and
  `tile_decal_fold` (`world_quad`/`alpha_key`/PAR-full).
- `EffectMultiMeshPool` shed its `discard`/`geometry`/`par` slot-fields. Whether its
  cross-frame *reuse* still earns its keep is open pending a real prim-count profile;
  batching is kept regardless.
- The routing lock landed as **two** instruments rather than one. `CallbackFoldRoutingTest`
  stayed the callback producer's lock instead of generalizing to every producer; the
  general coverage is the static `check_compositor_routing.py` scan plus per-producer
  routing tests.
- **The `④`/`⑤` markers in source citations are not decision numbers.** Eighteen
  citations across eighteen files spell `ADR-0074 ④a/④b/④c/⑤`, indexing the commit list
  of issue #229 — the implementation plan for this ADR — not anything in this document.
  The two numberings do not correspond: #229's commit 1 is decision 2 here, its commit 2
  is decision 5, its commit 3 is decision 3, its `4a`/`4b`/`4c` are the monomorphic-shader
  consequence rather than a decision at all, and its commit 5 is the pool shedding its
  slot-fields. `check_adr_anchors.py` matches none of the circled forms, so it can see
  neither numbering. Which citation form the eighteen should carry is open (#687).

## References

- [ADR-0009](0009-ordering-table-depth-is-one-model.md) — `DepthMode` and the ordering key
- [ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md) —
  the retired `render.psx_brightness` tunable
- [ADR-0077](0077-flat-ui-scenes-materialize-render-order-into-depth-to-join-the-fold.md) —
  flat UI scenes joining the same ordering key via `rung_z`
- [ADR-0191](0191-the-fold-predicate-is-the-kernels-and-a-producer-picks-between-two-shaders.md) —
  the fold-availability predicate moves into the kernel; `Fold` gains `owns()` and `shader()`
