# A cell's marking is slotted, and the highlight publish is its only writer

You put the cursor on a unit during the march, press Enter, and the tile lights up.
Then you move the cursor one square to pick where it goes, and the unit you picked
goes dark. The pick is gone from the screen while it is still very much alive in
`StrategyPhaseManager`. That is the *"cursor on a unit, press Enter, nothing
happens"* report arriving one beat later, and it is not a rendering bug.

`Tile` carries **one** highlight value, `current_highlight_type`. Three writers put
things in it and nothing arbitrates:

| writer | what it wants the slot to say |
|---|---|
| `CursorController._set_active_tile` | `CURSOR_ACTIVE` where the cursor is |
| `CursorController._on_camera_mode_changed` | the same, saved and restored across a takeover |
| `TileHighlights.paint`, driven by `StrategyPhaseManager` / `PlacementTileHighlighter` | the placement colouring, and the march pick |

Two of the three are the cursor, and both of them save the value they overwrote
into one member, `_active_prev_type`, captured at the moment the cursor **arrived**.
When the march pick then writes the same tile, that saved value is already a lie —
so the cursor's restore-on-leave puts a stale `PLACEMENT_PLAYER` back over a live
selection and the pick vanishes. The failing arm added to
`tests/CursorConfirmEndToEndTest.gd` reads exactly that: the latched tile wears
`1` — `PLACEMENT_PLAYER` — once the cursor has left.

There is a third symptom of the same missing arbiter, already in the tree wearing a
comment that admits it: `CursorController._process` exists **only** to re-assert
`CURSOR_ACTIVE` every frame, because *"other systems (StrategyPhaseManager /
PlacementPhaseController) repaint placement highlights through the same per-tile
slot"*. A per-frame repair loop is what a single slot with no owner costs, and it is
also what hides the defect: the cursor's own square heals, so only the square the
cursor **left** shows the damage.

ADR-0164 dec. 1 classed the highlight as *"a command with no reply"* and measured
its external clients as `src/strategy/` only, 14 lines. That measurement was
correct and it is why this was invisible: **two of the three writers are inside the
addon**, so the census that established the publish never saw them. The publish was
given one caller's traffic to model and three callers' arbitration to do.

Status: accepted (2026-09-02). Extends **ADR-0164 dec. 1** in place — the highlight
stays a publish, and this says what the publish owes. Extends **ADR-0196 dec. 6**
with a sixth `CellMarking.Kind`. Built on `fix/tile-highlights-layered-markings`.

## Context

### One slot, and the writers each believe they own it

`Tile.current_highlight_type` is an `int` with a setter that also drives the overlay
mesh and, for a routed type, registers with `TileOverlayCompositor`. Outside
`Tile.gd` the tree holds exactly **eleven** executing lines that touch the three
highlight members: **eight** in `CursorController` and **three** in
`TileHighlights`. Everything else that mentions them is prose. So the population to
arbitrate is small, known, and entirely inside the addon — which is the shape that
makes a sole-writer rule enforceable rather than aspirational.

The two families in that population want different things and neither is wrong:

- The **placement colouring** is a statement about the *terrain*: these squares are
  where you may deploy, that one is contested, that one is taken. It is painted once
  per phase change and covers many cells.
- The **cursor** is a statement about *where the player is looking*. It moves every
  input, covers exactly one cell, and is transient.

They are not competing answers to one question. They are two answers to two
questions that happen to be rendered in one place. Collapsing them into one slot
means every arrival has to remember what it displaced and every departure has to
guess whether its memory is still true — which is precisely the mechanism that
failed.

### `_active_prev_type` cannot be made correct

It is a single member holding a value captured at one instant, written from three
sites, and read at two. Every fix that keeps it is a fix to the *timing* of the
capture. But there is no capture time that survives an interleaving: the cursor
arrives, something else paints, the cursor leaves. Whatever the cursor saved is by
construction older than the paint it is about to erase. The `_process` self-heal is
the previous attempt to patch this by re-capturing every frame, and it patches the
one square where the damage is invisible.

### The march pick had no marking of its own

Before this, `StrategyPhaseManager._paint_march_selection` painted `CURSOR_ACTIVE`,
reusing the cursor's own marking for "the unit you picked". That reuse is what made
the collision unavoidable: the two writers were not merely sharing a slot, they were
writing the *same value* into it, so no arbiter could have told them apart. A latch
that the player walks away from is a different fact from where the cursor is
standing, and it needs its own name before it can be given its own slot.

### `kind_at` was built for the defect

`TileHighlights`'s own docstring says `kind_at` exists *"so the cursor's
restore-on-leave can put back what it painted over"*. It is the read half of the
save/restore this ADR deletes. It does not follow that the query goes: something
still has to answer *what is this tile showing*, and tests are the caller that
matters most. What changes is its justification and, with it, what it may promise.

