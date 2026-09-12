#!/usr/bin/env python3
"""Guard: every `compositor_layer` shader declares its PSX primitive kind, and it matches reality.

PSX has two colour models, and a fold must use the right one (ADR-0074 color-math clause):
  * `// psx-prim: textured`   — modulates a texel: `ALBEDO = texel * gouraud/128` (PSX
                                `(texel*color)>>7`; sprites, textured/paletted polys).
  * `// psx-prim: untextured` — the colour IS the output: `ALBEDO = color` (PSX flat/gouraud
                                polys, TILE, lines — no texel, no `>>7`, no `gouraud/128`).

The kind is static per material, so it is a **header-comment convention** (no runtime cost),
parsed here. This check FAILS if a `compositor_layer` entry shader:
  1. carries no `// psx-prim: textured|untextured` declaration (state it — it drives the
     color-math contract and stops an untextured prim from hiding, as `tile_decal` did), or
  2. declares `textured` but nothing in its `#include` closure samples a texture, or
  3. declares `untextured` but its closure DOES sample a texture (mislabeled → wrong model).

Pairs with `check_no_pow_in_fold.py` (no sRGB->linear in a fold) and
`check_no_psx_brightness_in_fold.py` (no ÷255->÷128 double-count). Exit 0 clean, 1 on violation.
Pure stdlib.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0147 / extraction #1: the scan root is `classify_blueprint.WALK_ROOTS`, not a
# hard-coded directory. A guard root that does not follow the refactor's output loses
# coverage SILENTLY — see tools/_walk_roots.py for the reproduction.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots()

_FOLD = re.compile(r"^[ \t]*render_mode\b[^;]*\bcompositor_layer\b", re.MULTILINE)
_INCLUDE = re.compile(r'#include\s+"res://([^"]+)"')
_DECL = re.compile(r"//[ \t]*psx-prim:[ \t]*(textured|untextured)\b")
_SAMPLE = re.compile(r"\btexture\s*\(|_sample\s*\(")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT = re.compile(r"//[^\n]*")


def _strip(text: str) -> str:
    return _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub("", text))


def _closure(entry: Path, cache: dict[Path, str]) -> set[Path]:
    out: set[Path] = set()
    stack = [entry]
    while stack:
        f = stack.pop()
        if f in out or not f.is_file():
            continue
        out.add(f)
        for rel in _INCLUDE.findall(cache.setdefault(f, f.read_text(encoding="utf-8"))):
            inc = (PROJECT_DIR / rel).resolve()
            if inc.is_file():
                stack.append(inc)
    return out


def main() -> int:
    cache: dict[Path, str] = {}
    shader_files: list[Path] = []
    for base in SCAN_DIRS:
        if not base.is_dir():
            print(f"ERROR: scan dir not found: {base}", file=sys.stderr)
            return 1
        shader_files += sorted(base.rglob("*.gdshader"))

    fold_entries = [f for f in shader_files
                    if _FOLD.search(_strip(cache.setdefault(f, f.read_text(encoding="utf-8"))))]

    missing, mismatch, rows = [], [], []
    for e in fold_entries:
        m = _DECL.search(cache[e])
        declared = m.group(1) if m else None
        samples = any(_SAMPLE.search(_strip(cache.setdefault(f, f.read_text(encoding="utf-8"))))
                      for f in _closure(e, cache))
        actual = "textured" if samples else "untextured"
        if declared is None:
            missing.append(e.name)
            rows.append((e.name, "MISSING declaration", actual))
        elif declared != actual:
            mismatch.append((e.name, declared, actual))
            rows.append((e.name, f"declared {declared}", f"but is {actual}  <- MISMATCH"))
        else:
            rows.append((e.name, declared, "ok"))

    print(f"compositor_layer entry shaders: {len(fold_entries)}")
    for name, decl, note in sorted(rows):
        print(f"  {name:42s} {decl:22s} {note}")
    print()

    ok = not missing and not mismatch
    if missing:
        print("Fold shaders missing a `// psx-prim: textured|untextured` declaration:")
        for n in missing:
            print(f"  {n}")
        print("\nAdd the declaration after the render_mode line — it states the color-math the\n"
              "fold must use (ADR-0074): textured ⇒ texel×gouraud/128, untextured ⇒ color direct.")
    if mismatch:
        print("Fold shaders whose declared psx-prim doesn't match what they do:")
        for n, d, a in mismatch:
            print(f"  {n}: declares {d} but {'samples a texture' if a=='textured' else 'never samples a texture'}")
        print("\nFix the declaration or the shader — a `textured` fold must sample a texel; an\n"
              "`untextured` fold must output its colour directly (no texel / no gouraud/128).")
    if ok:
        t = sum(1 for r in rows if r[1] == "textured")
        u = sum(1 for r in rows if r[1] == "untextured")
        print(f"OK: all {len(fold_entries)} folds declare a matching psx-prim kind "
              f"({t} textured, {u} untextured).")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
