#!/usr/bin/env python3
"""Delete dead GDScript functions identified by tombstone tracing.

Uses the func_trace.txt from runtime tracing combined with static reference
analysis (from instrument_functions.py --report) to identify definitely dead
functions, then removes them from the source files.

Usage:
    python3 tools/delete_dead_code.py --dry-run    # Show what would be deleted
    python3 tools/delete_dead_code.py               # Delete dead functions
"""

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent

# Files to never modify (standalone test scenes, PSXDitherCurves, debug panels)
KEEP_FILES = {
    "ProgressionTester.gd", "SequenceViewer.gd", "EffectViewerScene.gd",
    "ProjectileTester.gd", "CombatUITestScene.gd", "CombatUIDebugPanel.gd",
    "UICompileTest.gd", "PSXDitherCurves.gd",
    "EffectViewerPanel.gd", "ProgressionDebugPanel.gd",
    "FuncTracer.gd", "FuncTracerDumper.gd",
    "UIInteractionTest.gd", "ProgressionTesterTest.gd",
}


def strip_trailing_comment(s: str) -> str:
    in_str = None
    for i, ch in enumerate(s):
        if in_str:
            if ch == in_str:
                in_str = None
        elif ch in "\"'":
            in_str = ch
        elif ch == "#":
            return s[:i].rstrip()
    return s


def sig_complete(line: str) -> bool:
    return strip_trailing_comment(line.rstrip()).endswith(":")


def called_from_live_code(func_name: str, filepath: str, dead_funcs: set[str]) -> bool:
    """Check if func_name is called from any live code in the same file.

    Live code includes: non-dead functions, property setters, top-level class body
    (@onready, signal connections, etc.). A dead function only called from other
    dead functions is safe to delete (the whole chain is dead).
    """
    func_def_re = re.compile(r"^(static\s+)?func\s+(\w+)\s*\(")
    text = Path(filepath).read_text(encoding="utf-8")
    lines = text.splitlines()
    pat = re.compile(r"\b" + re.escape(func_name) + r"\b")

    current_func = None
    current_indent = 0

    for line in lines:
        stripped = line.lstrip()
        m = func_def_re.match(stripped)
        if m:
            current_func = m.group(2)
            current_indent = len(line) - len(stripped)
            continue

        # Skip FuncTracer instrumentation lines everywhere
        if "FuncTracer.t(" in line:
            continue

        if current_func:
            # Check if we've left the function body
            if stripped and not stripped.startswith("#"):
                line_indent = len(line) - len(stripped)
                if line_indent <= current_indent:
                    current_func = None
                    # Fall through to top-level check below

            if current_func:
                # Skip if we're inside the dead function's own body
                if current_func == func_name:
                    continue

                # Skip if the caller is also dead (dead-to-dead chain)
                if current_func in dead_funcs:
                    continue

                # Live function references func_name — keep it
                if pat.search(line):
                    return True
                continue

        # Top-level code: property setters, @onready, class body — all live
        # Skip the dead function's own definition line
        if func_def_re.match(stripped) and stripped.split("(")[0].endswith(func_name):
            continue
        if pat.search(line):
            return True

    return False


