"""Asset handler registry.

Handlers register by recipe key string (the TOML can't express enums).
Internally the patcher prefers PatchKind from .kinds for typed lookups;
recipe-side strings are converted at the boundary in patcher.py.
"""

from typing import Callable

from .kinds import PatchKind

ASSET_HANDLERS: dict[str, Callable] = {}


def register(kind: str | PatchKind):
    """Accept either the bare string or a PatchKind enumerator."""
    key = kind.value if isinstance(kind, PatchKind) else kind

    def deco(handler):
        ASSET_HANDLERS[key] = handler
        return handler
    return deco
