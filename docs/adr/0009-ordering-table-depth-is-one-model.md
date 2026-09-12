# Ordering Table depth is one model: a representative point projected, biased by `DepthMode`

Battle draw-order depth was computed three different ways. Terrain faces projected a
per-face centroid baked in `CUSTOM0` (`indexed_color.gdshader`). Unit sprites derived
depth from `MODEL_MATRIX[3]` and subtracted a hand-tuned `depth_bias` uniform. Effect
particles used yet another path with hand-picked `world_bias = 1.0 / 2.5` constants, while
tile overlays added a raw `+0.0001` to `DEPTH` and `TrapEffect` carried a
`debug_depth_bias = -0.0019`. The biases were reversed-Z NDC epsilons with no relationship
to the ROM, no shared meaning, and no single home — and "a new mesh forgot `CUSTOM0`" / "a
new shader hand-rolled a `DEPTH` epsilon" is a recurring mistake the project's own
`CLAUDE.md` records.

These looked like three depth *models*. They are not. Validated against the FFT (PSX)
disassembly and the [research notes](../../../research/), FFT has **one** Ordering Table
(OT): every primitive — terrain, unit, effect, overlay — competes in one ~383-bucket
painter's-algorithm table. A primitive's bucket is the projected screen-space Z
(`OTZ >> 2`) of a single **representative point**, plus a per-primitive **`DepthMode`**
adjustment. We adopt that one model.

## Status

Accepted. Decisions 1–2 and 4–8 built; **decision 3 has six outstanding violations**, booked
as debt on `tools/check_depth_shaders.py`'s `BURN_DOWN` and tracked at #363.

Verified 2026-08-28 against the tree. The seam and its GDScript source of truth both live in
`addons/exmateria_schema/compositing_key/` since prologue pass 6 (ADR-0146); 21 shader files
`#include` the seam directly, and `tools/check_depth_shaders.py` walks 102 shaders green.

## Decision

1. **One shared shader function.** `psx_ot_depth(vec3 point, mat4 proj, mat4 to_view,
   int mode)` computes reversed-Z `DEPTH` for every battle primitive. The GDScript oracle
   mirrors it as `DepthMode.ot_depth(point, proj, view, mode)`.
2. **It is defined once**, in
   `addons/exmateria_schema/compositing_key/psx_ot_depth.gdshaderinc`.
3. **Each shader calls it from `vertex()` into a varying** and writes `DEPTH =` that varying
   in `fragment()` — no inline epsilon, no ad-hoc projection. A shader that genuinely cannot
   use the seam carries a `psx-ot-depth-exempt: <reason>` marker, which the guard treats as a
   permanent sanctioned opt-out; three screen-space ortho UI quads (`vitals_bar`,
   `vitals_sprite`, `menu_cursor_shadow`) hold one.
4. **The representative `world_point` is sourced per mesh granularity**, and granularity is
   **primitive count, not node-ness**. "Its own `Node3D` ⇒ one representative point" is
   false: a 3D projectile is one node but a multi-face ensemble. Multi-face meshes take the
   per-face `CUSTOM0` centroid path; single-primitive meshes take the per-object
   `MODEL_MATRIX[3].xyz` path. The `mode` is FFT's `DepthMode`.
5. **The single GDScript source of truth** for the modes and the calibration is
   `addons/exmateria_schema/compositing_key/DepthMode.gd`.
6. **Occlusion and fold order are two derived keys, not one value.** The compositor needs
   depth for two different jobs and they are different quantities. *Occlusion* is the
   reversed-Z NDC `ot_depth`, hardware-tested against the opaque depth buffer — "does
   map/unit geometry hide this effect pixel?" *Fold order* is which transparent prim blends
   on top, and it needs a **sortable** key: the **linear view-space Z**
   (`DepthMode.ot_order_z`), bucketed at `UNITS_PER_OT_BUCKET`. Sharing one reversed-Z NDC
   value for both collapsed every combat prim into a single bucket (#212), because the
   reversed-Z NDC range for the combat ortho camera is not `[0,1]`. Same model and
   calibration underneath; two keys for two purposes.
7. **Within a bucket, order is particle age: the newest-spawned prim sorts LAST and folds
   ON TOP.** `OTDepthPrimOrder` (`src/effects/`) resolves equal-depth prims this way, and it
   is ROM-grounded — it mirrors PSX's double head-insert (`AddPrim` @ `0x80023bb4`: the
   display list is head-inserted at spawn, then walked head→tail with each node
   head-inserted into its OT bucket), so the newest particle draws last within a bucket.
   This is load-bearing, not incidental: for DEMI (E046) every particle is `PULL_FORWARD_8`,
   so `depth_mode` does not separate the additive from the subtractive prims — they tie in
   one bucket and age is the entire order, which is what keeps a white additive prim on top
   of a black subtractive one. The age key is a secondary counting-sort pass (stable LSD
   radix: age pass, then depth-bucket pass); with ages absent it falls back to submission
   order, harmless because same-direction saturating blends commute.
