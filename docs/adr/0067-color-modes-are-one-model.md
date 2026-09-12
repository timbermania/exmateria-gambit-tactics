# Color modes are one model: a base colour transformed by a re-derived stack of recipe+timeline layers

FFT recolours the scene the same way everywhere — sepia cutscenes, poison
tint, door-fade dim, lightning flash, combat screen tints — by transforming
the **final colour** on screen, *after* the palette/texture lookup, over
time. The game grew **two independent implementations** of that one 11-mode
PSX blend engine: a combat delta-sum stack (`ScreenEffectOverlay` /
`ScreenSubsystem` / `MapTintOverlay` / `UnitTintOverlay`, driven by
`EffectTimeline`, ADR-0014) and a scenario/cutscene tint path
(`ScenarioColorTint` + `ScenarioVM._effective_unit_tint` +
`MapComposer.set_field_*`, with luma branches in `unit.gdshader` /
`indexed_color.gdshader`). They reproduce the same ROM behaviour twice and
drift apart. This is the colour analog of the depth split ADR-0009 retired:
one model, implemented several times, unified behind one shared shader
include plus one CPU source of truth.

## Status

accepted (implemented). The scenario path (unit sprites + map field), the combat
screen background, and the `{66}` commit all fold through the one seam
(`psx_color_apply` / `ColorStack`); the legacy per-uniform paths are deleted and a
preflight net (`tools/check_color_shaders.py`) keeps every colour shader routed
through it. Byte-exactness is proven end to end — CPU `ColorStack.fold` == the legacy
shader math (parity oracles) and the GLSL == `fold` (`ColorStackGpuParityTest`).
Remaining/deferred: the combat `ScreenSubsystem`/`PaletteSubsystem` 11-mode reductions
still live outside the stack. As of 2026-07-11 this is **RE-grounded — no longer awaiting a
vague visual sign-off.** Grilling the dedup against the disassembly decoded the two PSX
appliers and the per-consumer knobs (see "Deferred combat unification" below); **both
consumers are statically known-wrong and fixable without an emulator.** The earlier framing
("combat is 8-bit vs the model's 5-bit") was wrong: there are *two* appliers, not one.

## Decision

There is **one** colour model, exposed as the depth cluster's exact mirror:

1. **One shader include**, `assets/shaders/psx_color_stack.gdshaderinc`,
   exposes one function — `vec3 psx_color_apply(vec3 base, int surface_id)`
   — that every colour-transforming shader `#include`s and calls, the way
   every depth shader calls `psx_ot_depth(...)`.
2. **The include is base-agnostic.** Each consumer computes its own **base
   colour** (`vec3`) however it likes — indexed palette lookup (sprite/map),
   4-corner bilinear gradient (combat background), gradient×Gouraud (lit
   map) — then hands it to the include, exactly as each depth consumer
   supplies its own representative point.
3. **The stack is a bounded ordered array of layers, folded in order, with
   one operation.** `c = base; for each layer: c = mix(c, recipe(c),
   progress); return c;`. There is **no compose-op enum** (add/over/multiply/
   replace) — every combine falls out of the layer's **recipe**: additive
   tint is affine `scale=1`, an absolute set is `scale=0`.
4. **A layer is a recipe + a progress + a surface mask.** A **recipe** is the
   CPU-side reduction of the 11 PSX `Color` modes to two shapes: affine
   `{scale, bias}` or luma `{div, delta5, source∈{current,base}}`. Endpoints
   are always implicitly `{identity, recipe}` — **no stored "from"**;
   `progress ∈ [0,1]` (computed on the CPU) fades the recipe in, or *out* for
   a mode-8 restore. The **surface mask** `{body,weapon,effect}` gates which
   composited sub-sprite a unit layer touches; single-surface consumers pass
   `surface_id = 0` and whole-surface layers set that bit.
5. **State is re-derived every frame from the layer timelines, never
   accumulated** into a colour buffer. This is what makes park / rewind /
   scrub in the scenario debugger work: any `now` is directly evaluable.
6. **One CPU owner — `ColorStack`** — is the single source of truth (the
   `DepthMode.gd` analog): it holds each surface's layer list, reduces
   modes→recipes, evaluates `progress` via the existing byte-exact DDA,
   merges settled affines, expires restored layers, applies `{66}` commits,
   resolves `{32}`/`{33}` precedence and broadcast fan-out, and pushes the
   uniform arrays. Both `EffectTimeline` and `ScenarioVM` become thin drivers
   that call `push_layer(...)`.

