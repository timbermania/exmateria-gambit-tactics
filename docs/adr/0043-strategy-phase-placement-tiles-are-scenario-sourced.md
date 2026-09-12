# Strategy-phase placement tiles are scenario-sourced, with procedural retained as a fallback

Today `PlacementTileGenerator` invents the entire strategy-phase board
procedurally: two islands flood-grown from random seeds on opposite map edges
(player vs enemy) plus a handful of Poisson-sampled "contested" tiles. It is
map-agnostic and tied to nothing in the scenario — the same map always generates
a different, made-up board.

But FFT already authors this data. ADR-0029 parsed the [scenario](../context/08-scenario.md)
table and **deferred** two adjacent tables; this ADR un-defers the placement
slice of them:

- **Deployment-zone table** (`ATTACK.OUT 0xBBD4`, 768 × 12-byte records). A
  scenario's `first_squad_deployment_idx` points at one. Each record is a `u32`
  **5×5 footprint bitmap** + center `(x, y)` + `zone_facing` + `unit_facing` +
  `max_squad_size` — decoded, a set of real tile coordinates. This is **where the
  player places units**.
- **ENTD** (`ENTD*.ENT`, via `entd_idx`). One 40-byte record per unit carries its
  exact `position_x`/`position_y`, `upper_level`, `initial_direction`, and an
  `is_player_controlled` flag. The non-player-controlled units' positions are
  **where the enemies stand**.

Both formats are already reverse-engineered by TacticsTemplateG
(`src/file_formats/attack_out_data.gd`, `fft_entd_unit.gd`); we verified the
deployment decode against the retail ROM (e.g. Gariland → 8 clustered tiles,
`max_squad_size` 5).

## Status

accepted — **partially superseded by
[ADR-0258](0258-the-march-is-retired-and-two-enums-lose-a-member-without-renumbering.md)**
(2026-09-07), and the surviving half is *stronger* than it was written.

**UPHELD, and promoted:** placement tiles are scenario-sourced. This stops being one of
two modes and becomes the ONLY way a unit reaches a tile —
`GPUArena._place_units_at_defaults` (deployment zone + `DeploymentPlan`, ENTD slot
tiles) and `GambitBattle`'s deployment assignment are both scenario-sourced end to end.

**RETIRED:** the procedural fallback ("random player / random enemy" — the flood-grown
islands and the Poisson-disc sampler) and the addendum's **contested tiles**, the
march-to-objective they existed for. `PlacementTileGenerator` keeps only ADR-0192 dec.
6's water rule and is renamed `PlacementPolicy`; there is no fallback board, so an
unresolvable deployment zone is now a warning rather than a mode switch.

## Decision

- **Player tiles come from the deployment zone.** Resolve a scenario's
  `first_squad_deployment_idx` (and the optional `second_squad_deployment_idx`)
  through the `0xBBD4` table to real tile coordinates. These are the player's
  placement tiles — clustered, authored, and map-correct.

- **Enemy tiles come from ENTD positions.** The enemy placement tiles are the
  `position_x/position_y` of the scenario's ENTD records with
  `is_player_controlled == false`. Enemies "start" on them the way the player
  starts on the deployment zone. They are authored, exact, and naturally far from
  the player zone — no procedural "enemy island" needed.

- **Contested tiles stay procedural.** "Contested" (neutral tiles either side may
  claim) has **no FFT equivalent** — it is a game-original concept. It remains
  procedurally scattered across the unclaimed middle.

- **The procedural generator is retained as a fallback mode, not deleted.**
  `PlacementTileGenerator` ("random player / random enemy") still produces a full
  board when no scenario data is wired (a map with `first_squad_deployment_idx
  == 0`, an unparsed map, or a deliberately non-FFT encounter). Tile sourcing is
  selectable; scenario-sourced is primary, procedural is the fallback.

- **Only positions are consumed from ENTD — not units (for now).** The game keeps
  its own [PartyRoster / EnemyRoster](../context/03-unit-roster.md); ENTD supplies
  *where* enemies stand, the rosters supply *who* fights. (Full ENTD rosters —
  real units, stats, equipment — are a larger, separable step left open.)

- **Port the decode; fix the upstream bitmap bug.** Re-implement
  TacticsTemplateG's deployment decode, correcting its `idx**2` to `1 << idx`
  when testing the footprint bitmap. The parse emits a **committed extracted
  artifact** (the ADR-0013 boundary — pure-derived from `ATTACK.OUT` / `ENTD*.ENT`,
  reproducible, never hand-maintained), alongside `scenarios.json`.

