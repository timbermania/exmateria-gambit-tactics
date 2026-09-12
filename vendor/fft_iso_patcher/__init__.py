"""PSX FFT ISO patcher.

Apply declarative patches (e.g. music slot replacement) to a Final Fantasy
Tactics ISO image. The patcher reads a TOML recipe, validates patches,
applies them sector-by-sector with EDC/ECC regeneration, and writes a
manifest of what was changed.

Public API:

    from fft_iso_patcher import apply, Recipe, PatchKind

    manifest = apply(Path("recipe.toml"))
    print(manifest.placements)

CLI:

    python -m fft_iso_patcher apply --recipe recipe.toml
    python -m fft_iso_patcher inspect --iso original.bin
"""

from .assets.kinds import PatchKind
from .manifest import ManifestBuilder
from .patcher import apply, apply_recipe
from .recipe import FreeSpace, PatchEntry, Recipe, RecipeIO, load_recipe

__all__ = [
    "apply",
    "apply_recipe",
    "Recipe",
    "RecipeIO",
    "FreeSpace",
    "PatchEntry",
    "load_recipe",
    "ManifestBuilder",
    "PatchKind",
]
__version__ = "0.1.0"
