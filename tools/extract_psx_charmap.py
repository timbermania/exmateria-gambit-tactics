#!/usr/bin/env python3
"""
One-shot extractor: build a PSX FFT charmap JSON from FFTPatcher's C# source.

Ports the static initialisation in `FFTPatcher/PatcherLib/TextUtilities/
TextUtilities.cs` — the `PSXCharacterSet` array (V3 baseline), the
`BuildVersion1Charmap` overrides (V1 ASCII/punctuation), and the
`BuildVersion3Charmap` expansion (single-byte → 0xD000+i shadows; bytes
0xD0+ map to 0xD1XX / 0xD2XX / ... 2-byte sequences) — and dumps the
combined dict to `tools/data/psx_charmap.json` for `decode_fft_text.py`
to consume at runtime.

This is a build-time tool — run it whenever FFTPatcher is updated:

    uv run python tools/extract_psx_charmap.py

The output JSON is committed; runtime decode does NOT depend on the
FFTPatcher source.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

def _fftpatcher_textutil() -> Path:
    """Locate FFTPatcher's TextUtilities.cs — $FFTPATCHER_SRC, else ~/FFTPatcher.

    FFTPatcher is a separate open-source checkout, not part of this repo and not
    on the disc, so there is no `_repo_paths` helper for it. An env var is the
    seam: ADR-0001 forbids a tracked file assuming one host's home directory.
    """
    env = os.environ.get("FFTPATCHER_SRC")
    root = Path(env) if env else Path.home() / "FFTPatcher"
    return root / "PatcherLib" / "TextUtilities" / "TextUtilities.cs"


FFTPATCHER_TEXTUTIL = _fftpatcher_textutil()
OUT = Path(__file__).parent / "data" / "psx_charmap.json"


def parse_psx_character_set(src: str) -> list[str]:
    """Pull the 2200-entry `PSXCharacterSet` array literal out of the C# file
    (between its declaration and the closing `});`) and decode the C# string
    literals (handling `\\xHH`, `\\uHHHH`, escaped quotes)."""
    start = src.index("PSXCharacterSet = new System.Collections.ObjectModel.ReadOnlyCollection<string>")
    open_brace = src.index("{", start)
    close = src.index("});", open_brace)
    body = src[open_brace + 1:close]

    # Match C# string literals: "..." with backslash-escape support.
    pattern = re.compile(r'"((?:\\.|[^"\\])*)"')
    result: list[str] = []

    def decode_csharp_string(s: str) -> str:
        out = []
        i = 0
        while i < len(s):
            c = s[i]
            if c == "\\" and i + 1 < len(s):
                nxt = s[i + 1]
                if nxt == "x":
                    hex2 = s[i + 2:i + 4]
                    out.append(chr(int(hex2, 16)))
                    i += 4
                    continue
                if nxt == "u":
                    hex4 = s[i + 2:i + 6]
                    out.append(chr(int(hex4, 16)))
                    i += 6
                    continue
                if nxt == "U":
                    hex8 = s[i + 2:i + 10]
                    out.append(chr(int(hex8, 16)))
                    i += 10
                    continue
                if nxt == "n":
                    out.append("\n")
                elif nxt == "t":
                    out.append("\t")
                elif nxt == "r":
                    out.append("\r")
                elif nxt in ('"', "\\", "'"):
                    out.append(nxt)
                else:
                    out.append(nxt)
                i += 2
                continue
            out.append(c)
            i += 1
        return "".join(out)

    for m in pattern.finditer(body):
        result.append(decode_csharp_string(m.group(1)))

    if len(result) < 2200:
        raise SystemExit(
            f"extractor parsed {len(result)} strings, expected 2200 — "
            f"PSXCharacterSet array layout may have changed"
        )
    return result[:2200]


def build_charmap() -> dict[int, str]:
    """Port of TextUtilities.BuildVersion{1,3}Charmap (V2 = kanji, identical
    in both psx/psp — we mirror it because the V1 overrides reference some of
    the same keys). Returns a flat int→str dict that GetNextChar can index."""
    src = FFTPATCHER_TEXTUTIL.read_text(encoding="utf-8")
    chars = parse_psx_character_set(src)
    psx: dict[int, str] = {}

    # --- BuildVersion3Charmap -------------------------------------------------
    # Single-byte 0..0xCF and their 0xD000+i shadows.
    for i in range(0xD0):
        psx[i] = chars[i]
        psx[i + 0xD000] = chars[i]
    # 0xD0..end → 2-byte key 0xD1XX, 0xD2XX, ... with stride 0xD0.
    for i in range(0xD0, len(chars)):
        key = (i - 0xD0) % 0xD0 + 0xD100 + 0x100 * ((i - 0xD0) // 0xD0)
        psx[key] = chars[i]

    # --- BuildVersion1Charmap (V1 overrides; many shadow V3 entries) ---------
    # lowercase a..z at 0x24+ and 0xD024+ — already done by V3 for the base,
    # but V1 in C# re-adds them; we follow the same semantics (Add throws on
    # duplicate keys in C#, but here we use [] = which overrides cleanly).
    for i, ch in enumerate("abcdefghijklmnopqrstuvwxyz"):
        psx[i + 0x24] = ch
        psx[i + 0x24 + 0xD000] = ch
    psx[0x40] = "?"
    psx[0xD040] = "?"
    psx[0xD9C9] = "?"
    psx[0xB2] = "♪"
    psx[0xD0B2] = "♪"
    psx[0xD117] = "—"
    psx[0xD118] = "「"
    psx[0xD11B] = "⋯"
    psx[0xD11F] = "×"
    psx[0xD120] = "÷"
    psx[0xD121] = "∩"
    psx[0xD122] = "∪"
    psx[0xD123] = "="
    psx[0xDA70] = "="
    psx[0xD124] = "≠"
    psx[0xD9B5] = "∞"
    psx[0xD9B7] = "&"
    psx[0xD9B8] = "%"
    psx[0xD9B9] = "○"
    psx[0xD9BA] = "←"
    psx[0xD9BB] = "→"
    psx[0xD9C2] = "『"
    psx[0xD9C3] = "』"
    psx[0xD9C4] = "」"
    psx[0xD9C5] = "～"
    psx[0xD9C7] = "△"
    psx[0xD9C8] = "□"
    psx[0xD9CA] = "♥"
    for i in range(6):  # D9CB..D9D0 = ⅠⅡⅢⅣⅤⅥ
        psx[0xD9CB + i] = chr(0x2160 + i)
    for i in range(12):  # DA00..DA0B = ♈..♓
        psx[0xDA00 + i] = chr(0x2648 + i)
    psx[0xDA0C] = "{Serpentarius}"
    psx[0xDA71] = "$"
    psx[0xDA72] = "¥"
    psx[0xDA74] = ","
    psx[0xDA75] = ";"
    psx[0xD11D] = "-"
    psx[0x42] = "+"
    psx[0xD042] = "+"
    psx[0xD11E] = "+"
    psx[0x46] = ":"
    psx[0xD046] = ":"
    psx[0xD9BD] = ":"
    psx[0x8D] = "("
    psx[0xD08D] = "("
    psx[0xD9BE] = "("
    psx[0x8E] = ")"
    psx[0xD08E] = ")"
    psx[0xD9BF] = ")"
    psx[0x91] = '"'
    psx[0xD091] = '"'
    psx[0xD9C0] = '"'
    psx[0xDA77] = '"'
    psx[0x93] = "'"
    psx[0xD093] = "'"
    psx[0xD9C1] = "'"
    psx[0xDA76] = "'"
    psx[0x8B] = "·"
    psx[0xD08B] = "·"
    psx[0xD9BC] = "·"
    psx[0x44] = "/"
    psx[0xD044] = "/"
    psx[0xD9C6] = "/"
    psx[0xD125] = ">"
    psx[0xD126] = "<"
    psx[0xD127] = "≧"
    psx[0xD128] = "≦"
    psx[0xFA] = " "
    psx[0xD12A] = " "
    psx[0xDA73] = " "
    psx[0x5F] = "."
    psx[0xD05F] = "."
    psx[0xD119] = "."
    psx[0xD11C] = "."
    psx[0xD9B6] = "."
    psx[0x3E] = "!"
    psx[0xD03E] = "!"
    psx[0xD11A] = "!"
    psx[0xB5] = "*"
    psx[0xD0B5] = "*"
    for k in (0xD111, 0xD129, 0xD12B, 0xD12C, 0xD12D, 0xD12E, 0xD12F, 0xD130, 0xD131, 0xD132):
        psx[k] = "*"
    psx[0xE0] = "{Ramza}"
    psx[0xF8] = "{Newline}"
    psx[0xFB] = "{Begin List}"
    psx[0xFC] = "{End List}"
    psx[0xFF] = "{Close}"
    # Digits 0..9 (V1 explicit re-add, identical to V3 baseline)
    for i in range(10):
        psx[i] = str(i)
        psx[i + 0xD000] = str(i)
    # A..Z at 0x0A..0x23 + shadows
    for i, ch in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
        psx[i + 0x0A] = ch
        psx[i + 0x0A + 0xD000] = ch
    # {Delay XX} / {Color XX} families (E2/E3 prefix).
    for i in range(256):
        psx[0xE200 + i] = f"{{Delay {i:02X}}}"
        psx[0xE300 + i] = f"{{Color {i:02X}}}"
    # Japanese hiragana/katakana entries (re-added by V1, override V3 baseline).
    psx[0x3F] = "あ"
    psx[0x41] = "い"
    psx[0x43] = "う"
    psx[0x45] = "え"
    psx[0xD03F] = "あ"
    psx[0xD041] = "い"
    psx[0xD043] = "う"
    psx[0xD045] = "え"
    for i in range(0x47, 0x5F):
        psx[i] = chr(i - 0x47 + 0x304A)
        psx[i + 0xD000] = chr(i - 0x47 + 0x304A)
    for i in range(0x60, 0x8B):
        psx[i] = chr(i - 0x60 + 0x3063)
        psx[i + 0xD000] = chr(i - 0x60 + 0x3063)
    psx[0x8C] = "わ"
    psx[0xD08C] = "わ"
    psx[0x8F] = "を"
    psx[0xD08F] = "を"
    psx[0x90] = "ん"
    psx[0xD090] = "ん"
    psx[0x92] = "ア"
    psx[0xD092] = "ア"
    for i in range(0x94, 0xB2):
        psx[i] = chr(i - 0x94 + 0x30A4)
        psx[i + 0xD000] = chr(i - 0x94 + 0x30A4)
    psx[0xB3] = "ッ"
    psx[0xD0B3] = "ッ"
    psx[0xB4] = "ツ"
    psx[0xD0B4] = "ツ"
    for i in range(0xB6, 0xD0):
        psx[i] = chr(i - 0xB6 + 0x30C6)
        psx[i + 0xD000] = chr(i - 0xB6 + 0x30C6)
    for i in range(0xD0, 0xDC):
        psx[i - 0xD0 + 0xD100] = chr(i - 0xD0 + 0x30E0)
    psx[0xD10C] = "レ"
    psx[0xD10D] = "ロ"
    psx[0xD10E] = "ヮ"
    psx[0xD10F] = "ワ"
    for i in range(0xE2, 0xE7):
        psx[i - 0xE2 + 0xD112] = chr(i - 0xE2 + 0x30F2)
    return psx


def main() -> None:
    if not FFTPATCHER_TEXTUTIL.exists():
        raise SystemExit(
            f"FFTPatcher source not found at {FFTPATCHER_TEXTUTIL} — "
            f"clone github.com/Glain/FFTPatcher to ~/FFTPatcher, "
            f"or point $FFTPATCHER_SRC at an existing checkout."
        )
    charmap = build_charmap()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(
        {str(k): v for k, v in sorted(charmap.items())},
        indent="\t",
        ensure_ascii=False,
    ) + "\n")
    print(f"Wrote {len(charmap)} entries to {OUT}")


if __name__ == "__main__":
    main()