## Consequences

- "Units start on real tiles." A scenario now **carries its own deployment**:
  authoring a battle no longer needs per-map procedural tuning, and enemy
  placement is data, not a random seed. This is the payoff for "marrying the
  scenario data."
- The procedural generator's role **demotes** from the source of truth to a
  fallback. A reader who finds island-growing + Poisson sampling should know it is
  the non-FFT path, not the default.
- The three placement roles are **asymmetric in faithfulness**: player tiles and
  enemy tiles are real FFT data; "contested" is invented. FFT itself has only a
  player deployment zone + fixed enemy positions.
- **Reachability is guaranteed by the march, not by the tiles.** Authored tiles
  can sit on terrain a low-`jump` unit couldn't normally path to; ADR-0042's
  granted march jump ensures every authored tile is always usable. Without that
  rule, a real scenario tile could become un-placeable — which is why the rule
  exists.
- Edge cases to handle (not re-litigated here): an ENTD enemy-position count that
  differs from the in-game enemy roster size (clamp / pick a subset); a scenario
  whose `map_id` has no parsed map or whose `first_squad_deployment_idx` is 0
  (fall back to procedural).
- A future reader who finds two tables being parsed out of `ATTACK.OUT` /
  `ENTD*.ENT` for placement — when ADR-0029 said they were deferred — has the
  rationale here: ADR-0029 deferred them; this ADR un-defers the placement slice
  (still not the full ENTD roster).

## Addendum — scenario tiles are spawns; contested tiles are the march objective

The decision-body above frames player tiles as "the player's placement tiles"
— tiles the player **clicks units onto** — and contested tiles as "neutral
tiles either side may claim," a procedural garnish in the unclaimed middle.
A pre-implementation grill (2026-06-13) reframed the strategy phase around a
different verb, and that reframe re-scopes both roles. The data decision is
unchanged — player tiles still come from the deployment zone, enemy tiles
still come from ENTD positions, contested is still procedural — but what the
three roles **mean to the player** changes.

The strategy phase is now **spawn → march → claim**:

- **Scenario tiles are spawns, not destinations.** At phase entry, units are
  loaded into the GPU buffer **already standing on** their scenario tiles:
  player units on the deployment-zone tiles (the union of
  `first_squad_deployment_idx` and `second_squad_deployment_idx`), enemy units
  on the ENTD enemy positions. This is **auto-filled** — the player does **not**
  click to arrange units within the deployment zone. The scenario tile is a
  start line; there is no "home tile" a unit ends on. (So "Units start on real
  tiles" in the Consequences is now literal: they *start* there and leave.)

- **Contested tiles are the objective every unit marches onto.** Contested
  stays procedural and stays the game-original concept with no FFT equivalent —
  but its role is promoted from "a neutral tile either side *may* claim" to
  "the tile each unit *must* march to." Every unit on both teams is assigned
  exactly one contested tile and walks there; the contested pool is therefore
  sized **≥ total units** (denser and wider-spread than the old ~8-tile
  Poisson scatter), and each tile is claimed 1:1 via `PlacementTileSet.claim_tile`.

- **The player's only placement decision is the destination.** During the
  existing 1-2-2-1 turn order, the player clicks a contested tile to send the
  active unit there; `AIPlacementController` picks for enemy units. There is no
  separate "arrange your starting formation" step — the starting formation *is*
  the scenario data.

- **Enemy clamp prefers red over guests.** ENTD's "enemy" set is
  `is_player_controlled == false`, which in some scenarios includes an AI
  **guest** on the player's side (e.g. Gariland entd 388 carries a
  `team_color == 0`/blue guest at (8,12) alongside five `team_color == 1`/red
  Thieves). When clamping the enemy positions to the EnemyRoster size
  (`min(ENTD enemies, roster)`), prefer `team_color == 1` (red) positions over
  guests, rather than blindly taking the first N. The artifact carries
  `team_color` per position precisely so this filter is possible at consume time.

The asymmetry recorded above sharpens: **player and enemy tiles are real FFT
spawns; contested tiles are the invented objective.** A reader who finds units
spawning on authored tiles and then walking to procedural ones should know the
authored tiles are the FFT data (where FFT puts them) and the procedural tiles
are this game's deployment minigame (where this game sends them). See ADR-0042's
matching addendum for the march target.
