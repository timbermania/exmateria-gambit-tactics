# Display-space fold

The Forward+ compositor (the 4.8 fork) blends FFT's additive/subtractive effects
in **display space** through the engine's Pass B, so each blend step clamps like
the PSX hardware. This cluster names that substrate and its pieces — kept
deliberately distinct from the [color stack](27-color-modes.md)'s "fold" (a different
operation, on colour layers). See ADR-0074.

**Fold**:
The display-space compositor substrate: a [foldable carrier](26-display-space-fold.md)
blends into the shared [fold surface](26-display-space-fold.md) via the engine's
Pass B, in [fold order](26-display-space-fold.md). Membership is a **material
property** (a `compositor_layer` render_mode plus the shared `FOLD_LAYER`
resource), not a class. Since ADR-0146 it lives in the shared kernel, not in
`Render`, and since [ADR-0191](../adr/0191-the-fold-predicate-is-the-kernels-and-a-producer-picks-between-two-shaders.md)
it publishes **three** statics, not one: `Fold.add(carrier, material, order_z,
rank)` (the decorator — a **no-op off-fork**, decorating nothing, because
`render_layer` is a fork-only property and assigning it on stock *raises*;
0191 dec. 12), `Fold.owns()` (is the fold available in this build — a
cached `RenderingServer` capability query, never host state), and
`Fold.shader(folded, fallback)` (pick between the producer's own two shaders,
which it holds as `preload`ed consts — and so does **every** GDScript reference
to a fold shader, pick or not, guarded by `check_fold_shader_preload.py`;
0191 dec. 11). Material construction is **not** here and
is not coming: ADR-0074 made the material producer-owned and ADR-0191 dec. 4
re-refused a factory, because only **6 of the 16** `compositor_layer` shaders are
mechanical — and those six are already deduplicated one layer down, into two
`.gdshaderinc` files, so a GDScript factory would collapse nothing that is still
duplicated — and a factory would also have to take `texture` / `palette_texture` /
`palette_rows` across a seam with no business knowing them. (0191 dec. 4 first
said "9 of the 29"; see its Amendment 1 for what each number really is.)
_Avoid_: the [color stack](27-color-modes.md) sense of "fold" (folding colour layers
over a base colour); calling it "the compositor" (ambiguous with the retired
GLSL path); scoping it to particles; asking `Fold.owns()`
whether a prim is *currently* folding — it answers only whether the build
supports it, and the Effect Studio's `native_blend` compare toggle is a separate
question that reaches `EngineFoldCompositor` alone.

**Foldable carrier**:
Any `GeometryInstance3D` a producer builds — a single-quad `MeshInstance3D`, a
baked multi-quad `ArrayMesh`, or a batched `MultiMeshInstance3D` — that wears a
**monomorphic** `compositor_layer` material (its blend / geometry / discard / PAR
baked into its own shader) and is handed to the [Fold](26-display-space-fold.md). A
`MultiMesh` is the *many-instances* option, open to any producer.
_Avoid_: a per-producer "adapter" type; scoping the `MultiMesh` carrier to
"particles"; a data-driven übershader that varies the four axes by uniform.

**Fold order**:
The paint order of foldable carriers, carried as each carrier's
`render_layer_order` and derived once by
`DepthMode.render_layer_order_for(order_z, rank)` from its
[OT depth](25-rendering-depth.md) bucket plus a submission-stream `rank` tie-break.
Distinct from the depth *test* (occlusion vs opaque geometry), which is
per-fragment and independent of it.
_Avoid_: re-deriving the bucket-from-depth inline per producer; conflating fold
order (paint/blend order) with occlusion.

**Fold surface**:
`addons/exmateria_render/fold_bracket/FoldSurface.gd` since extraction #1.
The compositor-owned display-space scratch the [Fold](26-display-space-fold.md)
accumulates into — seeded from the opaque scene before Pass B and resolved back
to screen after. Pure render-target plumbing, ignorant of producers and carriers.
_Avoid_: fusing it with carrier materialization; the name
"DisplayScratchCompositor".

