# The fold resolves every pixel, because the PSX framebuffer was 15-bit screen-wide

The display-space fold's Pass C carried a **coverage mark** — "did a carrier draw on this
pixel?" — and `discard`ed when the answer was no, so the untouched 3D background kept its
full precision. [#1257](https://github.com/timbermania/fft-monorepo/pull/1257) found the
mark could answer WRONG (a half blend over a subtractive prim discarded both) and fixed the
answer. The review asked the better question:

> this sounds like something that needs a more fundamental fix

> why do we even need a "something drew here" [mark] with the fold now?

**We do not.** The mark is deleted. Pass C resolves every pixel and the whole screen is
crushed to RGB555, which is what the hardware `Render` is imitating actually did.

## Status

accepted

## Context

The bracket is three passes (ADR-0074, ADR-0080). Pass A seeds the display-space
accumulator from the opaque scene colour; Pass B is the engine's held-out
`compositor_layer` pass, where carriers blend with hardware add/sub/mix; Pass C reads the
accumulator back into the linear colour layer, converting display→linear and quantizing to
`FoldSurface.quantize_levels` (31.0 = RGB555, a policy the bracket is given — ADR-0152).

Pass C also decided **which** pixels to write. Coverage lived in the accumulator's ALPHA,
seeded to a **0.5 baseline** rather than 0 because Godot's `blend_sub` drives alpha DOWN
(`REVERSE_SUBTRACT`) while add/mix drive it UP; "touched" was `abs(a - 0.5) > 0.1`.

Three things are true about that mark, and each was measured for this decision rather than
argued:

**(a) It cannot be computed from what Pass C can see.** The alpha test is not injective. A
`blend_mix` carrier maps `a_dst -> a_src + a_dst*(1 - a_src)`, so a mix whose own alpha IS
the baseline, landing on a pixel a sub carrier already drove to 0, returns
`0.5 + 0*(1 - 0.5) = 0.5` — the untouched value, bit for bit. Live that pair is **{76} Dark
Screen**'s half blend (ALPHA 0.5, fold rung 0, so it paints after every world-space member,
whose order key is a negative view-space Z) over a unit's **`blend_sub` ground shadow**: both
contributions were discarded, the shadow's footprint came back as the raw undrawn scene, and
the shadow appeared to **LIGHTEN** the brown overlay instead of darkening it. No baseline
fixes it — every `B` in `[0,1)` is the fixed point of some mix alpha — and the carriers blend
into the only channel a mark could live in. #1257's remedy was to ask the COLOUR too (bind
Pass A's seed at binding 1 and treat "the display value moved" as touched), which is correct
and still a derived signal: a carrier that paints its own background back reads as untouched,
and every future blend mode has to be re-checked against it.

