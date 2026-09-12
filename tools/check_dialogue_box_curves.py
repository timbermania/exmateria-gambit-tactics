#!/usr/bin/env python3
"""Presence + shape check for assets/ui/dialogue_box_curves.json.

CI half of the dialogue-box open/close anti-silent-failure contract (§C.2b of
research/working_documents/scenario_1_captures/prayer_text_fadeout_and_box_open_close_decode.md):
the parser (parse_dialogue_box_curves.py, wired into bootstrap_assets.sh) is the
recreation half; this asserts, in CI, that the committed asset actually exists,
has all 5 curves, each terminates at t==1.0, and that the open/close curves the
runtime consumes (c3 ease-out open, c2 linear open, c4 close) still match the
live PCSX capture byte-for-byte. A broken/absent asset fails the suite here
instead of silently disabling the box grow/shrink at runtime.

Pure Python — no Godot needed.

Run: uv run python tools/check_dialogue_box_curves.py
"""

import json
import sys
from pathlib import Path

CURVES_PATH = Path(__file__).parent.parent / "assets" / "ui" / "dialogue_box_curves.json"

# Live PCSX capture (probe_box_tween_bp.py, 2026-07-01) + ROM curve tables, raw
# Q12 (0x1000 = 4096 = full size). These are the curves the runtime reads for
# the chapel boxes: index 2 (linear open), 3 (ease-out open), 4 (CLOSE).
EXPECTED_RAW_Q12 = {
    2: [384, 768, 1152, 1536, 1920, 2304, 2688, 3072, 3456, 3840, 4096],
    3: [832, 1600, 2304, 2944, 3520, 4032, 4096],
    4: [1024, 2048, 3072, 4096],
}

NUM_CURVES = 5
Q12_ONE = 4096


def _fail(msg: str) -> None:
    print(f"ABORT: dialogue_box_curves.json — {msg}")
    sys.exit(1)


def main() -> None:
    if not CURVES_PATH.exists():
        _fail(
            f"MISSING at {CURVES_PATH}. Run: "
            "uv run python tools/parse_dialogue_box_curves.py "
            "(or bash tools/bootstrap_assets.sh)"
        )

    try:
        data = json.loads(CURVES_PATH.read_text())
    except json.JSONDecodeError as exc:
        _fail(f"is not valid JSON ({exc})")

    curves = data.get("curves")
    if not isinstance(curves, list) or len(curves) != NUM_CURVES:
        _fail(f"expected {NUM_CURVES} curves, got {len(curves) if isinstance(curves, list) else 'none'}")

    by_idx = {}
    for c in curves:
        if not isinstance(c, dict) or "index" not in c:
            _fail("a curve entry is missing its 'index'")
        by_idx[int(c["index"])] = c

    for i in range(NUM_CURVES):
        if i not in by_idx:
            _fail(f"curve index {i} missing")
        t = by_idx[i].get("t")
        if not isinstance(t, list) or not t:
            _fail(f"curve {i} has no 't' sequence")
        if abs(float(t[-1]) - 1.0) > 1e-6:
            _fail(f"curve {i} must terminate at t==1.0, got {t[-1]}")
        raw = by_idx[i].get("raw_q12")
        if not isinstance(raw, list) or raw[-1] != Q12_ONE:
            _fail(f"curve {i} raw_q12 must terminate at {Q12_ONE}, got {raw[-1] if raw else None}")

    for idx, expected in EXPECTED_RAW_Q12.items():
        got = by_idx[idx].get("raw_q12")
        if got != expected:
            _fail(
                f"curve {idx} drifted from the live PCSX capture:\n"
                f"  got  {got}\n  want {expected}\n"
                "Re-run: uv run python tools/parse_dialogue_box_curves.py"
            )

    print(
        f"OK: dialogue_box_curves.json has {NUM_CURVES} curves; "
        "c2/c3/c4 match the live PCSX capture; all terminate at t==1.0."
    )


if __name__ == "__main__":
    main()
