# Spatial convention (Placement / Orientation / Render)

Every PSX-derived quantity carrying a position or a direction belongs to
exactly one of three transform classes, and the **class — not the data's file
of origin — decides where the PSX→Godot conversion lives.** Sorting a new
quantity into its class on day one is what retires the recurring "do I negate
Y? subtract from `size_z`? rotate the facing?" re-litigation. The classifier
is one question: does the quantity name *where* a thing sits (**Placement**),
*which way it is turned, stored* (**Orientation**), or *which way it appears
from the camera right now* (**Render**)?

**Placement**:
A position — where a thing sits: mesh vertex, tile index, ENTD spawn tile,
scenario Warp/Walk depth row, Sprite-Move delta. Transformed by the ADR-0052
180°-about-X rotation (Y-negate + depth-mirror `size_z-1-z`) at **parse time**,
so runtime reads Godot-native coordinates. The scenario chunk was the last
holdout and flips in the parser too since #141 (ADR-0052 dec. 5); the raw form
survives only as a `.raw.json` reverse-engineering byte-diff sidecar beside the
consumed chunk (ADR-0052 dec. 12). **No Placement stays flipped at runtime as an
end-state.**
_Avoid_: "coordinate" alone (an Orientation is an angle, still coordinate-ish —
say Placement when you mean a position); runtime-flipping a Placement that a
parser can convert — the only one left is the scenario **camera body**, which
sits at a real-valued depth rather than a tile row and takes
`PsxNum.flip_depth_continuous` at runtime (ADR-0052 dec. 13); **applying the
map's 180°-about-X rotation to an effect emitter offset** — effect-local
coordinates (`parse_effect.py`) are their **own spatial subsystem**, empirically
`Y`-only, and the `size_z` depth-mirror is a *map/scenario* geometry rule that
does not govern them (the retired "effect position flips Y but not Z, so it's
half-rotated" red herring; see [Directional field vs Extent
field](16-effect-studio-authoring-tool.md)).
**Absolute vs relative**: the Placement transform is affine (`R·p + t`). An
*absolute* position gets the full transform — `t` is where `size_z` enters
(`z_out = size_z-1-z`). A *relative* Placement — a delta, a vertex normal, a
velocity — is a difference of two absolutes, so `t` cancels and it gets the
**linear part only**: pure sign-flips, **no `size_z`, no origin** (Sprite-Move
`+Y`→`-Z` negate; normal X/Z negate). A delta riding an absolute anchor
(`target = home + delta`): flip the anchor fully, the delta linearly, then add —
never one without the other (the retired Sprite-Move `+Z`/`-Z` frame-mix bug).

**Orientation**:
Which way a thing is turned, stored independent of position — a unit's facing
(its **orientation direction**), the `{19}` Camera opcode's pitch/yaw/roll,
`{2D}` Rotate. Consumed **raw**; the parser's correct action on an Orientation
is the *identity*. The ADR-0052 rotation mirrors camera and world *together*,
so a facing rendered against that co-mirrored camera is already right — a
second flip double-corrects (the scenario-4 `0↔2` facing bug). Placement flips;
Orientation does not. **"Identity" is about the FLIP, not about DECODING**
(ADR-0057 dec. 2): turning the ROM's *encoding* of an orientation into
an angle is required, and the discriminator is whether the function's input
includes anything from the other frame — `size_z`, the map, the live camera
means a chirality transform and is forbidden; only the record's own bytes,
reproducing arithmetic the engine itself performs, means a decode and belongs at
the parser boundary (ADR-0013). The [deployment zone](12-strategy-phase.md)'s
[start facing](12-strategy-phase.md) is the worked case: byte `0x07`'s two
nibbles are composed as the engine composes them, and emitting one nibble
unchanged — the maximally "identity" reading — deployed three of the four zone
families a quarter-turn off. (Named "Orientation" not "Pose": in graphics a
*pose* is position+orientation, which would collide with Placement.)
_Avoid_: "pose" (implies position too — that's Placement's job); "facing" as a
synonym (Orientation also covers camera pitch/roll); applying a
chirality/`size_z` flip to an Orientation (the retired bug); conflating it with
Render (Orientation is the stored angle; Render is how it looks from the live
camera).

**Orientation direction**:
A thing's facing *in the world, independent of any camera* — which way a unit
is turned, stored raw as the clockwise facing angle (`0x000=E, 0x400=S,
0x800=W, 0xC00=N`, one turn `0x1000`). The **single source of truth** for
"which way"; camera-independent. Quantizes to a world-cardinal
`FacingDirection` (N=+X, E=+Z, S=−X, W=−Z) for gameplay/movement — coarser, but
still orientation-side. The arrow only ever points *orientation direction →
render direction*, never back.
_Avoid_: "12-bit wheel" / "heading" / "facing angle" (the wheel is just its
encoding — say orientation direction); "cardinal direction" (a cardinal is the
lossy 4-value *view*, not this continuous truth); using a **render direction**
(the sprite-pose atlas index) where an orientation direction is required (the
retired E/S-swap category error).

**Render** (a.k.a. **Render-convention**):
The per-frame, **runtime-only** function turning a raw Orientation plus the
*live* camera angle into what the viewer sees — which billboard sprite frame +
mirror for a unit, cull-or-keep for a map polygon. The **sole home of cardinal
names** (N/E/S/W): "north" is a Render label no Placement or Orientation reads,
so the "we imposed NSEW arbitrarily" uncertainty is structurally confined here.
Cannot live in a parser — its input (camera yaw) does not exist until runtime.
_Avoid_: baking a Render decision at parse time (input is live); treating the
visible-angles cull as parser data (the *table* is parsed; the cull *decision*
is Render).

**Render direction**:
A thing's facing *relative to the live camera* — the **orientation direction**
combined with the current camera angle, quantized **per-frame** to a billboard
frame + mirror (unit) or a keep/cull decision (map polygon). Camera-*dependent*,
derived, never stored, never authoritative. Where cardinal names get assigned
("north *from here*"). The three FFT cardinal numberings sort cleanly: the raw
wheel and the `FacingDirection` enum are **orientation directions**
(world-absolute); the sprite-pose atlas index is a **render direction**
(camera-relative) — crossing the two is the category error behind the "E/S
swap" bugs.
_Avoid_: treating it as world-absolute (it moves when the camera orbits);
feeding a render direction back in as an orientation direction; re-deriving the
orientation→render quantization inline instead of through the one tested
converter.