**(b) The carve-out it implements is not the PlayStation's.** The PSX framebuffer was 15-bit
for the WHOLE screen — terrain, sprites and effects alike. Sparing the 3D background from the
crush was the infidelity, and the mark was what preserved it. ADR-0117 dec. 6 and ADR-0150
both say `Render` **is** the PlayStation look, and ADR-0152 dec. 2 makes 31.0 the default
because "changing it is a known drop and owes a register entry." **The carve-out was never an
ADR decision at all** — it entered as a property of `proto_ordered_fold` ("only touch effect
pixels") and survived in this tree as a comment in `foldsurface_resolve.glsl`, cited by
nothing.

**(c) Deleting it costs 4/255 and does not band.** Measured on ONE real Orbonne battle frame
(1024x960, captured on a stopped world via the `--battle=3` route) and measured INTRA-FRAME —
the frame against itself snapped to the lattice — because a frame-to-frame A/B here is void
(see the box below). **88.15% of pixels move, 79.21% of channel samples move, worst 4/255,
mean 1.364/255**; the deltas are 41.35% at 1/255, 20.18% at 2, 16.08% at 3 and 1.60% at 4.

Banding was the one real objection — a smooth gradient snapped to 32 levels shows contour
bands — and it is a SPATIAL claim, so it was measured spatially: how long is the longest run
of one identical colour down a scan line?

| | mean run | longest run | distinct colours |
|---|---|---|---|
| whole frame, before → after | 3.59 px → **3.68 px** | 151 px → 151 px | 3261 → 854 |
| sky (the smoothest large region) | 3.87 px → **3.90 px** | 16 px → 33 px | 310 → 60 |
| **CONTROL** — synthetic 8-bit gradient | 3.48 px → **28.00 px** | 4 px → 32 px | 161 → 20 |

The control is what makes the two rows above it mean something: the same instrument reads an
**8×** mean-run increase on a surface that must band. The frame reads +0.8%. Its sky's longest
single run does double, 16 px → 33 px, which is reported rather than smoothed over — but a
mean that does not move is not banding, it is one run that happened to merge. This frame is
dithered ROM palette art and has no smooth long-range gradient for a band to form in.

> **🔴 A FRAME-TO-FRAME A/B DOES NOT WORK HERE, and this was measured twice.** Diffing two
> live captures one shader apart reports **worst 240/255, mean 12.117/255** — nothing to do
> with a 5-bit snap. Two causes: Orbonne's rain streaks land in different places, and the
> camera swoop does not settle to the same framing between runs, so the units sit at different
> screen positions. (The handoff into this work recorded the same trap from a different pair:
> `max delta 255/255`, 81.7% of pixels moved.) **Every number above is therefore intra-frame**,
> and the one cross-capture claim used below — the fraction of channel samples sitting on the
> 5-bit lattice — is a quantity neither rain (~2% of pixels) nor a framing shift can fake.

## Decision

**1. Pass C has no coverage mark and no `discard`. Every pixel is resolved.**
`foldsurface_resolve.glsl` loses the alpha test. The whole screen round-trips display→linear
and snaps to `quantize_levels`. The fragment shader is four lines.

**2. The seed stops carrying a coverage channel.** `foldsurface_seed.glsl` wrote alpha
**0.5** as the "nothing drew here" baseline; it now writes **1.0**, the opaque alpha of a
display-space image. This is safe by construction, not by hope: none of the three hardware
blends a carrier can wear reads the DESTINATION alpha to compute a COLOUR, so the seeded
alpha was never an input to the fold — only to a coverage test that no longer exists.

**3. `FullscreenPass` grows no second sampled binding.** This ADR branches from `main`, not
from #1257, so the `seed_tex` binding, the `_source_texture_2` hook and the
`ResolvePass.seed_pass` wiring that PR added are not landed rather than landed-and-removed.
Both adapters want exactly one sampled texture, which is what the shared pass provides. The
diff against #1257 is therefore a strict simplification of it, not a partial revert.

**4. The 5-bit crush stays a policy, not a constant.** ADR-0152 is untouched:
`FoldSurface.quantize_levels` is still a `static var` read every frame into the push constant,
still defaults to 31.0, and `<= 0` still resolves at full precision. What changed is the
POPULATION it applies to, not who owns the level. A consumer that wants the display-space
fold without the crush sets 0.0 and now gets a full-precision round trip of the whole frame
rather than of the effect pixels only.

**5. `#1257` is superseded, not reverted.** It is the correct fix to the question "is this
pixel covered?" and it stays on the record as the measurement that killed the question. If
this ADR is ever reversed, #1257's shader is the fallback and its four-pixel guard is the
test.

**6. HDR headroom is not lost, because there is none.** Resolving every pixel clamps the
colour layer to `[0,1]` screen-wide (`srgb_to_lin(quantize(...))` clamps). That would matter
if a post-process read values above 1.0; nothing does. `glow_enabled` appears in exactly one
file in the tree (`tools/proto_single_held_particle.gd`, a prototype), no `WorldEnvironment`
resource sets a tonemap mode, and every producer on this path is `unshaded` flat palette art.

## Considered options

**Option A — a real per-pixel mark in the STENCIL.** Keep untouched pixels pristine but stop
inferring coverage from a channel the carriers blend into: every carrier gains
`stencil_mode write, <ref>`, Pass C attaches the shared scene depth to its framebuffer and
tests the stencil instead of comparing colours.

**It is buildable, and that was PROBED rather than reasoned** — the probe and its verdicts are
recorded here because this is the expensive half of the question and a later session should
not re-derive it:

- `stencil_mode write` **works** on a `compositor_layer` member inside the engine's held-out
  pass. The fold pass's framebuffer is `get_cache_multiview(views, layer_texture,
  depth_texture)` — colour plus the shared scene depth — and `use_stencil` in
  `scene_shader_forward_clustered.cpp` is gated on `PIPELINE_VERSION_COLOR_PASS`, which the
  held-out pass uses. Measured: a marking carrier at screen-left produced 8,836 marked
  samples left / 0 right.
- **The stencil aspect IS cleared every frame**, including on the branch the risk analysis
  worried about. `render_forward_clustered.cpp` clears stencil explicitly only in the depth
  pre-pass (`DRAW_CLEAR_ALL`); the no-pre-pass branch clears depth only (`DRAW_CLEAR_DEPTH`).
  It does not matter: for a combined depth/stencil attachment `rendering_device.cpp` assigns
  `description.stencil_load_op = p_load_ops[i]`, the SAME load op as depth, and
  `DRAW_CLEAR_DEPTH` alone already maps the attachment to `ATTACHMENT_OPERATION_CLEAR` with
  `clear_value.stencil`. Measured both ways — a carrier marked at x=-1 for four frames and
  moved to x=+1 read 0 left / 8,742 right, and the same arm with
  `rendering/driver/depth_prepass/enable` forced false read identically. Controls: a no-carrier
  arm produced 0 marked samples (so the probe needs the mark), and the static arm produced
  marks only inside the carrier (so the probe is not blind).
- No fork change is needed. `RDPipelineDepthStencilState`'s full stencil surface is bound to
  GDScript (`enable_stencil`, `front_op_*`/`back_op_*`), `RenderSceneBuffersRD.get_depth_texture`
  is bound, and with MSAA off the scene depth is `D32_SFLOAT_S8_UINT`/`D24_UNORM_S8_UINT`.
  (With MSAA ON it would be: `get_depth_texture` returns the RESOLVED depth, which on Forward+
  is `R32_SFLOAT` and has no stencil aspect at all. MSAA is off in this project.)

**It is refused on cost and on fidelity.** The carrier population is **22 shaders**, not the
15 a first grep suggested — `assets/shaders/` was missed, and `crystal_fold`,
`tile_decal_fold`, `effect_callback_fold` and `cursor_fold_add` were absent from the list
while `feedback_hud_sprite_additive_fold` and `results_screen_add_fold` had no mention.
`check_compositor_routing.py` independently reports the same 22. (ADR-0147 measured
**sixteen**, quoted by `src/ui3/formation/FormationScreenIn.gd` — a correct count at the
time, and the population has grown by six since; the claim it supports, that `Render`
produces zero of them, still holds.) **Eleven of the 22
contain no `discard` at all**, including `effect_fold_add`/`_mix`/`_sub` — the textured PSX
effect-sprite carriers. A stencil mark writes on any fragment that is not discarded, so
without adding an alpha `discard` to those eleven the mark would cover each effect sprite's
entire QUAD and quantize a moving rectangle of background: a COARSER mark than the derived
one it replaces. And even done perfectly it implements context (b)'s wrong carve-out
faithfully.

**Option C — a different baseline, or a mark in another channel.** Refused as arithmetic: the
mix fixed point exists for every baseline in `[0,1)`, the `compositor_layer` primitive
allocates one texture per layer so there is no second attachment for a carrier to write, and
`blend_sub`'s reverse-subtract makes a 0 baseline lose subtractive coverage outright.

## Consequences

- The 3D background is now 15-bit like everything else. Measured cost above; by eye on the
  captured Orbonne frame the two are indistinguishable, and the amplified difference map is
  featureless noise rather than contours.
- **The whole `#1257` bug class is gone, not narrowed.** There is nothing left to be
  non-injective: no mark, no baseline, no comparison. A `blend_mul` carrier — none exists
  today — needs no analysis before it can be written.
