# PSX→Godot spatial transforms sort into three classes: Placement, Orientation, Render

Every PSX-derived quantity that carries a position or a direction belongs to
exactly one of **three transform classes**, and the class — *not the file the
data came from* — decides where its PSX→Godot conversion lives. Naming the
classes turns the recurring, ad-hoc question "do I negate Y? subtract from
`size_z`? rotate the facing?" into a single lookup, and confines each historical
whack-a-mole bug to exactly one class.

## Status

accepted (2026-07-02). Generalises [ADR-0052](0052-psx-coords-rotate-180-around-x-at-parser-time.md),
which is now understood as the **Placement** instance of this rule. See also the
`CONTEXT.md` → **Spatial convention (Placement / Orientation / Render)** glossary
cluster, which holds the canonical term definitions.

## Decision: the three classes

**The classifier is one question:** does the quantity name *where* a thing sits,
*which way it is turned (stored)*, or *which way it appears from the camera right
now*?

### 1. Placement — *where a thing sits*

Mesh vertex, tile index, ENTD spawn tile, scenario Warp/Walk depth row,
Sprite-Move delta. Transformed by the ADR-0052 **180°-about-X rotation**
(Y-negate + depth-mirror `size_z-1-z`) at **parse time**, so the runtime reads
Godot-native coordinates and never negates or mirrors.

- **Home: the parser. No Placement stays flipped at runtime as an end-state.**
  The **scenario chunk** was the lone transitional holdout and is not one any
  more: #141 folded its flip into the parser like every other Placement
  (`extract_event.py::_flip_placement_rows`, ADR-0052 dec. 5). The parser emits
  the Godot-native consumed chunk and retains a raw byte-faithful `.raw.json`
  sidecar solely as reverse-engineering diff data (ADR-0052 dec. 12) —
  and live PSX RAM, not the committed JSON, is the real diff oracle. The
  placement opcodes (Warp / Walk To / Sprite Move) are settled RE, so
  pre-flipping them costs the active opcode-RE nothing. (An earlier framing
  deferred this "until scenario RE is done" — a never-fires trigger that just
  disguised a permanent exception; dropped.)

- **Absolute vs relative (the affine corollary).** The Placement transform is
  affine, `p_out = R·p + t`, where `R` is the linear part (the axis sign-flips of
  the 180°-about-X rotation) and `t` is the mirror translation (the `size_z-1`
  offset). An **absolute** position gets the full affine — that is where
  `size_z` enters. A **relative** Placement (a delta, a vertex normal, a
  velocity, an accel) is a difference of two absolutes, so `t` **cancels** and it
  gets the **linear part only**: pure sign-flips, no `size_z`, no origin. This is
  not a second rule — it is why Sprite-Move `+Y`→`-Z` *negates* (no `size_z`)
  while Warp *mirrors* (`size_z-1-z`), and why vertex normals negate X/Z with no
  `size_z`. The trap: a delta usually rides an absolute anchor
  (`target = home + delta`) — flip the anchor with the full affine, the delta
  with `R` only, then add; mixing frames is the retired Sprite-Move `+Z`/`-Z`
  bug.

### 2. Orientation — *which way a thing is turned, stored*

A unit's facing (its **orientation direction**), the `{19}` Camera opcode's
pitch/yaw/roll, `{2D}` Rotate, the deployment-zone record's **start facing** (which
way the player's squad is turned before anyone moves — the only source for it in a
`control == 0` battle, since the player's units are not in the ENTD at all).
Consumed **raw** — the parser's correct action is the *identity*.

- **Why raw:** the 180°-about-X rotation mirrors the camera and the world
  *together*. An orientation rendered against that co-mirrored camera is already
  correct; a second flip **double-corrects**. This is not a special case — it is
  the mathematical consequence of the rotation being *rigid* (two reflections
  compose to a rotation, and a rotation preserves relative angles).
