#!/usr/bin/env python3
"""
FFT scenario-chunk string-table walker + tokenizer.

Lifted out of ``scenario_screenplay.py`` so any tool can locate, walk,
and tokenize the per-chunk message table — most notably ``disasm_event.py
--with-text`` which bakes the structured token list into chunk JSON for
GDScript consumption.

The string table sits immediately after the terminating ``0xDB Event End``
opcode in a scenario's event-script chunk (the per-scenario RAM blob at
``0x8004A6BC``). Each entry is a 0xFE/0xFF-terminated byte sequence in
the FFT PSX charmap; the decoder is in ``decode_fft_text.decode_string``.

The tokenizer splits the FFTPatcher-decoded string into structured
tokens so the Godot renderer can drive a typewriter without re-parsing
``{Delay NN}`` / ``{Color NN}`` / ``{Newline}`` / macros at runtime.

    Token = {"type": "text",    "value": "..."}      # 1+ printable glyphs
          | {"type": "delay",   "frames": N}         # from {Delay NN}
          | {"type": "newline"}                      # from {Newline}
          | {"type": "color",   "palette": N}        # from {Color NN}
          | {"type": "macro",   "name": "Ramza"}     # {Ramza}, {Serpentarius}, …
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from _fft_bytecode import OpcodeTable, disasm
from decode_fft_text import decode_string

EVENT_END_OPCODE = 0xDB

# Match an FFTPatcher-style inline marker: ``{Name}`` or ``{Name AA}`` (one
# space, two hex digits). Bracketed hex like ``<HH>`` is the fallback for
# unknown bytes from ``decode_fft_text`` — we leave those embedded in
# text tokens since they're not actionable here.
_TOKEN_RE = re.compile(r"\{([A-Za-z][A-Za-z]*(?:\s+[0-9A-Fa-f]{2,4})?(?:\s+List)?)\}")


@dataclass
class StringTable:
    base: int                           # chunk offset of message #1
    entries: list[tuple[int, str]]      # 0-indexed; entries[i] = msg #(i+1)

    def get(self, message_id: int) -> tuple[int, str] | None:
        """1-based lookup (FFT message IDs start at 1; ID 0 means 'none')."""
        if message_id <= 0 or message_id > len(self.entries):
            return None
        return self.entries[message_id - 1]


def find_string_table_base(buf: bytes, table: OpcodeTable) -> int:
    """The string table sits immediately after the terminating 0xDB Event
    End opcode. Walk the disasm and return that offset; if no Event End is
    found, fall back to len(buf) so the table is empty."""
    insts = disasm(buf, table, chunk_base=0)
    for inst in insts:
        if inst.opcode == EVENT_END_OPCODE:
            return inst.offset + len(inst.raw)
    return len(buf)


def walk_strings(buf: bytes, base: int) -> list[tuple[int, str]]:
    """Decode all 0xFE/0xFF-terminated strings starting at ``base``. Stops
    at the first unterminated string (EOF or padding). Returns
    ``[(offset, text)]``."""
    out: list[tuple[int, str]] = []
    pos = base
    while pos < len(buf):
        text, npos, terminated = decode_string(buf, pos)
        if not terminated:
            break
        out.append((pos, text))
        pos = npos
    return out


def tokenize(text: str) -> list[dict]:
    """Split an FFTPatcher-decoded string into structured tokens.

    ``{Delay NN}`` / ``{Color NN}`` / ``{Newline}`` / ``{Ramza}``, etc.
    become their own records; everything between is grouped into ``text``
    tokens with the raw UTF-8 substring."""
    tokens: list[dict] = []
    buf: list[str] = []

    def flush_text() -> None:
        if buf:
            tokens.append({"type": "text", "value": "".join(buf)})
            buf.clear()

    pos = 0
    for m in _TOKEN_RE.finditer(text):
        if m.start() > pos:
            buf.append(text[pos:m.start()])
        body = m.group(1).strip()
        token = _classify(body)
        if token is None:
            # Unrecognised marker — keep it as literal text so callers
            # can see it in the output rather than silently dropping it.
            buf.append(m.group(0))
        else:
            flush_text()
            tokens.append(token)
        pos = m.end()
    if pos < len(text):
        buf.append(text[pos:])
    flush_text()
    return tokens


def _classify(body: str) -> dict | None:
    """Map the inside of a ``{…}`` marker to its token record, or None."""
    parts = body.split()
    head = parts[0]
    if head == "Delay" and len(parts) == 2:
        try:
            return {"type": "delay", "frames": int(parts[1], 16)}
        except ValueError:
            return None
    if head == "Color" and len(parts) == 2:
        try:
            return {"type": "color", "palette": int(parts[1], 16)}
        except ValueError:
            return None
    if body == "Newline":
        return {"type": "newline"}
    if body == "Close":
        # FFTPatcher's marker for the 0xFF byte — string is already
        # terminated by decode_string so we shouldn't see this, but
        # treat it as a no-op macro if a string contains a literal one.
        return {"type": "macro", "name": "Close"}
    # Bare names (Ramza, Serpentarius, Begin List, End List, Unknown)
    # become macros so consumers can decide how to render them.
    return {"type": "macro", "name": body}