def get_dead_functions_from_report() -> dict[str, list[str]]:
    """Run instrument_functions.py --report and parse definitely-dead functions.

    Filters to only functions with zero internal references (truly dead).
    Returns dict mapping filepath -> list of function names to delete.
    """
    result = subprocess.run(
        [sys.executable, str(PROJECT_ROOT / "tools" / "instrument_functions.py"), "--report"],
        capture_output=True, text=True, cwd=str(PROJECT_ROOT),
    )
    output = result.stdout + result.stderr

    # Parse the report's "definitely dead" section
    candidates: list[tuple[str, str]] = []  # (filepath, func_name)
    in_dead = False

    for line in output.splitlines():
        stripped = line.strip()
        if "DEFINITELY DEAD" in stripped:
            in_dead = True
            continue
        if in_dead and stripped.startswith("==="):
            break
        if in_dead and stripped.startswith("src/"):
            parts = stripped.split()
            if len(parts) >= 2:
                filepath = parts[0].rsplit(":", 1)[0]
                qualified = parts[1]
                func_name = qualified.rsplit(".", 1)[-1]
                filename = filepath.split("/")[-1]
                if filename not in KEEP_FILES:
                    candidates.append((filepath, func_name))

    # Group candidates by file so we know the dead set per file
    candidates_by_file: dict[str, list[str]] = defaultdict(list)
    for filepath, func_name in candidates:
        candidates_by_file[filepath].append(func_name)

    # Iteratively filter: remove functions called from live code, shrink dead set,
    # repeat until stable. This handles chains like _ready -> A -> B where A is
    # initially in the dead set but gets kept, which should also keep B.
    skipped = 0
    for filepath, func_names in candidates_by_file.items():
        full_path = PROJECT_ROOT / filepath
        if not full_path.exists():
            continue
        dead_set = set(func_names)
        changed = True
        while changed:
            changed = False
            for func_name in list(dead_set):
                if called_from_live_code(func_name, str(full_path), dead_set):
                    dead_set.discard(func_name)
                    skipped += 1
                    changed = True
        candidates_by_file[filepath] = list(dead_set)

    by_file: dict[str, list[str]] = defaultdict(list)
    for filepath, func_names in candidates_by_file.items():
        if func_names:
            by_file[filepath] = func_names

    if skipped:
        print(
            f"Skipped {skipped} functions called from live code", file=sys.stderr
        )

    return dict(by_file)


def remove_functions(filepath: Path, func_names: list[str]) -> int:
    """Remove specified functions from file. Returns count removed."""
    text = filepath.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    to_delete = set(func_names)

    result: list[str] = []
    i = 0
    deleted = 0

    while i < len(lines):
        m = re.match(r"^(\s*)(static\s+)?func\s+(\w+)\s*\(", lines[i])
        if m and m.group(3) in to_delete:
            func_indent = len(m.group(1))
            # Skip function signature (possibly multi-line)
            while i < len(lines) and not sig_complete(lines[i]):
                i += 1
            i += 1  # past the ':' line

            # Skip body (lines indented deeper than func, or blank)
            while i < len(lines):
                if lines[i].strip() == "":
                    i += 1
                else:
                    line_indent = len(lines[i]) - len(lines[i].lstrip())
                    if line_indent > func_indent:
                        i += 1
                    else:
                        break

            deleted += 1
        else:
            result.append(lines[i])
            i += 1

    # Collapse runs of >2 consecutive blank lines to 2
    cleaned: list[str] = []
    blank_run = 0
    for line in result:
        if line.strip() == "":
            blank_run += 1
            if blank_run <= 2:
                cleaned.append(line)
        else:
            blank_run = 0
            cleaned.append(line)

    # Trim trailing blank lines
    while cleaned and cleaned[-1].strip() == "":
        cleaned.pop()
    if cleaned and not cleaned[-1].endswith("\n"):
        cleaned[-1] += "\n"

    filepath.write_text("".join(cleaned), encoding="utf-8")
    return deleted


def main() -> None:
    dry_run = "--dry-run" in sys.argv

    print("Getting dead functions from tombstone report...", file=sys.stderr)
    dead_by_file = get_dead_functions_from_report()

    total = sum(len(v) for v in dead_by_file.values())
    print(f"Found {total} dead functions in {len(dead_by_file)} files", file=sys.stderr)

    total_deleted = 0
    for filepath_str in sorted(dead_by_file):
        func_names = dead_by_file[filepath_str]
        filepath = PROJECT_ROOT / filepath_str

        if not filepath.exists():
            print(f"  SKIP (not found): {filepath_str}", file=sys.stderr)
            continue

        if dry_run:
            print(f"{filepath_str}: {len(func_names)} dead: {', '.join(func_names)}")
        else:
            count = remove_functions(filepath, func_names)
            print(f"{filepath_str}: deleted {count}: {', '.join(func_names)}")

        total_deleted += len(func_names)

    action = "Would delete" if dry_run else "Deleted"
    print(f"\n{action} {total_deleted} functions", file=sys.stderr)


if __name__ == "__main__":
    main()
