"""Repo-root path resolution shared by every parser/extractor in this tools/ dir.

Goal: zero hardcoded host paths. Everything resolves from this file's location
on disk, so the same parser works identically on Linux, Windows, WSL, or any
checkout location, with no configuration.

Resolution order for the FFT extract:
    1. an explicit CLI value (caller passes it in via `--fft-extract` etc.)
    2. the `FFT_EXTRACT` environment variable
    3. `<repo>/project-assets/fft-extract/`, computed from this file's path

The same applies to derived paths: BATTLE/, BATTLE.BIN, SCUS_942.21, MAP/,
EFFECT/, SOUND/.
"""

from __future__ import annotations

import os
from pathlib import Path


def repo_root() -> Path:
    """`fft-monorepo/` — the parent of `godot-learning/`."""
    # this file: fft-monorepo/godot-learning/tools/_repo_paths.py
    return Path(__file__).resolve().parent.parent.parent


def godot_root() -> Path:
    """`fft-monorepo/godot-learning/`."""
    return Path(__file__).resolve().parent.parent


def assets_dir(subpath: str = "") -> Path:
    """Path under `godot-learning/assets/`, e.g. `assets_dir("sprites/textures")`."""
    return godot_root() / "assets" / subpath


def almanac_dir(subpath: str = "") -> Path:
    """Path under `addons/exmateria_almanac/`, e.g. `almanac_dir("jobs/jobs.json")`.

    Thirteen JSON payloads left `assets/` with the databases that read them
    (ADR-0243 dec. 8, ADR-0251 dec. 2): a table left behind in the host is an
    outbound edge into the game, which is what ADR-0146 dec. 1 ruled when
    `fold_layer.tres` travelled with `Fold.gd`. So WHERE THEY LIVE IS ANSWERED
    ONCE, HERE, rather than once per caller in `Path(...)` expressions that drift
    apart on the next move. That is `_walk_roots.EXTRACTED`'s argument one
    directory down.

    🔴 ELEVEN CALLERS, NOT SEVEN, AND THE FIRST COUNT WAS TAKEN BEFORE THE SUITE
    RAN. `tools/gen_reference_goldens.py` reached `assets/scenarios/scenarios.json`
    through `assets_dir()` and ABORTED the whole pre-flight on the missing file;
    ten more resolved the payloads through four different base expressions
    (`assets_dir()`, a module-level `ASSETS`, an `OUTPUT_DIR`, a hand-built
    `os.path.join`), which is exactly the drift this function exists to prevent
    and is why the census had to be taken mechanically rather than by grep for
    one spelling.
    """
    return godot_root() / "addons" / "exmateria_almanac" / subpath


def catalogue_dir(subpath: str = "") -> Path:
    """Path under `addons/exmateria_catalogue/`, e.g. `catalogue_dir("identity/unit_names.json")`.

    Extraction #6 (#1025 pass 3). FOUR JSON payloads left `assets/scenarios/` with
    the readers that load them, on `almanac_dir()`'s argument directly above and
    ADR-0251 dec. 2's rule that a payload travels beside its reader:
    `identity/unit_names.json`, `identity/unit_birthdays.json`,
    `templates/template_residue.json`, `seeding/template_jobs.json`.

    🔴 TWO CONTENT TREES DID NOT TRAVEL AND ARE NOT ADDRESSED HERE.
    `assets/characters/templates/` and `assets/sprites/textures/` are ROM-derived
    and gitignored — the first is not even a real directory in a worktree, it is a
    symlink written by `tools/link_worktree_godot_assets.sh` — so the addon cannot
    ship them. They are reached through the HOST-INJECTED root
    `exmateria_catalogue/content_root` (ADR-0202 dec. 5), which is a
    `ProjectSettings` key read by
    `addons/exmateria_catalogue/install/CatalogueContent.gd`, not a path helper.
    A `templates_dir()` here would put the literal back in a Python file and book
    the fix into the bucket it drains (ADR-0167).
    """
    return godot_root() / "addons" / "exmateria_catalogue" / subpath


def fft_extract_root(cli_value: str | os.PathLike | None = None) -> Path:
    """Locate the FFT PSX extract root.

    Priority: cli arg → $FFT_EXTRACT → <repo>/project-assets/fft-extract.
    """
    if cli_value:
        return Path(cli_value)
    env = os.environ.get("FFT_EXTRACT")
    if env:
        return Path(env)
    return repo_root() / "project-assets" / "fft-extract"


def battle_dir(cli_value=None) -> Path:
    """`<fft-extract>/BATTLE/` — .SPR, .SEQ, .SHP per class."""
    return fft_extract_root(cli_value) / "BATTLE"


def battle_bin(cli_value=None) -> Path:
    """`<fft-extract>/BATTLE.BIN`."""
    return fft_extract_root(cli_value) / "BATTLE.BIN"


def world_bin(cli_value=None) -> Path:
    """`<fft-extract>/WORLD/WORLD.BIN` — the world-map overlay (menu/glove cursor)."""
    return fft_extract_root(cli_value) / "WORLD" / "WORLD.BIN"


def scus(cli_value=None) -> Path:
    """`<fft-extract>/SCUS_942.21` — main executable."""
    return fft_extract_root(cli_value) / "SCUS_942.21"


def effect_dir(cli_value=None) -> Path:
    """`<fft-extract>/EFFECT/` — E000.BIN .. E511.BIN."""
    return fft_extract_root(cli_value) / "EFFECT"


def map_dir(cli_value=None) -> Path:
    """`<fft-extract>/MAP/` — per-battle map data."""
    return fft_extract_root(cli_value) / "MAP"


def sound_dir(cli_value=None) -> Path:
    """`<fft-extract>/SOUND/` — SMD music + WAVESET."""
    return fft_extract_root(cli_value) / "SOUND"


def event_dir(cli_value=None) -> Path:
    """`<fft-extract>/EVENT/` — ATTACK.OUT scenario table, event scripts, ITEM.BIN."""
    return fft_extract_root(cli_value) / "EVENT"


def attack_out(cli_value=None) -> Path:
    """`<fft-extract>/EVENT/ATTACK.OUT` — the scenario table (+ deployment zones)."""
    return event_dir(cli_value) / "ATTACK.OUT"


def iso(cli_value=None) -> Path:
    """The raw FFT ISO `.bin` — cli arg -> $FFT_ISO -> `<repo>/project-assets/`.

    Distinct from every helper above: those resolve inside the *extract*, which
    is the disc already unpacked. A few parsers (RANGETILE, the formation sheets,
    the sprite file map) read sectors the extract does not carry as files, so
    they need the image itself.
    """
    if cli_value:
        return Path(cli_value)
    env = os.environ.get("FFT_ISO")
    if env:
        return Path(env)
    return repo_root() / "project-assets" / "Final Fantasy Tactics.bin"
