#!/usr/bin/env python3
"""Regenerate src/effects/studio/FedsInstrumentNames.gd from the DAW's generated
instrument picker table (fft-plugin/src/fft_instrument_picker_generated.inc,
itself generated from fft-plugin/data/fft_picker_samples.csv).

The FEDS Instrument opcode (0xAC) selects a waveset sample by raw id; the DAW
already names every id ("Timpani (C-3)", category) — this ports those names to
the Godot studio so the inspector can show an author a name, not a bare number.
First row per id wins (later rows are variant-group aliases).

Run from the package root:  uv run python tools/generate_feds_instrument_names.py
The paired drift guard is tools/test_feds_instrument_names_drift.py.
"""
from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent.parent / "fft-plugin" / "src" / "fft_instrument_picker_generated.inc"
TARGET = HERE.parent / "src" / "effects" / "studio" / "FedsInstrumentNames.gd"

ROW_RE = re.compile(r'\{\s*(\d+),\s*"([^"]*)",\s*(-?\d+),\s*(-?\d+),\s*"([^"]*)"')

HEADER = '''extends RefCounted
## GENERATED — do not edit. Regenerate with:
##   uv run python tools/generate_feds_instrument_names.py
## Source of truth: fft-plugin/src/fft_instrument_picker_generated.inc (the DAW
## instrument picker table, itself generated from fft-plugin/data CSVs).
##
## Names for the FEDS Instrument opcode (0xAC) raw ids — waveset samples. First
## picker row per id wins (later rows are variant-group aliases). Drift guard:
## tools/test_feds_instrument_names_drift.py. No class_name (ADR-0004).

const NAMES := {
'''

# Static helpers appended after the generated NAMES dict — hand-authored but kept
# in the template so regeneration preserves them (ADR-0085 2026-08-12 Muted verdict:
# the `· Silence` category splits into trusted-empty vs gray-zone-clip tiers). They
# PARSE the NAMES strings, so no id list needs maintaining.
FOOTER = '''

# --- Silence-flavour split (ADR-0085 2026-08-12 amendment, Muted verdict) -------
# The `· Silence` category is NOT one tier: it splits by provenance into
# TRUSTED-EMPTY (provably zero output — "Empty" / "Empty/Silent") and GRAY-ZONE
# CLIP (faint but NONZERO — "Inaudible Clip" / "Nearly Inaudible Clip"). The Muted
# opcode verdict may hard-hatch a note only under a trusted-empty instrument; a
# clip note is not provably silent → the softer "faint" tell, never a hatch. These
# PARSE the NAMES strings (not hard-coded ids), so they survive regeneration.

## The category tail after " · " ("Silence", "Synth", …); "" for an unnamed id.
static func category(id: int) -> String:
\treturn String(NAMES.get(id, "")).get_slice(" · ", 1)


## True iff `id` is in the `· Silence` category (any flavour, empty or clip).
static func is_silence(id: int) -> bool:
\treturn category(id) == "Silence"


## The silence flavour of `id` — "Empty" (normalizing "Empty/Silent"), "Inaudible
## Clip", or "Nearly Inaudible Clip" — else "" (not a silence instrument). Parsed
## from the name before " · ".
static func silence_flavour(id: int) -> String:
\tif not is_silence(id):
\t\treturn ""
\tvar head := String(NAMES.get(id, "")).get_slice(" · ", 0).strip_edges()
\treturn "Empty" if head.begins_with("Empty") else head


## A TRUSTED-EMPTY instrument: provably zero output. A note under it, on a voice
## that is NOT noise-armed, is Muted (hard hatch).
static func is_trusted_empty(id: int) -> bool:
\treturn silence_flavour(id) == "Empty"


## A GRAY-ZONE clip: faint but nonzero. NOT provably silent → never Muted; a note
## under it gets the softer "faint" ≈ tell.
static func is_gray_zone_clip(id: int) -> bool:
\tvar f := silence_flavour(id)
\treturn f == "Inaudible Clip" or f == "Nearly Inaudible Clip"
'''


def parse_names(text: str) -> dict[int, tuple[str, str]]:
    names: dict[int, tuple[str, str]] = {}
    for m in ROW_RE.finditer(text):
        iid = int(m.group(1))
        if iid not in names:
            names[iid] = (m.group(2), m.group(5))
    return names


def render(names: dict[int, tuple[str, str]]) -> str:
    lines = [HEADER]
    for iid in sorted(names):
        name, category = names[iid]
        label = f"{name} · {category}" if category else name
        lines.append('\t%d: "%s",\n' % (iid, label.replace('"', "'")))
    lines.append("}\n")
    lines.append(FOOTER)
    return "".join(lines)


def main() -> None:
    names = parse_names(SOURCE.read_text())
    TARGET.write_text(render(names))
    print(f"wrote {TARGET} ({len(names)} instruments)")


if __name__ == "__main__":
    main()
