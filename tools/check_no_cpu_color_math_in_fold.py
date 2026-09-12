#!/usr/bin/env python3
"""Guard: a folded prim's colour, when resolved on the CPU, must be RAW display-space.

The shader guards (check_no_pow_in_fold / check_no_psx_brightness_in_fold) only see the .gdshader
files. But a display-space fold prim can have its colour computed in GDScript and handed to the fold
shader as a per-vertex / per-instance COLOR — and colour-space math (an sRGB->linear `pow(gamma)`, a
`÷255→÷128` `psx_brightness` gain) can hide THERE, invisible to the shader scan. That is exactly the
`tile_decal` bug (2026-07-31): `TileOverlayColor.flat_color` applied `pow(base, srgb_gamma)` on the
CPU, so the routed placement tile was colour-space-wrong even though its shader looked clean.

The fold blends in DISPLAY space (ADR-0074 colour-math clause): the CPU resolver must emit the raw
CLUT / display value — no `pow(gamma)`, no `psx_brightness`. (The in-scene, tonemapped-back twin of a
producer legitimately keeps its own pow; that path is NOT scanned here.)

This checks the CPU helpers that resolve a *fold* prim's COLOR (the RESOLVERS list below), with
comments AND string/docstring literals stripped, for `pow(` or a bare `psx_brightness`. A genuine,
justified occurrence opts out with an inline `# fold-cpu-color-exempt: <reason>` marker on the line.
Exit 0 clean, 1 on violation. Pure stdlib.

Keep RESOLVERS complete: when a NEW producer resolves a folded prim's colour in GDScript (builds a
`*_fold` material's COLOR / vertex ARRAY_COLOR / per-instance modulate), add its file here.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

# CPU helpers that resolve a display-space FOLD prim's colour (handed to a compositor_layer shader as
# COLOR). Each must stay RAW display-space. Rationale per entry.
RESOLVERS = {
    "addons/exmateria_battlefield/overlay/TileOverlayColor.gd": "flat_color -> tile_decal_fold vertex COLOR (the pow bug)",
    "addons/exmateria_effects/render/EffectParticleRenderer.gd":      "_compute_color_modulate -> particle add/sub/mix fold COLOR",
    "addons/exmateria_effects/render/EngineFoldCompositor.gd":        "bakes level_scale + POOL_GOURAUD_GAIN into fold COLOR",
    "addons/exmateria_effects/callbacks/EffectCallback.gd":    "scene-mesh callback fold vertex colours",
    "src/ui3/elements/DamageNumber3D.gd":         "feedback-HUD additive-fold glyph tint",
}

EXEMPT = "fold-cpu-color-exempt:"
_POW = re.compile(r"\bpow\s*\(")
_PSXB = re.compile(r"\bpsx_brightness\b")


def _strip_code_lines(text: str) -> list[tuple[int, str, str]]:
    """Return (lineno, raw_line, code_only) per physical line, with `#` comments and string /
    triple-quoted-docstring literals blanked out so only executable code is scanned."""
    out: list[tuple[int, str, str]] = []
    in_triple: str | None = None            # the closing delim we're waiting for (\"\"\" or ''')
    for i, raw in enumerate(text.splitlines(), 1):
        code_chars: list[str] = []
        j = 0
        n = len(raw)
        in_str: str | None = None           # single/double quote we're inside on THIS line
        while j < n:
            two = raw[j:j+3]
            if in_triple is not None:
                if two == in_triple:
                    in_triple = None
                    j += 3
                    continue
                j += 1
                continue
            if in_str is not None:
                if raw[j] == "\\":
                    j += 2
                    continue
                if raw[j] == in_str:
                    in_str = None
                j += 1
                continue
            if two == '"""' or two == "'''":
                in_triple = two
                j += 3
                continue
            c = raw[j]
            if c == "#":
                break                        # rest of line is a comment
            if c == '"' or c == "'":
                in_str = c
                j += 1
                continue
            code_chars.append(c)
            j += 1
        out.append((i, raw, "".join(code_chars)))
    return out


def main() -> int:
    violations: list[str] = []
    missing: list[str] = []
    for rel, why in RESOLVERS.items():
        p = PROJECT_DIR / rel
        if not p.is_file():
            missing.append(rel)
            continue
        for lineno, raw, code in _strip_code_lines(p.read_text(encoding="utf-8")):
            if EXEMPT in raw:
                continue
            if _POW.search(code):
                violations.append(f"{rel}:{lineno}: pow( in a fold colour resolver -> {raw.strip()}")
            if _PSXB.search(code):
                violations.append(f"{rel}:{lineno}: psx_brightness in a fold colour resolver -> {raw.strip()}")

    if missing:
        print("ERROR: RESOLVERS entries not found (update the list):")
        for m in missing:
            print(f"  {m}")
        return 1

    print(f"CPU fold-colour resolvers scanned: {len(RESOLVERS)}")
    if violations:
        print("\ncolour-space math hiding in a CPU fold-colour resolver:")
        for v in violations:
            print(f"  {v}")
        print(
            "\nA folded prim blends in DISPLAY space (ADR-0074): the CPU resolver must emit the RAW\n"
            "CLUT/display value — no pow(gamma), no psx_brightness. See TileOverlayColor.flat_color\n"
            "(the tile_decal fix) + formation_box_fold. If an occurrence is genuinely correct, mark the\n"
            "line `# fold-cpu-color-exempt: <reason>`."
        )
        return 1

    print("OK: no pow(gamma) / psx_brightness in any CPU fold-colour resolver — every routed prim's\n"
          "     CPU-resolved colour is raw display-space.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
