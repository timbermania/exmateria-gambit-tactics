---
status: accepted
---

# Flat UI scenes materialize render order into real depth to join the fold contract

## Status

Accepted.

Verified 2026-08-28 — decs. 1–7 built. `FormationScene` materializes its whole
`RP_*` ladder through `DepthMode.rung_z()` against the shared
`DepthMode.UNITS_PER_OT_BUCKET := 0.19`; `FOLD_PRIMS` carries **six** fold prims
and `FormationFoldRoutingTest` asserts the table covers exactly six; membership
is gated on `Fold.owns()` (`FormationScene:1726`, `:2104`) with the pick
delegated to `Fold.shader(fold, scene)`; the bespoke composite, both its `.glsl`
shaders and `use_displayspace_composite` have no declaration left in the tree;
and `DetailScene._add_frame` / `_mount_icon` take a default-less `z_rung` under
`tests/DetailUnauthoredDepthTest.gd`.

## Context

The formation / party-roster screen (`FormationScene`) was a flat
**orthographic** overlay: every primitive sat at world z=0 with depth writes and
depth test **off** (`depth_draw_never` / `depth_test_disabled`), and draw order
was an abstract painter's ladder on `render_priority` (`RP_BACKGROUND=0` …
`RP_HEADER_LABEL=10`, since grown to `RP_CHANGEJOB_CYLINDER := 15`). It was "2D
pretending in 3D," and the `render_priority` ladder was the workaround for
having no depth to sort by.

Its two PSX display-space effects — the additive orb **halo** and the 4-add /
4-sub **gold selection box** — were drawn by `FormationDisplaySpaceComposite`, a
**Mobile / Godot-4.6-era** `POST_TRANSPARENT` `CompositorEffect` that copied the
color layer to a scratch and blended each element in sRGB display space. It also
did `cam.compositor = comp`, **overwriting** the camera's compositor — fighting
the global `CompositorAutopilot` autoload that attaches the engine fold
(ADR-0074) to the active camera in every scene.

On the 4.8 Forward+ compositor fork — the only supported engine
([`godot-fork-only`]) — that Mobile-era pass no longer does its job, so the halo
and the gold box **silently vanished**. The scene was off the unified rendering
contract combat had already moved onto: OT depth (ADR-0009) + the display-space
fold (ADR-0074).

## Decision

**A flat ortho UI scene joins the unified contract by materializing its
`render_priority` ladder into real distance-from-camera depth.** Concretely:

1. **Depth, not paint order.** Each `RP_*` rung is a real world-space Z
   (background farthest → header nearest), one rung per **OT bucket**
   (`≥ UNITS_PER_OT_BUCKET`, 0.19 world-units, the shared `DepthMode` constant —
   not a scene-local copy). Because the camera is orthographic, that Z *is* the
   view-space `order_z`. `rank` is reserved only for genuinely coincident prims
   (the 8 glide-trail box slots).
2. **One depth source drives everything.** Opaque prims (floor, orb core, unit
   body, sort text, header chrome) **write `DEPTH`** through the same `DepthMode`
   reversed-Z the fold uses. The fold's paint order
   (`DepthMode.sorting_offset_for(order_z, rank)`) **and** the
   opaque/transparent occlusion (box **under** body, orb-rim **over** body) both
   fall out of that single Z — no `render_priority`, no per-shader magic depth.
3. **Fold membership stays deliberate.** Depth gives *ordering*, not *membership*
   (ADR-0074: folding is a material property). Each PSX add/sub prim wears a
   **monomorphic `*_fold` shader** and is handed to `Fold.add`; the opaque prims
   write depth and render in-scene, and are **not** folded. The set is
   `FOLD_PRIMS`: box-add, box-sub, orb-rim, unit-shadow, vitals-band, and the
   Change-Job commit cylinder (`changejob_cylinder`) — a prim that lives for four
   seconds and takes the identical per-prim decision. Adding it needed no
   amendment, which is the seam working.
4. **The autopilot owns the camera.** `FormationScene` does not set
   `cam.compositor`; `CompositorAutopilot` owns the fold as it does elsewhere.
