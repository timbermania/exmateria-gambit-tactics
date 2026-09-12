# Terrain lattice

The vocabulary for the battlefield's ground: what a tile *is*, the two different
things "what is at (x, z)" can mean, why **(x, z) does not name one square**, and
the one rule that decides whether a unit walks an edge or has to jump it. The [battlefield camera](29-battlefield-camera.md)
aims at this grid; the [blueprint](37-the-blueprint.md) places the addon that owns it.

**Lattice**:
The **terrain-query port** — the single interface anything outside the addon uses
to ask about ground. Six public questions: `terrain_at(cell)` (what is at this
exact **terrain cell**, as a value), `ground_at(x, z)` (the lowest cell of a
**column**), `column_at(x, z)` (every cell of one, low to high),
`world_position_at(cell)` (where it is, as a `Vector3`), `all_cells()` (every
cell), and `is_cliff_edge(a, b)` (may a unit step between these two). Two more,
`_tile_at` and `_tiles`, are underscored and addon-internal: they hand back
**Tile** nodes, which would put the node type on the published surface, and the
producer-side register `check_lattice_doors.py` scores public members only.
Constructed over a **Terrain index** and answers `null` / `Vector3.ZERO` / `false`
when it has none — a `Lattice` with no store is not an error, it is an empty map,
which is why an unbound one silently reports a world with no cliffs anywhere.
The three point queries exist rather than one `terrain_at(x, z, level = 0)`
because a defaulted level is exactly the assumption ADR-0219 exists to make
visible: every call site would keep compiling and none would have stated anything.
Established by ADR-0164; `all_cells` added by ADR-0170, the column pair by
ADR-0219.

