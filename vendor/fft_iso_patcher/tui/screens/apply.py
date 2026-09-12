"""Apply screen: write the patched ISO and recipe TOML, show progress."""

from __future__ import annotations

from pathlib import Path

from textual.app import ComposeResult
from textual.containers import Vertical
from textual.screen import Screen
from rich.markup import escape
from textual.widgets import Button, Footer, Header, ProgressBar, RichLog, Static
from textual.worker import Worker, WorkerState

from ...patcher import apply_recipe
from ...recipe import FreeSpace
from ...recipe_build import MusicPatchSpec, build_recipe, write_recipe_toml


class ApplyScreen(Screen):
    BINDINGS = [
        ("q", "app.quit", "Quit"),
        ("escape", "back", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        yield Vertical(
            Static("Applying patches...", id="apply-status"),
            ProgressBar(id="apply-progress", show_eta=False),
            RichLog(id="apply-log", highlight=False, markup=True, wrap=False),
            Button("Done", id="btn-done", disabled=True, variant="success"),
            id="apply-body",
        )
        yield Footer()

    def on_mount(self) -> None:
        self._log("Building recipe...")
        self.run_worker(self._do_apply, exclusive=True, thread=True, name="apply")

    def _log(self, line: str) -> None:
        self.query_one("#apply-log", RichLog).write(line)

    def _set_status(self, text: str) -> None:
        self.query_one("#apply-status", Static).update(text)

    def _do_apply(self) -> None:
        sess = self.app.session
        report = sess.report
        assert report is not None and sess.iso_path is not None

        free_space = FreeSpace(
            ranges=tuple(report.candidates),
            reserved_for_shishi=report.shishi_reservation,
        )

        music_patches = [
            MusicPatchSpec(
                slot=s.slot,
                file=s.replacement,
                allow_relocate=True,
            )
            for s in sess.replacements()
        ]

        recipe_path = sess.recipe_path
        assert recipe_path is not None
        recipe = build_recipe(
            iso_in=sess.iso_path,
            iso_out=sess.output_iso,
            manifest=sess.manifest_path,
            free_space=free_space,
            music_patches=music_patches,
            source_path=recipe_path,
        )

        self.app.call_from_thread(
            self._log, f"Writing recipe to {escape(str(recipe_path))}"
        )
        write_recipe_toml(recipe, recipe_path)

        progress_widget: ProgressBar = self.query_one("#apply-progress", ProgressBar)

        def progress(written: int, total: int) -> None:
            def update() -> None:
                progress_widget.total = total or 1
                progress_widget.progress = written
                self._set_status(f"Writing sectors: {written} / {total}")
            self.app.call_from_thread(update)

        try:
            manifest = apply_recipe(recipe, progress=progress)
        except Exception as exc:
            self.app.call_from_thread(
                self._log, f"[red]ERROR: {escape(str(exc))}[/red]"
            )
            self.app.call_from_thread(self._set_status, "[red]Apply failed.[/red]")
            self.app.call_from_thread(self._enable_done)
            return

        def finish() -> None:
            self._set_status(
                f"[green]Done.[/green] {len(manifest.placements)} placement(s)."
            )
            self._log(f"[b]Output ISO:[/b] {escape(str(sess.output_iso))}")
            self._log(f"[b]Recipe:[/b] {escape(str(recipe_path))}")
            if sess.manifest_path:
                self._log(f"[b]Manifest:[/b] {escape(str(sess.manifest_path))}")
            for p in manifest.placements:
                self._log(f"  {escape(str(p))}")
            self._enable_done()
        self.app.call_from_thread(finish)

    def _enable_done(self) -> None:
        btn: Button = self.query_one("#btn-done", Button)
        btn.disabled = False
        btn.focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-done":
            self.app.exit()

    def action_back(self) -> None:
        # Only allow back-out before/after, not while writing.
        worker = next(
            (w for w in self.workers if w.name == "apply"),
            None,
        )
        if worker is not None and worker.state == WorkerState.RUNNING:
            return
        self.app.pop_screen()
