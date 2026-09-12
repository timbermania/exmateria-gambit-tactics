# Asset Parsing (Python tools)

**Always run tools with `uv run`** — dependencies are managed via
`tools/pyproject.toml`; bare `python3` fails when they aren't installed
globally.

```bash
# Correct
uv run python tools/parse_all_maps.py project-assets/fft-extract/MAP
```

## Re-parsing FFT data

If the FFT extract (`project-assets/fft-extract`) is updated, re-run the
relevant parsers:

```bash
# Sprites (from BATTLE/*.SPR)
uv run python tools/extract_all_sprites.py project-assets/fft-extract assets/sprites/textures

# Animation data (SEQ/SHP files)
uv run python tools/parse_seq.py --all
uv run python tools/parse_shp.py --all

# Sprite type mappings
uv run python tools/parse_sprite_types.py

# Layer priorities (from BATTLE.BIN)
uv run python tools/parse_layer_priority.py

# RANGETILE atlas (from the RAW ISO, not the extract): cursor-highlight tile,
# HUD damage digits, HP/MP/CT vitals bars. Omitting this blanks the
# active-cursor barber-pole tile + HUD even though every other sprite parses.
uv run python tools/parse_range_tiles.py

# Effects (one-pass: JSON + texture + callbacks, all effects)
uv run python tools/parse_all_effects_py.py --force

# Maps (requires pygltflib via uv)
uv run python tools/parse_all_maps.py project-assets/fft-extract/MAP --force

# Placement: deployment zones (ATTACK.OUT 0xBBD4) + ENTD positions.
# Writes addons/exmateria_almanac/encounters/{deployment_zones,entd_positions}.json.
# NEEDS assets/maps/*/terrain.json (for size_z) — re-parse maps FIRST or the
# ADR-0052 depth flip is skipped for the maps that are missing, silently.
uv run python tools/parse_placement.py
```

After re-parsing placement, re-score the deployment START FACING rule — it is
derived from the ROM, and the corpus arm is the half that can catch a regression
in the artifacts:

```bash
uv run python tools/score_deploy_facing.py            # add --verbose for the table
```

## Effect parsing

Effect extraction is one fire-and-forget command — it writes every effect's
JSON sections **and** `texture.tga` **and** bespoke callback tables in a single
pass. It handles DATA and CODE-format effects alike by reading each effect's
header offset from the authoritative BATTLE.BIN table (`0x14d8d0`, minus load
base `0x801c2500`) — the same table the game uses — rather than guessing (see
`pitfalls.md` → effects for why a prologue scan is wrong).

```bash
# All effects (--force re-extracts existing)
uv run python tools/parse_all_effects_py.py --force

# A single effect (same one-pass output)
uv run python tools/parse_effect.py project-assets/fft-extract/EFFECT/E317.BIN
```

`parse_effect.py` is the library (`extract_effect()` = parse + texture +
callbacks); `parse_all_effects_py.py` is the batch loop. The Lua
`extract_effect_texture.lua` is invoked internally for `texture.tga` — no
separate step.

`sound_config.json` / `sound_tracks.json` / `feds.bin` and
`texture_indexed.bin` are **not** produced; stale copies are removed on
(re)parse. The `sounds/*.wav` in each effect folder come from runtime SPU
capture (`capture_effect_audio.py`), not this parser.

## Map authoring helpers

`tools/preview_map.py` prints an ASCII walkability (`.`/`#`) + height (`0`-`9`,
`+` = clamped above 9) grid for any parsed map — use it to pick spawn
coordinates for new scenarios in `tests/gambit_scenarios/` without launching
Godot. Reads `assets/maps/<MAP_ID>/terrain.json` (level_0 only — the runtime
ignores level_1).

```bash
uv run python tools/preview_map.py MAP042
```