## Decision

**1. A cell's marking is SLOTTED, and the slot is derived from the kind.**
`TileHighlights` keeps, per cell, one marking per **slot**:

| slot | kinds | meaning |
|---|---|---|
| `CURSOR` | `CURSOR_ACTIVE` | where the player is looking, right now |
| `SELECTION` | `SELECTED` | what the player has picked and walked away from |
| `TERRAIN_SET` | `PLACEMENT_PLAYER` `PLACEMENT_ENEMY` `PLACEMENT_CONTESTED` `PLACEMENT_UNAVAILABLE` | what this square *is*, for the phase in progress |

The topmost occupied slot is what the tile renders, in that order. `paint(cell,
kind)` keeps **two** arguments: the slot is a property of the kind, not a third
thing a caller has to know. That is the whole point — `src/strategy/` is being
relieved of arbitration, and a slot parameter would hand it straight back in a new
spelling.

The derivation lives in `TileHighlights`, not on `CellMarking`. The schema names
*what a marking is* so both sides can spell it (ADR-0196 dec. 6); which of several
simultaneous markings a tile shows is a rendering policy that only the publish has
the state to decide. Putting the slot on the schema would publish the arbitration to
every caller that merely wanted to name a colour.

**2. The slot table lives in `TileHighlights`, keyed by `Vector3i`.** Not on `Tile`.
Three reasons, and the first is decisive:

- The publish is the only thing that sees all the writers. State on `Tile` is state
  every writer can reach, which is the arrangement being replaced.
- `Vector3i` is already the key both sides hold (ADR-0219 dec. 1, ADR-0166 dec. 3):
  the producer has a `TerrainCell.grid`, so nothing lifts anything.
- A cell with no tile records **nothing**. `paint` on an absent cell stays the silent
  no-op it is today. A table that accumulated entries for cells the map does not have
  would be a second, divergent store of what terrain exists — and the store is
  `TerrainIndex`'s job.

`_bind` **drops** the table. It is called when the map is rebuilt underneath, and a
marking is a statement about a tile that no longer exists.

**3. `TileHighlights` is the ONLY writer.** `Tile.set_highlight_type` and
`Tile.clear_highlight` are renamed `_set_highlight_type` / `_clear_highlight` — the
addon-internal spelling ADR-0164 dec. 2 already uses for `_tile_at` and `_tiles` —
and one static arm enforces that `TileHighlights.gd` is their only caller. Rendering
stays on `Tile`: the underscore moves the *authority*, not the mesh.

The rule is worth a guard rather than a convention because the failure is silent
in exactly the way ADR-0219's was: a second writer compiles, runs, and produces a
picture that is wrong only in the frames after it.

**4. The cursor paints through the publish, and the save/restore is DELETED.**
`CursorController` acquires `highlights` in `seed_from_map`, alongside the `lattice`
it already takes from the same map, and paints its cell with
`CellMarking.Kind.CURSOR_ACTIVE` through `paint`. Deleted outright:
`_active_prev_type`, the whole `_process` override, and the third writer in
`_on_camera_mode_changed`. A takeover **clears the cursor slot**; returning to cursor
mode **repaints it**. Neither has anything to remember, because the slot below was
never disturbed.

This is the deletion test answering yes: the self-heal, the saved type and the
restore branches all vanish, and the complexity does not reappear at the call sites —
it is absorbed by an arbiter that has the state to do it once.

**5. `SELECTED` is a sixth `CellMarking.Kind`.** The march pick gets its own name and
its own slot. It renders as the cursor's shape dimmed — same palette row, same
opaque blend, same clock — so it reads as the trail the cursor left rather than as a
new kind of thing. Opaque (blend 4) keeps it on the in-scene path beside
`CURSOR_ACTIVE`; an additive blend would have routed it through
`TileOverlayCompositor` with the placement tiles, which is a different draw path for
a thing that is visually the cursor.

**6. `kind_at(cell)` stays, and answers about the RENDERED tile.** Not about the
table. A caller asking what a cell is showing is asking about the picture, and a
table read would answer about the top slot even if the tile is absent or the
compositor routed it elsewhere. Its docstring stops citing the restore-on-leave that
no longer exists and states what it is now: the read half of the publish, whose
principal caller is a test.

**7. Two arms, one behavioural and one structural.**
`tests/CursorConfirmEndToEndTest.gd` gains the walk-away arm — pick a unit, move the
cursor off it, assert the tile still wears `SELECTED`. It was seen **red** on the
parent commit, reporting `1`. A new scene-free
`addons/exmateria_battlefield/tests/TileHighlightsTest.{gd,tscn}` drives the publish
directly over a `TerrainFixture` (ADR-0218) and exercises the slot rules: paint two
slots, assert what renders; clear the top, assert the lower one comes back; `_bind`,
assert the table dropped; paint an absent cell, assert nothing was recorded. It lives
in the addon because it needs nothing this game has (ADR-0194).

