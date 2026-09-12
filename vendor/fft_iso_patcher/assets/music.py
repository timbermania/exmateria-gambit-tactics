"""Music slot replacement.

Reads the LBA + size table at `SCUS_942.21:0x37880` (100 entries x 8 bytes,
little-endian `(u32 lba, u32 size_bytes_padded_to_2048)`).

Two placement strategies:
  - In-place: new SMD fits the slot's existing sector allocation. Patch the
    payload sectors and (if size changed) the table entry's size word.
  - Relocate: new SMD is larger. Allocate from `free_space`, write payload
    to the new LBA, rewrite the full (lba, size) table entry.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

from ..constants import (
    ENGINE_MAX_SMD_BYTES,
    MUSIC_TABLE_OFFSET,
    N_MUSIC_SLOTS,
    SCUS_PATH,
)
from ..free_space import FreeSpaceAllocator
from ..iso9660 import find_file
from ..iso_sectors import PsxDisc, USER_DATA_SIZE
from ..iso_utils import bytes_to_sectors, pad_to_sector
from ..manifest import ManifestBuilder
from . import register
from .byte_patch import BytePatch
from .kinds import PatchKind


@dataclass(frozen=True)
class MusicTableEntry:
    """One row of the music slot table."""

    lba: int
    size_padded: int
    sector_lba_holding_entry: int
    offset_within_that_sector: int

    @property
    def n_sectors(self) -> int:
        return self.size_padded // USER_DATA_SIZE


def _read_table_entry(disc: PsxDisc, scus_lba: int, slot: int) -> MusicTableEntry:
    if not (0 <= slot < N_MUSIC_SLOTS):
        raise ValueError(f"music slot {slot} out of range [0, {N_MUSIC_SLOTS})")
    entry_byte_offset = MUSIC_TABLE_OFFSET + slot * 8
    sector_idx_within_scus, offset_in_sector = divmod(entry_byte_offset, USER_DATA_SIZE)
    if offset_in_sector + 8 > USER_DATA_SIZE:
        # Edge case: table entry crosses a sector boundary. Not expected for FFT.
        raise NotImplementedError(
            f"music table entry for slot {slot} crosses a sector boundary"
        )
    sector_lba = scus_lba + sector_idx_within_scus
    sector_payload = disc.read_user_data(sector_lba, 1)
    lba, size = struct.unpack_from("<II", sector_payload, offset_in_sector)
    return MusicTableEntry(
        lba=lba,
        size_padded=size,
        sector_lba_holding_entry=sector_lba,
        offset_within_that_sector=offset_in_sector,
    )


def _resolve_smd_path(file_str: str, manifest: ManifestBuilder) -> Path:
    smd_path = Path(file_str)
    if not smd_path.is_absolute():
        smd_path = (manifest.recipe_path.parent / smd_path).resolve()
    if not smd_path.exists():
        raise FileNotFoundError(f"music file {smd_path} does not exist")
    return smd_path


def _validate_smd_payload(payload: bytes, slot: int) -> None:
    if len(payload) > ENGINE_MAX_SMD_BYTES:
        raise ValueError(
            f"MUSIC_{slot:02d} payload is {len(payload)} bytes; the FFT "
            f"engine refuses to load SMDs above {ENGINE_MAX_SMD_BYTES} bytes "
            f"(10 sectors). Re-export with a smaller target_bytes budget. "
            f"See docs/iso_patching.md for the binary-search history."
        )


def _resolve_placement(
    slot: int,
    new_n_sectors: int,
    new_size_bytes: int,
    table_entry: MusicTableEntry,
    allow_relocate: bool,
    allocator: FreeSpaceAllocator,
) -> tuple[int, bool]:
    """Pick the LBA the payload should land at. Returns (target_lba, relocated)."""
    if new_n_sectors <= table_entry.n_sectors:
        return table_entry.lba, False
    if not allow_relocate:
        raise ValueError(
            f"MUSIC_{slot:02d} has {table_entry.n_sectors}-sector "
            f"({table_entry.size_padded}-byte) allocation; new payload is "
            f"{new_size_bytes} bytes ({new_n_sectors} sectors). "
            f"Set allow_relocate=true and add a [free_space].ranges entry."
        )
    target_lba = allocator.allocate(new_n_sectors, reservation_key=f"music_{slot}")
    return target_lba, True


def _payload_patches(
    target_lba: int, payload: bytes, n_sectors: int, label: str
) -> list[BytePatch]:
    """Slice payload into sector-sized chunks and emit one BytePatch per chunk."""
    patches: list[BytePatch] = []
    for k in range(n_sectors):
        slice_start = k * USER_DATA_SIZE
        chunk = payload[slice_start:slice_start + USER_DATA_SIZE]
        if len(chunk) < USER_DATA_SIZE:
            chunk = chunk + bytes(USER_DATA_SIZE - len(chunk))
        patches.append(
            BytePatch(
                lba=target_lba + k,
                offset_in_payload=0,
                data=chunk,
                label=f"{label} payload sector {k}",
            )
        )
    return patches


def _table_entry_patch(
    table_entry: MusicTableEntry,
    target_lba: int,
    new_size_padded: int,
    relocated: bool,
    label: str,
) -> BytePatch | None:
    """Patch the SCUS music-table entry. None when in-place AND size unchanged."""
    if relocated:
        return BytePatch(
            lba=table_entry.sector_lba_holding_entry,
            offset_in_payload=table_entry.offset_within_that_sector,
            data=struct.pack("<II", target_lba, new_size_padded),
            label=f"{label} table entry (lba+size)",
        )
    if new_size_padded != table_entry.size_padded:
        return BytePatch(
            lba=table_entry.sector_lba_holding_entry,
            offset_in_payload=table_entry.offset_within_that_sector + 4,
            data=struct.pack("<I", new_size_padded),
            label=f"{label} table size word",
        )
    return None


@register(PatchKind.MUSIC.value)
def resolve_music(
    entry_config: dict,
    disc: PsxDisc,
    allocator: FreeSpaceAllocator,
    manifest: ManifestBuilder,
) -> list[BytePatch]:
    slot = int(entry_config["slot"])
    smd_path = _resolve_smd_path(entry_config["file"], manifest)
    allow_relocate = bool(entry_config.get("allow_relocate", False))

    payload = smd_path.read_bytes()
    _validate_smd_payload(payload, slot)
    new_size_padded = pad_to_sector(len(payload))
    new_n_sectors = bytes_to_sectors(len(payload))

    scus_rec = find_file(disc, SCUS_PATH)
    table_entry = _read_table_entry(disc, scus_rec.lba, slot)

    target_lba, relocated = _resolve_placement(
        slot, new_n_sectors, len(payload), table_entry, allow_relocate, allocator
    )

    label = f"MUSIC_{slot:02d}"
    patches = _payload_patches(target_lba, payload, new_n_sectors, label)
    table_patch = _table_entry_patch(
        table_entry, target_lba, new_size_padded, relocated, label
    )
    if table_patch is not None:
        patches.append(table_patch)

    manifest.record_placement(
        kind=PatchKind.MUSIC.value,
        slot=slot,
        source=str(smd_path),
        lba=target_lba,
        n_sectors=new_n_sectors,
        size_bytes=len(payload),
        size_padded=new_size_padded,
        relocated=relocated,
        original_lba=table_entry.lba,
        original_size_padded=table_entry.size_padded,
    )

    return patches
