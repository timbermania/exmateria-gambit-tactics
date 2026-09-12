"""Sector range allocator for Phase 2 relocation. Phase 1 unused."""

from __future__ import annotations

from dataclasses import dataclass, field

from .recipe import FreeSpace as RecipeFreeSpace


@dataclass
class _Range:
    start: int   # inclusive
    end: int     # exclusive


@dataclass
class FreeSpaceAllocator:
    ranges: list[_Range] = field(default_factory=list)
    reservations: dict[str, int] = field(default_factory=dict)

    @classmethod
    def from_recipe(cls, fs: RecipeFreeSpace) -> "FreeSpaceAllocator":
        ranges: list[_Range] = []
        reserved = fs.reserved_for_shishi
        for start, end in fs.ranges:
            if end <= start:
                continue
            if reserved is None:
                ranges.append(_Range(start, end))
                continue
            r_start, r_end = reserved
            # Subtract the reserved interval from this range.
            if end <= r_start or start >= r_end:
                ranges.append(_Range(start, end))
                continue
            if start < r_start:
                ranges.append(_Range(start, r_start))
            if end > r_end:
                ranges.append(_Range(r_end, end))
        ranges.sort(key=lambda r: r.start)
        return cls(ranges=ranges)

    def allocate(self, n_sectors: int, reservation_key: str) -> int:
        """Reserve n_sectors and return the starting LBA. Deterministic
        (allocates from the lowest available range first) so re-runs land
        at the same LBA."""
        if reservation_key in self.reservations:
            return self.reservations[reservation_key]
        for r in self.ranges:
            if r.end - r.start >= n_sectors:
                lba = r.start
                r.start += n_sectors
                self.reservations[reservation_key] = lba
                return lba
        raise RuntimeError(
            f"no free range with {n_sectors} sectors available for {reservation_key}"
        )
