#!/usr/bin/env python
"""Locality-diff instrument: pin the Godot formation capture against the pcsx-redux oracle framebuffer.

§15.26 Round 44. The self-verify loop for formation-screen geometry. The Godot capture
(tests/tools/formation_picker_capture.gd) renders the composited picker screen through an ortho camera
aligned 1:1 with the PSX 256x240 framebuffer, HiDPI-scaled by an integer factor. The window is now 16:15
(1024x960), so the keep-height ortho frames EXACTLY display x[0,256] -> the capture is natively 256-wide
and area-resizes straight to 256x240 with NO crop (the old 4:3 window framed x[-32,288] and needed an
x[32..288] crop; that crop is now WRONG and has been removed).

Because the oracle (Ramza Lv99) and the port capture (a synthetic Squire) render DIFFERENT subjects, a raw
whole-frame diff is dominated by CONTENT (portrait, name, level, HP/MP, stat values), not geometry. So the
diff is masked:

  * global orienting pass (default): BLACKLIST known content rects -> black, to spot where disconnects live.
  * image diff pair (--pair NAME):   WHITELIST that pair's rects -> everything else black, to dive into one
                                     locality in isolation. Re-run after a fix = a regression check.
  * --raw:                           no masks (first look, before any rects are known).

Rects live in a JSON registry next to this script (oracle_diff_pairs.json): {content_masks:[...], pairs:[...]},
each entry {name, rect:[x,y,w,h]} or {name, rects:[[x,y,w,h],...], notes}. Coords are 256x240 DISPLAY space
(same as fb4.png). Start empty; fill as the user calls out rects.

Artifacts (all at 4x NEAREST): cmp_overlay.png (oracle->red, port->green, agree->gray; fringes show the
DIRECTION of misalignment), cmp_heatmap.png (abs-diff magnitude, hot colormap), plus the legacy
cmp_sidebyside.png / cmp_blend.png and the per-row dark-border table.

Usage:
    uv run python tests/tools/oracle_diff.py <port_capture.png> <oracle_fb.png> [out_dir] [--raw|--pair NAME] [--col X]

Deps: pillow, numpy (via `uv run --with pillow --with numpy` if not already resolved).
"""
import json
import os
import sys

from PIL import Image
import numpy as np

DARK = (32, 24, 16)
ZOOM = 4
REGISTRY = os.path.join(os.path.dirname(__file__), "oracle_diff_pairs.json")


def load_port_aligned(path):
    """Area-resize the natively-256-wide 16:15 capture straight to 256x240 (display space), no crop.

    The keep-height ortho (size=240*PPU, centre display (128,120)) frames display-y 0..240 over the height
    and -- now that the window is 16:15 -- display-x 0..256 over the width. So the capture is already the
    full 256x240 display window at an integer HiDPI factor; just area-average it down."""
    im = Image.open(path).convert("RGB")
    return im.resize((256, 240), Image.BOX)


def _load_registry():
    if not os.path.exists(REGISTRY):
        return {"content_masks": [], "pairs": []}
    with open(REGISTRY) as f:
        r = json.load(f)
    r.setdefault("content_masks", [])
    r.setdefault("pairs", [])
    return r


def _rects_of(entry):
    """An entry may carry a single `rect` or a list of `rects`."""
    if "rects" in entry:
        return [tuple(r) for r in entry["rects"]]
    if "rect" in entry:
        return [tuple(entry["rect"])]
    return []


def _apply_mask(arr_o, arr_p, rects, mode):
    """mode='whitelist' -> keep only rects (black elsewhere); 'blacklist' -> black the rects."""
    if not rects:
        return arr_o, arr_p
    h, w = arr_o.shape[:2]
    keep = np.zeros((h, w), bool)
    for (x, y, rw, rh) in rects:
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(w, x + rw), min(h, y + rh)
        keep[y0:y1, x0:x1] = True
    if mode == "blacklist":
        keep = ~keep
    m = keep[:, :, None]
    return arr_o * m, arr_p * m


def _lum(arr):
    return (0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2])


def _zoom_save(arr_uint8, path):
    Image.fromarray(arr_uint8).resize((256 * ZOOM, 240 * ZOOM), Image.NEAREST).save(path)


def channel_overlay(oa, pa):
    """oracle->red, port->green, agreement->gray. R=oracle lum, G=port lum, B=min(both)."""
    lo, lp = _lum(oa), _lum(pa)
    out = np.zeros((240, 256, 3))
    out[:, :, 0] = lo
    out[:, :, 1] = lp
    out[:, :, 2] = np.minimum(lo, lp)
    return np.clip(out, 0, 255).astype(np.uint8)


