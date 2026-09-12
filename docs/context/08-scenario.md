# Scenario

The encounter-setup vocabulary: the record that ties a **map**, a **song**,
and a **unit deployment** together into one playable battle. The word
"event" is deliberately **not** used here — it is already taken twice (see
_Avoid_), and in FFT the music byte you want lives in the scenario record,
not in the cutscene event it points at.

**Scenario**:
A parsed record of FFT's `EVENT/ATTACK.OUT` scenario table (~490 records,
24 bytes each) — the **entry point** for a playable battle. One scenario
references exactly one map, one (or one alternate) song, and one unit
deployment, plus weather / time-of-day / story-flow fields. The relationship
is **scenario → {map, song, units}, 1:1**: the [map](01-asset-extraction.md) is a
*field of* the scenario, not its parent. Picking a song is a scenario-keyed
lookup, never a map-keyed one — the **same map is reused by many scenarios
with different songs** (a story battle and a random encounter on one map play
different tracks), so "the song for MAP042" is ambiguous while "the song for
this scenario" is exact. The parser-emitted artifact is keyed by
`scenario_id`. A scenario is **ISO-derived** — a [committed extracted
artifact](01-asset-extraction.md), pure-derived from `ATTACK.OUT` + the parser's
hand-authored field offsets, never hand-maintained.
_Avoid_: calling it an "event" — that word names two *other* things in this
repo: [Game-event SFX](14-audio.md) (audio bound to game state) and the FFT
**event script** (the cutscene-instruction bytecode the scenario's *own id*
indexes in `TEST.EVT` — there is no `event_script_id` field; the link is
identity, and ATTACK.OUT `0x16` is `battle_conditionals_id`, which TacticsG
mislabelled — whose `{21}`/`{6B}` sound instructions
feed the [SFX catalog](14-audio.md), *not* battle music); driving song selection
off a loaded map id (many-to-one — pick the scenario, which names the song);
conflating with `WLDCORE.BIN` random battles or `ENTD*.ENT` unit rosters
(separate files, separate future parsers — a scenario only carries the
*index* into the deployment table, not the roster itself).

**Music id** (scenario field):
A scenario's `music_file_one_id` (primary) / `music_file_two_id` (alternate)
byte — an index that resolves directly to a `MUSIC_{id:02d}.SMD`
([SMDFile](14-audio.md)) in `assets/music/` (slots `00`–`99` are present). The
**only** authored link between a battle and its song; the runtime
[MusicPlayer](14-audio.md) plays the slot this names instead of a hardcoded
`play_slot(31)`.
_Avoid_: treating this as the [Cue](14-audio.md) namespace (cues name game-event
SFX, not songs); assuming a map implies a song without going through the
scenario.

