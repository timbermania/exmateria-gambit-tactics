# Occupancy is `Battle`'s in five spellings, and `Battlefield`'s sixth is inert

ADR-0159 dec. 6 asked how to invert `Tile.reserved_by` into an opaque claim, and
its pass-4 amendment sent it back for a design spanning *three holders across two
systems*. Measured at HEAD there are **six** spellings of the occupancy concept.
**Five of them are `Battle`'s.** The sixth — the only one in `Battlefield`, and
the only one any of passes 1, 3 or 4 looked at — is written once at deployment,
never released, never read for a decision, and its one guard runs *after* the
position it is guarding has already been assigned.

⚠️ **AMENDMENT 2026-09-07 — THE COUNT IN THIS ADR'S TITLE IS NOW 2, NOT 5.**
[ADR-0258](0258-the-march-is-retired-and-two-enums-lose-a-member-without-renumbering.md)
dec. 9 retired the deployment march and deleted `PlacementTileSet`, which was **two of
the holders below**: holder 2 (`get_tile_ownership()`) and holder 3 (`claimed_tiles`).
With the Consequences table's own collapse already counted, `Battle`'s spellings go
**4 → 2** — the deployment claim (now `DeploymentAssignment`, CPU-side, tile → unit)
and instantaneous standing (`is_tile_occupied`, derived per tick in the GPU mover).
That is exactly the two-claims-two-arbiters shape dec. 5 argued for, reached by
DELETION rather than by the collapse this ADR planned. Read the tables below as the
measurement they were at their own HEAD, not as the tree's shape today.

So there is no capability to design here. There is a corpse to delete, a node
handle to convert to a value, and a contested-resource row in ADR-0119 that
merges two different claims into one.

Status: accepted (2026-08-25). Resolves
[#554](https://github.com/timbermania/fft-monorepo/issues/554) on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560) (extraction #3,
loop pass 5). Amends **ADR-0159 dec. 6**, **ADR-0164 dec. 4** and **ADR-0119
dec. 1**, each in place.

## Context

Every figure below was measured in `~/Repos/fft-monorepo-ext3-pass4` at
`7e35dc423`, not quoted from a prior pass. Buckets are
`classify_blueprint.classify()`'s, read per file.

`#554`'s body — and the ADR-0159 dec. 6 amendment it was split from — states the
contested resource has **three** holders. That count came from following the
`Tile` type name. Four of the six spellings carry no type name at all, so the
census that produced the three could not have produced the six:
`touch_matrix.py` states it is a **FLOOR** for exactly this reason (ADR-0131
dec. 6), and this is the second consecutive ticket on this map where the floor
was the whole finding.

### The reading — `7e35dc423`

| # | spelling | direction | bucket | shape | reach |
|---|---|---|---|---|---|
| 1 | `Tile.reserved_by` + `try_reserve` / `release` / `is_blocked` / `became_available` | tile → unit | **`Battlefield`** | stored, node identity | 4 typed lines; 9 call sites / 6 files |
| 2 | `PlacementTileSet.get_tile_ownership()` | tile → category | `Battle` | derived from three arrays | 1 reader; 1 of 3 enum values consumed |
| 3 | `PlacementTileSet.claimed_tiles: Dictionary` | tile → unit | `Battle` | stored, node identity, **untyped** | 7 lines / 5 files |
| 4 | `MovementComponent.current_logical_tile` + `Unit.get_current_tile()` | unit → tile | `Battle` | stored node reference | **56 lines / 24 files, 3 typed** |
| 5 | `get_tile_occupant()` / `is_tile_occupied()` | derived | `Battle` | scans `U_POS_X` / `U_POS_Z` per call | 15 call sites / 3 shaders |
| 6 | `GPUArena._unit_at_grid()` | derived | assembler | scans `get_current_tile()` | 1 definition, 1 use |

`touch_matrix.py` reads `Battlefield → Battle` as exactly **4** lines, which is
holder 1 and nothing else. Holders 2, 3, 5 and 6 are invisible to it because they
are `Battle`-internal; holder 4 is invisible on 53 of its 56 lines because the
receiver is untyped.

### Holder 1 is inert, and every leg of that is statically closed

- **Never released or updated in gameplay.** The only writers are `try_reserve`
  (reached only from `Unit.place_on_tile`) and `release` (reached from
  `UnitControlPanel` ×3, `EffectViewerScene` ×1, `ProgressionTester` ×1 and two
  tests — every one of them a release-then-re-place pair that exists only to
  unblock the next `try_reserve`). `GPUVisualBridge.gd:110` moves a unit by
  writing `current_logical_tile` and never touches `reserved_by`. After the first
  combat step the field points at the deploy tile for the rest of the battle.