**Fold member lifetime** (freeing a carrier is safe):
`free()`ing a fold-enrolled carrier does **not** corrupt the engine. Rendering
on this build is single-threaded (`thread_model` default = `Safe`; no
RenderingServer thread), so there is no render-thread-vs-free race, and the
compositor keeps **no persistent per-member list**: the held-out draw list is
rebuilt from visible instances every frame, and its only persistent structures
(the engine-owned layer target, the "rendered this frame" set) are keyed by
**layer id** (the shared `fold_layer.tres`), never by member instance. So a freed
member simply drops out of next frame's list. `EngineFoldCompositor` proves it —
it frees and rebuilds its enrolled carriers *every frame* in `_process`.
_History_: the F3 SpinBox-arrow SIGSEGV was misattributed to "a freed carrier left
dangling in the compositor" (and drove the `Fold` un-enroll-on-`tree_exiting` hook,
`b6400949d`, now likely inert). The real cause is a synchronous `free()` nested in
the SpinBox `gui_input` callstack — a tunable write-back hazard, not a fold one.
See ADR-0068 W1–W3.
_Avoid_: adding fold-specific "don't free while compositing" guards; re-chasing the
compositor for tunable-scrub crashes.

**Fold stage**:
Where the [fold](26-display-space-fold.md)'s three steps bracket the frame. Seed +
engine Pass B blend share one compositor hook; the resolve is a **separate,
later** hook — Pass B draws *between* them, so seed-before / resolve-after cannot
collapse into one hook. Post-transparent in shipped v1; **pre-transparent** here
(seed+blend at `POST_OPAQUE`, resolve at `PRE_TRANSPARENT`), so modern linear
transparents composite *over* the folded PSX layer (ADR-0080). Say
**pre-transparent fold** for the ordering property: bare "POST_OPAQUE" is
ambiguous — upstream it names an MSAA-resolve seam, community asks use it for a
pre-opaque data-feed, and here it means an ordering point.
_Avoid_: unqualified "POST_OPAQUE"; collapsing seed/blend/resolve into one hook;
conflating the stage (ordering across the transparent boundary) with [fold
order](26-display-space-fold.md) (paint order *within* Pass B) or the depth test
(occlusion vs opaque geometry).

**Depth ladder**:
How a **flat orthographic UI scene** (the formation / roster screen) joins the
[OT depth](25-rendering-depth.md) + [Fold](26-display-space-fold.md) contract: its abstract
`render_priority` paint order is **materialized into real distance-from-camera**,
one rung per [OT bucket](25-rendering-depth.md) (background farthest → chrome nearest).
Because the camera is orthographic, that Z *is* the view-space `order_z`, so both
the [fold order](26-display-space-fold.md) and the opaque/transparent occlusion (the
selection box **under** the unit body, the orb halo **over** it) fall out of one
geometric source — no `render_priority`, no per-shader magic depth. Depth still
only decides *ordering*; [fold](26-display-space-fold.md) **membership** stays a
deliberate per-prim material choice (the PSX add/sub prims declare
`render_mode … compositor_layer` and join via `Fold.add`; the opaque prims just
write `DEPTH`). See ADR-0077.
_Avoid_: the old "coplanar at z=0 with depth off, sorted by `render_priority`"
pattern (it can't compose with the fold, which depth-tests transparents against
the whole opaque scene); treating a UI overlay as a special case *off* the unified
contract; inferring fold membership from depth (depth orders, material decides).

