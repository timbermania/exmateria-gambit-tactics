# Map state is one (arrangement, time, weather) row carrying geometry + environment, selected by raw weather index

## Status

accepted

## Context

FFT maps ship multiple GNS mesh rows, each tagged `(arrangement, time-of-day,
weather)`. A weather or night row is usually an *environment-only* patch (null
primary-mesh pointer) that reuses the default geometry but carries its own
**sky-gradient backdrop, ambient colour, three directional lights, and 16×16
texture palette**. A [scenario](../context/08-scenario.md)'s `weather` /
`is_nighttime` bytes select which row renders.

Our exporter dropped this: `resolve_state_exports` deduped on geometry only, so
the environment-only rows collapsed onto the default and their distinct env was
discarded (`build_states_index` recorded no lighting/palette). The runtime
`MapComposer` therefore rendered only the default `Primary/Day/None` sky —
Orbonne scenario 4 (MAP056, `weather_raw=2`) drew the bright-cyan clear sky
`(160,232,239)` where PSX draws an overcast grey `(135,138,149)`.

A trap surfaced while designing selection: the scenario weather enum
(`parse_scenarios.py`: `0 None,1 Normal,2 Strong,3 VeryStrong`) and the GNS
weather enum (`map_resource.py`: `0 None,1 NoneAlt,2 Normal,3 Strong,4 VeryStrong`)
are offset by the real `NoneAlt` slot, so **label matching selects the wrong sky**.

## Decision

- **A "map state" is one `(arrangement, time, weather)` GNS row carrying both its
  geometry (may dedup onto the default) and its environment.** We extend the
  existing System-C `states[]` index with the environment fields it dropped
  (gradient, ambient, directional_lights, and a palette reference) rather than
  adding a parallel structure — `states[]` now means "map states", not just
  "geometry states". Palettes are written once per distinct set as deduped
  sidecar files and referenced by state. A sidecar carries the state's full
  palette *appearance* — its 16 base CLUTs **and** its palette-cycling animation
  frames (offset 112, #132): the state's own frame table when it ships one (e.g.
  night water), else the default state's frames (a day-weather row that only
  patches the base CLUT still animates its unchanged water palette). Dedup keys
  on base + frames, so two states sharing a base CLUT but with different frame
  tables stay separate sidecars.

- **A state's TEXTURE is a third per-state layer, orthogonal to palette (#132).**
  GNS texture resources (type 23) are tagged `(arrangement, time, weather)` too,
  and 78 of 119 maps ship genuinely distinct per-state textures (verified by
  full-payload hash + visible-region diff: 90–100% of the byte differences fall
  *outside* the UV-animation scratch canvas, i.e. on rendered terrain — e.g.
  MAP005's night texture has lit windows). A night/weather state can differ in its
  texture, its palette, or both. Textures are deduped exactly like palettes:
  `resolve_texture_sidecars` writes each distinct payload once as
  `texture_<hash>.tga` (never `texture_indexed.tga`, the root), states matching the
  default (or with no own texture) reference the root, and `states[].texture_file`
  points each state at its sidecar. `MapComposer` selects it at load through the
  same applier seam as palette/lighting, swapping the chosen atlas into the
  `indexed_color` shader's `indexed_texture` uniform.

- **Selection is by RAW INDEX, never by label.** The runtime matches
  `scenario.weather_raw == state.weather` and `scenario.is_nighttime == state.night`
  as integers. Verified two ways against the shipping engine: the BATTLE.BIN
  selector at `0x800f3f94` builds a 16-bit composite key
  `(dn<<15)|(weather<<12)|arrangement` (weather masked `&0x7`, so `NoneAlt` is a
  distinct level) and compares by **exact equality** — no translation table; and
  the live `orbonne_rain_battle_active.sstate` has only the raw-index-2 (NORMAL)
  gradient resident in RAM. Full trace + citations:
  `research/working_documents/WEATHER_MAP_STATE_MAPPING_INVESTIGATION.md`.

- **`MapComposer` owns state selection** and applies the chosen state through the
  appliers it already uses at load — `ScreenEffectOverlay` (gradient),
  `MapLightingConfig` (ambient + directional lights), `PaletteTextureGenerator`
  (palette). The state key is passed **into** the map-load call so the chosen
  environment is applied in the initial pass (**select-at-load**, no
  default-then-swap flash). [ScenarioLoader](../context/08-scenario.md) stays thin
  (ADR-0030): it forwards the scenario's weather/is_night like it forwards
  `map_id`.

- **Fallback is asymmetric.** Missing **weather/time** → silently use the INITIAL
  `Primary/Day/None` row (mirrors the ROM: the selector finding no match leaves the
  map-init default loaded; benign — a default sky). Missing **arrangement** → **fail
  loudly** (`push_error`/assert), never silently substitute: arrangement is a
  geometry swap (e.g. Secondary = post-destruction map), and rendering the wrong
  geometry is never acceptable to hide. Arrangement is presently fixed to `Primary`
  (scenarios expose no Secondary selector yet — a known gap), so this guard mainly
  protects the future wiring.

- **Map-state weather is independent of the `{3C}` weather particles**
  ([ScenarioWeather](../context/09-event-script-interpreter.md)). This decision
  covers only the map's sky/lighting/palette; the rain/snow particle overlay stays
  event-script-driven and untouched. They are content-correlated but mechanically
  separate in the ROM, and coupling would double-drive the particles.

## Consequences

- Every map is re-exported (gitignored regenerable assets); `states[]` consumers
  must tolerate the new env fields.
- `map_resource.py`'s `MapWeather` member names (`NORMAL/STRONG/VERY_STRONG` at
  2/3/4) are mislabeled vs the wiki's `Light/Normal/Heavy`. Because selection is by
  raw index the mislabel is cosmetic; we keep the names for now with a corrective
  comment and leave a clean rename as a standalone later commit.
