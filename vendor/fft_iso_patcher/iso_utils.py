"""Sector arithmetic helpers shared across the patcher modules.

The (size + sector - 1) // sector idiom appeared in five places before
this module existed; it now lives here once.
"""

from __future__ import annotations

from .iso_sectors import USER_DATA_SIZE


def bytes_to_sectors(size_bytes: int, sector_size: int = USER_DATA_SIZE) -> int:
    """Round byte count up to whole sectors."""
    return (size_bytes + sector_size - 1) // sector_size


def pad_to_sector(size_bytes: int, sector_size: int = USER_DATA_SIZE) -> int:
    """Round byte count up to a sector-aligned byte count."""
    return bytes_to_sectors(size_bytes, sector_size) * sector_size
