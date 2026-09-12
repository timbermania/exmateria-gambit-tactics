# Sprite variants

How the same authored sprite data renders for different camera angles and
how the SHP frame data composes pieces. Two flip axes (vertical / horizontal)
plus a back-vs-front choice. The cluster keeps three usages of the word
"revert" — one in [SHP](18-sprite-layers.md) data, two at runtime — from
colliding.

**Per-tile invert / revert** (a.k.a. flip flags):
A sibling pair of booleans authored into every [SHP](18-sprite-layers.md) tile,
on every frame, for every [sprite type](18-sprite-layers.md). **`invert` is a
vertical flip; `revert` is a horizontal flip** — the project vocabulary
is symmetric and deliberate. They live in the parsed
`assets/sprites/animations/*_shp.json` per tile (`tile['invert']`,
`tile['revert']`), and pass through `SpriteLayerManager._load_frame_by_id`
into the per-layer shader uniforms (`_inversions`, `_reversions`). A
[frame](18-sprite-layers.md) is a composition of tiles; the artist picks
invert/revert per tile to reuse a single texture rectangle in multiple
orientations.
_Avoid_: collapsing "invert" and "revert" into "flip" — the pair is the
point; losing one name loses the symmetry; treating per-tile revert as
the same thing as the camera-derived [camera variant](22-sprite-variants.md)
revert — they share the word, they're different axes (authored vs.
runtime); using "vertical_flip" / "horizontal_flip" instead of
"invert" / "revert" — those generic names mask that this project, the
SHP data format, and the wiki all use the invert/revert pair.

**Unit facing**:
Which of the four world compass directions a unit is turned toward —
`N` / `E` / `S` / `W`, one of the three inputs to
[animation resolution](18-sprite-layers.md) alongside
[activity](18-sprite-layers.md) and camera quadrant. It is a **world**
direction, authored and simulated; the camera never changes it. What the camera
changes is which authored frame paints for it, which is the [camera
variant](22-sprite-variants.md) below. **Published as
`ExMateriaSchema.Facing.Direction`** — 52 crossing uses, the widest of the five
moved enums after activity; `AnimationStateController` keeps its class name and
the snap (`angle_12bit_to_facing`), and names the kernel for its own control flow
([ADR-0217](../adr/0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md)
dec. 7).
_Avoid_: conflating facing with the camera-relative angle — `facing_angle` is
the twelve-bit value the [camera variant](22-sprite-variants.md) derives from
facing *plus* the camera offset, and only the first is state; reading a unit's
facing off whichever node happens to store it (see [world
state](18-sprite-layers.md)).

**Camera variant**:
The render-time pose-resolution: given a unit's world facing + the camera
quadrant, **which authored frame to paint and whether to horizontally
mirror it**. All variants derive from a single camera-relative angle
`(facing_angle + camera_offset) & 0xfff`, sampled at one of two
precisions depending on the **anim id range** the unit is currently
playing (see [Current anim id](22-sprite-variants.md)):

- **Cardinal precision (2-bit, 4 values)** — used by the SEQ-range anim
  ids (1..0x1f4). Yields `{use_back, revert}` derived from
  `rotated_dir = (face_dir + (CAMERA_BASELINE_QUAD − camera_quad + 4) % 4) % 4`:
  **`use_back = rotated_dir ∈ {1, 2}`** (unit faces away from camera) and
  **`revert = rotated_dir ≥ 2`** (mirrored half). Two authored variants
  (front + back), the other two reached by horizontal mirroring.
- **Pose-octant precision (4-bit, 16 values)** — used by the **idle**
  anim id (0). Yields `{frame_base ∈ 1..5, revert}` via the BATTLE.BIN
  per-direction LUT at `0x800680dc..0x8006812b` (40 halfwords, six
  sub-tables; see ADR-XXXX). The "frame_base tent"
  `1,2,2,3,3,4,4,5,5,4,4,3,3,2,2,1` picks among 5 authored static poses;
  the mirror flag is set for octants 9..14 (left-facing half). Five
  authored variants because PSX cinematic idle samples distinct
  side-poses cardinal-collapse can't reach. **The 2-bit precision is the
  top 2 bits of the 4-bit pose_octant** — the same angle, two
  resolutions; no extra angle math.

