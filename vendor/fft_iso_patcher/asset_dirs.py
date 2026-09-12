"""Standard location for the extracted FFT disc tree.

A single canonical directory that all exmateria-* tools (iso-patcher,
exmateria-sound, daw-plugin) check by default. ``exmateria-extract`` writes
here; the other tools read from here. No env var required for the
typical install.

Layout, from the OS:

    Linux/BSD:  ``$XDG_DATA_HOME/exmateria/assets/``  (default
                ``~/.local/share/exmateria/assets/``)
    macOS:      ``~/Library/Application Support/exmateria/assets/``
    Windows:    ``%APPDATA%\\exmateria\\assets``

The directory contains a verbatim ISO9660 dump of the disc — the same
files you'd get with ``7z x`` or ``mkpsxiso -x``.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def standard_assets_dir() -> Path:
    """Canonical location for the extracted disc tree on this platform."""
    if sys.platform == "win32":
        base = os.environ.get("APPDATA")
        if base:
            return Path(base) / "exmateria" / "assets"
        return Path.home() / "AppData" / "Roaming" / "exmateria" / "assets"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "exmateria" / "assets"
    # Linux / BSD: XDG.
    base = os.environ.get("XDG_DATA_HOME")
    if base:
        return Path(base) / "exmateria" / "assets"
    return Path.home() / ".local" / "share" / "exmateria" / "assets"


def standard_iso_path() -> Path:
    """Canonical location of the cached source FFT ISO.

    ``exmateria-extract`` copies the user's input ISO here so other
    exmateria tools (notably the patcher TUI) can default to it without
    re-prompting the user for a path."""
    return standard_assets_dir().parent / "iso" / "original.bin"


def standard_output_dir() -> Path:
    """Default folder for user-facing artifacts (patched ISOs, recipe
    TOMLs, manifests).

    Lands in the user's Documents folder, not %APPDATA%, so they can
    actually find what the patcher produced. Created on demand."""
    if sys.platform == "win32":
        return Path.home() / "Documents" / "ExMateria"
    if sys.platform == "darwin":
        return Path.home() / "Documents" / "ExMateria"
    # Linux: respect XDG_DOCUMENTS_DIR if the user has one configured.
    xdg = os.environ.get("XDG_DOCUMENTS_DIR")
    if xdg:
        return Path(xdg) / "ExMateria"
    return Path.home() / "Documents" / "ExMateria"
