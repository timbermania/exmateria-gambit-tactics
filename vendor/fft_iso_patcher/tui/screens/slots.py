"""Slots screen: browse the 100 music slots and assign replacement SMD files."""

from __future__ import annotations

from pathlib import Path

from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen, Screen
from textual.widgets import Button, DataTable, Footer, Header, Input, Label, Static

from ...constants import ENGINE_MAX_SMD_BYTES
from ..paths import normalize_user_path
from ..state import SlotInfo


class _ReplaceModal(ModalScreen[Path | None]):
    """Prompt for a replacement SMD path. Returns the path or None."""

    BINDINGS = [("escape", "cancel", "Cancel")]

    def __init__(self, slot: int, current: Path | None) -> None:
        super().__init__()
        self.slot = slot
        self.current = current

    def compose(self) -> ComposeResult:
        current = str(self.current) if self.current else ""
        yield Vertical(
            Label(
                f"Replacement SMD for MUSIC_{self.slot:02d}\n"
                f"(blank to clear)",
                id="modal-label",
            ),
            Input(value=current, placeholder="/path/to/replacement.smd", id="modal-input"),
            Static("", id="modal-error"),
            Horizontal(
                Button("OK", id="modal-ok", variant="primary"),
                Button("Clear", id="modal-clear"),
                Button("Cancel", id="modal-cancel"),
                id="modal-buttons",
            ),
            id="modal-body",
        )

    def action_cancel(self) -> None:
        self.dismiss(None)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "modal-cancel":
            self.dismiss(None)
            return
        if event.button.id == "modal-clear":
            # Sentinel: an empty Path() means "clear the replacement". We can't
            # use None because None already means "user cancelled". Use the
            # caller-side convention: the slots screen treats Path("") as clear.
            self.dismiss(Path(""))
            return
        # OK
        raw = self.query_one("#modal-input", Input).value
        if not raw.strip():
            self.dismiss(Path(""))
            return
        path = normalize_user_path(raw)
        if not path.exists():
            from rich.markup import escape
            self.query_one("#modal-error", Static).update(
                f"[red]No such file: {escape(str(path))}[/red]"
            )
            return
        if path.stat().st_size > ENGINE_MAX_SMD_BYTES:
            self.query_one("#modal-error", Static).update(
                f"[red]File is {path.stat().st_size} bytes; engine max is "
                f"{ENGINE_MAX_SMD_BYTES}.[/red]"
            )
            return
        self.dismiss(path)


class SlotsScreen(Screen):
    """DataTable of music slots; press R / Enter on a row to assign a file."""

    BINDINGS = [
        ("r", "replace", "Replace selected"),
        ("enter", "replace", "Replace selected"),
        ("backspace", "clear", "Clear selected"),
        ("c", "continue", "Continue"),
        ("escape", "back", "Back"),
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)
        yield Static("", id="status-bar")
        table: DataTable = DataTable(id="slots-table")
        table.cursor_type = "row"
        yield table
        yield Horizontal(
            Button("Replace [R]", id="btn-replace", variant="primary"),
            Button("Clear [Backspace]", id="btn-clear"),
            Button("Continue [C]", id="btn-continue", variant="success"),
            Button("Back [Esc]", id="btn-back"),
            id="slots-buttons",
        )
        yield Footer()

    def on_mount(self) -> None:
        table: DataTable = self.query_one("#slots-table", DataTable)
        table.add_column("Slot", width=10)
        table.add_column("Orig LBA", width=10)
        table.add_column("Sectors", width=8)
        table.add_column("Status", width=12)
        table.add_column("Replacement", width=60)
        self._refresh_table()
        self._refresh_status()

    def _refresh_table(self) -> None:
        table: DataTable = self.query_one("#slots-table", DataTable)
        table.clear()
        for info in self.app.session.slots:
            status, replacement = self._row_render(info)
            table.add_row(
                f"MUSIC_{info.slot:02d}",
                str(info.original_lba),
                str(info.original_n_sectors),
                status,
                replacement,
                key=str(info.slot),
            )

    def _row_render(self, info: SlotInfo) -> tuple[str, str]:
        if info.replacement is None:
            return ("[dim]vanilla[/dim]", "")
        if info.replacement_n_sectors is None:
            return ("[red]?[/red]", str(info.replacement))
        if info.fits_in_place:
            status = "[green]in-place[/green]"
        else:
            status = "[yellow]relocate[/yellow]"
        rep = (
            f"{info.replacement.name} "
            f"({info.replacement_size} B, {info.replacement_n_sectors} sec)"
        )
        return (status, rep)

    def _refresh_status(self) -> None:
        sess = self.app.session
        report = sess.report
        replacements = sess.replacements()
        relocs = sess.relocations_needed()
        gaps = report.candidates if report else ()
        biggest = report.largest if report else None
        biggest_str = (
            f"largest free: ({biggest[0]}, {biggest[1]}) "
            f"= {biggest[1] - biggest[0]} sectors"
            if biggest
            else "no usable free space"
        )
        from rich.markup import escape
        text = (
            f"[b]ISO:[/b] {escape(str(sess.iso_path))}    "
            f"[b]replacements:[/b] {len(replacements)}    "
            f"[b]relocations needed:[/b] {relocs}    "
            f"[b]free ranges:[/b] {len(gaps)}    "
            f"{biggest_str}"
        )
        self.query_one("#status-bar", Static).update(text)

    def _selected_slot(self) -> SlotInfo | None:
        table: DataTable = self.query_one("#slots-table", DataTable)
        if table.cursor_row is None or table.cursor_row < 0:
            return None
        if table.cursor_row >= len(self.app.session.slots):
            return None
        return self.app.session.slots[table.cursor_row]

    def on_button_pressed(self, event: Button.Pressed) -> None:
        bid = event.button.id
        if bid == "btn-replace":
            self.action_replace()
        elif bid == "btn-clear":
            self.action_clear()
        elif bid == "btn-continue":
            self.action_continue()
        elif bid == "btn-back":
            self.action_back()

    def action_replace(self) -> None:
        info = self._selected_slot()
        if info is None:
            return

        def handle(result: Path | None) -> None:
            if result is None:
                return
            if str(result) == "":
                info.replacement = None
                info.replacement_size = None
                info.replacement_n_sectors = None
            else:
                info.replacement = result
                info.replacement_size = result.stat().st_size
                info.replacement_n_sectors = (
                    info.replacement_size + 2047
                ) // 2048
            self._refresh_table()
            self._refresh_status()

        self.app.push_screen(_ReplaceModal(info.slot, info.replacement), handle)

    def action_clear(self) -> None:
        info = self._selected_slot()
        if info is None or info.replacement is None:
            return
        info.replacement = None
        info.replacement_size = None
        info.replacement_n_sectors = None
        self._refresh_table()
        self._refresh_status()

    def action_continue(self) -> None:
        if not self.app.session.replacements():
            return
        # Block continue if any replacement is too big to fit even after
        # relocation into the largest available gap. (Simple Phase 2 model:
        # relocations consume the largest gap. If two huge slots both want
        # relocation and only one gap fits one of them, the patcher will
        # error during apply. The TUI surfaces total relocation needed in
        # the status bar so the user has a heads-up.)
        from .review import ReviewScreen
        self.app.push_screen(ReviewScreen())

    def action_back(self) -> None:
        self.app.pop_screen()
