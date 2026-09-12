"""Minimal ISO9660 directory walker for PSX BIN images.

Just enough to resolve a path like '/SCUS_942.21;1' to its LBA. We don't
need full ISO9660; FFT discs use vanilla directory records and the PVD is
always at LBA 16.
"""

from __future__ import annotations

from dataclasses import dataclass

from .iso_sectors import PsxDisc
from .iso_utils import bytes_to_sectors

PVD_LBA = 16
ROOT_DIR_RECORD_OFFSET = 156   # within PVD's user data
ROOT_DIR_RECORD_LENGTH = 34


@dataclass(frozen=True)
class DirRecord:
    name: str
    lba: int
    size_bytes: int
    is_dir: bool
    # Position of this record on disc: the LBA of the directory sector that
    # holds it and the byte offset within that sector's user data. Directory
    # records never cross sector boundaries, so this fully locates the
    # record for in-place pokes (e.g. the map leg's both-endian LBA/size
    # rewrites).
    containing_lba: int
    offset_in_containing: int


def _parse_dir_record(data: bytes, offset: int, containing_lba: int,
                      offset_in_containing: int) -> tuple[DirRecord | None, int]:
    """Parse one ISO9660 directory record at `data[offset:]`.

    `offset` is absolute within the concatenated directory bytes; `offset_in_containing`
    is that same position measured within its own sector (directory records
    never cross sector boundaries). Returns (record, next_offset) where
    record is None if `data[offset]` == 0 (end-of-records-in-sector marker)."""
    rec_len = data[offset]
    if rec_len == 0:
        return None, offset
    lba = int.from_bytes(data[offset + 2:offset + 6], "little")
    size_bytes = int.from_bytes(data[offset + 10:offset + 14], "little")
    flags = data[offset + 25]
    is_dir = bool(flags & 0x02)
    name_len = data[offset + 32]
    name = data[offset + 33:offset + 33 + name_len].decode("ascii", errors="replace")
    return DirRecord(
        name=name, lba=lba, size_bytes=size_bytes, is_dir=is_dir,
        containing_lba=containing_lba, offset_in_containing=offset_in_containing,
    ), offset + rec_len


def _list_dir(disc: PsxDisc, lba: int, size_bytes: int) -> list[DirRecord]:
    # ISO9660 directory data is laid out as user-data sectors (2048 bytes each).
    n_sectors = bytes_to_sectors(size_bytes)
    raw = disc.read_user_data(lba, n_sectors)
    records: list[DirRecord] = []
    # Walk sector-by-sector; records do not cross sector boundaries (a zero
    # record length marks "skip rest of this sector" — the next record, if
    # any, starts at the next sector's first byte).
    for s in range(n_sectors):
        sector_start = s * 2048
        sector_end = sector_start + 2048
        containing_lba = lba + s
        offset = sector_start
        while offset < sector_end:
            rec, next_offset = _parse_dir_record(
                raw, offset, containing_lba, offset - sector_start
            )
            if rec is None:
                break
            records.append(rec)
            offset = next_offset
            if offset > sector_end:
                # Defensive: a record length that runs past the sector
                # boundary means a corrupt record; restart at the next
                # sector rather than desync the walk.
                offset = sector_end
    return records


def list_dir(disc: PsxDisc, lba: int, size_bytes: int) -> list[DirRecord]:
    """List one directory level (the directory's own LBA/size, as found in a
    parent record). One pass over the listing; call once and index the
    results rather than re-walking per file."""
    return _list_dir(disc, lba, size_bytes)


def root_dir_record(disc: PsxDisc) -> DirRecord:
    pvd = disc.read_user_data(PVD_LBA, 1)
    rec, _ = _parse_dir_record(
        pvd, ROOT_DIR_RECORD_OFFSET, PVD_LBA, ROOT_DIR_RECORD_OFFSET
    )
    if rec is None:
        raise ValueError("PVD has no root directory record")
    return rec


def list_root(disc: PsxDisc) -> list[DirRecord]:
    root = root_dir_record(disc)
    return _list_dir(disc, root.lba, root.size_bytes)


def find_file(disc: PsxDisc, path: str) -> DirRecord:
    """Resolve a path like '/SCUS_942.21;1' to its DirRecord.

    Path components are case-sensitive and must include the ';1' version
    suffix that ISO9660 appends. Use '/' as separator. Leading '/' is
    optional but conventional.
    """
    if path.startswith("/"):
        path = path[1:]
    if not path:
        raise ValueError("empty path")
    parts = path.split("/")
    cur = root_dir_record(disc)
    cur_records = _list_dir(disc, cur.lba, cur.size_bytes)
    for i, part in enumerate(parts):
        match = next((r for r in cur_records if r.name == part), None)
        if match is None:
            available = sorted(r.name for r in cur_records if r.name not in (".", ".."))
            raise FileNotFoundError(
                f"path component {part!r} not found at {'/'.join(parts[:i]) or '/'}; "
                f"available: {available[:10]}{'...' if len(available) > 10 else ''}"
            )
        if i == len(parts) - 1:
            return match
        if not match.is_dir:
            raise NotADirectoryError(f"{part!r} is not a directory")
        cur_records = _list_dir(disc, match.lba, match.size_bytes)
    raise RuntimeError("unreachable")