**`TerrainFixture` gains `highlights` to make that possible** — the publish beside the
port, `_bind` for `_bind`, the same pair `MapComposer` exposes. ADR-0218 dec. 6 fixed
the fixture's interface at three verbs and a property; this makes it three verbs and
two properties, and the reason is that a fixture standing up only half of what a map
publishes leaves the addon's own arbitration untestable without a map, which is the
one thing a test seam must not do.

**8. Three things this deliberately leaves alone**, each named so a later reader does
not read the omission as an oversight:

- `StrategyPhaseManager:333`'s fallback repaint. It looks redundant with the pick's
  own paint and is not: it also refreshes `claimed_cells`, and the claim at `:295`
  has no repaint of its own.
- `TileCursorIntegrationTest`'s masking lambda. It is a real test double of a
  neighbouring concern and rewriting it is not this change's work.
- `:295`'s missing repaint. It is a genuine second finding; it is not this defect,
  and folding it in would make the arm above prove two things at once.

**9. Two things this does not settle.** The slot ORDER is fixed at three and stated
above; a fourth family arriving must argue its position rather than append. And the
compositor routing decision stays keyed on the kind's `blend_mode`, not on the slot —
whether those two should ever be the same axis is a question for whoever adds a
family that wants both paths.

## Prediction

Falsifiable, scored at build:

- **P1.** The walk-away arm in `CursorConfirmEndToEndTest` goes green and stays green
  with `_process` deleted. If it needs the self-heal, the slot table is not the
  arbiter this claims.
- **P2.** `grep -n "_active_prev_type" addons/` goes to **zero**.
- **P3.** `CursorController` loses its `_process` override entirely — not a shortened
  one. A surviving per-frame repair is the tell that a writer was missed.
- **P4.** The sole-writer arm passes with exactly **one** caller of
  `_set_highlight_type` / `_clear_highlight`, and it is `TileHighlights.gd`.
- **P5.** No test outside the two named arms changes to accommodate this. A third
  test needing an edit means the rendered picture moved somewhere this did not
  predict, and that should be said rather than absorbed.

## Consequences

- The publish gains state. It was a stateless forwarder over `TerrainIndex`; it is
  now the thing that remembers what each cell was told. That is the deepening: one
  place holds the arbitration that three writers were each holding a fragment of.
- The cursor stops reaching a `Tile` node to write it. It still reaches one to read
  terrain through the port, which ADR-0164 dec. 2 allows and
  `check_lattice_doors.py` scores.
- A marking now survives being covered. Nothing in the tree relied on the previous
  behaviour — it had no name and no test — but a caller that painted expecting to
  *replace* a lower slot will now find the lower slot still there when the upper one
  clears. Only the four placement kinds share a slot, and they replace each other as
  before.
- The march pick is visible after the cursor leaves it, which is the user-facing
  point and the only part of this a player can see.
- 🔴 This does not make the highlight a port. It still returns nothing a caller waits
  on; `kind_at` is a read for tests and for the picture, and no `Tile` crosses.

## Alternatives considered

**(b) Keep one slot, fix the restore's timing. Rejected.** This is the family of
fixes that includes "capture later", "capture on write" and "re-capture in
`_process`" — the last of which is already in the tree and is the self-heal. All of
them keep a single member that three sites write and two read, and none of them can
answer the question the interleaving asks: at the moment the cursor leaves, is the
value it saved still true? Nothing in the design can know, which is why the answer
has to be structural.

**(c) Give the cursor its own overlay node, separate from the tile's. Rejected.** It
does fix the collision, and it costs a second rendering path for a thing that already
renders correctly — a mesh, a compositor registration, and a second set of rules
about how the cursor's colour composes with the tile's. The defect is arbitration,
not rendering, and the fix should land where the defect is. It would also leave
`_active_prev_type` alive for the placement writers to keep colliding on, since two of
them still share the slot.

**(d) Put the slot on `Tile` — an array of markings per tile. Rejected.** The state
would then sit where every writer can reach it, which is the arrangement that
produced this. It also puts a rendering-policy array on the node the port refuses to
hand out (ADR-0164 dec. 2), so the only way to reason about the whole picture would
be to iterate tiles — the publish already holds the key space and can answer without
touching a node.

**(e) Add a `slot` parameter to `paint`. Rejected.** It makes the interface wider for
no leverage: `src/strategy/` would have to learn which slot each marking belongs in,
and the one thing it could then do — put a marking in the "wrong" slot — is the
disagreement this exists to prevent. A kind that needs a slot the derivation does not
give it is a new kind, and minting one is cheap (dec. 5 does exactly that).
