#!/usr/bin/env python3
"""Dump the SCUS_942.21 `InflictStatusList` as a debug artifact.

The committed game asset is `effects.json` per-ability (`inflict_statuses` +
`inflict_mode` per ADR-0013). This script writes a separate per-set artifact
under `tools/extracted/` for traceability and debugging — it carries the raw
mode byte + raw status bytes alongside the decoded semantic form so you can
inspect "what is set 65?" without re-reading the ROM.

Source of truth: `hacktics_disassembly.txt` label `InflictStatusList:` at
RAM 0x80063FC4 (SCUS file offset 0x547C4). 128 entries × 6 bytes.

Usage:
    uv run python tools/extract_inflict_status_sets.py
"""

from __future__ import annotations

import json
from pathlib import Path

from _fft_decode import (
    INFLICT_STATUS_TABLE_ENTRIES,
    INFLICT_STATUS_TABLE_RAM,
    INFLICT_STATUS_TABLE_SCUS_OFFSET,
    extract_inflict_status_sets,
)
from _repo_paths import scus as _scus

OUTPUT_PATH = Path(__file__).parent / "extracted" / "inflict_status_sets.json"


def main() -> None:
    scus_path = _scus()
    print(f"Reading {scus_path}")
    with open(scus_path, "rb") as f:
        scus = f.read()

    sets = extract_inflict_status_sets(scus)
    assert len(sets) == INFLICT_STATUS_TABLE_ENTRIES

    artifact = {
        "_meta": {
            "source": "SCUS_942.21 InflictStatusList",
            "ram_address": f"0x{INFLICT_STATUS_TABLE_RAM:08X}",
            "file_offset": f"0x{INFLICT_STATUS_TABLE_SCUS_OFFSET:X}",
            "entries": INFLICT_STATUS_TABLE_ENTRIES,
            "stride_bytes": 6,
            "layout": (
                "byte 0 = mode flags (MSB-first: bit7=all, bit6=random, "
                "bit5=separate, bit4=cancel); bytes 1-5 = Status1..Status5 "
                "matching _fft_decode.STATUS_NAMES_BY_BYTE (MSB-first per byte)"
            ),
            "note": (
                "Debug-only artifact — NOT a game asset. "
                "Game-facing data lives in assets/abilities/effects.json "
                "per-ability fields inflict_statuses + inflict_mode (ADR-0013)."
            ),
        },
        "sets": {str(k): v for k, v in sets.items()},
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(artifact, f, indent=2)
    print(f"Wrote {OUTPUT_PATH} ({len(sets)} entries)")

    # Summary stats
    by_mode: dict[str | None, int] = {}
    nonzero = 0
    for s in sets.values():
        by_mode[s["mode"]] = by_mode.get(s["mode"], 0) + 1
        if s["mode"] is not None or s["statuses"]:
            nonzero += 1
    print(f"Non-empty entries: {nonzero}")
    print("By mode:")
    for mode, n in sorted(by_mode.items(), key=lambda x: (x[0] is None, x[0])):
        print(f"  {mode}: {n}")


if __name__ == "__main__":
    main()
