---
status: accepted
---

# The fold composites pre-transparent so modern passes can layer over faithful PSX

## Context

The [display-space fold](../context/26-display-space-fold.md) (ADR-0074) currently
brackets the engine held-out pass across the **transparent** boundary: it seeds at
`PRE_TRANSPARENT` (`FoldSurface.gd:53`), the engine draws the carriers (Pass B)
**after the transparent resolve** (`render_forward_clustered.cpp:2523`), and resolves
back at `POST_TRANSPARENT` (`FoldSurface.gd:140`). So the folded PSX result is stamped
**over** the linear transparent pass.

That blocks the goal of **mixing regimes** — PSX-faithful effects that blend among
themselves (display-space add/sub/mix) with **modern** linear-alpha transparents
composited *over* them. Today a modern transparent in front of a PSX carrier is
clobbered by the binary coverage stamp, and that stamp was blended against a backdrop
(opaque-only) that never contained the transparent — the "stale backdrop / binary
stencil looks wrong" defect.

The v1 `CompositorRenderLayer` primitive hard-gates the held-out pass to
`POST_TRANSPARENT` in two places (`compositor_render_layer.cpp:108` setter;
`render_forward_clustered.cpp:2589` renderer). The `stage` field reserves an
"earlier stage" seam (plan Q4) — reserved **upstream for a different reason** (MSAA'd
held-out geometry), not for ordering.

## Decision

Move the fold's whole **seed → blend → resolve** bracket to **before the transparent
pass**: **seed + engine blend at `POST_OPAQUE`, resolve at `PRE_TRANSPARENT`** (see
[fold stage](../context/26-display-space-fold.md)). This is a **fork-local engine
change** — relax the `stage` gate and reposition Pass B to draw before the transparent
pass. Seed and blend share the `POST_OPAQUE` hook; the resolve is the separate, later
hook (Pass B runs between them, so the two userland ends must be distinct hooks).

Ship **depth-test-only**, exactly as v1: carriers are occluded by opaque geometry,
always sit under transparents, and do **not** occlude one another or later transparents.

## Why

Ordering is the load-bearing property. Only compositing the PSX layer into linear scene
color *before* the transparent pass gives it: modern transparents then draw over it with
correct linear alpha, and — because nothing renders between seed and resolve — the binary
coverage stamp is consistent with the backdrop it was blended against, so the stale-backdrop
defect **dissolves** rather than moving.

Two facts make this cheap **for this game specifically**: it runs **MSAA-off** (no
`msaa_3d` in `project.godot`), so the earlier stage carries none of the sample-count /
frame-anchor complexity upstream deferred it for; and it uses **no skybox**, so seeding at
`POST_OPAQUE` (before the sky draw) loses nothing — the backdrop is opaque + clear color
either way.

## Considered options

- **Seed the transparent pass into the scratch** (blend PSX against a transparent-inclusive
  backdrop). Rejected: it folds the modern transparents *into* the PSX add/sub math, in
  **display space** — destroying the "modern, linear" half of the goal — and doesn't fix
  ordering (resolve still lands post-transparent).
- **Scratch depth buffer + min-depth ("union") merge** so carriers occlude each other and
  later transparents. Deferred, not built: in the *reordered* position the same result is a
  **one-line depth-write flip** — let Pass B write the *shared* scene depth, safe because
  nothing but the transparent pass consumes depth after it. A separate depth target + merge
  is only warranted if the original scene depth must stay pristine, which pre-transparent it
  need not. YAGNI until a concrete artifact appears.

## Consequences

- **Occlusion limit (accepted):** a modern transparent *spatially behind* a PSX carrier
  shows *through* it (Pass B doesn't write depth). Fine while every modern transparent is
  meant to sit on top; the fix is the deferred depth-write flip above.
- **No inter-carrier occlusion**, unchanged from v1 — [fold order](../context/26-display-space-fold.md)
  (paint order) governs, not depth.
- **Diverges from the shipped v1 primitive** (which offers `POST_TRANSPARENT` only),
  widening the fork's gap with the upstream proposal. Upstreaming the earlier stage would
  still owe the MSAA path this game skips.
- **Implemented** — the engine relaxes the `stage` gate to accept `POST_OPAQUE` (resource setter +
  renderer) and draws the held-out Pass B parameterized by consume stage: `POST_OPAQUE` layers before the
  transparent pass, `POST_TRANSPARENT` layers after the resolve. The game's `FoldSurface` seeds at
  `POST_OPAQUE` / resolves at `PRE_TRANSPARENT`, and `fold_layer.tres` sets `stage = POST_OPAQUE`. Verified
  windowed: a modern linear-alpha transparent layers over the folded PSX carrier (clobbered pre-fix),
  add/sub/mix round-trips still pass, and the real Formation scene renders unchanged.
