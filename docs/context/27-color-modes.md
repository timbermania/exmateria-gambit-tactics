# Color modes

FFT recolours the scene — sepia cutscenes, poison tint, door-fade dim,
lightning flash, combat screen tints — by transforming the **final colour**
of whatever is on screen, *after* the palette/texture is looked up. This
cluster names the one model those transforms share, mirroring
[Rendering depth](25-rendering-depth.md): a single shader include any consumer
`#include`s to get the whole model, exactly as `ot_depth` is for depth.
The historical failure this cluster prevents: two independent
implementations of the same 11-mode PSX blend engine (combat's additive
delta-sum and scenario's field∘unit tints) drifting apart. See ADR-0067.

**Color stack**:
The ordered list of [color layers](27-color-modes.md) active on one surface,
folded over that surface's [base colour](27-color-modes.md) to produce the final
colour. Applied by one shared shader function — the depth cluster's
`ot_depth` analog — that every colour-transforming shader `#include`s
and calls identically. The fold is **one operation**: for each layer,
`c = mix(c, recipe(c), progress)`. There is **no separate compose-op axis**
(no add/over/multiply/replace enum) — additive combat tint is just an
affine recipe with `scale=1`, an absolute set is `scale=0`, so every
combine falls out of the recipe. The stack is evaluated fresh each frame
from the layer timelines (never an accumulated colour), so any `now` is
directly evaluable — park / rewind / scrub in the scenario debugger come
for free.
_Avoid_: "colour buffer" / "evolved CLUT" (that is the rejected stored
model — the stack is re-derived, not accumulated); "compose mode" or an
add/over/multiply/replace op set (there is one fold op; the recipe carries
the difference); folding the stack into the [palette](17-sprite-and-texture.md)
(the transform is post-lookup, palette-agnostic).

**Color layer**:
One entry in a [color stack](27-color-modes.md): a **recipe**, a **timeline**,
and a **surface mask**. Endpoints are always implicitly `{identity, recipe}` — a
layer has **no stored "from"**; it fades its recipe in (or out) by a
`progress(now)` that runs over `[t_start, t_end]` along a curve. Fade-out
and the mode-8 restore are the *same* layer's `progress` running downward,
not a new endpoint. All stack **mutation** is CPU-side; the shader only folds. A layer leaves
the stack in exactly two ways — **restore** (a mode-8 op runs its
`progress` back to 0) or **`{66}` commit** (bake into [base](27-color-modes.md),
the one irreversible, base-mutating path); reaching 100% never removes it.
Layers don't accumulate: contiguous **settled affine** layers of the same
[surface mask](27-color-modes.md) **merge symbolically** into one affine
(`{s0,b0}∘{s1,b1} = {s0·s1, s1·b0+b1}` — reversible, base untouched), and
luma layers never pile up because at most one is active per surface. So a
live stack self-limits to ~3 (affine-below · the one luma · affine-above)
plus the single mid-ramp layer, indefinitely. The count of concurrently
*transforming* (non-commutative) layers on one surface is thus small and
bounded — at most one is mid-ramp at a time, so the layer beneath it is
settled and no per-layer freeze snapshot is needed.
_Avoid_: storing a per-layer "from" colour or freezing a below-snapshot
(unneeded under one-active-ramp; reintroduces non-seekable state);
"retargeting" a layer (a different mode is a *new* layer pushed on top, not
a mutated endpoint).

**Surface mask**:
The `{body, weapon, effect}` bitmask on a [color layer](27-color-modes.md) that
gates *which* of a unit's composited sub-sprites the layer transforms. A
unit fragment resolves one winning sub-sprite by opaque painter's select
([sprite layers](18-sprite-layers.md)) and applies only layers whose mask
includes it. **Whole-unit** layers — every tint FFT actually ships (sepia,
poison, fade) — set all bits; sub-sprite masks (weapon-only glow) are for
*game* effects. Single-surface consumers (map, background, UI) carry one
implicit surface, so the same `surface_id` machinery degenerates to
"always applies," keeping one include signature for every consumer — the
mirror of how each [depth](25-rendering-depth.md) consumer supplies its own
representative point.
_Avoid_: a separate [color stack](27-color-modes.md) per sub-sprite (the mask on
one shared stack subsumes it); assuming single-surface shaders need a
different entry point than unit shaders.

**Recipe**:
What a [color layer](27-color-modes.md) computes from its input colour — the
reduction of FFT's 11 PSX `Color` modes to **two shapes**: **affine**
`{scale, bias}` (`c·scale + bias`) or **luma** `{div, delta, source}`
(the integer `floor((2R+3G+B)/div)+delta` sepia/grey mix). The shader never
sees mode *numbers*, only the two shapes; the CPU reduces mode→shape. A luma
recipe's `source ∈ {current, base}` selects whether it reads the
colour-so-far (modes 2/3) or the raw base (modes 6/7) — a field of the
recipe, **not** a compose axis. Byte-exact 5-bit quantization of the luma
integer math is a per-consumer parity knob orthogonal to the shape.
_Avoid_: "blend mode" / "PSX mode N" at the shader boundary (modes are a
CPU-side input; the shader sees affine/luma); treating `source` as an op.

**Consumer profile**:
The per-consumer knobs — `(param_scale, quantize, base source)` — that make
one shared [color stack](27-color-modes.md) faithful to whichever PSX applier a
consumer mirrors. FFT has **two distinct appliers** sharing only the 11-mode
classification, *not* one engine: the **palette tint**
(`color_tint_blend_apply @0x8008f710`, the shared backend for `{32}`/`{33}`/`{1A}`)
transforms a **5-bit CLUT** entry against the committed base palette
(`quantize=true`, `param ×1`); the **screen tint**
(`screen_tint_apply @0x80090840`) transforms the **16.16 framebuffer**
background feeding a full-screen gouraud quad (`quantize=false`, `param ×1`).
Neither doubles the param bytes — a Godot `×2` on the screen path is a
divergence, not faithful. Because the profiles genuinely differ, every
per-consumer knob is **named at its call site** (which consumer, which PSX
applier it mirrors), never a bare literal.
_Avoid_: "the combat 8-bit engine" as if one reduction serves both (palette is
5-bit CLUT, screen is 16.16 framebuffer); an unlabelled scale/quantize literal
(state the consumer and the applier it mirrors).

**Base colour**:
The `vec3` a colour-transforming shader produces **before** the [color
stack](27-color-modes.md) folds over it — the stack's starting `c`. Each
consumer computes its own: a sprite/map by indexed [palette](17-sprite-and-texture.md)
lookup, the combat background by a 4-corner bilinear gradient, the lit map
by gradient×Gouraud. The include is **base-agnostic** — sprites and Gouraud
surfaces are not different colour systems, only different base sources, the
direct mirror of how depth consumers supply their own representative point.
_Avoid_: assuming the include knows how base was made; treating the
gradient background as a special colour path rather than a base source.

**Commit** (a.k.a. bake, the `{66}` op):
Writing a settled tint **into** the palette in place —
`palette[i] := recipe(palette[i])` over every entry — so the stored colours
*become* the tinted colours. It is the **frozen form of a [color
layer](27-color-modes.md)** (a transform applied once and stored, instead of
folded every frame) and it **redefines [base colour](27-color-modes.md)**: after
a commit, a `source=base` [recipe](27-color-modes.md) and any later op read the
committed tint. This is why commit is *necessary*, not a mere optimization
(a post-lookup layer is invisible to a `source=base` read), and why it is
the **one irreversible, base-mutating path** — a backward seek past a commit
must rebuild base.
_Avoid_: calling commit an optimization (it changes base semantics);
conflating it with a [palette swap](27-color-modes.md) (commit *derives* new
colours `new=f(old)`; a swap *selects* different ones).

**Palette swap**:
Choosing a **different** set of colours (team-colour recolour, row-select
recolour) — **not** a [color layer](27-color-modes.md) and **not** a
[commit](27-color-modes.md). A swap *selects* a different pre-existing palette
(`new = otherCLUT`), where a commit *derives* one from the current
(`new = f(old)`). A swap changes *which* palette is sampled, upstream of the
fold, so it changes [base colour](27-color-modes.md) itself; the [color
stack](27-color-modes.md) then transforms whatever base the swap produced. Out of
scope for the colour include.
_Avoid_: modelling a swap as a layer or a stack op ("choose colours, not
transform them"); asking whether a swap goes at the top or bottom of the
stack (it is neither — it is upstream); confusing a swap (select) with a
commit (transform in place).