- **Its authority is consulted by nothing.** `is_blocked` has **zero** external
  callers, `became_available` has **zero** listeners, and `reserved_by` is read
  outside `Tile.gd` on exactly one line — `Unit.gd:1649`, inside a `push_error`
  format string. There is no dynamic dispatch: `call("release"`, `"try_reserve"`
  and `"reserved_by"` appear nowhere in `src/`, `tests/` or `addons/`.
- **Its one guard does not guard.** `Unit.place_on_tile` assigns
  `global_position` at line 1637 and calls `try_reserve` at 1645, so the unit is
  already standing there when the check runs; and every production caller ignores
  the `false` — `StrategyPhaseManager` ×2, `NavigatorMain`, and `GPUArena`, which
  gates on `claim_tile` (holder 3) instead. The bad state stays fully
  representable, which is the exact failure ADR-0119 was written against.
- **It has already been routed around by name.** `ScenarioVM.cinematic_place`
  bypasses `place_on_tile` because *"Cinematics routinely overlap units on the
  same tile"* and the reservation *"would reject the second warp"*.
- **Nothing depends on it as a de-dup either.** `StrategyPhaseManager._fill_team`
  places by index over distinct spawn tiles; the march path dedups through
  `claimed_tiles`; `GPUArena` gates on `claim_tile` before calling. Holder 1 is a
  second, weaker check standing behind a working one.

`Tile.gd:68` says *"reserved_by is the ONLY occupation tracking variable"* and
line 69 says *"It represents both reservation AND current occupation"*. It is
neither, and it is the sentence pass 1 and pass 3 both read.

## Decision

**1. Occupancy is `Battle`'s concept, and `Battlefield` holds none of it after
pass 6.** Five of six spellings are already `Battle`'s or the assembler's; the
sixth is inert. `#554`'s Done condition — *"a design that carries all three
holders"* — is therefore unanswerable as written, and is restated: **decide what
`Battlefield` sheds, and record where the concept actually lives.** The
capability design for the `Battle`-side spellings is not this map's work, for the
same reason ADR-0159 dec. 3 was corrected on `platform`: extraction #3's map does
not get to hold another system's design decision.

**2. Holder 1 is deleted, not inverted — and retyping it is rejected by name.**
Pass 6 removes `reserved_by`, `try_reserve`, `release`, `is_blocked` and
`became_available` from `src/map/Tile.gd`, and the nine call sites with them.
Goal #5's bar is **0 cross-system reach lines leaving the addon**
(`score_goals.outbound_reaches`), so those four lines have to go regardless; what
this decision settles is that nothing replaces them.

- **Relocating** the reservation onto a `Battle`-owned structure is rejected: it
  would be a **seventh** spelling beside holders 3 and 5, which already arbitrate
  deployment and combat respectively. There is no state to move — the field is
  stale from the first step and read by nothing.
- 🔴 **Retyping** it — `reserved_by: Node`, or an int unit id — is rejected
  **by name**, because it is the cheapest-looking move on the board and it is a
  fraud. It turns dec. 6's `−4` green on `touch_matrix.py` while leaving the
  concept exactly where it was. This is ADR-0164 dec. 4's hole wearing its
  outbound face: *"A register keyed on an inbound total cannot tell the fix from
  the hiding."*

The deletion cascades once: `get_grid_coords()`'s only caller is line 249, inside
`release`'s mismatch warning, so ADR-0159 dec. 10's *"dead surface with a
divergent unit"* goes out with it and the seam stops publishing two coordinate
accessors that derive differently.

⚠️ **What is lost, stated because it is not nothing.** A double-place stops
logging a `push_error`. That diagnostic fires on legitimate overlap (which is why
`ScenarioVM` bypasses the call), never prevented the state it named, and no
caller reads its return — but the log line is real and it goes.

Pass 6 replaces `Tile.gd:68`–`69`'s two sentences with a pointer naming holders
4 and 5 as where occupancy lives. Three passes were misled by those two lines;
deleting the field without deleting the claim would leave the next audit to
re-derive it wrong a fourth time.

**3. Holder 4 becomes `current_cell: Vector2i`, with a sentinel for "unplaced".**
`current_logical_tile` and `get_current_tile()` together are **56 lines across 24
files**, and exactly **three** carry the name `Tile`:

