# The duck-typed register goes first, because the port is what erases the baseline that proves it works

ADR-0164 dec. 4 criterion 2 said the register must be written *"at pass 6, not pass 9,
or pass 6 has no way to know it finished."* It did not say **before what**. The port and
holder 4 together consume the register's entire population, so a register written after
them is a scanner that reads zero — which is indistinguishable from a scanner that is
broken, and the only two independent measurements that could tell them apart
(ADR-0170 dec. 5's hand-counted **15** and **20**) exist only until the port lands.

And the rule that register enforces cannot be written the way ADR-0170 dec. 5 writes it.
*"Receiver carries no type"* is **false on five of its own fifteen sites**: `map_composer:
Node`, `map: Node3D` ×2, `map: Node`, and one `:=` inference all carry a type and are all
the defect. Inverting it — *clean iff the receiver is provably `Lattice`* — is decidable,
cannot be satisfied by swapping one wrong type for another, and subsumes the twelve
`TerrainIndex`-typed sites that criterion 1 was separately going to have to chase.

Status: accepted (2026-08-27). Loop **pass 6** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Amends
[ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 2 and dec. 4 criterion 2, and
[ADR-0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md)
dec. 2, dec. 3 and dec. 5, all in place.

## Context

Every figure below was measured on `origin/main` at `775df8cb4` in
`~/Repos/fft-monorepo-lattice`, not quoted from a prior pass. Where a prior ADR's number
is reproduced it is said so; where it is not, the correction is stated.

### Reproduced

- `MovementComponent.current_logical_tile` / `Unit.get_current_tile()` — **51 lines over
  20 files** (29 `src/`, 22 `tests/`). ADR-0166 dec. 3 measured 56/24 at `7e35dc423`;
  the concept did not move, the tree did.
- `tools/check_lattice_doors.py` — **9 rows, 0 stale**, arm 2 = 2, arm 3 = 3.
- **`class_name Lattice` and `class_name TerrainCell` do not exist.** Neither is written.
- ADR-0170 dec. 5's arm-1 baseline of **15** reproduces exactly, and the split is clean:
  a raw scan of `.get_tile` / `.get_all_tiles` / `has_method(<either>)` over `src/` reads
  **28 lines**, of which one is a `push_warning` string literal
  (`ScenarioUnitAlignmentDebugPanel.gd:133`), leaving **27** real sites — **12** whose
  receiver is annotated `TerrainIndex`, **15** whose receiver is not.

### Corrected

🔴 **ADR-0170 dec. 2's *"Every read above is a `TerrainCell` field; none needs the node"*
is false on one of its four consumers.** `ScenarioUnitAlignmentDebugPanel.gd:137` passes
`get_all_tiles()` into `MapGridOverlay.build_from_tiles`, which reads
`tile.tile_vertices` (four tile-local verts) **and `tile.global_transform`** to bake a
world-space grid mesh. Neither is on ADR-0164 dec. 2's `TerrainCell` field list and
neither is derivable from it. The sibling case *is* covered and shows the contrast:
`GPUBatchSimulator.build_map_data` reaches the same geometry through
`TileTraversalUtils.do_edge_vertices_match(tile, neighbor)`, which is exactly why dec. 2
put `is_cliff_edge` on the port.

🔴 **There is a fourth spelling of the door, and it is the acquisition path for all
twelve typed sites.** The handle is not called for, it is **read off an untyped map**:

| | duck-typed `.terrain_index` field reads |
|---|---|
| `src/` | `GPUArena.gd:117`, `ProgressionTester.gd:70`, `NavigatorMain.gd:1275` |
| `tests/` | **9 more**, same shape |

All three `src/` receivers are `@onready var map: Node3D = $ProceduralMap`. Every one of
the 12 `TerrainIndex`-typed call sites got its handle here. A register that scans **calls**
scores this zero, and a pass that re-points 27 call sites while leaving these three has
changed no structure at all. This is ADR-0166 dec. 4's own argument — *criteria 1 and 2
cannot see a stored node* — arriving one spelling further out: they cannot see the
**fetch** either.

⚠️ **`TerrainIndex` is `RefCounted`, `class_name`, and constructed exactly once**, at
`MapComposer.gd:188`. Its `add_tile` / `remove_tile` / `clear` have zero external callers,
but `add_tile(tile: Tile)` is arm 3 of the door register and **four `tests/` files name
it**.

⚠️ **`unselectable`, `pass_through_only` and `surface_type` are read exactly once each in
`src/`** — all three inside `PlacementTileGenerator._is_valid_for_placement`. `height` is
22 and `impassable` is 5.

✅ **ADR-0166 dec. 2 is already built.** `Tile.gd` carries no occupancy members; the file
now holds a comment recording the deletion. No pass owes it.

## Decision

**1. The register is built BEFORE the port and holder 4, and that ordering is the
decision.** *(Amends ADR-0164 dec. 4 criterion 2, which fixed the pass and not the
order.)*

The handoff ranked it fourth, after the two changes that consume its population. That is
this loop's own most expensive lesson applied to a schedule instead of a test: a control
that depends on the defect it controls for **expires on success**, and the expiry is
indistinguishable from a regression — `test_an_unlisted_reach_is_still_RED` and
`BattlefieldAddonAddressTest`'s pinned `rows.size() == 46` both cost a full suite run to
that shape at #642.

Here the loss is one step worse than a broken seed, because it is not recoverable. The
hard part of this register is **receiver-type inference**, and the only evidence that an
implementation of it is correct is that it reproduces a population somebody counted by
hand. ADR-0170 dec. 5's **15** and **20** are that evidence. They exist today; the port
deletes them. Build the register first and it is validated against a known answer, then
driven to zero by the work — the ordinary red-first shape. Build it second and *nothing
ever checks it*.

The objection is real and is answered rather than dismissed: arm 1 is defined against
*"the published port"*, and the published port does not exist yet, so the scan cannot key
on `terrain_at` / `world_position_at` / `is_cliff_edge` / `all_cells` alone. **It keys on
both name sets** — those four and the legacy `get_tile` / `get_all_tiles` — and the legacy
half burns down. That is the same both-directions burn-down `check_lattice_doors.py` and
`check_addon_portability.py` already use, and it means the guard is honest before, during
and after the port rather than only after.

**2. Arm 1 is phrased as an allowlist, not a denylist: a site is clean iff its receiver is
provably typed `Lattice`. Today that reads 27, not 15.** *(Amends ADR-0170 dec. 5.)*

Dec. 5 phrases arm 1 as *"call sites whose receiver carries no type."* Measured against
its own population that sentence is false five times:

```
src/scenarios/ScenarioVM.gd:104          var map_composer: Node = null
src/scenarios/ScenarioWeather.gd:72      var map_composer: Node = null
src/units/Unit.gd:1620                   func place_on_tile(..., map: Node3D)
src/units/MovementComponent.gd:23        func initialize_logical_position(map: Node3D)
src/debug/ScenarioUnitAlignmentDebugPanel.gd:131   var map := _get_map()
```

Each carries a type; each is the defect. A denylist phrased against *absence* of an
annotation needs a permanent special case for `Node`, `Node3D`, `Variant` and inference,
and each special case is a place the guard can be satisfied by writing a different wrong
type — ADR-0164 dec. 4(b)'s hole in its fourth dress.

The inversion needs no type lattice and no special cases: **is this receiver annotated
`Lattice`?** Everything else is on the register. The consequence is that the 12
`TerrainIndex`-typed sites join it, so the baseline is **27 = 15 + 12**.

That overlaps criterion 1, which also fails on those 12. The overlap is kept
deliberately: the two criteria fail for different reasons — criterion 1 because the name
`TerrainIndex` is published at all, arm 1 because the receiver is not the port — and one
edit fixes both. **The tool prints the 15/12 split inside the 27**, so ADR-0170 dec. 5's
hand-measured number survives as a live cross-check instead of being rounded away by its
own successor.

⚠️ GDScript has no interfaces, so *"provably typed `Lattice`"* is a claim about the
**receiver's declared type** and never about subclassing: it must admit `extends Lattice`
and a real `Lattice` seeded with fabricated `TerrainCell`s alike. ADR-0170 dec. 5 already
said this and it survives the inversion unchanged.

**3. Arm 1 also scores the handle FETCH, and the permitted form is one typed fetch at the
seam.** *(New; the shape ADR-0164 dec. 4 and ADR-0170 dec. 5 both miss.)*

The three `src/` `.terrain_index` reads in the Context are not calls and no arm sees them.
They are the door, one step earlier.

There is a constraint that makes this a decision rather than a chore: **criterion 1
requires `MapComposer` absent from the published set**, and six assembler scene roots hold
the map as `@onready var map: Node3D = $ProceduralMap`, a NodePath fetch that infers
`Node`. So the consumer can *never* type the map handle, and `map.lattice` is a duck-typed
read **permanently and by design**. An arm that failed on it would have no green state.

So the rule is stated as a shape rather than a prohibition:

> A fetch is clean **iff its result lands immediately in a `Lattice`-annotated variable or
> field** — `var lattice: Lattice = map.lattice`. Anything else is on the register.

One untyped step is permitted, at the seam, and everything after it is typed. This is the
strongest thing GDScript can enforce here, and it is checkable. It also catches four sites
a calls-only scan would pass — `_vm.map_composer.get_tile(...)` in `ScenarioVM` and
`ScenarioCameraDirector`, which never bind a handle at all.

The cost is that the register must read the **assignment a fetch feeds**, not just match an
expression. Accepted: without it, *"arm 1 is zero"* is true while every consumer still
reaches into the composer blind.

**4. `Lattice` is a new `class_name`; the `Tile` store loses its `class_name` and is
`preload`ed inside the addon.** *(Settles a shape ADR-0164 dec. 2 and ADR-0170 dec. 1
both assume and neither states.)*

The runner-up was renaming `TerrainIndex` → `Lattice` in place and underscore-prefixing
the `Tile`-taking mutators. It is cheaper and it is rejected, because *published* would
then be a **naming convention** — and a convention is precisely what criterion 1 exists to
replace. It also leaves arm 3's gap open: `add_tile(tile: Tile)` stays on the published
class, and four `tests/` files already name it.

Dropping `class_name` is not a convention. It makes the store **structurally unnameable**
from outside the addon: criterion 1 scans `class_name`s, so a type without one cannot be in
the published set, and a door on a class nobody can name is not a door. `MapComposer` and
`DynamicTerrainBuilder` are the only two files that need it and both are inside the addon,
so both `preload` it.

⚠️ This looks like the forwarder ADR-0170 dec. 1 refused, and it is not the same thing.
That refusal was about the **receiver being untypeable** — `$ProceduralMap` infers `Node`,
so a forwarder leaves every consumer duck-typed. Consumers name `Lattice` **by type**, which
is exactly what the forwarder could not give. Delegation was never the objection.

**5. `MapGridOverlay` takes the lattice, and no `Array[Tile]` leaves the addon at all.**
*(Amends ADR-0170 dec. 2, whose "none needs the node" is false here.)*

Today an `Array[Tile]` leaves the addon to a `Cutscene` debug panel and comes **straight
back into the addon**, because `MapGridOverlay` is itself an addon file
(`addons/exmateria_battlefield/debug/MapGridOverlay.gd`). The crossing is pure ceremony.

`build_from_tiles(tiles: Array)` becomes `build_from_lattice(lattice: Lattice)`; the
overlay reads the unpublished store directly, as an addon file may; the panel calls
`_grid.build_from_lattice(map.lattice)` and names only `Lattice` and `MapGridOverlay`.

The two rejected repairs both make the port worse to fix a debug panel:

- **Put world-space `vertices` on `TerrainCell`.** Every `all_cells()` call then allocates
  four `Vector3` per tile for three consumers that never read them, and the cell stops
  being a flat fact record.
- **Add a fifth port member, `cell_outline(x, z)`.** Publishes geometry to close a seam
  that has no geometry consumer outside the addon, and makes dec. 2's member count wrong a
  second time.

Deleting a crossing beats re-typing one. `Lattice` needs an addon-internal handle on the
store to do it, which is a back door only addon files can open — correct, because **the
addon is the encapsulation unit here, not the class**.

**6. `TerrainCell` is six fields, `world_position` is not one of them, and the coordinates
are one `Vector2i`.** *(Amends ADR-0164 dec. 2's eight-field proposal.)*

```gdscript
class_name TerrainCell
extends RefCounted          # matches ColorRecipe / Fold / DepthMode, the kernel's precedent

var grid: Vector2i
var height: int
var impassable: bool
var unselectable: bool
var pass_through_only: bool
var surface_type: String
```

- **`world_position` comes off, and it is the field ADR-0164 dec. 2 already named as the
  liar.** Dec. 2's own 🔴 says a payload is a snapshot, that `world_position` derives from a
  live node transform, and that *"`world_position_at` returning a scalar keeps the hot path
  allocation-free and staleness-free, but `terrain_at` does not."* ADR-0166 dec. 3's third
  reason for `Vector2i` is the same staleness. **Removing it costs nothing measurable**: the
  eight sites that read `get_tile(x, z).global_position` already hold `(x, z)`, so they
  become `lattice.world_position_at(x, z)` — a shorter expression, not a detour. What
  remains is a record of facts immutable for a tile's life. This does not make the snapshot
  concern vanish — `height` and `impassable` lie the day terrain mutates too — but it
  removes the only field that can go stale **without terrain changing at all**.
- **The three thin fields stay; the water rule does not.** All three serve
  `PlacementTileGenerator._is_valid_for_placement`, which excludes
  `["Water","Waterway","River","Sea","Lava"]`. Collapsing them to a `placeable` flag would
  move a **placement policy** onto a type the shared kernel owns. `surface_type` is what
  the map data says; which surfaces `Battle` refuses to deploy onto is `Battle`'s, and
  ADR-0166 dec. 1 is explicit that this map does not hold another system's design decision.
- **`grid: Vector2i`, not `grid_x` / `grid_z`.** ADR-0166 dec. 3's second reason — one type
  for one concept — already lands holder 4 and `claimed_tiles`' keys on `Vector2i`. A cell
  whose identity is spelled differently from the key everything else uses re-opens that on
  the first `Dictionary` lookup.

ADR-0164 dec. 2's two mechanical vetoes are **unaffected**: the sink veto passes a fortiori
on a strictly smaller field set with no new outbound edge, and the autoload veto is about
shape, not fields. `TerrainCell` remains ADR-0118 dec. 1's eighth row and the kernel's
third code member, and needs no new admission ADR.

**7. Arm 2's scope is left OPEN, deliberately.** ADR-0170 dec. 5 makes arm 2
reporting-only over `tests/` *"because `classify()` returns `None` for every test file and
a threshold there would be guesswork"*, while naming the risk it cannot fix: *"arm 1
reaching zero while twenty cases sit in `tests/` reads as coverage"*.

A **named burn-down** is not a threshold — it is the idiom `DOOR_BURN_DOWN` already uses,
for #424's reason quoted in that guard's own source: *"A NAMED LIST, never a pattern."* It
would answer dec. 5's risk directly, because a row can only leave a list by being deleted
from it deliberately, and ADR-0170 dec. 6 predicts ≥4 of the 7 mock producers get deleted
rather than ported — which a burn-down reports as stale rows, i.e. as the win.

This is recorded as an open question rather than decided, because it amends dec. 5's
ruling and the session that raised it did not rule on it. **Whoever builds arm 2 owns it.**
Whichever way it goes, both arms use dec. 2 and dec. 3's rule, so arm 2's population is no
longer dec. 5's `20` — it picks up the 9 duck-typed `.terrain_index` fetches and the
`TerrainIndex`-typed test call sites. The tool must print the split (consumer calls /
fetches / mock producers) so dec. 5's 13-and-7 stay individually checkable against the new
total.

## Prediction

Scored at pass 9, against `775df8cb4`:

| term | now | predicted | note |
|---|---:|---:|---|
| duck-typed register, arm 1 (`src/`) | **27** | **0** | 15 untyped + 12 `TerrainIndex`-typed |
| — of which untyped receiver | **15** | 0 | ADR-0170 dec. 5's number, printed as a split |
| duck-typed `.terrain_index` fetches, `src/` | **3** | **0** | dec. 3; no arm sees these today |
| Tile-door register (`check_lattice_doors.py`) | **9** | **4** | dec. 4/5/6 close the `TerrainIndex` + `MapComposer` rows; the five `TileCursor` rows are a separate piece of work |
| `class_name` on the `Tile` store | **1** | **0** | dec. 4 |
| `TerrainCell` fields | — | **6** | dec. 6; ADR-0164 dec. 2 proposed 8 |
| port members | — | **4** | unchanged from ADR-0170 dec. 2 |
| `Array[Tile]` crossings out of the addon | **1** | **0** | dec. 5 |

**The falsifiable one, in the direction that hurts:** ADR-0166 dec. 3 predicts every
holder-4 site converts cleanly because consumers read only `grid_x` / `grid_z` / `height` /
`global_position`. **If any site needs `Tile` identity rather than coordinates, dec. 3 is
what gives** — `GPUArena.gd:410`'s `if ut == tile` is the one to check first, and it is the
site dec. 3 cites as the *reason* for `Vector2i`.

**Second, and this one is about this ADR rather than its predecessors:** if arm 1 is built
first and reads anything other than **27 / 15 / 12**, the receiver-type inference is wrong
and must be fixed before the port lands — because after the port lands there is nothing
left to check it against. That is the entire argument of dec. 1, stated as a number.

## Consequences

- **The build order changes.** The register is first; the port, holder 4 and the Tile-door
  rows follow. The handoff's ranking put it fourth.
- **The register's enforcing baseline moves 15 → 27**, and it gains a fetch scan on top of
  its call scan. Its target is unchanged at 0.
- **The register overlaps criterion 1 on 12 lines.** Two guards fail on the same code until
  the port lands, by decision.
- **`TerrainIndex` loses its `class_name`**, so every consumer that annotates it must
  re-point. `NavigatorMain.gd:1275` is one, and it is also a fetch site.
- **`MapGridOverlay.build_from_tiles` changes signature**, changing its one caller.
- **`TerrainCell` is 6 fields, not 8.** No consumer holds a world position; anyone who wants
  one calls the port.
- **Arm 2's scope is an open question with an owner-on-arrival**, not a settled ruling.
- **The five `TileCursor` Tile-door rows are NOT closed by this work.** The Tile-door
  register falls 9 → 4, not 9 → 0. `active_tile` plus four `cursor_*` signal payloads are
  ADR-0164 dec. 3's ⚠️ `Vector2i`-only payload, a separate piece of work. A handoff describing
  those as *"two of the nine"* is wrong; the register's own output says five.

## Alternatives considered

- **Build the port first, then the register — the handoff's ranking.** Rejected on dec. 1:
  it is the only ordering under which nothing ever validates the register's hardest part.
- **Phrase arm 1 as ADR-0170 dec. 5 wrote it (receiver carries no annotation).** Rejected on
  dec. 2: false on five of its own fifteen sites, and every repair is a special case that can
  be satisfied by writing a different wrong type.
- **Rename `TerrainIndex` to `Lattice` in place, underscore the mutators.** Rejected on
  dec. 4: it makes "published" a convention and leaves arm 3's `add_tile(tile: Tile)` gap open.
- **Put `vertices` on `TerrainCell`, or add a fifth `cell_outline` port member.** Both
  rejected on dec. 5: they publish geometry to serve one debug panel whose consumer is already
  inside the addon.
- **Keep `world_position` on `TerrainCell`.** Rejected on dec. 6. It is the one field that can
  be stale without terrain changing, ADR-0164 dec. 2 already named it as such, and every site
  that reads it holds the coordinates that make `world_position_at` a shorter call.
- **Collapse the three thin fields into a `placeable` flag.** Rejected on dec. 6: it moves
  `Battle`'s placement policy onto a kernel-owned type.
- **Decide arm 2's scope here.** Declined rather than rejected — see dec. 7. It amends
  ADR-0170 dec. 5's ruling and was not ruled on.

## Amendment (2026-08-27, built) — dec. 7 is ruled: arm 2 is a named burn-down, ENFORCING

Dec. 7 left arm 2's scope open with an owner-on-arrival. This is the arrival. The register
is built (`tools/check_lattice_ports.py`, `tools/test_check_lattice_ports.py`, registered
in `tests/run_all_tests.sh` pre-flight beside the Tile-door pair), and **arm 2 enforces
against a named burn-down, on the same rule and in the same dict as arm 1.**

**The ruling.** ADR-0170 dec. 5 made arm 2 report rather than enforce, on ADR-0170's own
words: *"because `classify()` is blind there and any threshold would be guesswork"*. That objection is
sound and it does not reach a named list, because **a named list is not a threshold**: it
consults no `classify()`, no system attribution and no number — only whether this exact
site is on a list somebody wrote down. Dec. 5's argument rules out a *count*; it never
ruled out an *enumeration*, and #424's finding quoted in `check_lattice_doors.py`'s own
source is that the enumeration is the stronger form ("A NAMED LIST, never a pattern").

Against that, dec. 5's own stated risk is answered rather than carried: *"arm 1 reaching
zero while twenty cases sit in `tests/` reads as coverage"*. Under reporting-only that
sentence stays true forever — a report nobody's exit code depends on is the mechanism by
which it comes true. Under a burn-down the 30 `tests/` sites can only leave the list by
being deleted from it deliberately, and ADR-0170 dec. 6's prediction that **≥4 of the 7
mock producers are deleted rather than ported** is reported as stale rows, i.e. as the win
rather than as silence.

The cost is accepted and named: a test added on any branch that reaches the lattice
duck-typed reds the pre-flight until someone adds a row. That is the intended pressure and
it is one dict entry, and the burn-down ships complete, so the guard is green on arrival.

### Measured on arrival, against `775df8cb4`

**Arm 1 reproduced 27 / 15 / 12 on its first run** — dec. 1's falsifiable prediction, in
the direction that would have hurt. All five sites dec. 2 names as breaking ADR-0170
dec. 5's "receiver carries no type" are reported with the type they carry
(`Node` ×2, `Node3D` ×2, one unannotated `:=`), and the three `.terrain_index` fetches are
reported with what they land in. 48 burn-down rows cover 62 sites; the key carries no line
number, so several sites collapse onto one row and the report prints both counts.

Two of the numbers this ADR and its predecessor carry are **corrected**, both downward
from a raw grep and neither affecting a decision:

- 🔴 **ADR-0170 dec. 5's arm-2 consumer count is 12, not 13.** The thirteenth raw line is a
  `##` comment (`tests/MapBufferBoundsTest.gd:7`, prose describing what
  `MapBufferBoundsTest` iterates). Dec. 5's **7** mock producers reproduces exactly — 7
  files, 10 declarations, and the tool prints both because dec. 6's prediction is about
  files.
- ⚠️ **This ADR's Context says the `tests/` fetches are "9 more"; the scan reads 10 lines
  over 9 FILES.** `tests/gambit_runner/GambitScenarioRunner.gd` fetches at both `:78` and
  `:133`. Nine was a file count written as a line count.

The `src/` fetch arm is **3**, not the 5 a raw `.terrain_index` grep returns: two of the
five (`NavigatorMain.gd:1283`, `GPUArena.gd:199`) are **writes** — `combat_loop.terrain_index
= terrain` stores a handle rather than acquiring one — and the guard excludes them, with a
seed test that keeps the exclusion honest.

### One blind spot the build found, stated because it changes a row's *reason* and not its verdict

**A member inherited from a base class reads as `undeclared`.** `GPUArena.gd:117` lands its
fetch in `terrain_index`, declared `var terrain_index: TerrainIndex` on `CombatHost.gd:24`
and nowhere in `GPUArena` itself; inference is per file, so the row says *undeclared* where
it could say *`TerrainIndex`*. The verdict is unaffected — inherited or not, it is not
`Lattice` — and the same applies to most of arm 2's `terrain_index` receivers, which is why
arm 2's `TerrainIndex`-typed split prints 0 rather than a number comparable to arm 1's 12.
Cross-file type resolution is not attempted by any guard in this repo and is not attempted
here. Note the declaration itself is **not** on this register: a host holding
`var x: TerrainIndex` is criterion 1's published-symbol job.

### Two ways a seed test can pass on the wrong text, both caught by mutation

Eleven mutations were seeded into the guard — probe rewrite off, future names gone, legacy
names gone, header join off, write exclusion off, allowlist inverted back to a denylist,
arm 2 demoted to reporting, producer scan off, fetch arm off, string stripping off, stale
arm off — and each is now failed by the test written for it. Two were not, before the
sweep:

- `test_an_unlisted_MOCK_PRODUCER_is_RED` **passed with the producer scan turned off.**
  Deleting the scan turns seven shipped rows stale, the STALE block prints `func
  get_tile()`, and the assertion matched that instead of the seed. rc was 1 for the wrong
  reason.
- `test_a_fetch_landing_in_a_TerrainIndex_slot_is_RED` matched a **shipped** row's
  ``TerrainIndex`, not `Lattice``, not its own seed's.

Both are fixed by scoping every red assertion to the UNLISTED section of the report and
naming the seed file in it. This is the same shape as "a source assertion can match its own
comment", one guard over: **a seed test must read the arm it seeded, not the whole
report.**

## Amendment (2026-08-27, §3 BUILT) — both arms are ZERO, and three of this ADR's own numbers are corrected

The port, the payload, the overlay signature, the 27 + 3 re-points and holder 4 are all
built on `fix/lattice-port-register`. `tools/check_lattice_ports.py` reads **arm 1 = 0,
arm 2 = 0** and `PORT_BURN_DOWN` is **empty in both arms** — every one of its 48 rows was
deleted as its site went stale, which is the direction dec. 1 built this guard to measure.
The highlight publish the port forced into existence is
[ADR-0193](0193-the-highlight-is-a-publish-with-an-address-and-the-sentinel-belongs-to-the-schema.md).

### Scored against the Prediction table

| term | predicted | measured | |
|---|---:|---:|---|
| duck-typed register, arm 1 (`src/`) | 0 | **0** | ✅ |
| — of which untyped receiver | 0 | **0** | ✅ |
| duck-typed `.terrain_index` fetches, `src/` | 0 | **0** | ✅ |
| Tile-door register (`check_lattice_doors.py`) | 4 | **5** | 🔴 corrected below |
| `class_name` on the `Tile` store | 0 | **0** | ✅ |
| `TerrainCell` fields | 6 | **6** | ✅ |
| port members | 4 | **4** | ✅ |
| `Array[Tile]` crossings out of the addon | 0 | **0** | ✅ |
| arm 2 (`tests/`), not in the table | — | **0** | 32 sites / 25 rows, all closed |

🔴 **The Tile-door prediction of 4 is wrong by one, and this ADR contradicts itself about
it.** Its Consequences say *"the register falls 9 → 4, not 9 → 0. `active_tile` plus four
`cursor_*` signal payloads … A handoff describing those as 'two of the nine' is wrong; the
register's own output says **five**."* Nine minus the four that close is five. The `4` is a
survival from ADR-0166 dec. 4's table of **eight**, where `TileCursor` held four rows;
[#642](https://github.com/timbermania/fft-monorepo/issues/642) added `cursor_stepped`
after that reading and made the baseline nine, and the prediction cell was never
re-derived. **Measured: 9 → 5.** The four that closed are exactly the four named —
`MapComposer.get_tile` / `get_all_tiles` deleted outright, `TerrainIndex.get_tile` /
`get_all_tiles` no longer named outside the addon — and all five that remain are
`TileCursor`'s.

✅ **ADR-0166 dec. 3's falsifiable case survived, at the site this ADR named to check
first.** `GPUArena.gd:410`'s `if ut == tile` — a node-reference comparison deciding
deployment unit-selection — wanted **coordinates, not identity**: it is now
`unit.movement_component.current_cell == cell` and reads better than it did. No holder-4
site needed `Tile` identity. Dec. 3 held where it predicted it might not.

✅ **ADR-0170 dec. 6 predicted ≥4 of the 7 mock producers would be DELETED rather than
ported. Measured: all 7 lost their duck-typed door.** The four that returned something
which was not a `Tile` (`ScenarioSpriteMoveTest`'s bare `Node3D`,
`ScenarioCameraSwoopMonotonicTest`'s ad-hoc `MockTile`, two `FakeTile extends RefCounted`)
lost their tile stand-in class **outright** — a `TerrainCell` is trivial to fabricate where
a node is not, which is dec. 6's stated cause, and it shows as three files losing a class
and one losing its node plumbing entirely. The other three hold real `Tile` nodes because
`TileCursor` still hands them out, and became `extends Lattice` overrides.

### 🔴 That third repair cost this guard a fix, and the seed test that expired cost it another

**The producer arm counted an override inside `extends Lattice` as a mock producer.** It
read **10 → 19** on the pass that repaired all seven — the sanctioned repair scored as the
defect, and a guard whose green state its own ADR forbids. ADR-0170 dec. 5's ⚠️ names this
exact hole on arm 1 (*"a mock must `extends Lattice` and override, or construct a real
`Lattice` seeded with fabricated `TerrainCell`s. Arm 1 must be written so that BOTH routes
pass; one phrased against subclassing forbids the cheaper one"*) — it simply landed on the
producer arm instead. `_port_subclass_lines` is the repair: a declaration is a producer
only when it is **not** inside a class extending the port. Seeded both ways (a sanctioned
subclass and a bare duck-typed class in the SAME file, so the seed cannot pass by the scan
merely being off) and mutation-proved: with the exemption removed, the failure that fires
is that seed's own `assertNotIn`.

**And `test_every_shipped_row_prints_above_the_verdict` expired on success.** It iterated
`PORT_BURN_DOWN` and asserted each label appeared; when the port emptied the list it became
a loop over nothing wrapped around an assertion that could only fail. That is
[#642](https://github.com/timbermania/fft-monorepo/issues/642)'s lesson — *a control that
depends on the defect it controls for expires on success, and the expiry is
indistinguishable from a regression* — landing inside the very test file whose docstring
says *"when arm 1 reaches 0 these tests do not change."* It now SEEDS both the site and the
row, so it says the same thing at any burn-down size, zero included.

### Two more things the build settled that the design left implicit

- **The port object is stable across a map reload; the store is rebound** (ADR-0193
  dec. 4). Dec. 3's `var lattice: Lattice = map.lattice` is taken ONCE at boot by five
  consumers, and a composer that rebuilt the object on `change_map` would leave every one
  of them answering for the previous map — the held-node bug one level up, and worse,
  because a stale port still answers.
- **A fetch landing straight into an INHERITED field is not clean, and the fix is a typed
  local.** `GPUArena.gd:117` and six `tests/` files store the handle in `CombatHost.lattice`,
  declared on the base class; receiver inference is per file, so both the fetch and every
  later call read as *undeclared in this file* — this ADR's own stated blind spot. Rather
  than attempt cross-file resolution (which no guard in this repo does), each site takes
  `var lat: Lattice = ...` in the file that uses it. That is not a workaround for the guard:
  it is the file stating the type it is relying on, which is the only form of the claim
  anything can check.

### `Lattice` gained one addon-internal member the design did not name

`_tiles()` — the raw `Array[Tile]`, underscored, for `MapGridOverlay.build_from_lattice`
(dec. 5) and `TileCursor`, both addon files. Underscored is load-bearing:
`check_lattice_doors.py` scores PUBLIC members only, so a published `tiles()` here would
put the port itself onto the Tile-door register it exists to empty. ADR-0192 dec. 5's own
sentence is the licence — *"a back door only addon files can open — correct, because the
addon is the encapsulation unit here, not the class"* — and a host file reaching it is the
defect arm 1 catches.

### 🔴 ARM 3: the addon was the one region nothing scanned, and it paid on the first day

Arms 1 and 2 exclude `addons/exmateria_battlefield/` deliberately — the addon owns the
store, so `_store.get_tile(x, z)` inside `Lattice.gd` is the port doing its job. But
`addons/exmateria_battlefield/camera/PlayerCamera.gd` reached its map exactly the way
every host file did:

```gdscript
if not procedural_map or not procedural_map.has_method("get_all_tiles"):
	return Vector3.ZERO
var tiles = procedural_map.get_all_tiles()
```

Deleting the forwarder (dec. 1 of ADR-0170) did not make that error. **The `has_method`
probe absorbed it and the function started answering "no tiles" forever**, which centres
the battle camera on the world origin — a silent wrong answer, two call sites, in the one
region every register was blind to. It was found by grep, not by an instrument, which is
the definition of a hole.

**Arm 3 is the repair, and it is decidable without a `class_name`.** Inside the addon:

- a **LEGACY** call (`get_tile` / `get_all_tiles`) is clean iff its receiver is annotated
  with **this file's own `const X = preload(".../TerrainIndex.gd")` alias** — `TileStore`
  in `Lattice.gd` and `TileHighlights.gd`, `TerrainIndexStore` in `MapComposer.gd` and
  `DynamicTerrainBuilder.gd`;
- a **FUTURE** call keeps arm 1's allowlist rule, because inside the addon a consumer of
  the port is still a consumer of the port;
- `lattice/TerrainIndex.gd` is excluded by path — it is the store, and its own
  `func get_tile` is the definition. That exclusion is why arm 3 needs no producer scan.

It reads **0** on arrival, and the two `PlayerCamera` sites now take `_map_tiles()`, which
goes through `map.lattice` and opens the port's addon-internal back door.

⚠️ **Writing it cost the same lesson a third time: two arms over one file need opposite
strippers.** `store_aliases` first read `_code_lines`, and `strip_noncode` blanks string
literals — so the `preload("res://…")` path, the only thing identifying the store,
was gone before the scan saw it. Every alias came back empty and arm 3 reported the port's
own four call sites as the defect. It is the same shape as the `has_method("X")` probe
rewrite two functions above it, and it is now seeded both ways: the store alias must be
CLEAN and an untyped receiver must be RED, in the same run.
