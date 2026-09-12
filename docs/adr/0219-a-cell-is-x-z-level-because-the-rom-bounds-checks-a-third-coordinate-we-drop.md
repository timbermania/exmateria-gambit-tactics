# A cell is `(x, z, level)` — the ROM bounds-checks a third coordinate we drop on the floor

Algus walks *under* the Igros bridge. In PCSX-Redux he walks *on* it. The whole
difference is one byte we never modelled.

The ROM resolves a tile through `tile_ptr` @ `0x80183fb4`:

```
tile_ptr(x, z, level) = 0x8018F8CC + ((level << 8) + z*size_x + x) * 8
```

`8018400c` bounds-checks the third argument with `sltiu v0,a2,0x2` — **`level < 2`**
— and strides it by `level << 8`, a whole 256-slot plane. A live logging breakpoint
on that routine caught **738 of 3,321 calls in ~2 s passing `level = 1`**, every one
of them `tile_ptr(4, 2, 1)`: the bridge. Terrain level is not a curiosity in the data
format. It is load-bearing in the frame loop.

We resolve a tile as `(x, z)`. There is no representation of the second level in
`TerrainCell.grid`, in `MovementComponent.current_cell`, in `TerrainIndex`'s key, or
in `ScenarioApply.walk_to`'s signature — so `DynamicTerrainBuilder.gd:49` reads
`terrain.level_0` and stops, and `grep -rn "level_1" --include=*.gd` returns **zero
hits across the whole game**.

This is not one bridge. Across the 119 exported maps there are **202 selectable
level-1 tiles on 44 of them**.

**ADR-0192 dec. 6** landed `TerrainCell.grid` on one `Vector2i`, and **ADR-0166
dec. 3** landed `current_cell` on the same type. Both are right and both are built.
This ADR does not overturn either argument — every reason they gave holds for a
`Vector3i` verbatim. It corrects their **arity**. They chose two axes because two
axes was the whole world in view; the ROM has always had three.