## Considered options

- **Re-derive from the timeline (chosen)** vs **an evolving stored CLUT.**
  PSX itself keeps one forever-mutating CLUT (the stored model). We reject
  it because the scenario debugger's whole value is seeking to an arbitrary
  `now`, and a stored CLUT can only reach a state by *replaying* to it.
  Re-derive makes colour a pure function of `(base, layer_stack, now)`.
  Per-fragment cost is `O(active layers)`, which the fold below keeps at
  ~3. The prevalence data agrees: only 24 of 936 `Time>0` ramps are
  cross-family, so stored-CLUT generality is not needed for faithfulness —
  the case for unification is the two-engine duplication, not ROM coverage.
- **Ordered fold, no collapse (chosen)** vs **CPU-collapse of additive
  runs.** An early framing had the CPU merge commutative layers to shrink
  the array. Rejected: it never merges *timelines* (each layer keeps its
  own `t_start/t_end/curve`), only spatially-uniform additive *results*,
  and only *contiguous* runs unbroken by a non-commutative layer — fiddly
  special-casing. Keeping the array **ordered** makes interlacing
  (`[add, luma, add]`) fall out for free. Combat still presents as one layer
  because `ScreenEffectOverlay` already sums its per-owner deltas today —
  a driver choice, not an include mechanism.
- **One fold op + implicit identity "from" (chosen)** vs **a compose-op set
  + a stored per-layer "from".** A different mode is a *new layer pushed on
  top*, not a mutated endpoint; fade-out is the same layer's `progress`
  running downward. So no layer ever stores a non-identity "from", no
  freeze snapshot, no nested reconstruction. This holds under the invariant
  below; the rare cross-recipe interruption snaps (one frame), which the
  "ramps finish before next op" content pattern makes a non-event.
- **One stack + per-layer surface mask (chosen)** vs **a stack per
  sub-sprite.** The unit fragment already resolves one winning sub-sprite by
  opaque painter's select (ADR-0019), so a `{body,weapon,effect}` bitmask on
  each layer of one shared stack subsumes three separate stacks without 3×
  the uniforms. Every shipped FFT tint is whole-unit (all bits); masks are
  for *game* effects (weapon-only glow).
- **Single `ColorStack` CPU owner (chosen)** vs **a shared pure core with
  per-driver ownership** vs **shared shader only.** Only the single owner
  actually kills the duplication (the point of the ADR); the weaker options
  leave two lifecycle/precedence implementations free to drift, just one
  layer up.
- **Per-consumer quantization (chosen)** vs **per-layer** vs **global.** The
  5-bit byte-exactness endpoint is the *final* CLUT colour, quantized last,
  so mixed fidelity on one surface is incoherent; one `uniform bool
  psx_quantize` per shader mirrors PSX's uniform-per-CLUT fidelity. Global
  is too coarse to run a parity cutscene and a float game effect in one
  build.
