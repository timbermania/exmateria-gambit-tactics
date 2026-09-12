# Rendering depth

FFT draws the battle scene back-to-front with a PSX **Ordering Table**.
This cluster names the concepts that decide draw position — the
scene-wide bucket axis with its per-primitive bias, a separate intra-unit
layer axis, and the intra-particle composite that lives inside one bucket
— and keeps them from being confused for one another. The historical
failure modes this cluster prevents: confusing a sub-bucket nudge with a
bucket bias; treating an intra-thing axis (unit layers, frameset frames)
as a scene-wide ordering.

**Ordering Table depth** (a.k.a. OT depth, OT bucket):
The painter's-algorithm sort key shared by **everything** drawn in
battle — terrain faces, unit sprites, effect particles, tile overlays,
projectile models all compete in **one** table. A primitive's key is the
projected screen-space depth of a single **representative point**, dropped
into one of ~383 buckets drawn far→near. The representative point is the
*only* thing that differs by primitive: a terrain face uses the average of
its vertices (its centroid, FFT's GTE `AVSZ4`); a sprite uses its object
point. There is therefore **one depth model, not two** — "per-face" (map)
and "per-object" (sprite) are the same formula fed different points,
chosen by **primitive count, not node-ness**: a mesh of one primitive (a
billboard quad — a unit sprite, a thrown-weapon/item projectile) takes one
object point; a mesh of *many* primitives that can overlap in screen space
(the map, *and a 3D projectile model* like the arrow's 17 colored Gouraud
faces) bakes a per-face centroid into `CUSTOM0`. The projectile is the
worked example that kills the "its own node ⇒ one point" intuition: a 3D
projectile is its own `Node3D`, but it is an ensemble and sorts per face
like the map — only the single-quad billboard projectile uses the object
point. Everything drawn in battle writes OT depth; the only axes that vary
are textured-vs-vertex-color and blend mode, never *whether* a mesh
participates (a vertex-color projectile model is opaque Gouraud — PSX has
no per-pixel alpha, only the STP blend modes — so it gets a plain opaque OT
shader, not `StandardMaterial3D`). See ADR-0009.
_Avoid_: treating map depth and sprite depth as different systems; "z-order"
(Godot's 2D term); assuming draw *call order* sets layering (only the
bucket does); using a mesh's node-ness (rather than its primitive count) to
pick the representative-point convention; exempting any battle mesh from OT
depth via `StandardMaterial3D` (Godot's true per-fragment depth is
internally consistent but mis-sorts against flat-`CUSTOM0` meshes at face
extents — the latent bug behind "projectiles seem to work").

**Depth mode**:
The per-primitive adjustment layered on top of [Ordering Table
depth](25-rendering-depth.md) that nudges a thing forward or back in the sort.
Two categories, both enumerated once in `addons/exmateria_schema/compositing_key/DepthMode.gd` and
applied through one shared shader function (`ot_depth`):

- **ROM modes** mirror FFT's own behavior. `STANDARD`,
  `PULL_FORWARD_8` / `_16` (relative — shift toward camera by N OT
  buckets), `FIXED_FRONT` / `_BACK` / `FIXED_16` (absolute OT slots).
  Relative-mode magnitudes are ROM bucket offsets scale-converted into
  the game's world units via `UNITS_PER_OT_BUCKET`; fixed modes write
  near-extreme reversed-Z constants and ignore the representative point.
- **Project nudges** are sub-bucket *"just in front of / behind the thing
  under me"* world-distance offsets that the ROM doesn't name, smaller
  than `PULL_FORWARD_8` (~1.5 tiles). `UNIT` (sprite just in front of
  its tile), `TILE_OVERLAY` (between tile surface and unit), `MAP_SKIRT`
  (border geometry just behind the textured map). Tuned in
  `DepthDebugScene`, not derived from the ROM.

Magnitudes for both categories must be **world-space distances**, never a
hand-tuned reversed-Z screen-space epsilon — an NDC epsilon can't be
derived from the ROM and is what produced the historical scattered
`+0.0001` / `-0.001` / `-0.0019` hacks ADR-0009 retired.
_Avoid_: inventing ad-hoc per-surface depth biases outside this named set;
expressing any mode as an NDC epsilon.

**Layer priority**:
A **separate axis** from [Ordering Table depth](25-rendering-depth.md) and
[Depth mode](25-rendering-depth.md): the paint order of a *single unit's own*
[layers](18-sprite-layers.md) (`BODY` / `WEAPON` / `EFFECT` / `STATUS_TEXT`)
relative to **each other**, extracted from the ROM (`layer_priority.json`,
the table at BATTLE.BIN `0x80094548`) as a small set of 24 orderings an
animation can select. It decides which of a unit's layers sits on top,
**not** where the unit sorts against terrain or other units.
_Avoid_: conflating layer priority (intra-unit layer stacking) with OT
depth (scene-wide draw order); calling the layers by their template names
(`TYPE1` / `WEP1` / `EFF1`) — those are [sprite types](18-sprite-layers.md),
not layer names.

**Frameset**:
The multi-quad composite an effect particle renders as for one animation
step — **one OT bucket, multiple overlapping frames**. The animation
sequence's `FRAME` opcode picks both the frameset and the
[`depth_mode`](25-rendering-depth.md) for that render; ROM's
`render_particle_to_sprite` reads `depth_mode` from the **sequence
opcode**, not from individual frames, so every frame in the frameset
shares the same OT depth. When `frame_count > 1` (E019's "Fire 4" has
84 such framesets) the frames overlap to form blur/thickness (same UV,
offset vertices — 78 of 84 in E019) or texture compositing (different
UV — 6 of 84), drawn in **frame-iteration order** at the **same depth**.
Iteration order affects pixel value only for non-commutative blend
modes (MIX, SUB, ADD25 — ADD, the most common, is commutative); it is
**not** a Z axis. See `research/wiki_articles/effect_frames_section.txt`.
_Avoid_: treating frame-within-frameset ordering as depth (it isn't —
there is no second depth axis inside a particle); a CPU sort that
expresses frame-iteration order as a Z epsilon (it is blend-composition
order, not depth); naming the concept "particle frame stack" or any
"stack" variant that implies Z.
