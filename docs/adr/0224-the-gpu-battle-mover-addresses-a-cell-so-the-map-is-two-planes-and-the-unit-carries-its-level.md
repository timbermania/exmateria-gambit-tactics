# The GPU battle mover addresses a cell, so the map is two planes and the unit carries its level

Battle **placement** is level-aware and shipped. Battle **movement** is not, by
explicit declaration. The result is not "battle ignores levels" — it is worse than
that: a unit is deployed onto a level-1 tile, and the mover it is then handed to has
no slot for the cell it is standing on.

`ScenarioPlacementSource.gd:107-123` reads ENTD's `upper_level` and seats an enemy at
`(x, z, 1)`. `GPUCombatPacker`'s schema packs `POS_X = cell.x` and `POS_Z = cell.y`
and **drops `cell.z`**, while packing `U_HEIGHT` from `lattice.terrain_at(cell)` —
the level-1 height, correctly, because `terrain_at` takes a full cell. The shader
then answers `get_tile_height(x, z)`, the **level-0** height for the same column. The
unit's own height and the map's height for the tile it stands on disagree.

That is not hypothetical and it is not rare-in-principle. Of the 21 ENTD slots
carrying `upper_level = true`, **12 are reachable** through `scenarios.json` — 8
records across 6 maps — and every one of them sits over a **passable** level-0 cell
whose height differs from the level-1 cell above it:

| record | map | (x, z) | h0 | h1 | gap |
|---|---|---|---|---|---|
| 278 | MAP012 | 6, 6 | 0 | 15 | **15** |
| 296 | MAP057 | 2, 2 | 1 | 8 | 7 |
| 405 | MAP083 | 4, 6 / 4, 5 | 0 | 9 | 9 |
| 406 | MAP083 | 4, 3 / 4, 5 | 0 | 9 | 9 |
| 414 | MAP063 | 5, 1 | 0 | 9 | 9 |
| 424 | MAP057 | 2, 2 / 2, 10 | 1 | 8 | 7 |
| 435 | MAP060 | 4, 6 | 3 | 11 | 8 |
| 468 | MAP070 | 3, 4 | 0 | 12 | **12** |

The remaining 9 slots (records 144, 207, 208, 210, 273, 472) have **no scenario
referencing their ENTD index**, so nothing in this game can load them. They are named
here so the count is not silently wrong later, and they are not a consumer.