**Scenario/map/music name tables**:
Three hand-authored wiki-label tables (FFTorama, via FFTPatcher EntryEdit) that
give the scenario's numeric ids meaning, all under the tracked
`assets/scenarios/`: `scenario_names.json` (`scenario_id` → "Orbonne Prayer
(Setup)"), `map_names.json` (`map_id` → "Chapel of Orbonne Monastery"),
`music_names.json` (music id → "Pray"). They co-locate here — rather than next
to maps/music — because `assets/maps` and `assets/music` are gitignored
regenerable bulk and these tables must be tracked. [Hand-authored data
assets](01-asset-extraction.md), not
ISO-derived — the bytes can't name themselves. The scenario parser **joins
them into `scenarios.json`** at extraction (baking `scenario_name` / `map_name`
/ `music_one_name` / `music_two_name`), the same way `parse_abilities` bakes
text-section names into `effects.json`; the `*_names.json` files remain the
source of truth and the baked copies regenerate from them.
_Avoid_: editing the baked names in `scenarios.json` (edit the `*_names.json`
source and re-parse); treating `music_two_name` as a victory theme (it is the
[`{22} Switch Track`] alternate, switched mid-scene by the event script — most
scenarios leave it `0`; battle music is `music_file_one_id`).

**ScenarioDatabase**:
The data loader for the [scenario](08-scenario.md) table — a `class_name`
module (`src/data/`) with a lazy static cache that reads `scenarios.json` and
hands back a scenario record by `scenario_id`. Pure data, GPU/scene-agnostic;
the same `XDatabase` shape as `SpriteDatabase` / `JobDatabase`. The scenario
**picker** queries it for names without booting any orchestration.
_Avoid_: putting map-loading or music-playing on it (that is the
[ScenarioLoader](08-scenario.md)); duplicating the JSON into a generated GDScript
mirror.

**ScenarioLoader**:
The autoload that **applies** a [scenario](08-scenario.md): given a `scenario_id`
(and the active map node), it resolves the scenario via
[ScenarioDatabase](08-scenario.md) and drives the two effects of loading a scenario
— set the **map** (the map node loads `MAP{map_id:03d}`) and play the **battle
music** ([`music_file_one_id`](08-scenario.md) → [MusicPlayer](14-audio.md) slot). It is
the runtime expression of "a scenario is the load entry point; the map is a
field of it" (ADR-0029, ADR-0030). Deliberately **thin**: map + music only —
**not** unit spawning (rosters own that), conditionals, or camera. `music_id 0`
means "scenario sets no music" (silent — that music comes from the deferred
event script), never `MUSIC_00`.
_Avoid_: growing it into a god-object as scenarios gain units/weather/camera
(each gets its own owner; the loader only *coordinates* the apply); letting it
hold a stale map-node reference (the active map is passed in per apply, not
registered); selecting a raw map anywhere in the game — scenario selection
**supplants** map selection (the debug map picker is now a scenario picker).

**ENTD (unit-deployment record)**:
A 16-slot lineup card for one [scenario](08-scenario.md)'s **scripted cast** — the
units the scenario itself spawns regardless of the player's formation. The
parsed artifact lives in `assets/scenarios/entd.json`, keyed by `entd_idx`
(the scenario field that names it; 0..511, four files of 128 records each:
ENTD1 = 0..127, ENTD2 = 128..255, ENTD3 = 256..383, ENTD4 = 384..511). Each
slot is a 40-byte `EventUnit` (`sprite_set`, `job`, equipment, position,
facing, team, AI flags); slots with `unit_id == 0xFF` are padding. Sentinel
values `0xFE`/`0xFF`/`510` in `level`/`bravery`/`equipment`/abilities mean
"inherit the default for this job" — only generic units carry real numbers.
The parser is `tools/parse_entd.py`; the format authority is FFTPatcher
`Datatypes/ENTD/EventUnit.cs`.
Three flag facts the derivations turn on (measured 2026-09-01, ADR-0216 dec.8/12):
`flags2 always_present` separates the cast from the record's **dormant** rows —
ENTD 387 carries a Red Delita and a lv1 Ramza/Delita pair the battle never
spawns; `flags2 control` marks a slot the player commands and, **across the 72 battle
groups the story timeline names**, is set on exactly **one** of their 537
always-present slots (Orbonne's baked-in Ramza, the sole predetermined cast) —
everywhere else the player's units come from the roster and are not in the ENTD
at all. Scope that claim when you repeat it: over all 512 ENTD records the flag
is set on 410 always-present slots in 71 records, nearly all of them tutorial and
cinematic records no battle group reads; and `team_color` is only Blue(0) or Red(1)
across all 8,192 slots — `parse_entd.py` models four (`0x30 >> 4`) but green is
applied at runtime — and is **meaningless in a cinematic record**, where Ramza
alone reads Red 17 times.
_Avoid_: treating the ENTD record as the full battle roster (the player
formation merges in on top — see [Scripted cast](08-scenario.md)); reading byte
fields without going through the parser (FFT packs flag bytes MSB-first, and
the parser already decoded both the raw bytes and the named bundles); reading
`team_color` or `control` off a cinematic group's record as if it described a
fight.

**ATTACK.OUT vs the ENTD** (which file names the cast):
The roles are the reverse of the obvious guess. `EVENT/ATTACK.OUT` holds the
**scenario table** (`0x10938`) and the **[deployment zones](12-strategy-phase.md)**
(`0xBBD4`) — it is a join row and **names no unit**. `BATTLE/ENTD{1..4}.ENT`
holds the cast. So a battle's roster is *the ENTD's scripted units + up to the
zone's `max_squad_size` of your own roster on the zone's tiles*: Magic City
Gariland's zone 256 is 8 tiles / `max_squad_size` 5, and Delita's fixed ENTD tile
(8,2) is deliberately not one of them. **Neither file alone answers "who is in
this battle."**
_Avoid_: expecting ATTACK.OUT to name units; concluding a battle has no player
slots from the ENTD alone (that is the zone's answer, in the other file).

**Extractions stay 1:1 with their ROM table**:
`entd.json`, `deployment_zones.json` and `scenarios.json` each mirror one ROM
table and are **not** pre-joined into a battle-shaped view, even though the join
looks obvious: 145 of 145 `entd_idx` and 71 of 72 zones are SHARED across
scenarios, and a zone belongs to a **map** (`map_id` in the record), not a
battle. Keeping them 1:1 is what keeps them regenerable and writable back through
`fft-iso-patcher`. A consumer that wants the join gets a **derived** artifact
built on top — `roster_timeline.json` is exactly that pattern (build-time, never
runtime — ADR-0216 dec.2).
_Avoid_: merging two extractions "to save a lookup" (it makes both unwritable and
duplicates the shared rows); doing the join at runtime.

**Scripted cast vs player formation**:
Two roster sources merge at battle start. The **scripted cast** is the
[ENTD](08-scenario.md) record's 16 slots — plot characters, fixed enemies,
guests, and sometimes Ramza himself pinned to a specific tile. The **player
formation** is whatever units the player picked at the formation screen,
dropped onto tiles named by the scenario's [deployment
zones](12-strategy-phase.md). The two cases diverge sharply: degenerate
cinematic-only scenarios (scenario 1) carry their *entire* cast in ENTD and
admit no formation picks; standard battles list only enemies + plot guests
in ENTD and the player fills the rest. The `ramza_mandatory` scenario flag
disambiguates whether Ramza is in ENTD or chosen from formation.
_Avoid_: treating ENTD positions as the player-side spawn tiles (those are
[Deployment zones](12-strategy-phase.md)); using `sprite_set` as a unit identity
for generic enemies (slots 7-9 in scenario 1 all share sprite `0x80` and
distinguish themselves by `unit_id` — `0x80`/`0x81`/`0x82`).

**Map state**:
A map's complete look under one `(arrangement, time-of-day, weather)` key — its
geometry *and* its **environment**: the sky-gradient backdrop, ambient colour,
three directional lights, and the 16×16 texture palette. FFT ships one per key as
a GNS mesh row; a weather or night state is usually an *environment-only* variant
(null primary-mesh pointer) that reuses the default geometry. A
[scenario](08-scenario.md)'s `weather` and `is_nighttime` bytes **select** which map
state renders, and selection is **by raw index** — the weather byte is a direct
index into the map's weather rows, verified against the BATTLE.BIN selector
(`0x800f3f94`, exact-equality on a composite key) and the live Orbonne rain state.
The scenario and GNS weather enums do **not** share labels (GNS has a `NoneAlt`
slot the scenario enum lacks), so matching is numeric, never by name. Distinct
from this repo's other "state"s (the per-unit [state machine](03-unit-roster.md), GPU
[battle state](02-combat-buffer-layout.md), `AnimationState`) — those are runtime and
per-unit; a map state is a per-map **asset variant**.
_Avoid_: "map config" / "map variant" (say map state); matching a scenario to a
map state by weather **name** (match the raw byte — the enums are offset by
`NoneAlt`); conflating the **environment** half with the `{3C}` weather-particle
overlay ([ScenarioWeather](09-event-script-interpreter.md)) — the rain/snow particles
are a separate, event-script-driven system, not the map's sky/lighting/palette.

**Setup record** (a.k.a. the *(Setup)* scenario):
The scenario record a battle group is **rooted** at — the one carrying the group's
`battle_conditionals_id` and `first_squad_deployment_idx`, and the id
`roster_timeline.json` keys the group by. Its **event script is a 7-instruction
stub**: `No-op ×4`, `{4D} Reveal`, `{F1} Wait`, `{DB} Event End`. 170 of the 500
event chunks are byte-identical stubs and every one of them is a `(Setup)` record;
155 of those are immediately followed by their group's non-stub [opener](08-scenario.md). So a
setup record establishes *what battle this is* and contains **no camera, facing or
march instruction whatsoever** — booting it and expecting a framed battlefield is
the defect ADR-0264 retires.
_Avoid_: treating the setup record as "the battle" (its sibling opener is the battle
entry); reading its stub as evidence that battles need no event script — the script
is in the other record.

**Opener**:
The scenario record whose event script runs **on the already-booted battlefield,
immediately before combat** — `roster_timeline.json`'s `opener_scenario_id` for a
group. **All 72 battle groups have one**, sized 24–679 instructions (mean 144).
It is the authored source of the battle-entry camera pose: its terminal `{19}` is
the framing the player sees when deployment opens (Gariland's scn 10 PC 35 —
`Angle 302 / Map Rotation 5632 / Zoom 4096`, where 302 and 4096 are the ROM's
`camera_init` constants and the rotation is the map-dependent yaw). Reached on a
direct seek by fast-forwarding at 30× rather than by skipping it, because 28 of 72
openers `Erase`/`Draw` the player's squad and then `{1F}` Focus on it — a squad
that is not on the field before the opener's first instruction makes those sweeps
address nothing and the Focus fall through to empty terrain.
_Avoid_: "the battle cinematic" (it is not optional scenery — it is where the
battle's framing lives); assuming a battle without a story cinematic has no opener
(random encounters use the shared **Random Battle Template**, scenarios 400/401/402,
and 401 carries five `{19}`s including the terminal settle).
