# A colour crossing is a generic affine op with an opaque mode token

What `Effects` publishes to a tintable surface is a list of ops, each
`{scale, bias, duration, mode_token}` — multiply, add, over time, plus one
integer the wire does not interpret. The PSX colour model stays byte-exact and
comes off the interface by becoming a number.

Status: accepted (2026-08-20).

## Context

[ADR-0127](0127-effects-publishes-and-requires-two-ports.md) settles that the
colour lanes publish. It does not settle **what is in the message**, which
[#315](https://github.com/timbermania/fft-monorepo/issues/315) question 2 owes.

**Two shapes exist today for one job.** `palette` publishes a `ColorStack` — a
`Render` type carrying the PSX colour model itself, 5-bit CLUT values and the 11
blend modes, which the listener must fold through `psx_color_apply` before it has
a colour. `screen` publishes plain `Color` deltas, 0-1 floats, because
`ScreenSubsystem` folds *before* publishing. Same system, same job, two
interfaces — and the palette one means a stranger writing a tint listener must
implement PSX colour arithmetic.

**Bandwidth is not the constraint.** A folded colour is four floats delivered
in-process at 30 Hz; twenty tinted units plus map plus screen is on the order of
10 KB/s. The cost of publishing results rather than recipes lives somewhere else
entirely.

**The constraint is composition.** Several casts tint the same surface at once,
so the surface owner must combine their contributions. Colour operations do not
commute — *multiply by 0.5 then add red* is not *add red then multiply by 0.5* —
so summing independently-folded results yields a colour no effect asked for.
`MapTintOverlay.update_stack` takes the recipe precisely so it can concatenate
every owner's ops and fold **once, in order**. `ScreenEffectOverlay` gets away
with summing deltas (`compose_corners` sums then clamps) because its
contributions are additive in practice, not because summing is generally sound.

**A folded result is already a degenerate recipe.**
`MapTintOverlay.update_layer(owner_id, tint: Color)` takes a flattened colour and
expresses it as *"one scale=1 affine layer (bias = delta)"* through the same
stack seam. So the two shapes are not alternatives; one is a special case of the
other, and the machinery to bridge them is built.

**ADR-0118 dec. 4 already solved this shape once.** The compositing key is
published by splitting it: *"`layer`, `depth` and `anchor space` are generic;
`colour mode` travels as an **opaque token** the emitter never interprets."*

## Decision

**1. The published colour payload is a list of ops, each
`{scale, bias, duration, mode_token}`.** Scale and bias are generic affine
numbers in 0-1 float space. `duration` carries the ramp, in frames
(ADR-0122 dec. 6-7). `mode_token` is one integer.

**2. `mode_token` is opaque on the wire.** `Effects` does not interpret it and
neither does the schema. A listener that ignores it and applies the affine part
gets a sensible tint in about ten lines. A listener that honours it gets the
byte-exact ADR-0067 behaviour across all 11 modes.

**3. Composition stays with the surface owner.** The recipe is published, not the
result, so the owner folds all contributors in order. This is what keeps N
concurrent casts correct, and it is why the `owner_id` key on today's calls is
real compositing rather than singleton bookkeeping.

**4. The anchor port does not widen.** Because `Effects` publishes a recipe
rather than a folded colour, it never needs a surface's baseline. The blueprint's
*"an anchor answers position and orientation and nothing else"* survives — which
pre-folding would have broken.

**5. Three artifacts, three homes.** The distinction the ownership question turns
on:

| artifact | ships with |
|---|---|
| the **schema** (`{scale, bias, duration, mode_token}`) | the shared schema addon, alone (ADR-0121 dec. 5) |
| the **fold** (`psx_color_apply`, `ColorStack`) | `Render` — `assets/shaders/psx_color_stack.gdshaderinc`, per ADR-0121 dec. 6 |
| the **token registry** (*"mode 5 = baseline/2 + param"*) | `Render`, as its PSX profile |

**6. The schema is owned by neither end and by no implementer.** `Render` is at
neither end of a tint message: the map material is registered by
`DynamicGeometryBuilder` (`Battlefield`), the unit material by `Unit.gd`
(`Battle`). `Render` executes the recipe; it is not a correspondent. A schema
housed inside `Render` would make `Effects` depend on `Render`, and the most
pluckable system would drag a renderer behind it.

**7. `screen` and `palette` stop having two shapes.** Both publish this payload.
`screen`'s current `Color` delta becomes the scale=1 affine case that
`update_layer` already builds.

## Consequences

**The PSX colour model is removed as a concept, not relocated.** It survives
byte-exact where it already lives — `Render`'s shader — and leaves the interface
by becoming an integer. This is the move ADR-0123 made for landmarks: removing a
concept rather than adding one.

**A stranger's floor is the affine part.** Someone plugging their own renderer in
gets multiply-and-add with a ramp, ignores the token, and sees plausible tints
immediately. Faithfulness is opt-in and costs them a token registry, not a
rewrite.

**The four colour lanes fold into one payload type.** With `sound`/`landmark`
sharing one (ADR-0123) and the three camera lanes sharing another
(ADR-0122 dec. 8), nine of the ten lanes carry three payload types — see
ADR-0127 dec. 7.

**Untested: whether every shipped effect's palette ops express as affine +
token.** The screen path is proven affine — `ScreenSubsystem._push_gradient_op`
already models an absolute set as *"an affine with scale 0 (bias = target)"* —
and `update_layer` proves the delta case. The 11 CLUT modes are asserted to fit
because `ColorStack` already stores them as `rgb0`/`rgb1`/`meta` triples, but no
census has confirmed every shipped keyframe round-trips. That is a corpus query,
and it belongs to whoever builds the schema addon rather than to this decision.

**No code moves here.** Decision ticket on a planning map; pass 6 gates every
extraction and is gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299).
