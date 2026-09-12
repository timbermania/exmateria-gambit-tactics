"""Free-space surveyor.

Walks the ISO9660 tree, reads the music LBA+size table from
SCUS_942.21:0x37880, coalesces live extents, and reports the free sector
ranges between them. Read-only — never writes to the disc.

The Shishi sprite reservation `[219250, 224050)` is carved out of the
reported free space because Shishi's sprite repacker (in FFTPatcher)
writes there if the user runs it. Carving the reservation keeps recipes
authored against this surveyor's output safe to layer with Shishi.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from pathlib import Path

from .constants import MUSIC_TABLE_OFFSET, N_MUSIC_SLOTS, SCUS_PATH
from .iso9660 import DirRecord, _list_dir, find_file, root_dir_record
from .iso_sectors import PsxDisc, USER_DATA_SIZE
from .iso_utils import bytes_to_sectors

SHISHI_RESERVED: tuple[int, int] = (219250, 224050)
DEFAULT_MIN_GAP = 64


@dataclass(frozen=True)
class Extent:
    """A live region of the disc owned by some file or table."""

    label: str
    lba: int
    n_sectors: int

    @property
    def end(self) -> int:
        return self.lba + self.n_sectors


@dataclass(frozen=True)
class FreeSpaceReport:
    iso_path: Path
    total_sectors: int
    fs_extents: tuple[Extent, ...]
    music_extents: tuple[Extent, ...]
    merged_live: tuple[tuple[int, int], ...]
    gaps: tuple[tuple[int, int], ...]
    free: tuple[tuple[int, int], ...]
    min_gap: int
    shishi_reservation: tuple[int, int]

    @property
    def candidates(self) -> tuple[tuple[int, int], ...]:
        """Free ranges at least `min_gap` sectors long."""
        return tuple((s, e) for s, e in self.free if (e - s) >= self.min_gap)

    @property
    def largest(self) -> tuple[int, int] | None:
        cs = self.candidates
        if not cs:
            return None
        return max(cs, key=lambda r: r[1] - r[0])


def _walk(disc: PsxDisc, rec: DirRecord, path: str, out: list[Extent]) -> None:
    n_sectors = bytes_to_sectors(rec.size_bytes)
    out.append(Extent(label=path, lba=rec.lba, n_sectors=n_sectors))
    if not rec.is_dir:
        return
    children = _list_dir(disc, rec.lba, rec.size_bytes)
    for child in children:
        # ISO9660 stores '.' and '..' as raw bytes 0x00 / 0x01.
        if child.name in ("\x00", "\x01", ".", ".."):
            continue
        sep = "" if path.endswith("/") else "/"
        _walk(disc, child, f"{path}{sep}{child.name}", out)


def list_filesystem_extents(disc: PsxDisc) -> list[Extent]:
    extents: list[Extent] = []
    root = root_dir_record(disc)
    _walk(disc, root, "/", extents)
    return extents


def list_music_extents(disc: PsxDisc) -> list[Extent]:
    scus = find_file(disc, SCUS_PATH)
    sec_idx, off = divmod(MUSIC_TABLE_OFFSET, USER_DATA_SIZE)
    raw = disc.read_user_data(scus.lba + sec_idx, 1)
    extents: list[Extent] = []
    for slot in range(N_MUSIC_SLOTS):
        lba, size = struct.unpack_from("<II", raw, off + slot * 8)
        if lba == 0 and size == 0:
            continue
        extents.append(
            Extent(
                label=f"MUSIC_{slot:02d}",
                lba=lba,
                n_sectors=bytes_to_sectors(size),
            )
        )
    return extents


def coalesce(extents: list[Extent]) -> list[tuple[int, int]]:
    """Merge overlapping/adjacent live ranges. Returns sorted [(start, end), ...]."""
    intervals = sorted((e.lba, e.end) for e in extents if e.n_sectors > 0)
    merged: list[tuple[int, int]] = []
    for start, end in intervals:
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def find_gaps(merged: list[tuple[int, int]], total_sectors: int) -> list[tuple[int, int]]:
    """Return sorted [(start, end), ...] of free sector ranges in [0, total_sectors)."""
    gaps: list[tuple[int, int]] = []
    cursor = 0
    for start, end in merged:
        if start > cursor:
            gaps.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < total_sectors:
        gaps.append((cursor, total_sectors))
    return gaps


def carve_reservation(
    gaps: list[tuple[int, int]], reserved: tuple[int, int]
) -> list[tuple[int, int]]:
    r_start, r_end = reserved
    out: list[tuple[int, int]] = []
    for g_start, g_end in gaps:
        if g_end <= r_start or g_start >= r_end:
            out.append((g_start, g_end))
            continue
        if g_start < r_start:
            out.append((g_start, r_start))
        if g_end > r_end:
            out.append((r_end, g_end))
    return out


def survey(
    disc: PsxDisc,
    *,
    min_gap: int = DEFAULT_MIN_GAP,
    shishi_reservation: tuple[int, int] = SHISHI_RESERVED,
) -> FreeSpaceReport:
    """Walk the disc and return live extents + free ranges.

    Free space is computed as the complement of (filesystem extents
    ∪ music extents) within `[0, disc.total_sectors)`, then with
    `shishi_reservation` carved out.
    """
    fs_extents = list_filesystem_extents(disc)
    music_extents = list_music_extents(disc)

    merged = coalesce(fs_extents + music_extents)
    gaps = find_gaps(merged, disc.total_sectors)
    free = carve_reservation(gaps, shishi_reservation)

    return FreeSpaceReport(
        iso_path=disc.path,
        total_sectors=disc.total_sectors,
        fs_extents=tuple(fs_extents),
        music_extents=tuple(music_extents),
        merged_live=tuple(merged),
        gaps=tuple(gaps),
        free=tuple(free),
        min_gap=min_gap,
        shishi_reservation=shishi_reservation,
    )