- **"Identity" is about the FLIP, not about DECODING.** The rule above forbids a
  *chirality transform*; it says nothing about turning the ROM's **encoding** of an
  orientation into an angle, which is [ADR-0013](0013-fft-bitmask-decoding-lives-at-the-parser-boundary.md)'s
  territory and is required, not forbidden. **The discriminator is whether the
  function's input includes anything from the other frame.** `size_z`, the map, the
  live camera → a chirality transform on an Orientation, forbidden. Only the
  record's own bytes, reproducing arithmetic the engine itself performs → a decode,
  and it belongs at the parser boundary. `parse_entd.py` does both to one slot: it
  renumbers `y` and leaves the facing byte unflipped, while still *decoding* that
  byte (masked to its low bits, named) on the way out.
- Named **Orientation**, not "Pose": in graphics a *pose* is
  position + orientation, which would collide with Placement.

### 3. Render — *which way a thing appears from the camera right now*

The per-frame, **runtime-only** function turning a raw Orientation plus the
*live* camera angle into what the viewer sees — which billboard sprite frame +
mirror for a unit, cull-or-keep for a map polygon.

- **Home: the runtime.** It *cannot* live in a parser — its input (camera yaw)
  does not exist until runtime.
- **The sole home of cardinal names (N/E/S/W).** "North" is a Render label that
  no Placement or Orientation reads. So the long-standing unease — "we imposed
  NSEW arbitrarily, maybe wrong" — is *structurally confined to this class*. It
  cannot leak into the other two, because they have no cardinal names in them.
- **One truth, derived views.** The **orientation direction** (the raw facing
  angle) is the single source of truth. The `FacingDirection` world enum
  (gameplay/movement) and the sprite-pose atlas index are **derived views**,
  reached only through named, tested converters — never re-derived inline. The
  arrow only ever points **orientation direction → render direction**, never
  back.

## What each historical bug becomes under this model

The value of the model is that every past coordinate/facing bug is now a
*named category error*, not a mystery:

- **Scenario-4 facings 180° wrong** (`parse_entd.py` `0↔2` swap): applied a
  Placement flip to an Orientation. (Fixed — ADR-0052 dec. 10.)
- **"Ramza in the background"** (scenario chunk on raw rows): a Placement not
  flipped at its consume boundary. (Fixed — ADR-0052 dec. 5.)
- **The "E/S swap"** (`angle_12bit_to_facing`, harmonized 2026-06-30): used a
  **render direction** (sprite-pose atlas index) where an **orientation
  direction** (world enum) was required.
- **The deployment squad standing side-on** (`parse_placement.py`, fixed
  2026-09-10): read "identity" as *emit the stored bytes unchanged* and you refuse a
  decode. The deployment record's byte `0x07` holds two nibbles and the engine
  **composes** them (`R = zone_facing + unit_facing - 1`, ATTACK.OUT overlay
  `0x801C5588`; the four unrolled placement loops write a facing of `(-R) & 3`).
  Emitting the `unit_facing` nibble alone — the maximally "identity" move — is
  correct only when `zone_facing == 3`, which is Gariland's family and was the one
  battle it was calibrated against; the other three families deployed a quarter turn
  off. The fix, `start_facing_12bit`, is map-independent and carries no `size_z`, so
  dec. 2 holds unchanged: the record's *tiles* still take the Placement flip and its
  *facing* still takes none.
