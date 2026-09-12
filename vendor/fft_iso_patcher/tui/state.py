"""Mutable session state shared across TUI screens."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from ..free_space_survey import Extent, FreeSpaceReport
from ..iso_sectors import PsxDisc


@dataclass
class SlotInfo:
    """One row in the music slot browser."""

    slot: int
    original_lba: int
    original_n_sectors: int
    replacement: Path | None = None
    replacement_size: int | None = None
    replacement_n_sectors: int | None = None

    @property
    def original_size_bytes(self) -> int:
        return self.original_n_sectors * 2048

    @property
    def fits_in_place(self) -> bool:
        if self.replacement_n_sectors is None:
            return True
        return self.replacement_n_sectors <= self.original_n_sectors


@dataclass
class Session:
    """Everything the TUI accumulates between screens for one apply run."""

    iso_path: Path | None = None
    disc: PsxDisc | None = None
    report: FreeSpaceReport | None = None
    slots: list[SlotInfo] = field(default_factory=list)
    output_iso: Path | None = None
    recipe_path: Path | None = None
    manifest_path: Path | None = None

    def replacements(self) -> list[SlotInfo]:
        return [s for s in self.slots if s.replacement is not None]

    def relocations_needed(self) -> int:
        return sum(1 for s in self.replacements() if not s.fits_in_place)

    def reset_replacements(self) -> None:
        for s in self.slots:
            s.replacement = None
            s.replacement_size = None
            s.replacement_n_sectors = None


def build_slots_from_report(report: FreeSpaceReport) -> list[SlotInfo]:
    """Materialize one SlotInfo per music slot present in the music table."""
    by_slot: dict[int, Extent] = {}
    for ext in report.music_extents:
        # Labels are formatted as "MUSIC_NN" by list_music_extents.
        if not ext.label.startswith("MUSIC_"):
            continue
        try:
            n = int(ext.label.split("_", 1)[1])
        except (IndexError, ValueError):
            continue
        by_slot[n] = ext

    out: list[SlotInfo] = []
    for slot in sorted(by_slot):
        ext = by_slot[slot]
        out.append(
            SlotInfo(
                slot=slot,
                original_lba=ext.lba,
                original_n_sectors=ext.n_sectors,
            )
        )
    return out
