#!/usr/bin/env python3
"""Unified SOUND-sections writer CLI (ADR-0085 amendment 2026-08-11, slice 4) —
the json→bin half of studio_save's sound bridge.

Patches any of the three sound seams into one output BIN through the F1 writer
registry (`effect_writer_registry.patch_all`), every other byte verbatim:

  --sound       sound.json           TIER-1 SFX-trigger tracks
  --containers  sound_containers.json TIER-2 shared SoundContainers
  --feds        feds.bin             TIER-3 sound-definition blob (section splice)

Usage:
    write_effect_sound_sections.py <base.bin> <header.json> <out.bin>
        [--sound sound.json] [--containers sound_containers.json] [--feds feds.bin]

`header.json` is the extractor's per-effect header doc (geometry source). At
least one section flag is required — a save with nothing to write is a caller
bug, not a success.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional

import effect_writer_registry as ewr


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        description="Patch an E###.BIN's sound sections (triggers / containers / feds)")
    ap.add_argument("base_bin")
    ap.add_argument("header_json")
    ap.add_argument("out_bin")
    ap.add_argument("--sound", help="sound.json (TIER-1 trigger tracks)")
    ap.add_argument("--containers", help="sound_containers.json (TIER-2)")
    ap.add_argument("--feds", help="feds.bin (TIER-3 blob, same-size splice)")
    args = ap.parse_args(argv)

    sections = {}
    if args.sound:
        sections["sound"] = json.loads(Path(args.sound).read_text())
    if args.containers:
        sections["sound_containers"] = json.loads(Path(args.containers).read_text())
    if args.feds:
        sections["sound_def"] = Path(args.feds).read_bytes()
    if not sections:
        print("write_effect_sound_sections: no section flags given — nothing to write",
              file=sys.stderr)
        return 2

    base = Path(args.base_bin).read_bytes()
    header = json.loads(Path(args.header_json).read_text())["header"]

    try:
        out = ewr.patch_all(base, sections, header)
    except (ValueError, KeyError) as e:
        print("write_effect_sound_sections: %s" % e, file=sys.stderr)
        return 1

    Path(args.out_bin).write_bytes(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