Status: accepted (2026-09-03). Extends **ADR-0219** into the GPU battle engine, which
ADR-0219's own Consequences deferred ("anything that assumed column uniqueness must
state which level it means"). Adopts **dec. 6** verbatim rather than restating it.
Layout changes are generated, per **ADR-0001**. Terrain verdicts stay on the port,
per **ADR-0164 dec. 2**. Files
[#816](https://github.com/timbermania/fft-monorepo/issues/816) for the build and
[#817](https://github.com/timbermania/fft-monorepo/issues/817) for the
scenario→battle reset.

Verified 2026-09-05 — dec. 1, 2 and 3 built and green (the shipped 20-plane layout is
`tests/GPUMapBufferLevelRatchetTest.gd`'s subject, P1 over all 119 exported maps,
[#818](https://github.com/timbermania/fft-monorepo/issues/818)); dec. 1 and dec. 2 confirmed
independently against the ROM by [#839](https://github.com/timbermania/fft-monorepo/issues/839);
**dec. 6's AoE clause and dec. 4's `AOE_CENTER` clause retracted**, see the amendment below.

## Context

### The two filters are declarations, and they are load-bearing

`DistanceFieldGenerator.gd:90` and `GPUBatchSimulator.build_map_data` both drop every
cell whose `grid.z != GROUND_LEVEL`, and both say why in place. The reason is not
laziness: the distance field, the map buffer and the compute shader all index a
**column**, `z * map_width + x`. Since ADR-0219 dec. 5 minted the upper level, a
column can hold two cells, so without the filter the second would overwrite the first
and whichever `all_cells()` happened to yield last would win — silently, per run.

So deleting either filter does not "enable levels". It makes two cells collide on one
index. The filters are the correct expression of a model that has no second plane,
and they stay until the model gains one. This ADR gives it one.

### The seam is six functions; the hundred call sites are downstream of it

Across `src/gpu/shaders/`, exactly **8 lines** perform column arithmetic, and all 8
live in `combat_common.glslinc:759-802`, inside `get_tile_height` (755),
`is_tile_traversable` (762), `get_distance` (770) and `is_cliff_edge` (796).
Everything else — **~100 call sites** — merely passes `(x, z)` through:

```
get_tile_height(       44     is_tile_traversable(   16
get_distance(          22     get_tile_occupant(     15
                              is_tile_occupied(       3
```

This is a wide change, not a deep one: 100 mechanical edits behind 8 substantive
ones. Naming the accessors as the seam is what keeps it from being done twice.

### "Movement only" was not available

The tempting small version of this work — widen the mover, leave combat alone — does
not exist. Of the 44 `get_tile_height` sites, **27 are in `stage_attack` (10),
`stage_spell` (9) and `combat_combat` (8)**: range, arc and line-of-sight. Half the
`get_distance` sites are the same. The accessor is shared, so the moment it takes a
level, targeting must supply one. This ADR therefore rules on targeting too, because
declining to would leave 27 call sites with an unstated answer.

### Dec. 6 already answers the crux

The hard question looks like "when a step enters a column that offers two cells,
which one does the unit land on?" ADR-0219 dec. 6 and `EventPathfinder` answer it by
not choosing: `for nb in nav.cells_at(x, z)` enqueues **every** admissible cell of the
neighbour column, low to high, and the climb gate rejects the rest. The level is never
picked; both are explored and the search resolves it.

That transfers directly. The GPU's `stage_pathfind` is a greedy DFS over the
precomputed field rather than a BFS, so its analogue is `for d in 4 { for l in 2 }`
taking the minimum `get_distance` — the same candidate set, resolved by the same
field. No new rule is invented here, which is the point: the two movers must not
disagree about the same bridge.

### Sizing — memory is not the cost, and the bounds do not move

`get_flat_distances()` is a full pairwise matrix, so two planes **quadruples** it.
Worst case in the corpus is MAP125 at 16×16: **0.3 MB → 1.0 MB**. That is negligible
to negligible, and it must not be allowed to argue against the second plane. The cost
of this work is the call sites and the indexing discipline.

The walkable bounds do not move either. There are **125 walkable level-1 cells across
35 maps** (209 minted across 45, of which 84 are impassable), and **zero** of them lie
outside the ground plane's walkable bounding box. `min_x`, `min_z`, `map_width` and
`map_height` are unchanged by this ADR.

The one place the widening is genuinely not free is `stage_pathfind.glsl:82`:
`int visited[8]` is a 256-bit set, and MAP125 has exactly 256 columns. Two planes
needs 512.

## Decision

**1. The GPU cell identity is a dense two-plane index.**
`index = level * (map_width * map_height) + z * map_width + x`, for the map buffer,
the distance field's node numbering, and every accessor. `total_tiles` in the shader
continues to mean the **per-level** tile count; the field's node count becomes
`2 * total_tiles` and its matrix `(2 * total_tiles)²`.

Dense, not sparse, even though level 1 is sparse in the data (125 walkable cells over
35 maps). `get_distance` is 22 call sites on the hot path and computes
`from_idx * total_tiles + to_idx`; a sparse plane means a non-contiguous node
numbering and an indirection table in the innermost loop, bought with 0.7 MB.

**2. The map buffer is LEVEL-MAJOR, and that is what makes the first half of this
build provably inert.** The buffer is
`[L0: heights | traversable | cliff→L0 ×4 | cliff→L1 ×4][L1: same]` — **20 planes**,
not 6. Level 0's **first six** therefore occupy exactly the bytes they occupy today,
so every existing shader offset (`total_tiles * 2 + idx * 4` and friends) keeps
working and keeps reading L0 unchanged.

The eight cliff verdicts dec. 3 rules are laid out as **two 4-wide groups by target
level**, not one 8-wide group per cell, and that is load-bearing rather than
cosmetic: an 8-wide group moves `is_cliff_edge`'s stride to `idx * 8` and forces a
shader edit into the same commit as the buffer, which destroys the staging property
this decision exists for.

This is not cosmetic ordering. It is what lets the map buffer widen in one commit
that cannot move behaviour, before any shader reads the new plane. Plane-major
interleaving (`[heights L0][heights L1][traversable L0]…`) would move every offset
and force the two halves to land together.

The distance field cannot be widened inertly — its matrix **stride** is `total_tiles`,
so doubling the node count changes `get_distance` for every reader. It therefore stays
one plane until the shader pass.

**3. Cliff bits are 8 per cell — one per (direction, target level).** A step now has
up to two possible destinations per direction, so a 4-bit-per-cell table cannot state
the verdict. The alternative of computing a cross-level cliff verdict in the shader is
refused: `is_cliff_edge` is decided from `tile_vertices` and the tile transform, which
are terrain facts the shader cannot see and which ADR-0164 dec. 2 put on the port for
exactly that reason. The verdict stays on the port; the buffer gains a dimension —
laid out per dec. 2 as two 4-wide groups by target level, so the ground-to-ground
group keeps the stride the shader already computes.

The only consumer is `calculate_cliff_move_ticks` (movement timing), so this widens a
table with one reader.

**4. The unit record carries three levels, and they alias like the pairs they
follow.** `U_LEVEL`, `U_DEST_LEVEL`, `U_PROPOSED_LEVEL` join `U_POS_*`, `U_DEST_*`
and `U_PROPOSED_*`; `UNIT_SIZE` goes 98 → 101 and `SHADER_VERSION` 29 → 30. They are
declared in `combat_common.glslinc` and the GDScript mirror is **generated** —
ADR-0001, `tools/gen_gpu_layout.py` — never hand-edited.

Three, not one. Dest and proposed are independent positions that persist across ticks
and can legitimately be at a different level from current; deriving them at read time
means re-running a climb decision in two places from data that may have moved. In the
packer's `UNIT_CONFIG_SCHEMA` they follow the shape already there: `DEST_*` and
`PROPOSED_*` alias `pos_*` with no extractor of their own, so the three level fields
are one new extractor (`cell.z`) and two aliases.

`AOE_CENTER_X/Z` gains none — dec. 6 below makes AoE column-wide. `DBG_NEXT_X/Z`
gains none; it is debug output.

> 🔴 **Retracted — see the 2026-09-05 amendment.** The `AOE_CENTER_X/Z` clause falls with
> dec. 6. The ROM's effect grid collapses the column against the **aimed cell's own height**,
> so `U_AOE_CENTER_LEVEL` is required. The rest of this decision stands.

`U_JUMP = 11` already rides in the record, unused by the field, and stays that way (dec. 7).

The packer's completeness probe — every offset in `[0, UNIT_SIZE)` must be written by
`_write_unit_data` — is the net that makes this safe to grow.

**5. Adjacency is ADR-0219 dec. 6, verbatim.** Four column-to-column neighbours;
every admissible cell of the target column is a candidate, low to high; the climb
gate decides. There is no fifth and sixth move, no in-place level change, and no
half-level. A unit standing under a bridge cannot step onto the deck above it; it
walks to the ramp like everything else.

The GPU mover expands `4 × 2` candidates and takes the minimum `get_distance`, which
is the same candidate set `EventPathfinder` floods. Restating the rule in GPU terms
rather than adopting it is how the two movers would come to disagree about MAP009.

**6. Occupancy is level-aware; targeting is occupant-derived; AoE is column-wide.**
`get_tile_occupant` is a scan over unit records, not a buffer plane, so this is one
added comparison: a unit under a bridge no longer blocks a unit on it. Single-target
attacks resolve their target's level from that target's `U_LEVEL`. An empty-tile
target resolves to the column's ground. Area effects cover a **column** — everything
standing in `(x, z)` at any level is in the area.

AoE is column-wide because no vertical falloff rule has been measured, and inventing
one would be a plausible wrong answer of exactly the kind ADR-0219 warns about. The
target **cursor** stays column-addressed: level cycling is #795 and remains deferred,
so nothing here requires it.

> 🔴 **The AoE clause is retracted — see the 2026-09-05 amendment.** A vertical falloff rule
> **has** been measured: `FUN_801792A4`, called by the effect-grid builder for 324 of 368
> abilities, keeps one cell per column and erases it beyond `vertical` levels of the aimed
> cell. AoE is column-wide in neither of the two regimes that matter. The other two clauses
> of this decision — level-aware occupancy and occupant-derived single-target resolution —
> are confirmed and stand. The port's replacement rule is #845, not this ADR.

**7. Per-unit Jump stays out, and stays named.** `DistanceFieldGenerator.generate`
bakes **one** climb threshold (`jump_range`, default 3.0) into the whole matrix for
every unit. That is pre-existing and this ADR does not fix it. It is recorded because
levels make it easier to mistake for a level bug: a bridge 9 above its floor is
correctly unreachable under the baked rule, while a 3-height ledge is reachable by
everyone including units whose Jump says otherwise.

Note also that the event mover's `WALK_TO_CLIMB = 3` is a **ROM literal for `{28}
Walk To`**, not a unit stat, and the field's 3.0 default matches it by coincidence.
The ROM parameterizes its *gameplay* pathfinder from `unit+0x3B` through a routine
`Walk To` never reaches. Wiring `U_JUMP` into the field is a separate axis — it
multiplies the matrix by the number of distinct Jump values if done naively — and
belongs to its own decision.

**8. No feature flag. The 74 level-0-only maps are the A/B, and byte-identity is the
ratchet.** A flag would thread a branch through all ~100 accessor call sites, which is
more new risk than it retires. Instead: 74 of the 119 exported maps have no level-1
terrain at all, and for those the map buffer and the distance field must come out
**byte-identical** to what they hold today. That property is the mechanical proof that
100 edits moved nothing, and it is the same invariant the two filters existed to
protect. It lands first, not last.

**9. The writeback validates rather than trusts.** `GPUVisualBridge.gd:133` will
receive a `gpu_pos` carrying a level. It resolves that cell through the lattice and,
if the level is not minted there, falls back to `ground_at` and logs an **error** —
not a debug print. The line immediately above already has this shape
(`TerrainCell.ground(...)` then a null check on `terrain_at`), so this matches the
code beside it. Trusting the GPU verbatim turns an indexing bug into a null
dereference in a render path; erroring out crashes the picture over a state bug.

## Prediction

Falsifiable, scored at build:

- **P1.** For all 74 level-0-only maps, `build_map_data` and `get_flat_distances`
  return byte-identical arrays before and after the widening. A single differing byte
  means the level-major layout is not the compatibility guarantee dec. 2 claims.
- **P2.** The map-buffer half lands with **zero** shader edits and no behaviour
  change — including on the 6 defect maps, where the 12 slots keep misbehaving
  exactly as they do today. A behaviour move in that commit falsifies dec. 2.
- **P3.** `UNIT_SIZE` reaches 101 with the packer's completeness probe green and no
  hand edit to the generated GDScript region. If a mirror needs touching,
  ADR-0001 is being violated, not extended.
- **P4.** On MAP083 with record 405 or 406 deployed, the unit's `U_HEIGHT` equals
  `get_tile_height(pos_x, pos_z, level)` for its own level — the two numbers that
  today differ by 9.
- **P5.** That unit can path off the deck and reach the ground, and its route uses no
  in-place level change: every step in it moves to a different `(x, z)`.
- **P6.** `EventPathfinder` and the GPU mover produce the same route over MAP009's
  bridge for the same start, target and climb. A divergence means dec. 5 was restated
  rather than adopted.
- **P7.** `GPUPerfBenchmark` after the shader pass is within noise of a baseline
  taken in the same session. A regression outside noise has a named suspect —
  `visited[16]` plus `stack_l[32]`, ~40 ints of added private storage per invocation
  (dec. 1's sizing note) — and the packed-stack variant is the response.

## Consequences

- The GPU engine stops being the one mover that cannot represent the map. Every other
  consumer of a cell — `TerrainCell.grid`, `MovementComponent.current_cell`,
  `TerrainIndex`, `DynamicTerrainBuilder`, `EventPathfinder` — has been `Vector3i`
  since ADR-0219. This closes the last one.
- The two in-code filters are **deleted, not weakened**. Their comments were correct
  and this ADR is the "separate piece of work with no consumer yet" both of them
  named; that work now has 12 consumers.
- `GPUBatchSimulator`'s bounds check stays. It guards a real past crash (the
  index-936 crash) and widening the index space makes it more necessary, not less.
- 🔴 The first half of the build **does not fix the defect.** Widening the map buffer
  while the shader still column-indexes leaves all 12 slots misbehaving exactly as
  today. This is stated so nobody reads a green first commit as a fix.
- A unit can now stand under a bridge while another stands on it. Nothing in the tree
  relied on column-exclusive occupancy, but any AI heuristic that treated "tile
  occupied" as "column blocked" now sees a different world.
- #817 becomes live. The scenario→battle handoff's unconditional
  `initialize_logical_position()` is harmless only while battle cannot hold a level;
  the shader pass makes it a loss site, and fixes it in the same commit.
- The target cursor still names a column (#795). A player cannot yet aim at the deck
  and the floor separately, so a level-1 target is reachable only through the
  occupant-derived path in dec. 6.
- **Regime C's 29 abilities resolve one unit, not an area** — `FUN_8017CD24` routes them to
  `FUN_8017AC90` and `FUN_8017B874` never runs for them on the execution path. `effect_area` has
  exactly three readers in `battle_decompilation.c` and the table has only one spelling, so the
  `effect_area = 2` and `linear_attack` carried by 8 of them (the Bracelets, `BlackInk`,
  `BlowFire`) are **unread when the ability executes**. Settled by
  [#900](https://github.com/timbermania/fft-monorepo/issues/900). What is *not* settled is whether
  those eight look like an area in play; that is an animation question and needs PCSX, not the
  decompilation.

## Alternatives considered

**(b) A "column with two slots" packing, `(z * w + x) * 2 + level`. Rejected — it is
not a saving.** This was pitched as the cheap option on the grounds that level 1 is
sparse, but interleaving two slots per column allocates **exactly the same number of
slots** as two planes. It buys a different-looking index and nothing else, and it
gives up dec. 2's compatibility property: level 0 would no longer be contiguous, so no
existing shader offset would survive and the build could not be staged.

**(c) A sparse side table for the ~125 walkable level-1 cells. Rejected.** This is the
only variant that saves real memory — about 0.7 MB — and it spends it in the worst
place. `get_distance` would need an indirection from `(x, z, level)` to a node id on
every one of its 22 call sites, in the innermost loop of the mover, to avoid a cost
that dec. 1's sizing shows is negligible. It also makes the byte-identity ratchet of
dec. 8 harder to state, because the ground plane's node numbering would depend on
which level-1 cells exist.

**(d) Plane-major layout. Rejected on staging, not on taste.** `[heights L0][heights
L1][traversable L0]…` reads better as a description of the buffer, and it is what one
would write with no history. It moves every offset in the shader, which means the
buffer and the shader must widen in the same commit, which means there is no commit
whose inertness can be proven by P1 alone. The compatibility property is worth more
than the tidier description.

**(e) A config flag preserving single-plane behaviour. Rejected.** The config buffer
has spare slots and this was mechanically available. It would require threading a
branch through ~100 accessor call sites — two live code paths through the exact
surface the change is riskiest on — to provide a rollback that `git revert` already
provides. The 74 level-0-only maps give the same assurance with no branch: they must
not move, and dec. 8 checks that they do not.

**(f) Infer the level from the height. Rejected, as in ADR-0219.** Repeated here
because the GPU has `U_HEIGHT` and no `U_LEVEL`, which makes the inference look
available. It is not: MAP012's level-1 floor is `h15` over an `h0` and MAP057's is
`h8` over an `h1`. No threshold separates them.

## Amendment (2026-09-05) — dec. 6's column-wide AoE is retracted, and dec. 4's `AOE_CENTER` clause falls with it

Retracted 2026-09-05 while resolving
[Amend ADR-0224 - retract dec. 6's column-wide AoE and dec. 4's AOE_CENTER ruling](https://github.com/timbermania/fft-monorepo/issues/843),
a child of map
[What the ROM lets you hit](https://github.com/timbermania/fft-monorepo/issues/836).
All evidence is `[STATIC]`, which that map's charter permits for a binding decision provided
every census records the command that reproduces it. Line numbers are
`project-assets/fft-rom/battle_decompilation.c` in the **primary** worktree (3,104,644 bytes);
ability counts are over the 368 rows of `assets/abilities/ability_attributes.json`.

**What is retracted:** dec. 6's sentence *"Area effects cover a **column** — everything standing
in `(x, z)` at any level is in the area"*, its justification *"AoE is column-wide because no
vertical falloff rule has been measured"*, and dec. 4's *"`AOE_CENTER_X/Z` gains none — dec. 6
below makes AoE column-wide."* Dec. 6's other two clauses — level-aware occupancy and
occupant-derived single-target resolution — are untouched and confirmed.

### A vertical falloff rule has been measured

The effect-grid builder `FUN_8017B874` @ `0x8017B874` calls the column collapse `FUN_801792A4`
@ `0x801792A4` at **63923**. The collapse does two things, and both are vertical falloff:

1. **One cell per column survives** — the panel whose height is nearer the reference is kept and
   the other erased, ties to level 0, impassable panels erased outright first.
2. **The survivor is erased too** if it is out of tolerance. The tolerance is
   `(vertical & 0xff) << 1` (**62102**) — `vertical × 2` in half-levels, i.e. `vertical` whole
   levels — compared against `|ref_h − cell_h|`.

`ref_h` is read from **the aimed cell's own tile record**, as
`b2*2 + (b3 & 0x1f) + (b3 >> 5)*2` (63923) — the camera/movement height form settled by
[#839](https://github.com/timbermania/fft-monorepo/issues/839). The record is indexed
`level * 0x100 + z * W + x`, so the **level of the aimed cell is load-bearing**.

Fire carries `vertical = 1`, so its blast reaches one level. An AoE centred on a bridge deck does
**not** hit the unit in the moat below — on MAP083 those cells are 9 apart.

The collapse's third parameter — `top_down`, `flags2 >> 5 & 1` — inverts which panel wins before
the distance test. It is set on **0 of 368** abilities (the census below), so it is dead in shipped data and nothing
downstream of this amendment has to model it.

### The mechanism is not the one #843 stated, and that is recorded rather than fixed silently

#843 argues the collapse is called **unconditionally**. It is not. The collapse, the flood, and
the twin-panel seed are all inside one guard:

```c
/* battle_decompilation.c:63919-63926 */
if ((bVar6 & 0x20) == 0) {              // flags1 & 0x20 == weapon_range, CLEAR
    *pcVar14 = cVar1 + '\x01';          // 63921  seed the twin panel
    FUN_80179518(cVar1,0);              // 63922  flood
    FUN_801792a4(ref_h, vertical, ...); // 63923  COLUMN COLLAPSE
    FUN_80179204((int)local_36);        // 63925
}
```

and `flags4 & 0x20` (`direct`) forces that guard shut three lines into the function:

```c
/* battle_decompilation.c:63861-63864 */
if ((*(byte *)(iVar8 + -0x7ffa040a) & 0x20) != 0) {   // flags4 & 0x20 == direct
    bVar6 = bVar6 | 0x20;        // -> skips the block above
    uVar13 = uVar13 & 0x39;      // also clears linear_attack and three_directions
}
```

This is recorded, not quietly corrected, because a reader implementing from the retracted text
would build the wrong thing — and so would a reader implementing from #843's sentence. The retraction is unaffected — it is **stronger** under the
correct mechanism, because dec. 6 turns out to be wrong for the skipped abilities too.

The flag bit map is confirmed by two independent routes: the ROM's own use sites in the range-grid
builder `FUN_8017A290` (`& 0xC0` self-target, `& 0x20` weapon dispatch, `& 0x10` the ±sweep,
`& 0x08` the collapse, `& 0x01` erase-caster all land on the matching field), and
`research/effect-meta-data/scripts/dump_ability_data.py`, which decodes the attribute table from
the ROM independently. `flags1 & 0x20` is `weapon_range`; `flags4 & 0x20` is `direct`.

### Three regimes, and dec. 6 is wrong in all three

| # | condition | effect grid | abilities |
|---|---|---|---|
| **A** | `effect_area == -1` (63891) | every entry of **both** planes — the whole map | **15** — all Songs and Dances, plus GalaxyStop |
| **B** | `weapon_range` clear and `direct` clear | twin seed → flood → **column collapse** | **324** |
| **C** | `weapon_range` or `direct` set | **never reaches this builder** — the dispatcher routes it to `FUN_8017AC90`, which resolves one *unit* | **29** |

Only regime A is column-wide, and there "column" understates it by the whole map. Regime B has the
vertical filter dec. 6 says does not exist. Regime C is not a grid at all — see below.

**Regime C never runs this builder on the execution path.** `FUN_8017CD24` @ `0x8017CD24` is the
dispatcher, and it branches on exactly regime C's condition (**64736-64741**):

```c
if ((uVar2 == 8) || (uVar2 == 10) || (uVar2 - 1 < 2) ||
    ((bVar4 & 0x20) != 0) ||        // flags4 & 0x20 == direct
    ((bVar3 & 0x20) != 0)) {        // flags1 & 0x20 == weapon_range
    iVar1 = FUN_8017ac90();         // <- regime C
} else {
    iVar1 = FUN_8017aaf8();         // <- regimes A and B; this is what calls FUN_8017B874
}
```

`FUN_8017AC90` builds no grid. It resolves **one target unit** through the weapon/flight path —
`FUN_801AFF18`, `FUN_801B0818`, `FUN_8017AFC0` or `FUN_8017B3F4`, chosen on the *weapon* flags byte
— and then sets tile byte `+5` bit 7 on that one unit's tile, which is the write
[#838](https://github.com/timbermania/fft-monorepo/issues/838) already recorded. It reads
`effect_area` nowhere.

So dec. 6 is wrong for these 29 for a different reason again: they do not produce an area at all.
`FUN_8017B874`'s flag-set branch, which *does* yield a single aimed cell, is reached only through
`FUN_8017AAF8`'s three other callers — all in the `0x8006`/`0x8007` menu range, i.e. the targeting
cursor's preview, not execution. **That the three are UI is inference from their address range and
call graph; the routing itself is read.** Settled by
[#900](https://github.com/timbermania/fft-monorepo/issues/900).

**The census, and it is the one every count in this amendment comes from.** Run from
`godot-learning/`:

```
python3 - <<'PY'
import json
d = json.load(open('assets/abilities/ability_attributes.json'))
A = [a for a in d if a['effect_area'] == 255]
C = [a for a in d if (a['weapon_range'] or a['direct']) and a['effect_area'] != 255]
B = [a for a in d if not (a['weapon_range'] or a['direct']) and a['effect_area'] != 255]
print('total', len(d), '| A', len(A), '| B', len(B), '| C', len(C))
print('vertical_tolerance', sum(a['vertical_tolerance'] for a in d))
print('top_down_targeting', sum(a['top_down_targeting'] for a in d))
print('C rows with effect_area > 0', [a['name'] for a in C if a['effect_area'] > 0])
PY
```

```
total 368 | A 15 | B 324 | C 29
vertical_tolerance 86
top_down_targeting 0
C rows with effect_area > 0 ['IceBracelet', 'FireBracelet', 'ThnderBrcelet',
                            'BlackInk', 'BlowFire', 'IceBracelet',
                            'FireBracelet', 'ThnderBrcelet']
```

The three regimes partition the table exactly: 15 + 324 + 29 = 368, and no ability is in two of
them. Regime A never reaches the collapse — the whole-map fill is the `if (cVar1 == -1)` arm at
**63891-63899**, and the seed, the flood and the collapse are the `else` at **63900-63927**.

### Dec. 4 reopens: `U_AOE_CENTER_LEVEL` is required

The collapse's `ref_h` comes from the aimed cell's record at `level * 0x100 + z * W + x`. The level
is an input, not a derivation. Deriving it at read time from the column is the exact defect this ADR
opens with — `U_HEIGHT` packed from the right cell while the shader answered the ground under it —
so that route is closed by the document's own Context.

`AOE_CENTER_X/Z` therefore gains a level, on the alias shape dec. 4 already fixes: `DEST_*` and
`PROPOSED_*` alias `pos_*` with no extractor of their own. Record sizes and `SHADER_VERSION` are
generated (ADR-0001, `tools/gen_gpu_layout.py`) and are deliberately not written here.

### Both halves of the asymmetry, because the correct half is one refactor from being lost

`vertical` gates the **range** grid only when `vertical_tolerance` (`flags1 & 0x08`) is set —
**86** of 368 abilities (the census above), `FUN_8017A290` **62943-62944**, with `top_down` passed
as a literal `0`.
It bounds the **effect** grid in every regime-B ability — **324** — with no flag test at all.

Our port has the range half right: `stage_spell.glsl:443-447` gates on `ABFLAG_VERTICAL_TOLERANCE` and
tests `abs(target_height - my_height) > vert_tolerance`. **That is not symmetry waiting to be
tidied up.** The ROM's two grids read the same `vertical` byte under different conditions, and a
refactor that unified them would break the range half to fix the effect half.

### What this amendment does not rule

**The port's replacement rule.** Whether `stage_damage`'s AoE loop filters by level, what tolerance
it reads, and whether it reproduces the one-cell-per-column collapse at all are
[#845](https://github.com/timbermania/fft-monorepo/issues/845)'s, informed by the live PCSX arm
[#844](https://github.com/timbermania/fft-monorepo/issues/844). This amendment states the ROM's
answer and retracts ours. **No shader behaviour changes on it** — the two comments asserting the
retracted rule (`stage_damage.glsl`, `combat_combat.glslinc`) are rewritten in the same PR as
comments only, because they are written to stop a future reader from fixing the loop.
