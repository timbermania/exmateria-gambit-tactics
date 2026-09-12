"""Load screen: pick an input ISO (or an existing recipe TOML)."""

from __future__ import annotations

from pathlib import Path

from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Input, Label, Static

from ...asset_dirs import standard_assets_dir, standard_iso_path, standard_output_dir
from ...extract import extract as run_extract
from ...free_space_survey import survey
from ...iso_sectors import PsxDisc
from ...recipe import load_recipe
from ..paths import normalize_user_path
from ..state import build_slots_from_report


def _default_iso_value() -> str:
    """Pre-fill value for the ISO path input.

    If a previous extract run cached the source ISO at the standard
    location, use that — the user shouldn't have to re-paste a path
    they've already supplied once. Falls back to empty when nothing is
    cached."""
    cached = standard_iso_path()
    return str(cached) if cached.exists() else ""


class LoadScreen(Screen):
    BINDINGS = [
        ("q", "app.quit", "Quit"),
    ]

    def compose(self) -> ComposeResult:
        cached = _default_iso_value()
        intro = (
            "[b]fft_iso_patcher[/b] — load an FFT PSX ISO to begin.\n"
            "Tip: paste a path from your file manager into the box."
        )
        if cached:
            intro = (
                "[b]fft_iso_patcher[/b] — found a cached ISO at the standard "
                "ExMateria location.\nClick [b]Load ISO[/b] to use it, or paste "
                "a different path and click [b]Extract & set as base[/b]."
            )

        yield Header(show_clock=False)
        yield Vertical(
            Static(intro, id="intro"),
            Label("Path to vanilla (or already-patched) FFT BIN:"),
            Input(
                value=cached,
                placeholder="/path/to/Final Fantasy Tactics.bin",
                id="iso-path",
            ),
            Horizontal(
                Button("Load ISO", id="load-iso", variant="primary"),
                Button("Extract & set as base", id="extract-iso"),
                id="iso-buttons",
            ),
            Static("", id="iso-error"),
            Static("─" * 40, classes="divider"),
            Label("Or load an existing recipe TOML to edit:"),
            Input(placeholder="/path/to/recipe.toml", id="recipe-path"),
            Button("Load recipe", id="load-recipe"),
            Static("", id="recipe-error"),
            id="load-body",
        )
        yield Footer()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "load-iso":
            self._load_iso()
        elif event.button.id == "extract-iso":
            self._extract_iso()
        elif event.button.id == "load-recipe":
            self._load_recipe()

    def _err(self, widget_id: str, msg: str) -> None:
        from rich.markup import escape
        self.query_one(f"#{widget_id}", Static).update(f"[red]{escape(msg)}[/red]")

    def _info(self, widget_id: str, msg: str) -> None:
        from rich.markup import escape
        self.query_one(f"#{widget_id}", Static).update(f"[green]{escape(msg)}[/green]")

    def _extract_iso(self) -> None:
        raw = self.query_one("#iso-path", Input).value
        if not raw.strip():
            self._err("iso-error", "Enter a path first.")
            return
        path = normalize_user_path(raw)
        if not path.exists():
            self._err("iso-error", f"No such file: {path}")
            return
        # Bail early if the user has already pointed us at the cached ISO —
        # extracting it onto itself would just churn disk for no reason.
        cached = standard_iso_path()
        if path.resolve() == cached.resolve() and standard_assets_dir().is_dir():
            self._info("iso-error", "Already extracted; click Load ISO to continue.")
            return

        # Disable both action buttons during extract and run in a worker so
        # the UI stays responsive (extract is ~10-20s for a full disc).
        self.query_one("#load-iso", Button).disabled = True
        self.query_one("#extract-iso", Button).disabled = True
        self._info("iso-error", "Extracting…")
        self._run_extract_worker(path)

    @work(thread=True, exclusive=True, group="extract")
    def _run_extract_worker(self, iso_path: Path) -> None:
        """Drive ``extract.extract`` off the UI thread.

        The extractor caches the source ISO at ``standard_iso_path()`` as
        a side effect, so once this finishes the standard ExMateria
        location is up to date and the input field can switch to it.
        """
        out_dir = standard_assets_dir()

        # Coarse progress: bump the status line every 100 files. Calling
        # update from a worker thread is safe for Static widgets because
        # textual marshals widget mutations.
        counter = {"n": 0}

        def on_file(_entry) -> None:
            counter["n"] += 1
            if counter["n"] % 100 == 0:
                self.app.call_from_thread(
                    self._info,
                    "iso-error",
                    f"Extracting… {counter['n']} files",
                )

        try:
            run_extract(iso_path, out_dir, on_file=on_file)
        except Exception as exc:
            self.app.call_from_thread(self._err, "iso-error", f"Extract failed: {exc}")
            self.app.call_from_thread(self._reenable_buttons)
            return

        self.app.call_from_thread(self._extract_done, counter["n"])

    def _extract_done(self, file_count: int) -> None:
        cached = standard_iso_path()
        self.query_one("#iso-path", Input).value = str(cached)
        self._info(
            "iso-error",
            f"Extracted {file_count} files; ISO cached as base. "
            "Click Load ISO to continue.",
        )
        self._reenable_buttons()

    def _reenable_buttons(self) -> None:
        self.query_one("#load-iso", Button).disabled = False
        self.query_one("#extract-iso", Button).disabled = False

    def _load_iso(self) -> None:
        raw = self.query_one("#iso-path", Input).value
        if not raw.strip():
            self._err("iso-error", "Enter a path first.")
            return
        path = normalize_user_path(raw)
        if not path.exists():
            self._err("iso-error", f"No such file: {path}")
            return
        try:
            disc = PsxDisc(path)
        except Exception as exc:
            self._err("iso-error", f"Could not open as PSX BIN: {exc}")
            return
        try:
            report = survey(disc)
        except Exception as exc:
            self._err("iso-error", f"Survey failed: {exc}")
            return

        session = self.app.session
        session.iso_path = path
        session.disc = disc
        session.report = report
        session.slots = build_slots_from_report(report)
        # Default output paths to ~/Documents/ExMateria/ — somewhere the
        # user can actually find. The review screen lets them override.
        out_dir = standard_output_dir()
        out_dir.mkdir(parents=True, exist_ok=True)
        session.output_iso = out_dir / (path.stem + "_patched.bin")
        session.recipe_path = out_dir / (path.stem + "_patched.recipe.toml")
        session.manifest_path = out_dir / (path.stem + "_patched.manifest.json")

        from .slots import SlotsScreen
        self.app.push_screen(SlotsScreen())

    def _load_recipe(self) -> None:
        raw = self.query_one("#recipe-path", Input).value
        if not raw.strip():
            self._err("recipe-error", "Enter a recipe TOML path first.")
            return
        recipe_path = normalize_user_path(raw)
        if not recipe_path.exists():
            self._err("recipe-error", f"No such file: {recipe_path}")
            return
        try:
            recipe = load_recipe(recipe_path)
        except Exception as exc:
            self._err("recipe-error", f"Could not parse recipe: {exc}")
            return
        if not recipe.io.iso_in.exists():
            self._err(
                "recipe-error",
                f"Recipe references missing ISO: {recipe.io.iso_in}",
            )
            return
        try:
            disc = PsxDisc(recipe.io.iso_in)
            report = survey(disc)
        except Exception as exc:
            self._err("recipe-error", f"Could not open referenced ISO: {exc}")
            return

        session = self.app.session
        session.iso_path = recipe.io.iso_in
        session.disc = disc
        session.report = report
        session.slots = build_slots_from_report(report)
        session.output_iso = recipe.io.iso_out
        session.recipe_path = recipe_path
        session.manifest_path = recipe.io.manifest

        # Apply the recipe's existing music patches to the slot table.
        from ..state import SlotInfo
        slots_by_id: dict[int, SlotInfo] = {s.slot: s for s in session.slots}
        for entry in recipe.iter_patches():
            if entry.kind != "music":
                continue
            slot = int(entry.config["slot"])
            file_path = Path(entry.config["file"])
            if not file_path.is_absolute():
                file_path = (recipe_path.parent / file_path).resolve()
            info = slots_by_id.get(slot)
            if info is None or not file_path.exists():
                continue
            info.replacement = file_path
            info.replacement_size = file_path.stat().st_size
            info.replacement_n_sectors = (info.replacement_size + 2047) // 2048

        from .slots import SlotsScreen
        self.app.push_screen(SlotsScreen())
