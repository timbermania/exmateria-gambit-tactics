"""Raw byte patch type. Targets a specific (lba, sector_offset, bytes)."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BytePatch:
    """Write `data` into the user-data region of `lba` at byte offset
    `offset_in_payload` (0..2047). Patches that cross sector boundaries
    must be split into multiple BytePatches before reaching the writer."""

    lba: int
    offset_in_payload: int
    data: bytes
    label: str = ""   # human-readable for conflict diagnostics

    @property
    def end(self) -> int:
        return self.offset_in_payload + len(self.data)

    def overlaps(self, other: "BytePatch") -> bool:
        if self.lba != other.lba:
            return False
        return not (self.end <= other.offset_in_payload or other.end <= self.offset_in_payload)
