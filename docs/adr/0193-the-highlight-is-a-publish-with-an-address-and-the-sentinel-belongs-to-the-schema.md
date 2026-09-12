# The highlight is a publish with an address, and "not a cell" belongs to the schema

ADR-0164 dec. 1 cut `Tile`'s member surface into three capabilities and classified each:
the terrain query is a **port** (`Lattice`), the highlight is a **publish** — *"a command
with no reply"*, `src/strategy/` its only external client, 14 lines — and occupancy is
neither. It classified the highlight and gave it no address. That was survivable while
`src/strategy/` held `Tile` nodes it could call `set_highlight_type` on directly.

ADR-0192 dec. 4 ended that. With `class_name` off the tile store, the only way into the
addon from outside is the port, and the port answers with **values** — so
`PlacementTileSet`'s three arrays became `Array[Vector2i]` (which ADR-0164 dec. 2 and
ADR-0166 dec. 3 both already required for their own reasons), and the code that paints
them was left holding a coordinate and no way to spend it. The publish had to acquire an
address in the same pass that took the nodes away, or the placement highlight would have
been deleted rather than ported.

Status: accepted (2026-08-27), **built**. Loop **pass 6** of extraction #3, on map
[#560](https://github.com/timbermania/fft-monorepo/issues/560). Realises
[ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
dec. 1's second capability and amends
[ADR-0166](0166-occupancy-is-battles-in-five-spellings-and-battlefields-sixth-is-inert.md)
dec. 3 in place on where its sentinel lives.

## Context

Measured on `fix/lattice-port-register` at pass 6, after the port landed.

- **`src/strategy/` is the highlight's only external client, and it is 14 lines over two
  files** — `PlacementTileHighlighter` (12) and `StrategyPhaseManager` (2). Reproduces
  ADR-0164 dec. 1's count exactly.
- **`CursorController` is the third caller and it is INSIDE the addon**, so it needs no
  publish and gets none: it holds the `Tile` the cursor already resolved and calls
  `set_highlight_type` on it directly, as an addon file may.
- 🔴 **`Tile.HighlightType` is named 47 times, and 43 of those are inside the addon** —
  `TileOverlayConfig` 21, `Tile` itself 11, `CursorController` 10, `TileOverlayCompositor`
  5. Outside it: `PlacementTileHighlighter` 6, `StrategyPhaseManager` 1,
  `CursorConfirmEndToEndTest` 1, `TileOverlayCompositorTest` 6.
- **Two sentinels were about to exist for one value.** Holder 4's "unplaced"
  (ADR-0166 dec. 3), holder 3's "no destination" (`_choose_contested_for` returning
  nothing), and `PlacementInputHandler`'s "the pointer left the grid" are the same fact:
  *this is not a cell*. Before this decision each was going to spell it locally.

## Decision

**1. The highlight publish is `class_name TileHighlights`, in the addon, keyed by
`Vector2i`.** *(Realises ADR-0164 dec. 1.)*

```gdscript
func paint(cell: Vector2i, kind: Tile.HighlightType) -> void
func clear(cell: Vector2i) -> void
func kind_at(cell: Vector2i) -> Tile.HighlightType
```

`MapComposer` exposes it beside the port (`map.highlights`), built and rebound on the
same schedule. `Battle` names a coordinate and a colour; the addon does the lookup.

Three alternatives were live and all are worse:

- **Add a fifth member to `Lattice`.** Rejected: ADR-0170 dec. 2 fixes the port at four
  members and ADR-0192's prediction table pins it there, and ADR-0164 dec. 1's whole
  point is that a fire-and-forget command is *not* the synchronous query. Bundling them
  makes the port's own definition unfalsifiable.
- **Move `PlacementTileHighlighter` into the addon.** That is a system move
  (`Battle` → `Battlefield`) of code that decides *which* set is *which* colour — a
  placement policy, exactly what ADR-0166 dec. 1 says the map does not hold.
- **Let `src/strategy/` keep the nodes.** There is no route: the store is unnameable and
  the port returns values. The only remaining door that hands out a `Tile` is
  `TileCursor.active_tile()`, which is on `DOOR_BURN_DOWN` and is being removed.

⚠️ **This grows `Battlefield`'s published set by one `class_name`, and that is a cost
against ADR-0164 dec. 4 criterion 1, paid deliberately.** It buys three: the placement
sets stop holding live nodes, `PlacementTileSet.claimed_*` lands on the same `Vector2i`
key as holder 4, and the addon regains the freedom to change what a highlight *is*
without a host recompiling against `Tile`.

**2. `HighlightType` stays on `Tile`. The publish names it; it does not re-declare it.**

> 🔴 **SUPERSEDED 2026-08-28 by [ADR-0196](0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)
> dec. 6 at loop pass 8. The enum moves — to `CellMarking.Kind` in the SCHEMA, not to
> `TileHighlights`.** This decision was right about the outcome and wrong about the reason.
> The reason recorded here is a **count**, and a count is the cheap half: a scripted rename
> verified by a compile. It was not even stable — 43 here, 43 again in ADR-0195 dec. 6
> *"with the number re-derived"*, **47** in `TileHighlights.gd`'s own docstring, **39** in
> the tree. The expensive half was never named: `TileHighlights.gd` already depends on
> `Tile` (`_tile(cell) -> Tile`, and this decision's own `paint` signature), so moving the
> enum HERE creates `Tile.gd → TileHighlights.gd → Tile.gd` — the shape ADR-0170 dec. 4
> diagnosed and ADR-0166 dec. 1 closed. The schema has no such edge.
> ✅ This decision's last sentence — *"whoever closes criterion 1 owns deciding where the
> enum lives"* — named an owner and **no pass**, which is how two further passes cited it
> and moved on. ADR-0196 dec. 5 now forbids exactly that: a re-spelling count is never
> grounds to decline, and a deferral must name the pass that owns the resolution.

Moving the enum to `TileHighlights` would re-spell **43 addon-internal references**,
21 of them in `TileOverlayConfig`, to close a criterion-1 namer this pass does not score
and no decision has ruled on. Re-declaring it would be worse: two enums for one concept
is the shape ADR-0119 dec. 3 and ADR-0083's collapse both forbid, and there is no
mechanism that would notice them drifting.

So the publish's parameter is `Tile.HighlightType` — named, not a bare `int`, so the two
sides cannot disagree about what `2` means. 🔴 **The consequence is stated rather than
hidden: `Tile` remains in the published set, for its enum only.** That is unchanged from
before this pass, it is criterion 1's business and not criterion 2's or 3's, and whoever
closes criterion 1 owns deciding where the enum lives.

**3. "Not a cell" is ONE sentinel, `TerrainCell.NONE`, and it lives in the schema.**
*(Amends ADR-0166 dec. 3, which required a sentinel and did not say whose.)*

Dec. 3 rules that holder 4's absence state is *"carried by a sentinel constant rather
than a second `has_cell` field, because ADR-0119 dec. 3 and ADR-0083's collapse both say
not to leave two fields encoding one axis."* The argument is about not spelling one axis
twice — and a constant per holder spells it three times, on the same axis, in three
systems. `MovementComponent.UNPLACED`, a placement "no destination" and an input handler's
"off the grid" are the same value or they are a bug.

The kernel is where both sides can name it, and it costs the schema nothing: it is a
`const` on an already-admitted member, not a new member, so ADR-0139 dec. 3's admission
gate is not re-opened and ADR-0164 dec. 2's two mechanical vetoes are untouched.

**`Vector2i.MIN`, not `(-1, -1)`.** `DynamicTerrainBuilder` offsets a doodad's tiles by
its placement origin, so a small negative grid coordinate is a **legal cell** — the first
doodad placed left of the base map would make a `(-1, -1)` sentinel ambiguous, silently.

**4. The port and the publish are STABLE OBJECTS; the store behind them is what a map
reload replaces.**

`MapComposer._load_and_place_map` builds a fresh store on every `change_map` /
`rebuild_map`. If it also built a fresh `Lattice`, every consumer that took its handle at
boot — `CombatHost`, `ScenarioWeather`, `CinematicFacingResolver`, the gambit runner —
would be left holding a port onto the **previous** map, answering confidently for terrain
that no longer exists.

That is the held-node bug the port was built to remove, one level up, and **worse**,
because a stale `Lattice` still answers rather than returning null. So the composer
creates one `Lattice` and one `TileHighlights` for its lifetime and rebinds each
(`_bind`) when the store is rebuilt. The store is the thing that is replaced; the port is
the thing that is held.

## Consequences

- **`Battlefield` publishes one more `class_name`.** Criterion 1's set grows by
  `TileHighlights`; criterion 3's Tile-door register is unaffected (it returns an enum
  and takes a coordinate).
- **`PlacementTileSet` is `Vector2i` throughout** — `player_cells` / `enemy_cells` /
  `contested_cells` / `claimed_cells` — which is ADR-0164 dec. 2's "it also forces the
  occupancy keys off object identity" and ADR-0166's **holder 3**, landing.
- **Eight `src/strategy/` files and `GPUArena` speak coordinates**, and
  `PlacementInputHandler`'s three signals carry `Vector2i` rather than `Tile`.
- **`TerrainCell` gains a `const`, not a field.** Its field count stays at ADR-0192
  dec. 6's six.
- **`Tile` stays published for its enum**, and closing that is criterion 1's work.
- **A future map-reload change must keep the rebind.** Replacing `map.lattice` with a new
  object instead of rebinding it re-introduces the stale-handle bug at every consumer
  that stores one, and nothing in this tree would report it.

## Alternatives considered

- **A fifth `Lattice` member.** Rejected on dec. 1: it merges a command into the query
  ADR-0164 dec. 1 separated, and breaks the four-member count ADR-0170 dec. 2 fixed.
- **Move the highlighter into the addon.** Rejected on dec. 1: it relocates a `Battle`
  placement policy onto the map.
- **Pass the kind as a bare `int`.** Rejected on dec. 2: `TileOverlayCompositor.is_routed`
  already does it and it is the reason nothing notices when the numbers drift.
- **Move `HighlightType` onto `TileHighlights`.** Declined rather than rejected — 43
  addon-internal re-spellings for a criterion this pass does not score. It is the right
  move for whoever closes criterion 1.
- **A per-holder sentinel constant.** Rejected on dec. 3: it is dec. 3's own
  "two fields for one axis" argument, spelled three times instead of twice.
- **Rebuild `Lattice` per map load.** Rejected on dec. 4: every consumer that stores the
  handle would answer for the previous map, and a stale port still answers.
