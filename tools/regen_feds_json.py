#!/usr/bin/env python3
"""Re-decode every assets/effects/E###/feds.bin into its feds.json in place.

For opcode-table corrections (test_feds_opcode_drift.py): feds.bin is the
playback truth and stays untouched; feds.json is a decoded byproduct that must
follow the table. Cheaper than a full parse_all_effects_py re-extract.

Usage:
    uv run python tools/regen_feds_json.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from parse_effect import parse_feds_blob


def main():
    effects_dir = Path(__file__).resolve().parent.parent / "assets" / "effects"
    regen, failed = 0, []
    for feds_bin in sorted(effects_dir.glob("E*/feds.bin")):
        doc = parse_feds_blob(feds_bin.read_bytes())
        if doc is None:
            failed.append(feds_bin.parent.name)
            continue
        with open(feds_bin.parent / "feds.json", "w") as f:
            json.dump(doc, f, indent=2)
        regen += 1
    print(f"Regenerated {regen} feds.json files")
    if failed:
        print(f"FAILED to decode: {', '.join(failed)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
