# Encounter setup is a Scenario, not an Event; battle music is a scenario field

We are starting to parse FFT's per-battle setup data so the game can play the
correct song for the battle being loaded (instead of the hardcoded
`MusicPlayer.play_slot(31)`). The data lives in `EVENT/ATTACK.OUT`, and the
intuitive name for it — given the folder, the filename, and common usage — is
"event". That name is a trap here for two reasons:

1. **"Event" is already taken twice in this repo.** `CONTEXT.md` defines
   **Game-event SFX** (audio bound to game state) and the **Event Instructions**
   wiki (`event_instructions_sound.md`) documents the `{21}`/`{6B}`
   cutscene sound-instruction bytecode that feeds `SfxCatalog`. A third "event"
   meaning for battle-setup records would collide with both.

2. **The song byte is not in the FFT "event" at all.** In FFT the scripted
   cutscene (the `{XX}`-instruction bytecode) *is* the "event", and a battle
   record points *out* to it via an `event_script_id` field. The byte that
   selects battle music lives in the battle-setup record itself, one field over
   from `map_id` — not in the event script. So naming the setup record "event"
   would point the name at the wrong mechanism.

The record we are parsing is what TacticsTemplateG calls `FftScenarioData` and
what the ffhacktics wiki documents under ATTACK.OUT: a 24-byte join row holding
`map_id`, `music_file_one_id`/`two_id`, `entd_idx`, weather/time, story-flow
links, and the `event_script_id` pointer. It owns no heavy assets — every asset
it names (map, song, units) lives elsewhere and is referenced by id.

## Status

accepted

## Decision

- **Call it a `Scenario`.** The encounter-setup record from `EVENT/ATTACK.OUT`
  is a **scenario**. "Event" is reserved for the two existing meanings
  (Game-event SFX; the FFT cutscene event script). See `CONTEXT.md`
  ("Scenario", "Music id").

- **A scenario is the entry point; the map is a field of it.** The relationship
  is **scenario → {map, song, units}, 1:1**. The map is one of the scenario's
  fields, not its parent — this is the precise form of "the map is a subset of
  the event".

- **Song selection is scenario-keyed, never map-keyed.** The *same* map is
  reused by many scenarios with different songs (a story battle and a random
  encounter on one map play different tracks), so "the song for MAP042" is
  ambiguous. "The song for this scenario" is exact. `music_file_one_id` resolves
  to `assets/music/MUSIC_{id:02d}.SMD`.

- **The artifact is one keyed table, not per-scenario files.** A scenario is a
  pure join row, so `scenarios.json` is a single table keyed by `scenario_id`
  (same shape as `abilities.json`/`items.json`) — not 490 files (the per-folder
  shape is for *heavyweight* assets like maps, which a scenario is not). It is a
  **committed extracted artifact**: pure-derived from `ATTACK.OUT` + the
  parser's hand-authored field offsets, reproducible, never hand-maintained
  (ADR-0013 boundary).

- **Drop empty padding; key on a verified-unique id; keep the index too.** The
  table's last 10 records are all-zero padding (not scenarios) and are dropped,
  leaving 480 real scenarios with unique `scenario_id`s. The parser asserts
  uniqueness rather than silently overwriting on collision. Because
  `scenario_id` is a meaningful FFT id and *not* the table index (81 records
  differ), each record also stores its table `index` for index-based
  cross-references (ENTD/TacticsG style).

## Scope (first pass)

Parse the scenario table only, full 24-byte record. **Deferred:** ENTD unit
rosters (`entd_idx`), the deployment-zone table, `WLDCORE.BIN` random battles,
and the cutscene event scripts (`event_script_id`). Runtime wiring (a scenario
selector; `MusicPlayer` reading the scenario's song) is a follow-up — this ADR
covers the data model and the parser.

## Consequences

- A future reader who finds a parser reading `EVENT/ATTACK.OUT` but emitting
  `scenarios.json` has the rationale here instead of wondering why it isn't
  called "event".
- The runtime can replace `play_slot(31)` with a scenario-driven song once a
  scenario is selected; the data is now available.
- The deferred tables (ENTD, deployment, WLDCORE) and the cutscene event
  scripts each get their own parser later; none of them is "the scenario".
- Format details live in `research/wiki_articles/attack_out_scenario_table.md`;
  the parser (`tools/parse_scenarios.py`) is the source of truth.
