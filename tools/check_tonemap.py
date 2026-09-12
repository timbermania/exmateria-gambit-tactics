#!/usr/bin/env python3
"""Enforce LINEAR tonemapping on every Environment (PSX display-space blend fidelity).

The PSX had no tonemapper: it added 5-bit colour directly in the framebuffer and
clamped. Godot's LINEAR tonemapper (`TONE_MAPPER_LINEAR = 0`) is the faithful match
— effectively the identity plus a hard clamp. Every other option (Reinhard / Filmic /
ACES / AgX) is a non-linear S-curve that rolls off highlights, and that silently
breaks the whole colour model two ways:

  1. It corrupts every additive/subtractive blend in the game. `f(back + front)` only
     equals the PSX's `clamp(back + front)` when `f` is the identity. An S-curve pulls
     bright glows down and (ACES) shifts their hue — the exact "too bright / wrong
     colour" class of bug the effect-parity work keeps chasing.
  2. It makes the two blend PATHS disagree. The forward render_mode blends (tile
     overlays, the cursor dagger, screen colour) add pre-tonemap; the display-space
     compositor folds post-tonemap. Those match ONLY when the tonemap is the identity.
     Non-linear tonemap => the same effect looks different depending on which path drew
     it, and neither matches the PSX. See docs/SHADER_CONSOLIDATION_AUDIT.md.

This is a NEGATIVE net by necessity: LINEAR is the class default, so a correct
Environment simply OMITS `tonemap_mode` (Godot does not serialize a property equal to
its default — you cannot "pin" the value by setting it to the default in the editor).
We therefore cannot require the line to be present. Instead we scan every scene/resource
and fail if any Environment declares a non-zero `tonemap_mode`.

Covers both forms the property can take:
  - inline `[sub_resource type="Environment" ...]` blocks in .tscn scenes, and
  - standalone `[gd_resource type="Environment" ...]` .tres files.

`tonemap_mode` is unique to Environment, so any occurrence is an Environment property.

Exit 0 if clean, 1 on any non-linear tonemapper. Pure stdlib; no Godot needed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _walk_roots            # walk_files: rglob does not follow the
                              # addons/exmateria_sound symlink

PROJECT_DIR = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".godot", ".git"}

# Godot 4 Environment.ToneMapper enum (serialized as an int).
TONE_MAPPER_NAMES = {0: "Linear", 1: "Reinhard", 2: "Filmic", 3: "ACES", 4: "AgX"}
LINEAR = 0

SECTION_RE = re.compile(r"^\s*\[(.+?)\]\s*$")
TONEMAP_RE = re.compile(r"^\s*tonemap_mode\s*=\s*([0-9]+)")


def find_tonemaps(text: str) -> list[tuple[str, int, int]]:
    """Return (section_label, tonemap_value, line_no) for every tonemap_mode line.

    `section_label` is the nearest preceding `[...]` header (the sub_resource /
    resource the property belongs to), or "(file)" if the property appears before any
    header (shouldn't happen in valid Godot files, but reported rather than dropped).
    """
    results: list[tuple[str, int, int]] = []
    section = "(file)"
    for i, line in enumerate(text.splitlines(), start=1):
        m = SECTION_RE.match(line)
        if m:
            section = m.group(1)
            continue
        t = TONEMAP_RE.match(line)
        if t:
            results.append((section, int(t.group(1)), i))
    return results


def check_file(path: Path) -> list[str]:
    """Problems for one file: any Environment with a non-LINEAR tonemap_mode."""
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []
    problems = []
    for section, value, line_no in find_tonemaps(text):
        if value != LINEAR:
            name = TONE_MAPPER_NAMES.get(value, f"mode {value}")
            problems.append(
                f"line {line_no}: [{section}] sets tonemap_mode = {value} ({name}); "
                f"must be Linear (0) or omitted. A non-linear tonemapper corrupts "
                f"every additive/subtractive blend and desyncs the compositor fold."
            )
    return problems


def _iter_project_files():
    for path in sorted(_walk_roots.walk_files(PROJECT_DIR)):
        if path.suffix not in (".tscn", ".tres"):
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(PROJECT_DIR).parts):
            continue
        yield path


def main() -> int:
    violations: dict[str, list[str]] = {}
    scanned = 0
    environments = 0
    for path in _iter_project_files():
        scanned += 1
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        # Count Environments examined so the "OK" line is honest about coverage — a
        # green check over zero environments would be a silent no-op.
        environments += text.count('type="Environment"')
        problems = check_file(path)
        if problems:
            violations[str(path.relative_to(PROJECT_DIR))] = problems

    if violations:
        print("Non-linear tonemapper violations (PSX blend fidelity):")
        for name, problems in sorted(violations.items()):
            for p in problems:
                print(f"  {name}: {p}")
        print(
            "\nFix: set the Environment's Tonemap → Mode to 'Linear' in the inspector "
            "(or delete the tonemap_mode line). The PSX clamps; only Linear matches it. "
            "See docs/SHADER_CONSOLIDATION_AUDIT.md."
        )
        return 1

    print(
        f"OK: all {environments} Environment(s) across {scanned} scene/resource files "
        f"use Linear tonemapping (or the Linear default)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
