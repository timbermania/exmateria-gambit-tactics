#!/usr/bin/env python3
"""Guard: a class that submits/syncs a RenderingDevice must never obtain one from
`RenderingServer.get_rendering_device()`.

Godot has two kinds of RenderingDevice. `create_local_rendering_device()` returns a LOCAL one the
caller owns and may drive by hand. `get_rendering_device()` returns the GLOBAL one, owned by the
renderer, which rejects manual submission — `RenderingDevice::submit`/`sync` refuse any non-local
device with `Only local devices can submit and sync.` (rendering_device.cpp).

The two are interchangeable at the type level and NOT at the behaviour level, so a
`create_local_rendering_device() or get_rendering_device()` fallback compiles, type-checks, reads as
defensive, and is a silent failure: when the local device cannot be allocated (VRAM exhaustion) the
class picks up a device it can record a compute list onto and can never drive. That fallback lived
in `GPUBatchSimulator.initialize()` and made `initialize()` return TRUE on a dead simulator —
`GambitScenarioRunnerTest` printed `82 scenarios green` over **43,492** device errors (#430) and
`GPUArenaTest` printed `[PASS]` over **5,698** (#547). The verdict was not wrong about the run; the
run was not about the code.

Using the global device is perfectly legitimate for code that never drives it by hand — reading
back a buffer, updating a MultiMesh, sizing a texture. `EffectMultiMeshPool.gd` and
`FoldSurface.gd` do exactly that and are correctly clean under this rule. What is never legitimate
is holding the global device AND calling submit/sync on it.

So the invariant is a per-file co-occurrence, not a ban on either half:

    a .gd that calls `.submit(` or `.sync(`  MUST NOT call `get_rendering_device(`

Comments and string/docstring literals are blanked before scanning, so the prose explaining the rule
(including this file's own sibling comments in GPUBatchSimulator) cannot satisfy or trip it. A
genuine, justified occurrence opts out with an inline `# global-rd-exempt: <reason>` on the line.

Exit 0 clean, 1 on violation. Pure stdlib.

Run:
    uv run python tools/check_no_global_rd_for_compute.py
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent

# Roots scanned for .gd sources. `addons/` is frequently a SYMLINK in a linked worktree, so the walk
# below follows links (Path.rglob does not) — otherwise a linked checkout silently scans ~8 files
# where the canonical one scans ~164 and the guard goes green by seeing nothing.
SCAN_ROOTS = ("src", "tests", "addons")

EXEMPT = "global-rd-exempt:"

# The global device getter. Matched on the method name alone: it is reached as
# `RenderingServer.get_rendering_device()` today, but an alias or a cached `RenderingServer` local
# would still spell the method the same way.
_GLOBAL_RD = re.compile(r"\bget_rendering_device\s*\(")

# Manual submission. Both halves of the pair are matched — #430's errors came from `submit` at :936
# AND `sync` at :937 — so killing one call does not disarm the guard.
_DRIVE = re.compile(r"\.\s*(?:submit|sync)\s*\(")


def strip_code_lines(text: str) -> list[tuple[int, str, str]]:
    """Return (lineno, raw_line, code_only) per physical line, with `#` comments and string /
    triple-quoted-docstring literals blanked out so only executable code is scanned."""
    out: list[tuple[int, str, str]] = []
    in_triple: str | None = None  # the closing delim we're waiting for (\"\"\" or ''')
    for i, raw in enumerate(text.splitlines(), 1):
        code_chars: list[str] = []
        j = 0
        n = len(raw)
        in_str: str | None = None  # single/double quote we're inside on THIS line
        while j < n:
            three = raw[j:j + 3]
            if in_triple is not None:
                if three == in_triple:
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
            if three in ('"""', "'''"):
                in_triple = three
                j += 3
                continue
            if raw[j] in ('"', "'"):
                in_str = raw[j]
                j += 1
                continue
            if raw[j] == "#":
                break  # rest of the line is a comment
            code_chars.append(raw[j])
            j += 1
        out.append((i, raw, "".join(code_chars)))
    return out


def scan_source(text: str) -> tuple[list[tuple[int, str]], list[tuple[int, str]]]:
    """Return (global_rd_hits, drive_hits) as (lineno, raw_line), comments/strings stripped and
    `# global-rd-exempt:` lines skipped."""
    global_hits: list[tuple[int, str]] = []
    drive_hits: list[tuple[int, str]] = []
    for lineno, raw, code in strip_code_lines(text):
        if EXEMPT in raw:
            continue
        if _GLOBAL_RD.search(code):
            global_hits.append((lineno, raw.strip()))
        if _DRIVE.search(code):
            drive_hits.append((lineno, raw.strip()))
    return global_hits, drive_hits


def iter_gd_files(project_dir: Path):
    """Yield every .gd under SCAN_ROOTS, following symlinked roots."""
    seen: set[Path] = set()
    for root in SCAN_ROOTS:
        base = project_dir / root
        if not base.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(base, followlinks=True):
            dirnames[:] = [d for d in dirnames if d != ".godot"]
            for fn in filenames:
                if not fn.endswith(".gd"):
                    continue
                p = Path(dirpath) / fn
                real = p.resolve()
                if real in seen:
                    continue
                seen.add(real)
                yield p


def main() -> int:
    scanned = 0
    violations: list[str] = []
    for path in iter_gd_files(PROJECT_DIR):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        scanned += 1
        global_hits, drive_hits = scan_source(text)
        if not (global_hits and drive_hits):
            continue
        try:
            rel = path.relative_to(PROJECT_DIR)
        except ValueError:
            rel = path
        detail = [f"{rel}: holds the GLOBAL device AND drives it by hand"]
        for lineno, raw in global_hits:
            detail.append(f"    global device  {rel}:{lineno}: {raw}")
        for lineno, raw in drive_hits:
            detail.append(f"    driven         {rel}:{lineno}: {raw}")
        violations.append("\n".join(detail))

    print(f".gd files scanned: {scanned}")
    if violations:
        print("\na RenderingDevice obtained from the renderer is being submitted/synced by hand:")
        for v in violations:
            print(f"  {v}")
        print(
            "\nRenderingServer.get_rendering_device() returns the GLOBAL device, which rejects\n"
            "submit()/sync() with `Only local devices can submit and sync.` — a class holding it can\n"
            "record a compute list and never drive it, while initialize() reports success. Use\n"
            "create_local_rendering_device() with NO fallback and fail hard when it returns null\n"
            "(#430, #547). If an occurrence is genuinely correct, mark the line\n"
            "`# global-rd-exempt: <reason>`."
        )
        return 1

    print("OK: no .gd both holds the renderer's global device and submits/syncs it — every\n"
          "     hand-driven RenderingDevice is a local one.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