- Pass C's fragment is four lines, and `FullscreenPass` stays a one-sampled-texture seam.
- `FoldQuantizePolicyTest` grows the new invariant on its existing local-RenderingDevice
  harness (charter clause 13): four pixels in one draw, two of them sitting exactly on the
  retired 0.5 baseline, a destination pre-filled with an out-of-range sentinel and a draw list
  that does not clear, so "was not written" is observable rather than inferred. It also loses
  both of its `charter_allowlist.tsv` rows by declaring `test-kind` and `seeded-break`.
- **VERIFIED END TO END, not only in the unit test.** Both arms captured in one sitting on one
  terrain build, one shader apart: main's shader leaves **20.79%** of channel samples on the
  5-bit lattice, this one leaves **98.41%**. The residual ~2% of pixels is spatially confined
  to rain streaks, the debug compass gizmo and sprite highlights — the TRANSPARENT pass, which
  draws after Pass C by ADR-0080's design and was never in scope; background, terrain and sky
  read **0.00%** off-lattice. By eye the sky, terrain and sprites are indistinguishable
  between the arms; the only visible difference in a side-by-side is where the rain fell and
  where the camera settled.
- **The live bug #1257 was opened for is fixed identically.** #1257's own two-carrier probe
  (`blend_sub` ALPHA 1 at a negative order key, then `blend_mix` ALPHA 0.5 at rung 0) reports
  `INSIDE 0.1974 / OUTSIDE 0.3834` on this branch — the SAME four decimals as #1257's fixed
  build, where the broken build read `INSIDE 0.6000`, the raw undiscarded seed. The
  sub-alone positive control is DARKER at 0.2588. One number moved and is the witness for
  this ADR rather than against it: the probe's untouched background went `0.6000` →
  `0.6118`, because the background is now on the lattice too.
