#!/usr/bin/env python3
"""Guard: no sRGB->linear pow() reachable from a `compositor_layer` shader.

A `compositor_layer` shader writes into the DISPLAY-SPACE fold scratch (FoldSurface
seeds it sRGB, the 4.8 engine Pass B hardware-adds the display texels, Pass C
converts back ONCE). There is NO tonemap after the fold, so a `pow(color, psx_gamma)`
(the sRGB->linear transform) inside a fold shader is a color-space round-trip with
NO return leg: it linearizes a value and then adds it into a display-space
accumulator = a value in the wrong space. That is the gold-box bug class
(formation_box_fold: pow lifted + the x2.2 clipped the gold gradient to a pale band,
live PSX (216,176,72) vs port (255,255,115)) and the dormant effect_fold_add particle
landmine (research/working_documents/demi2_fold_audit/README.md). The PSX hardware
adds the RAW RGB555 texel; the faithful fold adds `col.rgb` directly — no pow.

`pow` legitimately lives ONLY in the IN-SCENE linear path (opaque bodies,
effect_particle_opaque, tile_cursor_opaque): those write Godot's linear HDR target
and the pipeline tonemaps + sRGB-encodes back, so the pow is the first half of a
round-trip the tonemap completes. A fold has no such return leg.

This check FAILS if any file reachable from a `compositor_layer` entry shader (the
entry `.gdshader` OR any file it `#include`s, transitively) contains a `pow(` in CODE
(comments stripped), unless:
  1. that file carries a `// fold-pow-exempt: <reason>` marker (a genuine
     non-color-space pow — e.g. a geometric/radial falloff, not sRGB->linear), or
  2. the file is on the BURN_DOWN allowlist below (a known-unfixed fold).

The allowlist RATCHETS BOTH WAYS (like check_compositor_routing.py):
  - a NEW pow reachable from a fold, not exempt/allowlisted, FAILS (no regressions),
  - a STALE allowlist entry (since fixed or exempt-marked) FAILS too, forcing its
    removal. The allowlist shrinking to empty is the burn-down chart.

Exit 0 if clean, 1 on violation. Pure stdlib.
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

EXEMPT = "fold-pow-exempt:"

_FOLD = re.compile(r"^[ \t]*render_mode\b[^;]*\bcompositor_layer\b", re.MULTILINE)
_INCLUDE = re.compile(r'#include\s+"res://([^"]+)"')
_POW = re.compile(r"\bpow\s*\(")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT = re.compile(r"//[^\n]*")

# ---------------------------------------------------------------------------
# Known folds that still apply an sRGB->linear pow in display space (the SAME class
# as the fixed gold box: pow() on a real PSX CLUT colour in the fold scratch). Delete
# a line here when its pow is removed or exempt-marked. This list only SHRINKS.
#
# EMPTY (2026-07-31): the raw-display-space fold contract is now fully STRUCTURAL. The
# last two — cursor_fold.gdshaderinc (tile-cursor outline) and formation_orb_rim_fold
# (orb halo, the unfinished ADR-0077 box-family fix) — had their pow removed. Any new
# pow reachable from a compositor_layer shader now hard-FAILS with no allowlist to hide in.
# ---------------------------------------------------------------------------
BURN_DOWN: set[str] = set()


def _strip_comments(text: str) -> str:
    return _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub("", text))


def _resolve_include(rel: str) -> Path | None:
    # res:// is the godot project root (this package dir).
    p = (PROJECT_DIR / rel).resolve()
    return p if p.is_file() else None


def _closure(entry: Path, cache: dict[Path, str]) -> set[Path]:
    """entry + every file it #includes, transitively (raw text, pre-strip)."""
    out: set[Path] = set()
    stack = [entry]
    while stack:
        f = stack.pop()
        if f in out or not f.is_file():
            continue
        out.add(f)
        raw = cache.setdefault(f, f.read_text(encoding="utf-8"))
        for rel in _INCLUDE.findall(raw):
            inc = _resolve_include(rel)
            if inc is not None:
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

    # Entry shaders = those declaring compositor_layer in a (non-comment) render_mode line.
    fold_entries = [f for f in shader_files
                    if _FOLD.search(_strip_comments(cache.setdefault(f, f.read_text(encoding="utf-8"))))]

    # Map each fold-reachable file -> the fold entries that reach it (for the report).
    reachers: dict[Path, set[str]] = {}
    for entry in fold_entries:
        for f in _closure(entry, cache):
            reachers.setdefault(f, set()).add(entry.name)

    # A reachable file offends if its CODE (comments stripped) contains pow(.
    offenders: dict[Path, set[str]] = {}
    for f, ents in reachers.items():
        if _POW.search(_strip_comments(cache[f])):
            offenders[f] = ents

    leaks = []   # pow-in-fold, not exempt, not allowlisted -> regression
    for f, ents in sorted(offenders.items(), key=lambda kv: kv[0].name):
        if EXEMPT in cache[f] or f.name in BURN_DOWN:
            continue
        leaks.append((f.name, sorted(ents)))

    # Stale ratchet: an allowlisted file that no longer offends (fixed or exempt-marked).
    offender_names = {f.name for f in offenders
                      if EXEMPT not in cache[f]}
    stale = sorted(n for n in BURN_DOWN if n not in offender_names)

    # --- Inventory ---
    print(f"compositor_layer entry shaders: {len(fold_entries)}")
    print("pow() reachable from a fold (each must be exempt-marked or burned down):")
    if offenders:
        for f in sorted(offenders, key=lambda p: p.name):
            if EXEMPT in cache[f]:
                st = "exempt (// fold-pow-exempt:)"
            elif f.name in BURN_DOWN:
                st = "BURN_DOWN (known-unfixed fold)"
            else:
                st = "LEAK (pow in display-space fold)"
            print(f"  {f.name}: {st}  <- reached by {', '.join(sorted(offenders[f]))}")
    else:
        print("  (none)")
    print()

    ok = True
    if leaks:
        ok = False
        print("pow() reachable from a compositor_layer shader, not exempt/allowlisted:")
        for name, ents in leaks:
            print(f"  {name}: pow() in a display-space fold (reached by {', '.join(ents)})")
        print(
            "\nThe fold blends in DISPLAY space with no tonemap after, so a pow(color,\n"
            "psx_gamma) [sRGB->linear] is wrong here — add the RAW texel instead\n"
            "(mirror formation_box_fold / feedback_hud_sprite_additive_fold). If the pow\n"
            f"is genuinely NOT a color-space transform, add a `// {EXEMPT} <reason>`\n"
            "marker in that file. Do NOT grow BURN_DOWN for new folds — it only shrinks."
        )
    if stale:
        ok = False
        print("Stale BURN_DOWN entries in check_no_pow_in_fold.py:")
        for n in stale:
            print(f"  {n}: no longer has a pow() reachable from a fold (fixed or exempt-marked)")
        print("\nRemove these from BURN_DOWN — the burn-down list only shrinks.")

    if ok:
        print(
            f"OK: no un-tracked pow() in any display-space fold — {len(fold_entries)} fold "
            f"entry shaders scanned, {len(BURN_DOWN)} on the burn-down allowlist. "
            "(0 allowlisted = the raw-display-space fold contract is fully structural.)"
        )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
