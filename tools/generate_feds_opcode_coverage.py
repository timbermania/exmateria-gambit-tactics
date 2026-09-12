#!/usr/bin/env python3
"""Generate feds_opcode_coverage.json — how much of the shipped corpus each FEDS
opcode actually appears in (ADR-0085 amendment 2026-08-18b §7, "the insert menu
is the corpus").

The structural-authoring insert menu offers the opcodes FFT itself writes,
ordered by TRACK COVERAGE, rather than the decoder's full table (which would
offer opcodes no FFT sound contains — a way to end up debugging the decoder
instead of the sound) or a hand-curated list (which rots). This is that ordering,
measured rather than authored.

Counted over every REAL track: a null slot (track offset 0) owns no bytes, so it
is skipped — 2008 real tracks out of 2018 slots, carrying 57 distinct opcodes.
(The amendment's illustrative table quotes a couple of per-opcode figures from a
scan that included those 10 null slots, e.g. EndBar 1938 rather than 1928; the
shape and ordering are the same.)

The JSON carries coverage ONLY. Which of the 57 the menu can actually emit is the
GDScript side's call, since it is the decoder there (SMD.OPCODE_INFO) that knows
each opcode's param count — one table, no second list to drift. Default parameter
VALUES come from feds_param_stats.json's per-param `mode`.

Run from the package root:
    uv run --project tools python tools/generate_feds_opcode_coverage.py
"""
import json
from pathlib import Path

import parse_effect as pe

HERE = Path(__file__).resolve().parent
EFFECTS_DIR = HERE.parent / "assets" / "effects"
COVERAGE_PATH = HERE.parent / "assets" / "feds_opcode_coverage.json"


def _iter_real_tracks():
    """Yield each shipped track's opcode-event list. A null slot (offset 0) owns no
    bytes — it is a hole in the table, not a track — and is skipped."""
    for effect_dir in sorted(EFFECTS_DIR.glob("E*")):
        feds_bin = effect_dir / "feds.bin"
        if not feds_bin.exists():
            continue
        doc = pe.parse_feds_blob(feds_bin.read_bytes())
        if doc is None:
            continue
        for track in doc["tracks"]:
            if int(track.get("offset", 0)) == 0:
                continue
            yield track["opcodes"]


def build_doc() -> dict:
    tracks_with: dict = {}
    occurrences: dict = {}
    total_tracks = 0
    for events in _iter_real_tracks():
        total_tracks += 1
        present = set()
        for ev in events:
            op = ev.get("opcode")
            if op is None or op < 0x80:      # note-form events are not opcodes
                continue
            occurrences[op] = occurrences.get(op, 0) + 1
            present.add(op)
        for op in present:
            tracks_with[op] = tracks_with.get(op, 0) + 1
    # Most-covered first; ties break by opcode so the file is deterministic.
    order = sorted(tracks_with, key=lambda o: (-tracks_with[o], o))
    return {
        "_comment": (
            "Per-opcode FEDS corpus coverage — the insert menu's ordering "
            "(ADR-0085, 2026-08-18b §7). `tracks` counts REAL tracks containing "
            "the opcode at least once (null slots skipped); `occurrences` counts "
            "every instance. Regenerate: uv run --project tools python "
            "tools/generate_feds_opcode_coverage.py"),
        "total_tracks": total_tracks,
        "opcodes": [
            {"opcode": "0x%02X" % op, "tracks": tracks_with[op],
             "occurrences": occurrences[op]}
            for op in order
        ],
    }


def render(doc: dict) -> str:
    return json.dumps(doc, indent=2, sort_keys=False) + "\n"


def main() -> int:
    COVERAGE_PATH.write_text(render(build_doc()))
    print("wrote %s" % COVERAGE_PATH)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
