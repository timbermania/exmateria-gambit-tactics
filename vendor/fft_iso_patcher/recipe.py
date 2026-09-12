"""Recipe TOML loader. Recipe = source of truth; manifest is derived."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

SUPPORTED_SCHEMA_VERSIONS = (1,)


@dataclass(frozen=True)
class RecipeIO:
    iso_in: Path
    iso_out: Path
    manifest: Path | None


@dataclass(frozen=True)
class FreeSpace:
    ranges: tuple[tuple[int, int], ...]
    reserved_for_shishi: tuple[int, int] | None = None


@dataclass(frozen=True)
class PatchEntry:
    kind: str
    config: dict[str, Any]


@dataclass(frozen=True)
class Recipe:
    schema_version: int
    io: RecipeIO
    free_space: FreeSpace
    patches: tuple[PatchEntry, ...]
    source_path: Path

    def iter_patches(self) -> tuple[PatchEntry, ...]:
        return self.patches


def _resolve(path_str: str, base: Path) -> Path:
    p = Path(path_str)
    if p.is_absolute():
        return p
    return (base / p).resolve()


def load_recipe(recipe_path: Path) -> Recipe:
    if isinstance(recipe_path, str):
        recipe_path = Path(recipe_path)
    base = recipe_path.parent.resolve()
    with recipe_path.open("rb") as f:
        raw = tomllib.load(f)

    schema_version = int(raw.get("schema_version", 1))
    if schema_version not in SUPPORTED_SCHEMA_VERSIONS:
        raise ValueError(
            f"recipe schema_version {schema_version} not in {SUPPORTED_SCHEMA_VERSIONS}"
        )

    io_block = raw.get("input", {})
    out_block = raw.get("output", {})
    iso_in = _resolve(io_block["iso"], base)
    iso_out = _resolve(out_block["iso"], base)
    manifest_str = out_block.get("manifest")
    manifest = _resolve(manifest_str, base) if manifest_str else None

    fs_block = raw.get("free_space", {}) or {}
    ranges_raw = fs_block.get("ranges", []) or []
    ranges = tuple(tuple(r) for r in ranges_raw)
    reserved = fs_block.get("reserved_for_shishi")
    reserved_t = tuple(reserved) if reserved else None
    free_space = FreeSpace(ranges=ranges, reserved_for_shishi=reserved_t)

    patches: list[PatchEntry] = []
    patches_block = raw.get("patches", {}) or {}
    for kind, entries in patches_block.items():
        if not isinstance(entries, list):
            raise ValueError(f"[patches.{kind}] must be a TOML array of tables")
        for entry in entries:
            patches.append(PatchEntry(kind=kind, config=dict(entry)))

    return Recipe(
        schema_version=schema_version,
        io=RecipeIO(iso_in=iso_in, iso_out=iso_out, manifest=manifest),
        free_space=free_space,
        patches=tuple(patches),
        source_path=recipe_path.resolve(),
    )
