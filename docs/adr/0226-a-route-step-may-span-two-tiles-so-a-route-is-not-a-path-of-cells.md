# A route step may span two tiles, so a route is not a path of cells

`EventPathfinder` was a 4-directional uniform-cost breadth-first search that
returned a list of cells:

```gdscript
return {"path": path, "endpoint": endpoint, "reached_target": reached}
```

Every step was one tile, so the `extra` field of the route byte the renderer
consumes was always `0`, and a **leap** could not be encoded at all. ADR-0225
transcribed the render half and it already knows how to fly one — `_arm_leap` is
covered across all 32 states of `unit+0x7f` — it was simply never handed such a
byte. That is the whole of
[#803](https://github.com/timbermania/fft-monorepo/issues/803): *"`{28}` Walk To
wades the Igros moat because the event pathfinder has no terrain cost and cannot
emit a JUMP step."*

The ROM's planner, `FUN_8017813C @ 0x8017813C`, is not a BFS and does not return a
path. It floods a **move budget** — the start is seeded with 125 and each step
subtracts the destination surface's cost out of the SCUS row at `0x8005EA50` — and
then rebuilds the route by walking **backward** from the target with no predecessor
links anywhere, accepting a predecessor `P` of a cell `C` iff

```
budget[P] − cost[surface(C)] − span == budget[C]
```

`span` is the third term and it is the one that matters here: `FUN_801764D8` is a
**second expander**, run beside the adjacent one on every direction of every step,
that relaxes the tile `span + 1` away when the tiles being flown over are clear.
So a step is not a move to a neighbour. It is a move to a cell up to
`stateB+0x05` tiles away, and that byte is `climb >> 1` — for `{28}`, `3 >> 1 = 1`.
One extra tile, which is exactly the width of the Igros moat.

Status: accepted (2026-09-04). Built on `port/803-rom-event-planner`, tickets
[#803](https://github.com/timbermania/fft-monorepo/issues/803) and
[#819](https://github.com/timbermania/fft-monorepo/issues/819). The sibling of
**ADR-0225**, which took the render half and explicitly filed this one as the
caller's remaining change (dec. 8). Publishes one name under **ADR-0211 dec. 4**
and ships its test under **ADR-0194**. Consumes **ADR-0202 dec. 5**'s host-injected
content root and **ADR-0219**'s two-level cell.

## Context

### The old planner was not a bad approximation of this one — it was a different question

A uniform-cost BFS answers *"what is the shortest chain of adjacent cells?"* The
ROM answers *"which cells can this unit reach on 124 move points, and what is the
cheapest way back from the target?"* The two coincide on a flat map with one
surface type and they diverge the moment terrain has a cost, because a cost flood
can express **around** and a step count cannot.

Three of the divergences were visible in the game:

- **the moat.** MAP009's Waterway costs 2 where grass costs 1, and a one-tile
  channel can be leaped for `span 1 + surface 1 = 2`, which ties with the two walk
  steps it replaces. The walk-back's span tie-break then decides — and it prefers
  the **adjacent** pass, so it takes the leap only when the leap is *cheaper*, not
  when it is equal. Scenario 29 PC 148: the ROM crosses in **8** steps with two
  leaps; the shipped BFS took **10** and waded.
- **the bridge.** `stateA+0x55` is 2, so the flood relaxes **both levels of a
  column** on every step. A level change costs nothing, and route byte bit 5 says
  which level a step landed on. Twelve of the 209 replayable corpus routes set that
  bit; no live capture in the whole investigation ever had, until arm O was built
  to make one.
- **the refusal.** There is no nearest-reachable-tile fallback anywhere in
  `FUN_8017813C`. An unreachable target returns NULL and the opcode does nothing.

### The input did not exist, and that was the actual blocker

`#819` was filed as render fidelity. It is the gate on both halves. The flood reads
**eight** fields per tile — surface, height, depth, slope height, slope type,
thickness, impassable, unselectable. `TerrainCell` carries four of them, and a
surface *name* rather than a byte. Depth is what makes a unit stand on the water
surface rather than the bed; slope height and type are what make a tile a different
height depending on which way you cross it; thickness is what makes a bridge deck a
**ceiling** over the moat rather than a second floor.

All eight are in every shipped `assets/maps/MAP###/terrain.json` already. So the
work was a reader, not an export — and the reader's real cost is that it needs a
second GDScript copy of the exporter's 13 slope-type and 50 surface-type
name-to-byte tables, which live only in `tools/fft_exporter/models/terrain.py`.

## Decision

**1. The route planner is a transcription, and it replaces `EventPathfinder` in
place rather than sitting beside it.** `EventPathfinder.gd` is now
`research/scenario29_walk_vs_jump/evidence/rom_event_flood.py` in GDScript, branch
for branch, every function carrying the address it came from. `find_path` and its
`nav` duck type are **deleted**, not deprecated: a second planner in the tree is
the failure mode the whole research document exists to avoid, and the two cannot be
reconciled anyway — one asks a `Lattice` three questions, the other reads eight
bytes per tile.

Replacing in place rather than adding `RomEventPlanner` beside it keeps the name
`EventPathfinder` accurate (it *is* the event movement pathfinder), keeps the
`[[Walk To Opcode]]` vault anchor resolving, and keeps ~15 ADR citations and the
move-manifest row pointing at a live file. ADR-0168's own guard test enumerates
"delete `EventPathfinder.gd` outright" as a thing nothing else in the tree would
notice.

**2. It is scored against the WIRE, and the fixtures carry two independent wire
measurements.** `tools/gen_rom_event_route_fixtures.py` bakes **18** live PCSX
captures into `addons/exmateria_battlefield/tests/fixtures/rom_event_route/`, each
with the post-patch MAP009 tile array its arm ran against. Two different columns of
those logs state two different facts and both are scored where they exist:

  * `route` — the ROM's emitted bytes, off the per-frame `rb=` column (five arms),
    the run report's OBSERVED line (seven), or the run's `-> route:` line (two).
    **12 arms.**
  * `cells` — the tile sequence the unit actually visited, off the per-frame
    `tile=` column. **8 arms**, and this is *more* than the Python spec scores:
    `rom_event_flood_arms.py` is 9/9 on route bytes, and arms B, C and F have no
    route column in their logs at all, so it can only state them from prose. The
    `tile=` column scores them against hardware.

`EventPathfinderTest` reports **107 assertions, 0 failed, 7/7 arms**, and it
reproduced the Python's score exactly on the first run — as ADR-0225 predicted for
its own half, and for the same reason: both are integer arithmetic over the same
tables, so any divergence at all would have been a transcription error.

**3. A REFUSAL is a first-class expectation, scored as hard as a route.** Three of
the eighteen arms — P, R1, R2 — are captures in which the ROM emitted **no route**:
arm P watched the route buffer stay empty for 3338 frames while the control reached
its target in 3333. The test asserts the empty buffer, `reached_target == false`,
an endpoint equal to the start, and a non-empty reason string. Arm **R0** is the
negative control that makes those three mean anything: same tile, depth 0, the
height raised instead — and the route is unchanged.

**4. The destination gate is `stateB+0x14`, and it is INHERITED rather than
written.** This is the decision the routing half has owed since it was transcribed,
and it is justified by measurement that **falsified its own prediction**.

`FUN_801787E0`'s reachability sweep reads `stateB+0x14`, which `FUN_8017813C` never
writes — it is left over from the last `FUN_80174430`. The prediction (README
§21.8) was that only depth ≥ 3 would refuse a target. Arms R1 and R2 patched the
destination to depth 1 and depth 2 and the ROM **refused both**. So the flag is
non-zero here and **any** depth > 0 tile is an invalid destination.

The competing explanation — that it is `stateB+0x11`, standability — is ruled out
by a capture already in hand: arm L had the unit **stand** on the depth-1 Waterway
at (1,8) during this very instruction. Depth-1 tiles were standable and still not
targetable. Arm R0 rules out the height change. The port therefore ships
`_b11 = 0` and `_b14 = 1`, and both are named as inherited state rather than
constants, because that is what they are.

**5. `RomTerrain` reads the map file, and the two enum tables are mechanized.**
`addons/exmateria_battlefield/terrain/RomTerrain.gd` turns a `terrain.json` into the
ROM's own eight-byte tiles in PSX coordinates, applying the ADR-0052 Z flip
`psx_y = size_z − 1 − grid_z` **once, at the boundary**. Skipping that flip returns
a fully-formed, plausible route on a **mirrored** map and never throws; it cost one
research round already.

`tools/check_rom_terrain_tables.py` asserts set equality on the names and equality
on every value, both directions, against the Python enums — and is registered in
the pre-flight, because a guard the suite does not list is a guard nobody runs
(ADR-0175). It is the deliverable and not a nicety, because a disagreement is
invisible to every other instrument here:

  * an unknown name reads as byte 0, which is `Flat` / `NaturalSurface` — a legal
    tile. A missing row silently **flattens** the map rather than raising;
  * a wrong byte simply **routes**. `Waterway` at index 15 instead of 14 costs 1
    instead of 2 and the Igros moat stops being a moat. No crash, no error, no
    failing assertion anywhere — just a route that is not the ROM's.

**6. A caller that cannot supply a map gets a poorer MAP, not a second planner.**
A scene with no `map_id` — every scenario test — falls back to
`RomTerrain.from_lattice`, which states height, impassable, unselectable and the
surface (via the same name table) and cannot state depth, slope or thickness. One
planner still runs; what changes is how much of a tile the caller can say. The
fallback warns **once per VM**, because a silent downgrade of the map underneath a
planner scored on real tiles is exactly the thing that reads as a routing bug
months later.

**7. The flood-record stride is `max(0x100, nx·ny)`, and the deviation is proved
inert.** The ROM indexes its flood records `level · 0x100 + psx_y · size_x + x`, so
256 slots per level. Across all 119 shipped `terrain.json` the largest map is
**MAP125 at 16 × 16 = 256 tiles exactly** — the ceiling, hit and never exceeded — so
the computed stride equals the ROM's everywhere the ROM can address. It widens only
for a synthetic map built in code, where a test scene's `Lattice` is routinely
20 × 20 and the ROM's stride would silently **alias** one tile onto another. The
index is a bijection used only to key this class's own arrays and never as an
address, so a larger stride relabels the same records. The evidence that it is
inert is that all 18 wire arms re-passed unchanged after the switch.

**8. The Z flip lives in `ScenarioPathMotion` too, and `psx_rows` is how it is
said.** `configure_rom` now takes the map's `size_z`. Without it a PSX-coordinate
terrain renders **mirrored down the map** — right length, right shape, right
duration, wrong direction — and the route byte's ±Y facings mirror with it. `0`
means "this frame is already Godot-oriented", which is what `configure`'s own local
frame is.

**9. `configure` stays, and its docstring says the new reason.** It documented the
missing leap as a fact about the planner. The planner emits one now; a **waypoint
list** still cannot carry it, because `_grid_delta_to_route_byte` has no way to say
a step spanned two tiles. That is a statement about the polyline, and it is the one
`configure` should have been making all along.

**10. The retired test's twelve questions are split three ways, in place.**
`ScenarioEventPathfinderTest` drove the BFS over a `MockNav` that no longer exists
and is deleted with it. `EventPathfinderTest` arm 7 records where each arm went:
four are covered by wire captures, five are carried over on synthetic terrain, and
**three are superseded** — including *"an unreachable target stops on the nearest
reachable tile"*, which was never the ROM, and *"the climb gate is what keeps the
walk out of the water"*, which is false in the most direct possible way: the ROM
leaps it.

## Prediction

The port itself could not be predicted into a file the way the research arms were,
because the fixture generator **refuses to bake** a capture the Python does not
reproduce — the expectations were fixed from the wire before a line of GDScript ran,
which is the same guarantee by a different mechanism. What was written down and
checked:

1. **A faithful GDScript port reproduces the Python's score exactly.** *Held, first
   run:* 107 assertions, 0 failed, over 18 wire captures and 6 corpus cross-checks.
2. **Q7's ship gate stays at zero when the destination gate is applied.** The
   corpus replay had never applied `FUN_801787E0` — it scored `walk_back` alone —
   so this was an open number, not a re-run. *Held:* over the 209 replayable
   shipped `{28}`s the gate refuses **0** additional routes, and **0** routes newly
   stop short. 7 of 209 change shape; 5 are scenario 29's leaps.
3. **At least one existing assertion encodes BFS-era behaviour and goes red.**
   *Held,* and it was not the one expected: `ScenarioApplyTest`'s
   `_test_walk_to_latches_where_it_stopped_not_where_it_was_sent` is built entirely
   on the nearest-tile fallback, and its premise is gone.

Two of this ADR's own synthetic arms were **falsified before they were written
down**, by checking them against the Python oracle rather than reasoning:

- *"climb 7 cannot clear seven whole levels."* False — `7 << 1 == 14` half-levels
  and the compare is `>`, so seven levels is exactly clearable and the arm has to
  reach for eight.
- *"a one-tile moat with a bridge deck is crossed over the deck."* True, but not for
  the reason assumed: the leap across it is *available* and loses the tie-break to
  the adjacent pass. The arm as first written asserted the cells and would have
  passed while testing something else.

## Consequences

- **Five shipped routes in scenario 29 now leap**, and seven of 209 change shape.
  Anything timed against the old route lengths was timed against a longer walk.
- **A `{28}` Walk To can now be refused outright.** `_plan_walk_route` returns `{}`
  and `ScenarioApply.walk_to` arms nothing, latches nothing and sets no walking
  state — which is what the ROM does, and is a state the game has never been in.
  Measured blast radius over the shipped corpus: zero.
- **`ScenarioVM` no longer owns `EventWalkNav`.** The 48-line adapter that bridged
  the pathfinder to the `Lattice` is deleted; the planner takes tiles, not queries.
- **The `{28}` cost switch is honoured.** The opcode's last operand byte flattens
  the whole movement-cost row; **20 of the 561** shipped instructions set it, and on
  those the planner stops routing around water. The catalog names that byte
  `Unknown` — the same name as the byte before `Speed` — so it cannot be read by
  name and `_op_walk_to` reads it by index.
- **`TerrainCell` is unchanged.** ADR-0192 dec. 6's six fields stay six. The four
  missing terrain fields are read from the map file rather than widened into the
  shared kernel's schema, which keeps the fidelity in the one subsystem that needs
  it and out of every GPU buffer that does not.
- **The addon still installs into a stranger project.** `EventPathfinderTest`'s 107
  assertions run green under `tests/stranger/exmateria_battlefield/run.sh`, because
  every fixture bakes its own tiles and the reader takes its content root from the
  host rather than naming `res://assets/`.
- **`#819` closes on top of this**, not beside it: its item 1–2 terrain reader is
  decision 5, and its "route bytes reaching the stepper carry no leap" is decision 1.

## Alternatives considered

**Add `RomEventPlanner` beside `EventPathfinder` and switch callers.** Rejected.
It is the same file's job, and two planners in one tree is how a shared misreading
survives — the exact failure this investigation was built to avoid. It would also
strand the `[[Walk To Opcode]]` vault anchor and ~15 ADR citations on a husk.

**Widen `TerrainCell` with `depth`, `slope_height`, `slope_type` and `thickness`.**
Rejected. It re-opens ADR-0192 dec. 6's field count for one subsystem's benefit, and
it puts four ROM-shaped bytes into the kernel type every GPU buffer and every
placement query already holds. The map file has them; a reader is smaller than a
schema change and does not propagate.

**Keep a nearest-reachable-tile fallback for refused targets.** Rejected. It is not
the ROM's behaviour, it was measured to affect zero shipped routes, and it is the
kind of "helpfulness" that makes a scripted cutscene put a unit somewhere its author
never named. A refusal is loud; a consolation destination is silent.

**Score the port against `rom_event_flood.py`.** Rejected, for ADR-0225 dec. 2's
reason: that scores a transcription against its sibling and a shared misreading
passes. The cross-check tier exists and is *labelled* as the weaker claim, which is
the point of having two tiers rather than one number.

**Keep the ROM's flat `0x100` stride.** Rejected: it aliases silently on any map
over 256 tiles, and the game's own synthetic test lattices are 20 × 20. A planner
that returns a wrong route on a map it cannot represent is worse than one that
represents it.

**Port the render and routing halves together.** Not available — the render half
landed first (ADR-0225) and this one needed it, because the route bytes have nowhere
to go without a stepper that reads them.
