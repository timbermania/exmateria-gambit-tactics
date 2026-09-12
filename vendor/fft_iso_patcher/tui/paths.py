"""Path-string normalization for user-pasted paths in the TUI.

Users paste paths from whichever environment they happen to be in — a
Windows file manager, a WSL shell, a native Linux desktop. This module
funnels every input through one resolver that picks the right
interpretation for the current platform.

Three platform paths (variants try in order; first one that exists wins):

- **Windows native** (the PyInstaller .exe build):
    1. The path as given (Windows happily accepts forward slashes).
    2. ``/mnt/c/foo`` style → ``C:\\foo`` (in case the user pastes a
       WSL path on a Windows-native run).
- **WSL** (``/proc/version`` contains "microsoft"):
    1. The path as given.
    2. ``C:\\Users\\you\\foo.bin`` → ``/mnt/c/Users/you/foo.bin``
       (and ``C:/Users/you/foo.bin`` likewise).
- **Linux / macOS native**: as given.

In every environment ``~`` is expanded and surrounding quotes/whitespace
stripped.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

_DRIVE_LETTER_RE = re.compile(r"^([A-Za-z]):[/\\](.*)$", re.DOTALL)
_MNT_DRIVE_RE = re.compile(r"^/mnt/([a-zA-Z])/(.*)$")


def _is_wsl() -> bool:
    """True when running inside WSL — i.e. Linux kernel reports microsoft."""
    if sys.platform != "linux":
        return False
    try:
        with open("/proc/version", "r", encoding="utf-8") as fh:
            return "microsoft" in fh.read().lower()
    except OSError:
        return False


def _strip_quotes(s: str) -> str:
    s = s.strip()
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        s = s[1:-1]
    return s


def _candidates(raw: str) -> list[Path]:
    """Generate the platform-correct list of paths to try, in priority order."""
    s = _strip_quotes(raw)
    candidates: list[Path] = []

    if sys.platform == "win32":
        # Native Windows. The given string is most likely already correct.
        candidates.append(Path(s).expanduser())
        # Fallback: user pasted a WSL-form path on a Windows native run.
        m = _MNT_DRIVE_RE.match(s)
        if m:
            drive, rest = m.group(1).upper(), m.group(2)
            candidates.append(Path(f"{drive}:\\{rest.replace('/', os.sep)}").expanduser())
        return candidates

    if _is_wsl():
        # WSL. Prefer the given path first, then convert C:\ / C:/ → /mnt/c/.
        candidates.append(Path(s).expanduser())
        m = _DRIVE_LETTER_RE.match(s)
        if m:
            drive, rest = m.group(1).lower(), m.group(2).replace("\\", "/")
            candidates.append(Path(f"/mnt/{drive}/{rest}").expanduser())
        return candidates

    # Plain POSIX. Just expand ~.
    candidates.append(Path(s).expanduser())
    return candidates


def normalize_user_path(raw: str) -> Path:
    """Coerce a user-typed path string into a usable Path.

    Tries platform-correct interpretations in order; returns the first
    one that exists on disk. If none exist, returns the first candidate
    (so callers' subsequent ``.exists()`` check produces the right
    error message). One funnel for every Input in the TUI.
    """
    candidates = _candidates(raw)
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0] if candidates else Path(raw)
