#!/usr/bin/env python3
"""Dump the SCUS_942.21 status-attribute table as a debug artifact (#1116).

What the game needs out of this table is ONE column: each status's default
duration in CT units. The kernel's consumer is `StatusRegistry.DEFAULT_CT`
(ADR-0013 — bit decoding stays at the parser, the consumer owns the name ->
shader-bit mapping), and the shader mirrors that table; this script is the
traceability artifact behind both, so "where does 36 come from" has an answer
that is a ROM offset and not a balance opinion.

Provenance for the table's base, stride, count and the meaning of byte 0 is in
`_fft_decode.STATUS_ATTR_*` — three cited disassembly sites, one of which is the
store into the per-unit countdown array.

Usage:
    uv run python tools/extract_status_attributes.py
"""

from __future__ import annotations

import json
from pathlib import Path

from _fft_decode import (
    STATUS_ATTR_TABLE_ENTRIES,
    STATUS_ATTR_TABLE_RAM,
    STATUS_ATTR_TABLE_SCUS_OFFSET,
    STATUS_ATTR_TABLE_STRIDE,
    STATUS_TIMER_FIRST_INDEX,
    STATUS_TIMER_SLOTS,
    extract_status_attributes,
)
from _repo_paths import scus as _scus

OUTPUT_PATH = Path(__file__).parent / "extracted" / "status_attributes.json"


def main() -> None:
    scus_path = _scus()
    print(f"Reading {scus_path}")
    with open(scus_path, "rb") as f:
        scus = f.read()

    attrs = extract_status_attributes(scus)
    assert len(attrs) == STATUS_ATTR_TABLE_ENTRIES

    timed = {v["name"]: v["default_ct"] for v in attrs.values() if v["default_ct"]}
    slotted = [v["name"] for v in attrs.values() if v["timer_slot"] is not None]

    # The table's own consistency claim: a status has a duration if and only if
    # the ROM gave it a countdown slot. If this ever parts, the base is wrong.
    assert sorted(timed) == sorted(slotted), (
        f"timed={sorted(timed)} but slotted={sorted(slotted)} — "
        "the record base or the timer window is mis-decoded"
    )

    artifact = {
        "_meta": {
            "source": "SCUS_942.21 status-attribute table",
            "ram_address": f"0x{STATUS_ATTR_TABLE_RAM:08X}",
            "file_offset": f"0x{STATUS_ATTR_TABLE_SCUS_OFFSET:X}",
            "entries": STATUS_ATTR_TABLE_ENTRIES,
            "stride_bytes": STATUS_ATTR_TABLE_STRIDE,
            "layout": (
                "byte 0 = default duration in CT units (0 = no timer); bytes 1-2 "
                "= flag bytes read by Initialize_Status_Check_Data (SCUS "
                "0x80059854); bytes 3-7 = a 40-bit status mask (MSB-first per "
                "byte, matching _fft_decode.STATUS_NAMES_BY_BYTE); byte 0x0F is "
                "an order column this decode does not fully explain"
            ),
            "setter": (
                "Status_CT_Set (SCUS 0x8005DB70) writes byte 0 into the unit's "
                "countdown array at unit+0x5D + (status - 24), and only for "
                f"status in [{STATUS_TIMER_FIRST_INDEX}, "
                f"{STATUS_TIMER_FIRST_INDEX + STATUS_TIMER_SLOTS})"
            ),
            "decrementer": (
                "BATTLE.BIN 0x8018D910 — unit[0x5D + i] -= 1 for i = 0..0xE, "
                "queueing the removal at zero. Death Sentence (slot 15) is "
                "outside the loop: it counts the unit's turns, not clock ticks."
            ),
            "note": (
                "Debug-only artifact — NOT a game asset. The game-facing table "
                "is StatusRegistry.DEFAULT_CT, keyed by this repo's own status "
                "names (ADR-0013)."
            ),
        },
        "statuses": {str(k): v for k, v in attrs.items()},
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(artifact, f, indent=2)
        f.write("\n")

    print(f"Wrote {OUTPUT_PATH}")
    print(f"  {len(timed)} of {STATUS_ATTR_TABLE_ENTRIES} statuses carry a duration:")
    for name, ct in timed.items():
        print(f"    {name:<16} {ct:3d} CT")
    print(f"  the other {STATUS_ATTR_TABLE_ENTRIES - len(timed)} have no countdown slot at all")


if __name__ == "__main__":
    main()