8. **Occlusion depth is computed with the renderer's reversed-Z projection, which exists
   only on the render thread**, as `RenderSceneData.get_cam_projection()` (near → 1,
   far → 0 — the same scale as Godot's opaque depth buffer).
   `Camera3D.get_camera_projection()` returns the **standard** projection (near → −1,
   far → +1; a mid-scene combat prim reads ≈ −0.77), the wrong scale to compare against the
   depth buffer. They are two different matrices for the same camera, by Godot's design.
   Probe-verified 2026-07-20. **Consequence: occlusion depth cannot be precomputed on the
   CPU** and packed into a prim record, because the main thread only has the standard
   projection. That is the load-bearing reason the GPU copy of the formula cannot fold into
   the GDScript one.

## Considered options

- **One model — representative point + `DepthMode`, world-space bias, ROM-derived modes
  (chosen).** Project one point per primitive to reversed-Z `DEPTH`; bias by a small fixed
  set of ROM-grounded modes. Chosen because the disassembly shows this *is* what FFT does,
  so it retires the three-mechanism split and the un-anchored epsilons at the root rather
  than tidying them.
- **Two regimes — per-face vs per-object as distinct depth systems (rejected).** The
  architecture review's first framing: a `CUSTOM0`-centroid system for the map and a separate
  world-position system for sprites. Rejected once the disassembly was read: `AVSZ4` (a
  quad's 4-vertex Z average) *is* a centroid, and a sprite's object point *is* its
  representative point — the same formula fed different points. The difference is mesh
  granularity, not two models.
- **Keep biases as reversed-Z NDC epsilons (rejected).** An NDC epsilon cannot be derived
  from the ROM's OT-bucket offsets, is resolution- and projection-dependent, and is the exact
  form that produced the scattered hand-tuned hacks. A world-space distance is convertible
  from the ROM and projection-independent.
- **Bake the per-effect bias distance in the parser (rejected).** The OT-bucket↔world
  relation has **no closed-form fixed-point divisor** the way position
  (`÷ FFT_UNITS_PER_TILE = 28`) and velocity (`÷ 4096`) do — it passes through the camera's
  `ZSF`, which squashes the scene depth range into the 383 buckets. It is a **calibration**,
  not a fixed-point conversion, so it does not belong with the parser's exact conversions.
  The mode *index* already implies the bias, so per-effect baking is also redundant.
- **Derive the calibration analytically from our camera (rejected).** Computing
  `UNITS_PER_OT_BUCKET` from our camera's near/far so 383 buckets map exactly to our depth
  range is false precision: our isometric camera is not FFT's GTE, so the ROM bucket counts
  will not map 1:1 regardless. An empirical anchor plus visual tuning is honest about that.
- **Consolidate the GDScript and GPU copies by CPU-packing depth into a free prim-record
  slot (rejected, retired).** Blocked by decision 8 — the main thread does not have the
  reversed-Z projection. The dead `_frame_proj` staged for it, orphaned when #212 moved the
  fold key to `ot_order_z`, was deleted. See
  `research/working_documents/COMPOSITOR_OT_BUCKET_WIDTH_PARITY.md` §5b.
- **Reverse-submission as the within-bucket key (rejected, superseded).** The earlier #214
  rule put the first-*staged* prim on top, which is wrong once staging is emitter-grouped
  rather than spawn-ordered. Age is the correct, spawn-faithful key. See
  `research/working_documents/DEMI2_E046_ADDITIVE_SUBTRACTIVE_ORDERING.md` and
  `COMPOSITOR_DEPTH_ORDERED_FOLD.md`.

## Consequences

- **The representative point, and the tri/quad question.** FFT's GPU draws both 3- and
  4-point polygons, using `AVSZ3` for tris and `AVSZ4` for quads — one `OTZ` per polygon
  either way. Our Godot meshes are **triangles**, and a PSX quad is split into two. We do
  **not** reconstruct quads at render time. At export time
  (`tools/fft_exporter/exporters/geometry.py`) the centroid of the *original* polygon is
  computed and the **same** centroid is baked into `CUSTOM0` on **both** child triangles of a
  split quad, so both project to identical depth and sort as one unit, reproducing `AVSZ4`.
  `psx_ot_depth()` is therefore **tri/quad-agnostic** — it projects whatever point `CUSTOM0`
  carries and never knows the polygon's vertex count. This is the original reason `CUSTOM0`
  exists: default per-vertex depth z-fights along the split-quad diagonal.
  - **Per-face path** (`CUSTOM0` centroid): the map mesh (`VisualGeometryIndex` /
    `DynamicGeometryBuilder._build_surface_arrays`), multi-face callback meshes, and 3D
    projectile ensembles (`ProjectileMeshBuilder`, drawn by
    `projectile_vertex_color.gdshader` in `STANDARD` mode — a `ShaderMaterial`, not
    `StandardMaterial3D`).
  - **Per-object path** (`MODEL_MATRIX[3].xyz`): unit sprites, effect particles (a
    `QuadMesh` billboard), tile overlays, single-quad callbacks, billboard sprite
    projectiles (`projectile_sprite.gdshader`), and placeholder primitives via
    `solid_ot.gdshader` — so no battle mesh keeps a `StandardMaterial3D` escape hatch.
  - **The AVSZ centroid rule is shared**, as two pure statics on `DepthMode`
    (`tri_centroid` / `quad_centroid`), called by the GDScript per-face builders
    (`EffectCallback._quad`, `ProjectileMeshBuilder`). The map still computes its centroid at
    export time in Python — a deliberate cross-language mirror, not a unifiable call site.
- **`DepthMode.Mode` has ten members, and six of them are the ROM's.** Modes 0–5 —
  `STANDARD`, `PULL_FORWARD_8` (−8 buckets), `FIXED_FRONT` (=8), `FIXED_BACK` (=0x17E),
  `FIXED_16` (=0x10), `PULL_FORWARD_16` (−16) — trace to the BATTLE.BIN switch at
  `0x801aa54c`. Modes 6–9 — `UNIT`, `TILE_OVERLAY`, `MAP_SKIRT`, `SHADOW` — are **project-side
  nudges** whose magnitudes (`UNIT_FORWARD` 0.13, a tunable `static var`;
  `TILE_OVERLAY_FORWARD` 0.05; `MAP_SKIRT_BACK` −0.02; `SHADOW_FORWARD` 0.05) are calibrated
  constants with no ROM bucket offset behind them. `SHADOW` carries a ROM *argument* — PSX
  inserts the shadow at the unit's own OT slot (`ot_base + unit[0x128] * 4`), so it projects
  from the sprite's representative point rather than its own ground origin — but its
  magnitude is still calibration. The one-model claim is unaffected: every mode feeds the
  same formula.
- **Relative vs fixed.** Relative modes shift the world point toward the camera by
  `bucket_offset × UNITS_PER_OT_BUCKET` and re-project. Fixed modes ignore the point and
  write a near-extreme reversed-Z constant (`FIXED_FRONT_DEPTH` 0.9999, `FIXED_16_DEPTH`
  0.9990, `FIXED_BACK_DEPTH` 0.0001), exposed as tunable uniforms so `DepthDebugScene` can
  confirm their ordering.
- **The reversed-Z inversion lives in exactly one conceptual place.** FFT's OT convention is
  inverted from Godot's: in FFT a *higher* bucket draws *first* (behind); in Godot's Forward+
  reversed-Z `DEPTH`, a *higher* value is *nearer* (front). This is the single most
  error-prone fact in the system and the source of past sign mistakes. `psx_ot_depth()`
  translates FFT mode semantics → Godot reversed-Z internally, so no call site ever reasons
  about it. That ownership is the deepening: a small interface (`mode` + a point) over the
  one confusing fact.
- **Two textual copies of the formula, one calibration.** `DepthMode.ot_depth` (GDScript) is
  the readable spec and has **no production caller** — since the #212 split it survives as the
  CPU oracle the GPU copy is unit-tested against. `psx_ot_depth.gdshaderinc` is the copy that
  fills Godot's real depth buffer. They agree because the *calibration* is single-sourced from
  `DepthMode` through the uniform defaults `DepthMode.apply()` pushes. A third copy once
  existed — a raw-RD GLSL hand-port in `combat_displayspace_composite.glsl`, which could not
  `#include` the Godot-shader-language seam — and was retired with the GLSL compositor
  (#228 Phase 3). Its replacement, the engine-fold, draws effect prims through
  Godot-shader-language materials (`effect_fold_add` / `effect_fold_mix` / `effect_fold_sub`,
  which reach the seam via `effect_particle_fold.gdshaderinc` → `effect_particle_stp.gdshaderinc`
  and write `DEPTH = psx_ot_computed_depth`), so it is covered by the shader copy rather than
  being a fourth one.
- **`UNITS_PER_OT_BUCKET` is a calibration, and four things derive from it.** It is anchored
  to the research bridge (8 buckets ≈ 1.5 tiles → **0.19** Godot units/bucket, since 1 tile =
  1 Godot unit = `FFT_UNITS_PER_TILE` = 28 FFT units) and tuned once in `DepthDebugScene`. It
  is a render-side constant on `DepthMode` — deliberately **not** in the parsers, which do
  only exact fixed-point conversions; the parsers keep emitting the `depth_mode` *index*
  per-frame via `ParticleAnimator`. Four derivations hang off it: `ot_depth` (raster
  occlusion), `ot_order_z` (fold order), `render_layer_order_for` (the ADR-0074 render-layer
  rank, `round(order_z / UNITS_PER_OT_BUCKET) * RANK_STRIDE + rank`), and `rung_z`.
- **`Layer priority` is a separate axis and is untouched.** The paint order of a single
  unit's own layers (`TYPE1` / `WEP1` / `EFF1` / text) comes from the ROM's
  `layer_priority.json` (BATTLE.BIN `0x80094548`, 24 variants, loaded via
  `AnimationDatabase.LAYER_PRIORITY_PATH`) and is wired into `unit_sprite_body.gdshaderinc`
  as `uniform int[4] priority`. It decides intra-unit layer stacking, not scene-wide draw
  order, and is not folded into OT depth.
- **Prior art: `TacticsTemplateG`.** A sibling project already moved its per-object shaders
  onto a shared `psx_depth_common.gdshaderinc` plus a typed `VfxConstants.DepthMode` with the
  same ROM-named modes and a camera-direction world-space bias — the model this ADR adopts.
  We improve on it in two ways: TacticsG's include centralizes the *uniforms* but each shader
  still copy-pastes the bias `if/else` into its `vertex()`, where ours exposes a *function*;
  and we keep the per-face `CUSTOM0` path for the map rather than forcing the map onto
  per-object depth.
- **Vocabulary.** `CONTEXT.md` carries `Ordering Table depth`, `Depth mode`, and `Layer
  priority` under a "Rendering depth" cluster, so the one-model framing and the
  depth/priority distinction are named rather than re-derived.
- **Not part of `bootstrap_assets.sh`.** The include, the `DepthMode` script and the
  calibration constant are hand-authored render code, not ISO-derived assets. The
  `depth_mode` *index* in extracted effect data remains an ISO-derived value the parser emits.
- **Supersedes ADR-0015 for folded effect prims.** [ADR-0015](0015-particle-draw-order-uses-godot-native-sort.md)
  routed transparent particle draw-order through Godot's native transparent-queue sort
  (`sorting_offset`). For the effect prims the compositor folds, decisions 6 and 7 replace
  that; ADR-0015 records itself as accepted-as-amended, with native sort still governing
  opaque and non-compositor draws.

## Verification

- **`tools/check_depth_shaders.py`** is the enforcement net, run from
  `tests/run_all_tests.sh`'s pre-flight. It walks 102 shaders and asserts every `.gdshader`
  that writes `DEPTH` `#include`s the seam and writes only `DEPTH = <the varying>`. Its walk
  roots come from `classify_blueprint.WALK_ROOTS` (ADR-0147/#354 — a guard root that does not
  follow the refactor's output loses coverage silently), and per ADR-0146 dec. 8 it resolves
  the `#include` target to a real file, so a stale path cannot satisfy the guard while
  compiling to nothing.
- **Decision 3's six violations** — `changejob_cylinder_fold`, `formation_band_fold`,
  `formation_box_fold`, `formation_box_sub_fold`, `formation_orb_rim_fold`,
  `formation_shadow_fold`, all in `src/ui3/shaders/`, all writing `DEPTH = fold_depth` (the
  ADR-0077 materialized rung Z). They are on the guard's `BURN_DOWN`, which ratchets **both
  ways**: a new violation anywhere fails, and a listed entry that no longer violates also
  fails, forcing its removal. **The list makes no claim about which they are.** Each is
  either an exemption owed a marker — their same-directory neighbours `vitals_bar`,
  `vitals_sprite` and `menu_cursor_shadow` have the identical rung-Z rationale and took one —
  or real debt to route through the seam. Working them means deciding *exempt* or *route*
  per file and deleting the line. Tracked at #363; the list emptying is the chart.
- **`tests/DepthModeTest.gd`** is the CPU oracle's guard: the fixed-mode constants, the
  relative-mode direction, and `tri_centroid` / `quad_centroid` as AVSZ3/AVSZ4 including
  order-independence. It is what single-sources the calibration now that the GLSL copy is
  gone.
- **`tests/OTDepthPrimOrderTest.gd`** guards decision 7 in both directions:
  `_test_prim_order_age_tie_break` (newest folds on top, and symmetrically when the
  subtractive prim is the newer one — age is the key, not blend direction) and
  `_test_prim_order_depth_separates_over_age` (a bucket-separating Δz beats age).
- **`DepthDebugScene`** (`assets/scenes/DepthDebugScene.tscn`) is the visual/calibration
  regression, run **headful** per project rule.