- **Soft spot S0:** the shared asset hub regenerated all 142 `assets/maps/*/terrain.json`
  part-way through this work, which is why (c) was re-taken. Any measurement in this repo that
  spans more than a few minutes has to say which terrain build it stands on: these do — one
  build, captured after the regeneration. It also reds `tools/test_reference_goldens.py` for
  `monastery`/232 on **every** worktree, because the goldens' only drifting field is
  `/terrain/sha256`, a hash over the whole `terrain` object rather than over the
  `height_grid`/`impassable_grid` the snapshot shows (those two are byte-identical). That red
  is not this branch and not standing drift; it is a regeneration reaching every tree through
  the hub symlink.
- **Soft spot S1:** the measurement stands on ONE frame. It is a real battle frame on a
  stopped world, and the banding arm carries its own positive control, but a scene with a
  genuinely smooth long-range gradient — an authored sky, a fade, a lit interior — would band
  where this one does not. Both instruments are recorded on the PR and reproducible: a
  capture probe that boots Orbonne via `DebugConfig.battle_seek_root` and screenshots a stopped
  world, and an offline pass that snaps the PNG to the lattice and measures scan-line run
  lengths against a synthetic-gradient control.
- **Soft spot S2:** the caveat carried from the measurement is that the captured PNG is 8-bit
  post-viewport output standing in for the in-fold display value, so the 1/255 bucket may
  partly be the viewport's own rounding. The 3–4/255 buckets (17.73% of samples) are well
  clear of it.
- **Soft spot S3:** `addons/exmateria_effects/callbacks/EffectCallback.gd`'s comment explained
  routing callbacks into the fold as avoiding "Pass C's coverage-discard"; the routing is
  still right and the reason is restated, but it was already loose — Pass C runs
  PRE_TRANSPARENT, so what it did to a transparent-layer draw was composite over it, not
  discard it.

## See also

- [ADR-0074](0074-display-space-fold-is-a-material-contract-not-a-module.md) — the bracket and
  the material contract this pass belongs to.
- [ADR-0080](0080-the-fold-composites-pre-transparent-to-layer-modern-over-psx.md) — why Pass C
  sits before the transparent pass.
- [ADR-0152](0152-a-psx-compromise-is-a-policy-the-bracket-is-given.md) — the quantize LEVEL is
  a policy; this ADR changes the population, not the owner.
- [ADR-0150](0150-psxdisplay-stays-because-render-is-the-playstation-look.md) and
  [ADR-0117](0117-the-blueprints-ten-systems.md) dec. 6 — `Render` IS the PlayStation look,
  which is the whole of context (b).
- [#1257](https://github.com/timbermania/fft-monorepo/pull/1257) — the derived-signal fix this
  supersedes, and the two-carrier probe that proved the bug.
