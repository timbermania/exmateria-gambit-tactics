#!/usr/bin/env python3
"""Enforce sprite-layer composition on one mesh per unit (ADR-0019).

A unit's sprite layers (BODY / WEAPON / EFFECT) render onto ONE billboard mesh
per unit. Each layer is a slot in a single ShaderMaterial, multiplexed in the
fragment shader; per-layer toggle is a shader UNIFORM (`wep_enable`,
`eff_enable`), NOT scene-tree `visible` on per-layer Node3D children. ADR-0019
records this so a future reader doesn't "refactor" the shader-multiplexed model
back into a scene-tree composition (one MeshInstance3D per layer).

`SpriteLayerManager` is the seam. This guard locks it in:

  1. `enable_layer(...)` toggles layers via `set_shader_parameter("*_enable", ...)`
     — the multiplex uniform, not a node flag.
  2. `SpriteLayerManager` never assigns `.visible` (the rejected scene-tree
     toggle) and never constructs a `MeshInstance3D` (no per-layer mesh child).
  3. The `wep_enable` / `eff_enable` uniforms are actually READ by the unit
     shader (following its `#include` chain — the shader body lives in a shared
     `.gdshaderinc`), so the toggle drives a real shader slot rather than a
     parameter nothing consumes.

Exit 0 if the shader-multiplexed shape holds, 1 on any violation. Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# Both moved into the addon with #744's 33-file scope. This guard is LOUD about a
# stale path — it prints `expected <path> — it is missing` and exits 1 — which is
# how the move surfaced them, so the repoint is a fix and not a precaution.
MANAGER = PROJECT_DIR / "addons" / "exmateria_sprite_rig" / "layers" / "SpriteLayerManager.gd"
UNIT_SHADER = PROJECT_DIR / "addons" / "exmateria_sprite_rig" / "render" / "unit.gdshader"
ENABLE_UNIFORMS = ("wep_enable", "eff_enable")

VISIBLE_ASSIGN = re.compile(r"\.visible\s*=")
MESHINSTANCE_NEW = re.compile(r"\bMeshInstance3D\s*\.\s*new\s*\(")
ENABLE_SETTER = re.compile(r'set_shader_parameter\(\s*"(wep|eff)_enable"')
INCLUDE = re.compile(r'#include\s+"(res://[^"]+)"')


def _res_to_path(res_rel: str) -> Path:
    return PROJECT_DIR / res_rel[len("res://"):]


def _shader_text_with_includes(path: Path, _seen: set[Path] | None = None) -> str:
    """The shader's text plus that of every file it `#include`s, transitively.

    The unit shader body (uniforms + compositor) was split into a shared
    `.gdshaderinc` so the opaque and additive wrappers can't drift (da9c37c25), so
    the `*_enable` uniform declarations live in the include, not the entry point.
    A guard that only read the entry point would false-positive on the split — so
    it must expand includes, the same way check_depth_shaders.py does.
    """
    _seen = _seen if _seen is not None else set()
    path = path.resolve()
    if path in _seen or not path.is_file():
        return ""
    _seen.add(path)
    text = path.read_text(encoding="utf-8")
    parts = [text]
    for m in INCLUDE.finditer(text):
        parts.append(_shader_text_with_includes(_res_to_path(m.group(1)), _seen))
    return "\n".join(parts)


def _code_lines(path: Path) -> list[str]:
    """Lines with trailing line-comment stripped (a `.visible` in a doc comment
    or a `MeshInstance3D` in a docstring isn't a real toggle/construction)."""
    return [line.split("#", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()]


def main() -> int:
    problems: list[str] = []

    if not MANAGER.is_file():
        print(f"ADR-0019: expected {MANAGER.relative_to(PROJECT_DIR)} — it is missing.")
        return 1

    lines = _code_lines(MANAGER)
    joined = "\n".join(lines)

    # 1. The layer toggle drives shader parameters.
    if not ENABLE_SETTER.search(joined):
        problems.append(
            "SpriteLayerManager.gd: enable_layer no longer toggles layers via "
            'set_shader_parameter("wep_enable"/"eff_enable", ...) — the shader '
            "multiplex is the ADR-0019 model, not a node flag."
        )

    # 2a. No scene-tree visibility toggle inside the layer manager.
    for i, line in enumerate(lines, 1):
        if VISIBLE_ASSIGN.search(line):
            problems.append(
                f"SpriteLayerManager.gd:{i}: assigns `.visible` — per-layer "
                "scene-tree visibility is the composition ADR-0019 rejected. "
                "Toggle the shader `*_enable` uniform instead."
            )
        # 2b. No per-layer mesh child constructed by the layer manager.
        if MESHINSTANCE_NEW.search(line):
            problems.append(
                f"SpriteLayerManager.gd:{i}: constructs a MeshInstance3D — layers "
                "compose on ONE mesh per unit (shader slots), not per-layer mesh "
                "children (ADR-0019)."
            )

    # 3. The uniforms are actually read by the unit shader — following its #include
    # chain, since the shader body (with the uniform declarations) lives in a shared
    # .gdshaderinc the thin wrapper includes (da9c37c25).
    shader_src = _shader_text_with_includes(UNIT_SHADER)
    for u in ENABLE_UNIFORMS:
        if not re.search(rf"uniform\s+bool\s+{u}\s*;", shader_src):
            problems.append(
                f"addons/exmateria_sprite_rig/render/unit.gdshader (+ its #includes): no `uniform bool "
                f"{u};` — the layer toggle drives a uniform the shader never reads (ADR-0019)."
            )

    if problems:
        print("ADR-0019 sprite-layers-on-one-mesh violations:")
        for p in problems:
            print(f"  {p}")
        print(
            "\nFix: keep layer composition shader-multiplexed on one mesh per unit — "
            "toggle `wep_enable`/`eff_enable` uniforms, no per-layer Node3D children "
            "or `.visible` flags. See ADR-0019."
        )
        return 1

    print("OK: sprite layers compose on one shader-multiplexed mesh, no scene-tree toggles (ADR-0019).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
