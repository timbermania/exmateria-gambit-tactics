"""Pipeline orchestration."""

from __future__ import annotations

import shutil
from collections import defaultdict
from pathlib import Path
from typing import Callable

from .assets import ASSET_HANDLERS
# Importing the asset modules has the side effect of registering handlers.
from .assets import byte_patch as _byte_patch  # noqa: F401
from .assets import map as _map  # noqa: F401  (shadows the built-in; the alias keeps it out of this module's namespace)
from .assets import music as _music  # noqa: F401
from .assets.byte_patch import BytePatch
from .free_space import FreeSpaceAllocator
from .iso_sectors import PsxDisc, USER_DATA_SIZE
from .manifest import ManifestBuilder
from .recipe import FreeSpace, Recipe, load_recipe

ProgressCallback = Callable[[int, int], None]


def _detect_conflicts(patches: list[BytePatch]) -> None:
    by_sector: dict[int, list[BytePatch]] = defaultdict(list)
    for p in patches:
        by_sector[p.lba].append(p)
    for lba, group in by_sector.items():
        for i, a in enumerate(group):
            for b in group[i + 1:]:
                if a.overlaps(b):
                    raise ValueError(
                        f"BytePatch conflict at LBA {lba}: "
                        f"{a.label!r} overlaps {b.label!r}"
                    )


def _group_by_sector(patches: list[BytePatch]) -> list[tuple[int, list[BytePatch]]]:
    by_sector: dict[int, list[BytePatch]] = defaultdict(list)
    for p in patches:
        by_sector[p.lba].append(p)
    return sorted(by_sector.items())


def _verify_free_space_unoccupied(disc: PsxDisc, free_space: FreeSpace) -> None:
    """Hard-fail if a declared free-space range overlaps a live extent.

    The CLI errors when allocation runs out of declared free space; this
    catches the worse case where a range *looks* free in the recipe but
    actually contains live data on the input ISO. Cheap correctness guard
    that lets us accept arbitrary (non-vanilla) ISOs without silently
    corrupting them.
    """
    if not free_space.ranges:
        return
    # Lazy import to avoid a cycle: free_space_survey -> iso9660 -> iso_sectors.
    from .free_space_survey import coalesce, list_filesystem_extents, list_music_extents

    live = coalesce(list_filesystem_extents(disc) + list_music_extents(disc))
    for fs_start, fs_end in free_space.ranges:
        for live_start, live_end in live:
            if fs_start < live_end and live_start < fs_end:
                raise ValueError(
                    f"declared [free_space].ranges entry [{fs_start}, {fs_end}) "
                    f"overlaps live data at [{live_start}, {live_end}); "
                    f"writing here would corrupt the ISO"
                )


def apply_recipe(
    recipe: Recipe,
    *,
    progress: ProgressCallback | None = None,
) -> ManifestBuilder:
    """Apply `recipe` to its input ISO, write the output ISO, return the
    manifest.

    `progress`, if given, is called as `progress(sectors_written,
    total_sectors)` after each sector write — used by the TUI for a real
    progress bar. It is also called once with `(0, total_sectors)` before
    the first write so callers can size their UI.
    """
    if not recipe.io.iso_in.exists():
        raise FileNotFoundError(f"input ISO {recipe.io.iso_in} not found")

    recipe.io.iso_out.parent.mkdir(parents=True, exist_ok=True)
    if recipe.io.iso_out != recipe.io.iso_in:
        shutil.copyfile(recipe.io.iso_in, recipe.io.iso_out)

    disc = PsxDisc(recipe.io.iso_out)
    _verify_free_space_unoccupied(disc, recipe.free_space)
    allocator = FreeSpaceAllocator.from_recipe(recipe.free_space)
    manifest = ManifestBuilder(
        recipe_path=recipe.source_path,
        iso_in=recipe.io.iso_in,
        iso_out=recipe.io.iso_out,
    )

    byte_patches: list[BytePatch] = []
    for entry in recipe.iter_patches():
        handler = ASSET_HANDLERS.get(entry.kind)
        if handler is None:
            raise KeyError(
                f"no asset handler registered for kind {entry.kind!r}; "
                f"available: {sorted(ASSET_HANDLERS)}"
            )
        byte_patches.extend(handler(entry.config, disc, allocator, manifest))

    _detect_conflicts(byte_patches)

    sector_groups = _group_by_sector(byte_patches)
    total_sectors = len(sector_groups)
    if progress is not None:
        progress(0, total_sectors)

    for written, (sector_lba, patches_in_sector) in enumerate(sector_groups, start=1):
        # If any patch covers the whole sector, just write its data; else
        # read-modify-write.
        full_sector_patch = next(
            (p for p in patches_in_sector
             if p.offset_in_payload == 0 and len(p.data) == USER_DATA_SIZE
             and len(patches_in_sector) == 1),
            None,
        )
        if full_sector_patch is not None:
            disc.write_user_data(sector_lba, full_sector_patch.data)
        else:
            existing = bytearray(disc.read_user_data(sector_lba, 1))
            for p in patches_in_sector:
                existing[p.offset_in_payload:p.end] = p.data
            disc.write_user_data(sector_lba, bytes(existing))
        if progress is not None:
            progress(written, total_sectors)

    if recipe.io.manifest is not None:
        recipe.io.manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write(recipe.io.manifest)

    return manifest


def apply(
    recipe_path: Path,
    *,
    progress: ProgressCallback | None = None,
) -> ManifestBuilder:
    recipe = load_recipe(Path(recipe_path))
    return apply_recipe(recipe, progress=progress)
