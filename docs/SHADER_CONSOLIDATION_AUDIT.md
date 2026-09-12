# Shader consolidation & unification audit

**Repo:** `godot-learning` (branch `compositor-displayspace-blend`)
**Date:** 2026-07-21
**Scope:** analysis only. Confirms the three "we unified X" claims, then ranks the
consolidation wins, drift risks, and deletions. WIN A + the dead-code deletion are
mechanical; everything else needs a decision or effect-parity gating before code moves.

> **Update (#228 Phase 3, 2026-07-29):** the raw-RD GLSL display-space compositor named
> throughout this snapshot — `CombatDisplaySpaceComposite` / `CombatCompositeDriver` and
> `combat_displayspace_composite.glsl` — was **retired**. Effect compositing now runs through
> the engine-fold (`FoldSurface` + `EngineFoldCompositor`, driven by the `CompositorAutopilot`
> autoload) on the Forward+ 4.8 fork. Read the compositor claims below as of the snapshot date:
> the fold *mechanism* moved, but the ADR-0040 packing / ADR-0009 depth conclusions still hold.

Census: **40 prod `.gdshader`** (`assets/shaders/` + `src/ui3/shaders/`), **4 probe**
`.gdshader` (`tools/probe_shaders/`, retired effect-particle modes), **1** prototype ramp,
**14 `.gdshaderinc`**.

---

## The three claims — verdicts

### 1. "Unified depth framework via a shader import" — ✅ CONFIRMED (correctly scoped)
One include, `addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc`, holds the single reversed-Z
function `ot_depth(point, proj, to_view, mode)`; the near=1.0/far=0.0 inversion lives
in exactly one place. Modes map to `addons/exmateria_schema/compositing_key/DepthMode.gd` (authoritative). Governed by
ADR-0009; recent commits (`070ccae54`, `6753fe755`) added the view-Z `ot_order_z` fold key
and §5b occlusion resolution.

**Nuance (not a defect):** unification is *among OT-depth writers*. Every UI/screen/formation
overlay deliberately opts out with `depth_draw_never` + `depth_test_disabled`. This is correct
scoping — verified: `darkscreen_mosaic`, `screen_color_mode*`, `show_graphic*`, `show_map_title*`,
and all of `src/ui3/shaders/formation_*` disable depth. **Record it so nobody "unifies" a
screen-space overlay into OT depth.**

### 2. "Unified 11 color modes via a shader import" — ⚠️ CONFIRMED for the fold, but there is DEAD parallel machinery
- `addons/exmateria_schema/colour_model/color_stack.gdshaderinc` is the real, working seam: the 11-mode ColorStack
  fold `color_apply(base, surface_id)`, CPU source `addons/exmateria_schema/colour_model/ColorStack.gd`, ADR-0067. The
  guard `tools/check_color_shaders.py` enforces exactly this include. **Callers: 5** — `unit`,
  `indexed_color`, `screen_background`, `formation_unit`, `tests/color_stack_gpu_probe`.
- **`assets/shaders/psx_color.gdshaderinc` is DEAD CODE.** Zero shaders `#include` it; `psx_finalize`
  and `psx_blend_source` have zero callers anywhere. It is a fully-written 60-line include (with a
  designed two-layer model: whole-frame output tone + per-ABR blend-space exponent) that nothing
  uses, and its header points at an **unwritten ADR** (`docs/adr/00NN-psx-color-model.md ... to be
  written`). Its intended role was split and inlined: the tone/gamma math (`pow`, `psx_gamma`,
  `psx_brightness`) now lives **inline inside each family include** (`tile_overlay.gdshaderinc`,
  `tile_cursor.gdshaderinc`, `formation_box.gdshaderinc`), and the recipe-fold role went to
  `color_stack`. So the "deliberate two-layer split (output-tone vs recipe-fold)" the handoff
  asked us to confirm **was never realized** — it's an abandoned design.
- The `color_stack` header's claim that "EVERY battle/scenario shader calls it" is **aspirational,
  not current** (5 of 40). That's not automatically a defect — most shaders don't transform CLUT color
  through the 11-mode stack — but the header overstates, and the *guard* is the real contract, so the
  header should be corrected to match.

### 3. "Unified blend modes across all shaders" — ⚠️ PARTIALLY TRUE
- Blend **cannot** be `#include`d — `blend_add`/`blend_sub`/`blend_mix` are `render_mode` flags on the
  shader's first line, not code. Correct as the user intuited.
- The working unifier is **the compositor.** `src/effects/CombatDisplaySpaceComposite.gd` folds the
  effect-particle mode buckets in DISPLAY space via its own RD raster pipelines (fixed-function
  `BLEND_OP_ADD`/`REVERSE_SUBTRACT`/`SRC_ALPHA`), with blend mode carried as *instance data* through
  one unified 20/24-float SSBO (ADR-0040 packing) — not as a material render_mode. This is why
  `effect_particle_mode0..3` were retired to `tools/probe_shaders/` (#227).
- Three mode-split render_mode families remain: `tile_overlay_mode0..3`, `tile_cursor_semi_mode0..3`,
  `screen_color_mode0..3`. See WIN A (collapse the free half) and WIN C (compositor — **and why it
  does not pay off here**).

---

## Ranked plan

### WIN A — collapse `mode1`+`mode3` in all three remaining families ✅ do it (mechanical, low risk)
Verified by diff: in every family, `mode1` and `mode3` have the **identical `render_mode` line**
(`blend_add`) and differ ONLY by a fragment multiply — `ALBEDO = c.rgb` (mode1) vs
`ALBEDO = c.rgb * 0.25` (mode3, "back + ¼ front"), plus comments.

| Pair | render_mode | Only real diff |
|---|---|---|
| `tile_overlay_mode1` / `_mode3` | `blend_add` | `* 0.25` |
| `tile_cursor_semi_mode1` / `_mode3` | `blend_add` | `* 0.25` |
| `screen_color_mode1` / `_mode3` | `blend_add` | `* 0.25` |

Since the render flags match, the split has **no justification**. Collapse each pair into one shader
with `uniform float front_scale = 1.0;` (mode3's binding sets `0.25`). Deletes **3 shader files** and
kills a 3× lockstep-edit drift surface. The binding arrays index by mode int
(`TileOverlayConfig.MODE_SHADERS[34-40]`, `TileCursor.SEMI_MODE_SHADERS[83-88]`,
`ScenarioColorScreen.MODE_SHADER_PATHS[30-35]`), so mode3 → same shader as mode1 + `set_shader_parameter("front_scale", 0.25)`.
**Gate:** a `/tdd` red test proving `front_scale=0.25` reproduces the old mode3 output, then
`/effect-parity` spot-check against PCSX (the 0=avg/1=add/2=sub/3=add¼ mapping is load-bearing).

### WIN DEAD — delete `psx_color.gdshaderinc` ✅ do it (or explicitly resurrect) — near-zero risk
Nothing includes it; its functions have no callers; it references an unwritten ADR; its logic is
already inlined elsewhere. Two honest options:
1. **Delete it** (recommended) — it is abandoned machinery masquerading as the color seam, and it
   actively confuses the "which include is the color model?" question (there appear to be two; there
   is one). Grep-clean: `psx_finalize`/`psx_blend_source`/`psx_color.gdshaderinc` all return only the
   file itself.
2. **Resurrect it** — only if the team wants the whole-frame output-tone layer it describes and is
   willing to write the ADR and route callers. Given the tone math is already inlined and working,
   this is a larger, lower-value project. Prefer (1).
Either way, **write down which include is THE color seam** (`color_stack`) and fix the two headers
that overstate coverage.

### WIN B — the add/sub twin pairs split into two very different cases
- **`formation_box` / `formation_box_sub` — clean.** Bodies are **identical** apart from the
  `render_mode` line (`blend_add` vs `blend_sub`) and comments; both already `#include
  "formation_box.gdshaderinc"`. Confirm 100% of the fragment logic lives in the include so the two
  files are pure 3-line render_mode wrappers (they nearly are). Low value (they're already deduped),
  low risk — a tidy-up, not a win.
- **`show_graphic` / `show_graphic_shadow` and `show_map_title` / `show_map_title_shadow` — NOT trivial
  twins (handoff corrected).** The shadow pass carries **real added fragment logic**: a `here_a`
  negative-space gate (`ALPHA = ... * (1.0 - here_a)`) plus a `shadow_uv` offset, so the drop-shadow
  falls only in the glyphs' negative space instead of cancelling the additive body. They already share
  the reveal + dither includes. **Do not "collapse" these** — the divergence is intentional and
  correct. At most, extract any *remaining* duplicated helper into the reveal include; leave the two
  render_mode wrappers.

### WIN C — route the three families through the compositor ❌ NOT worth it here (handoff over-ranked this)
The handoff called this "the big structural win." The runtime evidence says otherwise — the compositor
pays off for effect particles because they are **hundreds of instanced prims already staged in an
SSBO** with per-prim mode. These three families do **not** share that shape:

| Family | Draw shape (evidence) | Prim count | Compositor fit |
|---|---|---|---|
| `tile_overlay` | one-off `MeshInstance3D` **per tile**, per-mode material swap (`Tile.gd:109,160`, `TileOverlayConfig.gd:256`) | many, but **not** instanced/SSBO | would need new CPU→SSBO staging infra; high effort |
| `tile_cursor_semi` | **single** persistent 2-surface `MeshInstance3D` (`TileCursor.gd:122,174`) | one cursor | high effort, ~zero payoff |
| `screen_color` | **single** full-screen NDC quad, one per `{3E}` event (`ScenarioColorScreen.gd:141`) | one quad | screen-space, no depth — compositor folds vs opaque scene depth, so it'd need a depth-disabled variant; high effort, low payoff |

The compositor seam **is** reusable — `CombatDisplaySpaceComposite.add_effect(runs, tex, pal, use_pal)`
(`:221`) is producer-agnostic and validates nothing but the `{mode,base,count,buf}` run structure. The
blocker is that **none of these three families builds a run list or uploads a unified buffer**; the
`_pool.upload_unified()` staging in `EffectParticleRenderer.gd:396` is pool-specific. Building that
staging for one-off/single-quad draws costs more than the ×4→×1 material collapse saves.

**Recommendation:** WIN A already removes the *free* half of every family's split (mode1≡mode3). The
residual mode0/mode1/mode2 in each family are **genuinely three different render_modes**
(mix/add/sub) and cannot be `#include`d away. Accept them as three thin wrappers over a shared include
(which they already are). **Do not build compositor routing for these** unless a future feature makes
one of them high-count-instanced (then reuse `add_effect`).

---

## Drift risks (record in the writeup / issue)
1. **`psx_color.gdshaderinc` dead include** referencing an unwritten ADR — top doc-debt item. Delete or resurrect (WIN DEAD).
2. **`mode1`/`mode3` lockstep duplication** across 3 families — same blend flag, must-edit-in-pairs. Fixed by WIN A.
3. **`color_stack` "EVERY shader calls it" header** vs 5 real callers — header overstates; the guard is the real contract. Fix the header.
4. **Two parallel compositors** (`CombatDisplaySpaceComposite` + `src/ui3/formation/FormationDisplaySpaceComposite`) — the combat one's header flags a "deferred formation/combat merge" (#215 residual). Future unification, effect-parity-gated; out of scope here.
5. **`tools/probe_shaders/effect_particle_mode*`** are retired oracle copies — the audit must not count them as prod, and they must not silently diverge from the compositor's fold math (they're the reference).
6. **`ui_nearest.gdshader`** — verified `shader_type canvas_item` (2D/UI), which is why it has no `render_mode`. Not a broken 3D shader. No action.

---

## Do-now shortlist
1. **Delete `psx_color.gdshaderinc`** (WIN DEAD) + correct the `color_stack` header coverage claim. Mechanical, near-zero risk.
2. **WIN A**: collapse `mode1`+`mode3` → one shader + `front_scale` uniform in all three families (−3 files), TDD red test + `/effect-parity` gate.
3. Tidy `formation_box`/`_sub` if any logic is outside the include (WIN B clean half). Skip the show_graphic/show_map_title "twins" — their divergence is real.
4. **Do not** pursue WIN C (compositor routing) for these families — evidence shows it costs more than it saves. Note it as "reuse `add_effect` only if a family becomes high-count instanced."

Suggested vehicles: `/simplify` for WIN A + formation_box tidy; `/tdd` for the front_scale red test;
`/effect-parity` before collapsing any ABR blend; `/request-refactor-plan` if landing as a tracked
tiny-commit issue.
