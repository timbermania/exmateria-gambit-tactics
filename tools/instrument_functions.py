#!/usr/bin/env python3
"""Runtime function tracer instrumentation tool.

Instruments every GDScript function in src/ with a first-call-only tracker,
then compares traced functions against all functions to find dead code.

Usage:
    uv run python tools/instrument_functions.py --scan     # Dry-run: list all functions
    uv run python tools/instrument_functions.py --inject   # Add tracers + autoload
    uv run python tools/instrument_functions.py --remove   # Remove all tracers + autoload
    uv run python tools/instrument_functions.py --report   # Dead code report from trace
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
SRC_DIR = PROJECT_ROOT / "src"
PROJECT_GODOT = PROJECT_ROOT / "project.godot"
PROJECT_NAME = "learning"

SKIP_FILES = {"FuncTracer.gd", "FuncTracerDumper.gd"}
MARKER = "# @ft"
AUTOLOAD_LINE = 'FuncTracerDumper="*res://src/debug/FuncTracerDumper.gd"'

# Godot virtual methods called automatically by the engine
VIRTUAL_METHODS = {
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_enter_tree", "_exit_tree", "_notification",
    "_draw", "_gui_input", "_init", "_to_string", "_get_configuration_warnings",
    "_get_property_list", "_property_can_revert", "_property_get_revert",
    "_set", "_get", "_validate_property",
}


def get_gd_files() -> list[Path]:
    """Get all .gd files in src/, excluding tracer files."""
    files = sorted(SRC_DIR.rglob("*.gd"))
    return [f for f in files if f.name not in SKIP_FILES]


def extract_class_name(lines: list[str], filepath: Path) -> str:
    """Extract class_name from file, or derive from filename."""
    for line in lines:
        m = re.match(r"^class_name\s+(\w+)", line)
        if m:
            return m.group(1)
    return filepath.stem


def _strip_trailing_comment(s: str) -> str:
    """Remove trailing # comment, respecting string literals."""
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


def _sig_complete(line: str) -> bool:
    """Check if a line completes a function signature (ends with ':')."""
    return _strip_trailing_comment(line.rstrip()).endswith(":")


def scan_file(filepath: Path) -> list[dict]:
    """Parse a GDScript file and return list of function info dicts.

    Each dict has: name, file, sig_line (1-indexed), inject_after_line (1-indexed),
    body_indent (whitespace string).
    """
    text = filepath.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)

    outer_name = extract_class_name(lines, filepath)

    # Stack of (class_name, definition_indent_chars)
    # The outer class has indent -1 so nothing pops it
    class_stack: list[tuple[str, int]] = [(outer_name, -1)]

    functions = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip()

        # Skip blank lines and pure comment lines
        if not stripped or stripped.lstrip().startswith("#"):
            i += 1
            continue

        raw_indent = len(line) - len(line.lstrip())

        # Pop inner classes whose scope we've left
        while len(class_stack) > 1 and raw_indent <= class_stack[-1][1]:
            class_stack.pop()

        # Inner class definition: `class Foo:` or `class Foo extends Bar:`
        m = re.match(r"^(\s*)class\s+(\w+)", line)
        if m and not stripped.lstrip().startswith("class_name"):
            class_stack.append((m.group(2), len(m.group(1))))
            i += 1
            continue

        # Function definition: `func name(` or `static func name(`
        m = re.match(r"^(\s*)(static\s+)?func\s+(\w+)\s*\(", line)
        if m:
            func_indent_str = m.group(1)
            func_name = m.group(3)

            # Build qualified name from class stack
            qualified = ".".join(c[0] for c in class_stack) + "." + func_name

            # Find end of signature (line ending with ':')
            sig_end = i
            while sig_end < len(lines):
                if _sig_complete(lines[sig_end]):
                    break
                sig_end += 1

            if sig_end >= len(lines):
                # Malformed signature, skip
                i += 1
                continue

            # Find first non-blank body line to determine indent
            body_line_idx = sig_end + 1
            while body_line_idx < len(lines) and not lines[body_line_idx].strip():
                body_line_idx += 1

            if body_line_idx < len(lines):
                body_line = lines[body_line_idx]
                body_indent = body_line[: len(body_line) - len(body_line.lstrip())]
                # Sanity check: body should be indented deeper than function
                if len(body_indent) <= len(func_indent_str):
                    body_indent = func_indent_str + "\t"
            else:
                body_indent = func_indent_str + "\t"

            functions.append(
                {
                    "name": qualified,
                    "file": str(filepath),
                    "sig_line": i + 1,  # 1-indexed
                    "inject_after_line": sig_end + 1,  # 1-indexed
                    "body_indent": body_indent,
                }
            )

            i = sig_end + 1
            continue

        i += 1

    return functions


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def cmd_scan(args: argparse.Namespace) -> None:
    """Dry-run: show all detected functions."""
    files = get_gd_files()
    total = 0
    for filepath in files:
        funcs = scan_file(filepath)
        rel = filepath.relative_to(PROJECT_ROOT)
        for f in funcs:
            print(f"  {rel}:{f['sig_line']}  {f['name']}")
        total += len(funcs)
    print(f"\n{total} functions in {len(files)} files")


