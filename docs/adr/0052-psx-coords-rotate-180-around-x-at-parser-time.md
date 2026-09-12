# PSX coords rotate 180° around X at parser time

## Status

accepted. This is the **Placement** instance of
[ADR-0057](0057-psx-spatial-transforms-sort-into-three-classes-placement-orientation-render.md)'s
three-class model (Placement / Orientation / Render): the 180°-about-X rotation
below *is* the Placement transform, the pose carve-outs (camera yaw, ENTD facing)
are the **Orientation** class, and the runtime sprite-frame / polygon-cull
resolution is the **Render** class. Read 0057 first for the classifier; this ADR
for the Placement mechanics.

Verified 2026-08-28 — decisions 1–3 and 5–14 built; dec. 4's number is retired.
Dec. 5's named guard (`ScenarioSpriteMoveTest`) was quarantined red then; it runs
since 2026-09-01 (#752), and the red was never this ADR's depth mirror.

## Context

`ScenarioPlayer` reproduces PSX cinematic scenes (Orbonne Chapel, scenario 1)
frame-for-frame, so chirality parity matters. Converting PSX-Y-down to Godot-Y-up
by a single vertex-Y negation is **one reflection**, which flips chirality: units
appear left-right swapped, the altar lands on the wrong side of the frame, sprite
facings are 90° off. The tell is that the empirical fix which "looked right"
required a *glide reflection* — yaw −90° plus a horizontal viewport flip — and a
horizontal flip is a reflection, which is only needed because the underlying world
is mirrored.

## Decision

**At parse time, apply a 180° rotation around the X axis to every PSX-derived
coordinate.** The rotation is a composition of two reflections — the existing
Y-flip (kept) and a Z-flip (added). Two reflections compose to a rotation, so
chirality is preserved. The X axis is unchanged.

1. **Mesh vertices.** `z_out = (size_z_psx_units - z_psx) / 50`, where
   `size_z_psx_units = map_length_tiles * 28` (PSX uses 28 position-units per
   tile). The transform is a **composition across two files**, and neither reads
   as complete on its own: `parsers/mesh.py` emits `(-x, -y, z)` at read time and
   `exporters/coordinates.py::convert_position` then applies
   `(-x, y, size_z_psx_units - z)`. The net is `(x, -y, size_z - z)` — X
   unchanged, Y negated, Z mirrored. Read `convert_position` alone and its
   docstring says "negates X"; that is the second half of a double negation, not
   the rule.
2. **Tile indices.** `exporters/terrain.py::renumber_tile_z` gives
   `z_out = size_z_tiles - 1 - z_psx`, and the row iteration reverses to match so
   tile records in `terrain.json` are written in our-coord row-major order.
3. **ENTD spawn positions.** `tools/parse_entd.py::apply_chirality_fix_to_slot`
   renumbers **only** the depth tile: `y_out = size_z - 1 - y_psx`. Unused slots
   (`unit_id == 0xFF`) are left entirely untouched. Facing is not a placement —
   see dec. 10.
4. *(Retired. See `## Considered and rejected`; dec. 13 is the answer.)*
5. **Scenario-chunk placement rows flip at parse.**
   `tools/extract_event.py::_flip_placement_rows` bakes `size_z - 1 - y` onto the
   Event-Y of every opcode in `_PLACEMENT_DEPTH_OPCODES` — `{"Warp Unit",
   "Walk To"}` — and re-packs the record's `raw` hex from opcode plus params, so
   the consumed chunk is fully Godot-native with no PSX bytes lurking in it. A row
   outside `0 <= y < size_z` is disassembler over-walk past Event End (the string
   table walked as if it were opcodes, never executed) and is left byte-for-byte
   raw rather than mirrored to a negative row. The chunk stamps
   `_placement_flipped` and `_map_size_z` so a consumer can tell which form it
   holds, and the flip is gated on the extractor being handed a `placement_size_z`
   at all.
6. **Vertex normals take the linear part only.** A normal is a *relative*
   Placement — a direction, not a position — so it gets the axis-sign half of the
   transform and never the `size_z` mirror. Same composition as dec. 1:
   `parsers/mesh.py` emits `(-nx, -ny, nz)`, `coordinates.py::convert_normal`
   negates X and Z, and the net is `(nx, -ny, -nz)`.
7. **Winding reverses for both triangles of a quad** (`exporters/geometry.py`).
   The pre-existing pipeline
   had a single net Y reflection which a `v1↔v2` swap balanced; adding the Z
   reflection inverts the net winding, so both triangles reverse, not just one.
   For an FFT N-shape quad (`v0`=NW, `v1`=NE, `v2`=SW, `v3`=SE, diagonal
   `v1`–`v2`): tri1 `(v0,v2,v1) → (v0,v1,v2)`, tri2 `(v1,v2,v3) → (v1,v3,v2)`.
   The diagonal is preserved.
8. **Camera yaw is an Orientation, consumed raw.** `PSXCameraConvert` returns
   `deg_to_rad(yaw_deg)`. Because the camera body and the mesh content mirror
   *together* at parse time, the relative look-direction is preserved and no
   runtime yaw change is needed; the once-predicted `-yaw_deg` is a
   double-correction that blacks the scene. Pitch and roll are unaffected either
   way.
9. **No constant camera position offset compensates for chirality.** There is no
   such member on any object in `src/`, and four tests assert its absence
   (`ScenarioChapelChainTraceTest`, `ScenarioChapelChainSplineTest`,
   `ScenarioChapelJerkProbeTest`, `ScenarioCameraFloorAimCalibTest`). A constant
   world-X fudge drifts with yaw, so it can only ever mask a chirality bug, never
   fix one.
10. **ENTD facing is an Orientation, consumed raw.** The rotation flips PSX
    *placements* — the ENTD depth tile of dec. 3 — but not facings. A facing is a
    pose rendered relative to the camera, and dec. 8 already establishes that the
    camera body and the mesh mirror together, so a facing angle riding that
    co-mirrored camera needs no remap. The runtime lifts the raw 2-bit field to a
    12-bit world angle with `PsxNum.warp_facing_to_12bit` (`Facing << 10` — the
    ROM spawn-init rule at `0x80087c1c`): 0=E, 1=S, 2=W, 3=N. Spawn seeding uses
    the same lift, so there is one facing convention and not two.
11. **A relative depth delta takes the linear part only.** A Sprite Move
    (`{3B}`/`{6E}`) `+Y` is a difference of two mirrored absolutes, so the
    `size_z - 1` constant cancels and the mirror reduces to a sign flip.
    `ScenarioDecode.sprite_move_offset` negates the two flipped axes and mirrors
    neither: opcode `+X` (lateral) → world `+X`, opcode `+Z` (height, Y-down) →
    world `−Y`, opcode `+Y` (depth) → world `−Z`. Sprite Move is deliberately
    absent from dec. 5's opcode set for this reason.
12. **The committed chunk is Godot-native; the byte-faithful form is a sidecar.**
    `scenario_*_chunk.json` is consumed data and carries the dec. 5 flip;
    `scenario_*_chunk.raw.json` beside it is the raw PSX form, retained solely as
    reverse-engineering diff data. The real diff oracle is **live PSX RAM**, not
    either committed file, which is why keeping the chunk raw is not a
    prerequisite for verification and does not earn an exception to parse-time
    conversion.
13. **The scenario camera body's depth is mirrored at runtime, by the continuous
    helper.** `ScenarioCameraDirector` sets
    `godot_pos.z = PsxNum.flip_depth_continuous(opcode_Y / 112, map_size_z)`,
    falling back to the raw `z` when `map_size_z` is unset (VM-only tests and
    non-map scenes, which stay byte-for-byte untouched). The body sits at a
    real-valued depth rather than an integer tile row, so it takes the continuous
    form `size_z - z` and not dec. 5's `size_z - 1 - z`: a unit row `r` sits at
    `psx_z = r + 0.5`, and the tile-centring absorbs the `−1`. Without this the
    ortho camera films a depth-flipped world from an un-flipped position — a
    constant ~+21px lateral framing error. This is the camera **body**; the camera
    **yaw** remains raw (dec. 8).
14. **The per-polygon visible-angles cull table is Render-class and is emitted
    raw.** The mesh-resource header `+0xB0` table (mask `0x3FFC`, set means cull)
    is indexed by the *live PSX camera angle*, not by geometry orientation, so the
    Placement rotation must not remap it. At runtime the shader is fed the true
    PSX camera angle and the ROM-authored bits apply as-is, exactly as they did
    in-hardware, however the geometry was rotated for display — both sides of the
    test already live in PSX-angle space.

The runtime tile→world formula stays `Vector3(tile_x + 0.5, h, tile_z + 0.5)`,
because `tile_z` in JSON is already in our coord system after parse-time
renumbering. No PSX→world helper function exists and none is wanted: every
consumer reads JSON values that are already converted.

## Considered and rejected

- **`scale.y = -1` on the Map node**, leaving vertex data and tiles in raw PSX
  coords (Mr Gudenheim's `TacticsEngineG` approach). Mathematically identical to
  the parser-side Y-negation — both are single reflections, both flip chirality.
  His game looks fine because it is not reproducing PSX scene composition for
  parity; `ScenarioPlayer` is.
- **Mesh-only parser flip plus a runtime `tile_to_world` helper at every
  PSX-coord consumer.** The helper becomes permanent debt: any new consumer — a
  future ENTD-driven setup tool, a new scenario opcode handler — silently produces
  wrong coords if it forgets to call it, and the "remove helpers, fix parsers
  incrementally" exit clause realistically becomes "the helper layer is permanent."
  The failure mode is not hypothetical: the parse-time chunk flip below shipped
  *dormant* for four days for exactly this reason.
- **Renumber the mesh and every parser, but keep PSX-tile-numbered indices in
  `terrain.json` / `entd.json` for debuggability.** Still requires one runtime
  helper called from `cinematic_place`, `_op_camera` and roster spawn. The debug
  ergonomic of "tile indices match the PSX wiki" is small next to that:
  `psx_z = size_z - 1 - our_z` is one arithmetic step at the debugger boundary.
- **180° around Z instead of X.** Same chirality result, but it flips X and Y
  instead of Y and Z. The PSX Y-down→Y-up reflection already exists; pairing it
  with an X-flip is unnatural because X is the lateral axis, already correct in
  every scenario. The Z-flip pairs cleanly with the Y-flip we cannot avoid.
- **An empirical glide reflection** — yaw −90° plus a horizontal viewport flip.
  This is the observation that motivated the ADR, not a fix: it patches over the
  chirality bug rather than removing it.
- **Flipping the scenario camera's Event-Y at parse** (`y_out = size_z*256 -
  y_psx` in `parse_scenarios.py`) — *(dec. 4, never built: `parse_scenarios.py` is
  not the chunk producer, and the `flip_camera_y_q88` helper it named was dormant
  and has been removed. The number is retired rather than reused; dec. 13 is the
  answer.)*
- **Consuming the Camera opcode raw as a pose, body and all** — *(shipped
  2026-06-28, reversed: the yaw half is right and is dec. 8, but the body half
  left the ortho camera filming a depth-flipped world from an un-flipped position,
  a constant ~+21px lateral error. Dec. 13.)*
- **Flipping the scenario chunk at the runtime consume-boundary** (a
  `ScenarioVM._flip_depth_row` chokepoint, on the ground that the chunk is
  verification ground truth and must stay byte-faithful) — *(shipped 2026-06-28,
  reversed at #141: dec. 12 keeps the byte-faithful form as a sidecar and names
  live PSX RAM as the diff oracle, so the reason for the exception is served
  without an exception. Dec. 5 flips at parse like every other Placement.)*
- **Remapping the `+0xB0` visible-angles cull table as Placement metadata** —
  *(shipped as #135 on 2026-07-02, reverted 2026-07-03: it double-counted the
  flip. The runtime already feeds the true PSX camera angle, so remapping the
  table evaluated the cull at `−L` instead of `L` — off the cardinals this
  silently over-culled ~13% of the map in the parked quadrant, and MAP062 rendered
  black holes at camera angle `0xC10`, 268 polys culled against the correct 85.
  The remap, its in-place data migration, its golden re-record and its test were
  all reverted, and the `psx_camera_angle_offset` knob that was supposed to
  compensate stays deleted — it defaulted to 0 and the raw angle was already
  correct. Dec. 14.)*
- **Remapping ENTD facing** (swap `0↔2`, South↔North) — *(shipped, reversed
  2026-07-02: it was wrong and invisible for months, because the only side-by-side
  calibration reference was the Orbonne chapel cast and every chapel unit carries
  facing `3` (East), which a `0↔2` swap leaves untouched. Scenario 4 is the first
  scene with facing-`0`/`2` units and rendered them 180° wrong — enemies faced East
  not West, Agrias and her knights faced away from each other. `entd.json` was
  migrated in place and chapel stayed byte-identical. Dec. 10.)*

## Consequences

- `tile.z` in `terrain.json`, `entd.json` and the consumed scenario chunk no
  longer match PSX wiki tables or PSX-RAM dumps directly. Cross-referencing costs
  `psx_z = size_z - 1 - our_z`, one arithmetic step at debugger time.
- `tools/parse_map.py` runs two passes per map: parse terrain bytes first to get
  `size_z`, then parse mesh and geometry with `size_z` threaded through.
  `parse_entd.py` and the chunk extractor read each map's `size_z` from the
  already-emitted `terrain.json`; there is no sidecar `size.json`.
- Every PSX-coord consumer added in future inherits the convention: convert at
  parse, emit our-coord JSON, add no runtime helper. A new tool reading
  BATTLE.BIN positions applies the rotation itself.
- Decisions 1 and 6 are each split across two files, so neither reads as complete
  in isolation. That is the single most confusing thing about this ADR and the
  first thing to mechanize — see `## Verification`.
- The decision is hard to reverse: rolling back means changing every parser,
  regenerating all map / ENTD / scenario assets, and adding the runtime helper
  this ADR exists to avoid. Treat the chosen direction as load-bearing for any new
  map-coord-touching feature.

## Verification

- `tests/PsxNumTest.gd` pins both depth-mirror chokepoints — `flip_depth_row`
  (dec. 5) and `flip_depth_continuous` (dec. 13), including that the two differ by
  exactly the `+0.5` tile-centring and that a body at the map's flip centre is a
  fixed point of the continuous form only. It also pins dec. 10's
  `warp_facing_to_12bit` on all four field values.
- `tests/ScenarioSpriteMoveTest.gd::_test_walk_to_consumes_preflipped_rows`
  asserts dec. 5's post-reversal shape: rows arrive already flipped rather than
  being flipped on consume. **It runs** (2026-09-01, #752). It did not until then:
  the whole file was quarantined red on an unrelated facing case, so this ADR's
  most-revised decision had no executing guard. The facing case was never this
  ADR's depth mirror — `ScenarioWorld`'s `facing_direction` fallback wrote a
  12-bit angle into a 0..3 enum slot. The fallback is deleted, the skip row with
  it, and the stem is in `run_all_tests.sh`'s array.
- Four camera tests assert dec. 9's absent offset, and
  `tests/ReferenceRenderDirectionTest.gd` and
  `tests/ScenarioCastInitialFacingTest.gd` exercise dec. 10 end-to-end against the
  reference goldens. `tools/gen_reference_goldens.py` documents which scenes carry
  which raw facings, and why chapel can never be a facing-calibration reference.
- **Not yet built, and worth building.** (a) Feed `convert_position` and
  `convert_normal` a unit basis and assert the net Placement transform is
  `(x, -y, size_z - z)` with linear part `(x, -y, -z)`. That is the arm that
  proves decisions 1 and 6 without a reader composing two files in their head.
  (b) Assert no committed `scenario_*_chunk.json` carries
  `_placement_flipped: false`, and that each `_map_size_z` matches its map's
  `terrain.json` — the arm that would have caught a regenerated chunk silently
  losing the flip, at the data rather than at a unit test. Both are pure Python
  and need no scene; arm (b) serves ADR-0057 identically.
- Dec. 13 is **not** mechanizable as stated: "the camera body is depth-flipped" is
  a pixel-parity claim against a live PSX screen store, and the rig that
  established it is a capture comparison, not an assertion. The honest arm is
  narrower — assert `camera_flip_body_depth` is `true` and has a writer, so
  shipping it off becomes a deliberate act rather than an edit nobody notices. It
  has no writer today (#677, #670).