5. **Graceful off-fork fallback.** Membership is gated on `Fold.owns()`, and
   `FormationScene.fold_shader_for` hands each `FOLD_PRIMS` entry to
   `Fold.shader(fold, scene)` for the pick (ADR-0191 dec. 2, which moved this
   predicate into the `Fold` kernel and deleted the
   `CompositorAutopilot.owns_compositing()` the rule was first written against).
   Fork + Forward+ → `compositor_fold` materials + `Fold.add`; otherwise → the
   in-scene `blend_add` / `blend_sub` materials (the callbacks / cursor / crystal
   pattern). A non-fork boot degrades to slightly-wrong-but-present, never blank.
6. **The bespoke path stays retired.** `FormationDisplaySpaceComposite`, its two
   `.glsl` shaders (`formation_composite_copy.glsl`,
   `formation_displayspace_composite.glsl`) and the `use_displayspace_composite`
   flag are gone, and none of them comes back: a re-port is the rejected option
   below, not a shortcut.
7. **No unauthored depth.** A prim only gets the ladder's benefit if it *names* a
   rung. The `z_rung = −1` floor sentinel — and rung-less `screen_to_world`
   placement — is the "nobody decided" case and is **banned for any
   depth-writing UI prim**; rung 0 (`RP_BACKGROUND`) stays legal as the *authored*
   back. Enforced twice: the mount API takes a mandatory rung
   (`DetailScene._add_frame` and `_mount_icon` declare `z_rung` with **no
   default**, so "unauthored" is unspeakable), and a red-capable guard asserts no
   depth-writing UI prim resolves to the sentinel. The guard keys on the
   **authored** rung (`set_meta("z_rung")`), not the runtime world-Z, because
   off-fork every rung collapses to Z=0 and container/origin nodes legitimately
   sit at local Z=0. In `DetailScene` the stats sub-panel therefore rides the
   lower panel's near ladder — chrome at `RP_WINDOW_FRAME`, glyphs at `RP_TEXT`,
   **text strictly nearer than the frame** so the opaque frame does not occlude
   its own glyphs (the naive one-rung lift of the frame alone blanks the window).

## Why

The scene's own author's framing is the decision: *materialize render order into
real depth, and the unified buffer falls out.* Once every prim has a genuine
distance-from-camera, the two things the old ladder faked — blend order among the
transparents and occlusion against the opaques — are just the depth system and
the fold doing their jobs. There is then nothing scene-specific left to maintain:
formation is on the same OT-depth + fold contract as combat, so it inherits the
display-space PSX clamp for free and can never again silently lose its effects to
a renderer swap.

Monomorphic formation-specific fold shaders (rather than reusing the generic
particle `effect_fold_*` or the `cursor_fold_*` set) are forced by ADR-0074: the
formation prims are **paletted with a per-prim gouraud level and UV mirror**, and
sharing a shader across those axes would require the data-driven axis branching
ADR-0074 exists to forbid.

Decision 7 is the other half of the same idea. Materializing depth buys nothing
for a prim that declines to pick a rung, and the failure is invisible until
something moves: an opaque frame parked at the floor is occluded by distance, not
by opacity, so once the full-width vitals band became F3-draggable
(`VBAND_TOP_OUT` / `VBAND_BOT_OUT` are live tunables) dragging it down over a
floor-parked stats window let a fold prim at `RP_VITALS_BAND + offset` composite
**over** it and darken it. The rule forces the author to confront the depth;
choosing one nearer than any overlapping band is the correctness step it does not
itself guarantee. See the CONTEXT.md **Unauthored depth** glossary entry.

## Considered options

- **Make the Mobile composite run on the fork.** Port
  `FormationDisplaySpaceComposite`'s two-pass copy/blend to Forward+. Rejected:
  it keeps formation as a bespoke `CompositorEffect` off the shared contract,
  duplicating what the engine fold already does, and re-earns the exact "vanishes
  on the next renderer change" fragility. This is the `CombatDisplaySpaceComposite`
  that #228 / ADR-0074 already retired.
- **Keep `render_priority`, fold only the two broken prims.** Bolt the halo and
  box back onto the fold while leaving the rest of the scene depth-off. Rejected:
  the fold seeds its scratch with the *entire* opaque scene and depth-tests
  transparents against the opaque depth buffer — with the body still depth-off,
  the gold box can't be pushed *behind* it. Partial depth doesn't compose.