- **The visible-angles cull over-cull** (#135, reverted 2026-07-03): the
  per-polygon `+0xB0` cull table was mis-classified as **Placement** metadata that
  the ADR-0052 Z-flip must remap. It is **Render**: indexed by the *live* camera
  angle, not by geometry orientation. The runtime already feeds the true PSX
  camera angle, so remapping the table double-counted the flip and evaluated the
  cull at `−L` — over-culling ~13% of MAP062 (chapel) in the parked quadrant.
  Applying a Placement transform to a Render input is the same category error as
  the scenario-4 facing bug, just in the opposite direction. (The rigid-rotation
  argument in §2 above is exactly why no remap is needed: a rotation preserves
  relative angles, so once the camera angle is expressed in PSX-angle space the
  ROM table applies unchanged.)

## Considered alternatives

- **"Handle it all in the parsers" (the tempting monism).** Rejected because it
  is only right for **Placement**. It is a *no-op* for **Orientation** (raw =
  identity; there is nothing to bake), and *impossible* for **Render** (its
  input, the live camera, does not exist at parse time). Forcing all three into
  the parser is what produced the double-correction bugs (baking a flip onto a
  raw orientation).
- **"One flat coordinate & facing convention."** Rejected: the three classes
  have genuinely different data-flow (parse-baked / raw / per-frame), and
  collapsing them is exactly the conflation that made "where does this transform
  live?" un-answerable and re-litigated per feature.
- **Keep "Pose" as the class name.** Rejected: in graphics a pose includes
  position, colliding with Placement; and it reads as character-specific when the
  class also covers cameras and polygon normals.

## Consequences

- **New spatial quantities get classified on day one.** A future BATTLE.BIN
  position reader, a new scenario opcode, a new mesh attribute: sort it into
  Placement / Orientation / Render first, and its transform home is decided
  before any code is written.
- **The `camera_position_offset` runtime fudge knob is debt, by definition** — a
  runtime patch over a Placement verify-and-delete gap, slated for deletion after
  headful verification. (`psx_camera_angle_offset` is already deleted: the raw
  yaw → PSX-angle conversion is the true camera angle the Render cull test wants,
  with no offset.)
- **Render is the only class still carrying real debt** (three numberings, the
  converter discipline). Placement and Orientation are settled. Note the cull
  table itself is NOT debt: it is emitted raw and consumed at the live angle —
  #135's attempt to remap it was a category error (see the bug list above).
- **A decode is checked against the ROM and the corpus; only a flip is checked
  against this model.** The class model has nothing to say about whether a decode is
  *right* — that is a ROM question. So a decode earns its own two arms, not an ADR
  citation: the start facing carries `tools/score_deploy_facing.py` (the rule scored
  against two control arms — its mirror, and the nibble-only table it replaced —
  over every shipped battle, exiting non-zero unless it strictly beats both) and
  `tests/ScenarioPlacementDataTest.gd::_test_start_facing_points_at_the_enemy` (the
  served angle scored against the ENTD reds' positions, so the assertion cannot be
  satisfied by regenerating the artifact wrong). The ROM derivation and what about
  it is still unmeasured are in
  `research/working_documents/DEPLOYMENT_ZONE_START_FACING.md`.
- **Hard to reverse.** This reframes ADR-0052 and governs every map-coord- or
  facing-touching feature; treat it as load-bearing.

## Amendment (2026-08-28) — the model is built and its one transitional holdout closed, but a Placement this ADR never classified is flipped at runtime, and Render is no longer the class carrying the debt

*Audited 2026-08-28 against the tree at `docs/adr-consolidation`. This ADR had
no `## Decision` heading, so `ADR-0057 dec. N` resolved against nothing. The
`## The three classes` heading is now `## Decision: the three classes`, which
makes its existing `### 1./2./3.` items decision items — `dec. 1` is Placement,
`dec. 2` Orientation, `dec. 3` Render, matching the numbering already on the
page. No item was renumbered, no heading text below `##` was touched, and no
citation addressed the old heading (there are 93 citations to this ADR outside the generated `INDEX.md` / `AUDIT.md` rows, and none
name a section or a decision).*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
|---|---|---|---|
| 1 | Placement transforms at **parse time**; "No Placement stays flipped at runtime as an end-state" | **the stated holdout closed; a different one opened** | The scenario chunk is no longer transitional — see below. But the scenario **camera body's depth** is mirrored at runtime today, and it is a Placement this ADR never classified. |
| 1 | The affine corollary (absolute gets `R·p + t`, relative gets `R` only) | **yes** | `tools/extract_event.py:119-122` states it and `_PLACEMENT_DEPTH_OPCODES` at `:123` is `{"Warp Unit", "Walk To"}` — Sprite Move is deliberately absent. Vertex normals take the linear part only (`parsers/mesh.py:247-254`). |
| 2 | Orientation is consumed **raw**; the parser's correct action is the identity | **yes** | ENTD facing: `tools/parse_entd.py:122-129` renumbers only `y`, facing untouched. Camera yaw: `src/effects/PSXCameraConvert.gd:59-60` is now `deg_to_rad(yaw_deg)` — the `- 360.0` full-turn no-op was dropped for the literal identity this decision asks for. |
| 3 | Render is runtime-only; one orientation-direction truth, derived views through named converters | **yes, and it is golden-locked** | Three converters in one module — `AnimationStateController.angle_12bit_to_facing:97`, `angle_12bit_to_cardinal_bucket:125`, `pose_octant_to_atlas_cardinal:140` — pinned at the cardinals *and* the between-cardinal cases by `tests/RenderCardinalConverterTest.gd` (issue #138), which names this ADR in its first line. That test and `ReferenceRenderDirectionTest` are both in the suite (`tests/run_all_tests.sh:1889`, `:1894`) and neither is in `skip_tests.tsv`. |

### Dec. 1's "lone transitional holdout" closed a month before this audit

`### 1. Placement` (`:31-33`) says the scenario chunk "flips at the runtime
consume-boundary (`PsxNum.flip_depth_row`) **today**, and is being folded into
the parser … (test-first, #136)". #141 completed that fold:

- `tools/extract_event.py:126-149` (`_flip_placement_rows`) applies
  `size_z - 1 - y` to the placement Event-Y rows **at parse time**, stamping
  `_placement_flipped` / `_map_size_z` into the chunk (`:212-215`).
- `ScenarioVM._flip_depth_row` no longer exists. `PsxNum.flip_depth_row:142` and
  `flip_depth_continuous:153` remain as helpers, not as a consume boundary.
- The paragraph's own conditions are met: the parser emits the Godot-native
  chunk **and** retains a raw byte-faithful `.raw.json` sidecar as RE diff data.

`tools/parse_scenarios.py` records the resolution and cites this ADR by name.
Two other documents were still on the pre-#141 text — this ADR's own
`### 1. Placement` bullet, and
`docs/context/23-spatial-convention-placement-orientation-render.md`, the
glossary cluster the Status block calls canonical. Both were corrected on
2026-08-28 alongside ADR-0052's fold, because fixing this ADR alone would have
left the highest-traffic copy stale.

### A Placement this ADR does not classify is flipped at runtime

`### 2. Orientation` (`:58-60`) classifies "the `{19}` Camera opcode's
pitch/yaw/roll". `### 1. Placement` (`:25-26`) enumerates "Mesh vertex, tile
index, ENTD spawn tile, scenario Warp/Walk depth row, Sprite-Move delta". The
camera opcode also carries an X/Y/Z **position**, and it appears in neither list.

By this ADR's own classifier question — *does the quantity name where a thing
sits?* — the camera body's position is a Placement. It is mirrored at **runtime**:
`src/scenarios/ScenarioCameraDirector.gd:750-752` computes
`godot_pos.z = (map_size_z-1) - opcode_Y/112` through
`PsxNum.flip_depth_continuous`, gated on `camera_flip_body_depth`
(`:160`, default `true`, **no writer**). The docstring (`:142-158`) explains why:
an ortho camera filming a depth-flipped world from an un-flipped position gave a
constant ~+21px lateral error, and the fix is verified to the pixel (Agrias /
Ovelia / priest at native_par 107.6 / 148.4 / 66.7 against a live PSX screen
store of 107 / 147 / 68).

So the mechanism is right and measured; what is missing is the classification.
Dec. 1's end-state sentence is false today, and the exception it names is the
wrong one.

### Recorded question — where does the camera body's depth flip belong?

Two readings, and this pass does not pick:

1. **It is an ordinary Placement and dec. 1 means what it says.** Then the flip
   belongs in `extract_event.py` beside Warp and Walk To — the camera opcode's
   Event-Y joins `_PLACEMENT_DEPTH_OPCODES`, `camera_flip_body_depth` and its
   runtime branch are deleted, and dec. 1's end-state becomes true with no
   exceptions. Cost: the chunk's camera rows change, so the F19 pixel-parity
   result must be re-established against the regenerated data.
2. **The camera body is genuinely a runtime Placement.** The camera opcode is
   interpolated per frame by the VM (`ScenarioVM` drives the pose), so unlike a
   Warp row there is no static value in the chunk to pre-flip — the flip has to
   apply to an *interpolated* position, which is why it uses
   `flip_depth_continuous` rather than `flip_depth_row`. Under this reading dec. 1
   needs an explicit fourth sentence naming the camera body as a runtime
   Placement with a stated reason, rather than a silent exception.

The evidence leans to reading 2 — the continuous helper exists precisely for
this case and its docstring (`PsxNum.gd:146-152`) explains that
`flip_depth_row` would mis-flip a body sitting between rows — but the ADR is
silent, so the decision is not mine to make.

### Two Consequences have moved

- **"The `camera_position_offset` runtime fudge knob is debt, by definition …
  slated for deletion after headful verification"** (`:135-139`). It was
  deleted — #139, and four tests now assert its absence
  (`ScenarioChapelChainTraceTest.gd:90`, `ScenarioChapelChainSplineTest.gd:142`,
  `ScenarioChapelJerkProbeTest.gd:187`,
  `ScenarioCameraFloorAimCalibTest.gd:10`). One stale writer survives outside
  the guarded walk: `tools/diag_scenario_screens.gd:42-48` still assigns
  `_vm.camera_position_offset` from `OFFX`/`OFFY`/`OFFZ`, on an object where the
  member no longer exists.
- **"Render is the only class still carrying real debt (three numberings, the
  converter discipline)"** (`:140-142`). This is now the weakest sentence in the
  document. The three numberings are still three, but they are *named, converted
  through one module, and golden-locked* by `RenderCardinalConverterTest`, which
  was written for exactly this consequence. Meanwhile Placement carries the
  unclassified camera body above. On the measurement, the debt has swapped
  classes.

### The bug list grades 4 for 4

Every entry in *"What each historical bug becomes under this model"* is
confirmed by the tree, which is unusual for a list of this age:

- **Scenario-4 facings** — `parse_entd.py:122-129` renumbers only `y`; the
  `0↔2` table and `psx_face_to_our_face` are gone.
- **"Ramza in the background"** — fixed, and since #141 the flip is no longer at
  the consume boundary at all.
- **The E/S swap** — `angle_12bit_to_facing` and `angle_12bit_to_cardinal_bucket`
  are separate named converters, golden-locked at the byte-boundary truncate
  (`[0x000,0x400)→E … [0xC00,0x1000)→N`).
- **The #135 over-cull** — the `+0xB0` table is emitted raw (`parsers/mesh.py:28-43`,
  mask `0x3FFC` unremapped) and `psx_camera_angle_offset` is deleted;
  `addons/exmateria_battlefield/camera/PlayerCamera.gd:114-122` carries the
  double-count diagnosis as a source comment.

### On mechanizing this ADR

The guard column is `—`. Dec. 3 is already effectively guarded by
`RenderCardinalConverterTest`. The two unguarded halves are mechanizable:

1. **No Placement flips at runtime.** Assert that `PsxNum.flip_depth_row` and
   `flip_depth_continuous` have no callers in `src/` outside an explicit
   allowlist, and that the allowlist is empty (reading 1) or holds exactly the
   camera-body site with a comment citing this ADR (reading 2). This is the arm
   that turns dec. 1's end-state sentence from prose into a fact, and it is the
   arm that would have flagged the camera body.
2. **Every committed chunk is pre-flipped.** Assert no `scenario_*_chunk.json`
   carries `_placement_flipped: false`, and that its `_map_size_z` matches the
   map's `terrain.json`. `extract_event.py` already emits both fields; nothing
   reads them back. (Named identically in `docs/adr/audit-notes/0052.md` — one
   arm serves both ADRs.)
3. **Not mechanizable: the classifier itself.** "Sort a new quantity into
   Placement / Orientation / Render on day one" is a review discipline, not a
   predicate. The honest substitute is arm 1: it does not check that new
   quantities are classified, but it does make the one class boundary that has
   actually leaked twice impossible to cross silently.

Arms 1 and 2 are worth writing. Arm 1 should be written **after** the recorded
question above is answered, since its allowlist is the answer.
