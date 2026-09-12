# The lattice ships as one port and one publish, and `Tile` never crosses

`Battlefield`'s published interface is **not** two ports, and it is not the two
names the census reports. It is one **port** (the lattice query, answering with
values), one **publish** (the placement overlay), and a `StaticBody3D` that stops
crossing the boundary altogether. The split ADR-0159 dec. 11 found is real and its
axis was wrong: both consumers use both names, and the difference between them is
*which members* they touch.

And the register that was supposed to score the split cannot. A metric keyed on a
**bucket** cannot see a move inside it; a metric keyed on an inbound **total**
cannot see a reach that refuses a type. Both are the same hole in ADR-0131 dec. 7,
and this system has been sitting in the second one for the whole refactor.

Status: accepted (2026-08-25). Resolves
[#562](https://github.com/timbermania/fft-monorepo/issues/562) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3,
loop pass 5). Dec. 4 also records
[#561](https://github.com/timbermania/fft-monorepo/issues/561)'s `--delta`
finding, which until now lived only in a GitHub comment.

## Context

Every figure below was measured in `~/Repos/fft-monorepo-ext3-pass4` at
`5da42d558`, not quoted from a prior pass. `touch_matrix.py` holds per-symbol
inbound in `tools/.touch_cache.json` but **never prints it**; the tables here were
read out of that cache directly, which is itself a finding (dec. 3).

### The reading — `5da42d558`

Inbound to `Battlefield`, per symbol:

| symbol | lines | from |
|---|---:|---|
| `Tile` | **77** | `Battle` 72, assembler 5 |
| `TerrainIndex` | **22** | `Battle` 20, assembler 2 |
| `TileOverlayConfig` | 15 | `Debug` |
| `TileCursor` | 11 | `Debug` 4, assembler 4, `UI` 3 |
| `CursorController` | 8 | assembler |
| `PlayerCamera` | 8 | assembler |
| `SkirtConfig` | 4 | `Debug` |
| `MapGridOverlay` · `MapConstants` · `EventPathfinder` · `MapIlluminationDDA` | 2 · 1 · 1 · 1 | `Cutscene` ×3, `Effects` |

**150 lines over 11 symbols** (123 of them cross-*system*) — not ADR-0159's
predicted *"100 over 7"*. The prediction assumed the five `Debug` panels leave;
dec. 5 moved them and `Debug` now reaches **back in** on 23 lines, which the
prediction's inbound row did not carry.

`Battle → Tile` 72 splits `src/strategy/` **61**, `src/gpu/` **9**, `src/debug/`
1, `src/units/` 1 — **85%** placement, where dec. 11 read 81%. `Battle →
TerrainIndex` 20 splits `src/strategy/` 8, `src/gpu/` 12.

## Decision

**1. One port and one publish, not two ports — and the split is by capability,
not by consumer.** ADR-0159 dec. 11 read the interface as *"two names and two
clients"* and prescribed *"pass 4 should publish them as two."* Measured, that
axis does not cut the code.

**`TerrainIndex` is not an alternative to `Tile`; it is the only door to one.**
All **22** of its inbound lines are type annotations — declared vars, parameter
and return types. There is not one `TerrainIndex.`-qualified call anywhere in the
tree. Its used method surface is exactly **two**, `get_tile(x, z)` and
`get_all_tiles()`, and `add_tile` / `remove_tile` / `clear` have **zero** external
callers. Both used methods **return `Tile`**. You cannot publish `TerrainIndex`
without publishing `Tile`, so "two ports" was never two.

What does cut the code is `Tile`'s member surface, which is three disjoint
capabilities with three different client sets:

| capability | members | external clients |
|---|---|---|
| **terrain facts** (read) | `grid_x` `grid_z` `height` `impassable` `unselectable` `pass_through_only` `surface_type` `tile_vertices`, plus the node's `global_position` | `src/strategy/`, `src/gpu/`, the assembler, `Cutscene`, `Effects`, `Debug` |
| **highlight** (write, no reply) | `set_highlight_type` `clear_highlight` `current_highlight_type` | **`src/strategy/` only**, 14 lines |
| **occupancy** | `reserved_by` `try_reserve` `release` | **`src/units/Unit.gd` only** — i.e. [#554](https://github.com/timbermania/fft-monorepo/issues/554) |

`is_blocked`, `became_available` and `get_grid_coords` have **zero** external
callers; ADR-0159 dec. 10 already flagged the third as dead surface with a
divergent unit.

Applying ADR-0118 dec. 3's test — *"a port is a synchronous dependency, nothing
proceeds without the reply; a schema is fire-and-forget"* — separates them
without appeal to taste. The terrain query is a **port**, and ADR-0118 dec. 2
already declared it by name: **lattice**, one of the three. The highlight is a
command with no reply, so it is a **publish**. Occupancy is neither and stays
#554's.

⚠️ **The `src/gpu/` side is not "bulk reads."** `GPUBatchSimulator.build_map_data`
and `DistanceFieldGenerator.generate` take a **one-shot snapshot at init** —
`get_all_tiles()` flattened into a `PackedInt32Array` and a precomputed
neighbour/distance table, reading four facts per tile. The six *runtime*
`get_tile(x, z).global_position` calls in `GPUVisualBridge` and `CombatLoop` are a
**grid→world projection service**, which is a third shape dec. 11's table has no
column for.

**2. The lattice answers with values; `Tile` never crosses, and `TerrainCell` is
ADR-0118's eighth schema row.** The port publishes `terrain_at(x, z) ->
TerrainCell`, `world_position_at(x, z) -> Vector3` for the per-frame path, and
`is_cliff_edge(a, b) -> bool`. `Tile` stays a `StaticBody3D` inside the addon,
unchanged, which is what keeps this decision out of #554's way.

> ⚠️ **Amended 2026-08-25 by [ADR-0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md)
> dec. 2 at [#567](https://github.com/timbermania/fft-monorepo/issues/567).** Three members
> are not enough. `get_all_tiles()` is the second of the two used methods dec. 1 measured on
> door 1, and it has four external consumers — `DistanceFieldGenerator.gd:54`,
> `GPUBatchSimulator.gd:466`, `PlacementTileGenerator.gd:77` (all `Battle`) and
> `ScenarioUnitAlignmentDebugPanel.gd:137` (`Cutscene`) — every one of which reads only
> `TerrainCell` fields. The port publishes **four** members, adding
> `all_cells() -> Array[TerrainCell]`. Without it neither door can close.

**The consumers asked for this already, in prose, because the type system was
dodged.** Two of them declare the port in a comment:

- `src/effects/CinematicFacingResolver.gd:64` — `var _map  # MapComposer-like node exposing get_tile(x, z) -> Tile (terrain)`
- `src/scenarios/ScenarioWeather.gd:70` — `## MapComposer (or any node exposing get_tile(x,z) -> {global_position})`

The second is a **payload field-list written in English**. A third,
`Unit.get_current_tile()`, carries `# -> Tile (can't type hint due to circular
dependency)`. Twelve of the twenty-one external call sites already refuse the
node's type; that is `Cutscene` and `Effects` declining a dependency on a
`StaticBody3D`, not sloppiness.

> ⚠️ **Amended 2026-08-25 by [ADR-0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md)
> dec. 6 at [#567](https://github.com/timbermania/fft-monorepo/issues/567): true, and not
> the whole cause.** At least half the pressure is a **test seam**. Seven test files define
> their own `func get_tile`, and four return something that is not a `Tile` — a bare
> `Node3D`, an ad-hoc `MockTile`, and two `FakeTile extends RefCounted`. The source says so
> by name: `src/scenarios/ScenarioVM.gd:3788` probes `"impassable" in tile` under the
> comment *"Mock maps without an `impassable` field count as walkable."* This strengthens
> the decision — a `TerrainCell` is trivial to fabricate where a `StaticBody3D` is not, so
> the value payload removes the pressure that created the pattern and ≥4 mock classes are
> deleted rather than ported — and it retires the *"port answers the node"* runner-up on a
> second ground: it would have kept the test seam painful.

**It also forces the occupancy keys off object identity.**
`PlacementTileSet.claimed_tiles.has(tile)` and `tile in player_tiles /
enemy_tiles / contested_tiles` key on the **node reference**, read by
`PlacementTileHighlighter` (3), `StrategyPhaseManager` (2), `GPUArena` (1) and
`CursorConfirmEndToEndTest` (1). A value payload makes the key
`Vector2i(grid_x, grid_z)`. That is exactly the demux ADR-0159 dec. 10 asked for,
and it converts #554's untyped `Dictionary  # Tile -> Unit` — the widest holder of
the occupancy concept and the one `touch_matrix.py` states it cannot see — into a
typed, visible one. **This hands #554 a better starting position rather than
colliding with it**, which is what the ticket asked us not to decide twice.

`is_cliff_edge` is on the port because `TileTraversalUtils.do_edge_vertices_match`
computes a **terrain** fact from `tile_vertices + global_position` and currently
lives in `src/gpu/`, i.e. in `Battle`.

**Where `TerrainCell` lands is mechanical, and the ADR is a precondition rather
than a record.** ADR-0139 dec. 3 makes schema membership the whole admission test,
and states the gate: *"to add a member you must first add a schema, which means
naming a payload and the two systems it crosses between, in an ADR. A file move
cannot do it."* So this decision is what makes pass 6 able to write the type at
all. Both mechanical vetoes pass, checked rather
than assumed:

- **sink veto** (dec. 4a) — a `TerrainCell` of `grid_x`, `grid_z`, `height`,
  `impassable`, `unselectable`, `pass_through_only`, `surface_type`,
  `world_position` has **zero outbound edges** into any system, `content` or
  `platform` bucket. This is the veto that killed `Character.gd` on three.
- **autoload veto** (dec. 4b) — it is a `class_name` value type the consumer
  receives, not an ambient global.

So `TerrainCell` goes in **`addons/exmateria_schema/`** as the kernel's **third
code member** (after the compositing key and the colour model), and ADR-0118
dec. 1's table becomes **eight rows** — a count ADR-0139 dec. 14 already had to
correct once. `Battlefield → schema` grows, and #561 already recorded that row as
*"a declared addon dependency, not debt."*

> ⚠️ **Amended 2026-08-27 by [ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)
> dec. 6 at loop pass 6: the field set is SIX, not eight, and `world_position` is the
> field this decision itself names as the liar.** `world_position` comes off — the 🔴
> below says a payload is a snapshot and that `world_position_at` is staleness-free where
> `terrain_at` is not, and the eight sites reading `get_tile(x, z).global_position`
> already hold `(x, z)`, so `lattice.world_position_at(x, z)` is a shorter expression
> rather than a detour. `grid_x` / `grid_z` become one **`grid: Vector2i`**, matching the
> key ADR-0166 dec. 3 already lands holder 4 and `claimed_tiles` on. `unselectable`,
> `pass_through_only` and `surface_type` stay (one read each in `src/`, all three in
> `PlacementTileGenerator._is_valid_for_placement`) and the water-exclusion rule stays in
> `Battle`. Both mechanical vetoes are unaffected: the sink veto passes a fortiori on a
> strictly smaller field set, and the autoload veto is about shape.

🔴 **The cost, stated because the design does not remove it.** A payload is a
**snapshot**. `world_position` derives from a live node transform, and
`TerrainIndex.add_tile` / `remove_tile` exist explicitly *"for future dynamic
modifications."* Today every tile is built once by
`DynamicTerrainBuilder._create_tile` and never moves, so no snapshot can be stale;
the day terrain mutates, a held `TerrainCell` lies. `world_position_at` returning a
scalar keeps the hot path allocation-free and staleness-free, but `terrain_at` does
not, and no instrument on this map can represent it. **Whoever makes terrain
dynamic owns re-opening this decision.**

**3. The port ships; it is not injected — and the twelve invisible sites are the
proof, not the prediction.** ADR-0159 dec. 3 ruled this for `platform` on the
grounds that *"injecting a handle does not sever that; it **hides** it"* and
*"the guard scores a declaration."* There it was a mechanism argument. Here it is
already measured.

There are **three doors** into the lattice query, and the census sees one:

| door | external call sites | systems | scored |
|---|---:|---|---|
| `TerrainIndex.get_tile` / `get_all_tiles` | **9** | `Battle` only | 22 lines |
| **a duck-typed map handle → `.get_tile`** | **12** | `Cutscene` 9, `Battle` 2, `Effects` 1 | **0 lines** |
| `Unit.get_current_tile()` | — | `Battle` | 0 lines |

The receivers are `map: Node3D`, `var _map`, `map_composer`, `_vm.map_composer`.
`MapComposer.get_tile(x, z) -> Tile` is a **second implementation of the same
query**, and `MapComposer` does not appear in the inbound census **at all**.
`ScenarioVM` reaches it 5 times, `ScenarioCameraDirector` 3, `ScenarioWeather` 1 —
so **`Cutscene` is this system's second-largest client and its inbound reads as 4
lines.** No pass on this map has seen it. The collapse of the two implementations
and the disposition of those twelve sites is
[#567](https://github.com/timbermania/fft-monorepo/issues/567).

> ⚠️ **Amended 2026-08-25 by [ADR-0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md)
> dec. 1, 3 and 4 at [#567](https://github.com/timbermania/fft-monorepo/issues/567).** The
> finding stands; the table is wrong on two rows and the prose on one noun.
>
> - **`MapComposer.get_tile` is not a second implementation.** `src/map/MapComposer.gd:308-311`
>   is a three-line null-guarded forwarder to `terrain_index.get_tile`, and `get_all_tiles`
>   (318-321) the same. The guard is load-bearing (`terrain_index` is null before the map
>   builds). ADR-0170 dec. 1 drops both rather than keeping a forwarder.
> - **Door 2 was under-counted.** The `src/` population is **15 lines over 6 files**, not 12:
>   twelve `.get_tile` sites, one `.get_all_tiles`
>   (`ScenarioUnitAlignmentDebugPanel.gd:137`, which `classify()` books to **`Cutscene`**,
>   making its share **ten**), and two `has_method(<port method>)` guards. A further **20**
>   sit in `tests/`, where `classify()` returns `None`.
> - **Door 3 is not a door.** `Unit.get_current_tile()` reads a **stored field** and queries
>   the lattice never; it is ADR-0166's holder 4, already decided. Its circular-dependency
>   dodge is dissolved twice by ADR-0166 — dec. 1 deletes the four `Tile.gd` lines that name
>   `Unit` (70, 201, 213, 234, all occupancy), and dec. 2 makes the return `Vector2i`.

Therefore `exmateria_battlefield` **publishes a named `Lattice`** and consumers
name it. **Pass 9 should expect the inbound number to RISE**, and should read that
as the win: twelve reaches becoming visible is the register catching up with the
code, not the seam getting worse. A prediction that only looks good when the
number falls is the one this loop keeps being fooled by.

⚠️ **A fourth invisible crossing, recorded and not fixed here.** `TileCursor`'s
three signals declare `tile: Tile` in their payload. `FormationMapHost` (**`UI`**,
three handlers) and `GPUArena` (assembler) receive it as untyped `_tile` and
**discard it**; only `Battlefield`'s own `CursorController` reads it.
`touch_matrix.py` scores all four sites 0 because an untyped parameter carries no
type name. The published payload ships a `Tile` into `UI` that `UI` does not want,
and the payload should be `Vector2i` alone.

> ✅ **BUILT 2026-08-27 by [ADR-0195](0195-the-cursor-publishes-a-coordinate-and-criterion-3-closes.md).**
> All four `cursor_*` signals (the fourth, `cursor_stepped`, was created by
> [#589](https://github.com/timbermania/fft-monorepo/issues/589) after this was written)
> now carry `(grid_pos: Vector2i)` alone, and `active_tile()` became the addon-internal
> `_tile_under_cursor()`. This paragraph's "only `CursorController` reads it" is the
> reason the accessor was privatised rather than deleted. It understated the discard by
> one, too: `BattlefieldWiring._play_cursor_cue` bound and dropped it as well. And the
> node half was never information — every emit site sets `grid_pos` first and resolves
> the tile FROM it, so the payload carried a coordinate and the same coordinate
> dereferenced. Criterion 3's register (dec. 4 below) now reads **0 of a target 0**.

**4. A register keyed on a bucket cannot see a move inside it; a register keyed on
an inbound total cannot see a reach that refuses a type. Both are ADR-0131 dec. 7's
hole, and this is the first ADR to say so.** Dec. 7 exists so *"a system extracted
by deletion"* cannot read as extraction. It has two duals, and the refactor has
already shipped through one of them.

**(a) The bucket face — #561's finding, recorded here because it lived only in a
GitHub comment.** `("addons/exmateria_battlefield/", "Battlefield")` books the
moved files to the same bucket `("src/map/", "Battlefield")` booked them to, so the
lines column reads **identically before and after the move**. `--delta` against
`8360` will print roughly `Battlefield 7912 −448`, and every one of those 448 is
dec. 4 / dec. 5's pass-4 severance — **not one line of it is the extraction**. Run
pass 6, move zero files, and the number is the same. **Extraction #1 (`Render`)
shipped through this gap unnamed.** The positive evidence is #565's set-equality
manifest, `path_refs.py`'s re-pointed strings, and a `Battlefield` scorecard
existing at all — three readings that key on something the move changes.

**(b) The total face — this ticket's finding.** Under dec. 1–3, `Tile` and
`TerrainIndex` stop being inbound symbols and the inbound line count falls. It
falls **identically** if pass 6 implements the port as an injected untyped handle,
which is what all twelve invisible sites already are. **A register keyed on an
inbound total cannot tell the fix from the hiding.**

**So pass 9 scores this seam by sets, never by a total:**

1. **Published-symbol set equality.** The set of `Battlefield` `class_name`s named
   by any other system's source must **equal** the declared published set exactly,
   with `Tile`, `TerrainIndex`, `MapComposer`, `TileCursor`, `CursorController` and
   `PlayerCamera` **absent from it**. Difference computed both ways, on #565's
   precedent: a fact about a named set, not a number that moves for two reasons.

   > ⚠️ **Amended 2026-08-28 by [ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
   > dec. 2, 3 and 4 at loop pass 8: "equal … both ways" is unpassable, and a node path is
   > not a `class_name`.** Three separate corrections, all measured on `3e0343f97`:
   > **(a)** Of the addon's 30 `class_name`s, **16 are named by nothing outside it**
   > [🔴 measured by the built register: **13** are named by nothing outside the addon at
   > all, **20** by nothing in `src/`; 16 matches neither], so the
   > reverse difference reds permanently on names whose only defect is that no host wants
   > them yet — and enforcing it would make *deleting* a host call site red the guard. The
   > forbidden difference is **enforced**; the declared difference is **reported**, and the
   > declared set is a literal in the guard, never the README's prose (whose own ⚠️ admits
   > it was stale twice). Today's honest published set is **nine**, not thirty.
   > **(b)** The criterion scores **type references**. `$PlayerCamera`,
   > `get_node_or_null("PlayerCamera")` and a `.tscn` instancing `PlayerCamera.tscn` are
   > couplings to a SCENE TREE; criterion 1 exists so the *compiled* surface is narrow.
   > **(c)** Three of the six forbidden names were **already absent** and no instrument
   > said so: `TerrainIndex` 0 (unnameable since ADR-0192 dec. 4), `MapComposer` 0 (its two
   > non-comment lines are a trailing comment and a docstring body), `PlayerCamera` 0 (all
   > 28 are node paths) — all three confirmed at 0 by `tools/check_lattice_publish.py`. The
   > real population is `Tile` 10, `TileCursor` ~~9~~ **13**, `CursorController` 8 —
   > ~~27~~ **31**, and ~~17~~ **21** after the enum moves. 🔴 Two independent under-counts
   > on one symbol: the hand count dropped three `@onready var tile_cursor: TileCursor =
   > $TileCursor` lines — a type ANNOTATION sharing its line with a node path, and (b)
   > excludes the node-path OCCURRENCE, never the line — and the register's own first draft
   > dropped a fourth, `CursorDebugPanel.gd:85`, where a `#` opening a format string
   > truncated the line before a real static read.
   > 🔴 The register PRINTS the scene-tree term (107 `.tscn` files instance `PlayerCamera`,
   > 109 name `MapComposer`) and does not score it. That is the **install** term, and no ADR
   > rules on it.
2. **A duck-typed-door register.** A new check counting call sites whose receiver
   is untyped and whose method is on the published port — today **12**, target
   **0**. Nothing that exists can see these. It must be written at **pass 6**, not
   pass 9, or pass 6 has no way to know it finished.

   > ⚠️ **Amended 2026-08-25 by [ADR-0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md)
   > dec. 5 at [#567](https://github.com/timbermania/fft-monorepo/issues/567): the register
   > has TWO arms and the enforcing baseline is 15.** Arm 1 **enforces** over `src/` — call
   > sites whose receiver carries no type and whose method, **or `has_method` argument**, is
   > on the published port: today **15**, target **0**. Arm 2 **reports** over `tests/` — the
   > same scan plus mock **producers** defining `get_tile` / `get_all_tiles` outside the
   > addon: today **20**, no target, because `classify()` returns `None` for every test file
   > and a threshold there would be guesswork. Arm 2 must exist anyway: arm 1 reaching zero
   > while 20 cases sit in `tests/` reads as coverage. ⚠️ GDScript has no interfaces, so arm 1
   > must admit both `extends Lattice` and a real `Lattice` seeded with fabricated
   > `TerrainCell`s — phrase it against the receiver's type, never against subclassing.

   > ⚠️ **Amended 2026-08-27 by [ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)
   > dec. 1, 2 and 3 at loop pass 6: this criterion fixes the PASS and not the ORDER, and
   > the register goes BEFORE the port.** The port and holder 4 consume the register's
   > whole population, so a register written after them reads zero — indistinguishable
   > from one that is broken, and the two hand-counted measurements that could tell them
   > apart (ADR-0170 dec. 5's 15 and 20) exist only until the port lands. Arm 1 is also
   > re-phrased as an **allowlist** — clean iff the receiver is provably typed `Lattice` —
   > because *"carries no type"* is false on five of its own fifteen sites
   > (`map_composer: Node`, `map: Node3D` ×2, `map: Node`, one `:=` inference). The
   > baseline is therefore **27 = 15 + 12**, the 12 being the `TerrainIndex`-typed
   > receivers this criterion left to criterion 1. And arm 1 gains a **fetch** scan: the
   > handle is read off an untyped map at `GPUArena.gd:117`, `ProgressionTester.gd:70`
   > and `NavigatorMain.gd:1275` (plus 9 in `tests/`), which no arm here can see.
3. **A Tile-door register.** *(Added by [ADR-0166](0166-occupancy-is-battles-in-five-spellings-and-battlefields-sixth-is-inert.md)
   dec. 4 at #554.)* No `Battlefield` member reachable from outside the addon may
   have `Tile` in a **return or signal-payload** position — today **8**, target
   **0**: `TerrainIndex.get_tile` / `get_all_tiles`, `MapComposer.get_tile` /
   `get_all_tiles`, `TileCursor.active_tile`, and `TileCursor`'s three signals.
   Criteria 1 and 2 both miss a **stored node**: #554 measured
   `MovementComponent.current_logical_tile` / `Unit.get_current_tile()` at **56
   lines over 24 files with 3 typed**, and retyping those three to `Node3D` would
   satisfy 1 and 2 while every one of the 56 still holds a live `Tile`. This
   criterion is **producer-side** because that is the only side that is
   decidable — 40 addon files, against a consumer pattern that by construction
   carries no type name anywhere in 644 host files — and because it makes the
   held-node shape *impossible* rather than counted: if no door hands out a
   `Tile`, no host can hold one. It scores work this ADR already says is owed,
   #567's `MapComposer` collapse and the ⚠️ above's `Vector2i`-only cursor
   payload, both of which were recorded here and left unguarded.

4. **Port and publish separate for free**, because they are two mechanisms rather
   than two names: the port is a `class_name` reach, the overlay publish is a
   signal or autoload. They already land in different rows of `touch_matrix`'s
   `by shape:` line, so no per-symbol reporting is needed to tell them apart.

⚠️ **What the instruments cannot do today, stated rather than assumed.**
`score_goals.py` has **no inbound term at all** — `mechanical(goal=5)` scores
`outbound_reaches()` and nothing else. `touch_matrix.py` holds per-symbol inbound
in its cache and never prints it. The tables in this ADR were produced by reading
`tools/.touch_cache.json` by hand, and no register on this map would have produced
them.

## Prediction

Scored at pass 9. Terms this decision moves, against `5da42d558`:

| term | now | predicted | note |
|---|---:|---:|---|
| inbound symbols | 11 | **fewer, and the SET is the test** | `Tile` / `TerrainIndex` / `MapComposer` absent |
| inbound lines | 150 | **RISES** | twelve duck-typed sites become named reaches |
| duck-typed lattice call sites | **12** | **0** | needs an instrument that does not exist |
| `Cutscene → Battlefield` | 4 | **~13** | 9 of the 12 are `Cutscene`'s |
| schema rows (ADR-0118 dec. 1) | 7 | **8** | `TerrainCell` |
| kernel code members (ADR-0139 dec. 11) | 2 | **3** | `TerrainCell` in `addons/exmateria_schema/` |
| `Battle` holding `Battlefield` nodes | 4 collections | **0** | keys become `Vector2i` |

**The falsifiable one, in the direction that hurts:** if pass 9 reports inbound
*falling*, that is evidence the port was injected rather than shipped — dec. 3's
failure mode, not its success. Pass 9 must check the set, not the total, before
calling it either way.

## Consequences

- **Pass 6 owes a `Lattice` port, a `TerrainCell` schema in
  `addons/exmateria_schema/`, and an overlay publish channel**, plus re-pointing
  twelve duck-typed sites across `Cutscene`, `Battle` and `Effects` — work no
  earlier pass costed, because no earlier pass could see it.
- **`addons/exmateria_schema/` gains its first member added by a system's own
  pass**, which is precisely the growth path ADR-0139 dec. 11 describes.
- **`TileCursor`'s three signal payloads drop their `Tile`**, becoming
  `(grid_pos: Vector2i)`. Four handlers change; none of them read the dropped
  argument.
- `PlacementTileSet`'s three `Array[Tile]` collections and `claimed_tiles` become
  coordinate-keyed. **#554 inherits a typed holder 3** instead of an invisible one.
- **A snapshot payload is a debt the day terrain becomes dynamic**, and no
  instrument here can represent it.
- ADR-0159 dec. 11 is **superseded on its axis and upheld on its evidence**: the
  consumer split it measured is real, and it is not where the interface cuts.

## Alternatives considered

- **Two ports by consumer, as ADR-0159 dec. 11 prescribed.** Rejected on
  measurement: `TerrainIndex`'s only two used methods both return `Tile`, so the
  two names are one surface and one door. Publishing them as two would put two
  `class_name`s in the same addon bucket and change nothing any register reads —
  the same invisibility as dec. 4(a).
- **One surface, on the grounds that 85% of traffic is one consumer.** Rejected:
  it leaves `Battle` retaining `Battlefield`'s scene nodes in four long-lived
  collections, which is the coupling neither instrument scores, and it leaves the
  twelve duck-typed sites permanently invisible.
- **The port answers the node** (`tile_at(x, z) -> Tile`, `Tile` published with a
  real type on it). Rejected, and it is the honest runner-up: it removes the
  snapshot problem entirely and gives the twelve sites a type. But it puts a
  `StaticBody3D` in three systems' signatures — including `Cutscene`'s and
  `Effects`', which spent effort *avoiding* exactly that — and it keeps the
  identity-keyed occupancy holders, so #554 inherits the untyped `Dictionary`
  unchanged.
- **Add `--inbound <system>` to `touch_matrix.py` and score the split off
  per-symbol line counts**, as the ticket's question 3 implies. Rejected: it is a
  small flag and it would work, but it scores a **total**, so it stays fooled by
  the injection case — and it would have reported this system clean for the whole
  refactor while `Cutscene` reached it nine times. The flag may still be worth
  having; it is not the scoring mechanism.
- **An ADR-0159 amendment #4 for dec. 4(a) plus a separate ADR for the schema.**
  Rejected: the two faces are one finding, and splitting them would file the
  general rule in an older document's margin — which is how extraction #1 shipped
  through face (a) without anyone naming it.

## Amendment 1 — dec. 4 gains a fourth criterion, and the term dec. 4 called "install" was the wrong axis

2026-08-29, [ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md), extraction #3
loop pass 12.

Dec. 4's criterion 1 note above says:

> 🔴 The register PRINTS the scene-tree term (107 `.tscn` files instance `PlayerCamera`,
> 109 name `MapComposer`) and does not score it. That is the **install** term, and no ADR
> rules on it.

**Both halves are wrong.**

*The direction.* A host file naming `res://addons/exmateria_battlefield/…` is the host
reaching **into** the addon — the same direction as `var c: MapComposer`, the same failure
mode, and this same criterion's axis. The install term (axis B, ADR-0202,
`check_addon_install`) asks what breaks when the **host** is removed, and nothing in this
population does: delete the whole host tree and every one of these sites stays behind, in
the host. Axis B reads **0 / 0** and is untouched by any of it.

*The counts.* Measured 2026-08-29 after ADR-0204 landed: `PlayerCamera.tscn` has **7**
namers, not 107 — ADR-0204's inherited-scene mount collapsed them — and `MapComposer.gd`
has **115**, not 109, because the 109 was `.tscn`-only and missed the `.gd`
`preload`-by-path shape.

**Dec. 4 therefore gains criterion 4:** *no file outside the addon may name an
`res://addons/exmateria_battlefield/…` path, except at a declared mount.* Target 0
undeclared reaches, on ADR-0196 dec. 4's ENFORCED/REPORTED split.
`tools/check_lattice_scene.py` is its register — **138 sites over 132 files, plus 1
declared mount**, on the day it was built.

It is a criterion **beside** criterion 1, not folded into it: criterion 1's subject is the
compiled-symbol surface and its instrument is a `class_name` scan of `.gd`; criterion 4's
is the resource-path surface across `.tscn`, `.tres`, `.gd` and `.gdshader`. Merging them
is ADR-0131 dec. 7's own named failure — one number answering two questions. **Run both,
and report axis A and axis B as separate numbers** (ADR-0202 dec. 1).
