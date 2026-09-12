"""Patch kinds — typed names for the recipe TOML's `[[patches.<kind>]]` keys.

The TOML stays string-keyed (TOML can't express enums), but everything
inside the patcher uses these enumerators. New asset handlers should add
themselves here and to ASSET_HANDLERS.
"""

from __future__ import annotations

from enum import Enum


class PatchKind(str, Enum):
    """Inherits str so isinstance(k, str) keeps holds and it serializes
    as the bare string for manifest JSON / dict keys."""

    MUSIC = "music"
    MAP = "map"
