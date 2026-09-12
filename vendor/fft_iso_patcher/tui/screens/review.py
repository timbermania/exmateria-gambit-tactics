"""Review screen: edit output paths, see summary, kick off apply."""

from __future__ import annotations

from pathlib import Path

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Input, Label, Static

from ..paths import normalize_user_path


class ReviewScreen(Screen):
    BINDINGS = [
        ("escape", "back", "Back"),
        ("a", "apply", "Apply"),
    ]

    def compose(self) -> ComposeResult:
        sess = self.app.session
        yield Header(show_clock=False)
        yield Vertical(
            Static(self._summary(), id="review-summary"),
            Label("Output ISO:"),
            Input(value=str(sess.output_iso), id="output-iso"),
            Label("Recipe TOML (saved alongside the ISO):"),
            Input(value=str(sess.recipe_path), id="recipe-path-out"),
            Label("Manifest JSON (optional, leave blank to skip):"),
            Input(
                value=str(sess.manifest_path) if sess.manifest_path else "",
                id="manifest-path",
            ),
            Static("", id="review-error"),
            Horizontal(
                Button("Apply [A]", id="btn-apply", variant="success"),
                Button("Back [Esc]", id="btn-back"),
                id="review-buttons",
            ),
            id="review-body",
        )
        yield Footer()

    def _summary(self) -> str:
        from rich.markup import escape

        sess = self.app.session
        replacements = sess.replacements()
        relocs = sess.relocations_needed()
        report = sess.report
        biggest = report.largest if report else None
        biggest_str = (
            f"largest free range: ({biggest[0]}, {biggest[1]}) "
            f"= {biggest[1] - biggest[0]} sectors"
            if biggest
            else "no usable free space"
        )
        lines = [
            f"[b]Input ISO:[/b] {escape(str(sess.iso_path))}",
            f"[b]Replacements:[/b] {len(replacements)}    "
            f"[b]Relocations needed:[/b] {relocs}",
            f"[b]Free space:[/b] {biggest_str}",
            "",
            "[b]Slots being patched:[/b]",
        ]
        for s in replacements:
            tag = "in-place" if s.fits_in_place else "relocate"
            lines.append(
                f"  MUSIC_{s.slot:02d}  ({tag})  "
                f"{escape(s.replacement.name)} "
                f"({s.replacement_size} B, {s.replacement_n_sectors} sec)"
            )
        return "\n".join(lines)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-apply":
            self.action_apply()
        elif event.button.id == "btn-back":
            self.action_back()

    def action_back(self) -> None:
        self.app.pop_screen()

    def action_apply(self) -> None:
        sess = self.app.session
        out_str = self.query_one("#output-iso", Input).value.strip()
        recipe_str = self.query_one("#recipe-path-out", Input).value.strip()
        manifest_str = self.query_one("#manifest-path", Input).value.strip()

        if not out_str or not recipe_str:
            self.query_one("#review-error", Static).update(
                "[red]Output ISO and recipe path are required.[/red]"
            )
            return

        sess.output_iso = normalize_user_path(out_str)
        sess.recipe_path = normalize_user_path(recipe_str)
        sess.manifest_path = normalize_user_path(manifest_str) if manifest_str else None

        if sess.output_iso == sess.iso_path:
            self.query_one("#review-error", Static).update(
                "[red]Output ISO must differ from input ISO (TUI safety).[/red]"
            )
            return

        from .apply import ApplyScreen
        self.app.push_screen(ApplyScreen())
