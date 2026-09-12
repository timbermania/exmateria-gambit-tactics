#!/usr/bin/env python3
"""Transcribe the FFTPatcher UnitNames table (special_name id -> character name)
into a committed JSON asset the game loads (UnitNames.gd / GameNavigator battle
sourcing key, decision #181).

Source of truth: tools/data/UnitNames.xml (vendored FFTPatcher table). Only
entries that carry a `name` are emitted — a bare `<Entry hex="35" />` is an
unused/blank id and must NOT resolve as a canonical story unit (those ids fall
through to the FACTORY-generic path).

Emits addons/exmateria_catalogue/identity/unit_names.json keyed by DECIMAL id string (matching the
ENTD `special_name` int), e.g. {"1": "Ramza", "12": "Ovelia", ...}.

Run:  uv run python tools/build_unit_names.py           # write
      uv run python tools/build_unit_names.py --check    # verify committed file
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from _repo_paths import catalogue_dir

HERE = Path(__file__).resolve().parent
SRC = HERE / "data" / "UnitNames.xml"
OUT = catalogue_dir("identity/unit_names.json")   # ADR-0251 dec. 2, #1025 pass 3


def build() -> dict:
    root = ET.parse(SRC).getroot()
    names: dict[str, str] = {}
    for entry in root.findall("Entry"):
        name = entry.get("name")
        if not name:
            continue
        dec = str(int(entry.get("hex"), 16))
        names[dec] = name
    return {
        "_source": "tools/data/UnitNames.xml",
        "_comment": (
            "special_name (ENTD, decimal) -> canonical story-character display "
            "name. Sourcing key for GameNavigator battle-cast build (decision "
            "#181): a slot whose special_name is a key here is CANONICAL; else "
            "FACTORY-generic. Regenerate: uv run python tools/build_unit_names.py"
        ),
        "names": names,
    }


def main() -> int:
    data = build()
    text = json.dumps(data, indent=1, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != text:
            print(f"STALE: {OUT} differs from tools/data/UnitNames.xml. "
                  f"Run: uv run python tools/build_unit_names.py")
            return 1
        print(f"OK: {OUT.name} up to date ({len(data['names'])} names)")
        return 0
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT} ({len(data['names'])} names)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
