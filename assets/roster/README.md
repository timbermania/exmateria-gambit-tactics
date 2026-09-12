# assets/roster

One committed fixture: `unit_animation_viewer_roster.json`.

It is the Unit Animation Viewer's seed (ADR-0024) — a single level-1 male Squire
with no weapon, which the F3 panel reconfigures **in place** through the
production paths (`unit.change_job`, `unit_progression.equip_item`) rather than
spawning prebaked variants. `UnitAnimationViewerScene` reads it straight off disk
through `JsonAsset` and spawns it through `UnitSpawn`. It is an authoring-tool
fixture, not a save: nothing writes it back, and nothing registers it in the
`CharacterCatalog`.

## What used to be here

`roster.json` and `enemy_roster.json` — the four-a-side casts the `PartyRoster` /
`EnemyRoster` autoloads loaded at boot, mirroring live saves at
`user://{roster,enemy_roster}.json`. **ADR-0180 deleted both stores.** There is one
player population — the `CharacterCatalog` owned overlay, established by folding a
`MutationScript` through `CatalogueReplay` — and one enemy population, the ENTD.
`GPUArena` composes its cast from the scenario it is already booting.

That decision **removes a save path without adding one, deliberately**:
owned-overlay persistence is still ADR-0201 §8's deferred work ("a save cannot
exist before there is a game to save"). Do not reintroduce a per-side roster JSON
here to fill the gap — `tools/check_rosters_retired.py` will refuse it, and the
player-facing persistent roster arrives with the owned overlay's save/load or not
at all.