**Unauthored depth** (the `z_rung = −1` / floor sentinel):
A depth-writing UI prim that never *named* a rung on the [depth ladder](26-display-space-fold.md)
— placed at the Z=0 floor via the `z_rung = −1` default or a rung-less
`screen_to_world` — has **unauthored** depth: nobody decided where it sorts, so it
sits at the very back *by accident*. A [fold](26-display-space-fold.md) band then
composites **over** it, because a band is occluded only by opaque depth that is
**nearer** than the band — *opacity alone does not win; distance does.* (This is
the trap behind "the stats panel is opaque, so why does the band darken it?" — it
was opaque, but parked on the floor one rung *behind* the band.) **Rule: every
depth-writing UI prim must author a rung, even if the rung it names is 0.** The
illegal thing is the unauthored *sentinel*, not the *value* — rung 0
(`RP_BACKGROUND`) is a legitimate authored back. Authoring forces the author to
*confront* the depth; picking one *nearer than any band that can overlap it* is the
correctness step on top (rung 0 satisfies the rule yet still sorts behind a band).
_Avoid_: "it's opaque, so it occludes the band" (only if nearer); leaving a prim at
`z_rung = −1` because it "doesn't overlap a band *today*"; banning the runtime
world-Z *value* 0 (a container/origin node sits there by design, and off-fork every
rung collapses to 0 with ordering back on `render_priority` — a guard keys on the
*authored rung*, not the materialized Z). See ADR-0077.

#### Extraction #1 translation table (`Render`)

Loop pass 4 of extraction #1 (ADR-0147). Old term → new, kept for a reader who
knows the old vocabulary. Every row is a term this cluster used that stopped
being true *before* the extraction, not because of it.

| you may have read | say now | why |
|---|---|---|
| `compositor_fold` render_mode | **`compositor_layer`** render_mode + the shared `FOLD_LAYER` resource | renamed by the ticket-15 migration off the magic-string scratch onto the general layer primitive; `compositor_fold` survives in exactly one history comment |
| `Fold.add(carrier, material, order)` | **`Fold.add(carrier, material, order_z, rank)`** | membership is two per-instance properties now, and `rank` is the within-bucket submission tie-break |
| *the Fold is `Render`'s* | **the Fold is the kernel's** (`addons/exmateria_schema/compositing_key/`) | ADR-0146. Both the producers and `Render`'s own bracket encode against it, which is a published schema, not an interface one of them owns |
| *`Render`'s shader library* | **there isn't one** — `ot_depth` / `color_stack` are the kernel's, `par` / `dither` are `platform`'s, `screen_blend` is `Cutscene`'s | ADR-0146 dec. 4 + ADR-0147 dec. 4. A fact six buckets `#include` cannot live inside the first system to extract |
| *the engine-fold compositor* (as part of the fold) | **the carrier build**, and it is `Effects`' | ADR-0200 dec. 1 / ADR-0147 dec. 1. It reads the effect pool and materialises carriers; it is a producer, not part of the bracket |
| *`Render` produces into the fold* | **it does not** — four systems do (`UI`, `Battlefield`, `Effects`, `Sprite Rig`) | ADR-0147 dec. 5. The system that owns the bracket is not a producer into it |
| *the fold surface* | unchanged, and it is now **all `Render` owns of the fold** | the seed/resolve bracket, 365 of `Render`'s 699 lines. *"Named by nothing outside it"* was true only while the carrier build lived in `Render`: `EngineFoldCompositor` is `Effects`' now and reaches the bracket through `ExMateriaRender.FoldSurface` (by `class_name` until ADR-0212 dec. 1 collapsed this addon's surface to one façade), so the bracket has 2 inbound lines plus its alias (ADR-0148 dec. 6) |
| *`res://src/core/PSXDisplay.gd`* / *`res://src/effects/FoldSurface.gd`* | **`res://addons/exmateria_render/display_port/`** and **`.../fold_bracket/`** | extraction #1 landed at `e0323e7bf` (ADR-0147 dec. 1, built at loop pass 6). `class_name` references are unaffected; only `res://` paths moved, plus `project.godot`'s autoload line |

_Avoid_: calling `Render` "the compositor" (it owns the bracket, the kernel owns
the key, and producers own their carriers); reading `Fold.add`'s call sites as
inbound edges on `Render`; saying `Render` publishes **one** symbol — it publishes
two, `PSXDisplay` (26 of 28 inbound lines) and `FoldSurface` (2).
