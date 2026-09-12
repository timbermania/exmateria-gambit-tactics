#!/usr/bin/env python3
"""Guard: a fold shader named from GDScript is a `preload`ed `Shader`, never a `String` path.

ADR-0191 dec. 2 refuses a path-taking `Fold.shader()` on a hazard it states plainly:

    a `load()` on a mistyped path returns `null`, and in this subsystem a null shader
    means the fold "just stops, with no error" (tests/FoldSurfaceTest.gd:66-70).

That hazard is a property of NAMING A FOLD SHADER FROM GDSCRIPT. It is not a property of
picking between two of them — the pick is only where dec. 2 happened to meet it, because a
kernel signature was the thing being decided. ADR-0191 dec. 11 separates the two and
states the general rule this guard enforces; see it for why dec. 2's own scope stays the pick
(dec. 8 keeps two `load()`ed fold-shader const blocks on purpose, and Amendment 2 calls that
dec. 2's boundary — neither would be coherent if dec. 2 banned `load()` outright).

WHY A GUARD AND NOT A CONVENTION. This exact class survived a BUILT census, a `/code-review`
and a fix pass: `src/ui3/UIVitalsBand.gd` held its two shaders as `String` consts and resolved
them with `load()` for three reviews after the ADR claimed "19 shader-path String consts on the
pick -> 0" (Amendment 3). Every census that missed it was seeded on the PREDICATE — the one
thing that file never names. This guard is seeded on the SHADERS instead: it reads which files
declare `compositor_layer` and asks who names them, so a producer is visible whether or not it
mentions the fold at all.

WHAT IT SCANS. Every `.gd` under the walk roots PLUS `tools/` and `tests/`. The extra two are
deliberate and are the point of a re-seeded census: `walk_roots()` answers "which source does
this refactor own", and the two capture probes that materialise fold shaders
(tools/probe_demi_engine_fold.gd, tools/probe_occlusion_engine_fold.gd) are outside it. A guard
that scanned only the walk roots would read clean over both — the same shape as the
check_addon_portability blind spot ADR-0191 records but does not fix.

WHAT COUNTS AS A FOLD SHADER. A `.gdshader` whose `render_mode` line declares `compositor_layer`,
matched line-anchored on comment-stripped source, which is the same test check_no_pow_in_fold.py
and tests/FormationFoldRoutingTest.gd use. A comment that merely mentions the word does not
qualify (`unit_flat.gdshader` says it about a different mesh, and Amendment 1 records that
miscounting it wrecked dec. 4's original measurement).

VIOLATION. A `res://....gdshader` literal, in GDScript CODE, naming one of those files, that is
not the argument of a `preload(...)`. Comments and docstrings are stripped first, quote-aware —
a `#` inside a string literal does not start a comment.

ESCAPE HATCH. `# fold-shader-preload-exempt: <reason>` on the offending line or the one above.
There are no exemptions today; if one is ever needed it has to say why in the source.

Exit 0 if clean, 1 on violation. Pure stdlib.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402

# The walk roots say which source the refactor owns; the probes and the producer tests that name
# fold shaders live outside them, and a census that cannot see a caller cannot report it.
SCAN_DIRS = walk_roots() + [PROJECT_DIR / "tools", PROJECT_DIR / "tests"]

EXEMPT = "fold-shader-preload-exempt:"

_FOLD_RENDER_MODE = re.compile(r"^[ \t]*render_mode\b[^;]*\bcompositor_layer\b", re.MULTILINE)
_SHADER_LINE_COMMENT = re.compile(r"//[^\n]*")
_SHADER_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_RES_SHADER = re.compile(r'"(res://[^"]*\.gdshader)"')


def fold_shaders() -> set[str]:
    """Every `res://` path whose file declares `compositor_layer` in a render_mode."""
    found: set[str] = set()
    for root in SCAN_DIRS:
        if not root.is_dir():
            continue
        for f in root.rglob("*.gdshader"):
            src = f.read_text(encoding="utf-8", errors="replace")
            src = _SHADER_BLOCK_COMMENT.sub("", src)
            src = _SHADER_LINE_COMMENT.sub("", src)
            if _FOLD_RENDER_MODE.search(src):
                found.add("res://" + f.relative_to(PROJECT_DIR).as_posix())
    return found


def code_only(line: str) -> str:
    """The line with any GDScript comment removed. Quote-aware: a `#` inside a string is data."""
    quote = ""
    for i, ch in enumerate(line):
        if quote:
            if ch == "\\":
                continue
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i]
    return line


def scan() -> list[str]:
    folds = fold_shaders()
    if not folds:
        # A census that found nothing to protect is a broken census, not a clean bill.
        return ["no `compositor_layer` shader found at all — the scan is looking in the wrong place"]

    problems: list[str] = []
    seen: set[Path] = set()
    for root in SCAN_DIRS:
        if not root.is_dir():
            continue
        for f in sorted(root.rglob("*.gd")):
            if f in seen or ".godot" in f.parts:
                continue
            seen.add(f)
            lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
            for n, raw in enumerate(lines, 1):
                code = code_only(raw)
                for m in _RES_SHADER.finditer(code):
                    if m.group(1) not in folds:
                        continue
                    before = code[: m.start()]
                    if before.rstrip().endswith("preload("):
                        continue
                    context = raw + (lines[n - 2] if n >= 2 else "")
                    if EXEMPT in context:
                        continue
                    rel = f.relative_to(PROJECT_DIR).as_posix()
                    problems.append(
                        f"{rel}:{n}  {m.group(1)} is named as a String, not preload()ed\n"
                        f"        {raw.strip()}"
                    )
    return problems


def main() -> int:
    problems = scan()
    if problems:
        print("check_fold_shader_preload: %d problem(s)" % len(problems))
        for p in problems:
            print("  " + p)
        print()
        print("  A fold shader named from GDScript must be `preload(...)`ed into a `Shader`.")
        print("  A load() of a mistyped path returns null, a null shader does not raise, and the")
        print("  fold just stops with no error. preload makes the same typo a parse error.")
        print("  See ADR-0191 dec. 2 + Amendment 4 §2.")
        return 1
    n = len(fold_shaders())
    print("check_fold_shader_preload: OK — %d fold shaders, every GDScript reference preloaded" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
