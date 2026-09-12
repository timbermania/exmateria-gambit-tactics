# The third door is a forwarder, and the duck-typing is a test seam

[#567](https://github.com/timbermania/fft-monorepo/issues/567) asked whether
`MapComposer.get_tile` collapses into the `Lattice` port, what pass 6 owes for the
**12 duck-typed call sites**, and whether `Unit.get_current_tile()`'s circular-dependency
dodge survives.

All three questions carried a premise from
[ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 3's door table, and **each premise is wrong in a different direction**. The
"second implementation" is a three-line forwarder. The "third door" is not a door — it
reads a stored field and never queries the lattice. And the twelve are **fifteen** in
`src/` and **twenty more** in `tests/`, where `classify()` returns `None` and no register
on this map can see them.

The larger finding is the *cause*. ADR-0164 dec. 2 explains the duck-typing as `Cutscene`
and `Effects` declining a dependency on a `StaticBody3D`. Measured, at least half the
pressure is a **test seam** — seven test files manufacture the door by defining their own
`get_tile`, four of them returning something that is not a `Tile` at all, and the source
says so by name. That makes dec. 2's value payload right for a reason it did not claim,
and retires dec. 3's runner-up on a second ground it never considered.

Status: accepted (2026-08-25). Resolves
[#567](https://github.com/timbermania/fft-monorepo/issues/567) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3, loop pass 5).
Amends **ADR-0164 dec. 2, dec. 3 and dec. 4 criterion 2** in place. Upholds
**ADR-0166 dec. 2** and reads its consequence forward.

Code at `66a67d990`, classifier at `66a67d990`.

## Context

Every figure below was measured in `~/Repos/fft-monorepo-ext3-pass4` at `66a67d990`, not
quoted from a prior pass. `touch_matrix.py` at that commit reads `Cutscene → Battlefield`
= **4** and a cross-SYSTEM total of **1040**.

### The twelve, re-derived

The ticket's table is exact on its own terms — twelve `.get_tile` call sites with an
untyped receiver, `Cutscene` 9, `Battle` 2, `Effects` 1 — but it spans **six** files, not
the five its layout suggests:

| system | file | sites |
|---|---|---|
| `Cutscene` | `src/scenarios/ScenarioVM.gd` | 3537, 3554, 3785, 3796, 3808 |
| `Cutscene` | `src/scenarios/ScenarioCameraDirector.gd` | 709, 1097, 1110 |
| `Cutscene` | `src/scenarios/ScenarioWeather.gd` | 300 |
| `Battle` | `src/units/Unit.gd` · `src/units/MovementComponent.gd` | 1632 · 28 |
| `Effects` | `src/effects/CinematicFacingResolver.gd` | 156 |

### Where the untypedness comes from

It has **one origin**, and it is structural rather than stylistic: six assembler scene
roots hold the composed map as `@onready var map: Node3D = $ProceduralMap`
(`GPUArena.gd:39`, `ScenarioPlayerScene.gd:174`, `TrapViewerScene.gd:8`,
`ProgressionTester.gd:18`, `UnitAnimationViewerScene.gd:22`, `EffectViewerScene.gd:26`).
A NodePath fetch infers `Node`, and every consumer receives *that*. Production assigns the
handle onward at exactly **three** points — `ScenarioPlayerScene.gd:357`,
`ScenarioVM.gd:3079`, `src/gpu/CinematicManager.gd:282`.

## Decision

**1. `MapComposer` drops `get_tile` and `get_all_tiles`. There is no forwarder — and there
never was a second implementation.**

`src/map/MapComposer.gd:308-311` is a three-line null-guarded delegation:

> ```gdscript
> func get_tile(x: int, z: int) -> Tile:
> 	if terrain_index:
> 		return terrain_index.get_tile(x, z)
> 	return null
> ```

`get_all_tiles` (318-321) is the same shape. ADR-0164 dec. 3 and #567's body both call
this *a second implementation of the same query*; it is a forwarder with a null guard,
and the guard is load-bearing because `terrain_index` is null before the map builds. The
ticket's framing offered *collapse* or *keep a convenience forwarder* — the forwarder is
what already exists, so the live choice is whether the composer answers the lattice query
**at all**.

It does not, on three grounds in increasing force:

- **A forwarder cannot close the door, by construction.** While the query lives on the
  composer *node*, its receiver is whatever `$ProceduralMap` yields, which is `Node`.
  Every consumer keeps an untyped handle and the register stays at its baseline. That is
  precisely ADR-0164 dec. 3's injection failure mode: the count falls, the reach is never
  named.
- **Criteria 1 and 2 disagree on a forwarder, and criterion 2 is the honest one.**
  Criterion 1 requires `MapComposer` absent from the published *annotation* set; a
  forwarder satisfies it while every reach stays duck-typed, because there is no
  annotation to find. A design that passes a guard by being invisible to it is the shape
  this loop keeps being fooled by — dec. 4(b) in a third dress.
- **ADR-0166 dec. 4 criterion 3 forbids it outright.** `MapComposer.get_tile` /
  `get_all_tiles` are two of that register's eight rows, target **0**. A forwarder
  returning `Tile` violates it; a forwarder returning `TerrainCell` is a second port,
  which dec. 1 already refused.

`MapComposer` instead exposes the port it owns — `lattice: Lattice` — and consumers name
the type. The cost is 13 call sites across 6 `src/` files and 7 test files, plus the
three production assignment points above.

**2. The port needs a fourth member. ADR-0164 dec. 2's three-member surface is
incomplete, and door 1 cannot close without it.** *(Amends ADR-0164 dec. 2.)*

Dec. 2 publishes `terrain_at(x, z) -> TerrainCell`, `world_position_at(x, z) -> Vector3`
and `is_cliff_edge(a, b) -> bool`. There is no all-cells query — and dec. 1 states door
1's used surface is *exactly two methods*, the second of which is `get_all_tiles()`. Its
external consumers are real and they are not debug-only:

| consumer | system | reads per tile |
|---|---|---|
| `src/gpu/DistanceFieldGenerator.gd:54` | `Battle` | `impassable`, `grid_x`, `grid_z` |
| `src/gpu/GPUBatchSimulator.gd:466` | `Battle` | `grid_x`, `grid_z`, height, cliff edges |
| `src/strategy/PlacementTileGenerator.gd:77` | `Battle` | placement validity |
| `src/debug/ScenarioUnitAlignmentDebugPanel.gd:137` | `Cutscene` | grid line mesh |

So the port publishes **four** members, adding `all_cells() -> Array[TerrainCell]`. Every
read above is a `TerrainCell` field; none needs the node. Stated here rather than left for
pass 6 to discover, because without it the `get_all_tiles` sites have nowhere to re-point
and both doors stay open.

> 🔴 **Amended 2026-08-27 by [ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)
> dec. 5 at loop pass 6: *"none needs the node"* is FALSE on the fourth row.**
> `ScenarioUnitAlignmentDebugPanel.gd:137` hands `get_all_tiles()` to
> `MapGridOverlay.build_from_tiles`, which reads `tile.tile_vertices` (four tile-local
> verts) **and `tile.global_transform`** to bake a world-space grid mesh. Neither is on
> ADR-0164 dec. 2's field list and neither derives from it. The repair is not a fatter
> cell or a fifth member: `MapGridOverlay` **is an addon file**, so the `Array[Tile]`
> leaves the addon and comes straight back in. `build_from_tiles(tiles: Array)` becomes
> `build_from_lattice(lattice: Lattice)`, the overlay reads the unpublished store
> directly, and no `Array[Tile]` crosses the boundary at all. The port's member count is
> unchanged at four.

**3. Thirteen re-point, one dissolves, and the handle splits rather than retypes.**

The register's `src/` population is **fifteen lines across six files**, not twelve:

| | lines |
|---|---:|
| `.get_tile` call sites | 12 |
| `.get_all_tiles` call site — `src/debug/ScenarioUnitAlignmentDebugPanel.gd:137` | 1 |
| `has_method(<port method>)` guards — `ScenarioWeather.gd:299`, `…DebugPanel.gd:132` | 2 |
| **total** | **15** |

⚠️ **The `get_all_tiles` site is `Cutscene`'s, not `Debug`'s.** `classify()` books
`src/debug/ScenarioUnitAlignmentDebugPanel.gd` to **`Cutscene`**, and its receiver is
`get_node_or_null("ProceduralMap")` — a **by-name scene lookup**, the widest spelling of
all. `Cutscene`'s share of this door is **ten**, not nine.

**One of the twelve is deleted, not re-pointed.** `src/units/MovementComponent.gd:28`
reads `map.get_tile(int(pos.x), int(pos.z))` where `pos` is `_unit.global_position`.
ADR-0166 dec. 2 retypes `current_logical_tile` to `Vector2i`, and both arguments derive
from the unit's **own** transform — so the line becomes `Vector2i(int(pos.x),
int(pos.z))`, needs no map, and `initialize_logical_position(map: Node3D)`'s parameter
goes dead across its three callers (`Unit.gd:1655`, `NavigatorMain.gd:567`, `:1136`).
Pass 6 must not re-point a site #554 removes.

**The remaining twelve read exactly three things, and dec. 2's payload covers all of
them:** `tile.global_position(.y)` at eight sites → `world_position_at`; `tile.impassable`
/ `tile.height` at two (`ScenarioVM`'s `EventWalkNav`) → `terrain_at`; a bare existence
check at one (`Unit.place_on_tile`); and the all-cells iteration at one → dec. 2 above.
Nothing needs a member the port does not have.

🔴 **But re-pointing them leaves the handle exactly as untyped as it is today.** Through
`map_composer`, `src/` reaches:

| member | reaches | on the port? |
|---|---:|---|
| `get_tile` | 9 | yes |
| `has_method("get_tile")` | 1 | yes (guard) |
| `is_animation_active` | 3 | **no** |
| `play_texture_animation` · `commit_field_tint` · `set_field_color_stack` · `change_map` · `rebuild_map` | 1 each | **no** |
| `has_method(<those five>)` | 5 | **no** |
| `name` | 1 | — |

The port covers **10 of ~24**. What survives is a **field-effects and animation** seam
with five reflection guards of its own. So `ScenarioVM` and `ScenarioWeather` each gain a
typed `lattice: Lattice` **and keep** the untyped composer handle for that surface, which
is **named as remaining debt with its number** so pass 9 reads `Cutscene → Battlefield`
rising to ~13 as *partial*. Pulling the second seam in would re-open what `Battlefield`
publishes after dec. 1 settled it; leaving it unnamed is how it stays invisible for
another three passes.

**4. `Unit.get_current_tile()` is not a door into the lattice, and #554 dissolves its
dodge twice over.** *(Amends ADR-0164 dec. 3's door table.)*

Dec. 3 lists `Unit.get_current_tile()` as door 3. Its body reads a **stored field**
(`movement_component.current_logical_tile`) and queries nothing — it is ADR-0166's
**holder 4**, already decided, and the table row is a mis-classification.

**The circular dependency it dodges is real, and it is exactly the occupancy members.**
`src/map/Tile.gd` names `Unit` on four code lines — `70` (`reserved_by: Unit`), `201`
(`is_blocked`), `213` (`try_reserve`), `234` (`release`) — and on nothing else. Those four
are precisely what ADR-0166 dec. 1 **deletes**, so `Tile.gd → Unit.gd → Tile.gd` stops
existing. The asymmetry proves the author's comment was correct rather than lazy:
`MovementComponent.gd:9` already declares `var current_logical_tile: Tile` and compiles,
because `Tile.gd` does not name `MovementComponent`; only a return annotation in `Unit.gd`
closes the loop. And ADR-0166 dec. 2 dissolves it a second, independent time — the
function returns `Vector2i`, so there is no `Tile` left to annotate.

⚠️ **Recorded, not owned:** after #554 the function returns a `Vector2i` while still
called `get_current_tile()` across **28 call sites / 8 `src/` files and 5 test files**,
keeping the word *tile* meaning a scene node in `Battle`'s vocabulary. That is `Battle`'s
naming question and sits beside
[#571](https://github.com/timbermania/fft-monorepo/issues/571), already off this map.

**5. The duck-typed-door register has two arms — enforcing over `src/`, reporting over
`tests/` — because `classify()` returns `None` for every test file.** *(Amends ADR-0164
dec. 4 criterion 2, whose baseline was 12.)*

🔴 **`tests/` is a second population, and it is larger than the first.** `classify()`
returns **`None`** — not a bucket, not `content` — for every file under `tests/`. This is
ADR-0167 dec. 6's hole at `assembler` and #551's unbucketed-asset hole arriving a third
time, now as the **majority of a door's population**:

- **13 consumer call sites** — four through `@onready var map: Node3D = $ProceduralMap`
  (the identical assembler pattern), nine through a `terrain_index` handle whose own
  origin is a duck-typed `map.terrain_index` read at `tests/GPUCombatTestBase.gd:67`.
- **7 files that define `func get_tile`** — mock maps. **Producers of the door.** No
  register on this map counts a producer outside the addon; ADR-0166 dec. 4 chose the
  producer side precisely because it is the decidable one, and here the producers are
  outside it.

So:

| arm | scope | today | target |
|---|---|---:|---|
| **1 — enforcing** | `src/` (and, after pass 6, the host tree outside the addon): call sites whose receiver carries no type and whose method, or `has_method` argument, is on the published port | **15** | **0** |

> ⚠️ **Amended 2026-08-27 by [ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)
> dec. 2, 3 and 7: arm 1's rule is inverted, its baseline is 27, and arm 2's scope is
> re-opened.** *"Receiver carries no type"* is false on five of arm 1's own fifteen
> sites — `ScenarioVM.gd:104` and `ScenarioWeather.gd:72` (`map_composer: Node`),
> `Unit.gd:1620` and `MovementComponent.gd:23` (`map: Node3D`), and
> `ScenarioUnitAlignmentDebugPanel.gd:131` (`var map := _get_map()`). Arm 1 is re-phrased
> as an allowlist — **clean iff the receiver is provably typed `Lattice`** — which needs
> no special case for `Node` / `Node3D` / `Variant` / inference and cannot be satisfied by
> writing a different wrong type. The baseline becomes **27 = 15 + 12**, and the tool
> prints the split so this row's 15 stays checkable. Arm 1 additionally scores the handle
> **fetch** (`map.terrain_index` on an untyped receiver: 3 in `src/`, 9 in `tests/`), whose
> clean form is one typed fetch at the seam — `var lattice: Lattice = map.lattice` —
> because criterion 1 forbids publishing `MapComposer`, so the map handle can never be
> typed. ⚠️ **Arm 2's reporting-only ruling is re-opened, not overturned**: a NAMED
> BURN-DOWN is not a threshold (`DOOR_BURN_DOWN`'s own #424 rationale), and it answers this
> decision's *"reads as coverage"* risk directly. ADR-0192 dec. 7 leaves it to whoever
> builds arm 2. Either way both arms use the new rule, so arm 2's **20** moves too.
>
> ✅ **RULED and BUILT 2026-08-27** (ADR-0192's amendment, `tools/check_lattice_ports.py`).
> **Arm 2 ENFORCES against a named burn-down.** This row's reporting-only ruling rests on
> `classify()` being blind over `tests/`, which rules out a *threshold*; a named list
> consults no `classify()` at all, so the objection does not reach it, and this decision's
> own *"reads as coverage"* risk is answered instead of carried. Arm 1 reproduced **27 =
> 15 + 12** on the guard's first run — this row's **15** exactly. Two numbers above are
> corrected downward by the scan, neither changing a decision: arm 2's consumer calls are
> **12, not 20's 13** (the thirteenth raw line is a `##` comment in
> `tests/MapBufferBoundsTest.gd:7`), and the `tests/` handle fetches are **10 lines over 9
> FILES**, not "9" — `tests/gambit_runner/GambitScenarioRunner.gd` fetches twice. This
> row's **7** mock producers reproduces exactly (7 files, 10 declarations); the tool prints
> both units because dec. 6's ">=4 of the 7 are deleted" is a claim about files.
| **2 — reporting** | `tests/`: the same scan, plus mock **producers** defining `get_tile` / `get_all_tiles` outside the addon | **20** | none |

Arm 2 reports rather than enforces because `classify()` is blind there and any threshold
would be guesswork — and it must exist, because arm 1 reaching zero while twenty cases sit
in `tests/` reads as coverage. ADR-0168's rule: a silent cap is indistinguishable from a
met goal.

⚠️ **GDScript has no interfaces**, so a mock cannot *implement* `Lattice` — it must
`extends Lattice` and override, or the test constructs a real `Lattice` seeded with
fabricated `TerrainCell`s. Arm 1 must be written so that both routes pass; a register
phrased as *"the receiver must be a `Lattice`"* admits both, one phrased against
subclassing forbids the cheaper one.

**6. The duck-typing is a test seam as much as a type refusal, and that is why the value
payload is right.** *(Amends ADR-0164 dec. 2's stated cause.)*

Dec. 2 explains the twelve as `Cutscene` and `Effects` declining a dependency on a
`StaticBody3D`. That is true and it is not the whole cause. Four of the seven mocks return
something that is not a `Tile`:

| mock | returns |
|---|---|
| `EffectStudioCameraOwnershipTest._FakeMap` · `TileCursorIntegrationTest._FakeMap` · `TileCursorTakeoverTest._FakeMap` | real `Tile` |
| `ScenarioSpriteMoveTest.MockMap` | bare `Node3D` |
| `ScenarioCameraSwoopMonotonicTest.MockMap` | ad-hoc `MockTile` |
| `ScenarioWalkFacingAngleTest._FakeMap` · `ScenarioWalkToAnimTest.FakeMap` | `FakeTile extends RefCounted` |

And the source states the cause by name. `src/scenarios/ScenarioVM.gd:3788` reads
`if "impassable" in tile and tile.impassable:` under a comment reading *"Mock maps without
an `impassable` field count as walkable."* The `in` probe is there **for the mocks**.

Faking a `StaticBody3D` in a unit test is expensive; fabricating a `TerrainCell` is not.
So dec. 2's value payload **removes the pressure that created the pattern**, and at least
four of the seven mock classes can be deleted outright rather than ported. This also
retires dec. 3's honest runner-up — *the port answers the node* — on a **second** ground
it never considered: it would have kept the test seam painful, not merely put a
`StaticBody3D` in three systems' signatures.

## Prediction

Scored at pass 9, against `66a67d990`:

| term | now | predicted | note |
|---|---:|---:|---|
| duck-typed door, arm 1 (`src/`) | **15** | **0** | needs the instrument dec. 5 specifies |
| duck-typed door, arm 2 (`tests/`) | **20** | **falls, no target** | reported; ≥4 mock classes deleted outright |
| `Cutscene → Battlefield` | 4 | **~13** | ten sites named; ~14 residual reaches stay duck-typed **by decision** |
| port members (ADR-0164 dec. 2) | 3 | **4** | `all_cells()` |
| `MapComposer` lattice methods | 2 | **0** | no forwarder |
| `Tile.gd` → `Unit` references | 4 | **0** | ADR-0166 dec. 1; the cycle ends |

**The falsifiable one, in the direction that hurts:** if pass 9 reports
`Cutscene → Battlefield` at or near **24**, the animation/tint residue was re-pointed too
and this decision under-scoped the seam. If it reports **4**, nothing shipped. ~13 is the
success case *and* an incomplete one, and dec. 3 says so on purpose.

## Consequences

- **Pass 6 owes a fourth port member**, `all_cells() -> Array[TerrainCell]`, which no
  earlier pass costed.
- **Pass 6 re-points twelve sites and deletes a thirteenth**, and must take ADR-0166 dec. 2
  first at `MovementComponent.gd:28` or it will do the work twice.
- **`initialize_logical_position(map: Node3D)` loses its parameter**, changing three
  callers in `Battle` and `assembler`.
- **The duck-typed-door register gains a second, reporting arm** and its enforcing
  baseline moves 12 → **15**. Pass 6's owed-instrument count is unchanged at four; this
  changes the shape of one of them.
- **`Cutscene` keeps ~14 duck-typed reaches into `Battlefield`** after this ticket, named
  as debt rather than closed. Whoever publishes the field-effects surface owns them.
- **At least four test mock classes are deleted rather than ported**, which is the first
  place in extraction #3 where the extraction makes the test seam *cheaper*.
- ADR-0164 dec. 3's door table is **upheld on its finding and corrected on two rows**:
  door 2 is real and was under-counted; door 3 is not a door.

## Alternatives considered

- **Keep a convenience forwarder on `MapComposer`.** Rejected on dec. 1's three grounds,
  the decisive one being ADR-0166 dec. 4 criterion 3, which lists both methods as rows
  with target 0. It is also the option that reads best on criterion 1 while changing
  nothing, which is the tell.
- **Retype `ScenarioVM.map_composer: Node` to `Lattice` outright.** Rejected on
  measurement: the handle carries fourteen non-lattice reaches, five of them behind
  `has_method` guards. Retyping breaks them; the split does not.
- **Pull the animation/tint surface into this ticket and publish it too.** Rejected as
  re-opening ADR-0164 dec. 1 after it settled what `Battlefield` publishes. The risk is
  stated rather than dismissed: a named debt is still a debt nobody schedules, and this
  decision's own prediction is the only thing that will surface it.
- **Enforce the register over `tests/` as well.** Rejected because `classify()` returns
  `None` there, so the scope of an enforcing arm could not be stated in the same
  vocabulary as arm 1 — and a guard whose population is undefined reports the scanner, not
  the code.
- **Count the register at 12, as ADR-0164 dec. 4 wrote it.** Rejected: twelve is the
  `.get_tile` count. Fifteen is the edit, and the two `has_method` guards and the
  `get_all_tiles` site would survive a register that hit zero — the same
  unit-of-measurement error ADR-0169 recorded at *"exactly 8"*.
- **Rename `get_current_tile()` in this ticket.** Rejected: 28 call sites across `Battle`,
  `Debug`, `Cutscene` and `assembler`, and the concept is #571's. Recorded in dec. 4.
