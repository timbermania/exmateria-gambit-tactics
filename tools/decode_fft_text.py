#!/usr/bin/env python3
"""
FFT PSX text decoder.

Port of FFTPatcher's PSX charmap (PatcherLib/TextUtilities/CharMap.cs +
TextUtilities.cs `PSXMap`). Decodes a byte stream from any FFT data
source — event-script string sections, ITEM.BIN names, dialogue chunks
in RAM — into UTF-8 with FFTPatcher-style inline markers ({Newline},
{Color XX}, {Delay XX}, {Ramza}, …).

The charmap data itself lives in `tools/data/psx_charmap.json`, baked
from the FFTPatcher C# source by `extract_psx_charmap.py`. Runtime does
NOT depend on FFTPatcher being installed.

Decoding semantics (mirroring CharMap.GetNextChar):

- 0xFE and 0xFF terminate a string (FFTPatcher's `readTerminators`).
  We split on both and emit `--page-end--` between strings by default.
- Multi-byte prefixes that read one extra byte (key = lead * 256 + next):
      0xD0..0xDA, 0xE2, 0xE3, 0xE7, 0xE8, 0xEC, 0xEE, 0xF5, 0xF6
- Multi-byte prefixes that read two extra bytes (key = lead<<16 | …):
      0xF0..0xF3
- Everything else: single-byte lookup.
- Unknown keys fall back to a literal `<HH>` / `<HHHH>` / `<HHHHHH>` hex
  marker (same convention as the existing
  `research/working_documents/scenario_1_captures/dialogue_pages_decoded.txt`).

The pair (charmap + GetNextChar) is authoritative: every CHARMAP[k] value
is what FFTPatcher would render, and unknown bytes never go silent.

Usage:
    # Pipe-style:
    uv run python tools/decode_fft_text.py FILE [--offset N] [--length N]
    # Programmatic:
    from decode_fft_text import decode_bytes
    text = decode_bytes(some_bytes)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

CHARMAP_PATH = Path(__file__).parent / "data" / "psx_charmap.json"

# Bytes that act as string terminators. FFTPatcher's `readTerminators` —
# 0xFE = soft end-of-string, 0xFF = {Close} (also terminates).
TERMINATORS = frozenset((0xFE, 0xFF))

# Bytes that begin a 2-byte sequence (one extra byte consumed).
TWO_BYTE_PREFIXES = frozenset(
    list(range(0xD0, 0xDB)) + [0xE2, 0xE3, 0xE7, 0xE8, 0xEC, 0xEE, 0xF5, 0xF6]
)

# Bytes that begin a 3-byte sequence (two extra bytes consumed).
THREE_BYTE_PREFIXES = frozenset(range(0xF0, 0xF4))


def load_charmap(path: Path = CHARMAP_PATH) -> dict[int, str]:
    """Load the int→string charmap dict. JSON keys are str; cast to int."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {int(k): v for k, v in raw.items()}


# Module-level cache. Loaded lazily so importing doesn't hit disk if the
# caller only wants `decode_string` from a pre-built charmap.
_CHARMAP: dict[int, str] | None = None


def _charmap() -> dict[int, str]:
    global _CHARMAP
    if _CHARMAP is None:
        _CHARMAP = load_charmap()
    return _CHARMAP


def decode_string(data: bytes, pos: int = 0, end: int | None = None,
                  charmap: dict[int, str] | None = None
                  ) -> tuple[str, int, bool]:
    """Decode a single FFT string (terminated by 0xFE/0xFF). Returns
    (decoded_str, new_pos, terminated). `new_pos` points past the
    terminator if one was hit, otherwise at `end`. `terminated` is True
    iff a terminator byte was consumed."""
    cm = charmap if charmap is not None else _charmap()
    if end is None:
        end = len(data)
    out: list[str] = []
    while pos < end:
        b = data[pos]
        if b in TERMINATORS:
            return "".join(out), pos + 1, True
        if b in TWO_BYTE_PREFIXES and pos + 1 < end:
            key = b * 256 + data[pos + 1]
            out.append(cm.get(key, f"<{key:04X}>"))
            pos += 2
            continue
        if b in THREE_BYTE_PREFIXES and pos + 2 < end:
            key = (b << 16) | (data[pos + 1] << 8) | data[pos + 2]
            out.append(cm.get(key, f"<{key:06X}>"))
            pos += 3
            continue
        out.append(cm.get(b, f"<{b:02X}>"))
        pos += 1
    return "".join(out), pos, False


def decode_bytes(data: bytes, pos: int = 0, end: int | None = None,
                 charmap: dict[int, str] | None = None,
                 page_sep: str = "--page-end--\n",
                 newline_marker: str = "{NP}\n") -> str:
    """Decode a byte range as a sequence of FFT strings, joined with
    `page_sep` between successive 0xFE/0xFF terminators. The internal
    `{Newline}` token (FFTPatcher's marker for 0xF8) is post-processed
    into `newline_marker` so the output reads as discrete display lines
    — matches `dialogue_pages_decoded.txt`'s `{NP}\\n` convention."""
    cm = charmap if charmap is not None else _charmap()
    if end is None:
        end = len(data)
    pieces: list[str] = []
    while pos < end:
        text, pos, terminated = decode_string(data, pos, end, cm)
        # Apply golden-style display tweak: split on the {Newline} sentinel.
        text = text.replace("{Newline}", newline_marker)
        pieces.append(text + page_sep if terminated else text)
    return "".join(pieces)


def main() -> None:
    ap = argparse.ArgumentParser(description="Decode FFT PSX-format text bytes")
    ap.add_argument("file", type=Path, help="input byte stream (use - for stdin)")
    ap.add_argument("--offset", type=lambda s: int(s, 0), default=0,
                    help="start byte offset (default: 0)")
    ap.add_argument("--length", type=lambda s: int(s, 0), default=None,
                    help="number of bytes to decode (default: to EOF)")
    ap.add_argument("--charmap", type=Path, default=CHARMAP_PATH,
                    help="charmap JSON path (default: %(default)s)")
    ap.add_argument("--newline", default="{NP}\n",
                    help="replacement for {Newline}; default %(default)r (golden style)")
    ap.add_argument("--page-sep", default="--page-end--\n",
                    help="separator between FE/FF-terminated strings")
    args = ap.parse_args()

    if str(args.file) == "-":
        import sys
        data = sys.stdin.buffer.read()
    else:
        data = args.file.read_bytes()

    cm = load_charmap(args.charmap)
    end = args.offset + args.length if args.length is not None else None
    text = decode_bytes(data, args.offset, end, cm,
                        page_sep=args.page_sep, newline_marker=args.newline)
    print(text, end="" if text.endswith("\n") else "\n")


if __name__ == "__main__":
    main()