The whole-unit revert is fed to the shader as `global_reversion` and
composes with the per-tile authored [revert](22-sprite-variants.md) (both
apply). EVTCHR-range anim ids (≥0x1f5) bypass camera variant entirely —
see [Current anim id](22-sprite-variants.md).
_Avoid_: re-deriving the rotated_dir formula at the call site (it lives
once, in `_calculate_camera_relative_direction`); a "vertical camera
variant" (no such thing exists — units never need to render upside-down
per facing, so invert has no whole-unit camera counterpart); restarting
the [animation clock](19-animation-playback.md) when the camera variant
changes — variant is a paint-time concern, the clock keeps ticking
(ADR-0020 + the [body lead rule](19-animation-playback.md)); collapsing the
pose_octant into cardinal_idx for idle (the cinematic under-rotation
bug pre-Path-D — loses 3 of 5 PSX-faithful side-pose frames as a unit
rotates between cardinals); treating "use_back/revert" as the universal
camera-variant shape (it is the *SEQ-range* shape — idle has its own
shape, named `{frame_base, revert}`).

**Current anim id**:
The single integer field on Unit (`current_anim_id`, mirrors PSX
`unit+0x0c`) that names what the body layer is currently playing. **Two
writers, one renderer.** The combat-side resolver
([Animation resolution map](18-sprite-layers.md)) writes when an activity
changes; the event-script side (`ScenarioVM` consuming opcodes 0x11
Unit Anim and friends — FFT's "event scripts," **distinct from
[cinematic spell mode](02-combat-buffer-layout.md)** which is the per-cast
in-combat spotlight) writes the anim id directly. The renderer in
`_paint_body_variant` dispatches on the **value range**, mirroring PSX
`FUN_80085c0c`:

- **`0`** — idle. Paint resamples `pose_octant` per call and uses the
  [Camera variant](22-sprite-variants.md) pose-octant precision: SEQ slot 1..5
  + mirror flag, picked by Sub-tables A+B of the per-direction LUT.
- **`1..0x1f4`** — SEQ-range. Paint resamples `cardinal_idx` per call
  and uses Camera variant cardinal precision: `slot = (anim_id-1)*2 +
  {0,1,1,0}[cardinal_idx]` + mirror flag `{0,0,2,2}[cardinal_idx]`
  (Sub-tables E+F). This is the per-vsync re-sample that keeps the
  unit's body oriented to the camera as it rotates.
- **`≥0x1f5`** — EVTCHR. `slot = anim_id - 1` (no LUT — direct index
  into the EVTCHR atlas). **Deferred** until the runtime-pointer-table
  population at `0x800AED3C` is RE'd; today a `push_error` stub.

Writing `current_anim_id` restarts the playback clock (mirrors PSX's
`FUN_80084818` re-arm — pose-state quartet zeroed, frame counter
seeded). Re-sampling `pose_octant`/`cardinal_idx` does **not** restart
the clock — that's a paint-time concern (the existing Camera variant
rule generalised).
_Avoid_: a parallel `event_activity` or `script_anim_override` field
(the marriage problem this entry retires — PSX has one field, two
writers, not two parallel fields); routing `ScenarioVM` through the
Animation resolution map (the resolver maps activity→slot, but
event-script writes have no activity to map — they have an explicit
anim id); naming the event-script writer "cinematic" anywhere in code
or docs (it collides with the per-cast cinematic spell spotlight —
`CinematicManager`, ADR-0037 — which is a distinct concept that
pauses combat visuals); a
non-`(N, N+1)` front/back pair in `map.tres` (the strict adjacency the
SEQ-range dispatch encodes — the historical Resolution.body_back_slot
override was theoretical, the data is uniformly +1-adjacent today);
keeping the old `{body_slot, body_back_slot}` Resolution shape past
Path D (it duplicates the front/back duality the renderer now owns).