- **Symbolic affine merge + explicit `{66}` bake (chosen)** vs **baking the
  settled prefix into base** vs **no collapse.** Affines compose to a single
  affine (`{s0,b0}∘{s1,b1} = {s0·s1, s1·b0+b1}`), so a run of settled affine
  layers merges symbolically — reversible, base untouched, seek-safe — and
  luma never accumulates because at most one is active per surface. This
  self-limits the live stack to ~3 forever with no base mutation. Baking the
  prefix into the palette also works but is *irreversible* (a later restore
  can't un-bake) and forces a base rebuild on every backward seek, so it is
  reserved for the one op that genuinely needs it.

## Consequences

- **The invariant that makes the fold flat: ≤1 non-commutative (luma/
  replace) layer is mid-ramp per surface.** Additive layers are commutative
  and overlap freely. With one luma at most, the layer beneath it is
  settled, so "current"-reads are stable, `from` is identity, and no freeze
  snapshot is needed. This is a *fact about ROM content* (the sepia/grey
  scenes 8/14/54/396 sequence their ramps), not a constraint imposed on
  drivers; a violation snaps for one frame.
- **`{32}`/`{33}` precedence is a driver concern, not an include feature.**
  The field `{33}` is a broadcast the driver fans out onto every surface's
  stack; a unit's `{32}` is a layer on that unit. PSX *suppresses* the field
  on a unit with its own luma — and luma-over-luma ≠ just-the-unit-luma —
  so the driver simply doesn't push the field layer onto that unit at
  assembly time (what `_effective_unit_tint` does today). The include folds
  a pre-resolved stack.
- **Commit (`{66}`) is the one base-mutating, irreversible path, and it is
  necessary — not an optimization.** It writes `palette[i] := recipe(
  palette[i])`, *redefining* base so a later `source=base` recipe and any
  further op read the committed tint. A post-lookup layer is invisible to a
  `source=base` read, so only a bake can do this. It is distinct from a
  **palette swap**, which *selects* a different pre-existing CLUT (`new =
  otherCLUT`) rather than *deriving* one (`new = f(old)`) and is upstream of
  the fold, out of scope for the include. A backward seek past a commit
  rebuilds base (the debugger already reloads map state on rewind).
- **The public contract (portable vec4/int arrays — Godot struct-uniform
  arrays are unreliable):**
  ```glsl
  const int MAX_COLOR_LAYERS = 8;               // ~3-4 real worst case + headroom
  uniform vec4 color_layer_rgb0[MAX_COLOR_LAYERS]; // affine scale.xyz | luma delta5.xyz ; .w = progress
  uniform vec4 color_layer_rgb1[MAX_COLOR_LAYERS]; // affine bias.xyz               ; .w = luma div (0 ⇒ affine)
  uniform int  color_layer_meta[MAX_COLOR_LAYERS]; // [2:0] surface mask · [3] luma source(0=current,1=base)
  uniform int  color_layer_count;
  uniform bool psx_quantize;                       // per-consumer 5-bit fidelity
  ```
  `div==0 ⇒ affine, else luma` is a free discriminator. The shader does zero
  time math and zero mode logic — the CPU hands it `{recipe, progress,
  mask}`, it folds.
- **Progress is CPU-computed; the include imposes no timeline.** Each driver
  evaluates its own clock+curve (combat 30 Hz, scenario 60 Hz + PSX DDA) and
  hands the shader a float, so `ScenarioColorTint`'s byte-exact DDA (227/227
  vs live CLUT) is reused verbatim rather than re-derived in GLSL.
- **Migration is incremental, freshest-first, behind a provable guard.**
  (1) pure core (`ColorRecipe` reduce + DDA + affine-merge + `luma_out5`,
  most of which is `ScenarioColorTint`) TDD; (2) the include + `ColorStack`,
  uncommitted; (3) **scenario `unit.gdshader` / `indexed_color.gdshader`
  first** — freshest, and its byte-exact oracle makes "no regression"
  *provable* while exercising the hardest path (luma + source + precedence +
  quantize) early; (4) scenario map (`MapComposer`); (5) combat overlays +
  `screen_background.gdshader` (additive = the `scale=1` special case);
  (6) delete the old per-uniform paths (`unit_tint_scale/bias`,
  `field_tint_*`, the overlay delta dicts); (7) a preflight net (ADR-0009
  style) asserting every colour-transforming `.gdshader` `#include`s the
  include and routes through `psx_color_apply` — no ad-hoc tint uniforms or
  inline mode branches.
- **Vocabulary.** `CONTEXT.md` gains a "Color modes" cluster (`Color stack`,
  `Color layer`, `Recipe`, `Base colour`, `Surface mask`, `Commit`, `Palette
  swap`), sibling to "Rendering depth", so the one-model framing and the
  transform-vs-select and layer-vs-commit distinctions are named, not
  re-derived.
- **Not part of `bootstrap_assets.sh`.** The include, `ColorStack`, and
  `ColorRecipe` are hand-authored render code, not ISO-derived assets, the
  same carve-out ADR-0009 makes for `DepthMode`.

## Deferred combat unification — RE-grounded plan (2026-07-11)