- **Keep the flat scene, write synthetic per-shader `DEPTH` constants.** Leave
  geometry coplanar and hand each shader a hand-picked reversed-Z. Rejected:
  depth becomes a magic number duplicated in every shader and in the `Fold.add`
  `order_z`, two things to keep in sync — against the "one geometric source of
  truth" the real-Z ladder gives.

## Consequences

- Six monomorphic `compositor_fold` shaders — `formation_box_fold`,
  `formation_box_sub_fold`, `formation_orb_rim_fold`, `formation_shadow_fold`,
  `formation_band_fold`, `changejob_cylinder_fold` — alongside their in-scene
  twins kept as the off-fork fallback.
- Every opaque formation prim carries a `DEPTH` write from its rung's Z; the
  `RP_*` constants are a **depth ladder** (a Z per rung), not a `render_priority`
  ladder. The opaque depth write and the fold's `DEPTH` share one reversed-Z
  convention — this was the top build risk and is the one thing that does *not*
  fall out for free.
- `FormationDisplaySpaceCompositeTest` went with the class it tested. The four
  surviving mentions of the retired names are historical prose (shader headers,
  `FormationFoldRoutingTest`, a comment at `FormationScene:769` recording that
  the composite used to clobber the camera).
- The pattern generalizes: any flat ortho UI scene that needs PSX display-space
  effects joins the fold the same way — materialize its paint order into depth,
  then choose membership per prim.

## Verification

- `tools/check_depth_shaders.py` — dec. 2's seam corpus-wide: every `DEPTH` write
  goes through `psx_ot_depth.gdshaderinc` or carries an explicit greppable
  exemption.
- `tools/check_compositor_routing.py` and `tools/check_no_pow_in_fold.py` — the
  fold contract dec. 3 and dec. 5 join.
- `tests/FormationFoldRoutingTest.gd` — the routing guard generalized from
  `CallbackFoldRoutingTest`: dec. 3's membership on **both** branches
  (folded → the `*_fold` variant, off-fork → the in-scene twin), the table's
  exact six entries, and the opaque-prim invariant (no `ALPHA`, no
  `depth_draw_never` / `depth_test_disabled`) that dec. 2 needs.
- `tests/DetailUnauthoredDepthTest.gd` — dec. 7, keyed on the authored
  `set_meta("z_rung")`. Its docstring records which slices were red before the
  migration, so it is a guard proven to fire.
- Dec. 6 has **no** guard: nothing asserts a retired path stays retired. The
  writable arm is an assertion that `FormationDisplaySpaceComposite`, both
  `.glsl` files and `use_displayspace_composite` have no *declaration* anywhere
  (prose mentions are fine). It would pass today.

### Two traps this scene pays for

- **Assigning `ALPHA` at all opts a spatial material into the TRANSPARENT
  pipeline** — even `ALPHA = 1.0`. Such a prim renders *after* the fold's
  `PRE_TRANSPARENT` seed and never lands in the scratch, so folded prims
  composite over the flat clear-color (obvious wherever a fold prim has a filled
  footprint, hidden behind a thin rim). Opaque formation shaders must not write
  `ALPHA`; they stay opaque via `discard` of transparent texels. Dumping the
  scratch to a PNG (resolve pass without the coverage discard) is the fastest way
  to see a seed hole.
- **`depth_draw_always, depth_test_disabled` is a Vulkan no-op**, not an
  "always on top": the spec disables depth *writes* whenever the depth *test* is
  disabled, so such a prim never lands in the shared depth buffer and folded
  prims composite straight over it. This is why the shared `UIUnitInfoWindow`
  vitals panel is depth-test + depth-write **enabled** — its `vitals_sprite` /
  `vitals_bar` are opaque, occluded by real camera-Z, and its sub-elements are
  ordered by a small intra-panel Z ladder
  (`UIUnitInfoWindow.Z_BAND` / `Z_PORTRAIT` / `Z_BAR_TRACK` / `Z_BAR_FILL` /
  `Z_TEXT`), not `render_priority`.

See ADR-0009 (one depth model), ADR-0074 (fold is a material contract),
ADR-0191 (the `Fold` kernel owns the predicate), and the CONTEXT.md **Depth
ladder** glossary entry.