Status: accepted (2026-09-02). Amends **ADR-0192 dec. 6** and **ADR-0166 dec. 3** on
arity only, in place. Files
[#789](https://github.com/timbermania/fft-monorepo/issues/789) for the build.
Evidence: `research/bridge_terrain_level1/README.md`.

## Context

### The third coordinate is the ROM's, it is bounds-checked, and it is live

`tile_ptr`'s `sltiu v0,a2,0x2` is the ROM's own statement that a column holds at
most two tiles. The stride confirms the shape independently: the block after
`0x8018F8CC` ends at `0x8018F8CC + 0x1000`, and `0x1000` is exactly
`2 levels × 256 slots × 8 bytes`.

The unit side matches. Actors live in an array of stride `0x440` (**not** the
`0x1C0` table at `0x801908CC` — that was the wrong base, and reading the right
offsets off it is what made an earlier pass conclude the level byte did not
exist). Scenario 29's Algus is at `0x800B90C8`, where `+0x80/+0x81/+0x82` read
`04 02 01` — `(x, z, level)`, three adjacent bytes, exactly the argument triple
`tile_ptr` takes. Of the six live actors on that map, **only Algus carries
`level = 1`**, and he is the one unit the chunk's only `Z=1` instruction targets.

So the model this ADR adopts is not invented. It is transcribed.

### `Z` on a unit opcode is a level, not a height — and the census is binary

Across all 978 exported scenario chunks:

| opcode | instructions with X/Y/Z | distinct `Z` | non-zero `Z` |
|---|---|---|---|
| `Walk To` | 282 | **2** — `{0, 1}` | 6 |
| `Warp Unit` | 352 | **2** — `{0, 1}` | 10 |
| `Add Ghost Unit` | 39 | 1 — `{0}` | 0 |
| `Camera` | 1273 | 406 | 1197 |
| `Camera Move (relative)` | 41 | 15 | 39 |

The unit-placement opcodes are **binary over 634 instructions** — precisely
`tile_ptr`'s bound. A height byte on a game whose maps reach height 20+ cannot be
binary across 634 samples. Thirteen of the sixteen non-zero-`Z` instructions land
on a real level-1 tile in the exported terrain; of the three that do not, one is a
map we never exported and two are on MAP058, whose level-1 tiles are suspected to
live in a non-`PRIMARY` arrangement we also never export.

`Camera`'s identically-named `Z` is a free 16-bit **world** coordinate with 406
distinct values. Same field name, different concept — which is itself an argument
for spelling the tile axis on a type that cannot be confused with a world one.

### The level latches; it never interpolates

Stepping Algus off the bridge (`Walk To Unit 7 (3,11) Z=0`) and logging only the
actor's changed fields:

```
     +7C (from)   +80 (to)
 1   4,2,1    |   4,2,1     standing on the bridge
 2   4,2,1    |   3,2,1     target x moves first — level still 1
 3   4,2,1    |   3,2,0     *** the level flips as its own discrete event ***
 4   4,2,0    |   3,2,0     the 'from' copy follows
 5   3,2,0    |   3,2,0     arrived
```

There is no "half a level" state anywhere in the ROM's model. **A mover does not
interpolate level; it carries it.** That is what makes an integer axis the right
shape rather than a float or a derived height band.

### Both existing decisions chose `Vector2i` without this case in view

ADR-0166 dec. 3 gave three reasons for `Vector2i` over `TerrainCell`, in weight
order: **equality** (`Vector2i` compares by value, a `RefCounted` cell does not),
**one type for one concept** (the same key holds `claimed_tiles` and the `*_tiles`
arrays), and **staleness** (a held cell lies the day terrain mutates). ADR-0192
dec. 6 added a fourth: a cell whose identity is spelled differently from the key
everything else uses re-opens the second reason on the first `Dictionary` lookup.

**All four arguments hold for `Vector3i` without a word changed.** `Vector3i`
compares by value; it is still one type for one concept; it is still not a
snapshot; and it is still the key. Nothing in either decision's reasoning is about
the number two. They are amended, not refuted — which is why this ADR amends in
place rather than superseding.

### The store could not hold both levels even if the builder read them

`TerrainIndex.add_tile` keys on `_make_key(tile.grid_x, tile.grid_z) -> String` —
one entry per column. Iterating `level_1` without widening that key **overwrites**
the level-0 tile: the moat at MAP009 `(4,11)` would vanish and the bridge appear,
trading a hole in the bridge for a hole in the water. This is why the fix is not a
two-line loop change, and why it needs an ADR rather than a patch.

That `String` key is also, quietly, a second spelling of the identity ADR-0166
dec. 3 already ruled must be one type. It goes with the same edit.

### The level is dropped at four seams, and the first one is enough

1. `DynamicTerrainBuilder.gd:49` reads `terrain_data.terrain.level_0` and never
   `level_1`. Because `MapComposer` loads the base map through the **doodad** path,
   this doodad-looking line is the single loss site for every map in the game.
2. `TerrainIndex._make_key(x, z)` — one slot per column (above).
3. `TerrainCell.grid` / `current_cell` — no field to put it in.
4. `ScenarioVM._op_walk_to` → `ScenarioApply.walk_to(uid, tx, tz)` — no parameter
   to pass it through, under a comment asserting the `Z` byte *is* a height.

Pathfinding is a **victim, not a cause**: `EventPathfinder` routes correctly over
the world it was handed, in which `(4,11)` is simply a height-1 water tile.

## Decision

**1. A cell's identity is `Vector3i(x, z, level)`.** `TerrainCell.grid` becomes
`Vector3i`; `.x` and `.y` keep their present meanings (grid X, grid Z) and `.z`
carries the level.

```gdscript
var grid: Vector3i = Vector3i.ZERO   # (grid_x, grid_z, level)
```

The axis order is `(x, z, level)` and not `(x, level, z)` because it is the ROM's
own argument order at `tile_ptr`, it is the byte order at actor `+0x80`, and it
makes every existing `cell.grid.x` / `cell.grid.y` site **correct unchanged**. A
reordering would silently invert 31 call sites that currently compile either way.

🔴 **`grid.z` is a level index, not a world Z and not a height.** The name collision
with `Vector3` world coordinates is real and this is the one place it is written
down. `height` remains a separate field and remains the thing world-Y derives from.
Anything reading a `Vector3i` cell key as a position is wrong.

**2. `TerrainCell.NONE := Vector3i.MIN`.** One sentinel, still in the schema, for
the same reason ADR-0166 dec. 3 put it there: both a unit's "unplaced" and
`Battle`'s "no destination" need to spell it, and a second constant named the same
thing elsewhere re-opens "one type for one concept". `Vector3i.MIN` and not
`(-1,-1,-1)` for ADR-0192 dec. 6's reason unchanged — `DynamicTerrainBuilder`
offsets doodad tiles by a placement origin, so a small negative coordinate is legal.

**3. `MovementComponent.current_cell: Vector3i`.** ADR-0166 dec. 3's three reasons
are carried forward verbatim; only the arity changes. A unit's position without its
level is not a position — it is the exact ambiguity that put Algus in the moat.

**4. `TerrainIndex` keys on the `Vector3i` and `_make_key(x, z) -> String` is
deleted.** Not widened to `_make_key(x, z, level)`: a `String` key is a second
spelling of an identity this ADR just made one type, and ADR-0166 dec. 3 already
forbids that. `get_tile` / `remove_tile` take the cell key; the three internal
callers move with it.

**5. `DynamicTerrainBuilder` builds both levels**, minting a tile per non-empty
level-1 slot alongside every level-0 slot. Two tiles may share `(x, z)` and are
distinguished only by `grid.z`.

**6. Level is carried, never interpolated.** A mover interpolates world position and
**latches** level at the seat tile, matching §8.1.3's witnessed field-at-a-time
retirement. No code may compute, blend, or infer a level from a height — inference
is what the deleted comment in `_op_walk_to` was doing.

**7. `ScenarioApply.walk_to` and `_op_walk_to` carry the level**, and the comment
asserting *"the `Z` byte (height) is ignored — the map derives world-Y from the seat
tile"* is deleted rather than reworded. Its premise is false twice over: `Z` is not a
height, and at `(4,11)` there are two seat tiles, so "the seat tile" does not name
one.

**8. The exporter keeps writing both levels. Nothing is flattened.** See
Alternatives (c).

**9. Two things this ADR deliberately does not settle**, both named so a later reader
does not mistake silence for coverage:

- **Map arrangements.** `fft_exporter/__main__.py:124` writes only
  `MapArrangementState.PRIMARY` of FFT's six (day/night/weather). This is the
  leading explanation for MAP058's two `Z=1` warps onto a map with zero exported
  level-1 tiles. It is a *separate defect in the same area*, not part of this one,
  and it is filed as [#792](https://github.com/timbermania/fft-monorepo/issues/792)
  rather than left as prose — a defect named only inside an ADR is a defect nobody
  is holding.
- **Which ROM routine writes the unit level byte.** The value and its latching are
  witnessed; the writer is not. Naming it is not required to build any decision
  above, and pretending otherwise would gate this on work that changes nothing.

## Prediction

Falsifiable, scored at build:

- **P1.** Algus stands on the bridge at MAP009 `(4,11)` after scenario 29 PC 34, and
  steps down to level 0 at PC 164. Visual, against the two PCSX reference captures
  in `research/bridge_terrain_level1/evidence/`.
- **P2.** `grep -rn "level_1" --include=*.gd` goes from **0** to at least 1.
- **P3.** The 202 selectable level-1 tiles across 44 maps become reachable cells.
  Measured by counting minted tiles, not by inspection.
- **P4.** A runtime assertion that a supplied level is `< 2` **can never fire** from
  scenario data — the census says the corpus supplies only `{0, 1}`. It is therefore
  a control on *our* arithmetic, not on the ROM's data, and it is worth having for
  exactly that reason.
- **P5.** Sites touched are within the measured radius below. A build that touches
  materially more has found something this ADR did not model, and should say so
  rather than absorb it.

### Measured blast radius, 2026-09-02

| site | count |
|---|---|
| `current_cell` | 53 |
| `.grid` | 31 |
| `terrain_at` | 49 |
| `plan_walk` / `walk_to` | 64 |
| `TerrainIndex._make_key` callers | 3 |
| `Vector2i` overall (context, most unrelated) | 917 |

`EventPathfinder` is reachable only from `src/scenarios/ScenarioApply.gd`,
`src/scenarios/ScenarioVM.gd`, `addons/exmateria_battlefield/` and tests — **no
battle-movement pathfinder exists yet**, so this lands before there is a second
consumer to migrate. That is the cheapest this change will ever be.

## Consequences

- The shared kernel's cell identity changes type. Every `Dictionary` keyed on a cell
  re-keys. Because `.x`/`.y` keep their meaning, the majority of read sites compile
  and behave unchanged — the work concentrates at **construction** sites, which is
  where a level must be supplied and therefore where the thinking belongs.
- Sites that construct a cell key without a level become compile-visible. This is a
  feature: each one is a place that was silently assuming level 0.
- Two tiles may now occupy one `(x, z)`. Anything that assumed column uniqueness —
  cursor picking, occupancy, the GPU map buffer's per-column packing — must state
  which level it means. Where a system genuinely only has one, saying so explicitly
  is cheaper than the current implicit answer. **ADR-0224** is where the GPU battle
  engine states it: two planes, `U_LEVEL` on the unit record, and this ADR's dec. 6
  adopted verbatim as the mover's adjacency rule. Cursor picking is still deferred
  (#795).
- The bridge hole, the 6-height-unit drop, the apparent "pathfinding bug", and the
  wrong footstep sound (`Bridge` `0x23` → default `0x29` vs `Waterway` `0x0E` →
  water `0x23`) all close together, because they were one missing byte.
- ADR-0192 dec. 6's field **count** is untouched: `TerrainCell` is still six fields.
  Its sink and autoload vetoes pass a fortiori — no new outbound edge, same shape.
- 🔴 This does not make terrain dynamic and does not touch the snapshot caveat.
  `TerrainCell` is still a snapshot; whoever makes terrain mutate still owns that.

## Alternatives considered

**(b) Keep `Vector2i`, add an optional `upper: TerrainCell` (or a parallel `level`
field). Rejected.** It re-opens the "never two fields encoding one axis" rule of
**ADR-0119 dec. 3 / ADR-0083** — the same rule `TerrainCell.gd`'s own docstring
cites to justify a sentinel instead of a `has_cell` bool. Two members that must
agree is precisely the shape that produced this bug in a different spelling: a
position and a level that can be updated independently will be, and the failure is
silent. It is also the option that ages worst — every new consumer must learn to
carry a second value that the type does not force it to carry.

**(c) Flatten at export — pick the walkable level per column. Rejected, and it is
provably wrong rather than merely inferior.** MAP060 has six level-1 tiles sitting
over walkable level-0 `StoneFloor`; a flatten must discard a real, standable
surface. It would also make the export lossy against the ROM, which is the one
property `exmateria-map`'s byte-exactness work exists to protect, and it would push
a gameplay policy ("which level is the real one") into a data exporter that has no
business holding one.

**(d) Model the level as a height band and infer it. Rejected.** This is what the
current `_op_walk_to` comment already tries, and §8.1.3 shows the ROM never infers:
the byte is stored, latched, and retired as its own discrete field. MAP083's bridge
is `h9` over `h0` and MAP057's is `h8` over `h1`, but MAP012's level-1 `StoneFloor`
is `h15` over an `h0` — there is no threshold that separates them, and even if one
existed today it would be a coincidence the ROM does not rely on.

## Amendment (2026-09-02) — #789 built it, P5 is FALSIFIED, MAP058 was never about map
arrangements, and P1's witness could see the seat but not the route

Built on `research/bridge-terrain-level1`. Four predictions land. **P5 does not**, and
this section is the *"should say so rather than absorb it"* that P5 asked for.

### P1 — LANDS, live, with Algus on the deck

Scenario 29 captured headful through `tools/capture_scenario_beat.gd`:

```
pc 47  [ScenarioApply] Walk To 0x07 (7.5, 1.75, 12.5) -> seat (4,11,L1)
       [beat] iid=7 Unit_07 pos=(4.500, 3.036, 11.500)
pc 164 [ScenarioApply] Walk To 0x07 (4.5, 3.035714, 11.5) -> seat (3,11,L0)
```

World Y `3.036` is `MapConstants.surface_y(7)` — the `Bridge` deck. The moat under it
is `h1`, which is `0.464`. He is six height units up, on the tile the ROM puts him on,
and the second line is the step back down to level 0. Two corrections to P1's own
wording: the on-deck beat is **PC 47**, not PC 34 (34 is the walk's dispatch, not its
arrival), and the level-0 seat is `(3,11)` in game coordinates, which is the README's
PSX `(3,2)` under ADR-0052's z-flip — the same tile, not a disagreement.

### P2 — LANDS, and the prediction's own spelling is obsolete

`grep -rn "level_1" --include=*.gd` is still **0**, and that is the *pass*: dec. 5's
loop is data-driven (`"level_%d" % level`), so the literal never appears. Three hits
for `"level_%d"` across `DynamicTerrainBuilder` and `TerrainFixture`. A prediction
phrased as a grep string measured the fix it expected rather than the property it
wanted; the property is "the build path reads the levels the data offers", and
`tools/check_terrain_level.py` arm 1 asserts *that* instead.

### P3 — LANDS. 202 selectable is right; 209 tiles are minted

`_slot_is_occupied` mints an upper slot that is thick **or** selectable, so the build
puts **209 level-1 tiles on 45 maps** where the census counted **202 selectable on
44**. The seven-tile, one-map gap is real geometry that is not standable — a solid
upper slab. Both numbers are correct about different questions and the ADR only asked
one of them; the guard reports the selectable count so it stays comparable to the
number above.

### P4 — LANDS exactly as predicted, including the part where it never fires

`add_terrain` asserts `level < TerrainCell.LEVEL_COUNT`. The corpus supplies only
`{0, 1}`, so the assert is a control on our arithmetic. It gained a second,
independent corroboration during the build: the ENTD's `upper_level` bit is `{0, 1}`
across all 4,902 records (21 ones), from a data file with no connection to the
scenario chunks.

### P5 — FALSIFIED. Four things this ADR did not model

**(a) The GPU stack indexes terrain by COLUMN, and dec. 5 would have made it collide
silently.** `GPUBatchSimulator.build_map_data`, `DistanceFieldGenerator` and
`PlacementTileGenerator` each walk `all_cells()` into a flat `size_x * size_z` array.
Minting a second cell per column makes the last write win, per column, with no error
— the same failure mode as the original defect, in a new place, on the day the fix
lands. Consequences anticipated the *question* ("must state which level it means");
it did not anticipate that the answer had to be chosen in this build.

The answer taken is a **declaration, not a redesign**: those three filter
`all_cells()` to `cell.grid.z == TerrainCell.GROUND_LEVEL`. That is exactly
behaviour-preserving — level 1 was never built, so the GPU stack has never seen a
level-1 tile — and it defers buffer and shader work that today has no consumer. What
it buys is that the assumption is now written down at the site instead of being a
property of the store. Widening the buffer is real work for whoever gives the battle
engine a second level to fight on; it is not this ticket.

**(b) A FIFTH loss site: the ENTD's own `upper_level` bit.** The Context section names
four seams. There is a fifth, and it is a *data* seam rather than a code one:
`entd_positions.json` carries `upper_level` per enemy record, `parse_placement.py`
has been exporting it since it was written, and **nothing in the game read it.** 21
of 4,902 records set it. It is now carried through `ScenarioPlacementSource` and into
`GPUArena`'s `ENTD_TILE_META`, so an enemy the ROM stands on a bridge is stood on the
bridge. Found by compile error, which is dec. 1 working: the seam was invisible until
the type refused to drop the byte.

**(c) The cursor still names a COLUMN, and that is deferred to
[#795](https://github.com/timbermania/fft-monorepo/issues/795).** `TileCursor.grid_pos`
is a `Vector2i`. Making it a cell is not a retype: it is the gameplay question of how a
player selects *which* of two stacked cells they mean, and it reaches ~90 sites across
17 files. This ADR deliberately does not settle input, so the build does not settle it
either. The level is dropped at the three places that hand the cursor a position, each
with a comment naming #795 — dropped where something knows it is dropping it, which is
the opposite of the defect.

**(d) The lattice port went from four members to six.** ADR-0170 dec. 2 / ADR-0192
dec. 5 fixed the count at four; `ground_at(x, z)` and `column_at(x, z)` were added,
and dec. 4's "get_tile / remove_tile take the cell key" did not foresee it. The reason
is dec. 1's reason: a caller that addresses a column and means its ground was, before
this ADR, indistinguishable from a caller that holds a cell. One member with a
defaulted level would have let every existing call site keep compiling and state
nothing — which is the defect. Three members make the caller say which question it is
asking.

The same rule produced a deliberate *asymmetry* worth naming, because it looks like an
inconsistency: `terrain_at` refuses a default level, while `Unit.place_on_tile` takes
`level: int = TerrainCell.GROUND_LEVEL`. A query that silently answers about the wrong
tile is the bug; a *command* whose default is written into its signature, documented,
and visible at the call site is a stated choice. The test is whether the default is
readable at the site, not whether one exists.

### MAP058 refutes dec. 9's leading explanation

Dec. 9 offers map arrangements as "the leading explanation for MAP058's two `Z=1`
warps onto a map with zero exported level-1 tiles". It is not, and #792 does not block
#789:

- MAP058's GNS holds **2 non-pad resources, both `(arrangement 0, day, no weather)`.**
  There is no second arrangement for the exporter to have skipped.
- Its exported `level_1` grid **is present** — 120 slots, every one `unselectable` with
  zero thickness. The level was exported and it is genuinely empty.

The framing was off in a second way: MAP009 has 20 non-pad resources and **all of them
are arrangement 0**; the twenty differ by *time and weather* (5 weather × day/night).
"1 of 6 arrangements" describes the byte's range, not what these maps carry. #792 is
still a real defect — a map that does have a second arrangement exports only the first
— but it is not why MAP058 looks the way it does, and MAP058 should not be cited as
its symptom.

### A guard, because this defect was invisible rather than hard

`tools/check_terrain_level.py`, wired into `tests/run_all_tests.sh`'s pre-flight. Four
arms: the build path names levels by index and not by literal; no call site hands a
cell-keyed port member a `Vector3i(..., 0)` built inline (so `grep -rn
"TerrainCell.ground"` is a *complete* census of the ground-plane assumptions, which is
the property that was missing — not the fix); `LEVEL_COUNT` is still the ROM's 2 and
the builder still asserts against it; and the exported corpus still carries a second
level, which is rejected alternative (c) failing loudly instead of quietly. Proved red
on all seven legs before being trusted green.

### P1, revisited — the witness could see the SEAT, not the ROUTE

P1 above is not withdrawn: Algus does end on the deck, at `surface_y(7)`, and every
byte quoted for it is correct. But the witness it used — the arrival seat and its
world Y — **cannot see the path taken to reach it**, and the path was wrong. Run
headful with the route printed out of `ScenarioVM._plan_walk_route`, scenario 29 read:

```
uid=0x04  (7,11,L0) -> (6,11,L0) -> (5,11,L0) -> (4,11,L0) Waterway h1 -> (3,11,L0) -> (2,11,L0)
uid=0x01  (6,11,L0) -> (5,11,L0) -> (4,11,L0) Waterway h1 -> (3,11,L0) -> (2,11,L0) -> (1,11,L0)
uid=0x07  (7,12,L0) -> (6,12,L0) -> (5,12,L0) water -> (4,12,L0) water -> (4,11,L1)
```

Ramza and Delita cross the moat *through* it, six height units down and six back up;
Algus reaches the deck by climbing it from the water row beneath. The user's report
was about all three units walking in the water, and this ADR's build verified one
unit's endpoint.

**The cause is not in this ADR's scope, but it was hidden by an assumption this ADR's
own code states.** `EventPathfinder`'s `_NEIGHBORS` docstring says which of a column's
cells you land on "is decided by the climb gate, not by a separate move." That was
true of the *code* and false of the *running game*: `find_path` took `max_climb` as an
optional argument defaulting to `DEFAULT_MAX_CLIMB = 99`, and the sole production
caller never passed it — so the gate rejected nothing and `cells_at`'s lowest-first
enumeration decided every column. The ADR's column model is sound; the thing meant to
choose within a column had been switched off since before this build.

Fixed on the same branch: `max_climb` is **required** (so the parser is the guard, the
defect having been a forgettable argument), and the value is the ROM's, not a number
that works — `{28} Walk To` runs at a hardcoded literal 3 (`ori a3,zero,0x3` @
`0x8013e634`), clamped to 7 @ `0x80178424`. The unit's **Jump** (`unit+0x3B`) belongs
to the separate gameplay pathfinder `FUN_80178ca4`, which `Walk To` never reaches.
Full account: `research/bridge_terrain_level1/README.md` §10.

Two ROM readings from that work corroborate this ADR from a direction it did not use:
`FUN_8017813c` bounds-checks **both** the start level and the target level (`1 <
param_5`, `1 < param_8`), and its neighbour walk `FUN_80175ea0` iterates four
directions and then levels 0..1 — the exact column shape dec. 1 and `cells_at` adopt.

**Rule this leaves behind:** a prediction about where a unit *ends* is not a
prediction about where it *goes*. When a defect is spatial and the report is about
motion, the witness has to be the whole path.