Grilling the combat dedup (issue #164) against the disassembly, the research luma
doc, and the effect-editor format tool settled the open questions. **Key correction:**
combat is *not* "one 8-bit engine vs the model's 5-bit." There are **two distinct PSX
appliers** that share only the 11-mode classification; they differ *by consumer*, and
both current Godot subsystems diverge from them. Full RE cites:
`research/working_documents/COMBAT_COLOR_APPLIER_RECONCILIATION.md`.

- **Palette tint** — `color_tint_blend_apply @0x8008f710`, the *shared* backend for
  `{32}` Color Unit / `{33}` Color Field / `{1A}` Map Darkness, already mirrored
  byte-exact by `ColorRecipe`. Transforms a **5-bit CLUT** entry; modes 4-9 read the
  **absolute committed base palette** (`DAT_80099d76`, idempotent), write-back is
  **absolute** (not a delta), params are **×1** (`lbu`, no `<<1`). `PaletteSubsystem`
  diverges three provable ways: a delta-centred-on-0 domain, a `4/5/6/7 → bare param`
  short-circuit (base=0), and float luma. **Fix: route through `ColorStack` with
  `quantize=true`, absolute base.** Dedup + faithfulness in one move, statically justified.
  Live-Ghidra xrefs (2026-07-11) confirm combat **effects** also reach this applier (via
  the effect dispatcher `FUN_800e840c`), so `PaletteSubsystem` mirrors the *exact* engine
  `ColorRecipe` already reproduces byte-exact — the import is xref-proven, not inferred.
- **Screen tint** — `screen_tint_apply @0x80090840`, a *separate* applier accumulating
  in **16.16 fixed-point**, read back `>>16` and byte-copied to a full-screen gouraud
  quad (reader `0x800917b0`, dispatcher `FUN_800e8190` case `0x5a`, quad `SUB_8001d168`).
  Params are **×1** everywhere — **the `ScreenSubsystem` `param<<1` (×2) is spurious**,
  a Godot divergence with no ROM counterpart (the effect-editor's "DOUBLED" help text is
  likewise wrong). **Fix: route through `ColorStack` with `quantize=false` (framebuffer,
  not 5-bit) and remove the `×2`.**
- **Map track-0** — the effect-editor claims a **×8** vertex-colour scale for map/terrain
  tint. **REFUTED (2026-07-11, live Ghidra decompile + xrefs, corroborating a text-trace):**
  there is **no third "map vertex-colour" applier** — the only two tint sinks are
  `color_tint_blend_apply` and `screen_tint_apply`. The map is tinted through the **CLUT
  engine** (its palette entries change — 5-bit) or the **screen engine** (`{1A}` Map
  Darkness → `map_darkness_shim → screen_tint_apply` — 16.16). RGB is `×1` in both; every
  nearby `<<3` is the `×7` descriptor stride (`&DAT_80099676 + i*7`), not colour. The `×8`
  is a bare help-text annotation (`effect-editor/ui/color_tracks_tab.lua:47`) with no code
  behind it — same failure mode as the `×2`. **No `×8` to add; `MapTintOverlay` has none today.**

**Design rule (2026-07-11): per-consumer knobs are self-documenting.** Each `(param_scale,
quantize, base source)` is named at its call site with the consumer and the PSX applier it
mirrors — never a bare literal. See the **Consumer profile** term in `CONTEXT.md`.

**Sequence.** `ScreenSubsystem`/`PaletteSubsystem` have **zero** tests today —
characterization-test each subsystem's *current* output across modes 0-10 first, then swap;
the palette diff *is* the fix (validate each diffing mode against `0x8008f710`), the screen
diff is the `×2` removal. A live PCSX A/B is optional reassurance for the screen change (it
visibly halves param strength) but **not** a blocker — the disasm is unambiguous.

**Status — Task A (`PaletteSubsystem`) IMPLEMENTED (2026-07-11, TDD).** The palette combat
path now routes through the stack: `PaletteSubsystem.build_stack(channel, phase)` reduces
parsed keyframes to a per-channel `ColorStack` (Consumer profile: `quantize=true`, param ×1,
base = the fold's `base`); `UnitTintOverlay`/`MapTintOverlay` concatenate each owner's evaluated
snapshot into the shared `color_layer_*` uniforms (`ColorStack.apply_packed`), so combat effects
fold through `psx_color_apply` over the real ALBEDO/CLUT entry. The additive `unit_tint`/`map_tint`
shader uniforms were **retired** (both now BANNED by `tools/check_color_shaders.py`); map combat
tint is now pre-lighting (the faithful CLUT rewrite). The three bugs are fixed by construction:
luma 2/3/6/7 fold over the real base, absolute-base 4/5/6/7 read `base` (not delta-on-0), 5-bit
quantize on. Guards: `PaletteSubsystemTest` (16), `UnitTintOverlayTest` (10), the two
`ColorStack.apply_packed` cases. Purely-additive `TrapPaletteController` keeps working via the
`update_layer(delta)` additive bridge. A live combat A/B remains the optional reassurance for
phased (`phase1`/`phase2`) effect timing (the base's phase-start baseline; `for_each` is exact).

**Status — Task B (`ScreenSubsystem`) IMPLEMENTED (2026-07-11, TDD).** The screen path already
folds through the stack (`ScreenEffectOverlay`: tint via `_push_color_stack`, delta baked into the
gradient base, `quantize=false` throughout — the 16.16 framebuffer engine, not 5-bit). The only
divergence was the spurious `param = signed × 2` in `ScreenSubsystem._calculate_blend_target` —
**removed** (params now ×1, mirroring `screen_tint_apply @0x80090840`; the ROM's `<<16` is
fixed-point promotion read back `>>16`, not a ×2). Mode structure (byte_register source for 4-9,
luma divisors, restore/stop) unchanged. Guard: `ScreenSubsystemTest` (14). Visibly halves param
strength — the correction, not a regression.

**Status — Task C hardening + cleanup DONE (2026-07-11).** All four review items landed:
`ScenarioColorTint` delegates its `luma_out5`/`_sb`/`ramp_frames_for_time`/`RAMP_FAST_FRAMES`
core to `ColorRecipe` (one copy); `ScenarioLumaTintTest` oracle repointed to `ColorRecipe.luma_out5`;
`ScenarioColorUnitTest` reset test now asserts a real fold-to-identity (not the `_affine_scale`
identity-default tautology); `ColorStackGpuParityTest` gained four `psx_quantize=true` cases compared
exactly on the 5-bit grid. And `PaletteSubsystem`'s now-dead imperative stepper (~330 lines: `_evaluate`,
`_calculate_blend_target_for_channel`, `tint_colors`, the delta getters) was DELETED — it's purely a
keyframe→`ColorStack` mapper now (`CB91TimingTest`, the lone reader, migrated to `build_stack().fold()`).

**Only remaining:** the optional live combat PCSX A/B (combat effects don't render headless) — mainly
to confirm phased (`phase1`/`phase2`) effect timing; `for_each` is exact.

## Amendment (2026-08-28) — the model is fully built and guarded, and the one claim in it that a live capture could touch is the one that died: the screen `×2` this ADR called spurious was restored three days later, proven byte-exact on a savestate

_Audit pass, 2026-08-28. The six Decision items above were unnumbered bullets
until this pass; numbering is additive (this ADR had zero decision anchors
before). Every row below grades against the shaders, `ColorStack`, and the
tests — not against the ADRs that cite this one._

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
|---|---|---|---|
| 1 | One include, `assets/shaders/psx_color_stack.gdshaderinc`, exposing `vec3 psx_color_apply(vec3 base, int surface_id)` | **holds, MOVED path** | The function signature is exact (`:73`). The file is now `addons/exmateria_schema/colour_model/psx_color_stack.gdshaderinc` — the whole colour model (include + `ColorStack.gd` + `ColorRecipe.gd`) left `assets/shaders/` and `src/` for the schema addon during the extraction passes. |
| 2 | The include is base-agnostic; each consumer computes its own base | **holds** | `psx_color_apply(base, surface_id)` takes the base as an argument and reads no texture. Consumers span indexed sprite/map lookups, the combat gradient, and the lit map. |
| 3 | Bounded ordered array, one fold op, no compose-op enum | **holds** | `MAX_COLOR_LAYERS = 8` in both the include (`:37`) and `ColorStack.gd:22`; `fold()`/`fold_packed()` are the only combine; there is no op enum anywhere in the model. |
| 4 | A layer is recipe + progress + surface mask; the `source∈{current,base}` axis belongs to **luma** | **holds, GENERALIZED** | The mask, implicit-identity endpoints and CPU progress are all as written. But the source bit is no longer luma-only: `ColorRecipe.affine_base()` exists beside `affine()`, and the include's meta comment (`:40`) now reads "`[3] recipe source (0=current,1=base; affine & luma)`" where this ADR gives the axis to luma alone. A generalization past the Decision, not a departure from it — nothing lost, one axis widened. |
| 5 | State re-derived every frame, never accumulated | **holds** | `evaluate(now)` re-walks the layer list; the only base mutation is the `{66}` bake (`commit_bake`), which dec. 5's own Consequences carve out. |
| 6 | One CPU owner `ColorStack`; **`EffectTimeline` and `ScenarioVM`** become thin drivers calling `push_layer(...)` | **holds for the owner, WRONG DRIVER NAMED** | `ColorStack` is the single owner and carries every listed duty (`push_layer:118`, `push_op:147`, `_restore:165`, `_is_shadowed:183`, `evaluate:201`, merge via `_flush_run:231`, `commit_bake:286`, `apply_packed:368`). `EffectTimeline` calls **none** of it, and by design: ADR-0014 made it output-agnostic ("it pumps *time* only and never learns what a subsystem produces — each subsystem self-delivers"). The combat drivers are the subsystems it pumps — `PaletteSubsystem`, `ScreenSubsystem`, `ScreenEffectOverlay` — plus `ScenarioVM`, `MapComposer`, `MapIlluminationDDA` and the studio solvers. The rule's intent (one owner, thin drivers) landed; the driver this ADR named was the wrong node, and another ADR had already decided why. |

### The seam is real and netted

`tools/check_color_shaders.py` (`tests/run_all_tests.sh:309`) ran this pass:
`OK: all colour-transforming shaders route through the psx_color_apply seam
(ADR-0067).`, rc 0. Its `BANNED_UNIFORMS` tuple holds every legacy channel this
ADR promised to delete — `unit_tint_scale`, `unit_tint_bias`, `field_tint_scale`,
`field_tint_bias`, the luma pairs, and the combat `unit_tint` / `map_tint` — so
the deletion is enforced, not merely done. Confirmed independently: no shader
declares any of them; the surviving mentions in `unit_sprite_body.gdshaderinc:726`
and `indexed_color.gdshader:87` are epitaphs ("the `unit_tint` uniform couldn't
express the base-dependent luma"; "`map_tint` uniform is gone").

Two source docstrings did **not** get the memo, and they describe the deleted
mechanism as live: `ScenarioVM.gd:2202-2205` still says "The unit shader applies
`ALBEDO = ALBEDO * unit_tint_scale + unit_tint_bias` … see
assets/shaders/unit.gdshader", and `ScenarioVM.gd:2307-2309` still says the
field affine "is pushed to every unit's `unit_tint_scale`/`unit_tint_bias`". The
function immediately beneath the first one (`_push_unit_color_stack:2231`) pushes
`color_layer_*` through the stack and says so. The same paragraph also names
`MapComposer.set_field_tint`, which no longer exists — production has
`set_field_color_stack` / `commit_field_tint` / `bake_field_tint`
(`MapComposer.gd:649/675/703`); the only `set_field_tint` left tree-wide is a
test stub in `ScenarioCommitPaletteTest.gd:52`.

### The `×2` this ADR called spurious was restored three days later, by the check it called optional

The "Deferred combat unification" section (2026-07-11) states, of
`screen_tint_apply @0x80090840`: "Params are **×1** everywhere — **the
`ScreenSubsystem` `param<<1` (×2) is spurious**, a Godot divergence with no ROM
counterpart (the effect-editor's 'DOUBLED' help text is likewise wrong)." Task B
then reports it **removed**, and the Sequence paragraph rules that "A live PCSX
A/B is optional reassurance for the screen change … but **not** a blocker — the
disasm is unambiguous."

That live A/B happened, and it went the other way. `086f871e4` (2026-07-14,
three days later): "The screen Blend applier doubles the signed start byte
(`r = (i8)start << 1`), **proven live on E173/savestate9**: for_each idx8
start_r=192 (=-64) fires the setter with param -128. Godot applied it un-doubled
(half strength) → dim/flat red." It folds `ScreenSubsystem` over the live PSX
base gradient and reproduces the captured block byte-exact at frame 53, and it
closes the question by name ("Resolves the param×2 open question, living doc
§9.5"). Two of the pre-existing E005 mode-5 tests had been *computed* un-doubled
— never captured — and were corrected in that commit.

The doubling did not come back where this ADR removed it: `_calculate_blend_target`
no longer exists anywhere in `src/` or `tests/` (the whole imperative stepper was
deleted in Task C). It came back as an opt-in recipe flag threaded through the
model this ADR built — `ColorRecipe.from_mode(..., double_param)`,
`ColorStack.push_op(..., double_param)` — passed `true` at exactly one call site,
`ScreenSubsystem.gd:103-107`, whose comment records the provenance and the
carve-out: "the 8-bit framebuffer applier's convention, PROVEN live on
E173/savestate9 (§2 of the living doc). double_param=true; the palette CLUT path
does NOT double." So the *unification* held under the correction — the fix was a
per-consumer knob inside one engine, which is precisely what this ADR's
"Consumer profile" design rule prescribes. Only the empirical claim died.

Nothing amended this ADR to say so. ADR-0087 (accepted, build pending) already
treats the doubling as settled fact — "`double_param`, `<<1`: the row shows the
raw stored byte with the doubling told in the label — *Tint Δ (applied ×2)*" —
and lists this ADR under **Relates to** as "the one colour model both lanes
share", citing it without noting that it asserts the opposite. `SpacerVerdicts.gd:30`
encodes the same fact as a profile constant, `SCREEN_PROFILE := {"param_max": 255,
"quantize": false, "double_param": true, "clamp": true}` — a **fourth** profile
axis (`clamp`) beyond the three this ADR's design rule names.

### Counts, and one claim this pass could not settle

The status blocks' guard counts are all historical. Measured today:
`PaletteSubsystemTest` 24 test functions / 44 assertions (ADR says 16),
`UnitTintOverlayTest` 4 / 12 (ADR says 10), `ScreenSubsystemTest` 16 / 35 (ADR
says 14, and `086f871e4` reports it going 26→29 in yet a third unit). The ADR
never states which unit it is counting; on any reading all three have grown, so
these are stale numbers beside working guards, not lost coverage.

Also stale by internal contradiction: the **Status** section still says
"Remaining/deferred: the combat `ScreenSubsystem`/`PaletteSubsystem` 11-mode
reductions still live outside the stack", while the Task A and Task B blocks
below it report both IMPLEMENTED on 2026-07-11. The Task blocks are current; the
Status sentence was never updated when they landed.

### Recorded question — does the `×8` refutation inherit the `×2`'s doubt?

The same paragraph, written the same day by the same instrument (live Ghidra
decompile + xrefs, no emulator), makes two refutations of the same effect-editor
help text. One of them is now known to be wrong. The other has never been
re-checked, and the help text still carries both claims uncorrected
(`effect-editor/ui/color_tracks_tab.lua:47` "Map gets RGB x8 scaling", `:485`,
and `:507` "SIGNED (-128 to +127) and DOUBLED").

**Reading A — the `×8` refutation is independent and stands.** It is a
*structural* claim ("there is no third map-vertex-colour applier; the only two
tint sinks are `color_tint_blend_apply` and `screen_tint_apply`"), proven by
xref enumeration, and it explains the `<<3` sightings as the `×7` descriptor
stride. The `×2` died on a *magnitude* reading of one applier's parameter path —
the kind of thing a static read can miss and a capture cannot. Different claim,
different failure mode; nothing to redo, and `MapTintOverlay` correctly has no
`×8` today.

**Reading B — it inherits the doubt and needs the same live A/B.** Both claims
came from one sitting, both contradicted a hand-written annotation that had
survived in the tool for a long time, and the ADR's own confidence sentence
("the disasm is unambiguous") is the sentence that failed. If the map is tinted
through the CLUT engine, an `×8` on the *param* would show up exactly the way the
screen `×2` did — as content that renders at a fraction of its authored strength
— which no headless test can see.

Not resolved here. What would settle it is one live capture of a map-tint effect
against `MapTintOverlay`'s fold, the same shape as `086f871e4`'s E173 run.

### On mechanizing this ADR

The seam itself is netted (`check_color_shaders.py`, green, with the banned-uniform
list as its teeth) — this is one of the better-guarded ADRs in the corpus. Three
arms are possible and unwritten:

1. **A docstring arm.** The banned-uniform check reads shaders only. The same
   `BANNED_UNIFORMS` tuple applied to `.gd` prose would be red today at
   `ScenarioVM.gd:2204` and `:2308`, which describe deleted uniforms as the live
   mechanism. It would need an epitaph allowance — the two shader mentions above
   are deliberate and must stay.
2. **A dead-reference arm.** `MapComposer.set_field_tint` is cited from a live
   docstring and exists only as a test stub. A general "a `Class.method` named in
   prose resolves in `src/`+`addons/`" check is larger than this ADR, but this
   ADR supplies a concrete red case.
3. **A profile arm.** Assert every `push_op(..., double_param: true)` call site
   is a screen-lane consumer, and that no palette-lane caller passes it — the
   invariant `ScreenSubsystem.gd:105` states in prose ("the palette CLUT path
   does NOT double") and that `SpacerVerdicts`' two profile constants encode.
   Green today; it pins the correction that overturned this ADR's own claim.
