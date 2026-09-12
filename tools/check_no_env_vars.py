#!/usr/bin/env python3
"""Enforce the "no env vars for scene configuration" ban (ADR-0051).

Scene-level configuration MUST flow through the F3 DebugOverlay panel system,
not `OS.get_environment(...)` reads. Env-as-config is invisible in the editor
and leaks across shell sessions — the concrete bug ADR-0051 was written to kill
(a stale `SCENARIO_*` export silently quit a scene at PC 42). This is the config
analogue of check_par_shaders.py / check_depth_shaders.py: a cheap text net that
makes "just check an env var" impossible to ship into `src/` or `tests/`.

Both `OS.get_environment(` and `OS.has_environment(` are banned. A genuine need
to read process state (e.g. headless-vs-headful detection) — NOT a `SCENARIO_*`
scene toggle — may opt out with an explicit, greppable marker on the same line:
    OS.has_environment("CI")  # env-var-exempt: <reason>
Per the ADR, that escape hatch is a code-review call, not a routine convenience.

Scans every `.gd` under src/ and tests/. Exit 0 if clean, 1 if any violation.
Pure stdlib.
"""
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
# ADR-0148 dec. 3: a guard's scan root is a WALK. `src` alone stops covering a file
# the moment the refactor extracts it, SILENTLY — see tools/_walk_roots.py.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _walk_roots import walk_roots  # noqa: E402
SCAN_DIRS = walk_roots() + [PROJECT_DIR / "tests"]
EXEMPT = "env-var-exempt:"
BANNED = re.compile(r"\bOS\.(get|has)_environment\s*\(")


def check_file(path: Path) -> list[str]:
    problems = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("#", 1)[0]  # strip line comment before matching
        if BANNED.search(code) and EXEMPT not in line:
            problems.append(f"{lineno}: {line.strip()}")
    return problems


def main() -> int:
    violations = {}
    for sub in SCAN_DIRS:
        root = sub
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.gd")):
            problems = check_file(path)
            if problems:
                violations[path.relative_to(PROJECT_DIR)] = problems

    if violations:
        print("ADR-0051 env-var-as-config violations (OS.get/has_environment in src/ or tests/):")
        for rel, problems in violations.items():
            for p in problems:
                print(f"  {rel}:{p}")
        print(
            "\nFix: route the toggle through an F3 debug panel (a BaseDebugPanel "
            "subclass registered via DebugOverlay.register_panel), and have "
            "automation invoke a method on the scene/panel — not an env var. "
            "See ADR-0051 and docs/debug-panels.md. For a genuine process-state "
            f"read (not a scene toggle), add a `# {EXEMPT} <reason>` marker."
        )
        return 1

    print("OK: no OS.get/has_environment scene-config reads in the walk or tests/ (ADR-0051).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
