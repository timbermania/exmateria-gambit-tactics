# Nothing needed to be faked — the lattice's test seam is a fixture over the production builder

ADR-0170 dec. 5 sanctioned two routes for a lattice mock: *"it must `extends Lattice`
and override, or the test constructs a real `Lattice`"*. Every test took the first
route. Six files now subclass the port and override it, four more wrap the result in a
`class *Map extends Node` that exists only to satisfy `ScenarioVM._lattice()`'s
duck-typed `"lattice" in map_composer` probe, and the doubles have drifted apart from
each other and from production.

The measured cost is not tidiness. `Lattice._edge_vertices_match` — the port's only real
computation, and the sole producer of the per-neighbour cliff byte `GPUBatchSimulator`
bakes into the GPU map buffer — **is executed by no test in the suite.** One double
overrides `is_cliff_edge` to `false`; the other five never set `_store`, so the inherited
body short-circuits at its null guard and also answers `false`.

The second route was always available and nobody took it, because nothing said how. This
ADR says how, and deletes the first route's ten classes.

Status: accepted (2026-09-01). Resolves
[#747](https://github.com/timbermania/fft-monorepo/issues/747) and
[#748](https://github.com/timbermania/fft-monorepo/issues/748); files
[#749](https://github.com/timbermania/fft-monorepo/issues/749). Amends **ADR-0170
dec. 5** in place.

## Context

### The doubles disagree, and production is not among their answers

Five of six produce a `TerrainCell` carrying only `grid`: `height`, `impassable`,
`unselectable`, `pass_through_only` and `surface_type` are dropped on the floor. Only
`MapBufferBoundsTest` sets `height` and `impassable`; only it and
`ScenarioCameraSwoopMonotonicTest` set `height` at all. **Nothing anywhere seeds
`unselectable`, `pass_through_only` or `surface_type`.**

`world_position_at` is spelled four ways for one physical situation — `Vector3.ZERO`
(`ScenarioSpriteMoveTest`, `ScenarioWalkToAnimTest`), tile centre `(x+0.5, 0, z+0.5)`
(`ScenarioWalkFacingAngleTest`), corner `(x, y, z)`
(`ScenarioCameraSwoopMonotonicTest`), and the node's real `global_position`
(`FakeBattlefieldMap`). Production is the tile centre: `DynamicTerrainBuilder.gd:165-166`
sets `tile.position = center`, the mean of the four supplied corners, and re-expresses
`tile_vertices` relative to it. So one of the four is right by accident and three are
wrong.

Three of the six are **unbounded** — `terrain_at` never returns null — so their consumers
never meet a map edge the real map has.

### The production path is four lines

`DynamicTerrainBuilder` is `extends RefCounted` with three preloads (`Tile`,
`MapConstants`, `TerrainIndex`). `add_terrain` mints the tiles *and* populates the store
itself (`:81`), and returns them orphan — only a `CollisionShape3D` child. No
`SceneTreeManager`, no `MapComposer`, no mesh:

```gdscript
var index := TerrainIndex.new()
var builder := DynamicTerrainBuilder.new()
builder.initialize(index)
builder.add_terrain(terrain_dict, "fixture", Vector2i.ZERO)
var lattice := Lattice.new(index)
```

`Tile._ready` is two statements (`add_to_group`, one `changed` connect) and needs only a
`SceneTree` main loop. The heavy prerequisites live in `set_highlight_type`, which a
terrain fixture never calls.

### Corner vertices are pre-baked, and there is no GDScript rule to reuse

`grep` for `Incline`/`Convex`/`Concave` across every `.gd` returns one hit, and it is
`ConvexPolygonShape3D`. GDScript never reads `slope_type` or `slope_height` to build
geometry — vertices arrive from `tools/fft_exporter/models/terrain.py:177`
`calculate_vertices()` through `terrain.json`. A fixture therefore either supplies
vertices as literal data or writes arithmetic that already exists in Python.

`DynamicTerrainBuilder.gd:154-162` already writes some: a private flat-quad fallback for
rows missing `vertices`, whose `0.25 * h * TILE_SCALE = 0.4464h` **disagrees** with the
exporter's `(12h+1)/28 = 0.4286h + 0.0357`. It is a second height convention in the tree,
reachable only by omitting a field no shipped `terrain.json` omits.

## Decision

**1. The test seam is a fixture over the production path, not a second adapter.** A
class implementing `Lattice`'s interface with its own cliff math is rejected by name:
`is_cliff_edge` is a gameplay threshold with two production callers and one
implementation, and a second one is the defect this ADR exists to remove — the doubles
*are* that second implementation, answering `false`. ADR-0170 dec. 5's first route
(`extends Lattice` and override) is **withdrawn**; the second route is the only route,
and dec. 2 below is what makes it cheap.

**2. `ExMateriaBattlefield.TerrainFixture` — a `Node3D` in the addon's production tree,
published on the façade.** It assembles a terrain dict, drives `DynamicTerrainBuilder`,
parents the returned tiles under itself, and exposes `.lattice`. Being a `Node3D` that
exposes `lattice` it satisfies `ScenarioVM._lattice()`'s duck-typed probe *and*
`TileCursor`'s `procedural_map_path`, so it replaces the four `*Map` wrappers as well as
the six doubles — **ten classes deleted, one added.**

It goes on the façade rather than being reached by path because
`check_lattice_scene.py` **enforces on `tests/`** — 122 of its 139 sites are there — so
eight host tests preloading `res://addons/exmateria_battlefield/…` would red criterion 4
eight times. The façade grows from 14 published names to 15. An addon that ships no way
to stand up its own port is an addon whose consumers fake it, which is the state this
ADR is unwinding; the fixture is not a concession to the guard, it is the thing
ADR-0194's argument implies.

**3. Production's tile-centre convention is the only convention, and divergent
assertions are re-based.** A tile sits at `(grid_x + 0.5, y_mean, grid_z + 0.5)`;
`tile_vertices` are corners relative to that centre, summing to `Vector3.ZERO`, which is
what lets `Lattice._world_vertices` stay translation-only. World Y per FFT half-step is
`0.428571 h + 0.035714`, plus slope lift. A fixture that preserved a test's private
convention would be the double again with extra steps.

**4. Fixture maps are bounded.** The three unbounded doubles get a box comfortably larger
than the walk under test. An "infinite plane" mode is rejected: it is a second
implementation wearing a flag, and no map in the game is unbounded — the edge those
tests skip is one their production consumers face.

**5. One height→vertex rule, shared with the fallback.** The fixture's flat form
generates the four corners with the exporter's arithmetic, never by omitting `vertices`
and taking the fallback. That arithmetic is extracted once and
`DynamicTerrainBuilder`'s fallback is routed through it, which closes the `0.4464h` vs
`0.4286h + 0.0357` disagreement as a side effect and proves the fix through the
fixture's own tests. Writing a third copy of a rule while filing a ticket about the
second copy is the wrong shape. **The fallback's differing corner *winding* is not
closed here** — see #749, and the amendment below, which closed it the same day.

**6. The interface is `put` / `put_shape` / `flat`, and `.lattice` builds lazily.**
`put(grid, height, flags)` covers sparse cells, holes and flags in one verb;
`put_shape(grid, vertices)` is the escape hatch that makes a cliff and a fractional world
Y statable without a second interface; `TerrainFixture.flat(Rect2i)` is the common case.
`build()` is optional because first access to `.lattice` performs it. Taking the
`terrain.json` dict directly is the right *internal* path and the wrong interface — it
makes every test learn the exporter's schema to say "a flat 20×20".

**7. Cliff coverage is two tests, one per side of the seam.** In
`addons/exmateria_battlefield/tests/`, seeded corner vertices assert `is_cliff_edge` true
across a step and false across a matched edge — it needs no game, per ADR-0194. In host
`tests/`, a seeded cliff is asserted to reach the baked map buffer through
`GPUBatchSimulator.build_map_data` — because `MapBufferBoundsTest` is the file that
hardcoded `false`, and a rule proven only inside the addon would not have caught that.

**8. All eight consuming test files convert in one pass.** Leaving one double alive
leaves the pattern alive for the next test to copy. `ScenarioCameraSwoopMonotonicTest`
carries the risk — its 8.18 / 0.46 / 3.25 world heights are load-bearing for a "the
camera never pins to terrain" assertion and no integer height produces them — but dec. 6's
`put_shape` states them directly, so it converts like the rest.

## Consequences

- `check_lattice_scene.py`, `check_lattice_ports.py`, `check_lattice_doors.py`,
  `check_addon_install.py` and `check_addon_globals.py` must still read **0**. Dec. 2
  moves `check_addon_globals`' published-name count from 14 to 15, which is a count the
  guard reports rather than bounds.
- Every test converted under dec. 3 runs against terrain it did not previously have:
  real heights, real flags, real bounds. A red found there is a finding with a ticket,
  not a conversion defect — and is the point of the exercise.
- `Tile._exit_tree` calls `TileOverlayCompositor.of().unregister(self)` unconditionally,
  so freeing a fixture constructs that singleton if nothing else has. In this repo
  `content_root` is set (`project.godot:66`) and it resolves; in a bare install it
  `push_error`s once. Noted, not fixed.
- ADR-0170 dec. 5's first route is withdrawn, so a future `extends Lattice` in `tests/`
  is a regression this ADR names. No guard scores it today.

## Alternatives considered

- **A second adapter with its own cliff math** (`Lattice.from_cells`, as first drafted).
  Rejected by dec. 1. It also cannot work as drafted: `is_cliff_edge` reads
  `tile.tile_vertices` and `tile.global_position`, and `TerrainCell` carries neither —
  deliberately, since ADR-0164 dec. 2 kept `world_position` off the cell because it
  derives from a live transform.
- **Extending `TerrainCell` with vertex data** so `from_cells` works. Rejected: it puts
  a staleness-prone geometry field on the shared kernel's schema row to solve a test
  problem, and re-opens ADR-0164 dec. 2.
- **Static factories on `Lattice` itself** (`Lattice.from_rows(…)`). Rejected: it widens
  the port's own interface with test-shaped constructors, against the depth this
  extraction has been buying.
- **A fourth `DECLARED_MOUNTS` entry** in `check_lattice_scene.py` so host tests could
  preload the fixture by path. Rejected: mounts are scene paths, this is a script path,
  and weakening a guard to fit one file is worse than the two other options.
- **Fixing the fallback's winding here.** Deferred to #749: deciding the right order
  means asserting behaviour for a row nothing produces, which is wider than converting
  test doubles.

## Amendment (2026-09-01): #749 closed — the winding was answerable, and "inert" was wrong

Dec. 5 deferred the fallback's corner order on the grounds that "deciding the right
order means asserting behaviour for a row nothing produces". That framing made it look
like a choice. It was not: the exporter has an order, and it is readable.

**Derived.** `models/terrain.py` `calculate_vertices` emits the FFT corners
`(-x, z) (-x, z+28) (-x-28, z+28) (-x-28, z)`. `exporters/coordinates.py`
`convert_position` negates X and flips Z about the map's far edge; `exporters/terrain.py`
`renumber_tile_z` renumbers the tile INDEX by the same flip. Compose them and the four
corners land, in grid units, at `(gx, gz+1) (gx, gz) (gx+1, gz) (gx+1, gz+1)` — exactly
`MapConstants.flat_quad`, which dec. 5 had already written down but never checked.

**Measured.** Every tile of every shipped `assets/maps/*/terrain.json` — **28,930 of
them**, both levels, all 13 slope types — carries that XZ order. Zero carry any other.
So the order is not a decision to be made; it is a fact with one witness per tile, and
the fallback's reversed cycle was simply wrong.

`DynamicTerrainBuilder`'s fallback now calls `flat_quad`, so it states neither of the
two rules it used to state twice. `TerrainFixtureTest`'s fallback leg asserts the four
corners **spelled out literally**, not fetched from `flat_quad` — asking the fallback to
match the function it now calls would assert nothing. Seeding the old cycle back in
fails exactly those four assertions.

**One claim of this ADR's is corrected.** `flat_quad`'s docstring called winding "inert
for everything that reads these today". Three readers are indeed indifferent — the
centre is a mean, the cliff rule is all-pairs, the collision shape is a convex hull —
but `Tile.gd`'s highlight mesh assigns corner `i` a **fixed** UV, so a reversed cycle
mirrors the RANGETILE crop on that tile. Face orientation is *not* a consequence, and
not by luck: both overlay shaders declare `cull_disabled` and record that a winding flip
is why. So the fallback was one latent visual difference away from mattering, in a file
that said it could not.