def magnitude_heatmap(oa, pa):
    """Per-pixel abs-diff magnitude (max over channels) through a hot colormap."""
    d = np.abs(oa.astype(int) - pa.astype(int)).max(2) / 255.0    # 0..1
    r = np.clip(3 * d, 0, 1)
    g = np.clip(3 * d - 1, 0, 1)
    b = np.clip(3 * d - 2, 0, 1)
    return (np.stack([r, g, b], 2) * 255).astype(np.uint8)


def main():
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    col = int(sys.argv[sys.argv.index("--col") + 1]) if "--col" in sys.argv else None
    raw = "--raw" in sys.argv
    pair_name = sys.argv[sys.argv.index("--pair") + 1] if "--pair" in sys.argv else None
    if len(a) < 2:
        print(__doc__)
        sys.exit(2)
    port_path, oracle_path = a[0], a[1]
    out = a[2] if len(a) > 2 else "/tmp/picker_re2"

    port = load_port_aligned(port_path)
    orc = Image.open(oracle_path).convert("RGB").resize((256, 240))
    port.save(f"{out}/port_aligned.png")
    pa, oa = np.array(port).astype(np.uint8), np.array(orc).astype(np.uint8)

    # --- masking: whitelist one image diff pair, blacklist content for the global pass, or raw ---
    reg = _load_registry()
    label = "raw (no mask)"
    if raw:
        pass
    elif pair_name is not None:
        entry = next((p for p in reg["pairs"] if p.get("name") == pair_name), None)
        if entry is None:
            names = ", ".join(p.get("name", "?") for p in reg["pairs"]) or "(none defined yet)"
            print(f"no image diff pair named {pair_name!r}. defined: {names}")
            sys.exit(2)
        oa, pa = _apply_mask(oa, pa, _rects_of(entry), "whitelist")
        label = f"pair:{pair_name}  {entry.get('notes', '')}"
    else:
        content = [r for e in reg["content_masks"] for r in _rects_of(e)]
        oa, pa = _apply_mask(oa, pa, content, "blacklist")
        label = f"global orienting pass (blacklisted {len(content)} content rect(s))"

    # --- artifacts ---
    _zoom_save(channel_overlay(oa, pa), f"{out}/cmp_overlay.png")
    _zoom_save(magnitude_heatmap(oa, pa), f"{out}/cmp_heatmap.png")

    sbs = Image.new("RGB", (256 * 2 + 8, 240), (40, 40, 40))
    sbs.paste(Image.fromarray(oa), (0, 0)); sbs.paste(Image.fromarray(pa), (256 + 8, 0))
    sbs.resize((sbs.width * 3, 240 * 3), Image.NEAREST).save(f"{out}/cmp_sidebyside.png")
    Image.fromarray(((pa.astype(int) + oa.astype(int)) // 2).astype(np.uint8)).resize(
        (256 * 3, 240 * 3), Image.NEAREST).save(f"{out}/cmp_blend.png")

    # per-row dark-border count where they differ (locates misaligned horizontal frame edges)
    def darkrows(x):
        m = (np.abs(x[:, :, 0].astype(int) - DARK[0]) < 28) & (np.abs(x[:, :, 1].astype(int) - DARK[1]) < 28) & (
            np.abs(x[:, :, 2].astype(int) - DARK[2]) < 28)
        return m.sum(1)
    do, dp = darkrows(oa), darkrows(pa)
    print(f"[{label}]")
    print("y   oracle_dark port_dark   (rows differing >40 or heavy)")
    for y in range(24, 236):
        if abs(int(do[y]) - int(dp[y])) > 40 or do[y] > 80 or dp[y] > 80:
            print(f"{y:4d}   {int(do[y]):4d}      {int(dp[y]):4d}")

    if col is not None:
        print(f"\ncol x={col}   y   PORT | ORACLE")
        for y in range(24, 236):
            print(f" {y:3d}: {tuple(int(v) for v in pa[y, col])!s:20} | {tuple(int(v) for v in oa[y, col])}")

    print(f"\nwrote {out}/cmp_overlay.png (oracle=red port=green agree=gray), cmp_heatmap.png, "
          f"cmp_sidebyside.png, cmp_blend.png, port_aligned.png")


if __name__ == "__main__":
    main()
