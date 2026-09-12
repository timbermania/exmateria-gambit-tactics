"""Build Recipe dataclasses programmatically and emit them as TOML.

The TUI assembles a Recipe in memory using `build_recipe`, optionally writes
it as a TOML file with `write_recipe_toml`, and runs it via the same code
path the CLI uses (`patcher.apply_recipe`). Keeping the TOML write path
makes recipes shareable and lets users re-edit them by hand later.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .recipe import (
    SUPPORTED_SCHEMA_VERSIONS,
    FreeSpace,
    PatchEntry,
    Recipe,
    RecipeIO,
)


@dataclass(frozen=True)
class MusicPatchSpec:
    slot: int
    file: Path
    allow_relocate: bool = True


def build_recipe(
    *,
    iso_in: Path,
    iso_out: Path,
    manifest: Path | None,
    free_space: FreeSpace,
    music_patches: list[MusicPatchSpec],
    source_path: Path,
    schema_version: int = 1,
) -> Recipe:
    """Construct an in-memory Recipe equivalent to a hand-written TOML.

    `source_path` is the path the recipe TOML *would* live at — patch
    handlers resolve relative file paths against `source_path.parent`,
    so it must be set even when no TOML is actually written. For TUI-built
    recipes that aren't saved, pass the directory containing the music
    files (or any directory that makes the absolute paths inside the
    recipe still resolve).
    """
    if schema_version not in SUPPORTED_SCHEMA_VERSIONS:
        raise ValueError(
            f"schema_version {schema_version} not in {SUPPORTED_SCHEMA_VERSIONS}"
        )

    patches: list[PatchEntry] = []
    for spec in music_patches:
        patches.append(
            PatchEntry(
                kind="music",
                config={
                    "slot": int(spec.slot),
                    "file": str(spec.file),
                    "allow_relocate": bool(spec.allow_relocate),
                },
            )
        )

    return Recipe(
        schema_version=schema_version,
        io=RecipeIO(
            iso_in=Path(iso_in).resolve(),
            iso_out=Path(iso_out).resolve(),
            manifest=Path(manifest).resolve() if manifest is not None else None,
        ),
        free_space=free_space,
        patches=tuple(patches),
        source_path=Path(source_path).resolve(),
    )


def _toml_path(p: Path) -> str:
    """Quote a path for TOML. Backslashes (Windows paths) are doubled and
    double-quotes are escaped; that matches TOML basic-string rules."""
    s = str(p).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{s}"'


def render_recipe_toml(recipe: Recipe) -> str:
    """Serialize `recipe` back to TOML. Round-trips through `load_recipe`."""
    lines: list[str] = []
    lines.append(f"schema_version = {recipe.schema_version}")
    lines.append("")
    lines.append("[input]")
    lines.append(f"iso = {_toml_path(recipe.io.iso_in)}")
    lines.append("")
    lines.append("[output]")
    lines.append(f"iso = {_toml_path(recipe.io.iso_out)}")
    if recipe.io.manifest is not None:
        lines.append(f"manifest = {_toml_path(recipe.io.manifest)}")
    lines.append("")

    fs = recipe.free_space
    if fs.ranges or fs.reserved_for_shishi is not None:
        lines.append("[free_space]")
        if fs.ranges:
            ranges_str = ", ".join(f"[{s}, {e}]" for s, e in fs.ranges)
            lines.append(f"ranges = [{ranges_str}]")
        if fs.reserved_for_shishi is not None:
            r0, r1 = fs.reserved_for_shishi
            lines.append(f"reserved_for_shishi = [{r0}, {r1}]")
        lines.append("")

    for entry in recipe.patches:
        lines.append(f"[[patches.{entry.kind}]]")
        for key, value in entry.config.items():
            if isinstance(value, bool):
                lines.append(f"{key} = {'true' if value else 'false'}")
            elif isinstance(value, int):
                lines.append(f"{key} = {value}")
            elif isinstance(value, str):
                # Treat strings that look like paths the same way.
                lines.append(f"{key} = {_toml_path(Path(value))}")
            else:
                raise TypeError(
                    f"don't know how to render {key}={value!r} ({type(value).__name__})"
                )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def write_recipe_toml(recipe: Recipe, path: Path) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(render_recipe_toml(recipe))
