"""PatcherApp: the Textual application root."""

from __future__ import annotations

import datetime as _dt
import os
import sys
import traceback
from pathlib import Path

from textual.app import App

from .screens.load import LoadScreen
from .state import Session

# Where crash dumps land. Override with FFT_TUI_CRASH_LOG=/path/to/file.
CRASH_LOG_PATH = Path(
    os.environ.get(
        "FFT_TUI_CRASH_LOG",
        Path.home() / ".cache" / "fft_iso_patcher" / "tui_crash.log",
    )
)


class PatcherApp(App):
    CSS = """
    Screen {
        layers: base modal;
    }
    #intro {
        margin: 1 0;
    }
    .divider {
        color: $accent-darken-2;
        margin: 1 0;
    }
    #status-bar {
        background: $boost;
        padding: 0 1;
    }
    #slots-buttons, #review-buttons, #modal-buttons, #iso-buttons {
        height: 3;
        align-horizontal: left;
    }
    #slots-buttons Button, #review-buttons Button, #modal-buttons Button, #iso-buttons Button {
        margin: 0 1;
    }
    DataTable {
        height: 1fr;
    }
    #apply-log {
        height: 1fr;
        border: solid $accent;
    }
    #apply-progress {
        margin: 1 0;
    }
    #modal-body {
        background: $surface;
        border: thick $accent;
        padding: 1 2;
        width: 70;
        height: auto;
        align: center middle;
    }
    #review-body, #load-body, #apply-body {
        padding: 1 2;
    }
    """

    TITLE = "fft_iso_patcher"
    SUB_TITLE = "PSX Final Fantasy Tactics ISO patcher"

    def __init__(self) -> None:
        super().__init__()
        self.session: Session = Session()

    def on_mount(self) -> None:
        self.push_screen(LoadScreen())
        # If a base ISO has already been extracted to the standard ExMateria
        # location, jump straight to the slots screen — most patcher sessions
        # operate on the same base, so re-prompting is just friction. The
        # LoadScreen stays at the bottom of the stack: hit Esc / pop back to
        # change base or load a recipe.
        self._auto_load_cached_base()

    def _auto_load_cached_base(self) -> None:
        from ..asset_dirs import standard_iso_path, standard_output_dir
        from ..free_space_survey import survey
        from ..iso_sectors import PsxDisc
        from .screens.slots import SlotsScreen
        from .state import build_slots_from_report

        cached = standard_iso_path()
        if not cached.exists():
            return
        try:
            disc = PsxDisc(cached)
            report = survey(disc)
        except Exception:
            # Cache unreadable / bad — fall through to LoadScreen so the user
            # can re-extract or pick a different ISO.
            return

        self.session.iso_path = cached
        self.session.disc = disc
        self.session.report = report
        self.session.slots = build_slots_from_report(report)
        # Output goes to ~/Documents/ExMateria/ rather than next to the
        # cached ISO (%APPDATA%), so the user can actually find it.
        out_dir = standard_output_dir()
        out_dir.mkdir(parents=True, exist_ok=True)
        self.session.output_iso = out_dir / (cached.stem + "_patched.bin")
        self.session.recipe_path = out_dir / (cached.stem + "_patched.recipe.toml")
        self.session.manifest_path = out_dir / (cached.stem + "_patched.manifest.json")

        self.push_screen(SlotsScreen())

    def _handle_exception(self, error: Exception) -> None:
        """Override Textual's panic handler to also dump a crash log to disk.

        Textual already logs the traceback to stderr after the TUI tears
        down; this just adds a file we can both read after the fact (the
        scrollback gets clipped on long tracebacks)."""
        try:
            CRASH_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
            with CRASH_LOG_PATH.open("a", encoding="utf-8") as f:
                ts = _dt.datetime.now().isoformat(timespec="seconds")
                f.write(f"\n{'=' * 70}\n")
                f.write(f"crash at {ts}\n")
                f.write(f"argv:    {sys.argv}\n")
                f.write(f"cwd:     {Path.cwd()}\n")
                f.write(f"session: iso={self.session.iso_path} "
                        f"out={self.session.output_iso} "
                        f"replacements={len(self.session.replacements())}\n")
                f.write(f"screen:  {type(self.screen).__name__ if self.screen else None}\n")
                f.write(f"error:   {type(error).__name__}: {error}\n\n")
                traceback.print_exception(type(error), error, error.__traceback__, file=f)
            try:
                # Surface the dump path to stderr so the user sees where to look
                # once Textual has restored the terminal.
                sys.stderr.write(
                    f"\n[fft_iso_patcher] crash log written to {CRASH_LOG_PATH}\n"
                )
            except Exception:
                pass
        except Exception:
            # Never let dump-writing itself crash the panic handler.
            pass
        super()._handle_exception(error)
