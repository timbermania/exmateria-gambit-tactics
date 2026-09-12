# Scenario is the runtime load entry point; the scenario picker supplants map select

ADR-0029 established that a **scenario** (not an "event") is the data join-row
tying a map, a song, and a unit deployment together, and that *the map is a
field of the scenario*. This ADR is the runtime follow-through: how the game
actually *loads* a scenario, and what that does to the existing map-selection
path.

Today the runtime hardcodes the two things a scenario should drive: the map
(`MapComposer._load_and_place_map`'s `"MAP042"` default) and the music
(`GPUArena`'s `MusicPlayer.play_slot(31)` test hook). Map selection is a raw
**map picker** in `GeneralDebugPanel` (an `OptionButton` over
`get_available_maps()` calling `MapComposer.change_map`). There is no link
between a map and its song, and "load a battle" is not expressible — you pick
geometry, not an encounter.

We make the **scenario** the unit of loading. Picking a scenario sets the map
*and* the battle music; you no longer pick a raw map at all.

## Status

accepted

## Decision

- **`ScenarioDatabase` (data) + `ScenarioLoader` (orchestration) are separate.**
  `ScenarioDatabase` (`src/data/`, `RefCounted`, lazy static cache) loads
  `scenarios.json` and serves records by `scenario_id` — the same `XDatabase`
  shape as `SpriteDatabase`/`JobDatabase`, so scenario data (incl. names) is
  queryable without booting orchestration. `ScenarioLoader` is a **thin
  autoload** that *applies* a scenario: resolve via `ScenarioDatabase`, set the
  map, play the music. The data/orchestration split every other table follows.

- **`ScenarioLoader` is deliberately thin: map + music only.** Not unit
  spawning (rosters own that — `entd_idx` is deferred), not conditionals, not
  camera/weather. As scenarios gain those, each gets its own owner; the loader
  only *coordinates* the apply. This is the guard against the autoload becoming
  a god-object.

- **The map node is passed in, not held.** `apply_scenario(scenario_id,
  map_composer)` takes the active `MapComposer` as an argument; `MusicPlayer`
  is called directly (it is a global autoload). The loader holds **no** map-node
  reference, so there is no stale-ref lifecycle across scene reloads. (Rejected:
  a `register_map_composer` stateful autoload; a `scenario_applied` signal that
  would make the map node listen for "scenario" concepts.)

- **The scenario picker supplants the map picker.** `GeneralDebugPanel`'s
  map-select `OptionButton` becomes a **scenario** selector (names from
  `ScenarioDatabase`); selection calls `ScenarioLoader.apply_scenario(id,
  map_composer)`. Raw map selection is removed from the game — you select an
  encounter, and the map follows. (This is why a future reader won't find a
  "map select".)

- **Boot loads one scenario, once.** `MapComposer` gains
  `@export var auto_build_on_ready := true` (preserving current behaviour for
  the four other scenes that embed it). `GPUArena.tscn` sets it `false`, and
  `GPUArena._ready` applies a default `scenario_id`, so the scenario's map is
  built a single time — no `MAP042`-then-reload flash. (Rejected: eating a
  redundant initial `MAP042` build; leaving boot silent until the user opens the
  picker.)

- **Graceful degradation, never a crash.** `music_file_one_id == 0` means "the
  scenario sets no music" (the real track comes from the deferred event-script
  `{84} Play Song`) — the loader stops music and stays silent; it never calls
  `play_slot(0)` (which would load `MUSIC_00`). A scenario whose `map_id` has no
  parsed folder (only `map_id` 0 and 53 today) `push_error`s, keeps the current
  map, and still applies music.

## Consequences

- "Load a battle" is now a first-class action; map + music are coherent.
- A dev looking for map selection finds a scenario picker — documented here and
  in `CONTEXT.md` ("ScenarioLoader").
- `MapComposer.auto_build_on_ready == false` appears only in `GPUArena.tscn`;
  the flag exists so the scene, not the node, drives the first (scenario) load.
- The deferred pieces (ENTD units, event-script music/`{22} Switch Track`,
  conditionals) attach to `ScenarioLoader`/the scenario flow later without
  reshaping this seam.