def cmd_inject(args: argparse.Namespace) -> None:
    """Add FuncTracer.t() calls to the top of every function body."""
    files = get_gd_files()
    total_injected = 0
    files_modified = 0

    for filepath in files:
        funcs = scan_file(filepath)
        if not funcs:
            continue

        text = filepath.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)

        # Skip if already injected
        if any(MARKER in line for line in lines):
            rel = filepath.relative_to(PROJECT_ROOT)
            print(f"  SKIP (already injected): {rel}")
            continue

        # Inject in reverse order so line numbers stay valid
        for func_info in reversed(funcs):
            # inject_after_line is 1-indexed, the signature end line
            insert_idx = func_info["inject_after_line"]  # 0-indexed position after sig
            indent = func_info["body_indent"]
            tracer_call = f'{indent}FuncTracer.t("{func_info["name"]}")  {MARKER}\n'
            lines.insert(insert_idx, tracer_call)
            total_injected += 1

        filepath.write_text("".join(lines), encoding="utf-8")
        files_modified += 1

    # Add autoload to project.godot
    _add_autoload()

    print(f"\nInjected {total_injected} tracers in {files_modified} files")
    print("Added FuncTracerDumper autoload to project.godot")


def cmd_remove(args: argparse.Namespace) -> None:
    """Remove all FuncTracer.t() lines and the autoload entry."""
    files = list(SRC_DIR.rglob("*.gd"))
    total_removed = 0
    files_modified = 0

    for filepath in files:
        text = filepath.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)

        new_lines = [line for line in lines if MARKER not in line]
        removed = len(lines) - len(new_lines)
        if removed > 0:
            filepath.write_text("".join(new_lines), encoding="utf-8")
            total_removed += removed
            files_modified += 1

    _remove_autoload()

    print(f"Removed {total_removed} tracer lines from {files_modified} files")
    print("Removed FuncTracerDumper autoload from project.godot")


