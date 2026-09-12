"""Derived JSON manifest of what landed where. Regenerable from the recipe."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class ManifestBuilder:
    recipe_path: Path
    iso_in: Path
    iso_out: Path
    schema_version: int = 1
    placements: list[dict[str, Any]] = field(default_factory=list)

    def record_placement(self, **fields: Any) -> None:
        self.placements.append(fields)

    def write(self, path: Path) -> None:
        doc = {
            "schema_version": self.schema_version,
            "recipe": str(self.recipe_path),
            "iso_in": str(self.iso_in),
            "iso_out": str(self.iso_out),
            "placements": self.placements,
        }
        path.write_text(json.dumps(doc, indent=2) + "\n")
