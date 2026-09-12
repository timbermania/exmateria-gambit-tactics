# The cursor publishes a coordinate, and criterion 3 closes

`TileCursor` derives the `Tile` under itself from `grid_pos` and then handed both to
everyone: four `cursor_*` signals carried `(grid_pos: Vector2i, tile: Tile)`, and
`active_tile() -> Tile` handed the node out on demand. Those five members were the whole
of what ADR-0164 dec. 4 criterion 3 had left to close — the last rows on
`check_lattice_doors.DOOR_BURN_DOWN`, ruled by ADR-0164 dec. 3's ⚠️ (*"the payload should
be `Vector2i` alone"*) and explicitly deferred out of pass 6 by ADR-0192's Consequences.

The cursor's own file docstring has said since it was written that *"the cursor never
holds a `Tile` reference — Tile lifecycle is the map's concern; the cursor only names a
logical position."* That was true of its STATE and false of its INTERFACE, and this is
the pass where the two agree.

Status: accepted (2026-08-27), **built**. Loop **pass 7** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Realises
[ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 3's ⚠️ and closes its dec. 4 criterion 3, whose register was added by
[ADR-0166](0166-occupancy-is-battles-in-five-spellings-and-battlefields-sixth-is-inert.md)
dec. 4. Amends ADR-0166 dec. 4's table (the baseline is nine, not eight) in place.

## Context

Measured on `fix/lattice-port-register` after the pass-6 port landed.

- **`check_lattice_doors.py` read 5, all listed with an owner**: `active_tile` plus
  `cursor_moved` / `cursor_stepped` / `cursor_confirmed` / `cursor_inspected`. The
  baseline was **nine**, not ADR-0166 dec. 4's table of eight — #589 added
  `cursor_stepped` after that table was measured, and pass 6 closed four.
- 🔴 **NOT ONE HOST CONSUMER READ THE NODE HALF.** `FormationMapHost` bound it as
  `_tile` in three handlers and discarded it; `BattlefieldWiring._play_cursor_cue` did
  the same; `GPUArena._on_cursor_confirmed` did the same. The single host that *did*
  read it, `GPUArena._on_deployment_confirm`, spent it on
  `var cell := Vector2i(tile.grid_x, tile.grid_z)` on the next line.
- 🔴 **AND THAT COORDINATE IS `grid_pos`.** Every emit site sets `grid_pos` first and
  then resolves the tile FROM it (`move_to`, `_try_step`, and both `_unhandled_input`
  branches all go through `_get_tile_at(grid_pos)`), and `Lattice._cell_of` builds a
  cell's `grid` as exactly `Vector2i(tile.grid_x, tile.grid_z)`. The node half was never
  information — it was the coordinate, dereferenced, travelling beside itself.
- **The one caller that genuinely wants the node is inside the addon.**
  `CursorController._set_active_tile` paints `Tile.HighlightType.CURSOR_ACTIVE` on it,
  which is a per-NODE property. Criterion 3 is about the addon BOUNDARY, so an addon file
  holding a `Tile` is not a door.
- **The null check was a question about the grid, not about the node.**
  `_on_deployment_confirm`'s `if tile == null: return` asked "is the cursor over a real
  cell?" — a question the port answers directly with `terrain_at`.
- **Criterion 1 is not closed by this and was not going to be.** `Tile` is named on 46
  `.gd` lines outside the addon (excluding three lines of docstring prose in `Unit.gd`
  that merely narrate ADR-0166 dec. 1). Ten of the `src/` lines are
  `Tile.HighlightType.X`, which ADR-0193 dec. 2 declined to move.

## Decision

**1. The four `cursor_*` signals carry `(grid_pos: Vector2i)` and nothing else.**
ADR-0164 dec. 3's ⚠️, built. Four consumers lose a parameter they were already binding
to `_tile`; none loses a fact.

**2. `active_tile()` becomes `_tile_under_cursor()` — private, not deleted.** Criterion 3
scores a PUBLIC member with `Tile` in a return position, so privatising it is the whole
of the close; `CursorController` is an addon file and may call it, and it is the only
caller left outside `TileCursor` itself. Renamed rather than merely underscored because
`CursorController` already owns a field called `_active_tile`, and `_cursor._active_tile()`
beside `self._active_tile` reads as the same thing twice.

*Not deleted* — the alternative was for `CursorController` to reach `_get_tile_at(pos)`,
the two-argument helper. Same access, worse name at the call site: the controller wants
"the tile the cursor is on", which is a property of the cursor, not a lookup it performs.

**3. `GPUArena`'s off-grid guard goes through the port.**
`if lat == null or lat.terrain_at(cell.x, cell.y) == null: return`, with
`var lat: Lattice = lattice` bound first — see dec. 5. Same question, same answer, no
node.

**4. `DOOR_BURN_DOWN` is emptied, and both of its arms stay armed.** Nine rows, nine
closed. An empty burn-down is not a disabled guard: an UNLISTED door still reds arm 1 the
moment someone writes one. It is also not a silent one — `check_lattice_doors.py` prints
`TILE-DOOR REGISTER CLEAR` and says why that matters (*"no host can hold a lattice node,
so holders 3, 4 and 6 are impossible rather than merely counted"*).

**5. 🔴 THE PORT REGISTER CAUGHT THE FIX, AND THAT IS THE PASS'S BEST EVIDENCE FOR
ITSELF.** Replacing a held node with a lattice query creates lattice queries, and three of
the ones this pass wrote were duck-typed: `GPUArena`'s `lattice` field is declared on
`CombatHost`, and `check_lattice_ports` infers receiver types PER FILE, so a bare
`lattice.terrain_at()` in `GPUArena.gd` reads as an undeclared receiver; the two test
lambdas wrote `fake_map.lattice.terrain_at(...)`, a chained expression that binds no typed
handle. Arm 1 and arm 2 went from 0 to 1 and 0 to 8. Both are back at 0 through the port's
own answer — one `Lattice`-annotated slot per file, then calls through it. **Criterion 3
cannot be closed without criterion 2's register watching, because the close is a
node-to-query rewrite and a query is exactly what criterion 2 scores.**

**6. `Tile.HighlightType` stays where ADR-0193 dec. 2 left it.** Declined again, on the
same ground and with the number re-derived: moving the enum re-spells 43 addon-internal
references to close a criterion-1 namer this pass does not score. Criterion 1 fell 46 → 41
`.gd` lines as a side effect of this work; it is not this pass's target and is not
claimed as met.

> 🔴 **SUPERSEDED 2026-08-28 by [ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
> dec. 6 — see the fuller note at ADR-0193 dec. 2.** The enum moves to `CellMarking.Kind`
> in the schema. The number re-derived here was re-derived against the same wrong
> destination: `TileHighlights` cannot host it without re-creating the `Tile → TileHighlights
> → Tile` cycle, and neither decline said so. ⚠️ The scope sentence was also too small —
> criterion 1 names **six** symbols, of which `Tile` was the third largest and three were
> already at zero (ADR-0164 dec. 4 criterion 1's new ⚠️).

## Consequences

- **Criterion 3 of three is MET.** `check_lattice_doors.py` reads 0 of a target 0, rc 0.
  Criterion 2 reads 0/0/0. Criterion 1 has no guard at all — it is the one of ADR-0164
  dec. 4's three that nobody has mechanised, and whoever takes it inherits dec. 6 above.
- **Four public members with `Tile` in a return position remain, under
  INTERNAL-BUT-PUBLIC** — `TerrainIndex.get_tile` / `get_all_tiles`,
  `DynamicTerrainBuilder.add_terrain` / `remove_terrain_in_bounds`. ADR-0166 dec. 4
  excludes them by name because nothing outside the addon names them. Each is one caller
  away from arm 1.
- **The three cursor test fixtures still build real `Tile` nodes, and their stated reason
  was wrong after this pass.** They no longer hold one because a payload hands it to
  them; they hold one because the cursor RESOLVES one internally — `_refresh_mesh`
  anchors the dagger to `tile.global_position` and `CursorController` paints the
  highlight. Both go through `Lattice._tile_at`, which is why the `_FakeLattice`
  override of `_tile_at` is the one that matters. The docstrings say that now.
- 🔴 **A CONTROL IN THIS FAMILY EXPIRED ON SUCCESS FOR THE THIRD TIME.**
  `test_every_shipped_row_prints_above_the_verdict` iterated `DOOR_BURN_DOWN` and asserted
  the register's heading appeared. The register prints that heading only when it HAS rows,
  so at size zero the test became a loop over nothing wrapped around an assertion that
  could only fail. It is now `test_a_LISTED_row_prints_above_the_verdict`, which
  constructs both the door and the row — the same repair `check_lattice_ports` made one
  pass earlier. **The file's own docstring claimed "when the register reaches 0 these
  tests do not change", and it was false about one of its own twelve.**
- **A new seed pins the shape a CLOSED row actually has.**
  `test_a_row_whose_door_LOST_its_Tile_is_STALE` writes a member that exists, is called
  from outside, and returns `Vector2i`. The pre-existing stale test deletes the member
  instead — a different shape, and the one that would NOT have caught a scanner asking
  "does this name resolve?" rather than "is this name a door?".

## Alternatives considered

- **Delete `active_tile()` outright and let `CursorController` call `_get_tile_at`.**
  Rejected: see dec. 2. Same privacy, worse name.
- **Move the highlight paint out of `CursorController` so nothing needs the node.**
  Rejected as out of scope and probably wrong: `TileHighlights` (ADR-0193 dec. 1) is
  keyed by `Vector2i` and would serve, but `CursorController` is an ADDON file, so
  routing it through the publish buys no isolation — it converts a legal internal read
  into an indirection. The publish exists for `src/strategy/`, which is outside.
- **Keep `tile` on the payload and mark the four signals exempt.** Rejected — an
  exclusion expressed as an exemption is the failure #424 measured: it manufactures its
  own debt and cannot tell a triaged door from one that merely matches. The register is a
  burn-down precisely so that the answer is "delete the row", never "widen the filter".
- **Emit `TerrainCell` instead of `Vector2i`.** Rejected: `TerrainCell` is allocated per
  call (`_cell_of` constructs one), and `cursor_moved` fires on every step. The payload's
  job is to NAME a cell; a listener that wants the cell's fields has the port.