def cmd_report(args: argparse.Namespace) -> None:
    """Read trace dump, compare against all functions, report dead code."""
    trace_path = _find_trace_file()
    if not trace_path:
        print("ERROR: func_trace.txt not found.")
        print("Run the game first and press F4 (or just quit) to dump the trace.")
        sys.exit(1)

    # Read traced function signatures
    traced = set(trace_path.read_text(encoding="utf-8").strip().splitlines())
    print(f"Traced: {len(traced)} called functions")

    # Scan all functions
    files = get_gd_files()
    all_funcs: list[dict] = []
    for filepath in files:
        funcs = scan_file(filepath)
        for func_info in funcs:
            func_info["rel_path"] = str(filepath.relative_to(PROJECT_ROOT))
            all_funcs.append(func_info)

    print(f"Total:  {len(all_funcs)} functions in {len(files)} files")

    # Find uncalled functions
    uncalled = [f for f in all_funcs if f["name"] not in traced]
    called_count = len(all_funcs) - len(uncalled)
    print(f"Called: {called_count}")
    print(f"Uncalled: {len(uncalled)}\n")

    if not uncalled:
        print("No dead code candidates found!")
        return

    # Build reference index: read all .gd and .tscn files once
    file_contents = _load_file_contents()

    # Categorize uncalled functions
    definitely_dead: list[dict] = []
    likely_dead: list[dict] = []
    needs_review: list[dict] = []

    for func_info in uncalled:
        base_name = func_info["name"].rsplit(".", 1)[-1]
        is_virtual = base_name in VIRTUAL_METHODS or base_name.startswith("_on_")

        has_refs = _has_code_references(base_name, func_info["file"], file_contents)

        if is_virtual:
            needs_review.append(func_info)
        elif has_refs:
            likely_dead.append(func_info)
        else:
            definitely_dead.append(func_info)

    # Print report
    if definitely_dead:
        print(f"=== DEFINITELY DEAD ({len(definitely_dead)}) ===")
        print("Uncalled AND zero code references\n")
        for f in definitely_dead:
            print(f"  {f['rel_path']}:{f['sig_line']}  {f['name']}")
        print()

    if likely_dead:
        print(f"=== LIKELY DEAD ({len(likely_dead)}) ===")
        print("Uncalled but has code references (may be unreachable path)\n")
        for f in likely_dead:
            print(f"  {f['rel_path']}:{f['sig_line']}  {f['name']}")
        print()

    if needs_review:
        print(f"=== NEEDS REVIEW ({len(needs_review)}) ===")
        print("Uncalled virtuals (_ready, _process) or signal handlers (_on_*)\n")
        for f in needs_review:
            print(f"  {f['rel_path']}:{f['sig_line']}  {f['name']}")
        print()

    print("--- Summary ---")
    print(f"Called:          {called_count}")
    print(f"Definitely dead: {len(definitely_dead)}")
    print(f"Likely dead:     {len(likely_dead)}")
    print(f"Needs review:    {len(needs_review)}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load_file_contents() -> dict[str, str]:
    """Read all .gd and .tscn files into memory for reference checking."""
    contents: dict[str, str] = {}
    for pattern in ("**/*.gd", "**/*.tscn"):
        for filepath in PROJECT_ROOT.glob(pattern):
            # Skip .godot cache directory
            if ".godot" in filepath.parts:
                continue
            try:
                contents[str(filepath)] = filepath.read_text(encoding="utf-8")
            except Exception:
                pass
    return contents


def _has_code_references(
    func_name: str, source_file: str, file_contents: dict[str, str]
) -> bool:
    """Check if func_name appears in any file besides its own definition."""
    pattern = re.compile(r"\b" + re.escape(func_name) + r"\b")
    source_abs = os.path.abspath(source_file)
    for fpath, text in file_contents.items():
        if os.path.abspath(fpath) == source_abs:
            continue
        if pattern.search(text):
            return True
    return False


def _find_trace_file() -> Path | None:
    """Find func_trace.txt in Godot user data directory."""
    # Try WSL Windows path
    try:
        result = subprocess.run(
            ["cmd.exe", "/c", "echo", "%USERNAME%"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        win_user = result.stdout.strip()
        if win_user and win_user != "%USERNAME%":
            path = Path(
                f"/mnt/c/Users/{win_user}/AppData/Roaming/Godot/app_userdata/{PROJECT_NAME}/func_trace.txt"
            )
            if path.exists():
                return path
    except Exception:
        pass

    # Try Linux path
    xdg_data = os.environ.get(
        "XDG_DATA_HOME", os.path.expanduser("~/.local/share")
    )
    path = Path(xdg_data) / "godot" / "app_userdata" / PROJECT_NAME / "func_trace.txt"
    if path.exists():
        return path

    return None


def _add_autoload() -> None:
    """Add FuncTracerDumper autoload to project.godot."""
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    if "FuncTracerDumper" in text:
        return

    lines = text.splitlines(keepends=True)
    last_autoload_idx = None

    for i, line in enumerate(lines):
        # Find last existing autoload entry
        if '="*res://' in line:
            last_autoload_idx = i

    if last_autoload_idx is not None:
        lines.insert(last_autoload_idx + 1, AUTOLOAD_LINE + "\n")
        PROJECT_GODOT.write_text("".join(lines), encoding="utf-8")


def _remove_autoload() -> None:
    """Remove FuncTracerDumper autoload from project.godot."""
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    if "FuncTracerDumper" not in text:
        return

    lines = text.splitlines(keepends=True)
    new_lines = [line for line in lines if "FuncTracerDumper" not in line]
    PROJECT_GODOT.write_text("".join(new_lines), encoding="utf-8")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Runtime function tracer instrumentation for dead code detection"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--scan", action="store_true", help="Dry-run: show all detected functions"
    )
    group.add_argument(
        "--inject", action="store_true", help="Add FuncTracer.t() to all functions"
    )
    group.add_argument(
        "--remove", action="store_true", help="Remove all tracer lines and autoload"
    )
    group.add_argument(
        "--report",
        action="store_true",
        help="Generate dead code report from trace dump",
    )

    args = parser.parse_args()

    if args.scan:
        cmd_scan(args)
    elif args.inject:
        cmd_inject(args)
    elif args.remove:
        cmd_remove(args)
    elif args.report:
        cmd_report(args)


if __name__ == "__main__":
    main()