**Terrain level**:
The **third grid coordinate**, and the reason `(x, z)` alone does not identify a
square. FFT stacks at most **two** tiles per column — a bridge over the moat it
crosses, a catwalk over the floor beneath it — and the ROM bounds-checks exactly
that (`tile_ptr` @ `0x80183fb4`, `level < 2`, one 256-slot plane per level). It is
an **index**, latched: a unit *carries* its level and flips it as a discrete event
at the seat tile. It is never blended, and never inferred from **half-step
height** — MAP012's level-1 floor sits at `h15` and MAP083's bridge at `h9`, so no
threshold separates them. Not rare: **202 selectable level-1 tiles across 44 of
the 119 exported maps**.
🔴 `grid.z` is a *level*, not a world Z and not a height. The collision with
`Vector3` world coordinates is real, and this is where it is written down.
Established from the ROM by ADR-0219 and built by
[#789](https://github.com/timbermania/fft-monorepo/issues/789): the builder mints
**209 level-1 tiles on 45 of the 119 maps** (202 of them selectable; the other
seven are thick but unstandable slabs).

**Column**:
Everything at one `(x, z)` — up to `TerrainCell.LEVEL_COUNT` (2) **terrain cells**,
distinguished only by **terrain level**. It is the unit of *addressing* that most
of the game still uses and the unit of *identity* that none of it may use: a
camera, a weather emitter and a placement source each genuinely address a column
and mean its ground, while a unit's `current_cell` and a pathfinder's frontier hold
a cell. The **Lattice** makes the difference a caller states — `ground_at` answers
the lowest cell present (which is *not* always level 0, on a map whose ground plane
has a hole), `column_at` answers all of them. The [Tile cursor](29-battlefield-camera.md)
still names a column and not a cell, because *which* of two stacked cells a player
means is a control-scheme question ADR-0219 deliberately leaves open
([#795](https://github.com/timbermania/fft-monorepo/issues/795)).

**Ground plane**:
`TerrainCell.GROUND_LEVEL` (0) — the declared operating plane of everything that
indexes terrain by **column** rather than by cell. The GPU combat stack is the
population that matters: `GPUBatchSimulator.build_map_data`,
`DistanceFieldGenerator` and `PlacementPolicy` each pack a flat
`size_x × size_z` array, so a second cell in a column would be a *silent* last-write
wins. They filter `all_cells()` to the ground plane and say so. That is
behaviour-preserving — none of them ever saw a level-1 tile — but it converts an
assumption held by the store into one written at the site, which is the whole
lesson of ADR-0219: the defect was not hard to fix, it was impossible to see,
because every layer agreed to ignore the same byte. Giving the battle engine a
second level to fight on means widening those buffers, and is not the same work as
giving the *map* one.

**Terrain cell**:
The **value answer** to "what is at (x, z)?", and what the **Lattice** hands out
instead of the **Tile** node it reads it from. Six fields: `grid` (one vector, which is also
the key every occupancy `Dictionary` uses), `height` in FFT
half-steps, and four descriptors — `impassable`, `unselectable`,
`pass_through_only`, `surface_type`. `world_position` is deliberately **not** a
field: it derives from a live node transform, so it is the one fact that can go
stale without terrain changing, and it is a port query instead. A cell is a
**snapshot**; today no tile ever moves, so none can be stale. `TerrainCell.NONE`
(the vector's `MIN`, not `(-1,-1,-1)` — doodad offsets make small negatives legal)
is the shared sentinel for "unplaced / off-grid / no destination". Schema row 8,
owned by `exmateria_schema` so both sides can spell it.
`grid` is a `Vector3i(x, z, level)` — ADR-0219 amends ADR-0192 dec. 6 and ADR-0166
dec. 3 **on arity only**, all four of their reasons for a vector key (value
equality, one type for one concept, staleness, one spelling for the key) holding
unchanged for three axes. The axis order is the ROM's own at `tile_ptr`, so `.x` /
`.y` keep their meanings and every existing read stayed correct through the
change; the work landed at **construction** sites, which is where a level has to be
supplied and therefore where the thinking belongs. `TerrainCell.ground(x, z)` is
the one spelling for "I mean the ground plane", so grepping it is a complete
census of that assumption — a property `tools/check_terrain_level.py` keeps true.

**Tile**:
The **node** behind a cell — a `StaticBody3D` on collision layer 2, one per grid
square, minted only by `DynamicTerrainBuilder._create_tile` and parented under the
map's `Tiles` container. Carries everything a cell does plus what the cell
deliberately drops: `tile_vertices`, `slope_type`, `slope_height`, `depth`,
`thickness`, `shading`, `normal`, and the highlight machinery. The distinction that
matters: a **cell** is what gameplay reasons about, a **tile** is what the scene
renders and collides. Systems outside the addon get cells; only the cursor and the
camera reach tiles, through the two underscored doors.

**Terrain index**:
The store the **Lattice** reads — a `Dictionary` holding one **Tile** per
occupied square, filled by `DynamicTerrainBuilder.add_terrain` as it mints them.
Sparse by construction: a square with no tile is simply absent, which is how a map
states a hole and how `terrain_at` answers `null`. Keyed on the **terrain cell**'s
own `Vector3i`, so the moat and the bridge over it are two entries; a second
`Dictionary` buckets a **column**'s cells by `(x, z)` for `ground_at` /
`column_at`.
It was `_make_key(x, z) -> String` (`"x,z"`), which is **one slot per column** — so
iterating level 1 without changing it would have *overwritten* the level-0 tile
rather than sat beside it, trading a hole in the bridge for a hole in the water.
ADR-0219 dec. 4 **deleted** it rather than widening it to take a level: a `String`
key is a second spelling of an identity ADR-0166 dec. 3 already ruled must be one
type.

**Tile vertices**:
Four corner `Vector3`s **relative to the tile's own centre**, summing to
`Vector3.ZERO`. They arrive pre-baked from the Python exporter
(`models/terrain.py` → `terrain.json`); GDScript has no rule that turns
`slope_type` / `slope_height` into corners, and writing one would be a second
implementation of the exporter's geometry. Consumers rely on the zero centroid:
the cliff rule projects them translation-only (`vertex + global_position`), never
through the full transform, because tiles carry no rotation and changing that would
silently move a gameplay threshold.

**Tile centre convention**:
A tile node sits at `(grid_x + 0.5, y_mean, grid_z + 0.5)` — its position is the
*mean of its four world corners*, and the corners are then re-expressed relative to
it. So `world_position_at` returns a **centre**, not a corner, and callers that
place a unit take only the `y` from it and re-derive `x`/`z` as `grid + 0.5`
themselves. One world unit per tile. The convention is worth naming because it is
the thing test doubles historically got wrong four different ways.

**Half-step height**:
FFT states terrain height in integer half-steps; the world is continuous. The
exporter's conversion is `y = (12·(height + depth) + 1) / 28`, i.e. `0.428571` world
units per half-step plus a constant `0.035714` lift, with a slope adding
`slope_height × 3/7` to its lifted corners only. The integer stays integral in the
**Terrain cell** because both the CPU distance field and the GPU mover compare it
directly against a jump range. Distinct from **terrain level**: height is how far
up a tile's surface is, level is *which* of a column's two tiles you mean. The
ROM's own vertical unit is 12 world units against a 28-unit tile pitch.

**Cliff edge**:
The rule that decides whether a unit may **walk** between two adjacent squares or
must **jump**: their faces must share at least two corners, within `0.01` world
units. Fewer than two means one face steps off the other. It is the **Lattice**'s
only real computation, and the sole producer of the per-neighbour cliff byte
`GPUBatchSimulator` bakes into the GPU map buffer — the `is_cliff_edge` in
`combat_common.glslinc` is a *reader* of that baked table, not a second
implementation. Two production callers, and until ADR-0218 no test executed it at
all.

**Column adjacency**:
The rule that keeps **terrain level** out of the step vocabulary: a step goes to an
adjacent **column**, never "up a level". `EventPathfinder`'s direction table
(`DIRS`) is four entries and stays that way — it relaxes BOTH levels of each
neighbouring column on every step and lets the climb gate (**cliff edge** plus jump
range) decide *which* cell of it is reachable. Since ADR-0226 that expansion runs over
the ROM's own tiles rather than the `Lattice` (`RomTerrain` reads them out of
`terrain.json`), and a step may span more than one column — the LEAP. So walking onto the Igros
bridge from the bank is an ordinary east step whose landing happens to be level 1,
and stepping off it is an ordinary step back whose landing is level 0 — both fell
out of the existing rule with no new policy. The level is **carried, never
interpolated**: a mover blends world position and latches the level at the seat
tile, matching the ROM's witnessed field-at-a-time retirement. Nothing may compute
or infer a level from **half-step height**.

**Cell marking**:
What a **terrain cell** is currently being *said about*, as a named value —
`CellMarking.Kind`, owned by `exmateria_schema` so both sides can spell it
(ADR-0196 dec. 6). Six of them: the four `PLACEMENT_*` colours the deployment phase
paints, `CURSOR_ACTIVE` for the square the player is looking at, and `SELECTED` for
the one they have picked and walked away from. `SELECTED` exists because the march
pick used to paint `CURSOR_ACTIVE` — the pick and the cursor were writing the *same
value*, so nothing could tell them apart, and the pick vanished the moment the cursor
moved on. `src/strategy/` decides which cells are which marking; the addon decides
what one looks like (`TileOverlayConfig`). Never a bare `int`, so the two sides cannot
disagree about what `2` means.

**Highlight publish**:
`TileHighlights` — the addon's *second* published surface over the same store the
**Lattice** reads, and a **publish** rather than a port: a command with no reply
(ADR-0164 dec. 1). Three members, all keyed by the **terrain cell**'s own `Vector3i`:
`paint(cell, kind)`, `clear(cell, kind)` and `kind_at(cell)`. It is also the
**arbiter** — see **marking slot** — and since ADR-0221 the only writer of `Tile`'s
highlight at all, which `tools/check_highlight_writer.py` keeps true. A map exposes it
as `map.highlights` and a **terrain fixture** does too.

**Marking slot**:
The layer a **cell marking** occupies, so that a cell can wear several at once while
the **Tile** renders exactly one — the topmost occupied, in the order `TERRAIN_SET` <
`SELECTION` < `CURSOR`. The slot is **derived from the kind**, never passed: `paint`
takes a cell and a marking, and callers are relieved of the arbitration rather than
handed it in a new spelling. The four `PLACEMENT_*` kinds share `TERRAIN_SET` because
they are one statement about what a square *is*. Before ADR-0221 there was one slot on
the node and three writers with no arbiter, so the cursor's restore-on-leave erased a
march pick and `CursorController._process` re-asserted `CURSOR_ACTIVE` every frame to
hide the same collision on the one square where it did not show. Both are gone.

**Terrain fixture**:
The addon's shipped way to stand a **Lattice** up from data — a `Node3D` exposing
`.lattice`, published on the `ExMateriaBattlefield` façade. It states terrain
(`put` a cell, `put_shape` explicit corners, `flat` a whole rectangle), drives the
production `DynamicTerrainBuilder`, and owns the tiles it made. Nothing about it is
fake: the tiles, the store, the port and the cliff rule are all production, which is
the entire point — it replaced ten hand-written doubles that between them dropped
every cell field but `grid`, disagreed four ways about the **tile centre
convention**, and answered `false` to every **cliff edge** question ever asked.
Named for what it holds rather than what it replaces. ADR-0218; the ban on
`extends Lattice` doubles is the same decision's other half.
