#!/usr/bin/env python3
"""Measure byte-exact panel-text glyph positions from the roster/formation oracle.

FORMATION_SCREEN.md §14 / issue #172. The two bottom detail panels' text
(name/job/Lv/Exp/Hp/Mp/Ct labels+values, Brave/Faith) is NOT placed by static
constants in the roster overlay — it is computed at RUNTIME by the resident menu
widget layout code (FUN_8012a598 @0x8012a598) using FONT.BIN proportional glyph
metrics (@0x801661fc). And an Exec breakpoint on the hot menu draw path
HARD-CRASHES this pcsx build (verified). So the byte-exact ground truth is the
oracle framebuffer itself: `t04.png` is a native 256x240 capture of this exact
screen. This tool measures each text element's first-glyph (x,y) off that oracle
via connected-component glyph detection (±1px).

Two panels, two ink models (calibrated from t04.png):
  * LEFT "vitals"  — bright CREAM text (min(r,g,b)>150, near-gray) on black.
  * RIGHT "info"   — dark text (avg<95) on tan (152,144,120); search the tan
                     interior so the black panel border is excluded.

Run (from godot-learning/):
  uv run --with pillow --with numpy python tools/measure_formation_panel_text.py <t04.png>
"""
import sys
import numpy as np
from PIL import Image
from collections import deque


def load(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    avg = (r + g + b) // 3
    mn = np.minimum(np.minimum(r, g), b)
    mx = np.maximum(np.maximum(r, g), b)
    white = (mn > 150) & ((mx - mn) < 45)     # cream menu text core
    dark = avg < 95                           # dark text on tan
    return white, dark


def cc_boxes(mask, minpx):
    """4/8-connected component bounding boxes with a min pixel count."""
    ys, xs = np.where(mask)
    S = set(zip(ys.tolist(), xs.tolist()))
    boxes = []
    while S:
        y, x = next(iter(S))
        q = deque([(y, x)])
        S.discard((y, x))
        x0 = x1 = x
        y0 = y1 = y
        n = 0
        while q:
            cy, cx = q.popleft()
            n += 1
            x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    p = (cy + dy, cx + dx)
                    if p in S:
                        S.discard(p)
                        q.append(p)
        if n >= minpx:
            boxes.append((x0, y0, x1, y1))
    return boxes


def rows(boxes, y_tol=4, tok_gap=3):
    """Group glyph boxes into text rows, then into space-separated tokens."""
    boxes.sort(key=lambda t: ((t[1] + t[3]) // 2, t[0]))
    grouped = []
    for bx in boxes:
        yc = (bx[1] + bx[3]) // 2
        for row in grouped:
            if abs(row["yc"] - yc) <= y_tol:
                row["b"].append(bx)
                break
        else:
            grouped.append({"yc": yc, "b": [bx]})
    out = []
    for row in sorted(grouped, key=lambda r: r["yc"]):
        bs = sorted(row["b"], key=lambda t: t[0])
        toks = []
        cur = [bs[0]]
        for prev, nb in zip(bs, bs[1:]):
            if nb[0] - prev[2] >= tok_gap:
                toks.append(cur)
                cur = [nb]
            else:
                cur.append(nb)
        toks.append(cur)
        ytop = min(t[1] for t in bs)
        out.append((ytop, [(t[0][0], t[-1][2], min(u[1] for u in t), max(u[3] for u in t)) for t in toks]))
    return out


def report(name, mask, xr, yr, minpx=4, tok_gap=3):
    m = np.zeros_like(mask)
    m[yr[0]:yr[1], xr[0]:xr[1]] = mask[yr[0]:yr[1], xr[0]:xr[1]]
    print(f"=== {name} ===")
    for ytop, toks in rows(cc_boxes(m, minpx), tok_gap=tok_gap):
        desc = "  ".join(f"x{a}(w{b - a + 1}) y{y0}-{y1}" for (a, b, y0, y1) in toks)
        print(f"  row ytop={ytop}: {desc}")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "t04.png"
    white, dark = load(path)
    report("LEFT vitals panel (cream text)", white, (40, 130), (162, 224), minpx=4, tok_gap=5)
    report("RIGHT info panel (dark on tan)", dark, (140, 246), (180, 224), minpx=4, tok_gap=4)


if __name__ == "__main__":
    main()