```
src/units/MovementComponent.gd:9          var current_logical_tile: Tile = null
src/strategy/StrategyPhaseManager.gd:336  var ut: Tile = unit.movement_component.current_logical_tile
src/scenarios/NavigatorMain.gd:1006       var leader_tile: Tile = leader.get_current_tile()
```

The other **53 are duck-typed** — 4.4× the twelve `MapComposer.get_tile` sites
dec. 3 of ADR-0164 found, one holder over, and found the same way.

🔴 **Holder 4 falls between ADR-0164's two acceptance criteria.** Criterion 1
(published-symbol set equality, `Tile` absent) catches the three typed lines.
Criterion 2 (the duck-typed-door register) counts call sites whose *method* is on
the published port — holder 4 is a **stored field**, not a call. Retyping those
three lines to `Node3D` would satisfy **both** criteria while 56 sites still hold
live `Tile` nodes. Decision 4 exists because of this.

🔴 **And it is not deferrable.** `GPUVisualBridge.gd:110` assigns
`current_logical_tile = gpu_tile`, where `gpu_tile` comes from
`terrain_index.get_tile(...)` — the call ADR-0164 dec. 2 replaces with
`terrain_at(x, z) -> TerrainCell`. The moment the port lands, holder 4's value
source changes type. Pass 6 converts it either way; this decision settles what
to.

`Vector2i` over `TerrainCell`, for three reasons in order of weight:

- **Equality.** `GPUArena.gd:410` is `if ut == tile`, a node-reference
  comparison that decides deployment unit-selection. A `RefCounted`
  `TerrainCell` still compares by *reference*, so two `terrain_at` calls for one
  cell would be `!=` — converting a reference comparison into a subtler one.
  `Vector2i` compares by value and the site is correct permanently.
- **One type for one concept.** ADR-0164 dec. 2 already re-keys holder 3's
  `claimed_tiles` and the three `*_tiles` arrays onto `Vector2i(grid_x, grid_z)`.
  Landing holder 4 on the same key is what finally makes the occupancy concept
  *one* concept, which is what #554 was opened to get.
- **Staleness.** ADR-0164 dec. 2 accepts that a `TerrainCell` is a **snapshot**
  and that a held one lies the day terrain mutates. A per-tick unit field is the
  worst place in the tree to hold one. Consumers needing `height` or a world
  position call the port with the cell, so the snapshot never outlives the query.

Consumers read `grid_x` / `grid_z` (`GPUCombatPacker.gd:329`/`330`), `height`
(`:357`) and `global_position` (`CombatLoop.gd:358`) off holder 4; all four are
answerable from a cell plus the port. The absence state — six sites test
`== null` for *unplaced* (`ValidationUtils.gd:33`, `StrategyPhaseManager.gd:337`,
`MovementComponent.gd:20`/`29`, `CursorConfirmEndToEndTest` ×3) — is carried by a
sentinel constant rather than a second `has_cell` field, because ADR-0119 dec. 3
and ADR-0083's collapse both say not to leave two fields encoding one axis.

**4. A third acceptance criterion, and it is producer-side: the Tile-door
register, 8 → 0.** Amending ADR-0164 dec. 4, whose criteria 1 and 2 cannot see a
stored node. **No `Battlefield` member reachable from outside the addon may have
`Tile` in a return or signal-payload position.** Read across all 40 `Battlefield`
files, today there are eight:

