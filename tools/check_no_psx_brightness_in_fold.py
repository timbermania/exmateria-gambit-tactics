#!/usr/bin/env python3
"""Guard: `psx_brightness` is a scale-conversion band-aid, not part of the fold contract.

The faithful PSX additive fold is `display_texel * (gouraud/128)` (ADR-0074 color-math
clause). `psx_brightness` (~2.2) is NOT part of that — it is a legacy `÷255→÷128` scale
conversion for the effect-POOL's colour-curve envelope (normalized `/127` in
ParticlePhysics, so it does not span the full PSX gouraud range). The formation prims
(box/orb/cursor) compute `gouraud/128` DIRECTLY from geometry (ORB_BASE_LEVEL=128
identity), so they are already absolute — multiplying them by `psx_brightness` DOUBLE-
BRIGHTENS (the overbright blue halo, 2026-07-31; the gold box dodged it by never
applying it). Canonical correct example: formation_box_fold (`clamp(c.rgb * brightness)`).

This check FAILS if `psx_brightness` is reachable from a `compositor_layer` entry shader
(the entry `.gdshader` OR any file it `#include`s, transitively; comments stripped),
unless the fold is on the BURN_DOWN allowlist. The allowlist is the ENDGAME chart: it
lists the pool / decal / callback folds whose modulate is still the `/127` envelope, so
the `psx_brightness` there is currently load-bearing. When the pool decode is changed to
emit `gouraud/128` directly (fold the ~2.2 into the curve→gouraud step, set the global to
1.0), delete those lines — and when the list is EMPTY, `psx_brightness` can be deleted
outright and every fold is uniformly `texel * gouraud/128`.

The point of the guard NOW: a NEW fold — especially a display-native CLUT / direct-gouraud
prim like the orb/cursor/box — must NOT add `psx_brightness` (that is the double-count
regression). It has to compute `gouraud/128` directly instead.

Ratchets both ways: a new psx_brightness-in-fold not on the list FAILS; a stale entry
(since migrated off it) FAILS, forcing removal. Exit 0 clean, 1 on violation. Pure stdlib.
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

EXEMPT = "fold-brightness-exempt:"

_FOLD = re.compile(r"^[ \t]*render_mode\b[^;]*\bcompositor_layer\b", re.MULTILINE)
_INCLUDE = re.compile(r'#include\s+"res://([^"]+)"')
_PSXB = re.compile(r"\bpsx_brightness\b")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT = re.compile(r"//[^\n]*")

# ---------------------------------------------------------------------------
# The ENDGAME burn-down: folds whose modulate is still the effect-pool's `/127` colour-curve
# ENVELOPE, so their `psx_brightness` (~2.2) is currently load-bearing (the ÷255→÷128 scale
# conversion). Migrate each by decoding the pool curve to gouraud/128 directly, then delete
# its line. EMPTY = psx_brightness can be deleted and the fold contract is uniform
# `texel * gouraud/128`. This list only SHRINKS.
# ---------------------------------------------------------------------------
# EMPTY (2026-07-31): every fold migrated off psx_brightness — the endgame is complete. The fold
# contract is now uniform `texel × gouraud/128` (textured) / `color` (untextured), with the ÷255→÷128
# display-gouraud gain baked per-producer (EngineFoldCompositor.POOL_GOURAUD_GAIN for particles+trap;
# a shader-local `2.2` gain const in crystal_fold (FOLD_GAIN) + effect_callback_fold
# (PSX_OUTPUT_LEVEL, renamed to agree with its in-scene twin — ADR-0191 dec. 6); tile_decal drops
# it as a spurious double-count). With this empty, ANY psx_brightness reachable from a fold is a LEAK
# and fails — and the global itself is deleted (project.godot). This list only ever shrank.
#   effect_fold_add/sub/mix — POOL_GOURAUD_GAIN baked into COLOR; byte-identical on the DEMI2 rig.
#   crystal_fold            — shader-local FOLD_GAIN const; net-neutral (const == old default).
#   tile_decal_fold         — untextured display-color; dropped the double-count + pulled pow(gamma)
#                             out of TileOverlayColor.flat_color (guarded by check_no_cpu_color_math).
#   effect_callback_fold    — shader-local PSX_OUTPUT_LEVEL const behind the use_psx_brightness toggle.
BURN_DOWN: set[str] = set()


def _strip_comments(text: str) -> str:
    return _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub("", text))


def _closure(entry: Path, cache: dict[Path, str]) -> set[Path]:
    out: set[Path] = set()
    stack = [entry]
    while stack:
        f = stack.pop()
        if f in out or not f.is_file():
            continue
        out.add(f)
        raw = cache.setdefault(f, f.read_text(encoding="utf-8"))
        for rel in _INCLUDE.findall(raw):
            inc = (PROJECT_DIR / rel).resolve()
            if inc.is_file():
                stack.append(inc)
    return out


def main() -> int:
    # HARD ZERO (2026-07-31): the endgame is COMPLETE — psx_brightness is deleted (no project
    # shader_global, no declaration in any shader). BURN_DOWN must stay empty forever: it only ever
    # shrank, and there is no global left to be load-bearing. A non-empty BURN_DOWN would mean someone
    # re-introduced the global AND allowlisted a fold for it — reject outright (mirrors the pow guard's
    # end-state). The fold contract is uniform `texel × gouraud/128` / `color`, gain baked per-producer.
    if BURN_DOWN:
        print("check_no_psx_brightness_in_fold: BURN_DOWN must be EMPTY (the psx_brightness endgame is\n"
              f"complete and the global is deleted). Remove these — no fold may re-acquire it: {sorted(BURN_DOWN)}")
        return 1

    cache: dict[Path, str] = {}
    shader_files: list[Path] = []
    for base in SCAN_DIRS:
        if not base.is_dir():
            print(f"ERROR: scan dir not found: {base}", file=sys.stderr)
            return 1
        shader_files += sorted(base.rglob("*.gdshader"))

    fold_entries = [f for f in shader_files
                    if _FOLD.search(_strip_comments(cache.setdefault(f, f.read_text(encoding="utf-8"))))]

    # Which fold entries have psx_brightness reachable in code (self or a transitive include)?
    offenders: dict[str, list[str]] = {}   # entry name -> files (in its closure) that reference it
    for entry in fold_entries:
        hits = [f.name for f in _closure(entry, cache) if _PSXB.search(_strip_comments(cache[f]))]
        if hits:
            offenders[entry.name] = sorted(set(hits))

    leaks = [n for n in offenders
             if n not in BURN_DOWN and EXEMPT not in cache_by_name(cache, n)]
    stale = sorted(n for n in BURN_DOWN if n not in offenders)

    print(f"compositor_layer entry shaders: {len(fold_entries)}")
    print("psx_brightness reachable from a fold (each must be burned down or exempt):")
    if offenders:
        for n in sorted(offenders):
            st = ("BURN_DOWN (pool/decal/callback — endgame migrates to gouraud/128)"
                  if n in BURN_DOWN else
                  "exempt" if EXEMPT in cache_by_name(cache, n) else
                  "LEAK (psx_brightness in a fold — double-count risk)")
            print(f"  {n}: {st}  <- via {', '.join(offenders[n])}")
    else:
        print("  (none — psx_brightness fully removed from the fold family)")
    print()

    ok = True
    if leaks:
        ok = False
        print("psx_brightness reachable from a compositor_layer shader, not on BURN_DOWN:")
        for n in sorted(leaks):
            print(f"  {n}: multiplies psx_brightness in a fold")
        print(
            "\npsx_brightness is the ÷255→÷128 conversion for the effect-POOL envelope only.\n"
            "A display-native CLUT / direct-gouraud fold (box/orb/cursor class) must compute\n"
            "gouraud/128 DIRECTLY and NOT multiply psx_brightness (that double-brightens — the\n"
            "overbright-halo bug). See formation_box_fold + ADR-0074's color-math clause. Do NOT\n"
            "grow BURN_DOWN for a new fold; it only shrinks (toward deleting psx_brightness)."
        )
    if stale:
        ok = False
        print("Stale BURN_DOWN entries in check_no_psx_brightness_in_fold.py:")
        for n in stale:
            print(f"  {n}: no longer references psx_brightness (migrated / removed)")
        print("\nRemove these from BURN_DOWN — the endgame burn-down only shrinks.")

    if ok:
        print(
            f"OK: no un-tracked psx_brightness in any fold — {len(fold_entries)} fold entries, "
            f"{len(BURN_DOWN)} on the endgame burn-down. "
            "(0 = psx_brightness can be deleted; fold contract is uniform texel×gouraud/128.)"
        )
    return 0 if ok else 1


def cache_by_name(cache: dict[Path, str], name: str) -> str:
    """Concatenated text of every cached file whose basename == name (for the EXEMPT check
    on the entry shader itself)."""
    return "\n".join(t for p, t in cache.items() if p.name == name)


if __name__ == "__main__":
    sys.exit(main())