| member | shape | external reach |
|---|---|---|
| `TerrainIndex.get_tile() -> Tile` | port | 9 sites, `Battle` |
| `TerrainIndex.get_all_tiles() -> Array[Tile]` | port | via `MapComposer` |
| `MapComposer.get_tile() -> Tile` | second impl | **12 duck-typed** ([#567](https://github.com/timbermania/fft-monorepo/issues/567)) |
| `MapComposer.get_all_tiles() -> Array[Tile]` | second impl | `ScenarioUnitAlignmentDebugPanel` (`Debug`), through `has_method` |
| `TileCursor.active_tile() -> Tile` | publish | `GPUArena`, **`FormationMapHost` (`UI`)** |
| `TileCursor.cursor_moved` / `cursor_confirmed` / `cursor_inspected(_, tile: Tile)` | publish ×3 | `FormationMapHost` ×3 handlers |

> ✅ **CLOSED 2026-08-27 — the register reads 0 of a target 0, and the baseline it burned
> down was NINE.** Four rows went at loop pass 6
> ([ADR-0170](0170-the-third-door-is-a-forwarder-and-the-duck-typing-is-a-test-seam.md)
> dec. 1 deleted the `MapComposer` forwarders;
> [ADR-0192](0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)
> dec. 4 took the `class_name` off the tile store, so the two `TerrainIndex` rows stopped
> being named outside the addon and now report under INTERNAL-BUT-PUBLIC). The remaining
> five — the whole `TileCursor` set — went at
> [ADR-0195](0195-the-cursor-publishes-a-coordinate-and-criterion-3-closes.md).
> `DOOR_BURN_DOWN` is empty and both arms stay armed: an unlisted door still reds arm 1.

`DynamicTerrainBuilder.add_terrain` and `remove_terrain_in_bounds` also return
`Array[Tile]` and have **zero** external callers, so they stay internal and are
not on the register.

> ⚠️ **Amended 2026-08-27 at [#642](https://github.com/timbermania/fft-monorepo/issues/642),
> by the register this decision asked for: the baseline is NINE, and the ninth was created
> by pass 6 itself.** `tools/check_lattice_doors.py` — the criterion built as a guard —
> reads a **fourth** `TileCursor` signal, `cursor_stepped(grid_pos: Vector2i, tile: Tile)`,
> named outside the addon by `src/scenes/BattlefieldWiring.gd:77`. The table above is not
> wrong about what it read: [#589](https://github.com/timbermania/fft-monorepo/issues/589)
> inverted the cursor cue out of the addon and connected that edge *after* this reading was
> taken, so the row is a measurement that a later commit invalidated. Nothing else moved —
> the other eight are exactly as listed, and both `DynamicTerrainBuilder` exclusions still
> have zero external callers, which the guard reports as its arm 2 rather than assuming.
>
> **Two things the rule as written above cannot see**, both reported by the guard rather
> than enforced:
>
> - **A parameter is not a return or a signal payload**, and it is the same held-node
>   shape from the other direction — a host that calls
>   `TerrainIndex.add_tile(tile: Tile)` must HOLD a `Tile` to make the call. Three public
>   members take one; `add_tile` is named by four files in `tests/`.
> - **A wrapped `func` header.** The guard's first draft scanned per line and asserted the
>   addon had none; it has **fourteen**. That draft's own scan-limit arm is what reported
>   them, and the scan now joins a header until its parentheses balance.

**Producer-side, deliberately.** It is the only one of the three criteria that is
*decidable*: a closed set of 40 files, against a consumer-side pattern that by
construction carries no type name anywhere in 644 host files. It also makes
holders 3, 4 and 6 **impossible** rather than merely counted — if no published
door hands out a `Tile`, no host can hold one, so the 53 invisible sites close
without anyone having to find them. And it creates no new work: it scores work
ADR-0164 already says is owed — #567's `MapComposer` collapse, and dec. 3's ⚠️
that the `TileCursor` payload *"should be `Vector2i` alone"*, which was recorded
and left unguarded.

**5. The fourth contested resource is two claims, not one.** Amending ADR-0119
dec. 1, whose row reads *"the cell — the right to stand somewhere | one combatant
| move, deploy, removal"*. Measured, that is two claims with two arbiters that
never speak:

| claim | arbiter | lifetime |
|---|---|---|
| **deployment assignment** — which unit is assigned which destination | `PlacementTileSet.claim_tile` (holder 3) | placement phase; `claimed_tiles` is never cleared and never read after `Phase.COMPLETE` |
| **instantaneous standing** — whether a step is legal right now | `is_tile_occupied` in the GPU mover (holder 5) | every simulated tick |

They are not sequential: `_run_march_sequence` drives `_combat_loop.set_deploy_move`,
so both are live during the march, arbitrating different questions.

**Neither needs the capability treatment, and for opposite reasons.** The
deployment claim already *is* claim-and-refuse at one choke point — `claim_tile`
returns `false` if the cell is taken, and `GPUArena` and `PlacementPhaseController`
both gate on it — so re-keying it to `Vector2i` (already forced by ADR-0164
dec. 2) is the entire remaining fix. Instantaneous standing is **derived, not
stored**: occupancy is a function of positions held by the one authority that owns
them, which is a stronger guarantee than a handle rather than a weaker one.

⚠️ **This is the one place ADR-0119 is bent rather than applied.** Its rejected
alternatives include *"A membership test"*, on the grounds that ownership then
*"lives in a test one system must reach into another to perform, re-answered
every frame instead of settled at the handoff."* Holder 5 is a membership test.
The objection does not land on it: the scan reaches into **nothing** — it reads
the unit buffer the same shader invocation already owns — and there is no handoff
to settle it at, because position *is* the state. A CPU-side claim would need a
per-tick GPU readback to stay true, which is a second authority for state the
simulator already holds.

What was actually broken was holder 1: a third spelling, in the wrong system,
stale from the first step, enforcing nothing. Decision 2 deletes it.

## Prediction

Scored at pass 9 alongside ADR-0164's three criteria.

| term | now (`7e35dc423`) | predicted | from |
|---|---:|---:|---|
| `Battlefield → Battle`, `touch_matrix.py` | 4 | **0** | dec. 2 |
| outbound cross-system | 11 | **7** | dec. 2 — ADR-0159 dec. 6's `−4`, now earned |
| outbound **debt** | 10 | **6** | `Effects` 4, `Audio` 1, `PlayerCamera.tscn` → `CombatUI.tscn` 1 |
| Tile-door register (dec. 4) | **8** | **0** | producer-side, read over 40 files |
| holder 4 sites holding a `Tile` node | **56** (3 visible) | **0** | dec. 3 |
| spellings of occupancy in `Battlefield` | 1 | **0** | dec. 2 |
| spellings of occupancy in `Battle` | 5 | **4** | holders 2/3 collapse onto one `Vector2i` key |

**The falsifiable one.** Dec. 3 predicts 56 sites convert cleanly because all four
members consumers read are answerable from a cell plus the port. If any site turns
out to need `Tile` **identity** rather than its coordinates — beyond
`GPUArena.gd:410`, which dec. 3 fixes — the conversion is wider than stated and
dec. 3 is what gives. Pass 6 should look for that rather than confirm the table.

## Consequences

- **ADR-0159 dec. 6 is resolved by deletion**, not by the inversion it
  prescribed, and its `−4 outbound / debt 10 → 6` row is earned for the first
  time. Its pass-4 amendment's *"there is no design yet for a capability that
  spans three holders across two systems"* is answered: there are six, five are
  another system's, and no capability is owed.
- **`BLUEPRINT.md`'s prescription is untouched and unused here.** *"Holding the
  handle **is** the authority"* remains right; it simply has nothing to apply to
  once dec. 5 splits the row, because one claim already refuses at a choke point
  and the other is derived.
- **Pass 6 gains a fourth register** (dec. 4's Tile-door count) beside ADR-0164's
  duck-typed-door register. Both must exist at pass 6, not pass 9, or pass 6 has
  no way to know it finished.
- **Pass 6's test surface is wider than the manifest suggests.** Eleven test files
  carry 24 of holder 4's 56 lines. [#565](https://github.com/timbermania/fft-monorepo/issues/565)'s
  manifest counts source files; the test rewrite is pass 6's and was already
  scoped there.
- **A `Battle` question is filed rather than answered:** whether the deployment
  claim wants ADR-0119's handle treatment, once `Battle` is the system under
  extraction and its own pass 5 can weigh it.
- **The method fact, which is the third on this map and the second in a row.**
  Pass 4's was *ask what the instrument cannot represent*. ADR-0164's was *look
  for a second implementation of the same query*. This one is: **a concept's
  spellings are found by reading the writers of its state, not by following its
  type name.** Following the name found three of six, and the three it found
  included the only dead one.

## Alternatives considered

- **Design the capability across all six spellings (#554 as written).** Rejected
  by dec. 1 and dec. 5: five spellings are `Battle`'s, the deployment claim is
  already a claim, and combat standing is derived from state the GPU owns. The
  design would have been written for a defect that dec. 2 deletes.
- **Invert holder 1 into an opaque claim, as ADR-0159 dec. 6 prescribed.**
  Rejected: there is no state to invert. The field is written once, never
  released, read by no decision, and its signal has no listeners.
- **Relocate holder 1 into `Battle`.** Rejected as a seventh spelling — see
  dec. 2.
- **Retype holder 1 to shed the reach.** Rejected by name in dec. 2. It is the
  only alternative here that would have passed every instrument on this map.
- **`TerrainCell` for holder 4.** Rejected by dec. 3 on equality, key
  consistency and staleness, in that order.
- **A consumer-side held-node register for criterion 3.** Rejected by dec. 4: its
  baseline is ≥56 and not exactly measurable, because the pattern carries no type
  name. The producer-side form has a baseline of 8 over a closed file set.
- **No third criterion.** Rejected: criteria 1 and 2 are both satisfied by
  retyping three lines, which is dec. 2's rejected move surfacing where ADR-0164
  does not guard.
